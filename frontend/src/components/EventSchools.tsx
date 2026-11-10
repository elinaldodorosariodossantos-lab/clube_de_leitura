import {useState} from 'react';
import {CheckCircle2,Plus,School,Trash2,X} from 'lucide-react';
import {useAdminResource} from '../hooks/useAdminResource';
import {useModalFocus} from '../hooks/useModalFocus';
import {Notice} from './PortalUI';
export type EventSchool={id:string;name:string};
export function EventSchools({selectedIds,initialSchools=[],disabled,onChange}:{selectedIds:string[];initialSchools?:EventSchool[];disabled:boolean;onChange:(ids:string[])=>void}){
 const {data,loading,error,reload}=useAdminResource<EventSchool[]>('/events/admin/schools');
 const [open,setOpen]=useState(false),[search,setSearch]=useState(''),[draft,setDraft]=useState<Set<string>>(new Set());
 useModalFocus(()=>setOpen(false),open);
 const schools=data??initialSchools,needle=search.normalize('NFD').replace(/[\u0300-\u036f]/g,'').toLocaleLowerCase('pt-BR');
 const filtered=schools.filter(s=>s.name.normalize('NFD').replace(/[\u0300-\u036f]/g,'').toLocaleLowerCase('pt-BR').includes(needle));
 function toggle(id:string){setDraft(old=>{const next=new Set(old);if(next.has(id))next.delete(id);else next.add(id);return next;});}
 return <section className="event-schools" aria-labelledby="event-schools-title"><h3 id="event-schools-title"><School size={21}/>ESCOLAS PARTICIPANTES</h3><button type="button" className="club-button secondary" disabled={disabled} onClick={()=>{setDraft(new Set(selectedIds));setSearch('');setOpen(true);}}><Plus size={17}/>Selecionar escolas</button>
 {selectedIds.length?<ul className="event-linked-schools">{selectedIds.map(id=>{const s=schools.find(s=>s.id===id);return <li key={id}><span><strong>{s?.name??'Escola vinculada'}</strong><small><CheckCircle2 size={14}/>Vinculada</small></span><button type="button" disabled={disabled} aria-label={'Remover '+(s?.name??'escola')+' do evento'} onClick={()=>onChange(selectedIds.filter(x=>x!==id))}><Trash2 size={17}/></button></li>;})}</ul>:<p>Nenhuma escola selecionada. Selecione as escolas que participarão deste evento.</p>}
 {open&&<div className="event-school-backdrop"><section className="event-school-dialog" role="dialog" aria-modal="true" aria-labelledby="school-picker-title"><header><h2 id="school-picker-title">Selecionar escolas</h2><button type="button" aria-label="Fechar seleção de escolas" onClick={()=>setOpen(false)}><X size={21}/></button></header><label>Pesquisar escola<input autoComplete="off" onKeyDown={e=>{if(e.key==='Enter')e.preventDefault();}} value={search} onChange={e=>setSearch(e.target.value)} placeholder="Nome da escola"/></label>
 {loading&&<Notice>Consultando escolas cadastradas…</Notice>}{error&&<Notice error>{error}<button type="button" onClick={()=>void reload()}>Tentar novamente</button></Notice>}
 <div className="event-school-selection"><span>{draft.size} selecionadas</span><button type="button" disabled={loading||!!error||!filtered.length} onClick={()=>setDraft(old=>new Set([...old,...filtered.map(s=>s.id)]))}>Selecionar todas da pesquisa</button></div>
 <div className="event-school-options">{filtered.map(s=><label key={s.id}><input type="checkbox" checked={draft.has(s.id)} onChange={()=>toggle(s.id)}/><span><strong>{s.name}</strong>{draft.has(s.id)&&<small>Selecionada</small>}</span></label>)}{!loading&&!error&&!filtered.length&&<p>Nenhuma escola encontrada.</p>}</div>
 <footer><button type="button" className="club-button secondary" onClick={()=>setOpen(false)}>Cancelar</button><button type="button" className="club-button" disabled={loading||!!error} onClick={()=>{onChange([...draft]);setOpen(false);}}>Confirmar seleção</button></footer></section></div>}
 </section>;
}
