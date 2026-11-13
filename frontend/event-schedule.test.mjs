import {test} from 'node:test';
import assert from 'node:assert/strict';
import {readFile} from 'node:fs/promises';
import ts from 'typescript';
const code=ts.transpileModule(await readFile(new URL('./src/services/event-schedule.ts',import.meta.url),'utf8'),{compilerOptions:{target:ts.ScriptTarget.ES2022,module:ts.ModuleKind.ESNext}}).outputText;
const {eventBoundaryDelay,eventScheduleMessage}=await import('data:text/javascript;base64,'+Buffer.from(code).toString('base64'));
test('event opens at start and closes at end using server time with timezone offsets',()=>{
 const base={startsAt:'2026-11-13T08:00:00-03:00',endsAt:'2026-11-13T18:00:00-03:00'};
 assert.equal(eventBoundaryDelay({...base,status:'not_started',serverNow:'2026-11-13T10:59:00Z'}),60030);
 assert.equal(eventBoundaryDelay({...base,status:'active',serverNow:'2026-11-13T20:59:00Z'}),60030);
 assert.equal(eventBoundaryDelay({...base,status:'active',serverNow:'2026-11-13T21:00:00Z'}),30);
 assert.equal(eventBoundaryDelay({...base,status:'ended',serverNow:'2026-11-13T21:00:00Z'}),null);
 assert.equal(eventBoundaryDelay(undefined),null);
 assert.equal(eventBoundaryDelay({...base,status:'active',serverNow:'bad'}),null);
});
test('before start and after end have distinct child-facing messages',()=>{
 assert.match(eventScheduleMessage({status:'not_started'}),/ainda não começou/);
 assert.match(eventScheduleMessage({status:'ended'}),/terminou/);
 assert.equal(eventScheduleMessage({status:'active'}),'');
});
