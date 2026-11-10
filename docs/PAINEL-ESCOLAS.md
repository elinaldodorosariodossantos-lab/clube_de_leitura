# Painel Escolas

## Acesso pelo menu

Em **Escolas → Acompanhamento**, o painel reúne os indicadores e a consulta dos alunos. **Listar** mantém o cadastro de escolas e **Turmas** mantém a gestão de turmas existente. Na listagem de escolas, a ação **Acompanhamento** abre os mesmos indicadores com aquela escola selecionada. Abrir um aluno e voltar preserva o grupo e os filtros da consulta.

A integração atual não adiciona tabelas, migrações ou alterações nas permissões. Reutiliza o RPC `clube_escolas`, inclusive a extensão do módulo de escolas e turmas já existente. O painel também continua disponível em Relatórios.

Arquivos desta integração: `frontend/src/pages/Admin.tsx`, `SchoolDirectory.tsx`, `SchoolsPanel.tsx`, `frontend/src/services/adminRoutes.ts` e `frontend/admin-routes.test.mjs`. A navegação é validada em `.qa/schools-navigation-browser.mjs`, além das verificações do painel descritas abaixo.

## Ativar no banco

Execute o arquivo completo `supabase/instalar-eventos.sql` no SQL Editor do Supabase. O instalador verifica as etapas presentes e aplica a nova migração `202610290001_painel_escolas.sql` somente quando necessário. Se todas as migrações anteriores estiverem aplicadas, execute apenas a migração nova, uma única vez.

O banco remoto não foi alterado durante a implementação. Os testes utilizam PostgreSQL local isolado, com PGlite. Depois de aplicar o SQL, use o backend e o frontend atualizados.

## Dados e segurança

Não há tabelas novas. O painel reutiliza:

- `public.alunos`, `public.perfis` e `public.escolas`, com associação por `alunos.escola_id`.
- `public.jornadas`, `public.tentativas`, `public.respostas` e `public.textos`.
- `clube_private.admin_alunos`, `admin_resultados_validos`, `conteudos_tentativas` e `acessos`.

A migração adiciona o RPC `public.clube_escolas(text,jsonb)` e um índice parcial em escola/data de cadastro. A função exige a autorização administrativa existente. Usuários anônimos não têm permissão de execução; alunos autenticados também não passam pela autorização administrativa. As políticas RLS e os fluxos de login, cadastro, eventos e pontuação não foram alterados.

A idade usa a data de nascimento confiável e a data atual de Fortaleza, pelas funções da regra de idade já instalada. A idade manual não é usada. Nascimento ausente/inválido aparece sem idade; esses cadastros permanecem consultáveis.

O código curto é decifrado apenas no backend com a chave já utilizada nas fichas de acesso. O navegador não recebe credenciais cifradas, hashes nem o token longo de acesso. Se a credencial for antiga ou a chave estiver indisponível, aparece “Indisponível”; consulte a ficha no cadastro de alunos. A pesquisa por código requer o código completo, ignora espaços/hífens e compara hashes no banco. Nunca é feita a decifragem de todos os cadastros para pesquisar.

Cadastros excluídos logicamente ficam fora da listagem, como no painel Alunos. Seus históricos continuam armazenados e não são apagados.

## Indicadores e filtros

Selecione os filtros e clique em **Aplicar filtros**. **Limpar filtros** restaura todas as escolas, idades, séries e datas, com ordenação A–Z. Os filtros são combinados no banco antes da paginação de 20 alunos.

- Alunos cadastrados: total correspondente a todos os filtros aplicados.
- Escolas cadastradas: total de escolas existentes, ou uma quando a escola selecionada existe. Para “Sem escola vinculada”, zero. Idade, série e pesquisa não apagam escolas cadastradas deste indicador.
- Atividades concluídas: soma de conclusões validadas dos alunos filtrados. Conclusões duplicadas ou inconsistentes não entram.
- Cadastros no período: alunos filtrados no período de cadastro escolhido; em “Qualquer período”, todo o período.
- Pontos: soma de pontuações validadas desses alunos, exibida acima da tabela.

Os filtros de data se referem ao cadastro do aluno, não à conclusão das atividades. As atividades e pontos são os totais históricos dos alunos encontrados. “Últimos 7 dias” inclui hoje e os seis dias anteriores; “Últimos 30 dias” inclui hoje e os 29 anteriores. Intervalos personalizados incluem os dois dias informados, no fuso de Fortaleza, usando limite superior exclusivo no início do dia seguinte.

Os detalhes reutilizam o painel existente de cadastro, jornadas e progresso. Acrescentam respostas paginadas com enunciado histórico, alternativa escolhida, situação da correção e pontos. Voltar às escolas preserva os filtros aplicados durante a navegação.

## Validação

1. Sem alunos, confirme indicadores zero e estado vazio.
2. Cadastre alunos em duas escolas, com idades e séries diferentes. Verifique o total geral e cada escola.
3. Combine escola, idade, série e nome. Pesquise também pelo código curto completo. Limpe os filtros.
4. Teste hoje, 7 dias, 30 dias e intervalo personalizado. Intervalos invertidos/incompletos são recusados. Cadastros sem escola podem ser consultados pela opção específica.
5. Com mais de 20 alunos, navegue pelas páginas e compare as ordenações por nome e data.
6. Abra os detalhes e confira responsável, nascimento, idade, jornadas, atividades e respostas. Conclua uma leitura real e confira a mesma pontuação na tabela, nos detalhes e nos indicadores.
7. Tente acessar os endpoints sem login ou com uma sessão de aluno: os dados administrativos devem ser negados.

Comandos executados:

```text
npm run build
npm test
node --test --test-concurrency=1 supabase/tests/*.test.mjs
```

Testes específicos: `backend/src/schools.test.ts`, `supabase/tests/schools.test.mjs`, `frontend/admin-routes.test.mjs` e `.qa/schools-browser.mjs`. O teste de navegador usa `.qa/books-preview.mjs` e dados locais, sem criar cadastros no Supabase remoto.

## Arquivos alterados

- `backend/src/schools.ts`, `backend/src/admin.ts`, `backend/src/schools.test.ts`.
- `frontend/src/pages/SchoolsPanel.tsx`, `Admin.tsx`, `AdminStudentDetails.tsx`.
- `frontend/src/services/adminRoutes.ts`, `frontend/src/schools.css`, `frontend/admin-routes.test.mjs`.
- `supabase/migrations/202610290001_painel_escolas.sql`, `supabase/instalar-eventos.sql`, `supabase/tests/schools.test.mjs`.
- `.qa/prepare-events-installer.mjs`, `.qa/books-preview.mjs`, `.qa/schools-browser.mjs`.
