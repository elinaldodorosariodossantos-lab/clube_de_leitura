import {beforeEventSchools} from './fixtures/before-event-schools.mjs';
import {legacyContexts} from './fixtures/legacy-policy.mjs';
import {test} from 'node:test';
import assert from 'node:assert/strict';
import {readFile} from 'node:fs/promises';
import {randomUUID} from 'node:crypto';
import {PGlite} from '../../.qa/postgres/node_modules/@electric-sql/pglite/dist/index.js';

test('conquistas reais: pendências, oito cenários de progressão, sessão e eventos',async t=>{
 const db=new PGlite(),admin=randomUUID(),user=randomUUID();let sid,session=user;
 const identity=async(id,anonymous)=>{await db.exec('reset role');await db.query("select set_config('request.jwt.claim.sub',$1,false),set_config('request.jwt.claims',$2,false)",[id,JSON.stringify({sub:id,is_anonymous:anonymous})]);await db.exec('set role authenticated');};
 const rpc=async(fn,op,args={})=>(await db.query(`select public.${fn}($1,$2::jsonb) data`,[op,JSON.stringify(args)])).rows[0].data;
 const reading=(op,args)=>rpc('clube_leitura',op,args);
 const superuser=async()=>db.exec('reset role');
 const state=()=>reading('state');
 const enter=async level=>(await reading('enter',{level})).attempt;
 async function answerAll(a){await reading('stage',{id:a.id,stage:'questoes'});for(const q of a.activity.questions)await reading('answer',{id:a.id,questionId:q.id,selected:0});}
 async function finish(a){await answerAll(a);return reading('finish',{id:a.id});}
 try{
  await db.exec(`create role anon;create role authenticated;create schema auth;create table auth.users(id uuid primary key,is_anonymous boolean default true);
   create function auth.uid() returns uuid language sql stable as $$select nullif(current_setting('request.jwt.claim.sub',true),'')::uuid$$;
   create function auth.jwt() returns jsonb language sql stable as $$select coalesce(nullif(current_setting('request.jwt.claims',true),''),'{}')::jsonb$$;grant usage on schema auth to anon,authenticated;`);
  for(const name of ['202610120001_clube.sql','202610140001_portal.sql','202610150001_leitura.sql','202610150002_admin.sql','202610190001_progressao.sql','202610190002_sequencia.sql'])await db.exec(await readFile(new URL('../migrations/'+name,import.meta.url),'utf8'));
  const installer=await readFile(new URL('../instalar-eventos.sql',import.meta.url),'utf8').then(beforeEventSchools);await db.exec(installer);await legacyContexts(db);await db.exec(installer);await legacyContexts(db);
  await db.query('insert into auth.users values($1,false),($2,true)',[admin,user]);await db.query("insert into public.perfis(id,nome,papel) values($1,'Admin','admin')",[admin]);
  await identity(admin,false);
  const book=(id,level,ordering,age='8 anos')=>({id,title:'Livro '+id,author:'Escola',age,level,ordering,active:true,required:true,questions:[{prompt:'Primeira',options:['Sim','Nao'],correct:0},{prompt:'Segunda',options:['Sim','Nao'],correct:0}],pages:[{id:randomUUID(),text:'Conteúdo',image:''}]});
  for(const b of [book('easy-one','facil',0),book('easy-two','facil',1),book('medium','medio',0),book('hard','dificil',0)])await rpc('clube_gestao','story_save',b);
  await superuser();await db.exec("update public.textos set ativo=false where id not in ('easy-one','easy-two','medium','hard')");
  await identity(user,true);sid=(await rpc('clube_portal','register',{name:'Aluno Conquistas',age:8,school:'Escola Conquistas',className:'3 ano'})).student.id;
  await superuser();await db.query("update public.alunos set data_nascimento=(clube_private.hoje_leitura()-interval '8 years')::date where id=$1",[sid]);await identity(user,true);
  await t.test('6. Médio bloqueado antes do Fácil',async()=>{await assert.rejects(enter('medio'),/anterior/i);});
  let a=await enter('facil');
  await t.test('2. Uma questão sem resposta impede finalizar',async()=>{await reading('stage',{id:a.id,stage:'questoes'});await reading('answer',{id:a.id,questionId:a.activity.questions[0].id,selected:0});await assert.rejects(reading('finish',{id:a.id}),/todas/);assert.equal((await state()).levels.find(x=>x.id==='facil').complete,false);});
  await reading('answer',{id:a.id,questionId:a.activity.questions[1].id,selected:0});
  await t.test('1. Uma história pendente impede a conquista e o desbloqueio',async()=>{const r=await reading('finish',{id:a.id});assert.equal(r.achievementId,null);assert.equal((await state()).levels.find(x=>x.id==='medio').unlocked,false);await assert.rejects(enter('medio'));});
  a=await enter('facil');let achievement;
  await t.test('3. Todas as histórias e questões geram conquista com pontos reais',async()=>{const r=await finish(a);assert.ok(r.achievementId);achievement=(await reading('achievement_claim',{id:r.achievementId})).achievement;assert.equal(achievement.level,'facil');assert.equal(achievement.nextLevel,'medio');assert.equal(achievement.percentage,100);const s=await state();assert.equal(achievement.points,40/3);assert.equal(achievement.maxPoints,40/3);assert.equal(achievement.scoreVersion,2);assert.equal(s.levels.find(x=>x.id==='facil').complete,true);});
  await t.test('4. Recarregar preserva desbloqueio e não repete a animação',async()=>{assert.equal((await state()).achievementId,null);assert.equal((await state()).levels.find(x=>x.id==='medio').unlocked,true);assert.equal((await reading('achievement_claim',{id:achievement.id})).achievement,null);assert.equal((await reading('finish',{id:a.id})).achievementId,null);});
  await t.test('5. Novo login mantém progresso e nível correto',async()=>{await superuser();const visitor=randomUUID();session=visitor;await db.query('insert into auth.users(id) values($1)',[visitor]);await db.query("update clube_private.acessos set codigo_curto_hash=encode(sha256(convert_to('DZR35E','UTF8')),'hex'),credencial_cifrada='teste' where aluno_id=$1",[sid]);await identity(visitor,true);assert.equal((await rpc('clube_portal','return',{code:'DZR35E'})).student.id,sid);assert.equal((await state()).levels.find(x=>x.id==='medio').unlocked,true);assert.equal((await reading('achievement_continue',{id:achievement.id})).achievement.nextLevel,'medio');});
  await t.test('7. Concluir Médio libera Difícil somente se permitido',async()=>{a=await enter('medio');assert.equal(a.level,'medio');await superuser();await db.exec("update public.textos set faixa_etaria='9 anos' where nivel='dificil'");await identity(session,true);const r=await finish(a);achievement=(await reading('achievement_claim',{id:r.achievementId})).achievement;assert.equal(achievement.nextLevel,null);assert.equal((await state()).journey.status,'concluida');await assert.rejects(enter('dificil'));await superuser();await db.exec("update public.textos set faixa_etaria='8 anos' where nivel='dificil'");await identity(session,true);assert.equal((await reading('achievement_continue',{id:achievement.id})).achievement.nextLevel,'dificil');assert.equal((await state()).levels.find(x=>x.id==='dificil').unlocked,true);});
  await t.test('8. Sem próximo nível oferece conclusão da jornada',async()=>{a=await enter('dificil');const r=await finish(a);achievement=(await reading('achievement_claim',{id:r.achievementId})).achievement;assert.equal(achievement.nextLevel,null);assert.equal((await state()).journey.status,'concluida');});
  await t.test('Idade atual impede encaminhar a nível indisponível',async()=>{await superuser();await db.exec("update public.textos set faixa_etaria='9 anos' where nivel='dificil'");await identity(session,true);assert.equal((await reading('achievement_continue',{id:achievement.id})).achievement.nextLevel,null);await assert.rejects(enter('dificil'));});
  await t.test('Seleção individual de evento exige todas as histórias atribuídas',async()=>{
   await identity(admin,false);const dates=(await db.query("select (now()-interval '1 hour')::text start,(now()+interval '1 day')::text finish")).rows[0];
   const event=await rpc('clube_eventos','save',{requestId:randomUUID(),name:'Evento Conquista',description:'Seleção individual',startsAt:dates.start,endsAt:dates.finish,active:true,ageConfigs:[{age:8,levels:[{level:'facil',quantity:2,storyIds:['easy-one','easy-two']}]}]});
   await rpc('clube_eventos','send',{id:event.id,studentIds:[sid]});await identity(session,true);
   let ea=(await rpc('clube_eventos','enter',{id:event.id})).attempt;assert.equal((await finish(ea)).achievementId,null);
   ea=(await rpc('clube_eventos','enter',{id:event.id})).attempt;const r=await finish(ea);assert.ok(r.achievementId);const c=(await reading('achievement_claim',{id:r.achievementId})).achievement;assert.equal(c.eventId,event.id);assert.equal(c.nextLevel,null);assert.equal((await rpc('clube_eventos','enter',{id:event.id})).complete,true);
  });
  await t.test('Outro aluno não pode consultar ou consumir conquista',async()=>{await superuser();const other=randomUUID();await db.query('insert into auth.users(id) values($1)',[other]);await identity(other,true);await rpc('clube_portal','register',{name:'Outro Aluno',age:8,school:'Escola Conquistas',className:'3 ano'});await assert.rejects(reading('achievement_claim',{id:achievement.id}));await assert.rejects(reading('achievement_continue',{id:achievement.id}));await assert.rejects(db.query('select * from clube_private.conquistas_niveis'));});
  await t.test('Evento com três níveis mantém atribuições e encaminha somente à próxima seleção',async()=>{
   await superuser();await db.exec("update public.textos set faixa_etaria='8 anos' where nivel='dificil'");await identity(admin,false);
   const dates=(await db.query("select (now()-interval '1 hour')::text start,(now()+interval '1 day')::text finish")).rows[0];
   const event=await rpc('clube_eventos','save',{requestId:randomUUID(),name:'Três níveis atribuídos',description:'Uma seleção por nível',startsAt:dates.start,endsAt:dates.finish,active:true,ageConfigs:[{age:8,levels:[{level:'facil',quantity:1,storyIds:['easy-one']},{level:'medio',quantity:1,storyIds:['medium']},{level:'dificil',quantity:1,storyIds:['hard']}]}]});
   await rpc('clube_eventos','send',{id:event.id,studentIds:[sid]});await identity(session,true);
   for(const [level,next] of [['facil','medio'],['medio','dificil'],['dificil',null]]){const a=(await rpc('clube_eventos','enter',{id:event.id})).attempt;assert.equal(a.level,level);const r=await finish(a);const c=(await reading('achievement_claim',{id:r.achievementId})).achievement;assert.equal(c.nextLevel,next);assert.equal(c.eventId,event.id);assert.equal((await reading('achievement_continue',{id:c.id})).achievement.nextLevel,next);}
   assert.equal((await rpc('clube_eventos','enter',{id:event.id})).complete,true);
  });
  await t.test('Somente Fácil disponível encerra a jornada sem oferecer Médio',async()=>{
   await identity(admin,false);await rpc('clube_gestao','story_save',book('only-seven','facil',0,'7 anos'));
   await superuser();const child=randomUUID();await db.query('insert into auth.users(id) values($1)',[child]);await identity(child,true);const childId=(await rpc('clube_portal','register',{name:'Aluno Sete',age:7,school:'Escola Conquistas',className:'2 ano'})).student.id;
   await superuser();await db.query("update public.alunos set data_nascimento=(clube_private.hoje_leitura()-interval '7 years')::date where id=$1",[childId]);await identity(child,true);
   const a=await enter('facil'),r=await finish(a);assert.equal((await reading('achievement_claim',{id:r.achievementId})).achievement.nextLevel,null);assert.equal((await state()).journey.status,'concluida');await assert.rejects(enter('medio'));
  });
 }finally{await db.close();}
});
