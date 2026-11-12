import {forwardRef,useImperativeHandle,useLayoutEffect,useRef,useState} from 'react';
import type {BookPage} from '../types/management';
import {readingParts,type ReadingBlock,type ReadingPart} from '../services/reader-fit';
import {BookPageContent} from './BookPageContent';

export type PageView={id:string;part:number;count:number;ready:boolean};
export type PageViewportHandle={next:()=>boolean;previous:()=>boolean};
type Props={page:BookPage;onView:(view:PageView)=>void};

export const BookPageViewport=forwardRef<PageViewportHandle,Props>(function BookPageViewport({page,onView},ref){
 const viewport=useRef<HTMLDivElement>(null),content=useRef<HTMLDivElement>(null),notify=useRef(onView);
 notify.current=onView;
 const [parts,setParts]=useState<ReadingPart[]>([]),[part,setPart]=useState(0);
 const current=useRef({part:0,count:0});current.current={part,count:parts.length};
 useImperativeHandle(ref,()=>({
  next(){if(current.current.part+1>=current.current.count)return false;current.current.part++;setPart(current.current.part);return true;},
  previous(){if(current.current.part<=0)return false;current.current.part--;setPart(current.current.part);return true;}
 }),[]);
 useLayoutEffect(()=>{
  const host=viewport.current,canvas=content.current;if(!host||!canvas)return;
  let alive=true,frame=0;
  const measure=()=>{
   if(!alive||host.clientHeight<1||host.clientWidth<1)return;
   const composition=canvas.querySelector<HTMLElement>('.story-page-content');if(!composition)return;
   const height=Math.max(1,host.clientHeight-8),figures=Array.from(composition.querySelectorAll<HTMLElement>('.story-image'));
   const texts=Array.from(composition.querySelectorAll<HTMLElement>('.story-text'));
   const textHeight=texts.reduce((sum,e)=>sum+e.offsetHeight,0);
   composition.classList.toggle('reader-long-overlay',composition.classList.contains('template-overlay')&&textHeight>height-80);
   const style=getComputedStyle(composition),gap=parseFloat(style.gap)||18;
   const side=composition.classList.contains('template-mixed')&&style.display==='grid';
   const overlay=composition.classList.contains('template-overlay');
   const budget=side||overlay?height-48:texts.length?height-Math.min(textHeight,height*.65)-gap*(texts.length+figures.length):height-gap*Math.max(0,figures.length-1);
   const imageHeight=Math.max(32,Math.floor(Math.min(height,Math.max(Math.min(80,height*.25),budget))/Math.max(1,side||overlay?1:figures.length)));
   host.style.setProperty('--reader-image-height',imageHeight+'px');
   host.style.setProperty('--reader-page-height',height+'px');
   const bounds=host.getBoundingClientRect(),offset=host.scrollTop,blocks:ReadingBlock[]=[];
   const append=(rect:DOMRect)=>{if(rect.height>0&&rect.width>0)blocks.push({top:Math.max(0,rect.top-bounds.top+offset),bottom:rect.bottom-bounds.top+offset});};
   for(const figure of figures)append(figure.getBoundingClientRect());
   for(const text of texts){
    const walker=document.createTreeWalker(text,NodeFilter.SHOW_TEXT);let node:Node|null;
    while((node=walker.nextNode())){if(!node.textContent?.trim())continue;const range=document.createRange();range.selectNodeContents(node);for(const rect of Array.from(range.getClientRects()))append(rect);}
   }
   const next=readingParts(blocks,host.clientHeight);
   setParts(old=>JSON.stringify(old)===JSON.stringify(next)?old:next);
   setPart(p=>Math.min(p,next.length-1));
  };
  const schedule=()=>{cancelAnimationFrame(frame);frame=requestAnimationFrame(measure);};
  const observer=new ResizeObserver(schedule);observer.observe(host);observer.observe(canvas);
  host.addEventListener('load',schedule,true);host.addEventListener('error',schedule,true);
  void document.fonts?.ready.then(()=>{if(alive)schedule();});
  measure();
  return()=>{alive=false;cancelAnimationFrame(frame);observer.disconnect();host.removeEventListener('load',schedule,true);host.removeEventListener('error',schedule,true);};
 },[page]);
 useLayoutEffect(()=>{
  const host=viewport.current,visible=parts[part];if(!host||!visible)return;
  host.scrollTop=visible.top;
  host.style.clipPath='inset(0 0 '+Math.max(0,host.clientHeight-visible.height)+'px 0)';
  notify.current({id:page.id,part,count:parts.length,ready:true});
 },[page.id,parts,part]);
 return <div ref={viewport} className="storybook-sheet-content storybook-fit-page" tabIndex={0}>
  <div ref={content} className="storybook-fit-content"><BookPageContent page={page}/></div>
  {parts.length>1&&<div className="storybook-fit-spacer" aria-hidden="true"/>}
 </div>;
});
