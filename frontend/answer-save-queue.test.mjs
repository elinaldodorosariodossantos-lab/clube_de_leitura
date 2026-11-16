import {test} from 'node:test';
import assert from 'node:assert/strict';
import {readFile} from 'node:fs/promises';
import ts from 'typescript';
const code=ts.transpileModule(await readFile(new URL('./src/services/answer-save-queue.ts',import.meta.url),'utf8'),{compilerOptions:{target:ts.ScriptTarget.ES2022,module:ts.ModuleKind.ESNext}}).outputText;
const {AnswerSaveQueue}=await import('data:text/javascript;base64,'+Buffer.from(code).toString('base64'));
const deferred=()=>{let resolve,reject;const promise=new Promise((yes,no)=>{resolve=yes;reject=no;});return {promise,resolve,reject};};
const tick=()=>new Promise(r=>setImmediate(r));

test('rapid answers save in sequence; finish waits for every confirmed response',async()=>{
 const calls=[],gates=[],saved=[],confirmed={};let sending=0;
 const queue=new AnswerSaveQueue(async(q,choice)=>{assert.equal(++sending,1);calls.push([q,choice]);const gate=deferred();gates.push(gate);await gate.promise;confirmed[q]=choice;sending--;return {...confirmed};},(result,drafts)=>saved.push({...result,...drafts}),()=>{});
 queue.enqueue(1,0);queue.enqueue(2,1);queue.enqueue(3,2);
 assert.deepEqual(queue.drafts(),{1:0,2:1,3:2});assert.equal(calls.length,1);
 let finished=false;const finish=queue.flush().then(()=>{finished=true;});
 gates[0].resolve();await tick();assert.equal(finished,false);assert.equal(calls.length,2);
 assert.deepEqual(saved[0],{1:0,2:1,3:2});
 gates[1].resolve();await tick();assert.equal(finished,false);assert.equal(calls.length,3);
 gates[2].resolve();await finish;assert.equal(finished,true);assert.equal(queue.pending,false);
 assert.deepEqual(confirmed,{1:0,2:1,3:2});
});
test('an older response cannot erase a newer choice for the same question',async()=>{
 const gates=[],saved=[],calls=[];
 const queue=new AnswerSaveQueue(async(q,choice)=>{const gate=deferred();gates.push(gate);calls.push([q,choice]);await gate.promise;return {[q]:choice};},(result,drafts)=>saved.push({...result,...drafts}),()=>{});
 queue.enqueue(1,0);queue.enqueue(1,1);queue.enqueue(1,2);
 gates[0].resolve();await tick();assert.deepEqual(saved[0],{1:2});assert.deepEqual(calls,[[1,0],[1,2]]);
 gates[1].resolve();await queue.flush();assert.deepEqual(saved.at(-1),{1:2});
});
test('a failed save retains choices, blocks completion and retries only on user action',async()=>{
 let calls=0;const gate=deferred();
 const queue=new AnswerSaveQueue(async()=>{calls++;if(calls===1)await gate.promise;return 'saved';},()=>{},()=>{});
 queue.enqueue(1,2);queue.enqueue(2,0);gate.reject(new Error('offline'));await tick();
 assert.equal(calls,1);assert.deepEqual(queue.drafts(),{1:2,2:0});
 await assert.rejects(queue.flush(),/offline/);assert.equal(calls,1);
 await queue.retry();assert.equal(calls,3);assert.equal(queue.pending,false);assert.equal(queue.error,null);
});
test('closing the student session stops queued saves and ignores the previous response',async()=>{
 const gate=deferred();let calls=0,saved=0;
 const queue=new AnswerSaveQueue(async()=>{calls++;await gate.promise;return 'old student';},()=>saved++,()=>{});
 queue.enqueue(1,0);queue.enqueue(2,1);queue.dispose();gate.resolve();await tick();
 assert.equal(calls,1);assert.equal(saved,0);assert.equal(queue.pending,false);
});
