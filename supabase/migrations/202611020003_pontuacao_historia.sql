begin;
-- Contextos existentes continuam nas regras antigas; somente contextos novos usam 20 por história.
alter table public.jornadas add column regra_pontos smallint not null default 2 check(regra_pontos in(2,3));
alter table public.jornadas alter column regra_pontos set default 3;
alter table public.evento_alunos add column regra_pontos smallint not null default 2 check(regra_pontos in(2,3));
alter table public.evento_alunos alter column regra_pontos set default 3;
alter table public.tentativas add column leitura_concluida_em timestamptz,add column avaliacao_historia jsonb;
alter table public.tentativas add constraint avaliacao_historia_consistente check(avaliacao_historia is null or coalesce(jsonb_typeof(avaliacao_historia)='object' and avaliacao_historia->>'version'='3' and (avaliacao_historia->>'maxPoints')::numeric=20 and (avaliacao_historia->>'points')::numeric between 0 and 20 and (avaliacao_historia->>'points')::numeric=(avaliacao_historia->>'readingPoints')::numeric+(avaliacao_historia->>'questionPoints')::numeric,false));
-- Somente contextos sem tentativas, conquistas ou certificados podem adotar a regra nova.
update public.jornadas j set regra_pontos=3 where not exists(select 1 from public.tentativas a where a.jornada_id=j.id) and not exists(select 1 from clube_private.conquistas_niveis c where c.contexto_id=j.id and not c.evento) and not exists(select 1 from clube_private.conclusoes_jornadas f where f.contexto_id=j.id and not f.evento);
update public.evento_alunos p set regra_pontos=3 where not exists(select 1 from public.tentativas a where a.evento_participante_id=p.id) and not exists(select 1 from clube_private.conquistas_niveis c where c.contexto_id=p.id and c.evento) and not exists(select 1 from clube_private.conclusoes_jornadas f where f.contexto_id=p.id and f.evento);
alter table clube_private.avaliacoes_niveis add column regra_pontos smallint not null default 2 check(regra_pontos in(2,3));
alter table clube_private.avaliacoes_niveis drop constraint avaliacoes_niveis_unidades_leitura_check,
 drop constraint avaliacoes_niveis_unidades_questoes_check,drop constraint avaliacoes_niveis_unidades_check;
alter table clube_private.avaliacoes_niveis add constraint avaliacao_regra_valores check(
 (regra_pontos=2 and unidades_leitura=20 and unidades_questoes between 0 and 20 and unidades between 0 and 40) or
 (regra_pontos=3 and unidades_leitura=10*historias and unidades_questoes between 0 and 10*historias and unidades between 0 and 20*historias));
alter table clube_private.recompensas_moedas drop constraint recompensas_moedas_valor_unidades_check,
 add constraint recompensa_nao_negativa check(valor_unidades>=0);
create table clube_private.atribuicoes_jornada(
 jornada_id uuid not null references public.jornadas(id),aluno_id uuid not null references public.alunos(id),
 texto_id text not null references public.textos(id),nivel text not null references public.niveis(id),ordem integer not null,
 atividade jsonb not null,gabarito jsonb not null,primary key(jornada_id,texto_id),unique(jornada_id,nivel,ordem));
create index atribuicoes_jornada_aluno_idx on clube_private.atribuicoes_jornada(aluno_id,jornada_id,nivel);
alter table clube_private.atribuicoes_jornada enable row level security;
revoke all on clube_private.atribuicoes_jornada from public,anon,authenticated;

create function clube_private.regra_contexto(student uuid,context_id uuid,is_event boolean) returns integer language sql stable security definer set search_path='' as $$
 select coalesce(case when is_event then(select regra_pontos from public.evento_alunos where id=context_id and aluno_id=student)
 else(select regra_pontos from public.jornadas where id=context_id and aluno_id=student) end,2)
$$;
-- Os pesos antigos n?o controlam a nota nova nem podem causar overflow da corre??o legada.
create function clube_private.gabarito_historia_v3() returns trigger language plpgsql security definer set search_path='' as $$
declare a public.tentativas;
begin
 select * into a from public.tentativas where id=new.tentativa_id;
 if clube_private.regra_contexto(a.aluno_id,coalesce(a.evento_participante_id,a.jornada_id),a.evento_participante_id is not null)=3 then
  select coalesce(jsonb_object_agg(key,value||jsonb_build_object('originalPoints',coalesce(value->'originalPoints',value->'points'),'points',1)),'{}') into new.gabarito from jsonb_each(new.gabarito);
 end if;return new;
