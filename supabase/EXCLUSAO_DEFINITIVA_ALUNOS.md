# Exclusão definitiva de alunos

Aplique `migrations/202611130003_exclusao_definitiva_alunos.sql` antes de publicar o frontend. O instalador completo também inclui essa etapa.

Esta mudança substitui a exclusão que apenas ocultava o aluno. Ao confirmar **Excluir aluno definitivamente**, são apagados cadastro, perfil de aluno, credenciais, sessões, respostas, tentativas, snapshots, jornadas, participações em eventos, avaliações, conquistas, conclusões/certificados, pontuação e moedas do aluno. As identidades de autenticação exclusivas desse aluno também são removidas; contas de equipe e identidades vinculadas a outros cadastros não são apagadas.

**A aplicação da migração também apaga definitivamente os dados dos alunos já marcados como excluídos pela regra antiga.** A operação é transacional: se alguma referência impedir a exclusão, nenhum apagamento parcial é confirmado.

As posições dos rankings são calculadas novamente a partir dos participantes restantes. Não altera os pontos dos outros alunos, as escolas, as turmas ou a biblioteca compartilhada. O ranking final aberto é atualizado ao retornar à aba e a cada 15 segundos enquanto estiver visível.

Desativar acesso continua apenas bloqueando o login e preservando os dados. A confirmação de exclusão na interface informa que a remoção é definitiva.

Verificação: `node --test supabase/tests/permanent-student-deletion.test.mjs`.
