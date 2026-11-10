-- Execute uma vez no SQL Editor do projeto Supabase.
-- A conta deve existir em Authentication > Users antes desta operação.
-- Não altera senha, alunos ou resultados existentes.
begin;
do $$
declare usuario uuid;
begin
 select id into usuario from auth.users
 where lower(email)='escolaedukarxp@gmail.com' and not coalesce(is_anonymous,false);
 if usuario is null then
  raise exception 'Crie primeiro a conta escolaedukarxp@gmail.com em Authentication > Users.';
 end if;
 insert into public.perfis(id,nome,papel)
 values(usuario,'Escola Edukar XP','admin')
 on conflict(id) do update set papel='admin';
end $$;
commit;
