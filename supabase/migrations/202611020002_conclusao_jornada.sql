begin;
-- Resumo final imutável. Não altera respostas, avaliações, pontos ou moedas.
alter table clube_private.configuracao add column certificado_instituicao text not null default '' check(length(certificado_instituicao)<=160),
 add column certificado_identificacao text not null default '' check(length(certificado_identificacao)<=160);
create table clube_private.conclusoes_jornadas(
 id uuid primary key default gen_random_uuid(),aluno_id uuid not null references public.alunos(id),
 contexto_id uuid not null,evento_id uuid references public.eventos_leitura(id),evento boolean not null,
 faixa_grupo text,niveis text[] not null,resumo jsonb not null,
 concluida_em timestamptz not null,apresentada_em timestamptz,
 unique(aluno_id,contexto_id,evento));
create index conclusoes_ranking_idx on clube_private.conclusoes_jornadas(evento_id,faixa_grupo) where evento;
alter table clube_private.conclusoes_jornadas enable row level security;
revoke all on clube_private.conclusoes_jornadas from public,anon,authenticated;

create function clube_private.jornada_registrar(student uuid,context_id uuid,is_event boolean) returns uuid
language plpgsql security definer set search_path='' as $$
declare final_id uuid;level_id text;levels text[];stats jsonb;items jsonb:='[]';c clube_private.conquistas_niveis;
 v clube_private.avaliacoes_niveis;points numeric;maximum numeric;coins numeric;coin_units numeric;finished timestamptz;
 event_id uuid;group_value text;event_name text;person jsonb;issuer jsonb;legacy boolean:=false;
