import {STAIR_DURATION,STAIR_SCALE,stairPose,stairLocal,stairRailY} from './stairs.mjs';
// Pixel coordinates refer to the approved, unmodified 512px idle cells.
// Rigby owns the hierarchy, interpolation and skinning. These landmarks are
// deliberately authored per character rather than inferred from sprite bounds.
const landmarks = {
 mick: [[255,333],[264,268],[275,246],[282,226],[226,263],[202,294],[224,315],[238,325],[290,267],[302,301],[324,313],[338,319],[237,340],[215,374],[197,419],[279,341],[293,375],[291,419]],
 pete: [[260,325],[270,274],[280,250],[290,229],[238,265],[215,289],[205,310],[205,323],[292,273],[308,299],[326,314],[333,327],[241,331],[231,363],[209,410],[280,333],[305,362],[308,407]],
 tiffany: [[260,311],[273,273],[279,247],[290,231],[240,264],[217,283],[198,299],[183,311],[295,270],[308,297],[326,299],[337,296],[242,327],[239,358],[207,410],[279,326],[310,361],[324,410]],
 keno: [[268,320],[271,253],[281,225],[281,202],[220,236],[191,280],[191,307],[197,329],[313,245],[331,278],[345,309],[349,331],[242,329],[228,366],[218,414],[290,329],[309,367],[315,410]],
 steve: [[274,311],[289,264],[306,242],[322,222],[247,254],[221,279],[209,311],[211,327],[311,270],[327,295],[354,306],[367,311],[250,320],[213,361],[172,409],[285,321],[330,348],[331,409]],
 vanessa: [[270,306],[278,268],[281,247],[290,225],[252,265],[230,289],[216,308],[210,323],[298,269],[309,294],[332,311],[341,318],[252,315],[238,360],[218,411],[283,315],[309,360],[332,411]],
 alex: [[263,323],[270,269],[289,244],[295,222],[220,269],[204,289],[226,310],[238,313],[302,269],[330,308],[352,295],[364,289],[243,336],[214,374],[178,426],[287,337],[318,370],[331,424]],
 jimmy: [[268,321],[278,270],[294,244],[296,222],[234,269],[217,290],[218,316],[222,333],[303,267],[328,294],[355,305],[365,313],[247,338],[217,378],[198,424],[284,337],[326,358],[327,414]],
 jason: [[267,321],[270,263],[294,238],[294,216],[221,267],[193,294],[235,303],[245,297],[311,268],[336,301],[356,297],[365,290],[242,337],[209,377],[183,424],[285,337],[320,375],[326,424]],
};
const ease={bezier:[.32,0,.68,1]};
const key=(time,value,curve=ease)=>({time,value,curve});
const names=['hips','chest','neck','head','arm_back','forearm_back','wrist_back','hand_back','arm_front','forearm_front','wrist_front','hand_front','thigh_back','shin_back','foot_back','thigh_front','shin_front','foot_front'];
const parents=['ground','hips','chest','neck','chest','arm_back','forearm_back','wrist_back','chest','arm_front','forearm_front','wrist_front','hips','thigh_back','shin_back','hips','thigh_front','shin_front'];
function distance(p,a,b){const dx=b[0]-a[0],dy=b[1]-a[1],t=Math.max(0,Math.min(1,((p[0]-a[0])*dx+(p[1]-a[1])*dy)/(dx*dx+dy*dy||1)));return Math.hypot(p[0]-a[0]-t*dx,p[1]-a[1]-t*dy);}

