import {CalendarDays,Clock3,Power} from 'lucide-react';

export function EventSchedule({start,end,active,onStart,onEnd,onActive}:{start:string;end:string;active:boolean;onStart:(value:string)=>void;onEnd:(value:string)=>void;onActive:(value:boolean)=>void}){
 return <><div className="event-schedule-grid"><ScheduleField label="Início do evento" value={start} onChange={onStart}/><ScheduleField label="Encerramento" value={end} min={start} onChange={onEnd}/></div><small className="event-timezone"><Clock3 size={14} aria-hidden="true"/>Horários no fuso deste navegador. Os cartões exibem o horário de Fortaleza.</small><div className={'event-activation '+(active?'is-active':'')}><div><strong>Situação do evento</strong><small>{active?'Disponível aos alunos durante o período definido.':'Ative quando o evento estiver pronto para os alunos.'}</small></div><button type="button" role="switch" aria-checked={active} aria-label="Ativar evento" className="event-status-toggle" onClick={()=>onActive(!active)}><Power size={16} aria-hidden="true"/><span>{active?'Ativo':'Inativo'}</span><span className="event-toggle-track" aria-hidden="true"><span/></span></button></div></>;
}

function ScheduleField({label,value,min,onChange}:{label:string;value:string;min?:string;onChange:(value:string)=>void}){
 const [date='',time='']=value.split('T'),[minDate='',minTime='']=(min??'').split('T');
 return <div className="event-schedule-card"><div className="event-schedule-title"><CalendarDays size={18} aria-hidden="true"/><strong>{label}</strong></div><label>Data<input type="date" required aria-label={'Data: '+label} value={date} min={minDate||undefined} onChange={e=>onChange(e.target.value+'T'+time)}/></label><label className="event-schedule-time"><span><Clock3 size={14} aria-hidden="true"/>Horário</span><input type="time" required step={60} aria-label={'Horário: '+label} value={time} min={date&&date===minDate?minTime:undefined} onChange={e=>onChange(date+'T'+e.target.value)}/></label></div>;
}
