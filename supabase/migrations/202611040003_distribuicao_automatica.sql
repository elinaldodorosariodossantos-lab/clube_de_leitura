begin;
alter table public.eventos_leitura add column distribuicao_automatica boolean not null default false,add column versao_configuracao integer not null default 1;
alter table public.evento_alunos add column versao_configuracao integer not null default 1;
-- O catalogo e compartilhado; cada evento conserva seu proprio conjunto e snapshots.
create function clube_private.evento_pool(age_value integer,level_id text) returns text[] language sql stable security definer set search_path='' as $$
 select coalesce(array_agg(t.id order by t.id),array[]::text[]) from public.textos t where t.ativo and t.excluido_em is null and t.paginas_publicadas
 and t.nivel=level_id and clube_private.evento_faixa(t.faixa_etaria,age_value,age_value) and clube_private.texto_pronto(t.id)
$$;
create function clube_private.evento_config_automatica(configs jsonb) returns jsonb language plpgsql security definer set search_path='' as $$
declare a jsonb;l jsonb;pool text[];items jsonb;result jsonb:='[]';amount numeric;age_value integer;
begin
 if jsonb_typeof(configs) is distinct from 'array' or jsonb_array_length(configs) not between 1 and 16 then raise exception 'Configure as idades do evento.' using errcode='22023';end if;
 for a in select value from jsonb_array_elements(configs) loop
  if coalesce(a->>'age','')!~'^[0-9]+$' or (a->>'age')::integer not between 4 and 19 or jsonb_typeof(a->'levels') is distinct from 'array' then raise exception 'Idade ou niveis invalidos.' using errcode='22023';end if;
  age_value:=(a->>'age')::integer;items:='[]';
  for l in select value from jsonb_array_elements(a->'levels') loop
   if l->>'level' is null or l->>'level' not in('facil','medio','dificil') or jsonb_typeof(l->'quantity') is distinct from 'number' then raise exception 'Quantidade ou nivel invalido.' using errcode='22023';end if;
   amount:=(l->>'quantity')::numeric;
   if amount<0 or amount<>trunc(amount) or amount>2147483647 then raise exception 'Informe uma quantidade inteira maior ou igual a zero.' using errcode='22023';end if;
   if amount=0 then continue;end if;
   pool:=clube_private.evento_pool(age_value,l->>'level');
   if cardinality(pool)<amount then raise exception 'Existem apenas % historias disponiveis para % anos no nivel %. Cadastre mais historias ou reduza a quantidade solicitada.',cardinality(pool),age_value,case l->>'level' when 'facil' then 'Facil' when 'medio' then 'Medio' else 'Dificil' end using errcode='22023';end if;
   items:=items||jsonb_build_array(jsonb_build_object('level',l->>'level','quantity',amount,'storyIds',to_jsonb(pool)));
  end loop;
  if jsonb_array_length(items)=0 then raise exception 'Habilite ao menos um nivel para % anos.',age_value using errcode='22023';end if;
  result:=result||jsonb_build_array(jsonb_build_object('age',age_value,'levels',items));
 end loop;return result;
end $$;
create function clube_private.evento_auto_elegivel(e public.eventos_leitura,student uuid) returns boolean language sql stable security definer set search_path='' as $$
 select e.distribuicao_automatica and e.ativo and not e.arquivado and now()>=e.inicio and now()<e.fim and clube_private.evento_escola_permitida(e.id,student)
 and exists(select 1 from jsonb_array_elements(e.configuracoes) c where (c->>'age')::integer=clube_private.idade_aluno(student))
