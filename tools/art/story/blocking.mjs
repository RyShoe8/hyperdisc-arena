import {STAIR_START,STAIR_DURATION,STAIR_SCALE,stairPose} from './stairs.mjs';
// Performance direction for the opening. Walks, gestures and reaction delays
// are separate from dialogue duration; captions never drive the acting loop.
export function blockScene({T,beats,clip,move,face,size,positions,runDurations}){
 const gang=['keno','steve','alex','jimmy','jason','vanessa'];
 const play=(id,beat,anim,delay=0,speed=1)=>clip(id,T(beat)+delay,anim,1,speed);
 const action=(id,beat,anim,delay=0)=>{play(id,beat,anim,delay);};
 // A complete stride must cover a consistent distance, regardless of clip FPS.
 const stride={mick:132,pete:124,tiffany:116,tango:68,alex:118,jimmy:120,jason:126,steve:126,vanessa:116,keno:126};
 const travel=(id,t,from,to,length)=>{
  const distance=Math.hypot(to[0]-from[0],to[1]-from[1]);
  const scale=id==='tango'?1.05:1.15;
  const speed=distance/length/(stride[id]*scale)*runDurations[id];
  face(id,t,to[0]>=from[0]);move(id,t,...from);move(id,t+length,...to);
  clip(id,t,'run',0,Math.max(.12,speed));clip(id,t+length,'listen',1);
 };
 // A complete game of fetch, then another invitation to play while Pete talks.
 clip('tango',0,'wag');clip('mick',.7,'throw',1,.8);clip('mick',2,'listen',1);
 travel('tango',1.2,[755,855],[1030,844],1.45);
 // Push off, catch at the apex, then land before turning back. Dense authored
 // trajectory keys preserve the ballistic arc in the native Rigby scene.
 clip('tango',2.65,'jump',1,.22);
 for(let i=0;i<=36;i++){
  const p=i/36;move('tango',2.65+p*1.2,1030+p*145,844-4*142*p*(1-p));
 }
 clip('tango',3.85,'idle',1,.6);
 travel('tango',4.25,[1175,844],[710,855],3.15);
 face('tango',7.4,true);clip('tango',7.4,'wag');
 play('mick',1,'reach');play('mick',1,'listen',2);
 for(const b of [2,3,4]){
  play('pete',b,'storytelling');play('mick',b,'listen',.5);
  if(beats[b].duration>6)play('pete',b,'point',5.7);
  if(beats[b].duration>9)play('pete',b,'shrug',8.6);
 }
 face('mick',T(2),false);face('mick',T(4)+2,true);
 play('tango',3,'alert',3);clip('tango',T(3)+5,'wag');
 play('tiffany',5,'point');play('tiffany',5,'bored',2);
 // Stagger arrivals; nobody slides along in an idle pose.
 // Let the stair performance finish before foreground arrivals cross it.
 travel('mick',T(6)+4.5,positions.mick,[1160,840],3.1);
 travel('pete',T(6)+4.6,positions.pete,[800,830],3.2);
 travel('tango',T(6)+4.7,[710,855],[1260,880],2.9);
 clip('tango',T(7),'wag');
 // Approach on the platform, descend each painted tread, then leave the rails.
 const top=stairPose(0).root,bottom=stairPose(STAIR_DURATION).root;
 travel('tiffany',T(6),positions.tiffany,top,STAIR_START);
 size('tiffany',T(6),STAIR_SCALE,false);
 size('tiffany',T(6)+STAIR_START,STAIR_SCALE,false);
 clip('tiffany',T(6)+STAIR_START,'stairs',1,1);
 for(let i=0;i<=Math.round(STAIR_DURATION*30);i++){
  const t=i/30;move('tiffany',T(6)+STAIR_START+t,...stairPose(t).root);
 }
 const landed=T(6)+STAIR_START+STAIR_DURATION;
 travel('tiffany',landed,bottom,[1450,830],2.6);
 size('tiffany',landed,STAIR_SCALE,true,true);
 size('tiffany',landed+2.5,1.15,true);
 face('tiffany',landed+2.6,true);
 for(let i=0;i<gang.length;i++){
  const id=gang[i],[x,y]=positions[id];
  move(id,0,x+1200,y);move(id,T(6)+i*.15,x+1200,y);
  travel(id,T(6)+i*.15,[x+1200,y],[x,y],4.7,.85);
 }
 // Steal, reach, pull away: an actual interaction with the whistle.
 play('keno',7,'reach');play('tiffany',7,'warning',.4);
 play('keno',7,'boast',1);play('tiffany',7,'anger',2.1);
 const choices={8:'point',9:'boast',10:'warning',11:'point',12:'boast',13:'storytelling',14:'boast',18:'point',19:'anger',20:'shrug',21:'shrug',22:'storytelling',23:'point',24:'shrug',26:'warning',27:'boast',28:'point',29:'shrug',30:'point',33:'warning',34:'boast',46:'shrug',47:'warning',48:'shrug',50:'warning'};
 for(const [b0,anim]of Object.entries(choices)){
  const b=+b0,id=beats[b].speaker;
  play(id,b,anim);
  if(beats[b].duration>4.8)play(id,b,'speak',4.5,.8);
  if(beats[b].duration>9.5)play(id,b,'point',9.3);
  if(beats[b].duration>13)play(id,b,'shrug',12.5);
  clip(id,T(b+1)-.12,b>36?'anger':'listen',1);
 }
 // Reactions are deliberately not synchronized into a chorus of idles.
 play('tiffany',9,'bored',.6);play('mick',9,'anger',1.4);
 play('steve',10,'laugh',1.2);play('keno',10,'shrug',2);
 play('pete',12,'boast',.4);play('keno',12,'bored',1.8);play('vanessa',12,'bored',3);
 play('tiffany',13,'bored',1);play('alex',13,'shrug',2.2);play('jason',14,'bored',.7);
 for(let i=0;i<gang.length;i++){
  if(gang[i]==='vanessa')continue;
  play(gang[i],15,i%2?'bored':'shrug',i*.15);
  clip(gang[i],T(16)+i*.13,'laugh',0,.8+i*.06);
  play(gang[i],18,'listen',.15+i*.1);
 }
 play('mick',16,'anger',.25);play('pete',17,'warning',1.1);play('tiffany',17,'bored',.6);
 // Vanessa disengages from the group and actually rests against the tower.
 travel('keno',T(15),positions.keno,[2100,835],1.7);
 face('keno',T(15)+1.7,false);
 travel('steve',T(15)+.2,positions.steve,[2390,810],1.8);
 face('steve',T(15)+2,false);
 travel('vanessa',T(15),positions.vanessa,[2013,850],2.2);
 face('vanessa',T(15)+2.2,false);
 for(const b of [15,16,17,18,19,20,21,22,23,24,25,26,27,28,29,30,31])
  play('vanessa',b,'rail_lean',b===15?2.2:0);
 play('tango',18,'alert',1.2);clip('tango',T(19),'wag');
 // Keno closes the gap. Mick stands his ground, the rest start to lose interest.
 travel('keno',T(18),[2100,835],[1685,840],2.8);play('keno',18,'point',2.8);
 play('tiffany',19,'warning',1);play('keno',19,'laugh',2.5);
 face('jason',T(20),true);play('jason',20,'point',1.4);face('jason',T(21),false);
 play('jimmy',21,'laugh',1.1);play('alex',22,'bored',2);play('pete',24,'shrug',.9);
 // Tiffany takes her whistle back herself. Mick's step-in arrives too late.
 travel('tiffany',T(25),[1450,810],[1560,810],.65,.8);play('tiffany',25,'reach',.65,1.4);play('keno',25,'alarm',1);
 travel('tiffany',T(25)+2.1,[1560,810],[1450,810],.7,.8);face('tiffany',T(25)+2.1,false);face('tiffany',T(26),true);play('tiffany',26,'warning');
 travel('mick',T(27),[1160,840],[1260,842],.8,.75);play('mick',27,'boast',.8);
 face('tiffany',T(28),false);play('tiffany',28,'bored',2.6);play('mick',28,'shrug',1.2);face('tiffany',T(30),true);
 clip('tango',T(30),'wag');play('jimmy',31,'laugh');play('jimmy',31,'alarm',1.4);play('jimmy',31,'bored',2.3);
 // A loaded weapon changes everybody's body language before the throw.
 play('keno',32,'boast');play('alex',32,'alarm',.8);play('tiffany',32,'alarm',1.1);play('mick',32,'anger',1.6);clip('tango',T(32)+1.2,'alert');
 // Keno deliberately creates throwing distance; the gang clears his lane.
 travel('keno',T(32)+.4,[1685,840],[2340,830],2.2);
 face('keno',T(32)+2.6,false);play('keno',32,'boast',2.6);
 travel('alex',T(32)+.2,positions.alex,[2730,760],1.6);face('alex',T(32)+1.8,false);
 travel('steve',T(32)+.3,[2390,810],[2830,820],2.1);face('steve',T(32)+2.4,false);
 travel('jason',T(32)+.4,positions.jason,[3030,855],2.1);face('jason',T(32)+2.5,false);
 travel('jimmy',T(32)+.5,positions.jimmy,[3210,810],2.1);face('jimmy',T(32)+2.6,false);
 play('vanessa',32,'rail_push',.2);travel('vanessa',T(32)+1.2,[2013,850],[2540,710],2.3);
 face('vanessa',T(32)+3.5,false);
 travel('tiffany',T(32)+1.2,[1450,830],[1110,760],1.7);face('tiffany',T(32)+2.9,true);
 clip('tiffany',T(32)+2.9,'alarm',1);
 travel('tango',T(32)+1.7,[1260,880],[1405,880],.8);
 clip('tango',T(32)+2.5,'alert',1,.7);
 play('alex',33,'warning');play('vanessa',33,'alarm',.3);play('steve',33,'bored',1.2);
 // Read the danger -> look back at Mick -> commit -> intercept. No dialogue
 // explains the choice: an eyeline insert precedes one continuous wide action.
 clip('tango',T(34)+.6,'alert',1,.7);
 clip('tango',T(35),'look_back',1,1);
 clip('tango',T(35)+1.0,'alert',1,1);
 play('keno',35,'throw',1.2,.55);
 travel('tango',T(35)+1.6,[1405,880],[1460,866],.35);
 clip('tango',T(35)+1.95,'jump',1,.13);
 for(let i=0;i<=60;i++){
  const p=i/60;
  // An accelerating takeoff, high chest at contact and a committed silhouette.
  move('tango',T(35)+1.95+p*2.05,1460+145*p,866-143*p-30*Math.sin(p*Math.PI));
 }
 // The injury is an occluded impact, not a comic fall or death sprite.
 move('tango',T(36),1605,2400);
 for(let i=0;i<gang.length;i++)play(gang[i],36,'alarm',.08+i*.04);
 move('keno',T(36)+.3,2340,830);move('keno',T(36)+.9,2460,820);clip('keno',T(36)+.3,'run',1,.7);play('keno',37,'bored');
 play('mick',36,'alarm',.08);play('pete',36,'alarm',.2);play('tiffany',36,'alarm',.1);
 travel('mick',T(37),[1260,842],[1390,870],.8,.9);play('mick',37,'kneel',.8);
 travel('tiffany',T(37)+.2,[1110,760],[1580,865],2.2);face('tiffany',T(37)+2.4,false);play('tiffany',37,'console',2.4);
 play('mick',38,'console');play('tiffany',38,'console',.3);play('mick',39,'grief',.8);
 travel('pete',T(38),[800,830],[1730,875],3.3,1);face('pete',T(38)+3.3,false);play('pete',38,'console',3.3);
 play('mick',40,'console');play('tiffany',41,'warning');
 face('pete',T(41)+.8,true);travel('pete',T(41)+.8,[1730,875],[2520,875],2.8,1);
 play('mick',42,'grief');play('tiffany',43,'console');
 face('pete',T(43),false);travel('pete',T(43),[2520,875],[1730,875],2.4,1);
 play('pete',44,'console');play('tiffany',44,'console');
 for(const [id,x]of [['pete',1730],['tiffany',1580]]){
  const finish=T(45)-.8,span=finish-T(44)-1.8;
  travel(id,T(44)+1.8,[x,875],[x+290,875],span);
  clip(id,finish,'reach',1,.7);
  // Load behind the tailgate, then cut to the departing truck.
  move(id,T(45),x+290,875);move(id,T(45)+.01,x+290,2400);
 }
 play('mick',44,'grief');play('mick',45,'grief');play('keno',45,'bored');
 play('vanessa',46,'anger',.7);play('steve',47,'alarm',.3);
 play('mick',49,'grief');play('mick',49,'resolve',1.6);
 travel('vanessa',T(50),[2540,710],[1580,805],2.1,1);face('vanessa',T(50)+2.1,true);play('vanessa',50,'warning',2.1);
 for(let i=0;i<gang.length;i++){
  const id=gang[i];if(id==='vanessa')continue;
  const from=({keno:[2460,820],alex:[2730,760],steve:[2830,820],jason:[3030,855],jimmy:[3210,810]})[id];
  face(id,T(51)+i*.15,true);travel(id,T(51)+i*.15,from,[from[0]+1200,from[1]-25],Math.max(2.5,T(52)-T(51)-i*.15),1);
 }
 play('mick',51,'resolve');play('vanessa',51,'anger',.2);
}
