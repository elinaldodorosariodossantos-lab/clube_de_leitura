import {test} from 'node:test';
import assert from 'node:assert/strict';
import express from 'express';
import {createServer} from 'node:http';
import {randomUUID} from 'node:crypto';
import {createClient} from '@supabase/supabase-js';
import {PNG} from 'pngjs';
import {createRequire} from 'node:module';
const jsQR=createRequire(import.meta.url)('jsqr') as (data:Uint8ClampedArray,width:number,height:number)=>{data:string}|null;
import {management} from './management.js';
test('gestão HTTP: autorização, cadastro, colisão, QR decodificável, edição e regeneração',async()=>{
 const previous={url:process.env.SUPABASE_URL,key:process.env.SUPABASE_ANON_KEY,encryption:process.env.ACCESS_CREDENTIALS_KEY,base:process.env.PUBLIC_APP_URL,origin:process.env.APP_ORIGIN,environment:process.env.NODE_ENV};
 const records=new Map<string,any>(),requests=new Map<string,string>();let signups=0,collisions=1;let restartArgs:any;
 const mock=express();mock.use(express.json());mock.post('/auth/v1/signup',(_req,res)=>{signups++;res.json({access_token:'unused',refresh_token:'unused',expires_in:3600,token_type:'bearer',user:{id:randomUUID(),is_anonymous:true,aud:'authenticated',created_at:new Date().toISOString()}});});
 mock.post('/rest/v1/rpc/clube_admin_autorizado',(req,res)=>res.json(req.get('authorization')==='Bearer admin'));
 mock.post('/storage/v1/object/clube-capas/:name',express.raw({type:'image/*'}),(req,res)=>res.json({Key:'clube-capas/'+req.params.name,Id:randomUUID()}));
 mock.post('/storage/v1/object/list/clube-capas',(_req,res)=>res.json([{id:randomUUID(),name:'pagina.png'}]));
 mock.post('/rest/v1/rpc/clube_gestao',(req,res)=>{const {op,args}=req.body;if(op==='student_journey_restart'){restartArgs=args;res.json({newJourneyId:randomUUID()});return;}if(op==='student_request'){res.json(requests.has(args.requestId)?records.get(requests.get(args.requestId)!):null);return;}if(op==='student_save'&&!args.id&&collisions-- >0){res.status(409).json({code:'23505',message:'collision'});return;}if(op==='student_save'){const id=args.id??randomUUID();const old=records.get(id)??{};if(args.requestId)requests.set(args.requestId,id);records.set(id,{...old,id,name:args.name,school:'Escola de teste',className:args.className,status:old.status??'ativo',encrypted:args.encrypted??old.encrypted});res.json(records.get(id));return;}if(op==='credentials_save'){Object.assign(records.get(args.id),{encrypted:args.encrypted});res.json(records.get(args.id));return;}if(op==='student_status'){records.get(args.id).status=args.status;res.json(records.get(args.id));return;}if(op==='credentials'){res.json(records.get(args.id));return;}res.json([]);});
 const auth=createServer(mock);await new Promise<void>(r=>auth.listen(0,'127.0.0.1',r));const authAddress=auth.address() as {port:number};process.env.SUPABASE_URL=`http://127.0.0.1:${authAddress.port}`;process.env.SUPABASE_ANON_KEY='public-test-key';process.env.ACCESS_CREDENTIALS_KEY='a'.repeat(64);process.env.PUBLIC_APP_URL='https://leitura.example';
 const app=express();app.use(express.json());app.use((req,res,next)=>{res.locals.client=createClient(process.env.SUPABASE_URL!,process.env.SUPABASE_ANON_KEY!,{global:{headers:{Authorization:'Bearer '+(req.get('x-test-role')??'admin')}},auth:{persistSession:false}});next();});app.use('/manage',management);app.use((e:any,_req:express.Request,res:express.Response,_next:express.NextFunction)=>res.status(e.status??500).json({error:e.message}));const server=createServer(app);await new Promise<void>(r=>server.listen(0,'127.0.0.1',r));const base=`http://127.0.0.1:${(server.address() as {port:number}).port}/manage`;
 async function request(path:string,method='GET',body?:unknown,role='admin'){return fetch(base+path,{method,headers:{'Content-Type':'application/json','x-test-role':role},body:body===undefined?undefined:JSON.stringify(body)});}
 try{
  assert.equal((await request('/students','POST',{},'student')).status,403);assert.equal(signups,0);
  assert.equal((await request('/students','POST',{name:'X'})).status,400);assert.equal(signups,0);
  const input={requestId:randomUUID(),name:'Aluno de Teste',birthDate:'2016-01-10',guardian:'Responsável de Teste',schoolId:randomUUID(),className:'4º ano'};
  for(const birthDate of ['2099-01-01','2016-02-30','not-a-date'])assert.equal((await request('/students','POST',{...input,birthDate})).status,400);assert.equal(signups,0);
  const created=await request('/students','POST',input);assert.equal(created.status,201);const card=await created.json() as any;assert.match(card.code,/^[A-HJ-NP-Z2-9]{6}$/);assert.match(card.link,/^https:\/\/leitura\.example\/#\/acesso\/[a-f0-9]{64}$/);assert.equal(signups,1,'Colisão não cria outra conta anônima');assert.ok(!('encrypted' in card.student));
  const retry=await request('/students','POST',input);assert.equal(retry.status,200);const retried=await retry.json() as any;assert.equal(retried.student.id,card.student.id);assert.equal(retried.code,card.code);assert.equal(signups,1,'Resposta perdida não cria outra identidade nem outro aluno');
  const png=PNG.sync.read(Buffer.from(card.qr.split(',')[1],'base64'));const decoded=jsQR(new Uint8ClampedArray(png.data),png.width,png.height);assert.equal(decoded?.data,card.link,'QR representa exatamente o link individual');
  const edited=await request('/students/'+card.student.id,'PUT',{...input,name:'Aluno Editado'});assert.equal(edited.status,200);assert.ok(!('encrypted' in await edited.json()));const before=await (await request('/students/'+card.student.id+'/access')).json() as any;assert.equal(before.code,card.code);assert.equal(before.link,card.link);
  assert.equal((await request('/students/'+card.student.id+'/status','POST',{status:'inativo'})).status,200);
  const rotated=await (await request('/students/'+card.student.id+'/access','POST',{})).json() as any;assert.notEqual(rotated.code,card.code);assert.notEqual(rotated.link,card.link);
  const uploaded=await fetch(base+'/covers',{method:'POST',headers:{'Content-Type':'image/png'},body:Buffer.from(card.qr.split(',')[1],'base64')});assert.equal(uploaded.status,201);assert.ok((await uploaded.json() as {url:string}).url.includes('/storage/v1/object/public/clube-capas/'));
  assert.equal((await fetch(base+'/covers',{method:'POST',headers:{'Content-Type':'image/png'},body:'arquivo inválido'})).status,400);
  const gallery=await request('/images');assert.equal(gallery.status,200);assert.ok((await gallery.json() as any).images[0].url.endsWith('/pagina.png'));
  assert.equal((await request('/images','GET',undefined,'student')).status,403);
  const book={title:'Livro por páginas',level:'facil',age:'7 anos',active:true,required:true,ordering:0,pages:[{id:randomUUID(),text:'Página um',image:'https://storage.example/pagina.png'},{id:randomUUID(),text:'Página dois',image:''}],questions:[{prompt:'Qual?',options:['A','B'],correct:0}]};
  assert.equal((await request('/stories','POST',book)).status,201);
  for(const layout of ['illustration','side','frame'])assert.equal((await request('/stories','POST',{...book,pages:book.pages.map(p=>({...p,layout}))})).status,201);
  assert.equal((await request('/stories','POST',{...book,pages:book.pages.map(p=>({...p,layout:'inexistente'}))})).status,400);
  assert.equal((await request('/stories','POST',{...book,pages:[]})).status,400);
  assert.equal((await request('/stories','POST',{...book,pages:[{...book.pages[0],image:'blob:temporaria'}]})).status,400);
  assert.equal((await request('/stories','POST',{...book,questions:[{prompt:'',options:['',''],correct:0}]})).status,400);
  assert.equal((await request('/stories','POST',{...book,active:false,pages:[],questions:[{prompt:'',options:['',''],correct:0}]})).status,201);
  const originJourney=randomUUID();assert.equal((await request('/students/'+card.student.id+'/journey-restart','POST',{journeyId:originJourney},'student')).status,403);assert.equal(restartArgs,undefined);assert.equal((await request('/students/'+card.student.id+'/journey-restart','POST',{})).status,400);assert.equal((await request('/students/'+card.student.id+'/journey-restart','POST',{journeyId:originJourney})).status,200);assert.deepEqual(restartArgs,{id:card.student.id,journeyId:originJourney});
  process.env.PUBLIC_APP_URL='';process.env.APP_ORIGIN='';process.env.NODE_ENV='development';const localCard=await (await request('/students/'+card.student.id+'/access')).json() as any;assert.ok(localCard.link.startsWith(base.replace('/manage','')+'/#/acesso/'));
  process.env.NODE_ENV='production';assert.equal((await request('/students','POST',input)).status,503);assert.equal(signups,1,'Produção sem URL não cria identidade sem ficha');
 }finally{server.closeAllConnections();server.close();auth.closeAllConnections();auth.close();for(const [key,value] of Object.entries({SUPABASE_URL:previous.url,SUPABASE_ANON_KEY:previous.key,ACCESS_CREDENTIALS_KEY:previous.encryption,PUBLIC_APP_URL:previous.base,APP_ORIGIN:previous.origin,NODE_ENV:previous.environment})){if(value===undefined)delete process.env[key];else process.env[key]=value;}}
});
