export type ReadingBlock={top:number;bottom:number};
export type ReadingPart={top:number;height:number};

// Prefer line/image boundaries to avoid slicing a word or an illustration.
export function readingParts(blocks:ReadingBlock[],viewportHeight:number):ReadingPart[]{
 const height=Math.max(1,Math.floor(viewportHeight)),valid=blocks.filter(b=>Number.isFinite(b.top)&&Number.isFinite(b.bottom)&&b.bottom>b.top);
 const end=Math.ceil(Math.max(height,...valid.map(b=>b.bottom))),parts:ReadingPart[]=[];
 let top=0;
 while(top<end-1){
  let bottom=Math.min(end,top+height);
  if(bottom<end){
   for(let i=0;i<valid.length+1;i++){
    const crossing=valid.filter(b=>b.top<bottom-.5&&b.bottom>bottom+.5);
    if(!crossing.length)break;
    const earlier=Math.floor(Math.min(...crossing.map(b=>b.top)));
    if(earlier<=top+1)break;
    bottom=earlier;
   }
  }
  if(bottom<=top+1)bottom=Math.min(end,top+height);
  parts.push({top,height:bottom-top});top=bottom;
 }
 return parts.length?parts:[{top:0,height}];
}
