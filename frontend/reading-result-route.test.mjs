import {test} from 'node:test';
import assert from 'node:assert/strict';
import {readFile} from 'node:fs/promises';
import ts from 'typescript';
const code=ts.transpileModule(await readFile(new URL('./src/services/reading-result-route.ts',import.meta.url),'utf8'),{compilerOptions:{target:ts.ScriptTarget.ES2022,module:ts.ModuleKind.ESNext}}).outputText;
const {parseReadingResultRoute,readingResultPath}=await import('data:text/javascript;base64,'+Buffer.from(code).toString('base64'));
const id='11111111-1111-4111-8111-111111111111',next='22222222-2222-4222-8222-222222222222';
test('level and journey URLs preserve the result and pending final screen through reload',()=>{
 for(const result of [{kind:'level',id},{kind:'journey',id},{kind:'level',id,nextJourneyId:next}])assert.deepEqual(parseReadingResultRoute(readingResultPath(result)),result);
});
test('invalid result identifiers cannot become result API paths',()=>{
 for(const path of ['conquista/../../admin','conquista/no-id','conclusao/'+id+'/extra','atividade/'+id,'conquista/'])assert.equal(parseReadingResultRoute(path),undefined);
 assert.deepEqual(parseReadingResultRoute('conquista/'+id+'?conclusao=invalid'),{kind:'level',id});
});
