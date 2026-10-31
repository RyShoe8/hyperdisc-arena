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

func draw(ci: CanvasItem,id: String,p,frame: int) -> void:
	var a: Vector2=p.origin
	var b: Vector2=p.floor_point(p.court_size)
	var t:=float(frame)/60.0
	var accent:=float(cue)/78
	var energy:=maxf(heat,accent)
	var rail_y:=b.y+7
	if id=="concrete":
		# A pair of lit strips marks the playable stretch of both bank walls.
		for y in [a.y-3,b.y+3]:
			var x:=lerpf(a.x,b.x,target)
			ci.draw_rect(Rect2(x-(b.x-a.x)*0.10,y-2,(b.x-a.x)*0.20,4),Color("ffd077"))
			for end in [-1,1]:
				ci.draw_rect(Rect2(x+end*(b.x-a.x)*0.10-3,y-5,6,10),Color("fff0bc"))
	# A small physical ribbon at the near edge explains / acknowledges local feats.
	var label: String=(str(REPLIES[id])+"  x"+str(hits)) if cue>0 else str(CUES[id])
	var plaque:=Rect2(b.x-280,rail_y+27,280,27)
	ci.draw_rect(plaque,Color("21192e"))
	var ink:=Color("fdecb9") if cue<=0 or last_side<0 else (UI.P1 if last_side==0 else UI.P2)
	UI.text(ci,plaque.position+Vector2(140,21),label,18,ink,UI.ui,1)

	# Fixtures sit on the near rail, below the playable surface.
	for i in 32:
		var u:=(i+0.5)/32.0
		var x:=lerpf(a.x,b.x,u)
		var wave:=absf(u-origin)
		var flash:=maxf(0,1-absf(wave-fmod((180-win)/72.0,1.6))*8) if win>0 else 0.0
		var col: Color
		match id:
			"concrete": # Wicker lanterns: a bank lights the strand outward from impact.
				if i%3!=0: continue
				var glow:=maxf(flash,maxf(0,1-absf(wave-(1-accent))*6)*accent)
				col=Color("f0aa55").lerp(Color("fff2a0"),glow)
				ci.draw_line(Vector2(x,rail_y),Vector2(x,rail_y+7),Color("67432e"),3)
				ci.draw_rect(Rect2(x-5,rail_y+7,10,10),col.darkened(0.25-0.18*sin(t*2+i)))
				ci.draw_rect(Rect2(x-2,rail_y+9,4,6),col)
			"lawn": # DJ spectrum; the highs open up on a curve.
				var bars:=1+roundi((2+5*energy)*(0.5+0.5*sin(t*(4+energy*4)+i*0.48)))
				for j in bars:
					ci.draw_rect(Rect2(x-8,rail_y+22-j*3,16,2),Color("27d6dd").lerp(Color("fa408f"),j/7.0))
			"clay": # Industrial hazard beacons pulse beside the kegs.
				if i%4!=0: continue
				var on:bool=(cue>0 or win>0) and (frame/10+i/4)%2==0
				ci.draw_rect(Rect2(x-11,rail_y+8,22,6),Color("292636"))
				ci.draw_rect(Rect2(x-7,rail_y,14,8),Color("ffac35") if on else Color("a45b30"))
			"beach": # Spindrift travels down the timber pilings after a save.
				var swell:=0.5+0.5*sin(u*20-t*2.5)
				if swell>0.55:
					var rise:float=swell*(3+10*maxf(accent,flash))
					ci.draw_rect(Rect2(x,rail_y+12-rise,8,3),Color(0.68,0.94,0.94,0.45+swell*0.4))
			"tiled": # Arcade marquee: defensive returns send a packet along the strip.
				var lit:=posmod(i-frame/(3 if cue>0 else 12),10)<3 or flash>0.2
				col=Color("f343bf") if i%4<2 else Color("56e9c2")
				ci.draw_rect(Rect2(x-7,rail_y+4,14,5),col if lit else col.darkened(0.72))
			"stadium": # Rally tracking lights and a winning-side chase.
				col=Color("ff468e") if u<0.5 else Color("43d8ef")
				ci.draw_rect(Rect2(x-13,rail_y+4,26,6),col.lightened(flash*0.6) if flash>0.1 or sin(t*4+i*0.5)>0.4-energy else col.darkened(0.62))
	if win>0 and id in ["stadium","tiled","lawn"]:
		for i in 30:
			var x:=lerpf(a.x,b.x,fmod(i*0.618+sin(t+i)*0.007,1))
			var y:=fposmod(t*(32+i%5*8)+i*31,94)
			ci.draw_rect(Rect2(x,b.y+9+y,3+(i%3),4),Color("ffd96c") if i%2==0 else Color("f75d99"))
