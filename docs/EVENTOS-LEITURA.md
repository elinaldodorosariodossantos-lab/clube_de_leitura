# Eventos de Leitura — Clube da Leitura 2026

Para perguntas com quantidades variáveis de alternativas, aplique também `202610230002_alternativas_dinamicas.sql`, incluída no instalador atualizado. Consulte `docs/PERGUNTAS-ALTERNATIVAS.md` para a edição e as verificações.

## Instalação no Supabase

O código está implementado no repositório; nenhuma migração foi executada automaticamente no banco remoto.

Para instalar, copie **todo** o conteúdo de `supabase/instalar-eventos.sql` no SQL Editor do projeto Supabase e execute. Esse instalador verifica e aplica somente as etapas ausentes de gestão (`202610190003`), proteção do cadastro (`202610190004`), eventos (`202610200001`) e configurações por idade (`202610230001`). Ele é transacional e pode ser executado novamente após sucesso. As migrações anteriores de progressão/sequência precisam estar instaladas; o script avisa se a coluna de sequência está ausente.

Se os eventos já estão instalados, execute somente `supabase/migrations/202610230001_eventos_idades.sql`, uma vez, ou use o instalador atualizado. Não execute depois a mesma migração individual novamente. Não é necessário executar o setup inicial ou apagar registros. Sem essa atualização, a API bloqueia a nova configuração com uma mensagem indicando a migração necessária.

Continuam necessários: autenticação anônima habilitada, `SUPABASE_URL`/`SUPABASE_ANON_KEY` no backend e uma conta não anônima com `perfis.papel='admin'`. As capas reutilizam o bucket `clube-capas` com PNG/JPEG/WebP de até 5 MB e suas políticas administrativas. Nenhuma chave service_role é necessária no frontend.

Após instalar, reinicie a API caso ela tenha sido iniciada sem modo watch e atualize o navegador.

## Uso

Abra `/administrador` e entre em **Eventos de Leitura** (`#/admin/eventos`). O menu de **Histórias** permanece como biblioteca de conteúdo, com as funcionalidades anteriores.

1. Clique **Cadastrar evento**. Preencha nome, descrição, início/fim e situação. A capa é opcional.
2. Em **Histórias do evento**, use **Adicionar idade** para configurar idades individuais de 4 a 19 anos, conforme os limites existentes do cadastro. Idades duplicadas são impedidas. Habilite Fácil, Médio e/ou Difícil para cada idade.
3. Em cada combinação de idade e nível, selecione o conjunto de histórias publicadas elegíveis e informe **Histórias por aluno**. A lista consulta o banco e mostra título, autor, nível, faixa e situação; os contadores mostram disponíveis e selecionadas. A quantidade deve ser inteira, positiva e não ultrapassar o conjunto selecionado. Uma idade sem nível habilitado impede salvar.
4. Salve. Use o ícone de envio para abrir os destinatários. A idade é calculada pelo nascimento na data inicial do evento (Fortaleza). O filtro inicial mostra alunos ativos de uma idade configurada com ao menos um nível habilitado já liberado pelas regras pedagógicas. Idades intermediárias não cadastradas e alunos sem nascimento não são elegíveis. Cada aluno recebe as quantidades apenas dos níveis já liberados no momento do envio.
5. Pesquise e filtre por escola, série ou idade exata. Selecione individualmente ou todos dos filtros. Confira a disponibilidade por idade/nível antes de confirmar. Histórias insuficientes bloqueiam o envio, inclusive se foram despublicadas depois de salvar. O servidor revalida o lote inteiro e persiste os sorteios individualmente.
6. A mesma tela de destinatários apresenta o relatório por idade e nível: alunos, histórias atribuídas, conclusões e pontos reais. O cartão do estudante mostra a idade de referência e as quantidades recebidas por nível.