begin
 if context_id is null then return null;end if;
 if is_event then
  select p.evento_id,e.nome,case when jsonb_array_length(p.configuracao)>0 then 'idade:'||p.idade_referencia else 'faixa:'||p.idade_min||':'||p.idade_max end
  into event_id,event_name,group_value from public.evento_alunos p join public.eventos_leitura e on e.id=p.evento_id where p.id=context_id and p.aluno_id=student;
  if event_id is null then return null;end if;
 else
  if not exists(select 1 from public.jornadas where id=context_id and aluno_id=student) then return null;end if;
 end if;
 select id into final_id from clube_private.conclusoes_jornadas where aluno_id=student and contexto_id=context_id and evento=is_event;
 if final_id is not null then return final_id;end if;
 -- A mesma ordem de locks das operações de leitura serializa a conclusão.
 perform 1 from public.alunos where id=student for update;
 if is_event then
  if not exists(select 1 from public.evento_leituras where participante_id=context_id) or exists(
   select 1 from public.evento_leituras where participante_id=context_id and not clube_private.resultado_completo(tentativa_id)) then return null;end if;
  select array_agg(level order by array_position(array['facil','medio','dificil'],level)) into levels
  from(select distinct s.atividade->>'level' as level from public.evento_leituras l join clube_private.evento_conteudos s on s.leitura_id=l.id where l.participante_id=context_id) x;
 else
  if context_id is distinct from(select id from public.jornadas where aluno_id=student order by ciclo desc limit 1) or not clube_private.jornada_completa(student) then return null;end if;
  select array_agg(id order by array_position(array['facil','medio','dificil'],id)) into levels from clube_private.progresso_niveis(student)
  where required>0 and clube_private.nivel_liberado(student,id);
 end if;
 if coalesce(cardinality(levels),0)=0 then return null;end if;
 foreach level_id in array levels loop
  -- Conta as atribuições e todas as perguntas corrigidas, nunca somente o status visual.
  stats:=clube_private.avaliacao_calcular(student,context_id,is_event,level_id);
  if not coalesce((stats->>'complete')::boolean,false) then return null;end if;
  select * into c from clube_private.conquistas_niveis where aluno_id=student and contexto_id=context_id and evento=is_event and nivel=level_id;
  if c.id is null then return null;end if;
  select * into v from clube_private.avaliacoes_niveis where conquista_id=c.id;
  if v.conquista_id is not null then
   points:=v.unidades/3;maximum:=40::numeric/3;
   select valor_unidades into coin_units from clube_private.recompensas_moedas where conquista_id=c.id;
   coins:=coalesce(coin_units,0)/3;
   stats:=jsonb_build_object('stories',v.historias,'questions',v.questoes,'hits',v.acertos,'wrong',v.questoes-v.acertos);
  else
   legacy:=true;points:=c.pontos;coins:=0;coin_units:=0;
   -- O máximo legado é derivado do gabarito capturado, sem reavaliar as respostas.
   select coalesce(sum((answer.value->>'points')::numeric),0) into maximum
   from public.tentativas a join clube_private.conteudos_tentativas s on s.tentativa_id=a.id
   cross join lateral jsonb_each(s.gabarito) answer
   where a.aluno_id=student and coalesce(a.evento_participante_id,a.jornada_id)=context_id and a.nivel=level_id and clube_private.resultado_completo(a.id);
  end if;
  items:=items||jsonb_build_array(stats||jsonb_build_object('level',level_id,'points',points,'maxPoints',maximum,'coins',coalesce(coins,0),'legacy',v.conquista_id is null,
   'pointUnits',v.unidades,'coinUnits',coalesce(coin_units,0),
   'performance',case when maximum>0 then points*100/maximum else 0 end));
  finished:=greatest(finished,c.concluida_em);
 end loop;
 select jsonb_build_object('name',coalesce(a.nome_completo,p.nome),'school',e.nome) into person
 from public.alunos a left join public.perfis p on p.id=a.perfil_id left join public.escolas e on e.id=a.escola_id where a.id=student;
 select jsonb_build_object('institution',certificado_instituicao,'identification',certificado_identificacao) into issuer from clube_private.configuracao where id;
 insert into clube_private.conclusoes_jornadas(aluno_id,contexto_id,evento_id,evento,faixa_grupo,niveis,concluida_em,resumo)
 values(student,context_id,event_id,is_event,group_value,levels,finished,
  person||jsonb_build_object('eventName',event_name,'issuer',issuer,'levels',items,'legacy',legacy,
  'stories',(select sum((x->>'stories')::integer) from jsonb_array_elements(items) x),
  'questions',(select sum((x->>'questions')::integer) from jsonb_array_elements(items) x),
  'hits',(select sum((x->>'hits')::integer) from jsonb_array_elements(items) x),
  'wrong',(select sum((x->>'wrong')::integer) from jsonb_array_elements(items) x),
  'points',case when legacy then (select sum((x->>'points')::numeric) from jsonb_array_elements(items) x) else (select sum((x->>'pointUnits')::numeric)/3 from jsonb_array_elements(items) x) end,
  'maxPoints',case when legacy then (select sum((x->>'maxPoints')::numeric) from jsonb_array_elements(items) x) else cardinality(levels)*40::numeric/3 end,
  'coins',(select sum((x->>'coinUnits')::numeric)/3 from jsonb_array_elements(items) x)))
 on conflict(aluno_id,contexto_id,evento) do nothing;
 select id into final_id from clube_private.conclusoes_jornadas where aluno_id=student and contexto_id=context_id and evento=is_event;
 return final_id;
end $$;

create function clube_private.jornada_final_json(c clube_private.conclusoes_jornadas) returns jsonb
language sql stable security definer set search_path='' as $$
 with ranked as(select f.id,f.aluno_id,f.resumo,row_number() over(order by (f.resumo->>'points')::numeric desc,f.concluida_em,f.aluno_id) as position
 from clube_private.conclusoes_jornadas f where c.evento and f.evento_id=c.evento_id and f.faixa_grupo=c.faixa_grupo and f.niveis=c.niveis and f.resumo->>'legacy'=c.resumo->>'legacy')
 select c.resumo||jsonb_build_object('id',c.id,'eventId',c.evento_id,'completedAt',c.concluida_em,'coinBalance',clube_private.saldo_moedas(c.aluno_id),
 'performance',case when (c.resumo->>'maxPoints')::numeric>0 then (c.resumo->>'points')::numeric*100/(c.resumo->>'maxPoints')::numeric else 0 end,
 'ranking',coalesce((select jsonb_agg(jsonb_build_object('position',r.position,'name',r.resumo->>'name','school',r.resumo->>'school','points',(r.resumo->>'points')::numeric,'self',r.aluno_id=c.aluno_id) order by r.position)
 from ranked r where r.position<=3 or r.aluno_id=c.aluno_id),'[]'))
$$;

