begin;
create function clube_private.nome_ordenacao(nome text) returns text language sql immutable set search_path='' as $$
 select translate(lower(trim(coalesce(nome,''))),'áàâãäéèêëíìîïóòôõöúùûüçñ','aaaaaeeeeiiiiooooouuuucn')
$$;
revoke all on function clube_private.nome_ordenacao(text) from public,anon,authenticated;
-- Ordena antes de paginar, para manter A–Z entre todas as páginas e filtros.
do $alphabetical$
declare definition text;updated text;old_order text;
begin
 definition:=pg_get_functiondef('clube_private.clube_gestao(text,jsonb)'::regprocedure);
 old_order:='case when args->>''sort''=''points_desc'' then points end desc,case when args->>''sort''=''points_asc'' then points end asc,case when args->>''sort''=''name_desc'' then name end desc,name,id';
 updated:=replace(definition,old_order,'clube_private.nome_ordenacao(name) collate "C",lower(name) collate "C",id');
 if updated=definition then raise exception 'Aplique primeiro as migrações de gestão de alunos.';end if;
 execute updated;
end $alphabetical$;
notify pgrst,'reload schema';
commit;
