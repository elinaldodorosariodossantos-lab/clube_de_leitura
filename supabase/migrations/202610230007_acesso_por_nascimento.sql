begin;
-- A data civil da escola é usada também quando o servidor está em UTC.
create function clube_private.hoje_leitura() returns date language sql stable set search_path='' as $$select (now() at time zone 'America/Fortaleza')::date$$;
create function clube_private.idade_em(nascimento date,referencia date) returns integer language sql immutable set search_path='' as $$
 select case when nascimento is null or not isfinite(nascimento) or nascimento>referencia or nascimento<referencia-interval '120 years' then null else extract(year from age(referencia,nascimento))::integer end
$$;
create function clube_private.idade_aluno(student uuid) returns integer language sql stable security definer set search_path='' as $$
 select clube_private.idade_em(data_nascimento,clube_private.hoje_leitura()) from public.alunos where id=student
$$;
create function clube_private.faixa_idades(faixa text) returns integer[] language plpgsql immutable set search_path='' as $$
declare parts text[];lo integer;hi integer;
begin
 parts:=regexp_match(lower(trim(faixa)),'^(de\s+)?([0-9]{1,2})\s*(a|até|ate|[-–])\s*([0-9]{1,2})(\s*anos?)?$');
 if parts is not null then lo:=parts[2]::integer;hi:=parts[4]::integer;
 else
  parts:=regexp_match(lower(trim(faixa)),'^([0-9]{1,2})(\s*anos?)?(\s*(ou\s+mais|e\s+mais|\+))?$');
  if parts is null then return null;end if;
  lo:=parts[1]::integer;hi:=case when parts[3] is not null then 19 else lo end;
 end if;
 if lo<4 or hi>19 or hi<lo then return null;end if;
 return array[lo,hi];
end $$;
create or replace function clube_private.evento_faixa(age_text text,min_age integer,max_age integer) returns boolean language sql immutable set search_path='' as $$
 select coalesce(min_age>=bounds[1] and max_age<=bounds[2] and max_age>=min_age,false) from (select clube_private.faixa_idades(age_text) bounds) s
$$;
create function clube_private.historia_idade(student uuid,faixa text) returns boolean language sql stable security definer set search_path='' as $$
 select clube_private.evento_faixa(faixa,clube_private.idade_aluno(student),clube_private.idade_aluno(student))
