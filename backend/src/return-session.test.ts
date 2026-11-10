import {test} from 'node:test';import assert from 'node:assert/strict';import express from 'express';import {createServer} from 'node:http';import type {AddressInfo} from 'node:net';import {portal} from './portal.js';
test('entrada por código recupera sessão ativa e só troca após validar o novo código',async t=>{
 const previous={url:process.env.SUPABASE_URL,key:process.env.SUPABASE_ANON_KEY};let signups=0,failSignup=false,registers=0;
 const a={id:'00000000-0000-4000-8000-000000000011',name:'Aluno Anterior',points:13,completed:5},b={id:'00000000-0000-4000-8000-000000000012',name:'Outro Aluno',points:8,completed:3};
 const linked=new Map<string,typeof a>(),revoked=new Set<string>();
 const token=(id:string)=>[Buffer.from('{}').toString('base64url'),Buffer.from(JSON.stringify({sub:id,exp:Math.floor(Date.now()/1000)+3600})).toString('base64url'),'test'].join('.');
 const user=(id:string)=>({id,is_anonymous:true,aud:'authenticated',role:'authenticated',app_metadata:{},user_metadata:{},created_at:new Date().toISOString()});
 const mock=express();mock.use(express.json());mock.use((req,res,next)=>{try{res.locals.uid=JSON.parse(Buffer.from((req.get('authorization')??'').split('.')[1],'base64url').toString()).sub;}catch{res.locals.uid='none';}next();});
 mock.post('/auth/v1/signup',(_req,res)=>{if(failSignup){res.status(503).json({msg:'Unavailable'});return;}const id='00000000-0000-4000-8000-'+String(++signups).padStart(12,'0');res.json({access_token:token(id),refresh_token:'refresh-'+id,expires_in:3600,token_type:'bearer',user:user(id)});});
 mock.get('/auth/v1/user',(_req,res)=>{if(revoked.has(res.locals.uid)){res.status(401).json({code:'bad_jwt',msg:'Signed out'});return;}res.json(user(res.locals.uid));});
 mock.post('/auth/v1/logout',(_req,res)=>{revoked.add(res.locals.uid);res.sendStatus(204);});
 mock.post('/rest/v1/rpc/clube_portal',(req,res)=>{
  const id=res.locals.uid;if(req.body.op==='return'){
   assert.ok(!linked.has(id),'O RPC de retorno recebe uma identidade nova, nunca a já vinculada');
   const student=req.body.args.code==='DZR35E'?a:req.body.args.code==='AB2CD3'?b:null;
   if(!student){res.json({accessError:'invalid'});return;}linked.set(id,student);res.json({student});return;
  }
  if(req.body.op==='register')registers++;
  res.json(req.body.op==='session'?{student:linked.get(id)??null,admin:false}:{});
 });
 const upstream=createServer(mock);await new Promise<void>(r=>upstream.listen(0,'127.0.0.1',r));process.env.SUPABASE_URL='http://127.0.0.1:'+(upstream.address() as AddressInfo).port;process.env.SUPABASE_ANON_KEY='test';
 const app=express();app.use(express.json());app.use('/api/portal',portal);const server=createServer(app);await new Promise<void>(r=>server.listen(0,'127.0.0.1',r));const base='http://127.0.0.1:'+(server.address() as AddressInfo).port;
 const jar=new Map<string,string>([['clube_admin_access','admin-access-preserved'],['clube_admin_refresh','admin-refresh-preserved']]);
 async function request(path:string,body?:unknown){const response=await fetch(base+'/api/portal'+path,{method:body===undefined?'GET':'POST',headers:{Origin:base,'Content-Type':'application/json','X-Clube-Context':'student',Cookie:[...jar].map(([k,v])=>k+'='+v).join('; ')},body:body===undefined?undefined:JSON.stringify(body)});for(const c of response.headers.getSetCookie()){const [k,...v]=c.split(';')[0].split('=');if(v.join('='))jar.set(k,v.join('='));else jar.delete(k);}return response;}
 try{
  await t.test('entrada inicial',async()=>{const response=await request('/return',{code:'DZR35E'});assert.equal(response.status,200);assert.deepEqual((await response.json()).student,a);});
  await t.test('mesmo código e cookie ativo retomam o aluno com os mesmos resultados',async()=>{const oldRefresh=jar.get('clube_refresh');const response=await request('/return',{code:'DZR35E'});assert.equal(response.status,200);assert.deepEqual((await response.json()).student,a);assert.notEqual(jar.get('clube_refresh'),oldRefresh);assert.deepEqual((await(await request('/session')).json()).student,a);});
  await t.test('código inválido preserva a sessão e não encerra o aluno atual',async()=>{const oldRefresh=jar.get('clube_refresh'),count=revoked.size;assert.equal((await request('/return',{code:'AAAAAA'})).status,400);assert.equal(jar.get('clube_refresh'),oldRefresh);assert.deepEqual((await(await request('/session')).json()).student,a);assert.equal(revoked.size,count+1,'Somente a identidade candidata inválida é encerrada');});
  await t.test('código válido de outro aluno troca o acesso sem afetar o administrador',async()=>{const response=await request('/return',{code:'AB2CD3'});assert.equal(response.status,200);assert.deepEqual((await response.json()).student,b);assert.deepEqual((await(await request('/session')).json()).student,b);assert.equal(jar.get('clube_admin_access'),'admin-access-preserved');assert.equal(jar.get('clube_admin_refresh'),'admin-refresh-preserved');assert.equal(registers,0,'O retorno não cadastra alunos novamente');});
  await t.test('consulta com tokens validos nao reenvia cookies antigos',async()=>{const response=await request('/session');assert.equal(response.status,200);assert.deepEqual((await response.json()).student,b);assert.deepEqual(response.headers.getSetCookie(),[]);});
  await t.test('formato inválido não cria identidade nem derruba sessão',async()=>{const count=signups;assert.equal((await request('/return',{code:'!'})).status,400);assert.equal(signups,count);assert.deepEqual((await(await request('/session')).json()).student,b);});
 }finally{server.closeAllConnections();server.close();upstream.closeAllConnections();upstream.close();if(previous.url===undefined)delete process.env.SUPABASE_URL;else process.env.SUPABASE_URL=previous.url;if(previous.key===undefined)delete process.env.SUPABASE_ANON_KEY;else process.env.SUPABASE_ANON_KEY=previous.key;}
});
