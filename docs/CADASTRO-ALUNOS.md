# Cadastro e gerenciamento de alunos

O módulo usa os cadastros reais do Supabase. Não foram alterados o editor de histórias nem o layout de outras áreas.

## Ativação

1. As migrações anteriores, inclusive `202610190003_gestao.sql`, devem estar aplicadas.
2. Execute **uma vez** `supabase/migrations/202610190004_cadastro_alunos.sql` no SQL Editor. Não execute novamente o setup inicial.
3. Mantenha `SUPABASE_URL`, `SUPABASE_ANON_KEY` e `ACCESS_CREDENTIALS_KEY` no backend. Se a chave de cifragem ainda não existe, execute `node backend/scripts/configure-access-key.mjs` uma vez. Preserve a chave ao trocar de ambiente: ela permite recuperar as fichas já emitidas.
4. Para produção, configure `PUBLIC_APP_URL` com o domínio HTTPS do aplicativo. Em desenvolvimento, o link usa a origem atual.
5. O provedor de login anônimo precisa estar habilitado no Supabase. A conta administrativa precisa do papel `admin` em `public.perfis`.

## Dados e segurança

São reutilizadas `public.alunos`, `public.perfis`, `public.escolas`, `public.jornadas`, `public.tentativas` e `clube_private.acessos`/`sessoes`. A edição de dados pessoais conserva as credenciais; desativar revoga as sessões e bloqueia novas entradas sem apagar o progresso.

A nova migração acrescenta somente `alunos.cadastro_requisicao` (UUID único) e `cadastro_dados_hash`. Não cria tabelas nem altera políticas RLS. O RPC `clube_gestao` valida o administrador antes de consultar ou modificar dados. Sua implementação anterior passa para o schema privado, sem permissão de execução direta para usuários.

O formulário mantém um identificador para cada envio. `student_request` consulta a operação antes de criar uma identidade. `student_save` usa bloqueio transacional por identificador e a constraint única para impedir dois alunos para o mesmo envio, inclusive com solicitações simultâneas. Repetir um cadastro confirmado devolve a ficha original; reutilizar a chave com outros dados é rejeitado. Alunos com nomes iguais continuam permitidos.

As credenciais são geradas no backend e salvas junto com o cadastro em uma transação. Os hashes únicos tratam colisões; código/link completos ficam cifrados no schema privado. Somente a ficha do aluno selecionado é devolvida a um administrador autorizado. A chave privada do Supabase não é usada no frontend.

## Teste manual

1. Entre em `/administrador` e abra **Alunos → Cadastrar aluno**.
2. Informe nome completo, nascimento, responsável, escola e série. Datas impossíveis/futuras e campos incompletos são rejeitados; permanece a faixa de cadastro existente, de 4 a 19 anos.
3. Clique **Salvar aluno**. A ficha deve mostrar o aluno escolhido, código de seis caracteres, QR e link; a lista é atualizada.
4. Copie código/link e imprima a ficha. Feche e recarregue a página para conferir persistência.
5. Edite os dados e abra novamente a ficha: o código e o link devem permanecer iguais.
6. Desative o aluno e tente seu código em outra sessão: o acesso deve ser recusado. Reative para permitir novamente.
7. Saia da administração e entre pelo código, link ou QR. O aluno deve retornar ao próprio progresso. Reentrar não cria um novo cadastro ou nova pontuação.

## Verificação realizada

Compilação/TypeScript, testes HTTP e PostgreSQL local com as migrações reais: cadastro, obrigatoriedade, datas impossíveis/futuras, colisão, repetição após perda da resposta, ficha/QR decodificado, edição sem rotação, autorização, desativação e progresso preservado. O navegador foi testado com API real e PostgreSQL local isolado: cadastro, ficha, cópia, PDF, lista, edição, situação, persistência após recarregar e entrada pelo código. Não foram criados alunos fictícios no Supabase remoto.

## Arquivos da etapa

- `frontend/src/pages/ManageStudents.tsx`: validação, data máxima, bloqueio e identificador estável do envio.
- `frontend/src/pages/AdminStudentDetails.tsx`, `frontend/src/types/admin.ts`: nascimento e responsável na consulta dos dados.
- `frontend/src/admin.css`: fieldset do formulário de alunos.
- `backend/src/student-validation.ts`, `backend/src/management.ts`: validação e recuperação segura do envio.
- `backend/src/management.test.ts`, `supabase/tests/management.test.mjs`: testes ampliados.
- `supabase/migrations/202610190004_cadastro_alunos.sql`: proteção transacional contra repetição.

As fichas e o login reutilizam `StudentAccessCard`, `StudentLogin`, `/return` e os mecanismos de sessão existentes.