alter function public.clube_leitura(text,jsonb) rename to leitura_antes_final_jornada;
alter function public.leitura_antes_final_jornada(text,jsonb) set schema clube_private;
create function public.clube_leitura(op text,args jsonb default '{}') returns jsonb language plpgsql security definer set search_path='' as $$
declare student uuid;result jsonb;a public.tentativas;c clube_private.conclusoes_jornadas;final_id uuid;pid uuid;celebrate boolean;
begin
 student:=clube_private.aluno_atual();if student is null then raise exception 'Aluno não identificado' using errcode='42501';end if;
 if op in ('journey_get','journey_claim') then
  select * into c from clube_private.conclusoes_jornadas where id=(args->>'id')::uuid and aluno_id=student for update;
  if c.id is null then raise exception 'Conclusão não encontrada' using errcode='42501';end if;
  celebrate:=op='journey_claim' and c.apresentada_em is null;
  if celebrate then
   update clube_private.conclusoes_jornadas set apresentada_em=now() where id=c.id;
   update clube_private.conquistas_niveis set apresentada_em=coalesce(apresentada_em,now()) where aluno_id=student and contexto_id=c.contexto_id and evento=c.evento;
  end if;
  return jsonb_build_object('completion',clube_private.jornada_final_json(c),'celebrate',celebrate);
 end if;
 result:=clube_private.leitura_antes_final_jornada(op,args);
 if op='finish' then
  select * into a from public.tentativas where id=(args->>'id')::uuid and aluno_id=student;
  final_id:=clube_private.jornada_registrar(student,coalesce(a.evento_participante_id,a.jornada_id),a.evento_participante_id is not null);
  return result||jsonb_build_object('journeyCompletionId',final_id);
 elsif op='state' then
  -- Retomada de conclusões anteriores: congela os valores já existentes, sem recalcular notas.
  perform clube_private.jornada_registrar(student,(result->'journey'->>'id')::uuid,false);
  for pid in select p.id from public.evento_alunos p where p.aluno_id=student and exists(select 1 from public.evento_leituras l where l.participante_id=p.id)
   and not exists(select 1 from public.evento_leituras l where l.participante_id=p.id and not clube_private.resultado_completo(l.tentativa_id)) loop
   perform clube_private.jornada_registrar(student,pid,true);
  end loop;
  select id into final_id from clube_private.conclusoes_jornadas where aluno_id=student and apresentada_em is null order by concluida_em,id limit 1;
  return result||jsonb_build_object('journeyCompletionId',final_id,'journeyCompletions',coalesce((select jsonb_agg(jsonb_build_object('id',x.id,'eventName',x.resumo->>'eventName','completedAt',x.concluida_em,'points',x.resumo->'points') order by x.concluida_em desc,x.id) from clube_private.conclusoes_jornadas x where aluno_id=student),'[]'));
 end if;
 return result;
end $$;
revoke all on function public.clube_leitura(text,jsonb) from public,anon;
grant execute on function public.clube_leitura(text,jsonb) to authenticated;

alter function public.clube_gestao(text,jsonb) rename to gestao_antes_certificado;
alter function public.gestao_antes_certificado(text,jsonb) set schema clube_private;
create function public.clube_gestao(op text,args jsonb default '{}') returns jsonb language plpgsql security definer set search_path='' as $$
begin
 if not clube_private.administrador() then raise exception 'Administrador obrigatório' using errcode='42501';end if;
 if op='certificate_settings_save' then
  if length(coalesce(args->>'institution',''))>160 or length(coalesce(args->>'identification',''))>160 then raise exception 'Identificação institucional inválida' using errcode='22023';end if;
  update clube_private.configuracao set certificado_instituicao=trim(coalesce(args->>'institution','')),certificado_identificacao=trim(coalesce(args->>'identification','')) where id;
 end if;
 if op in ('certificate_settings','certificate_settings_save') then return(select jsonb_build_object('institution',certificado_instituicao,'identification',certificado_identificacao) from clube_private.configuracao where id);end if;
 return clube_private.gestao_antes_certificado(op,args);
end $$;
revoke all on function public.clube_gestao(text,jsonb) from public,anon;
grant execute on function public.clube_gestao(text,jsonb) to authenticated;
revoke all on function clube_private.jornada_registrar(uuid,uuid,boolean),clube_private.jornada_final_json(clube_private.conclusoes_jornadas),clube_private.leitura_antes_final_jornada(text,jsonb),clube_private.gestao_antes_certificado(text,jsonb) from public,anon,authenticated;
notify pgrst,'reload schema';
commit;
