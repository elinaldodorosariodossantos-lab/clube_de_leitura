import {useEffect,useRef,useState} from 'react';
import {mayLeaveForm} from './services/management';
import {StudentAccess} from './pages/StudentAccess';
import {StudentLogin} from './pages/StudentLogin';
import {StudentHome} from './pages/StudentHome';
import {Admin} from './pages/Admin';
import {Notice} from './components/PortalUI';
import {portalApi,advancePortalSession} from './services/portal';
import type {PortalSession,Student,StudentTab} from './types/portal';
import './portal.css';
import './reading.css';
import './admin.css';
import './student-theme.css';
function route(){return window.location.hash.replace(/^#\//,'')||(['/adm','/administrador'].includes(window.location.pathname.replace(/\/$/,''))?'admin':'');}
const studentPages:Record<string,StudentTab>={leitura:'home',jornada:'journey',progresso:'progress',perfil:'profile'};
const tabPaths:Record<StudentTab,string>={home:'leitura',journey:'jornada',progress:'progresso',profile:'perfil'};
export function PortalApp(){
 const [page,setPage]=useState(route),[session,setSession]=useState<PortalSession>({student:null,admin:false}),[loading,setLoading]=useState(true),[code,setCode]=useState<string>(),[error,setError]=useState('');
 const pageRef=useRef(page),sessionRequest=useRef(0);
 const [sessionError,setSessionError]=useState('');
 async function refresh(){const request=++sessionRequest.current;setLoading(true);setSessionError('');try{const s=await portalApi<PortalSession>('/session');if(request===sessionRequest.current)setSession(s);}catch(e){if(request===sessionRequest.current)setSessionError((e as Error).message);throw e;}finally{if(request===sessionRequest.current)setLoading(false);}}
 useEffect(()=>{const changed=()=>{if(!mayLeaveForm()){window.history.replaceState(null,'','#/'+pageRef.current);return;}const wasAdmin=pageRef.current==='admin'||pageRef.current.startsWith('admin/');pageRef.current=route();setPage(pageRef.current);const isAdmin=pageRef.current==='admin'||pageRef.current.startsWith('admin/');if(wasAdmin!==isAdmin)void refresh().catch(()=>{});setError('');window.scrollTo({top:0});};window.addEventListener('hashchange',changed);refresh().catch(()=>{}).finally(()=>setLoading(false));return()=>window.removeEventListener('hashchange',changed);},[]);
 useEffect(()=>{let checking=false;let active=true;const expired=async(event:Event)=>{const context=(event as CustomEvent<{context:string}>).detail?.context;const inAdmin=pageRef.current==='admin'||pageRef.current.startsWith('admin/');if((context==='admin')!==inAdmin||checking)return;checking=true;const request=sessionRequest.current;
  try{const current=await portalApi<PortalSession>('/session');if(!active||request!==sessionRequest.current)return;
   if(current.student||current.admin){setSession(current);return;}
   sessionRequest.current++;advancePortalSession();setLoading(false);setSessionError('');setSession(current);setCode(undefined);setError('Sua sessão expirou. Entre novamente para continuar. Suas respostas, pontos e conquistas estão salvos.');
  }catch{/* Uma falha de conexão não comprova que a sessão terminou. */}finally{checking=false;}};window.addEventListener('clube:session-expired',expired);return()=>{active=false;window.removeEventListener('clube:session-expired',expired);};},[]);
 useEffect(()=>{if(session.student&&['','aluno','retornar','inicio'].includes(page))window.location.replace('#/leitura');},[session.student,page]);
 function identified(student:Student,newCode?:string){advancePortalSession();setError('');sessionRequest.current++;setLoading(false);setSession({student,admin:false});setCode(newCode);window.location.replace('#/leitura');}
 async function logout(){try{await portalApi('/logout',{});setSession({student:null,admin:false});setCode(undefined);window.location.hash='/';}catch(e){setError((e as Error).message);}}
 const accessToken=page.startsWith('acesso/')?page.slice(7):undefined;
 const attemptId=page.startsWith('atividade/')?page.slice('atividade/'.length):undefined;
 const selectedLevel=(['facil','medio','dificil'].includes(page.split('/')[1])&&page.split('/')[0]==='historias'?page.split('/')[1]:undefined) as import('./types/portal').ReadingLevel|undefined;
 const adminRoute=page==='admin'||page.startsWith('admin/');
 const studentRoute=!adminRoute;
 return <div className="club-app">{error&&<div className="global-notice"><Notice error>{error}</Notice></div>}{loading&&(studentRoute||adminRoute||page==='')?<main className="loading-page"><Notice>Preparando seu clube…</Notice></main>:sessionError?<main className='loading-page'><Notice error>{sessionError}</Notice><button className='club-button' onClick={()=>void refresh().catch(()=>{})}>Tentar novamente</button></main>:adminRoute?<Admin route={page} authorized={session.admin} onLogin={async()=>{await refresh();window.location.replace('#/admin/visao-geral');}} onLogout={logout}/>:accessToken?<StudentAccess token={accessToken} active={!!session.student} onIdentified={identified} onLogout={logout}/>:studentRoute&&session.student?<StudentHome key={session.student.id} level={selectedLevel} attemptId={attemptId} onOpenAttempt={id=>{window.location.hash='/atividade/'+id;}} student={session.student} code={code} admin={session.admin} tab={studentPages[page]??'home'} onNavigate={tab=>{window.location.hash='/'+tabPaths[tab];}} onLogout={logout}/>:<StudentLogin onIdentified={identified}/>}</div>;
}
