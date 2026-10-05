Add-Type -AssemblyName System.Drawing
$runtimeDir=Split-Path ([System.Drawing.Bitmap]).Assembly.Location
Add-Type -ReferencedAssemblies @(([object]).Assembly.Location,([System.Drawing.Bitmap]).Assembly.Location,([System.Drawing.Color]).Assembly.Location,(Join-Path $runtimeDir 'System.Private.Windows.GdiPlus.dll'),(Join-Path $runtimeDir 'System.Private.Windows.Core.dll'),(Join-Path C:\Users\rysho\.cache\codex-runtimes\codex-primary-runtime\dependencies\native\powershell 'System.Collections.dll')) -TypeDefinition @'
using System;
using System.Drawing;
public class SpriteComponent { public int[] bounds; public int[] anchor; public int[][] runs; }
public class ComponentFrames {
 public static object[] Read(string path,int expected) {
  using(var b=new Bitmap(path)) {
   int w=b.Width,h=b.Height;bool[] visible=new bool[w*h];int[] labels=new int[w*h],queue=new int[w*h];
   for(int y=0;y<h;y++)for(int x=0;x<w;x++)visible[y*w+x]=b.GetPixel(x,y).A>16;
   int[][] components=new int[1000][];int count=0,id=0;
   for(int p=0;p<visible.Length;p++){if(!visible[p]||labels[p]!=0)continue;id++;int head=0,tail=0,minx=w,miny=h,maxx=0,maxy=0;queue[tail++]=p;labels[p]=id;
    while(head<tail){int q=queue[head++],x=q%w,y=q/w;minx=Math.Min(minx,x);maxx=Math.Max(maxx,x);miny=Math.Min(miny,y);maxy=Math.Max(maxy,y);for(int dy=-1;dy<=1;dy++)for(int dx=-1;dx<=1;dx++){int xx=x+dx,yy=y+dy;if(xx<0||xx>=w||yy<0||yy>=h)continue;int k=yy*w+xx;if(visible[k]&&labels[k]==0){labels[k]=id;queue[tail++]=k;}}}
    if(tail>1000)components[count++]=new int[]{id,tail,minx,miny,maxx,maxy};
   }
   if(count<expected)throw new Exception("Fewer than expected isolated sprites");for(int i=0;i<count;i++)for(int j=i+1;j<count;j++)if(components[j][1]>components[i][1]){int[] temp=components[i];components[i]=components[j];components[j]=temp;}for(int i=0;i<expected;i++)for(int j=i+1;j<expected;j++)if((components[j][3]+components[j][5])/2<(components[i][3]+components[i][5])/2){int[] temp=components[i];components[i]=components[j];components[j]=temp;}for(int row=0;row<expected/3;row++)for(int i=row*3;i<row*3+3;i++)for(int j=i+1;j<row*3+3;j++)if(components[j][2]<components[i][2]){int[] temp=components[i];components[i]=components[j];components[j]=temp;}object[] output=new object[expected];
   for(int i=0;i<expected;i++){int[] part=components[i];int[][] runs=new int[w*h][];int runCount=0,footMin=w,footMax=0;for(int y=part[3];y<=part[5];y++){int start=-1;for(int x=part[2];x<=part[4]+1;x++){bool on=x<=part[4]&&labels[y*w+x]==part[0];if(on&&start<0)start=x;if(!on&&start>=0){runs[runCount++]=new int[]{y,start,x-start};if(y>=part[5]-80){footMin=Math.Min(footMin,start);footMax=Math.Max(footMax,x-1);}start=-1;}}}int[][] trimmed=new int[runCount][];Array.Copy(runs,trimmed,runCount);output[i]=new SpriteComponent{bounds=new int[]{part[2],part[3],part[4],part[5]},anchor=new int[]{(footMin+footMax)/2,part[5]},runs=trimmed};}
   return output;
  }
 }
}
'@

foreach($characterId in @('pete','tiffany')) {
 foreach($sequenceName in @('run','actions')) {
  $sourcePath = Join-Path $PSScriptRoot ($characterId+'_sources/'+$sequenceName+'-v1.png')
  $expectedCount = if($sequenceName -eq 'run'){6}else{9}
  [ComponentFrames]::Read($sourcePath,$expectedCount) | ConvertTo-Json -Depth 6 -Compress | Set-Content (Join-Path $PSScriptRoot ($characterId+'_sources/'+$sequenceName+'-components.json'))
 }
}
