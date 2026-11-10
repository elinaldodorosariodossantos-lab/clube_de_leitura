Regra atual: 20 pontos por história. Consulte [REESTRUTURACAO_2026.md](REESTRUTURACAO_2026.md). As descrições de 40/3 abaixo documentam a compatibilidade da versão anterior, sem recálculo histórico.

# Conquistas, pontuação e moedas

## Regra vigente

A jornada completa vale **40 pontos**, divididos igualmente entre Fácil, Médio e Difícil. Cada nível vale exatamente `40/3`, aproximadamente **13,33 pontos**. Esta regra substitui a proposta inicial de 40 pontos por nível, conforme a correção solicitada.

Por nível:

- Leituras: `20/3 × histórias concluídas / histórias atribuídas`.
- Questões: `20/3 × acertos corrigidos / questões atribuídas`.
- Erros não ganham a parcela correspondente. Não há débito repetido nem saldo negativo.
- Moedas: o mesmo valor da pontuação final, creditado uma única vez.

Com cinco leituras e dez questões, sete acertos rendem `34/3 ≈ 11,33` pontos, **85%** de aproveitamento e a mesma quantidade de moedas. Todas corretas rendem `40/3 ≈ 13,33`; cinco corretas rendem `30/3 = 10`. Todas erradas ainda rendem os `20/3` das leituras efetivamente concluídas.

Os cálculos usam unidades racionais no PostgreSQL: o divisor é 3 e o máximo de cada nível é 40 unidades. As categorias têm 20 unidades cada. Os totais são somados antes da divisão; assim, três níveis perfeitos são `120/3 = 40`, sem se tornarem 39,99 por arredondamento. A tela arredonda apenas a apresentação para duas casas decimais. Denominadores e quantidades vêm das atribuições e dos snapshots reais, sem arredondar cada pergunta antes de somar.

## Atualização do Supabase

Execute **um** destes caminhos no SQL Editor:

1. `supabase/instalar-eventos.sql` completo, recomendado: aplica somente etapas ausentes e pode ser executado novamente.
2. `supabase/migrations/202611020001_pontuacao_moedas.sql`, caso todas as etapas anteriores, inclusive `202611010001_conquistas_niveis.sql`, já estejam instaladas.

Atualize frontend e backend juntos. A implementação e a migração foram testadas localmente; os testes não modificam o Supabase remoto.

## Preservação e segurança

O registro `pontuacao_legada` identifica níveis que já tinham alguma atividade concluída ou conquista antes desta migração. Esses níveis mantêm o resultado original durante toda a sua conclusão. Não são convertidos para a nova escala e não recebem moedas retroativas. Os demais níveis usam a regra nova, mesmo se já tiverem leituras ainda em andamento. Nenhuma resposta, gabarito, snapshot ou pontuação original de tentativa é reescrita.

Os resultados originais das atividades permanecem disponíveis para auditoria. A avaliação acadêmica nova é registrada por nível em `avaliacoes_niveis`; o total apresentado ao aluno combina essas avaliações com os resultados legados, sem adicionar moedas à nota. As consultas administrativas antigas das tentativas mantêm seus valores de auditoria. O ranking da recompensa usa exclusivamente as avaliações novas na escala vigente.

Eventos continuam usando exclusivamente `evento_leituras` e `evento_conteudos`: não há novo sorteio, alteração de destinatários ou uso do catálogo inteiro como denominador. A sequência comum mantém as histórias obrigatórias compatíveis e as tentativas iniciadas. O nível só termina após todas as leituras, respostas e correções válidas serem confirmadas, seguindo as regras de nascimento e progressão existentes.

`recompensas_moedas` tem chave única por conquista; a conquista já tem unicidade por aluno, contexto e nível. Crédito, avaliação e conclusão ocorrem na mesma transação. `ON CONFLICT DO NOTHING` impede duplicação por repetição ou concorrência. Todas as tabelas novas têm RLS e não permitem acesso direto de alunos. Os RPCs validam a identidade e a propriedade do resultado.

A apresentação automática continua sendo consumida atomicamente por `achievement_claim`, sem localStorage. Recarregar ou entrar novamente não repete a animação. Uma consulta explícita em Meu progresso permite rever a conquista e atualizar o pódio, sem novo crédito.

## Ranking e apresentação

O pódio consulta os três primeiros resultados confirmados do mesmo evento, grupo etário da atribuição e nível. Configurações por idade usam a idade de referência distribuída; eventos por faixa usam seus limites originais. Empates usam a data da conclusão e um identificador estável como desempate. Nomes e escolas vêm dos cadastros reais. Sem participantes suficientes, aparecem somente os existentes; jornadas individuais mostram uma explicação, sem inventar colocados.

