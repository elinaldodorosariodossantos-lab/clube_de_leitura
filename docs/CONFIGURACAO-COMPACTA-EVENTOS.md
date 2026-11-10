# Quantidades de histórias por idade

Na terceira página do evento, cada linha contém idade, quantidades de Fácil, Médio e Difícil e ações de adicionar/remover. Zero significa que o nível não será utilizado: ao salvar, ele é omitido do array `levels`, como já exige o banco. Cada idade precisa de pelo menos um nível com quantidade positiva.

O botão abaixo de cada quantidade positiva abre o conjunto de histórias daquele nível. Selecione histórias suficientes para a quantidade por aluno. O painel consulta somente histórias publicadas compatíveis com a idade e o nível. As outras linhas permanecem compactas.

Números negativos, fracionários e idades duplicadas são recusados. Alterar/remover uma idade ou desativar um nível com histórias selecionadas solicita confirmação. Eventos distribuídos também solicitam confirmação; a mudança afeta a configuração futura, preservando atribuições, respostas e pontuações anteriores.

Não há nova tabela ou migração. A interface reutiliza `eventos_leitura.configuracoes`, `evento_alunos.configuracao` e o RPC `clube_eventos`. O sorteio continua verificando nascimento, nível liberado, elegibilidade e quantidade. Atualizar a página não refaz o sorteio.

## Arquivos

- `frontend/src/components/EventAgeStories.tsx`: linhas e seleção de histórias sob demanda.
- `frontend/src/services/eventAges.ts`: atualização independente das quantidades e conversão de zero para nível ausente.
- `frontend/src/events.css`: layout responsivo.
- `frontend/event-ages.test.mjs`: quantidades iguais/diferentes, zero e valores inválidos.
- `supabase/tests/event-ages.test.mjs`: persistência e distribuição com três quantidades independentes.
- `.qa/event-compact-browser.mjs`: verificação no navegador com banco local isolado.

## Como testar

1. Crie um evento e avance até histórias. Configure 5 anos com 5/5/5 e outra linha com 6 anos e 8/5/3. Confira que uma quantidade não altera as demais.
2. Selecione conjuntos elegíveis suficientes no botão abaixo de cada quantidade. Com conjunto insuficiente, o evento não pode ser salvo/distribuído. O sistema não usa histórias de outra idade para completar.
3. Coloque zero em um nível. Ele deixa de participar dos novos envios. Tente uma idade repetida e quantidade negativa ou fracionária: devem ser recusadas.
4. Salve, atualize a página e edite novamente: confira os valores e os conjuntos.
5. Envie a alunos com nascimento compatível e níveis liberados. Confira as quantidades atribuídas, entre novamente e confirme que a seleção permanece igual. Remova uma configuração já distribuída e confirme que os resultados continuam no histórico.

Testes automatizados: `node --test frontend/event-ages.test.mjs supabase/tests/event-ages.test.mjs supabase/tests/age-access.test.mjs`. A compilação é verificada com `npm run build -w frontend`.
