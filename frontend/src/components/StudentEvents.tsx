import {BookOpen,CalendarDays,CheckCircle2} from 'lucide-react';
import {Notice} from './PortalUI';
import {useAdminResource} from '../hooks/useAdminResource';
import {levelNames} from './ReadingLevels';
import {eventDate} from '../services/events';
import type {StudentEvent} from '../types/events';
import '../events.css';
export function StudentEvents({busy,onEnter}:{busy:boolean;onEnter:(id:string)=>void}){
 const {data,loading,error,reload}=useAdminResource<StudentEvent[]>('/events/mine');
 if(!loading&&!error&&data?.length===0)return null;
 return <section className="student-events" aria-label="Meus eventos de leitura"><h2>Meus eventos de leitura</h2>{loading&&<Notice>Consultando seus eventos…</Notice>}{error&&<Notice error>{error}<button onClick={()=>void reload()}>Tentar novamente</button></Notice>}{data&&!data.length&&<p>Não há eventos liberados para sua escola no momento.</p>}<div className="event-cards">{data?.map(event=><article className="event-card" key={event.id}><div className={'event-cover '+event.level}>{event.cover?<img src={event.cover} alt=""/>:<><BookOpen size={34}/><strong>{event.name}</strong></>}</div><h3>{event.name}</h3><p>{event.description}</p><div className="event-badges">{event.assignedLevels?.length?event.assignedLevels.map(l=><span key={l.level} className={l.level}>{levelNames[l.level]} · {l.quantity} histórias</span>):<span className={event.level}>{levelNames[event.level]}</span>}<span>{event.age?`${event.age} anos`:`${event.minAge} a ${event.maxAge} anos`}</span></div><p><CalendarDays size={15}/>{eventDate(event.startsAt)} → {eventDate(event.endsAt)}</p>{event.assignedStories?.length?(['facil','medio','dificil'] as const).map(level=>{const stories=event.assignedStories!.filter(s=>s.level===level);return stories.length?<section key={level}><h4>{levelNames[level]}</h4><ol>{stories.map(story=><li key={story.id}>{story.title}{story.completed?' ✓':''}</li>)}</ol></section>:null;}):null}<progress max={event.total} value={event.completed} aria-label={'Progresso em '+event.name}/><p>{event.completed} de {event.total} histórias concluídas</p>{event.completed===event.total?<p><CheckCircle2 size={18}/>Evento concluído!</p>:<button className="club-button" disabled={busy} onClick={()=>onEnter(event.id)}>{busy?'Abrindo…':event.ongoing||event.completed?'Continuar leitura':'Começar leitura'}</button>}</article>)}</div></section>;
}
