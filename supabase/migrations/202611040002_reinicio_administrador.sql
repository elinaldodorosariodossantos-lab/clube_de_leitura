begin;
-- Nova jornada somente por autorizacao administrativa, sem apagar historicos.
create table clube_private.autorizacoes_reinicio_jornada(
 jornada_origem uuid primary key references public.jornadas(id),aluno_id uuid not null references public.alunos(id),
 nova_jornada uuid not null unique references public.jornadas(id),administrador_id uuid not null references auth.users(id),
 autorizado_em timestamptz not null default now());
alter table clube_private.autorizacoes_reinicio_jornada enable row level security;
revoke all on clube_private.autorizacoes_reinicio_jornada from public,anon,authenticated;
alter function public.clube_leitura(text,jsonb) rename to leitura_antes_reinicio_admin;
alter function public.leitura_antes_reinicio_admin(text,jsonb) set schema clube_private;
create function public.clube_leitura(op text,args jsonb default '{}') returns jsonb language plpgsql security definer set search_path='' as $$
begin
 if op='new_journey' then raise exception 'Somente a administracao pode autorizar uma nova jornada.' using errcode='42501';end if;
 return clube_private.leitura_antes_reinicio_admin(op,args);
end $$;
revoke all on function public.clube_leitura(text,jsonb) from public,anon;
grant execute on function public.clube_leitura(text,jsonb) to authenticated;
-- O endpoint legado tambem nao pode criar tentativas independentes para repetir leituras.
alter function public.clube_api(text,jsonb) rename to api_antes_reinicio_admin;
alter function public.api_antes_reinicio_admin(text,jsonb) set schema clube_private;
create function public.clube_api(op text,args jsonb default '{}') returns jsonb language plpgsql security definer set search_path='' as $$
begin
 if op in('start','new_journey') then raise exception 'Inicie as atividades pelo painel do aluno. Uma nova jornada exige autorizacao administrativa.' using errcode='42501';end if;
 return clube_private.api_antes_reinicio_admin(op,args);
end $$;
revoke all on function public.clube_api(text,jsonb) from public,anon;
grant execute on function public.clube_api(text,jsonb) to authenticated;
revoke all on function clube_private.api_antes_reinicio_admin(text,jsonb) from public,anon,authenticated;
alter function public.clube_gestao(text,jsonb) rename to gestao_antes_reinicio_admin;
alter function public.gestao_antes_reinicio_admin(text,jsonb) set schema clube_private;
create function public.clube_gestao(op text,args jsonb default '{}') returns jsonb language plpgsql security definer set search_path='' as $$
declare student public.alunos;source public.jornadas;target uuid;
begin
 if not clube_private.administrador() then raise exception 'Administrador obrigatorio' using errcode='42501';end if;
 if op<>'student_journey_restart' then return clube_private.gestao_antes_reinicio_admin(op,args);end if;
 select * into student from public.alunos where id=(args->>'id')::uuid for update;
 if student.id is null or student.excluido_em is not null or student.situacao<>'ativo' then raise exception 'Aluno ativo nao encontrado.' using errcode='22023';end if;
 select * into source from public.jornadas where id=(args->>'journeyId')::uuid and aluno_id=student.id for update;
 if source.id is null then raise exception 'Jornada do aluno nao encontrada.' using errcode='22023';end if;
 select nova_jornada into target from clube_private.autorizacoes_reinicio_jornada where jornada_origem=source.id and aluno_id=student.id;
 if target is not null then return jsonb_build_object('sourceJourneyId',source.id,'newJourneyId',target,'alreadyAuthorized',true);end if;
 if source.id is distinct from(select id from public.jornadas where aluno_id=student.id order by ciclo desc limit 1) then raise exception 'Atualize os dados: esta nao e a jornada atual do aluno.' using errcode='22023';end if;
 perform clube_private.sincronizar_catalogo(student.id);perform clube_private.sincronizar_catalogo(student.id);
 if not clube_private.jornada_completa(student.id) or exists(select 1 from public.tentativas t where t.jornada_id=source.id and t.status='started' and clube_private.texto_autorizado(student.id,t.texto_id)) then
 raise exception 'A jornada atual deve estar concluida antes de autorizar outra.' using errcode='22023';end if;
 update public.jornadas set status='concluida',concluida_em=coalesce(concluida_em,now()),texto_atual_id=null,nivel_atual=null where id=source.id;
 insert into public.jornadas(aluno_id,ciclo) values(student.id,source.ciclo+1) returning id into target;
 insert into clube_private.autorizacoes_reinicio_jornada(jornada_origem,aluno_id,nova_jornada,administrador_id) values(source.id,student.id,target,auth.uid());
 return jsonb_build_object('sourceJourneyId',source.id,'newJourneyId',target,'alreadyAuthorized',false);
end $$;
revoke all on function public.clube_gestao(text,jsonb) from public,anon;
grant execute on function public.clube_gestao(text,jsonb) to authenticated;
revoke all on function clube_private.leitura_antes_reinicio_admin(text,jsonb),clube_private.gestao_antes_reinicio_admin(text,jsonb) from public,anon,authenticated;
notify pgrst,'reload schema';
commit;
