// Gerado por backend/scripts/prepare-edge.mjs; edite backend/src.
import process from "node:process";
import {Buffer} from "node:buffer";
import { z } from 'zod';
export function validBirthDate(value) {
    if (!/^\d{4}-\d{2}-\d{2}$/.test(value))
        return false;
    const date = new Date(value + 'T12:00:00Z');
    return !Number.isNaN(date.getTime()) && date.toISOString().slice(0, 10) === value && value <= new Date().toLocaleDateString('en-CA', { timeZone: 'America/Fortaleza' });
}
export const studentSchema = z.object({ name: z.string().trim().min(3).max(120).refine(v => v.split(/\s+/).length >= 2), birthDate: z.string().refine(validBirthDate, 'Informe uma data de nascimento válida, que não seja futura.'), schoolYear: z.coerce.number().int().min(2000).max(2100).optional(), guardian: z.string().trim().min(3).max(160), schoolId: z.string().uuid(), className: z.string().trim().min(1).max(60) });
