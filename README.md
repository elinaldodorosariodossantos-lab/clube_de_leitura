# Clube da Leitura 2026

Eventos: o administrador vincula escolas e distribui as seleções individuais; o banco valida o acesso pela escola do aluno. [Implantação e validação](supabase/EVENTOS_ESCOLAS.md).

Novas jornadas: somente o administrador pode autorizar o reinício, em Alunos → Detalhes. [Implantação e validação](supabase/REINICIO_ADMINISTRADOR.md).

Regra atual: **10 pontos por leitura concluída + 5 por resposta correta**, nos três níveis, sem teto fixo por nível. Históricos preservam sua regra registrada. [Migração e testes](supabase/PONTUACAO_OFICIAL_2026.md).

## Gerenciamento de alunos e histórias

Cadastro, edição, acesso por QR/link/código de seis caracteres e conteúdo editorial estão documentados no [guia administrativo](docs/GESTAO-ALUNOS-HISTORIAS.md). A nova migração é `202610190003_gestao.sql`, aplicada após as migrações de progressão e sequência.

## Painel do aluno atualizado

O fluxo atual abre a leitura diretamente pelo nível e avança automaticamente pela ordem cadastrada. Veja [a migração e o guia da sequência](docs/SEQUENCIA-LEITURA.md).

Interface conforme a referência, catálogo de histórias e progressão Fácil → Médio → Difícil. Para o banco que já recebeu as quatro migrações anteriores, aplique somente `supabase/migrations/202610190001_progressao.sql`. Consulte [o guia do painel do aluno](PAINEL-ALUNO.md) para regras, segurança, arquivos e testes.

## Administração: indicadores e alunos

O painel usa rotas próprias, indicadores validados no banco e listagem paginada com filtros e detalhes. Aplique `supabase/migrations/202610150002_admin.sql` no banco existente. Consulte [as consultas, os arquivos alterados e a configuração administrativa](docs/ADMINISTRACAO.md).

## Leitura por níveis e retomada

O aluno agora entra diretamente na tela de níveis em `/#/leitura`, com atividade persistente, retomada e ciclos de jornada. Para habilitar no banco existente, aplique apenas `supabase/migrations/202610150001_leitura.sql`. Veja [o guia de leitura e os arquivos alterados](docs/LEITURA-NIVEIS.md). Essa implementação substitui os estados de preparação descritos na documentação da etapa 1.

## Portal de apresentação, alunos e administração — etapa 1

A página principal agora abre o portal público com cadastro e retorno de alunos, área pessoal e administração protegida. Consulte [as instruções da etapa 1](docs/ETAPA-1.md) para configurar o Supabase, executar a migração nova e autorizar administradores. Sem as credenciais, a apresentação funciona, mas o cadastro real permanece indisponível. O módulo de leitura anterior foi preservado em `/leitura-legada`; as instruções abaixo descrevem esse módulo.

React + TypeScript + Vite, Express + TypeScript e Supabase PostgreSQL/Auth. O gabarito não faz parte dos arquivos do frontend. As respostas são salvas antes de avançar; pontuação e correção só são reveladas após a conclusão. Os pontos de leitura são confirmados na conclusão da leitura; os acertos são corrigidos no backend ao finalizar as questões.

## Executar localmente

Requer Node.js 22.12+ (validado com Node 24). Na raiz:

```powershell
npm.cmd install
npm.cmd run dev
```

Abra http://127.0.0.1:5173. A API usa a porta 3001. Sem configuração, o modo demonstração grava em `backend/data/attempts.json`. A identidade da demonstração é um identificador do navegador, não uma autenticação real. Use somente com dados fictícios e no computador local. Produção rejeita modo demo.

```powershell
npm.cmd run build
npm.cmd test
```

## Conectar ao Supabase

1. Copie `backend/.env.example` para `backend/.env` e `frontend/.env.example` para `frontend/.env`.
2. No backend defina `DATA_MODE=supabase`, `SUPABASE_URL` e `SUPABASE_ANON_KEY`. No frontend configure `VITE_SUPABASE_URL` e `VITE_SUPABASE_ANON_KEY`. São a URL e a chave pública do mesmo projeto. Nenhuma chave service_role é necessária.
3. Execute a migração `supabase/migrations/202610120001_clube.sql` e depois `supabase/seed.sql` pelo SQL Editor do projeto Supabase. A migração cria novas tabelas e não apaga dados; exige que esses nomes ainda não existam.
4. Crie o usuário em Authentication e, como administrador do banco, cadastre seu perfil e aluno usando o UUID real:

```sql
insert into public.perfis(id,nome) values ('UUID_DO_USUARIO','Nome do aluno');
insert into public.alunos(perfil_id,faixa_etaria) values ('UUID_DO_USUARIO','6 a 10 anos');
```

5. Reinicie o projeto e entre com e-mail e senha. O servidor valida o token no Supabase e encaminha o contexto autenticado à função `clube_api`.

## Segurança e expansão

A função SQL deriva o aluno de `auth.uid()`, valida a questão e alternativa, bloqueia a tentativa durante alterações e calcula os pontos em uma transação. Finalizar novamente retorna o resultado já persistido. Não aceita pontuação, aluno ou gabarito enviados pelo cliente. Tabelas têm RLS e apenas leitura autorizada; alterações passam pela função. O gabarito fica em schema privado sem permissões para usuários. Professores e administradores não recebem acesso cruzado automaticamente: não há painel ou autorização por turma implementados. Os níveis estão centralizados em `niveis`; somente a atividade fácil foi cadastrada.

O frontend mantém o identificador da tentativa e recupera respostas e resultado após recarregar. O modo demo serializa alterações e grava o arquivo com substituição atômica; use uma única instância do backend nesse modo. Em produção sirva o frontend e encaminhe `/api` para o Express por um proxy HTTPS; não use o servidor Vite de desenvolvimento como hospedagem.

## Verificação

Os quatro testes passaram: pontuação para todos os números de acertos, alternativas inválidas, respostas incompletas, ausência de gabarito na atividade pública e integração da API local (isolamento entre usuários, conclusão duplicada, bloqueio de edição após conclusão e persistência após reinício). Frontend e backend compilam. A integração Supabase requer as credenciais e execução da migração; valide com duas contas que cada uma só consegue acessar suas tentativas. A migração e suas políticas não foram executadas em um banco real nesta sessão. Não houve verificação visual em navegador. Não foi fornecida referência visual anexada: a interface segue as orientações de cores, cartões e acessibilidade do pedido.
# Livros manuais por páginas

O cadastro de histórias inclui páginas ordenadas com texto, upload e seleção de imagens, rascunhos e leitor sequencial com progresso salvo. Aplique `202610230004_livros_paginas.sql` após as migrações anteriores, ou execute o instalador atualizado `supabase/instalar-eventos.sql`. Consulte o [guia de instalação, arquivos e testes](docs/LIVROS-POR-PAGINAS.md).

