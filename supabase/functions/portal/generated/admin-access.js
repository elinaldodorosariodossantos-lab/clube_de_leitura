// Gerado por backend/scripts/prepare-edge.mjs; edite backend/src.
import process from "node:process";
import {Buffer} from "node:buffer";
import express from 'express';
import { createClient } from '@supabase/supabase-js';
import { z } from 'zod';
export const adminAccess = express.Router();
adminAccess.use(async (_req, res, next) => {
    const { data, error } = await res.locals.client.rpc('clube_admin_autorizado');
    if (error || data !== true) {
        res.status(error ? 503 : 403).json({ error: 'Administrador obrigatório.' });
        return;
    }
    next();
});
async function profiles(res) {
    const { data, error } = await res.locals.client.rpc('clube_acessos', { op: 'list', args: {} });
    if (error)
        throw Object.assign(new Error('Não foi possível consultar os acessos administrativos.'), { status: 503 });
    return data;
}
adminAccess.get('/', async (_req, res) => res.json(await profiles(res)));
const fields = z.object({ name: z.string().trim().min(3).max(120), email: z.email().max(254), password: z.string().min(8).max(128).optional() });
adminAccess.post('/', async (req, res) => {
    const parsed = fields.extend({ id: z.uuid().optional() }).safeParse(req.body);
    if (!parsed.success || (!parsed.data.id && !parsed.data.password)) {
        res.status(400).json({ error: 'Informe nome, e-mail e senha com pelo menos 8 caracteres.' });
        return;
    }
    const { id, name, email, password } = parsed.data;
    if (id && !(await profiles(res)).some(p => p.id === id)) {
        res.status(404).json({ error: 'Administrador não encontrado.' });
        return;
    }
    const key = process.env.SUPABASE_SERVICE_ROLE_KEY;
    if (!key) {
        res.status(503).json({ error: 'A configuração para gerenciar acessos ainda precisa ser concluída no backend.' });
        return;
    }
    const auth = createClient(process.env.SUPABASE_URL, key, { auth: { persistSession: false, autoRefreshToken: false } }).auth.admin;
    const result = id ? await auth.updateUserById(id, { email, ...(password ? { password } : {}) }) : await auth.createUser({ email, password, email_confirm: true });
    if (result.error || !result.data.user) {
        res.status(400).json({ error: 'Não foi possível salvar o acesso. Confira o e-mail e os requisitos da senha.' });
        return;
    }
    const saved = await res.locals.client.rpc('clube_acessos', { op: 'save', args: { id: result.data.user.id, name } });
    if (saved.error) {
        if (!id)
            await auth.deleteUser(result.data.user.id);
        res.status(503).json({ error: 'Não foi possível salvar o perfil administrativo. Tente novamente.' });
        return;
    }
    res.status(id ? 200 : 201).json({ ok: true });
});
