begin;
-- Exclusão da lista e do acesso; resultados permanecem disponíveis no histórico.
alter table public.alunos add column excluido_em timestamptz;
do $filter$
declare definition text;updated text;
begin
 definition:=pg_get_functiondef('clube_private.clube_gestao(text,jsonb)'::regprocedure);
 updated:=replace(definition,'from clube_private.admin_alunos a where (coalesce(args->>''search''',
 'from clube_private.admin_alunos a where not exists(select 1 from public.alunos deleted where deleted.id=a.id and deleted.excluido_em is not null) and (coalesce(args->>''search''');
 if updated=definition then raise exception 'Aplique primeiro a migração de gestão de alunos.';end if;
 execute updated;
end $filter$;
alter function public.clube_gestao(text,jsonb) rename to gestao_antes_exclusao;
alter function public.gestao_antes_exclusao(text,jsonb) set schema clube_private;
revoke all on function clube_private.gestao_antes_exclusao(text,jsonb) from public,anon,authenticated;
create function public.clube_gestao(op text,args jsonb default '{}') returns jsonb language plpgsql security definer set search_path='' as $$
declare student public.alunos;
begin
 if not clube_private.administrador() then raise exception 'Administrador obrigatório' using errcode='42501';end if;
 if op in ('student_delete','student_save','student_status','credentials','credentials_save') and coalesce(args->>'id','')<>'' then
  select * into student from public.alunos where id=(args->>'id')::uuid for update;
  if student.id is null then raise exception 'Aluno não encontrado' using errcode='P0002';end if;
  if op='student_delete' then
   update public.alunos set excluido_em=coalesce(excluido_em,now()),situacao='inativo',atualizado_em=now() where id=student.id;
   delete from clube_private.sessoes where aluno_id=student.id;
   return jsonb_build_object('deleted',true,'historyPreserved',true);
  end if;
  if student.excluido_em is not null then raise exception 'Aluno excluído da lista. Histórico preservado.' using errcode='22023';end if;
 end if;
 return clube_private.gestao_antes_exclusao(op,args);
end $$;
revoke all on function public.clube_gestao(text,jsonb) from public,anon;
grant execute on function public.clube_gestao(text,jsonb) to authenticated;
notify pgrst,'reload schema';
commit;
