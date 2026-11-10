import {test} from 'node:test';
import assert from 'node:assert/strict';
import {readFile} from 'node:fs/promises';
import ts from 'typescript';
const source=await readFile(new URL('./src/services/portal.ts',import.meta.url),'utf8');
const compiled=ts.transpileModule(source,{compilerOptions:{target:ts.ScriptTarget.ES2022,module:ts.ModuleKind.ESNext}}).outputText;
const {portalApi,advancePortalSession}=await import('data:text/javascript;base64,'+Buffer.from(compiled).toString('base64'));
test('API do portal: recupera consultas temporariamente indisponíveis e não repete cadastros',async()=>{
 const original=globalThis.fetch;let calls=0;
 try{
  globalThis.fetch=async()=>{calls++;return calls===1?new Response('',{status:502}):Response.json({minAge:4,maxAge:19});};
  assert.deepEqual(await portalApi('/settings'),{minAge:4,maxAge:19});assert.equal(calls,2);
  calls=0;globalThis.fetch=async()=>{calls++;if(calls===1)throw new TypeError('fetch failed');return Response.json([]);};
  assert.deepEqual(await portalApi('/schools'),[]);assert.equal(calls,2);
  calls=0;globalThis.fetch=async()=>{calls++;return new Response('',{status:502});};
  await assert.rejects(portalApi('/register',{name:'Teste'}),/confirmar o envio/);assert.equal(calls,1);
  calls=0;globalThis.fetch=async()=>{calls++;throw new TypeError('fetch failed');};
  await assert.rejects(portalApi('/return',{code:'test'}),/confirmar o envio/);assert.equal(calls,1);
  calls=0;globalThis.fetch=async()=>{calls++;return Response.json({error:'Confira os dados.'},{status:400});};
  await assert.rejects(portalApi('/register',{}),/Confira os dados/);assert.equal(calls,1);
  calls=0;globalThis.fetch=async()=>{calls++;return Response.json({error:'Configure SUPABASE_URL.'},{status:503});};
  await assert.rejects(portalApi('/settings'),/identificação ainda está sendo preparado/);assert.equal(calls,1);
 }finally{globalThis.fetch=original;}
});

test('sessões: requisições selecionam aluno ou administrador pela área atual',async()=>{
 const fetchOriginal=globalThis.fetch,windowOriginal=globalThis.window;const contexts=[];
 try{
  globalThis.fetch=async(_url,options)=>{contexts.push(options.headers['X-Clube-Context']);return Response.json({});};
  globalThis.window={location:{hash:'#/admin/alunos',pathname:'/'}};
  await portalApi('/session');await portalApi('/logout',{});await portalApi('/return',{code:'DZR35E'});
  globalThis.window.location.hash='#/leitura';await portalApi('/session');await portalApi('/admin/overview');
  await portalApi('/events/admin?search=');await portalApi('/events/admin/event-id/recipients');await portalApi('/events/mine');
  assert.deepEqual(contexts,['admin','admin','student','student','admin','admin','admin','student']);
 }finally{globalThis.fetch=fetchOriginal;if(windowOriginal===undefined)delete globalThis.window;else globalThis.window=windowOriginal;}
});

test('401 na conquista pede identificação novamente sem repetir o POST',async()=>{
 const originalFetch=globalThis.fetch,originalWindow=globalThis.window,originalEvent=globalThis.CustomEvent;let calls=0;const events=[];
 try{
  globalThis.CustomEvent=class{constructor(type,options){this.type=type;this.detail=options.detail;}};
  globalThis.window={location:{hash:'#/atividade/teste',pathname:'/'},dispatchEvent:event=>{events.push(event);return true;}};
  globalThis.fetch=async()=>{calls++;return Response.json({error:'Identifique-se para acessar sua leitura.'},{status:401});};
  await assert.rejects(portalApi('/reading/achievements/06aa8275-0cd1-4d1c-b028-5bbe5dcad63d/claim',{}),/Identifique-se/);assert.equal(calls,1);assert.equal(events.length,1);assert.equal(events[0].type,'clube:session-expired');assert.deepEqual(events[0].detail,{context:'student'});
  events.length=0;await assert.rejects(portalApi('/admin/login',{email:'teste@example.test',password:'errada'}));assert.equal(events.length,0,'Senha inválida não encerra outra sessão');
 }finally{globalThis.fetch=originalFetch;if(originalWindow===undefined)delete globalThis.window;else globalThis.window=originalWindow;if(originalEvent===undefined)delete globalThis.CustomEvent;else globalThis.CustomEvent=originalEvent;}
});


test('resposta 401 atrasada n?o encerra o novo login',async()=>{
 const previousFetch=globalThis.fetch,previousWindow=globalThis.window,previousEvent=globalThis.CustomEvent;const events=[];let release;
 try{
  globalThis.CustomEvent=class{constructor(type,options){this.type=type;this.detail=options.detail;}};
  globalThis.window={location:{hash:'#/leitura',pathname:'/'},dispatchEvent:event=>{events.push(event);return true;}};
  globalThis.fetch=async url=>url.endsWith('/return')?Response.json({student:{id:'novo'}}):new Promise(resolve=>{release=resolve;});
  const pending=assert.rejects(portalApi('/reading/state'),/Identifique-se/);
  await portalApi('/return',{code:'DZR35E'});
  release(Response.json({error:'Identifique-se'},{status:401}));await pending;
  assert.equal(events.length,0,'401 da identidade anterior n?o deve expirar a nova sess?o');
  globalThis.fetch=async()=>Response.json({error:'Identifique-se'},{status:401});
  await assert.rejects(portalApi('/session'));assert.equal(events.length,0,'Verifica??o da sess?o n?o gera eventos recursivos');
  advancePortalSession();
 }finally{globalThis.fetch=previousFetch;if(previousWindow===undefined)delete globalThis.window;else globalThis.window=previousWindow;if(previousEvent===undefined)delete globalThis.CustomEvent;else globalThis.CustomEvent=previousEvent;}
});

test('consultas simultâneas compartilham a requisição, sem cache permanente nem reaproveitar leitura anterior a um envio',async()=>{
 const previousFetch=globalThis.fetch;let calls=0,release;
 try{
  globalThis.fetch=async()=>{calls++;return new Promise(resolve=>{release=resolve;});};
  const first=portalApi('/reading/state'),second=portalApi('/reading/state');assert.equal(first,second);assert.equal(calls,1);
  release(Response.json({value:'initial'}));assert.deepEqual(await first,{value:'initial'});await second;
  const stale=portalApi('/reading/state');assert.equal(calls,2);const oldRelease=release;
  globalThis.fetch=async()=>{calls++;return Response.json({value:'updated'});};
  await portalApi('/reading/attempts/test/finish',{});assert.deepEqual(await portalApi('/reading/state'),{value:'updated'});
  oldRelease(Response.json({value:'stale'}));assert.deepEqual(await stale,{value:'stale'});assert.equal(calls,4);
 }finally{globalThis.fetch=previousFetch;}
});

test('métodos de edição e exclusão usam o cliente único sem repetição automática',async()=>{
 const previousFetch=globalThis.fetch;const methods=[];
 try{globalThis.fetch=async(_url,options)=>{methods.push(options.method);return Response.json({error:'falha de confirmação'},{status:503});};
  await assert.rejects(portalApi('/admin/manage/stories/one',{title:'Um'},'PUT'));
  await assert.rejects(portalApi('/admin/manage/stories/one',undefined,'DELETE'));
  assert.deepEqual(methods,['PUT','DELETE']);
 }finally{globalThis.fetch=previousFetch;}
});
