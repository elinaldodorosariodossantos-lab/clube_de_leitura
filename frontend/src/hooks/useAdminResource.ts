import {useCallback,useEffect,useRef,useState} from 'react';
import {portalApi} from '../services/portal';
export function useAdminResource<T>(path:string,paused=false){
 const [data,setData]=useState<T>(),[loading,setLoading]=useState(true),[error,setError]=useState('');
 const sequence=useRef(0),pause=useRef(paused);pause.current=paused;
 const reload=useCallback(async(force=true)=>{if(!force&&pause.current)return;const request=++sequence.current;setLoading(true);setError('');try{const result=await portalApi<T>(path);if(sequence.current===request&&(force||!pause.current))setData(result);}catch(e){if(sequence.current===request&&(force||!pause.current)){setData(undefined);setError((e as Error).message);}}finally{if(sequence.current===request)setLoading(false);}},[path]);
 useEffect(()=>{setData(undefined);void reload(false);const visible=()=>{if(document.visibilityState==='visible')void reload(false);};const interval=window.setInterval(visible,20000);window.addEventListener('focus',visible);window.addEventListener('online',visible);document.addEventListener('visibilitychange',visible);return()=>{sequence.current++;window.clearInterval(interval);window.removeEventListener('focus',visible);window.removeEventListener('online',visible);document.removeEventListener('visibilitychange',visible);};},[reload]);
 return {data,loading,error,reload};
}
