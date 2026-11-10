begin;
-- Amplia alternativas sem alterar perguntas, respostas ou snapshots existentes.
create function clube_private.alternativa_valida(options jsonb,choice integer) returns boolean language sql immutable set search_path='' as $$
 select coalesce(jsonb_typeof(options)='array' and choice>=0 and choice<jsonb_array_length(options),false)
$$;
revoke all on function clube_private.alternativa_valida(jsonb,integer) from public,anon,authenticated;
alter table public.questoes drop constraint questoes_alternativas_check,
 add constraint questoes_alternativas_check check(jsonb_typeof(alternativas)='array' and jsonb_array_length(alternativas)>=2);
alter table clube_private.gabaritos drop constraint gabaritos_correta_check,
 add constraint gabaritos_correta_check check(correta>=0);
alter table public.respostas drop constraint respostas_selecionada_check,
 add constraint respostas_selecionada_check check(selecionada>=0);

-- Atualiza as funções instaladas, preservando os wrappers de cadastro e eventos.
do $functions$
declare target regprocedure;definition text;updated text;
begin
 foreach target in array array['clube_private.clube_gestao(text,jsonb)'::regprocedure,'clube_private.clube_leitura(text,jsonb)'::regprocedure,'public.clube_leitura(text,jsonb)'::regprocedure,'clube_private.api_antes_eventos(text,jsonb)'::regprocedure] loop
  definition:=pg_get_functiondef(target);updated:=definition;
  updated:=replace(updated,'jsonb_array_length(q->''options'')<>4','jsonb_array_length(q->''options'')<2');
  updated:=replace(updated,'(q->>''correct'')::integer not between 0 and 3','not clube_private.alternativa_valida(q->''options'',(q->>''correct'')::integer)');
  updated:=replace(updated,'quatro alternativas','ao menos duas alternativas');
  updated:=replace(updated,'choice not between 0 and 3','choice<0');
  updated:=replace(updated,'where (q->>''id'')::integer=qid)','where (q->>''id'')::integer=qid and clube_private.alternativa_valida(q->''options'',choice))');
  updated:=replace(updated,'and (item->>''id'')::integer=qid)','and (item->>''id'')::integer=qid and clube_private.alternativa_valida(item->''options'',choice))');
  if updated=definition then raise exception 'Função % não corresponde à versão esperada. Aplique primeiro as migrações de gestão e eventos.',target;end if;
  execute updated;
 end loop;
end $functions$;

create function clube_private.validar_gabarito_dinamico() returns trigger language plpgsql security definer set search_path='' as $$
begin
 if not exists(select 1 from public.questoes q where q.id=new.questao_id and clube_private.alternativa_valida(q.alternativas,new.correta)) then
  raise exception 'Escolha uma alternativa correta existente na pergunta.' using errcode='22023';
 end if;
 return new;
end $$;
create trigger validar_gabarito_dinamico before insert or update on clube_private.gabaritos for each row execute function clube_private.validar_gabarito_dinamico();
revoke all on function clube_private.validar_gabarito_dinamico() from public,anon,authenticated;
notify pgrst,'reload schema';
commit;
