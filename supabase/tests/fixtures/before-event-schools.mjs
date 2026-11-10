// As suites historicas exercitam o contrato anterior; a suite event-schools valida a migracao e o contrato novo.
export function beforeEventSchools(sql){const marker=" if to_regclass('public.evento_escolas') is null then";const index=sql.indexOf(marker);return index<0?sql:sql.slice(0,index)+'end $instalar_eventos$;commit;';}
