# Acesso por data de nascimento

## Aplicação no Supabase

Execute o arquivo completo `supabase/instalar-eventos.sql` no SQL Editor. Ele aplica somente as etapas ausentes, incluindo `202610230007_acesso_por_nascimento.sql`. Se todas as etapas anteriores já estiverem instaladas, pode executar somente essa nova migração. Não execute ambas como migrações independentes: a migração individual é para uma aplicação única.

A alteração foi validada em PostgreSQL local (PGlite). O banco remoto não foi alterado por esta implementação.

## Regra

A fonte de verdade é `public.alunos.data_nascimento`. A idade é `extract(year from age(data_atual, nascimento))`, usando a data civil de `America/Fortaleza`. O cálculo ocorre a cada consulta, considera o aniversário completo e ignora a coluna legada `idade` e valores enviados pelo navegador. Não precisa de tarefa agendada.

Nascimento ausente, futuro ou não finito bloqueia histórias e mostra uma solicitação de correção à escola. O sistema não inventa uma data para cadastros antigos: corrija esses cadastros no painel administrativo.

O campo existente `textos.faixa_etaria` aceita idade única (`5 anos`), intervalo inclusivo (`5 a 7 anos`, `6–8 anos`) ou limite inferior (`13 anos ou mais`), entre 4 e 19. Formatos não reconhecidos ficam indisponíveis até correção. O formulário administrativo permite digitar a faixa e sugere idades individuais.

As funções de leitura, progresso, autorização e eventos verificam a idade no banco. As políticas RLS existentes de textos e questões reutilizam essa autorização. Os blocos exibidos contêm somente histórias da idade atual; Médio e Difícil continuam dependendo da progressão existente. Chamadas diretas e snapshots de leituras antigas também passam pela verificação.

Eventos validam cada conjunto por idade e nível, usando a idade atual do aluno. Falta de histórias elegíveis gera erro, sem completar a quantidade com outra faixa. Aniversários e atualizações de página não refazem atribuições. Se uma atribuição pendente se tornar incompatível, o evento fica indisponível para aquele aluno; as atribuições e o progresso permanecem armazenados. Resultados concluídos e pontuações continuam no histórico; conteúdo de leitura fora da faixa não é reaberto.

## Arquivos

- Banco: `supabase/migrations/202610230007_acesso_por_nascimento.sql` e `supabase/instalar-eventos.sql`.
- Gerador do instalador: `.qa/prepare-events-installer.mjs`.
- Interface: `frontend/src/pages/ManageStories.tsx`, `frontend/src/components/ReadingLevels.tsx`, `frontend/src/components/StudentEvents.tsx`, `frontend/src/types/portal.ts`.
- Testes: `supabase/tests/age-access.test.mjs`, com adequação dos cadastros nos testes `book-pages.test.mjs` e `dynamic-options.test.mjs`.

## Verificação

Execute `node --test supabase/tests/age-access.test.mjs`. O teste instala o banco, reaplica o instalador e cobre aniversário passado e futuro, limites inclusivos, tentativa de acesso direto, RLS, nascimento inválido, idade manual adulterada, evento com várias faixas, insuficiência, retomada e preservação das atribuições. Simula também a mudança de data no servidor sem alterar o nascimento para comprovar a atualização automática no aniversário. A simulação só existe no banco isolado do teste.

Para regressão: `npm test`, `npm run build` e `node --test --test-concurrency=1 supabase/tests/*.test.mjs`.

No navegador, cadastre uma história para `5 a 7 anos`, outra para `8 a 10 anos` e um aluno com nascimento correspondente a 5 anos. Entre com o código do aluno e confira que só a primeira aparece. Tente abrir a URL de uma leitura incompatível; ela deve ser bloqueada. Remova o nascimento em um cadastro de teste para verificar a mensagem de correção. Em eventos, tente solicitar mais histórias do que o conjunto elegível: o painel deve informar a insuficiência.
