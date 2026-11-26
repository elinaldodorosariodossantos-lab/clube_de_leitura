begin;
alter function public.clube_gestao(text,jsonb) rename to gestao_antes_escolas_selecionaveis;
alter function public.gestao_antes_escolas_selecionaveis(text,jsonb) set schema clube_private;
revoke all on function clube_private.gestao_antes_escolas_selecionaveis(text,jsonb) from public,anon,authenticated;
create function public.clube_gestao(op text,args jsonb default '{}') returns jsonb
language plpgsql security definer set search_path='' as $$
declare result jsonb;schools jsonb;
begin
 if not clube_private.administrador() then raise exception 'Administrador obrigatorio' using errcode='42501';end if;
 if op in('schools','students') then
  select coalesce(jsonb_agg(jsonb_build_object('id',s.id,'name',s.nome) order by clube_private.nome_ordenacao(s.nome),s.id),'[]') into schools
  from public.escolas s where s.excluido_em is null;
  if op='schools' then return schools;end if;
  result:=clube_private.gestao_antes_escolas_selecionaveis(op,args);
  return jsonb_set(result,'{schools}',schools);
 end if;
 if op='student_save' and exists(select 1 from public.escolas where id=(args->>'schoolId')::uuid and excluido_em is not null) then
  raise exception 'Esta escola foi excluida. Selecione uma escola cadastrada.' using errcode='22023';
 end if;
 result:=clube_private.gestao_antes_escolas_selecionaveis(op,args);
 if op='school_save' and exists(select 1 from public.escolas where id=(result->>'id')::uuid and excluido_em is not null) then
  raise exception 'Esta escola foi excluida. Cadastre outra escola ou revise o cadastro no painel Escolas.' using errcode='22023';
 end if;
 return result;
end $$;
revoke all on function public.clube_gestao(text,jsonb) from public,anon;
grant execute on function public.clube_gestao(text,jsonb) to authenticated;
notify pgrst,'reload schema';
commit;
