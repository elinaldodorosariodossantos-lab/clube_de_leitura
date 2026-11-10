import PDFDocument from 'pdfkit';
import QRCode from 'qrcode';
import {readCredentials} from './credentials.js';
export type CredentialRecord={id:string;name:string;className:string;schoolYear:number;encrypted:string|null};
export async function schoolCredentialsPdf(school:string,students:CredentialRecord[],base:string):Promise<Buffer>{
 if(!students.length)throw Object.assign(new Error('Nenhum aluno encontrado para emitir credenciais.'),{status:400});
 const ordered=[...students].sort((a,b)=>a.schoolYear-b.schoolYear||a.className.localeCompare(b.className,'pt-BR',{numeric:true})||a.name.localeCompare(b.name,'pt-BR'));
 const cards=ordered.map(student=>{if(!student.encrypted)throw Object.assign(new Error('Há alunos sem credencial recuperável. Nenhum código foi alterado.'),{status:409});let credential;try{credential=readCredentials(student.encrypted);}catch{throw Object.assign(new Error('Não foi possível ler uma credencial existente. Nenhum código foi alterado.'),{status:409});}if(!credential.code||!credential.token)throw Object.assign(new Error('Uma credencial existente está incompleta.'),{status:409});return {...student,code:credential.code,link:base.replace(/\/+$/,'')+'/#/acesso/'+credential.token};});
 const doc=new PDFDocument({size:'A4',margin:0,autoFirstPage:false,info:{Title:'Credenciais - '+school,Author:'Clube da Leitura'}}),chunks:Buffer[]=[];
 function fit(text:string,x:number,y:number,width:number,height:number,font:string,size:number){doc.font(font).fontSize(size);while(size>4&&doc.heightOfString(text,{width,align:'center',lineGap:1})>height){size-=.25;doc.fontSize(size);}doc.text(text,x,y,{width,height,align:'center',lineGap:1});}
 const result=new Promise<Buffer>((resolve,reject)=>{doc.on('data',(chunk:Buffer)=>chunks.push(chunk));doc.on('end',()=>resolve(Buffer.concat(chunks)));doc.on('error',reject);});
 try{for(let i=0;i<cards.length;i++){
  if(i%6===0)doc.addPage();
  // A4: 10 mm outer margins, 4 mm cutting gutters, three columns and two rows.
  const margin=28.35,gap=11.34,width=(doc.page.width-2*margin-2*gap)/3,height=(doc.page.height-2*margin-gap)/2;
  const card=cards[i],slot=i%6,x=margin+(slot%3)*(width+gap),y=margin+Math.floor(slot/3)*(height+gap),inner=width-16;
  doc.lineWidth(.8).strokeColor('#000000').rect(x,y,width,height).stroke().fillColor('#000000');
  fit(school.toLocaleUpperCase('pt-BR'),x+8,y+12,inner,57,'Helvetica-Bold',10);
  const qr=await QRCode.toBuffer(card.link,{width:600,margin:4,errorCorrectionLevel:'M'});doc.image(qr,x+(width-136)/2,y+76,{width:136,height:136});
  fit(card.link,x+8,y+217,inner,54,'Helvetica',7);
  doc.link(x+8,y+217,inner,54,card.link);
  fit(card.code,x+8,y+283,inner,33,'Helvetica-Bold',25);
  fit(card.name.toLocaleUpperCase('pt-BR'),x+8,y+324,inner,33,'Helvetica-Bold',11);
  fit(card.className+' | '+card.schoolYear,x+8,y+height-23,inner,16,'Helvetica-Bold',10);
 }doc.end();return await result;}catch(error){doc.end();await result.catch(()=>{});throw error;}
}
