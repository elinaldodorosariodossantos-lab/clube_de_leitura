begin;
-- Unidades racionais: cada nível vale 40/3; somar unidades antes de dividir evita 39,99 na jornada.
-- A nova avaliação complementa os snapshots e a correção existentes; não reescreve respostas.
create table clube_private.pontuacao_legada(
 aluno_id uuid not null,contexto_id uuid not null,evento boolean not null,nivel text not null,
 primary key(aluno_id,contexto_id,evento,nivel));
insert into clube_private.pontuacao_legada
 select distinct aluno_id,coalesce(evento_participante_id,jornada_id),evento_participante_id is not null,nivel
 from public.tentativas where status='completed' and coalesce(evento_participante_id,jornada_id) is not null
 union select aluno_id,contexto_id,evento,nivel from clube_private.conquistas_niveis;
alter table clube_private.conquistas_niveis alter column pontos type numeric;
create table clube_private.avaliacoes_niveis(
 conquista_id uuid primary key references clube_private.conquistas_niveis(id),
 aluno_id uuid not null references public.alunos(id),contexto_id uuid not null,evento boolean not null,
 nivel text not null references public.niveis(id),historias integer not null check(historias>0),
 questoes integer not null check(questoes>0),acertos integer not null check(acertos between 0 and questoes),
 unidades_leitura numeric not null check(unidades_leitura=20),unidades_questoes numeric not null check(unidades_questoes between 0 and 20),
 unidades numeric not null check(unidades between 0 and 40),faixa_grupo text,concluida_em timestamptz not null default now(),
 unique(aluno_id,contexto_id,evento,nivel),check(unidades=unidades_leitura+unidades_questoes));
create table clube_private.recompensas_moedas(
 conquista_id uuid primary key references clube_private.avaliacoes_niveis(conquista_id),
 aluno_id uuid not null references public.alunos(id),valor_unidades numeric not null check(valor_unidades between 0 and 40),
 criada_em timestamptz not null default now());
alter table clube_private.pontuacao_legada enable row level security;
alter table clube_private.avaliacoes_niveis enable row level security;
alter table clube_private.recompensas_moedas enable row level security;
revoke all on clube_private.pontuacao_legada,clube_private.avaliacoes_niveis,clube_private.recompensas_moedas from public,anon,authenticated;
create index avaliacoes_ranking_idx on clube_private.avaliacoes_niveis(contexto_id,faixa_grupo,nivel,unidades desc) where evento;
create index recompensas_aluno_idx on clube_private.recompensas_moedas(aluno_id);

