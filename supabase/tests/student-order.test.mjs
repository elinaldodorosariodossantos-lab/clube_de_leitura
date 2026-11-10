import {beforeEventSchools} from './fixtures/before-event-schools.mjs';
import {test} from 'node:test';
import assert from 'node:assert/strict';
import {readFile} from 'node:fs/promises';
import {randomUUID} from 'node:crypto';
import {PGlite} from '../../.qa/postgres/node_modules/@electric-sql/pglite/dist/index.js';

test('alunos sempre em ordem alfabetica com acentos, caixa e paginacao',async()=>{
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


  const names=['zoe Silva','Álvaro Santos','ana Lima','Bruno Alves','Érica Silva'];
  for(const name of names){await db.exec('reset role');const id=randomUUID();await db.query('insert into auth.users values($1,true)',[id]);await identity(id,true);await rpc('clube_portal','register',{name,age:7,school:'Escola Local',className:'2 ano'});}
  await identity(admin,false);
  const expected=['Álvaro Santos','ana Lima','Bruno Alves','Érica Silva','zoe Silva'];
  for(const sort of ['name_asc','name_desc','points_desc'])assert.deepEqual((await rpc('clube_gestao','students',{sort})).students.map(s=>s.name),expected);
  assert.deepEqual((await rpc('clube_gestao','students',{page:2,pageSize:2})).students.map(s=>s.name),expected.slice(2,4));
  assert.deepEqual((await rpc('clube_gestao','students',{search:'Silva'})).students.map(s=>s.name),expected.filter(n=>n.includes('Silva')));
 }finally{await db.close();}
});
