import {useLayoutEffect,useRef} from 'react';
import type {ComponentPropsWithoutRef} from 'react';

function fitContent(element:HTMLTextAreaElement){
 element.style.height='auto';
 const style=getComputedStyle(element);
 const borders=parseFloat(style.borderTopWidth)+parseFloat(style.borderBottomWidth);
 element.style.height=`${element.scrollHeight+borders}px`;
}

export function AutoGrowingTextarea(props:ComponentPropsWithoutRef<'textarea'>){
 const ref=useRef<HTMLTextAreaElement>(null);
 useLayoutEffect(()=>{if(ref.current)fitContent(ref.current);},[props.value]);
 useLayoutEffect(()=>{
  const element=ref.current;if(!element)return;
  let width=element.getBoundingClientRect().width;
  const observer=new ResizeObserver(()=>{
   const nextWidth=element.getBoundingClientRect().width;
   if(nextWidth!==width){width=nextWidth;fitContent(element);}
  });
  observer.observe(element);
  return ()=>observer.disconnect();
 },[]);
 return <textarea {...props} ref={ref} style={{...props.style,boxSizing:'border-box',overflowY:'hidden',resize:'none'}}/>;
}
