import type {AdminStudent} from '../types/admin';

const schoolDate=new Intl.DateTimeFormat('en-CA',{timeZone:'America/Fortaleza',year:'numeric',month:'2-digit',day:'2-digit'});
export function overviewDay(value:string){
 const date=new Date(value);if(!Number.isFinite(date.getTime()))return null;
 const parts=schoolDate.formatToParts(date),part=(name:string)=>parts.find(p=>p.type===name)?.value;
 return `${part('year')}-${part('month')}-${part('day')}`;
}
export function registrationSeries(students:AdminStudent[],days:number,updatedAt:string){
 const last=overviewDay(updatedAt);if(!last)return [];
 const end=new Date(last+'T12:00:00Z'),counts=new Map<string,number>();
 for(const student of students){const key=overviewDay(student.createdAt);if(key)counts.set(key,(counts.get(key)??0)+1);}
 return Array.from({length:days},(_,index)=>{
  const date=new Date(end);date.setUTCDate(date.getUTCDate()-(days-1-index));
  const key=date.toISOString().slice(0,10);
  return {day:key,label:key.slice(8)+'/'+key.slice(5,7),count:counts.get(key)??0};
 });
}
export function overviewReaderHighlights(students:AdminStudent[]){
 const readers=students.filter(s=>s.completed>0);
 const highest=[...readers].filter(s=>s.points>0).sort((a,b)=>b.points-a.points);
 const leaders=highest.filter(s=>s.points===highest[0]?.points);
 return {participating:readers.length,participation:students.length?Math.round(readers.length*100/students.length):0,leaders};
}
export const readingTips=[
 'Uma boa história começa com um convite: vamos ler juntos?',
 'Pergunte à criança qual personagem ela gostaria de conhecer.',
 'Reserve um momento do dia para descobrir uma nova história.',
 'Depois da leitura, convide os pequenos a desenhar sua parte favorita.',
 'Ler em voz alta também é uma forma de compartilhar carinho.',
 'Cada criança tem seu ritmo. Celebre cada nova descoberta.',
 'Um livro abre a porta para muitas conversas e aventuras.'
];
