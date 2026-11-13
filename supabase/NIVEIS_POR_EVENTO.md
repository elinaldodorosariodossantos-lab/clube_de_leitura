# Histórias dos eventos nos níveis

Aplique `migrations/202611130001_niveis_por_evento.sql` no SQL Editor do Supabase antes de publicar o frontend. Para uma instalação ainda incompleta, `instalar-eventos.sql` também inclui essa etapa e ignora as etapas já instaladas.

O cartão separado do evento sai da página do aluno. Os níveis passam a usar somente as seleções individuais do evento aberto para a escola e idade do aluno. A distribuição automática continua sendo capturada uma única vez, no primeiro acesso.

- Antes do início: aviso de que o evento ainda não começou, sem histórias.
- Do início inclusive até o fim exclusive: histórias, progresso e sequência do evento nos níveis.
- No encerramento: aviso de evento encerrado, sem acesso às leituras pendentes. Resultados, moedas e históricos permanecem salvos.

Exemplo: um evento de 13/11/2026 às 08:00 até 18:00, no horário da escola, abre às 08:00 e fecha às 18:00. O banco valida os timestamps; o frontend usa a hora enviada pelo servidor para atualizar a tela na mudança de período, mesmo sem recarregar a página.

Com eventos simultâneos, apresenta um evento por vez: prioriza o primeiro com histórias pendentes, ordenado por início e identificador. Não mistura histórias ou pontuações de eventos diferentes. Ao concluir esse evento, o próximo elegível pode ocupar os níveis.

Não requer publicar novamente a Edge Function: as rotas atuais de leitura continuam sendo usadas. A validação ocorre nos RPCs do Supabase, inclusive para URLs abertas diretamente.

Verificação local: `node --test supabase/tests/event-schedule.test.mjs supabase/tests/automatic-distribution.test.mjs` e `node --test frontend/event-schedule.test.mjs`.
