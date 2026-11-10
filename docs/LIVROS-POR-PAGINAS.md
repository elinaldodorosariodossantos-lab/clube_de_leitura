# Livros manuais por páginas

O cadastro de **Histórias** agora permite montar livros manualmente. Não há geração de texto ou imagem, integração de IA ou serviço pago de geração.

## Instalação

Execute o arquivo completo `supabase/instalar-eventos.sql` no SQL Editor do Supabase. Ele aplica apenas etapas ausentes, em uma transação. Em um banco com todas as etapas anteriores instaladas, também é possível executar somente `supabase/migrations/202610230004_livros_paginas.sql`.

Reinicie o backend e atualize o frontend após a instalação. A migração não foi executada no Supabase remoto por esta implementação.

A lixeira da lista de histórias usa também `202610230005_exclusao_historias.sql`, já incluída no instalador. A exclusão pede confirmação, remove a história da lista e a inativa para novas leituras. Os arquivos de imagem, perguntas, snapshots, eventos distribuídos e resultados permanecem armazenados. Histórias excluídas não podem ser republicadas pelos controles de situação ou edição.

## Uso e teste manual

1. Em Histórias, cadastre título, autor opcional, nível e idade. Em **Páginas do livro**, clique em **Adicionar página** quantas vezes precisar.
2. Escreva o texto e envie uma imagem PNG, JPEG ou WebP de até 5 MB, ou escolha uma das imagens disponíveis. Altere ou remova a imagem individualmente.
   Com texto e imagem preenchidos, escolha uma das três prévias: imagem acima, lado a lado ou página emoldurada. O modelo é salvo individualmente no JSON da página e acompanha seus snapshots; não requer outra migration. O leitor utiliza o mesmo componente visual das prévias. No celular, o modelo lado a lado se organiza verticalmente para manter a legibilidade.
3. Use as setas para reordenar páginas. A numeração acompanha a posição. A lixeira remove a página; páginas já publicadas ou utilizadas pedem confirmação.
4. Use **Salvar rascunho** para continuar depois, inclusive com páginas ou perguntas incompletas. Título, nível e idade continuam necessários. Reabra o cadastro e confira ordem, texto, imagens e perguntas.
5. Complete as páginas e perguntas, ative a história e salve. Cada página publicada precisa de texto ou imagem; as perguntas precisam de alternativas completas e gabarito válido. A capa única deixou de ser um campo do editor. Capas existentes são preservadas.
6. Entre como aluno, leia uma página por vez e teste Voltar/Avançar. Recarregue a tela na segunda página: ela deve ser retomada. Na última página, **Concluir leitura** abre as perguntas.
7. Responda e finalize. Confira pontuação e histórico. Repita em celular e tablet, e em evento com distribuição por idade e sorteio.
8. Edite um livro após iniciar uma tentativa ou distribuir um evento. A tentativa e o evento já distribuído devem continuar mostrando sua versão anterior, com suas imagens e gabaritos.

## Estrutura e permissões inspecionadas

Foram inspecionadas as migrações de `public.textos`, `questoes`, `tentativas`, `respostas`, jornadas e eventos; os RPCs de gestão/leitura; `clube_private.conteudos_tentativas`, `evento_conteudos` e os gabaritos privados; e as políticas e uploads do bucket `clube-capas`.

A implementação adapta a tabela existente `public.textos`: `paginas_livro` é um array JSONB ordenado de `{id, text, image}`. Assim uma história contém qualquer quantidade de páginas sem criar outro módulo de cadastro. A tabela privada `clube_private.rascunhos_livros` conserva perguntas incompletas e seus gabaritos exclusivamente para o administrador. `paginas_publicadas` registra se o livro já foi publicado, inclusive depois de desativado.

`public.tentativas.pagina_atual` e `pagina_maxima` guardam a posição e o avanço sequencial. O RPC valida propriedade da tentativa, aluno ativo, período do evento, índice existente e avanço antes de liberar as perguntas.

Os arrays de páginas são capturados nos snapshots existentes, tanto no início de uma tentativa como na distribuição de um evento. Histórias e snapshots antigos são convertidos em uma página usando seu próprio texto e capa, sem buscar conteúdo atual para reescrever o histórico.

As imagens usam o upload existente e URLs públicas permanentes do Supabase Storage. Novos uploads recebem nomes únicos e `upsert:false`. Remover uma imagem ou página não apaga o arquivo do bucket, pois versões anteriores podem depender dele. A biblioteca lista os arquivos com paginação. Não são usados URLs assinados temporários nem URLs `blob:` persistidos.

Os novos campos permanecem sob as políticas RLS existentes. Escritas continuam exclusivamente pelos RPCs de administrador e leitura; não foram concedidas permissões diretas adicionais. O bucket mantém suas políticas de administrador e os gabaritos permanecem privados. As operações de salvar e remover páginas são transacionais.

## Arquivos principais

- Editor existente: `frontend/src/pages/ManageStories.tsx`; componentes `BookPagesEditor.tsx` e `BookReader.tsx` em `frontend/src/components/`.
- Leitura: `frontend/src/components/ReadingActivity.tsx`, `frontend/src/hooks/useReading.ts`, `frontend/src/pages/StudentHome.tsx`.
- Tipos e estilos: `frontend/src/types/management.ts`, `frontend/src/types/portal.ts`, `frontend/src/admin.css`.
- API: `backend/src/management.ts`, `backend/src/reading.ts`; validação HTTP em `backend/src/management.test.ts`.
- Banco: migration `202610230004_livros_paginas.sql`, instalador e seu gerador `.qa/prepare-events-installer.mjs`.
- Testes: `supabase/tests/book-pages.test.mjs`, `.qa/books-preview.mjs`, `.qa/books-browser.mjs`.

## Validação automatizada

```sh
npm run build
npm test
node --test --test-concurrency=1 supabase/tests/*.test.mjs
```

O teste de banco usa PostgreSQL isolado via PGlite em `.qa/postgres`, sem criar alunos no Supabase remoto. Cobre rascunhos, publicação inválida, índices, avanço, retomada, reordenação, remoção confirmada, snapshots de tentativas/eventos, respostas e pontuação. A suíte HTTP cobre upload, biblioteca restrita ao administrador e validação de páginas. O teste no navegador usa o servidor local isolado `.qa/books-preview.mjs`, porta 5195, e um navegador com CDP na porta 9241; as imagens também são isoladas, sem upload remoto.
