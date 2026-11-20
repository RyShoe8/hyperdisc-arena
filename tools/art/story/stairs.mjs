// Painted tread centres, in set coordinates. Feet alternate one tread at a
// time; the support foot stays fixed until the next foot has taken the weight.
export const STAIR_SCALE=1.15;
export const STAIR_START=.8;
export const STAIR_STEP=.4;
const world=([x,y])=>[-350+x*3900/2172,-100+y*1300/724];
export const TREADS=[[855,361],[828,377],[800,393],[776,409],[753,428],[727,447],[702,466],[676,487]].map(world).concat([[830,805]]);
export const STAIR_DURATION=TREADS.length*STAIR_STEP;
const initial=[[1250,527],[1280,527]];
const lerp=(a,b,p)=>a.map((v,i)=>v+(b[i]-v)*p);
export function stairPose(time){
 const t=Math.max(0,Math.min(time,STAIR_DURATION));
 const step=Math.min(TREADS.length-1,Math.floor(t/STAIR_STEP));
 const phase=Math.min(1,(t-step*STAIR_STEP)/STAIR_STEP);
 const feet=initial.map(p=>[...p]);
 for(let i=0;i<step;i++)feet[i%2]=TREADS[i];
 const moving=step%2,from=[...feet[moving]],to=TREADS[step];
 // Weight transfer precedes lift-off; heel settles before the other leg lifts.
 const p=Math.max(0,Math.min(1,(phase-.12)/.78));
 const ease=p*p*(3-2*p);
 const rootFrom=[(feet[0][0]+feet[1][0])/2+4,(feet[0][1]+feet[1][1])/2+36];
 const rootTo=[(to[0]+feet[1-moving][0])/2+4,(to[1]+feet[1-moving][1])/2+36];
 const root=lerp(rootFrom,rootTo,phase*phase*(3-2*phase));
 feet[moving]=lerp(from,to,ease);
 feet[moving][1]-=Math.sin(p*Math.PI)*22;
 return {root,feet,support:1-moving,step,phase};
}
export function stairLocal(point,root){return [256+(root[0]-point[0])/STAIR_SCALE,450+(point[1]-root[1])/STAIR_SCALE];}
export function stairRailY(x){return 406+(1185-x)*255/366;}