export function addActing(id,doc,meta){
 if(id==='tango')return addDog(doc,meta);
 const pts=Object.fromEntries(names.map((n,i)=>[n,landmarks[id][i]]));
 const [ax,ay]=meta.anchor;
 pts.ground=[ax,ay];
 const indices={ground:0};
 // Keep the legacy frame, body and head slots for the game's run/throw cells.
 for(let i=0;i<names.length;i++){
  const name=names[i],parent=parents[i],p=pts[name],origin=pts[parent]||[ax,ay];
  indices[name]=doc.bones.length;
  doc.bones.push({name:'acting_'+name,parent:indices[parent],x:p[0]-origin[0],y:origin[1]-p[1],rotation:0,scale_x:1,scale_y:1,length:0});
 }
 const jaw=[pts.head[0]+8,pts.head[1]+12],eye=[pts.head[0]+10,pts.head[1]-1];
 if(id==='tiffany'){
  pts.hair=[252,220];indices.hair=doc.bones.length;
  doc.bones.push({name:'acting_hair',parent:indices.head,x:pts.hair[0]-pts.head[0],y:pts.head[1]-pts.hair[1],rotation:0,scale_x:1,scale_y:1,length:0});
 }
 for(const [name,p]of [['jaw',jaw],['eyelids',eye]]){indices[name]=doc.bones.length;pts[name]=p;doc.bones.push({name:'acting_'+name,parent:indices.head,x:p[0]-pts.head[0],y:pts.head[1]-p[1],rotation:0,scale_x:1,scale_y:1,length:0});}
 const ends={hips:'chest',chest:'neck',neck:'head',arm_back:'forearm_back',forearm_back:'wrist_back',wrist_back:'hand_back',arm_front:'forearm_front',forearm_front:'wrist_front',wrist_front:'hand_front',thigh_back:'shin_back',shin_back:'foot_back',thigh_front:'shin_front',shin_front:'foot_front'};
 const widths={hips:27,chest:27,neck:12,head:21,arm_back:17,forearm_back:13,hand_back:17,arm_front:17,forearm_front:13,hand_front:17,thigh_back:20,thigh_front:20,shin_back:13,shin_front:13,foot_back:14,foot_front:14};
 const choose=(p)=>{
  if(id==='tiffany'&&p[0]<272&&p[1]<260)return [['hair',1]];
  // Standing performances never reskin the legs. Earlier arm influences leaked
  // into nearby knee pixels even with IK disabled; lock the complete lower body.
  if(p[1]>Math.max(pts.hips[1]+18,pts.hand_back[1]+18,pts.hand_front[1]+18))return [['ground',1]];
  // Facial details follow local jaw/eyelid bones without stretching the cranium.
  if(Math.abs(p[0]-jaw[0])<8&&Math.abs(p[1]-jaw[1])<5)return [['jaw',.8],['head',.2]];
  if(Math.abs(p[0]-eye[0])<9&&Math.abs(p[1]-eye[1])<3)return [['eyelids',.9],['head',.1]];
  if(p[1]<pts.neck[1]-5)return [['head',1]];
  let candidates=Object.keys(widths).filter(n=>{
   if(id==='keno'&&p[1]>310&&p[0]>225&&p[0]<328)return ['hips','thigh_back','shin_back','foot_back','thigh_front','shin_front','foot_front'].includes(n);
   if(id==='tiffany'&&p[0]>252&&p[0]<302&&p[1]>256&&p[1]<298)return ['chest','neck','hips'].includes(n);
   return true;
  }).map(n=>{
   let end=pts[ends[n]]||pts[n];if(n.startsWith('foot'))end=[end[0]+17,end[1]+12];
   if(n.startsWith('hand')){const wrist=pts[n.replace('hand','wrist')];end=[end[0]+(end[0]-wrist[0])*1.2,end[1]+(end[1]-wrist[1])*1.2];}
   return [n,distance(p,pts[n],end)/(widths[n]||10)];
  }).sort((a,b)=>a[1]-b[1]).slice(0,2);
  const weights=candidates.map(([n,d])=>[n,1/Math.pow(.15+d,6)]),total=weights.reduce((s,w)=>s+w[1],0);
  return weights.map(([n,w])=>[n,w/total]);
 };
 const mesh=makeMesh(meta,choose,pts,indices);
 const slot=doc.slots.length;
 doc.slots.push({name:'full body acting',bone:0,color:[1,1,1,1],attachment:null,attachments:[mesh]});
 // All existing atlas clips must explicitly release the acting mesh.
 for(const a of doc.animations)a.slots.push({slot,attachment:[key(0,null,'stepped')]});
 const base={arm_back:18,forearm_back:-12,arm_front:-27,forearm_front:-22,head:0,chest:0,hipsX:0,hipsY:0};
 const poses={
  neutral:{}, curious:{head:9,chest:-3,arm_front:-5,forearm_front:12},
  explain:{chest:4,head:-5,arm_front:25,forearm_front:18,arm_back:8,forearm_back:-5,hipsX:4},
  palms:{chest:-4,head:4,arm_front:43,forearm_front:34,arm_back:-22,forearm_back:-45,hipsY:3},
  boast:{chest:-7,head:11,arm_front:45,forearm_front:63,arm_back:29,forearm_back:-14,hipsY:5},
  point:{chest:7,head:-6,arm_front:68,forearm_front:-33,arm_back:20,hipsX:6},
  shrug:{chest:-5,head:7,arm_front:38,forearm_front:47,arm_back:-30,forearm_back:-36,hipsY:3},
  laugh:{chest:17,head:-14,arm_front:8,forearm_front:58,arm_back:10,forearm_back:25,hipsY:-9,jaw:2},
  laugh_back:{chest:-11,head:15,arm_front:20,forearm_front:38,arm_back:-4,hipsY:2,jaw:3},
  bored:{chest:4,head:-10,arm_front:35,forearm_front:92,arm_back:24,hipsY:-3},
  alarm:{chest:-12,head:10,arm_front:53,forearm_front:18,arm_back:-28,forearm_back:-17,hipsX:-6,hipsY:-8,jaw:2},
  anger:{chest:8,head:-10,arm_front:-8,forearm_front:9,arm_back:4,hipsX:5,hipsY:-3},
  down:{chest:25,head:-20,arm_front:-12,forearm_front:-18,arm_back:9,hipsY:-36,hipsX:8},
  rescue:{chest:23,head:-18,arm_front:-7,forearm_front:23,arm_back:8,forearm_back:-28,hipsY:-29,hipsX:9},
  carry:{chest:10,head:-9,arm_front:22,forearm_front:33,arm_back:-5,forearm_back:-25,hipsY:-8},
  grief:{chest:22,head:-25,arm_front:32,forearm_front:102,arm_back:24,hipsY:-32,hipsX:6},
  warning:{chest:8,head:-6,arm_front:60,forearm_front:-16,arm_back:-8,hipsY:-2},
  salute:{chest:-4,head:8,arm_front:60,forearm_front:100,arm_back:22,hipsY:3},
 };
 const schedules={
  listen:[[0,'neutral'],[.3,'curious'],[3.8,'curious'],[4.8,'neutral']],
  speak:[[0,'neutral'],[.3,'explain'],[1.65,'explain'],[1.95,'point'],[3.75,'point'],[4.2,'neutral'],[4.8,'neutral']],
  storytelling:[[0,'explain'],[.7,'palms'],[1.5,'point'],[2.2,'boast'],[3.2,'palms'],[4,'explain'],[5.6,'neutral']],
  boast:[[0,'neutral'],[.65,'boast'],[1.6,'salute'],[2.7,'point'],[3.8,'boast'],[4.8,'boast']],
  laugh:[[0,'neutral'],[.28,'laugh_back'],[.65,'laugh'],[1.35,'laugh'],[1.7,'laugh_back'],[2.2,'neutral'],[2.7,'neutral']],
  shrug:[[0,'neutral'],[.4,'shrug'],[1.1,'shrug'],[1.8,'explain'],[2.8,'neutral']],
  bored:[[0,'neutral'],[.8,'bored'],[2.2,'bored'],[3.4,'neutral']],
  alarm:[[0,'neutral'],[.18,'alarm'],[.6,'alarm'],[1.5,'warning'],[2.4,'alarm']],
  point:[[0,'neutral'],[.35,'point'],[1.1,'point'],[1.65,'explain'],[2.8,'neutral']],
  anger:[[0,'neutral'],[.7,'anger'],[1.7,'point'],[2.4,'anger'],[3.7,'anger']],
  kneel:[[0,'neutral'],[.65,'down'],[1.1,'rescue'],[2.4,'rescue']],
  console:[[0,'down'],[.65,'rescue'],[1.5,'down'],[2.8,'rescue']],
  grief:[[0,'down'],[1,'grief'],[2.3,'grief'],[3.4,'down']],
  carry:[[0,'carry'],[.3,'carry'],[.6,'carry']],
  rise:[[0,'grief'],[.8,'down'],[1.9,'anger'],[3,'anger']],
  resolve:[[0,'anger'],[1.1,'anger'],[2.3,'point'],[3.2,'anger']],
  warning:[[0,'neutral'],[.3,'warning'],[1.2,'warning'],[2,'explain'],[2.9,'warning']],
  reach:[[0,'neutral'],[.2,'explain'],[.5,'point'],[.85,'boast'],[1.3,'neutral']],
 };
 for(const [name,seq]of Object.entries(schedules)){
  doc.animations=doc.animations.filter(a=>a.name!==name);
  const duration=seq.at(-1)[0],tracks=new Map();
  const add=(n,type,t,v)=>{const b=indices[n];if(!tracks.has(b))tracks.set(b,{bone:b});const a=tracks.get(b);(a[type]??=[]).push(key(t,v));};
  for(const [t,p]of seq){const pose={...base,...poses[p]};
   pose.hipsX=0;pose.hipsY=0;
   if(['mick','pete','tiffany'].includes(id)&&['down','rescue','grief'].includes(p)){pose.chest=Math.min(16,pose.chest);}
   for(const n of ['chest','head','arm_front','forearm_front','arm_back','forearm_back'])add(n,'rotate',t,pose[n]*(n==='chest'?-.22:n.includes('arm')?.4:.45));
   add('hips','translate',t,[pose.hipsX,pose.hipsY]);
   add('jaw','translate',t,[0,-(pose.jaw||0)]);


  }
  if(id==='tiffany'){for(let t=0;t<=duration+.001;t+=.1)add('hair','rotate',Math.min(t,duration),-2+Math.sin(t*3.1)*3+Math.sin(t*6)*1.2);}
  const talking=['speak','storytelling','boast','shrug','warning','point','anger'].includes(name);
  if(talking){const tr=tracks.get(indices.jaw);tr.translate=[];for(let t=0;t<=duration;t+=.14)tr.translate.push(key(+t.toFixed(3),[0,(Math.sin(t*21)+Math.sin(t*39)>.1)?-1.8:0]));}
  tracks.set(indices.eyelids,{bone:indices.eyelids,scale:[key(0,[1,1]),key(.93,[1,1]),key(.99,[1,.13]),key(1.07,[1,1]),key(duration,[1,1])]});
  doc.animations.push({name,duration,bones:[...tracks.values()],slots:[0,1,2].map(slot=>({slot,attachment:[key(0,null,'stepped')]})).concat([{slot,attachment:[key(0,'acting','stepped')]}])});
 }
 const meshes={acting:mesh};
 const meshAnchors={};
 if(id==='mick'){const k=addKneeling(doc,meta,slot);meshes.kneeling=k.mesh;meshAnchors.kneeling=k.indices;}
 if(id==='vanessa'){const k=addRailLean(doc,meta,slot);meshes.rail=k.mesh;meshAnchors.rail=k.indices;}
 if(id==='tiffany'){const k=addStairs(doc,meta);Object.assign(meshes,k.meshes);Object.assign(meshAnchors,k.meshAnchors);}
 return {mesh,meshes,indices,meshAnchors};
}

