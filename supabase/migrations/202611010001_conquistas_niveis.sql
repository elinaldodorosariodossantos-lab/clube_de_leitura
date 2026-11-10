begin;
-- Conquistas por jornada ou seleção individual de evento. Nenhuma resposta é alterada.
create table clube_private.conquistas_niveis(
 id uuid primary key default gen_random_uuid(),aluno_id uuid not null references public.alunos(id),
 contexto_id uuid not null,evento boolean not null,nivel text not null references public.niveis(id),
 pontos bigint not null check(pontos>=0),proximo_nivel text references public.niveis(id),
 concluida_em timestamptz not null default now(),apresentada_em timestamptz,
 unique(aluno_id,contexto_id,evento,nivel));
alter table clube_private.conquistas_niveis enable row level security;
revoke all on clube_private.conquistas_niveis from public,anon,authenticated;

-- Usa a correção existente e exige uma resposta corrigida para cada pergunta do snapshot.
create function clube_private.resultado_completo(attempt_id uuid) returns boolean language sql stable security definer set search_path='' as $$
 select exists(select 1 from clube_private.admin_resultados_validos v
 join clube_private.conteudos_tentativas s on s.tentativa_id=v.id where v.id=attempt_id
 and jsonb_array_length(s.atividade->'questions')>0
 and not exists(select 1 from jsonb_array_elements(s.atividade->'questions') q where not exists(
 select 1 from public.respostas r where r.tentativa_id=v.id and r.questao_id=(q->>'id')::integer and r.correta is not null and r.pontos is not null)))
$$;

-- A sequência comum atribui as histórias obrigatórias compatíveis com o nascimento.
-- Leituras já iniciadas também impedem a conquista enquanto estiverem pendentes.
create or replace function clube_private.progresso_niveis(student uuid) returns table(id text,available bigint,completed bigint,required bigint,required_completed bigint,complete boolean) language sql stable security definer set search_path='' as $$
 with latest as(select j.id from public.jornadas j where aluno_id=student order by ciclo desc limit 1),counts as(
 select n.id,count(t.id) as available,
 count(t.id) filter(where exists(select 1 from public.tentativas a where a.aluno_id=student and a.jornada_id=(select id from latest) and a.texto_id=t.id and clube_private.resultado_completo(a.id))) as completed,
 count(t.id) filter(where t.obrigatorio) as required,
 count(t.id) filter(where t.obrigatorio and exists(select 1 from public.tentativas a where a.aluno_id=student and a.jornada_id=(select id from latest) and a.texto_id=t.id and clube_private.resultado_completo(a.id))) as required_completed
 from public.niveis n left join public.textos t on t.nivel=n.id and t.ativo and t.excluido_em is null and clube_private.historia_idade(student,t.faixa_etaria) group by n.id)
 select c.*,c.required>0 and c.required=c.required_completed and not exists(
 select 1 from public.tentativas a join clube_private.conteudos_tentativas s on s.tentativa_id=a.id
 where a.aluno_id=student and a.jornada_id=(select id from latest) and a.nivel=c.id
 and clube_private.historia_idade(student,s.atividade->>'age') and not clube_private.resultado_completo(a.id)) from counts c
$$;

-- Uma jornada pode terminar no último nível que tem atribuições para esta idade.
-- Um nível isolado após uma lacuna continua bloqueado pela regra pedagógica.
create or replace function clube_private.jornada_completa(student uuid) returns boolean language sql stable security definer set search_path='' as $$
 with p as(select * from clube_private.progresso_niveis(student))
 select coalesce((select complete from p where id='facil'),false)
 and not exists(select 1 from p where required>0 and not complete and
 (id='facil' or (id='medio' and exists(select 1 from p where id='facil' and required>0)) or
 (id='dificil' and (select count(*)=2 from p where id in('facil','medio') and required>0))))
$$;

create function clube_private.conquista_proximo(student uuid,context_id uuid,is_event boolean,level_id text) returns text language sql stable security definer set search_path='' as $$
 with candidate as(select id,ord from unnest(array['facil','medio','dificil']) with ordinality as levels(id,ord)
 where ord>array_position(array['facil','medio','dificil'],level_id))
 select c.id from candidate c where clube_private.nivel_liberado(student,c.id) and
 case when is_event then exists(select 1 from public.evento_alunos p join public.evento_leituras l on l.participante_id=p.id
 join clube_private.evento_conteudos s on s.leitura_id=l.id where p.id=context_id and p.aluno_id=student
 and clube_private.evento_disponivel(p.evento_id,student) and s.atividade->>'level'=c.id
 and clube_private.historia_idade(student,s.atividade->>'age') and not clube_private.resultado_completo(l.tentativa_id))
 else context_id=(select id from public.jornadas where aluno_id=student order by ciclo desc limit 1)
 and exists(select 1 from clube_private.progresso_niveis(student) p where p.id=c.id and p.required>0 and not p.complete) end
 order by c.ord limit 1
$$;

