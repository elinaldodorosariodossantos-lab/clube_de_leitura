import {test} from 'node:test';
import assert from 'node:assert/strict';
import {pingDatabase} from './ping-database.mjs';
test('daily check reads database settings, never the static health route',async()=>{
 let called;
 const result=await pingDatabase({fetchImpl:async(url,options)=>{called={url:String(url),options};return Response.json({minAge:4,maxAge:19});}});
 assert.equal(called.url,'https://clube-de-leitura-edu.vercel.app/api/portal/settings');
 assert.equal(called.options.cache,'no-store');assert.equal(result.ok,true);assert.equal(result.attempt,1);
});
test('temporary failures retry, while authorization failures do not',async()=>{
 let calls=0,waits=0;
 const result=await pingDatabase({sleep:async()=>{waits++;},fetchImpl:async()=>++calls<3?new Response('',{status:503}):Response.json({minAge:4,maxAge:19})});
 assert.equal(result.attempt,3);assert.equal(waits,2);
 calls=0;await assert.rejects(pingDatabase({fetchImpl:async()=>{calls++;return new Response('',{status:403});}}),/HTTP 403/);assert.equal(calls,1);
});
test('HTML, static health JSON and exhausted outages fail instead of reporting success',async()=>{
 for(const response of [()=>new Response('<html>Login</html>'),()=>Response.json({version:'healthy'})])await assert.rejects(pingDatabase({fetchImpl:async()=>response()}));
 let calls=0;await assert.rejects(pingDatabase({sleep:async()=>{},fetchImpl:async()=>{calls++;throw new Error('Offline');}}),/Offline/);assert.equal(calls,3);
});