function makeMesh(meta,choose,pts,indices,image='frame-'+meta.animations.idle.start,grid=meta.acting_grid){
 const crop=meta.story_images[image].crop;
 const adjacency=grid.points.map(()=>new Set());
 for(let i=0;i<grid.triangles.length;i+=3){const tri=grid.triangles.slice(i,i+3);for(const a of tri)for(const b of tri)if(a!==b)adjacency[a].add(b);}
 let weights=grid.points.map((p,i)=>Object.fromEntries(choose(grid.bind_points[i])));
 // Weight-paint smoothing prevents a single edge vertex being pulled by a
 // distant joint. This remains native Rigby skin data, not a runtime warp.
 for(let pass=0;pass<2;pass++)weights=weights.map((own,i)=>{
  const result=Object.fromEntries(Object.entries(own).map(([n,w])=>[n,w*.55]));
  for(const j of adjacency[i])for(const [n,w]of Object.entries(weights[j]))result[n]=(result[n]||0)+w*.45/adjacency[i].size;
  return result;
 });
 return {name:'acting',type:'mesh',image,width:crop[2]-crop[0],height:crop[3]-crop[1],uvs:grid.points.flatMap(p=>[(p[0]-crop[0])/(crop[2]-crop[0]),(p[1]-crop[1])/(crop[3]-crop[1])]),triangles:grid.triangles,hull:0,
 weights:grid.points.map((p,i)=>{const entries=Object.entries(weights[i]).filter(([,w])=>w>.012),sum=entries.reduce((n,[,w])=>n+w,0);return entries.map(([name,weight])=>({bone:indices[name],x:p[0]-pts[name][0],y:pts[name][1]-p[1],weight:weight/sum}));}) };
}

