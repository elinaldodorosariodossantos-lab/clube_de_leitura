import {test} from 'node:test';
import assert from 'node:assert/strict';
import {readFile} from 'node:fs/promises';
import ts from 'typescript';
const compile=source=>ts.transpileModule(source,{compilerOptions:{target:ts.ScriptTarget.ES2022,module:ts.ModuleKind.ESNext}}).outputText;
const url=code=>'data:text/javascript;base64,'+Buffer.from(code).toString('base64');
const pages=url(compile(await readFile(new URL('./src/services/book-pages.ts',import.meta.url),'utf8')));
const code=compile(await readFile(new URL('./src/services/page-layout-models.ts',import.meta.url),'utf8')).replace("'./book-pages'",JSON.stringify(pages));
const {pageLayoutModels,applyPageLayout,selectedPageLayout}=await import(url(code));

test('all six page previews preserve every text, image and element setting on selection',()=>{
 const page={id:'page',text:'Título\n\nHistória',image:'https://example.test/a.png',template:'mixed',align:'justify',elements:[{id:'title',type:'text',text:'Título',style:'title',align:'center'},{id:'first',type:'image',image:'https://example.test/a.png',format:'portrait',size:'custom',width:70,height:420,fit:'contain'},{id:'body',type:'text',text:'História',style:'paragraph'},{id:'second',type:'image',image:'https://example.test/b.png',alt:'Segunda ilustração'}]};
 const original=structuredClone(page);assert.ok(pageLayoutModels.length>=4);
 for(const model of pageLayoutModels){
  const chosen=applyPageLayout(page,model),saved=JSON.parse(JSON.stringify(chosen));
  assert.equal(selectedPageLayout(saved),model.id);assert.equal(saved.text,page.text);assert.equal(saved.image,page.image);assert.equal(saved.align,page.align);assert.deepEqual(saved.elements,page.elements);
 }
 assert.deepEqual(page,original);
});
test('legacy pages keep their content and custom templates are not silently replaced',()=>{
 const page={id:'legacy',text:'Era uma vez…',image:'https://example.test/original.png',layout:'side'};
 assert.equal(selectedPageLayout(page),'left');
 for(const model of pageLayoutModels){const next=applyPageLayout(page,model);assert.equal(next.text,page.text);assert.equal(next.image,page.image);assert.equal(next.elements,undefined);}
 assert.equal(selectedPageLayout({...page,template:'two-images'}),undefined);
});