$$;
create function clube_private.evento_auto_atribuir(event_id uuid,student uuid) returns uuid language plpgsql security definer set search_path='' as $$
declare e public.eventos_leitura;pid uuid;age_value integer;l jsonb;pool text[];chosen text[];all_ids text[]:=array[]::text[];cfg jsonb:='[]';signature text;i integer;
begin
 -- Evento antes de aluno: mesma ordem usada no envio e na leitura.
 select * into e from public.eventos_leitura where id=event_id for update;
 perform 1 from public.alunos where id=student for update;
 if not clube_private.evento_auto_elegivel(e,student) then raise exception 'Evento indisponivel para sua escola, idade ou periodo.' using errcode='42501';end if;
 select id into pid from public.evento_alunos where evento_id=event_id and aluno_id=student;
 if pid is not null then return pid;end if;
 age_value:=clube_private.idade_aluno(student);
 -- Trava a biblioteca antes de validar e capturar os snapshots.
 perform 1 from public.textos where ativo and excluido_em is null order by id for share;
 for l in select v from jsonb_array_elements(e.configuracoes) c cross join lateral jsonb_array_elements(c->'levels') v where (c->>'age')::integer=age_value order by array_position(array['facil','medio','dificil'],v->>'level') loop
  -- Revalida o conjunto deste evento; nunca usa IDs enviados pelo aluno.
  select coalesce(array_agg(id order by id),array[]::text[]) into pool from unnest(clube_private.evento_pool(age_value,l->>'level')) id where id in(select jsonb_array_elements_text(l->'storyIds'));
  if cardinality(pool)<(l->>'quantity')::integer then raise exception 'Historias insuficientes para % anos / %. Solicite a escola para revisar o evento.',age_value,l->>'level' using errcode='22023';end if;
  chosen:=clube_private.evento_sortear(e.id,student,age_value,l->>'level',pool,(l->>'quantity')::integer);
  select jsonb_agg(x order by x)::text into signature from unnest(chosen) x;
  cfg:=cfg||jsonb_build_array(jsonb_build_object('level',l->>'level','quantity',cardinality(chosen),'storyIds',to_jsonb(chosen),'signature',signature,'configurationVersion',e.versao_configuracao));all_ids:=all_ids||chosen;
 end loop;
 insert into public.evento_alunos(evento_id,aluno_id,nivel,idade_min,idade_max,referencia,assinatura,idade_referencia,configuracao,versao_configuracao)
 values(e.id,student,cfg->0->>'level',age_value,age_value,clube_private.hoje_leitura(),to_jsonb(all_ids)::text,age_value,cfg,e.versao_configuracao) returning id into pid;
 for i in 1..cardinality(all_ids) loop perform clube_private.evento_guardar_leitura(pid,all_ids[i],i-1);end loop;
 return pid;
end $$;
-- Niveis futuros atribuidos nao bloqueiam todo o evento; a sequencia e verificada ao entrar.
create or replace function clube_private.evento_disponivel(event_id uuid,student uuid) returns boolean language sql stable security definer set search_path='' as $$
 select case when e.distribuicao_automatica then clube_private.evento_auto_elegivel(e,student)
 and exists(select 1 from public.evento_alunos p where p.evento_id=e.id and p.aluno_id=student)
 and not exists(select 1 from public.evento_alunos p join public.evento_leituras l on l.participante_id=p.id join clube_private.evento_conteudos s on s.leitura_id=l.id left join public.tentativas t on t.id=l.tentativa_id where p.evento_id=e.id and p.aluno_id=student and coalesce(t.status,'started')<>'completed' and not clube_private.historia_idade(student,s.atividade->>'age'))
 else clube_private.evento_escola_permitida(event_id,student) and clube_private.evento_disponivel_antes_escolas(event_id,student) and exists(select 1 from public.evento_alunos p join public.evento_leituras l on l.participante_id=p.id where p.evento_id=event_id and p.aluno_id=student) end from public.eventos_leitura e where e.id=event_id
$$;
-- A progressao da competicao usa os niveis atribuidos neste evento.
create function clube_private.evento_nivel_liberado(pid uuid,level_id text) returns boolean language sql stable security definer set search_path='' as $$
 select exists(select 1 from public.evento_alunos p where p.id=pid and exists(select 1 from jsonb_array_elements(p.configuracao) c where c->>'level'=level_id)
 and (level_id='facil' or clube_private.nivel_liberado(p.aluno_id,level_id) or (
 exists(select 1 from jsonb_array_elements(p.configuracao) c where array_position(array['facil','medio','dificil'],c->>'level')<array_position(array['facil','medio','dificil'],level_id))
 and not exists(select 1 from public.evento_leituras l join clube_private.evento_conteudos s on s.leitura_id=l.id where l.participante_id=p.id and array_position(array['facil','medio','dificil'],s.atividade->>'level')<array_position(array['facil','medio','dificil'],level_id) and not clube_private.resultado_completo(l.tentativa_id)))))
