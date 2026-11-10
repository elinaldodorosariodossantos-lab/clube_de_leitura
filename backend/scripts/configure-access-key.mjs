import {readFile,writeFile} from 'node:fs/promises';
import {randomBytes} from 'node:crypto';
const path=new URL('../.env',import.meta.url);
if(process.env.ACCESS_CREDENTIALS_KEY){
 if(!/^[a-f0-9]{64}$/i.test(process.env.ACCESS_CREDENTIALS_KEY))throw new Error('ACCESS_CREDENTIALS_KEY inválida no ambiente.');
 console.log('Chave fornecida pelo ambiente; mantida.');
}else{
 const contents=await readFile(path,'utf8').catch(e=>{if(e.code==='ENOENT')return '';throw e;});
 const found=contents.match(/^ACCESS_CREDENTIALS_KEY=(.*)$/m);
 if(found?.[1]&&/^[a-f0-9]{64}$/i.test(found[1].trim()))console.log('Chave já configurada; mantida.');
 else if(found?.[1]?.trim())throw new Error('Há uma chave inválida no arquivo. Confira a configuração sem substituir credenciais existentes.');
 else{
  const entry='ACCESS_CREDENTIALS_KEY='+randomBytes(32).toString('hex');
  await writeFile(path,found?contents.replace(/^ACCESS_CREDENTIALS_KEY=.*$/m,entry):contents+'\n'+entry+'\n',{mode:0o600});
  console.log('Chave configurada no backend, sem exibição do segredo. Reinicie a API.');
 }
}