$$;
-- As funções existentes passam a filtrar ANTES de contar, sortear e paginar.
do $age_functions$
declare target regprocedure;definition text;updated text;
begin
 foreach target in array array['clube_private.progresso_niveis(uuid)'::regprocedure,'clube_private.leitura_com_eventos_base(text,jsonb)'::regprocedure,'clube_private.clube_leitura_anterior(text,jsonb)'::regprocedure] loop
  definition:=pg_get_functiondef(target);
  updated:=replace(definition,'t.ativo and','t.ativo and clube_private.historia_idade(student,t.faixa_etaria) and');
  updated:=replace(updated,'and status=''started'' and clube_private.texto_autorizado(student,texto_id)','and status=''started'' and exists(select 1 from clube_private.conteudos_tentativas s where s.tentativa_id=public.tentativas.id and clube_private.historia_idade(student,s.atividade->>''age'')) and clube_private.texto_autorizado(student,texto_id)');
  if updated=definition then raise exception 'Função % incompatível com a migração de idades.',target;end if;
  execute updated;
 end loop;
 foreach target in array array['public.clube_eventos(text,jsonb)'::regprocedure,'clube_private.eventos_antes_idades(text,jsonb)'::regprocedure,'clube_private.evento_destinatarios(public.eventos_leitura,jsonb)'::regprocedure,'clube_private.evento_elegivel(public.eventos_leitura,public.alunos)'::regprocedure] loop
  definition:=pg_get_functiondef(target);
  updated:=replace(definition,'(e.inicio at time zone ''America/Fortaleza'')::date','clube_private.hoje_leitura()');
  updated:=replace(updated,'extract(year from age(clube_private.hoje_leitura(),a.data_nascimento))::integer','clube_private.idade_aluno(a.id)');
  updated:=replace(updated,'extract(year from age(clube_private.hoje_leitura(),student_row.data_nascimento))','clube_private.idade_aluno(student_row.id)');
  if updated=definition then raise exception 'Função de evento % incompatível.',target;end if;
  execute updated;
 end loop;
 definition:=pg_get_functiondef('clube_private.aluno_json(uuid)'::regprocedure);
 execute replace(definition,'''age'',a.idade','''age'',clube_private.idade_aluno(a.id)');
 definition:=pg_get_functiondef('clube_private.leitura_estado(uuid)'::regprocedure);
 execute replace(definition,'and a.status=''started''','and a.status=''started'' and exists(select 1 from clube_private.conteudos_tentativas s where s.tentativa_id=a.id and clube_private.historia_idade(student,s.atividade->>''age''))');
end $age_functions$;
create or replace function clube_private.evento_elegivel(e public.eventos_leitura,a public.alunos) returns boolean language sql stable security definer set search_path='' as $$
 select coalesce(a.situacao='ativo' and clube_private.idade_aluno(a.id) is not null and case when jsonb_array_length(e.configuracoes)=0 then
 clube_private.idade_aluno(a.id) between e.idade_min and e.idade_max and clube_private.nivel_liberado(a.id,e.nivel)
 else exists(select 1 from jsonb_array_elements(e.configuracoes) c cross join lateral jsonb_array_elements(c->'levels') l where (c->>'age')::integer=clube_private.idade_aluno(a.id) and clube_private.nivel_liberado(a.id,l->>'level')) end,false)
$$;
create or replace function clube_private.texto_autorizado(student uuid,text_id text) returns boolean language sql stable security definer set search_path='' as $$
 select exists(select 1 from public.textos t where t.id=text_id and t.ativo and t.excluido_em is null and clube_private.historia_idade(student,t.faixa_etaria) and clube_private.texto_pronto(t.id) and clube_private.nivel_liberado(student,t.nivel))
$$;
alter function clube_private.nivel_liberado(uuid,text) rename to nivel_antes_nascimento;
create function clube_private.nivel_liberado(student uuid,level_id text) returns boolean language sql stable security definer set search_path='' as $$
 select clube_private.idade_aluno(student) is not null and exists(select 1 from clube_private.progresso_niveis(student) where id=level_id and available>0) and clube_private.nivel_antes_nascimento(student,level_id)
$$;
-- Estado público: apenas blocos com conteúdo compatível; histórico de pontos permanece.
alter function clube_private.leitura_estado(uuid) rename to estado_antes_nascimento;
-- Toda resposta que inclui um snapshot passa pela mesma verificação, inclusive retomadas.
create or replace function clube_private.leitura_tentativa(a public.tentativas) returns jsonb language sql stable security definer set search_path='' as $$
 select clube_private.attempt_json(a)||jsonb_build_object('journeyId',a.jornada_id,'level',a.nivel,'stage',a.etapa,'index',a.questao_atual,'pageIndex',a.pagina_atual,
 'activity',(select case when clube_private.historia_idade(a.aluno_id,atividade->>'age') then atividade else jsonb_build_object('id',a.texto_id,'title',atividade->>'title','content','','pages','[]'::jsonb,'questions','[]'::jsonb,'level',a.nivel,'age','') end from clube_private.conteudos_tentativas where tentativa_id=a.id))
$$;
create function clube_private.leitura_estado(student uuid) returns jsonb language sql stable security definer set search_path='' as $$
 select result||jsonb_build_object('levels',coalesce((select jsonb_agg(x order by ord) from jsonb_array_elements(result->'levels') with ordinality as rows(x,ord) where (x->>'available')::integer>0),'[]'),
 'ageAccessError',case when clube_private.idade_aluno(student) is null then 'Peça à escola para corrigir sua data de nascimento no cadastro para acessar as histórias.' else null end)
 from (select clube_private.estado_antes_nascimento(student) result) s
$$;
-- Mantém período e vínculos; uma atribuição nunca é refeita em um aniversário.
create or replace function clube_private.evento_disponivel(event_id uuid,student uuid) returns boolean language sql stable security definer set search_path='' as $$
 select student is not null and clube_private.idade_aluno(student) is not null and exists(
  select 1 from public.eventos_leitura e join public.evento_alunos p on p.evento_id=e.id join public.alunos a on a.id=p.aluno_id
  where e.id=event_id and p.aluno_id=student and a.situacao='ativo' and e.ativo and not e.arquivado and now()>=e.inicio and now()<e.fim
  and clube_private.idade_aluno(student) between e.idade_min and e.idade_max
  and (jsonb_array_length(e.configuracoes)=0 or exists(select 1 from jsonb_array_elements(e.configuracoes) c where (c->>'age')::integer=clube_private.idade_aluno(student)))
  and not exists(select 1 from public.evento_leituras l join clube_private.evento_conteudos s on s.leitura_id=l.id left join public.tentativas t on t.id=l.tentativa_id
   where l.participante_id=p.id and coalesce(t.status,'started')<>'completed' and (not clube_private.historia_idade(student,s.atividade->>'age') or not clube_private.nivel_liberado(student,s.atividade->>'level'))))
$$;
alter function public.clube_leitura(text,jsonb) rename to leitura_antes_nascimento;
alter function public.leitura_antes_nascimento(text,jsonb) set schema clube_private;
create function public.clube_leitura(op text,args jsonb default '{}') returns jsonb language plpgsql security definer set search_path='' as $$
declare student uuid;a public.tentativas;result jsonb;compatible boolean;
begin
 student:=clube_private.aluno_atual();if student is null then raise exception 'Aluno não identificado' using errcode='42501';end if;
 if op='state' then return clube_private.leitura_antes_nascimento(op,args);end if;
 if op in ('get','page','stage','answer','finish') then
  select * into a from public.tentativas where id=(args->>'id')::uuid and aluno_id=student;
  if a.id is null then raise exception 'Tentativa não encontrada' using errcode='42501';end if;
  select clube_private.historia_idade(student,atividade->>'age') into compatible from clube_private.conteudos_tentativas where tentativa_id=a.id;
  if a.status='completed' and op in ('get','finish') then
   result:=clube_private.leitura_antes_nascimento(op,args);
   if not coalesce(compatible,false) then result:=jsonb_set(result,'{activity}',jsonb_build_object('id',a.texto_id,'title',result->'activity'->>'title','content','','pages','[]'::jsonb,'questions','[]'::jsonb,'level',a.nivel,'age',''));end if;
   return result;
  end if;
  if clube_private.idade_aluno(student) is null then raise exception 'Peça à escola para corrigir sua data de nascimento no cadastro para acessar as histórias.' using errcode='22023';end if;
  if not coalesce(compatible,false) then
   raise exception 'Esta história não está disponível para sua idade atual. Seu progresso está preservado.' using errcode='22023';end if;
 end if;
 if clube_private.idade_aluno(student) is null then raise exception 'Peça à escola para corrigir sua data de nascimento no cadastro para acessar as histórias.' using errcode='22023';end if;
 return clube_private.leitura_antes_nascimento(op,args);
end $$;
revoke all on function public.clube_leitura(text,jsonb) from public,anon;
grant execute on function public.clube_leitura(text,jsonb) to authenticated;
-- O módulo legado e consultas manipuladas também respeitam a data confiável.
alter function public.clube_api(text,jsonb) rename to api_antes_nascimento;
alter function public.api_antes_nascimento(text,jsonb) set schema clube_private;
create function public.clube_api(op text,args jsonb default '{}') returns jsonb language plpgsql security definer set search_path='' as $$
declare student uuid;a public.tentativas;
begin
 student:=coalesce(clube_private.aluno_atual(),(select id from public.alunos where perfil_id=auth.uid() and situacao='ativo'));
 if student is null then raise exception 'Aluno não identificado' using errcode='42501';end if;
 if op='history' then return clube_private.api_antes_nascimento(op,args);end if;
 if op in ('get','answer','finish') then
  select * into a from public.tentativas where id=(args->>'id')::uuid and aluno_id=student;
  if a.id is null then raise exception 'Tentativa não encontrada' using errcode='42501';end if;
  if not (a.status='completed' and op in ('get','finish')) and not exists(select 1 from clube_private.conteudos_tentativas s where s.tentativa_id=a.id and clube_private.historia_idade(student,s.atividade->>'age')) then raise exception 'História incompatível com sua idade atual.' using errcode='22023';end if;
 elsif not exists(select 1 from public.textos where id='passarinho' and clube_private.historia_idade(student,faixa_etaria)) then raise exception 'História incompatível com sua idade atual. Confira sua data de nascimento com a escola.' using errcode='22023';end if;
 return clube_private.api_antes_nascimento(op,args);
end $$;
revoke all on function public.clube_api(text,jsonb) from public,anon;
grant execute on function public.clube_api(text,jsonb) to authenticated;
-- Faixas inválidas não podem ser salvas ou publicadas pela administração.
alter function public.clube_gestao(text,jsonb) rename to gestao_antes_nascimento;
alter function public.gestao_antes_nascimento(text,jsonb) set schema clube_private;
create function public.clube_gestao(op text,args jsonb default '{}') returns jsonb language plpgsql security definer set search_path='' as $$
begin
 if not clube_private.administrador() then raise exception 'Administrador obrigatório' using errcode='42501';end if;
 if op='story_save' and clube_private.faixa_idades(args->>'age') is null then raise exception 'Informe uma idade de 4 a 19 anos ou faixa válida, como 5 a 7 anos.' using errcode='22023';end if;
 return clube_private.gestao_antes_nascimento(op,args);
end $$;
revoke all on function public.clube_gestao(text,jsonb) from public,anon;
grant execute on function public.clube_gestao(text,jsonb) to authenticated;
revoke all on function clube_private.hoje_leitura(),clube_private.idade_em(date,date),clube_private.idade_aluno(uuid),clube_private.faixa_idades(text),clube_private.historia_idade(uuid,text),clube_private.nivel_antes_nascimento(uuid,text),clube_private.nivel_liberado(uuid,text),clube_private.estado_antes_nascimento(uuid),clube_private.leitura_estado(uuid),clube_private.leitura_antes_nascimento(text,jsonb),clube_private.api_antes_nascimento(text,jsonb),clube_private.gestao_antes_nascimento(text,jsonb) from public,anon,authenticated;
notify pgrst,'reload schema';
commit;
