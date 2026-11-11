import {useRef,useState} from 'react';
import {Trash2,Power} from 'lucide-react';
import {useModalFocus} from '../hooks/useModalFocus';
import {Notice} from './PortalUI';

export function StudentActionDialog({name,action,onClose,onConfirm}:{name:string;action:'delete'|'activate'|'deactivate';onClose:()=>void;onConfirm:()=>Promise<void>}){
 const [busy,setBusy]=useState(false),[error,setError]=useState('');const running=useRef(false);
 useModalFocus(()=>{if(!running.current)onClose();});
 const title=action==='delete'?'Excluir aluno':action==='activate'?'Ativar acesso':'Desativar acesso';
 async function confirm(){if(running.current)return;running.current=true;setBusy(true);setError('');try{await onConfirm();onClose();}catch(e){setError((e as Error).message);}finally{running.current=false;setBusy(false);}}
 return <div className="management-modal" role="dialog" aria-modal="true" aria-labelledby="student-action-title" aria-describedby="student-action-description"><section className="management-dialog student-action-dialog" aria-busy={busy}>
  <div className={'student-action-icon '+(action==='delete'?'destructive':'')}>{action==='delete'?<Trash2 size={26} aria-hidden="true"/>:<Power size={26} aria-hidden="true"/>}</div>
  <h2 id="student-action-title">{title}?</h2>
  <p id="student-action-description">{action==='delete'?<>O cadastro de <strong>{name}</strong> será removido da lista e o acesso ao sistema será bloqueado.</>:action==='activate'?<>O acesso de <strong>{name}</strong> ao sistema será liberado.</>:<>O acesso de <strong>{name}</strong> ao sistema será bloqueado até que você o ative novamente.</>}</p>
  <p className="student-action-history">As leituras, pontuações e o histórico do aluno serão preservados.</p>
  {error&&<Notice error>{error}</Notice>}
  <div className="management-actions"><button type="button" disabled={busy} onClick={onClose}>Cancelar</button><button type="button" className={'club-button '+(action==='delete'?'student-action-delete':'')} disabled={busy} onClick={()=>void confirm()}>{busy?'Salvando…':title}</button></div>
 </section></div>;
}
