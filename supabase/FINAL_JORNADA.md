# Conclusão final da jornada

A tela final é independente das conquistas de cada nível. Não possui ação de reiniciar, alterar nota nem avançar para outro nível. A conclusão e o certificado podem ser consultados em **Meu progresso → Jornadas concluídas e certificados**.

## Instalação

Execute `supabase/migrations/202611020002_conclusao_jornada.sql` depois de `202611020001_pontuacao_moedas.sql`, ou execute novamente o instalador completo `supabase/instalar-eventos.sql`. O instalador detecta a tabela privada e não reaplica a etapa. Publique/reinicie o backend e o frontend compilados juntos.

Nenhuma migração foi executada no Supabase remoto durante o desenvolvimento. Os testes utilizam PostgreSQL isolado em memória.

## Regra oficial e compatibilidade

A migração 202611020003_pontuacao_historia.sql define 20 pontos por história atribuída. As notas, moedas e certificados antigos permanecem na regra registrada. Consulte [REESTRUTURACAO_2026.md](REESTRUTURACAO_2026.md) para a política vigente, auditoria e testes. Não há mais teto fixo de 40 para contextos novos.

## Confirmação e persistência

`clube_private.jornada_registrar` verifica o proprietário, os critérios de progressão existentes e cada pergunta corrigida. Na jornada comum, considera os níveis com atribuições obrigatórias compatíveis com a idade e liberados pela sequência pedagógica, além das leituras iniciadas que impedem a avaliação completa. Níveis inexistentes ou bloqueados após uma lacuna não são tratados como concluídos. Nos eventos, usa todas as leituras da seleção individual e os snapshots enviados, nunca o catálogo que pode ter sido editado depois.

Somente uma avaliação completa em cada nível e uma conquista persistida permitem o resumo final. A tabela privada `conclusoes_jornadas` possui chave única por aluno/contexto/tipo; o vínculo individual de evento já é único por aluno/evento. O resumo guarda resultados, nome, escola, níveis, data e identificação institucional. A conclusão é registrada na finalização da última tentativa. A consulta de estado também permite retomar conclusões anteriores verificáveis, congelando os valores existentes sem corrigir respostas ou recompensas.

A primeira apresentação é consumida por `journey_claim`, atomicamente, e marca as conquistas do contexto como apresentadas para evitar abrir novamente a última celebração de nível. `journey_get` consulta sem crédito nem animação de entrada. Atualizar, sair e entrar novamente não cria outra conclusão nem recompensa. A página apenas anima a exibição do total já ganho.

As novas tabelas têm RLS habilitada, sem acesso direto para anon/authenticated. Os helpers são privados, com permissões revogadas, e os RPCs validam o aluno identificado. Os endpoints recebem somente o UUID da conclusão; nunca aluno, nota ou saldo enviados pelo navegador.

## Ranking

Somente eventos possuem pódio final. A consulta compara conclusões confirmadas do mesmo evento, faixa atribuída, conjunto de níveis e origem de pontuação. A soma é acadêmica; moedas não participam. Desempate: pontos decrescentes, conclusão crescente e UUID do aluno, reproduzindo a ordem determinística existente. Retorna até três colocados e a posição do aluno consultante quando estiver fora do pódio. Nomes/escolas vêm das conclusões reais, sem participantes inventados. Resultados legados não são misturados com os normalizados.

## Certificado

O administrador configura **Instituição** e **Identificação institucional ou do responsável** em Visão geral. Campos vazios são omitidos. Não há assinatura inventada. A configuração é capturada na conclusão; futuras mudanças não reescrevem certificados emitidos. O certificado inclui nome completo, evento quando houver, níveis efetivamente concluídos, data civil de Fortaleza e nota/limite reais. O botão Imprimir usa o diálogo do navegador, com folha A4 horizontal e estilo de impressão sem os elementos do painel. A opção Salvar como PDF depende do navegador.

## Arquivos principais

- Banco: migração `202611020002_conclusao_jornada.sql`, instalador atualizado e auditoria SQL.
- Backend: `reading.ts` (GET conclusão e POST claim), `admin.ts` (configuração institucional).
- Frontend: `JourneyCompletion.tsx`, `journey-completion.css`, `CertificateSettings.tsx`, tipos de portal, `StudentHome.tsx`, `useReading.ts` e `AdminOverview.tsx`.
- Verificação: `supabase/tests/journey-final.test.mjs`, `.qa/journey-final-preview.mjs`, `.qa/journey-final-browser.mjs`.

## Verificação

`npm run test:sql`, `npm test` e `npm run build`. Os casos novos cobrem pendências, dois/três níveis, idempotência, novo login, outro aluno, dados do certificado, ranking real e desempate, encerramento do evento e histórico legado. A prévia visual usa dados fictícios somente no banco isolado de QA, nunca no ranking real de produção.

A configuração institucional reutiliza clube_private.configuracao, com colunas aditivas. A conclusão imutável congela o certificado e impede duplicidade.

Validação atual: 70 testes SQL e 36 de backend/frontend aprovados, build completo e fluxo real no navegador; veja REESTRUTURACAO_2026.md.
