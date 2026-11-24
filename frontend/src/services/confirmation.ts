export type ConfirmationOptions={title?:string;confirmLabel?:string;cancelLabel?:string;danger?:boolean};
export type ConfirmationRequest=ConfirmationOptions&{message:string;theme:'light'|'dark'};
let current:ConfirmationRequest|null=null;
let resolvePending:((confirmed:boolean)=>void)|undefined;
const listeners=new Set<()=>void>();
export const confirmationSnapshot=()=>current;
export function subscribeConfirmation(listener:()=>void){listeners.add(listener);return()=>{listeners.delete(listener);};}
export function finishConfirmation(confirmed:boolean){const resolve=resolvePending;resolvePending=undefined;current=null;listeners.forEach(listener=>listener());resolve?.(confirmed);}
export function confirmAction(message:string,options:ConfirmationOptions={}):Promise<boolean>{
 // Repeated clicks must never authorize a second operation behind the dialog.
 if(current)return Promise.resolve(false);
 current={message,title:'Confirmar ação',confirmLabel:'Confirmar',cancelLabel:'Cancelar',...options,theme:document.querySelector('.admin-modern')?.getAttribute('data-theme')==='dark'?'dark':'light'};
 const promise=new Promise<boolean>(resolve=>{resolvePending=resolve;});
 listeners.forEach(listener=>listener());return promise;
}
