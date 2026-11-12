import {test} from 'node:test';
import assert from 'node:assert/strict';
import {readFile} from 'node:fs/promises';
import {createRequire} from 'node:module';
import {pathToFileURL} from 'node:url';
import React from 'react';
import {renderToStaticMarkup} from 'react-dom/server';
import ts from 'typescript';
const require=createRequire(import.meta.url);
const moduleUrl=code=>'data:text/javascript;base64,'+Buffer.from(code).toString('base64');
const compile=(source,tsx=false)=>ts.transpileModule(source,{fileName:tsx?'component.tsx':'helpers.ts',compilerOptions:{target:ts.ScriptTarget.ES2022,module:ts.ModuleKind.ESNext,jsx:ts.JsxEmit.ReactJSX}}).outputText;
const helpers=moduleUrl(compile(await readFile(new URL('./src/services/book-pages.ts',import.meta.url),'utf8')));
let code=compile((await readFile(new URL('./src/components/BookPageContent.tsx',import.meta.url),'utf8')).replace(/import '\.\.\/storybook.css';/,''),true);
code=code.replace(/from ['"]react(\/jsx-runtime)?['"]/g,(_all,suffix)=>'from '+JSON.stringify(pathToFileURL(require.resolve('react'+(suffix??''))).href));
code=code.replace(/from ['"]\.\.\/services\/book-pages['"]/g,'from '+JSON.stringify(helpers));
const {BookPageContent}=await import(moduleUrl(code));
const render=page=>renderToStaticMarkup(React.createElement(BookPageContent,{page}));

test('papel: mantém imagens originais e layouts legados, sem duplicá-las como fundo',()=>{
 for(const layout of ['illustration','side','frame']){
  const page={id:'old',text:'Era uma vez…',image:'https://example.test/original.png',layout},original=structuredClone(page),html=render(page);
  assert.deepEqual(page,original);assert.equal((html.match(/<img /g)??[]).length,1);
  assert.ok(html.includes('src="https://example.test/original.png"'));assert.ok(html.includes('Era uma vez…'));
  assert.ok(!html.includes('story-page-background'));assert.ok(!html.includes('page-background-illustration'));
 }
});
test('composição: todos os modelos mantêm seus elementos, alinhamento e texto seguro',()=>{
 const base={id:'page',text:'Texto',image:'https://example.test/one.png',align:'justify',imagePosition:'right',elements:[
  {id:'title',type:'text',style:'title',text:'Uma **aventura**'},
  {id:'body',type:'text',style:'paragraph',text:'Texto <script> de teste.'},
  {id:'picture',type:'image',image:'https://example.test/one.png',format:'portrait',size:'custom',width:75,height:320,fit:'contain'},
  {id:'other',type:'image',image:'https://example.test/two.png',format:'landscape',size:'large'}
 ]};
 for(const template of ['mixed','text','image','two-images','overlay']){
  const page={...base,template},original=structuredClone(page),html=render(page);assert.deepEqual(page,original);
  assert.ok(html.includes('template-'+template));assert.ok(html.includes('text-align:justify'));
  assert.equal((html.match(/<img /g)??[]).length,template==='text'?0:2);
  if(['mixed','text','overlay'].includes(template)){assert.ok(html.includes('<strong>aventura</strong>'));assert.ok(html.includes('&lt;script&gt;'));}
  assert.ok(!html.includes('<script>'));
 }
});
