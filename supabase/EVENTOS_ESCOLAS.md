# Escolas participantes dos eventos

## Implantação

Execute `supabase/instalar-eventos.sql` completo no SQL Editor do Supabase. Ele inclui a migração `202611040001_eventos_escolas.sql` e aplica somente etapas ausentes, em uma transação. Se todas as migrações anteriores já estiverem instaladas, também é possível aplicar apenas essa nova migração uma vez.

A migração foi validada localmente; não foi executada no banco remoto nesta entrega. Ela não executa o arquivo separado de reinício de pontuação.

## Uso no painel

Em Cadastrar/Editar evento, a primeira etapa agora contém **ESCOLAS PARTICIPANTES**. Use **+ Selecionar escolas** para pesquisar as escolas cadastradas, selecionar individualmente ou selecionar todas as escolas da pesquisa. Confirmar seleção altera o formulário; Cancelar descarta a seleção do modal. Salvar evento persiste os vínculos. Cada escola vinculada pode ser removida da lista sem excluir seu cadastro.

O cadastro atual de escolas contém identificador e nome, sem município. A seleção reutiliza esse cadastro e não cria outro módulo de escolas ou campos de município.

Vincular uma escola permite autorizar seus alunos, mas não distribui automaticamente histórias para todos eles. O administrador continua usando **Enviar aos alunos**, com os filtros e o sorteio individual já existentes.

Eventos antigos recebem automaticamente as escolas dos participantes já registrados. Eles ficam sinalizados na lista e no editor para revisão. Eventos sem participantes não recebem vínculos gerais: devem ser configurados antes da ativação/distribuição. Participantes sem escola cadastrada também precisam ter seu cadastro administrativo revisado.

## Banco e autorização

- Nova tabela `public.evento_escolas`, com chave primária composta `(evento_id, escola_id)`, chaves estrangeiras para eventos/escolas e data de criação. A chave impede duplicatas; há índice adicional `(escola_id, evento_id)`.
- Nova coluna `public.eventos_leitura.escolas_revisar`, para sinalizar a migração de eventos antigos. Eventos sem vínculos também são identificados como pendentes de configuração.
- A escola considerada é sempre `public.alunos.escola_id`, consultada no banco a partir do aluno autenticado. Nenhuma escola enviada pelo aluno determina a autorização.
- `evento_escola_permitida` valida escola, vínculo e situação do aluno. `evento_disponivel` combina isso com atividade do evento, período, atribuição individual, data de nascimento, faixa etária e níveis existentes.
- `evento_elegivel` aplica o vínculo antes da distribuição. O lote de envio é validado por inteiro; alunos de escolas não vinculadas não recebem sorteios.
- `clube_eventos` integra os vínculos ao salvar e oferece `school_options` e `schools_save` para a administração. As operações exigem o administrador real identificado pelo banco.
- `clube_leitura` e `clube_api` revalidam as tentativas, inclusive acessos diretos a identificadores existentes. `leitura_tentativa` também impede que o estado devolva páginas/perguntas de eventos indisponíveis.
- `clube_texto_permitido`, usado pelas políticas de histórias e questões, passa a considerar a autorização dos eventos. Textos legitimamente atribuídos na jornada comum continuam disponíveis por essa jornada.

A nova tabela tem RLS e não recebe permissões diretas de leitura ou escrita para anon/authenticated. Há política de consulta documentando administradores e alunos autorizados. As políticas existentes `eventos_autorizados`, `participantes_proprios` e `leituras_proprias` são atualizadas explicitamente para consultar a autorização nova. As políticas existentes de textos/questões reutilizam `clube_texto_permitido`. Funções auxiliares e implementações anteriores permanecem privadas, sem execução direta pelo aluno.

Desvincular uma escola bloqueia os novos acessos, sem apagar escola, aluno, participação, respostas, snapshots, pontos, moedas ou certificados. Revincular permite retomar a mesma seleção e tentativa. A edição de vínculos não refaz sorteios.

## Arquivos principais

- `frontend/src/components/EventSchools.tsx`: seletor de escolas, pesquisa, múltipla seleção e remoção.
- `frontend/src/pages/ReadingEventEditor.tsx`: integração ao cadastro e à edição.
- `frontend/src/pages/ReadingEvents.tsx`: quantidade de escolas e alerta de revisão.
- `frontend/src/components/StudentEvents.tsx`: mensagem amigável quando não há eventos disponíveis.
- `frontend/src/types/events.ts` e `frontend/src/events.css`: contrato e apresentação.
- `backend/src/events.ts`: validação de IDs e rotas administrativas para consultar/salvar escolas.
- `backend/src/events.test.ts`: encaminhamento ao RPC, UUIDs e duplicatas.
- `supabase/migrations/202611040001_eventos_escolas.sql`, `supabase/instalar-eventos.sql` e `.qa/prepare-events-installer.mjs`: migração e instalação incremental.
- `supabase/tests/event-schools.test.mjs`: contrato novo e compatibilidade da migração.
- `supabase/tests/fixtures/before-event-schools.mjs`: mantém as suítes históricas no contrato anterior para regressão. A suíte nova aplica o instalador completo para testar a migração real e as novas regras.

## Testes

A suíte de banco específica cobre os 13 cenários pedidos: criação com uma e várias escolas; adição; remoção; duplicatas; visualização autorizada e negada; acesso direto por tentativa; consultas diretas com RLS; idade; sorteio persistente; progresso/pontos preservados; atualização após desvincular e revincular. Também verifica migração de participantes existentes, remoção de todos os vínculos e exclusão de evento sem excluir escolas.

No navegador, foram verificados pesquisa, cancelamento sem alteração, confirmação, várias escolas selecionadas, remoção, reabertura com seleções existentes, fechamento por Escape e envio dos IDs no salvamento do evento. A prévia foi verificada em 1366×900 e 390×844, sem exceções JavaScript e sem transbordamento horizontal no modal. A captura está em `.qa/event-schools-mobile.png`. A prévia utiliza respostas locais simuladas para a interface; as regras de autorização são exercitadas pela suíte SQL real via PGlite.

Comandos de validação: `npm.cmd run build`; `npm.cmd run test -w backend`; `node --test frontend/*.test.mjs`; `node --test --test-concurrency=1 supabase/tests/*.test.mjs`.

Resultado final: compilação do frontend e backend aprovada; 105 testes SQL aprovados (incluindo 16 da vinculação de escolas), 26 testes do backend e 10 do frontend aprovados, todos com zero falhas. Verificação funcional no navegador em desktop e celular aprovada.

Atualizacao: o cadastro por quantidades e o primeiro acesso automatico estao descritos em [DISTRIBUICAO_AUTOMATICA.md](DISTRIBUICAO_AUTOMATICA.md).
