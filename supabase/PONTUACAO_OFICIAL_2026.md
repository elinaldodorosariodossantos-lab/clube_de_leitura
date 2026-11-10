# Pontuação oficial — Clube da Leitura 2026

## Regra vigente

Nos três níveis: leitura efetivamente concluída = 10 pontos; acerto = 5; erro = 0. Abrir uma história ou deixar uma questão pendente não concede pontos. O máximo depende da atribuição: 10 × histórias + 5 × questões.

A conclusão da leitura é registrada pelo fluxo existente, depois da última página, ao entrar nas questões. Os acertos são corrigidos ao finalizar todas as respostas, conforme o gabarito privado capturado na atribuição. A nota de leitura confirmada aparece no total acadêmico mesmo quando o nível está pendente.

A unicidade continua por aluno e atividade atribuída no contexto da jornada/participação do evento. Recarregar, repetir chamadas ou fazer novo login não cria outra atribuição ou recompensa. Concluir a mesma história em outra atribuição legítima de outro evento permanece uma atividade independente, como no sistema existente.

## Histórico e implantação

A regra recebe a versão 4 nas colunas existentes, sem criar outro sistema de notas. Versões 2 e 3 permanecem para interpretar contextos históricos. Nenhuma resposta, nota, conquista, moeda ou certificado antigo é recalculado pela migração. Contextos com qualquer tentativa iniciada ficam na regra anterior; somente contextos sem tentativas, conquistas ou certificados adotam a nova regra.

Arquivo: `migrations/202611030002_pontuacao_oficial.sql`. Requer todas as migrações anteriores, inclusive `202611030001_catalogo_atualizado.sql`.

No SQL Editor, executar o arquivo completo `instalar-eventos.sql`, que inclui somente etapas ausentes em uma transação. Alternativamente, se todas as etapas anteriores já estiverem instaladas, executar somente a nova migração uma vez. Não aplicar a migração isolada novamente depois do instalador.

Validado em PostgreSQL local via PGlite. Nenhuma migração foi executada no Supabase remoto nesta entrega. A nova regra depende dessa aplicação no ambiente de destino.

## Fonte confiável e funções alteradas

- `historia_avaliar`: 10 pela leitura confirmada e 5 por acerto na regra 4; máximo variável por snapshot.
- `avaliacao_calcular`: soma histórias/questões atribuídas ao aluno no contexto e nível.
- `conquista_registrar`, `conquista_json`: persistem a avaliação oficial e a recompensa existente de 1 ponto = 1 moeda. O crédito continua no fechamento do nível, uma única vez.
- `gabarito_historia_v3`: o trigger existente grava peso 5 para questões da regra 4; pesos administrativos antigos não determinam a regra nova.
- `attempt_json`, `total_academico`, `pontuacao_contexto`, `pontos_validos_tentativa`: respostas, totais, históricos e relatórios coerentes.
- `saldo_moedas`, `ranking_conquista`, `jornada_registrar`: divisor 1 na regra 4, máximo pelas atribuições, classificação por nota acadêmica no mesmo evento/faixa/regra.
- `pontuacao_resumo`: resumo privado de pontos por nível para Meu progresso; reutiliza as avaliações oficiais.
- Roteamento de leitura/API, progresso, autorização, atribuição e sincronização do catálogo reconhecem a regra 4, mantendo o fluxo existente.
- `clube_escolas` informa 5 por resposta correta na regra nova; demais painéis usam os totais oficiais existentes.

As constraints aceitam a versão nova e verificam a fórmula. RLS, funções privadas e grants existentes permanecem em vigor. Pontos, moedas e acertos enviados pelo navegador não participam do cálculo.

## Arquivos modificados

- Nova migração, `instalar-eventos.sql` e gerador `.qa/prepare-events-installer.mjs`.
- `frontend/src/components/StoryQuestions.tsx`: explica a regra no editor.
- `frontend/src/components/ReadingActivity.tsx`: usa o máximo oficial recebido.
- `frontend/src/pages/StudentHome.tsx`: pontos de Fácil, Médio, Difícil e acumulado, com leitura/questões; recompensas separadas do saldo.
- `frontend/src/components/JourneyCompletion.tsx` e `frontend/src/types/portal.ts`: discriminação de leitura/questões no resumo por nível, usando valores do banco.
- `supabase/tests/official-scoring.test.mjs`: cobertura da regra nova.
- `supabase/tests/story-scoring.test.mjs`: mantém a suíte anterior na versão 3 para verificar compatibilidade.
- `supabase/auditar-pontuacao-jornadas.sql`, README e referência no documento histórico de reestruturação.

## Validação

Comandos: `npm.cmd run build -w frontend`; `node --test --test-concurrency=1 supabase/tests/*.test.mjs`; `node --test supabase/tests/official-scoring.test.mjs`.

| Teste obrigatório | Resultado |
| --- | --- |
| 1. Uma leitura concluída | 10 pontos; abrir apenas = 0 |
| 2. Uma resposta correta | 5 pontos |
| 3. Resposta errada | 0 pontos |
| 4. Cinco leituras | 50 pontos, inclusive sem acertos |
| 5. Dez acertos | 50 pontos nas questões |
| 6. Cinco leituras e dez acertos | 100 pontos |
| 7. Três níveis acumulados | 100 + 80 + 60 = 240 |
| 8. Atualizar/repetir chamadas | Nota e saldo preservados, sem duplicação |
| 9. Novo login | Sessão retorna a nota persistida |
| 10. Recompensa idempotente | Reabrir conquista/certificado não credita novamente |
| 11. Ranking real | Mesmo evento/idade: 100 pontos antes de 75 |
| 12. Manipulação pelo cliente | Campos extras ignorados; escrita direta e gabarito bloqueados |

Também testados: perguntas em quantidades diferentes, máximo variável (5 histórias com 4 questões = 150), pendências impedindo conclusão/recompensa, históricos v2/v3 preservados, instalador repetido e administração/relatórios.

Os testes de refresh e login exercitam as chamadas autenticadas ao banco e a persistência. Não foi realizada uma nova inspeção visual em navegador nesta entrega.

Resultado: compila??o frontend aprovada; su?te SQL completa com 81 testes aprovados (zero falhas); su?te oficial ampliada com 11 testes aprovados (zero falhas). Os n?meros incluem os testes principais e seus subtestes, sem somar as su?tes sobrepostas.
