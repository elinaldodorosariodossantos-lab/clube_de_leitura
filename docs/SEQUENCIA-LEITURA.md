# Acesso direto e sequência de leitura

Atualização de 19/10/2026, restrita ao aluno. O visual da referência foi preservado. Não houve alteração no painel administrativo.

## Configuração necessária

Aplicar **uma vez** `supabase/migrations/202610190002_sequencia.sql`, depois de `202610190001_progressao.sql` e das migrações anteriores. Não reaplicar o setup nem scripts já executados. O aplicativo utiliza uma chave pública e não pode executar essa migração pelo backend.

A única coluna nova é `public.textos.ordem`, inteiro não negativo, padrão zero. A seleção usa `ordem ASC, id ASC`; portanto, empates têm resultado estável. O administrador poderá configurar esse campo futuramente, sem necessidade de mudar o painel do aluno. `ativo` continua sendo publicação e `obrigatorio` indica participação na sequência. Não há total fixo de histórias nem conteúdo novo de produção.

## Fluxo

O login continua em `/#/leitura`. O cartão **Começar leitura** chama `POST /api/portal/reading/enter`, que consulta `clube_leitura('enter', {level})` no Supabase. Sem lista intermediária: o banco devolve a leitura autorizada em andamento ou cria uma tentativa para a primeira história obrigatória publicada, pronta para correção e ainda não concluída, respeitando a ordem cadastrada. As rotas antigas `/#/historias/<nivel>` também fazem essa entrada direta.

Depois de validar a última resposta e finalizar, o frontend consulta novamente a sequência. Havendo outra história obrigatória, abre diretamente sua leitura. Ao terminar o nível, mantém o resultado da última atividade e mostra a conclusão e ações para escolher o próximo nível ou revisar resultados. O histórico permite rever as correções das atividades anteriores. Se a consulta seguinte falhar após salvar a conclusão, o resultado permanece salvo e **Tentar novamente** ou **Continuar sequência** retoma a seleção sem duplicar pontos.

Fácil começa liberado. Médio exige as obrigatórias disponíveis de Fácil; Difícil exige Fácil e Médio. O cálculo continua dinâmico e protegido no banco/RLS. Histórias opcionais não entram no percurso obrigatório automático. Um nível sem histórias disponíveis apresenta a mensagem de novas histórias em breve.

## Mudanças no catálogo

- Reordenar uma história em andamento não troca sua tentativa: ela continua até terminar; a nova ordem vale para a próxima seleção.
- Uma história despublicada não pode continuar sendo lida nem responder questões. As respostas são preservadas, ela sai dos requisitos atuais e a próxima história publicada pode ser aberta.
- Se for republicada na mesma jornada, a tentativa salva pode ser retomada. Uma nova obrigatória em nível anterior recalcula os bloqueios, preservando conclusões e pontos.
- Um novo ciclo é sempre explícito. Tentativas despublicadas permanecem arquivadas no ciclo anterior e não impedem essa ação quando os requisitos publicados foram concluídos. Elas não recebem pontos por abandono.

## Segurança e estruturas

Reutiliza textos, níveis, alunos, jornadas, tentativas, respostas, questões, sessões e a view privada de resultados válidos. Não cria tabelas e não altera políticas RLS: as políticas da migração de progressão continuam em vigor.

A função anterior é movida para `clube_private` e tem sua execução revogada para clientes. A nova função pública verifica identidade, desbloqueio, publicação e ordem antes de criar uma tentativa. O endpoint antigo `start` também respeita a seleção; enviar arbitrariamente outro `storyId` não permite pular a sequência. Leituras anteriores continuam revisáveis por seu identificador autorizado. Correção, respostas salvas, cookies HttpOnly e código de recuperação são preservados.

## Arquivos

- `supabase/migrations/202610190002_sequencia.sql` e `supabase/tests/sequence.test.mjs`.
- `backend/src/reading.ts` e `backend/src/portal.test.ts`.
- `frontend/src/pages/StudentHome.tsx`, `components/ReadingLevels.tsx`, `components/ReadingActivity.tsx`, `hooks/useReading.ts`, `types/portal.ts`, `PortalApp.tsx`.
- Este guia, referências em README/PAINEL-ALUNO e scripts locais `.qa/sequence-preview.mjs`, `.qa/sequence-browser.mjs` e `.qa/sequence-direct-browser.mjs`.

Verificações: `npm run build`, `npm test` e `npm run test:sql`. O teste SQL novo cobre ordem, tentativa repetida, reordenação durante a leitura, proteção de função privada, bloqueio de níveis, despublicação/republicação, finalização idempotente e ciclos. QA local de navegador não cria contas no Supabase remoto.

Resultado desta etapa: TypeScript/build e 13 testes aprovados. O teste focado de navegador `sequence-direct-browser.mjs` confirmou entrada direta, perguntas, avanço automático à segunda história e desbloqueio do Médio. A execução mais longa com retorno por código foi interrompida pelo encerramento do navegador de teste; esse cenário não foi usado como evidência de aprovação nesta etapa.
