import {test} from 'node:test';
import assert from 'node:assert/strict';
import {score,activity} from './activity.js';
test('pontuação de zero a cinco acertos',()=>{for(let hits=0;hits<=5;hits++){const key=[0,1,1,2,1];const answers=Object.fromEntries(key.map((v,i)=>[i+1,i<hits?v:(v+1)%4]));const r=score(answers);assert.equal(r.points,hits*10);assert.equal(r.hits,hits);assert.equal(r.percentage,hits*20);}});
test('rejeita respostas incompletas e alternativas inválidas',()=>{assert.throws(()=>score({1:0}));assert.throws(()=>score({1:4,2:1,3:1,4:2,5:1}));});
test('atividade pública não contém gabarito',()=>assert.ok(activity.questions.every(q=>!('correct' in q))));
