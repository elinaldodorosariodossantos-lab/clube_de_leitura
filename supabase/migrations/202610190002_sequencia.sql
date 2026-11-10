begin;
-- Aplicar depois de 202610190001_progressao.sql. Nenhum registro é apagado.
alter table public.textos add column ordem integer not null default 0 check(ordem>=0);
create index textos_sequencia_idx on public.textos(nivel,ordem,id) where ativo and obrigatorio;

-- Conserva correção, retomada e políticas da versão anterior como implementação privada.
alter function public.clube_leitura(text,jsonb) set schema clube_private;
revoke all on function clube_private.clube_leitura(text,jsonb) from public,anon,authenticated;

create function public.clube_leitura(op text,args jsonb default '{}') returns jsonb
language plpgsql security definer set search_path='' as $$
declare student uuid;cycle_id uuid;cycle_number integer;a public.tentativas;story text;level_id text;complete boolean;finished boolean;
begin
 student:=clube_private.aluno_atual();
 if student is null then raise exception 'Aluno não identificado' using errcode='42501';end if;
 if op='state' then return clube_private.leitura_estado(student)||jsonb_build_object('sequenceReady',true);end if;
 if op='new_journey' then
  perform 1 from public.alunos where id=student for update;
  select id,ciclo into cycle_id,cycle_number from public.jornadas where aluno_id=student order by ciclo desc limit 1 for update;
  if cycle_id is null or not clube_private.jornada_completa(student) or exists(select 1 from public.tentativas t where t.jornada_id=cycle_id and t.status='started' and clube_private.texto_autorizado(student,t.texto_id)) then
   raise exception 'Conclua a jornada atual antes de iniciar outra' using errcode='22023';end if;
  update public.jornadas set status='concluida',concluida_em=coalesce(concluida_em,now()),texto_atual_id=null,nivel_atual=null where id=cycle_id;
  insert into public.jornadas(aluno_id,ciclo) values(student,cycle_number+1);
  return clube_private.leitura_estado(student)||jsonb_build_object('sequenceReady',true);
 end if;
 if op not in ('enter','start') then return clube_private.clube_leitura(op,args);end if;
 level_id:=args->>'level';
 if level_id is null or level_id not in ('facil','medio','dificil') then raise exception 'Nível inválido' using errcode='22023';end if;
 perform 1 from public.alunos where id=student for update;
 select id into cycle_id from public.jornadas where aluno_id=student order by ciclo desc limit 1 for update;
 if cycle_id is null then raise exception 'Jornada indisponível' using errcode='22023';end if;
 if not clube_private.nivel_liberado(student,level_id) then raise exception 'Conclua as histórias obrigatórias do nível anterior' using errcode='42501';end if;
 -- Uma mudança na posição nunca troca uma leitura que já está em andamento.
 select * into a from public.tentativas where aluno_id=student and jornada_id=cycle_id
  and status='started' and clube_private.texto_autorizado(student,texto_id)
  order by (nivel=level_id) desc,id limit 1;
 if a.id is null then
  select t.id into story from public.textos t where t.nivel=level_id and t.ativo and t.obrigatorio and clube_private.texto_pronto(t.id)
   and not exists(select 1 from clube_private.admin_resultados_validos done where done.jornada_id=cycle_id and done.texto_id=t.id and done.aluno_id=student)
   order by t.ordem,t.id limit 1;
 else story:=a.texto_id;end if;
 if args ? 'storyId' and (args->>'storyId' is distinct from story) then raise exception 'Siga a sequência de leitura do nível' using errcode='42501';end if;
 if story is not null then
  if a.id is null then
   -- O aluno e a jornada continuam bloqueados durante a criação da tentativa.
   insert into public.tentativas(aluno_id,jornada_id,texto_id,nivel)
    select student,cycle_id,t.id,t.nivel from public.textos t where t.id=story returning * into a;
   update public.jornadas set status='em_andamento',texto_atual_id=a.texto_id,nivel_atual=a.nivel where id=cycle_id;
  end if;
  if op='start' then return clube_private.leitura_tentativa(a);end if;
  return jsonb_build_object('attempt',clube_private.leitura_tentativa(a),'empty',false,'levelComplete',false,'journeyComplete',false);
 end if;
 select p.complete into complete from clube_private.progresso_niveis(student) p where p.id=level_id;
 finished:=clube_private.jornada_completa(student);
 if finished and not exists(select 1 from public.tentativas where jornada_id=cycle_id and status='started') then
  update public.jornadas set status='concluida',concluida_em=coalesce(concluida_em,now()),texto_atual_id=null,nivel_atual=null where id=cycle_id;
 end if;
 if op='start' then raise exception 'Novas histórias estarão disponíveis em breve. Nenhuma leitura obrigatória pendente neste nível.' using errcode='22023';end if;
 return jsonb_build_object('attempt',null,'empty',true,'levelComplete',coalesce(complete,false),'journeyComplete',finished);
end $$;
revoke all on function public.clube_leitura(text,jsonb) from public,anon;
grant execute on function public.clube_leitura(text,jsonb) to authenticated;
notify pgrst,'reload schema';
commit;
