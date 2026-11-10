-- Atualiza o catalogo comum sem reescrever notas, snapshots ou selecoes de eventos.
alter table clube_private.conclusoes_jornadas add column atual boolean not null default true;
alter table clube_private.conclusoes_jornadas drop constraint conclusoes_jornadas_aluno_id_contexto_id_evento_key;
create unique index conclusao_jornada_atual_idx on clube_private.conclusoes_jornadas(aluno_id,contexto_id,evento) where atual;
create function clube_private.sincronizar_catalogo(student uuid) returns void language plpgsql security definer set search_path='' as $$
declare context_id uuid;added integer;
begin
 perform 1 from public.alunos where id=student for update;
 select id into context_id from public.jornadas where aluno_id=student order by ciclo desc limit 1;
 if clube_private.regra_contexto(student,context_id,false)<>3 then return;end if;
 if not exists(select 1 from clube_private.atribuicoes_jornada where jornada_id=context_id) then return;end if;
 insert into clube_private.atribuicoes_jornada(jornada_id,aluno_id,texto_id,nivel,ordem,atividade,gabarito)
 select context_id,student,t.id,t.nivel,coalesce((select max(x.ordem)+1 from clube_private.atribuicoes_jornada x where x.jornada_id=context_id and x.nivel=t.nivel),0)+row_number() over(partition by t.nivel order by t.ordem,t.id)::integer-1,
 jsonb_build_object('id',t.id,'title',t.titulo,'author',t.autor,'cover',t.capa_url,'minutes',t.tempo_leitura_minutos,'content',t.conteudo,'pages',t.paginas_livro,'age',t.faixa_etaria,'level',t.nivel,'questions',
 (select jsonb_agg(jsonb_build_object('id',q.id,'prompt',q.enunciado,'options',q.alternativas) order by q.id) from public.questoes q where q.texto_id=t.id and q.ativo)),
 (select jsonb_object_agg(q.id,jsonb_build_object('correct',g.correta,'points',coalesce(q.valor,n.pontos))) from public.questoes q join clube_private.gabaritos g on g.questao_id=q.id where q.texto_id=t.id and q.ativo)
 from public.textos t join public.niveis n on n.id=t.nivel
 where t.ativo and t.obrigatorio and t.excluido_em is null and clube_private.historia_idade(student,t.faixa_etaria) and clube_private.texto_pronto(t.id)
 and not exists(select 1 from clube_private.atribuicoes_jornada x where x.jornada_id=context_id and x.texto_id=t.id)
 and not exists(select 1 from clube_private.conquistas_niveis c where c.aluno_id=student and c.contexto_id=context_id and not c.evento and c.nivel=t.nivel)
 and (t.nivel='facil' or (t.nivel='medio' and exists(select 1 from clube_private.atribuicoes_jornada x where x.jornada_id=context_id and x.nivel='facil')) or(t.nivel='dificil' and(select count(distinct x.nivel)=2 from clube_private.atribuicoes_jornada x where x.jornada_id=context_id and x.nivel in('facil','medio'))));
 get diagnostics added=row_count;
 if added>0 then
  update clube_private.conclusoes_jornadas set atual=false where aluno_id=student and contexto_id=context_id and not evento and atual;
  update public.jornadas set status='em_andamento',concluida_em=null where id=context_id;
 end if;
end $$;
-- Certificados anteriores continuam consultaveis; a jornada ampliada recebe um novo resumo ao terminar.
do $patch$ declare definition text;begin
 definition:=pg_get_functiondef('clube_private.jornada_registrar(uuid,uuid,boolean)'::regprocedure);
 definition:=replace(definition,'from clube_private.conclusoes_jornadas where aluno_id=student and contexto_id=context_id and evento=is_event','from clube_private.conclusoes_jornadas where aluno_id=student and contexto_id=context_id and evento=is_event and atual');
 definition:=replace(definition,'on conflict(aluno_id,contexto_id,evento) do nothing','on conflict(aluno_id,contexto_id,evento) where atual do nothing');execute definition;
 definition:=pg_get_functiondef('clube_private.leitura_antes_pontos_historia(text,jsonb)'::regprocedure);
 definition:=replace(definition,'where aluno_id=student and apresentada_em is null','where aluno_id=student and atual and apresentada_em is null');execute definition;
end $patch$;
alter function public.clube_leitura(text,jsonb) rename to leitura_antes_catalogo;
alter function public.leitura_antes_catalogo(text,jsonb) set schema clube_private;
create function public.clube_leitura(op text,args jsonb default '{}') returns jsonb language plpgsql security definer set search_path='' as $$
declare student uuid;
begin
 student:=clube_private.aluno_atual();if student is null then raise exception 'Aluno nao identificado' using errcode='42501';end if;
 if op in('state','enter','start','finish') then
  perform clube_private.sincronizar_catalogo(student);
  -- Segunda passagem permite incorporar Medio e Dificil publicados juntos.
  perform clube_private.sincronizar_catalogo(student);
 end if;
 return clube_private.leitura_antes_catalogo(op,args);
end $$;
revoke all on function public.clube_leitura(text,jsonb) from public,anon;
grant execute on function public.clube_leitura(text,jsonb) to authenticated;
revoke all on function clube_private.sincronizar_catalogo(uuid),clube_private.leitura_antes_catalogo(text,jsonb) from public,anon,authenticated;
notify pgrst,'reload schema';
