> Documento histórico da regra 3. A regra vigente está em [PONTUACAO_OFICIAL_2026.md](PONTUACAO_OFICIAL_2026.md).

# Reestruturação técnica — Clube da Leitura 2026

## Regra oficial atual

Cada história atribuída vale **até 20 pontos**: 10 pela leitura concluída e 10 pelas questões. O valor de uma resposta correta é `10 / quantidade de questões do snapshot da história`. A nota do nível é a soma das histórias atribuídas; seu máximo é `histórias atribuídas × 20`. A jornada soma os níveis, sem teto fixo de 40. Cada ponto confirmado equivale a uma moeda.

Os pontos das histórias são calculados no PostgreSQL. A avaliação por história é persistida na tentativa; a avaliação do nível e o crédito de moedas são confirmados uma única vez quando todas as histórias, leituras e correções atribuídas estiverem concluídas. Antes disso, o resultado parcial pode ser consultado, mas não constitui crédito de um nível concluído. Não há prêmio por abrir uma tela, consultar o ranking ou imprimir um certificado.

| Caso validado | Resultado |
|---|---:|
| 5 histórias, todas lidas e corretas | 100 / 100 |
| 5 histórias, todas lidas, metade correta em cada uma | 75 / 100 |
| 5 histórias, 4 leituras e questões corretas | 90 / 100; nível pendente |
| 3 histórias perfeitas | 60 / 60 |
| 1 história com 5 questões e 3 acertos | 16 / 20 |

O caso de 90 pontos verifica a separação matemática entre leitura e questões em uma fixture administrativa. O fluxo normal não permite responder sem visitar todas as páginas e concluir a leitura, nem finalizar uma tentativa com leitura ou questões pendentes.

## Auditoria e diagnóstico

Foi feito um inventário inicial de 111 arquivos de fontes, migrações e testes, com análise de imports, rotas, serviços, hooks, políticas e funções SQL. A auditoria foi do projeto e do banco reproduzido pelas migrações em PostgreSQL isolado; **não foi uma auditoria dos dados privados do Supabase remoto**.

Problemas encontrados e corrigidos:

1. A regra anterior dividia uma quantidade fixa de pontos pelo nível, não por história. Ela foi isolada como compatibilidade histórica.
2. Relatórios administrativos e o login somavam a coluna de correção antiga, enquanto o painel do aluno exibia a avaliação normalizada. Cadastro, login, painel, visão geral, escolas e detalhes agora usam os helpers oficiais no banco.
3. A seleção comum dependia de um catálogo mutável. Uma publicação posterior podia mudar o denominador e a quantidade exigida. As atribuições novas ficam fixas com conteúdo e gabarito capturados.
4. Eventos e gerenciamento implementavam seus próprios `fetch`, sem o mesmo tratamento de sessão, tentativas e erro. Agora usam o cliente `portalApi`; upload também usa o transporte compartilhado.
5. Consultas GET simultâneas podiam se repetir. Há deduplicação somente enquanto a consulta está em andamento, separada por sessão e contexto aluno/admin. Não existe cache permanente de nota ou saldo. Um envio invalida leituras pendentes para novas consultas.
6. Um segundo clique podia passar antes de o estado React de `busy` atualizar. O hook de leitura usa uma trava síncrona e descarta resultados de uma identidade já desmontada.
7. Uma resposta de atualização podia sobrescrever uma leitura nova ou converter um envio confirmado em falha. Os canais de leitura têm sequenciamento; a atualização secundária do painel não repete a finalização.
8. Requisições não tinham prazo máximo. O transporte compartilhado cancela após 30 segundos; GETs têm até três tentativas e gravações nunca são repetidas automaticamente.
9. A atualização automática das configurações podia trocar o formulário em edição. Ela é pausada enquanto há alterações não salvas, com proteção de saída e recarga manual após salvar.
10. Os pesos antigos das perguntas podiam interferir na correção interna e causar overflow. Em snapshots novos da regra 3, a correção interna utiliza um contador seguro; o peso original é preservado em `originalPoints`. O cálculo acadêmico oficial usa somente os 10 pontos divididos pelas questões da história.
11. Relatórios e Configurações continham apenas páginas “em desenvolvimento”. Foram ligados a funcionalidades reais existentes.
12. Havia componentes sem imports, blocos CSS repetidos e estilos de uma barra removida. Foram removidos somente os usos comprovadamente inexistentes.