create function clube_private.avaliacao_calcular(student uuid,context_id uuid,is_event boolean,level_id text) returns jsonb
language sql stable security definer set search_path='' as $$
 with assigned as(
  select l.texto_id,l.tentativa_id,s.atividade from public.evento_alunos p
  join public.evento_leituras l on l.participante_id=p.id join clube_private.evento_conteudos s on s.leitura_id=l.id
  where is_event and p.id=context_id and p.aluno_id=student and s.atividade->>'level'=level_id
  union all
  select t.id,saved.id,coalesce(snap.atividade,jsonb_build_object('questions',coalesce((select jsonb_agg(jsonb_build_object('id',q.id)) from public.questoes q where q.texto_id=t.id and q.ativo),'[]'::jsonb)))
  from public.textos t
  left join lateral(select a.id from public.tentativas a where a.aluno_id=student and a.jornada_id=context_id and a.texto_id=t.id order by clube_private.resultado_completo(a.id) desc,a.id limit 1) saved on true
  left join clube_private.conteudos_tentativas snap on snap.tentativa_id=saved.id
  where not is_event and exists(select 1 from public.jornadas j where j.id=context_id and j.aluno_id=student)
  and t.nivel=level_id and ((t.ativo and t.excluido_em is null and t.obrigatorio and clube_private.historia_idade(student,t.faixa_etaria))
  or (saved.id is not null and clube_private.historia_idade(student,snap.atividade->>'age')))
 ), books as(select *,clube_private.resultado_completo(tentativa_id) as done from assigned),
 questions as(select b.tentativa_id,q->>'id' as qid,b.done from books b cross join lateral jsonb_array_elements(b.atividade->'questions') q),
 totals as(select (select count(*) from books)::integer as stories,(select count(*) from books where done)::integer as completed,
 count(*)::integer as total,count(*) filter(where exists(select 1 from public.respostas r where r.tentativa_id=q.tentativa_id and r.questao_id=q.qid::integer))::integer as answered,
 count(*) filter(where q.done and exists(select 1 from public.respostas r where r.tentativa_id=q.tentativa_id and r.questao_id=q.qid::integer and r.correta))::integer as hits,
 count(*) filter(where q.done)::integer as corrected from questions q),
 score as(select *,case when stories>0 then 20::numeric*completed/stories else 0 end as reading_points,
 case when total>0 then 20::numeric*hits/total else 0 end as question_points from totals)
 select jsonb_build_object('version',2,'maxPoints',40::numeric/3,'stories',stories,'completedStories',completed,'questions',total,'answered',answered,'corrected',corrected,
 'hits',hits,'wrong',corrected-hits,'readingPoints',reading_points/3,'questionPoints',question_points/3,'points',(reading_points+question_points)/3,'pointUnits',reading_points+question_points,'pointDivisor',3,
 'lostPoints',case when total>0 then 20::numeric*(corrected-hits)/(total*3) else 0 end,
 'readingUnit',jsonb_build_object('numerator',20,'denominator',stories*3),'questionUnit',jsonb_build_object('numerator',20,'denominator',total*3),
 'questionPointValue',case when total>0 then 20::numeric/(total*3) else 0 end,
 'complete',stories>0 and completed=stories and total>0 and answered=total and corrected=total) from score
$$;

alter function clube_private.conquista_registrar(public.tentativas) rename to conquista_antes_moedas;
create function clube_private.conquista_registrar(a public.tentativas) returns uuid language plpgsql security definer set search_path='' as $$
declare achievement_id uuid;c clube_private.conquistas_niveis;stats jsonb;group_value text;
begin
 achievement_id:=clube_private.conquista_antes_moedas(a);
 select * into c from clube_private.conquistas_niveis where aluno_id=a.aluno_id and contexto_id=coalesce(a.evento_participante_id,a.jornada_id) and evento=(a.evento_participante_id is not null) and nivel=a.nivel;
 if c.id is null or exists(select 1 from clube_private.pontuacao_legada l where l.aluno_id=c.aluno_id and l.contexto_id=c.contexto_id and l.evento=c.evento and l.nivel=c.nivel) then return achievement_id;end if;
 if not exists(select 1 from clube_private.avaliacoes_niveis where conquista_id=c.id) then
  stats:=clube_private.avaliacao_calcular(c.aluno_id,c.contexto_id,c.evento,c.nivel);
  if not coalesce((stats->>'complete')::boolean,false) then raise exception 'Há leituras ou questões pendentes neste nível.' using errcode='22023';end if;
  if c.evento then select case when jsonb_array_length(configuracao)>0 then 'idade:'||idade_referencia else 'faixa:'||idade_min||':'||idade_max end into group_value from public.evento_alunos where id=c.contexto_id;end if;
  insert into clube_private.avaliacoes_niveis(conquista_id,aluno_id,contexto_id,evento,nivel,historias,questoes,acertos,unidades_leitura,unidades_questoes,unidades,faixa_grupo)
  values(c.id,c.aluno_id,c.contexto_id,c.evento,c.nivel,(stats->>'stories')::integer,(stats->>'questions')::integer,(stats->>'hits')::integer,20,(stats->>'pointUnits')::numeric-20,(stats->>'pointUnits')::numeric,group_value)
  on conflict(conquista_id) do nothing;
  update clube_private.conquistas_niveis set pontos=(select unidades/3 from clube_private.avaliacoes_niveis where conquista_id=c.id) where id=c.id;
 end if;
 insert into clube_private.recompensas_moedas(conquista_id,aluno_id,valor_unidades) select conquista_id,aluno_id,unidades from clube_private.avaliacoes_niveis where conquista_id=c.id on conflict(conquista_id) do nothing;
 return achievement_id;
