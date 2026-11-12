import {test} from 'node:test';
import assert from 'node:assert/strict';
import {readFile} from 'node:fs/promises';
import ts from 'typescript';
test('recording is cached, muted rewards stay silent and simultaneous rewards do not overlap',async()=>{
 const source=await readFile(new URL('./src/services/coin-audio.ts',import.meta.url),'utf8');
 const code=ts.transpileModule(source,{compilerOptions:{target:ts.ScriptTarget.ES2022,module:ts.ModuleKind.ESNext}}).outputText;
 const originalFetch=globalThis.fetch,originalStorage=globalThis.localStorage;
 let muted=false,requests=0,starts=0,stops=0,decodes=0;
 globalThis.localStorage={getItem:()=>muted?'off':'on'};
 globalThis.fetch=async url=>{assert.equal(url,'/audio/coin-reward.mp3');requests++;return {ok:true,arrayBuffer:async()=>new ArrayBuffer(8)};};
 try{
  const service=await import('data:text/javascript;base64,'+Buffer.from(code).toString('base64'));
  const ctx={state:'running',destination:{},decodeAudioData:async()=>{decodes++;return {};},createBufferSource:()=>({connect(){},disconnect(){},start(){starts++;},stop(){stops++;}}),createGain:()=>({gain:{value:0},connect(){},disconnect(){}})};
  await service.prepareCoinReward(ctx);await service.prepareCoinReward(ctx);
  assert.equal(requests,1);assert.equal(decodes,1);
  muted=true;await service.playCoinReward(ctx);assert.equal(starts,0);
  muted=false;await Promise.all([service.playCoinReward(ctx),service.playCoinReward(ctx)]);assert.equal(starts,1);
  service.stopCoinReward();assert.equal(stops,1);
  const original=await readFile(new URL('../som/som de moedas.mpeg',import.meta.url));
  const published=await readFile(new URL('./public/audio/coin-reward.mp3',import.meta.url));assert.deepEqual(published,original);
 }finally{globalThis.fetch=originalFetch;if(originalStorage===undefined)delete globalThis.localStorage;else globalThis.localStorage=originalStorage;}
});
