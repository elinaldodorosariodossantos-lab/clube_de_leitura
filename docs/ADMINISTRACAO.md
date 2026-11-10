# Administração — visão geral e alunos

## Ativação no Supabase existente

**Atualização de 19/10/2026:** o responsável aplicou a migração, e a presença da função `clube_admin` foi confirmada pela API. O bloqueio sem autenticação também foi confirmado. As instruções abaixo servem para novas instalações; não execute novamente no projeto já atualizado.

Execute **somente** `supabase/migrations/202610150002_admin.sql` no SQL Editor do projeto já configurado. Não reexecute `setup-clube.sql` nem as migrações anteriores. A migração administrativa depende da estrutura de alunos e escolas da etapa 1; pode ser aplicada mesmo que `202610150001_leitura.sql` ainda esteja pendente.

Não cria tabelas nem altera cadastros. Cria duas views privadas, uma função de leitura autorizada e um índice. A chave pública configurada no projeto não permite aplicar SQL pelo painel de gerenciamento; a migração remota foi aplicada pelo responsável.

O administrador precisa de uma conta permanente de e-mail/senha no Supabase Auth e de `public.perfis.papel='admin'`, concedido pelo responsável pelo banco para o UUID real da conta. Nunca use o UUID de uma conta anônima de aluno. Para uma conta administrativa já existente, nenhuma alteração de papel é necessária.

```sql
insert into public.perfis(id,nome,papel)
values ('UUID_REAL_DA_CONTA', 'Nome do administrador', 'admin')
on conflict(id) do update set papel='admin';
```

Após compilar, reinicie o backend se estiver usando `npm.cmd start -w backend`. O frontend continua usando o proxy `/api`, sem conexão privilegiada no navegador.

## Rotas

| Rota | Conteúdo |
| --- | --- |
| `/#/admin` ou `/#/admin/entrar` | Login; com sessão autorizada, segue para a visão geral |
| `/#/admin/visao-geral` | Quatro indicadores |
| `/#/admin/alunos` | Pesquisa, filtro, ordenação e paginação |
| `/#/admin/alunos/<uuid>` | Cadastro, jornadas e progresso individual |
| `/#/admin/escolas` | Em desenvolvimento |
| `/#/admin/relatorios` | Em desenvolvimento |
| `/#/admin/configuracoes` | Em desenvolvimento |

Depois do login administrativo, o destino é a visão geral. Acesso direto ou recarga de qualquer rota recupera a sessão e verifica o papel. O menu marca a página ativa, inclusive nos detalhes de um aluno. Os filtros são mantidos ao abrir detalhes e voltar à listagem na mesma navegação; uma recarga da página restabelece os filtros padrão.

## Consultas e critérios dos indicadores

O Express valida a sessão e chama `clube_admin(op,args)` com o contexto autenticado. Operações:

- `overview`: quatro indicadores e horário da consulta.
- `students`: registros paginados, quantidade filtrada e escolas com alunos.
- `student`: cadastro, jornadas e tentativas do aluno solicitado.

Os indicadores são calculados no PostgreSQL, sem contar alunos por junção com atividades:

```sql
select count(*) from public.alunos;

select count(distinct e.nome_normalizado)
from public.escolas e join public.alunos a on a.escola_id=e.id;

select count(*) from clube_private.admin_resultados_validos;

select coalesce(sum(pontuacao),0)
from clube_private.admin_resultados_validos;
```

`admin_resultados_validos` considera somente `status='completed'`, data de conclusão preenchida, respostas completas do texto correto, correção armazenada em todas as respostas e consistência entre acertos, pontos, percentual e respostas. Atividades em andamento e conclusões sem respostas não entram nos totais.

Duplicatas são agrupadas por **aluno + jornada + texto**. Havendo mais de uma conclusão válida nesse grupo, a primeira conclusão é contada, com desempate pelo UUID. Jornadas diferentes são contadas separadamente. Para registros legados sem jornada, o grupo é aluno + texto; não é possível inferir ciclos ausentes. Os registros brutos continuam preservados e os detalhes identificam os que ficaram fora dos totais. Não se reexecuta o gabarito sobre resultados históricos; a validação usa a correção armazenada.

`admin_alunos` reutiliza essa mesma view para os totais individuais. Assim, dashboard, listagem e detalhes usam o mesmo critério. A soma dos totais de todos os alunos corresponde ao indicador geral. Nomes legados podem ser recuperados de `perfis.nome` quando `alunos.nome_completo` está ausente.

Escolas usam o identificador e a normalização já existente: espaços consecutivos e maiúsculas/minúsculas não geram outra escola. Escolas sem aluno não são contadas nem aparecem no filtro. Não há fusão automática por semelhança, abreviações, acentos ou possíveis erros de digitação, para evitar juntar instituições diferentes.

