import {test} from 'node:test';
import assert from 'node:assert/strict';
import {readFile} from 'node:fs/promises';
import ts from 'typescript';
const source=await readFile(new URL('./src/services/admin-overview.ts',import.meta.url),'utf8');
const code=ts.transpileModule(source,{compilerOptions:{target:ts.ScriptTarget.ES2022,module:ts.ModuleKind.ESNext}}).outputText;
const {overviewDay,registrationSeries,overviewReaderHighlights}=await import('data:text/javascript;base64,'+Buffer.from(code).toString('base64'));

test('dashboard registrations use Fortaleza dates and the complete selected interval',()=>{
 const students=[{createdAt:'2026-11-15T02:30:00Z'},{createdAt:'2026-11-15T03:01:00Z'},{createdAt:'2026-11-08T02:00:00Z'},{createdAt:'invalid'},{createdAt:'2026-11-16T12:00:00Z'}];
 assert.equal(overviewDay(students[0].createdAt),'2026-11-14');
 const series=registrationSeries(students,7,'2026-11-15T12:00:00Z');
 assert.equal(series.length,7);assert.equal(series[0].day,'2026-11-09');
 assert.equal(series.at(-2).count,1);assert.equal(series.at(-1).count,1);
 assert.equal(series.reduce((n,d)=>n+d.count,0),2);
 assert.deepEqual(registrationSeries(students,30,'invalid'),[]);
});
test('reader highlights do not invent leaders, rank ties or participation',()=>{
 assert.deepEqual(overviewReaderHighlights([]),{participating:0,participation:0,leaders:[]});
 const students=[{id:'a',completed:1,points:15},{id:'b',completed:2,points:15},{id:'c',completed:0,points:0}];
 const result=overviewReaderHighlights(students);
 assert.equal(result.participating,2);assert.equal(result.participation,67);
 assert.deepEqual(result.leaders.map(s=>s.id),['a','b']);
 assert.equal(overviewReaderHighlights([{completed:0,points:0}]).leaders.length,0);
});
