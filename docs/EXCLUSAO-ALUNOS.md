As ações da lista de alunos usam ícones com descrições acessíveis: lápis para editar, energia para ativar/desativar, gráfico para progresso e lixeira para excluir.

A exclusão pede confirmação, remove o aluno da lista de gerenciamento e bloqueia o acesso. Os registros de leitura, respostas, pontuações e eventos permanecem no histórico administrativo. Um aluno excluído não pode ser reativado pelos botões de situação nem receber novas credenciais.

Para habilitar a exclusão no banco existente, execute `supabase/migrations/202610230003_exclusao_alunos.sql` após as migrações anteriores, ou execute o arquivo completo `supabase/instalar-eventos.sql`, que instala somente as etapas ausentes.

Validação: `node --test supabase/tests/student-deletion.test.mjs`.
