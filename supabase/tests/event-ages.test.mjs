import {beforeEventSchools} from './fixtures/before-event-schools.mjs';
import {legacyContexts} from './fixtures/legacy-policy.mjs';
import {test} from 'node:test';
import assert from 'node:assert/strict';
import {readFile} from 'node:fs/promises';
import {randomUUID,createHash} from 'node:crypto';
import {PGlite} from '../../.qa/postgres/node_modules/@electric-sql/pglite/dist/index.js';
test('idades: configurações dinâmicas, níveis, sorteios, insuficiência e progresso preservado',async()=>{
 const db=new PGlite(),admin=randomUUID(),students=[];const hash=v=>createHash('sha256').update(v).digest('hex');
 const identity=async(uid,anonymous=true)=>{await db.exec('reset role');await db.query("select set_config('request.jwt.claim.sub',$1,false),set_config('request.jwt.claims',$2,false)",[uid,JSON.stringify({sub:uid,is_anonymous:anonymous})]);await db.exec('set role authenticated');};
 const rpc=async(fn,op,args={})=>(await db.query(`select public.${fn}($1,$2::jsonb) as data`,[op,JSON.stringify(args)])).rows[0].data;
 const event=(op,args)=>rpc('clube_eventos',op,args),manage=(op,args)=>rpc('clube_gestao',op,args),read=(op,args)=>rpc('clube_leitura',op,args);
 try{
  await db.exec(`create role anon;create role authenticated;create schema auth;create table auth.users(id uuid primary key,is_anonymous boolean default true);
  create function auth.uid() returns uuid language sql stable as $$select nullif(current_setting('request.jwt.claim.sub',true),'')::uuid$$;
  create function auth.jwt() returns jsonb language sql stable as $$select coalesce(nullif(current_setting('request.jwt.claims',true),''),'{}')::jsonb$$;grant usage on schema auth to anon,authenticated;`);
  for(const f of ['202610120001_clube.sql','202610140001_portal.sql','202610150001_leitura.sql','202610150002_admin.sql','202610190001_progressao.sql','202610190002_sequencia.sql'])await db.exec(await readFile(new URL('../migrations/'+f,import.meta.url),'utf8'));
  await db.exec(await readFile(new URL('../instalar-eventos.sql',import.meta.url),'utf8').then(beforeEventSchools));await legacyContexts(db);
  // O instalador atualizado também cobre esta etapa; execução direta continua testada quando necessário.
  if(!(await db.query("select exists(select 1 from information_schema.columns where table_schema='public' and table_name='eventos_leitura' and column_name='configuracoes') as ready")).rows[0].ready)await db.exec(await readFile(new URL('../migrations/202610230001_eventos_idades.sql',import.meta.url),'utf8'));
  await db.query('insert into auth.users values($1,false)',[admin]);await db.query("insert into public.perfis values($1,'Admin','admin',now())",[admin]);await identity(admin,false);
  assert.equal(await event('age_config_ready'),true);
  const school=await manage('school_save',{name:'Escola Idades'});const dates=(await db.query("select (now()-interval '1 day')::text as start,(now()+interval '20 days')::text as finish")).rows[0];
  for(const [i,age] of [7,7,8,6,7].entries()){
   const profile=randomUUID(),visitor=randomUUID();await db.exec('reset role');await db.query('insert into auth.users(id) values($1),($2)',[profile,visitor]);const birth=(await db.query("select (current_date-make_interval(years=>$1::integer)-interval '1 month')::date::text as birth",[age])).rows[0].birth;await identity(admin,false);
   const code='AB2CD'+(i+2);const student=await manage('student_save',{profileId:profile,name:'Aluno Idade '+i,birthDate:birth,guardian:'Responsável Local',schoolId:school.id,className:'Turma A',tokenHash:hash('token'+i),shortHash:hash(code),encrypted:'cifrado'});students.push({...student,visitor,code});
  }
  const pools={facil:[],medio:[]};for(const level of Object.keys(pools))for(let i=0;i<3;i++){const s=await manage('story_save',{id:level+'-idade-'+i,title:'História '+level+' '+i,author:'Autora Local',level,age:'6 a 12 anos',active:true,required:false,ordering:i,content:'Texto do teste.',cover:'',questions:[{prompt:'Escolha A',options:['A','B','C','D'],correct:0}]});pools[level].push(s.id);}
  await identity(students[0].visitor);await rpc('clube_portal','return',{code:students[0].code});let normal=(await read('enter',{level:'facil'})).attempt;await read('stage',{id:normal.id,stage:'questoes'});for(const q of normal.activity.questions)await read('answer',{id:normal.id,questionId:q.id,selected:0});await read('finish',{id:normal.id});const baseline=(await read('state')).student.points;
  await identity(admin,false);const ageConfigs=[{age:7,levels:[{level:'facil',quantity:1,storyIds:pools.facil},{level:'medio',quantity:1,storyIds:pools.medio}]},{age:8,levels:[{level:'facil',quantity:2,storyIds:pools.facil}]}];
  const input={requestId:randomUUID(),name:'Evento por Idades',description:'Sorteio individual',cover:'',startsAt:dates.start,endsAt:dates.finish,active:true,ageConfigs};
  await assert.rejects(event('save',{...input,ageConfigs:[...ageConfigs,ageConfigs[0]]}),e=>e.code==='22023');
  await assert.rejects(event('save',{...input,ageConfigs:[{age:3,levels:ageConfigs[0].levels}]}),e=>e.code==='22023');
  await assert.rejects(event('save',{...input,ageConfigs:[{age:7,levels:[{level:'facil',quantity:4,storyIds:pools.facil}]}]}),e=>e.code==='22023');
  await assert.rejects(event('save',{...input,ageConfigs:[{age:7,levels:[{level:'facil',quantity:0,storyIds:pools.facil}]}]}),e=>e.code==='22023');
  const saved=await event('save',input);assert.deepEqual((await event('get',{id:saved.id})).ageConfigs,ageConfigs);assert.equal((await event('distribution_check',{id:saved.id})).valid,true);
  const eligible=await event('recipients',{id:saved.id});assert.equal(eligible.students.length,4);assert.ok(!eligible.students.some(s=>s.id===students[3].id));assert.equal((await event('list',{age:'6'})).length,0);assert.equal((await event('list',{level:'medio'})).length,1);
  await assert.rejects(event('send',{id:saved.id,studentIds:[students[0].id,students[3].id]}),e=>e.code==='22023');assert.equal((await event('get',{id:saved.id})).recipients,0,'Lote inválido é revertido inteiro');
  const ids=[0,1,2,4].map(i=>students[i].id);assert.deepEqual(await event('send',{id:saved.id,studentIds:ids}),{created:4,existing:0});assert.deepEqual(await event('send',{id:saved.id,studentIds:ids}),{created:0,existing:4});
  await db.exec('reset role');const before=(await db.query('select aluno_id,idade_referencia,configuracao from public.evento_alunos where evento_id=$1 order by aluno_id',[saved.id])).rows;assert.equal(before.find(p=>p.aluno_id===students[0].id).configuracao.length,2);assert.equal(before.find(p=>p.aluno_id===students[1].id).configuracao.length,1,'Nível bloqueado não é atribuído');assert.equal(before.find(p=>p.aluno_id===students[2].id).configuracao[0].quantity,2);
  const signatures=before.filter(p=>p.idade_referencia===7).map(p=>p.configuracao.find(c=>c.level==='facil').signature);assert.equal(new Set(signatures).size,3);
  await identity(students[0].visitor);const mine=(await event('mine'))[0];assert.equal(mine.age,7);assert.equal(mine.assignedLevels.length,2);assert.ok(!('ageConfigs' in mine));assert.ok(!('storyIds' in mine));
  let attempt=(await event('enter',{id:saved.id})).attempt;await read('stage',{id:attempt.id,stage:'questoes'});await read('answer',{id:attempt.id,questionId:attempt.activity.questions[0].id,selected:0});assert.equal((await event('enter',{id:saved.id})).attempt.id,attempt.id);
  await identity(admin,false);await assert.rejects(event('save',{...input,id:saved.id,ageConfigs:[ageConfigs[1]]}),e=>e.code==='22023');await event('save',{...input,id:saved.id,confirmChanges:true,ageConfigs:[ageConfigs[1]]});
  await db.exec('reset role');await db.query("update public.alunos set data_nascimento=data_nascimento-interval '1 year' where id=$1",[students[0].id]);await identity(students[0].visitor);assert.equal((await event('mine'))[0].age,7,'Idade distribuída permanece estável');assert.equal(Object.keys((await read('get',{id:attempt.id})).answers).length,1);await read('finish',{id:attempt.id});
  attempt=(await event('enter',{id:saved.id})).attempt;assert.equal(attempt.level,'medio');await read('stage',{id:attempt.id,stage:'questoes'});await read('answer',{id:attempt.id,questionId:attempt.activity.questions[0].id,selected:0});await read('finish',{id:attempt.id});assert.equal((await event('enter',{id:saved.id})).complete,true);assert.ok(Math.abs((await read('state')).student.points-(baseline+80/3))<1e-9);
  await assert.rejects(event('report',{id:saved.id}),e=>e.code==='42501');await identity(admin,false);const report=await event('report',{id:saved.id});assert.equal(report.find(r=>r.age===7&&r.level==='medio').points,40/3);
  await manage('story_status',{id:pools.facil[0],active:false});await manage('story_status',{id:pools.facil[1],active:false});const availability=await event('distribution_check',{id:saved.id});assert.equal(availability.valid,false);assert.equal(availability.groups[0].available,1);await assert.rejects(event('send',{id:saved.id,studentIds:[students[3].id]}),e=>e.code==='22023');
  await db.exec('reset role');assert.deepEqual((await db.query('select aluno_id,idade_referencia,configuracao from public.evento_alunos where evento_id=$1 order by aluno_id',[saved.id])).rows,before,'Editar, aniversário e falhas não refazem sorteios');

  // Tres quantidades independentes usam o mesmo RPC e o mesmo sorteio persistente.
  const hardPool=[];for(let i=0;i<3;i++){const item=await manage('story_save',{id:'hard-compact-'+i,title:'Livro compacto '+i,author:'Escola',level:'dificil',age:'6 a 12 anos',active:true,required:false,ordering:i,content:'Texto',cover:'',questions:[{prompt:'Escolha',options:['A','B'],correct:0}]});hardPool.push(item.id);}
  const compact=[{age:8,levels:[{level:'facil',quantity:1,storyIds:[pools.facil[2]]},{level:'medio',quantity:2,storyIds:pools.medio},{level:'dificil',quantity:3,storyIds:hardPool}]}];
  const compactEvent=await event('save',{...input,requestId:randomUUID(),name:'Linhas compactas',ageConfigs:compact});assert.deepEqual((await event('get',{id:compactEvent.id})).ageConfigs,compact);
  await event('send',{id:compactEvent.id,studentIds:[students[0].id]});
  await db.exec('reset role');const assignedCompact=(await db.query('select configuracao from public.evento_alunos where evento_id=$1',[compactEvent.id])).rows[0].configuracao;
  for(const configured of assignedCompact){assert.equal(configured.quantity,compact[0].levels.find(l=>l.level===configured.level).quantity);assert.equal(configured.storyIds.length,configured.quantity);}
  await identity(admin,false);assert.equal((await event('send',{id:compactEvent.id,studentIds:[students[0].id]})).existing,1);
 }finally{await db.close();}
});
