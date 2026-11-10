import {useState} from 'react';
import type {BookPage} from '../types/management';
export const bookLayouts=[{id:'illustration',name:'Imagem acima'},{id:'side',name:'Lado a lado'},{id:'frame',name:'Página emoldurada'}] as const;
function PageImage({source,compact}:{source:string;compact:boolean}){
 const [status,setStatus]=useState<'loading'|'ready'|'error'>('loading');
 return <>{status!=='ready'&&<span className="book-image-status" role="status">{status==='error'?'Ilustra\u00e7\u00e3o indispon\u00edvel. Voc\u00ea pode continuar a leitura.':'Carregando ilustra\u00e7\u00e3o\u2026'}</span>}<img src={source} alt={compact?'':'Ilustra\u00e7\u00e3o da p\u00e1gina'} style={{visibility:status==='ready'?'visible':'hidden'}} onLoad={()=>setStatus('ready')} onError={()=>setStatus('error')}/></>;
}
export function BookPageContent({page,compact=false}:{page:BookPage;compact?:boolean}){
 const layout=bookLayouts.some(model=>model.id===page.layout)?page.layout:'illustration';
 return <div className={'book-composition book-layout-'+layout+(compact?' is-miniature':'')}>{page.image&&<div className="book-composition-image"><PageImage key={page.image} source={page.image} compact={compact}/></div>}<div className="book-composition-text digital-book-text">{compact?<p>{page.text}</p>:page.text.split(/\n+/).map((text,index)=><p key={index}>{text}</p>)}</div></div>;
}
