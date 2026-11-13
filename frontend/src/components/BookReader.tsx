import {useEffect,useLayoutEffect,useRef,useState} from 'react';
import {ArrowLeft,ArrowRight,CheckCircle2} from 'lucide-react';
import {BookPageViewport,type PageView,type PageViewportHandle} from './BookPageViewport';
import {pageElements} from '../services/book-pages';
import type {BookPage} from '../types/management';
import '../storybook.css';

type Turn={from:number;to:number;forward:boolean;phase:'saving'|'turning';snapshot:HTMLElement;scroll:number};
function PaperDecoration(){return <svg className="storybook-margin-art" viewBox="0 0 44 120" aria-hidden="true" focusable="false"><path d="M30 116C9 90 37 59 18 7" fill="none" stroke="#849843" strokeWidth="2"/><g fill="#8fa64b"><path d="M25 99C3 99 4 83 8 79C20 79 27 89 25 99Z"/><path d="M22 81C39 82 43 68 37 64C27 64 21 72 22 81Z"/><path d="M23 56C5 56 3 43 8 38C18 39 24 47 23 56Z"/><path d="M21 32C37 32 39 20 35 15C24 16 19 23 21 32Z"/></g><g fill="#e5be70"><circle cx="13" cy="108" r="3"/><circle cx="34" cy="51" r="2"/></g></svg>;}
export function BookReader({pages,index,busy,onPage,onComplete}:{pages:BookPage[];index:number;busy:boolean;onPage:(index:number)=>void|Promise<unknown>;onComplete:()=>void}){
 const [turn,setTurn]=useState<Turn|null>(null),[error,setError]=useState('');
 const root=useRef<HTMLDivElement>(null),locked=useRef(false),mounted=useRef(true),timer=useRef<ReturnType<typeof setTimeout>|undefined>(undefined);
 const snapshotHost=useRef<HTMLDivElement>(null);
 useLayoutEffect(()=>{if(!turn||!snapshotHost.current)return;snapshotHost.current.replaceChildren(turn.snapshot);const content=turn.snapshot.querySelector<HTMLElement>('.storybook-sheet-content');if(content)content.scrollTop=turn.scroll;},[turn]);
 const viewport=useRef<PageViewportHandle>(null);
 const [view,setView]=useState<PageView>({id:'',part:0,count:1,ready:false});
 const warmed=useRef(new Set<string>());
 const current=Math.min(Math.max(index,0),Math.max(0,pages.length-1));
 useEffect(()=>{for(const page of pages.slice(Math.max(0,current-1),current+2)){for(const element of pageElements(page)){if(element.type!=='image'||!element.image||warmed.current.has(element.image))continue;warmed.current.add(element.image);const image=new Image();image.decoding='async';image.src=element.image;void image.decode?.().catch(()=>{warmed.current.delete(element.image!);});}}},[pages,current]);
 useEffect(()=>{mounted.current=true;return()=>{mounted.current=false;clearTimeout(timer.current);};},[]);
 useLayoutEffect(()=>{
  const workspace=root.current?.closest<HTMLElement>('.reading-adventure');if(!workspace)return;
  let frame=0;const fit=()=>{cancelAnimationFrame(frame);frame=requestAnimationFrame(()=>{workspace.classList.add('reader-viewport');const top=workspace.getBoundingClientRect().top+window.scrollY;workspace.style.setProperty('--reader-available',Math.max(240,(window.visualViewport?.height??window.innerHeight)-top)+'px');});};
  fit();window.addEventListener('resize',fit);window.visualViewport?.addEventListener('resize',fit);
  return()=>{cancelAnimationFrame(frame);window.removeEventListener('resize',fit);window.visualViewport?.removeEventListener('resize',fit);workspace.classList.remove('reader-viewport');workspace.style.removeProperty('--reader-available');};
 },[]);
 const visible=current,last=current===pages.length-1,disabled=busy||!!turn;
 const ready=view.id===pages[current]?.id&&view.ready,lastPart=ready&&view.part===view.count-1;
 function forward(){if(disabled||locked.current||!ready)return;if(viewport.current?.next())return;if(last)void complete();else void navigate(current+1);}
 function backward(){if(disabled||locked.current||!ready)return;if(viewport.current?.previous())return;void navigate(current-1);}
 async function navigate(next:number){
  if(locked.current||busy||next<0||next>=pages.length||Math.abs(next-current)!==1)return;
  const sheet=root.current?.querySelector<HTMLElement>('.storybook-spread>.storybook-sheet');if(!sheet)return;
  const snapshot=sheet.cloneNode(true) as HTMLElement;
  snapshot.setAttribute('aria-hidden','true');snapshot.inert=true;
  const scroll=sheet.querySelector<HTMLElement>('.storybook-sheet-content')?.scrollTop??0;
  const transition:Turn={from:current,to:next,forward:next>current,phase:'saving',snapshot,scroll};
  locked.current=true;setError('');setTurn(transition);
  try{
   await onPage(next);if(!mounted.current)return;
   setTurn({...transition,phase:'turning'});
   await new Promise<void>(resolve=>{timer.current=setTimeout(resolve,window.matchMedia('(prefers-reduced-motion: reduce)').matches?0:240);});
  }catch{if(mounted.current)setError('Não foi possível virar a página. Tente novamente; seu progresso está preservado.');}
  finally{if(mounted.current){setTurn(null);locked.current=false;root.current?.querySelector<HTMLElement>('.storybook-spread .storybook-sheet-content')?.focus({preventScroll:true});}}
 }
 async function complete(){if(locked.current||busy||!last||!lastPart)return;locked.current=true;setError('');try{await onComplete();}catch{setError('Não foi possível concluir a leitura. Tente novamente.');}finally{if(mounted.current)locked.current=false;}}
 if(!pages.length)return <p>Este livro ainda não possui páginas.</p>;
 function sheet(pageIndex:number){const page=pages[pageIndex];return <article key={pageIndex} className={'storybook-sheet '+(pageIndex%2?'sheet-right':'sheet-left')} aria-label={'Página '+(pageIndex+1)}><PaperDecoration/><BookPageViewport key={page.id} ref={viewport} page={page} onView={setView}/><span className="storybook-folio" aria-hidden="true">{pageIndex+1}</span></article>;}
 return <div ref={root} className="digital-book physical-book storybook-reader is-single" onKeyDown={e=>{if(e.target instanceof HTMLElement&&e.target.closest('button,input,textarea,select'))return;if(e.key==='ArrowRight'||e.key==='PageDown'){e.preventDefault();forward();}if(e.key==='ArrowLeft'||e.key==='PageUp'){e.preventDefault();backward();}}}>
  <div className="storybook-cover" aria-busy={disabled}><div className="storybook-spread" role="group" aria-label="Página do livro">{sheet(visible)}</div>
   {turn&&<div className={'storybook-turn '+(turn.forward?'turn-forward':'turn-backward')+' turn-'+turn.phase} aria-hidden="true"><div className="storybook-turn-leaf"><div ref={snapshotHost} className="storybook-turn-front"/></div></div>}
  </div>
  {error&&<p className="storybook-error" role="alert">{error}</p>}
  <nav className="digital-book-navigation storybook-navigation" aria-label="Páginas do livro">
   <button type="button" className="club-button secondary" aria-label="Página anterior" title="Página anterior" disabled={disabled||!ready||(current===0&&view.part===0)} onClick={backward}><ArrowLeft size={24} aria-hidden="true"/><span>Voltar</span></button>
   <span className="storybook-page-counter" role="status" aria-live="polite" aria-atomic="true">Página {(turn?.from??current)+1} de {pages.length}{!turn&&ready&&view.count>1&&<small className="storybook-part-counter">Parte {view.part+1} de {view.count}</small>}<span className="sr-only">{turn?' — virando a página':''}</span></span>
   {last&&lastPart?<button type="button" className="club-button" disabled={disabled} aria-label="Concluir leitura" title="Concluir leitura" onClick={()=>void complete()}><span className="storybook-complete-label">Concluir leitura</span><CheckCircle2 size={24} aria-hidden="true"/></button>:<button type="button" className="club-button" disabled={disabled} aria-label="Próxima página" title="Próxima página" onClick={forward}><span>Avançar</span><ArrowRight size={24} aria-hidden="true"/></button>}
  </nav>
 </div>;
}
