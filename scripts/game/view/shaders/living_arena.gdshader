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
	in_audience = i >= 0 && i < audience_count;
	// Scenery animation is restricted to the perimeter, outside the court.
	bool side = p.x<145.0 || p.x>1775.0;
	bool perimeter = side || p.y<145.0 || p.y>930.0;
	if (perimeter) {
		float green = step(color.r*1.2,color.g)*step(color.b*1.1,color.g);
		float blue_water = step(color.r*1.45,color.b)*step(0.4,color.g);
		bool pool = court_style==1 && (p.x<195.0 || p.x>1725.0 || p.y<48.0);
		bool sea = (court_style==0 || court_style==3) && p.y<100.0 && (p.x<300.0 || p.x>1620.0);
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
	if (perimeter && (court_style==1 || court_style==2 || court_style==5)) {
		float neon = step(0.65,max(color.r,color.b))*step(color.g+0.15,max(color.r,color.b));
		color.rgb *= 1.0+neon*(0.06+0.22*excitement)*sin(t*(2.0+excitement*3.0)+p.x*0.008);
	}
	COLOR = color;
}
