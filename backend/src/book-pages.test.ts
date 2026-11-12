import {test} from 'node:test';
import assert from 'node:assert/strict';
import {randomUUID} from 'node:crypto';
import {bookPage,pageIsPublishable} from './book-pages.js';

test('composição: preserva páginas antigas e normaliza blocos sem perder opções',()=>{
 const legacy={id:randomUUID(),text:'Uma história',image:'https://example.test/a.png',layout:'side' as const};
 assert.deepEqual(bookPage.parse(legacy),legacy);
 const source={...legacy,text:'resumo antigo',image:'',template:'mixed',align:'justify',imagePosition:'right',elements:[
  {id:'title',type:'text',style:'title',text:'A grande aventura'},
  {id:'scene',type:'image',image:legacy.image,alt:'Uma floresta',format:'portrait',size:'custom',width:70,height:420,fit:'contain'},
  {id:'paragraph',type:'text',text:'Texto com **destaque**.',align:'center'}
 ]};
 const saved=bookPage.parse(source);
 assert.equal(saved.text,'A grande aventura\n\nTexto com **destaque**.');assert.equal(saved.image,legacy.image);
 assert.deepEqual(saved.elements,source.elements);assert.equal(saved.imagePosition,'right');assert.equal(pageIsPublishable(saved),true);
 for(const patch of [{image:'javascript:alert(1)'},{image:'blob:temporary'},{width:101},{height:0}])assert.equal(bookPage.safeParse({...source,elements:[{...source.elements[1],...patch}]}).success,false);
 assert.equal(bookPage.safeParse({...source,elements:[source.elements[0],source.elements[0]]}).success,false);
});
test('modelos publicados exigem conteúdo visível; os rascunhos podem permanecer vazios',()=>{
 const base={id:randomUUID(),text:'Texto',image:'https://example.test/a.png'};
 for(const template of ['mixed','text','image','overlay'] as const)assert.equal(pageIsPublishable(bookPage.parse({...base,template})),true);
 assert.equal(pageIsPublishable(bookPage.parse({...base,template:'text',text:''})),false);
 assert.equal(pageIsPublishable(bookPage.parse({...base,template:'image',image:''})),false);
 assert.equal(pageIsPublishable(bookPage.parse({...base,template:'two-images'})),false);
 assert.equal(pageIsPublishable(bookPage.parse({...base,template:'two-images',elements:[{id:'one',type:'image',image:base.image},{id:'two',type:'image',image:base.image}]})),true);
 assert.equal(bookPage.safeParse({...base,text:'',image:'',elements:[]}).success,true);
});
