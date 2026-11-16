import {useEffect,useState} from 'react';
import {useAdminResource} from './useAdminResource';
import {portalApi} from '../services/portal';
import type {AdminStudent,AdminStudentsData} from '../types/admin';

/** Complete the existing paged query before deriving any club-wide statistics. */
export function useOverviewReaders(){
 const resource=useAdminResource<AdminStudentsData>('/admin/students?sort=points_desc&pageSize=100&page=1');
 const [readers,setReaders]=useState<AdminStudent[]>(),[pending,setPending]=useState(false),[pageError,setPageError]=useState('');
 useEffect(()=>{
  let active=true;const first=resource.data;setReaders(undefined);setPageError('');
  if(!first){setPending(false);return;}
  setPending(true);
  void (async()=>{
   try{
    const students=[...first.students];
    for(let page=2;students.length<first.total;page++){
     const next=await portalApi<AdminStudentsData>('/admin/students?sort=points_desc&pageSize=100&page='+page);
     if(!active)return;
     if(next.total!==first.total||!next.students.length)throw new Error('Os cadastros mudaram durante a consulta. Atualize os dados para consultar o conjunto completo.');
     students.push(...next.students);
    }
    const unique=[...new Map(students.map(s=>[s.id,s])).values()];
    if(unique.length!==first.total)throw new Error('Não foi possível carregar todos os cadastros. Atualize os dados para tentar novamente.');
    if(active)setReaders(unique);
   }catch(error){if(active)setPageError((error as Error).message);}
   finally{if(active)setPending(false);}
  })();
  return()=>{active=false;};
 },[resource.data]);
 return {readers,loading:resource.loading||pending,error:resource.error||pageError,reload:resource.reload,updatedAt:resource.data?.updatedAt};
}
