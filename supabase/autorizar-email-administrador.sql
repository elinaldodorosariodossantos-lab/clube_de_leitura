-- Execute no SQL Editor do Supabase para autorizar somente esta conta.
-- Mantém a senha existente e não altera a configuração das demais contas.
begin;
do $$
declare usuario uuid;
begin
 select u.id into usuario from auth.users u
 join public.perfis p on p.id=u.id and p.papel='admin'
 where lower(u.email)='escolaedukarxp@gmail.com'
 and not coalesce(u.is_anonymous,false)
 for update of u;
 if usuario is null then
  raise exception 'Conta administrativa não encontrada. Execute configurar-administrador.sql primeiro.';
 end if;
 update auth.users
 set email_confirmed_at=coalesce(email_confirmed_at,now()),updated_at=now()
 where id=usuario;
end $$;
commit;
