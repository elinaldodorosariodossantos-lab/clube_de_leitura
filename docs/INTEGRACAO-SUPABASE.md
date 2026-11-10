# Integração Supabase

Projeto configurado: `lbwswawfosddkmhgcoej`. A URL e a chave pública estão em `backend/.env`, ignorado pelo Git. O backend usa `DATA_MODE=supabase`.

Na verificação de 14/10/2026, a conexão com Authentication respondeu HTTP 200. A API informou que `perfis`, `alunos`, `tentativas`, `escolas`, `jornadas` e `clube_portal` não estavam no catálogo. Anonymous Sign-Ins estava desativado. Nenhuma tabela ou conta foi criada remotamente nesta verificação.

## Concluir pelo painel

Atualização: a instalação do banco foi confirmada pela resposta de `clube_portal` e pelas restrições de acesso direto às tabelas. O proxy Vite preserva o `Host` do navegador (`changeOrigin: false`) para a validação de origem nas operações do portal. Há um teste de integração com o proxy real que verifica formulários da mesma origem, bloqueio de origens externas e `APP_ORIGIN` explícito.

1. Abra o SQL Editor do projeto e execute o conteúdo de `supabase/setup-clube.sql`. Esse arquivo aplica as duas migrações em uma transação, sem seed de histórias nem dados fictícios. Uma verificação inicial interrompe a execução caso já existam tabelas do clube; nesse caso, confira o estado e aplique somente as migrações individuais necessárias.
2. Na área Authentication, habilite **Anonymous Sign-Ins**. O aluno usa essa opção para criar uma sessão identificada pelo Supabase, sem e-mail nem senha pessoal.
3. Para a administração, crie uma conta de e-mail/senha em Authentication e conceda o papel `admin` a seu UUID real conforme `docs/ETAPA-1.md`. Não conceda esse papel a uma conta de aluno.
4. Execute a verificação:

```powershell
node backend/scripts/check-supabase.mjs
```

O resultado esperado é `anonymousEnabled: true` e configuração de idade retornada por `clube_portal` e `supabase-js`. As consultas diretas às tabelas podem retornar erro de permissão: isso é esperado porque dados de alunos são acessados somente pelas operações protegidas.

5. Reinicie `npm.cmd run dev` caso o backend ainda esteja usando a configuração antiga. Teste cadastro, salve o código, saia e retorne. Use apenas dados de teste enquanto valida a integração. Depois, teste uma conta comum sem papel administrativo e a conta administrativa autorizada.

A chave pública permite acessar a API, mas não concede direitos para executar DDL ou alterar configurações do projeto. Essas etapas precisam de uma sessão administrativa no painel Supabase ou de uma conexão autorizada ao banco. Não é necessário divulgar uma chave privada no chat para executar as instruções pelo painel.
