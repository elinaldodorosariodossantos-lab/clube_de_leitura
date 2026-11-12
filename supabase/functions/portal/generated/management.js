// Gerado por backend/scripts/prepare-edge.mjs; edite backend/src.
import process from "node:process";
import {Buffer} from "node:buffer";
import { bookPage, pageIsPublishable } from './book-pages.js';
import express from 'express';
import { createClient } from '@supabase/supabase-js';
import { randomUUID } from 'node:crypto';
import QRCode from 'qrcode';
import { z } from 'zod';
import { createCredentials, readCredentials } from './credentials.js';
import { studentSchema as student } from './student-validation.js';
export const management = express.Router();
const uuid = z.string().uuid();
function studentData(value) { const result = student.safeParse(value); if (result.success)
    return result.data; const field = result.error.issues[0]?.path[0]; const messages = { name: 'Informe o nome completo do aluno.', birthDate: 'Informe uma data de nascimento válida, que não seja futura.', guardian: 'Informe o pai ou responsável (pelo menos 3 caracteres).', schoolId: 'Selecione uma escola válida.', className: 'Informe a série escolar.', schoolYear: 'Informe um ano letivo entre 2000 e 2100.' }; throw Object.assign(new Error(messages[String(field)] ?? 'Confira os dados do aluno.'), { status: 400 }); }
const question = z.object({ prompt: z.string().trim().min(1), options: z.array(z.string().trim().min(1)).min(2), correct: z.number().int().min(0), value: z.number().int().positive().nullable().optional() }).refine(q => q.correct < q.options.length);
const draftQuestion = z.object({ prompt: z.string(), options: z.array(z.string()), correct: z.number().int().nonnegative(), value: z.number().int().positive().nullable().optional() });
const story = z.object({ title: z.string().trim().min(2).max(200), author: z.string().max(160).default(''), level: z.enum(['facil', 'medio', 'dificil']), age: z.string().trim().min(1).max(100), cover: z.union([z.url().refine(v => v.startsWith('https://')), z.literal('')]).default(''), active: z.boolean(), required: z.boolean(), ordering: z.number().int().nonnegative(), content: z.string().default(''), summary: z.string().default(''), minutes: z.number().int().positive().nullable().optional(), questions: z.array(draftQuestion), pages: z.array(bookPage).optional(), confirmPageRemoval: z.boolean().optional() }).refine(v => !v.active || (v.questions.length > 0 && v.questions.every(q => question.safeParse(q).success) && (!v.pages || (v.pages.length > 0 && v.pages.every(pageIsPublishable)))));
async function rpc(res, op, args = {}) { const { data, error } = await res.locals.client.rpc('clube_gestao', { op, args }); if (error)
    throw Object.assign(new Error(error.code === '42501' ? 'Administrador obrigatório.' : error.code === '22023' ? error.message : error.code === 'P0002' ? 'Registro não encontrado.' : error.code === 'PGRST202' ? 'A migração de gerenciamento ainda precisa ser aplicada.' : 'Não foi possível salvar. Tente novamente.'), { status: error.code === '42501' ? 403 : error.code === '22023' ? 400 : error.code === 'P0002' ? 404 : 503, code: error.code }); return data; }
management.use(async (_req, res, next) => { const { data, error } = await res.locals.client.rpc('clube_admin_autorizado'); if (error)
    throw Object.assign(new Error('A migração de gerenciamento ainda precisa ser aplicada.'), { status: 503 }); if (data !== true)
    throw Object.assign(new Error('Administrador obrigatório.'), { status: 403 }); next(); });
function parse(schema, value) { const result = schema.safeParse(value); if (!result.success)
    throw Object.assign(new Error('Confira os campos obrigatórios e os valores informados.'), { status: 400 }); return result.data; }
function publicBase(req) { const configured = process.env.PUBLIC_APP_URL?.trim() || process.env.APP_ORIGIN?.trim(); if ('production' === 'production' && !configured)
    throw Object.assign(new Error('Configure PUBLIC_APP_URL com a URL de produção.'), { status: 503 }); const url = new URL(configured || `${req.protocol}://${req.get('host')}`); if ('production' === 'production' && url.protocol !== 'https:')
    throw Object.assign(new Error('A URL de produção deve usar HTTPS.'), { status: 503 }); url.hash = ''; url.search = ''; return url.href.replace(/\/$/, ''); }
async function card(req, record) { if (!record)
    throw Object.assign(new Error('Aluno não encontrado.'), { status: 404 }); const { encrypted, ...safe } = record; if (!encrypted)
    return { student: safe, needsCredentials: true }; const { token, code } = readCredentials(encrypted), link = publicBase(req) + '/#/acesso/' + token; return { student: safe, code, link, qr: await QRCode.toDataURL(link, { width: 360, margin: 2, errorCorrectionLevel: 'M' }), schoolYear: safe.schoolYear ?? new Date().getFullYear() }; }
