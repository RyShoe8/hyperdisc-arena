shader_type canvas_item;
render_mode unshaded;

uniform sampler2D applause : source_color, filter_nearest;
uniform sampler2D celebration : source_color, filter_nearest;
uniform sampler2D surprise : source_color, filter_nearest;
uniform sampler2D seat_map : filter_nearest;
uniform vec4 audience[64];
uniform vec2 grids[64];
uniform int audience_count = 0;
uniform int court_style = 0;
uniform float clock_seconds = 0.0;
uniform int reaction = 0;
uniform float reaction_age = 0.0;
uniform float rally_x = 0.5;
uniform int reaction_side = -1;
uniform float excitement = 0.0;
uniform float event_serial = 0.0;

float random(vec2 p) {
	return fract(sin(dot(p,vec2(127.1,311.7)))*43758.5453);
}

void fragment() {
	vec2 uv = UV;
	vec2 p = uv*vec2(1920.0,1080.0);
	float t = floor(clock_seconds*12.0)/12.0;
	vec4 color = texture(TEXTURE,uv);
	bool in_audience = false;
	int i = int(round(texture(seat_map,uv).r*255.0))-1;
	if (i >= 0 && i < audience_count) {
		vec4 box = audience[i];
		vec2 local = (p-box.xy)/box.zw;
		if (local.x>=0.0 && local.x<1.0 && local.y>=0.0 && local.y<1.0) {
			in_audience = true;
			vec2 cell = floor(local*grids[i]);
			vec2 part = fract(local*grids[i]);
			float seed = random(cell+vec2(float(i)*23.0,7.0));
			float edge = smoothstep(0.0,0.14,part.x)*(1.0-smoothstep(0.86,1.0,part.x));
			float anchored = (1.0-smoothstep(0.6,1.0,part.y))*edge;
			// Subpixel head/shoulder shifts stay anchored to the authored seat.
			vec2 motion = vec2(sin(t*(0.8+seed)+seed*31.0)*0.6+(rally_x-0.5)*0.7,
				 sin(t*(1.1+seed)+seed*17.0)*0.45)*anchored;
			vec2 sample_uv = uv+motion/vec2(1920.0,1080.0);
			color = texture(TEXTURE,sample_uv);
			// Independent small groups use precomputed low-change seams
			// between the authored poses, rather than arbitrary grid cuts.
			float gesture_seed = random(vec2(float(i)*41.0,17.0));
			float tempo = 0.8+gesture_seed*1.7;
			float beat = fract(t*tempo+gesture_seed*19.0);
			float event_seed = random(vec2(float(i)*13.0,event_serial+5.0));
			float allegiance = random(vec2(float(i),93.0));
			bool supporting = reaction_side<0 || (allegiance<0.5) == (reaction_side==0);
			float delay = 0.1+event_seed*0.9+abs((box.x+box.z*0.5)/1920.0-rally_x)*0.3;
			float duration = 1.2+gesture_seed*2.8;
			float age = reaction_age-delay;
			int pose = 0;
			if (reaction>0 && age>0.0 && age<duration && event_seed<0.65+excitement*0.3) {
				if (reaction==1) pose = beat<0.4+gesture_seed*0.25 ? 1 : 0;
				if (reaction==2) {
					if (supporting) pose = beat<0.45 ? 2 : (beat<0.8 ? 1 : 0);
					else pose = age<0.65 ? 3 : 0;
				}
				if (reaction==3) pose = age<0.45+gesture_seed*0.4 ? 3 : (supporting && beat<0.4 ? 1 : 0);
			} else {
				// Different personalities applaud intermittently between big plays.
				float idle_cycle = mod(t+gesture_seed*29.0,10.0+gesture_seed*13.0);
				if (idle_cycle<0.5+excitement && gesture_seed>0.45) pose = beat<0.5 ? 1 : 0;
			}
			vec4 moved = color;
			if (pose==1) moved = texture(applause,sample_uv);
			if (pose==2) moved = texture(celebration,sample_uv);
			if (pose==3) moved = texture(surprise,sample_uv);
			color = moved;
		}
	}
	// Scenery animation is restricted to the perimeter, outside the court.
	bool side = p.x<145.0 || p.x>1775.0;
	bool perimeter = side || p.y<145.0 || p.y>930.0;
	if (perimeter) {
		float green = step(color.r*1.2,color.g)*step(color.b*1.1,color.g);
		float blue_water = step(color.r*1.45,color.b)*step(0.4,color.g);
		bool pool = court_style==2 && (p.x<195.0 || p.x>1725.0 || p.y<48.0);
		bool sea = court_style==0 && p.y<100.0 && (p.x<300.0 || p.x>1620.0);
		if (pool || sea) {
			vec2 water_uv = uv+vec2(sin(t*1.2+p.y*0.09),cos(t+p.x*0.07))*0.0005;
			color = mix(color,texture(TEXTURE,water_uv),blue_water*0.65);
		}
		if (!in_audience && court_style!=3 && court_style!=5 && (side || p.y>1010.0)) {
			vec2 leaf_uv = uv+vec2(sin(t*0.8+p.y*0.035)*0.8,0.0)/vec2(1920.0,1080.0);
			color = mix(color,texture(TEXTURE,leaf_uv),green*0.7);
		}
	}
	if (court_style==0 && p.y>12.0 && p.y<52.0 && p.x>345.0 && p.x<1570.0) {
		float fabric = step(0.55,max(color.r,color.b))*step(0.12,max(color.r,color.b)-min(color.r,color.b));
		vec2 flag_uv = uv+vec2(sin(t*1.4+p.x*0.06)*0.7,0.0)/vec2(1920.0,1080.0);
		color = mix(color,texture(TEXTURE,flag_uv),fabric*0.6);
	}
	if (perimeter && (court_style==3 || court_style==5)) {
		float neon = step(0.65,max(color.r,color.b))*step(color.g+0.15,max(color.r,color.b));
		color.rgb *= 1.0+neon*0.035*sin(t*1.5+p.x*0.008);
	}
	COLOR = color;
}
