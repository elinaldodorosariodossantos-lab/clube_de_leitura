-- Execute uma vez no SQL Editor para iniciar a contagem de todos em zero.
-- Preserva atividades, respostas, progresso, certificados e valores historicos.
-- Reexecutar este mesmo arquivo nao reinicia a contagem novamente.
begin;
do $reinicio$
declare definition text;
begin
 perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended('clube_reinicio_contagem_unico',0));
 if to_regprocedure('clube_private.total_antes_reinicio(uuid)') is not null then return;end if;
 if to_regprocedure('clube_private.pontuacao_resumo(uuid)') is null then raise exception 'Execute instalar-eventos.sql completo antes deste reinicio.';end if;
 -- O lock dos alunos serializa as operacoes de leitura e fechamento de recompensas.
 lock table public.alunos in share row exclusive mode;
 lock table public.tentativas,public.respostas,clube_private.recompensas_moedas,clube_private.avaliacoes_niveis in share row exclusive mode;
 execute $instalar$
 create table clube_private.reinicio_contagem(id boolean primary key default true check(id),iniciado_em timestamptz not null);
 insert into clube_private.reinicio_contagem values(true,clock_timestamp());
 create table clube_private.reinicio_contagem_alunos(
 aluno_id uuid primary key references public.alunos(id),pontos numeric not null,moedas numeric not null,niveis jsonb not null);
 insert into clube_private.reinicio_contagem_alunos
 select id,clube_private.total_academico(id),clube_private.saldo_moedas(id),clube_private.pontuacao_resumo(id) from public.alunos;
 create table clube_private.reinicio_contagem_contextos(
 aluno_id uuid not null,contexto_id uuid not null,evento boolean not null,nivel text not null,pontos numeric not null,
 primary key(aluno_id,contexto_id,evento,nivel));
 insert into clube_private.reinicio_contagem_contextos
 with contexts as(select distinct aluno_id,coalesce(evento_participante_id,jornada_id) context_id,evento_participante_id is not null is_event,nivel
 from public.tentativas where coalesce(evento_participante_id,jornada_id) is not null)
 select c.aluno_id,c.context_id,c.is_event,c.nivel,coalesce(case
 when exists(select 1 from clube_private.pontuacao_legada p where p.aluno_id=c.aluno_id and p.contexto_id=c.context_id and p.evento=c.is_event and p.nivel=c.nivel)
 then(select sum(t.pontuacao) from clube_private.admin_resultados_validos t where t.aluno_id=c.aluno_id and coalesce(t.evento_participante_id,t.jornada_id)=c.context_id and (t.evento_participante_id is not null)=c.is_event and t.nivel=c.nivel)
 when clube_private.regra_contexto(c.aluno_id,c.context_id,c.is_event)>=3 then coalesce(v.unidades,case when clube_private.regra_contexto(c.aluno_id,c.context_id,c.is_event)=4 then (clube_private.avaliacao_calcular(c.aluno_id,c.context_id,c.is_event,c.nivel)->>'points')::numeric else 0 end)
 else coalesce(v.unidades,(clube_private.avaliacao_calcular(c.aluno_id,c.context_id,c.is_event,c.nivel)->>'pointUnits')::numeric)/3 end,0)
 from contexts c left join clube_private.avaliacoes_niveis v on v.aluno_id=c.aluno_id and v.contexto_id=c.context_id and v.evento=c.is_event and v.nivel=c.nivel;
 alter table clube_private.reinicio_contagem_contextos add column leitura numeric,add column questoes numeric;
 update clube_private.reinicio_contagem_contextos b set leitura=(clube_private.avaliacao_calcular(b.aluno_id,b.contexto_id,b.evento,b.nivel)->>'readingPoints')::numeric,questoes=(clube_private.avaliacao_calcular(b.aluno_id,b.contexto_id,b.evento,b.nivel)->>'questionPoints')::numeric
 where b.pontos>0 and clube_private.regra_contexto(b.aluno_id,b.contexto_id,b.evento)>=3;
 alter table clube_private.reinicio_contagem enable row level security;
 alter table clube_private.reinicio_contagem_alunos enable row level security;
 alter table clube_private.reinicio_contagem_contextos enable row level security;
 revoke all on clube_private.reinicio_contagem,clube_private.reinicio_contagem_alunos,clube_private.reinicio_contagem_contextos from public,anon,authenticated;

 create function clube_private.pontos_desde_reinicio(student uuid,context_id uuid,is_event boolean,level_id text,amount numeric) returns numeric
 language sql stable security definer set search_path='' as $$
 select greatest(0,amount-coalesce((select pontos from clube_private.reinicio_contagem_contextos where aluno_id=student and contexto_id=context_id and evento=is_event and nivel=level_id),0))
 $$;
 alter function clube_private.total_academico(uuid) rename to total_antes_reinicio;
 create function clube_private.total_academico(student uuid) returns numeric language sql stable security definer set search_path='' as $$
 select greatest(0,clube_private.total_antes_reinicio(student)-coalesce((select pontos from clube_private.reinicio_contagem_alunos where aluno_id=student),0))
 $$;
 alter function clube_private.saldo_moedas(uuid) rename to saldo_antes_reinicio;
 create function clube_private.saldo_moedas(student uuid) returns numeric language sql stable security definer set search_path='' as $$
 select coalesce(sum(clube_private.pontos_desde_reinicio(student,v.contexto_id,v.evento,v.nivel,r.valor_unidades/case when v.regra_pontos>=3 then 1 else 3 end)),0)
 from clube_private.recompensas_moedas r join clube_private.avaliacoes_niveis v on v.conquista_id=r.conquista_id
 where r.aluno_id=student and r.criada_em>=(select iniciado_em from clube_private.reinicio_contagem where id)
 $$;
 alter function clube_private.pontuacao_contexto(uuid,uuid,boolean) rename to contexto_antes_reinicio;
 create function clube_private.pontuacao_contexto(student uuid,context_id uuid,is_event boolean) returns numeric language sql stable security definer set search_path='' as $$
 select greatest(0,clube_private.contexto_antes_reinicio(student,context_id,is_event)-coalesce((select sum(pontos) from clube_private.reinicio_contagem_contextos where aluno_id=student and contexto_id=context_id and evento=is_event),0))
 $$;
 alter function clube_private.pontuacao_resumo(uuid) rename to resumo_antes_reinicio;
 create function clube_private.pontuacao_resumo(student uuid) returns jsonb language sql stable security definer set search_path='' as $$
 select jsonb_agg(x||jsonb_build_object('points',greatest(0,(x->>'points')::numeric-coalesce((b->>'points')::numeric,0)),
 'readingPoints',case when x->>'readingPoints' is not null then greatest(0,(x->>'readingPoints')::numeric-coalesce((b->>'readingPoints')::numeric,0)) end,
 'questionPoints',case when x->>'questionPoints' is not null then greatest(0,(x->>'questionPoints')::numeric-coalesce((b->>'questionPoints')::numeric,0)) end) order by ord)
 from jsonb_array_elements(clube_private.resumo_antes_reinicio(student)) with ordinality a(x,ord)
 left join lateral(select v b from clube_private.reinicio_contagem_alunos p cross join lateral jsonb_array_elements(p.niveis) v where p.aluno_id=student and v->>'level'=x->>'level') old on true
 $$;
 alter function clube_private.conquista_json(clube_private.conquistas_niveis) rename to conquista_antes_reinicio;
 create function clube_private.conquista_json(c clube_private.conquistas_niveis) returns jsonb language plpgsql stable security definer set search_path='' as $$
 declare result jsonb;points numeric;coins numeric;baseline clube_private.reinicio_contagem_contextos;
 begin
 result:=clube_private.conquista_antes_reinicio(c);
 select * into baseline from clube_private.reinicio_contagem_contextos where aluno_id=c.aluno_id and contexto_id=c.contexto_id and evento=c.evento and nivel=c.nivel;
 points:=clube_private.pontos_desde_reinicio(c.aluno_id,c.contexto_id,c.evento,c.nivel,(result->>'points')::numeric);
 coins:=case when c.concluida_em<(select iniciado_em from clube_private.reinicio_contagem where id) then 0 else clube_private.pontos_desde_reinicio(c.aluno_id,c.contexto_id,c.evento,c.nivel,coalesce((result->>'coins')::numeric,0)) end;
 return result||jsonb_build_object('points',points,'coins',coins,'performance',case when (result->>'maxPoints')::numeric>0 then points*100/(result->>'maxPoints')::numeric else 0 end,
 'readingPoints',case when c.concluida_em<(select iniciado_em from clube_private.reinicio_contagem where id) then 0 else greatest(0,(result->>'readingPoints')::numeric-coalesce(baseline.leitura,0)) end,
 'questionPoints',case when c.concluida_em<(select iniciado_em from clube_private.reinicio_contagem where id) then 0 else greatest(0,(result->>'questionPoints')::numeric-coalesce(baseline.questoes,0)) end,
 'beforeReset',c.concluida_em<(select iniciado_em from clube_private.reinicio_contagem where id));
 end $$;
 create or replace function clube_private.ranking_conquista(achievement uuid) returns jsonb language sql stable security definer set search_path='' as $$
 with current_score as(select * from clube_private.avaliacoes_niveis where conquista_id=achievement and evento),
 scores as(select v.aluno_id,v.concluida_em,clube_private.pontos_desde_reinicio(v.aluno_id,v.contexto_id,true,v.nivel,v.unidades/case when v.regra_pontos>=3 then 1 else 3 end) points
 from clube_private.avaliacoes_niveis v join public.evento_alunos p on p.id=v.contexto_id
 join current_score c on c.nivel=v.nivel and c.faixa_grupo=v.faixa_grupo and c.regra_pontos=v.regra_pontos
 join public.evento_alunos cp on cp.id=c.contexto_id and cp.evento_id=p.evento_id where v.evento),
 ranked as(select *,row_number() over(order by points desc,concluida_em,aluno_id) position from scores where points>0)
 select coalesce(jsonb_agg(jsonb_build_object('position',r.position,'name',coalesce(a.nome_completo,p.nome),'school',e.nome,'points',r.points,'self',r.aluno_id=(select aluno_id from current_score)) order by r.position),'[]')
 from ranked r join public.alunos a on a.id=r.aluno_id left join public.perfis p on p.id=a.perfil_id left join public.escolas e on e.id=a.escola_id where r.position<=3 or r.aluno_id=(select aluno_id from current_score)
 $$;
 revoke all on function clube_private.pontos_desde_reinicio(uuid,uuid,boolean,text,numeric),clube_private.total_antes_reinicio(uuid),clube_private.total_academico(uuid),clube_private.saldo_antes_reinicio(uuid),clube_private.saldo_moedas(uuid),clube_private.contexto_antes_reinicio(uuid,uuid,boolean),clube_private.pontuacao_contexto(uuid,uuid,boolean),clube_private.resumo_antes_reinicio(uuid),clube_private.pontuacao_resumo(uuid),clube_private.conquista_antes_reinicio(clube_private.conquistas_niveis),clube_private.conquista_json(clube_private.conquistas_niveis) from public,anon,authenticated;
 $instalar$;
 -- O ranking final tambem considera somente pontos da contagem atual.
 definition:=pg_get_functiondef('clube_private.jornada_final_json(clube_private.conclusoes_jornadas)'::regprocedure);
 definition:=replace(definition,'(f.resumo->>''points'')::numeric','greatest(0,(f.resumo->>''points'')::numeric-coalesce((select sum(b.pontos) from clube_private.reinicio_contagem_contextos b where b.aluno_id=f.aluno_id and b.contexto_id=f.contexto_id and b.evento=f.evento),0))');
 definition:=replace(definition,'(r.resumo->>''points'')::numeric','greatest(0,(r.resumo->>''points'')::numeric-coalesce((select sum(b.pontos) from clube_private.reinicio_contagem_contextos b join clube_private.conclusoes_jornadas f on f.aluno_id=b.aluno_id and f.contexto_id=b.contexto_id and f.evento=b.evento where f.id=r.id),0))');
 definition:=replace(definition,'where c.evento and','where f.concluida_em>=(select iniciado_em from clube_private.reinicio_contagem where id) and greatest(0,(f.resumo->>''points'')::numeric-coalesce((select sum(b.pontos) from clube_private.reinicio_contagem_contextos b where b.aluno_id=f.aluno_id and b.contexto_id=f.contexto_id and b.evento=f.evento),0))>0 and c.evento and');execute definition;
 -- A data e informativa; executar novamente nao muda o marco inicial.
 definition:=pg_get_functiondef('public.clube_leitura(text,jsonb)'::regprocedure);
 definition:=replace(definition,'return result;','if op=''state'' then result:=result||jsonb_build_object(''scoreCountingStartedAt'',(select iniciado_em from clube_private.reinicio_contagem where id));end if;return result;');execute definition;
 -- Recompila a view para resolver a funcao atual, mantendo os dados cadastrais.
 execute 'create or replace view clube_private.admin_alunos as select a.id,a.name,clube_private.idade_aluno(a.id) as age,a.school,a."schoolId",a."className",a."createdAt",a.status,a.completed,clube_private.total_academico(a.id) as points,a."birthDate",a.guardian,a."schoolYear" from clube_private.admin_alunos_historicos a';
end $reinicio$;
notify pgrst,'reload schema';
commit;

-- Confira o marco da contagem e os totais atuais apos a execucao.
select iniciado_em as contagem_iniciada_em,(select count(*) from public.alunos) as alunos,
 (select coalesce(sum(clube_private.total_academico(id)),0) from public.alunos) as pontos_atuais,
 (select coalesce(sum(clube_private.saldo_moedas(id)),0) from public.alunos) as moedas_atuais
from clube_private.reinicio_contagem where id;
