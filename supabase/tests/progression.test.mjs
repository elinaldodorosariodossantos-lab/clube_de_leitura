import {test} from 'node:test';
import assert from 'node:assert/strict';
import {readFile} from 'node:fs/promises';
import {PGlite} from '../../.qa/postgres/node_modules/@electric-sql/pglite/dist/index.js';

test('progressão dinâmica: publicação, RLS, retomada, pontuação idempotente e ciclos',async()=>{
 const db=new PGlite(),uid='00000000-0000-4000-8000-000000000001';
 const call=async(op,args={})=>(await db.query('select public.clube_leitura($1,$2::jsonb) as data',[op,JSON.stringify(args)])).rows[0].data;
 const login=async()=>{await db.query("select set_config('request.jwt.claim.sub',$1,false),set_config('request.jwt.claims',$2,false)",[uid,JSON.stringify({sub:uid,is_anonymous:true})]);await db.exec('set role authenticated');};
 const publish=async(id,{active=true,required=true}={})=>{await db.exec('reset role');await db.query("insert into public.textos(id,titulo,conteudo,faixa_etaria,nivel,ativo,obrigatorio) values($1,$1,'Texto apenas de teste','6 a 8 anos','facil',$2,$3)",[id,active,required]);await db.query("insert into public.questoes(id,texto_id,enunciado,alternativas) values((select max(id)+1 from public.questoes),$1,'Questão de teste','[\"a\",\"b\",\"c\",\"d\"]')",[id]);await db.query('insert into clube_private.gabaritos select id,0 from public.questoes where texto_id=$1',[id]);await login();};
 async function finish(level,storyId,keys){const a=await call('start',{level,storyId});await call('stage',{id:a.id,stage:'questoes'});for(const [i,q] of a.activity.questions.entries())await call('answer',{id:a.id,questionId:q.id,selected:keys[i]??0});const result=await call('finish',{id:a.id});assert.deepEqual(await call('finish',{id:a.id}),result);return result;}
 try{
  await db.exec(`create role anon;create role authenticated;create schema auth;create table auth.users(id uuid primary key);insert into auth.users values('${uid}');
   create function auth.uid() returns uuid language sql stable as $$select nullif(current_setting('request.jwt.claim.sub',true),'')::uuid$$;
   create function auth.jwt() returns jsonb language sql stable as $$select coalesce(nullif(current_setting('request.jwt.claims',true),''),'{}')::jsonb$$;grant usage on schema auth to anon,authenticated;`);
  for(const f of ['202610120001_clube.sql','202610140001_portal.sql','202610150001_leitura.sql','202610150002_admin.sql','202610190001_progressao.sql'])await db.exec(await readFile(new URL('../migrations/'+f,import.meta.url),'utf8'));
  await login();await db.query("select public.clube_portal('register',$1::jsonb)",[JSON.stringify({name:'Aluna de Teste',age:7,school:'Escola de Teste'})]);
  assert.deepEqual((await call('state')).levels.map(l=>l.unlocked),[true,false,false]);
  assert.equal((await call('stories',{level:'facil'}))[0].id,'passarinho');
  await assert.rejects(call('start',{level:'dificil',storyId:'agua-comunidade'}),e=>e.code==='42501');
  await assert.rejects(call('stories',{level:'medio'}),e=>e.code==='42501');
  assert.equal((await db.query('select * from public.textos')).rows.length,1);
  assert.equal((await db.query('select * from public.questoes')).rows.length,5);
  await publish('rascunho',{active:false});await publish('opcional',{required:false});
  assert.equal((await call('state')).levels[0].required,1);
  const a=await call('start',{level:'facil',storyId:'passarinho'});assert.equal(a.result,null);assert.ok(a.activity.questions.every(q=>!('correct' in q)));
  await call('stage',{id:a.id,stage:'questoes'});await call('answer',{id:a.id,questionId:1,selected:0});assert.equal((await call('get',{id:a.id})).index,1);assert.equal((await call('state')).active.answers['1'],0);
  await assert.rejects(call('start',{level:'facil',storyId:'rascunho'}),e=>e.code==='42501');
  await finish('facil','passarinho',[0,1,1,2,1]);assert.deepEqual((await call('state')).levels.map(l=>l.unlocked),[true,true,false]);
  await finish('medio','biblioteca-bairro',[1,0,2,3,1]);await finish('dificil','agua-comunidade',[0,2,1,3,0]);
  let state=await call('state');assert.equal(state.journey.status,'concluida');assert.equal(state.student.points,225);assert.equal(state.student.completed,3);
  assert.equal((await call('start',{level:'facil',storyId:'passarinho'})).id,a.id,'Revisão não cria nova tentativa');
  await publish('nova-obrigatoria');state=await call('state');assert.equal(state.journey.status,'em_andamento');assert.equal(state.levels[1].unlocked,false);assert.equal(state.student.points,225);
  await assert.rejects(call('new_journey'),e=>e.code==='22023');
  await finish('facil','nova-obrigatoria',[0]);state=await call('state');assert.equal(state.journey.status,'concluida');assert.equal(state.student.points,235);assert.equal(state.history.length,4);
  const next=await call('new_journey');assert.equal(next.journey.cycle,2);assert.equal(next.student.points,235);assert.deepEqual(next.levels.map(l=>l.unlocked),[true,false,false]);assert.ok(next.levels.every(l=>l.completed===0));
  await finish('facil','passarinho',[0,1,1,2,1]);await finish('facil','nova-obrigatoria',[0]);
  const medium=await call('start',{level:'medio',storyId:'biblioteca-bairro'});
  await call('stage',{id:medium.id,stage:'questoes'});await call('answer',{id:medium.id,questionId:201,selected:1});
  await publish('publicacao-durante-leitura');
  await assert.rejects(call('get',{id:medium.id}),e=>e.code==='42501');
  await assert.rejects(call('answer',{id:medium.id,questionId:202,selected:0}),e=>e.code==='42501');
  await finish('facil','publicacao-durante-leitura',[0]);
  assert.equal((await call('state')).active.id,medium.id);assert.equal((await call('get',{id:medium.id})).index,1,'Respostas permanecem após atualização dos requisitos');
  await db.exec('reset role');
  await db.exec(`with original as(select * from public.tentativas where id='${a.id}'), copy as(
   insert into public.tentativas(aluno_id,texto_id,nivel,acertos,pontuacao,percentual,status,concluida_em,jornada_id,etapa)
   select aluno_id,texto_id,nivel,acertos,pontuacao,percentual,status,concluida_em,jornada_id,etapa from original returning id)
   insert into public.respostas(tentativa_id,questao_id,selecionada,correta,pontos) select copy.id,r.questao_id,r.selecionada,r.correta,r.pontos from public.respostas r cross join copy where r.tentativa_id='${a.id}';`);
  await login();assert.equal((await call('state')).student.points,305,'Duplicata histórica não soma pontos novamente');
  await db.exec("reset role;update public.textos set ativo=false where id='passarinho'");await login();
  assert.equal((await call('get',{id:a.id})).activity.content,'','História despublicada não reabre texto, mas preserva resultado');
  assert.ok(!(await call('stories',{level:'facil'})).some(s=>s.id==='passarinho'));
  await db.exec('reset role;set role anon');await assert.rejects(call('state'),e=>e.code==='42501');
 }finally{await db.close();}
});