async function withCredentials(res, op, args) { for (let attempt = 0; attempt < 8; attempt++) {
    try {
        return await rpc(res, op, { ...args, ...createCredentials() });
    }
    catch (e) {
        if (e.code !== '23505')
            throw e;
    }
} throw Object.assign(new Error('Não foi possível reservar um código único. Tente novamente.'), { status: 503 }); }
management.get('/schools', async (_req, res) => res.json(await rpc(res, 'schools')));
management.post('/schools', async (req, res) => res.json(await rpc(res, 'school_save', parse(z.object({ name: z.string().trim().min(2).max(160) }), req.body))));
management.get('/students', async (req, res) => { const args = parse(z.object({ search: z.string().max(120).default(''), sort: z.enum(['name_asc', 'name_desc', 'points_desc', 'points_asc']).default('name_asc'), schoolId: z.union([uuid, z.literal('')]).default(''), className: z.string().max(60).default(''), status: z.enum(['', 'ativo', 'inativo']).default(''), page: z.coerce.number().int().min(1).max(1000000).default(1), pageSize: z.coerce.number().int().min(1).max(100).default(20) }), req.query); res.json(await rpc(res, 'students', args)); });
management.post('/students', async (req, res) => {
    const data = studentData(req.body), requestId = parse(uuid, req.body.requestId ?? randomUUID());
    createCredentials();
    publicBase(req);
    const saved = await rpc(res, 'student_request', { ...data, requestId });
    if (saved) {
        res.status(200).json(await card(req, saved));
        return;
    }
    const c = createClient(process.env.SUPABASE_URL, process.env.SUPABASE_ANON_KEY, { auth: { persistSession: false, autoRefreshToken: false } });
    const auth = await c.auth.signInAnonymously();
    if (auth.error || !auth.data.user)
        throw Object.assign(new Error('Não foi possível criar a identidade do aluno. Confira o login anônimo no Supabase.'), { status: 503 });
    res.status(201).json(await card(req, await withCredentials(res, 'student_save', { ...data, requestId, profileId: auth.data.user.id })));
});
management.put('/students/:id', async (req, res) => { const id = parse(uuid, req.params.id); const record = await rpc(res, 'student_save', { ...studentData(req.body), id }); const { encrypted, ...safe } = record; res.json(safe); });
management.delete('/students/:id', async (req, res) => res.json(await rpc(res, 'student_delete', { id: parse(uuid, req.params.id) })));
management.post('/students/:id/status', async (req, res) => { const id = parse(uuid, req.params.id), data = parse(z.object({ status: z.enum(['ativo', 'inativo']) }), req.body); const result = await rpc(res, 'student_status', { id, ...data }); const { encrypted, ...safe } = result; res.json(safe); });
management.post('/students/:id/journey-restart', async (req, res) => res.json(await rpc(res, 'student_journey_restart', { id: parse(uuid, req.params.id), ...parse(z.object({ journeyId: uuid }), req.body) })));
management.get('/students/:id/access', async (req, res) => res.json(await card(req, await rpc(res, 'credentials', { id: parse(uuid, req.params.id) }))));
management.post('/students/:id/access', async (req, res) => res.json(await card(req, await withCredentials(res, 'credentials_save', { id: parse(uuid, req.params.id) }))));
management.get('/stories', async (req, res) => res.json(await rpc(res, 'stories', parse(z.object({ search: z.string().max(120).default(''), level: z.enum(['', 'facil', 'medio', 'dificil']).default(''), status: z.enum(['', 'ativo', 'inativo']).default('') }), req.query))));
management.get('/stories/:id', async (req, res) => { const data = await rpc(res, 'story', { id: parse(z.string().min(1).max(200), req.params.id) }); if (!data)
    throw Object.assign(new Error('História não encontrada.'), { status: 404 }); res.json(data); });
management.post('/stories', async (req, res) => res.status(201).json(await rpc(res, 'story_save', parse(story, req.body))));
management.delete('/stories/:id', async (req, res) => res.json(await rpc(res, 'story_delete', { id: parse(z.string().min(1).max(200), req.params.id) })));
management.put('/stories/:id', async (req, res) => res.json(await rpc(res, 'story_save', { ...parse(story, req.body), id: parse(z.string().min(1).max(200), req.params.id) })));
management.post('/stories/:id/status', async (req, res) => res.json(await rpc(res, 'story_status', { id: parse(z.string().min(1).max(200), req.params.id), ...parse(z.object({ active: z.boolean() }), req.body) })));
management.post('/covers', express.raw({ type: ['image/png', 'image/jpeg', 'image/webp'], limit: '5mb' }), async (req, res) => { const mime = req.get('content-type') ?? '', data = req.body; const valid = Buffer.isBuffer(data) && data.length > 12 && (mime === 'image/png' && data.subarray(0, 8).equals(Buffer.from([137, 80, 78, 71, 13, 10, 26, 10])) || mime === 'image/jpeg' && data[0] === 255 && data[1] === 216 && data[2] === 255 || mime === 'image/webp' && data.toString('ascii', 0, 4) === 'RIFF' && data.toString('ascii', 8, 12) === 'WEBP'); if (!valid)
    throw Object.assign(new Error('Envie uma imagem PNG, JPEG ou WebP válida, até 5 MB.'), { status: 400 }); const path = randomUUID() + '.' + (mime === 'image/png' ? 'png' : mime === 'image/jpeg' ? 'jpg' : 'webp'); const result = await res.locals.client.storage.from('clube-capas').upload(path, data, { contentType: mime, upsert: false }); if (result.error)
    throw Object.assign(new Error('Não foi possível enviar a capa. Confira o bucket e as políticas da migração.'), { status: 503 }); res.status(201).json({ url: res.locals.client.storage.from('clube-capas').getPublicUrl(path).data.publicUrl }); });
management.get('/images', async (req, res) => { const offset = parse(z.coerce.number().int().nonnegative().default(0), req.query.offset); const { data, error } = await res.locals.client.storage.from('clube-capas').list('', { limit: 60, offset, sortBy: { column: 'created_at', order: 'desc' } }); if (error)
    throw Object.assign(new Error('Não foi possível carregar as imagens.'), { status: 503 }); res.json({ images: (data ?? []).filter((f) => f.id && /\.(png|jpe?g|webp)$/i.test(f.name)).map((f) => ({ name: f.name, url: res.locals.client.storage.from('clube-capas').getPublicUrl(f.name).data.publicUrl })), nextOffset: (data?.length ?? 0) === 60 ? offset + 60 : null }); });
