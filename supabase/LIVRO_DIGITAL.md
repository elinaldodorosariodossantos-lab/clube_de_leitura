# Livro digital

O leitor existente BookReader usa CSS 3D com rotateY, perspectiva, frente e verso, sombra animada e virada de 780 ms. BookPageContent continua exibindo somente o texto e a imagem cadastrados. Em telas grandes, imagem e texto ficam em duas faces visuais conectadas; no celular, em uma folha. A ordem salva das paginas permanece igual.

O endpoint atual salva o progresso. Concluir leitura continua acionando a etapa de perguntas, com as mesmas validacoes e pontuacao do banco. Nenhuma migracao, permissao ou dependencia foi adicionada.

Controles bloqueados durante a virada e o envio; setas do teclado com foco no livro; indicador anunciado; prefers-reduced-motion reduz o movimento; proxima imagem precarregada. Textos extensos podem exigir rolagem vertical para preservar a legibilidade.

Validacao: build completo, testes existentes e navegador com 1, 3, 5 e 12 paginas, imagens de proporcoes diferentes, texto curto e longo, avanco/volta, cliques repetidos, retomada apos recarga, conclusao e larguras 1440, 768, 390 e 320. A retomada visual foi exercitada com fixture local; persistencia real e bloqueio de conclusao continuam cobertos pelos testes SQL existentes.

QA reproduzivel: node .qa/prepare-book-fixture.mjs; iniciar Vite na porta 5198 e Chrome CDP na 9244; node .qa/book-flip-browser.mjs. As fixtures nao fazem parte do aplicativo publicado.

## Ajuste de viewport

BookReader mede a altura disponivel abaixo do cabecalho real e observa redimensionamentos. student-theme.css organiza cabecalho compacto, miolo flexivel e navegacao inferior. A imagem usa somente a altura restante, com object-fit contain.

Verificado no navegador: 1920x1080, 1366x768, 1280x720, 1024x768, 768x1024, 390x844, 360x740 e 740x360. Conteudo curto, titulo, nivel, etapas e controles cabem sem rolagem. Texto excessivo e detectado com fonte minima de 18px: aviso solicita divisao editorial em paginas menores e todo o original permanece acessivel, mesmo que nesse caso excepcional seja necessaria rolagem. Nao se oculta excesso nem se modifica cadastro ou snapshots.
