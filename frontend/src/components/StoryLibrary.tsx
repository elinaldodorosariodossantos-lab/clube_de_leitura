import {useState} from 'react';
import {BookOpen} from 'lucide-react';
import {useAdminResource} from '../hooks/useAdminResource';
import {levelNames} from './ReadingLevels';
import {Notice} from './PortalUI';
import type {StoryRow} from '../types/management';

export function StoryLibrary({busy,onSelect}:{busy:boolean;onSelect:(id:string)=>Promise<void>}){
 const [open,setOpen]=useState(false),[search,setSearch]=useState('');
 const {data,loading,error,reload}=useAdminResource<StoryRow[]>('/admin/manage/stories?'+new URLSearchParams({search}),!open);
 return <fieldset disabled={busy} className="story-library"><legend>Banco de histórias</legend>
  <p>Reaproveite uma história cadastrada com suas páginas, imagens e perguntas. Escolha a idade e o nível para o novo cadastro.</p>
  <button type="button" aria-expanded={open} aria-controls="story-library-results" onClick={()=>setOpen(value=>!value)}><BookOpen size={18} aria-hidden="true"/>{open?'Fechar banco de histórias':'Buscar história cadastrada'}</button>
  {open&&<div id="story-library-results">
   <label>Buscar por título ou autor<input type="search" maxLength={120} value={search} onChange={event=>setSearch(event.target.value)}/></label>
   {loading?<Notice>Buscando histórias…</Notice>:error?<Notice error>{error}<button type="button" onClick={()=>void reload()}>Tentar novamente</button></Notice>:<>
    <ul className="story-library-list">{data?.map(story=><li key={story.id}><div><strong>{story.title}</strong><small>{story.author||'Autor não informado'} · {story.age} · {levelNames[story.level]} · {story.active?'Ativa':'Rascunho / inativa'}</small></div><button type="button" aria-label={'Usar história '+story.title} onClick={()=>void onSelect(story.id)}>Usar história</button></li>)}</ul>
    {!data?.length&&<Notice>Nenhuma história encontrada.</Notice>}
   </>}
  </div>}
 </fieldset>;
}
