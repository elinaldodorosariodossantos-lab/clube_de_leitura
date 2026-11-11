type Method='GET'|'POST'|'PUT'|'DELETE';
let sessionGeneration=0;
const reads=new Map<string,Promise<unknown>>();
export function advancePortalSession(){sessionGeneration++;reads.clear();}
function context(path:string){return path.startsWith('/admin')||path==='/events/admin'||path.startsWith('/events/admin?')||path.startsWith('/events/admin/')||(['/session','/logout'].includes(path)&&typeof window!=='undefined'&&(window.location.hash?window.location.hash.startsWith('#/admin'):['/adm','/administrador'].includes(window.location.pathname.replace(/\/$/,''))))?'admin':'student';}
export function portalApi<T>(path:string,body?:unknown,method:Method=body===undefined?'GET':'POST'):Promise<T>{
 if(method!=='GET'){reads.clear();return request<T>(path,body,method).finally(()=>reads.clear());}
 const key=sessionGeneration+'|'+context(path)+'|'+path;
 const existing=reads.get(key);if(existing)return existing as Promise<T>;
 const promise=request<T>(path,undefined,'GET');reads.set(key,promise);
 void promise.finally(()=>{if(reads.get(key)===promise)reads.delete(key);}).catch(()=>{});
 return promise;
}
export function portalUpload<T>(path:string,file:File):Promise<T>{reads.clear();return request<T>(path,file,'POST',file.type).finally(()=>reads.clear());}
async function request<T>(path:string,body:unknown,method:Method,rawType?:string):Promise<T>{
 const authContext=context(path),generation=sessionGeneration,readOnly=method==='GET',attempts=readOnly?3:1;
 const unavailable=readOnly?'Não foi possível conectar ao clube. Aguarde alguns instantes e tente novamente.':'Não foi possível confirmar o envio. Aguarde alguns instantes antes de tentar novamente.';
 for(let attempt=0;attempt<attempts;attempt++){
  if(attempt>0)await new Promise(resolve=>setTimeout(resolve,attempt*500));
  const controller=new AbortController(),timeout=setTimeout(()=>controller.abort(),30000);
  let response:Response,data:Record<string,unknown>|null;
  try{response=await fetch('/api/portal'+path,{method,signal:controller.signal,credentials:'same-origin',headers:{'Content-Type':rawType??'application/json','X-Clube-Context':authContext},body:readOnly?undefined:rawType?body as File:body===undefined?undefined:JSON.stringify(body)});data=await response.json().catch(()=>null);}
  catch{if(attempt<attempts-1)continue;throw new Error(unavailable);}finally{clearTimeout(timeout);}
  if(data===null||[502,504].includes(response.status)){if(attempt<attempts-1)continue;throw new Error(unavailable);}
  if(!response.ok){
   if(response.status===401&&generation===sessionGeneration&&!['/session','/admin/login','/register','/return'].includes(path)&&typeof window!=='undefined'&&typeof window.dispatchEvent==='function')window.dispatchEvent(new CustomEvent('clube:session-expired',{detail:{context:authContext}}));
   const message=typeof data.error==='string'?data.error:'Não foi possível concluir.';
   throw new Error(response.status===503&&!path.startsWith('/admin')&&/SUPABASE|migração|Anonymous Sign-Ins/.test(message)?'O serviço de identificação ainda está sendo preparado. Procure a equipe responsável para continuar.':message);
  }
  if(['/return','/register','/admin/login','/logout'].includes(path))advancePortalSession();
  return data as T;
 }
 throw new Error(unavailable);
}
