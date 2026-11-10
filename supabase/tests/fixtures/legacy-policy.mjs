// Fixtures de compatibilidade: criam contextos antigos, sem mudar a pol?tica de produ??o.
export async function legacyContexts(db){await db.exec('alter table public.jornadas alter column regra_pontos set default 2;alter table public.evento_alunos alter column regra_pontos set default 2;');}
