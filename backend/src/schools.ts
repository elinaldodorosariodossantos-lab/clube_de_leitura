import {schoolManagement} from './school-management.js';
import {schoolMigrationMissing,schoolMigrationMessage} from './school-errors.js';
import express from 'express';
import {z} from 'zod';
import {hashCredential,readCredentials} from './credentials.js';
export const schools=express.Router();
const filters=z.object({schoolId:z.union([z.uuid(),z.literal(''),z.literal('none')]).default(''),search:z.string().trim().max(120).default(''),className:z.string().max(60).default(''),age:z.union([z.literal(''),z.coerce.number().int().min(0).max(120)]).default(''),period:z.enum(['any','today','7days','30days','custom']).default('any'),from:z.union([z.iso.date(),z.literal('')]).default(''),to:z.union([z.iso.date(),z.literal('')]).default(''),sort:z.enum(['name_asc','name_desc','created_desc','created_asc']).default('name_asc'),page:z.coerce.number().int().min(1).max(1000000).default(1),pageSize:z.coerce.number().int().min(1).max(100).default(20)}).refine(v=>v.period!=='custom'||(!!v.from&&!!v.to&&v.from<=v.to));
async function rpc(res:express.Response,op:string,args:unknown){
 const {data,error}=await res.locals.client.rpc('clube_escolas',{op,args});
 if(error&&schoolMigrationMissing(error))throw Object.assign(new Error(schoolMigrationMessage),{status:503});
 if(error)throw Object.assign(new Error(error.code==='42501'?'Sua conta não tem autorização administrativa.':error.code==='PGRST202'?'Aplique a atualização do painel Escolas no Supabase (202610290001_painel_escolas.sql).':error.code==='P0002'?'Aluno não encontrado.':error.code==='22023'?'Confira os filtros e o intervalo de datas.':'Não foi possível consultar o painel Escolas. Tente novamente.'),{status:error.code==='42501'?403:error.code==='P0002'?404:error.code==='22023'?400:503});
 return data;
}
schools.get('/',async(req,res)=>{
 const parsed=filters.safeParse(req.query);if(!parsed.success){res.status(400).json({error:'Confira os filtros e o intervalo de datas.'});return;}
 const normalized=parsed.data.search.replace(/[\s-]/g,'').toUpperCase();
 const codeHash=/^[A-HJ-NP-Z2-9]{6}$/.test(normalized)?hashCredential(normalized):/^([A-F0-9]{32}|[A-F0-9]{64})$/.test(normalized)?hashCredential(normalized.toLowerCase()):undefined;
 const data=await rpc(res,'dashboard',{...parsed.data,codeHash});
 data.students=data.students.map((record:{encrypted?:string;[key:string]:unknown})=>{const {encrypted,...student}=record;let code:string|null=null;if(encrypted){try{code=readCredentials(encrypted).code;}catch{/* Credenciais antigas/indisponíveis não impedem consultar o cadastro. */}}return {...student,code};});
 res.setHeader('Cache-Control','no-store');res.json(data);
});
schools.get('/students/:id',async(req,res)=>{if(!z.uuid().safeParse(req.params.id).success){res.status(400).json({error:'Aluno inválido.'});return;}res.json(await rpc(res,'student',{id:req.params.id}));});
schools.get('/students/:id/responses',async(req,res)=>{
 const parsed=z.object({page:z.coerce.number().int().min(1).max(1000000).default(1),pageSize:z.coerce.number().int().min(1).max(100).default(20)}).safeParse(req.query);
 if(!parsed.success||!z.uuid().safeParse(req.params.id).success){res.status(400).json({error:'Consulta inválida.'});return;}
 res.json(await rpc(res,'responses',{id:req.params.id,...parsed.data}));
});

schools.use(schoolManagement);
