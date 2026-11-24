import {pathToFileURL} from 'node:url';

export async function pingDatabase({baseUrl=process.env.APP_URL||'https://clube-de-leitura-edu.vercel.app',fetchImpl=fetch,sleep=ms=>new Promise(resolve=>setTimeout(resolve,ms))}={}){
 const target=new URL('/api/portal/settings',baseUrl);
 if(target.protocol!=='https:'&&!['localhost','127.0.0.1'].includes(target.hostname))throw new Error('Use um endereço HTTPS para o sistema.');
 for(let attempt=1;attempt<=3;attempt++){
  let retryable=true;
  try{
   const response=await fetchImpl(target,{headers:{Accept:'application/json','Cache-Control':'no-cache'},cache:'no-store',redirect:'error',signal:AbortSignal.timeout(20000)});
   if(!response.ok){retryable=response.status===429||response.status>=500;throw new Error('Consulta ao banco retornou HTTP '+response.status+'.');}
   retryable=false;
   const settings=await response.json();
   if(!settings||!Number.isInteger(settings.minAge)||!Number.isInteger(settings.maxAge)||settings.minAge<0||settings.maxAge<settings.minAge)throw new Error('A resposta não contém as configurações esperadas do banco.');
   return {ok:true,attempt,checkedAt:new Date().toISOString()};
  }catch(error){
   if(!retryable||attempt===3)throw error;
   await sleep(5000);
  }
 }
}
if(process.argv[1]&&import.meta.url===pathToFileURL(process.argv[1]).href){
 try{console.log(JSON.stringify(await pingDatabase()));}
 catch(error){console.error('Falha na verificação diária:',error.message);process.exitCode=1;}
}
