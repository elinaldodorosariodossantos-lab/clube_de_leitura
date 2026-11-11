-- Diagnóstico somente de leitura. Não altera escolas, alunos ou históricos.
select
 to_regprocedure('public.clube_escolas(text,jsonb)') is not null as painel_escolas_instalado,
 to_regclass('public.turmas') is not null as tabela_turmas_instalada,
 to_regprocedure('clube_private.escolas_antes_modulo(text,jsonb)') is not null as extensao_escolas_instalada,
 coalesce((select strpos(pg_get_functiondef(p.oid),'schools_list')>0 or
   (strpos(pg_get_functiondef(p.oid),'escolas_antes_exclusao')>0 and to_regprocedure('clube_private.escolas_antes_exclusao(text,jsonb)') is not null)
  from pg_proc p join pg_namespace n on n.oid=p.pronamespace
  where n.nspname='public' and p.proname='clube_escolas' and pg_get_function_identity_arguments(p.oid)='op text, args jsonb'),false) as operacao_listar_escolas_instalada;
