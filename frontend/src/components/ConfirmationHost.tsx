import {useEffect,useSyncExternalStore} from 'react';
import {createPortal} from 'react-dom';
import {CircleHelp,TriangleAlert} from 'lucide-react';
import {confirmationSnapshot,subscribeConfirmation,finishConfirmation} from '../services/confirmation';
import {useModalFocus} from '../hooks/useModalFocus';
import './confirmation.css';
export function ConfirmationHost(){
 const request=useSyncExternalStore(subscribeConfirmation,confirmationSnapshot);
 useModalFocus(()=>finishConfirmation(false),!!request);
 useEffect(()=>()=>finishConfirmation(false),[]);
 if(!request)return null;
 return createPortal(<div className="app-confirm-overlay" data-theme={request.theme} onClick={event=>{if(event.target===event.currentTarget)finishConfirmation(false);}}><section className="app-confirm-card" role="dialog" aria-modal="true" aria-labelledby="app-confirm-title" aria-describedby="app-confirm-description"><span className={'app-confirm-symbol'+(request.danger?' is-danger':'')}>{request.danger?<TriangleAlert aria-hidden="true"/>:<CircleHelp aria-hidden="true"/>}</span><h2 id="app-confirm-title">{request.title}</h2><p id="app-confirm-description">{request.message}</p><div className="app-confirm-actions"><button type="button" onClick={()=>finishConfirmation(false)}>{request.cancelLabel}</button><button type="button" className={'app-confirm-primary'+(request.danger?' is-danger':'')} onClick={()=>finishConfirmation(true)}>{request.confirmLabel}</button></div></section></div>,document.body);
}
