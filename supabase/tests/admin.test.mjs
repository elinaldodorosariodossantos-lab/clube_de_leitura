import {test} from 'node:test';
import assert from 'node:assert/strict';
import {readFile} from 'node:fs/promises';
import {PGlite} from '../../.qa/postgres/node_modules/@electric-sql/pglite/dist/index.js';

test('PostgreSQL administrativo: indicadores, validação, duplicatas, escolas, filtros e autorização',async()=>{
 const db=new PGlite();
 const admin='00000000-0000-4000-8000-000000000001',ana='00000000-0000-4000-8000-000000000002',bruno='00000000-0000-4000-8000-000000000003',carla='00000000-0000-4000-8000-000000000004';
 async function identify(uid,anonymous=true){await db.exec('reset role');await db.query("select set_config('request.jwt.claim.sub',$1,false),set_config('request.jwt.claims',$2,false)",[uid,JSON.stringify({sub:uid,is_anonymous:anonymous,user_metadata:{papel:'admin'}})]);await db.exec('set role authenticated');}
 async function rpc(fn,op,args={}){return (await db.query(`select public.${fn}($1,$2::jsonb) as data`,[op,JSON.stringify(args)])).rows[0].data;}
 const query=(op,args)=>rpc('clube_admin',op,args),reading=(op,args)=>rpc('clube_leitura',op,args);
 async function register(uid,name,school){await identify(uid);return (await rpc('clube_portal','register',{name,age:9,school})).student;}
 async function finish(level){const keys={facil:[0,1,1,2,1],medio:[1,0,2,3,1],dificil:[0,2,1,3,0]};const a=await reading('start',{level});await reading('stage',{id:a.id,stage:'questoes'});for(const [i,q] of a.activity.questions.entries())await reading('answer',{id:a.id,questionId:q.id,selected:keys[level][i]});return reading('finish',{id:a.id});}
 async function clone(id,journeyId,score){await db.exec('reset role');const duplicate=(await db.query(`insert into public.tentativas(aluno_id,texto_id,nivel,acertos,pontuacao,percentual,status,concluida_em,jornada_id)
 select aluno_id,texto_id,nivel,acertos,coalesce($3::integer,pontuacao),percentual,status,concluida_em+interval '1 minute',$2::uuid from public.tentativas where id=$1 returning id`,[id,journeyId,score??null])).rows[0].id;await db.query('insert into public.respostas(tentativa_id,questao_id,selecionada,correta,pontos) select $1,questao_id,selecionada,correta,pontos from public.respostas where tentativa_id=$2',[duplicate,id]);return duplicate;}
 try{
  await db.exec(`create role anon;create role authenticated;create schema auth;create table auth.users(id uuid primary key);
   create function auth.uid() returns uuid language sql stable as $$select nullif(current_setting('request.jwt.claim.sub',true),'')::uuid$$;
   create function auth.jwt() returns jsonb language sql stable as $$select coalesce(nullif(current_setting('request.jwt.claims',true),''),'{}')::jsonb$$;
   grant usage on schema auth to anon,authenticated;insert into auth.users values('${admin}'),('${ana}'),('${bruno}'),('${carla}');`);
  for(const file of ['202610120001_clube.sql','202610140001_portal.sql','202610150002_admin.sql'])await db.exec(await readFile(new URL('../migrations/'+file,import.meta.url),'utf8'));
  await db.query("insert into public.perfis(id,nome,papel) values($1,'Administrador de teste','admin')",[admin]);
  await identify(admin,false);const empty=await query('overview');assert.deepEqual([empty.totalStudents,empty.totalSchools,empty.completed,empty.points],[0,0,0,0]);assert.deepEqual((await query('students')).students,[]);
  await identify(admin,true);await assert.rejects(query('overview'),e=>e.code==='42501','Uma identidade anônima não pode ser administradora');
  // O painel não depende da migração de leitura. Ela é aplicada agora para gerar resultados reais de teste.
  await db.exec('reset role');await db.exec(await readFile(new URL('../migrations/202610150001_leitura.sql',import.meta.url),'utf8'));
  const studentAna=await register(ana,'Ana Leitora','Escola Sol');const easy=await finish('facil');await finish('medio');await finish('dificil');await reading('new_journey');await finish('facil');
  const studentBruno=await register(bruno,'Bruno Leitor','  escola   SOL  ');const medium=await finish('medio');const ongoing=await reading('start',{level:'dificil'});
  const studentCarla=await register(carla,'Carla Leitora','Escola Lua');
  await assert.rejects(query('overview'),e=>e.code==='42501');await assert.rejects(query('students'),e=>e.code==='42501');await assert.rejects(query('student',{id:studentAna.id}),e=>e.code==='42501');
  await db.exec('reset role');await db.exec("insert into public.escolas(nome) values('Escola sem alunos')");
  await db.query('update public.tentativas set pontuacao=999 where id=$1',[ongoing.id]);
  await db.query("insert into public.tentativas(aluno_id,texto_id,nivel,status,concluida_em,acertos,pontuacao,percentual) values($1,'passarinho','facil','completed',now(),0,0,0)",[studentCarla.id]);
  const duplicate=await clone(easy.id,easy.journeyId);const inconsistent=await clone(easy.id,easy.journeyId,999);
  await identify(admin,false);const overview=await query('overview');assert.deepEqual([overview.totalStudents,overview.totalSchools,overview.completed,overview.points],[3,2,5,350]);
  const list=await query('students');assert.equal(list.total,3);assert.equal(list.schools.length,2);assert.deepEqual(list.students.map(s=>[s.name,s.completed,s.points]),[['Ana Leitora',4,275],['Bruno Leitor',1,75],['Carla Leitora',0,0]]);
  assert.equal(list.students[0].schoolId,list.students[1].schoolId,'Variações de maiúsculas e espaços usam a mesma escola');
  assert.equal((await query('students',{search:'ANA'})).students[0].id,studentAna.id);
  assert.equal((await query('students',{search:'%'})).total,0,'Busca literal não trata símbolos como curingas');
  assert.equal((await query('students',{schoolId:list.students[0].schoolId})).total,2);
  assert.deepEqual((await query('students',{sort:'name_desc'})).students.map(s=>s.name),['Carla Leitora','Bruno Leitor','Ana Leitora']);
  assert.deepEqual((await query('students',{sort:'points_desc'})).students.map(s=>s.points),[275,75,0]);
  assert.deepEqual((await query('students',{sort:'points_asc'})).students.map(s=>s.points),[0,75,275]);
  const paged=await query('students',{page:2,pageSize:1});assert.equal(paged.students.length,1);assert.equal(paged.students[0].id,studentBruno.id);assert.equal(paged.total,3);
  await assert.rejects(query('students',{page:0}),e=>e.code==='22023');await assert.rejects(query('students',{sort:'drop table alunos'}),e=>e.code==='22023');
  const details=await query('student',{id:studentAna.id});assert.equal(details.student.points,275);assert.equal(details.journeys.length,2);assert.equal(details.attempts.length,6);
  assert.equal(details.attempts.find(a=>a.id===duplicate).includedInTotals,false);assert.equal(details.attempts.find(a=>a.id===inconsistent).points,null);
  assert.equal((await query('student',{id:studentCarla.id})).student.completed,0);
  await assert.rejects(query('student',{id:'00000000-0000-4000-8000-000000000099'}),e=>e.code==='P0002');
  // Registros antigos sem jornada também são deduplicados, sem apagar o histórico bruto.
  await clone(medium.id,null);await clone(medium.id,null);await identify(admin,false);const legacy=await query('overview');assert.equal(legacy.completed,6);assert.equal(legacy.points,425);
  await assert.rejects(db.query('select * from clube_private.admin_alunos'),e=>e.code==='42501');
  await identify(admin,false);await db.exec('reset role');await db.query("update public.perfis set papel='aluno' where id=$1",[admin]);await identify(admin,false);await assert.rejects(query('overview'),e=>e.code==='42501','O papel é verificado novamente em cada consulta');
  await db.exec('reset role;set role anon');await assert.rejects(query('overview'),e=>e.code==='42501');
 }finally{await db.close();}
});
