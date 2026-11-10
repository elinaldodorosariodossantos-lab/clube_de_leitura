import {formatPoints} from '../services/format';
import {BookOpen,Star} from 'lucide-react';
import type {ReadingState} from '../types/portal';

export function WelcomeBanner({name,state,loading}:{name:string;state?:ReadingState;loading:boolean}){
 const required=state?.levels.reduce((total,level)=>total+level.required,0)??0;
 const done=state?.levels.reduce((total,level)=>total+level.requiredCompleted,0)??0;
 return <section className="welcome-banner" aria-label="Sua jornada de leitura">
  <div className="welcome-illustration"><img src="/images/leitora.png" alt=""/></div>
  <div className="welcome-copy"><h1>Olá, {name.split(' ')[0]}!</h1><h2>Vamos continuar sua jornada de leitura?</h2><p>Cada história é uma nova descoberta!</p></div>
  <div className="welcome-stats" aria-busy={loading}>
   <div className="welcome-journey"><span className="welcome-stat-icon"><BookOpen size={30}/></span><div><small>Sua jornada</small><strong>{state?`${done} de ${required}`:'—'}</strong><span>leituras obrigatórias concluídas</span><progress value={done} max={required||1} aria-label="Progresso das leituras obrigatórias da jornada"/></div></div>
   <div className="welcome-points"><span className="welcome-stat-icon"><Star size={30}/></span><div><small>Seus pontos</small><strong>{state?formatPoints(state.student.points):'—'}</strong><span>pontos acumulados</span></div></div>
   <p>{state?`${state.student.completed} leituras concluídas em todas as jornadas.`:loading?'Recuperando suas conquistas…':'Não foi possível carregar o progresso.'}</p>
  </div>
 </section>;
}
