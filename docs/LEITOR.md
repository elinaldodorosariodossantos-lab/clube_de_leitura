# Composição das histórias

Em **Histórias → Cadastrar / Editar**, expanda cada página para escolher seu modelo, alinhamento e posição das imagens. Adicione blocos de texto ou imagem, arraste pela alça ou use as setas para reordená-los. A prévia acompanha as alterações antes de salvar. Elementos ocultos por um modelo continuam guardados e reaparecem ao mudar de modelo.

Textos podem ser títulos, subtítulos, parágrafos ou destaques. Use `**palavras**` para negrito. Imagens usam o upload e a biblioteca existentes; podem ter descrição acessível, formato, tamanho e ajuste sem cortes ou preenchimento.

O leitor mostra duas páginas em telas a partir de 960 pixels e uma por vez em telas menores. As setas e o teclado viram páginas com animação; a preferência do dispositivo por movimento reduzido é respeitada. Textos longos permanecem completos, com rolagem dentro da folha.

As opções ficam no JSON `paginas_livro` já existente. Os campos `id`, `text`, `image` e os modelos legados são mantidos. O backend valida as opções e recompõe `text` e `image` a partir dos elementos para preservar a compatibilidade com o SQL. Não é necessária migração de banco. Snapshots de leituras iniciadas e eventos distribuídos permanecem preservados.

A mudança exige o frontend e o backend atualizados juntos; os módulos locais da Edge Function são preparados com `node backend/scripts/prepare-edge.mjs`. **Nenhum commit ou envio é executado automaticamente.**
