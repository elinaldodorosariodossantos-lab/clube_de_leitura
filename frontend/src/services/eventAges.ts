import type {AgeConfig,EventDraft} from '../types/events';
import type {ReadingLevel} from '../types/portal';
import {levelNames} from '../components/ReadingLevels';
export function initialAgeConfigs(event:EventDraft):AgeConfig[]{
 if(event.ageConfigs?.length)return structuredClone(event.ageConfigs);
 return Array.from({length:event.id?event.maxAge-event.minAge+1:1},(_,i)=>({age:event.minAge+i,levels:[{level:event.level,quantity:event.mode==='ordem'?Math.max(1,event.storyIds.length):event.quantity,storyIds:[...event.storyIds]}]}));
}
// Zero é representado pela ausência do nível na estrutura já usada pelo Supabase.
export function withLevelQuantity(config:AgeConfig,level:ReadingLevel,quantity:number):AgeConfig{
 if(!Number.isSafeInteger(quantity)||quantity<0)throw new RangeError('Informe uma quantidade inteira maior ou igual a zero.');
 const existing=config.levels.find(l=>l.level===level);
 return {...config,levels:quantity===0?config.levels.filter(l=>l.level!==level):existing?config.levels.map(l=>l.level===level?{...l,quantity}:l):[...config.levels,{level,quantity,storyIds:[]}]};
}
export function ageConfigError(configs:AgeConfig[]):string{
 if(!configs.length)return 'Adicione ao menos uma idade.';
 if(new Set(configs.map(c=>c.age)).size!==configs.length)return 'Não repita idades no evento.';
 for(const c of configs){
  if(!Number.isInteger(c.age)||c.age<4||c.age>19)return 'Informe idades inteiras entre 4 e 19 anos.';
  if(!c.levels.length)return `Habilite ao menos um nível para ${c.age} anos.`;
  if(new Set(c.levels.map(l=>l.level)).size!==c.levels.length)return `Não repita níveis para ${c.age} anos.`;
  for(const l of c.levels){if(!Number.isInteger(l.quantity)||l.quantity<1)return `Informe uma quantidade inteira maior que zero para ${c.age} anos / ${levelNames[l.level]}.`;}
 }
 return '';
}
export function ageSummary(configs:AgeConfig[]){return configs.map(c=>`${c.age} anos: ${c.levels.map(l=>`${levelNames[l.level]} (${l.quantity})`).join(', ')}`).join(' · ');}
