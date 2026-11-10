import dotenv from 'dotenv';
import {createClient} from '@supabase/supabase-js';
dotenv.config({path:new URL('../.env',import.meta.url)});
const url=process.env.SUPABASE_URL,key=process.env.SUPABASE_ANON_KEY;
if(!url||!key)throw new Error('Configure backend/.env antes de verificar.');
const headers={apikey:key};
async function inspect(path,options={}){
 try{const r=await fetch(url+path,{...options,headers:{...headers,...options.headers},signal:AbortSignal.timeout(15000)});const data=await r.json().catch(()=>null);return {status:r.status,data};}
 catch(e){return {error:e.cause?.code??e.message};}
}
const auth=await inspect('/auth/v1/settings');
console.log(JSON.stringify({check:'auth',status:auth.status,anonymousEnabled:auth.data?.external?.anonymous_users,error:auth.error}));
for(const table of ['perfis','alunos','tentativas','escolas','jornadas']){
 const r=await inspect('/rest/v1/'+table+'?select=id&limit=0');
 console.log(JSON.stringify({check:table,status:r.status,code:r.data?.code,message:r.data?.message,error:r.error}));
}
const rpc=await inspect('/rest/v1/rpc/clube_portal',{method:'POST',headers:{'Content-Type':'application/json'},body:JSON.stringify({op:'config'})});
console.log(JSON.stringify({check:'clube_portal',status:rpc.status,code:rpc.data?.code,message:rpc.data?.message,settings:rpc.status===200?rpc.data:undefined,error:rpc.error}));
const sdk=createClient(url,key,{auth:{persistSession:false,autoRefreshToken:false}});
const {data,error}=await sdk.rpc('clube_portal',{op:'config'});
console.log(JSON.stringify({check:'supabase-js',settings:data,code:error?.code,message:error?.message}));
const reading=await sdk.rpc('clube_leitura',{op:'state'});
console.log(JSON.stringify({check:'clube_leitura',installed:reading.error?.code!=='PGRST202',code:reading.error?.code,message:reading.error?.message}));
const administrative=await sdk.rpc('clube_admin',{op:'overview'});
console.log(JSON.stringify({check:'clube_admin',installed:administrative.error?.code==='PGRST202'?false:administrative.error?.code==='42501'?true:null,code:administrative.error?.code,message:administrative.error?.message}));