Alunos já associados aparecem marcados como **Já enviado**. Repetir o envio preserva as seleções anteriores. Ajustar os filtros não apaga as seleções manuais feitas nas outras páginas; o contador representa todos os selecionados.

No painel do aluno, **Meus eventos de leitura** mostra somente eventos atribuídos, ativos e no período. O botão abre diretamente a primeira história pendente; respostas são salvas a cada questão e a conclusão leva à próxima história. Os níveis e o percurso anterior continuam disponíveis de forma independente.

## Datas, edição e histórico

O formulário usa o fuso do navegador e transmite timestamps com fuso ao servidor. Os cartões exibem Fortaleza. O início é inclusivo; o encerramento é exclusivo. Um evento ativo no futuro fica **Programado** e, após o fim, **Encerrado**. É possível preparar destinatários antes do início; isso não autoriza iniciar uma leitura fora do período.

Editar um evento com destinatários exige confirmação. Nome, descrição, capa, período e ativação são atualizados para o evento. O conjunto sorteado, a ordem, o nível autorizado, a referência etária e a versão do conteúdo/perguntas/pontos já enviados permanecem preservados por participante. A nova configuração vale para novos destinatários. Não há novo sorteio ao entrar, editar ou reenviar.

A seleção prefere histórias que o aluno ainda não concluiu. Cada combinação é usada antes de repetir quando há opções suficientes para a mesma idade/nível; não se repete uma história dentro da seleção. Ao esgotar as combinações, repetir um conjunto entre alunos é permitido. A ordem sorteada pode variar. Eventos legados mantêm o modo anterior até serem editados; ao abrir o formulário, a faixa antiga vira blocos individuais por idade. Salvar o formulário usa sorteio individual para novos destinatários e preserva todas as distribuições antigas.

Remover uma idade ou desabilitar um nível de evento distribuído exige confirmação sobre o impacto futuro. A confirmação de salvamento também protege as distribuições já existentes. Fazer aniversário, alterar a data de nascimento, atualizar a página ou reenviar não muda a idade capturada, histórias, perguntas, respostas ou pontos do participante. Este formulário não substitui seleções já distribuídas.

Inativar ou arquivar bloqueia consultas do evento disponível e novas operações da atividade, mantendo progresso e pontos. Resultados já concluídos continuam no histórico pessoal. Apagar exige confirmação: sem participantes, remove apenas evento e vínculos de configuração; com participantes, arquiva. Não há exclusão em cascata de respostas, tentativas ou pontuações.

## Banco e segurança

São reutilizados alunos, perfis, escolas, textos, questões, gabaritos, tentativas, respostas e snapshots de tentativas. As novas relações são:

- `eventos_leitura`: configuração e período.
- `evento_historias`: biblioteca e ordem configuradas.
- `evento_alunos`: destinatários únicos e configuração pedagógica autorizada.
- `evento_leituras`: sequência individual, única por participante/texto, e vínculo à tentativa existente.
- `clube_private.evento_conteudos`: snapshot privado de texto, questões e gabaritos capturado ao enviar.

A migração `202610230001` reutiliza essas relações e suas políticas RLS: adiciona `eventos_leitura.configuracoes` (idades, níveis, conjuntos e quantidades), `evento_alunos.idade_referencia` e `evento_alunos.configuracao` (sorteio capturado). Não cria tabelas duplicadas. As associações continuam em `evento_leituras`, com as mesmas constraints de unicidade e snapshots privados.

`tentativas.evento_participante_id` separa o contexto do evento da jornada. A contagem administrativa valida respostas e deduplica por aluno/contexto/texto, permitindo conclusões legítimas do mesmo texto em eventos diferentes sem duplicar os pontos de um reenvio ou de uma mesma tentativa.

