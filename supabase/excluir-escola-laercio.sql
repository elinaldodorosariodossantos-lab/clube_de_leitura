-- Execute no SQL Editor do Supabase para retirar apenas o cadastro "laercio".
-- Alunos, turmas e resultados vinculados permanecem preservados.
begin;
update public.escolas
set excluido_em=coalesce(excluido_em,now())
where lower(trim(nome))='laercio'
returning id,nome,excluido_em;
commit;
