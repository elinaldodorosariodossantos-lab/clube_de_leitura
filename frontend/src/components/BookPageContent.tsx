import {useLayoutEffect,useRef,useState,type CSSProperties,Fragment} from 'react';
import type {BookPage,BookElement} from '../types/management';
import {pageElements,pageTemplate} from '../services/book-pages';
import '../storybook.css';

export const bookLayouts=[{id:'illustration',name:'Imagem acima'},{id:'side',name:'Lado a lado'},{id:'frame',name:'Página emoldurada'}] as const;
function PageImage({element,compact}:{element:BookElement;compact:boolean}){
 const image=useRef<HTMLImageElement>(null);
 const [status,setStatus]=useState<'loading'|'ready'|'error'>('loading');
 useLayoutEffect(()=>{const node=image.current;if(node?.complete&&node.naturalWidth>0)setStatus('ready');},[element.image]);
 return <>{status!=='ready'&&<span className="story-image-status" role="status">{status==='error'?'Ilustração indisponível. Você pode continuar a leitura.':'Carregando ilustração…'}</span>}<img ref={image} src={element.image} alt={compact?'':element.alt??'Ilustração da página'} style={{visibility:status==='ready'?'visible':'hidden'}} onLoad={()=>setStatus('ready')} onError={()=>setStatus('error')}/></>;
}
function emphasis(text:string){return text.split(/(\*\*[^*]+\*\*)/g).map((part,i)=>part.startsWith('**')&&part.endsWith('**')?<strong key={i}>{part.slice(2,-2)}</strong>:<Fragment key={i}>{part}</Fragment>);}
export function BookPageContent({page,compact=false,reading=false}:{page:BookPage;compact?:boolean;reading?:boolean}){
 const template=pageTemplate(page),position=page.imagePosition??(page.layout==='side'?'left':'above');
 const available=pageElements(page).filter(e=>template==='text'?e.type==='text':template==='image'||template==='two-images'?e.type==='image':true);
 const elements=template==='two-images'?available.slice(0,2):available;
 const renderElement=(element:BookElement)=>element.type==='image'?<figure key={element.id} className={'story-image format-'+(element.format??'landscape')+' size-'+(element.size??'large')} style={{'--image-width':(element.size==='custom'?element.width??100:element.size==='small'?35:element.size==='medium'?65:100)+'%','--image-height':(element.height??320)+'px','--image-fit':element.fit??'contain'} as CSSProperties}>{element.image?<PageImage key={element.image} element={element} compact={compact}/>:<span className="story-image-placeholder">Adicione uma ilustração</span>}</figure>:<div key={element.id} className={'story-text text-'+(element.style??'paragraph')} style={{textAlign:element.align??page.align??'left'}}>{(element.text??'').split(/\n+/).map((text,i)=>element.style==='title'?<h2 key={i}>{emphasis(text)}</h2>:element.style==='subtitle'?<h3 key={i}>{emphasis(text)}</h3>:<p key={i}>{emphasis(text)}</p>)}</div>;
 return <div className={'story-page-content template-'+template+' position-'+position+(compact?' is-miniature':'')+(page.layout==='frame'?' legacy-frame':'')} style={{textAlign:page.align??'left'}}>
 {template==='overlay'?<>{elements.filter(e=>e.type==='image').map(renderElement)}<div className="story-overlay-copy">{elements.filter(e=>e.type==='text').map(renderElement)}</div></>:reading&&template==='mixed'&&(position==='left'||position==='right')&&elements.filter(e=>e.type==='image').length===1?<>{elements.filter(e=>e.type==='image').map(renderElement)}<div className="story-reading-copy">{elements.filter(e=>e.type==='text').map(renderElement)}</div></>:elements.map(renderElement)}
 </div>;
}
