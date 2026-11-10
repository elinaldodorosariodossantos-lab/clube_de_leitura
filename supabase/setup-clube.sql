-- Instalação inicial do Clube da Leitura 2026.
-- Execute no SQL Editor do Supabase. Não apaga dados existentes.
-- Interrompe antes de qualquer alteração se alguma tabela do clube já existir.
-- As duas migrações são aplicadas em uma transação única.
begin;
do $verificar$
begin
 if exists(select 1 from pg_catalog.pg_tables where schemaname='public' and tablename in ('perfis','alunos','niveis','textos','questoes','tentativas','respostas','escolas','jornadas')) then
  raise exception 'Já existem tabelas do clube. Use as migrações individuais após conferir o estado do banco.';
 end if;
end $verificar$;

create schema if not exists clube_private;
revoke all on schema clube_private from public, anon, authenticated;
create table public.perfis(id uuid primary key references auth.users(id),nome text not null,papel text not null default 'aluno' check(papel in ('aluno','professor','admin')),criado_em timestamptz not null default now());
create table public.alunos(id uuid primary key default gen_random_uuid(),perfil_id uuid not null unique references public.perfis(id),faixa_etaria text,turma text);
create table public.niveis(id text primary key,pontos integer not null check(pontos>0));
insert into public.niveis values ('facil',10),('medio',15),('dificil',20);
create table public.textos(id text primary key,titulo text not null,conteudo text not null,faixa_etaria text not null,nivel text not null references public.niveis(id),ativo boolean not null default true);
create table public.questoes(id integer primary key,texto_id text not null references public.textos(id),enunciado text not null,alternativas jsonb not null check(jsonb_array_length(alternativas)=4),valor integer check(valor>0));
create table clube_private.gabaritos(questao_id integer primary key references public.questoes(id),correta integer not null check(correta between 0 and 3));
create table public.tentativas(id uuid primary key default gen_random_uuid(),aluno_id uuid not null references public.alunos(id),texto_id text not null references public.textos(id),nivel text not null references public.niveis(id),acertos integer,pontuacao integer,percentual numeric,status text not null default 'started' check(status in ('started','completed')),concluida_em timestamptz);
create table public.respostas(id uuid primary key default gen_random_uuid(),tentativa_id uuid not null references public.tentativas(id),questao_id integer not null references public.questoes(id),selecionada integer not null check(selecionada between 0 and 3),correta boolean,pontos integer,unique(tentativa_id,questao_id));
create index on public.questoes(texto_id);
create index on public.tentativas(aluno_id,concluida_em desc);
create index on public.respostas(tentativa_id);
alter table public.perfis enable row level security;
alter table public.alunos enable row level security;
alter table public.niveis enable row level security;
alter table public.textos enable row level security;
alter table public.questoes enable row level security;
alter table public.tentativas enable row level security;
alter table public.respostas enable row level security;
alter table clube_private.gabaritos enable row level security;
create policy perfil_proprio on public.perfis for select to authenticated using(id=auth.uid());
create policy aluno_proprio on public.alunos for select to authenticated using(perfil_id=auth.uid());
create policy niveis_leitura on public.niveis for select to authenticated using(true);
create policy textos_ativos on public.textos for select to authenticated using(ativo);
create policy questoes_ativas on public.questoes for select to authenticated using(exists(select 1 from public.textos t where t.id=texto_id and t.ativo));
create policy tentativas_proprias on public.tentativas for select to authenticated using(exists(select 1 from public.alunos a where a.id=aluno_id and a.perfil_id=auth.uid()));
create policy respostas_proprias on public.respostas for select to authenticated using(exists(select 1 from public.tentativas t where t.id=tentativa_id));
revoke all on public.perfis,public.alunos,public.niveis,public.textos,public.questoes,public.tentativas,public.respostas from anon,authenticated;
grant select on public.perfis,public.alunos,public.niveis,public.textos,public.questoes,public.tentativas,public.respostas to authenticated;
create function clube_private.attempt_json(a public.tentativas) returns jsonb language sql stable security definer set search_path='' as $$
select jsonb_build_object('id',a.id,'status',a.status,'completedAt',a.concluida_em,'answers',coalesce((select jsonb_object_agg(r.questao_id,r.selecionada) from public.respostas r where r.tentativa_id=a.id),'{}'::jsonb),'result',case when a.status='completed' then jsonb_build_object('hits',a.acertos,'points',a.pontuacao,'percentage',a.percentual,'details',(select jsonb_agg(jsonb_build_object('id',q.id,'prompt',q.enunciado,'options',q.alternativas,'selected',r.selecionada,'correct',g.correta,'points',r.pontos) order by q.id) from public.respostas r join public.questoes q on q.id=r.questao_id join clube_private.gabaritos g on g.questao_id=q.id where r.tentativa_id=a.id)) else null end)
$$;
create function public.clube_api(op text,args jsonb default '{}') returns jsonb language plpgsql security definer set search_path='' as $$
declare student uuid; a public.tentativas; qid integer; choice integer; value integer;
begin
 if auth.uid() is null then raise exception 'Autenticação obrigatória' using errcode='42501'; end if;
 select id into student from public.alunos where perfil_id=auth.uid();
 if student is null then raise exception 'Aluno não cadastrado pela escola' using errcode='42501'; end if;
 if op='activity' then
 return (select jsonb_build_object('id',t.id,'title',t.titulo,'content',t.conteudo,'age',t.faixa_etaria,'level',t.nivel,'questions',(select jsonb_agg(jsonb_build_object('id',q.id,'prompt',q.enunciado,'options',q.alternativas) order by q.id) from public.questoes q where q.texto_id=t.id)) from public.textos t where t.id='passarinho' and t.ativo);
 elsif op='start' then
 insert into public.tentativas(aluno_id,texto_id,nivel) select student,id,nivel from public.textos where id='passarinho' and ativo returning * into a;
 if a.id is null then raise exception 'Atividade indisponível'; end if;
 return clube_private.attempt_json(a);
 elsif op='history' then
 return coalesce((select jsonb_agg(clube_private.attempt_json(t) order by t.concluida_em desc) from public.tentativas t where t.aluno_id=student and t.status='completed'),'[]'::jsonb);
 end if;
 select * into a from public.tentativas where id=(args->>'id')::uuid and aluno_id=student for update;
 if a.id is null then raise exception 'Tentativa não encontrada' using errcode='42501'; end if;
 if op='get' then return clube_private.attempt_json(a); end if;
 if op='finish' and a.status='completed' then return clube_private.attempt_json(a); end if;
 if a.status='completed' then raise exception 'Tentativa já concluída'; end if;
 if op='answer' then
 qid:=(args->>'questionId')::integer; choice:=(args->>'selected')::integer;
 if choice is null or choice not between 0 and 3 or not exists(select 1 from public.questoes where id=qid and texto_id=a.texto_id) then raise exception 'Alternativa inválida'; end if;
 insert into public.respostas(tentativa_id,questao_id,selecionada) values(a.id,qid,choice) on conflict(tentativa_id,questao_id) do update set selecionada=excluded.selecionada;
 elsif op='finish' then
 if (select count(*) from public.respostas where tentativa_id=a.id)<>(select count(*) from public.questoes where texto_id=a.texto_id) then raise exception 'Responda a todas as questões'; end if;
 select pontos into value from public.niveis where id=a.nivel;
 update public.respostas r set correta=(r.selecionada=g.correta),pontos=case when r.selecionada=g.correta then coalesce(q.valor,value) else 0 end from clube_private.gabaritos g,public.questoes q where r.tentativa_id=a.id and g.questao_id=r.questao_id and q.id=r.questao_id;
 update public.tentativas set status='completed',concluida_em=now(),acertos=(select count(*) from public.respostas where tentativa_id=a.id and correta),pontuacao=(select sum(pontos) from public.respostas where tentativa_id=a.id),percentual=(select 100.0*count(*) filter(where correta)/count(*) from public.respostas where tentativa_id=a.id) where id=a.id returning * into a;
 else raise exception 'Operação inválida'; end if;
 return clube_private.attempt_json(a);
