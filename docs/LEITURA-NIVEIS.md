# Tela de níveis e continuidade da leitura

> A modernização do painel e a progressão obrigatória substituem a seleção livre descrita neste guia histórico. Consulte [a atualização do painel do aluno](../PAINEL-ALUNO.md) e aplique a nova migração `202610190001_progressao.sql` depois das anteriores.

## Ativar no Supabase existente

**Atualização de 19/10/2026:** o responsável aplicou a migração, e a presença de `clube_leitura` foi confirmada pela API, com bloqueio de acesso sem autenticação. Não reexecute no projeto já atualizado; as instruções a seguir descrevem a instalação original.

Em uma instalação ainda não atualizada, execute **somente** `supabase/migrations/202610150001_leitura.sql` no SQL Editor do projeto já configurado. Não execute novamente `setup-clube.sql` nem as migrações anteriores. A migração foi testada em PostgreSQL local e posteriormente aplicada pelo responsável no projeto remoto.

A migração acrescenta `etapa` e `questao_atual` à tabela existente `tentativas` e cria a função protegida `clube_leitura`. As tabelas `alunos`, `jornadas`, `textos`, `questoes`, `respostas` e o schema privado de gabaritos são reutilizados. Inclui três leituras iniciais com cinco questões cada. Conteúdos já cadastrados são preservados com `ON CONFLICT DO NOTHING`. Não são inseridos alunos, pontuações ou resultados fictícios.

Novos textos: **A biblioteca do bairro** (médio) e **Uma decisão sobre a água** (difícil). O fácil reutiliza **O passarinho e a árvore**. Os novos textos são conteúdo pedagógico inicial, passível de revisão pela equipe.

Se houver uma tentativa legada aberta sem ciclo, uma delas é vinculada à jornada aberta existente, preservando respostas. Se houver várias tentativas legadas abertas, elas continuam preservadas; apenas uma é adotada pelo fluxo novo. Resultados históricos sem ciclo continuam visíveis como histórico anterior.

## Rotas e comportamento

- `/#/aluno` e `/#/retornar`: cadastro ou identificação pelo código individual.
- Ao reabrir a página pública com uma sessão de aluno válida, o sistema também segue diretamente para os níveis, sem outro cadastro.
- `/#/leitura`: diretamente os três níveis, saudação e progresso. O cartão do código aparece depois dos níveis, sem bloquear a entrada.
- `/#/atividade/<uuid>`: texto, questões ou resultado da tentativa autorizada. A etapa e a próxima questão vêm do banco, inclusive após recarregar.
- `/#/jornada`: níveis e situação do ciclo atual.
- `/#/progresso`: totais reais e resultados das leituras de todos os ciclos.
- `/#/perfil`: dados do próprio aluno.
- `/#/admin` e `/leitura-legada`: preservados.

Não existe restrição por idade para escolher um nível. Com uma atividade aberta, o botão **Continuar de onde parei** retoma essa atividade; a seleção de outra fica disponível após concluí-la. Respostas são gravadas antes do avanço, e a posição é a primeira questão não respondida. Após todas as respostas, o aluno finaliza explicitamente para ver correção e pontos. Na etapa de questões, **Reler o texto** preserva respostas e posição.

Concluir o conteúdo disponível nos três níveis fecha o ciclo. **Revisar meus resultados** abre o histórico. **Iniciar uma nova jornada** cria outro ciclo, explicitamente, sem apagar respostas ou pontos. Entrar ou recarregar não cria ciclos nem repete leituras concluídas. Havendo mais de um texto ativo por nível, cada escolha abre a próxima leitura ainda pendente no ciclo.

## Sessão e autorização

A sessão Supabase existente é recuperada e renovada pelos cookies HttpOnly. Somente cadastro ou retorno explícito iniciam autenticação anônima; carregar páginas não cria usuários. O UUID persistente do aluno é resolvido pelo vínculo privado com a sessão autenticada, inclusive depois de retornar com código em outro dispositivo.

`clube_leitura` verifica esse vínculo em cada chamada, filtra tentativas pelo aluno e serializa mutações com bloqueio da linha do aluno. O cliente não fornece aluno, pontos ou gabaritos. A conclusão é idempotente; respostas de tentativas concluídas são imutáveis. Novos ciclos só são aceitos após a conclusão anterior. Funções auxiliares privadas não têm execução pública e o acesso direto às tabelas continua sujeito aos privilégios e à RLS existentes.

## Executar e verificar

```powershell
npm.cmd run build
npm.cmd test
```

Para testar o SQL isoladamente, sem tocar no banco real, instale o PostgreSQL temporário de teste (sem adicionar dependência à aplicação):

```powershell
npm.cmd install --no-save --package-lock=false --prefix .qa/postgres @electric-sql/pglite
npm.cmd run test:sql
```

O teste SQL executa as três migrações, registra dois alunos apenas na base local e verifica escolha de nível fora da faixa recomendada, retomada, troca de sessão por código, isolamento, gabarito privado, correção, idempotência, conclusão dos três níveis e preservação dos resultados ao criar outro ciclo. Os testes da API verificam validação de operações e que consultas não criam identidades anônimas adicionais.

A revisão no navegador usou uma instância isolada com autenticação simulada e PostgreSQL local, sem criar alunos no Supabase remoto. Foram exercitados cadastro → níveis, escolha do difícil com idade de 7 anos, respostas → recarga → retomada, conclusão dos três níveis, novo ciclo e conservação dos pontos calculados e do histórico. Desktop e celular de 390 px foram inspecionados, sem overflow horizontal. Capturas em `.qa/reading-levels-desktop.png`, `.qa/reading-levels-mobile.png`, `.qa/reading-resumed.png` e `.qa/reading-complete.png` são exclusivamente dessa base de teste.

Após aplicar a migração remota, reinicie o backend se estiver usando `npm.cmd start -w backend` (modo estável). Para desenvolvimento com compilação automática, use `npm.cmd run dev` na raiz.

## Arquivos criados ou modificados

- `frontend/src/PortalApp.tsx`: rota protegida da atividade.
- `frontend/src/pages/StudentHome.tsx`: entrada direta nos níveis, progresso, histórico e perfil.
- `frontend/src/components/ReadingLevels.tsx`: cartões, retomada e ações de ciclo.
- `frontend/src/components/ReadingActivity.tsx`: texto, respostas salvas e resultados.
- `frontend/src/hooks/useReading.ts`: carregamento e operações persistentes.
- `frontend/src/types/portal.ts`, `frontend/src/reading.css`: contratos e apresentação responsiva.
- `backend/src/reading.ts`, `backend/src/portal.ts`: rotas autenticadas e chamada RPC.
- `backend/scripts/check-supabase.mjs`: diagnóstico da instalação da função de leitura.
- `backend/src/portal.test.ts`: cobertura das rotas e da sessão.
- `supabase/migrations/202610150001_leitura.sql`: persistência, conteúdo e ciclo.
- `supabase/tests/reading.test.mjs`, `package.json`: teste PostgreSQL local e comando `test:sql`.

A validação local não substitui a aplicação e verificação da migração no Supabase conectado.
