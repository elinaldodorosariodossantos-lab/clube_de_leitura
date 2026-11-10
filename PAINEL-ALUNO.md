# Painel do aluno — atualização de 19/10/2026

> Atualização posterior: a lista intermediária foi substituída pelo acesso direto e avanço automático. Consulte [o fluxo definitivo e a migração de sequência](docs/SEQUENCIA-LEITURA.md). As referências ao catálogo abaixo descrevem a versão anterior.

Interface baseada na referência enviada: cabeçalho azul, banner com saudação e progresso integrado, personagens nos cartões verde/laranja/vermelho e rodapé em ondas. Sem menu lateral. Login continua direcionando para `/#/leitura`.

## Aplicação no Supabase

Depois das quatro migrações já aplicadas, executar **somente** `supabase/migrations/202610190001_progressao.sql` no SQL Editor. O script é transacional, versionado e deve ser executado uma vez. Não executar novamente `setup-clube.sql`. Não é possível aplicar DDL com a chave pública usada pelo aplicativo.

A atualização acrescenta a `public.textos`: `obrigatorio` (padrão verdadeiro, preservando o catálogo), `resumo`, `capa_url` (HTTPS) e `tempo_leitura_minutos` (positivo). Nenhuma tabela duplicada ou história fictícia é criada. `ativo=true` significa publicado; `ativo=false` representa rascunho/despublicação. Uma história disponível precisa de questões e gabaritos completos. A capa, o resumo e a duração aparecem somente quando cadastrados.

Reutiliza alunos, sessões, jornadas, tentativas, respostas, questões, níveis e gabaritos. Reutiliza a view privada `admin_resultados_validos` da migração administrativa para totais válidos, deduplicação e conclusões. O painel administrativo e suas consultas não foram alterados.

## Progressão e preservação

- Fácil começa liberado. Médio requer todas as histórias obrigatórias publicadas e disponíveis de Fácil; Difícil requer Fácil e Médio completos. Idade não bloqueia acesso.
- Quantidades são consultadas no banco, sem totais fixos no frontend. Histórias opcionais aparecem no catálogo, mas não impedem avanço. Um nível sem histórias disponíveis não é considerado concluído.
- Uma nova publicação obrigatória atualiza os requisitos da **última jornada**. Conclusões e pontos anteriores permanecem. Se necessário, níveis seguintes ficam bloqueados até completar a nova história. Jornadas anteriores ficam arquivadas, sem reabertura automática.
- Se isso ocorrer durante uma leitura de nível posterior, suas respostas ficam salvas. O aluno pode realizar a nova história anterior e depois retomar a leitura suspensa. Não se criam novas tentativas para revisar uma história concluída no mesmo ciclo.
- A jornada atual só permite novo ciclo por ação explícita, depois de atender aos requisitos e finalizar as tentativas abertas. A publicação de histórias não cria ciclos nem apaga conquistas.
- Resultado próprio já concluído continua revisável mesmo com despublicação ou novo bloqueio; nesse caso o texto integral não é reaberto. Histórias ainda não concluídas respeitam publicação e desbloqueio em todas as operações.

`clube_leitura` centraliza autorização, catálogo, início por história, respostas, correção e finalização. Mutações continuam serializadas pelo aluno e finalizações são idempotentes. Políticas RLS de textos/questões passam a usar `clube_texto_permitido`; assim, consultas REST diretas também respeitam o bloqueio. Gabaritos continuam privados. A sessão usa cookies HttpOnly; o código individual permite recuperar o identificador persistente em outro acesso/dispositivo. Sem esse código, não se promete recuperar uma sessão perdida apenas pelo nome.

## Rotas e atualização

`/#/leitura`: níveis; `/#/historias/facil`, `/medio`, `/dificil`: catálogos protegidos; `/#/atividade/<id>`: fluxo existente com retomada. Perfil e resultados continuam disponíveis por ações discretas e as rotas antigas permanecem compatíveis. A tela consulta alterações a cada 30 segundos e ao recuperar foco; ações são sempre revalidadas no banco. Um banco ainda sem a nova migração apresenta uma mensagem de atualização pendente, sem inventar progresso.

## Verificação

`npm run build` executa TypeScript do frontend/backend e build Vite. `npm test` cobre API, sessão, validação e proxy. `npm run test:sql` cobre migrações reais em PostgreSQL local (PGlite), incluindo publicação obrigatória adicional, rascunhos, opcionais, RLS, bloqueio por acesso direto, retomada, duplicatas e novos ciclos. A dependência de QA local pode ser instalada com `npm install --no-save --package-lock=false --prefix .qa/postgres @electric-sql/pglite`.

Para testar no aplicativo: identificar aluno → Fácil liberado → Ver histórias → finalizar as histórias obrigatórias → Médio liberado → repetir até Difícil. Recarregar durante as perguntas e retornar por código deve preservar a etapa. Publicar uma história obrigatória adicional deve atualizar os requisitos sem alterar pontos anteriores. Testar também `/#/historias/dificil` antes de desbloquear: o catálogo deve recusar acesso.

QA de navegador usa apenas banco e autenticação locais, sem cadastrar crianças no Supabase remoto. Scripts `.qa/progression-preview.mjs` e `.qa/progression-browser.mjs` verificam cadastro, catálogo, recarga, retorno, sessão e largura de 390 px. Capturas em `.qa/student-desktop.png` e `.qa/student-mobile.png` usam dados de teste.

## Arquivos desta etapa

- `frontend/src/PortalApp.tsx`, `types/portal.ts`, `hooks/useReading.ts`: rotas, tipos e consultas.
- `frontend/src/pages/StudentHome.tsx`, `components/ReadingLevels.tsx`, `components/WelcomeBanner.tsx`, `components/LevelStoryList.tsx`, `reading.css`: experiência visual e catálogo.
- `frontend/public/images/leitores-niveis.png`: ilustrações decorativas geradas para esta interface; a leitora existente foi reaproveitada no banner.
- `backend/src/reading.ts`, `backend/src/portal.test.ts`: catálogo, seleção de história, diagnóstico de migração e testes.
- `supabase/migrations/202610190001_progressao.sql`, `supabase/tests/progression.test.mjs`: progressão e segurança.
- Este guia, README, aviso de atualização em `docs/LEITURA-NIVEIS.md`, origem das imagens e scripts/capturas locais de QA.
