// Gerado por backend/scripts/prepare-edge.mjs; edite backend/src.
import process from "node:process";
import {Buffer} from "node:buffer";
import express from 'express';
import { z } from 'zod';
import { management } from './management.js';
import { schools } from './schools.js';
export const administration = express.Router();
administration.use((_req, res, next) => { if (!res.locals.user) {
    res.status(401).json({ error: 'Entre com sua conta administrativa.' });
    return;
} next(); });
async function rpc(res, op, args = {}) {
    const { data, error } = await res.locals.client.rpc('clube_admin', { op, args });
    if (error) {
        const status = error.code === '42501' ? 403 : error.code === 'PGRST202' ? 503 : error.code === 'P0002' ? 404 : error.code === '22023' ? 400 : 503;
        const e = new Error(status === 403 ? 'Sua conta não tem autorização administrativa.' : status === 404 ? 'Aluno não encontrado.' : status === 400 ? 'Confira os filtros informados.' : status === 503 && error.code === 'PGRST202' ? 'O painel precisa ser habilitado pela equipe responsável.' : 'Não foi possível consultar os dados. Tente novamente.');
        e.status = status;
        throw e;
    }
    return data;
}
administration.use('/manage', management);
administration.use('/schools', schools);
const filters = z.object({ search: z.string().trim().max(120).default(''), schoolId: z.union([z.string().uuid(), z.literal('')]).default(''), sort: z.enum(['name_asc', 'name_desc', 'points_desc', 'points_asc']).default('name_asc'), page: z.coerce.number().int().min(1).max(1000000).default(1), pageSize: z.coerce.number().int().min(1).max(100).default(20) });
administration.get('/overview', async (_req, res) => res.json(await rpc(res, 'overview')));
administration.get('/students', async (req, res) => { const parsed = filters.safeParse(req.query); if (!parsed.success) {
    res.status(400).json({ error: 'Confira os filtros informados.' });
    return;
} res.json(await rpc(res, 'students', parsed.data)); });
administration.get('/students/:id', async (req, res) => { if (!z.string().uuid().safeParse(req.params.id).success) {
    res.status(400).json({ error: 'Identificador de aluno inválido.' });
    return;
} res.json(await rpc(res, 'student', { id: req.params.id })); });
async function certificateSettings(res, op, args = {}) { const { data, error } = await res.locals.client.rpc('clube_gestao', { op, args }); if (error) {
    res.status(error.code === '42501' ? 403 : error.code === 'PGRST202' ? 503 : 400).json({ error: error.code === '42501' ? 'Administrador obrigatório.' : 'Não foi possível consultar ou salvar a identificação do certificado. Aplique a atualização do banco.' });
    return;
} res.json(data); }
administration.get('/certificate-settings', async (_req, res) => { await certificateSettings(res, 'certificate_settings'); });
administration.post('/certificate-settings', async (req, res) => { const p = z.object({ institution: z.string().trim().max(160), identification: z.string().trim().max(160) }).safeParse(req.body); if (!p.success) {
    res.status(400).json({ error: 'Identificação institucional inválida.' });
    return;
} await certificateSettings(res, 'certificate_settings_save', p.data); });
