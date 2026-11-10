import {useEffect,useState} from 'react';
import {createClient} from '@supabase/supabase-js';
import {Experience} from './Experience';
import './experience.css';
type Question={id:number;prompt:string;options:string[]};
type Activity={title:string;content:string;age:string;level:string;questions:Question[]};
type Attempt={id:string;answers:Record<string,number>;status:string;completedAt?:string;result?:{hits:number;points:number;percentage:number;details:(Question&{selected:number;correct:number;points:number})[]}};
const env=import.meta.env as Record<string,string>;
const supabase=env.VITE_SUPABASE_URL&&env.VITE_SUPABASE_ANON_KEY?createClient(env.VITE_SUPABASE_URL,env.VITE_SUPABASE_ANON_KEY):null;
const legacy=window.location.pathname==='/leitura-legada';
let demo=legacy?localStorage.getItem('demo-user'):null;if(legacy&&!demo){demo=crypto.randomUUID();localStorage.setItem('demo-user',demo);}
export default function LegacyApp(){
 const [mode,setMode]=useState(''),[token,setToken]=useState(''),[activity,setActivity]=useState<Activity>(),[attempt,setAttempt]=useState<Attempt>(),[page,setPage]=useState('home'),[index,setIndex]=useState(0),[busy,setBusy]=useState(false),[error,setError]=useState(''),[details,setDetails]=useState(false),[history,setHistory]=useState<Attempt[]>([]),[email,setEmail]=useState(''),[password,setPassword]=useState('');
 async function api(path:string,method='GET',body?:unknown){const r=await fetch('/api'+path,{method,headers:{Authorization:`Bearer ${token}`,'Content-Type':'application/json'},body:body?JSON.stringify(body):undefined});const data=await r.json();if(!r.ok)throw new Error(data.error??'Não foi possível concluir.');return data;}
 async function action(fn:()=>Promise<void>){setBusy(true);setError('');try{await fn();}catch(e){setError((e as Error).message);}finally{setBusy(false);}}
 useEffect(()=>{fetch('/api/config').then(r=>r.json()).then(async c=>{setMode(c.mode);if(c.mode==='demo')setToken(demo!);else if(supabase){const {data}=await supabase.auth.getSession();setToken(data.session?.access_token??'');}else setError('Configure as variáveis do Supabase no frontend.');}).catch(()=>setError('A API está indisponível. Inicie o backend.'));const subscription=supabase?.auth.onAuthStateChange((_event,session)=>setToken(session?.access_token??''));return()=>subscription?.data.subscription.unsubscribe();},[]);
 useEffect(()=>{if(!token)return;void action(async()=>{setActivity(await api('/activity'));setHistory(await api('/history'));const id=localStorage.getItem('attempt-'+token.slice(-12));if(id){const a=await api('/attempts/'+id);setAttempt(a);setPage(a.status==='completed'?'result':'quiz');setIndex(Math.min(Object.keys(a.answers).length,4));}});},[token]);
 async function start(){await action(async()=>{const a=await api('/attempts','POST');setAttempt(a);localStorage.setItem('attempt-'+token.slice(-12),a.id);setIndex(0);setDetails(false);setPage('reading');});}
 const result=attempt?.result;
 const performance=result?result.hits===5?['Excelente!','Você demonstrou que compreendeu muito bem o texto.']:result.hits>=3?['Muito bem!','Você está avançando! Releia os detalhes e continue descobrindo.']:['Cada leitura é uma descoberta!','Vamos ler novamente? Você pode aprender mais a cada tentativa.']:[];
 return <Experience mode={mode} token={token} activity={activity} attempt={attempt} page={page} index={index} busy={busy} error={error} details={details} history={history} email={email} password={password} performance={performance} setPage={setPage} setIndex={setIndex} setDetails={setDetails} setEmail={setEmail} setPassword={setPassword} start={start}
 select={(questionId,selected)=>action(async()=>{if(attempt)setAttempt(await api('/attempts/'+attempt.id+'/answers','PUT',{questionId,selected}));})}
 finish={()=>action(async()=>{if(attempt){setAttempt(await api('/attempts/'+attempt.id+'/finish','POST'));setPage('result');}})}
 loadHistory={()=>action(async()=>{setHistory(await api('/history'));setPage('history');})}
 openAttempt={a=>{setAttempt(a);setDetails(false);setPage('result');}}
 login={()=>action(async()=>{if(!supabase)throw new Error('Supabase não configurado.');const {error}=await supabase.auth.signInWithPassword({email,password});if(error)throw error;})}
 logout={()=>{if(mode==='supabase'){void supabase?.auth.signOut();setAttempt(undefined);}setPage('home');}}/>;
}
