"""A stand-in PlayBound server for testing online play locally.

Implements just what the game calls: game sign-in (link codes), friends,
presence, play invites and Connect rooms with signaling. Everything lives in
memory. Every user is friends with every other.

    python tools/fake_playbound.py [--port 8787]

Then start the game with  -- --playbound-api=http://127.0.0.1:8787
and PLAYBOUND_TOKEN=tok-alice (or tok-bob, ...) to be signed in, or sign in
from the game: open the printed link page and the code is approved.

Rooms always get the code HYPER1, HYPER2, ... so tests can join blind.
"""
import argparse
import itertools
import json
import re
import threading
import time
import uuid
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from urllib.parse import parse_qs, urlparse

USERS = {
    "tok-alice": {"id": "u-alice", "username": "alice"},
    "tok-bob": {"id": "u-bob", "username": "bob"},
    "tok-carol": {"id": "u-carol", "username": "carol"},
    "tok-dave": {"id": "u-dave", "username": "dave"},
}
lock = threading.Lock()
presence = {}  # user id -> {"status", "gameId", "seen"}
links = {}  # code -> {"poll", "status", "user"}
invites = {}  # id -> invite dict
sessions = {}  # id -> {"code", "host", "client", "signals": []}
room_numbers = itertools.count(1)


def user_for(headers):
    auth = headers.get("Authorization", "")
    return USERS.get(auth.removeprefix("Bearer ").strip())


