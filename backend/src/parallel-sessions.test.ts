import {test} from 'node:test';
import assert from 'node:assert/strict';
import express from 'express';
import {createServer} from 'node:http';
import type {AddressInfo} from 'node:net';
import {portal} from './portal.js';

test('administrador e aluno: sessões simultâneas, migração legada e saída independente',async()=>{
 const previous={url:process.env.SUPABASE_URL,key:process.env.SUPABASE_ANON_KEY};
 const token=(role:string)=>[Buffer.from('{}').toString('base64url'),Buffer.from(JSON.stringify({sub:role,exp:Math.floor(Date.now()/1000)+3600})).toString('base64url'),'test'].join('.');
 const user=(role:string)=>({id:role==='admin'?'00000000-0000-4000-8000-000000000001':'00000000-0000-4000-8000-000000000002',is_anonymous:role!=='admin',aud:'authenticated',role:'authenticated',app_metadata:{},user_metadata:{},created_at:new Date().toISOString()});
 const session=(role:string)=>({access_token:token(role),refresh_token:'refresh-'+role,expires_in:3600,token_type:'bearer',user:user(role)});
 const mock=express();mock.use(express.json());
 mock.use((req,res,next)=>{try{res.locals.role=JSON.parse(Buffer.from((req.get('authorization')??'').replace('Bearer ','').split('.')[1],'base64url').toString()).sub;}catch{res.locals.role='none';}next();});
 mock.post('/auth/v1/token',(req,res)=>res.json(session(req.query.grant_type==='password'?'admin':req.body.refresh_token.replace('refresh-',''))));
 mock.post('/auth/v1/signup',(_req,res)=>res.json(session('student')));
 mock.get('/auth/v1/user',(_req,res)=>res.json(user(res.locals.role)));
 const revoked:string[]=[];mock.post('/auth/v1/logout',(_req,res)=>{revoked.push(res.locals.role);res.sendStatus(204);});
 mock.post('/rest/v1/rpc/clube_portal',(req,res)=>{
  if(req.body.op==='session'){res.json({admin:res.locals.role==='admin',student:res.locals.role==='student'?{id:user('student').id,name:'Aluno Teste'}:null});return;}
  if(req.body.op==='return'){assert.equal(res.locals.role,'student');res.json(req.body.args.code==='AAAAAA'?{accessError:'invalid'}:{student:{id:user('student').id,name:'Aluno Teste'}});return;}
  res.json({});
 });
 mock.post('/rest/v1/rpc/clube_admin',(_req,res)=>{if(res.locals.role!=='admin'){res.status(403).json({code:'42501',message:'Forbidden'});return;}res.json({totalStudents:1});});
 mock.post('/rest/v1/rpc/clube_leitura',(_req,res)=>{if(res.locals.role!=='student'){res.status(403).json({code:'42501',message:'Forbidden'});return;}res.json({sequenceReady:true,levels:[{unlocked:true}]});});
 mock.post('/rest/v1/rpc/clube_eventos',(req,res)=>{const expected=req.body.op==='mine'?'student':'admin';if(res.locals.role!==expected){res.status(403).json({code:'42501',message:'Forbidden'});return;}res.json([]);});
 const upstream=createServer(mock);await new Promise<void>(r=>upstream.listen(0,'127.0.0.1',r));
 process.env.SUPABASE_URL='http://127.0.0.1:'+(upstream.address() as AddressInfo).port;process.env.SUPABASE_ANON_KEY='test';
 const app=express();app.use(express.json());app.use('/api/portal',portal);const server=createServer(app);await new Promise<void>(r=>server.listen(0,'127.0.0.1',r));const base='http://127.0.0.1:'+(server.address() as AddressInfo).port;
 const jar=new Map<string,string>();
 async function request(path:string,body?:unknown,context='student',cookie?:string){const response=await fetch(base+'/api/portal'+path,{method:body===undefined?'GET':'POST',headers:{Origin:base,'Content-Type':'application/json','X-Clube-Context':context,Cookie:cookie??[...jar].map(([k,v])=>k+'='+v).join('; ')},body:body===undefined?undefined:JSON.stringify(body)});for(const c of response.headers.getSetCookie()){const [k,...v]=c.split(';')[0].split('=');if(v.join('='))jar.set(k,v.join('='));else jar.delete(k);}return response;}
 try{
  assert.equal((await request('/admin/login',{email:'admin@example.test',password:'secret'},'admin')).status,200);
  const adminAccess=jar.get('clube_admin_access');assert.ok(adminAccess);assert.ok(!jar.has('clube_access'));
  assert.equal((await request('/return',{code:'AAAAAA'})).status,400);assert.equal(jar.get('clube_admin_access'),adminAccess);
  assert.equal((await request('/return',{code:'DZ R3-5E'})).status,200);assert.ok(jar.has('clube_access'));assert.equal(jar.get('clube_admin_access'),adminAccess);
  assert.equal((await request('/admin/overview')).status,200);assert.equal((await request('/reading/state')).status,200);
  assert.equal((await request('/events/admin?search=')).status,200);
  assert.equal((await request('/events/admin/00000000-0000-4000-8000-000000000003/recipients')).status,200);
  assert.equal((await request('/events/mine')).status,200);
  assert.equal((await (await request('/session')).json()).admin,false);assert.equal((await (await request('/session',undefined,'admin')).json()).admin,true);
  assert.equal((await request('/logout',{})).status,200);assert.ok(!jar.has('clube_access'));assert.equal(jar.get('clube_admin_access'),adminAccess);assert.equal(revoked.at(-1),'student');
  assert.equal((await request('/admin/overview')).status,200);
  assert.equal((await request('/return',{code:'DZR35E'})).status,200);const studentAccess=jar.get('clube_access');
  assert.equal((await request('/logout',{},'admin')).status,200);assert.ok(!jar.has('clube_admin_access'));assert.equal(jar.get('clube_access'),studentAccess);assert.equal(revoked.at(-1),'admin');
  assert.equal((await request('/reading/state')).status,200);assert.equal((await request('/admin/overview')).status,403);
  const beforeLogout=revoked.length;assert.equal((await request('/logout',{},'admin')).status,200);assert.equal(jar.get('clube_access'),studentAccess);assert.equal(revoked.length,beforeLogout,'Sair de administração ausente não encerra sessão do aluno');
  // Cookie de administrador de versões anteriores é separado automaticamente.
  jar.clear();jar.set('clube_access',token('admin'));jar.set('clube_refresh','refresh-admin');
  assert.equal((await request('/return',{code:'DZR35E'})).status,200);assert.equal(jar.get('clube_admin_access'),token('admin'));assert.equal(jar.get('clube_access'),token('student'));
  assert.equal((await request('/admin/overview')).status,200);
 }finally{server.closeAllConnections();server.close();upstream.closeAllConnections();upstream.close();for(const [key,value] of Object.entries({SUPABASE_URL:previous.url,SUPABASE_ANON_KEY:previous.key})){if(value===undefined)delete process.env[key];else process.env[key]=value;}}
});