end $$;
create trigger gabarito_historia_v3 before insert or update on clube_private.conteudos_tentativas for each row execute function clube_private.gabarito_historia_v3();
revoke all on function clube_private.gabarito_historia_v3() from public,anon,authenticated;
create function clube_private.atribuir_jornada(student uuid,context_id uuid) returns void language plpgsql security definer set search_path='' as $$
begin
 if clube_private.regra_contexto(student,context_id,false)<>3 then return;end if;
 perform 1 from public.alunos where id=student for update;
 if exists(select 1 from clube_private.atribuicoes_jornada where jornada_id=context_id) then return;end if;
 perform 1 from public.textos t where t.ativo and t.obrigatorio and t.excluido_em is null order by t.id for share;
 insert into clube_private.atribuicoes_jornada(jornada_id,aluno_id,texto_id,nivel,ordem,atividade,gabarito)
 select context_id,student,t.id,t.nivel,row_number() over(partition by t.nivel order by t.ordem,t.id)::integer-1,
 jsonb_build_object('id',t.id,'title',t.titulo,'author',t.autor,'cover',t.capa_url,'minutes',t.tempo_leitura_minutos,'content',t.conteudo,'pages',t.paginas_livro,'age',t.faixa_etaria,'level',t.nivel,'questions',
 (select jsonb_agg(jsonb_build_object('id',q.id,'prompt',q.enunciado,'options',q.alternativas) order by q.id) from public.questoes q where q.texto_id=t.id and q.ativo)),
 (select jsonb_object_agg(q.id,jsonb_build_object('correct',g.correta,'points',coalesce(q.valor,n.pontos))) from public.questoes q join clube_private.gabaritos g on g.questao_id=q.id where q.texto_id=t.id and q.ativo)
 from public.textos t join public.niveis n on n.id=t.nivel
 where t.ativo and t.obrigatorio and t.excluido_em is null and clube_private.historia_idade(student,t.faixa_etaria) and clube_private.texto_pronto(t.id)
 and (t.nivel='facil' or(t.nivel='medio' and exists(select 1 from public.textos e where e.nivel='facil' and e.ativo and e.obrigatorio and e.excluido_em is null and clube_private.historia_idade(student,e.faixa_etaria) and clube_private.texto_pronto(e.id)))
 or(t.nivel='dificil' and(select count(distinct e.nivel)=2 from public.textos e where e.nivel in('facil','medio') and e.ativo and e.obrigatorio and e.excluido_em is null and clube_private.historia_idade(student,e.faixa_etaria) and clube_private.texto_pronto(e.id))));
end $$;

create function clube_private.historia_avaliar(attempt_id uuid) returns jsonb language sql stable security definer set search_path='' as $$
 with a as(select t.*,s.atividade from public.tentativas t join clube_private.conteudos_tentativas s on s.tentativa_id=t.id where t.id=attempt_id),
 counts as(select a.id,a.status,a.leitura_concluida_em,count(q)::integer total,
 count(r.questao_id)::integer answered,count(r.questao_id) filter(where r.correta is not null and r.pontos is not null)::integer corrected,
 count(r.questao_id) filter(where r.correta)::integer hits
 from a cross join lateral jsonb_array_elements(a.atividade->'questions') q
 left join public.respostas r on r.tentativa_id=a.id and r.questao_id=(q->>'id')::integer group by a.id,a.status,a.leitura_concluida_em),
 calculated as(select *,case when leitura_concluida_em is not null then 10 else 0 end reading,
 case when total>0 then 10::numeric*hits/total else 0 end questions from counts)
 select jsonb_build_object('version',3,'scoreVersion',3,'maxPoints',20,'readingComplete',leitura_concluida_em is not null,
 'stories',1,'completedStories',case when status='completed' and leitura_concluida_em is not null then 1 else 0 end,
 'questions',total,'answered',answered,'corrected',corrected,'hits',hits,'wrong',corrected-hits,'readingPoints',reading,'questionPoints',questions,
 'points',reading+questions,'questionPointValue',case when total>0 then 10::numeric/total else 0 end,
 'questionUnit',jsonb_build_object('numerator',10,'denominator',total),
 'lostPoints',case when total>0 then 10::numeric*(corrected-hits)/total else 0 end,
 'complete',status='completed' and leitura_concluida_em is not null and total>0 and answered=total and corrected=total and clube_private.resultado_completo(id)) from calculated
$$;

