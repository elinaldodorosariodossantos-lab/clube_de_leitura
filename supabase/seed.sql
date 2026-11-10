begin;
insert into public.textos(id,titulo,conteudo,faixa_etaria,nivel) values('passarinho','O passarinho e a árvore','Era uma vez um passarinho chamado Léo que vivia em uma árvore perto de uma escola. Todas as manhãs, ele cantava para as crianças. Certo dia, encontrou um pequeno ninho caído no chão. Com a ajuda de outros pássaros, encontrou um lugar seguro para o ninho. Léo ficou feliz porque ajudou sua família.','6 a 10 anos','facil') on conflict do nothing;
insert into public.questoes(id,texto_id,enunciado,alternativas) values
(1,'passarinho','Qual era o nome do passarinho que aparecia todos os dias na escola?','["Léo","Pedro","Tico","Azulão"]'),
(2,'passarinho','O que o passarinho encontrou no chão certo dia?','["Uma folha seca","Um pequeno ninho","Uma semente","Um brinquedo"]'),
(3,'passarinho','Quem ajudou o passarinho a encontrar um lugar seguro para o ninho?','["Os alunos da escola","Outros pássaros","O professor","As crianças"]'),
(4,'passarinho','Qual foi o sentimento do passarinho no final da história?','["Triste","Com medo","Feliz","Cansado"]'),
(5,'passarinho','Qual é a principal mensagem do texto?','["Que os pássaros cantam mais alto que as crianças.","Que ajudar o outro faz bem e pode deixar todos felizes.","Que a escola é um lugar perigoso.","Que os ninhos devem ficar no chão."]') on conflict do nothing;
insert into clube_private.gabaritos values(1,0),(2,1),(3,1),(4,2),(5,1) on conflict do nothing;
commit;
