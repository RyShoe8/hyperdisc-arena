shader_type canvas_item;
render_mode unshaded;
uniform float cinematic_time = 0.0;

float hash(vec2 p) {
	return fract(sin(dot(p,vec2(127.1,311.7)))*43758.5453);
}
float noise(vec2 p) {
	vec2 i=floor(p),f=fract(p);
	f=f*f*(3.0-2.0*f);
	return mix(mix(hash(i),hash(i+vec2(1,0)),f.x),mix(hash(i+vec2(0,1)),hash(i+vec2(1,1)),f.x),f.y);
}
void fragment() {
	vec2 uv=UV;
	vec2 world=vec2(-350,-100)+uv*vec2(3900,1300);
	vec4 original=texture(TEXTURE,uv);
	// Tower, staircase, rocks and pier are dry, static occluders. Every painted
	// building pixel remains untouched, including the openings beneath its deck.
	float left=smoothstep(120.0,180.0,world.x)*(1.0-smoothstep(735.0,790.0,world.x));
	float right=smoothstep(2015.0,2070.0,world.x)*(1.0-smoothstep(3160.0,3280.0,world.x));
	float lane=max(left,right);
	float shore=mix(681.0,568.0,clamp((world.x-700.0)/2600.0,0.0,1.0));
	shore+=sin(world.x*.008)*5.0;
	float water=smoothstep(442.0,452.0,world.y)*(1.0-smoothstep(shore-8.0,shore+5.0,world.y))*lane;
	vec2 pixel=floor(world/2.0)*2.0;
	float depth=clamp((world.y-445.0)/(shore-445.0),0.0,1.0);
	float swell=sin(depth*18.85-cinematic_time*2.3+sin(world.x*.004)*.4);
	// Advect the painted blue/green water vertically. The amplitude grows toward
	// the beach, creating a face that steepens before the white lip collapses.
	uv.y+=water*swell*(2.0+depth*4.0)/1300.0;
	uv.x+=water*sin(cinematic_time*.7+world.y*.035)*1.4/3900.0;
	vec3 color=texture(TEXTURE,uv).rgb;
	float phase=fract(depth*3.0-cinematic_time*.36+sin(world.x*.006)*.055);
	float crest=smoothstep(.68,.83,phase)*(1.0-smoothstep(.89,1.0,phase));
	float grain=noise(pixel*vec2(.045,.14)+vec2(cinematic_time*.2,0));
	float lip=smoothstep(.76,.83,phase)*(1.0-smoothstep(.88,.99,phase+grain*.065));
	float face=crest*(1.0-lip)*water*depth;
	color=mix(color,vec3(.12,.44,.50),face*.5);
	color=mix(color,vec3(1.0,.89,.68),lip*water*(.32+.55*depth)*smoothstep(.18,.6,grain));
	// Each nearshore breaker bursts into a wide, irregular foam tongue. It has
	// separate uprush and longer retreat phases, leaving a temporarily wet beach.
	float cycle=fract(cinematic_time/5.8+sin(world.x*.003)*.035);
	float rush=smoothstep(.08,.36,cycle);
	float retreat=smoothstep(.48,1.0,cycle);
	float advance=(rush-retreat)*27.0;
	float edge=shore-5.0+advance+noise(vec2(pixel.x*.015,cinematic_time*.18))*8.0;
	float shore_lane=lane*smoothstep(shore-45.0,shore-15.0,world.y);
	float wash=shore_lane*(1.0-smoothstep(edge-20.0,edge,world.y))*smoothstep(.08,.18,cycle);
	float wet=shore_lane*smoothstep(shore,shore+5.0,world.y)*(1.0-smoothstep(shore+30.0,shore+38.0,world.y));
	color=mix(color,color*vec3(.72,.82,.94),wet*.25*(1.0-retreat*.6));
	float froth=noise(pixel*.13+vec2(0,cinematic_time*.7));
	float rim=1.0-smoothstep(2.0,6.0,abs(world.y-edge));
	color=mix(color,vec3(.94,.94,.79),wash*(.15+.34*froth)*(1.0-retreat*.75));
	color=mix(color,vec3(1.0,.95,.81),rim*shore_lane*(.4+.4*froth)*sin(cycle*3.14159));
	COLOR=vec4(mix(original.rgb,color,max(water,shore_lane)),original.a);
}