alter function clube_private.avaliacao_calcular(uuid,uuid,boolean,text) rename to avaliacao_calcular_v2;
create function clube_private.avaliacao_calcular(student uuid,context_id uuid,is_event boolean,level_id text) returns jsonb language plpgsql stable security definer set search_path='' as $$
declare result jsonb;
begin
 if clube_private.regra_contexto(student,context_id,is_event)<>3 then return clube_private.avaliacao_calcular_v2(student,context_id,is_event,level_id);end if;
 with assigned as(
 select l.tentativa_id,s.atividade from public.evento_leituras l join public.evento_alunos p on p.id=l.participante_id join clube_private.evento_conteudos s on s.leitura_id=l.id
 where is_event and p.aluno_id=student and p.id=context_id and s.atividade->>'level'=level_id
 union all
 select t.id,x.atividade from clube_private.atribuicoes_jornada x left join public.tentativas t on t.jornada_id=x.jornada_id and t.texto_id=x.texto_id and t.aluno_id=student
 where not is_event and x.jornada_id=context_id and x.aluno_id=student and x.nivel=level_id),
 scores as(select coalesce(t.avaliacao_historia,clube_private.historia_avaliar(t.id),jsonb_build_object('complete',false,'readingComplete',false,'questions',jsonb_array_length(a.atividade->'questions'),'answered',0,'corrected',0,'hits',0,'wrong',0,'readingPoints',0,'questionPoints',0,'points',0,'lostPoints',0)) s
 from assigned a left join public.tentativas t on t.id=a.tentativa_id),
 totals as(select count(*)::integer stories,count(*) filter(where(s->>'readingComplete')::boolean)::integer read,
 count(*) filter(where(s->>'complete')::boolean)::integer completed,coalesce(sum((s->>'questions')::integer),0) questions,
 coalesce(sum((s->>'answered')::integer),0) answered,coalesce(sum((s->>'corrected')::integer),0) corrected,
 coalesce(sum((s->>'hits')::integer),0) hits,coalesce(sum((s->>'wrong')::integer),0) wrong,
 coalesce(sum((s->>'readingPoints')::numeric),0) reading,coalesce(sum((s->>'questionPoints')::numeric),0) points,coalesce(sum((s->>'lostPoints')::numeric),0) lost from scores)
 select jsonb_build_object('version',3,'scoreVersion',3,'maxPoints',20*stories,'stories',stories,'completedStories',completed,'readStories',read,
 'questions',questions,'answered',answered,'corrected',corrected,'hits',hits,'wrong',wrong,'readingPoints',reading,'questionPoints',points,'points',reading+points,
 'pointUnits',reading+points,'pointDivisor',1,'lostPoints',lost,'complete',stories>0 and completed=stories and questions>0 and answered=questions and corrected=questions) into result from totals;
 return result;
end $$;

alter function clube_private.progresso_niveis(uuid) rename to progresso_niveis_v2;
create function clube_private.progresso_niveis(student uuid) returns table(id text,available bigint,completed bigint,required bigint,required_completed bigint,complete boolean)
language plpgsql stable security definer set search_path='' as $$
declare context_id uuid;
begin
 select j.id into context_id from public.jornadas j where j.aluno_id=student order by j.ciclo desc limit 1;
 if clube_private.regra_contexto(student,context_id,false)<>3 or not exists(select 1 from clube_private.atribuicoes_jornada x where x.jornada_id=context_id) then
 return query select * from clube_private.progresso_niveis_v2(student);return;end if;
 return query with counts as(select n.id level_id,count(x.texto_id) amount,count(x.texto_id) filter(where coalesce((t.avaliacao_historia->>'complete')::boolean,false)) done
 from public.niveis n left join clube_private.atribuicoes_jornada x on x.nivel=n.id and x.jornada_id=context_id and clube_private.historia_idade(student,x.atividade->>'age')
 left join public.tentativas t on t.jornada_id=x.jornada_id and t.texto_id=x.texto_id and t.aluno_id=student group by n.id)
 select level_id,amount,done,amount,done,amount>0 and amount=done from counts;
end $$;
alter function clube_private.texto_autorizado(uuid,text) rename to texto_autorizado_v2;
create function clube_private.texto_autorizado(student uuid,text_id text) returns boolean language sql stable security definer set search_path='' as $$
 select case when exists(select 1 from public.jornadas j where j.aluno_id=student and j.regra_pontos=3 and j.id=(select id from public.jornadas where aluno_id=student order by ciclo desc limit 1)) and exists(select 1 from clube_private.atribuicoes_jornada x where x.aluno_id=student and x.jornada_id=(select id from public.jornadas where aluno_id=student order by ciclo desc limit 1))
 then exists(select 1 from clube_private.atribuicoes_jornada x where x.aluno_id=student and x.texto_id=text_id and x.jornada_id=(select id from public.jornadas where aluno_id=student order by ciclo desc limit 1)
 and clube_private.historia_idade(student,x.atividade->>'age') and clube_private.nivel_liberado(student,x.nivel))
 else clube_private.texto_autorizado_v2(student,text_id) end