function addDog(doc,meta){
 const pts={spine:[270,370],head:[320,327],jaw:[343,334],tail:[205,355],tailtip:[172,319],ears:[314,309],backlegs:[220,395],frontlegs:[303,395]};
 const parents={head:'spine',jaw:'head',tail:'spine',tailtip:'tail',ears:'head',backlegs:'spine',frontlegs:'spine'},indices={};
 for(const [n,p]of Object.entries(pts)){const parent=parents[n],o=pts[parent]||meta.anchor;indices[n]=doc.bones.length;doc.bones.push({name:'acting_'+n,parent:parent?indices[parent]:0,x:p[0]-o[0],y:o[1]-p[1],rotation:0,scale_x:1,scale_y:1,length:0});}
 const mesh=makeMesh(meta,p=>{
  if(p[0]<210&&p[1]<365)return p[1]<336?[['tailtip',.7],['tail',.3]]:[['tail',1]];
  if(p[0]>315&&p[1]>327&&p[1]<345)return [['jaw',.8],['head',.2]];
  if(p[1]<319&&p[0]>290)return [['ears',.8],['head',.2]];
  if(p[1]<355&&p[0]>290)return [['head',1]];
  if(p[1]>400)return [[p[0]<260?'backlegs':'frontlegs',1]];
  return [['spine',1]];
 },pts,indices);
 const slot=doc.slots.length;doc.slots.push({name:'dog acting',bone:0,color:[1,1,1,1],attachment:null,attachments:[mesh]});
 for(const a of doc.animations)a.slots.push({slot,attachment:[key(0,null,'stepped')]});
 for(const [name,alert]of [['listen',false],['wag',false],['alert',true]]){
  doc.animations=doc.animations.filter(a=>a.name!==name);
  doc.animations.push({name,duration:2,bones:[
   {bone:indices.tail,rotate:[key(0,-9),key(.25,13),key(.5,-9),key(.75,13),key(1,-9),key(1.25,13),key(1.5,-9),key(1.75,13),key(2,-9)]},
   {bone:indices.tailtip,rotate:[key(0,8),key(.5,-12),key(1,8),key(1.5,-12),key(2,8)]},
   {bone:indices.head,rotate:[key(0,0),key(.4,alert?14:-7),key(1.2,alert?10:3),key(2,0)]},
   {bone:indices.ears,rotate:[key(0,0),key(.3,alert?-15:5),key(.7,0),key(2,0)]},
   {bone:indices.jaw,translate:[key(0,[0,0]),key(.35,[0,-1.5]),key(.7,[0,0]),key(1.1,[0,-1.5]),key(1.5,[0,0]),key(2,[0,0])]},
  ],slots:[0,1,2].map(slot=>({slot,attachment:[key(0,null,'stepped')]})).concat([{slot,attachment:[key(0,'acting','stepped')]}])});
 }
 return {mesh,indices};
}

