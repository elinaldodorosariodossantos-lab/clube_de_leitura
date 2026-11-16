import type {BookPage} from '../types/management';
import {pageTemplate} from './book-pages';
export const pageLayoutModels=[
 {id:'above',name:'Imagem acima',description:'Ilustração no alto e texto logo abaixo.',template:'mixed',position:'above',layout:'illustration'},
 {id:'left',name:'Imagem à esquerda',description:'Imagem e texto lado a lado.',template:'mixed',position:'left',layout:'side'},
 {id:'right',name:'Imagem à direita',description:'Texto à esquerda da ilustração.',template:'mixed',position:'right',layout:'side'},
 {id:'below',name:'Imagem abaixo',description:'Texto primeiro, ilustração em seguida.',template:'mixed',position:'below',layout:'illustration'},
 {id:'frame',name:'Página emoldurada',description:'Texto e imagem em uma moldura delicada.',template:'mixed',position:'above',layout:'frame'},
 {id:'overlay',name:'Texto sobre a imagem',description:'Ilustração com o texto em destaque.',template:'overlay',position:'above',layout:'illustration'}
] as const;
export type PageLayoutModel=typeof pageLayoutModels[number];
/** Only presentation changes. Keep all original text, images and element IDs. */
export function applyPageLayout(page:BookPage,model:PageLayoutModel):BookPage{
 return {...page,template:model.template,imagePosition:model.position,layout:model.layout};
}
export function selectedPageLayout(page:BookPage):string|undefined{
 const template=pageTemplate(page),position=page.imagePosition??(page.layout==='side'?'left':'above');
 if(template==='overlay')return 'overlay';
 if(template!=='mixed')return;
 if(page.layout==='frame'&&position==='above')return 'frame';
 return pageLayoutModels.find(model=>model.template==='mixed'&&model.id!=='frame'&&model.position===position)?.id;
}