A tela segue a referência com céu, raios, troféu vetorial, moedas douradas animadas, confetes, nota, aproveitamento, saldo, acertos e erros, pódio e botão para avançar. O próximo nível é revalidado no banco e a navegação mantém o contexto atribuído, sem login ou sorteio novos. Sem próximo nível disponível, oferece a conclusão da jornada.

O componente é responsivo, tem diálogo acessível, foco contido, saída por teclado e suporte a `prefers-reduced-motion`. Não foram adicionadas dependências de animação.

## Arquivos

- `frontend/src/components/LevelAchievement.tsx`, `RewardArtwork.tsx` e `frontend/src/achievement.css`: visual e acessibilidade.
- `frontend/src/components/ReadingActivity.tsx`, `frontend/src/pages/StudentHome.tsx` e `frontend/src/types/portal.ts`: nota do nível, saldo e revisão de recompensas.
- `backend/src/reading.ts`: consulta autenticada da conquista, além das operações existentes de apresentação e continuação.
- `supabase/migrations/202611020001_pontuacao_moedas.sql`: tabelas, avaliação, crédito, saldo, total acadêmico e ranking.
- `supabase/instalar-eventos.sql` e `.qa/prepare-events-installer.mjs`: instalação idempotente.
- `supabase/tests/rewards.test.mjs`: cálculo, persistência, isolamento e proteção do histórico.
- `supabase/tests/level-achievements.test.mjs`, `event-ages.test.mjs` e `events.test.mjs`: expectativas ajustadas à nova escala; as verificações dos valores originais das respostas permanecem.
- `.qa/rewards-preview.mjs`, `.qa/rewards-browser.mjs` e `.qa/achievements-browser.mjs`: verificação visual isolada.

Tabelas reutilizadas: `tentativas`, `respostas`, `textos`, `questoes`, `alunos`, `jornadas`, `evento_alunos`, `evento_leituras`, `conteudos_tentativas`, `evento_conteudos`, `conquistas_niveis` e `admin_resultados_validos`.

Funções novas principais: `avaliacao_calcular`, `saldo_moedas`, `total_academico` e `ranking_conquista`. `conquista_registrar`, `conquista_json` e o RPC `clube_leitura` recebem camadas compatíveis; correção e autorização anteriores são reutilizadas.

## Validação

```powershell
npm.cmd run build
npm.cmd test
node --test --test-concurrency=1 supabase/tests/*.test.mjs
```

O teste de recompensas cobre cinco histórias/dez questões com dez, sete, cinco e zero acertos; história e questão pendentes; quantidades 3, 4 e 10; novo login; repetição; manipulação; ranking; preservação de resultado anterior à migração; e três níveis somando exatamente 40 pontos e moedas no banco.

Para o fluxo visual com PostgreSQL em memória, sem dados remotos:

```powershell
node .qa/rewards-preview.mjs
# Em outro terminal:
node .qa/launch-management-browser.mjs 9243
# Em outro terminal:
node .qa/rewards-browser.mjs
```

Reinicie o preview antes de repetir: ele mantém as conquistas na sua base local durante a execução. O navegador verifica 1440, 768, 390 e 320 px, navegação e foco por Tab, movimento reduzido, valores reais, recarga sem repetição, avanço e conclusão final. Dados fictícios existem somente nas bases isoladas de teste.

Resultado da validação: compilação aprovada, 42 testes SQL aprovados, 18 testes de backend/frontend aprovados e fluxos visuais aprovados, incluindo o pódio e a revisão sem novo crédito.

## Sessão expirada na conquista (401)

A renovação de sessão compartilha uma única rotação por token entre requisições concorrentes e aceita um cookie de acesso ainda válido após verificação no Supabase. Um 401 real encerra a identificação exibida no frontend e solicita o código do aluno novamente; a conquista pendente continua no banco. O envio de claim não é repetido automaticamente. Essa correção não exige migração SQL.

## Recuperação por código com sessão ativa

A entrada por código valida a credencial numa identidade temporária independente. Isso permite recuperar a tela de entrada quando o servidor ainda tem uma sessão ativa. Somente depois da validação a sessão do aluno é substituída; códigos inválidos preservam o acesso anterior. A sessão administrativa não é encerrada e não há novo cadastro de aluno. Essa correção não exige executar SQL.


## Encerramento completo da jornada

A migração 202611020002_conclusao_jornada.sql acrescenta o resumo final persistido e o certificado sem novo crédito. Consulte FINAL_JORNADA.md para instalação, ranking, regras, auditoria e testes.