## Fonte oficial de cada informação

| Informação | Fonte |
|---|---|
| Identidade e permissões | Supabase Auth, cookies HttpOnly e `portal-auth.ts` |
| Cadastro, escola e idade confiável | `alunos`, `perfis`, `escolas` e helpers de nascimento |
| Catálogo editorial | `textos`, `questoes` e `gabaritos` privados |
| Atribuições comuns novas | `clube_private.atribuicoes_jornada` |
| Atribuições de eventos | `evento_alunos`, `evento_leituras` e `evento_conteudos` existentes |
| Conteúdo efetivamente lido | Snapshot em `conteudos_tentativas` |
| Escolhas do aluno | `respostas` |
| Leitura concluída | `tentativas.leitura_concluida_em`, confirmada após a sequência de páginas |
| Nota da história | `tentativas.avaliacao_historia`, calculada por `historia_avaliar` |
| Nota confirmada do nível | `avaliacoes_niveis` e `conquistas_niveis` |
| Moedas e saldo | `recompensas_moedas` e `saldo_moedas` |
| Total acadêmico | `total_academico` e `pontuacao_contexto` |
| Ranking | Avaliações/conclusões reais, separadas por regra de pontuação |
| Certificado e conclusão final | Resumo imutável em `conclusoes_jornadas` |

As colunas antigas de correção são mantidas para validar e interpretar registros anteriores; elas não são uma segunda fonte acadêmica da regra nova. Para regra 3, relatórios leem a avaliação oficial, não somam diretamente a coluna legada `pontuacao`. O frontend apenas formata valores com duas casas e anima a apresentação. `localStorage` guarda preferência de som e identificadores do módulo legado, não notas, saldo ou progresso oficial.

## Compatibilidade sem recálculo histórico

`regra_pontos` identifica a regra do contexto:

- Contextos que já possuem tentativas, conquistas ou certificados conservam a versão 2, além da identificação legada já existente. Notas, moedas e certificados não são reescritos.
- Contextos novos e existentes ainda completamente intocados usam a versão 3, de 20 por história.
- A mudança de regra não refaz sorteios de eventos. Participantes existentes sem tentativa conservam sua seleção e adotam a regra nova.
- Uma nova jornada de um aluno antigo usa a regra 3. Uma jornada já em andamento termina na regra registrada.
- Rankings não misturam avaliações de regras diferentes.

A migração não contém `DROP TABLE`, exclusão de aluno, remoção de resposta ou recálculo retroativo. Funções `_v2` permanecem privadas porque têm dependências históricas reais. O módulo `/leitura-legada` e suas rotas foram conservados por esse mesmo motivo.

## Alterações no Supabase

Migração: `202611020003_pontuacao_historia.sql`, adicionada ao instalador transacional e idempotente `instalar-eventos.sql`.

- Coluna de regra em jornadas, participantes de eventos e avaliações.
- Marcador de conclusão da leitura e avaliação JSON validada na tentativa.
- Uma tabela privada de atribuições comuns, com FKs, chave única e RLS.
- Constraints de avaliações adaptadas ao máximo por histórias.
- Trigger de recompensa que exige igualdade exata entre avaliação, aluno e crédito.
- Snapshots novos preservam gabarito correto e peso original; o contador interno não participa da nota oficial.
- Helpers de avaliação, total acadêmico, saldo, ranking e relatório atualizados.
- A view administrativa antiga foi preservada como `admin_alunos_historicos`; o nome oficial consulta os totais consolidados.
- Resumos finais já emitidos permanecem imutáveis. Novos resumos e certificados usam os máximos efetivos de cada nível.

Todas as funções privadas novas têm execução revogada de public/anon/authenticated. A tabela de atribuições tem RLS e não permite acesso direto desses papéis. Os RPCs públicos continuam validando o aluno ou administrador. Não há `service_role` no frontend.

