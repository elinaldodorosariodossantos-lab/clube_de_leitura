begin;
-- Reutiliza alunos/acessos: a chave identifica a operação, nunca o nome do aluno.
alter table public.alunos add column cadastro_requisicao uuid unique,
 add column cadastro_dados_hash text;
alter function public.clube_gestao(text,jsonb) set schema clube_private;
revoke all on function clube_private.clube_gestao(text,jsonb) from public,anon,authenticated;
create function public.clube_gestao(op text,args jsonb default '{}') returns jsonb
language plpgsql security definer set search_path='' as $$
declare request_id uuid;existing public.alunos;fingerprint text;result jsonb;
begin
 if not clube_private.administrador() then raise exception 'Administrador obrigatório' using errcode='42501';end if;
 if op='student_request' or (op='student_save' and coalesce(args->>'id','')='' and args ? 'requestId') then
  request_id:=(args->>'requestId')::uuid;
  if request_id is null then raise exception 'Identificador de cadastro obrigatório' using errcode='22023';end if;
  fingerprint:=encode(sha256(convert_to((args-'requestId'-'profileId'-'tokenHash'-'shortHash'-'encrypted')::text,'UTF8')),'hex');
  perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended(request_id::text,0));
  select * into existing from public.alunos where cadastro_requisicao=request_id;
  if existing.id is not null then
   if existing.cadastro_dados_hash is distinct from fingerprint then
    raise exception 'Este envio já foi usado com outros dados. Atualize a lista antes de continuar.' using errcode='22023';
   end if;
   return clube_private.clube_gestao('credentials',jsonb_build_object('id',existing.id));
  end if;
  if op='student_request' then return null;end if;
  result:=clube_private.clube_gestao(op,args);
  update public.alunos set cadastro_requisicao=request_id,cadastro_dados_hash=fingerprint where id=(result->>'id')::uuid;
  return result;
 end if;
 return clube_private.clube_gestao(op,args);
end $$;
revoke all on function public.clube_gestao(text,jsonb) from public,anon;
grant execute on function public.clube_gestao(text,jsonb) to authenticated;
notify pgrst,'reload schema';
commit;
