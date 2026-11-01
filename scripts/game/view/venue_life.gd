## Court-side fixtures animate from match events, without changing rollback state.
extends RefCounted
var heat := 0.0
var cue := 0
var win := 0
var origin := 0.5
var banks := 0
var hits := 0
var last_side := -1
var target := 0.25
const UI := preload("res://scripts/game/ui/theme.gd")
const CUES := {"concrete":"HIT THE LIT BANK", "lawn":"BEND A CURVE", "clay":"MAKE A POWER THROW", "beach":"MAKE A DIVE SAVE", "tiled":"SLAP OR BLOCK", "stadium":"LAND A SPECIAL"}
const REPLIES := {"concrete":"BANK!", "lawn":"REMIX!", "clay":"LAST CALL!", "beach":"RESCUE!", "tiled":"HIGH SCORE!", "stadium":"POWER PLAY!"}
var dive := [0,0,0,0]

func tick() -> void:
	heat = move_toward(heat,0,0.003)
	cue = maxi(0,cue-1)
	win = maxi(0,win-1)
	for i in dive.size(): dive[i] = maxi(0,int(dive[i])-1)

func handle(id: String,e: Dictionary,position: float) -> void:
	var event: String=e.type
	if event=="throw": banks=0
	if event=="bounce": banks+=1
	var actor:=clampi(int(e.get("player",e.get("side",0))),0,3)
	if event=="dash": dive[actor]=25
	var accent: bool = (id=="concrete" and event=="bounce") or (id=="lawn" and event=="throw" and e.get("curve",false)) or (id=="clay" and event=="throw" and e.get("supersonic",false)) or (id=="beach" and event=="catch" and (int(dive[actor])>0 or e.get("special",false))) or (id=="tiled" and event in ["slap","block","drop"]) or (id=="stadium" and event=="special")
	if event in ["catch","throw","special","slap"]: heat=minf(1,heat+0.12)
	if id=="concrete" and accent:
		accent=absf(position-target)<0.10
	if accent:
		hits+=1
		last_side=int(e.get("side",-1))
		if id=="concrete": target=[0.25,0.72,0.38,0.60][hits%4]
		cue=78
		origin=clampf(position,0,1)
		heat=minf(1,heat+0.35)
	if event in ["point","set_end","match_over"]:
		win=180 if event=="point" else 260
		origin=float(e.get("side",e.get("winner",0)))
		heat=1.0
