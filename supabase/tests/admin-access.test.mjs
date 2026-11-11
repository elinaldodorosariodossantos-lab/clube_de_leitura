import {test} from 'node:test';
import assert from 'node:assert/strict';
import {readFile} from 'node:fs/promises';
import {PGlite} from '../../.qa/postgres/node_modules/@electric-sql/pglite/dist/index.js';
test('acessos administrativos: permissões, criação e edição preservam alunos',async()=>{
 const db=new PGlite(),admin='00000000-0000-4000-8000-000000000001',student='00000000-0000-4000-8000-000000000002',newAdmin='00000000-0000-4000-8000-000000000003';
 const identity=async(id)=>{await db.exec('reset role');await db.query("select set_config('request.jwt.claim.sub',$1,false)",[id]);await db.exec('set role authenticated');};
 const rpc=async(op,args={})=>(await db.query('select public.clube_acessos($1,$2::jsonb) data',[op,JSON.stringify(args)])).rows[0].data;
 try{
  await db.exec(`create role anon;create role authenticated;create schema auth;create schema clube_private;
   create table auth.users(id uuid primary key,email text,is_anonymous boolean default false);
   create function auth.uid() returns uuid language sql stable as $$select nullif(current_setting('request.jwt.claim.sub',true),'')::uuid$$;
   create table public.perfis(id uuid primary key references auth.users(id),nome text,papel text,criado_em timestamptz default now());
   create function clube_private.administrador() returns boolean language sql stable security definer as $$select exists(select 1 from public.perfis where id=auth.uid() and papel='admin')$$;`);
  for(const [id,email] of [[admin,'admin@example.com'],[student,'student@example.com'],[newAdmin,'new@example.com']])await db.query('insert into auth.users(id,email) values($1,$2)',[id,email]);
  await db.query("insert into public.perfis(id,nome,papel) values($1,'Admin','admin'),($2,'Aluno','aluno')",[admin,student]);
  await db.exec(await readFile(new URL('../migrations/202611110002_acessos_administrativos.sql',import.meta.url),'utf8'));
  await identity(student);await assert.rejects(rpc('list'),e=>e.code==='42501');await assert.rejects(rpc('save',{id:student,name:'Tentativa'}),e=>e.code==='42501');
  await identity(admin);assert.equal((await rpc('list')).length,1);
  await assert.rejects(rpc('save',{id:student,name:'Promover aluno'}),e=>e.code==='22023');
  await rpc('save',{id:newAdmin,name:'Novo administrador'});assert.equal((await rpc('list')).length,2);
  await rpc('save',{id:admin,name:'Nome atualizado'});assert.equal((await rpc('list')).find(a=>a.id===admin).name,'Nome atualizado');
  await db.exec('reset role');assert.equal((await db.query('select papel from public.perfis where id=$1',[student])).rows[0].papel,'aluno');
 }finally{await db.close();}
});
