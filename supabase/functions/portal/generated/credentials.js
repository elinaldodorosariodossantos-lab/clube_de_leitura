// Gerado por backend/scripts/prepare-edge.mjs; edite backend/src.
import process from "node:process";
import {Buffer} from "node:buffer";
import { createCipheriv, createDecipheriv, createHash, randomBytes, randomInt } from 'node:crypto';
const alphabet = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';
export const hashCredential = (value) => createHash('sha256').update(value).digest('hex');
function encryptionKey() { const value = process.env.ACCESS_CREDENTIALS_KEY; if (!value || !/^[a-f0-9]{64}$/i.test(value))
    throw Object.assign(new Error('Configure ACCESS_CREDENTIALS_KEY no backend para proteger as fichas de acesso.'), { status: 503 }); return Buffer.from(value, 'hex'); }
export function createCredentials() { const token = randomBytes(32).toString('hex'), code = Array.from({ length: 6 }, () => alphabet[randomInt(alphabet.length)]).join(''); const iv = randomBytes(12), cipher = createCipheriv('aes-256-gcm', encryptionKey(), iv); const encrypted = Buffer.concat([cipher.update(JSON.stringify({ token, code }), 'utf8'), cipher.final()]); return { tokenHash: hashCredential(token), shortHash: hashCredential(code), encrypted: [iv.toString('hex'), cipher.getAuthTag().toString('hex'), encrypted.toString('hex')].join('.') }; }
export function readCredentials(value) { const [iv, tag, data] = value.split('.'); const cipher = createDecipheriv('aes-256-gcm', encryptionKey(), Buffer.from(iv, 'hex')); cipher.setAuthTag(Buffer.from(tag, 'hex')); return JSON.parse(Buffer.concat([cipher.update(Buffer.from(data, 'hex')), cipher.final()]).toString('utf8')); }
