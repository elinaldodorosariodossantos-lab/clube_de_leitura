import {portalApi} from './portal';
export function manage<T>(path:string,method:'GET'|'POST'|'PUT'|'DELETE'='GET',body?:unknown):Promise<T>{return portalApi<T>('/admin/manage'+path,body,method);}
let guard:(()=>boolean|Promise<boolean>)|undefined;
let pending:Promise<boolean>|undefined;
export async function mayLeaveForm(){
 if(pending)return pending;
 const current=guard;if(!current)return true;
 pending=(async()=>{if(!await current())return false;if(guard===current)guard=undefined;return true;})();
 try{return await pending;}finally{pending=undefined;}
}
export function registerFormGuard(callback:()=>boolean|Promise<boolean>){guard=callback;return()=>{if(guard===callback)guard=undefined;};}
