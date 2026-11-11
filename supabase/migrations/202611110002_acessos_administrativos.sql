begin;
create function public.clube_acessos(op text,args jsonb default '{}') returns jsonb language plpgsql security definer set search_path='' as $$
declare target uuid;
begin
 if not clube_private.administrador() then raise exception 'Administrador obrigatório' using errcode='42501';end if;
 if op='list' then
  return coalesce((select jsonb_agg(jsonb_build_object('id',p.id,'name',p.nome,'email',u.email,'createdAt',p.criado_em) order by p.nome,p.id)
   from public.perfis p join auth.users u on u.id=p.id where p.papel='admin'),'[]');
 elsif op='save' then
  target:=(args->>'id')::uuid;
  if length(trim(coalesce(args->>'name',''))) not between 3 and 120 or not exists(select 1 from auth.users where id=target and not coalesce(is_anonymous,false))
   or exists(select 1 from public.perfis where id=target and papel<>'admin') then raise exception 'Perfil administrativo inválido' using errcode='22023';end if;
  insert into public.perfis(id,nome,papel) values(target,trim(args->>'name'),'admin') on conflict(id) do update set nome=excluded.nome;
  return jsonb_build_object('ok',true);
 end if;
 raise exception 'Operação inválida' using errcode='22023';
end $$;
revoke all on function public.clube_acessos(text,jsonb) from public,anon;
grant execute on function public.clube_acessos(text,jsonb) to authenticated;
notify pgrst,'reload schema';
commit;