## Limpeza e reorganização

Arquivos removidos após verificar referências:

- `frontend/src/pages/Landing.tsx`
- `frontend/src/pages/Identification.tsx`
- `frontend/src/pages/AdminStudents.tsx`
- `frontend/src/components/LevelStoryList.tsx`
- `frontend/src/pages/AdminPlaceholder.tsx` — substituído por telas funcionais

Também foram eliminados 11 blocos CSS exatamente repetidos ou pertencentes à barra já removida, o import React sem uso e uma variável de áudio não utilizada. A verificação TypeScript agora rejeita variáveis e parâmetros sem uso. Não foram removidas dependências necessárias ao fluxo legado, aos testes ou aos serviços atuais.

Páginas e componentes reaproveitados:

- Relatórios usa `SchoolsPanel` com título de participação e filtros reais.
- Configurações reúne `CertificateSettings`, sem duplicá-lo na visão geral.
- O editor informa a regra atual de 20 pontos por história.
- Conquistas e a página final exibem o máximo do banco, sem teto fixo de 40.
- A classificação própria fora do top 3 é separada do pódio.

Não houve troca de framework, nova biblioteca de estado, novo módulo de autenticação ou dependência de produção.

## Validação

Comandos: `npm run build`, `npm test` e `npm run test:sql`. O build inclui a checagem TypeScript estrita, com `noUnusedLocals` e `noUnusedParameters`. Não há lint configurado no projeto; ele não é apresentado como uma verificação executada.

Os testes da regra histórica usam fixtures explicitamente identificadas como versão 2. Os testes novos criam contextos reais de versão 3 e verificam os valores oficiais, perguntas heterogêneas, precisão, atribuições imutáveis, fonte única dos relatórios, permissões e créditos únicos. Os testes não mudam o padrão de produção.

O ambiente `.qa/restructure-preview.mjs` utiliza PostgreSQL isolado em memória e os roteadores reais da aplicação. Os dados de QA não são enviados ao Supabase remoto. Os scripts de navegador verificam aluno, níveis, eventos, pódio, certificado A4, persistência, quatro resoluções e páginas administrativas.

Resultados finais: **70 testes SQL e 36 testes de backend/frontend aprovados**, além do build completo. O navegador validou a jornada de 80 pontos, evento de 85/100, saldo de 165, ranking, certificado PDF A4 de uma página, recarga, quatro larguras (1440, 768, 390 e 320 pixels) e todas as páginas administrativas. A edição de configurações também foi verificada por 21 segundos: nenhuma consulta automática durante a edição, salvamento persistente após recarga e relatórios no celular sem erro HTTP ou JavaScript.

## Aplicação e limites

Execute o instalador completo no SQL Editor do Supabase, ou a migração 003 depois das migrações 001/002 de novembro. A aplicação deve usar frontend e backend compilados da mesma versão. Não foi feita aplicação automática no banco remoto.

O arquivo `auditar-pontuacao-jornadas.sql` é somente de leitura e distingue as versões. Ele permite revisar dados e políticas reais antes de qualquer futura correção histórica. Não foi efetuado saneamento de notas antigas, nem auditoria das configurações externas de produção ou envio a um bucket remoto durante esta tarefa. Uploads, credenciais, autenticação e permissões são cobertos pelos testes locais existentes; as credenciais e políticas efetivas do serviço remoto permanecem sob validação do ambiente de implantação.

## Atualizacao do catalogo (03/11/2026)

A migracao 202611030001_catalogo_atualizado.sql adiciona historias publicadas, obrigatorias, corrigiveis e compativeis com a idade nos niveis comuns ainda sem conquista. O painel sincroniza na consulta de estado e na entrada/finalizacao. Niveis ja premiados permanecem com seus snapshots e notas; novos conteudos desses niveis entram na proxima jornada. Eventos conservam sua selecao individual. Certificados anteriores permanecem consultaveis; uma jornada ampliada recebe novo resumo ao concluir os novos niveis.
