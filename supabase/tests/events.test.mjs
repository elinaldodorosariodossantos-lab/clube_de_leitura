import {beforeEventSchools} from './fixtures/before-event-schools.mjs';
import {legacyContexts} from './fixtures/legacy-policy.mjs';
import {test} from 'node:test';
import assert from 'node:assert/strict';
import {readFile} from 'node:fs/promises';
import {randomUUID,createHash} from 'node:crypto';
import {PGlite} from '../../.qa/postgres/node_modules/@electric-sql/pglite/dist/index.js';
test('eventos: atribuição transacional, sorteios persistentes, leitura, isolamento e histórico',async()=>{
 const db=new PGlite();const admin=randomUUID(),students=[],visitors=[];
 const identity=async(uid,anonymous=true)=>{await db.exec('reset role');await db.query("select set_config('request.jwt.claim.sub',$1,false),set_config('request.jwt.claims',$2,false)",[uid,JSON.stringify({sub:uid,is_anonymous:anonymous})]);await db.exec('set role authenticated');};
 const rpc=async(fn,op,args={})=>(await db.query(`select public.${fn}($1,$2::jsonb) as data`,[op,JSON.stringify(args)])).rows[0].data;
 const events=(op,args)=>rpc('clube_eventos',op,args),manage=(op,args)=>rpc('clube_gestao',op,args),read=(op,args)=>rpc('clube_leitura',op,args);
 const hash=v=>createHash('sha256').update(v).digest('hex');
 try{
  await db.exec(`create role anon;create role authenticated;create schema auth;create table auth.users(id uuid primary key,is_anonymous boolean default true);
  create function auth.uid() returns uuid language sql stable as $$select nullif(current_setting('request.jwt.claim.sub',true),'')::uuid$$;
  create function auth.jwt() returns jsonb language sql stable as $$select coalesce(nullif(current_setting('request.jwt.claims',true),''),'{}')::jsonb$$;grant usage on schema auth to anon,authenticated;`);
  for(const file of ['202610120001_clube.sql','202610140001_portal.sql','202610150001_leitura.sql','202610150002_admin.sql','202610190001_progressao.sql','202610190002_sequencia.sql'])await db.exec(await readFile(new URL('../migrations/'+file,import.meta.url),'utf8'));
  await db.exec(await readFile(new URL('../instalar-eventos.sql',import.meta.url),'utf8').then(beforeEventSchools));await legacyContexts(db);
  await db.exec(await readFile(new URL('../instalar-eventos.sql',import.meta.url),'utf8').then(beforeEventSchools));await legacyContexts(db);
  await db.query('insert into auth.users values($1,false)',[admin]);await db.query("insert into public.perfis values($1,'Admin','admin',now())",[admin]);await identity(admin,false);
  const school=await manage('school_save',{name:'Escola Eventos'});const dates=(await db.query("select (now()-interval '1 day')::text as start,(now()+interval '5 days')::text as finish,(current_date-interval '7 years 1 month')::date::text as birth")).rows[0];
  for(let i=0;i<4;i++){
   const uid=randomUUID(),visitor=randomUUID();await db.exec('reset role');await db.query('insert into auth.users(id) values($1),($2)',[uid,visitor]);await identity(admin,false);
   const code='AA2BB'+(i+2);const s=await manage('student_save',{name:'Leitor Evento '+i,birthDate:dates.birth,guardian:'Pessoa Responsável',schoolId:school.id,className:'2º ano',profileId:uid,tokenHash:hash('token'+i),shortHash:hash(code),encrypted:'cifrado'});students.push({...s,code});visitors.push(visitor);
  }
  const storyIds=[];for(let i=0;i<3;i++){
   const story=await manage('story_save',{id:'evento-historia-'+i,title:'História de evento '+i,author:'Autor',age:'6 a 8 anos',level:'facil',active:true,required:false,ordering:i,content:'Texto para o evento.',cover:'',summary:'',questions:[{prompt:'Escolha A',options:['A','B','C','D'],correct:0}]});storyIds.push(story.id);
  }
  const input={requestId:randomUUID(),name:'Evento Local',description:'Ler e descobrir',level:'facil',minAge:6,maxAge:8,startsAt:dates.start,endsAt:dates.finish,active:true,mode:'sorteio',quantity:2,storyIds,cover:''};
  await assert.rejects(events('save',{...input,endsAt:dates.start}),e=>e.code==='22023');await assert.rejects(events('save',{...input,minAge:10}),e=>e.code==='22023');await assert.rejects(events('save',{...input,quantity:4}),e=>e.code==='22023');
  await assert.rejects(events('save',{...input,level:'medio'}),e=>e.code==='22023');await assert.rejects(events('save',{...input,storyIds:['inexistente']}),e=>e.code==='22023');
  const event=await events('save',input);assert.equal((await events('save',input)).id,event.id);assert.equal((await events('list')).length,1);const eligible=await events('recipients',{id:event.id});assert.equal(eligible.students.length,4);assert.ok(eligible.students.every(s=>s.age===7&&s.eligible));
  await assert.rejects(events('send',{id:event.id,studentIds:[students[0].id,randomUUID()]}),e=>e.code==='22023');
  assert.deepEqual(await events('send',{id:event.id,studentIds:students.map(s=>s.id)}),{created:4,existing:0});
  assert.deepEqual(await events('send',{id:event.id,studentIds:students.map(s=>s.id)}),{created:0,existing:4});
  await db.exec('reset role');const picks=(await db.query('select assinatura from public.evento_alunos where evento_id=$1 order by enviado_em,id',[event.id])).rows;assert.equal(new Set(picks.map(p=>p.assinatura)).size,3,'Todas as combinações são usadas antes de repetir');
  assert.equal((await db.query('select count(*)::int as n from public.evento_leituras')).rows[0].n,8);
  await identity(visitors[0]);await assert.rejects(events('list'),e=>e.code==='42501');await assert.rejects(events('mine'),e=>e.code==='42501');await assert.rejects(events('enter',{id:event.id}),e=>e.code==='42501');
  await assert.rejects(db.query('select * from public.evento_alunos'),e=>e.code==='42501');await assert.rejects(db.query('select * from clube_private.evento_conteudos'),e=>e.code==='42501');
  await rpc('clube_portal','return',{code:students[0].code});const mine=await events('mine');assert.equal(mine.length,1);assert.ok(!('storyIds' in mine[0]));assert.ok(!('recipients' in mine[0]));
  let entry=await events('enter',{id:event.id});let attempt=entry.attempt;assert.equal(attempt.eventId,event.id);assert.equal(attempt.activity.questions.length,1);
  assert.equal((await events('enter',{id:event.id})).attempt.id,attempt.id);
  await read('stage',{id:attempt.id,stage:'questoes'});await read('answer',{id:attempt.id,questionId:attempt.activity.questions[0].id,selected:0});
  const resumed=await read('get',{id:attempt.id});assert.equal(Object.keys(resumed.answers).length,1);
  await identity(admin,false);await events('status',{id:event.id,active:false});await identity(visitors[0]);assert.deepEqual(await events('mine'),[]);await assert.rejects(read('finish',{id:attempt.id}),e=>e.code==='42501');await assert.rejects(rpc('clube_api','finish',{id:attempt.id}),e=>e.code==='42501');
  await identity(admin,false);await events('status',{id:event.id,active:true});await assert.rejects(events('save',{...input,id:event.id}),e=>e.code==='22023');
  await events('save',{...input,id:event.id,confirmChanges:true,storyIds:[storyIds[2]],quantity:1});
  await identity(visitors[0]);assert.equal((await events('mine'))[0].total,2,'Editar evento não refaz seleções');
  const finished=await read('finish',{id:attempt.id});assert.equal(finished.result.points,10);assert.deepEqual(await read('finish',{id:attempt.id}),finished);
  const next=(await events('enter',{id:event.id})).attempt;assert.notEqual(next.id,attempt.id);await read('stage',{id:next.id,stage:'questoes'});await read('answer',{id:next.id,questionId:next.activity.questions[0].id,selected:0});await read('finish',{id:next.id});assert.equal((await events('enter',{id:event.id})).complete,true);
  assert.equal((await read('state')).student.points,40/3);await identity(visitors[1]);await rpc('clube_portal','return',{code:students[1].code});await assert.rejects(read('get',{id:attempt.id}),e=>e.code==='42501');
  await identity(admin,false);assert.equal((await rpc('clube_admin','overview')).points,40/3);
  const future=await events('save',{...input,requestId:randomUUID(),startsAt:new Date(Date.now()+86400000).toISOString(),endsAt:new Date(Date.now()+172800000).toISOString()});assert.equal(future.status,'programado');
  await events('send',{id:future.id,studentIds:[students[0].id]});await identity(visitors[0]);assert.ok(!(await events('mine')).some(x=>x.id===future.id));await assert.rejects(events('enter',{id:future.id}),e=>e.code==='42501');
  await identity(admin,false);assert.equal((await events('delete',{id:future.id})).archived,true);const empty=await events('save',{...input,requestId:randomUUID()});assert.equal((await events('delete',{id:empty.id})).deleted,true);
  const expired=await events('save',{...input,requestId:randomUUID(),startsAt:new Date(Date.now()-172800000).toISOString(),endsAt:new Date(Date.now()-86400000).toISOString()});assert.equal(expired.status,'encerrado');await events('send',{id:expired.id,studentIds:[students[0].id]});await identity(visitors[0]);await assert.rejects(events('enter',{id:expired.id}),e=>e.code==='42501');await identity(admin,false);
  await manage('student_status',{id:students[3].id,status:'inativo'});await assert.rejects(events('send',{id:expired.id,studentIds:[students[3].id]}),e=>e.code==='22023');
  assert.equal((await events('delete',{id:event.id})).archived,true);await identity(visitors[0]);assert.equal((await read('state')).student.points,40/3);assert.equal((await read('get',{id:attempt.id})).result.points,10);
 }finally{await db.close();}
});
