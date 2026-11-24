import {confirmAction} from '../services/confirmation';
import {useEffect} from 'react';
import {registerFormGuard} from '../services/management';
export function useUnsavedForm(dirty:boolean){useEffect(()=>{if(!dirty)return;const warning=(e:BeforeUnloadEvent)=>{e.preventDefault();e.returnValue='';};window.addEventListener('beforeunload',warning);const stop=registerFormGuard(()=>confirmAction('Você tem alterações que ainda não foram salvas. Se sair agora, elas serão descartadas.',{title:'Sair sem salvar?',confirmLabel:'Sair sem salvar',cancelLabel:'Continuar editando',danger:true}));return()=>{stop();window.removeEventListener('beforeunload',warning);};},[dirty]);}
