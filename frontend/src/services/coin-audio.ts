// One shared audio context survives navigation between wallet and ranking.
let context:AudioContext|undefined;
let recording:Promise<ArrayBuffer>|undefined;
const decoded=new WeakMap<AudioContext,Promise<AudioBuffer>>();
let lastPlayed=-Infinity,expires=0,generation=0,loading=false;
let active:AudioBufferSourceNode|undefined;
function enabled(){try{return localStorage.getItem('clube-coin-sound')!=='off';}catch{return true;}}
export function prepareCoinReward(ctx:AudioContext){
 context=ctx;
 let buffer=decoded.get(ctx);
 if(!buffer){
  recording??=fetch('/audio/coin-reward.mp3').then(r=>{if(!r.ok)throw new Error('Áudio indisponível');return r.arrayBuffer();}).catch(e=>{recording=undefined;throw e;});
  buffer=recording.then(bytes=>ctx.decodeAudioData(bytes.slice(0))).catch(e=>{decoded.delete(ctx);throw e;});
  decoded.set(ctx,buffer);
 }
 return buffer;
}
async function flush(ctx:AudioContext){
 if(!enabled()||ctx.state!=='running'||expires<performance.now()||!expires||loading||active)return;
 loading=true;const ticket=generation;
 try{
  const buffer=await prepareCoinReward(ctx);
  if(ticket!==generation||!enabled()||ctx.state!=='running'||expires<performance.now())return;
  expires=0;
  const source=ctx.createBufferSource(),gain=ctx.createGain();source.buffer=buffer;gain.gain.value=.8;
  source.connect(gain);gain.connect(ctx.destination);active=source;lastPlayed=performance.now();
  source.onended=()=>{source.disconnect();gain.disconnect();if(active===source)active=undefined;};source.start();
 }catch{/* Audio failures never prevent receiving coins. */}
 finally{loading=false;}
}
// Invoke synchronously within a pointer/keyboard gesture, before any network work.
export function unlockCoinAudio(){
 try{
  if(!context||context.state==='closed')context=new AudioContext();
  const ctx=context;
  void prepareCoinReward(ctx).catch(()=>{});
  if(ctx.state!=='running')void ctx.resume().then(()=>flush(ctx)).catch(()=>{});
  else void flush(ctx);
  return ctx;
 }catch{return undefined;}
}
export function stopCoinReward(){
 expires=0;generation++;
 if(active){const source=active;active=undefined;try{source.stop();}catch{/* Already ended. */}}
}
export async function playCoinReward(ctx=context){
 if(!enabled()||active||performance.now()-lastPlayed<1800)return;
 expires=performance.now()+10_000;
 if(ctx&&ctx.state!=='closed')context=ctx;
 const ready=unlockCoinAudio();
 if(ready)await flush(ready);
}
