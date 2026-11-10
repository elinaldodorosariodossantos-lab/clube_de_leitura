import {useUnsavedForm} from '../hooks/useUnsavedForm';
import {useState} from 'react';
import {useAdminResource} from '../hooks/useAdminResource';
import {portalApi} from '../services/portal';
import {Notice} from './PortalUI';
export function CertificateSettings(){
 const [dirty,setDirty]=useState(false);useUnsavedForm(dirty);
 const {data,loading,error,reload}=useAdminResource<{institution:string;identification:string}>('/admin/certificate-settings',dirty);
 const [busy,setBusy]=useState(false),[message,setMessage]=useState('');
 async function save(event:React.FormEvent<HTMLFormElement>){event.preventDefault();const values=new FormData(event.currentTarget);setBusy(true);setMessage('');try{await portalApi('/admin/certificate-settings',{institution:values.get('institution'),identification:values.get('identification')});setMessage('Identificação salva para os próximos certificados. Os certificados já emitidos permanecem iguais.');setDirty(false);await reload();}catch(e){setMessage((e as Error).message);}finally{setBusy(false);}}
 return <section className="club-card"><h2>Identificação dos certificados</h2><p>Informe apenas os dados institucionais autorizados. Campos vazios não aparecem no certificado.</p>{loading&&<Notice>Consultando configuração…</Notice>}{error&&<Notice error>{error}<button onClick={()=>void reload()}>Tentar novamente</button></Notice>}{data&&<form key={JSON.stringify(data)} onSubmit={save} onChange={()=>setDirty(true)}><label>Instituição<input name="institution" maxLength={160} defaultValue={data.institution} disabled={busy}/></label><label>Identificação institucional ou do responsável<input name="identification" maxLength={160} defaultValue={data.identification} disabled={busy}/></label><button className="club-button" disabled={busy}>{busy?'Salvando…':'Salvar identificação'}</button></form>}{message&&<Notice>{message}</Notice>}</section>;
}
