import express from 'express';
import {z} from 'zod';
export const reading=express.Router();
reading.use((_req,res,next)=>{if(!res.locals.user){res.status(401).json({error:'Identifique-se para acessar sua leitura.'});return;}next();});
async function rpc(res:express.Response,op:string,args:unknown={}){
 const {data,error}=await res.locals.client.rpc('clube_leitura',{op,args});
 if(error){const status=error.code==='42501'?403:error.code==='PGRST202'?503:400;const e=new Error(status===403?'Você não tem acesso a esta atividade.':status===503?'A área de leitura ainda não foi habilitada pela equipe responsável.':error.code==='22023'?error.message:'Não foi possível salvar sua leitura. Tente novamente.') as Error&{status:number};e.status=status;throw e;}
 if(op==='state'&&(data?.sequenceReady!==true||!Array.isArray(data?.levels)||data.levels.some((level:Record<string,unknown>)=>typeof level.unlocked!=='boolean'))){const e=new Error('A atualização dos níveis ainda precisa ser aplicada pela equipe responsável.') as Error&{status:number};e.status=503;throw e;}
 return data;
}
const id=z.string().uuid();
reading.get('/journeys/:id',async(req,res)=>{if(!id.safeParse(req.params.id).success){res.status(400).json({error:'Conclusão inválida.'});return;}res.json(await rpc(res,'journey_get',{id:req.params.id}));});
reading.post('/journeys/:id/claim',async(req,res)=>{if(!id.safeParse(req.params.id).success){res.status(400).json({error:'Conclusão inválida.'});return;}res.json(await rpc(res,'journey_claim',{id:req.params.id}));});
reading.get('/state',async(_req,res)=>res.json(await rpc(res,'state')));
reading.post('/enter',async(req,res)=>{const p=z.object({level:z.enum(['facil','medio','dificil'])}).safeParse(req.body);if(!p.success){res.status(400).json({error:'Escolha um nível de leitura válido.'});return;}res.json(await rpc(res,'enter',p.data));});
reading.get('/levels/:level/stories',async(req,res)=>{const level=z.enum(['facil','medio','dificil']).safeParse(req.params.level);if(!level.success){res.status(400).json({error:'Nível inválido.'});return;}res.json(await rpc(res,'stories',{level:level.data}));});
reading.post('/start',async(req,res)=>{const p=z.object({level:z.enum(['facil','medio','dificil']),storyId:z.string().min(1).max(200).optional()}).safeParse(req.body);if(!p.success){res.status(400).json({error:'Escolha um nível de leitura válido.'});return;}res.json(await rpc(res,'start',p.data));});
reading.get('/achievements/:id',async(req,res)=>{if(!id.safeParse(req.params.id).success){res.status(400).json({error:'Conquista inválida.'});return;}res.json(await rpc(res,'achievement_get',{id:req.params.id}));});
for(const action of ['claim','continue'] as const)reading.post('/achievements/:id/'+action,async(req,res)=>{if(!id.safeParse(req.params.id).success){res.status(400).json({error:'Conquista inválida.'});return;}res.json(await rpc(res,'achievement_'+action,{id:req.params.id}));});
reading.post('/new-journey',(_req,res)=>res.status(403).json({error:'Somente a administração pode autorizar uma nova jornada.'}));
reading.use('/attempts/:id',(req,res,next)=>{if(!id.safeParse(req.params.id).success){res.status(400).json({error:'Atividade inválida.'});return;}next();});
reading.get('/attempts/:id',async(req,res)=>res.json(await rpc(res,'get',{id:req.params.id})));
reading.post('/attempts/:id/stage',async(req,res)=>{const p=z.object({stage:z.enum(['leitura','questoes'])}).safeParse(req.body);if(!p.success){res.status(400).json({error:'Etapa inválida.'});return;}res.json(await rpc(res,'stage',{id:req.params.id,...p.data}));});
reading.post('/attempts/:id/answers',async(req,res)=>{const p=z.object({questionId:z.number().int().positive(),selected:z.number().int().min(0)}).safeParse(req.body);if(!p.success){res.status(400).json({error:'Escolha uma resposta válida.'});return;}res.json(await rpc(res,'answer',{id:req.params.id,...p.data}));});
reading.post('/attempts/:id/finish',async(req,res)=>res.json(await rpc(res,'finish',{id:req.params.id})));

reading.post('/attempts/:id/page',async(req,res)=>{const p=z.object({pageIndex:z.number().int().nonnegative()}).safeParse(req.body);if(!p.success){res.status(400).json({error:'Página inválida.'});return;}res.json(await rpc(res,'page',{id:req.params.id,...p.data}));});
