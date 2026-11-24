import {test} from 'node:test';
import assert from 'node:assert/strict';
import {readFile} from 'node:fs/promises';
import ts from 'typescript';
async function load(path,transform=s=>s){const source=transform(await readFile(new URL(path,import.meta.url),'utf8'));const code=ts.transpileModule(source,{compilerOptions:{target:ts.ScriptTarget.ES2022,module:ts.ModuleKind.ESNext}}).outputText;return import('data:text/javascript;base64,'+Buffer.from(code).toString('base64'));}
const confirmation=await load('./src/services/confirmation.ts');
const forms=await load('./src/services/management.ts',s=>s.replace("import {portalApi} from './portal';",'const portalApi=()=>Promise.resolve();'));
test('confirmation rejects repeated clicks and resolves cancellation without authorizing an action',async()=>{
 const previous=globalThis.document;
 globalThis.document={querySelector:()=>({getAttribute:()=> 'dark'})};
 try{
  const first=confirmation.confirmAction('Excluir?');
  assert.equal(confirmation.confirmationSnapshot().theme,'dark');
  assert.equal(await confirmation.confirmAction('Excluir novamente?'),false);
  confirmation.finishConfirmation(false);assert.equal(await first,false);
  assert.equal(confirmation.confirmationSnapshot(),null);
  const next=confirmation.confirmAction('Salvar?');confirmation.finishConfirmation(true);assert.equal(await next,true);
 }finally{confirmation.finishConfirmation(false);globalThis.document=previous;}
});
test('navigation shares one pending guard, preserves it on cancel and clears it only after approval',async()=>{
 let resolve,calls=0;
 const stop=forms.registerFormGuard(()=>{calls++;return new Promise(r=>{resolve=r;});});
 const first=forms.mayLeaveForm(),second=forms.mayLeaveForm();assert.equal(calls,1);
 resolve(false);assert.equal(await first,false);assert.equal(await second,false);
 const next=forms.mayLeaveForm();assert.equal(calls,2);resolve(true);assert.equal(await next,true);
 assert.equal(await forms.mayLeaveForm(),true);assert.equal(calls,2);stop();
});
test('an old pending navigation never clears a newly registered form guard',async()=>{
 let resolve;forms.registerFormGuard(()=>new Promise(r=>{resolve=r;}));
 const pending=forms.mayLeaveForm();let fresh=0;
 const stop=forms.registerFormGuard(()=>{fresh++;return false;});
 resolve(true);await pending;assert.equal(await forms.mayLeaveForm(),false);assert.equal(fresh,1);stop();
});
