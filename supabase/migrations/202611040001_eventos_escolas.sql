begin;
-- Reutiliza escolas/alunos e as selecoes individuais existentes.
create table public.evento_escolas(
 evento_id uuid not null references public.eventos_leitura(id),escola_id uuid not null references public.escolas(id),
 criado_em timestamptz not null default now(),primary key(evento_id,escola_id));
create index evento_escolas_escola_idx on public.evento_escolas(escola_id,evento_id);
alter table public.evento_escolas enable row level security;
revoke all on public.evento_escolas from public,anon,authenticated;
alter table public.eventos_leitura add column escolas_revisar boolean not null default true;
alter table public.eventos_leitura alter column escolas_revisar set default false;
-- Migra somente escolas de participantes existentes. Nunca libera todas as escolas.
insert into public.evento_escolas(evento_id,escola_id)
 select distinct p.evento_id,a.escola_id from public.evento_alunos p join public.alunos a on a.id=p.aluno_id where a.escola_id is not null;

create function clube_private.evento_escola_permitida(event_id uuid,student uuid) returns boolean language sql stable security definer set search_path='' as $$
 select exists(select 1 from public.alunos a join public.evento_escolas v on v.escola_id=a.escola_id
 where a.id=student and a.situacao='ativo' and a.excluido_em is null and v.evento_id=event_id)
$$;
create policy evento_escolas_autorizadas on public.evento_escolas for select to authenticated using(
 clube_private.administrador() or clube_private.evento_escola_permitida(evento_id,clube_private.aluno_atual()));
-- Sem grants diretos: a consulta e o gerenciamento passam pelos RPCs autenticados.
alter function clube_private.evento_disponivel(uuid,uuid) rename to evento_disponivel_antes_escolas;
create function clube_private.evento_disponivel(event_id uuid,student uuid) returns boolean language sql stable security definer set search_path='' as $$
 select clube_private.evento_escola_permitida(event_id,student) and clube_private.evento_disponivel_antes_escolas(event_id,student)
 and exists(select 1 from public.evento_alunos p join public.evento_leituras l on l.participante_id=p.id where p.evento_id=event_id and p.aluno_id=student)
$$;
-- As policies referenciam OIDs; reatribui explicitamente a funcao apos o rename.
alter policy eventos_autorizados on public.eventos_leitura using(clube_private.administrador() or clube_private.evento_disponivel(id,clube_private.aluno_atual()));
alter policy participantes_proprios on public.evento_alunos using(clube_private.administrador() or(aluno_id=clube_private.aluno_atual() and clube_private.evento_disponivel(evento_id,clube_private.aluno_atual())));
alter policy leituras_proprias on public.evento_leituras using(clube_private.administrador() or exists(select 1 from public.evento_alunos p where p.id=participante_id and p.aluno_id=clube_private.aluno_atual() and clube_private.evento_disponivel(p.evento_id,clube_private.aluno_atual())));
alter function clube_private.evento_elegivel(public.eventos_leitura,public.alunos) rename to evento_elegivel_antes_escolas;
create function clube_private.evento_elegivel(e public.eventos_leitura,a public.alunos) returns boolean language sql stable security definer set search_path='' as $$
 select e.ativo and not e.arquivado and clube_private.evento_escola_permitida(e.id,a.id) and clube_private.evento_elegivel_antes_escolas(e,a)
$$;
alter function clube_private.evento_json(public.eventos_leitura) rename to evento_json_antes_escolas;
create function clube_private.evento_json(e public.eventos_leitura) returns jsonb language sql stable security definer set search_path='' as $$
 select clube_private.evento_json_antes_escolas(e)||jsonb_build_object(
 'schoolIds',coalesce((select jsonb_agg(v.escola_id order by v.escola_id) from public.evento_escolas v where v.evento_id=e.id),'[]'),
 'schools',coalesce((select jsonb_agg(jsonb_build_object('id',s.id,'name',s.nome) order by s.nome,s.id) from public.evento_escolas v join public.escolas s on s.id=v.escola_id where v.evento_id=e.id),'[]'),
 'schoolsNeedReview',e.escolas_revisar or not exists(select 1 from public.evento_escolas v where v.evento_id=e.id))
$$;

