import {test} from 'node:test';
import assert from 'node:assert/strict';
import express from 'express';
import {createServer} from 'node:http';
import {randomUUID} from 'node:crypto';
import {events,eventSchema,ageConfigsSchema,schoolIdsSchema} from './events.js';
test('idades e níveis: quantidades, duplicatas e limites aceitos',()=>{
 const levels=[{level:'facil',quantity:2,storyIds:['a','b','c']}];
 const configs=[{age:5,levels},{age:9,levels:[{level:'medio',quantity:1,storyIds:['d']}]}];
 assert.ok(ageConfigsSchema.safeParse(configs).success);
 assert.ok(ageConfigsSchema.safeParse([{age:4,levels:[{level:'facil',quantity:5},{level:'medio',quantity:0}]}]).success);
 for(const value of [[...configs,configs[0]],[{age:20,levels}],[{age:5,levels:[...levels,...levels]}],[{age:5,levels:[{...levels[0],quantity:-1}]}],[{age:5,levels:[{...levels[0],quantity:1.5}]}]])assert.equal(ageConfigsSchema.safeParse(value).success,false);
});
test('eventos HTTP: validação e operações encaminhadas ao RPC seguro',async()=>{
 const input={schoolIds:[randomUUID()],requestId:randomUUID(),name:'Semana de Leitura',description:'Vamos ler juntos',level:'facil',minAge:6,maxAge:8,startsAt:'2026-10-20T08:00:00-03:00',endsAt:'2026-10-30T18:00:00-03:00',active:true,mode:'sorteio',quantity:1,storyIds:['passarinho']};
 assert.ok(eventSchema.safeParse(input).success);
 for(const patch of [{minAge:9},{endsAt:input.startsAt},{quantity:2},{storyIds:['passarinho','passarinho']},{description:''}])assert.equal(eventSchema.safeParse({...input,...patch}).success,false);
 const calls:{fn:string;op:string;args:any}[]=[];const app=express();app.use(express.json());app.use((req,res,next)=>{if(req.get('x-user')==='yes')res.locals.user={id:'authorized'};res.locals.client={rpc:async(fn:string,body:{op:string;args:unknown})=>{calls.push({fn,...body});return {data:body.op==='age_config_ready'?true:body.op==='mine'?[]:{ok:true},error:null};}};next();});app.use('/events',events);app.use((error:any,_req:express.Request,res:express.Response,_next:express.NextFunction)=>res.status(error.status??500).json({error:error.message}));
 const server=createServer(app);await new Promise<void>(r=>server.listen(0,'127.0.0.1',r));const base=`http://127.0.0.1:${(server.address() as {port:number}).port}/events`;
 const request=(path:string,method='GET',body?:unknown,authenticated=true)=>fetch(base+path,{method,headers:{'Content-Type':'application/json','x-user':authenticated?'yes':'no'},body:body===undefined?undefined:JSON.stringify(body)});
 try{
  assert.equal((await request('/mine','GET',undefined,false)).status,401);assert.equal(calls.length,0);
  assert.equal((await request('/admin','POST',{...input,quantity:2})).status,400);assert.equal(calls.length,0);
  assert.equal((await request('/admin','POST',input)).status,201);assert.equal(calls[0].fn,'clube_eventos');assert.equal(calls[0].op,'save');
  assert.equal((await request('/admin','POST',{...input,automatic:true,storyIds:[],quantity:13,ageConfigs:[{age:4,levels:[{level:'facil',quantity:5},{level:'medio',quantity:3},{level:'dificil',quantity:5}]}]})).status,201);assert.equal(calls.at(-1)?.args.automatic,true);assert.equal(calls.at(-1)?.args.ageConfigs[0].levels[0].storyIds.length,0);
  const school=randomUUID();assert.equal((await request('/admin/schools')).status,200);assert.equal(calls.at(-1)?.op,'school_options');
  const id=randomUUID();assert.equal((await request('/admin/'+id+'/schools','PUT',{schoolIds:[school]})).status,200);assert.equal(calls.at(-1)?.op,'schools_save');assert.deepEqual(calls.at(-1)?.args.schoolIds,[school]);assert.equal(schoolIdsSchema.safeParse([school,school]).success,false);assert.equal(schoolIdsSchema.safeParse(['invalid']).success,false);assert.equal((await request('/admin/'+id+'/send','POST',{studentIds:[randomUUID()]})).status,200);assert.equal(calls.at(-1)?.op,'send');
  assert.equal((await request('/'+id+'/enter','POST',{})).status,200);assert.equal(calls.at(-1)?.op,'enter');assert.equal(calls.at(-1)?.args.id,id);
  assert.equal((await request('/admin/'+id+'/recipients?eligibleOnly=false&age=7')).status,200);assert.equal(calls.at(-1)?.args.age,7);
 }finally{server.closeAllConnections();server.close();}
});
