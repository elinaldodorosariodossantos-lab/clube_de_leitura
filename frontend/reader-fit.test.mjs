import {test} from 'node:test';
import assert from 'node:assert/strict';
import {readFile} from 'node:fs/promises';
import ts from 'typescript';
const source=await readFile(new URL('./src/services/reader-fit.ts',import.meta.url),'utf8');
const code=ts.transpileModule(source,{compilerOptions:{target:ts.ScriptTarget.ES2022,module:ts.ModuleKind.ESNext}}).outputText;
const {readingParts}=await import('data:text/javascript;base64,'+Buffer.from(code).toString('base64'));
test('keeps illustrations and text lines whole across continuations',()=>{
 const blocks=[{top:4,bottom:240},...Array.from({length:40},(_,i)=>({top:260+i*30,bottom:283+i*30}))];
 const parts=readingParts(blocks,400);
 assert.ok(parts.length>1);
 for(const block of blocks)assert.ok(parts.some(p=>block.top>=p.top&&block.bottom<=p.top+p.height));
 for(let i=1;i<parts.length;i++)assert.equal(parts[i].top,parts[i-1].top+parts[i-1].height);
 assert.ok(parts.every(p=>p.height<=400));
});
test('does not create a continuation for empty paper or invalid bounds',()=>{
 assert.deepEqual(readingParts([],400),[{top:0,height:400}]);
 assert.deepEqual(readingParts([{top:NaN,bottom:900}],400),[{top:0,height:400}]);
});
