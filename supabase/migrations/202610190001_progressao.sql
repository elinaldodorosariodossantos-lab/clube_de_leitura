begin;
-- ativo é a publicação existente; nenhum conteúdo ou resultado é removido.
alter table public.textos add column obrigatorio boolean not null default true,
 add column resumo text, add column capa_url text check(capa_url is null or capa_url ~ '^https://'),
 add column tempo_leitura_minutos integer check(tempo_leitura_minutos>0);
create function clube_private.texto_pronto(text_id text) returns boolean language sql stable security definer set search_path='' as $$
 select exists(select 1 from public.questoes where texto_id=text_id) and not exists(select 1 from public.questoes q where q.texto_id=text_id and not exists(select 1 from clube_private.gabaritos g where g.questao_id=q.id))
$$;
create function clube_private.progresso_niveis(student uuid) returns table(id text,available bigint,completed bigint,required bigint,required_completed bigint,complete boolean) language sql stable security definer set search_path='' as $$
 with latest as(select j.id from public.jornadas j where aluno_id=student order by ciclo desc limit 1), counts as(
 select n.id,count(t.id) as available,count(t.id) filter(where exists(select 1 from clube_private.admin_resultados_validos a where a.aluno_id=student and a.jornada_id=(select id from latest) and a.texto_id=t.id and a.status='completed')) as completed,
 count(t.id) filter(where t.obrigatorio) as required,count(t.id) filter(where t.obrigatorio and exists(select 1 from clube_private.admin_resultados_validos a where a.aluno_id=student and a.jornada_id=(select id from latest) and a.texto_id=t.id and a.status='completed')) as required_completed
 from public.niveis n left join public.textos t on t.nivel=n.id and t.ativo and clube_private.texto_pronto(t.id) group by n.id)
 select *,available>0 and required=required_completed from counts
$$;
create function clube_private.nivel_liberado(student uuid,level_id text) returns boolean language sql stable security definer set search_path='' as $$
 select student is not null and case level_id when 'facil' then true when 'medio' then coalesce((select complete from clube_private.progresso_niveis(student) where id='facil'),false)
 when 'dificil' then (select count(*)=2 and bool_and(complete) from clube_private.progresso_niveis(student) where id in('facil','medio')) else false end
$$;
create function clube_private.jornada_completa(student uuid) returns boolean language sql stable security definer set search_path='' as $$
 select count(*)=3 and bool_and(complete) from clube_private.progresso_niveis(student)
$$;
create function clube_private.texto_autorizado(student uuid,text_id text) returns boolean language sql stable security definer set search_path='' as $$
 select exists(select 1 from public.textos t where t.id=text_id and t.ativo and clube_private.texto_pronto(t.id) and clube_private.nivel_liberado(student,t.nivel))
$$;
create or replace function clube_private.leitura_estado(student uuid) returns jsonb language sql stable security definer set search_path='' as $$
 select jsonb_build_object('student',clube_private.aluno_json(student)||jsonb_build_object('completed',(select count(*) from clube_private.admin_resultados_validos where aluno_id=student),'points',(select coalesce(sum(pontuacao),0) from clube_private.admin_resultados_validos where aluno_id=student)),'journey',
 (select jsonb_build_object('id',j.id,'cycle',j.ciclo,'status',case when clube_private.jornada_completa(student) then 'concluida' when j.status='concluida' then 'em_andamento' else j.status end) from public.jornadas j where aluno_id=student order by ciclo desc limit 1),
 'levels',(select jsonb_agg(to_jsonb(p)||jsonb_build_object('requiredCompleted',p.required_completed,'unlocked',clube_private.nivel_liberado(student,p.id)) order by case p.id when 'facil' then 1 when 'medio' then 2 else 3 end) from clube_private.progresso_niveis(student) p),
 'active',(select clube_private.leitura_tentativa(a) from public.tentativas a where a.aluno_id=student and a.jornada_id=(select id from public.jornadas where aluno_id=student order by ciclo desc limit 1) and a.status='started' and clube_private.texto_autorizado(student,a.texto_id) order by a.id limit 1),
 'history',coalesce((select jsonb_agg(jsonb_build_object('id',a.id,'title',t.titulo,'level',a.nivel,'cycle',j.ciclo,'points',a.pontuacao,'completedAt',a.concluida_em) order by a.concluida_em desc) from clube_private.admin_resultados_validos a join public.textos t on t.id=a.texto_id left join public.jornadas j on j.id=a.jornada_id where a.aluno_id=student and a.status='completed'),'[]'))
