import {eventBoundaryDelay} from '../services/event-schedule';
import {useCallback,useEffect,useRef,useState} from 'react';
import {portalApi} from '../services/portal';
import {AnswerSaveQueue} from '../services/answer-save-queue';
import type {ReadingAttempt,ReadingEntry,ReadingLevel,ReadingState} from '../types/portal';
export function useReading(studentId:string,attemptId?:string){
 const [state,setState]=useState<ReadingState>(),[attempt,setAttempt]=useState<ReadingAttempt>(),[loading,setLoading]=useState(true),[busy,setBusy]=useState(false),[error,setError]=useState('');
 const [savingAnswers,setSavingAnswers]=useState(false),[answerError,setAnswerError]=useState('');
 const running=useRef(false),identity=useRef(studentId),active=useRef(true),stateRequest=useRef(0),attemptRequest=useRef(0),currentAttempt=useRef(attemptId);
 const handoff=useRef<ReadingAttempt|undefined>(undefined),answerQueues=useRef(new Map<string,AnswerSaveQueue<ReadingAttempt>>());
 identity.current=studentId;currentAttempt.current=attemptId;
 const refresh=useCallback(async()=>{const request=++stateRequest.current;const data=await portalApi<ReadingState>('/reading/state');if(active.current&&identity.current===studentId&&request===stateRequest.current)setState(data);return data;},[studentId]);
 const flushAnswers=async()=>{for(const queue of answerQueues.current.values())await queue.flush();};
 function withDrafts(a:ReadingAttempt){const queue=answerQueues.current.get(a.id);return queue?{...a,answers:{...a.answers,...queue.drafts()}}:a;}
 function adoptAttempt(a:ReadingAttempt){
  // A one-use handoff from an authorized RPC avoids fetching the same snapshot again.
  handoff.current=withDrafts(a);attemptRequest.current++;
  setState(s=>s?{...s,active:a}:s);
 }
 useEffect(()=>{active.current=true;setLoading(true);setState(undefined);setError('');const id=studentId;void refresh().catch(e=>{if(active.current&&identity.current===id)setError(e.message);}).finally(()=>{if(active.current&&identity.current===id)setLoading(false);});return()=>{active.current=false;stateRequest.current++;attemptRequest.current++;for(const queue of answerQueues.current.values())queue.dispose();answerQueues.current.clear();handoff.current=undefined;};},[studentId,refresh]);
 useEffect(()=>{const warn=(event:BeforeUnloadEvent)=>{if(![...answerQueues.current.values()].some(queue=>queue.pending))return;event.preventDefault();event.returnValue='';};window.addEventListener('beforeunload',warn);return()=>window.removeEventListener('beforeunload',warn);},[]);
 useEffect(()=>{const sync=()=>{if(document.visibilityState==='hidden'||running.current||[...answerQueues.current.values()].some(queue=>queue.pending))return;void refresh().catch(e=>{if(active.current&&identity.current===studentId)setError(e.message);});};window.addEventListener('focus',sync);const timer=window.setInterval(sync,30000);return()=>{window.removeEventListener('focus',sync);window.clearInterval(timer);};},[studentId,refresh]);
 useEffect(()=>{
  const request=++attemptRequest.current;
  if(!attemptId){setAttempt(undefined);return;}
  setError('');
  if(handoff.current?.id===attemptId){setAttempt(handoff.current);handoff.current=undefined;return;}
  setAttempt(undefined);
  void portalApi<ReadingAttempt>('/reading/attempts/'+attemptId).then(a=>{if(active.current&&identity.current===studentId&&request===attemptRequest.current)setAttempt(withDrafts(a));}).catch(e=>{if(active.current&&identity.current===studentId&&request===attemptRequest.current)setError(e.message);});
 },[attemptId,studentId]);
 useEffect(()=>{const schedule=state?.eventSchedule,delay=eventBoundaryDelay(schedule);if(delay===null)return;const timer=setTimeout(()=>{if(schedule?.status==='active')setState(s=>s?.eventSchedule===schedule?{...s,eventSchedule:{...schedule,status:'ended'},active:null,levels:s.levels.map(l=>({...l,available:0,unlocked:false,stories:[]}))}:s);void refresh().catch(e=>{if(active.current)setError(e.message);});},delay);return()=>clearTimeout(timer);},[state?.eventSchedule,refresh]);
 async function act<T>(fn:()=>Promise<T>):Promise<T|undefined>{if(running.current)return;running.current=true;stateRequest.current++;attemptRequest.current++;setBusy(true);setError('');try{await flushAnswers();if(!active.current||identity.current!==studentId)return;const value=await fn();return active.current&&identity.current===studentId?value:undefined;}catch(e){if(active.current)setError((e as Error).message);}finally{running.current=false;if(active.current)setBusy(false);}}
 async function update(operation:string,body:unknown={}){if(!attempt)return;return act(async()=>{const a=await portalApi<ReadingAttempt>(`/reading/attempts/${attempt.id}/${operation}`,body);if(active.current&&currentAttempt.current===a.id)setAttempt(a);if(operation==='finish'){void refresh().catch(e=>{if(active.current)setError(e.message);});}else setState(s=>s?{...s,active:a}:s);return a;});}
 function answer(questionId:number,selected:number){
  if(!attempt||running.current||attempt.status==='completed')return;
  const id=attempt.id;
  stateRequest.current++;attemptRequest.current++;
  if(!answerQueues.current.has(id)){
   const queue=new AnswerSaveQueue<ReadingAttempt>(
    (questionId,selected)=>portalApi<ReadingAttempt>('/reading/attempts/'+id+'/answers',{questionId,selected}),
    (saved,drafts)=>{
     if(!active.current||identity.current!==studentId)return;
     const merged={...saved,answers:{...saved.answers,...drafts}};
     if(currentAttempt.current===id)setAttempt(merged);
     setState(s=>s?.active?.id===id?{...s,active:merged}:s);
    },
    ()=>{if(active.current&&identity.current===studentId){const queues=[...answerQueues.current.values()];setSavingAnswers(queues.some(q=>q.pending));setAnswerError(queues.find(q=>q.error)?.error?.message??'');}}
   );
   answerQueues.current.set(id,queue);
  }
  setAttempt(current=>current?.id===id?{...current,answers:{...current.answers,[questionId]:selected}}:current);
  answerQueues.current.get(id)!.enqueue(questionId,selected);
 }
 return {state,attempt,loading,busy,error,savingAnswers,answerError,adoptAttempt,flushAnswers,retryAnswers:async()=>{try{for(const queue of answerQueues.current.values())if(queue.pending)await queue.retry();}catch{/* The retained answer and retry action remain visible. */}},refreshState:()=>act(refresh),refresh:()=>act(async()=>{await refresh();if(attemptId){const a=await portalApi<ReadingAttempt>('/reading/attempts/'+attemptId);if(currentAttempt.current===a.id)setAttempt(withDrafts(a));}}),
  enter:(level:ReadingLevel)=>act(async()=>{const result=await portalApi<ReadingEntry>('/reading/enter',{level});if(result.attempt)adoptAttempt(result.attempt);else void refresh().catch(e=>{if(active.current)setError(e.message);});return result;}),
  start:(level:ReadingLevel,storyId?:string)=>act(async()=>{const a=await portalApi<ReadingAttempt>('/reading/start',{level,storyId});adoptAttempt(a);return a;}),
  page:(pageIndex:number)=>update('page',{pageIndex}),stage:(stage:'leitura'|'questoes')=>update('stage',{stage}),answer,finish:()=>update('finish')};
}