$$;

alter function clube_private.conquista_registrar(public.tentativas) rename to conquista_registrar_v2;
create function clube_private.conquista_registrar(a public.tentativas) returns uuid language plpgsql security definer set search_path='' as $$
declare stats jsonb;context_id uuid;is_event boolean;c clube_private.conquistas_niveis;group_value text;
begin
 context_id:=coalesce(a.evento_participante_id,a.jornada_id);is_event:=a.evento_participante_id is not null;
 if clube_private.regra_contexto(a.aluno_id,context_id,is_event)<>3 then return clube_private.conquista_registrar_v2(a);end if;
 if not clube_private.resultado_completo(a.id) then return null;end if;
 if a.leitura_concluida_em is null then raise exception 'Conclua a leitura antes de finalizar.' using errcode='22023';end if;
 update public.tentativas set avaliacao_historia=clube_private.historia_avaliar(a.id) where id=a.id and avaliacao_historia is null;
 stats:=clube_private.avaliacao_calcular(a.aluno_id,context_id,is_event,a.nivel);
 if not coalesce((stats->>'complete')::boolean,false) then return null;end if;
 insert into clube_private.conquistas_niveis(aluno_id,contexto_id,evento,nivel,pontos,proximo_nivel)
 values(a.aluno_id,context_id,is_event,a.nivel,(stats->>'points')::numeric,clube_private.conquista_proximo(a.aluno_id,context_id,is_event,a.nivel)) on conflict(aluno_id,contexto_id,evento,nivel) do nothing;
 select * into c from clube_private.conquistas_niveis where aluno_id=a.aluno_id and contexto_id=context_id and evento=is_event and nivel=a.nivel;
 if is_event then select case when jsonb_array_length(configuracao)>0 then 'idade:'||idade_referencia else 'faixa:'||idade_min||':'||idade_max end into group_value from public.evento_alunos where id=context_id;end if;
 insert into clube_private.avaliacoes_niveis(conquista_id,aluno_id,contexto_id,evento,nivel,historias,questoes,acertos,unidades_leitura,unidades_questoes,unidades,faixa_grupo,regra_pontos)
 values(c.id,a.aluno_id,context_id,is_event,a.nivel,(stats->>'stories')::integer,(stats->>'questions')::integer,(stats->>'hits')::integer,(stats->>'readingPoints')::numeric,(stats->>'questionPoints')::numeric,(stats->>'points')::numeric,group_value,3) on conflict(conquista_id) do nothing;
 insert into clube_private.recompensas_moedas(conquista_id,aluno_id,valor_unidades) select conquista_id,aluno_id,unidades from clube_private.avaliacoes_niveis where conquista_id=c.id on conflict(conquista_id) do nothing;
 return case when c.apresentada_em is null then c.id else null end;
end $$;

create function clube_private.validar_recompensa() returns trigger language plpgsql security definer set search_path='' as $$
begin
 if not exists(select 1 from clube_private.avaliacoes_niveis v where v.conquista_id=new.conquista_id and v.aluno_id=new.aluno_id and v.unidades=new.valor_unidades) then raise exception 'Recompensa divergente da avaliação oficial.' using errcode='22023';end if;return new;
end $$;
create trigger validar_recompensa before insert or update on clube_private.recompensas_moedas for each row execute function clube_private.validar_recompensa();
create or replace function clube_private.saldo_moedas(student uuid) returns numeric language sql stable security definer set search_path='' as $$
 select coalesce(sum(amount/divisor),0) from(select sum(r.valor_unidades) amount,case when v.regra_pontos=3 then 1 else 3 end divisor
 from clube_private.recompensas_moedas r join clube_private.avaliacoes_niveis v on v.conquista_id=r.conquista_id where r.aluno_id=student group by v.regra_pontos) x
$$;

create or replace function clube_private.ranking_conquista(achievement uuid) returns jsonb language sql stable security definer set search_path='' as $$
 with current_score as(select * from clube_private.avaliacoes_niveis where conquista_id=achievement and evento),
 ranked as(select v.aluno_id,v.unidades/case when v.regra_pontos=3 then 1 else 3 end points,
 row_number() over(order by v.unidades desc,v.concluida_em,v.aluno_id) position
 from clube_private.avaliacoes_niveis v join public.evento_alunos p on p.id=v.contexto_id
 join current_score c on c.nivel=v.nivel and c.faixa_grupo=v.faixa_grupo and c.regra_pontos=v.regra_pontos
 join public.evento_alunos cp on cp.id=c.contexto_id and cp.evento_id=p.evento_id where v.evento)
 select coalesce(jsonb_agg(jsonb_build_object('position',r.position,'name',coalesce(a.nome_completo,p.nome),'school',e.nome,'points',r.points,'self',r.aluno_id=(select aluno_id from current_score)) order by r.position),'[]')
 from ranked r join public.alunos a on a.id=r.aluno_id left join public.perfis p on p.id=a.perfil_id left join public.escolas e on e.id=a.escola_id where r.position<=3 or r.aluno_id=(select aluno_id from current_score)
