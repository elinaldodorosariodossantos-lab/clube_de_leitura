import {useAdminResource} from '../hooks/useAdminResource';
import type {EligibleStory} from '../types/events';
import {useState} from 'react';
import {Plus,Trash2} from 'lucide-react';
import {Notice} from './PortalUI';
import {levelNames} from './ReadingLevels';
import {withLevelQuantity} from '../services/eventAges';
import type {ReadingLevel} from '../types/portal';
import type {AgeConfig} from '../types/events';
const levels=['facil','medio','dificil'] as const;
export function EventAgeStories({configs,onChange,distributed}:{configs:AgeConfig[];onChange:(configs:AgeConfig[])=>void;distributed:boolean}){
 const [error,setError]=useState('');
 function addAge(){const age=Array.from({length:16},(_,i)=>i+4).find(a=>!configs.some(c=>c.age===a));if(age!==undefined){setError('');onChange([...configs,{age,levels:[]}]);}}
 function changeAge(index:number,age:number){
  if(!Number.isInteger(age)||age<4||age>19){setError('Informe uma idade inteira entre 4 e 19 anos.');return;}
  if(configs.some((c,i)=>i!==index&&c.age===age)){setError('Essa idade já está configurada.');return;}
  if(distributed&&!window.confirm('Alterar a idade e limpar somente os conjuntos futuros? As atribuições e o histórico existentes serão preservados.'))return;
  setError('');onChange(configs.map((c,i)=>i===index?{...c,age,levels:c.levels.map(l=>({...l,storyIds:[]}))}:c));
 }
 function removeAge(index:number){
  if(distributed&&!window.confirm('Remover esta idade da configuração futura? As atribuições, leituras, respostas e pontuações existentes serão preservadas.'))return;
  setError('');onChange(configs.filter((_,i)=>i!==index));
 }
 function quantity(index:number,level:ReadingLevel,value:number){
  if(!Number.isSafeInteger(value)||value<0){setError('Informe uma quantidade inteira maior ou igual a zero.');return;}
  const previous=configs[index].levels.find(l=>l.level===level);
  if(value===0&&previous&&distributed&&!window.confirm('Desativar este nível para novos envios? O conjunto futuro será removido; atribuições e histórico serão preservados.'))return;
  setError('');
  onChange(configs.map((c,i)=>i===index?withLevelQuantity(c,level,value):c));
 }
 const addButton=<button type="button" className="age-row-icon" disabled={configs.length>=16} onClick={addAge} aria-label="Adicionar idade" title="Adicionar idade"><Plus size={18}/></button>;
 return <div className="event-age-configs compact-age-configs"><p className="age-quantity-help">Histórias por aluno em cada nível. <strong>0 = nível não utilizado.</strong></p>{error&&<Notice error>{error}</Notice>}
 {configs.map((c,index)=><section className="compact-age-row" key={index}><div className="age-quantity-row"><label className="age-number">Idade (anos)<input type="number" required min={4} max={19} step={1} value={c.age} aria-label={'Idade da linha '+(index+1)} onChange={e=>changeAge(index,Number(e.target.value))}/></label>
 {levels.map(level=>{const config=c.levels.find(l=>l.level===level);return <div className={'age-quantity-cell '+level} key={level}><label>{levelNames[level]}<input type="number" required min={0} step={1} value={config?.quantity??0} aria-label={'Quantidade de histórias por aluno - '+levelNames[level]+': '+c.age+' anos'} onChange={e=>quantity(index,level,Number(e.target.value))}/></label></div>;})}
 <div className="age-row-actions">{addButton}<button type="button" className="age-row-icon remove" onClick={()=>removeAge(index)} aria-label={'Remover idade '+c.age} title="Remover idade"><Trash2 size={17}/></button></div></div>
 <div className="age-availability-list">{c.levels.map(config=><Availability key={c.age+'-'+config.level} age={c.age} level={config.level} quantity={config.quantity}/>)}</div>
 {!c.levels.length&&<small className="age-row-empty">Defina uma quantidade acima de zero em pelo menos um nível.</small>}

 </section>)}
 {!configs.length&&addButton}</div>;
}
function Availability({age,level,quantity}:{age:number;level:ReadingLevel;quantity:number}){
 const resource=useAdminResource<EligibleStory[]>('/events/admin/stories?'+new URLSearchParams({level,minAge:String(age),maxAge:String(age)}));
 const label=levelNames[level]+' · '+age+' anos';
 if(resource.loading)return <p className="age-availability" role="status">{label}: consultando biblioteca…</p>;
 if(resource.error||!Array.isArray(resource.data))return <div className="age-availability age-availability-error" role="alert">{label}: {resource.error||'Não foi possível consultar a biblioteca.'} <button type="button" onClick={()=>void resource.reload()}>Tentar novamente</button></div>;
 const count=resource.data.filter(s=>s.active&&s.eligible).length;
 return <p className={'age-availability '+(quantity>count?'age-availability-warning':'')} role="status"><strong>{label}:</strong> {count===0?'Nenhuma história publicada e compatível encontrada. Confira a faixa etária e a publicação no cadastro de Histórias.':quantity>count?count+' histórias disponíveis; '+quantity+' solicitadas. Reduza a quantidade ou publique mais histórias compatíveis.':count+' histórias disponíveis.'}</p>;
}
