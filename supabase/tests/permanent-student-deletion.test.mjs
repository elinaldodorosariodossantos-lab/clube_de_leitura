import {test} from 'node:test';
import assert from 'node:assert/strict';
import {readFile} from 'node:fs/promises';
import {randomUUID} from 'node:crypto';
import {PGlite} from '../../.qa/postgres/node_modules/@electric-sql/pglite/dist/index.js';

test('permanent student deletion purges history, credentials and rankings atomically',async()=>{
 const db=new PGlite(),admin=randomUUID(),users=[randomUUID(),randomUUID(),randomUUID()],visitor=randomUUID();
 const identity=async(id,anonymous=true)=>{await db.exec('reset role');await db.query("select set_config('request.jwt.claim.sub',$1,false),set_config('request.jwt.claims',$2,false)",[id,JSON.stringify({sub:id,is_anonymous:anonymous})]);await db.exec('set role authenticated');};
 const rpc=async(fn,op,args={})=>(await db.query('select public.'+fn+'($1,$2::jsonb) data',[op,JSON.stringify(args)])).rows[0].data;
 const manage=(op,args)=>rpc('clube_gestao',op,args),reading=(op,args)=>rpc('clube_leitura',op,args);
 const full=await readFile(new URL('../instalar-eventos.sql',import.meta.url),'utf8'),marker=" if to_regprocedure('clube_private.excluir_aluno_definitivamente(uuid)') is null then";
 const before=full.slice(0,full.indexOf(marker))+'end $instalar_eventos$;commit;';
 const migration=await readFile(new URL('../migrations/202611130003_exclusao_definitiva_alunos.sql',import.meta.url),'utf8');
 const students=[],results=[];
 try{
  await db.exec("create role anon;create role authenticated;create schema auth;create table auth.users(id uuid primary key,is_anonymous boolean default true);create function auth.uid() returns uuid language sql stable as $$select nullif(current_setting('request.jwt.claim.sub',true),'')::uuid$$;create function auth.jwt() returns jsonb language sql stable as $$select coalesce(nullif(current_setting('request.jwt.claims',true),''),'{}')::jsonb$$;grant usage on schema auth to anon,authenticated;");
  for(const file of ['202610120001_clube.sql','202610140001_portal.sql','202610150001_leitura.sql','202610150002_admin.sql','202610190001_progressao.sql','202610190002_sequencia.sql'])await db.exec(await readFile(new URL('../migrations/'+file,import.meta.url),'utf8'));
  await db.exec(before);await db.query('insert into auth.users values($1,false),($2,true),($3,true),($4,true),($5,true)',[admin,...users,visitor]);await db.query("insert into public.perfis(id,nome,papel) values($1,'Admin','admin')",[admin]);
  for(let i=0;i<users.length;i++){await identity(users[i]);const r=await rpc('clube_portal','register',{name:['Aluno Excluido','Aluno Ativo','Aluno Antigo'][i],age:4,school:'Escola Exclusao',className:'Infantil'});students.push({...r.student,code:r.code});await db.exec('reset role');await db.query("update public.alunos set data_nascimento=(clube_private.hoje_leitura()-interval '4 years')::date where id=$1",[r.student.id]);}
  await identity(admin,false);
  await manage('story_save',{id:'shared-story',title:'Historia Compartilhada',author:'Escola',age:'4 anos',level:'facil',ordering:0,active:true,required:true,pages:[{id:randomUUID(),text:'Era uma vez.',image:''}],questions:[{prompt:'Quem?',options:['A','B'],correct:0}]});
  const school=(await manage('schools')).find(s=>s.name==='Escola Exclusao');
  const event=await rpc('clube_eventos','save',{requestId:randomUUID(),automatic:true,name:'Evento de Exclusao',description:'Leitura',startsAt:new Date(Date.now()-3600000).toISOString(),endsAt:new Date(Date.now()+86400000).toISOString(),active:true,schoolIds:[school.id],ageConfigs:[{age:4,levels:[{level:'facil',quantity:1}]}]});
  for(const user of users){await identity(user);const a=(await rpc('clube_eventos','enter',{id:event.id})).attempt;await reading('stage',{id:a.id,stage:'questoes'});await reading('answer',{id:a.id,questionId:a.activity.questions[0].id,selected:0});results.push(await reading('finish',{id:a.id}));}
  await identity(visitor);assert.ok((await rpc('clube_portal','return',{code:students[0].code})).student);
  await identity(admin,false);await manage('student_delete',{id:students[2].id});
  await identity(users[1]);const oldRank=(await reading('achievement_get',{id:results[1].achievementId})).achievement.ranking;assert.equal(oldRank.length,3);
  await db.exec('reset role');await db.exec(migration);
  assert.equal((await db.query('select count(*) n from public.alunos where id=$1',[students[2].id])).rows[0].n,0);
  await identity(users[1]);assert.equal((await reading('achievement_get',{id:results[1].achievementId})).achievement.ranking.length,2);
  await assert.rejects(manage('student_delete',{id:students[0].id}),e=>e.code==='42501');
  await assert.rejects(db.query('select clube_private.excluir_aluno_definitivamente($1)',[students[0].id]),e=>e.code==='42501');
  await db.exec('reset role');
  const origin=(await db.query('select id from public.jornadas where aluno_id=$1 order by ciclo limit 1',[students[0].id])).rows[0].id,next=randomUUID();
  await db.query("update public.jornadas set status='concluida',concluida_em=now() where id=$1",[origin]);
  await db.query("insert into public.jornadas(id,aluno_id,ciclo) values($1,$2,2)",[next,students[0].id]);
  await db.query("insert into clube_private.autorizacoes_reinicio_jornada(jornada_origem,aluno_id,nova_jornada,administrador_id) values($1,$2,$3,$4)",[origin,students[0].id,next,admin]);
  await db.query("insert into clube_private.atribuicoes_jornada(jornada_id,aluno_id,texto_id,nivel,ordem,atividade,gabarito) select $1,$2,'shared-story','facil',0,s.atividade,s.gabarito from clube_private.conteudos_tentativas s join public.tentativas t on t.id=s.tentativa_id where t.aluno_id=$2",[origin,students[0].id]);
  await db.query("insert into clube_private.pontuacao_legada values($1,$2,false,'facil')",[students[0].id,origin]);
  await db.exec('create table public.qa_student_guard(aluno_id uuid references public.alunos(id))');await db.query('insert into public.qa_student_guard values($1)',[students[0].id]);
  await identity(admin,false);await assert.rejects(manage('student_delete',{id:students[0].id}),e=>e.code==='23503');
  await db.exec('reset role');assert.equal((await db.query('select count(*) n from clube_private.recompensas_moedas where aluno_id=$1',[students[0].id])).rows[0].n,1);
  assert.equal((await db.query('select count(*) n from clube_private.acessos where aluno_id=$1',[students[0].id])).rows[0].n,1);
  await db.exec('drop table public.qa_student_guard');await identity(admin,false);
  const deleted=await manage('student_delete',{id:students[0].id});assert.deepEqual(deleted,{deleted:true,permanent:true,historyPreserved:false});
  assert.equal((await manage('student_delete',{id:students[0].id})).deleted,true);
  await assert.rejects(rpc('clube_admin','student',{id:students[0].id}),e=>e.code==='P0002');
  await db.exec('reset role');
  for(const table of ['public.alunos','public.tentativas','public.jornadas','public.evento_alunos','clube_private.acessos','clube_private.sessoes','clube_private.conquistas_niveis','clube_private.avaliacoes_niveis','clube_private.recompensas_moedas','clube_private.conclusoes_jornadas','clube_private.pontuacao_legada','clube_private.atribuicoes_jornada','clube_private.autorizacoes_reinicio_jornada']){
   const column=table==='public.alunos'?'id':'aluno_id';assert.equal((await db.query('select count(*) n from '+table+' where '+column+'=any($1::uuid[])',[[students[0].id,students[2].id]])).rows[0].n,0,table);
  }
  assert.equal((await db.query('select count(*) n from auth.users where id=any($1::uuid[])',[[users[0],users[2],visitor]])).rows[0].n,0);
  assert.equal((await db.query('select count(*) n from public.perfis where id=any($1::uuid[])',[[users[0],users[2]]])).rows[0].n,0);
  assert.equal((await db.query('select count(*) n from auth.users where id=any($1::uuid[])',[[admin,users[1]]])).rows[0].n,2);
  for(const table of ['public.respostas','clube_private.conteudos_tentativas','public.evento_leituras','clube_private.evento_conteudos'])assert.equal((await db.query('select count(*) n from '+table)).rows[0].n,1,table);
  const visitorAgain=randomUUID();await db.query('insert into auth.users(id) values($1)',[visitorAgain]);await identity(visitorAgain);assert.equal((await rpc('clube_portal','return',{code:students[0].code})).accessError,'invalid');await db.exec('reset role');
  const survivor=(await db.query('select count(*) n from public.tentativas where aluno_id=$1',[students[1].id])).rows[0].n;assert.equal(survivor,1);
  assert.equal((await db.query("select count(*) n from public.textos where id='shared-story'")).rows[0].n,1);
  await identity(users[0]);await assert.rejects(reading('state'),e=>e.code==='42501');await identity(users[1]);const rank=(await reading('achievement_get',{id:results[1].achievementId})).achievement.ranking;
  assert.equal(rank.length,1);assert.equal(rank[0].name,'Aluno Ativo');assert.equal(rank[0].position,1);
  const final=(await reading('journey_get',{id:results[1].journeyCompletionId})).completion;assert.equal(final.ranking.length,1);assert.equal(final.ranking[0].position,1);assert.equal(final.ranking[0].name,'Aluno Ativo');
  await db.exec('reset role');await db.exec(full);assert.equal((await db.query('select count(*) n from public.alunos')).rows[0].n,1);
 }finally{await db.close();}
});