alter function public.clube_eventos(text,jsonb) rename to eventos_antes_escolas;
alter function public.eventos_antes_escolas(text,jsonb) set schema clube_private;
create function public.clube_eventos(op text,args jsonb default '{}') returns jsonb language plpgsql security definer set search_path='' as $$
declare result jsonb;e public.eventos_leitura;school_ids uuid[];event_id uuid;replayed boolean:=false;
begin
 if op='mine' then
  result:=clube_private.eventos_antes_escolas(op,args);
  return coalesce((select jsonb_agg(x-'schoolIds'-'schools'-'schoolsNeedReview' order by ord) from jsonb_array_elements(result) with ordinality r(x,ord)),'[]');
 end if;
 if op='enter' then return clube_private.eventos_antes_escolas(op,args);end if;
 if not clube_private.administrador() then raise exception 'Administrador obrigatorio' using errcode='42501';end if;
 if op='school_options' then return public.clube_gestao('schools');end if;
 if op in('save','schools_save') then
  if op='schools_save' or coalesce(args->>'id','')<>'' then
   select * into e from public.eventos_leitura where id=(args->>'id')::uuid for update;
   if e.id is null then raise exception 'Evento nao encontrado' using errcode='P0002';end if;
  elsif args?'requestId' then
   perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended(args->>'requestId',0));
   select * into e from public.eventos_leitura where id=(args->>'requestId')::uuid for update;
   replayed:=e.id is not null;
  end if;
  if not(args?'schoolIds') then
   if e.id is null then raise exception 'Selecione as escolas participantes do evento.' using errcode='22023';end if;
   select coalesce(jsonb_agg(escola_id),'[]') into result from public.evento_escolas where evento_id=e.id;
   args:=args||jsonb_build_object('schoolIds',result);
  end if;
  if jsonb_typeof(args->'schoolIds') is distinct from 'array' or jsonb_array_length(args->'schoolIds')>10000 then raise exception 'Escolas participantes invalidas.' using errcode='22023';end if;
  if exists(select 1 from jsonb_array_elements_text(args->'schoolIds') x where x is null or x!~*'^[a-f0-9]{8}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{12}$') then raise exception 'Escola invalida.' using errcode='22023';end if;
  select coalesce(array_agg(x::uuid),array[]::uuid[]) into school_ids from jsonb_array_elements_text(args->'schoolIds') x;
  if (select count(distinct x) from unnest(school_ids) x)<>cardinality(school_ids) or exists(select 1 from unnest(school_ids) x where not exists(select 1 from public.escolas s where s.id=x)) then raise exception 'Selecione escolas cadastradas, sem duplicatas.' using errcode='22023';end if;
  if replayed then return clube_private.evento_json(e);end if;
  if op='save' then
   if coalesce((args->>'active')::boolean,false) and cardinality(school_ids)=0 then raise exception 'Selecione ao menos uma escola antes de ativar o evento.' using errcode='22023';end if;
   result:=clube_private.eventos_antes_escolas(op,args);event_id:=(result->>'id')::uuid;
  else event_id:=e.id;end if;
  delete from public.evento_escolas v where v.evento_id=event_id and not(v.escola_id=any(school_ids));
  insert into public.evento_escolas(evento_id,escola_id) select event_id,x from unnest(school_ids) x on conflict do nothing;
  update public.eventos_leitura set escolas_revisar=false,atualizado_em=now() where id=event_id returning * into e;
  return clube_private.evento_json(e);
 end if;
 if op in('send','status','delete') then
  select * into e from public.eventos_leitura where id=(args->>'id')::uuid for update;
  if e.id is null then raise exception 'Evento nao encontrado' using errcode='P0002';end if;
  if op='send' then
   if not e.ativo or e.arquivado then raise exception 'Ative o evento antes de distribuir as historias.' using errcode='22023';end if;
   if exists(select 1 from jsonb_array_elements_text(args->'studentIds') x where not clube_private.evento_escola_permitida(e.id,x::uuid)) then raise exception 'Ha alunos de escolas nao vinculadas ao evento. Atualize os destinatarios.' using errcode='22023';end if;
  elsif op='status' and coalesce((args->>'active')::boolean,false) and not exists(select 1 from public.evento_escolas where evento_id=e.id) then
   raise exception 'Selecione as escolas participantes antes de ativar o evento.' using errcode='22023';
  elsif op='delete' and not exists(select 1 from public.evento_alunos where evento_id=e.id) then delete from public.evento_escolas where evento_id=e.id;
  end if;
 end if;
 return clube_private.eventos_antes_escolas(op,args);
end $$;
revoke all on function public.clube_eventos(text,jsonb) from public,anon;
grant execute on function public.clube_eventos(text,jsonb) to authenticated;

