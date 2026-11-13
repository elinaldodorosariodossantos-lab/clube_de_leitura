begin;
-- Reutiliza atribuicoes, snapshots e resultados. Nao altera pontos ou historias.
create function clube_private.agenda_leitura(student uuid) returns jsonb
language plpgsql security definer set search_path='' as $$
declare selected jsonb;e public.eventos_leitura;pid uuid;level_id text;amount integer;done integer;allowed boolean;
 levels jsonb:='[]';items jsonb;next_event public.eventos_leitura;phase text;
begin
 select x into selected from jsonb_array_elements(public.clube_eventos('mine')) x
 where (x->>'startsAt')::timestamptz<=now() and now()<(x->>'endsAt')::timestamptz
 order by ((x->>'completed')::integer<(x->>'total')::integer) desc,(x->>'startsAt')::timestamptz,x->>'id' limit 1;
 if selected is not null then
  select * into e from public.eventos_leitura where id=(selected->>'id')::uuid;
  select id into pid from public.evento_alunos where evento_id=e.id and aluno_id=student;
  foreach level_id in array array['facil','medio','dificil'] loop
   select coalesce(jsonb_agg(x order by (x->>'order')::integer),'[]') into items
    from jsonb_array_elements(coalesce(selected->'assignedStories','[]')) x where x->>'level'=level_id;
   if pid is not null then
    select count(*),count(*) filter(where clube_private.resultado_completo(l.tentativa_id)) into amount,done
     from public.evento_leituras l join clube_private.evento_conteudos s on s.leitura_id=l.id
     where l.participante_id=pid and s.atividade->>'level'=level_id;
    allowed:=case when e.distribuicao_automatica or exists(select 1 from public.evento_alunos p where p.id=pid and jsonb_array_length(p.configuracao)>0)
     then clube_private.evento_nivel_liberado(pid,level_id) else clube_private.nivel_liberado(student,level_id) end;
    allowed:=allowed and not exists(select 1 from public.evento_leituras l join clube_private.evento_conteudos s on s.leitura_id=l.id
     where l.participante_id=pid and array_position(array['facil','medio','dificil'],s.atividade->>'level')<array_position(array['facil','medio','dificil'],level_id)
      and not clube_private.resultado_completo(l.tentativa_id));
   else
    select coalesce(sum((x->>'quantity')::integer),0) into amount from jsonb_array_elements(selected->'assignedLevels') x where x->>'level'=level_id;
    done:=0;
    allowed:=not exists(select 1 from jsonb_array_elements(selected->'assignedLevels') x
     where array_position(array['facil','medio','dificil'],x->>'level')<array_position(array['facil','medio','dificil'],level_id))
     and (level_id='facil' or clube_private.nivel_liberado(student,level_id));
   end if;
   levels:=levels||jsonb_build_array(jsonb_build_object('id',level_id,'available',amount,'completed',done,'required',amount,'requiredCompleted',done,
    'complete',amount>0 and done=amount,'unlocked',amount>0 and allowed,'eventId',e.id,'stories',items));
  end loop;
  return jsonb_build_object('status','active','eventId',e.id,'startsAt',e.inicio,'endsAt',e.fim,'serverNow',now(),'levels',levels);
 end if;
 -- Fora do horario divulga somente a agenda, nunca titulos ou conteudo.
 select x.* into next_event from public.eventos_leitura x
 where x.ativo and not x.arquivado and clube_private.evento_escola_permitida(x.id,student)
 and ((x.distribuicao_automatica and exists(select 1 from jsonb_array_elements(x.configuracoes) c where (c->>'age')::integer=clube_private.idade_aluno(student)))
  or exists(select 1 from public.evento_alunos p where p.evento_id=x.id and p.aluno_id=student))
 order by (x.inicio>now()) desc,case when x.inicio>now() then x.inicio end, x.fim desc,x.id limit 1;
 phase:=case when next_event.id is null then 'unavailable' when now()<next_event.inicio then 'not_started' when now()>=next_event.fim then 'ended' else 'unavailable' end;
 foreach level_id in array array['facil','medio','dificil'] loop
  levels:=levels||jsonb_build_array(jsonb_build_object('id',level_id,'available',0,'completed',0,'required',0,'requiredCompleted',0,'complete',false,'unlocked',false,'stories','[]'::jsonb));
 end loop;
 return jsonb_build_object('status',phase,'startsAt',next_event.inicio,'endsAt',next_event.fim,'serverNow',now(),'levels',levels);
end $$;
revoke all on function clube_private.agenda_leitura(uuid) from public,anon,authenticated;

