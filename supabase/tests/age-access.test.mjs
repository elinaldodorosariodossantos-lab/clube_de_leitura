import {beforeEventSchools} from './fixtures/before-event-schools.mjs';
import {legacyContexts} from './fixtures/legacy-policy.mjs';
import {test} from 'node:test';
import assert from 'node:assert/strict';
import {readFile} from 'node:fs/promises';
import {randomUUID} from 'node:crypto';
import {PGlite} from '../../.qa/postgres/node_modules/@electric-sql/pglite/dist/index.js';

test('idade confiavel: aniversarios, limites, RLS, URLs, eventos e preservacao',async()=>{
 const db=new PGlite(),admin=randomUUID(),student=randomUUID();
 const identity=async(id,anonymous)=>{await db.exec('reset role');await db.query("select set_config('request.jwt.claim.sub',$1,false),set_config('request.jwt.claims',$2,false)",[id,JSON.stringify({sub:id,is_anonymous:anonymous})]);await db.exec('set role authenticated');};
 const rpc=async(fn,op,args={})=>(await db.query(`select public.${fn}($1,$2::jsonb) as data`,[op,JSON.stringify(args)])).rows[0].data;
 try{
  await db.exec(`create role anon;create role authenticated;create schema auth;create table auth.users(id uuid primary key,is_anonymous boolean default true);
  create function auth.uid() returns uuid language sql stable as $$select nullif(current_setting('request.jwt.claim.sub',true),'')::uuid$$;
  create function auth.jwt() returns jsonb language sql stable as $$select coalesce(nullif(current_setting('request.jwt.claims',true),''),'{}')::jsonb$$;grant usage on schema auth to anon,authenticated;`);
  for(const name of ['202610120001_clube.sql','202610140001_portal.sql','202610150001_leitura.sql','202610150002_admin.sql','202610190001_progressao.sql','202610190002_sequencia.sql'])await db.exec(await readFile(new URL('../migrations/'+name,import.meta.url),'utf8'));
  await db.exec(await readFile(new URL('../instalar-eventos.sql',import.meta.url),'utf8').then(beforeEventSchools));await legacyContexts(db);
  await db.exec(await readFile(new URL('../instalar-eventos.sql',import.meta.url),'utf8').then(beforeEventSchools));await legacyContexts(db);
  await db.query('insert into auth.users values($1,false),($2,true)',[admin,student]);await db.query("insert into public.perfis(id,nome,papel) values($1,'Admin','admin')",[admin]);
  await identity(admin,false);
  const book=(id,age)=>({id,title:'Livro '+id,author:'Escola',age,level:'facil',ordering:0,active:true,required:true,questions:[{prompt:'Escolha',options:['Sim','Nao'],correct:0}],pages:[{id:randomUUID(),text:'Conteudo '+id,image:''}]});
  for(const item of [book('cinco','5 anos'),book('faixa','5 a 7 anos'),book('oito','8 a 10 anos')])await rpc('clube_gestao','story_save',item);
  await assert.rejects(rpc('clube_gestao','story_save',book('invalida','qualquer idade')));
  await db.exec('reset role');await db.exec("update public.textos set ativo=false where id not in ('cinco','faixa','oito')");
  const calc=async(birth,reference)=>(await db.query('select clube_private.idade_em($1::date,$2::date) age',[birth,reference])).rows[0].age;
  assert.equal(await calc('2021-10-22','2026-10-23'),5);
  assert.equal(await calc('2021-10-24','2026-10-23'),4);
  assert.equal(await calc('2021-10-24','2026-10-24'),5);
  assert.equal(await calc(null,'2026-10-23'),null);
  assert.equal(await calc('2027-01-01','2026-10-23'),null);
  assert.equal(await calc('infinity','2026-10-23'),null);
  await identity(student,true);
  const sid=(await rpc('clube_portal','register',{name:'Aluno Idade',age:19,school:'Escola Idade',className:'1 ano'})).student.id;
  const setAge=async(age)=>{await db.exec('reset role');await db.query("update public.alunos set data_nascimento=(clube_private.hoje_leitura()-make_interval(years=>$2))::date where id=$1",[sid,age]);await identity(student,true);};
  assert.match((await rpc('clube_leitura','state')).ageAccessError,/nascimento/);
  await assert.rejects(rpc('clube_leitura','enter',{level:'facil'}),/nascimento/);
  await setAge(5);
  assert.equal((await rpc('clube_leitura','state')).student.age,5,'Idade manual 19 ignorada');
  assert.deepEqual((await db.query('select id from public.textos order by id')).rows.map(x=>x.id),['cinco','faixa']);
  await assert.rejects(rpc('clube_leitura','enter',{level:'facil',storyId:'oito',age:9}));
  const attempt=(await rpc('clube_leitura','enter',{level:'facil'})).attempt;
  await setAge(7);
  assert.deepEqual((await db.query('select id from public.textos order by id')).rows.map(x=>x.id),['faixa'],'Limite maximo incluso');
  await assert.rejects(rpc('clube_leitura','get',{id:attempt.id}),/idade/);
  await assert.rejects(rpc('clube_leitura','answer',{id:attempt.id,questionId:attempt.activity.questions[0].id,selected:0}),/idade/);
  await setAge(8);
  assert.deepEqual((await db.query('select id from public.textos order by id')).rows.map(x=>x.id),['oito']);
  await setAge(5);
  assert.equal((await rpc('clube_leitura','get',{id:attempt.id})).id,attempt.id,'Progresso preservado');
  await identity(admin,false);
  const dates=(await db.query("select (now()-interval '1 hour')::text start,(now()+interval '1 day')::text finish")).rows[0];
  const eventData={name:'Evento Idades',description:'Faixas distintas',startsAt:dates.start,endsAt:dates.finish,active:true,ageConfigs:[{age:5,levels:[{level:'facil',quantity:2,storyIds:['cinco','faixa']}]},{age:8,levels:[{level:'facil',quantity:1,storyIds:['oito']}]}]};
  await assert.rejects(rpc('clube_eventos','save',{...eventData,requestId:randomUUID(),ageConfigs:[{age:5,levels:[{level:'facil',quantity:2,storyIds:['cinco','oito']}]}]}));
  await assert.rejects(rpc('clube_eventos','save',{...eventData,requestId:randomUUID(),ageConfigs:[{age:5,levels:[{level:'facil',quantity:3,storyIds:['cinco','faixa']}]}]}));
  const event=await rpc('clube_eventos','save',{...eventData,requestId:randomUUID()});
  assert.equal((await rpc('clube_eventos','send',{id:event.id,studentIds:[sid]})).created,1);
  assert.equal((await rpc('clube_eventos','send',{id:event.id,studentIds:[sid]})).existing,1);
  await db.exec('reset role');
  const assigned=async()=>(await db.query('select l.id,l.texto_id from public.evento_leituras l join public.evento_alunos p on p.id=l.participante_id where p.evento_id=$1 order by l.id',[event.id])).rows;
  const original=await assigned();assert.equal(original.length,2);assert.ok(original.every(x=>['cinco','faixa'].includes(x.texto_id)));
  await identity(student,true);
  assert.equal((await rpc('clube_eventos','mine')).length,1);
  const ea=(await rpc('clube_eventos','enter',{id:event.id})).attempt;
  assert.equal((await rpc('clube_eventos','enter',{id:event.id})).attempt.id,ea.id);
  await setAge(6);
  assert.equal((await rpc('clube_eventos','mine')).length,0);
  await assert.rejects(rpc('clube_eventos','enter',{id:event.id}));
  await assert.rejects(rpc('clube_leitura','get',{id:ea.id}));
  await db.exec('reset role');assert.deepEqual(await assigned(),original,'Aniversario nao redistribui historias');
  await db.query('update public.alunos set data_nascimento=null where id=$1',[sid]);await identity(student,true);
  assert.deepEqual((await rpc('clube_leitura','state')).levels,[]);
  assert.equal((await db.query('select id from public.textos')).rows.length,0);
  await assert.rejects(db.query('update public.alunos set data_nascimento=current_date where id=$1',[sid]));
  await db.exec('reset role');
  await db.query("update public.alunos set data_nascimento='2021-10-24' where id=$1",[sid]);
  // Simula a virada da data no servidor, sem alterar cadastro nem idade manual.
  await db.exec("create or replace function clube_private.hoje_leitura() returns date language sql stable set search_path='' as $$select date '2026-10-23'$$");
  await identity(student,true);assert.equal((await rpc('clube_leitura','state')).student.age,4);
  assert.equal((await db.query('select id from public.textos')).rows.length,0);
  await db.exec('reset role');
  await db.exec("create or replace function clube_private.hoje_leitura() returns date language sql stable set search_path='' as $$select date '2026-10-24'$$");
  await identity(student,true);assert.equal((await rpc('clube_leitura','state')).student.age,5);
  assert.equal((await db.query('select id from public.textos')).rows.length,2);
  // Codigo curto e credencial do link/QR usam o mesmo cadastro confiavel no login.
  await db.exec('reset role');
  const shortCode='DZR35E',linkToken='a'.repeat(64);
  await db.query("update clube_private.acessos set codigo_hash=encode(sha256(convert_to($2,'UTF8')),'hex'),codigo_curto_hash=encode(sha256(convert_to($3,'UTF8')),'hex'),credencial_cifrada='teste' where aluno_id=$1",[sid,linkToken,shortCode]);
  for(const [channel,code] of [['codigo',shortCode],['link',linkToken],['qr',linkToken]]){
   for(const [birth,expectedAge,available] of [['2021-10-24',5,2],['2022-10-24',4,0],[null,null,0]]){
    await db.exec('reset role');
    await db.query('update public.alunos set data_nascimento=$2::date where id=$1',[sid,birth]);
    const visitor=randomUUID();await db.query('insert into auth.users(id) values($1)',[visitor]);await identity(visitor,true);
    const login=await rpc('clube_portal','return',{code,age:19});
    assert.equal(login.student.id,sid,channel);assert.equal(login.student.age,expectedAge,channel+' calcula idade no login');
    const state=await rpc('clube_leitura','state');
    assert.equal((await db.query('select id from public.textos')).rows.length,available,channel+' filtra historias');
    if(!available){assert.deepEqual(state.levels,[]);await assert.rejects(rpc('clube_leitura','enter',{level:'facil'}));}
    if(birth===null)assert.match(state.ageAccessError,/nascimento/);
   }
  }
 }finally{await db.close();}
});