$$;
alter function clube_private.conquista_proximo(uuid,uuid,boolean,text) rename to proximo_antes_automatico;
create function clube_private.conquista_proximo(student uuid,context_id uuid,is_event boolean,level_id text) returns text language plpgsql stable security definer set search_path='' as $$
begin
 if is_event and exists(select 1 from public.evento_alunos p join public.eventos_leitura e on e.id=p.evento_id where p.id=context_id and p.aluno_id=student and e.distribuicao_automatica) then
 return (select c->>'level' from public.evento_alunos p cross join lateral jsonb_array_elements(p.configuracao) c where p.id=context_id and p.aluno_id=student and array_position(array['facil','medio','dificil'],c->>'level')>array_position(array['facil','medio','dificil'],level_id) and clube_private.evento_nivel_liberado(p.id,c->>'level') and clube_private.evento_disponivel(p.evento_id,student) order by array_position(array['facil','medio','dificil'],c->>'level') limit 1);
 end if;return clube_private.proximo_antes_automatico(student,context_id,is_event,level_id);
end $$;
alter function public.clube_eventos(text,jsonb) rename to eventos_antes_automatico;
alter function public.eventos_antes_automatico(text,jsonb) set schema clube_private;
create function public.clube_eventos(op text,args jsonb default '{}') returns jsonb language plpgsql security definer set search_path='' as $$
declare e public.eventos_leitura;result jsonb;student uuid;pid uuid;l record;configs jsonb;created integer:=0;kept integer:=0;old_version integer;old_configs jsonb;replayed boolean:=false;
begin
 if op in('mine','enter') then
  student:=clube_private.aluno_atual();if student is null then raise exception 'Aluno nao identificado' using errcode='42501';end if;
  if op='mine' then
   result:=clube_private.eventos_antes_automatico(op,args);
   for e in select x.* from public.eventos_leitura x where clube_private.evento_auto_elegivel(x,student) and not exists(select 1 from public.evento_alunos p where p.evento_id=x.id and p.aluno_id=student) order by x.inicio,x.id loop
    select c->'levels' into configs from jsonb_array_elements(e.configuracoes) c where (c->>'age')::integer=clube_private.idade_aluno(student);
    result:=result||jsonb_build_array((clube_private.evento_json(e)-'storyIds'-'ageConfigs'-'recipients'-'schoolIds'-'schools'-'schoolsNeedReview')||jsonb_build_object('age',clube_private.idade_aluno(student),'total',(select sum((x->>'quantity')::integer) from jsonb_array_elements(configs) x),'completed',0,'ongoing',false,'assignedLevels',(select jsonb_agg(x-'storyIds') from jsonb_array_elements(configs) x)));
   end loop;
   -- So divulga titulos das historias que pertencem a esta distribuicao.
   return coalesce((select jsonb_agg(x||jsonb_build_object('assignedStories',coalesce((select jsonb_agg(jsonb_build_object('id',r.texto_id,'title',s.atividade->>'title','level',s.atividade->>'level','order',r.ordem,'completed',coalesce(t.status='completed',false)) order by r.ordem) from public.evento_alunos p join public.evento_leituras r on r.participante_id=p.id join clube_private.evento_conteudos s on s.leitura_id=r.id left join public.tentativas t on t.id=r.tentativa_id where p.evento_id=(x->>'id')::uuid and p.aluno_id=student),'[]'))) from jsonb_array_elements(result) x),'[]');
  end if;
  select * into e from public.eventos_leitura where id=(args->>'id')::uuid;
  if e.distribuicao_automatica then
   pid:=clube_private.evento_auto_atribuir(e.id,student);
   select s.atividade->>'level' level into l from public.evento_leituras r join clube_private.evento_conteudos s on s.leitura_id=r.id left join public.tentativas t on t.id=r.tentativa_id where r.participante_id=pid and coalesce(t.status,'started')<>'completed' order by r.ordem limit 1;
   if l.level is not null and not clube_private.evento_nivel_liberado(pid,l.level) then raise exception 'Conclua o nivel anterior.' using errcode='42501';end if;
  end if;
  return clube_private.eventos_antes_automatico(op,args);
 end if;
 if not clube_private.administrador() then raise exception 'Administrador obrigatorio' using errcode='42501';end if;
 if op='save' and coalesce((args->>'automatic')::boolean,false) then
  if args?'id' then select versao_configuracao,configuracoes into old_version,old_configs from public.eventos_leitura where id=(args->>'id')::uuid for update;
  elsif args?'requestId' then
   perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended(args->>'requestId',0));
   select * into e from public.eventos_leitura where id=(args->>'requestId')::uuid;
   if e.id is not null then return clube_private.evento_json(e);end if;
  end if;
  perform 1 from public.textos where ativo and excluido_em is null order by id for share;
  configs:=clube_private.evento_config_automatica(args->'ageConfigs');
  result:=clube_private.eventos_antes_automatico(op,args||jsonb_build_object('ageConfigs',configs));
  update public.eventos_leitura set distribuicao_automatica=true,versao_configuracao=coalesce(old_version,1)+case when old_configs is not null and old_configs is distinct from configs then 1 else 0 end where id=(result->>'id')::uuid;
  return result;
 end if;
 if op='send' then
  select * into e from public.eventos_leitura where id=(args->>'id')::uuid for update;
  if e.distribuicao_automatica then
   if jsonb_typeof(args->'studentIds') is distinct from 'array' or jsonb_array_length(args->'studentIds')=0 then raise exception 'Selecione os alunos.' using errcode='22023';end if;
   for student in select distinct x::uuid from jsonb_array_elements_text(args->'studentIds') x order by 1 loop
    if exists(select 1 from public.evento_alunos where evento_id=e.id and aluno_id=student) then kept:=kept+1;end if;
    pid:=clube_private.evento_auto_atribuir(e.id,student);created:=created+1;
   end loop;return jsonb_build_object('created',created-kept,'existing',kept);
  end if;
 end if;
 return clube_private.eventos_antes_automatico(op,args);
