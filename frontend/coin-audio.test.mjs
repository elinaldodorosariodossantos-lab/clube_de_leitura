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

test('a reward blocked before a gesture plays after unlock, and mute cancels a pending reward',async()=>{
 const source=await readFile(new URL('./src/services/coin-audio.ts',import.meta.url),'utf8');
 const code=ts.transpileModule(source,{compilerOptions:{target:ts.ScriptTarget.ES2022,module:ts.ModuleKind.ESNext}}).outputText;
 const saved={fetch:globalThis.fetch,localStorage:globalThis.localStorage,AudioContext:globalThis.AudioContext};
 let muted=false,allowed=false,starts=0,instance;
 globalThis.localStorage={getItem:()=>muted?'off':'on'};
 globalThis.fetch=async()=>({ok:true,arrayBuffer:async()=>new ArrayBuffer(8)});
 globalThis.AudioContext=class{
  state='suspended';destination={};
  constructor(){instance=this;}
  async resume(){if(!allowed)throw Error('Needs gesture');this.state='running';}
  async decodeAudioData(){return {};}
  createBufferSource(){return {connect(){},disconnect(){},start(){starts++;},stop(){}};}
  createGain(){return {gain:{value:0},connect(){},disconnect(){}};}
 };
 try{
  const service=await import('data:text/javascript;base64,'+Buffer.from(code+'\n// suspended regression').toString('base64'));
  await service.playCoinReward();await new Promise(r=>setImmediate(r));assert.equal(starts,0);
  allowed=true;service.unlockCoinAudio();await new Promise(r=>setImmediate(r));assert.equal(starts,1);
  service.stopCoinReward();
  // A new module models a fresh session with a blocked reward then sound disabled.
  allowed=false;starts=0;
  const mutedService=await import('data:text/javascript;base64,'+Buffer.from(code+'\n// muted regression').toString('base64'));
  await mutedService.playCoinReward();await new Promise(r=>setImmediate(r));
  muted=true;mutedService.stopCoinReward();allowed=true;mutedService.unlockCoinAudio();
  await new Promise(r=>setImmediate(r));assert.equal(starts,0);assert.equal(instance.state,'running');
 }finally{for(const [key,value] of Object.entries(saved)){if(value===undefined)delete globalThis[key];else globalThis[key]=value;}}
});
