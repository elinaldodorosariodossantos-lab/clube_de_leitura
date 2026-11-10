begin;
-- Escolas existentes permanecem; datas historicas desconhecidas ficam nulas.
alter table public.escolas add column municipio text check(municipio is null or length(trim(municipio)) between 2 and 160),add column criado_em timestamptz;
alter table public.escolas alter column criado_em set default now();
create table public.turmas(id uuid primary key default gen_random_uuid(),escola_id uuid not null references public.escolas(id),nome text not null check(length(trim(nome)) between 1 and 60),nome_normalizado text generated always as(lower(trim(regexp_replace(nome,'\s+',' ','g')))) stored,ano_letivo integer not null check(ano_letivo between 2000 and 2100),criado_em timestamptz not null default now(),unique(escola_id,nome_normalizado,ano_letivo));
alter table public.alunos add column turma_id uuid references public.turmas(id);
insert into public.turmas(escola_id,nome,ano_letivo) select distinct on(escola_id,lower(trim(regexp_replace(turma,'\s+',' ','g'))),ano_letivo) escola_id,trim(regexp_replace(turma,'\s+',' ','g')),ano_letivo from public.alunos where escola_id is not null and trim(coalesce(turma,''))<>'' order by escola_id,lower(trim(regexp_replace(turma,'\s+',' ','g'))),ano_letivo,id;
update public.alunos a set turma_id=t.id from public.turmas t where t.escola_id=a.escola_id and t.ano_letivo=a.ano_letivo and t.nome_normalizado=lower(trim(regexp_replace(a.turma,'\s+',' ','g')));
create index turmas_escola_ano_idx on public.turmas(escola_id,ano_letivo);
create index alunos_turma_idx on public.alunos(turma_id);
alter table public.turmas enable row level security;
revoke all on public.turmas from public,anon,authenticated;
create function clube_private.sincronizar_turma_aluno() returns trigger language plpgsql security definer set search_path='' as $$
declare c public.turmas;
begin
 if new.turma_id is not null and (tg_op='INSERT' or new.turma_id is distinct from old.turma_id) then
  select * into c from public.turmas where id=new.turma_id;
  if c.id is null or c.escola_id is distinct from new.escola_id then raise exception 'A turma precisa pertencer a escola do aluno.' using errcode='22023';end if;
  new.turma:=c.nome;new.ano_letivo:=c.ano_letivo;return new;
 end if;
 if new.escola_id is null or trim(coalesce(new.turma,''))='' then new.turma_id:=null;return new;end if;
 insert into public.turmas(escola_id,nome,ano_letivo) values(new.escola_id,trim(regexp_replace(new.turma,'\s+',' ','g')),new.ano_letivo) on conflict(escola_id,nome_normalizado,ano_letivo) do update set nome=public.turmas.nome returning * into c;
 new.turma_id:=c.id;new.turma:=c.nome;return new;
