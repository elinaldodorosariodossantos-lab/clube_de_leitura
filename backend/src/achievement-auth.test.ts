import {test} from 'node:test';
import assert from 'node:assert/strict';
import express from 'express';
import {createServer} from 'node:http';
import type {AddressInfo} from 'node:net';
import {portal} from './portal.js';

test('conquistas HTTP: renovação concorrente, cookie de acesso, expiração e saída',async t=>{
 const before={url:process.env.SUPABASE_URL,key:process.env.SUPABASE_ANON_KEY};
 const uid='00000000-0000-4000-8000-000000000002',achievement='06aa8275-0cd1-4d1c-b028-5bbe5dcad63d';
 const token=(kind:string,expires:number)=>[Buffer.from('{}').toString('base64url'),Buffer.from(JSON.stringify({sub:uid,kind,exp:expires})).toString('base64url'),'test'].join('.');
 const expired=token('expired',1),access=token('current',Math.floor(Date.now()/1000)+3600);
 const user={id:uid,is_anonymous:true,aud:'authenticated',role:'authenticated',app_metadata:{},user_metadata:{},created_at:new Date().toISOString()};
 let rotations=0,mutations=0;const mock=express();mock.use(express.json());
 mock.post('/auth/v1/token',async(req,res)=>{rotations++;await new Promise(r=>setTimeout(r,80));if(req.body.refresh_token!=='initial-refresh'||rotations!==1){res.status(400).json({code:'refresh_token_already_used',msg:'Invalid Refresh Token: Already Used'});return;}res.json({access_token:access,refresh_token:'rotated-refresh',expires_in:3600,token_type:'bearer',user});});
 mock.get('/auth/v1/user',(req,res)=>{if(req.get('authorization')!=='Bearer '+access){res.status(401).json({code:'bad_jwt',msg:'Invalid JWT'});return;}res.json(user);});
 mock.post('/auth/v1/logout',(_req,res)=>res.sendStatus(204));
 mock.post('/rest/v1/rpc/clube_leitura',(req,res)=>{assert.equal(req.get('authorization'),'Bearer '+access);if(req.body.op==='achievement_claim'){mutations++;assert.equal(req.body.args.id,achievement);res.json({achievement:{id:achievement}});}else if(req.body.op==='journey_get'||req.body.op==='journey_claim'){assert.equal(req.body.args.id,achievement);res.json({completion:{id:achievement},operation:req.body.op});}else res.json({sequenceReady:true,levels:[{unlocked:true}]});});
 const upstream=createServer(mock);await new Promise<void>(r=>upstream.listen(0,'127.0.0.1',r));process.env.SUPABASE_URL='http://127.0.0.1:'+(upstream.address() as AddressInfo).port;process.env.SUPABASE_ANON_KEY='test';
 const app=express();app.use(express.json());app.use('/api/portal',portal);const server=createServer(app);await new Promise<void>(r=>server.listen(0,'127.0.0.1',r));const base='http://127.0.0.1:'+(server.address() as AddressInfo).port;
 const request=(path:string,cookie:string,post=false)=>fetch(base+'/api/portal'+path,{method:post?'POST':'GET',headers:{Origin:base,'Content-Type':'application/json','X-Clube-Context':'student',Cookie:cookie},body:post?'{}':undefined});
 const originalCookie='clube_access='+expired+'; clube_refresh=initial-refresh',currentCookie='clube_access='+access+'; clube_refresh=rotated-refresh';
 try{
  await t.test('finish/state/claim com o mesmo cookie expirado compartilham uma única rotação',async()=>{const responses=await Promise.all([request('/reading/state',originalCookie),request('/reading/achievements/'+achievement+'/claim',originalCookie,true),request('/reading/state',originalCookie)]);for(const response of responses){assert.equal(response.status,200,await response.clone().text());assert.ok(response.headers.getSetCookie().some(x=>x.startsWith('clube_refresh=rotated-refresh')));assert.ok(!response.headers.getSetCookie().some(x=>x.includes('Max-Age=0')));}assert.equal(rotations,1);assert.equal(mutations,1);});
  await t.test('requisição atrasada com o token anterior não encerra a sessão renovada',async()=>{const response=await request('/reading/state',originalCookie);assert.equal(response.status,200);assert.equal(rotations,1);});
  await t.test('cookie de acesso válido sem refresh continua autorizado pelo Supabase',async()=>{assert.equal((await request('/reading/achievements/'+achievement+'/claim','clube_access='+access,true)).status,200);assert.equal(mutations,2);});
  await t.test('sessão realmente inválida devolve 401 e não executa a conquista',async()=>{const response=await request('/reading/achievements/'+achievement+'/claim','clube_access='+expired+'; clube_refresh=revoked',true);assert.equal(response.status,401);assert.equal(mutations,2);assert.equal((await request('/reading/achievements/'+achievement+'/claim','',true)).status,401);assert.equal(mutations,2);});
  await t.test('rotas atuais de conclusao sao reconhecidas e encaminhadas ao RPC',async()=>{const health=await request('/health','');assert.equal(health.status,200);assert.equal((await health.json()).version,'20261102-story-scoring');for(const action of ['', '/claim']){const response=await request('/reading/journeys/'+achievement+action,currentCookie,!!action);assert.equal(response.status,200);const body=await response.json();assert.equal(body.completion.id,achievement);assert.equal(body.operation,action?'journey_claim':'journey_get');}assert.equal((await request('/reading/journeys/invalido',currentCookie)).status,400);});
  await t.test('logout invalida também a janela de reaproveitamento da rotação',async()=>{assert.equal((await request('/logout',currentCookie,true)).status,200);assert.equal((await request('/reading/state',originalCookie)).status,401);});
 }finally{server.closeAllConnections();server.close();upstream.closeAllConnections();upstream.close();if(before.url===undefined)delete process.env.SUPABASE_URL;else process.env.SUPABASE_URL=before.url;if(before.key===undefined)delete process.env.SUPABASE_ANON_KEY;else process.env.SUPABASE_ANON_KEY=before.key;}
});