$$;
alter function clube_private.conquista_json(clube_private.conquistas_niveis) rename to conquista_json_v2;
create function clube_private.conquista_json(c clube_private.conquistas_niveis) returns jsonb language plpgsql stable security definer set search_path='' as $$
declare v clube_private.avaliacoes_niveis;
begin
 select * into v from clube_private.avaliacoes_niveis where conquista_id=c.id;
 if v.regra_pontos is distinct from 3 then return clube_private.conquista_json_v2(c);end if;
 return clube_private.conquista_json_antes_moedas(c)||jsonb_build_object('scoreVersion',3,'points',v.unidades,'maxPoints',20*v.historias,'performance',v.unidades*100/(20*v.historias),
 'stories',v.historias,'completedStories',v.historias,'questions',v.questoes,'hits',v.acertos,'wrong',v.questoes-v.acertos,'readingPoints',v.unidades_leitura,'questionPoints',v.unidades_questoes,
 'lostPoints',10*v.historias-v.unidades_questoes,'pointUnits',v.unidades,'pointDivisor',1,'coins',(select valor_unidades from clube_private.recompensas_moedas where conquista_id=c.id),
 'coinBalance',clube_private.saldo_moedas(c.aluno_id),'ranking',clube_private.ranking_conquista(c.id));
end $$;

create or replace function clube_private.total_academico(student uuid) returns numeric language sql stable security definer set search_path='' as $$
 with contexts as(select distinct coalesce(evento_participante_id,jornada_id) context_id,evento_participante_id is not null is_event,nivel from public.tentativas where aluno_id=student and coalesce(evento_participante_id,jornada_id) is not null),
 normalized as(select c.*,case when clube_private.regra_contexto(student,c.context_id,c.is_event)=3 then 1 else 3 end divisor,
 case when clube_private.regra_contexto(student,c.context_id,c.is_event)=3 then coalesce(v.unidades,0) else coalesce(v.unidades,(clube_private.avaliacao_calcular(student,c.context_id,c.is_event,c.nivel)->>'pointUnits')::numeric) end amount
 from contexts c left join clube_private.avaliacoes_niveis v on v.aluno_id=student and v.contexto_id=c.context_id and v.evento=c.is_event and v.nivel=c.nivel
 where not exists(select 1 from clube_private.pontuacao_legada l where l.aluno_id=student and l.contexto_id=c.context_id and l.evento=c.is_event and l.nivel=c.nivel))
 select coalesce((select sum(amount/divisor) from(select sum(amount) amount,divisor from normalized group by divisor) g),0)+coalesce((select sum(a.pontuacao) from clube_private.admin_resultados_validos a where a.aluno_id=student and not exists(select 1 from normalized c where c.context_id=coalesce(a.evento_participante_id,a.jornada_id) and c.nivel=a.nivel and c.is_event=(a.evento_participante_id is not null))),0)
$$;

alter function clube_private.attempt_json(public.tentativas) rename to attempt_json_v2;
create function clube_private.attempt_json(a public.tentativas) returns jsonb language plpgsql stable security definer set search_path='' as $$
declare result jsonb;grade jsonb;total integer;
begin
 result:=clube_private.attempt_json_v2(a);
 if clube_private.regra_contexto(a.aluno_id,coalesce(a.evento_participante_id,a.jornada_id),a.evento_participante_id is not null)<>3 then return result;end if;
 grade:=coalesce(a.avaliacao_historia,clube_private.historia_avaliar(a.id));result:=result||jsonb_build_object('storyScore',grade);
 if a.status='completed' then
  total:=(grade->>'questions')::integer;
  result:=jsonb_set(result,'{result,points}',grade->'points');
  result:=jsonb_set(result,'{result,details}',coalesce((select jsonb_agg(q||jsonb_build_object('points',case when q->>'selected'=q->>'correct' then 10::numeric/nullif(total,0) else 0 end) order by ord)
  from jsonb_array_elements(result->'result'->'details') with ordinality as items(q,ord)),'[]'));
 end if;return result;
end $$;

