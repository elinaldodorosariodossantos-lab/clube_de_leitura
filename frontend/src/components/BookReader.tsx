import {useEffect,useLayoutEffect,useRef,useState} from 'react';
import {ArrowLeft,ArrowRight,CheckCircle2} from 'lucide-react';
import {BookPageContent} from './BookPageContent';
import type {BookPage} from '../types/management';
import '../storybook.css';

type Turn={from:number;to:number;forward:boolean};
export function BookReader({pages,index,busy,onPage,onComplete}:{pages:BookPage[];index:number;busy:boolean;onPage:(index:number)=>void|Promise<unknown>;onComplete:()=>void}){
 const [wide,setWide]=useState(()=>window.matchMedia('(min-width: 960px)').matches),[turn,setTurn]=useState<Turn|null>(null),[error,setError]=useState('');
 const root=useRef<HTMLDivElement>(null),locked=useRef(false),mounted=useRef(true),timer=useRef<ReturnType<typeof setTimeout>|undefined>(undefined);
 const current=Math.min(Math.max(index,0),Math.max(0,pages.length-1)),spread=wide?Math.floor(current/2)*2:current;
 useEffect(()=>{mounted.current=true;const media=window.matchMedia('(min-width: 960px)'),change=()=>setWide(media.matches);media.addEventListener('change',change);return()=>{mounted.current=false;clearTimeout(timer.current);media.removeEventListener('change',change);};},[]);
 useLayoutEffect(()=>{
  const workspace=root.current?.closest<HTMLElement>('.reading-adventure');if(!workspace)return;
  let frame=0;const fit=()=>{cancelAnimationFrame(frame);frame=requestAnimationFrame(()=>{workspace.classList.add('reader-viewport');const top=workspace.getBoundingClientRect().top+window.scrollY;workspace.style.setProperty('--reader-available',Math.max(240,(window.visualViewport?.height??window.innerHeight)-top)+'px');});};
  fit();window.addEventListener('resize',fit);window.visualViewport?.addEventListener('resize',fit);
  return()=>{cancelAnimationFrame(frame);window.removeEventListener('resize',fit);window.visualViewport?.removeEventListener('resize',fit);workspace.classList.remove('reader-viewport');workspace.style.removeProperty('--reader-available');};
 },[]);
 const visible=turn?.from??spread,shown=wide?[visible,visible+1]:[visible],last=spread+(wide?2:1)>=pages.length,disabled=busy||!!turn;
 async function saveThrough(next:number){if(next>current){for(let p=current+1;p<=next;p++)await onPage(p);}else if(next!==current)await onPage(next);}
 async function navigate(next:number){
  if(locked.current||busy||next<0||next>=pages.length)return;locked.current=true;setError('');setTurn({from:spread,to:next,forward:next>spread});
  try{await Promise.all([saveThrough(next),new Promise<void>(r=>{timer.current=setTimeout(r,window.matchMedia('(prefers-reduced-motion: reduce)').matches?0:650);})]);}
  catch{setError('Não foi possível virar a página. Tente novamente; seu progresso está preservado.');}
  finally{if(mounted.current){setTurn(null);locked.current=false;root.current?.querySelector<HTMLElement>('.storybook-sheet-content')?.focus({preventScroll:true});}}
 }
 async function complete(){if(locked.current||busy)return;locked.current=true;setError('');try{await saveThrough(pages.length-1);await onComplete();}catch{setError('Não foi possível concluir a leitura. Tente novamente.');}finally{if(mounted.current)locked.current=false;}}
 if(!pages.length)return <p>Este livro ainda não possui páginas.</p>;
 function sheet(pageIndex:number,animation=false){const page=pages[pageIndex];return <article key={pageIndex} className={'storybook-sheet '+(pageIndex%2?'sheet-right':'sheet-left')+(page?'':' sheet-empty')} aria-label={page?'Página '+(pageIndex+1):'Fim do livro'} aria-hidden={animation||!page?true:undefined}>{page?<><div className="storybook-sheet-content" tabIndex={animation?-1:0}><BookPageContent page={page}/></div><span className="storybook-folio" aria-hidden="true">{pageIndex+1}</span></>:<div className="storybook-end" aria-hidden="true"><CheckCircle2 size={44}/><span>Fim desta aventura</span></div>}</article>;}
 return <div ref={root} className={'digital-book physical-book storybook-reader '+(wide?'is-spread':'is-single')} onKeyDown={e=>{if(e.target instanceof HTMLElement&&e.target.closest('button,input,textarea,select'))return;if(e.key==='ArrowRight'&&!last){e.preventDefault();void navigate(spread+(wide?2:1));}if(e.key==='ArrowLeft'&&spread>0){e.preventDefault();void navigate(Math.max(0,spread-(wide?2:1)));}}}>
  <div className="storybook-cover" aria-busy={disabled}><div className="storybook-spread" role="group" aria-label="Livro de histórias aberto">{shown.map(p=>sheet(p))}</div>
   {wide&&<span className="storybook-spine" aria-hidden="true"/>}
   {turn&&<div className={'storybook-turn '+(turn.forward?'turn-forward':'turn-backward')} aria-hidden="true"><div className="storybook-turn-leaf"><div className="storybook-turn-front">{sheet(turn.forward?Math.min(turn.from+Number(wide),pages.length-1):turn.from,true)}</div><div className="storybook-turn-back">{sheet(turn.to,true)}</div></div></div>}
  </div>
  {error&&<p className="storybook-error" role="alert">{error}</p>}
  <nav className="digital-book-navigation storybook-navigation" aria-label="Páginas do livro">
   <button type="button" className="club-button secondary" aria-label="Página anterior" title="Página anterior" disabled={disabled||spread===0} onClick={()=>void navigate(Math.max(0,spread-(wide?2:1)))}><ArrowLeft size={24} aria-hidden="true"/></button>
   <span className="sr-only" role="status" aria-live="polite">Página {spread+1}{wide&&spread+1<pages.length?' e '+(spread+2):''} de {pages.length}{turn?' — virando a página':''}</span>
   {last?<button type="button" className="club-button" disabled={disabled} aria-label="Concluir leitura" title="Concluir leitura" onClick={()=>void complete()}><CheckCircle2 size={24} aria-hidden="true"/></button>:<button type="button" className="club-button" disabled={disabled} aria-label="Próxima página" title="Próxima página" onClick={()=>void navigate(spread+(wide?2:1))}><ArrowRight size={24} aria-hidden="true"/></button>}
  </nav>
 </div>;
}