## Pesquisa, filtros e atualização

A consulta paginada aceita `search`, `schoolId`, `sort`, `page` e `pageSize`. A pesquisa é literal, sem distinção entre maiúsculas e minúsculas; `%` não funciona como curinga. A ordenação aceita nome crescente/decrescente ou pontos crescente/decrescente, com desempate estável por nome e UUID. O backend permite até 100 registros por página; a interface solicita 20.

Dashboard, lista e detalhes consultam novamente a cada **20 segundos**, quando visíveis, ao recuperar foco/conexão e pelo botão **Atualizar**. Requisições antigas não substituem os resultados de filtros mais recentes. Falhas limpam os indicadores/lista consultados e apresentam **Tentar novamente**; valores fictícios não substituem respostas inválidas. Banco vazio mostra zero e estados vazios reais.

## Segurança

- O papel é lido de `perfis`, não de campos editáveis do navegador nem de `user_metadata`.
- Contas anônimas são recusadas, inclusive se um perfil tiver papel administrativo por engano.
- Cada chamada SQL verifica novamente `clube_private.administrador()`. Revogar o papel bloqueia consultas seguintes.
- A função usa `SECURITY DEFINER` com `search_path=''` para agregação controlada; somente após verificar o administrador consulta as tabelas. A RLS e os privilégios existentes permanecem intactos. Nenhuma view privada é liberada para `anon` ou `authenticated`; a função é a entrada autorizada.
- O frontend só monta as consultas administrativas após a autorização da sessão. A API também exige usuário verificado e a função confere o papel; modificar a interface não concede acesso.
- Sessões continuam em cookies HttpOnly. Nenhuma chave privada vai ao frontend.
- Esta etapa oferece somente consulta. Não há controles nem endpoints de edição ou exclusão de alunos.

## Verificações

```powershell
npm.cmd run build
npm.cmd test
npm.cmd run test:sql
```

O teste SQL usa o PostgreSQL local temporário da etapa de leitura. Se ainda não estiver instalado:

```powershell
npm.cmd install --no-save --package-lock=false --prefix .qa/postgres @electric-sql/pglite
```

Foram testados banco vazio, alunos únicos, escolas normalizadas e sem alunos, atividades em andamento com pontos indevidos, conclusões incompletas/inconsistentes, duplicatas com e sem ciclo, ciclos legítimos distintos, pesquisa, filtros, quatro ordenações, paginação, detalhes, revogação de papel e bloqueio de contas comuns/anônimas. O teste também aplica a migração administrativa antes da migração de leitura para verificar essa independência.

No navegador, uma base PostgreSQL isolada e autenticação simulada foram usadas para verificar senha incorreta, conta não autorizada, login, redirecionamento, indicadores, menus, pesquisa, filtro, ordenação, paginação, detalhes, recarga, celular de 390 px sem overflow da página, erro/repetir e atualização após novo cadastro. Os dados das capturas `.qa/admin-*.png` pertencem exclusivamente a essa base de teste. Nenhum cadastro foi criado no Supabase remoto.

A verificação do login de uma conta real depende da conta administrativa do projeto e da migração remota. O script `node backend/scripts/check-supabase.mjs` verifica a disponibilidade da função sem acessar cadastros.

## Arquivos criados e alterados

- `frontend/src/pages/Admin.tsx`: login e layout com menu por rotas.
- `frontend/src/pages/AdminOverview.tsx`: indicadores.
- `frontend/src/pages/AdminStudents.tsx`: pesquisa, filtro, ordenação e paginação.
- `frontend/src/pages/AdminStudentDetails.tsx`: cadastro e progresso individual.
- `frontend/src/pages/AdminPlaceholder.tsx`: áreas em desenvolvimento.
- `frontend/src/components/AdminQueryState.tsx`: carregamento, atualização e erro/repetir.
- `frontend/src/hooks/useAdminResource.ts`: consultas e atualização periódica.
- `frontend/src/services/adminRoutes.ts`, `frontend/src/types/admin.ts`: rotas e contratos tipados.
- `frontend/src/PortalApp.tsx`, `frontend/src/admin.css`: proteção, navegação e apresentação responsiva.
- `backend/src/admin.ts`: endpoints de leitura e validação de filtros.
- `backend/src/portal.ts`: integração e login sem carregar a lista completa de alunos.
- `backend/scripts/check-supabase.mjs`: diagnóstico da função administrativa.
- `backend/src/portal.test.ts`, `frontend/admin-routes.test.mjs`: testes de sessão, API e rotas.
- `supabase/migrations/202610150002_admin.sql`, `supabase/tests/admin.test.mjs`: consultas e testes PostgreSQL.
- `README.md` e este guia: execução e configuração pendente.