// The crouch is the existing hand-drawn frame, never a compressed standing
// mesh. Legs are rigid; only a restrained upper-body lean and head bow move.
function addKneeling(doc,meta,slot){
 const pts={ground:meta.anchor,torso:[263,340],head:[321,290],jaw:[342,289]}, indices={ground:0};
 for(const [name,parent]of [['torso','ground'],['head','torso'],['jaw','head']]){
  indices[name]=doc.bones.length;const p=pts[name],o=pts[parent];
  doc.bones.push({name:'kneeling_'+name,parent:indices[parent],x:p[0]-o[0],y:o[1]-p[1],rotation:0,scale_x:1,scale_y:1,length:0});
 }
 const mesh=makeMesh(meta,p=>{
  if(p[1]>345)return [['ground',1]];
  if(p[0]>305&&p[1]<299)return [['head',1]];
  if(p[1]>330){const f=(345-p[1])/15;return [['ground',1-f],['torso',f]];}
  return [['torso',1]];
 },pts,indices,'frame-9',meta.kneel_grid);
 mesh.name='kneeling';doc.slots[slot].attachments.push(mesh);
 const sequences={
  kneel:[[0,0,0],[.4,-2,-3],[2.4,-2,-3]],
  console:[[0,-2,-3],[.4,-3,-9],[1.6,-3,-9],[2.1,-2,-5],[3,-2,-5]],
  grief:[[0,-2,-5],[.7,-4,-14],[2.8,-4,-14],[3.6,-3,-12]],
 };
 for(const [name,seq]of Object.entries(sequences)){
  doc.animations=doc.animations.filter(a=>a.name!==name);
  doc.animations.push({name,duration:seq.at(-1)[0],bones:[{bone:indices.torso,rotate:seq.map(([t,v])=>key(t,v))},{bone:indices.head,rotate:seq.map(([t,,v])=>key(t,v))}],slots:[0,1,2].map(slot=>({slot,attachment:[key(0,null,'stepped')]})).concat([{slot,attachment:[key(0,'kneeling','stepped')]}])});
 }
 return {mesh,indices};
}

