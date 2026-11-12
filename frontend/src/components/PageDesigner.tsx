import {useRef,useState} from 'react';
import {ArrowUp,ArrowDown,Trash2,Upload,Images,GripVertical,Type,ImagePlus,Eye} from 'lucide-react';
import {portalUpload} from '../services/portal';
import {manage} from '../services/management';
import {pageElements,pageProblem,pageTemplate,withPageElements} from '../services/book-pages';
import {BookPageContent} from './BookPageContent';
import {AutoGrowingTextarea} from './AutoGrowingTextarea';
import type {BookPage,BookElement,PageTemplate} from '../types/management';

type Gallery={images:{name:string;url:string}[];nextOffset:number|null};
export const pageTemplates:{id:PageTemplate;name:string;description:string}[]=[
 {id:'mixed',name:'Texto com imagem',description:'Uma ilustração acompanha a leitura.'},
 {id:'text',name:'Somente texto',description:'Espaço para contar a história.'},
 {id:'image',name:'Somente imagem',description:'Uma página para a imaginação.'},
 {id:'two-images',name:'Duas imagens',description:'Duas cenas na mesma página.'},
 {id:'overlay',name:'Texto sobre a imagem',description:'Texto em destaque sobre a ilustração.'}
];
export function PageDesigner({page,onChange,onError,onBusy}:{page:BookPage;onChange:(p:BookPage)=>void;onError:(s:string)=>void;onBusy:(b:boolean)=>void}){
 const [gallery,setGallery]=useState<Gallery>(),[target,setTarget]=useState<string>(),[dragging,setDragging]=useState<string>(),[showPreview,setShowPreview]=useState(true);
 const latest=useRef(page);latest.current=page;
 const elements=pageElements(page),template=pageTemplate(page),problem=pageProblem(page);
 function setElements(next:BookElement[]){onChange(withPageElements(latest.current,next));}
 function patch(id:string,values:Partial<BookElement>){setElements(pageElements(latest.current).map(e=>e.id===id?{...e,...values}:e));}
 function add(type:'text'|'image'){setElements([...elements,{id:crypto.randomUUID(),type,...(type==='text'?{text:'',style:'paragraph' as const}:{image:'',alt:'',format:'landscape' as const,size:'large' as const,fit:'contain' as const})}]);}
 function move(from:number,to:number){if(to<0||to>=elements.length||to===from)return;const next=[...elements];next.splice(to,0,next.splice(from,1)[0]);setElements(next);}
 async function upload(id:string,file?:File){if(!file)return;if(!['image/png','image/jpeg','image/webp'].includes(file.type)||file.size>5*1024*1024){onError('Envie PNG, JPEG ou WebP até 5 MB.');return;}onBusy(true);onError('');try{const result=await portalUpload<{url:string}>('/admin/manage/covers',file);patch(id,{image:result.url});}catch(e){onError((e as Error).message);}finally{onBusy(false);}}
 async function browse(id:string,offset=0){onBusy(true);onError('');try{const result=await manage<Gallery>('/images?offset='+offset);setTarget(id);setGallery(old=>offset&&old?{...result,images:[...old.images,...result.images]}:result);}catch(e){onError((e as Error).message);}finally{onBusy(false);}}
 return <div className="page-designer">
  <div className="page-design-settings">
   <label>Modelo da página<select value={template} onChange={e=>onChange({...page,template:e.target.value as PageTemplate})}>{pageTemplates.map(t=><option key={t.id} value={t.id}>{t.name}</option>)}</select></label>
   <label>Alinhamento dos textos<select value={page.align??'left'} onChange={e=>onChange({...page,align:e.target.value as BookPage['align']})}><option value="left">À esquerda</option><option value="center">Centralizado</option><option value="justify">Justificado</option></select></label>
   <label>Posição das imagens<select value={page.imagePosition??(page.layout==='side'?'left':'above')} onChange={e=>onChange({...page,imagePosition:e.target.value as BookPage['imagePosition']})}><option value="left">À esquerda do texto</option><option value="right">À direita do texto</option><option value="center">Centralizada</option><option value="above">Acima do texto</option><option value="below">Abaixo do texto</option></select></label>
  </div>
  <div className="page-designer-toolbar"><span>{pageTemplates.find(t=>t.id===template)?.description} Arraste os elementos ou use as setas para reorganizar.</span><button type="button" onClick={()=>setShowPreview(v=>!v)} aria-pressed={showPreview}><Eye size={17}/>{showPreview?'Ocultar prévia':'Mostrar prévia'}</button></div>
  <div className={'page-designer-layout '+(!showPreview?'preview-hidden':'')}>
   <div className="page-elements">
    {elements.map((element,index)=><section key={element.id} className={'page-element '+(dragging===element.id?'is-dragging':'')} onDragOver={e=>{if(dragging)e.preventDefault();}} onDrop={e=>{e.preventDefault();if(!dragging)return;move(elements.findIndex(v=>v.id===dragging),index);setDragging(undefined);}}>
     <header><span className="page-drag-handle" draggable onDragStart={e=>{e.dataTransfer.setData('text/plain',element.id);e.dataTransfer.effectAllowed='move';setDragging(element.id);}} onDragEnd={()=>setDragging(undefined)} title="Arraste para reorganizar"><GripVertical size={18}/></span><strong>{element.type==='text'?'Texto':'Imagem'} {index+1}</strong><div className="page-element-actions"><button type="button" disabled={index===0} aria-label={'Mover elemento '+(index+1)+' para cima'} onClick={()=>move(index,index-1)}><ArrowUp size={16}/></button><button type="button" disabled={index===elements.length-1} aria-label={'Mover elemento '+(index+1)+' para baixo'} onClick={()=>move(index,index+1)}><ArrowDown size={16}/></button><button type="button" aria-label={'Remover elemento '+(index+1)} onClick={()=>setElements(elements.filter(e=>e.id!==element.id))}><Trash2 size={16}/></button></div></header>
     {element.type==='text'?<><div className="page-element-options"><label>Estilo<select value={element.style??'paragraph'} onChange={e=>patch(element.id,{style:e.target.value as BookElement['style']})}><option value="title">Título</option><option value="subtitle">Subtítulo</option><option value="paragraph">Parágrafo</option><option value="highlight">Destaque</option></select></label><label>Alinhamento<select value={element.align??''} onChange={e=>patch(element.id,{align:(e.target.value||undefined) as BookElement['align']})}><option value="">Usar o da página</option><option value="left">À esquerda</option><option value="center">Centralizado</option><option value="justify">Justificado</option></select></label></div><label>Conteúdo<AutoGrowingTextarea value={element.text??''} onChange={e=>patch(element.id,{text:e.target.value})}/></label><small>Use **palavras** para destacar um trecho em negrito.</small></>:<>
      {element.image&&<img className="page-element-thumbnail" src={element.image} alt={element.alt??''}/>}
      <div className="page-element-options"><label>Formato<select value={element.format??'landscape'} onChange={e=>patch(element.id,{format:e.target.value as BookElement['format']})}><option value="landscape">Paisagem</option><option value="portrait">Retrato</option><option value="square">Quadrada</option><option value="featured">Imagem em destaque</option><option value="full">Página inteira</option></select></label><label>Tamanho<select value={element.size??'large'} onChange={e=>patch(element.id,{size:e.target.value as BookElement['size']})}><option value="small">Pequeno</option><option value="medium">Médio</option><option value="large">Grande</option><option value="custom">Personalizado</option></select></label></div>
      {element.size==='custom'&&<div className="page-element-options"><label>Largura (%)<input type="number" min={10} max={100} value={element.width??100} onChange={e=>patch(element.id,{width:Number(e.target.value)})}/></label><label>Altura (px)<input type="number" min={80} max={900} value={element.height??320} onChange={e=>patch(element.id,{height:Number(e.target.value)})}/></label></div>}
      <label>Ajuste da imagem<select value={element.fit??'contain'} onChange={e=>patch(element.id,{fit:e.target.value as BookElement['fit']})}><option value="contain">Mostrar inteira, sem cortes</option><option value="cover">Preencher o espaço (pode recortar)</option></select></label>
      <label>Descrição da imagem<input maxLength={300} value={element.alt??''} placeholder="Descreva a cena para quem usa leitor de tela" onChange={e=>patch(element.id,{alt:e.target.value})}/></label>
      <div className="page-image-actions"><label className="page-upload"><Upload size={17}/>Enviar imagem<input type="file" accept="image/png,image/jpeg,image/webp" onChange={e=>{const f=e.target.files?.[0];e.target.value='';void upload(element.id,f);}}/></label><button type="button" onClick={()=>void browse(element.id)}><Images size={17}/>Biblioteca</button>{element.image&&<button type="button" onClick={()=>patch(element.id,{image:''})}>Retirar imagem</button>}</div>
      {target===element.id&&gallery&&<div className="book-image-library"><strong>Escolha uma imagem</strong><div className="book-image-grid">{gallery.images.map(image=><button type="button" key={image.name} title={image.name} onClick={()=>{patch(element.id,{image:image.url});setTarget(undefined);}}><img src={image.url} alt={image.name}/></button>)}</div>{!gallery.images.length&&<p>Nenhuma imagem enviada ainda.</p>}{gallery.nextOffset!==null&&<button type="button" onClick={()=>void browse(element.id,gallery.nextOffset!)}>Carregar mais</button>}<button type="button" onClick={()=>setTarget(undefined)}>Fechar biblioteca</button></div>}
     </>}
    </section>)}
    {!elements.length&&<p className="page-empty">Comece adicionando um texto ou uma imagem.</p>}
    <div className="page-add-elements"><button type="button" onClick={()=>add('text')}><Type size={18}/>Adicionar texto</button><button type="button" onClick={()=>add('image')}><ImagePlus size={18}/>Adicionar imagem</button></div>
   </div>
   {showPreview&&<aside className="page-live-preview"><strong><Eye size={16}/>Prévia desta página</strong><div className="page-preview-paper"><BookPageContent page={page}/></div>{problem&&<p className="page-design-warning">{problem} Os elementos ocultos pelo modelo permanecem salvos.</p>}</aside>}
  </div>
 </div>;
}
