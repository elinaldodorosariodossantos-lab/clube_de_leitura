# Interface administrativa

Modernização visual aplicada ao painel existente. Login, logout, proteção de formulários, permissões, rotas e telas de gestão continuam usando a implementação anterior. Não há migração ou configuração adicional.

- `admin-modern.css` limita o novo tema ao painel autenticado. O leitor e o login conservam seus estilos.
- Os quatro indicadores vêm de `/admin/overview`, sem variações fictícias.
- O gráfico apresenta **cadastros por dia**, pois a consulta atual fornece a data de cadastro, mas não uma série global de conclusões. Os períodos de 7, 30 e 90 dias usam o horário de Fortaleza.
- As atividades recentes mostram os últimos alunos cadastrados. Não são simuladas publicações ou conquistas sem registros disponíveis.
- O carregamento usa todas as páginas de `/admin/students` antes de calcular as séries e os destaques. Falha ou mudança na paginação mostra uma opção para tentar novamente, sem apresentar uma amostra como se fosse o total.
- Os destaques apresentam participação em leituras e maior pontuação registrada, indicando empates. Não criam ou modificam rankings, metas, pontos ou recompensas.
- Os atalhos abrem as rotas atuais de Histórias, Alunos, Eventos e Relatórios. O cadastro permanece nos formulários existentes.
- O menu móvel possui fechamento por botão, fundo ou Escape, contenção do foco e devolução do foco ao botão de abertura.

Verificação: build de produção, testes de datas e destaques e navegação local com respostas de teste nas APIs existentes, incluindo paginação, erros, dados vazios, login/logout e larguras de 320 a 1920 pixels. Nenhuma conta ou dado de produção é usado nesses testes.