end $$;
revoke all on function clube_private.attempt_json(public.tentativas) from public,anon,authenticated;
revoke all on function public.clube_api(text,jsonb) from public,anon;
grant execute on function public.clube_api(text,jsonb) to authenticated;


-- Extensão aditiva: os cadastros e as tentativas anteriores são preservados.
create table public.escolas(id uuid primary key default gen_random_uuid(),nome text not null check(length(trim(nome)) between 2 and 160),nome_normalizado text generated always as (lower(trim(regexp_replace(nome,'\s+',' ','g')))) stored unique);
alter table public.alunos add column nome_completo text check(length(trim(nome_completo)) between 3 and 120),add column idade integer check(idade between 4 and 19),add column escola_id uuid references public.escolas(id),add column criado_em timestamptz not null default now(),add column atualizado_em timestamptz not null default now(),add column situacao text not null default 'ativo' check(situacao in ('ativo','inativo'));
update public.alunos a set nome_completo=p.nome,criado_em=p.criado_em from public.perfis p where p.id=a.perfil_id;
create index alunos_escola_idx on public.alunos(escola_id);
create table clube_private.acessos(aluno_id uuid primary key references public.alunos(id),codigo_hash text not null unique);
create table clube_private.sessoes(usuario_id uuid primary key references auth.users(id),aluno_id uuid not null references public.alunos(id));
create index sessoes_aluno_idx on clube_private.sessoes(aluno_id);
create table clube_private.configuracao(id boolean primary key default true check(id),idade_min integer not null default 4,idade_max integer not null default 19,check(idade_min between 4 and 19 and idade_max between idade_min and 19));
insert into clube_private.configuracao(id) values(true);
create table public.jornadas(id uuid primary key default gen_random_uuid(),aluno_id uuid not null references public.alunos(id),ciclo integer not null check(ciclo>0),status text not null default 'preparacao' check(status in ('preparacao','em_andamento','concluida')),texto_atual_id text references public.textos(id),nivel_atual text references public.niveis(id),criado_em timestamptz not null default now(),concluida_em timestamptz,unique(aluno_id,ciclo));
create unique index jornada_aberta_idx on public.jornadas(aluno_id) where status<>'concluida';
alter table public.tentativas add column jornada_id uuid references public.jornadas(id);
create index tentativas_jornada_idx on public.tentativas(jornada_id);
alter table public.escolas enable row level security;
alter table public.jornadas enable row level security;
alter table clube_private.acessos enable row level security;
alter table clube_private.sessoes enable row level security;
alter table clube_private.configuracao enable row level security;
revoke all on public.escolas,public.jornadas from anon,authenticated;
revoke all on clube_private.acessos,clube_private.sessoes,clube_private.configuracao from public,anon,authenticated;
create function clube_private.administrador() returns boolean language sql stable security definer set search_path='' as $$ select exists(select 1 from public.perfis where id=auth.uid() and papel='admin') and not coalesce((auth.jwt()->>'is_anonymous')::boolean,true) $$;
create function clube_private.aluno_atual() returns uuid language sql stable security definer set search_path='' as $$ select s.aluno_id from clube_private.sessoes s join public.alunos a on a.id=s.aluno_id where s.usuario_id=auth.uid() and a.situacao='ativo' $$;
create function clube_private.aluno_json(student uuid) returns jsonb language sql stable security definer set search_path='' as $$
 select jsonb_build_object('id',a.id,'name',a.nome_completo,'age',a.idade,'school',e.nome,'className',coalesce(a.turma,''),'createdAt',a.criado_em,'status',a.situacao,'completed', (select count(*) from public.tentativas where aluno_id=a.id and status='completed'),'points',(select coalesce(sum(pontuacao),0) from public.tentativas where aluno_id=a.id and status='completed'),'ongoing',exists(select 1 from public.tentativas where aluno_id=a.id and status='started'),'journey',(select jsonb_build_object('id',j.id,'cycle',j.ciclo,'status',j.status,'textId',j.texto_atual_id,'level',j.nivel_atual) from public.jornadas j where j.aluno_id=a.id order by j.ciclo desc limit 1)) from public.alunos a left join public.escolas e on e.id=a.escola_id where a.id=student
