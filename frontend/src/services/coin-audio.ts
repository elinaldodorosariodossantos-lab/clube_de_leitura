// Impactos metalicos e coleta arcade, sintetizados localmente.
export function playCoinReward(ctx:AudioContext){
 if(ctx.state!=='running')return;
 const rate=ctx.sampleRate,duration=1.65,buffer=ctx.createBuffer(1,Math.ceil(rate*duration),rate),samples=buffer.getChannelData(0);
 const strikes=[0,.105,.205,.305,.405,.515,.625,.755,.9,1.04];
 let seed=72819;const noise=()=>{seed=(seed*1664525+1013904223)>>>0;return seed/2147483648-1;};
 strikes.forEach((at,index)=>{const pitch=[1,1.06,.98,1.12,1.04,1.18,1.1,1.25,1.16,1.33][index];const length=.32;
  for(let i=0;i<rate*length;i++){const t=i/rate,pos=Math.floor(at*rate)+i;if(pos>=samples.length)break;
   const attack=Math.min(1,t/.0015);
   // Parciais nao harmonicas: borda e corpo da moeda batendo.
   const metal=Math.sin(2*Math.PI*2140*pitch*t)*.075*Math.exp(-t*19)+Math.sin(2*Math.PI*3472*pitch*t)*.04*Math.exp(-t*29)+Math.sin(2*Math.PI*5261*pitch*t)*.018*Math.exp(-t*43);
   // Salto de altura curto, caracteristico de uma moeda coletada em jogos.
   const base=index===strikes.length-1?1568:1318.51;const split=.028,phase=2*Math.PI*base*pitch*(Math.min(t,split)+1.5*Math.max(0,t-split));
   const arcade=(Math.sin(phase)+.18*Math.sin(phase*3))*.045*Math.exp(-t*15);
   const click=noise()*.07*Math.exp(-t*340);
   samples[pos]+=attack*(metal+arcade+click)*(.85+index*.015)*Math.min(1,(length-t)/.02);
  }
 });
 const source=ctx.createBufferSource(),gain=ctx.createGain();source.buffer=buffer;gain.gain.value=.8;source.connect(gain);gain.connect(ctx.destination);source.onended=()=>{source.disconnect();gain.disconnect();};source.start();
}