$$;
create or replace function public.clube_leitura(op text,args jsonb default '{}') returns jsonb language plpgsql security definer set search_path='' as $$
declare student uuid;j public.jornadas;a public.tentativas;txt public.textos;qid integer;choice integer;amount integer;total integer;idx integer;
begin
 student:=clube_private.aluno_atual();
 if student is null then raise exception 'Aluno não identificado' using errcode='42501';end if;
 if op='state' then return clube_private.leitura_estado(student);end if;
 if op='stories' then
  if not clube_private.nivel_liberado(student,args->>'level') then raise exception 'Nível bloqueado' using errcode='42501';end if;
  return coalesce((select jsonb_agg(jsonb_build_object('id',t.id,'title',t.titulo,'summary',t.resumo,'cover',t.capa_url,'minutes',t.tempo_leitura_minutos,'required',t.obrigatorio,'status',coalesce(saved.status,'not_started'),'attemptId',saved.id) order by t.titulo,t.id)
   from public.textos t left join lateral(select x.id,x.status from public.tentativas x where x.aluno_id=student and x.texto_id=t.id and x.jornada_id=(select id from public.jornadas where aluno_id=student order by ciclo desc limit 1) order by (x.status='completed') desc,x.id limit 1) saved on true
   where t.nivel=args->>'level' and t.ativo and clube_private.texto_pronto(t.id)),'[]');
 end if;
 -- Todas as mutações do aluno são serializadas para impedir tentativas/ciclos duplicados.
 perform 1 from public.alunos where id=student for update;
 select * into j from public.jornadas where aluno_id=student order by ciclo desc limit 1 for update;
 if op='new_journey' then
  if j.id is null or not clube_private.jornada_completa(student) or exists(select 1 from public.tentativas where jornada_id=j.id and status='started') then raise exception 'Conclua a jornada atual antes de iniciar outra' using errcode='22023';end if;
  insert into public.jornadas(aluno_id,ciclo) values(student,j.ciclo+1);
  return clube_private.leitura_estado(student);
 elsif op='start' then
  if args->>'level' is null or args->>'level' not in ('facil','medio','dificil') then raise exception 'Nível inválido' using errcode='22023';end if;
  if j.id is null then raise exception 'Jornada indisponível' using errcode='22023';end if;
  if not clube_private.nivel_liberado(student,args->>'level') then raise exception 'Nível bloqueado' using errcode='42501';end if;
  if args ? 'storyId' and not exists(select 1 from public.textos t where t.id=args->>'storyId' and t.nivel=args->>'level' and t.ativo and clube_private.texto_pronto(t.id)) then raise exception 'História indisponível' using errcode='42501';end if;
  if args ? 'storyId' then
   select * into a from public.tentativas where aluno_id=student and jornada_id=j.id and texto_id=args->>'storyId' and status='completed' order by id limit 1;
   if a.id is not null then return clube_private.leitura_tentativa(a);end if;
  end if;
  select * into a from public.tentativas where aluno_id=student and jornada_id=j.id and status='started' and clube_private.texto_autorizado(student,texto_id) order by id limit 1;
  if a.id is not null then
   if args ? 'storyId' and a.texto_id<>args->>'storyId' then raise exception 'Continue a leitura em andamento antes de começar outra' using errcode='22023';end if;
   if not clube_private.texto_autorizado(student,a.texto_id) then raise exception 'Atividade indisponível; seu progresso está salvo' using errcode='42501';end if;
   return clube_private.leitura_tentativa(a);
  end if;
  select * into txt from public.textos t where t.nivel=args->>'level' and t.ativo and clube_private.texto_pronto(t.id) and (not(args ? 'storyId') or t.id=args->>'storyId')
   and not exists(select 1 from public.tentativas done where done.jornada_id=j.id and done.texto_id=t.id and done.status='completed') order by t.id limit 1;
  if txt.id is null then raise exception 'Nenhuma leitura pendente neste nível' using errcode='22023';end if;
  insert into public.tentativas(aluno_id,jornada_id,texto_id,nivel) values(student,j.id,txt.id,txt.nivel) returning * into a;
  update public.jornadas set status='em_andamento',texto_atual_id=txt.id,nivel_atual=txt.nivel where id=j.id;
  return clube_private.leitura_tentativa(a);
 end if;
 select * into a from public.tentativas where id=(args->>'id')::uuid and aluno_id=student for update;
 if a.id is null then raise exception 'Tentativa não encontrada' using errcode='42501';end if;
 if not clube_private.texto_autorizado(student,a.texto_id) then
  if a.status='completed' and op in ('get','finish') then return clube_private.attempt_json(a)||jsonb_build_object('journeyId',a.jornada_id,'level',a.nivel,'stage','resultado','index',a.questao_atual,'activity',jsonb_build_object('id',a.texto_id,'title',(select titulo from public.textos where id=a.texto_id),'content','','age','','level',a.nivel,'questions','[]'::jsonb));end if;
  raise exception 'História indisponível ou nível bloqueado; seu progresso está salvo' using errcode='42501';end if;
 if op='get' then return clube_private.leitura_tentativa(a);end if;
 if op='finish' and a.status='completed' then return clube_private.leitura_tentativa(a);end if;
 if a.status='completed' then raise exception 'Atividade já concluída' using errcode='22023';end if;
 if a.jornada_id is null or a.jornada_id<>j.id then raise exception 'Jornada inválida' using errcode='42501';end if;
 select count(*) into total from public.questoes where texto_id=a.texto_id;
 if op='stage' then
  if args->>'stage' is null or args->>'stage' not in ('leitura','questoes') then raise exception 'Etapa inválida' using errcode='22023';end if;
  update public.tentativas set etapa=args->>'stage' where id=a.id returning * into a;
 elsif op='answer' then
  qid:=(args->>'questionId')::integer;choice:=(args->>'selected')::integer;
  if a.etapa<>'questoes' or choice is null or choice not between 0 and 3 or not exists(select 1 from public.questoes where id=qid and texto_id=a.texto_id) then raise exception 'Resposta inválida' using errcode='22023';end if;
  insert into public.respostas(tentativa_id,questao_id,selecionada) values(a.id,qid,choice) on conflict(tentativa_id,questao_id) do update set selecionada=excluded.selecionada;
  select pos-1 into idx from (select q.id,row_number() over(order by q.id)::integer as pos from public.questoes q where q.texto_id=a.texto_id) ordered
   where not exists(select 1 from public.respostas r where r.tentativa_id=a.id and r.questao_id=ordered.id) order by pos limit 1;
  update public.tentativas set questao_atual=coalesce(idx,greatest(0,total-1)) where id=a.id returning * into a;
 elsif op='finish' then
  if total=0 or (select count(*) from public.respostas where tentativa_id=a.id)<>total then raise exception 'Responda a todas as questões' using errcode='22023';end if;
  if (select count(*) from public.questoes q join clube_private.gabaritos g on g.questao_id=q.id where q.texto_id=a.texto_id)<>total then raise exception 'Atividade sem correção configurada' using errcode='22023';end if;
  select pontos into amount from public.niveis where id=a.nivel;
  update public.respostas r set correta=r.selecionada=g.correta,pontos=case when r.selecionada=g.correta then coalesce(q.valor,amount) else 0 end
   from public.questoes q join clube_private.gabaritos g on g.questao_id=q.id where r.tentativa_id=a.id and r.questao_id=q.id;
  update public.tentativas set status='completed',etapa='resultado',concluida_em=now(),
   acertos=(select count(*) from public.respostas where tentativa_id=a.id and correta),
   pontuacao=(select coalesce(sum(pontos),0) from public.respostas where tentativa_id=a.id),
   percentual=(select 100.0*count(*) filter(where correta)/count(*) from public.respostas where tentativa_id=a.id) where id=a.id returning * into a;
  if clube_private.jornada_completa(student) then
   update public.jornadas set status='concluida',concluida_em=now(),texto_atual_id=null,nivel_atual=null where id=j.id;
  else update public.jornadas set texto_atual_id=null,nivel_atual=null where id=j.id;end if;
 else raise exception 'Operação inválida' using errcode='22023';end if;
 return clube_private.leitura_tentativa(a);
end $$;

-- A mesma autorização protege consultas diretas às histórias e questões.
create function public.clube_texto_permitido(text_id text) returns boolean language sql stable security definer set search_path='' as $$
 select clube_private.administrador() or clube_private.texto_autorizado(clube_private.aluno_atual(),text_id)
$$;
revoke all on function public.clube_texto_permitido(text) from public,anon;
grant execute on function public.clube_texto_permitido(text) to authenticated;
drop policy textos_ativos on public.textos;
drop policy questoes_ativas on public.questoes;
create policy textos_ativos on public.textos for select to authenticated using(public.clube_texto_permitido(id));
create policy questoes_ativas on public.questoes for select to authenticated using(public.clube_texto_permitido(texto_id));
revoke all on function clube_private.texto_pronto(text),clube_private.progresso_niveis(uuid),clube_private.nivel_liberado(uuid,text),clube_private.jornada_completa(uuid),clube_private.texto_autorizado(uuid,text) from public,anon,authenticated;
notify pgrst,'reload schema';
commit;
