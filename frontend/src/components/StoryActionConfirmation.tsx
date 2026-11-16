import {createPortal} from 'react-dom';
import {Power,Trash2} from 'lucide-react';
import {useModalFocus} from '../hooks/useModalFocus';
import type {StoryRow} from '../types/management';
import './story-action-confirmation.css';

export function StoryActionConfirmation({story,remove,busy,onCancel,onConfirm}:{story:StoryRow;remove:boolean;busy:boolean;onCancel:()=>void;onConfirm:()=>void}){
 useModalFocus(()=>{if(!busy)onCancel();});
 const action=remove?'Excluir':story.active?'Inativar':'Ativar';
 return createPortal(<div className="story-confirm-overlay" onClick={event=>{if(event.target===event.currentTarget&&!busy)onCancel();}}><section className="story-confirm-card" role="dialog" aria-modal="true" aria-labelledby="story-confirm-title" aria-describedby="story-confirm-description" aria-busy={busy}>
  <span className={'story-confirm-icon'+(remove?' is-danger':'')}>{remove?<Trash2 size={26}/>:<Power size={26}/>}</span>
  <h2 id="story-confirm-title">{action} história?</h2>
  <p className="story-confirm-name">{story.title}</p>
  <p id="story-confirm-description">{remove?'A história sairá da lista e ficará indisponível para novas leituras. Os eventos já distribuídos e os resultados dos alunos serão preservados.':story.active?'A história ficará indisponível para novas leituras. O histórico dos alunos será preservado.':'A história ficará disponível conforme as configurações de leitura. O histórico dos alunos será preservado.'}</p>
  <div className="story-confirm-actions"><button type="button" disabled={busy} onClick={onCancel}>Cancelar</button><button type="button" className={'story-confirm-submit'+(remove?' is-danger':'')} disabled={busy} onClick={onConfirm}>{busy?'Aguarde…':action+' história'}</button></div>
 </section></div>,document.body);
}
