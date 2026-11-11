import {useState} from 'react';
import {KeyRound,Pencil,Plus} from 'lucide-react';
import {Notice} from '../components/PortalUI';
import {portalApi} from '../services/portal';
import {useEffect} from 'react';
import {useUnsavedForm} from '../hooks/useUnsavedForm';
type Access={id:string;name:string;email:string;createdAt:string};
export function AdminAccess(){
 const [rows,setRows]=useState<Access[]>([]),[editing,setEditing]=useState<Access|null|undefined>(),[name,setName]=useState(''),[email,setEmail]=useState(''),[password,setPassword]=useState(''),[busy,setBusy]=useState(false),[error,setError]=useState(''),[loading,setLoading]=useState(true);
 useUnsavedForm(editing!==undefined&&(name!==(editing?.name??'')||email!==(editing?.email??'')||password!==''));
 async function reload(){setLoading(true);try{setRows(await portalApi<Access[]>('/admin/access'));}catch(e){setError((e as Error).message);}finally{setLoading(false);}}
 useEffect(()=>{void reload();},[]);
 function open(row:Access|null){setEditing(row);setName(row?.name??'');setEmail(row?.email??'');setPassword('');setError('');}
 async function save(e:React.FormEvent){e.preventDefault();if(busy)return;setBusy(true);setError('');try{await portalApi('/admin/access',{...(editing?{id:editing.id}:{}),name,email,...(password?{password}:{})});setPassword('');setEditing(undefined);await reload();}catch(e){setError((e as Error).message);}finally{setBusy(false);}}
 return <section className="schools-panel school-module"><header className="schools-heading"><div><h1><KeyRound/>Acessos</h1><p>Gerencie os acessos administrativos.</p></div><button className="club-button" disabled={busy||loading} onClick={()=>open(null)}><Plus size={18}/>Novo acesso</button></header>{error&&<Notice error>{error}</Notice>}{loading?<Notice>Carregando acessos…</Notice>:<div className="schools-table-scroll school-module-table"><table><thead><tr><th>Nome</th><th>E-mail</th><th>Ações</th></tr></thead><tbody>{rows.map(row=><tr key={row.id}><td>{row.name}</td><td>{row.email}</td><td><button disabled={busy} onClick={()=>open(row)}><Pencil size={16}/>Editar</button></td></tr>)}</tbody></table></div>}{editing!==undefined&&<form className="management-dialog management-form" onSubmit={save}><h2>{editing?'Editar acesso':'Novo acesso'}</h2><fieldset disabled={busy}><label>Nome<input required minLength={3} maxLength={120} value={name} onChange={e=>setName(e.target.value)}/></label><label>E-mail<input required type="email" maxLength={254} value={email} onChange={e=>setEmail(e.target.value)}/></label><label>{editing?'Nova senha (opcional)':'Senha'}<input required={!editing} type="password" autoComplete="new-password" minLength={8} maxLength={128} value={password} onChange={e=>setPassword(e.target.value)}/></label></fieldset><div className="management-actions"><button className="club-button" disabled={busy}>{busy?'Salvando…':'Salvar'}</button><button type="button" disabled={busy} onClick={()=>{setEditing(undefined);setPassword('');}}>Cancelar</button></div></form>}</section>;
}
