shader_type canvas_item;
render_mode unshaded;
uniform vec4 regions[32];
uniform vec2 behavior[32]; // kind, phase
uniform int region_count = 0;
uniform float clock_seconds = 0.0;
uniform float energy = 0.0;
uniform float celebration = 0.0;
uniform float activity = 1.0;
void fragment() {
 vec4 color = texture(TEXTURE,UV);
 vec2 p = UV*vec2(512.0,288.0);
 float t = floor(clock_seconds*12.0)/12.0;
 for (int i=0; i<32; i++) {
  if (i>=region_count) {break;}
  vec4 r=regions[i];
  if (p.x<r.x || p.y<r.y || p.x>=r.x+r.z || p.y>=r.y+r.w) {continue;}
  float kind=behavior[i].x;
  float phase=behavior[i].y;
  vec2 q=(p-r.xy)/r.zw;
  float edge=smoothstep(0.0,0.12,q.x)*smoothstep(0.0,0.12,1.0-q.x)*smoothstep(0.0,0.12,q.y)*smoothstep(0.0,0.12,1.0-q.y);
  if (kind<0.5) {
   // Light ripples in existing water colors, never displace scenery pixels.
   float water=smoothstep(0.02,0.20,color.b-color.r);
   float ripple=pow(max(0.0,sin(floor(p.y*2.0)*1.7-t*1.5+sin(p.x*0.35+phase))),10.0);
   color.rgb += vec3(0.10,0.16,0.18)*ripple*water*edge*activity;
  } else if(kind<1.5) {
   float warm=smoothstep(0.12,0.4,color.r-color.b)*smoothstep(0.3,0.7,color.r);
   float flicker=sin(t*2.1+phase)*0.025+sin(t*4.7+phase*2.0)*0.015;
   color.rgb *= 1.0+(flicker+celebration*0.10)*warm*edge*activity;
  } else if(kind<2.5) {
   float bright=max(color.r,max(color.g,color.b));
   float lit=smoothstep(0.35,0.7,bright);
   float sweep=pow(max(0.0,sin(q.x*7.0-t*(1.5+energy)+phase)),6.0);
   color.rgb += color.rgb*(0.05+0.18*sweep+celebration*0.22)*lit*edge*activity;
  } else {
   float lit=smoothstep(0.4,0.8,max(color.r,max(color.g,color.b)));
   float pulse=0.5+0.5*sin(t*3.0+phase);
   color.rgb *= 1.0+lit*edge*(0.035*pulse+celebration*0.25*pulse)*activity;
  }
 }
 COLOR=color;
}
