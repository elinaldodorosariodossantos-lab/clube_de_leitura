import {useRef,useState} from 'react';
import {Upload,Images,Trash2,CheckCircle2,SlidersHorizontal,Eye,ImagePlus} from 'lucide-react';
import {portalUpload} from '../services/portal';
import {manage} from '../services/management';
import {pageElements,withPageElements,pageProblem} from '../services/book-pages';
import {pageLayoutModels,applyPageLayout,selectedPageLayout} from '../services/page-layout-models';
import {BookPageContent} from './BookPageContent';
import {AutoGrowingTextarea} from './AutoGrowingTextarea';
import {AdvancedPageDesigner} from './AdvancedPageDesigner';
import type {BookPage,BookElement} from '../types/management';
import '../page-designer.css';
export {pageTemplates} from './AdvancedPageDesigner';

type Props={page:BookPage;onChange:(page:BookPage)=>void;onError:(message:string)=>void;onBusy:(busy:boolean)=>void};
type Gallery={images:{name:string;url:string}[];nextOffset:number|null};
export function PageDesigner({page,onChange,onError,onBusy}:Props){
 const latest=useRef(page);latest.current=page;
 const [slots]=useState(()=>({text:crypto.randomUUID(),image:crypto.randomUUID()}));
 const [gallery,setGallery]=useState<Gallery>(),[galleryTarget,setGalleryTarget]=useState<string>();
 const elements=pageElements(page),texts=elements.filter(e=>e.type==='text'),images=elements.filter(e=>e.type==='image');
 const textFields=texts.length?texts:[{id:slots.text,type:'text' as const,text:'',style:'paragraph' as const}];
 const imageFields=images.length?images:[{id:slots.image,type:'image' as const,image:'',alt:''}];
 const ready=texts.some(e=>e.text?.trim())&&images.some(e=>e.image);
 const selected=selectedPageLayout(page),problem=pageProblem(page);
 function patchElement(element:BookElement,patch:Partial<BookElement>){
  const current=latest.current,items=pageElements(current),exists=items.some(e=>e.id===element.id);
  onChange(withPageElements(current,exists?items.map(e=>e.id===element.id?{...e,...patch}:e):[...items,{...element,...patch}]));
 }
 async function upload(element:BookElement,file?:File){
  if(!file)return;
  if(!['image/png','image/jpeg','image/webp'].includes(file.type)||file.size>5*1024*1024){onError('Envie PNG, JPEG ou WebP até 5 MB.');return;}
  onBusy(true);onError('');
  try{const result=await portalUpload<{url:string}>('/admin/manage/covers',file);patchElement(element,{image:result.url,format:element.format??'landscape',size:element.size??'large',fit:element.fit??'contain'});}
  catch(error){onError((error as Error).message);}finally{onBusy(false);}
 }
 async function browse(element:BookElement,offset=0){
  onBusy(true);onError('');
  try{const result=await manage<Gallery>('/images?offset='+offset);setGalleryTarget(element.id);setGallery(old=>offset&&old?{...result,images:[...old.images,...result.images]}:result);}
  catch(error){onError((error as Error).message);}finally{onBusy(false);}
 }
 return <div className="page-designer page-designer-simple">
  <div className="page-content-fields">
   <section className="page-text-field"><h3>1. Adicione o texto</h3>{textFields.map((element,index)=><label key={element.id}>{index?'Texto adicional '+(index+1):'Texto da página'}<AutoGrowingTextarea value={element.text??''} placeholder="Digite aqui o texto desta página da história…" onChange={event=>patchElement(element,{text:event.target.value})}/></label>)}<small>O texto aparecerá nas prévias. Use **palavras** para destacar um trecho em negrito.</small></section>
   <section className="page-picture-field"><h3>2. Adicione a imagem</h3>{imageFields.map((element,index)=><div className="page-picture-slot" key={element.id}>{imageFields.length>1&&<strong>Imagem {index+1}</strong>}{element.image?<img className="page-picture-thumbnail" src={element.image} alt={element.alt||'Imagem desta página'}/>:<div className="page-picture-placeholder"><ImagePlus size={32}/><span>Envie uma imagem ou escolha na biblioteca</span></div>}<div className="page-picture-actions"><label className="page-upload"><Upload size={17}/>{element.image?'Trocar imagem':'Enviar imagem'}<input type="file" aria-label={'Enviar imagem '+(index+1)+' da página'} accept="image/png,image/jpeg,image/webp" onChange={event=>{const file=event.target.files?.[0];event.target.value='';void upload(element,file);}}/></label><button type="button" onClick={()=>void browse(element)}><Images size={17}/>Biblioteca</button>{element.image&&<button type="button" aria-label={'Remover imagem '+(index+1)+' da página'} onClick={()=>patchElement(element,{image:''})}><Trash2 size={17}/><span>Remover</span></button>}</div>{galleryTarget===element.id&&gallery&&<div className="book-image-library"><strong>Escolha uma imagem</strong><div className="book-image-grid">{gallery.images.map(image=><button type="button" key={image.name} title={image.name} aria-label={'Selecionar imagem '+image.name} onClick={()=>{patchElement(element,{image:image.url});setGalleryTarget(undefined);}}><img src={image.url} alt={image.name}/></button>)}</div>{!gallery.images.length&&<p>Nenhuma imagem enviada ainda.</p>}{gallery.nextOffset!==null&&<button type="button" onClick={()=>void browse(element,gallery.nextOffset!)}>Carregar mais imagens</button>}<button type="button" onClick={()=>setGalleryTarget(undefined)}>Fechar biblioteca</button></div>}</div>)}<small>PNG, JPEG ou WebP · até 5 MB. As imagens originais são preservadas.</small></section>
  </div>
  <section className="page-model-picker" aria-label="Prévias dos modelos da página"><div className="page-model-heading"><div><h3>3. Escolha o modelo da página</h3><p>{ready?'Compare as prévias com seu texto e sua imagem. Clique no modelo que preferir.':'Preencha o texto e adicione uma imagem para visualizar e escolher os modelos.'}</p></div>{ready&&<span>{pageLayoutModels.length} modelos disponíveis</span>}</div>
   <div className="page-model-grid" role="radiogroup" aria-label={'Modelo visual da página '+page.id}>{pageLayoutModels.map(model=><label className={'page-model-choice'+(selected===model.id?' is-selected':'')+(!ready?' is-unavailable':'')} key={model.id}><input type="radio" name={'page-model-'+page.id} value={model.id} checked={selected===model.id} disabled={!ready} onChange={()=>onChange(applyPageLayout(latest.current,model))}/><div className="page-model-paper" aria-hidden="true">{ready?<BookPageContent page={applyPageLayout(page,model)} compact reading/>:<span className={'page-model-placeholder placeholder-'+model.id}><span/><i/><i/><i/></span>}</div><span className="page-model-label"><strong>{model.name}</strong>{selected===model.id&&<CheckCircle2 size={19}/>}</span><small>{model.description}</small></label>)}</div>
   {ready&&<details className="page-selected-preview"><summary><Eye size={18}/>Ver prévia ampliada do modelo escolhido</summary><div className="page-preview-paper"><BookPageContent page={page} reading/></div>{problem&&<p className="page-design-warning">{problem} Os elementos permanecem salvos.</p>}</details>}
  </section>
  <details className="page-advanced-options"><summary><SlidersHorizontal size={18}/>Opções avançadas de edição<span>Alinhamento, formatos, tamanhos e organização dos elementos</span></summary><AdvancedPageDesigner page={page} onChange={onChange} onError={onError} onBusy={onBusy}/></details>
 </div>;
}
