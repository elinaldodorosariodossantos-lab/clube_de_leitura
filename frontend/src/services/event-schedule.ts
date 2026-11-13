import type {EventSchedule} from '../types/portal';

export function eventScheduleMessage(schedule?:EventSchedule){
 if(!schedule)return 'A escola está preparando seus níveis de leitura.';
 if(schedule.status==='not_started')return 'O evento ainda não começou. Aguarde o horário de início para ler suas histórias.';
 if(schedule.status==='ended')return 'O evento terminou. Suas leituras e conquistas estão salvas. Aguarde o próximo evento!';
 if(schedule.status!=='active')return 'Não há um evento de leitura disponível no momento. Aguarde a liberação da escola.';
 return '';
}
// Use the server's clock, including timezone offsets, for refresh boundaries.
export function eventBoundaryDelay(schedule?:EventSchedule){
 if(!schedule)return null;
 const boundary=schedule.status==='active'?schedule.endsAt:schedule.status==='not_started'?schedule.startsAt:null;
 if(!boundary)return null;
 const delay=Date.parse(boundary)-Date.parse(schedule.serverNow);
 return Number.isFinite(delay)?Math.min(2_147_000_000,Math.max(0,delay)+30):null;
}