end $$;
revoke all on function public.clube_eventos(text,jsonb) from public,anon;
grant execute on function public.clube_eventos(text,jsonb) to authenticated;
revoke all on function clube_private.eventos_antes_automatico(text,jsonb),clube_private.evento_pool(integer,text),clube_private.evento_config_automatica(jsonb),clube_private.evento_auto_elegivel(public.eventos_leitura,uuid),clube_private.evento_auto_atribuir(uuid,uuid) from public,anon,authenticated;
-- Bloqueia acesso direto a um nivel futuro mesmo com IDs de tentativa conhecidos.
alter function public.clube_leitura(text,jsonb) rename to leitura_antes_automatico;
alter function public.leitura_antes_automatico(text,jsonb) set schema clube_private;
create function public.clube_leitura(op text,args jsonb default '{}') returns jsonb language plpgsql security definer set search_path='' as $$
declare a public.tentativas;
begin
 if op in('get','page','stage','answer','finish') then
 select t.* into a from public.tentativas t join public.evento_alunos p on p.id=t.evento_participante_id join public.eventos_leitura e on e.id=p.evento_id where t.id=(args->>'id')::uuid and t.aluno_id=clube_private.aluno_atual() and e.distribuicao_automatica;
 if a.id is not null and not clube_private.evento_nivel_liberado(a.evento_participante_id,a.nivel) then raise exception 'Conclua o nivel anterior.' using errcode='42501';end if;
 end if;return clube_private.leitura_antes_automatico(op,args);
end $$;
revoke all on function public.clube_leitura(text,jsonb) from public,anon;
grant execute on function public.clube_leitura(text,jsonb) to authenticated;
-- Mantem o OID usado pelas policies de textos e questoes.
do $policy$ declare definition text;updated text;begin
 definition:=pg_get_functiondef('public.clube_texto_permitido(text)'::regprocedure);
 updated:=replace(definition,'and clube_private.evento_disponivel(p.evento_id,i.student)',
 'and clube_private.evento_disponivel(p.evento_id,i.student) and (not exists(select 1 from public.eventos_leitura e where e.id=p.evento_id and e.distribuicao_automatica) or clube_private.evento_nivel_liberado(p.id,(select s.atividade->>''level'' from clube_private.evento_conteudos s where s.leitura_id=l.id)))');
 if updated=definition then raise exception 'Politica de textos incompativel. Aplique eventos_escolas primeiro.';end if;execute updated;
end $policy$;
revoke all on function clube_private.evento_nivel_liberado(uuid,text),clube_private.proximo_antes_automatico(uuid,uuid,boolean,text),clube_private.conquista_proximo(uuid,uuid,boolean,text),clube_private.leitura_antes_automatico(text,jsonb) from public,anon,authenticated;
notify pgrst,'reload schema';
commit;
