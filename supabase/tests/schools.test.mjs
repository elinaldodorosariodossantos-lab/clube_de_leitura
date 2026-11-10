import {beforeEventSchools} from './fixtures/before-event-schools.mjs';
import {test} from 'node:test';
import assert from 'node:assert/strict';
import {readFile} from 'node:fs/promises';
import {randomUUID} from 'node:crypto';
import {PGlite} from '../../.qa/postgres/node_modules/@electric-sql/pglite/dist/index.js';

test('painel escolas: filtros, datas locais, idade, codigo, paginacao, resultados e autorizacao',async()=>{
 const db=new PGlite(),admin=randomUUID(),student=randomUUID();
 const identity=async(id,anonymous)=>{await db.exec('reset role');await db.query("select set_config('request.jwt.claim.sub',$1,false),set_config('request.jwt.claims',$2,false)",[id,JSON.stringify({sub:id,is_anonymous:anonymous})]);await db.exec('set role authenticated');};
 const rpc=async(fn,op,args={})=>(await db.query(`select public.${fn}($1,$2::jsonb) as data`,[op,JSON.stringify(args)])).rows[0].data;
 try{
  await db.exec(`create role anon;create role authenticated;create schema auth;create table auth.users(id uuid primary key,is_anonymous boolean default true);
  create function auth.uid() returns uuid language sql stable as $$select nullif(current_setting('request.jwt.claim.sub',true),'')::uuid$$;
  create function auth.jwt() returns jsonb language sql stable as $$select coalesce(nullif(current_setting('request.jwt.claims',true),''),'{}')::jsonb$$;grant usage on schema auth to anon,authenticated;`);
  for(const name of ['202610120001_clube.sql','202610140001_portal.sql','202610150001_leitura.sql','202610150002_admin.sql','202610190001_progressao.sql','202610190002_sequencia.sql'])await db.exec(await readFile(new URL('../migrations/'+name,import.meta.url),'utf8'));
  await db.exec(await readFile(new URL('../instalar-eventos.sql',import.meta.url),'utf8').then(beforeEventSchools));
  await db.exec(await readFile(new URL('../instalar-eventos.sql',import.meta.url),'utf8').then(beforeEventSchools));
  await db.query('insert into auth.users values($1,false),($2,true)',[admin,student]);await db.query("insert into public.perfis(id,nome,papel) values($1,'Admin','admin')",[admin]);
  await identity(admin,false);
  const dashboard=args=>rpc('clube_escolas','dashboard',args);
  assert.equal((await dashboard()).total,0);assert.equal((await dashboard()).summary.completed,0);
  const sol=await rpc('clube_gestao','school_save',{name:'Escola Sol'}),lua=await rpc('clube_gestao','school_save',{name:'Escola Lua'});
  const ids=[];
  for(let i=0;i<23;i++){
   const uid=i===0?student:randomUUID();if(i){await db.exec('reset role');await db.query('insert into auth.users(id) values($1)',[uid]);}
   await identity(uid,true);const registered=await rpc('clube_portal','register',{name:'Aluno Escola '+String(i).padStart(2,'0'),age:19,school:'Escola Sol',className:i%2?'2 ano':'1 ano'});ids.push(registered.student.id);
   await db.exec('reset role');await db.query("update public.alunos set data_nascimento=case when $2=22 then null else (clube_private.hoje_leitura()-make_interval(years=>7+($2%2)))::date end,escola_id=case when $2=22 then null when $2%2=0 then $3::uuid else $4::uuid end,criado_em=((clube_private.hoje_leitura()-$2)::timestamp at time zone 'America/Fortaleza')+interval '12 hours' where id=$1",[registered.student.id,i,sol.id,lua.id]);
  }
  await identity(admin,false);
  let d=await dashboard();assert.equal(d.total,23);assert.equal(d.students.length,20);assert.equal(d.summary.schools,2);assert.equal(d.students[0].age,7,'Idade manual 19 ignorada');
  assert.equal((await dashboard({page:2})).students.length,3);
  assert.equal((await dashboard({sort:'created_asc',pageSize:1})).students[0].id,ids[22]);
  assert.equal((await dashboard({sort:'name_desc',pageSize:1})).students[0].id,ids[22]);
  assert.equal((await dashboard({schoolId:sol.id})).total,11);assert.equal((await dashboard({schoolId:lua.id})).total,11);
  assert.equal((await dashboard({schoolId:'none'})).students[0].id,ids[22]);
  assert.equal((await dashboard({age:8})).total,11);assert.equal((await dashboard({className:'1 ano'})).total,12);
  assert.equal((await dashboard({schoolId:sol.id,age:7,className:'1 ano',search:'Escola 00'})).total,1);
  assert.equal((await dashboard({search:'inexistente'})).summary.completed,0);
  assert.equal((await dashboard({period:'today'})).total,1);assert.equal((await dashboard({period:'7days'})).total,7);assert.equal((await dashboard({period:'30days'})).total,23);
  await db.exec('reset role');const dates=(await db.query("select (clube_private.hoje_leitura()-10)::text first,(clube_private.hoje_leitura()-5)::text last")).rows[0];await identity(admin,false);
  assert.equal((await dashboard({period:'custom',from:dates.first,to:dates.last})).total,6);
  await assert.rejects(dashboard({period:'custom',from:dates.last,to:dates.first}),e=>e.code==='22023');
  await assert.rejects(dashboard({page:0}),e=>e.code==='22023');
  // Bordas do dia em Fortaleza: 02:59 UTC ainda é o dia anterior.
  await db.exec('reset role');await db.query("update public.alunos set criado_em=(clube_private.hoje_leitura()::timestamp at time zone 'America/Fortaleza')-interval '1 second' where id=$1",[ids[0]]);await identity(admin,false);assert.equal((await dashboard({period:'today'})).total,0);
  await db.exec('reset role');await db.query("update clube_private.acessos set codigo_curto_hash=encode(sha256(convert_to('DZR35E','UTF8')),'hex'),credencial_cifrada='test' where aluno_id=$1",[ids[0]]);const codeHash=(await db.query("select encode(sha256(convert_to('DZR35E','UTF8')),'hex') hash")).rows[0].hash;await identity(admin,false);
  assert.equal((await dashboard({search:'DZR35E',codeHash})).students[0].id,ids[0]);
  assert.equal((await rpc('clube_escolas','student',{id:ids[22]})).student.age,null);
  await identity(student,true);await assert.rejects(dashboard(),e=>e.code==='42501');await assert.rejects(rpc('clube_escolas','student',{id:ids[1]}),e=>e.code==='42501');await assert.rejects(rpc('clube_escolas','responses',{id:ids[0]}),e=>e.code==='42501');
  // Gera uma conclusão real e verifica os mesmos totais e respostas validados.
  const attempt=(await rpc('clube_leitura','enter',{level:'facil'})).attempt;
  await rpc('clube_leitura','stage',{id:attempt.id,stage:'questoes'});
  for(const q of attempt.activity.questions)await rpc('clube_leitura','answer',{id:attempt.id,questionId:q.id,selected:0});
  const finished=await rpc('clube_leitura','finish',{id:attempt.id});
  await identity(admin,false);d=await dashboard({search:'Escola 00'});assert.equal(d.summary.completed,1);assert.equal(d.summary.points,finished.result.points);
  const detail=await rpc('clube_escolas','student',{id:ids[0]});assert.equal(detail.student.age,7);assert.equal(detail.attempts.length,1);
  const answers=await rpc('clube_escolas','responses',{id:ids[0],pageSize:2});assert.equal(answers.total,attempt.activity.questions.length);assert.equal(answers.responses.length,2);assert.equal(answers.responses[0].selected,0);assert.ok(answers.responses[0].prompt);
  assert.equal((await rpc('clube_escolas','responses',{id:ids[0],page:2,pageSize:2})).responses.length,2);
  await db.exec('reset role');await db.query('update public.alunos set excluido_em=now() where id=$1',[ids[22]]);await identity(admin,false);assert.equal((await dashboard()).total,22,'Exclusao logica preservada');
  await db.exec('reset role');await db.exec('set role anon');await assert.rejects(dashboard(),e=>e.code==='42501');
 }finally{await db.close();}
});
