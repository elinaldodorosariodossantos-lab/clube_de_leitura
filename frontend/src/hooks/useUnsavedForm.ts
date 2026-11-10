import {useEffect} from 'react';
import {registerFormGuard} from '../services/management';
export function useUnsavedForm(dirty:boolean){useEffect(()=>{if(!dirty)return;const warning=(e:BeforeUnloadEvent)=>{e.preventDefault();e.returnValue='';};window.addEventListener('beforeunload',warning);const stop=registerFormGuard(()=>window.confirm('Há alterações não salvas. Deseja sair sem salvar?'));return()=>{stop();window.removeEventListener('beforeunload',warning);};},[dirty]);}
