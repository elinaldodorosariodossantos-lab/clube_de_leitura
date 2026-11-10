import {test} from 'node:test';
import assert from 'node:assert/strict';
import {readFile} from 'node:fs/promises';
import {PGlite} from '../../.qa/postgres/node_modules/@electric-sql/pglite/dist/index.js';

test('sequência direta: ordem, reordenação, retomada, publicação, isolamento e finalização',async()=>{
 const db=new PGlite(),uid='00000000-0000-4000-8000-000000000001';
 const call=async(op,args={})=>(await db.query('select public.clube_leitura($1,$2::jsonb) as data',[op,JSON.stringify(args)])).rows[0].data;
 const login=async()=>{await db.query("select set_config('request.jwt.claim.sub',$1,false),set_config('request.jwt.claims',$2,false)",[uid,JSON.stringify({sub:uid,is_anonymous:true})]);await db.exec('set role authenticated');};
 const edit=async sql=>{await db.exec('reset role');await db.exec(sql);await login();};
 const enter=async level=>call('enter',{level});
 async function finish(a){await call('stage',{id:a.id,stage:'questoes'});for(const q of a.activity.questions)await call('answer',{id:a.id,questionId:q.id,selected:0});const result=await call('finish',{id:a.id});assert.deepEqual(await call('finish',{id:a.id}),result);return result;}
 try{
  await db.exec(`create role anon;create role authenticated;create schema auth;create table auth.users(id uuid primary key);insert into auth.users values('${uid}');
   create function auth.uid() returns uuid language sql stable as $$select nullif(current_setting('request.jwt.claim.sub',true),'')::uuid$$;
   create function auth.jwt() returns jsonb language sql stable as $$select coalesce(nullif(current_setting('request.jwt.claims',true),''),'{}')::jsonb$$;grant usage on schema auth to anon,authenticated;`);
  for(const f of ['202610120001_clube.sql','202610140001_portal.sql','202610150001_leitura.sql','202610150002_admin.sql','202610190001_progressao.sql','202610190002_sequencia.sql'])await db.exec(await readFile(new URL('../migrations/'+f,import.meta.url),'utf8'));
  await login();await db.query("select public.clube_portal('register',$1::jsonb)",[JSON.stringify({name:'Aluno de Teste',age:7,school:'Escola de Teste'})]);
  assert.equal((await call('state')).sequenceReady,true);
  await assert.rejects(enter('dificil'),e=>e.code==='42501');
  await assert.rejects(db.query("select clube_private.clube_leitura('start','{}')"),e=>e.code==='42501');
  await edit(`update public.textos set ordem=50 where id='passarinho';
   insert into public.textos(id,titulo,conteudo,faixa_etaria,nivel,ordem,obrigatorio,ativo) values
   ('segunda','Segunda','Texto local de teste','6 a 8 anos','facil',20,true,true),
   ('primeira','Primeira','Texto local de teste','6 a 8 anos','facil',10,true,true),
   ('opcional','Opcional','Texto local de teste','6 a 8 anos','facil',0,false,true),
   ('rascunho','Rascunho','Texto local de teste','6 a 8 anos','facil',0,true,false);
   insert into public.questoes(id,texto_id,enunciado,alternativas) values(401,'primeira','Teste','["a","b","c","d"]'),(402,'segunda','Teste','["a","b","c","d"]'),(403,'opcional','Teste','["a","b","c","d"]'),(404,'rascunho','Teste','["a","b","c","d"]');
   insert into clube_private.gabaritos values(401,0),(402,0),(403,0),(404,0);`);
  await assert.rejects(call('start',{level:'facil',storyId:'segunda'}),e=>e.code==='42501');
  let a=(await enter('facil')).attempt;assert.equal(a.activity.id,'primeira');assert.equal(a.result,null);
  assert.equal((await enter('facil')).attempt.id,a.id,'Reentrada não duplica tentativas');
  await call('stage',{id:a.id,stage:'questoes'});await call('answer',{id:a.id,questionId:401,selected:0});
  await edit("update public.textos set ordem=1 where id='segunda'");
  assert.equal((await enter('facil')).attempt.id,a.id,'Reordenação preserva leitura aberta');
  assert.equal((await enter('facil')).attempt.answers['401'],0);
  await finish(a);a=(await enter('facil')).attempt;assert.equal(a.activity.id,'segunda');
  await edit("update public.textos set ativo=false where id='segunda'");
  await assert.rejects(call('get',{id:a.id}),e=>e.code==='42501');
  let next=(await enter('facil')).attempt;assert.equal(next.activity.id,'passarinho');await finish(next);
  let end=await enter('facil');assert.equal(end.attempt,null);assert.equal(end.levelComplete,true);assert.equal((await call('state')).levels[1].unlocked,true);
  await edit("update public.textos set ativo=true where id='segunda'");assert.equal((await call('state')).levels[1].unlocked,false);
  assert.equal((await enter('facil')).attempt.id,a.id,'Republicação retoma a mesma tentativa');await finish(a);
  for(const level of ['medio','dificil'])await finish((await enter(level)).attempt);
  end=await enter('dificil');assert.equal(end.journeyComplete,true);assert.equal(end.attempt,null);
  const state=await call('state');assert.equal(state.history.length,5);const points=state.student.points;
  assert.equal((await enter('dificil')).attempt,null);assert.equal((await call('state')).student.points,points);
  const cycle=await call('new_journey');assert.equal(cycle.journey.cycle,2);assert.equal(cycle.student.points,points);
  await edit("update public.textos set ativo=false where nivel='facil'");
  end=await enter('facil');assert.equal(end.empty,true);assert.equal(end.levelComplete,false);assert.equal(end.attempt,null);
  await db.exec('reset role;set role anon');await assert.rejects(enter('facil'),e=>e.code==='42501');
 }finally{await db.close();}
});
