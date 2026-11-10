begin;
-- Regra oficial: 10 por leitura concluida + 5 por acerto. Historicos permanecem imutaveis.
alter table public.jornadas drop constraint jornadas_regra_pontos_check, add constraint jornadas_regra_pontos_check check(regra_pontos in(2,3,4));
alter table public.evento_alunos drop constraint evento_alunos_regra_pontos_check, add constraint evento_alunos_regra_pontos_check check(regra_pontos in(2,3,4));
alter table clube_private.avaliacoes_niveis drop constraint avaliacoes_niveis_regra_pontos_check, add constraint avaliacoes_niveis_regra_pontos_check check(regra_pontos in(2,3,4));
alter table public.jornadas alter column regra_pontos set default 4;
alter table public.evento_alunos alter column regra_pontos set default 4;
update public.jornadas j set regra_pontos=4 where not exists(select 1 from public.tentativas t where t.jornada_id=j.id) and not exists(select 1 from clube_private.conquistas_niveis c where c.contexto_id=j.id and not c.evento) and not exists(select 1 from clube_private.conclusoes_jornadas c where c.contexto_id=j.id and not c.evento);
update public.evento_alunos p set regra_pontos=4 where not exists(select 1 from public.tentativas t where t.evento_participante_id=p.id) and not exists(select 1 from clube_private.conquistas_niveis c where c.contexto_id=p.id and c.evento) and not exists(select 1 from clube_private.conclusoes_jornadas c where c.contexto_id=p.id and c.evento);
alter table public.tentativas drop constraint avaliacao_historia_consistente;
alter table public.tentativas add constraint avaliacao_historia_consistente check(avaliacao_historia is null or coalesce(
 jsonb_typeof(avaliacao_historia)='object' and avaliacao_historia->>'version' in('3','4') and
 (avaliacao_historia->>'maxPoints')::numeric=case when avaliacao_historia->>'version'='4' then 10+5*(avaliacao_historia->>'questions')::integer else 20 end and
 (avaliacao_historia->>'points')::numeric between 0 and (avaliacao_historia->>'maxPoints')::numeric and
 (avaliacao_historia->>'points')::numeric=(avaliacao_historia->>'readingPoints')::numeric+(avaliacao_historia->>'questionPoints')::numeric,false));
alter table clube_private.avaliacoes_niveis drop constraint avaliacao_regra_valores;
alter table clube_private.avaliacoes_niveis add constraint avaliacao_regra_valores check(
 (regra_pontos=2 and unidades_leitura=20 and unidades_questoes between 0 and 20 and unidades between 0 and 40) or
 (regra_pontos=3 and unidades_leitura=10*historias and unidades_questoes between 0 and 10*historias and unidades between 0 and 20*historias) or
 (regra_pontos=4 and unidades_leitura=10*historias and unidades_questoes=5*acertos and unidades=10*historias+5*acertos));

-- Reutiliza as mesmas funcoes de autorizacao, atribuicao e persistencia nas regras por historia.
do $routing$
declare target regprocedure;definition text;
begin
 foreach target in array array[
 'clube_private.gabarito_historia_v3()'::regprocedure,'clube_private.atribuir_jornada(uuid,uuid)'::regprocedure,
 'clube_private.sincronizar_catalogo(uuid)'::regprocedure,'clube_private.progresso_niveis(uuid)'::regprocedure,
 'clube_private.texto_autorizado(uuid,text)'::regprocedure,'clube_private.conquista_registrar(public.tentativas)'::regprocedure,
 'clube_private.attempt_json(public.tentativas)'::regprocedure,'clube_private.leitura_antes_catalogo(text,jsonb)'::regprocedure,
 'public.clube_api(text,jsonb)'::regprocedure,'clube_private.saldo_moedas(uuid)'::regprocedure,
 'clube_private.ranking_conquista(uuid)'::regprocedure,'clube_private.total_academico(uuid)'::regprocedure,
 'clube_private.pontuacao_contexto(uuid,uuid,boolean)'::regprocedure,'clube_private.pontos_validos_tentativa(uuid)'::regprocedure,
 'clube_private.jornada_registrar(uuid,uuid,boolean)'::regprocedure,'clube_private.conquista_json(clube_private.conquistas_niveis)'::regprocedure,
 'public.clube_escolas(text,jsonb)'::regprocedure] loop
  definition:=pg_get_functiondef(target);
  definition:=replace(replace(replace(definition,'<>3','<3'),')=3',')>=3'),'regra_pontos=3','regra_pontos>=3');
  definition:=replace(definition,'v.regra_pontos is distinct from 3','(v.regra_pontos is null or v.regra_pontos < 3)');
  execute definition;
 end loop;
