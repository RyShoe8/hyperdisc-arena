// Native editable Rigby projects are the animation source. Godot consumes
// quads evaluated by Rigby's own Pose engine, not a second animation solver.
import fs from 'node:fs';
import path from 'node:path';
import {pathToFileURL} from 'node:url';
import {addActing} from './acting.mjs';
import {blockScene} from './blocking.mjs';
import {STAIR_START,STAIR_DURATION,STAIR_STEP,TREADS,stairPose} from './stairs.mjs';
const root = path.resolve(import.meta.dirname, '../../..');
const tool = path.resolve(process.argv[2] || path.join(root, 'build/rigby-tool'));
const use = file => import(pathToFileURL(path.join(tool, file)));
const {zip} = await use('src/editor/zip.js');
const {Skeleton} = await use('src/core/model.js');
const {Pose} = await use('src/core/pose.js');
const {actorStateAt} = await use('src/core/scene.js');
const {toolTable, callTool} = await use('src/cli/main.js');
const ids = ['mick','pete','tiffany','tango','alex','jimmy','jason','steve','vanessa','keno'];
const source = path.join(root, 'build/story-cast');
const output = path.join(root, 'tools/art/story/projects');
fs.mkdirSync(output,{recursive:true});
const bone=(name,parent,x=0,y=0)=>({name,...(parent===null?{}:{parent}),x,y,rotation:0,scale_x:1,scale_y:1,length:0});
const key=(time,value,curve={bezier:[.35,0,.65,1]})=>({time,value,curve});
const select=(slot,name)=>({slot,attachment:[key(0,name,'stepped')]});
const records={}, docs={}, entries={};
const round=n=>Math.round(n*1000)/1000;
function capturePose(sk,pose){
 const drawables=pose.quads(sk);
 const quads=drawables.filter(q=>q.kind==='region').map(q=>[q.image,...q.positions.flatMap(([x,y])=>[round(x),round(-y)])]);
 const mesh=drawables.find(q=>q.kind==='mesh');
 return mesh?{m:mesh.attachment.name,q:quads,b:pose.world.map(m=>[m.a,m.b,m.c,m.d,m.tx,m.ty].map(round))}:quads;
}
for(const id of ids){
 const meta=JSON.parse(fs.readFileSync(path.join(source,id,'source.json')));
 const images=meta.story_images, [ax,ay]=meta.anchor, [nx,ny]=meta.neck;
 const headPos=[nx-ax,ay-ny];
 const names=Object.keys(images);
 const attach=(name,b=1)=>{const [x,y,r,z]=images[name].crop;return {name,width:r-x,height:z-y,x:(x+r)/2-ax-(b===2?headPos[0]:0),y:ay-(y+z)/2-(b===2?headPos[1]:0),rotation:0,scale_x:1,scale_y:1};};
 const slot=(name,b,names,current)=>({name,bone:b,color:[1,1,1,1],attachment:current,attachments:names.map(n=>attach(n,b))});
 const anims=[];
 for(const [name,a] of Object.entries(meta.animations)){
  let time=0;const keys=[];
  for(let i=0;i<a.count;i++){keys.push(key(time,'frame-'+(a.start+i),'stepped'));time+=(a.ticks?.[i]??60/(a.fps||12))/60;}
  anims.push({name,duration:time,bones:[],slots:[{slot:0,attachment:keys},select(1,null),select(2,null)]});
 }
 if(id==='tiffany')anims.push({name:'stairs',duration:.6,bones:[],slots:[{slot:0,attachment:Array.from({length:6},(_,i)=>key(i*.1,'stairs-'+i,'stepped'))},select(1,null),select(2,null)]});
 if(id==='tango')anims.push({name:'look_back',duration:1.2,bones:[{bone:1,rotate:[key(0,0),key(.3,1),key(1.2,1)]}],slots:[select(0,'look-back'),select(1,null),select(2,null)]});
 for(const [name,angle] of [['listen',1.1],['speak',3.2],['resolve',-.8],['laugh',4.8]]){
  const duration=2.4;
  anims.push({name,duration,bones:[{bone:1,translate:[key(0,[0,0]),key(.6,[0,1.5]),key(1.2,[0,0]),key(1.8,[0,2]),key(2.4,[0,0])],scale:[key(0,[1,1]),key(1.2,[.998,1.006]),key(2.4,[1,1])]},{bone:2,rotate:[key(0,0),key(.4,angle),key(.9,-angle*.4),key(1.5,angle*.65),key(2.4,0)]}],slots:[select(0,null),select(1,'body'),select(2,'head')]});
 }
 // Authored action holds are editable in the same Rigby project.
 for(const [name,frame] of [['kneel',id==='mick'?9:meta.animations.knock.start],['reach',meta.animations.catch.start+1],['brace',meta.animations.hold.start]]){
  anims.push({name,duration:1,bones:[{bone:1,translate:[key(0,[0,0]),key(1,[0,-1])]}],slots:[select(0,'frame-'+frame),select(1,null),select(2,null)]});
 }
 const doc={format:'rigby-snapshot/1',name:id,workspace:'film',textureFilter:'nearest',images:names.map(name=>({name,width:images[name].crop[2]-images[name].crop[0],height:images[name].crop[3]-images[name].crop[1]})),bones:[bone('ground',null),bone('body',0),bone('head',1,...headPos)],slots:[slot('authored poses',1,names.filter(n=>n.startsWith('frame-')||n.startsWith('stairs-')||n==='rail-lean'||n==='look-back'),'frame-'+meta.animations.idle.start),slot('resting body',1,['body'],null),slot('acting head',2,['head'],null)],animations:anims};
 const acting=addActing(id,doc,meta);
 const files=names.map(name=>({path:'images/'+name+'.png',bytes:fs.readFileSync(path.join(source,id,name+'.png'))}));
 files.push({path:'project.json',bytes:Buffer.from(JSON.stringify(doc))});
 fs.writeFileSync(path.join(output,id+'.rigby'),zip(files));entries[id]=files;
 const sk=Skeleton.fromJson(JSON.stringify(doc)), pose=new Pose(sk); docs[id]=sk;
 const animations={};
 for(const anim of sk.animations){const frames=[];for(let i=0;i<=Math.ceil(anim.duration*30);i++){
  pose.reset(sk);pose.apply(sk,anim,Math.min(i/30,anim.duration),1);pose.updateWorld(sk);
  frames.push(capturePose(sk,pose));
 }animations[anim.name]={duration:anim.duration,frames};}
 records[id]={images,animations,meshes:acting.meshes||{acting:acting.mesh},anchors:acting.indices,meshAnchors:acting.meshAnchors||{}};
 if(id==='tiffany')records[id].stairs={start:STAIR_START,duration:STAIR_DURATION,step:STAIR_STEP,treads:TREADS};
}
const raw=JSON.parse(fs.readFileSync(path.join(root,'data/story_prologue.json')));
let elapsed=0;
const beats=raw.beats.map((b,i)=>{let duration=b.duration??Math.max(3.5,b.text.split(/\s+/).length/2.8+1.3);if(i===53)duration=5;if(i===35)duration=4.0;if(i===36)duration=1.0;const out={...b,start:round(elapsed),duration:round(duration)};elapsed+=duration;return out;});
const T=i=>beats[i].start;
const duration=round(elapsed);
const stage={format:'rigby-snapshot/1',name:'No Ordinary Day — beach prologue',workspace:'film',textureFilter:'nearest',settings:{width:1920,height:1080,fps:30,background:[.07,.04,.12,1],frame:{x:0,y:0,scale:1,camera:true}},images:[],bones:[bone('root',null),bone('camera',0)],slots:[],animations:[{name:'opening',duration,bones:[],slots:[]}],scene:{actors:[],depth:{},focal:1000}};
const shot=stage.animations[0];
const setFile=path.join(source,'beach-set.png');
if(fs.existsSync(setFile)){
 stage.images.push({name:'beach-set',width:3200,height:1400});
 stage.bones.push(bone('beach-set',0));
 stage.slots.push({name:'beach-set',bone:2,color:[1,1,1,1],attachment:'beach-set',attachments:[{name:'beach-set',width:3200,height:1400,x:1600,y:-700,rotation:0,scale_x:1,scale_y:1}]});
}
const positions={mick:[560,830],pete:[320,805],tango:[755,855],tiffany:[1500,574],alex:[2220,840],jimmy:[2780,815],jason:[2600,850],steve:[1980,810],vanessa:[2410,800],keno:[1790,835]};
const moveTracks={},flipTracks={};
for(const id of ids){
 const n=stage.bones.length;stage.bones.push(bone(id,0));stage.slots.push({name:id,bone:n,attachment:null,attachments:[],color:[1,1,1,1]});
 const actor={id,name:id,bone:id,slot:id,source:id+'.rigby',skin:null,flip:false,ground:0,clips:{opening:[]}};stage.scene.actors.push(actor);
 const [x,y]=positions[id];const scale=id==='tango'?1.05:1.15;
 const track={bone:n,translate:[key(0,[x,-y])],scale:[key(0,[['mick','pete','tango'].includes(id)?scale:-scale,scale],'stepped')]};shot.bones.push(track);moveTracks[id]=track;
 actor.clips.opening.push({animation:'listen',start:0,speed:1,loops:0,blend:0});
}
function move(id,t,x,y,curve='linear'){moveTracks[id].translate.push(key(t,[x,-y],curve));}
function face(id,t,right){const s=id==='tango'?1.05:1.15;moveTracks[id].scale.push(key(t,[right?s:-s,s],'stepped'));}
function size(id,t,s,right,interpolate=false){moveTracks[id].scale.push(key(t,[right?s:-s,s],interpolate?'linear':'stepped'));}
function clip(id,t,animation,loops=0,speed=1){stage.scene.actors.find(a=>a.id===id).clips.opening.push({start:round(t),animation,loops,speed,blend:0});}
blockScene({T,beats,clip,move,face,size,positions,runDurations:Object.fromEntries(ids.map(id=>[id,records[id].animations.run.duration]))});
const cameras=[];
function cam(t,x,y,z,cut=false){cameras.push({t,x,y,z,cut});}
cam(0,1150,560,.95);cam(T(1),850,575,1.3);
for(let i=2;i<54;i++){
 let x=1530,y=680,z=1.35;const b=beats[i];
 if(i<5){x=540;y=655;z=1.95;}
 else if(i===5){x=1495;y=440;z=1.95;}
 else if(i===6){x=1390;y=470;z=1.6;}
 else if(i>=37&&i<=43){x=1480;y=750;z=2.1;}
 else if(i===44||i===45){x=2130;y=710;z=.95;}
 else if(i>=49){x=1390;y=720;z=2.05;}
 else if(b.speaker&&positions[b.speaker]){x=(i<27&&b.speaker==='mick')?1160:(b.speaker==='mick'?1260:positions[b.speaker][0]);y=positions[b.speaker][1]-140;z=1.85;if(b.speaker==='tiffany'){x=1450;y=670;}if(b.speaker==='pete'){x=800;y=675;}if(b.speaker==='keno'&&i>=18){x=1685;y=680;}}
 if([7,15,16,17,25,31,35,36,51,52,53].includes(i)){x=i>=35?1490:2100;y=690;z=i>=51?1.2:1.02;}
 if(i===32){x=1850;y=670;z=1.08;}
 if(i===33){x=2730;y=620;z=1.65;}
 if(i===34){x=2340;y=665;z=1.85;}
 if(i===35){x=1350;y=740;z=2.0;}
 if(i===36){x=1660;y=660;z=1.15;}
 if(i===46){x=2830;y=640;z=1.85;}
 if(i===47){x=2540;y=570;z=1.85;}
 if(i===48){x=2460;y=660;z=1.85;}
 cam(T(i),x,y,z,true);
 if(i===6){
  for(let t=0;t<=STAIR_DURATION+.001;t+=.2){const {root}=stairPose(t);cam(T(i)+STAIR_START+t,root[0]+85,root[1]-90,1.6);}
  cam(T(i)+4.6,1730,650,.8,true);
 }
 if(i===35)cam(T(i)+1.15,1770,690,1.05,true);
 if(i===37){cam(T(i)+.55,1580,655,2.3,true);cam(T(i)+1.3,1480,750,2.1,true);}
 if(i===49){cam(T(i),2460,650,2.3,true);cam(T(i)+1.8,1415,635,2.5,true);}
 // Slow, motivated push inside a shot; never an automatic zoom on every line.
 if(i>=2 && beats[i].duration>6 && ![37,49].includes(i))cam(T(i)+beats[i].duration-.15,x+(i%2?12:-12),y-3,z*1.045);
}
cameras.sort((a,b)=>a.t-b.t);
const cameraTrack={bone:1,translate:[],scale:[]};shot.bones.push(cameraTrack);
for(const c of cameras){if(c.cut&&c.t>0){const prev=cameras[cameras.indexOf(c)-1];cameraTrack.translate.push(key(c.t-.001,[prev.x,-prev.y],'stepped'));cameraTrack.scale.push(key(c.t-.001,[prev.z,prev.z],'stepped'));}cameraTrack.translate.push(key(c.t,[c.x,-c.y]));cameraTrack.scale.push(key(c.t,[c.z,c.z]));}
for(const track of shot.bones)for(const type of ['translate','scale'])track[type]?.sort((a,b)=>a.time-b.time);
for(const actor of stage.scene.actors)actor.clips.opening.sort((a,b)=>a.start-b.start);
for(const actor of stage.scene.actors){
 const clips=actor.clips.opening;
 for(let i=1;i<clips.length;i++){
  const from=records[actor.id].animations[clips[i-1].animation].frames[0];
  const to=records[actor.id].animations[clips[i].animation].frames[0];
  if(from.m&&from.m===to.m)clips[i].blend=.18;
 }
}
const files=[{path:'project.json',bytes:Buffer.from(JSON.stringify(stage))}];
if(fs.existsSync(setFile))files.push({path:'images/beach-set.png',bytes:fs.readFileSync(setFile)});
const scoreFile=path.join(root,'assets/audio/story/prologue.ogg');
if(fs.existsSync(scoreFile)){
 stage.audio=[{sound:'prologue.ogg',animation:'opening',offset:0,volume:1}];
 files[0].bytes=Buffer.from(JSON.stringify(stage));
 files.push({path:'audio/prologue.ogg',bytes:fs.readFileSync(scoreFile)});
}
for(const id of ids)for(const e of entries[id])files.push({path:'actors/'+id+'/'+e.path,bytes:e.bytes});
fs.writeFileSync(path.join(output,'beach-prologue.rigby'),zip(files));
const stageDoc=Skeleton.fromJson(JSON.stringify(stage)), pose=new Pose(stageDoc), frames=[];
const blendPoses=Object.fromEntries(ids.map(id=>[id,new Pose(docs[id])]));
for(let f=0;f<=Math.ceil(duration*30);f++){
 const t=Math.min(duration,f/30);pose.reset(stageDoc);pose.apply(stageDoc,stageDoc.animations[0],t,1);pose.updateWorld(stageDoc);
 const c=pose.world[1];const actors=[];
 for(const actor of stageDoc.scene.actors){
  const w=pose.world[stageDoc.boneIndex(actor.bone)],doc=docs[actor.id],s=actorStateAt(actor,doc,'opening',t);
  let animation=s?.anim?.name||'idle',localTime=round(s?.time||0);
  if(s?.from?.anim){
   const p=blendPoses[actor.id];p.reset(doc);p.apply(doc,s.from.anim,s.from.time,1);p.apply(doc,s.anim,s.time,s.alpha);p.updateWorld(doc);
   animation='transition-'+f;localTime=0;
   records[actor.id].animations[animation]={duration:0,frames:[capturePose(doc,p)]};
  }
  actors.push([round(w.tx),round(-w.ty),round(w.a),round(w.d),animation,localTime]);
 }
 frames.push([round(c.tx),round(-c.ty),round(c.a),actors]);
}
fs.writeFileSync(path.join(root,'data/story_rigby.json'),JSON.stringify({generator:'Rigby2D '+JSON.parse(fs.readFileSync(path.join(tool,'package.json'))).version,fps:30,duration,ids,beats,cast:records,frames}));
const tools=toolTable(root);
for(const id of [...ids,'beach-prologue']){
 const r=await callTool(tools,'validate_project',{path:path.join(output,id+'.rigby')});
 fs.writeFileSync(path.join(source,id+'-validation.json'),JSON.stringify(r,null,2));
 console.log(id,JSON.stringify(r).slice(0,300));
}
console.log(`Baked ${duration}s / ${frames.length} frames from Rigby. Projects: ${output}`);