alter function public.clube_leitura(text,jsonb) rename to leitura_antes_agenda_eventos;
alter function public.leitura_antes_agenda_eventos(text,jsonb) set schema clube_private;
create function public.clube_leitura(op text,args jsonb default '{}') returns jsonb
language plpgsql security definer set search_path='' as $$
declare student uuid;agenda jsonb;result jsonb;entry jsonb;a public.tentativas;level_info jsonb;event_id uuid;
begin
 student:=clube_private.aluno_atual();if student is null then raise exception 'Aluno nao identificado' using errcode='42501';end if;
 if op in('state','enter','start','stories') then
  agenda:=clube_private.agenda_leitura(student);
  if op='state' then
   result:=clube_private.leitura_antes_agenda_eventos(op,args);
   -- A retomada segue apenas o evento aberto, sem reabrir a jornada comum.
   select t.* into a from public.tentativas t join public.evento_alunos p on p.id=t.evento_participante_id
    where t.aluno_id=student and t.status='started' and p.evento_id=(agenda->>'eventId')::uuid
    and clube_private.evento_disponivel(p.evento_id,student) order by t.id limit 1;
   return result||jsonb_build_object('eventSchedule',agenda-'levels','levels',agenda->'levels',
    'active',case when a.id is not null then clube_private.leitura_tentativa(a) else null end);
  end if;
  if agenda->>'status'<>'active' then
   if op='stories' then return '[]'::jsonb;end if;
   raise exception 'As historias ficam disponiveis somente durante o evento.' using errcode='22023';
  end if;
  select x into level_info from jsonb_array_elements(agenda->'levels') x where x->>'id'=args->>'level';
  if level_info is null then raise exception 'Nivel invalido' using errcode='22023';end if;
  if op='stories' then return level_info->'stories';end if;
  if not (level_info->>'unlocked')::boolean then raise exception 'Conclua o nivel anterior ou aguarde historias neste nivel.' using errcode='22023';end if;
  if (level_info->>'complete')::boolean then
   if op='start' then raise exception 'Este nivel ja foi concluido.' using errcode='22023';end if;
   return jsonb_build_object('attempt',null,'empty',true,'levelComplete',true,'journeyComplete',false);
  end if;
  entry:=public.clube_eventos('enter',jsonb_build_object('id',agenda->>'eventId'));
  if entry->'attempt'->>'level' is distinct from args->>'level' then raise exception 'Siga a sequencia das historias do evento.' using errcode='22023';end if;
  if args?'storyId' and args->>'storyId' is distinct from entry->'attempt'->'activity'->>'id' then raise exception 'Siga a sequencia das historias do evento.' using errcode='22023';end if;
  if op='start' then return entry->'attempt';end if;
  return entry||jsonb_build_object('empty',false,'levelComplete',false,'journeyComplete',false);
 end if;
 if op in('get','page','stage','answer','finish') then
  select * into a from public.tentativas where id=(args->>'id')::uuid and aluno_id=student;
  if a.id is null then raise exception 'Tentativa nao encontrada' using errcode='42501';end if;
  if a.status='completed' and op in('get','finish') then
   select evento_id into event_id from public.evento_alunos where id=a.evento_participante_id and aluno_id=student;
   return clube_private.leitura_tentativa(a)||case when event_id is not null then jsonb_build_object('eventId',event_id) else '{}'::jsonb end;
  end if;
  if a.status<>'completed' then
   select evento_id into event_id from public.evento_alunos where id=a.evento_participante_id and aluno_id=student;
   if event_id is null or not clube_private.evento_disponivel(event_id,student) then
    raise exception 'O evento nao esta aberto. Seu progresso esta salvo.' using errcode='22023';
   end if;
  end if;
 end if;
 return clube_private.leitura_antes_agenda_eventos(op,args);
end $$;
revoke all on function clube_private.leitura_antes_agenda_eventos(text,jsonb) from public,anon,authenticated;
revoke all on function public.clube_leitura(text,jsonb) from public,anon;
grant execute on function public.clube_leitura(text,jsonb) to authenticated;

-- As policies existentes mantem o OID e passam a restringir o catalogo ao evento.
create or replace function public.clube_texto_permitido(text_id text) returns boolean
language sql stable security definer set search_path='' as $$
 select clube_private.administrador() or exists(
  select 1 from public.evento_alunos p join public.evento_leituras l on l.participante_id=p.id
  join clube_private.evento_conteudos s on s.leitura_id=l.id
  where p.aluno_id=clube_private.aluno_atual() and l.texto_id=text_id
   and clube_private.evento_disponivel(p.evento_id,p.aluno_id)
   and (jsonb_array_length(p.configuracao)=0 or clube_private.evento_nivel_liberado(p.id,s.atividade->>'level')))
$$;
alter function public.clube_api(text,jsonb) rename to api_antes_agenda_eventos;
alter function public.api_antes_agenda_eventos(text,jsonb) set schema clube_private;
create function public.clube_api(op text,args jsonb default '{}') returns jsonb
language plpgsql security definer set search_path='' as $$
begin
 if op in('get','answer','finish') then return public.clube_leitura(op,args);end if;
 if op in('activity','start') then raise exception 'Escolha um nivel durante o evento para iniciar a leitura.' using errcode='22023';end if;
 return clube_private.api_antes_agenda_eventos(op,args);
end $$;
revoke all on function clube_private.api_antes_agenda_eventos(text,jsonb) from public,anon,authenticated;
revoke all on function public.clube_api(text,jsonb) from public,anon;
grant execute on function public.clube_api(text,jsonb) to authenticated;
notify pgrst,'reload schema';
commit;
