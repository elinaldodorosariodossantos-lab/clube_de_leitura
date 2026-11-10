import {test} from 'node:test';
import assert from 'node:assert/strict';
import {inflateSync} from 'node:zlib';
import {randomUUID} from 'node:crypto';
import {createRequire} from 'node:module';
import {writeFile} from 'node:fs/promises';
import {schoolCredentialsPdf} from './school-credentials-pdf.js';
import {createCredentials,readCredentials} from './credentials.js';
const jsQR=createRequire(import.meta.url)('jsqr') as (data:Uint8ClampedArray,width:number,height:number)=>{data:string}|null;

function streams(pdf:Buffer){
 return [...pdf.toString('latin1').matchAll(/\d+ 0 obj\s*([\s\S]*?)endobj/g)].flatMap(m=>{
  const split=m[1].indexOf('stream\n');if(split<0||!m[1].includes('/FlateDecode'))return [];
  const dict=m[1].slice(0,split),length=Number(dict.match(/\/Length (\d+)/)?.[1]);
  return [{dict,data:inflateSync(Buffer.from(m[1].slice(split+7,split+7+length),'latin1'))}];
 });
}
test('credenciais: 6, 10 e 30 alunos, grade 3 por 2 e leitura dos QR extraídos do PDF',async()=>{
 const previous=process.env.ACCESS_CREDENTIALS_KEY;process.env.ACCESS_CREDENTIALS_KEY='a'.repeat(64);
 try{
  const records=Array.from({length:30},(_,i)=>({id:randomUUID(),name:i===0?'ALBERTH COSTA CORREA DE ALBUQUERQUE E SILVA DOS SANTOS PEREIRA':'ALUNO TESTE '+String(i).padStart(2,'0'),className:i%2?'6º B':'5º A',schoolYear:2026,encrypted:createCredentials().encrypted}));
  const before=JSON.stringify(records),school='CENTRO DE REFER. EDUCACIONAL PROFª MARIA VALDIONICE PEREIRA DA SILVA';
  for(const count of [6,10,30]){
   const selected=records.slice(0,count),pdf=await schoolCredentialsPdf(school,selected,'https://clube.example/'),raw=pdf.toString('latin1');
   assert.equal((raw.match(/\/Type \/Page\b/g)??[]).length,Math.ceil(count/6));
   const content=streams(pdf),pages=content.filter(s=>!s.dict.includes('/Subtype /Image')&&s.data.toString('latin1').includes(' re\n'));
   assert.equal(pages.length,Math.ceil(count/6));
   for(let i=0;i<pages.length;i++){
    const rectangles=[...pages[i].data.toString('latin1').matchAll(/([\d.]+) ([\d.]+) ([\d.]+) ([\d.]+) re\n/g)];
    assert.equal(rectangles.length,Math.min(6,count-i*6),'somente os cartões necessários na última página');
    if(rectangles.length===6){assert.equal(new Set(rectangles.map(r=>r[1])).size,3);assert.equal(new Set(rectangles.map(r=>r[2])).size,2);}
   }
   const images=content.filter(s=>s.dict.includes('/Subtype /Image')&&s.dict.includes('/DeviceRGB'));
   assert.equal(images.length,count);
   const decoded=images.map(({dict,data})=>{
    const width=Number(dict.match(/\/Width (\d+)/)?.[1]),height=Number(dict.match(/\/Height (\d+)/)?.[1]);
    assert.equal(width,600);assert.equal(data.length,width*height*3);
    const rgba=new Uint8ClampedArray(width*height*4);
    for(let i=0;i<width*height;i++){rgba[i*4]=data[i*3];rgba[i*4+1]=data[i*3+1];rgba[i*4+2]=data[i*3+2];rgba[i*4+3]=255;}
    const qr=jsQR(rgba,width,height);assert.ok(qr,'QR impresso decodificável');return qr.data;
   });
   const ordered=[...selected].sort((a,b)=>a.className.localeCompare(b.className,'pt-BR',{numeric:true})||a.name.localeCompare(b.name,'pt-BR'));
   assert.deepEqual(decoded,ordered.map(s=>'https://clube.example/#/acesso/'+readCredentials(s.encrypted).token));
   const text=content.filter(s=>!s.dict.includes('/Subtype /Image')).map(s=>[...s.data.toString('latin1').matchAll(/<([0-9a-f]+)>/gi)].map(h=>Buffer.from(h[1],'hex').toString('latin1')).join('')).join('');
   for(const s of selected){assert.ok(text.includes(s.name));assert.ok(text.includes(readCredentials(s.encrypted).code));}
   await writeFile(new URL('../../.qa/credenciais-'+count+'-alunos.pdf',import.meta.url),pdf);
  }
  assert.equal(JSON.stringify(records),before,'impressão não altera as credenciais');
 }finally{if(previous===undefined)delete process.env.ACCESS_CREDENTIALS_KEY;else process.env.ACCESS_CREDENTIALS_KEY=previous;}
});