create function clube_private.conquista_registrar(a public.tentativas) returns uuid language plpgsql security definer set search_path='' as $$
declare context_id uuid;is_event boolean;amount bigint;done bigint;score bigint;achievement_id uuid;
begin
 if not clube_private.resultado_completo(a.id) then return null;end if;
 is_event:=a.evento_participante_id is not null;context_id:=coalesce(a.evento_participante_id,a.jornada_id);
 if context_id is null then return null;end if;
 if is_event then
  select count(*),count(*) filter(where clube_private.resultado_completo(l.tentativa_id)),coalesce(sum(v.pontuacao),0)
  into amount,done,score from public.evento_leituras l join clube_private.evento_conteudos s on s.leitura_id=l.id
  left join clube_private.admin_resultados_validos v on v.id=l.tentativa_id
  where l.participante_id=context_id and s.atividade->>'level'=a.nivel;
  if amount=0 or done<>amount then return null;end if;
 else
  if context_id is distinct from (select id from public.jornadas where aluno_id=a.aluno_id order by ciclo desc limit 1)
   or not coalesce((select complete from clube_private.progresso_niveis(a.aluno_id) where id=a.nivel),false) then return null;end if;
  select coalesce(sum(v.pontuacao),0) into score from clube_private.admin_resultados_validos v
  where v.aluno_id=a.aluno_id and v.jornada_id=context_id and v.nivel=a.nivel and clube_private.resultado_completo(v.id);
 end if;
 insert into clube_private.conquistas_niveis(aluno_id,contexto_id,evento,nivel,pontos,proximo_nivel)
 values(a.aluno_id,context_id,is_event,a.nivel,score,clube_private.conquista_proximo(a.aluno_id,context_id,is_event,a.nivel))
 on conflict(aluno_id,contexto_id,evento,nivel) do nothing;
 select id into achievement_id from clube_private.conquistas_niveis where aluno_id=a.aluno_id and contexto_id=context_id and evento=is_event and nivel=a.nivel and apresentada_em is null;
 return achievement_id;
end $$;

-- Também registra conclusões feitas pelo endpoint legado, na mesma transação.
create function clube_private.registrar_conquista_conclusao() returns trigger language plpgsql security definer set search_path='' as $$
begin
 perform clube_private.conquista_registrar(new);
 return new;
end $$;
create trigger registrar_conquista_conclusao after update of status on public.tentativas
 for each row when(new.status='completed' and old.status is distinct from new.status)
 execute function clube_private.registrar_conquista_conclusao();
revoke all on function clube_private.registrar_conquista_conclusao() from public,anon,authenticated;

create function clube_private.conquista_json(c clube_private.conquistas_niveis) returns jsonb language sql stable security definer set search_path='' as $$
 select jsonb_build_object('id',c.id,'level',c.nivel,'points',c.pontos,'percentage',100,
 'nextLevel',clube_private.conquista_proximo(c.aluno_id,c.contexto_id,c.evento,c.nivel),
 'eventId',case when c.evento then (select evento_id from public.evento_alunos where id=c.contexto_id) end)
$$;

alter function public.clube_leitura(text,jsonb) rename to leitura_antes_conquistas;
alter function public.leitura_antes_conquistas(text,jsonb) set schema clube_private;
revoke all on function clube_private.leitura_antes_conquistas(text,jsonb) from public,anon,authenticated;
create function public.clube_leitura(op text,args jsonb default '{}') returns jsonb language plpgsql security definer set search_path='' as $$
declare student uuid;result jsonb;a public.tentativas;c clube_private.conquistas_niveis;achievement_id uuid;
begin
 student:=clube_private.aluno_atual();if student is null then raise exception 'Aluno não identificado' using errcode='42501';end if;
 if op in ('achievement_claim','achievement_continue') then
  select * into c from clube_private.conquistas_niveis where id=(args->>'id')::uuid and aluno_id=student for update;
  if c.id is null then raise exception 'Conquista não encontrada' using errcode='42501';end if;
  if op='achievement_claim' then
   if c.apresentada_em is not null then return jsonb_build_object('achievement',null);end if;
   update clube_private.conquistas_niveis set apresentada_em=now() where id=c.id;
  end if;
  return jsonb_build_object('achievement',clube_private.conquista_json(c));
 end if;
 -- A autorização, correção e ordem dos locks continuam nas funções existentes.
 result:=clube_private.leitura_antes_conquistas(op,args);
 if op='finish' then
  select * into a from public.tentativas where id=(args->>'id')::uuid and aluno_id=student;
  achievement_id:=clube_private.conquista_registrar(a);
  return result||jsonb_build_object('achievementId',achievement_id);
 elsif op='state' then
  select id into achievement_id from clube_private.conquistas_niveis where aluno_id=student and apresentada_em is null
  and (evento or contexto_id=(result->'journey'->>'id')::uuid) order by concluida_em,id limit 1;
  return result||jsonb_build_object('achievementId',achievement_id);
 end if;
 return result;
end $$;
revoke all on function public.clube_leitura(text,jsonb) from public,anon;
grant execute on function public.clube_leitura(text,jsonb) to authenticated;
revoke all on function clube_private.resultado_completo(uuid),clube_private.conquista_proximo(uuid,uuid,boolean,text),clube_private.conquista_registrar(public.tentativas),clube_private.conquista_json(clube_private.conquistas_niveis) from public,anon,authenticated;
notify pgrst,'reload schema';
commit;
