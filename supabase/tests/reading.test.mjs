import {test} from 'node:test';
import assert from 'node:assert/strict';
import {readFile} from 'node:fs/promises';
import {PGlite} from '../../.qa/postgres/node_modules/@electric-sql/pglite/dist/index.js';

test('PostgreSQL: migrações, sessão, níveis, retomada, isolamento, correção e novos ciclos',async()=>{
 const db=new PGlite();
 const first='00000000-0000-4000-8000-000000000001',second='00000000-0000-4000-8000-000000000002',returning='00000000-0000-4000-8000-000000000003';
 async function identify(uid){await db.exec('reset role');await db.query("select set_config('request.jwt.claim.sub',$1,false),set_config('request.jwt.claims',$2,false)",[uid,JSON.stringify({sub:uid,is_anonymous:true})]);await db.exec('set role authenticated');}
 async function call(op,args={}){const r=await db.query('select public.clube_leitura($1,$2::jsonb) as data',[op,JSON.stringify(args)]);return r.rows[0].data;}
 async function register(uid,name){await identify(uid);return (await db.query("select public.clube_portal('register',$1::jsonb) as data",[JSON.stringify({name,age:7,school:'Escola de teste',className:'2º A'})])).rows[0].data;}
 try{
  await db.exec(`create role anon;create role authenticated;create schema auth;create table auth.users(id uuid primary key);
   create function auth.uid() returns uuid language sql stable as $$select nullif(current_setting('request.jwt.claim.sub',true),'')::uuid$$;
   create function auth.jwt() returns jsonb language sql stable as $$select coalesce(nullif(current_setting('request.jwt.claims',true),''),'{}')::jsonb$$;
   grant usage on schema auth to anon,authenticated;
   insert into auth.users values('${first}'),('${second}'),('${returning}');`);
  for(const migration of ['202610120001_clube.sql','202610140001_portal.sql','202610150001_leitura.sql'])await db.exec(await readFile(new URL('../migrations/'+migration,import.meta.url),'utf8'));
  const registered=await register(first,'Ana Leitora');
  const initial=await call('state');assert.equal(initial.student.points,0);assert.equal(initial.student.completed,0);assert.equal(initial.levels.length,3);assert.ok(initial.levels.every(l=>l.available===1));
  const start=await call('start',{level:'dificil'});assert.equal(start.level,'dificil');assert.equal(start.stage,'leitura');assert.equal(start.result,null);assert.ok(start.activity.questions.every(q=>!('correct' in q)));
  assert.equal((await call('start',{level:'facil'})).id,start.id,'Não cria outra atividade enquanto há uma aberta');
  await assert.rejects(call('new_journey'),e=>e.code==='22023');
  await call('stage',{id:start.id,stage:'questoes'});
  const firstQuestion=start.activity.questions[0];
  const answered=await call('answer',{id:start.id,questionId:firstQuestion.id,selected:0});assert.equal(answered.index,1);assert.equal(answered.answers[firstQuestion.id],0);
  const resumed=await call('state');assert.equal(resumed.active.id,start.id);assert.equal(resumed.active.index,1);assert.equal(resumed.active.stage,'questoes');assert.equal(resumed.active.answers[firstQuestion.id],0);assert.equal(resumed.active.result,null);
  await assert.rejects(call('finish',{id:start.id}),e=>e.code==='22023');
  await assert.rejects(call('answer',{id:start.id,questionId:1,selected:0}),e=>e.code==='22023');
  await assert.rejects(call('answer',{id:start.id,questionId:firstQuestion.id,selected:9}),e=>e.code==='22023');
  const other=await register(second,'Bruno Leitor');assert.notEqual(other.student.id,registered.student.id);
  assert.equal((await call('state')).student.points,0);assert.equal((await call('state')).active,null);
  await assert.rejects(call('get',{id:start.id}),e=>e.code==='42501');
  await assert.rejects(call('answer',{id:start.id,questionId:firstQuestion.id,selected:0}),e=>e.code==='42501');
  await assert.rejects(db.query('select * from clube_private.gabaritos'),e=>e.code==='42501');
  await assert.rejects(db.query('select * from public.jornadas'),e=>e.code==='42501');
  await identify(returning);
  const restored=(await db.query("select public.clube_portal('return',$1::jsonb) as data",[JSON.stringify({code:registered.code})])).rows[0].data;
  assert.equal(restored.student.id,registered.student.id);assert.equal((await call('state')).active.index,1);
  await identify(first);await assert.rejects(call('state'),e=>e.code==='42501');await identify(returning);
  const keys={dificil:[0,2,1,3,0],facil:[0,1,1,2,1],medio:[1,0,2,3,1]};
  let last;
  for(const level of ['dificil','facil','medio']){
   const a=await call('start',{level});await call('stage',{id:a.id,stage:'questoes'});
   for(const [i,q] of a.activity.questions.entries())await call('answer',{id:a.id,questionId:q.id,selected:keys[level][i]});
   const finished=await call('finish',{id:a.id});assert.equal(finished.result.hits,5);assert.equal(finished.result.points,level==='facil'?50:level==='medio'?75:100);assert.equal(finished.stage,'resultado');
   assert.deepEqual(await call('finish',{id:a.id}),finished,'Finalização repetida não duplica pontos');
   await assert.rejects(call('answer',{id:a.id,questionId:a.activity.questions[0].id,selected:1}),e=>e.code==='22023');
   last=finished;
  }
  const complete=await call('state');assert.equal(complete.journey.status,'concluida');assert.equal(complete.student.points,225);assert.equal(complete.student.completed,3);assert.equal(complete.history.length,3);assert.equal(complete.active,null);
  await assert.rejects(call('start',{level:'facil'}),e=>e.code==='22023');
  const unchanged=await call('state');assert.equal(unchanged.journey.cycle,1);assert.equal(unchanged.student.points,225);
  const next=await call('new_journey');assert.equal(next.journey.cycle,2);assert.equal(next.journey.status,'preparacao');assert.equal(next.student.points,225);assert.equal(next.history.length,3);assert.ok(next.levels.every(l=>l.completed===0));
  await assert.rejects(call('new_journey'),e=>e.code==='22023');
  assert.deepEqual(await call('get',{id:last.id}),last,'Resultados anteriores continuam acessíveis');
  const fresh=await call('start',{level:'dificil'});assert.notEqual(fresh.id,start.id);assert.equal(Object.keys(fresh.answers).length,0);
  await db.exec('reset role;set role anon');await assert.rejects(call('state'),e=>e.code==='42501');
 }finally{await db.close();}
});
