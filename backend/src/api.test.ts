import {test} from 'node:test';
import assert from 'node:assert/strict';
import {spawn} from 'node:child_process';
import {mkdtemp,rm} from 'node:fs/promises';
import {tmpdir} from 'node:os';
import {join,resolve} from 'node:path';
import {randomUUID} from 'node:crypto';
test('API: autorização, conclusão incompleta, idempotência e persistência',async()=>{
 const cwd=await mkdtemp(join(tmpdir(),'clube-test-'));
 const server=resolve('dist/server.js');
 let child=spawn(process.execPath,[server],{cwd,env:{...process.env,DATA_MODE:'demo',PORT:'3099',NODE_ENV:'test'},stdio:'pipe'});
 const ready=()=>new Promise<void>((resolve,reject)=>{child.stdout.on('data',()=>resolve());child.once('error',reject);child.once('exit',code=>reject(new Error('Servidor encerrou: '+code)));});
 const owner=randomUUID();
 async function api(path:string,method='GET',body?:unknown,user:string=owner){return fetch('http://127.0.0.1:3099/api'+path,{method,headers:{Authorization:`Bearer ${user}`,'Content-Type':'application/json'},body:body?JSON.stringify(body):undefined});}
 async function stop(){if(child.exitCode!==null||child.signalCode!==null)return;const exit=new Promise<void>(r=>child.once('exit',()=>r()));child.kill();await exit;}
 try{await ready();assert.equal((await api('/activity','GET',undefined,'')).status,401);
 const activity=await (await api('/activity')).json();assert.ok(activity.questions.every((q:object)=>!('correct' in q)));
 const a=await (await api('/attempts','POST')).json();
 assert.equal((await api('/attempts/'+a.id,'GET',undefined,randomUUID())).status,404);
 assert.equal((await api('/attempts/'+a.id+'/finish','POST')).status,400);
 assert.equal((await api('/attempts/'+a.id+'/answers','PUT',{questionId:1,selected:9})).status,400);
 for(const [i,v] of [0,1,1,2,1].entries())assert.equal((await api('/attempts/'+a.id+'/answers','PUT',{questionId:i+1,selected:v})).status,200);
 const responses=await Promise.all([api('/attempts/'+a.id+'/finish','POST'),api('/attempts/'+a.id+'/finish','POST')]);
 const results=await Promise.all(responses.map(r=>r.json()));assert.deepEqual(results[0],results[1]);assert.equal(results[0].result.points,50);
 assert.equal((await api('/attempts/'+a.id+'/answers','PUT',{questionId:1,selected:1})).status,409);
 assert.equal((await (await api('/history')).json()).length,1);
 await stop();child=spawn(process.execPath,[server],{cwd,env:{...process.env,DATA_MODE:'demo',PORT:'3099',NODE_ENV:'test'},stdio:'pipe'});await ready();
 assert.equal((await (await api('/attempts/'+a.id)).json()).result.points,50);
 }finally{await stop();await rm(cwd,{recursive:true,force:true});}
});
