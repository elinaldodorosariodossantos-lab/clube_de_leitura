// Original recording supplied in som/som de moedas.mpeg (MPEG audio).
let context:AudioContext|undefined;
let recording:Promise<ArrayBuffer>|undefined;
const decoded=new WeakMap<AudioContext,Promise<AudioBuffer>>();
let lastPlayed=-Infinity;
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
export function stopCoinReward(){active?.stop();active=undefined;}
export async function playCoinReward(ctx=context){
 if(!enabled()||!ctx||ctx.state!=='running'||performance.now()-lastPlayed<1800)return;
 lastPlayed=performance.now();
 try{
  const buffer=await prepareCoinReward(ctx);
  if(!enabled()||ctx.state!=='running'||active)return;
  const source=ctx.createBufferSource(),gain=ctx.createGain();source.buffer=buffer;gain.gain.value=.8;
  source.connect(gain);gain.connect(ctx.destination);active=source;
  source.onended=()=>{source.disconnect();gain.disconnect();if(active===source)active=undefined;};source.start();
 }catch{/* Sound failure must not interrupt the reward. */}
}