Todas as tabelas novas têm RLS; não há leitura/gravação direta concedida aos clientes. O RPC `clube_eventos` verifica o administrador em todas as operações administrativas e a identidade persistente do aluno em `mine`/`enter`. O aluno recebe seu progresso, sem a lista completa de histórias do evento nem os destinatários. O RPC de leitura verifica dono, disponibilidade e contexto a cada operação, inclusive pelo endpoint legado.

Envios são transacionais, travam o evento e cada aluno e usam constraints únicas para impedir participações/leituras duplicadas. Começar/continuar também trava as linhas pertinentes. As correções usam o snapshot privado e são idempotentes. Erros de lote desfazem todo o envio.

## Arquivos

- Migrações e instalador: `supabase/migrations/202610200001_eventos.sql`, `supabase/migrations/202610230001_eventos_idades.sql`, `supabase/instalar-eventos.sql`; gerador em `.qa/prepare-events-installer.mjs`.
- API: `backend/src/events.ts`, integração em `backend/src/portal.ts`.
- Configuração por idade: `frontend/src/components/EventAgeStories.tsx`, `frontend/src/services/eventAges.ts`, `frontend/src/types/events.ts` e `frontend/src/events.css`.
- Disponibilidade e relatório: `frontend/src/components/EventDistributionStatus.tsx` e `frontend/src/pages/ReadingEventRecipients.tsx`.
- Administração: `ReadingEvents.tsx`, `ReadingEventEditor.tsx`, `ReadingEventRecipients.tsx`; menu/rotas em `Admin.tsx`, `adminRoutes.ts`, `types/admin.ts`.
- Aluno: `components/StudentEvents.tsx`, integração em `pages/StudentHome.tsx` e contexto em `types/portal.ts`.
- Compartilhados: `services/events.ts`, `types/events.ts`, `events.css`.
- Testes: `backend/src/events.test.ts`, `frontend/event-ages.test.mjs`, `supabase/tests/event-ages.test.mjs`, `supabase/tests/events.test.mjs`; roteiro de navegador em `.qa/ages-browser.mjs` e ambiente isolado em `.qa/events-preview.mjs`.

## Verificação

Execute `npm run build`, `npm test` e `npm run test:sql`. O teste PostgreSQL carrega as migrações, instala as etapas faltantes pelo instalador, repete a instalação, cria eventos, envia, verifica combinações únicas, retoma respostas, testa isolamento/limites temporais e garante preservação de histórico e pontuação. Os testes de API verificam campos, filtros, sessão e encaminhamento seguro dos comandos.

Os testes de navegador usam uma API Express e PostgreSQL local isolado, sem criar alunos ou eventos fictícios no projeto Supabase real. O visual de referência é aplicado à estrutura; capas e nomes dos eventos reais só aparecem após cadastro, sem eventos demonstrativos na aplicação.

Validação automatizada: build e TypeScript aprovados; 10 testes de backend, 4 de frontend e 7 de PostgreSQL. O novo teste SQL cobre várias idades, vários alunos, níveis desbloqueados, quantidades diferentes, insuficiência, filtros, lotes inválidos sem gravação parcial, snapshots, aniversário, respostas, pontos e relatórios.

No navegador, o ambiente isolado validou adicionar/remover idades, bloquear duplicatas, configurar 1 e 2 histórias por idade, salvar/reabrir, distribuir para dois alunos, apresentar o relatório, entrar como aluno e preservar a leitura após recarregar. Os layouts desktop e celular foram conferidos sem transbordamento horizontal. Capturas locais: `.qa/eventos-idades.png` e `.qa/eventos-idades-celular.png`.

Para conferir manualmente, crie um evento com duas idades existentes nos cadastros e quantidades distintas por nível. Salve e reabra; envie aos alunos elegíveis; entre como aluno e responda uma questão; recarregue e confira a resposta mantida. Edite o evento com confirmação e confira que o relatório e as seleções anteriores permanecem. Despublique uma história do conjunto e confirme o aviso de insuficiência antes do envio. A nova migração ainda precisa ser aplicada no projeto real.
