// Gerado por backend/scripts/prepare-edge.mjs; edite backend/src.
import process from "node:process";
import {Buffer} from "node:buffer";
export function schoolMigrationMissing(error) {
    const message = (error.message ?? '').normalize('NFD').replace(/[\u0300-\u036f]/g, '').trim();
    return error.code === 'PGRST202' || error.code === '42883' || error.code === '42P01' || (error.code === '22023' && /^operacao invalida[.!]?$/i.test(message));
}
export const schoolMigrationMessage = 'O banco ainda não reconhece esta operação de Escolas. Execute o arquivo supabase/instalar-eventos.sql completo no SQL Editor do Supabase, incluindo a etapa 202611050001_modulo_escolas.sql. Depois atualize a página.';
