import {useEffect,useLayoutEffect,useRef,useState} from 'react';
import {ArrowLeft,ArrowRight,CheckCircle2} from 'lucide-react';
import {BookPageContent} from './BookPageContent';
import type {BookPage} from '../types/management';
import '../storybook.css';

type Turn={from:number;to:number;forward:boolean};
function PaperDecoration(){return <svg className="storybook-margin-art" viewBox="0 0 44 120" aria-hidden="true" focusable="false"><path d="M30 116C9 90 37 59 18 7" fill="none" stroke="#849843" strokeWidth="2"/><g fill="#8fa64b"><path d="M25 99C3 99 4 83 8 79C20 79 27 89 25 99Z"/><path d="M22 81C39 82 43 68 37 64C27 64 21 72 22 81Z"/><path d="M23 56C5 56 3 43 8 38C18 39 24 47 23 56Z"/><path d="M21 32C37 32 39 20 35 15C24 16 19 23 21 32Z"/></g><g fill="#e5be70"><circle cx="13" cy="108" r="3"/><circle cx="34" cy="51" r="2"/></g></svg>;}
export function BookReader({pages,index,busy,onPage,onComplete}:{pages:BookPage[];index:number;busy:boolean;onPage:(index:number)=>void|Promise<unknown>;onComplete:()=>void}){
 const [turn,setTurn]=useState<Turn|null>(null),[error,setError]=useState('');
 const root=useRef<HTMLDivElement>(null),locked=useRef(false),mounted=useRef(true),timer=useRef<ReturnType<typeof setTimeout>|undefined>(undefined);
 const current=Math.min(Math.max(index,0),Math.max(0,pages.length-1));
 useEffect(()=>{mounted.current=true;return()=>{mounted.current=false;clearTimeout(timer.current);};},[]);
 useLayoutEffect(()=>{
  const workspace=root.current?.closest<HTMLElement>('.reading-adventure');if(!workspace)return;
  let frame=0;const fit=()=>{cancelAnimationFrame(frame);frame=requestAnimationFrame(()=>{workspace.classList.add('reader-viewport');const top=workspace.getBoundingClientRect().top+window.scrollY;workspace.style.setProperty('--reader-available',Math.max(240,(window.visualViewport?.height??window.innerHeight)-top)+'px');});};
  fit();window.addEventListener('resize',fit);window.visualViewport?.addEventListener('resize',fit);
  return()=>{cancelAnimationFrame(frame);window.removeEventListener('resize',fit);window.visualViewport?.removeEventListener('resize',fit);workspace.classList.remove('reader-viewport');workspace.style.removeProperty('--reader-available');};
 },[]);
 const visible=turn?.from??current,last=current===pages.length-1,disabled=busy||!!turn;
 async function navigate(next:number){
  if(locked.current||busy||next<0||next>=pages.length||Math.abs(next-current)!==1)return;locked.current=true;setError('');setTurn({from:current,to:next,forward:next>current});
  try{await Promise.all([Promise.resolve(onPage(next)),new Promise<void>(r=>{timer.current=setTimeout(r,window.matchMedia('(prefers-reduced-motion: reduce)').matches?0:650);})]);}
  catch{setError('Não foi possível virar a página. Tente novamente; seu progresso está preservado.');}
  finally{if(mounted.current){setTurn(null);locked.current=false;root.current?.querySelector<HTMLElement>('.storybook-sheet-content')?.focus({preventScroll:true});}}
 }
 async function complete(){if(locked.current||busy||!last)return;locked.current=true;setError('');try{await onComplete();}catch{setError('Não foi possível concluir a leitura. Tente novamente.');}finally{if(mounted.current)locked.current=false;}}
 if(!pages.length)return <p>Este livro ainda não possui páginas.</p>;
 function sheet(pageIndex:number,animation=false){const page=pages[pageIndex];return <article key={pageIndex} className={'storybook-sheet '+(pageIndex%2?'sheet-right':'sheet-left')+(page?'':' sheet-empty')} aria-label={page?'Página '+(pageIndex+1):'Fim do livro'} aria-hidden={animation||!page?true:undefined}><PaperDecoration/>{page?<><div className="storybook-sheet-content" tabIndex={animation?-1:0}><BookPageContent page={page}/></div><span className="storybook-folio" aria-hidden="true">{pageIndex+1}</span></>:<div className="storybook-end" aria-hidden="true"><CheckCircle2 size={44}/><span>Fim desta aventura</span></div>}</article>;}
 return <div ref={root} className="digital-book physical-book storybook-reader is-single" onKeyDown={e=>{if(e.target instanceof HTMLElement&&e.target.closest('button,input,textarea,select'))return;if(e.key==='ArrowRight'&&!last){e.preventDefault();void navigate(current+1);}if(e.key==='ArrowLeft'&&current>0){e.preventDefault();void navigate(current-1);}}}>
  <div className="storybook-cover" aria-busy={disabled}><div className="storybook-spread" role="group" aria-label="Página do livro">{sheet(visible)}</div>
   {turn&&<div className={'storybook-turn '+(turn.forward?'turn-forward':'turn-backward')} aria-hidden="true"><div className="storybook-turn-leaf"><div className="storybook-turn-front">{sheet(turn.from,true)}</div><div className="storybook-turn-back">{sheet(turn.to,true)}</div></div></div>}
  </div>
  {error&&<p className="storybook-error" role="alert">{error}</p>}
  <nav className="digital-book-navigation storybook-navigation" aria-label="Páginas do livro">
   <button type="button" className="club-button secondary" aria-label="Página anterior" title="Página anterior" disabled={disabled||current===0} onClick={()=>void navigate(current-1)}><ArrowLeft size={24} aria-hidden="true"/><span>Voltar</span></button>
   <span className="storybook-page-counter" role="status" aria-live="polite" aria-atomic="true">Página {current+1} de {pages.length}<span className="sr-only">{turn?' — virando a página':''}</span></span>
   {last?<button type="button" className="club-button" disabled={disabled} aria-label="Concluir leitura" title="Concluir leitura" onClick={()=>void complete()}><span className="storybook-complete-label">Concluir leitura</span><CheckCircle2 size={24} aria-hidden="true"/></button>:<button type="button" className="club-button" disabled={disabled} aria-label="Próxima página" title="Próxima página" onClick={()=>void navigate(current+1)}><span>Avançar</span><ArrowRight size={24} aria-hidden="true"/></button>}
  </nav>
 </div>;
}
