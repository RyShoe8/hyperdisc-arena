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
	COLOR = color;
}
