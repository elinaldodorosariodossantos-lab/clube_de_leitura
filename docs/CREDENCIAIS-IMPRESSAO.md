# Credenciais para impressão

Em **Escolas → Turmas**, use **Gerar credenciais** na linha da turma. O diálogo já seleciona a turma e o ano letivo. Confirme em **Gerar credenciais** para baixar o PDF. Em **Escolas → Listar → Credenciais**, escolha todos os alunos da escola ou uma turma.

O PDF usa A4 vertical, três colunas e duas linhas, com margens de 10 mm e espaços de 4 mm para recorte. Cada cartão tem borda preta, fundo branco, escola, QR Code, link completo de acesso, código, nome em maiúsculas e turma/ano. Os textos se ajustam ao espaço reservado. Os QR Codes têm 600 pixels e margem branca própria. Imprima em tamanho real (100%), sem cabeçalho ou rodapé adicional.

São consultados todos os alunos não excluídos vinculados à escola e, quando selecionada, à turma, independentemente da paginação da tabela. O PDF da escola agrupa os alunos por ano letivo e turma, em ordem de nome. A última página contém somente os cartões necessários.

A geração reutiliza `clube_escolas('credentials', ...)`, as tabelas `escolas`, `turmas`, `alunos`, `perfis` e as credenciais cifradas existentes em `clube_private.acessos`. A autorização administrativa e os filtros continuam no RPC. A decifragem ocorre somente no servidor. Não são criados códigos, alunos ou registros durante a impressão. Se uma credencial não puder ser recuperada, a geração falha com uma mensagem, preservando os acessos.

Não há migração nova. O banco precisa ter o módulo Escolas já instalado (`202611050001_modulo_escolas.sql`, incluído em `supabase/instalar-eventos.sql`). A URL pública de acesso continua usando `PUBLIC_APP_URL` ou `APP_ORIGIN` no backend; configure o endereço HTTPS correto antes de imprimir para entrega.

## Validação

- `npm run build` e `npm test`.
- `node --test supabase/tests/school-management.test.mjs`: escola/turma corretas, leitura sem alteração das credenciais e bloqueio a usuários sem autorização.
- `backend/src/school-credentials-pdf.test.ts`: 6, 10 e 30 alunos geram 1, 2 e 5 páginas; grade de três colunas por duas linhas; nomes extensos completos; agrupamento por turma; QR Codes extraídos do próprio PDF e decodificados, comparando cada destino com o token existente.
- `.qa/credentials-browser.mjs`, com o servidor local `.qa/books-preview.mjs` e o navegador `.qa/launch-management-browser.mjs 9241`: ação na turma, seleção inicial e download por turma/escola. Usa somente cadastros locais de teste.

Para validar em produção, escolha uma turma com códigos existentes, gere o PDF, confira os nomes e escaneie um QR Code com o celular. Confirme que abre o acesso do aluno correspondente. Repita com uma escola com várias turmas e confira a turma/ano em cada cartão. Nenhum dado de produção é necessário para executar os testes automatizados.
