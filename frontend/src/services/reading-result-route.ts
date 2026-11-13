export type ReadingResultRoute={kind:'level'|'journey';id:string;nextJourneyId?:string};
const uuid=/^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;
export function readingResultPath(result:ReadingResultRoute){
 const path=(result.kind==='level'?'conquista/':'conclusao/')+result.id;
 return result.kind==='level'&&result.nextJourneyId?path+'?conclusao='+encodeURIComponent(result.nextJourneyId):path;
}
export function parseReadingResultRoute(page:string):ReadingResultRoute|undefined{
 const [path,query='']=page.split('?'),[kind,id,extra]=path.split('/');
 if(extra!==undefined||!uuid.test(id??'')||(kind!=='conquista'&&kind!=='conclusao'))return;
 const next=new URLSearchParams(query).get('conclusao');
 return {kind:kind==='conquista'?'level':'journey',id,...(kind==='conquista'&&next&&uuid.test(next)?{nextJourneyId:next}:{})};
}
