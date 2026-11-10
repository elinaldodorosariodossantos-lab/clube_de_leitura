import {portalApi} from './portal';
export function eventApi<T>(path:string,method:'GET'|'POST'|'PUT'|'DELETE'='GET',body?:unknown):Promise<T>{return portalApi<T>('/events'+path,body,method);}
export const eventDate=(value:string)=>new Date(value).toLocaleString('pt-BR',{timeZone:'America/Fortaleza',dateStyle:'short',timeStyle:'short'});
