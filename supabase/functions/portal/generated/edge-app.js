// Gerado por backend/scripts/prepare-edge.mjs; edite backend/src.
import process from "node:process";
import {Buffer} from "node:buffer";
import express from 'express';
import { portal } from './portal.js';
export const app = express();
app.set('trust proxy', 1);
app.use(express.json({ limit: '2mb' }));
// O gateway do Supabase preserva o nome da função no caminho.
app.use('/portal', portal);
app.use((_req, res) => { res.status(404).json({ error: 'Rota do portal não encontrada.' }); });
