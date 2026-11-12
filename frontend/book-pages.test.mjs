import {test} from 'node:test';
import assert from 'node:assert/strict';
import {readFile} from 'node:fs/promises';
import ts from 'typescript';
const code=ts.transpileModule(await readFile(new URL('./src/services/book-pages.ts',import.meta.url),'utf8'),{compilerOptions:{target:ts.ScriptTarget.ES2022,module:ts.ModuleKind.ESNext}}).outputText;
const {pageBackgroundImage,pageElements,withPageElements,pageTemplate,pageProblem}=await import('data:text/javascript;base64,'+Buffer.from(code).toString('base64'));
test('páginas antigas recebem uma composição sem alterar o conteúdo original',()=>{
 const page={id:'old',text:'Era uma vez…',image:'https://example.test/image.png',layout:'side'};
 const original=structuredClone(page),elements=pageElements(page);assert.deepEqual(page,original);assert.equal(pageTemplate(page),'mixed');assert.equal(pageProblem(page),null);
 const reordered=withPageElements(page,[elements[1],{id:'two',type:'text',text:'O fim.'},elements[0]]);
 assert.equal(reordered.text,'Era uma vez…\n\nO fim.');assert.equal(reordered.image,page.image);assert.equal(reordered.elements[0].type,'text');
 assert.equal(pageProblem({...reordered,template:'two-images'}),'Adicione duas imagens para este modelo.');
 assert.equal(pageProblem({...page,template:'image',image:''}),'Adicione uma imagem para este modelo.');
});
test('cada página usa a própria ilustração como fundo e acompanha trocas ou remoções',()=>{
 const first={id:'one',text:'Texto',image:'https://example.test/floresta.png'};
 const second={id:'two',text:'Outra cena',image:'https://example.test/abelha.png'};
 assert.equal(pageBackgroundImage(first),first.image);assert.equal(pageBackgroundImage(second),second.image);
 assert.equal(pageBackgroundImage({...first,template:'text'}),'');
 const changed=withPageElements(first,[{id:'picture',type:'image',image:second.image},{id:'text',type:'text',text:first.text}]);
 assert.equal(pageBackgroundImage(changed),second.image);
 assert.equal(pageBackgroundImage(withPageElements(changed,[{id:'text',type:'text',text:first.text}])),'');
 assert.equal(first.image,'https://example.test/floresta.png');
});
