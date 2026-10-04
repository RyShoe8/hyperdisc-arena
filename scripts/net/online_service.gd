## What the game needs from an online platform. PlayBound will implement
## this (see docs/ONLINE.md for the API contract); DirectService is the
## stand-in until then. Game code only talks to this interface.
##
## Everything is asynchronous: calls return immediately and results arrive
## through the signals. poll() is called every frame.
extends RefCounted

## Signed in or out, or the profile changed.
signal profile_changed
## The friends list or anyone's presence changed.
signal friends_changed
## A friend invited us to a match: {id, from_id, from_name}.
signal invite_received(invite: Dictionary)
## A friend answered our invite.
signal invite_answered(invite_id: String, accepted: bool)
## Both players are ready to connect: {role: "host"|"join", transport: Transport,
## opponent: {id, display_name}}. The game then opens an OnlineMatch on it.
signal match_ready(info: Dictionary)
## Something went wrong that the player should see.
signal error(message: String)


## Name shown in menus ("Direct connect", "PlayBound").
func service_name() -> String:
	return ""


func is_signed_in() -> bool:
	return false


## {id, display_name}. id is empty when there is no account.
func profile() -> Dictionary:
	return {"id": "", "display_name": "PLAYER"}


## Sign in with an existing account, or create one. The platform may open a
## browser or its own login screen.
func sign_in() -> void:
	pass


func create_account() -> void:
	pass


func sign_out() -> void:
	pass


## True if accounts, friends and invites are available.
func supports_friends() -> bool:
	return false


## [{id, display_name, online, in_game, joinable}], online friends first.
func friends() -> Array[Dictionary]:
	return []


func send_invite(_friend_id: String) -> void:
	pass


func respond_to_invite(_invite_id: String, _accept: bool) -> void:
	pass


## Called by the game while a match is being played, so friends see it.
func set_presence(_status: String) -> void:
	pass


func poll() -> void:
	pass
