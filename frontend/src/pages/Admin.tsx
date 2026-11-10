import {SchoolDirectory} from './SchoolDirectory';
import {useEffect,useState} from 'react';
import {ShieldCheck,LogOut,Users,School,LayoutDashboard,FileChartColumn,BookOpen,CalendarDays} from 'lucide-react';
import {Brand,Notice} from '../components/PortalUI';
import {portalApi} from '../services/portal';
import {adminPaths,parseAdminRoute} from '../services/adminRoutes';
import {SchoolsPanel} from './SchoolsPanel';
import {AdminOverview} from './AdminOverview';
import {ManageStudents} from './ManageStudents';
import {ReadingEvents} from './ReadingEvents';
import '../events.css';
import {ManageStories} from './ManageStories';
import {mayLeaveForm} from '../services/management';
import {CertificateSettings} from '../components/CertificateSettings';
import type {AdminTab} from '../types/admin';
type Props={route:string;authorized:boolean;onLogin:()=>Promise<void>;onLogout:()=>Promise<void>};
export function Admin({route,authorized,onLogin,onLogout}:Props){
 useEffect(()=>{if(authorized&&(route==='admin'||route==='admin/entrar'))window.location.replace('#/admin/visao-geral');},[authorized,route]);
 if(!authorized)return <AdminLogin onLogin={onLogin}/>;
 return <div className="admin-shell"><header className="club-header"><Brand/><div className="student-header"><span className="admin-label"><ShieldCheck size={18}/>Área administrativa</span><button onClick={()=>{if(mayLeaveForm())void onLogout();}}><LogOut size={17}/>Sair</button></div></header><AdminWorkspace route={route} onLogout={onLogout}/></div>;
}
function AdminLogin({onLogin}:{onLogin:()=>Promise<void>}){
 const [email,setEmail]=useState(''),[password,setPassword]=useState(''),[busy,setBusy]=useState(false),[error,setError]=useState('');
 async function login(e:React.FormEvent){e.preventDefault();setBusy(true);setError('');try{await portalApi('/admin/login',{email,password});setPassword('');await onLogin();}catch(e){setError((e as Error).message);}finally{setBusy(false);}}
 return <main className="admin-access-page"><section className="admin-access-card" aria-labelledby="admin-access-title"><div className="admin-access-brand"><span className="admin-access-book"><BookOpen size={48} strokeWidth={1.8}/></span><div>Clube da <strong>Leitura</strong><small>2026</small></div></div><h1 id="admin-access-title">Login</h1>{error&&<Notice error>{error}</Notice>}<form onSubmit={login} aria-busy={busy}><label className="sr-only" htmlFor="admin-email">E-mail</label><input id="admin-email" type="email" placeholder="E-mail" autoComplete="username" required disabled={busy} value={email} onChange={e=>setEmail(e.target.value)}/><label className="sr-only" htmlFor="admin-password">Senha</label><input id="admin-password" type="password" placeholder="Senha" autoComplete="current-password" required disabled={busy} value={password} onChange={e=>setPassword(e.target.value)}/><button className="club-button" type="submit" disabled={busy}>{busy?'Verificando acesso…':'Entrar'}</button></form></section></main>;
}
function AdminWorkspace({route,onLogout}:{route:string;onLogout:()=>Promise<void>}){
 const {tab,studentId,schoolId,classId,schoolSection,notFound}=parseAdminRoute(route);
 const navigation:{id:AdminTab;label:string;Icon:typeof Users}[]=[{id:'overview',label:'Visão geral',Icon:LayoutDashboard},{id:'students',label:'Alunos',Icon:Users},{id:'events',label:'Eventos de Leitura',Icon:CalendarDays},{id:'stories',label:'Histórias',Icon:BookOpen},{id:'schools',label:'Escolas',Icon:School},{id:'reports',label:'Relatórios',Icon:FileChartColumn}];
 return <div className="portal-layout admin-workspace"><nav className="portal-nav admin-nav" aria-label="Menu administrativo">{navigation.map(({id,label,Icon})=><a href={'#/'+adminPaths[id]} key={id} aria-current={tab===id?'page':undefined} className={tab===id?'selected':''}><Icon size={19}/>{label}</a>)}<button className="admin-sidebar-logout" onClick={()=>{if(mayLeaveForm())void onLogout();}}><LogOut size={18}/>Sair</button></nav><main className="portal-content admin-content">{notFound?<Notice>Esta página administrativa não foi encontrada. <a href="#/admin/visao-geral">Ir para a visão geral</a></Notice>:tab==='overview'?<AdminOverview/>:tab==='students'?<ManageStudents selectedId={studentId}/>:tab==='events'?<ReadingEvents/>:tab==='schools'?(studentId||schoolSection==='dashboard'?<SchoolsPanel key={schoolSection==='dashboard'?schoolId:'schools-dashboard'} selectedId={studentId} initialSchoolId={schoolSection==='dashboard'?schoolId:undefined}/>:<SchoolDirectory key={route} schoolId={schoolId} classId={classId} classes={schoolSection==='classes'}/>):tab==='stories'?<ManageStories/>:tab==='reports'?<SchoolsPanel report/>:<><h1>Configurações</h1><CertificateSettings/></>}</main></div>;
}
