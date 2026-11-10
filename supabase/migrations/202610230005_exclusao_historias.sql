begin;
-- Retira histórias do cadastro sem apagar referências, eventos e resultados.
alter table public.textos add column excluido_em timestamptz;
alter function public.clube_gestao(text,jsonb) rename to gestao_antes_exclusao_historias;
alter function public.gestao_antes_exclusao_historias(text,jsonb) set schema clube_private;
revoke all on function clube_private.gestao_antes_exclusao_historias(text,jsonb) from public,anon,authenticated;
create function public.clube_gestao(op text,args jsonb default '{}') returns jsonb language plpgsql security definer set search_path='' as $$
declare story public.textos;result jsonb;
begin
 if not clube_private.administrador() then raise exception 'Administrador obrigatório' using errcode='42501';end if;
 if op='stories' then
  result:=clube_private.gestao_antes_exclusao_historias(op,args);
  return coalesce((select jsonb_agg(x order by ord) from jsonb_array_elements(result) with ordinality as rows(x,ord)
   join public.textos t on t.id=x->>'id' where t.excluido_em is null),'[]');
 end if;
 if op in ('story_delete','story_save','story_status','story') and coalesce(args->>'id','')<>'' then
  select * into story from public.textos where id=args->>'id' for update;
  if op='story_delete' then
   if story.id is null then raise exception 'História não encontrada' using errcode='P0002';end if;
   update public.textos set ativo=false,excluido_em=coalesce(excluido_em,now()) where id=story.id;
   return jsonb_build_object('deleted',true,'historyPreserved',true);
  end if;
  if story.excluido_em is not null then
   if op='story' then return null;end if;
   raise exception 'História excluída da lista. Histórico preservado.' using errcode='22023';
  end if;
 end if;
 return clube_private.gestao_antes_exclusao_historias(op,args);
end $$;
revoke all on function public.clube_gestao(text,jsonb) from public,anon;
grant execute on function public.clube_gestao(text,jsonb) to authenticated;
notify pgrst,'reload schema';
commit;
