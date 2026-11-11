import {test} from 'node:test';
import assert from 'node:assert/strict';
import express from 'express';
import {adminAccess} from './admin-access.js';

test('acessos: exige administrador e não altera contas fora da lista',async()=>{
 const app=express();app.use(express.json());let allowed=false,calls=0;
 app.use((_req,res,next)=>{res.locals.client={rpc:async(name:string)=>{calls++;return {data:name==='clube_admin_autorizado'?allowed:[],error:null};}};next();});
 app.use('/access',adminAccess);
 const server=app.listen(0,'127.0.0.1');await new Promise<void>(r=>server.once('listening',r));
 const address=server.address() as {port:number},base='http://127.0.0.1:'+address.port+'/access';
 try{
  assert.equal((await fetch(base)).status,403);assert.equal(calls,1);
  allowed=true;assert.deepEqual(await (await fetch(base)).json(),[]);
  const response=await fetch(base,{method:'POST',headers:{'Content-Type':'application/json'},body:JSON.stringify({id:'00000000-0000-4000-8000-000000000001',name:'Outro usuário',email:'other@example.com',password:'longpassword'})});
  assert.equal(response.status,404);
  assert.equal((await fetch(base,{method:'POST',headers:{'Content-Type':'application/json'},body:JSON.stringify({name:'Novo Admin',email:'new@example.com',password:'123'})})).status,400);
 }finally{server.closeAllConnections();server.close();}
});

test('acessos: cria e edita pelo Auth privado; remove usuário novo se o perfil falhar',async()=>{
 const prior={url:process.env.SUPABASE_URL,key:process.env.SUPABASE_SERVICE_ROLE_KEY};
 const id='00000000-0000-4000-8000-000000000001';let failProfile=false,deleted=false,updated=false;
 const mock=express();mock.use(express.json());
 mock.use((req,_res,next)=>{assert.equal(req.get('apikey'),'private-test-key');next();});
 mock.post('/auth/v1/admin/users',(req,res)=>{assert.equal(req.body.email,'admin@example.com');assert.equal(req.body.password,'newpassword');res.json({id,email:req.body.email});});
 mock.put('/auth/v1/admin/users/:id',(req,res)=>{assert.equal(req.params.id,id);assert.equal(req.body.password,undefined);updated=true;res.json({id,email:req.body.email});});
 mock.delete('/auth/v1/admin/users/:id',(_req,res)=>{deleted=true;res.json({});});
 const upstream=mock.listen(0,'127.0.0.1');await new Promise<void>(r=>upstream.once('listening',r));
 process.env.SUPABASE_URL='http://127.0.0.1:'+(upstream.address() as {port:number}).port;process.env.SUPABASE_SERVICE_ROLE_KEY='private-test-key';
 const app=express();app.use(express.json());
 app.use((_req,res,next)=>{res.locals.client={rpc:async(name:string,args?:{op:string})=>({data:name==='clube_admin_autorizado'?true:args?.op==='list'?[{id}]:{ok:true},error:failProfile&&args?.op==='save'?{code:'error'}:null})};next();});
 app.use('/access',adminAccess);const server=app.listen(0,'127.0.0.1');await new Promise<void>(r=>server.once('listening',r));
 const request=(body:unknown)=>fetch('http://127.0.0.1:'+(server.address() as {port:number}).port+'/access',{method:'POST',headers:{'Content-Type':'application/json'},body:JSON.stringify(body)});
 try{
  const response=await request({name:'Admin Teste',email:'admin@example.com',password:'newpassword'});assert.equal(response.status,201);assert.deepEqual(await response.json(),{ok:true});
  assert.equal((await request({id,name:'Editado',email:'admin@example.com'})).status,200);assert.equal(updated,true);
  failProfile=true;assert.equal((await request({name:'Admin Teste',email:'admin@example.com',password:'newpassword'})).status,503);assert.equal(deleted,true);
 }finally{
  server.closeAllConnections();server.close();upstream.closeAllConnections();upstream.close();
  if(prior.url===undefined)delete process.env.SUPABASE_URL;else process.env.SUPABASE_URL=prior.url;
  if(prior.key===undefined)delete process.env.SUPABASE_SERVICE_ROLE_KEY;else process.env.SUPABASE_SERVICE_ROLE_KEY=prior.key;
 }
});
