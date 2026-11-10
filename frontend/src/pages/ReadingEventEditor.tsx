import {useRef,useState} from 'react';
import {ArrowLeft,ArrowRight,Upload,Trash2} from 'lucide-react';
import {Notice} from '../components/PortalUI';
import {EventAgeStories} from '../components/EventAgeStories';
import {EventSchools} from '../components/EventSchools';
import {EventSchedule} from '../components/EventSchedule';
import {ageConfigError,initialAgeConfigs} from '../services/eventAges';
import {useUnsavedForm} from '../hooks/useUnsavedForm';
import {eventApi} from '../services/events';
import type {EventDraft} from '../types/events';
function localDate(iso:string){if(!iso)return '';const d=new Date(iso);return new Date(d.getTime()-d.getTimezoneOffset()*60000).toISOString().slice(0,16);}
export function EventEditor({initial,onClose,onSaved}:{initial:EventDraft;onClose:()=>void;onSaved:()=>Promise<void>}){
 const [step,setStep]=useState(0);
 const [data,setData]=useState({...initial,schoolIds:initial.schoolIds??[],ageConfigs:initialAgeConfigs(initial),startsAt:localDate(initial.startsAt),endsAt:localDate(initial.endsAt)}),[dirty,setDirty]=useState(false),[busy,setBusy]=useState(false),[error,setError]=useState('');const imageInput=useRef<HTMLInputElement>(null);const saving=useRef(false),requestId=useRef(crypto.randomUUID());useUnsavedForm(dirty);
 function change<K extends keyof EventDraft>(key:K,value:EventDraft[K]){if(saving.current)return;setData(d=>({...d,[key]:value}));setDirty(true);}
 function back(){if(busy)return;if(step>0){setError('');setStep(step-1);return;}if(!dirty||window.confirm('Descartar as alterações não salvas e voltar para os eventos?'))onClose();}
 async function upload(file?:File){if(!file)return;if(!['image/png','image/jpeg','image/webp'].includes(file.type)||file.size>5*1024*1024){setError('Envie PNG, JPEG ou WebP de até 5 MB.');return;}setBusy(true);try{const response=await fetch('/api/portal/admin/manage/covers',{method:'POST',credentials:'same-origin',headers:{'Content-Type':file.type},body:file});const result=await response.json();if(!response.ok)throw Error(result.error??'Não foi possível enviar a capa.');change('cover',result.url);}catch(e){setError((e as Error).message);}finally{setBusy(false);}}
 async function save(e:React.FormEvent){e.preventDefault();if(saving.current)return;setError('');
  if(step===0){if(data.name.trim().length<2||!data.description.trim()){setError('Preencha o nome e a descrição do evento.');return;}setStep(1);return;}
  const start=Date.parse(data.startsAt),end=Date.parse(data.endsAt);
  if(!Number.isFinite(start)||!Number.isFinite(end)||end<=start){setError('Informe o início e um encerramento posterior ao início do evento.');return;}
  if(step===1){setStep(2);return;}
  if(data.active&&!data.schoolIds.length){setError('Selecione ao menos uma escola participante antes de ativar o evento.');setStep(0);return;}
  const configurationError=ageConfigError(data.ageConfigs);
  if(configurationError){setError(configurationError);return;}
  const storyIds=[...new Set(data.ageConfigs.flatMap(c=>c.levels.flatMap(l=>l.storyIds)))],quantity=Math.max(...data.ageConfigs.map(c=>c.levels.reduce((sum,l)=>sum+l.quantity,0)));
  const minAge=Math.min(...data.ageConfigs.map(c=>c.age)),maxAge=Math.max(...data.ageConfigs.map(c=>c.age)),level=data.ageConfigs[0].levels[0].level;
  if(!Number.isFinite(start)||!Number.isFinite(end)||end<=start){setError('Confira a faixa etária e informe um encerramento posterior ao início.');return;}
  const confirmChanges=!!initial.recipients;
  if(confirmChanges&&!window.confirm('Este evento já foi enviado. A seleção e o conteúdo dos participantes atuais serão preservados; a nova seleção valerá para novos destinatários. O período e a situação serão atualizados para todos. Salvar?'))return;
  saving.current=true;setBusy(true);try{await eventApi('/admin'+(initial.id?'/'+initial.id:''),initial.id?'PUT':'POST',{...data,automatic:true,mode:'sorteio',level,minAge,maxAge,storyIds,quantity,startsAt:new Date(start).toISOString(),endsAt:new Date(end).toISOString(),requestId:requestId.current,confirmChanges});setDirty(false);await onSaved();}catch(e){setError((e as Error).message);}finally{saving.current=false;setBusy(false);}
 }
 const pageTitles=['Informações do evento','Data e situação do evento','Quantidade de histórias por aluno'];
 const pageDescriptions=['Preencha o nome e a descrição. A imagem de capa é opcional.','Informe o início, o encerramento e a situação do evento.','Para cada idade, informe quantas histórias cada aluno receberá em cada nível.'];
 return <section className="event-panel event-wizard event-wizard-simple"><form className="event-editor event-wizard-form" onSubmit={save} aria-busy={busy} aria-labelledby="event-page-title"><button type="button" className="event-wizard-back" disabled={busy} onClick={back}><ArrowLeft size={17} aria-hidden="true"/>Voltar</button><ol className="event-number-timeline" aria-label="Etapas do evento">{[0,1,2].map(index=><li key={index} className={index<step?'completed':index===step?'current':'pending'} aria-current={index===step?'step':undefined}><span className="event-number-bubble" aria-label={'Etapa '+(index+1)+(index<step?' concluída':index===step?' atual':' pendente')}>{index+1}</span></li>)}</ol><header className="event-page-title"><h2 id="event-page-title">{pageTitles[step]}</h2><p>{pageDescriptions[step]}</p></header>{error&&<Notice error>{error}</Notice>}
 {step===0&&<fieldset disabled={busy} className="event-info"><legend><b>1</b> Informações do evento</legend>{initial.schoolsNeedReview&&<Notice>Revise as escolas participantes deste evento. Os vínculos migrados preservam as participações anteriores.</Notice>}<EventSchools selectedIds={data.schoolIds} initialSchools={initial.schools} disabled={busy} onChange={ids=>change('schoolIds',ids)}/><label>Nome do evento *<input required minLength={2} maxLength={160} value={data.name} onChange={e=>change('name',e.target.value)}/></label><label>Descrição *<textarea required maxLength={4000} rows={5} value={data.description} onChange={e=>change('description',e.target.value)}/></label><div className="event-upload"><span className="event-upload-label">Imagem do evento (opcional)</span><button type="button" className="event-upload-button" onClick={()=>imageInput.current?.click()}><Upload size={19} aria-hidden="true"/>Selecionar imagem</button><input ref={imageInput} type="file" hidden aria-label="Selecionar imagem do evento" accept="image/png,image/jpeg,image/webp" onChange={e=>{const file=e.target.files?.[0];e.target.value='';void upload(file);}}/></div>{data.cover&&<div className="event-image-preview"><img src={data.cover} alt="Prévia da capa do evento"/><button type="button" className="event-remove-image" onClick={()=>change('cover','')}><Trash2 size={16} aria-hidden="true"/>Remover imagem</button></div>}<small>PNG, JPEG ou WebP, até 5 MB. Não inclua dados pessoais na capa pública.</small></fieldset>}
 {step===1&&<fieldset disabled={busy}><legend>Data e situação</legend><EventSchedule start={data.startsAt} end={data.endsAt} active={data.active} onStart={value=>change('startsAt',value)} onEnd={value=>change('endsAt',value)} onActive={value=>change('active',value)}/></fieldset>}
 {step===2&&<fieldset disabled={busy} className="event-stories-step"><legend>Painel de histórias</legend><EventAgeStories configs={data.ageConfigs} distributed={!!initial.recipients} onChange={value=>change('ageConfigs',value)}/></fieldset>}
 <footer className="event-wizard-footer"><button key={step} type="submit" className="club-button" disabled={busy}>{busy?'Aguarde…':step<2?'Avançar':'Salvar evento'}{!busy&&<ArrowRight size={17}/>}</button></footer></form></section>;
}