class Handler(BaseHTTPRequestHandler):
    def log_message(self, fmt, *args):
        print("%s %s" % (self.command, self.path), flush=True)

    def reply(self, status, body):
        data = json.dumps(body).encode()
        self.send_response(status)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(data)))
        self.end_headers()
        self.wfile.write(data)

    def body(self):
        n = int(self.headers.get("Content-Length", 0) or 0)
        if not n:
            return {}
        try:
            return json.loads(self.rfile.read(n))
        except ValueError:
            return {}

    def do_GET(self):
        url = urlparse(self.path)
        q = {k: v[0] for k, v in parse_qs(url.query).items()}
        with lock:
            self.route("GET", url.path, q, {})

    def do_POST(self):
        url = urlparse(self.path)
        body = self.body()
        with lock:
            self.route("POST", url.path, {}, body)

    def route(self, method, path, q, body):
        me = user_for(self.headers)

        # --- Game sign-in -------------------------------------------------
        if path == "/api/game-auth/link" and method == "POST":
            code = uuid.uuid4().hex[:8].upper()
            poll = uuid.uuid4().hex
            links[code] = {"poll": poll, "status": "pending", "user": None}
            url = "http://127.0.0.1:%d/link?code=%s" % (self.server.server_port, code)
            print("SIGN-IN LINK %s" % url, flush=True)
            return self.reply(201, {"code": code[:4] + "-" + code[4:], "pollToken": poll,
                                    "verifyUrl": url, "expiresInMs": 600000, "intervalMs": 1000})
        if path == "/link" and method == "GET":
            # Visiting the page approves the code as alice (or ?as=bob).
            code = q.get("code", "").replace("-", "").upper()
            token = "tok-" + q.get("as", "alice")
            if code in links and token in USERS:
                links[code].update(status="approved", user=token)
                return self.reply(200, {"approved": code, "as": USERS[token]["username"]})
            return self.reply(404, {"error": "No such code"})
        if path == "/api/game-auth/link/poll" and method == "POST":
            for link in links.values():
                if link["poll"] == body.get("pollToken"):
                    if link["status"] == "approved":
                        link["status"] = "claimed"
                        return self.reply(200, {"status": "approved", "token": link["user"],
                                                "user": USERS[link["user"]]})
                    if link["status"] == "pending":
                        return self.reply(200, {"status": "pending"})
                    return self.reply(410, {"status": "expired"})
            return self.reply(404, {"status": "invalid"})
        if path == "/api/game-auth/me":
            return self.reply(200, {"user": me}) if me else self.reply(401, {"error": "Unauthorized"})
        if path == "/api/game-auth/logout":
            return self.reply(200, {"ok": True})

        # --- Friends and presence ----------------------------------------------
        if path == "/api/friends":
            if not me:
                return self.reply(401, {"error": "Unauthorized"})
            friends = []
            for u in USERS.values():
                if u["id"] == me["id"]:
                    continue
                p = presence.get(u["id"])
                online = p and time.time() - p["seen"] < 120
                friends.append({"id": u["id"], "username": u["username"], "presence": {
                    "status": p["status"] if online else "offline",
                    "currentGameId": p["gameId"] if online else None}})
            return self.reply(200, {"friends": friends})
        if path.startswith("/api/presence/"):
            if not me:
                return self.reply(401, {"error": "Unauthorized"})
            if path.endswith("/end"):
                presence.pop(me["id"], None)
            else:
                presence[me["id"]] = {"status": body.get("status", "online"),
                                      "gameId": body.get("gameId"), "seen": time.time()}
            return self.reply(200, {"sessionId": "pres-" + me["id"], "heartbeatIntervalMs": 60000})

        # --- Invites ---------------------------------------------------------------
        if path == "/api/play-invites":
            if not me:
                return self.reply(401, {"error": "Unauthorized"})
            if method == "POST":
                to = body.get("recipientId")
                inv_id = uuid.uuid4().hex[:12]
                invites[inv_id] = {"id": inv_id, "senderId": me["id"], "senderUsername": me["username"],
                                   "recipientId": to, "gameSlug": body.get("gameSlug"),
                                   "connectCode": body.get("connectCode"), "status": "pending"}
                return self.reply(200, {"results": [{"recipientId": to, "inviteId": inv_id}]})
            out = []
            for inv in invites.values():
                if me["id"] in (inv["senderId"], inv["recipientId"]):
                    out.append(dict(inv, direction="incoming" if inv["recipientId"] == me["id"] else "outgoing"))
            return self.reply(200, {"invites": out})
        m = re.fullmatch(r"/api/play-invites/(\w+)", path)
        if m and method == "POST":
            inv = invites.get(m.group(1))
            if not inv or not me or inv["recipientId"] != me["id"]:
                return self.reply(404, {"error": "Invite not found"})
            inv["status"] = "accepted" if body.get("action") == "accept" else "declined"
            return self.reply(200, {"invite": inv})

        # --- Connect rooms -----------------------------------------------------------
        m = re.fullmatch(r"/api/multiplayer/([\w-]+)/sessions", path)
        if m and method == "POST":
            sid = uuid.uuid4().hex
            code = "HYPER%d" % next(room_numbers)
            sessions[sid] = {"code": code, "host": "h-" + sid, "client": "c-" + sid, "signals": [],
                             "version": body.get("gameVersion")}
            return self.reply(201, {"sessionId": sid, "joinCode": code, "hostToken": "h-" + sid,
                                    "stunServers": [], "turnServers": []})
        m = re.fullmatch(r"/api/multiplayer/([\w-]+)/sessions/(\w+)/join", path)
        if m and method == "POST":
            for sid, s in sessions.items():
                if s["code"] == m.group(2).upper():
                    return self.reply(200, {"sessionId": sid, "joinCode": s["code"], "clientToken": s["client"],
                                            "stunServers": [], "turnServers": [],
                                            "versionMismatch": s["version"] != body.get("gameVersion")})
            return self.reply(404, {"error": "Room not found"})
        m = re.fullmatch(r"/api/multiplayer/([\w-]+)/sessions/(\w+)/signal", path)
        if m:
            s = sessions.get(m.group(2))
            token = self.headers.get("Authorization", "").removeprefix("Bearer ").strip()
            if not s or token not in (s["host"], s["client"]):
                return self.reply(401, {"error": "Invalid session capability."})
            if method == "POST":
                msg = {"id": uuid.uuid4().hex, "senderRole": body.get("senderRole"),
                       "recipientRole": body.get("recipientRole"), "payload": body.get("payload"),
                       "timestamp": int(time.time() * 1000)}
                s["signals"].append(msg)
                return self.reply(201, {"success": True, "messageId": msg["id"]})
            since = int(q.get("since", 0))
            out = [x for x in s["signals"] if x["recipientRole"] == q.get("forRole") and x["timestamp"] > since]
            return self.reply(200, {"messages": out})

        self.reply(404, {"error": "Not found: " + path})


if __name__ == "__main__":
    ap = argparse.ArgumentParser()
    ap.add_argument("--port", type=int, default=8787)
    port = ap.parse_args().port
    print("Fake PlayBound on http://127.0.0.1:%d" % port, flush=True)
    ThreadingHTTPServer(("127.0.0.1", port), Handler).serve_forever()
