import {z} from 'zod';
const image=z.union([z.url().max(4096).refine(v=>v.startsWith('https://')),z.literal('')]);
const alignment=z.enum(['left','center','justify']);
export const bookElement=z.object({
 id:z.string().min(1).max(100),type:z.enum(['text','image']),text:z.string().max(30000).optional(),
 style:z.enum(['title','subtitle','paragraph','highlight']).optional(),align:alignment.optional(),image:image.optional(),alt:z.string().max(300).optional(),
 format:z.enum(['landscape','portrait','square','featured','full']).optional(),size:z.enum(['small','medium','large','custom']).optional(),
 width:z.number().min(10).max(100).optional(),height:z.number().int().min(80).max(900).optional(),fit:z.enum(['contain','cover']).optional()
});
export const bookPage=z.object({
 layout:z.enum(['illustration','side','frame']).optional(),id:z.string().uuid(),text:z.string(),image,
 template:z.enum(['mixed','text','image','two-images','overlay']).optional(),align:alignment.optional(),
 imagePosition:z.enum(['left','right','center','above','below']).optional(),elements:z.array(bookElement).max(100).optional()
}).refine(p=>!p.elements||new Set(p.elements.map(e=>e.id)).size===p.elements.length,{message:'Identificadores de elementos repetidos.'})
 .transform(p=>p.elements?{...p,text:p.elements.filter(e=>e.type==='text').map(e=>e.text??'').join('\n\n'),image:p.elements.find(e=>e.type==='image'&&e.image)?.image??''}:p);
export function pageIsPublishable(page:z.infer<typeof bookPage>){
 const texts=page.elements?page.elements.some(e=>e.type==='text'&&e.text?.trim()):!!page.text.trim();
 const images=page.elements?page.elements.filter(e=>e.type==='image'&&e.image).length:Number(!!page.image);
 const template=page.template??(texts&&images?'mixed':images?'image':'text');
 return template==='text'?texts:template==='image'?images>0:template==='two-images'?images>=2:texts&&images>0;
}