end $$;

create function clube_private.saldo_moedas(student uuid) returns numeric language sql stable security definer set search_path='' as $$
 select coalesce(sum(valor_unidades),0)/3 from clube_private.recompensas_moedas where aluno_id=student
$$;
create function clube_private.ranking_conquista(achievement uuid) returns jsonb language sql stable security definer set search_path='' as $$
 with current_score as(select * from clube_private.avaliacoes_niveis where conquista_id=achievement and evento),
 ranked as(select v.unidades,v.aluno_id,v.concluida_em,
 row_number() over(order by v.unidades desc,v.concluida_em,v.aluno_id) as position
 from clube_private.avaliacoes_niveis v join public.evento_alunos p on p.id=v.contexto_id
 join current_score c on c.nivel=v.nivel and c.faixa_grupo=v.faixa_grupo
 join public.evento_alunos current_participant on current_participant.id=c.contexto_id and current_participant.evento_id=p.evento_id
 where v.evento)
 select coalesce(jsonb_agg(jsonb_build_object('position',r.position,'name',coalesce(a.nome_completo,p.nome),'school',e.nome,'points',r.unidades/3,'self',r.aluno_id=(select aluno_id from current_score)) order by r.position),'[]')
 from ranked r join public.alunos a on a.id=r.aluno_id left join public.perfis p on p.id=a.perfil_id left join public.escolas e on e.id=a.escola_id where r.position<=3
$$;

alter function clube_private.conquista_json(clube_private.conquistas_niveis) rename to conquista_json_antes_moedas;
create function clube_private.conquista_json(c clube_private.conquistas_niveis) returns jsonb language sql stable security definer set search_path='' as $$
 select clube_private.conquista_json_antes_moedas(c)||coalesce((select jsonb_build_object('scoreVersion',2,'points',v.unidades/3,'maxPoints',40::numeric/3,
 'percentage',100,'performance',v.unidades*100/40,'stories',v.historias,'completedStories',v.historias,'questions',v.questoes,'hits',v.acertos,'wrong',v.questoes-v.acertos,
 'readingPoints',v.unidades_leitura/3,'questionPoints',v.unidades_questoes/3,'lostPoints',(20-v.unidades_questoes)/3,'pointUnits',v.unidades,'pointDivisor',3,
 'questionPointValue',20::numeric/(v.questoes*3),'coins',r.valor_unidades/3,'coinBalance',clube_private.saldo_moedas(c.aluno_id),'ranking',clube_private.ranking_conquista(c.id))
 from clube_private.avaliacoes_niveis v join clube_private.recompensas_moedas r on r.conquista_id=v.conquista_id where v.conquista_id=c.id),jsonb_build_object('scoreVersion',1,'coinBalance',clube_private.saldo_moedas(c.aluno_id),'ranking','[]'::jsonb))
$$;

