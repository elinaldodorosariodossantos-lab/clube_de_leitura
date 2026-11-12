import type {BookPage,BookElement,PageTemplate} from '../types/management';

export function pageElements(page:BookPage):BookElement[]{
 if(page.elements)return page.elements;
 const elements:BookElement[]=[];
 if(page.image)elements.push({id:page.id+'-image',type:'image',image:page.image,alt:'Ilustração da página',format:'landscape',size:'large',fit:'contain'});
 if(page.text)elements.push({id:page.id+'-text',type:'text',text:page.text,style:'paragraph'});
 return elements;
}
// Keep the original fields for existing SQL validation, summaries and older clients.
export function withPageElements(page:BookPage,elements:BookElement[]):BookPage{
 return {...page,elements,text:elements.filter(e=>e.type==='text').map(e=>e.text??'').join('\n\n'),image:elements.find(e=>e.type==='image'&&e.image)?.image??''};
}
export function pageTemplate(page:BookPage):PageTemplate{return page.template??(page.image&&page.text?'mixed':page.image?'image':'text');}
export function pageBackgroundImage(page:BookPage):string{
 if(pageTemplate(page)==='text')return '';
 return pageElements(page).find(element=>element.type==='image'&&element.image)?.image??'';
}
export function pageProblem(page:BookPage):string|null{
 const elements=pageElements(page),images=elements.filter(e=>e.type==='image'&&e.image),text=elements.some(e=>e.type==='text'&&e.text?.trim()),template=pageTemplate(page);
 if(template==='two-images'&&images.length<2)return 'Adicione duas imagens para este modelo.';
 if((template==='image'||template==='overlay')&&!images.length)return 'Adicione uma imagem para este modelo.';
 if((template==='text'||template==='mixed'||template==='overlay')&&!text)return 'Adicione texto para este modelo.';
 if(template==='mixed'&&!images.length)return 'Adicione uma imagem para este modelo.';
 return null;
}
