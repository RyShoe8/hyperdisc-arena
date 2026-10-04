## JSON over HTTPS to the PlayBound API. Each call is awaited:
##   var res := await api.call_api(HTTPClient.METHOD_GET, "/api/game-auth/me")
## and returns the parsed body plus "_status" (HTTP code, 0 if unreachable)
## and "_ok" (2xx).
extends Node

const DEFAULT_BASE := "https://playbound.club"

var base := DEFAULT_BASE
var token := ""


## bearer overrides the signed-in token (Connect rooms use their own).
func call_api(method: int, path: String, body: Variant = null, auth := true, bearer := "") -> Dictionary:
	if not is_inside_tree():
		return {"_status": 0, "_ok": false, "error": "COULDN'T REACH PLAYBOUND"}
	var req := HTTPRequest.new()
	req.timeout = 15.0
	add_child(req)
	var headers := PackedStringArray([
		"Accept: application/json",
		"User-Agent: HyperDiscArena/%s" % ProjectSettings.get_setting("application/config/version", "dev"),
	])
	if body != null:
		headers.append("Content-Type: application/json")
	var use_token := bearer if bearer != "" else token
	if auth and use_token != "":
		headers.append("Authorization: Bearer " + use_token)
	var payload := JSON.stringify(body) if body != null else ""
	var err := req.request(base + path, headers, method, payload)
	if err != OK:
		req.queue_free()
		return {"_status": 0, "_ok": false, "error": "COULDN'T REACH PLAYBOUND"}
	var res: Array = await req.request_completed
	req.queue_free()
	var status: int = res[1]
	var text: String = (res[3] as PackedByteArray).get_string_from_utf8()
	var parser := JSON.new()
	var parsed := parser.parse(text) if text != "" else ERR_PARSE_ERROR
	var data = parser.data if parsed == OK else {}
	var out: Dictionary = data if data is Dictionary else {}
	out["_status"] = status if res[0] == HTTPRequest.RESULT_SUCCESS else 0
	out["_ok"] = out["_status"] >= 200 and out["_status"] < 300
	if out["_status"] == 0 and not out.has("error"):
		out["error"] = "COULDN'T REACH PLAYBOUND"
	return out
