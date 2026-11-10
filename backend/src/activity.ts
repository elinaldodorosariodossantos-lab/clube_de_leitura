export const levels = {facil:10,medio:15,dificil:20};
export const activity = {id:'passarinho',title:'O passarinho e a árvore',level:'facil' as const,age:'6 a 10 anos',content:'Era uma vez um passarinho chamado Léo que vivia em uma árvore perto de uma escola. Todas as manhãs, ele cantava para as crianças. Certo dia, encontrou um pequeno ninho caído no chão. Com a ajuda de outros pássaros, encontrou um lugar seguro para o ninho. Léo ficou feliz porque ajudou sua família.',questions:[
{id:1,prompt:'Qual era o nome do passarinho que aparecia todos os dias na escola?',options:['Léo','Pedro','Tico','Azulão']},
{id:2,prompt:'O que o passarinho encontrou no chão certo dia?',options:['Uma folha seca','Um pequeno ninho','Uma semente','Um brinquedo']},
{id:3,prompt:'Quem ajudou o passarinho a encontrar um lugar seguro para o ninho?',options:['Os alunos da escola','Outros pássaros','O professor','As crianças']},
{id:4,prompt:'Qual foi o sentimento do passarinho no final da história?',options:['Triste','Com medo','Feliz','Cansado']},
{id:5,prompt:'Qual é a principal mensagem do texto?',options:['Que os pássaros cantam mais alto que as crianças.','Que ajudar o outro faz bem e pode deixar todos felizes.','Que a escola é um lugar perigoso.','Que os ninhos devem ficar no chão.']}]};
const key=[0,1,1,2,1];
export function score(answers:Record<string,number>) {
 if(activity.questions.some(q=>!Number.isInteger(answers[q.id])||answers[q.id]<0||answers[q.id]>3)) throw new Error('Responda às cinco questões.');
 const details=activity.questions.map((q,i)=>({...q,selected:answers[q.id],correct:key[i],points:answers[q.id]===key[i]?levels[activity.level]:0}));
 const hits=details.filter(q=>q.points>0).length;
 return {hits,points:hits*levels[activity.level],percentage:hits/5*100,details};
}
