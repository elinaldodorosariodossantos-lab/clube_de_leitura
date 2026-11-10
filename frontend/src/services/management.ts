import {portalApi} from './portal';
export function manage<T>(path:string,method:'GET'|'POST'|'PUT'|'DELETE'='GET',body?:unknown):Promise<T>{return portalApi<T>('/admin/manage'+path,body,method);}
let guard:(()=>boolean)|undefined;
export function mayLeaveForm(){const current=guard;if(current&&!current())return false;if(guard===current)guard=undefined;return true;}
export function registerFormGuard(callback:()=>boolean){guard=callback;return()=>{if(guard===callback)guard=undefined;};}
