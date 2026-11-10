import {test} from 'node:test';
import assert from 'node:assert/strict';
import {createServer as httpServer} from 'node:http';
import {fileURLToPath} from 'node:url';
import express from 'express';
import {createServer,loadConfigFromFile} from 'vite';
import {portal} from '../backend/dist/portal.js';

test('proxy real do Vite: formulário da mesma origem passa e origens externas são recusadas',async()=>{
 const previous={url:process.env.SUPABASE_URL,key:process.env.SUPABASE_ANON_KEY,origin:process.env.APP_ORIGIN};
 process.env.SUPABASE_URL='http://127.0.0.1:1';process.env.SUPABASE_ANON_KEY='public-test-key';delete process.env.APP_ORIGIN;
 const app=express();app.use(express.json());app.use('/api/portal',portal);const backend=httpServer(app);
 let vite;
 try{
  await new Promise(r=>backend.listen(0,'127.0.0.1',r));
  const root=fileURLToPath(new URL('.',import.meta.url));
  const loaded=await loadConfigFromFile({command:'serve',mode:'test'},fileURLToPath(new URL('./vite.config.ts',import.meta.url)));
  const options=loaded.config.server.proxy['/api'];
  vite=await createServer({configFile:false,root,logLevel:'silent',server:{host:'127.0.0.1',port:0,proxy:{'/api':{...options,target:`http://127.0.0.1:${backend.address().port}`}}}});
  await vite.listen();
  const base=`http://127.0.0.1:${vite.httpServer.address().port}`;
  async function submit(origin){return fetch(base+'/api/portal/register',{method:'POST',headers:{'Content-Type':'application/json',...(origin?{Origin:origin}:{})},body:'{}'});}
  const valid=await submit(base);assert.equal(valid.status,400);assert.match((await valid.json()).error,/nome completo/);
  for(const origin of ['https://untrusted.test','invalid-origin',undefined])assert.equal((await submit(origin)).status,403);
  process.env.APP_ORIGIN='https://clube.example';
  assert.equal((await submit('https://clube.example')).status,400);
  assert.equal((await submit(base)).status,403);
 }finally{
  await vite?.close();backend.closeAllConnections();await new Promise(r=>backend.close(r));
  for(const [name,value] of Object.entries({SUPABASE_URL:previous.url,SUPABASE_ANON_KEY:previous.key,APP_ORIGIN:previous.origin}))if(value===undefined)delete process.env[name];else process.env[name]=value;
 }
});
