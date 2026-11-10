begin;
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
commit;
