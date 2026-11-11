// Gerado por backend/scripts/prepare-edge.mjs; edite backend/src.
import process from "node:process";
import {Buffer} from "node:buffer";
import { createHash } from 'node:crypto';
const refreshes = new Map();
function key(token) { return createHash('sha256').update(process.env.SUPABASE_URL ?? '').update('\0').update(token).digest('hex'); }
function hasUnexpiredAccess(access) {
    // O payload só seleciona o caminho de renovação; a identidade sempre é verificada pelo Supabase.
    try {
        const exp = JSON.parse(Buffer.from(access.split('.')[1], 'base64url').toString()).exp;
        return typeof exp === 'number' && exp > Date.now() / 1000;
    }
    catch {
        return false;
    }
}
export async function restorePortalSession(client, access, refresh) {
    if (access && hasUnexpiredAccess(access))
        return client.auth.setSession({ access_token: access, refresh_token: refresh });
    const now = Date.now();
    for (const [k, v] of refreshes)
        if (v.expires < now)
            refreshes.delete(k);
    const tokenKey = key(refresh);
    let entry = refreshes.get(tokenKey);
    if (!entry) {
        // Requisições concorrentes e respostas atrasadas reutilizam a mesma rotação por 15 segundos.
        entry = { promise: client.auth.refreshSession({ refresh_token: refresh }), expires: now + 15000 };
        refreshes.set(tokenKey, entry);
        const own = entry;
        void own.promise.then(result => { if (result.error || !result.data.session) {
            if (refreshes.get(tokenKey) === own)
                refreshes.delete(tokenKey);
        }
        else {
            own.session = result.data.session;
            own.expires = Date.now() + 15000;
        } }, () => { if (refreshes.get(tokenKey) === own)
            refreshes.delete(tokenKey); });
        if (refreshes.size > 512) {
            const oldest = refreshes.keys().next().value;
            if (oldest !== undefined && oldest !== tokenKey)
                refreshes.delete(oldest);
        }
    }
    const refreshed = await entry.promise;
    if (refreshed.error || !refreshed.data.session)
        return refreshed;
    // Cada requisição recebe seu próprio cliente autenticado, sem compartilhar estado de usuário.
    return client.auth.setSession({ access_token: refreshed.data.session.access_token, refresh_token: refreshed.data.session.refresh_token });
}
export function forgetPortalSession(refresh) {
    if (!refresh)
        return;
    const tokenKey = key(refresh), users = new Set();
    for (const [k, v] of refreshes)
        if (k === tokenKey || v.session?.refresh_token === refresh) {
            if (v.session?.user.id)
                users.add(v.session.user.id);
            refreshes.delete(k);
        }
    for (const [k, v] of refreshes)
        if (v.session && users.has(v.session.user.id))
            refreshes.delete(k);
}
