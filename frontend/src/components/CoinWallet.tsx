import {unlockCoinAudio,stopCoinReward,synchronizeCoinReward} from '../services/coin-audio';
import {useEffect,useRef,useState} from 'react';
import {Volume2,VolumeX} from 'lucide-react';
import {WalletCoins} from './WalletCoins';
import {formatPoints} from '../services/format';
export function CoinWallet({balance}:{balance?:number}){
 const [shown,setShown]=useState(balance??0),[reward,setReward]=useState(0),[sound,setSound]=useState(()=>{try{return localStorage.getItem('clube-coin-sound')!=='off';}catch{return true;}});
 const previous=useRef<number|undefined>(balance),frame=useRef(0),timer=useRef<ReturnType<typeof setTimeout>|undefined>(undefined);
 useEffect(()=>{const unlock=()=>{unlockCoinAudio();};window.addEventListener('pointerdown',unlock);window.addEventListener('keydown',unlock);window.addEventListener('click',unlock);return()=>{window.removeEventListener('pointerdown',unlock);window.removeEventListener('keydown',unlock);window.removeEventListener('click',unlock);cancelAnimationFrame(frame.current);clearTimeout(timer.current);};},[]);
 useEffect(()=>{if(balance===undefined)return;const before=previous.current;previous.current=balance;cancelAnimationFrame(frame.current);clearTimeout(timer.current);if(before===undefined||balance<=before){setShown(balance);setReward(0);return;}
  const cancel=synchronizeCoinReward(()=>{const reduced=window.matchMedia('(prefers-reduced-motion: reduce)').matches;setReward(balance-before);const start=performance.now();const step=(now:number)=>{const p=Math.min((now-start)/1400,1);setShown(before+(balance-before)*(1-Math.pow(1-p,3)));if(p<1)frame.current=requestAnimationFrame(step);};if(reduced)setShown(balance);else frame.current=requestAnimationFrame(step);timer.current=setTimeout(()=>setReward(0),2100);
  },2100);return()=>{cancel();cancelAnimationFrame(frame.current);clearTimeout(timer.current);};
 },[balance]);
 function toggle(){const next=!sound;try{localStorage.setItem('clube-coin-sound',next?'on':'off');}catch{}setSound(next);if(next){unlockCoinAudio();}else stopCoinReward();}
 return <><span className={'student-wallet'+(reward?' wallet-reward':'')} aria-label={balance===undefined?'Consultando moedas':'Saldo: '+formatPoints(balance)+' moedas de leitura'}><WalletCoins/><span className="wallet-amount"><strong>{balance===undefined?'—':formatPoints(shown)}</strong><small>Moedas de leitura</small></span><button type="button" className="wallet-sound" onClick={toggle} aria-label={sound?'Desativar som das moedas':'Ativar som das moedas'} aria-pressed={sound} title={sound?'Desativar som':'Ativar som'}>{sound?<Volume2 size={16}/>:<VolumeX size={16}/>}</button></span>{reward>0&&<div className="wallet-coin-rain" aria-hidden="true" key={balance}>{Array.from({length:9},(_,i)=><span className="wallet-falling-coin" key={i} style={{left:(10+i*10)+'%',animationDelay:i*.1+'s'}}>★</span>)}<strong>+ {formatPoints(reward)} moedas!</strong></div>}</>;
}