$$;
create function public.clube_portal(op text,args jsonb default '{}') returns jsonb language plpgsql security definer set search_path='' as $$
declare student uuid;school uuid;code text;cfg clube_private.configuracao;nm text;sc text;ag integer;
begin
 if op='config' then select * into cfg from clube_private.configuracao where id;return jsonb_build_object('minAge',cfg.idade_min,'maxAge',cfg.idade_max);end if;
 if op='schools' then return coalesce((select jsonb_agg(jsonb_build_object('id',id,'name',nome) order by nome) from public.escolas),'[]');end if;
 if auth.uid() is null then raise exception 'Autenticação obrigatória' using errcode='42501';end if;
 if op='register' then
  if not coalesce((auth.jwt()->>'is_anonymous')::boolean,false) or exists(select 1 from public.alunos where perfil_id=auth.uid()) or exists(select 1 from clube_private.sessoes where usuario_id=auth.uid()) then raise exception 'Cadastro não permitido' using errcode='42501';end if;
  nm:=trim(regexp_replace(args->>'name','\s+',' ','g'));sc:=trim(regexp_replace(args->>'school','\s+',' ','g'));ag:=(args->>'age')::integer;
  select * into cfg from clube_private.configuracao where id;
  if nm is null or length(nm) not between 3 and 120 or position(' ' in nm)=0 or sc is null or length(sc) not between 2 and 160 or ag is null or ag not between cfg.idade_min and cfg.idade_max or length(coalesce(args->>'className',''))>60 then raise exception 'Dados inválidos' using errcode='22023';end if;
  insert into public.escolas(nome) values(sc) on conflict(nome_normalizado) do update set nome=public.escolas.nome returning id into school;
  insert into public.perfis(id,nome) values(auth.uid(),nm);
  insert into public.alunos(perfil_id,nome_completo,idade,escola_id,turma) values(auth.uid(),nm,ag,school,trim(args->>'className')) returning id into student;
  code:=replace(gen_random_uuid()::text,'-','');
  insert into clube_private.acessos values(student,encode(sha256(convert_to(code,'UTF8')),'hex'));
  insert into clube_private.sessoes values(auth.uid(),student);
  insert into public.jornadas(aluno_id,ciclo) values(student,1);
  return jsonb_build_object('student',clube_private.aluno_json(student),'code',code);
 elsif op='return' then
  if not coalesce((auth.jwt()->>'is_anonymous')::boolean,false) or exists(select 1 from public.alunos where perfil_id=auth.uid()) or exists(select 1 from clube_private.sessoes where usuario_id=auth.uid()) then raise exception 'Retorno não permitido' using errcode='42501';end if;
  code:=lower(regexp_replace(args->>'code','[\s-]','','g'));
  if code is null or code!~'^[a-f0-9]{32}$' then raise exception 'Código inválido' using errcode='22023';end if;
  select a.aluno_id into student from clube_private.acessos a join public.alunos s on s.id=a.aluno_id where a.codigo_hash=encode(sha256(convert_to(code,'UTF8')),'hex') and s.situacao='ativo' for update of a;
  if student is null then raise exception 'Código inválido' using errcode='22023';end if;
  delete from clube_private.sessoes where aluno_id=student;
  insert into clube_private.sessoes values(auth.uid(),student);
  return jsonb_build_object('student',clube_private.aluno_json(student));
 elsif op='session' then return jsonb_build_object('admin',clube_private.administrador(),'student',clube_private.aluno_json(clube_private.aluno_atual()));
 elsif op='student' then
  student:=clube_private.aluno_atual();if student is null then raise exception 'Aluno não identificado' using errcode='42501';end if;
  return clube_private.aluno_json(student);
 elsif op='admin' then
  if not clube_private.administrador() then raise exception 'Administrador obrigatório' using errcode='42501';end if;
  return jsonb_build_object('totalStudents',(select count(*) from public.alunos),'totalSchools',(select count(*) from public.escolas),'completed',(select count(*) from public.tentativas where status='completed'),'points',(select coalesce(sum(pontuacao),0) from public.tentativas where status='completed'),'schools',coalesce((select jsonb_agg(jsonb_build_object('id',id,'name',nome) order by nome) from public.escolas),'[]'),'students',coalesce((select jsonb_agg(clube_private.aluno_json(id) order by criado_em desc) from public.alunos),'[]'));
 end if;
 raise exception 'Operação inválida' using errcode='22023';
end $$;
revoke all on function clube_private.administrador(),clube_private.aluno_atual(),clube_private.aluno_json(uuid) from public,anon,authenticated;
revoke all on function public.clube_portal(text,jsonb) from public,anon,authenticated;
grant execute on function public.clube_portal(text,jsonb) to anon,authenticated;
-- As novas tabelas só são consultadas pela função que verifica identidade e papel.
-- A leitura direta das tabelas existentes continua regida pelas políticas anteriores.

notify pgrst, 'reload schema';
commit;
