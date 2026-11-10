# Verificação do login do aluno

O primeiro acesso é feito em `/#/aluno`, com nome completo, idade e escola. Após salvar, o aluno recebe seu código e segue para `/#/leitura`. O retorno em outro dispositivo ou depois de sair usa esse código em `/#/retornar`. Nome e escola não substituem o código.

Ao abrir uma rota de leitura sem uma sessão válida, o site apresenta a entrada por código, com link para primeiro cadastro. Com sessão válida, recupera o aluno e seu progresso sem criar outro usuário anônimo. Os tokens de acesso e renovação ficam nos cookies HttpOnly, sem dados pessoais em localStorage.

## Correções em 19/10/2026

- O backend estava parado; foi iniciado novamente para atender o frontend em `http://127.0.0.1:5173`.
- Falhas ao consultar a sessão deixaram de ser ignoradas. A área protegida apresenta o erro com **Tentar novamente**, sem oferecer outro cadastro durante uma falha temporária.
- Falhas transitórias de autenticação preservam os cookies. Sessões inválidas são limpas; vínculos antigos revogados por um retorno em outro dispositivo não deixam o aluno preso no formulário.
- A renovação continua funcionando quando o cookie de acesso expira e o cookie de renovação permanece válido.
- O retorno por código não depende de consultar escolas e limites de idade. Códigos incompletos são validados antes do envio; letras maiúsculas, traços e espaços são normalizados.
- O mesmo identificador de aluno e as respostas salvas são recuperados ao retornar com o código.

Verificações concluídas: TypeScript/compilação, testes da API e PostgreSQL, além do fluxo completo no navegador com base isolada e autenticação simulada. O navegador confirmou um único cadastro de aluno após cadastro, recargas e retorno por código; a nova identidade de autenticação foi criada apenas no retorno explícito após sair. A simulação de indisponibilidade preservou a sessão e recuperou a questão atual pelo botão de nova tentativa. Nenhum dado de criança foi inserido no projeto remoto.

Arquivos: `frontend/src/PortalApp.tsx`, `frontend/src/pages/Identification.tsx`, `backend/src/portal.ts`, `backend/src/portal.test.ts` e este guia.

## Configuração remota verificada

Authentication respondeu com Anonymous Sign-Ins habilitado, e a função `clube_portal` respondeu corretamente. Nenhum cadastro de criança ou conta anônima foi criado no Supabase remoto durante a verificação.

A instalação de `clube_leitura` e `clube_admin` foi confirmada em 19/10/2026 após a aplicação das migrações pelo responsável. Ambas recusam execução com a chave pública sem uma sessão autenticada. A API local também exige login nas rotas de leitura e administração. As migrações correspondentes já aplicadas são:

1. `supabase/migrations/202610150001_leitura.sql` — níveis, atividades e retomada.
2. `supabase/migrations/202610150002_admin.sql` — indicadores e consultas administrativas.

Não reexecute essas migrações nem `setup-clube.sql`. Falta apenas verificar os fluxos autenticados com as contas reais do projeto; a conferência remota não criou alunos nem consultou dados pessoais.
