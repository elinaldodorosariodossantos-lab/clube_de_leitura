# Perguntas e alternativas dinâmicas

Execute uma vez `supabase/migrations/202610230002_alternativas_dinamicas.sql` no SQL Editor após as migrações de eventos e idades. Também é possível executar todo o `supabase/instalar-eventos.sql` atualizado, que aplica somente as etapas ausentes. Esta atualização ainda não foi aplicada automaticamente ao Supabase remoto.

Em Histórias, abra o cadastro ou edição. Cada pergunta começa com duas alternativas. Use **+ Alternativa** para adicionar opções e a lixeira para removê-las; são necessárias ao menos duas. Marque o círculo da alternativa correta. Ao remover uma opção, o gabarito acompanha a nova posição; se a correta for removida, a primeira passa a ser a correta e pode ser alterada.

**Concluir pergunta** recolhe o bloco. **Adicionar pergunta** valida os campos, recolhe a anterior e abre a próxima. Clique no cabeçalho de uma pergunta para reabrir sua edição. O resumo recolhido mostra o enunciado e a quantidade de alternativas. Perguntas incompletas impedem o salvamento, inclusive quando recolhidas.

A API e o banco validam a quantidade e o índice correto. A resposta do estudante é validada contra as alternativas capturadas no início da tentativa; editar uma história preserva os conteúdos, gabaritos, respostas e pontos anteriores. A nova migração amplia as constraints e atualiza as funções existentes, sem apagar registros ou duplicar o módulo.

Arquivos principais alterados/criados:

- `frontend/src/components/StoryQuestions.tsx`: alternativas, gabarito, validação e perguntas recolhíveis.
- `frontend/src/pages/ManageStories.tsx`: integração e validação ao salvar.
- `frontend/src/admin.css`: apresentação das perguntas e alternativas.
- `backend/src/management.ts`, `backend/src/reading.ts`, `backend/src/server.ts`: validação de alternativas e encaminhamento de respostas.
- `supabase/migrations/202610230002_alternativas_dinamicas.sql` e `supabase/instalar-eventos.sql`: suporte no PostgreSQL.
- `.qa/prepare-events-installer.mjs`: geração do instalador atualizado.
- `supabase/tests/dynamic-options.test.mjs`: testes de persistência, correção, índices inválidos e preservação de snapshots.
- `.qa/questions-browser.mjs`: roteiro de alternativas, recolhimento, reabertura e persistência na interface.

Para verificar, crie uma pergunta com seis alternativas e marque a última como correta; adicione outra pergunta, reabra a primeira, remova uma opção intermediária e confira o gabarito. Salve e reabra a história. Distribua em evento e responda a última alternativa como aluno. Edite a história enquanto uma tentativa estiver em andamento e confirme que a correção dessa tentativa continua usando a versão anterior. Use `npm test`, `npm run build` e `npm run test:sql` para os testes automatizados.
