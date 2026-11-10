O administrador e o aluno podem permanecer conectados simultaneamente no mesmo navegador. O aluno entra pelo código ou pela ficha sem precisar encerrar a administração.

O backend usa cookies HttpOnly distintos para administração (`clube_admin_access` e `clube_admin_refresh`) e aluno (`clube_access` e `clube_refresh`). Rotas administrativas selecionam a sessão administrativa; leitura e identificação selecionam a do aluno. `/session`, `/logout` e eventos recebem o contexto da área atual. A autorização continua sendo validada pelos RPCs do Supabase; o contexto apenas seleciona a credencial existente.

Cookies antigos de administrador são separados automaticamente ao abrir a área do aluno. Sair do aluno mantém a administração; sair da administração mantém o aluno. Falhas no código não apagam a sessão administrativa. Nenhuma migration SQL é necessária. Atualize o frontend e reinicie o backend.

Validação automatizada: `npm test`. O teste `backend/src/parallel-sessions.test.ts` verifica sessões simultâneas, cookies antigos, código inválido, autorização e saída independente. A seleção de contexto é testada em `frontend/portal-api.test.mjs`.

Validação manual: entre na administração; abra a entrada do aluno em outra aba ou navegue à página inicial; digite um código válido; volte à administração e confira que ela continua conectada. Saia do aluno e confira novamente o painel administrativo. O roteiro `.qa/parallel-sessions-browser.mjs` verifica esse fluxo no ambiente local isolado `.qa/books-preview.mjs`.
