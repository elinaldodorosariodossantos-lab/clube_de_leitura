import express from 'express';
import {createClient, type Session} from '@supabase/supabase-js';
import {z} from 'zod';
import {reading} from './reading.js';
import {administration} from './admin.js';
import {events} from './events.js';
import {restorePortalSession,forgetPortalSession} from './portal-auth.js';

export const studentSchema=z.object({name:z.string().trim().min(3).max(120).refine(v=>v.split(/\s+/).length>=2),age:z.number().int().min(4).max(19),school:z.string().trim().min(2).max(160),className:z.string().trim().max(60).default('')});
export const portal=express.Router();
portal.get('/health',(_req,res)=>{res.setHeader('Cache-Control','no-store');res.json({version:'20261102-story-scoring',features:['level-achievements','journey-completion','certificates','story-scoring']});});
const buckets=new Map<string,{count:number;until:number}>();
function client(accessToken?:string){return createClient(process.env.SUPABASE_URL!,process.env.SUPABASE_ANON_KEY!,{auth:{persistSession:false,autoRefreshToken:false,detectSessionInUrl:false},...(accessToken?{global:{headers:{Authorization:'Bearer '+accessToken}}}:{})});}
function cookies(req:express.Request){const parsed:Record<string,string>={};for(const part of (req.headers.cookie??'').split(';')){const index=part.indexOf('=');if(index<1)continue;try{parsed[part.slice(0,index).trim()]=decodeURIComponent(part.slice(index+1).trim());}catch{/* Cookie inválido não identifica um usuário. */}}return parsed;}
function save(res:express.Response,s:Session,context:'admin'|'student'=res.locals.authContext??'student'){const prefix=context==='admin'?'clube_admin':'clube';const options={httpOnly:true,sameSite:'strict' as const,secure:process.env.NODE_ENV==='production',path:'/api/portal'};res.cookie(prefix+'_access',s.access_token,{...options,maxAge:3600000});res.cookie(prefix+'_refresh',s.refresh_token,{...options,maxAge:7*86400000});}
function clearSession(res:express.Response,context:'admin'|'student'=res.locals.authContext??'student'){const prefix=context==='admin'?'clube_admin':'clube';for(const name of [prefix+'_access',prefix+'_refresh'])res.clearCookie(name,{path:'/api/portal',httpOnly:true,sameSite:'strict',secure:process.env.NODE_ENV==='production'});}
function temporaryAuthError(error:unknown){const e=error as {status?:number;name?:string};return !e.status||e.status===429||e.status>=500||e.name==='AuthRetryableFetchError';}
portal.use((req,res,next)=>{
 res.setHeader('Cache-Control','no-store');
 if(!['GET','HEAD'].includes(req.method)){
  const origin=req.get('origin');const allowed=process.env.APP_ORIGIN;
  let authorized=false;
  try{authorized=!!origin&&(allowed?origin===allowed:new URL(origin).origin===`${req.protocol}://${req.get('host')}`);}catch{/* Origens malformadas também são recusadas. */}
  if(!authorized){res.status(403).json({error:'Origem da solicitação não autorizada.'});return;}
 }
 if(!process.env.SUPABASE_URL||!process.env.SUPABASE_ANON_KEY){res.status(503).json({error:'Configure SUPABASE_URL e SUPABASE_ANON_KEY no backend e execute a migração da primeira etapa.'});return;}
 next();
});
portal.use(async(req,res,next)=>{try{
 const c=client(),cookie=cookies(req);const adminContext=req.path==='/admin'||req.path.startsWith('/admin/')||req.path==='/events/admin'||req.path.startsWith('/events/admin/')||(!req.path.startsWith('/reading')&&!['/register','/return','/student'].includes(req.path)&&req.get('X-Clube-Context')==='admin');res.locals.authContext=adminContext?'admin':'student';res.locals.client=c;
 const prefix=adminContext&&cookie.clube_admin_refresh?'clube_admin':'clube',access=cookie[prefix+'_access'],refresh=cookie[prefix+'_refresh'];
 if(refresh){
  const {data,error}=await restorePortalSession(c,access,refresh);
  if(error){if(temporaryAuthError(error))throw error;clearSession(res);res.locals.client=client();}
  else if(data.session){const verified=await c.auth.getUser();if(verified.error){if(temporaryAuthError(verified.error))throw verified.error;clearSession(res);res.locals.client=client();}else{
    if(adminContext&&prefix==='clube'){const identity=await c.rpc('clube_portal',{op:'session',args:{}});if(identity.error)throw identity.error;if(!identity.data?.admin){if(req.path==='/logout')res.locals.client=client();else res.locals.user=verified.data.user;next();return;}}
    if(!adminContext&&prefix==='clube'&&verified.data.user?.is_anonymous!==true){const identity=await c.rpc('clube_portal',{op:'session',args:{}});if(identity.error)throw identity.error;if(identity.data?.admin){save(res,data.session,'admin');clearSession(res,'student');res.locals.client=client();next();return;}}
    res.locals.user=verified.data.user;if(req.path!=='/logout'&&(data.session.access_token!==access||data.session.refresh_token!==refresh))save(res,data.session);}}
 }else if(access){
  const verified=await c.auth.getUser(access);
  if(verified.error){if(temporaryAuthError(verified.error))throw verified.error;clearSession(res);}
  else if(verified.data.user){res.locals.user=verified.data.user;res.locals.client=client(access);}
 }
 next();
}catch{res.status(503).json({error:'Não foi possível conectar ao serviço de identificação.'});}});
portal.use((req,res,next)=>{
 if(['/register','/return','/admin/login'].includes(req.path)){
  const key=(req.ip??'local')+req.path,now=Date.now();for(const [k,v] of buckets)if(v.until<now)buckets.delete(k);
  const b=buckets.get(key)??{count:0,until:now+15*60000};b.count++;buckets.set(key,b);
  const limit=req.path==='/register'?Number(process.env.REGISTRATION_LIMIT??120):20;
  if(b.count>limit){res.status(429).json({error:'Muitas tentativas. Aguarde 15 minutos para tentar novamente.'});return;}
 }next();
});
async function rpc(res:express.Response,op:string,args:unknown={},rpcClient=res.locals.client){const {data,error}=await rpcClient.rpc('clube_portal',{op,args});if(data?.accessError){throw Object.assign(new Error(data.accessError==='rate_limited'?'Muitas tentativas. Aguarde 15 minutos para tentar novamente.':'Confira os dados ou o código informado.'),{status:data.accessError==='rate_limited'?429:400});}if(error){const e=new Error(error.code==='42501'?'Acesso não autorizado.':error.code==='22023'?'Confira os dados ou o código informado.':'Não foi possível concluir. Confira a configuração do banco.') as Error&{status:number};e.status=error.code==='42501'?403:400;throw e;}return data;}
portal.post('/register',async(req,res)=>{
 const parsed=studentSchema.safeParse(req.body);if(!parsed.success){res.status(400).json({error:'Informe nome completo, idade de 4 a 19 anos e escola.'});return;}
 const config=await rpc(res,'config');if(parsed.data.age<config.minAge||parsed.data.age>config.maxAge){res.status(400).json({error:`A idade deve estar entre ${config.minAge} e ${config.maxAge} anos.`});return;}
 if(res.locals.user){res.status(409).json({error:'Saia da conta atual antes de cadastrar outro aluno.'});return;}
 const c=res.locals.client;const {data,error}=await c.auth.signInAnonymously();if(error||!data.session){res.status(503).json({error:'Não foi possível identificar o aluno. Verifique se Anonymous Sign-Ins está habilitado no Supabase.'});return;}
 const result=await rpc(res,'register',parsed.data);save(res,data.session);res.status(201).json(result);
});
portal.post('/return',async(req,res)=>{
 const parsed=z.object({code:z.string().transform(v=>{const c=v.replace(/[\s-]/g,'');return c.length===6?c.toUpperCase():c.toLowerCase();}).pipe(z.string().regex(/^(?:[A-HJ-NP-Z2-9]{6}|[A-F0-9]{32}|[A-F0-9]{64})$/i))}).safeParse(req.body);
 if(!parsed.success){res.status(400).json({error:'Confira seu código individual de 6 caracteres ou a credencial recebida.'});return;}
 // Valida o código numa identidade nova: um login ativo não impede recuperar a entrada.
 // Não encerra nem substitui a sessão atual antes de confirmar o código no banco.
 const candidate=client();
 const {data,error}=await candidate.auth.signInAnonymously();if(error||!data.session){res.status(503).json({error:'Não foi possível iniciar a identificação no Supabase.'});return;}
 let result;
 try{result=await rpc(res,'return',parsed.data,candidate);}catch(cause){
  try{await candidate.auth.signOut({scope:'local'});}catch{/* Preserva o erro original e a sessão anterior. */}
  throw cause;
 }
 if(res.locals.user?.is_anonymous===true){
  forgetPortalSession(cookies(req).clube_refresh);
  try{await res.locals.client.auth.signOut({scope:'local'});}catch{/* O novo acesso já foi confirmado. */}
 }
 res.locals.client=candidate;res.locals.user=data.user;
 save(res,data.session,'student');res.json(result);
});
portal.post('/admin/login',async(req,res)=>{
 const parsed=z.object({email:z.string().trim().email().max(254),password:z.string().min(1).max(256)}).safeParse(req.body);if(!parsed.success){res.status(400).json({error:'Informe e-mail e senha.'});return;}
 const {data,error}=await res.locals.client.auth.signInWithPassword(parsed.data);
 if(error?.code==='email_not_confirmed'){res.status(401).json({error:'Confirme seu e-mail pela mensagem enviada pelo Supabase antes de entrar. Verifique também a caixa de spam.'});return;}
 if(error||!data.session){res.status(error?.status===429?429:401).json({error:error?.status===429?'Muitas tentativas. Aguarde alguns minutos antes de tentar novamente.':'E-mail ou senha inválidos.'});return;}
 try{const result=await rpc(res,'session');if(!result.admin){const e=new Error('Sua conta não tem autorização administrativa.') as Error&{status:number};e.status=403;throw e;}save(res,data.session);res.json({admin:true});}catch(e){await res.locals.client.auth.signOut({scope:'local'});throw e;}
});
portal.post('/logout',async(req,res)=>{const cookie=cookies(req);forgetPortalSession(cookie[res.locals.authContext==='admin'?'clube_admin_refresh':'clube_refresh']);await res.locals.client.auth.signOut({scope:'local'});clearSession(res);res.json({ok:true});});
portal.get('/schools',async(_req,res)=>res.json(await rpc(res,'schools')));
portal.get('/settings',async(_req,res)=>res.json(await rpc(res,'config')));
portal.get('/session',async(_req,res)=>{const session=res.locals.user?await rpc(res,'session'):{student:null,admin:false};if(res.locals.user&&!session.student&&!session.admin)clearSession(res);res.json(session);});
portal.get('/student',async(_req,res)=>{if(!res.locals.user){res.status(401).json({error:'Identifique-se para continuar.'});return;}res.json(await rpc(res,'student'));});
portal.get('/admin',async(_req,res)=>{if(!res.locals.user){res.status(401).json({error:'Entre com sua conta administrativa.'});return;}res.json(await rpc(res,'admin'));});
portal.use('/reading',reading);
portal.use('/events',events);
portal.use('/admin',administration);
portal.use((err:unknown,_req:express.Request,res:express.Response,_next:express.NextFunction)=>{const e=err as Error&{status?:number};res.status(e.status??503).json({error:e.status?e.message:'Não foi possível concluir a solicitação. Tente novamente.'});});
