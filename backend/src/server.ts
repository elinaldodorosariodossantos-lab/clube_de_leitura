import 'dotenv/config';
import express from 'express';
import {createClient} from '@supabase/supabase-js';
import {z} from 'zod';
import {randomUUID} from 'node:crypto';
import {mkdir,readFile,writeFile,rename} from 'node:fs/promises';
import {activity,score} from './activity.js';
import {portal} from './portal.js';
const app=express();app.use(express.json({limit:'2mb'}));
app.use('/api/portal',portal);
// Rotas do portal nunca passam pela autenticacao Bearer do modulo legado.
app.use('/api/portal',(_req,res)=>{res.status(404).json({error:'Rota do portal indisponivel. Atualize o servidor da aplicacao.'});});
const mode=process.env.DATA_MODE??'demo';
if(process.env.NODE_ENV==='production'&&mode!=='supabase') throw new Error('Produção exige DATA_MODE=supabase');
if(mode==='supabase'&&(!process.env.SUPABASE_URL||!process.env.SUPABASE_ANON_KEY)) throw new Error('Configure SUPABASE_URL e SUPABASE_ANON_KEY');
type Attempt={id:string;owner:string;answers:Record<string,number>;status:string;result?:ReturnType<typeof score>;completedAt?:string};
await mkdir('data',{recursive:true});
let attempts:Record<string,Attempt>={};
try{attempts=JSON.parse(await readFile('data/attempts.json','utf8'));}catch(e){if((e as NodeJS.ErrnoException).code!=='ENOENT')throw e;}
let queue=Promise.resolve();
function transaction<T>(fn:()=>Promise<T>){const pending=queue.then(fn);queue=pending.then(()=>{},()=>{});return pending;}
async function persist(){await writeFile('data/attempts.tmp',JSON.stringify(attempts));await rename('data/attempts.tmp','data/attempts.json');}
app.get('/api/config',(_req,res)=>res.json({mode}));
app.use('/api',async(req,res,next)=>{try{
 const token=req.headers.authorization?.replace(/^Bearer /,'');
 if(mode==='supabase'){
 if(!token){res.status(401).json({error:'Entre na sua conta.'});return;}
 const client=createClient(process.env.SUPABASE_URL!,process.env.SUPABASE_ANON_KEY!,{global:{headers:{Authorization:`Bearer ${token}`}},auth:{persistSession:false}});
 const {data,error}=await client.auth.getUser(token);if(error||!data.user){res.status(401).json({error:'Sessão inválida.'});return;}res.locals.client=client;res.locals.owner=data.user.id;
 }else {if(!token||!z.uuid().safeParse(token).success){res.status(401).json({error:'Identificador de demonstração inválido.'});return;}res.locals.owner=token;}
 next();}catch(e){next(e);}});
async function rpc(res:express.Response,op:string,args:unknown={}){const {data,error}=await res.locals.client.rpc('clube_api',{op,args});if(error){const e=new Error(error.message) as Error&{status:number};e.status=error.code==='42501'?403:400;throw e;}return data;}
app.get('/api/activity',async(_req,res)=>res.json(mode==='supabase'?await rpc(res,'activity'):activity));
app.post('/api/attempts',async(_req,res)=>{if(mode==='supabase'){res.status(201).json(await rpc(res,'start'));return;}await transaction(async()=>{const a:Attempt={id:randomUUID(),owner:res.locals.owner,answers:{},status:'started'};attempts[a.id]=a;await persist();res.status(201).json(a);});});
app.get('/api/history',async(_req,res)=>res.json(mode==='supabase'?await rpc(res,'history'):Object.values(attempts).filter(a=>a.owner===res.locals.owner&&a.status==='completed')));
app.get('/api/attempts/:id',async(req,res)=>{if(mode==='supabase'){res.json(await rpc(res,'get',{id:req.params.id}));return;}const a=attempts[String(req.params.id)];if(!a||a.owner!==res.locals.owner){res.status(404).json({error:'Tentativa não encontrada.'});return;}res.json(a);});
app.put('/api/attempts/:id/answers',async(req,res)=>{const body=z.object({questionId:mode==='supabase'?z.number().int().positive():z.number().int().min(1).max(5),selected:mode==='supabase'?z.number().int().min(0):z.number().int().min(0).max(3)}).parse(req.body);if(mode==='supabase'){res.json(await rpc(res,'answer',{id:req.params.id,...body}));return;}await transaction(async()=>{const a=attempts[String(req.params.id)];if(!a||a.owner!==res.locals.owner){res.status(404).json({error:'Tentativa não encontrada.'});return;}if(a.status==='completed'){res.status(409).json({error:'Tentativa já concluída.'});return;}a.answers[body.questionId]=body.selected;await persist();res.json(a);});});
app.post('/api/attempts/:id/finish',async(req,res)=>{if(mode==='supabase'){res.json(await rpc(res,'finish',{id:req.params.id}));return;}await transaction(async()=>{const a=attempts[String(req.params.id)];if(!a||a.owner!==res.locals.owner){res.status(404).json({error:'Tentativa não encontrada.'});return;}if(a.status!=='completed'){a.result=score(a.answers);a.status='completed';a.completedAt=new Date().toISOString();await persist();}res.json(a);});});
app.use((err:Error&{status?:number},_req:express.Request,res:express.Response,_next:express.NextFunction)=>{res.status(err instanceof z.ZodError?400:err.status??400).json({error:err instanceof z.ZodError?'Dados inválidos.':err.message});});
app.listen(Number(process.env.PORT??3001),'127.0.0.1',()=>console.log(`Clube da Leitura: API na porta ${process.env.PORT??3001} (${mode})`));
