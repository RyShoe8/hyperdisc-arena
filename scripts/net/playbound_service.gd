## PlayBound accounts, friends, presence and invites. A placeholder until
## the PlayBound API exists: docs/ONLINE.md lists exactly what each method
## needs from it. The rest of the game already talks to this interface, so
## filling these in is all that's needed to switch over.
extends "res://scripts/net/online_service.gd"

## Set from the PlayBound launcher or build config once the API is live.
var api_base := ""


func service_name() -> String:
	return "PlayBound"


func is_available() -> bool:
	return api_base != ""


func is_signed_in() -> bool:
	return false  # TODO(PlayBound): session token present and valid (GET /me)


func profile() -> Dictionary:
	return {"id": "", "display_name": "PLAYER"}  # TODO(PlayBound): GET /me


func sign_in() -> void:
	# TODO(PlayBound): device/browser login flow -> session token, then
	# profile_changed. See docs/ONLINE.md "Accounts".
	error.emit("PLAYBOUND SIGN-IN ISN'T AVAILABLE YET")


func create_account() -> void:
	error.emit("PLAYBOUND ACCOUNTS AREN'T AVAILABLE YET")


func supports_friends() -> bool:
	return is_available()


func friends() -> Array[Dictionary]:
	return []  # TODO(PlayBound): GET /friends plus the presence stream


func send_invite(_friend_id: String) -> void:
	pass  # TODO(PlayBound): POST /invites


func respond_to_invite(_invite_id: String, _accept: bool) -> void:
	pass  # TODO(PlayBound): POST /invites/{id}/respond, then match_ready


func set_presence(_status: String) -> void:
	pass  # TODO(PlayBound): PUT /me/presence