end $$;
create trigger sincronizar_turma_aluno before insert or update of escola_id,turma,ano_letivo,turma_id on public.alunos for each row execute function clube_private.sincronizar_turma_aluno();
revoke all on function clube_private.sincronizar_turma_aluno() from public,anon,authenticated;
alter function public.clube_escolas(text,jsonb) rename to escolas_antes_modulo;
alter function public.escolas_antes_modulo(text,jsonb) set schema clube_private;
revoke all on function clube_private.escolas_antes_modulo(text,jsonb) from public,anon,authenticated;
create function public.clube_escolas(op text,args jsonb default '{}') returns jsonb language plpgsql security definer set search_path='' as $$
declare sid uuid;cid uuid;nm text;city text;year_value integer;page_number integer:=coalesce((args->>'page')::integer,1);page_size integer:=coalesce((args->>'pageSize')::integer,20);search text:=trim(coalesce(args->>'search',''));result jsonb;c public.turmas;e public.escolas;first_day date;last_day date;
begin
 if not clube_private.administrador() then raise exception 'Administrador obrigatorio' using errcode='42501';end if;
 if page_number not between 1 and 1000000 or page_size not between 1 and 100 or length(search)>120 then raise exception 'Filtros invalidos.' using errcode='22023';end if;
 if op='schools_list' then
  return (with filtered as(select s.id,s.nome as name,s.municipio as municipality,s.criado_em as "createdAt",(select count(*) from public.alunos a where a.escola_id=s.id and a.excluido_em is null) as students from public.escolas s where (search='' or strpos(clube_private.nome_ordenacao(s.nome),clube_private.nome_ordenacao(search))>0) and (coalesce(args->>'municipality','')='' or s.municipio=args->>'municipality')),paged as(select * from filtered order by clube_private.nome_ordenacao(name),id limit page_size offset (page_number-1)*page_size) select jsonb_build_object('schools',coalesce((select jsonb_agg(to_jsonb(p) order by clube_private.nome_ordenacao(p.name),p.id) from paged p),'[]'),'total',(select count(*) from filtered),'municipalities',coalesce((select jsonb_agg(municipio order by municipio) from(select distinct municipio from public.escolas where municipio is not null) x),'[]')));
 end if;
 if op in('school_get','school_update','school_delete','school_students','credentials') then
  sid:=(args->>'schoolId')::uuid;select * into e from public.escolas where id=sid for update;
  if e.id is null then raise exception 'Escola nao encontrada.' using errcode='P0002';end if;
  if op='school_update' then
   nm:=trim(regexp_replace(args->>'name','\s+',' ','g'));city:=nullif(trim(args->>'municipality'),'');
   if nm is null or length(nm) not between 2 and 160 or (city is not null and length(city) not between 2 and 160) then raise exception 'Confira o nome e municipio.' using errcode='22023';end if;
   update public.escolas set nome=nm,municipio=city where id=sid returning * into e;
  elsif op='school_delete' then
   if exists(select 1 from public.alunos where escola_id=sid) or exists(select 1 from public.turmas where escola_id=sid) or exists(select 1 from public.evento_escolas where escola_id=sid) then raise exception 'A escola possui alunos, turmas ou eventos vinculados e nao pode ser excluida.' using errcode='22023';end if;
   delete from public.escolas where id=sid;return jsonb_build_object('deleted',true);
  end if;
  if op in('school_get','school_update') then return jsonb_build_object('id',e.id,'name',e.nome,'municipality',e.municipio,'createdAt',e.criado_em,'classes',coalesce((select jsonb_agg(jsonb_build_object('id',id,'name',nome,'schoolYear',ano_letivo) order by ano_letivo desc,clube_private.nome_ordenacao(nome),id) from public.turmas where escola_id=sid),'[]'));end if;
  cid:=nullif(args->>'classId','')::uuid;
  if cid is not null and not exists(select 1 from public.turmas where id=cid and escola_id=sid) then raise exception 'Turma nao pertence a escola selecionada.' using errcode='22023';end if;
  if op='credentials' then
   return jsonb_build_object('school',e.nome,'students',coalesce((select jsonb_agg(jsonb_build_object('id',a.id,'name',coalesce(a.nome_completo,p.nome),'className',coalesce(nullif(a.turma,''),'Sem turma'),'schoolYear',a.ano_letivo,'encrypted',x.credencial_cifrada) order by clube_private.nome_ordenacao(coalesce(a.nome_completo,p.nome)),a.id) from public.alunos a left join public.perfis p on p.id=a.perfil_id left join clube_private.acessos x on x.aluno_id=a.id where a.escola_id=sid and a.excluido_em is null and (cid is null or a.turma_id=cid)),'[]'));
  end if;
  if args->>'period'='today' then first_day:=clube_private.hoje_leitura();last_day:=first_day;
  elsif args->>'period'='7days' then last_day:=clube_private.hoje_leitura();first_day:=last_day-6;
  elsif args->>'period'='30days' then last_day:=clube_private.hoje_leitura();first_day:=last_day-29;
  elsif args->>'period'='custom' then first_day:=(args->>'from')::date;last_day:=(args->>'to')::date;if first_day is null or last_day is null or last_day<first_day then raise exception 'Intervalo invalido.' using errcode='22023';end if;end if;
  return (with filtered as(select a.id,coalesce(a.nome_completo,p.nome) name,a.data_nascimento as "birthDate",clube_private.idade_aluno(a.id) age,coalesce(nullif(a.turma,''),'Sem turma') as "className",a.turma_id as "classId",a.ano_letivo as "schoolYear",a.criado_em as "createdAt",a.situacao status,x.credencial_cifrada encrypted from public.alunos a left join public.perfis p on p.id=a.perfil_id left join clube_private.acessos x on x.aluno_id=a.id where a.escola_id=sid and a.excluido_em is null and (cid is null or a.turma_id=cid) and (coalesce(args->>'age','')='' or clube_private.idade_aluno(a.id)=(args->>'age')::integer) and (search='' or strpos(clube_private.nome_ordenacao(coalesce(a.nome_completo,p.nome)),clube_private.nome_ordenacao(search))>0) and (first_day is null or(a.criado_em>=first_day::timestamp at time zone 'America/Fortaleza' and a.criado_em<(last_day+1)::timestamp at time zone 'America/Fortaleza'))),paged as(select * from filtered order by clube_private.nome_ordenacao(name),id limit page_size offset (page_number-1)*page_size) select jsonb_build_object('students',coalesce((select jsonb_agg(to_jsonb(p) order by clube_private.nome_ordenacao(p.name),p.id) from paged p),'[]'),'total',(select count(*) from filtered)));
 end if;
 if op='classes_list' then
  return (with filtered as(select t.id,t.escola_id as "schoolId",s.nome school,t.nome name,t.ano_letivo as "schoolYear",(select count(*) from public.alunos a where a.turma_id=t.id and a.excluido_em is null) as students from public.turmas t join public.escolas s on s.id=t.escola_id where (coalesce(args->>'schoolId','')='' or t.escola_id=(args->>'schoolId')::uuid) and (coalesce(args->>'schoolYear','')='' or t.ano_letivo=(args->>'schoolYear')::integer) and (search='' or strpos(clube_private.nome_ordenacao(t.nome||' '||s.nome),clube_private.nome_ordenacao(search))>0)),paged as(select * from filtered order by clube_private.nome_ordenacao(school),clube_private.nome_ordenacao(name),"schoolYear" desc,id limit page_size offset (page_number-1)*page_size) select jsonb_build_object('classes',coalesce((select jsonb_agg(to_jsonb(p) order by clube_private.nome_ordenacao(p.school),clube_private.nome_ordenacao(p.name),p."schoolYear" desc,p.id) from paged p),'[]'),'total',(select count(*) from filtered),'schools',(select coalesce(jsonb_agg(jsonb_build_object('id',id,'name',nome) order by clube_private.nome_ordenacao(nome)),'[]') from public.escolas)));
 end if;
 if op in('class_save','class_delete') then
  cid:=nullif(args->>'id','')::uuid;
  if cid is not null then select * into c from public.turmas where id=cid for update;if c.id is null then raise exception 'Turma nao encontrada.' using errcode='P0002';end if;end if;
  if op='class_delete' then
   if exists(select 1 from public.alunos where turma_id=cid) then raise exception 'A turma possui alunos vinculados e nao pode ser excluida.' using errcode='22023';end if;
   delete from public.turmas where id=cid;return jsonb_build_object('deleted',true);
  end if;
  sid:=(args->>'schoolId')::uuid;nm:=trim(regexp_replace(args->>'name','\s+',' ','g'));year_value:=(args->>'schoolYear')::integer;
  if nm is null or length(nm) not between 1 and 60 or year_value is null or year_value not between 2000 and 2100 or not exists(select 1 from public.escolas where id=sid) then raise exception 'Dados da turma invalidos.' using errcode='22023';end if;
  if c.id is not null and c.escola_id<>sid and exists(select 1 from public.alunos where turma_id=c.id) then raise exception 'Nao e permitido mover uma turma com alunos para outra escola.' using errcode='22023';end if;
  if exists(select 1 from public.turmas t where t.escola_id=sid and t.nome_normalizado=lower(nm) and t.ano_letivo=year_value and t.id is distinct from cid) then raise exception 'Esta turma ja existe nesta escola e ano letivo.' using errcode='22023';end if;
  insert into public.turmas(id,escola_id,nome,ano_letivo) values(coalesce(cid,gen_random_uuid()),sid,nm,year_value) on conflict(id) do update set escola_id=excluded.escola_id,nome=excluded.nome,ano_letivo=excluded.ano_letivo returning * into c;
  update public.alunos set turma=c.nome,ano_letivo=c.ano_letivo where turma_id=c.id;
  return jsonb_build_object('id',c.id,'schoolId',c.escola_id,'name',c.nome,'schoolYear',c.ano_letivo);
 end if;
 return clube_private.escolas_antes_modulo(op,args);
end $$;
revoke all on function public.clube_escolas(text,jsonb) from public,anon;
grant execute on function public.clube_escolas(text,jsonb) to authenticated;
notify pgrst,'reload schema';
commit;
