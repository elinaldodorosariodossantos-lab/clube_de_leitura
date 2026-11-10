# Reinício de jornada autorizado pelo administrador

O bloco “Uma jornada inteira de descobertas” foi removido do painel do aluno. Não há mais botão para iniciar outra jornada, e os níveis concluídos não oferecem uma nova leitura pelo botão de início.

A liberação fica em **Administrador → Alunos → Detalhes do aluno → Jornadas do aluno → Autorizar nova jornada**. O botão aparece para alunos ativos cuja última jornada está concluída. O administrador confirma a ação; o sistema cria uma única nova jornada e o aluno passa a vê-la na atualização do painel.

O controle trata o reinício de uma jornada concluída. A retomada de uma atividade em andamento e a navegação entre páginas da mesma leitura continuam no fluxo existente.

## Segurança e histórico

- O endpoint HTTP `/reading/new-journey` responde 403 e não encaminha a operação ao banco.
- O RPC público `clube_leitura('new_journey')` também é bloqueado.
- O endpoint SQL legado `clube_api` não cria novas tentativas independentes por `start` nem novas jornadas.
- Apenas o administrador real autenticado pode executar `clube_gestao('student_journey_restart')`, com o aluno e o identificador da jornada atual.
- A jornada precisa estar concluída; atividades em andamento não são apagadas para liberar outra.
- O bloqueio por aluno, a unicidade da jornada de origem e a validação do identificador atual impedem duplicações e alterações por dados desatualizados.
- `clube_private.autorizacoes_reinicio_jornada` registra aluno, jornada de origem, nova jornada, administrador autenticado e data. A tabela tem RLS e não permite acesso direto por alunos.
- Leituras, respostas, pontos, moedas, certificados e participações em eventos anteriores são preservados. O reinício não redistribui histórias de eventos.

## Implantação

Execute o arquivo completo `supabase/instalar-eventos.sql` no SQL Editor do Supabase. A nova etapa é `202611040002_reinicio_administrador.sql`; o instalador aplica apenas etapas ausentes.

O banco remoto não foi alterado nesta entrega. O bloqueio também no RPC depende da aplicação da migração.

## Arquivos principais

- `frontend/src/components/ReadingLevels.tsx`: remove o bloco e desabilita o início de níveis concluídos.
- `frontend/src/pages/StudentHome.tsx` e `frontend/src/hooks/useReading.ts`: removem a ação de reinício do aluno.
- `frontend/src/pages/AdminStudentDetails.tsx`: autorização no painel administrativo.
- `backend/src/reading.ts`: bloqueio HTTP do reinício pelo aluno.
- `backend/src/management.ts`: rota administrativa de autorização.
- Migração nova, instalador SQL e seu gerador `.qa/prepare-events-installer.mjs`.
- `supabase/tests/admin-journey-restart.test.mjs`, `backend/src/portal.test.ts` e `backend/src/management.test.ts`: validação da autorização e do bloqueio.

## Validação

- Compilação do frontend e backend: aprovada.
- Backend: 26 testes aprovados, incluindo a negativa de reinício pelo aluno e o encaminhamento administrativo.
- SQL: 23 testes focados aprovados, combinando autorização administrativa e eventos por escola.
- Cenários do reinício: negação ao aluno e a parâmetros adulterados; bloqueio do endpoint legado e de escrita direta; autorização real do administrador; histórico e valores preservados; autorização repetida sem duplicação; nova leitura somente na jornada liberada; recusa de jornada pendente ou de outro aluno; auditoria com o administrador autenticado.
