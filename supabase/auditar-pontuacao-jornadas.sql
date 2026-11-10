-- Somente leitura; executar depois de 202611030002_pontuacao_oficial.sql.
-- Decimais periódicos em contextos antigos não são tratados como erro automaticamente.
select c.aluno_id,c.contexto_id,c.evento,c.nivel,c.pontos,v.regra_pontos,
 case when v.conquista_id is null then 'legado: preservar' when v.regra_pontos=4 then '10 por leitura + 5 por acerto' when v.regra_pontos=3 then 'historico: 20 por história' else 'versão 2: unidades / 3' end origem,
 v.historias,v.questoes,v.acertos,v.unidades,
 v.unidades/case when v.regra_pontos>=3 then 1 else 3 end esperado,
 r.valor_unidades/case when v.regra_pontos>=3 then 1 else 3 end moedas,
 case when v.conquista_id is null then null else c.pontos-v.unidades/case when v.regra_pontos>=3 then 1 else 3 end end diferenca
from clube_private.conquistas_niveis c left join clube_private.avaliacoes_niveis v on v.conquista_id=c.id
left join clube_private.recompensas_moedas r on r.conquista_id=c.id order by c.concluida_em,c.id;

select c.id,c.aluno_id,c.pontos,v.regra_pontos,v.unidades,r.valor_unidades
from clube_private.conquistas_niveis c join clube_private.avaliacoes_niveis v on v.conquista_id=c.id
left join clube_private.recompensas_moedas r on r.conquista_id=c.id
where abs(c.pontos-v.unidades/case when v.regra_pontos>=3 then 1 else 3 end)>0.000001
 or r.conquista_id is null or r.valor_unidades<>v.unidades or r.aluno_id<>v.aluno_id;

select aluno_id,contexto_id,evento,nivel from clube_private.pontuacao_legada order by aluno_id,contexto_id,nivel;
select regra_pontos,count(*) contextos from public.jornadas group by regra_pontos;
select regra_pontos,count(*) participantes from public.evento_alunos group by regra_pontos;
select schemaname,tablename,policyname,roles,cmd,qual,with_check from pg_policies
where schemaname in('public','clube_private','storage') order by schemaname,tablename,policyname;