-- O resumo final permanece imutável. Somente novos resumos recebem o divisor correto por regra.
do $final$ declare definition text;begin
 definition:=pg_get_functiondef('clube_private.jornada_registrar(uuid,uuid,boolean)'::regprocedure);
 definition:=replace(definition,'points:=v.unidades/3;maximum:=40::numeric/3;','points:=v.unidades/case when v.regra_pontos=3 then 1 else 3 end;maximum:=case when v.regra_pontos=3 then 20*v.historias else 40::numeric/3 end;');
 definition:=replace(definition,'coins:=coalesce(coin_units,0)/3;','coins:=coalesce(coin_units,0)/case when v.regra_pontos=3 then 1 else 3 end;');
 definition:=replace(definition,'''pointUnits'',v.unidades,','''scoreVersion'',coalesce(v.regra_pontos,1),''pointDivisor'',case when v.regra_pontos=3 then 1 else 3 end,''pointUnits'',v.unidades,');
 definition:=replace(definition,'sum((x->>''pointUnits'')::numeric)/3','sum((x->>''pointUnits'')::numeric)/min((x->>''pointDivisor'')::numeric)');
 definition:=replace(definition,'cardinality(levels)*40::numeric/3','(select sum((x->>''maxPoints'')::numeric) from jsonb_array_elements(items) x)');
 definition:=replace(definition,'sum((x->>''coinUnits'')::numeric)/3','sum((x->>''coinUnits'')::numeric/case when x->>''scoreVersion''=''3'' then 1 else 3 end)');execute definition;
 definition:=pg_get_functiondef('clube_private.jornada_final_json(clube_private.conclusoes_jornadas)'::regprocedure);
 definition:=replace(definition,'f.resumo->>''legacy''=c.resumo->>''legacy''','f.resumo->>''legacy''=c.resumo->>''legacy'' and coalesce(f.resumo->''levels''->0->>''scoreVersion'',''2'')=coalesce(c.resumo->''levels''->0->>''scoreVersion'',''2'')');execute definition;
end $final$;

alter function public.clube_leitura(text,jsonb) rename to leitura_antes_pontos_historia;
alter function public.leitura_antes_pontos_historia(text,jsonb) set schema clube_private;
create function public.clube_leitura(op text,args jsonb default '{}') returns jsonb language plpgsql security definer set search_path='' as $$
declare student uuid;context_id uuid;result jsonb;a public.tentativas;chosen clube_private.atribuicoes_jornada;level_id text;modern boolean;
begin
 student:=clube_private.aluno_atual();if student is null then raise exception 'Aluno não identificado' using errcode='42501';end if;
 if op in('enter','start') then
  select id into context_id from public.jornadas where aluno_id=student order by ciclo desc limit 1;
  if clube_private.regra_contexto(student,context_id,false)=3 then
   if clube_private.idade_aluno(student) is null then raise exception 'Confira a data de nascimento com a escola.' using errcode='22023';end if;
   level_id:=args->>'level';if level_id is null or level_id not in('facil','medio','dificil') then raise exception 'Nível inválido' using errcode='22023';end if;
   perform clube_private.atribuir_jornada(student,context_id);
   if not clube_private.nivel_liberado(student,level_id) then raise exception 'Conclua o nível anterior.' using errcode='42501';end if;
   select * into a from public.tentativas where aluno_id=student and jornada_id=context_id and status='started' and clube_private.texto_autorizado(student,texto_id) order by(nivel=level_id) desc,id limit 1 for update;
   if a.id is null then
    select x.* into chosen from clube_private.atribuicoes_jornada x where x.jornada_id=context_id and x.nivel=level_id and clube_private.historia_idade(student,x.atividade->>'age')
    and not exists(select 1 from public.tentativas t where t.jornada_id=context_id and t.texto_id=x.texto_id and(t.avaliacao_historia->>'complete')::boolean) order by x.ordem limit 1;
    if chosen.texto_id is not null then
     if args?'storyId' and args->>'storyId' is distinct from chosen.texto_id then raise exception 'Siga a sequência atribuída.' using errcode='42501';end if;
     insert into public.tentativas(aluno_id,jornada_id,texto_id,nivel) values(student,context_id,chosen.texto_id,chosen.nivel) returning * into a;
     update clube_private.conteudos_tentativas set atividade=chosen.atividade,gabarito=chosen.gabarito where tentativa_id=a.id;
     update public.jornadas set status='em_andamento',texto_atual_id=a.texto_id,nivel_atual=a.nivel where id=context_id;
    end if;
   elsif args?'storyId' and args->>'storyId' is distinct from a.texto_id then raise exception 'Siga a sequência atribuída.' using errcode='42501';end if;
   if op='start' then if a.id is null then raise exception 'Nenhuma história atribuída pendente.' using errcode='22023';end if;return clube_private.leitura_tentativa(a);end if;
   return jsonb_build_object('attempt',case when a.id is not null then clube_private.leitura_tentativa(a) else null end,'empty',a.id is null,'levelComplete',coalesce((select complete from clube_private.progresso_niveis(student) where id=level_id),false),'journeyComplete',clube_private.jornada_completa(student));
  end if;
 end if;
 if op in('get','page','stage','answer','finish') then
  select * into a from public.tentativas where id=(args->>'id')::uuid and aluno_id=student;
  if a.id is null then raise exception 'Tentativa não encontrada' using errcode='42501';end if;
  modern:=clube_private.regra_contexto(student,coalesce(a.evento_participante_id,a.jornada_id),a.evento_participante_id is not null)=3;
  if modern and op='finish' and a.leitura_concluida_em is null then raise exception 'Conclua a leitura antes de finalizar.' using errcode='22023';end if;
 end if;
 result:=clube_private.leitura_antes_pontos_historia(op,args);
 if modern and op='stage' and args->>'stage'='questoes' then
  update public.tentativas set leitura_concluida_em=coalesce(leitura_concluida_em,now()) where id=a.id;
  return result||jsonb_build_object('storyScore',clube_private.historia_avaliar(a.id));
 end if;
 if op='state' then
  result:=jsonb_set(result,'{history}',coalesce((select jsonb_agg(x||jsonb_build_object('points',coalesce(t.avaliacao_historia->'points',x->'points')) order by ord) from jsonb_array_elements(result->'history') with ordinality as h(x,ord) join public.tentativas t on t.id=(x->>'id')::uuid),'[]'));
 end if;
 return result;
end $$;
revoke all on function public.clube_leitura(text,jsonb) from public,anon;
grant execute on function public.clube_leitura(text,jsonb) to authenticated;
-- O endpoint legado continua disponível para históricos, mas não contorna a regra nova.
alter function public.clube_api(text,jsonb) rename to api_antes_pontos_historia;
alter function public.api_antes_pontos_historia(text,jsonb) set schema clube_private;
create function public.clube_api(op text,args jsonb default '{}') returns jsonb language plpgsql security definer set search_path='' as $$
begin
 if op in('get','answer','finish') and exists(select 1 from public.tentativas a where a.id=(args->>'id')::uuid and clube_private.regra_contexto(a.aluno_id,coalesce(a.evento_participante_id,a.jornada_id),a.evento_participante_id is not null)=3) then return public.clube_leitura(op,args);end if;
 return clube_private.api_antes_pontos_historia(op,args);
end $$;
revoke all on function public.clube_api(text,jsonb) from public,anon;
grant execute on function public.clube_api(text,jsonb) to authenticated;
-- Funções antigas ficam privadas apenas para interpretar contextos históricos.
revoke all on function clube_private.regra_contexto(uuid,uuid,boolean),clube_private.atribuir_jornada(uuid,uuid),clube_private.historia_avaliar(uuid),clube_private.avaliacao_calcular_v2(uuid,uuid,boolean,text),
 clube_private.progresso_niveis_v2(uuid),clube_private.texto_autorizado_v2(uuid,text),clube_private.conquista_registrar_v2(public.tentativas),clube_private.validar_recompensa(),
 clube_private.conquista_json_v2(clube_private.conquistas_niveis),clube_private.attempt_json_v2(public.tentativas),clube_private.leitura_antes_pontos_historia(text,jsonb),clube_private.api_antes_pontos_historia(text,jsonb)
 from public,anon,authenticated;
revoke all on function clube_private.avaliacao_calcular(uuid,uuid,boolean,text),clube_private.progresso_niveis(uuid),clube_private.texto_autorizado(uuid,text),clube_private.conquista_registrar(public.tentativas),clube_private.conquista_json(clube_private.conquistas_niveis),clube_private.attempt_json(public.tentativas) from public,anon,authenticated;
-- Cadastro, login e relatórios consultam o mesmo total acadêmico.
alter function clube_private.aluno_json(uuid) rename to aluno_json_antes_pontos_historia;
create function clube_private.aluno_json(student uuid) returns jsonb language sql stable security definer set search_path='' as $$
 select clube_private.aluno_json_antes_pontos_historia(student)||jsonb_build_object('points',clube_private.total_academico(student),'completed',(select count(*) from clube_private.admin_resultados_validos where aluno_id=student))
$$;
alter view clube_private.admin_alunos rename to admin_alunos_historicos;
create view clube_private.admin_alunos as select a.id,a.name,clube_private.idade_aluno(a.id) as age,a.school,a."schoolId",a."className",a."createdAt",a.status,a.completed,
 clube_private.total_academico(a.id) as points,a."birthDate",a.guardian,a."schoolYear" from clube_private.admin_alunos_historicos a;
revoke all on clube_private.admin_alunos from public,anon,authenticated;
create function clube_private.pontuacao_contexto(student uuid,context_id uuid,is_event boolean) returns numeric language sql stable security definer set search_path='' as $$
 with levels as(select distinct nivel from public.tentativas where aluno_id=student and coalesce(evento_participante_id,jornada_id)=context_id and(evento_participante_id is not null)=is_event),
 totals as(select l.nivel,
 case when exists(select 1 from clube_private.pontuacao_legada p where p.aluno_id=student and p.contexto_id=context_id and p.evento=is_event and p.nivel=l.nivel)
 then(select coalesce(sum(t.pontuacao),0) from clube_private.admin_resultados_validos t where t.aluno_id=student and coalesce(t.evento_participante_id,t.jornada_id)=context_id and t.nivel=l.nivel)
 when clube_private.regra_contexto(student,context_id,is_event)=3 then coalesce(v.unidades,0)
 else coalesce(v.unidades,(clube_private.avaliacao_calcular(student,context_id,is_event,l.nivel)->>'pointUnits')::numeric)/3 end amount
 from levels l left join clube_private.avaliacoes_niveis v on v.aluno_id=student and v.contexto_id=context_id and v.evento=is_event and v.nivel=l.nivel)
 select coalesce(sum(amount),0) from totals
$$;
create function clube_private.pontos_validos_tentativa(attempt_id uuid) returns numeric language plpgsql stable security definer set search_path='' as $$
declare stats jsonb;context_id uuid;is_event boolean;a public.tentativas;
begin
 select * into a from public.tentativas where id=attempt_id;
 context_id:=coalesce(a.evento_participante_id,a.jornada_id);is_event:=a.evento_participante_id is not null;
 if clube_private.regra_contexto(a.aluno_id,context_id,is_event)=3 then return(a.avaliacao_historia->>'points')::numeric;end if;
 if context_id is null or exists(select 1 from clube_private.pontuacao_legada p where p.aluno_id=a.aluno_id and p.contexto_id=context_id and p.evento=is_event and p.nivel=a.nivel) then return a.pontuacao;end if;
 stats:=clube_private.avaliacao_calcular(a.aluno_id,context_id,is_event,a.nivel);
 return 20::numeric/(nullif((stats->>'stories')::numeric,0)*3)+20::numeric*a.acertos/(nullif((stats->>'questions')::numeric,0)*3);
end $$;
do $reports$
declare target regprocedure;definition text;
begin
 -- Recompila as consultas que dependem da view oficial e conserva filtros/paginação.
 foreach target in array array['clube_private.clube_gestao(text,jsonb)'::regprocedure,'public.clube_admin(text,jsonb)'::regprocedure,'public.clube_escolas(text,jsonb)'::regprocedure,'public.clube_eventos(text,jsonb)'::regprocedure] loop
  definition:=pg_get_functiondef(target);
  definition:=replace(definition,'''points'',(select coalesce(sum(pontuacao),0) from clube_private.admin_resultados_validos)', '''points'',(select coalesce(sum(clube_private.total_academico(id)),0) from public.alunos)');
  definition:=replace(definition,'(select coalesce(sum(pontuacao),0) from clube_private.admin_resultados_validos v where v.jornada_id=j.id)','clube_private.pontuacao_contexto(student,j.id,false)');
  definition:=replace(definition,'(select v.pontuacao from clube_private.admin_resultados_validos v where v.id=t.id)','(select clube_private.pontos_validos_tentativa(v.id) from clube_private.admin_resultados_validos v where v.id=t.id)');
  definition:=replace(definition,'coalesce(sum(v.pontuacao),0)','coalesce(sum(clube_private.pontos_validos_tentativa(v.id)),0)');
  definition:=replace(definition,'r.pontos as points', 'case when clube_private.regra_contexto(t.aluno_id,coalesce(t.evento_participante_id,t.jornada_id),t.evento_participante_id is not null)=3 then case when r.correta then 10::numeric/nullif(jsonb_array_length(s.atividade->''questions''),0) when r.correta is null then null else 0 end else r.pontos end as points');
  execute definition;
 end loop;
end $reports$;
revoke all on function clube_private.aluno_json(uuid),clube_private.aluno_json_antes_pontos_historia(uuid),clube_private.pontuacao_contexto(uuid,uuid,boolean),clube_private.pontos_validos_tentativa(uuid) from public,anon,authenticated;

notify pgrst,'reload schema';
commit;