function addRailLean(doc,meta,slot){
 const pts={ground:meta.anchor,torso:[268,295],head:[270,230],hand_front:[363,255]},indices={ground:0};
 for(const name of ['torso','head','hand_front']){
  const p=pts[name],parent=name==='head'?'torso':'ground',o=pts[parent];
  indices[name]=doc.bones.length;
  doc.bones.push({name:'rail_'+name,parent:indices[parent],x:p[0]-o[0],y:o[1]-p[1],rotation:0,scale_x:1,scale_y:1,length:0});
 }
 const mesh=makeMesh(meta,p=>{
  // Palm and feet remain in world contact. Only the supported torso/head act.
  if(p[1]>318||p[0]>310)return [['ground',1]];
  if(p[1]<249)return [['head',1]];
  return [['torso',.5],['ground',.5]];
 },pts,indices,'rail-lean',meta.lean_grid);
 mesh.name='rail';doc.slots[slot].attachments.push(mesh);
 for(const [name,amount]of [['rail_lean',-2],['rail_push',3]]){
  doc.animations.push({name,duration:2.4,bones:[
   {bone:indices.torso,rotate:[key(0,0),key(.6,amount),key(2.4,amount)]},
   {bone:indices.head,rotate:[key(0,0),key(.7,-5),key(1.8,-5),key(2.4,0)]}
  ],slots:[0,1,2].map(slot=>({slot,attachment:[key(0,null,'stepped')]})).concat([{slot,attachment:[key(0,'rail','stepped')]}])});
 }
 return {mesh,indices};
}

