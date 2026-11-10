import {test} from 'node:test';
import assert from 'node:assert/strict';
import express from 'express';
import {createServer} from 'node:http';
import type {AddressInfo} from 'node:net';
import {portal,studentSchema} from './portal.js';

test('cadastro: valida nome completo, idade, escola e limita os campos',()=>{
 const valid={name:'Ana Maria',age:9,school:'Escola Municipal',className:'4º A'};
 assert.ok(studentSchema.safeParse(valid).success);
 for(const invalid of [{name:'Ana'},{age:3},{age:20},{age:9.5},{age:'9'},{school:' '},{name:'a'.repeat(121)}])assert.equal(studentSchema.safeParse({...valid,...invalid}).success,false);
 assert.deepEqual(studentSchema.parse({...valid,papel:'admin'}),valid);
});

test('portal: configuração ausente, origem, cookies e autorização administrativa',async()=>{
 const prior={url:process.env.SUPABASE_URL,key:process.env.SUPABASE_ANON_KEY};
 const app=express();app.use(express.json());app.use('/api/portal',portal);const api=createServer(app);
 const issuedToken=(kind:string)=>[Buffer.from('{}').toString('base64url'),Buffer.from(JSON.stringify({sub:kind,exp:Math.floor(Date.now()/1000)+3600})).toString('base64url'),Buffer.from('test-signature').toString('base64url')].join('.');
 let kind='student',rpcCalls=0,anonymousSignups=0,authStatus=200,orphanSession=false;
 const sessionStudent={id:'00000000-0000-4000-8000-000000000002',name:'Ana Maria'};
 const readingCalls:{op:string;args:Record<string,unknown>}[]=[];
 const adminCalls:{op:string;args:Record<string,unknown>}[]=[];
 const upstream=createServer(async(req,res)=>{
  let raw='';for await(const chunk of req)raw+=chunk;const body=raw?JSON.parse(raw):{};
  res.setHeader('Content-Type','application/json');
  const user={id:kind==='admin'?'00000000-0000-4000-8000-000000000001':'00000000-0000-4000-8000-000000000002',aud:'authenticated',role:'authenticated',email:'team@example.test',created_at:new Date().toISOString(),app_metadata:{},user_metadata:{}};
  if(req.url?.startsWith('/auth/v1/token')||req.url==='/auth/v1/signup'){if(req.url==='/auth/v1/signup')anonymousSignups++;res.end(JSON.stringify({access_token:issuedToken(kind),refresh_token:'refresh-'+kind,expires_in:3600,token_type:'bearer',user}));return;}
  if(req.url==='/auth/v1/user'){if(authStatus!==200){res.statusCode=authStatus;res.end(JSON.stringify({code:authStatus===401?'bad_jwt':'over_request_rate_limit',msg:'QA auth failure'}));return;}res.end(JSON.stringify(user));return;}
  if(req.url==='/rest/v1/rpc/clube_leitura'){readingCalls.push(body);res.end(JSON.stringify(body.op==='state'?{sequenceReady:true,levels:[{unlocked:true}]}:{op:body.op,args:body.args}));return;}
  if(req.url==='/rest/v1/rpc/clube_admin'){adminCalls.push(body);if(kind!=='admin'){res.statusCode=403;res.end(JSON.stringify({code:'42501',message:'Forbidden'}));return;}res.end(JSON.stringify({op:body.op,args:body.args}));return;}
  if(req.url?.startsWith('/auth/v1/logout')){res.statusCode=204;res.end();return;}
  if(req.url==='/rest/v1/rpc/clube_portal'){
   rpcCalls++;
   if(body.op==='admin'&&kind!=='admin'){res.statusCode=403;res.end(JSON.stringify({code:'42501',message:'Forbidden'}));return;}
   if(body.op==='config'){res.end(JSON.stringify({minAge:4,maxAge:19}));return;}
   if(body.op==='register'){res.end(JSON.stringify({student:{name:body.args.name},code:'1234567890abcdef1234567890abcdef'}));return;}
   if(body.op==='return'){res.end(JSON.stringify({student:sessionStudent,codeReceived:body.args.code}));return;}
   if(body.op==='session'){res.end(JSON.stringify({admin:kind==='admin',student:kind==='student'&&!orphanSession?sessionStudent:null}));return;}
   res.end(JSON.stringify({totalStudents:0,students:[],admin:kind==='admin',student:null}));return;
  }
  res.statusCode=404;res.end('{}');
 });
 await new Promise<void>(r=>api.listen(0,'127.0.0.1',r));await new Promise<void>(r=>upstream.listen(0,'127.0.0.1',r));
 const url=`http://127.0.0.1:${(api.address() as AddressInfo).port}`;
 async function request(path:string,body?:unknown,cookie?:string,origin=url,context='student'){return fetch(url+'/api/portal'+path,{method:body===undefined?'GET':'POST',headers:{'Content-Type':'application/json','X-Clube-Context':context,Origin:origin,...(cookie?{Cookie:cookie}:{})},body:body===undefined?undefined:JSON.stringify(body)});}
 try{
  delete process.env.SUPABASE_URL;delete process.env.SUPABASE_ANON_KEY;
  assert.equal((await request('/session')).status,503);
  process.env.SUPABASE_URL=`http://127.0.0.1:${(upstream.address() as AddressInfo).port}`;process.env.SUPABASE_ANON_KEY='test-public-key';
  assert.equal((await request('/register',{},undefined,'https://untrusted.test')).status,403);
  assert.equal((await request('/register',{name:'Ana',age:9,school:'Escola'})).status,400);
  assert.equal((await request('/return',{code:'guess'})).status,400);
  const before=rpcCalls;assert.equal((await request('/admin')).status,401);assert.equal(rpcCalls,before);
  const denied=await request('/admin/login',{email:'team@example.test',password:'secret'});assert.equal(denied.status,403);assert.equal(denied.headers.get('set-cookie'),null);
  kind='admin';const login=await request('/admin/login',{email:'team@example.test',password:'secret'});assert.equal(login.status,200);
  const setCookie=login.headers.getSetCookie();assert.equal(setCookie.length,2);assert.ok(setCookie.every(c=>c.includes('HttpOnly')&&c.includes('SameSite=Strict')&&c.includes('Path=/api/portal')));
  const cookie=setCookie.map(c=>c.split(';')[0]).join('; ');assert.equal((await request('/admin',undefined,cookie)).status,200);
  assert.equal((await request('/admin',undefined,'clube_refresh=refresh-admin')).status,200);
  assert.equal((await request('/admin/overview')).status,401);
  assert.equal((await request('/admin/overview',undefined,cookie)).status,200);
  assert.deepEqual(adminCalls.at(-1),{op:'overview',args:{}});
  const studentId='00000000-0000-4000-8000-000000000022';
  assert.equal((await request('/admin/students?search=Ana&sort=points_desc&page=2&pageSize=10&schoolId='+studentId,undefined,cookie)).status,200);
  assert.deepEqual(adminCalls.at(-1),{op:'students',args:{search:'Ana',schoolId:studentId,sort:'points_desc',page:2,pageSize:10}});
  const beforeAdmin=adminCalls.length;
  assert.equal((await request('/admin/students?sort=unsafe',undefined,cookie)).status,400);
  assert.equal((await request('/admin/students?page=0',undefined,cookie)).status,400);
  assert.equal((await request('/admin/students/not-a-uuid',undefined,cookie)).status,400);
  assert.equal(adminCalls.length,beforeAdmin);
  assert.equal((await request('/admin/students/'+studentId,undefined,cookie)).status,200);
  assert.deepEqual(adminCalls.at(-1),{op:'student',args:{id:studentId}});
  assert.equal((await request('/register',{name:'Ana Maria',age:9,school:'Escola'},cookie)).status,201,'Cadastro do aluno não exige sair da administração');
  const logout=await request('/logout',{},cookie,url,'admin');assert.equal(logout.status,200);assert.ok(logout.headers.getSetCookie().every(c=>c.includes('Expires=Thu, 01 Jan 1970')));
  kind='student';const registration=await request('/register',{name:'Ana Maria',age:9,school:'Escola'});assert.equal(registration.status,201);assert.equal((await registration.json()).code.length,32);
  const studentCookie=registration.headers.getSetCookie().map(c=>c.split(';')[0]).join('; '),signups=anonymousSignups;
  assert.equal((await request('/admin/overview',undefined,studentCookie)).status,403);
  assert.equal((await request('/admin/students',undefined,studentCookie)).status,403);
  assert.equal((await request('/admin/students/'+studentId,undefined,studentCookie)).status,403);
  assert.equal((await request('/reading/state')).status,401);
  assert.equal((await request('/reading/state',undefined,studentCookie)).status,200);
  await request('/session',undefined,studentCookie);await request('/reading/state',undefined,studentCookie);
  assert.equal(anonymousSignups,signups,'Consultas e recarregamentos reutilizam a sessão');
  const beforeReading=readingCalls.length;
  assert.equal((await request('/reading/start',{level:'admin'},studentCookie)).status,400);
  assert.equal((await request('/reading/attempts/invalid',undefined,studentCookie)).status,400);
  assert.equal(readingCalls.length,beforeReading,'Validação impede operações inválidas no banco');
  const attemptId='00000000-0000-4000-8000-000000000004';
  assert.equal((await request('/reading/start',{level:'medio'},studentCookie)).status,200);
  assert.deepEqual(readingCalls.at(-1),{op:'start',args:{level:'medio'}});
  assert.equal((await request('/reading/levels/facil/stories',undefined,studentCookie)).status,200);
  assert.deepEqual(readingCalls.at(-1),{op:'stories',args:{level:'facil'}});
  assert.equal((await request('/reading/enter',{level:'facil',points:999},studentCookie)).status,200);
  assert.deepEqual(readingCalls.at(-1),{op:'enter',args:{level:'facil'}});
  assert.equal((await request('/reading/enter',{level:'admin'},studentCookie)).status,400);
  assert.equal((await request('/reading/levels/admin/stories',undefined,studentCookie)).status,400);
  assert.equal((await request('/reading/start',{level:'facil',storyId:'passarinho',points:999},studentCookie)).status,200);
  assert.deepEqual(readingCalls.at(-1),{op:'start',args:{level:'facil',storyId:'passarinho'}});
  assert.equal((await request(`/reading/attempts/${attemptId}/answers`,{questionId:201,selected:1,points:999},studentCookie)).status,200);
  assert.deepEqual(readingCalls.at(-1),{op:'answer',args:{id:attemptId,questionId:201,selected:1}});
  assert.equal((await request(`/reading/attempts/${attemptId}/answers`,{questionId:201,selected:-1},studentCookie)).status,400);
  assert.equal((await request(`/reading/attempts/${attemptId}/answers`,{questionId:201,selected:5},studentCookie)).status,200);
  assert.deepEqual(readingCalls.at(-1),{op:'answer',args:{id:attemptId,questionId:201,selected:5}});
  assert.equal((await request(`/reading/attempts/${attemptId}/stage`,{stage:'resultado'},studentCookie)).status,400);
  assert.equal((await request('/reading/new-journey',{},studentCookie)).status,403);
  assert.notEqual(readingCalls.at(-1)?.op,'new_journey');
  authStatus=429;const unavailable=await request('/session',undefined,studentCookie);assert.equal(unavailable.status,503);assert.equal(unavailable.headers.getSetCookie().length,0,'Falha temporária não apaga a sessão');
  authStatus=200;const recovered=await request('/session',undefined,studentCookie);assert.equal(recovered.status,200);assert.equal((await recovered.json()).student.id,sessionStudent.id);assert.equal(anonymousSignups,signups);
  authStatus=401;const invalid=await request('/session',undefined,studentCookie);assert.equal(invalid.status,200);assert.equal((await invalid.json()).student,null);assert.ok(invalid.headers.getSetCookie().every(c=>c.includes('Expires=Thu, 01 Jan 1970')));authStatus=200;
  orphanSession=true;const revoked=await request('/session',undefined,studentCookie);assert.equal((await revoked.json()).student,null);assert.ok(revoked.headers.getSetCookie().some(c=>c.startsWith('clube_refresh=;')),'Vínculo antigo não impede retorno com código');orphanSession=false;
  const returned=await request('/return',{code:'1234-5678-90AB-CDEF-1234-5678-90AB-CDEF'});assert.equal(returned.status,200);assert.equal((await returned.json()).codeReceived,'1234567890abcdef1234567890abcdef');
 }finally{
  if(prior.url===undefined)delete process.env.SUPABASE_URL;else process.env.SUPABASE_URL=prior.url;
  if(prior.key===undefined)delete process.env.SUPABASE_ANON_KEY;else process.env.SUPABASE_ANON_KEY=prior.key;
  api.closeAllConnections();upstream.closeAllConnections();await Promise.all([new Promise<void>(r=>api.close(()=>r())),new Promise<void>(r=>upstream.close(()=>r()))]);
 }
});