end $routing$;

create or replace function clube_private.historia_avaliar(attempt_id uuid) returns jsonb language sql stable security definer set search_path='' as $$
 with a as(select t.*,s.atividade,clube_private.regra_contexto(t.aluno_id,coalesce(t.evento_participante_id,t.jornada_id),t.evento_participante_id is not null) rule
 from public.tentativas t join clube_private.conteudos_tentativas s on s.tentativa_id=t.id where t.id=attempt_id),
 counts as(select a.id,a.status,a.leitura_concluida_em,a.rule,count(q)::integer total,
 count(r.questao_id)::integer answered,count(r.questao_id) filter(where r.correta is not null and r.pontos is not null)::integer corrected,
 count(r.questao_id) filter(where r.correta)::integer hits
 from a cross join lateral jsonb_array_elements(a.atividade->'questions') q
 left join public.respostas r on r.tentativa_id=a.id and r.questao_id=(q->>'id')::integer group by a.id,a.status,a.leitura_concluida_em,a.rule),
 calculated as(select *,case when leitura_concluida_em is not null then 10 else 0 end reading,
 case when rule=4 then 5::numeric when total>0 then 10::numeric/total else 0 end unit from counts)
 select jsonb_build_object('version',rule,'scoreVersion',rule,'maxPoints',case when rule=4 then 10+5*total else 20 end,
 'readingComplete',leitura_concluida_em is not null,'stories',1,'completedStories',case when status='completed' and leitura_concluida_em is not null then 1 else 0 end,
 'questions',total,'answered',answered,'corrected',corrected,'hits',hits,'wrong',corrected-hits,'readingPoints',reading,'questionPoints',case when rule=4 then 5*hits else 10::numeric*hits/nullif(total,0) end,
 'points',reading+case when rule=4 then 5*hits else 10::numeric*hits/nullif(total,0) end,'questionPointValue',unit,
 'questionUnit',jsonb_build_object('numerator',case when rule=4 then 5 else 10 end,'denominator',case when rule=4 then 1 else total end),
 'lostPoints',case when rule=4 then 5*(corrected-hits) else 10::numeric*(corrected-hits)/nullif(total,0) end,
 'complete',status='completed' and leitura_concluida_em is not null and total>0 and answered=total and corrected=total and clube_private.resultado_completo(id)) from calculated
$$;