-- Revalida todos os endpoints de tentativa, inclusive atividades ja concluidas.
alter function public.clube_leitura(text,jsonb) rename to leitura_antes_escolas;
alter function public.leitura_antes_escolas(text,jsonb) set schema clube_private;
create function public.clube_leitura(op text,args jsonb default '{}') returns jsonb language plpgsql security definer set search_path='' as $$
declare student uuid;event_id uuid;
begin
 student:=clube_private.aluno_atual();if student is null then raise exception 'Aluno nao identificado' using errcode='42501';end if;
 if op in('get','page','stage','answer','finish') then
  select p.evento_id into event_id from public.tentativas t join public.evento_alunos p on p.id=t.evento_participante_id where t.id=(args->>'id')::uuid and t.aluno_id=student;
  if event_id is not null and not clube_private.evento_disponivel(event_id,student) then raise exception 'Este evento nao esta disponivel no momento. Seu progresso esta salvo.' using errcode='42501';end if;
 end if;
 return clube_private.leitura_antes_escolas(op,args);
end $$;
revoke all on function public.clube_leitura(text,jsonb) from public,anon;
grant execute on function public.clube_leitura(text,jsonb) to authenticated;
alter function public.clube_api(text,jsonb) rename to api_antes_escolas;
alter function public.api_antes_escolas(text,jsonb) set schema clube_private;
create function public.clube_api(op text,args jsonb default '{}') returns jsonb language plpgsql security definer set search_path='' as $$
begin
 if op in('get','answer','finish') and exists(select 1 from public.tentativas where id=(args->>'id')::uuid and evento_participante_id is not null) then return public.clube_leitura(op,args);end if;
 return clube_private.api_antes_escolas(op,args);
end $$;
revoke all on function public.clube_api(text,jsonb) from public,anon;
grant execute on function public.clube_api(text,jsonb) to authenticated;
alter function clube_private.leitura_tentativa(public.tentativas) rename to tentativa_antes_escolas;
create function clube_private.leitura_tentativa(a public.tentativas) returns jsonb language plpgsql stable security definer set search_path='' as $$
declare result jsonb;event_id uuid;
begin
 result:=clube_private.tentativa_antes_escolas(a);
 if a.evento_participante_id is not null then
  select evento_id into event_id from public.evento_alunos where id=a.evento_participante_id;
  if not clube_private.evento_disponivel(event_id,a.aluno_id) then
   result:=jsonb_set(result,'{activity}',jsonb_build_object('id',a.texto_id,'title',result->'activity'->>'title','content','','pages','[]'::jsonb,'questions','[]'::jsonb,'level',a.nivel,'age',''));
  end if;
 end if;return result;
end $$;
revoke all on function clube_private.evento_escola_permitida(uuid,uuid),clube_private.evento_disponivel_antes_escolas(uuid,uuid),clube_private.evento_disponivel(uuid,uuid),clube_private.evento_elegivel_antes_escolas(public.eventos_leitura,public.alunos),clube_private.evento_elegivel(public.eventos_leitura,public.alunos),clube_private.evento_json_antes_escolas(public.eventos_leitura),clube_private.evento_json(public.eventos_leitura),clube_private.eventos_antes_escolas(text,jsonb),clube_private.leitura_antes_escolas(text,jsonb),clube_private.api_antes_escolas(text,jsonb),clube_private.tentativa_antes_escolas(public.tentativas),clube_private.leitura_tentativa(public.tentativas) from public,anon,authenticated;
-- As politicas existentes de textos e questoes reutilizam esta mesma autorizacao.
-- Um texto tambem atribuido na jornada comum continua acessivel nessa jornada.
create or replace function public.clube_texto_permitido(text_id text) returns boolean language sql stable security definer set search_path='' as $$
 with identity as(select clube_private.aluno_atual() student)
 select clube_private.administrador() or exists(select 1 from identity i where
 (clube_private.texto_autorizado(i.student,text_id) and (
 exists(select 1 from public.textos t where t.id=text_id and t.obrigatorio)
 or exists(select 1 from clube_private.atribuicoes_jornada x where x.aluno_id=i.student and x.texto_id=text_id and x.jornada_id=(select id from public.jornadas where aluno_id=i.student order by ciclo desc limit 1))
 or exists(select 1 from public.tentativas t where t.aluno_id=i.student and t.texto_id=text_id and t.evento_participante_id is null)
 or(not exists(select 1 from public.evento_historias h where h.texto_id=text_id) and not exists(select 1 from public.evento_leituras l where l.texto_id=text_id))))
 or exists(select 1 from public.evento_alunos p join public.evento_leituras l on l.participante_id=p.id where p.aluno_id=i.student and l.texto_id=text_id and clube_private.evento_disponivel(p.evento_id,i.student)))
$$;
notify pgrst,'reload schema';
commit;
