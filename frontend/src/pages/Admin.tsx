import {AdminAccess} from './AdminAccess';
import {SchoolDirectory} from './SchoolDirectory';
import {useEffect,useState} from 'react';
import {ShieldCheck,LogOut,Users,School,LayoutDashboard,FileChartColumn,BookOpen,CalendarDays,Menu,X,UserRound,Sun,Moon} from 'lucide-react';
import {Notice} from '../components/PortalUI';
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
import {useModalFocus} from '../hooks/useModalFocus';
import {AdminBookMark} from '../components/AdminArtwork';
import type {AdminTab} from '../types/admin';
type Props={route:string;authorized:boolean;onLogin:()=>Promise<void>;onLogout:()=>Promise<void>};
export function Admin({route,authorized,onLogin,onLogout}:Props){
 const [theme,setTheme]=useState<'light'|'dark'>(()=>{try{return localStorage.getItem('clube-admin-theme')==='dark'?'dark':'light';}catch{return 'light';}});
 function toggleTheme(){setTheme(current=>{const next=current==='light'?'dark':'light';try{localStorage.setItem('clube-admin-theme',next);}catch{/* The theme still works when storage is unavailable. */}return next;});}
 useEffect(()=>{if(authorized&&(route==='admin'||route==='admin/entrar'))window.location.replace('#/admin/visao-geral');},[authorized,route]);
 if(!authorized)return <AdminLogin onLogin={onLogin}/>;
 return <div className="admin-shell admin-modern" data-theme={theme}><AdminWorkspace route={route} onLogout={onLogout} theme={theme} onToggleTheme={toggleTheme}/></div>;
}
function AdminLogin({onLogin}:{onLogin:()=>Promise<void>}){
 const [email,setEmail]=useState(''),[password,setPassword]=useState(''),[busy,setBusy]=useState(false),[error,setError]=useState('');
 async function login(e:React.FormEvent){e.preventDefault();setBusy(true);setError('');try{await portalApi('/admin/login',{email,password});setPassword('');await onLogin();}catch(e){setError((e as Error).message);}finally{setBusy(false);}}
 return <main className="admin-access-page"><section className="admin-access-card" aria-labelledby="admin-access-title"><div className="admin-access-brand"><span className="admin-access-book"><BookOpen size={48} strokeWidth={1.8}/></span><div>Clube da <strong>Leitura</strong><small>2026</small></div></div><h1 id="admin-access-title">Login</h1>{error&&<Notice error>{error}</Notice>}<form onSubmit={login} aria-busy={busy}><label className="sr-only" htmlFor="admin-email">E-mail</label><input id="admin-email" type="email" placeholder="E-mail" autoComplete="username" required disabled={busy} value={email} onChange={e=>setEmail(e.target.value)}/><label className="sr-only" htmlFor="admin-password">Senha</label><input id="admin-password" type="password" placeholder="Senha" autoComplete="current-password" required disabled={busy} value={password} onChange={e=>setPassword(e.target.value)}/><button className="club-button" type="submit" disabled={busy}>{busy?'Verificando acesso…':'Entrar'}</button></form></section></main>;
}
function AdminWorkspace({route,onLogout,theme,onToggleTheme}:{route:string;onLogout:()=>Promise<void>;theme:'light'|'dark';onToggleTheme:()=>void}){
 const {tab,studentId,schoolId,classId,schoolSection,storyId,newStory,notFound}=parseAdminRoute(route);
 const [menuOpen,setMenuOpen]=useState(false);
 useModalFocus(()=>setMenuOpen(false),menuOpen);
 useEffect(()=>{setMenuOpen(false);document.querySelector('.admin-content')?.scrollTo({top:0,behavior:'instant'});},[route]);
 useEffect(()=>{const media=window.matchMedia('(min-width:981px)');const close=()=>{if(media.matches)setMenuOpen(false);};media.addEventListener('change',close);return()=>media.removeEventListener('change',close);},[]);
 const navigation:{id:AdminTab;label:string;Icon:typeof Users}[]=[{id:'overview',label:'Visão geral',Icon:LayoutDashboard},{id:'students',label:'Alunos',Icon:Users},{id:'events',label:'Eventos de Leitura',Icon:CalendarDays},{id:'stories',label:'Histórias',Icon:BookOpen},{id:'schools',label:'Escolas',Icon:School},{id:'reports',label:'Relatórios',Icon:FileChartColumn},{id:'access',label:'Acessos',Icon:ShieldCheck}];
 const logout=async()=>{if(await mayLeaveForm())await onLogout();};
 return <div className="portal-layout admin-workspace">
 <header className="admin-topbar"><button className="admin-menu-toggle" aria-label="Abrir menu administrativo" aria-controls="admin-sidebar" aria-expanded={menuOpen} onClick={()=>setMenuOpen(true)}><Menu size={23}/></button><div className="admin-greeting"><span className="admin-avatar"><UserRound size={26}/></span><div><strong>Olá, Administrador!</strong><span>Bem-vindo ao painel do Clube da Leitura</span></div></div><div className="admin-topbar-actions"><span><ShieldCheck size={21}/>Área Administrativa</span><button type="button" className="admin-theme-toggle" onClick={onToggleTheme} aria-label={theme==='light'?'Ativar tema escuro':'Ativar tema claro'} title={theme==='light'?'Ativar tema escuro':'Ativar tema claro'} aria-pressed={theme==='dark'}>{theme==='light'?<Moon size={21} aria-hidden="true"/>:<Sun size={21} aria-hidden="true"/>}</button><button onClick={logout}><LogOut size={19}/>Sair</button></div></header>
 {menuOpen&&<button className="admin-menu-backdrop" aria-label="Fechar menu administrativo" tabIndex={-1} onClick={()=>setMenuOpen(false)}/>}
 <aside id="admin-sidebar" className={'admin-sidebar'+(menuOpen?' is-open':'')} role={menuOpen?'dialog':undefined} aria-modal={menuOpen?true:undefined} aria-label="Navegação administrativa"><button className="admin-menu-close" aria-label="Fechar menu" onClick={()=>setMenuOpen(false)}><X size={22}/></button><a className="admin-sidebar-brand" href="#/admin/visao-geral" aria-label="Clube da Leitura — visão geral"><AdminBookMark/><span>Clube da<strong>Leitura</strong></span></a><nav className="portal-nav admin-nav" aria-label="Menu administrativo">{navigation.map(({id,label,Icon})=><a href={'#/'+adminPaths[id]} key={id} aria-current={tab===id?'page':undefined} className={tab===id?'selected':''}><Icon size={21}/>{label}</a>)}</nav><div className="admin-sidebar-art" aria-hidden="true"><span>★</span><img src="/images/leitora.png" alt=""/><small>Cada página, uma descoberta.</small></div><button className="admin-sidebar-logout" onClick={logout}><LogOut size={20}/>Sair</button></aside>
 <main className={'portal-content admin-content'+(tab==='reports'?' admin-reports-content':'')}>{notFound?<Notice>Esta página administrativa não foi encontrada. <a href="#/admin/visao-geral">Ir para a visão geral</a></Notice>:tab==='overview'?<AdminOverview/>:tab==='students'?<ManageStudents selectedId={studentId}/>:tab==='events'?<ReadingEvents/>:tab==='schools'?(studentId||schoolSection==='dashboard'?<SchoolsPanel key={schoolSection==='dashboard'?schoolId:'schools-dashboard'} selectedId={studentId} initialSchoolId={schoolSection==='dashboard'?schoolId:undefined}/>:<SchoolDirectory key={route} schoolId={schoolId} classId={classId} classes={schoolSection==='classes'}/>):tab==='stories'?<ManageStories storyId={storyId} create={newStory}/>:tab==='reports'?<SchoolsPanel report/>:tab==='access'?<AdminAccess/>:<><h1>Configurações</h1><CertificateSettings/></>}</main></div>;
}