-- Maximo variavel: 10 por historia atribuida + 5 por pergunta atribuida.
do $calculations$ declare definition text;begin
 definition:=pg_get_functiondef('clube_private.gabarito_historia_v3()'::regprocedure);
 definition:=replace(definition,'''points'',1','''points'',case when clube_private.regra_contexto(a.aluno_id,coalesce(a.evento_participante_id,a.jornada_id),a.evento_participante_id is not null)=4 then 5 else 1 end');execute definition;
 definition:=pg_get_functiondef('clube_private.avaliacao_calcular(uuid,uuid,boolean,text)'::regprocedure);
 definition:=replace(definition,'<>3','<3');
 definition:=replace(definition,'''version'',3,''scoreVersion'',3,''maxPoints'',20*stories', '''version'',clube_private.regra_contexto(student,context_id,is_event),''scoreVersion'',clube_private.regra_contexto(student,context_id,is_event),''maxPoints'',case when clube_private.regra_contexto(student,context_id,is_event)=4 then 10*stories+5*questions else 20*stories end');execute definition;
 definition:=pg_get_functiondef('clube_private.conquista_registrar(public.tentativas)'::regprocedure);
 definition:=replace(definition,'group_value,3)','group_value,clube_private.regra_contexto(a.aluno_id,context_id,is_event))');execute definition;
 definition:=pg_get_functiondef('clube_private.conquista_json(clube_private.conquistas_niveis)'::regprocedure);
 definition:=replace(definition,'''scoreVersion'',3', '''scoreVersion'',v.regra_pontos');
 definition:=replace(definition,'20*v.historias','(case when v.regra_pontos=4 then 10*v.historias+5*v.questoes else 20*v.historias end)');
 definition:=replace(definition,'10*v.historias-v.unidades_questoes','case when v.regra_pontos=4 then 5*v.questoes-v.unidades_questoes else 10*v.historias-v.unidades_questoes end');execute definition;
 definition:=pg_get_functiondef('clube_private.attempt_json(public.tentativas)'::regprocedure);
 definition:=replace(definition,'10::numeric/nullif(total,0)','(grade->>''questionPointValue'')::numeric');execute definition;
 definition:=pg_get_functiondef('clube_private.jornada_registrar(uuid,uuid,boolean)'::regprocedure);
 definition:=replace(definition,'then 20*v.historias else','then case when v.regra_pontos=4 then 10*v.historias+5*v.questoes else 20*v.historias end else');
 definition:=replace(definition,'''wrong'',v.questoes-v.acertos)', '''wrong'',v.questoes-v.acertos,''readingPoints'',v.unidades_leitura/case when v.regra_pontos>=3 then 1 else 3 end,''questionPoints'',v.unidades_questoes/case when v.regra_pontos>=3 then 1 else 3 end)');
 definition:=replace(definition,'when x->>''scoreVersion''=''3''','when x->>''scoreVersion'' in(''3'',''4'')');execute definition;
 definition:=pg_get_functiondef('public.clube_escolas(text,jsonb)'::regprocedure);
 definition:=replace(definition,'then 10::numeric/nullif(jsonb_array_length(s.atividade->''questions''),0)','then case when clube_private.regra_contexto(t.aluno_id,coalesce(t.evento_participante_id,t.jornada_id),t.evento_participante_id is not null)=4 then 5::numeric else 10::numeric/nullif(jsonb_array_length(s.atividade->''questions''),0) end');execute definition;
 -- A nota academica nova inclui leituras efetivamente concluidas antes da recompensa de nivel.
 definition:=pg_get_functiondef('clube_private.total_academico(uuid)'::regprocedure);
 definition:=replace(definition,'then coalesce(v.unidades,0)','then coalesce(v.unidades,case when clube_private.regra_contexto(student,c.context_id,c.is_event)=4 then (clube_private.avaliacao_calcular(student,c.context_id,c.is_event,c.nivel)->>''points'')::numeric else 0 end)');execute definition;
 definition:=pg_get_functiondef('clube_private.pontuacao_contexto(uuid,uuid,boolean)'::regprocedure);
 definition:=replace(definition,'then coalesce(v.unidades,0)','then coalesce(v.unidades,case when clube_private.regra_contexto(student,context_id,is_event)=4 then (clube_private.avaliacao_calcular(student,context_id,is_event,l.nivel)->>''points'')::numeric else 0 end)');execute definition;
end $calculations$;

-- Resumo por nivel usa os mesmos resultados oficiais; nunca recebe pontos do navegador.
create function clube_private.pontuacao_resumo(student uuid) returns jsonb language sql stable security definer set search_path='' as $$
 with scores as(
 select t.nivel,clube_private.pontos_validos_tentativa(t.id) points,t.avaliacao_historia grade from clube_private.admin_resultados_validos v join public.tentativas t on t.id=v.id where t.aluno_id=student
 union all
 select t.nivel,(clube_private.historia_avaliar(t.id)->>'points')::numeric,clube_private.historia_avaliar(t.id) from public.tentativas t
 where t.aluno_id=student and t.status='started' and clube_private.regra_contexto(student,coalesce(t.evento_participante_id,t.jornada_id),t.evento_participante_id is not null)=4)
 select jsonb_agg(jsonb_build_object('level',n.id,'points',coalesce(s.points,0),'readingPoints',s.reading,'questionPoints',s.questions) order by array_position(array['facil','medio','dificil'],n.id))
 from public.niveis n left join(select nivel,sum(points) points,case when bool_and(grade is not null) then sum((grade->>'readingPoints')::numeric) end reading,case when bool_and(grade is not null) then sum((grade->>'questionPoints')::numeric) end questions from scores group by nivel) s on s.nivel=n.id
$$;
revoke all on function clube_private.pontuacao_resumo(uuid) from public,anon,authenticated;
do $state$ declare definition text;begin
 definition:=pg_get_functiondef('public.clube_leitura(text,jsonb)'::regprocedure);
 definition:=replace(definition,'declare student uuid;','declare student uuid;result jsonb;');
 definition:=replace(definition,'return clube_private.leitura_antes_catalogo(op,args);', 'result:=clube_private.leitura_antes_catalogo(op,args); if op=''state'' then result:=result||jsonb_build_object(''scoresByLevel'',clube_private.pontuacao_resumo(student));end if;return result;');execute definition;
end $state$;
notify pgrst,'reload schema';
commit;