-- Total acadêmico: usa os novos critérios nos contextos novos e os valores antigos nos legados.
create function clube_private.total_academico(student uuid) returns numeric language sql stable security definer set search_path='' as $$
 with contexts as(select distinct coalesce(evento_participante_id,jornada_id) as context_id,evento_participante_id is not null as is_event,nivel
 from public.tentativas where aluno_id=student and coalesce(evento_participante_id,jornada_id) is not null),
 new_contexts as(select c.* from contexts c where not exists(select 1 from clube_private.pontuacao_legada l where l.aluno_id=student and l.contexto_id=c.context_id and l.evento=c.is_event and l.nivel=c.nivel)),
 units as(select coalesce(v.unidades,(clube_private.avaliacao_calcular(student,c.context_id,c.is_event,c.nivel)->>'pointUnits')::numeric) as value
 from new_contexts c left join clube_private.avaliacoes_niveis v on v.aluno_id=student and v.contexto_id=c.context_id and v.evento=c.is_event and v.nivel=c.nivel)
 select coalesce((select sum(value)/3 from units),0)+coalesce((select sum(a.pontuacao) from clube_private.admin_resultados_validos a where a.aluno_id=student and
 not exists(select 1 from new_contexts c where c.context_id=coalesce(a.evento_participante_id,a.jornada_id) and c.nivel=a.nivel and c.is_event=(a.evento_participante_id is not null))),0)
$$;

-- Consulta autenticada para retomar resultados sem repetir a animação nem o crédito.
alter function public.clube_leitura(text,jsonb) rename to leitura_antes_recompensas;
alter function public.leitura_antes_recompensas(text,jsonb) set schema clube_private;
create function public.clube_leitura(op text,args jsonb default '{}') returns jsonb language plpgsql security definer set search_path='' as $$
declare student uuid;result jsonb;a public.tentativas;c clube_private.conquistas_niveis;context_id uuid;is_event boolean;level_id text;summary jsonb;
begin
 student:=clube_private.aluno_atual();if student is null then raise exception 'Aluno não identificado' using errcode='42501';end if;
 if op='achievement_get' then
  select * into c from clube_private.conquistas_niveis where id=(args->>'id')::uuid and aluno_id=student;
  if c.id is null then raise exception 'Conquista não encontrada' using errcode='42501';end if;
  return jsonb_build_object('achievement',clube_private.conquista_json(c));
 end if;
 result:=clube_private.leitura_antes_recompensas(op,args);
 if op='state' then
  select coalesce(jsonb_agg(clube_private.conquista_json(x) order by x.concluida_em desc,x.id),'[]') into summary from clube_private.conquistas_niveis x where aluno_id=student;
  return jsonb_set(result,'{student,points}',to_jsonb(clube_private.total_academico(student)))||jsonb_build_object('coinBalance',clube_private.saldo_moedas(student),'achievements',summary);
 elsif op in ('get','finish') then
  select * into a from public.tentativas where id=(args->>'id')::uuid and aluno_id=student;
  context_id:=coalesce(a.evento_participante_id,a.jornada_id);is_event:=a.evento_participante_id is not null;level_id:=a.nivel;
  select * into c from clube_private.conquistas_niveis where aluno_id=student and contexto_id=context_id and evento=is_event and nivel=level_id;
  if c.id is not null then return result||jsonb_build_object('levelScore',clube_private.conquista_json(c));end if;
  if context_id is not null and not exists(select 1 from clube_private.pontuacao_legada l where l.aluno_id=student and l.contexto_id=context_id and l.evento=is_event and l.nivel=level_id) then
   return result||jsonb_build_object('levelScore',clube_private.avaliacao_calcular(student,context_id,is_event,level_id));
  end if;
 end if;
 return result;
end $$;
revoke all on function public.clube_leitura(text,jsonb) from public,anon;
grant execute on function public.clube_leitura(text,jsonb) to authenticated;
revoke all on function clube_private.total_academico(uuid),clube_private.avaliacao_calcular(uuid,uuid,boolean,text),clube_private.conquista_antes_moedas(public.tentativas),clube_private.conquista_registrar(public.tentativas),clube_private.saldo_moedas(uuid),clube_private.ranking_conquista(uuid),clube_private.conquista_json_antes_moedas(clube_private.conquistas_niveis),clube_private.conquista_json(clube_private.conquistas_niveis),clube_private.leitura_antes_recompensas(text,jsonb) from public,anon,authenticated;
notify pgrst,'reload schema';
commit;
