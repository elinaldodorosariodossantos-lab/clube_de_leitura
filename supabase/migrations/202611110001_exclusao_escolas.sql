begin;
-- Exclusão lógica: mantém vínculos e resultados dos alunos.
alter table public.escolas add column excluido_em timestamptz;
do $listar$ declare definition text;updated text;begin
 definition:=pg_get_functiondef('public.clube_escolas(text,jsonb)'::regprocedure);
 updated:=replace(definition,'from public.escolas s where (search=', 'from public.escolas s where s.excluido_em is null and (search=');
 updated:=replace(updated,'from public.escolas where municipio is not null','from public.escolas where excluido_em is null and municipio is not null');
 if updated=definition then raise exception 'Aplique primeiro a migração do módulo Escolas.';end if;
 execute updated;
end $listar$;
alter function public.clube_escolas(text,jsonb) rename to escolas_antes_exclusao;
alter function public.escolas_antes_exclusao(text,jsonb) set schema clube_private;
revoke all on function clube_private.escolas_antes_exclusao(text,jsonb) from public,anon,authenticated;
create function public.clube_escolas(op text,args jsonb default '{}') returns jsonb language plpgsql security definer set search_path='' as $$
declare sid uuid;
begin
 if not clube_private.administrador() then raise exception 'Administrador obrigatório' using errcode='42501';end if;
 if op='school_delete' then
  sid:=(args->>'schoolId')::uuid;
  update public.escolas set excluido_em=coalesce(excluido_em,now()) where id=sid;
  if not found then raise exception 'Escola não encontrada.' using errcode='P0002';end if;
  return jsonb_build_object('deleted',true,'historyPreserved',true);
 end if;
 if op='school_update' and exists(select 1 from public.escolas where id=(args->>'schoolId')::uuid and excluido_em is not null) then
  raise exception 'Escola excluída da lista. Histórico preservado.' using errcode='22023';
 end if;
 return clube_private.escolas_antes_exclusao(op,args);
end $$;
revoke all on function public.clube_escolas(text,jsonb) from public,anon;
grant execute on function public.clube_escolas(text,jsonb) to authenticated;
notify pgrst,'reload schema';
commit;
