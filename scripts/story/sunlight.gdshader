shader_type canvas_item;
render_mode unshaded;
uniform float cinematic_time=0.0;
varying vec4 vertex_tint;
void vertex(){vertex_tint=COLOR;}
void fragment(){
	vec4 ink=texture(TEXTURE,UV)*vertex_tint;
	float skin=step(.4,ink.r)*step(ink.g*1.15,ink.r)*step(ink.b*1.14,ink.g);
	float edge=max(0.0,ink.a-texture(TEXTURE,UV-vec2(2.0,2.0)*TEXTURE_PIXEL_SIZE).a);
	float glint=pow(max(0.0,sin(UV.y/TEXTURE_PIXEL_SIZE.y*.12+cinematic_time*.6)),18.0);
	float painted_highlight=smoothstep(.42,.76,dot(ink.rgb,vec3(.3,.59,.11)));
	ink.rgb=mix(ink.rgb,vec3(1.0,.86,.65),skin*(edge*.4+glint*.12*painted_highlight));
	COLOR=ink;
}
