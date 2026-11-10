import {useState} from 'react';
import {BookOpen,KeyRound} from 'lucide-react';
import {Brand,Notice} from '../components/PortalUI';
import {portalApi} from '../services/portal';
import type {Student} from '../types/portal';
export function StudentAccess({token,active,onIdentified,onLogout}:{token:string;active:boolean;onIdentified:(student:Student)=>void;onLogout:()=>Promise<void>}){
 const [busy,setBusy]=useState(false),[error,setError]=useState('');
 async function enter(){setBusy(true);setError('');try{const data=await portalApi<{student:Student}>('/return',{code:token});onIdentified(data.student);}catch(e){setError((e as Error).message);}finally{setBusy(false);}}
 async function switchUser(){if(!window.confirm('Sair da conta atual para utilizar este acesso individual?'))return;await onLogout();window.location.hash='/acesso/'+token;}
 return <><header className="club-header"><Brand/></header><main className="club-card individual-entry"><KeyRound size={36}/><h1>Seu próximo capítulo começa aqui</h1><p>Confirme para entrar no Clube da Leitura com seu acesso individual.</p>{error&&<Notice error>{error}</Notice>}{active?<><p>Já existe uma conta conectada neste navegador.</p><a className="club-button" href="#/leitura">Continuar na conta atual</a><button onClick={()=>void switchUser()}>Usar o acesso desta ficha</button></>:<button className="club-button" disabled={busy||!/^[a-f0-9]{64}$/i.test(token)} onClick={()=>void enter()}><BookOpen size={18}/>{busy?'Identificando…':'Entrar e continuar minha leitura'}</button>}<small>Compartilhe seu link somente com seu responsável ou com a escola.</small></main></>;
}
