begin;
-- Arrays ordenados mantêm texto e imagem de cada página na mesma versão.
alter table public.textos add column paginas_livro jsonb not null default '[]' check(jsonb_typeof(paginas_livro)='array'),add column paginas_publicadas boolean not null default false;
create table clube_private.rascunhos_livros(texto_id text primary key references public.textos(id),perguntas jsonb not null check(jsonb_typeof(perguntas)='array'));
alter table clube_private.rascunhos_livros enable row level security;
revoke all on clube_private.rascunhos_livros from public,anon,authenticated;
alter table public.tentativas add column pagina_atual integer not null default 0 check(pagina_atual>=0),add column pagina_maxima integer not null default 0 check(pagina_maxima>=0);
update public.textos set paginas_publicadas=ativo,paginas_livro=jsonb_build_array(jsonb_build_object('id',gen_random_uuid(),'text',conteudo,'image',coalesce(capa_url,'')));
-- Cada snapshot antigo é convertido a partir de seu próprio conteúdo histórico.
update clube_private.conteudos_tentativas set atividade=atividade||jsonb_build_object('pages',jsonb_build_array(jsonb_build_object('id',gen_random_uuid(),'text',atividade->>'content','image',coalesce(atividade->>'cover',''))));
update clube_private.evento_conteudos set atividade=atividade||jsonb_build_object('pages',jsonb_build_array(jsonb_build_object('id',gen_random_uuid(),'text',atividade->>'content','image',coalesce(atividade->>'cover',''))));
do $snapshots$
declare target regprocedure;definition text;updated text;
begin
 foreach target in array array['clube_private.snapshot_leitura()'::regprocedure,'clube_private.evento_guardar_leitura(uuid,text,integer)'::regprocedure,'clube_private.eventos_antes_idades(text,jsonb)'::regprocedure] loop
  definition:=pg_get_functiondef(target);
  updated:=replace(definition,'''content'',t.conteudo,','''content'',t.conteudo,''pages'',t.paginas_livro,');
  if updated=definition then raise exception 'Snapshot % incompatível; aplique as migrações anteriores.',target;end if;
  execute updated;
 end loop;
end $snapshots$;
create or replace function clube_private.leitura_tentativa(a public.tentativas) returns jsonb language sql stable security definer set search_path='' as $$
 select clube_private.attempt_json(a)||jsonb_build_object('journeyId',a.jornada_id,'level',a.nivel,'stage',a.etapa,'index',a.questao_atual,'pageIndex',a.pagina_atual,
 'activity',(select atividade from clube_private.conteudos_tentativas where tentativa_id=a.id))
$$;
alter function public.clube_gestao(text,jsonb) rename to gestao_antes_paginas;
alter function public.gestao_antes_paginas(text,jsonb) set schema clube_private;
revoke all on function clube_private.gestao_antes_paginas(text,jsonb) from public,anon,authenticated;
create function public.clube_gestao(op text,args jsonb default '{}') returns jsonb language plpgsql security definer set search_path='' as $$
declare result jsonb;pages jsonb;p jsonb;old public.textos;sid text;protected boolean;published boolean;questions jsonb;
begin
 if not clube_private.administrador() then raise exception 'Administrador obrigatório' using errcode='42501';end if;
 if op='stories' then
  result:=clube_private.gestao_antes_paginas(op,args);
  return coalesce((select jsonb_agg(x||jsonb_build_object('questions',coalesce((select jsonb_array_length(d.perguntas) from clube_private.rascunhos_livros d where d.texto_id=t.id),(x->>'questions')::integer),'cover',coalesce(nullif(x->>'cover',''),t.paginas_livro->0->>'image','')) order by ord)
   from jsonb_array_elements(result) with ordinality as rows(x,ord) join public.textos t on t.id=x->>'id'),'[]');
 elsif op='story' then
  result:=clube_private.gestao_antes_paginas(op,args);
  select * into old from public.textos where id=args->>'id';
  if old.id is null then return null;end if;
  protected:=old.paginas_publicadas or old.ativo or exists(select 1 from public.tentativas where texto_id=old.id) or exists(select 1 from public.evento_leituras where texto_id=old.id);
  return result||jsonb_build_object('pages',old.paginas_livro,'pagesProtected',protected,'questions',coalesce((select perguntas from clube_private.rascunhos_livros where texto_id=old.id),result->'questions'));
 elsif op='story_status' and (args->>'active')::boolean then
  result:=public.clube_gestao('story',args);
  if result is null then raise exception 'História não encontrada' using errcode='P0002';end if;
  return public.clube_gestao('story_save',result||jsonb_build_object('active',true));
 elsif op='story_save' then
  sid:=coalesce(nullif(args->>'id',''),gen_random_uuid()::text);
  select * into old from public.textos where id=sid for update;
  pages:=coalesce(args->'pages',old.paginas_livro,jsonb_build_array(jsonb_build_object('id',gen_random_uuid(),'text',coalesce(args->>'content',''),'image',coalesce(args->>'cover',''))));
  published:=coalesce((args->>'active')::boolean,false);questions:=args->'questions';
  if jsonb_typeof(pages) is distinct from 'array' or (published and jsonb_array_length(pages)=0) then raise exception 'Adicione páginas antes de publicar.' using errcode='22023';end if;
  if (select count(distinct x->>'id') from jsonb_array_elements(pages) x)<>jsonb_array_length(pages) then raise exception 'Identificadores de página inválidos.' using errcode='22023';end if;
  for p in select value from jsonb_array_elements(pages) loop
   if jsonb_typeof(p) is distinct from 'object' or coalesce(p->>'id','')='' or jsonb_typeof(p->'text') is distinct from 'string' or jsonb_typeof(p->'image') is distinct from 'string'
    or (p->>'image'<>'' and p->>'image'!~'^https://') or (published and trim(p->>'text')='' and p->>'image'='') then
    raise exception 'Cada página publicada precisa de texto ou imagem permanente HTTPS.' using errcode='22023';end if;
  end loop;
  protected:=old.paginas_publicadas or old.ativo or exists(select 1 from public.tentativas where texto_id=sid) or exists(select 1 from public.evento_leituras where texto_id=sid);
  if protected and exists(select 1 from jsonb_array_elements(old.paginas_livro) o where not exists(select 1 from jsonb_array_elements(pages) n where n->>'id'=o->>'id')) and not coalesce((args->>'confirmPageRemoval')::boolean,false) then
   raise exception 'Confirme a remoção de páginas publicadas ou utilizadas. O histórico será preservado.' using errcode='22023';end if;
  if jsonb_typeof(questions) is distinct from 'array' then raise exception 'Perguntas inválidas.' using errcode='22023';end if;
  result:=clube_private.gestao_antes_paginas(op,args||jsonb_build_object('id',sid,'content',coalesce(nullif(trim((select string_agg(x->>'text',E'\n\n' order by ord) from jsonb_array_elements(pages) with ordinality as t(x,ord))),''),'Rascunho em edição'),'questions',case when published then questions else '[]'::jsonb end));
  update public.textos set paginas_livro=pages,paginas_publicadas=paginas_publicadas or published where id=sid;
  insert into clube_private.rascunhos_livros(texto_id,perguntas) values(sid,questions) on conflict(texto_id) do update set perguntas=excluded.perguntas;
  return result;
 end if;
 return clube_private.gestao_antes_paginas(op,args);
end $$;
revoke all on function public.clube_gestao(text,jsonb) from public,anon;
grant execute on function public.clube_gestao(text,jsonb) to authenticated;
alter function public.clube_leitura(text,jsonb) rename to leitura_antes_paginas;
alter function public.leitura_antes_paginas(text,jsonb) set schema clube_private;
revoke all on function clube_private.leitura_antes_paginas(text,jsonb) from public,anon,authenticated;
create function public.clube_leitura(op text,args jsonb default '{}') returns jsonb language plpgsql security definer set search_path='' as $$
declare result jsonb;a public.tentativas;page integer;total integer;
begin
 if op='page' or (op='stage' and args->>'stage'='questoes') then
  -- Reutiliza autorização, período do evento e ordem de locks existentes.
  result:=clube_private.leitura_antes_paginas('get',args);
  perform 1 from public.alunos where id=clube_private.aluno_atual() for update;
  select * into a from public.tentativas where id=(args->>'id')::uuid for update;
  total:=jsonb_array_length(result->'activity'->'pages');
  if op='page' then
   page:=(args->>'pageIndex')::integer;
   if a.status='completed' or a.etapa<>'leitura' or page is null or page<0 or page>=total or page>a.pagina_maxima+1 then raise exception 'Página inválida. Avance em sequência.' using errcode='22023';end if;
   update public.tentativas set pagina_atual=page,pagina_maxima=greatest(pagina_maxima,page) where id=a.id returning * into a;
   return clube_private.leitura_tentativa(a)||case when result ? 'eventId' then jsonb_build_object('eventId',result->'eventId') else '{}'::jsonb end;
  end if;
  if total>1 and (a.pagina_maxima<total-1 or a.pagina_atual<>total-1) then raise exception 'Conclua todas as páginas antes das perguntas.' using errcode='22023';end if;
 end if;
 return clube_private.leitura_antes_paginas(op,args);
end $$;
revoke all on function public.clube_leitura(text,jsonb) from public,anon;
grant execute on function public.clube_leitura(text,jsonb) to authenticated;
notify pgrst,'reload schema';
commit;