function addStairs(doc,meta){
 // A continuous native Rigby rig replaces six whole-sprite swaps. The soles
 // have explicit world-space contacts, with fixed-length knees bending toward
 // the toes. Neither the camera nor the runtime compositor solves the limbs.
 const pts={ground:meta.anchor,hair:[235,230],head:[269,245],neck:[269,261],
  front_hip:[263,322],front_knee:[282,370],front_ankle:[299,418],front_sole:[310,436],
  back_hip:[239,320],back_knee:[250,363],back_ankle:[232,418],back_sole:[244,442],
  shoulder:[284,270],elbow:[307,290],hand_front:[329,296]};
 const indices={ground:0},angles={ground:0};
 const add=(name,parent,rotation=0,length=0)=>{
  const p=pts[name],o=pts[parent],a=(angles[parent]||0)*Math.PI/180;
  const dx=p[0]-o[0],dy=o[1]-p[1];
  indices[name]=doc.bones.length;angles[name]=rotation;
  doc.bones.push({name:'stairs_'+name,parent:indices[parent],x:dx*Math.cos(a)+dy*Math.sin(a),y:-dx*Math.sin(a)+dy*Math.cos(a),rotation:rotation-(angles[parent]||0),scale_x:1,scale_y:1,length});
 };
 const direction=(a,b)=>Math.atan2(pts[a][1]-pts[b][1],pts[b][0]-pts[a][0])*180/Math.PI;
 const length=(a,b)=>Math.hypot(pts[b][0]-pts[a][0],pts[b][1]-pts[a][1]);
 for(const name of ['hair','head','neck'])add(name,'ground');
 doc.ik??=[];
 for(const limb of [['front_hip','front_knee','front_ankle'],['back_hip','back_knee','back_ankle']]){
  const [a,b,c]=limb;
  add(a,'ground',direction(a,b),length(a,b));add(b,a,direction(b,c),length(b,c));add(c,'ground');
  doc.ik.push({name:'stairs_'+a,bones:[indices[a],indices[b]],target:indices[c],mix:1,bendPositive:false,stretch:false,compress:false});
 }
 add('shoulder','ground',direction('shoulder','hand_front'),length('shoulder','hand_front'));
 add('elbow','shoulder',direction('shoulder','hand_front'));
 add('hand_front','ground');
 doc.ik.push({name:'stairs_supported_arm',bones:[indices.shoulder],target:indices.hand_front,mix:1,stretch:false,compress:false});
 add('front_sole','front_ankle');add('back_sole','back_ankle');
 const segments={front_hip:'front_knee',front_knee:'front_ankle',back_hip:'back_knee',back_knee:'back_ankle',shoulder:'elbow',elbow:'hand_front'};
 const mesh=makeMesh(meta,p=>{
  if(p[0]<254&&p[1]<278)return [['hair',1]];
  let candidates;
  if(p[0]>286&&p[1]>263&&p[1]<316){
   // Preserve the drawn forearm's volume. Its complete silhouette rotates
   // about the shoulder, rather than shearing between wrist and elbow bones.
   const influence=Math.min(1,(p[0]-286)/12);
   return [['shoulder',influence],['ground',1-influence]];
  }else if(p[1]>320){
   if(p[1]>416)return [[p[0]>270?'front_ankle':'back_ankle',1]];
   candidates=['front_hip','front_knee','back_hip','back_knee'];
  }else return [['ground',1]];
  const nearest=candidates.map(n=>[n,distance(p,pts[n],pts[segments[n]])]).sort((a,b)=>a[1]-b[1]).slice(0,2);
  const weights=nearest.map(([n,d])=>[n,1/Math.pow(2+d,6)]),sum=weights.reduce((s,w)=>s+w[1],0);
  const blend=p[1]>320&&p[1]<333?(p[1]-320)/13:1;
  return weights.map(([n,w])=>[n,w/sum*blend]).concat(blend<1?[['ground',1-blend]]:[]);
 },pts,indices,'stairs-2',meta.stairs_grids[2]);
 // makeMesh uses unrotated bind coordinates; transform each weight into the
 // actual oriented bone's bind frame before Rigby skins it.
 const angleByIndex=Object.fromEntries(Object.entries(indices).map(([n,i])=>[i,(angles[n]||0)*Math.PI/180]));
 for(const vertex of mesh.weights)for(const w of vertex){const a=angleByIndex[w.bone],x=w.x,y=w.y;w.x=x*Math.cos(a)+y*Math.sin(a);w.y=-x*Math.sin(a)+y*Math.cos(a);}
 mesh.name='stair-descent';
 const slot=doc.slots.length;
 doc.slots.push({name:'stair performance',bone:0,color:[1,1,1,1],attachment:null,attachments:[mesh]});
 doc.animations=doc.animations.filter(a=>a.name!=='stairs');
 for(const a of doc.animations)a.slots.push({slot,attachment:[key(0,null,'stepped')]});
 const tracks=new Map();
 const translate=(name,t,p)=>{const bone=indices[name];if(!tracks.has(bone))tracks.set(bone,{bone,translate:[]});tracks.get(bone).translate.push(key(t,[p[0]-pts[name][0],pts[name][1]-p[1]],'linear'));};
 for(let i=0;i<=Math.round(STAIR_DURATION*30);i++){
  const t=i/30,{root,feet}=stairPose(t);
  for(const [f,name,sole]of [[0,'front_ankle','front_sole'],[1,'back_ankle','back_sole']]){
   const local=stairLocal(feet[f],root);
   translate(name,t,[local[0]-(pts[sole][0]-pts[name][0]),local[1]-(pts[sole][1]-pts[name][1])]);
  }
  const shoulder=[root[0]-(pts.shoulder[0]-256)*STAIR_SCALE,root[1]+(pts.shoulder[1]-450)*STAIR_SCALE];
  const slope=-255/366,norm=Math.hypot(1,slope),intercept=stairRailY(0);
  const signed=(shoulder[1]-slope*shoulder[0]-intercept)/norm;
  const projection=[shoulder[0]+signed*slope/norm,shoulder[1]-signed/norm];
  const radius=length('shoulder','hand_front')*STAIR_SCALE;
  const reach=Math.sqrt(Math.max(0,radius*radius-signed*signed));
  const palm=[projection[0]-reach/norm,projection[1]-reach*slope/norm];
  translate('hand_front',t,stairLocal(palm,root));
 }
 const hair=[];for(let t=0;t<=STAIR_DURATION+.001;t+=.1)hair.push(key(t,-2+Math.sin(t*3.1)*3+Math.sin(t*6)*1.2));
 doc.animations.push({name:'stairs',duration:STAIR_DURATION,bones:[...tracks.values(),{bone:indices.hair,rotate:hair}],slots:doc.slots.map((_,s)=>({slot:s,attachment:[key(0,s===slot?mesh.name:null,'stepped')]}))});
 return {meshes:{[mesh.name]:mesh},meshAnchors:{[mesh.name]:indices}};
}
