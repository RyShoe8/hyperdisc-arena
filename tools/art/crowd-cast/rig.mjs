import fs from 'node:fs';
import path from 'node:path';
import {pathToFileURL} from 'node:url';

// Native Rigby projects share choreography and retain all 25 painted attachments.
// Godot reads the same sampled attachment/translation tracks in release builds.
const fromRig = name => import(pathToFileURL(path.resolve(process.argv[2],name)));
const {zip} = await fromRig('src/editor/zip.js');
const {sample} = await fromRig('src/core/animation.js');
const poses = {
  clap: [[0,0,0,0],[14,8,-.01,-.015],[23,16,.01,-.035],[29,16,.01,-.035],[41,8,-.015,0],[53,16,.015,-.028],[60,16,.015,-.02],[75,8,-.01,0],[86,16,.01,-.03],[94,16,.01,-.03],[108,8,-.01,0],[125,0,0,0]],
  cheer: [[0,0,0,0],[8,0,-.025,.035],[23,24,.025,-.085],[34,24,.018,-.07],[46,23,.01,-.045],[57,24,.03,-.082],[70,24,.03,-.065],[97,0,0,0]],
  slump: [[0,0,0,0],[13,0,-.015,-.02],[38,0,.045,.09],[74,0,.04,.075],[107,0,0,0]],
  flinch: [[0,0,0,0],[7,5,-.055,.045],[17,7,-.04,.023],[35,0,0,0]],
  talk: [[0,0,0,0],[20,3,.055,-.01],[32,4,.069,.018],[44,3,.055,-.013],[60,4,.062,.007],[84,0,0,0]],
  listen: [[0,0,0,0],[22,0,.042,-.012],[42,0,.052,.021],[53,0,.047,-.012],[70,0,0,0]],
  lean: [[0,0,0,0],[16,0,.045,-.044],[47,0,.055,-.038],[75,0,0,0]]
};
const clips={}, animations=[];
for(const [name, keys] of Object.entries(poses)) {
  const ease={bezier:[.34,0,.62,1]};
  const positions=keys.map(([time,frame,x,y])=>({time:time/60,value:[x*172,-y*172],curve:ease}));
  const attach=keys.map(([time,frame])=>({time:time/60,value:frame,curve:ease}));
  const rows=[], swaps=[];
  for(let t=0;t<=keys.at(-1)[0];t++) {
    let frame=sample(attach,t/60);
    if(name==='cheer') {
      // Atlas cells 17..24 connect rest directly to the raised gesture.
      const k = frame<23 ? Math.round(frame/3) : Math.round(frame-16);
      frame = k ? 16+k : 0;
    } else frame=Math.round(frame);
    const [x,y]=sample(positions,t/60);
    rows.push([frame,+((x/172).toFixed(4)),+((-y/172).toFixed(4))]);
    if(!t || rows[t-1][0]!==frame) swaps.push({time:t/60,value:String(frame),curve:'stepped'});
  }
  clips[name]=rows;
  animations.push({name,duration:(rows.length-1)/60,bones:[{bone:1,translate:positions}],slots:[{slot:0,attachment:swaps}]});
}
fs.writeFileSync('data/crowd_motion.json',JSON.stringify(clips));
for(const view of ['front','profile','rear']) for(let id=0;id<12;id++) {
  const folder='build/crowd-attachments/'+view+'/'+id;
  const images=Array.from({length:25},(_,i)=>({name:String(i),width:152,height:172}));
  const bone=(name,parent)=>({name,parent,x:0,y:0,length:0,rotation:0,scale_x:1,scale_y:1});
  const slots=[{name:'performance',bone:1,attachment:'0',color:[1,1,1,1],
    attachments:images.map(img=>({...img,x:0,y:86,rotation:0,scale_x:1,scale_y:1}))}];
  const project={format:'rigby-snapshot/1',name:view+' fan '+id,textureFilter:'linear',images,
    bones:[bone('seat'),bone('body',0)],slots,events:[],animations};
  const files=images.map(img=>({path:'images/'+img.name+'.png',bytes:fs.readFileSync(folder+'/'+img.name+'.png')}));
  files.push({path:'project.json',bytes:Buffer.from(JSON.stringify(project))});
  fs.writeFileSync(folder+'/spectator.rigby',zip(files));
}
