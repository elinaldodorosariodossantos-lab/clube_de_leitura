import {useEffect,useLayoutEffect,useRef,useState} from 'react';
import {ArrowLeft,ArrowRight,CheckCircle2} from 'lucide-react';
import {BookPageContent} from './BookPageContent';
import type {BookPage} from '../types/management';
import '../book-reader.css';
type Turn={from:number;to:number;direction:'forward'|'backward'};
export function BookReader({pages,index,busy,onPage,onComplete}:{pages:BookPage[];index:number;busy:boolean;onPage:(index:number)=>void|Promise<unknown>;onComplete:()=>void}){
 const current=Math.min(Math.max(index,0),Math.max(0,pages.length-1)),[turn,setTurn]=useState<Turn|null>(null),[imageLoading,setImageLoading]=useState(false);
 const book=useRef<HTMLDivElement>(null),[tooLong,setTooLong]=useState(false);
 const locked=useRef(false),timer=useRef<ReturnType<typeof setTimeout>|undefined>(undefined),mounted=useRef(true);
 useEffect(()=>{mounted.current=true;return()=>{mounted.current=false;clearTimeout(timer.current);};},[]);
 useEffect(()=>{let active=true;const source=pages[current]?.image;setImageLoading(!!source);if(source){const image=new Image();image.onload=image.onerror=()=>{if(active)setImageLoading(false);};image.src=source;}const next=pages[current+1]?.image;if(next){const preload=new Image();preload.src=next;}return()=>{active=false;};},[current,pages[current]?.image,pages[current+1]?.image]);
 useLayoutEffect(()=>{
  const root=book.current,workspace=root?.closest<HTMLElement>('.reading-adventure');if(!root||!workspace)return;
  let frame=0;const fit=()=>{cancelAnimationFrame(frame);frame=requestAnimationFrame(()=>{
   const top=workspace.getBoundingClientRect().top+window.scrollY;
   const bottomGap=workspace.classList.contains('reading-focused')?0:12;
   workspace.style.setProperty('--reader-available',Math.max(200,(window.visualViewport?.height??window.innerHeight)-top-bottomGap)+'px');
   workspace.classList.add('reader-viewport');
   const paper=root.querySelector<HTMLElement>('.digital-book-page'),text=paper?.querySelector<HTMLElement>('.book-composition-text');
   if(!paper||!text)return;
   const available=Math.max(80,(window.visualViewport?.height??window.innerHeight)-root.getBoundingClientRect().top-(root.querySelector<HTMLElement>('.digital-book-navigation')?.offsetHeight??56)-28);
   let font=Math.min(28,Math.max(18,window.innerHeight*.03));text.style.setProperty('--reader-font',font+'px');
   while(font>18&&text.scrollHeight>available*.6){font--;text.style.setProperty('--reader-font',font+'px');}
   setTooLong(text.scrollHeight>available);
  });};
  const observer=new ResizeObserver(fit);observer.observe(root);window.addEventListener('resize',fit);window.visualViewport?.addEventListener('resize',fit);fit();
  return()=>{cancelAnimationFrame(frame);observer.disconnect();window.removeEventListener('resize',fit);window.visualViewport?.removeEventListener('resize',fit);workspace.classList.remove('reader-viewport');workspace.style.removeProperty('--reader-available');};
 },[current,pages,imageLoading]);
 async function navigate(next:number){
  if(locked.current||busy||next===current||!Number.isInteger(next)||next<0||next>=pages.length)return;
  locked.current=true;setTurn({from:current,to:next,direction:next>current?'forward':'backward'});
  const reduced=window.matchMedia('(prefers-reduced-motion: reduce)').matches;
  try{
   await Promise.all([Promise.resolve(onPage(next)),new Promise<void>(resolve=>{timer.current=setTimeout(resolve,reduced?80:800);})]);
  }catch{
   // O indice confirmado permanece na pagina anterior quando o salvamento falha.
  }finally{if(mounted.current){setTurn(null);locked.current=false;}}

 }
 const visible=turn?.to??current,page=pages[visible],disabled=busy||!!turn;
 if(!page)return <p>Este livro ainda não possui páginas.</p>;
 return <div ref={book} className={"digital-book physical-book"+(tooLong?" book-content-long":"")} onKeyDown={event=>{if(event.target instanceof HTMLElement&&event.target.closest('button,input,textarea,select'))return;if(event.key==='ArrowRight'&&current<pages.length-1){event.preventDefault();navigate(current+1);}if(event.key==='ArrowLeft'){event.preventDefault();navigate(current-1);}}}>
 <div className="book-stage" tabIndex={0} role="region" aria-label="Livro digital. Use as setas para virar as páginas." aria-busy={disabled}>
 <article className="club-card digital-book-page book-paper" aria-label={'Página '+(visible+1)}><BookPageContent key={page.id+page.image} page={page}/><span className="book-folio" aria-hidden="true">{visible+1}</span></article>
 {turn&&<div className={'book-turn book-turn-'+turn.direction} aria-hidden="true"><div className="book-leaf"><div className="book-leaf-front book-paper"><BookPageContent page={pages[turn.from]}/></div><div className="book-leaf-back book-paper"><BookPageContent page={pages[turn.to]}/></div></div></div>}
 </div>
 {tooLong&&<p className="book-length-notice" role="status">Este texto precisa ser dividido em páginas menores pela escola para caber nesta tela com letra legível. O conteúdo completo está preservado, sem cortes.</p>}
 <nav className="digital-book-navigation" aria-label="Páginas do livro"><button type="button" className="club-button secondary" disabled={disabled||current===0} onClick={()=>navigate(current-1)}><ArrowLeft size={18}/>Voltar</button><span className="sr-only" role="status" aria-live="polite" aria-atomic="true">Página {current+1} de {pages.length}</span>{current<pages.length-1?<button type="button" className="club-button" disabled={disabled} onClick={()=>navigate(current+1)}>Avançar<ArrowRight size={18}/></button>:<button type="button" className="club-button" disabled={disabled} onClick={()=>{if(locked.current||busy)return;locked.current=true;onComplete();timer.current=setTimeout(()=>{locked.current=false;},800);}}>Concluir leitura<CheckCircle2 size={18}/></button>}</nav><p className="sr-only" role="status">{turn?'Virando a página…':busy?'Salvando progresso…':imageLoading?'Carregando ilustração…':''}</p>
 </div>;
}
