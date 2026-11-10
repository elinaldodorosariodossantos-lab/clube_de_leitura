import express from 'express';
import {portal} from '../../backend/src/portal.js';

// Reutiliza a API autenticada no mesmo domínio do frontend.
const app=express();
app.set('trust proxy',1);
app.use(express.json({limit:'2mb'}));
app.use('/api/portal',portal);
app.use((_req,res)=>{res.status(404).json({error:'Rota do portal não encontrada.'});});
export default app;
