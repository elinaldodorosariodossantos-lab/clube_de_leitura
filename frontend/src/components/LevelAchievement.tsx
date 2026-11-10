import {formatPoints as number} from '../services/format';
import {useEffect,useRef,useState,type CSSProperties} from 'react';
import {ArrowRight,BookOpen,CheckCircle2,Coins,LogOut,Star,UserRound} from 'lucide-react';
import {useModalFocus} from '../hooks/useModalFocus';
import {levelNames} from './ReadingLevels';
import {GoldCoin,RewardTrophy} from './RewardArtwork';
import type {LevelAchievementData} from '../types/portal';
import '../achievement.css';
type Props={celebrate?:boolean;achievement:LevelAchievementData;studentName?:string;busy:boolean;error?:string;message?:string;onContinue:()=>void;onClose:()=>void;onLogout?:()=>void};
export function LevelAchievement({achievement:a,celebrate=false,studentName,busy,error,message,onContinue,onClose,onLogout}:Props){
 const [displayed,setDisplayed]=useState({points:celebrate?0:a.points,coins:celebrate?0:(a.coins??0)});
 useEffect(()=>{if(!celebrate||window.matchMedia('(prefers-reduced-motion: reduce)').matches){setDisplayed({points:a.points,coins:a.coins??0});return;}let frame=0;const started=performance.now();const tick=(now:number)=>{const progress=Math.min(1,(now-started)/1400),ratio=1-Math.pow(1-progress,3);setDisplayed({points:a.points*ratio,coins:(a.coins??0)*ratio});if(progress<1)frame=requestAnimationFrame(tick);};setDisplayed({points:0,coins:0});frame=requestAnimationFrame(tick);return()=>cancelAnimationFrame(frame);},[a.id,a.points,a.coins,celebrate]);
 const panel=useRef<HTMLElement>(null);
 useModalFocus(()=>{if(!busy)onClose();});
 useEffect(()=>{if(!busy&&panel.current&&!panel.current.contains(document.activeElement))panel.current.querySelector<HTMLButtonElement>('button:not(:disabled)')?.focus();},[busy]);
 const next=a.nextLevel?levelNames[a.nextLevel]:null,modern=(a.scoreVersion??1)>=2;
 return <div className="achievement-backdrop"><section ref={panel} className={"level-achievement reward-simple reward-results"+(celebrate?" is-celebrating":"")} role="dialog" aria-modal="true" aria-labelledby="achievement-title" aria-describedby="achievement-message">
  <header className="reward-header"><span className="reward-brand"><BookOpen/><strong>Clube da Leitura <em>2026</em></strong></span><span className="reward-account">{studentName&&<span><UserRound size={20}/>Olá, {studentName.split(' ')[0]}!</span>}<button onClick={onLogout??onClose} disabled={busy}><LogOut size={19}/>{onLogout?'Sair':'Voltar ao clube'}</button></span></header>
  <div className="reward-landscape" aria-hidden="true"><span className="reward-cloud cloud-left"/><span className="reward-cloud cloud-right"/><span className="reward-foliage foliage-left"/><span className="reward-foliage foliage-right"/>{Array.from({length:14},(_,i)=><GoldCoin key={i} className={'landscape-coin coin-'+i}/>)}</div>
  <div className="achievement-confetti" aria-hidden="true">{Array.from({length:32},(_,i)=><i key={i} style={{'--x':`${(i*37)%100}%`,'--delay':`${(i%8)*.09}s`,'--turn':`${i*43}deg`,'--color':['#2474ec','#ffbf38','#e750c5','#38bb9a'][i%4]} as CSSProperties}/>)}</div>
  <div className="reward-body">
   <div className="achievement-medal"><RewardTrophy/></div>
   <div className="reward-hero"><span className="reward-complete"><CheckCircle2/>{`Nível ${levelNames[a.level]} concluído`}</span><h1 id="achievement-title">Parabéns!</h1><p id="achievement-message">{message??'Todas as leituras e atividades foram concluídas. Suas conquistas estão salvas!'}</p>
    <div className="reward-coins"><span className="coin-stack" aria-hidden="true"><GoldCoin/><GoldCoin/><GoldCoin/></span><div><strong>{modern?`${new Intl.NumberFormat('pt-BR',{maximumFractionDigits:2}).format(displayed.coins)} moedas`:`${number(displayed.points)} pontos`}</strong></div><Star className="reward-sparkle" aria-hidden="true"/></div>
    <span className="reward-balance"><Coins size={19}/>Seu saldo: <strong>{number(a.coinBalance??0)} moedas</strong></span>
   </div>
   {a.eventId&&!!a.ranking?.length&&<section className="level-ranking-summary level-completion-ranking" aria-labelledby="level-ranking-title"><h2 id="level-ranking-title">Ranking do nível {levelNames[a.level]}</h2><ol className="level-ranking-list">{[...a.ranking].sort((x,y)=>x.position-y.position).map(row=><li key={row.position} className={row.self?'is-self':''}><span className="level-ranking-position">{row.position}º</span><span className="level-ranking-person"><strong>{row.name}{row.self?' (Você)':''}</strong>{row.school&&<small>{row.school}</small>}</span><strong className="level-ranking-points">{number(row.points)}<small>pontos</small></strong></li>)}</ol></section>}
   <div className="reward-next">{next?<p>Próxima etapa: nível <strong>{next}</strong>. Você pode parar e voltar depois; seu progresso fica salvo.</p>:<><div className="achievement-unlock"><CheckCircle2/><strong>Jornada concluída!</strong></div><p>Você concluiu os níveis disponíveis para você. Suas conquistas estão salvas!</p></>}{error&&<p role="alert" className="achievement-error">{error}</p>}<button className="club-button achievement-continue" disabled={busy} onClick={onContinue}>{busy?'Abrindo sua próxima etapa…':next?'Continuar':'Ver meu progresso'}<ArrowRight size={27}/></button>{next&&<button className="achievement-later" disabled={busy} onClick={onClose}>Continuar depois</button>}</div>
  </div>
 </section></div>;
}
