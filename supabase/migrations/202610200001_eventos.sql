begin;
-- Aplicar após 202610190004_cadastro_alunos.sql. Não remove conteúdos existentes.
create table public.eventos_leitura(
 id uuid primary key default gen_random_uuid(),nome text not null check(length(trim(nome)) between 2 and 160),
 descricao text not null check(length(trim(descricao)) between 1 and 4000),capa_url text check(capa_url is null or capa_url~'^https://'),
 nivel text not null references public.niveis(id),idade_min integer not null check(idade_min between 4 and 19),
 idade_max integer not null check(idade_max between idade_min and 19),inicio timestamptz not null,fim timestamptz not null check(fim>inicio),
 ativo boolean not null default false,arquivado boolean not null default false,modo text not null check(modo in ('ordem','sorteio')),
 quantidade integer not null check(quantidade>0),criado_em timestamptz not null default now(),atualizado_em timestamptz not null default now());
create table public.evento_historias(evento_id uuid not null references public.eventos_leitura(id),texto_id text not null references public.textos(id),ordem integer not null check(ordem>=0),primary key(evento_id,texto_id),unique(evento_id,ordem));
create table public.evento_alunos(
 id uuid primary key default gen_random_uuid(),evento_id uuid not null references public.eventos_leitura(id),aluno_id uuid not null references public.alunos(id),
 nivel text not null references public.niveis(id),idade_min integer not null,idade_max integer not null,referencia date not null,
 assinatura text not null,enviado_em timestamptz not null default now(),unique(evento_id,aluno_id));
create index evento_alunos_assinatura_idx on public.evento_alunos(evento_id,assinatura);
create index evento_alunos_aluno_idx on public.evento_alunos(aluno_id);
create table public.evento_leituras(
 id uuid primary key default gen_random_uuid(),participante_id uuid not null references public.evento_alunos(id),
 texto_id text not null references public.textos(id),ordem integer not null check(ordem>=0),
 tentativa_id uuid unique references public.tentativas(id),unique(participante_id,texto_id),unique(participante_id,ordem));
create table clube_private.evento_conteudos(leitura_id uuid primary key references public.evento_leituras(id),atividade jsonb not null,gabarito jsonb not null);
alter table public.tentativas add column evento_participante_id uuid references public.evento_alunos(id),
 add constraint tentativa_contexto check(evento_participante_id is null or jornada_id is null);
create unique index tentativa_evento_texto_idx on public.tentativas(evento_participante_id,texto_id) where evento_participante_id is not null;
alter table public.eventos_leitura enable row level security;
alter table public.evento_historias enable row level security;
alter table public.evento_alunos enable row level security;
alter table public.evento_leituras enable row level security;
alter table clube_private.evento_conteudos enable row level security;
revoke all on public.eventos_leitura,public.evento_historias,public.evento_alunos,public.evento_leituras from public,anon,authenticated;
revoke all on clube_private.evento_conteudos from public,anon,authenticated;

create function clube_private.evento_disponivel(event_id uuid,student uuid) returns boolean language sql stable security definer set search_path='' as $$
 select student is not null and exists(select 1 from public.eventos_leitura e join public.evento_alunos p on p.evento_id=e.id
 join public.alunos a on a.id=p.aluno_id where e.id=event_id and p.aluno_id=student and a.situacao='ativo' and e.ativo and not e.arquivado and now()>=e.inicio and now()<e.fim)
$$;
create policy eventos_autorizados on public.eventos_leitura for select to authenticated using(clube_private.evento_disponivel(id,clube_private.aluno_atual()) or clube_private.administrador());
create policy participantes_proprios on public.evento_alunos for select to authenticated using(aluno_id=clube_private.aluno_atual() or clube_private.administrador());
create policy leituras_proprias on public.evento_leituras for select to authenticated using(exists(select 1 from public.evento_alunos p where p.id=participante_id and (p.aluno_id=clube_private.aluno_atual() or clube_private.administrador())));
-- Sem grants diretos: as políticas documentam a identidade e as consultas passam pelo RPC.
create function clube_private.evento_faixa(age_text text,min_age integer,max_age integer) returns boolean language plpgsql immutable set search_path='' as $$
declare pair text[];single text[];
begin
 pair:=regexp_match(age_text,'([0-9]{1,2})[^0-9]+([0-9]{1,2})');
 if pair is not null then return min_age>=pair[1]::integer and max_age<=pair[2]::integer;end if;
 single:=regexp_match(age_text,'([0-9]{1,2})');
 return single is not null and min_age>=single[1]::integer and (age_text~*'(mais|\+)' or max_age=single[1]::integer);
end $$;
create function clube_private.evento_json(e public.eventos_leitura) returns jsonb language sql stable security definer set search_path='' as $$
 select jsonb_build_object('id',e.id,'name',e.nome,'description',e.descricao,'cover',coalesce(e.capa_url,''),'level',e.nivel,'minAge',e.idade_min,'maxAge',e.idade_max,
 'startsAt',e.inicio,'endsAt',e.fim,'active',e.ativo,'archived',e.arquivado,'mode',e.modo,'quantity',e.quantidade,
 'status',case when e.arquivado then 'arquivado' when not e.ativo then 'inativo' when now()<e.inicio then 'programado' when now()>=e.fim then 'encerrado' else 'ativo' end,
 'storyIds',coalesce((select jsonb_agg(h.texto_id order by h.ordem) from public.evento_historias h where h.evento_id=e.id),'[]'),
 'recipients',(select count(*) from public.evento_alunos where evento_id=e.id))
$$;
create function clube_private.evento_elegivel(e public.eventos_leitura,a public.alunos) returns boolean language sql stable security definer set search_path='' as $$
 select a.situacao='ativo' and a.data_nascimento is not null
 and extract(year from age((e.inicio at time zone 'America/Fortaleza')::date,a.data_nascimento)) between e.idade_min and e.idade_max
 and clube_private.nivel_liberado(a.id,e.nivel)
$$;
create function clube_private.evento_destinatarios(e public.eventos_leitura,args jsonb) returns jsonb language sql stable security definer set search_path='' as $$
 with base as(select a.*,extract(year from age((e.inicio at time zone 'America/Fortaleza')::date,a.data_nascimento))::integer as event_age,
 clube_private.evento_elegivel(e,a) as eligible from public.alunos a),filtered as(
 select a.* from base a where (coalesce(args->>'search','')='' or strpos(lower(a.nome_completo),lower(args->>'search'))>0)
 and (coalesce(args->>'schoolId','')='' or a.escola_id::text=args->>'schoolId') and (coalesce(args->>'className','')='' or a.turma=args->>'className')
 and (coalesce(args->>'age','')='' or a.event_age=(args->>'age')::integer)
 and (not coalesce((args->>'eligibleOnly')::boolean,true) or a.eligible))
 select jsonb_build_object('students',coalesce((select jsonb_agg(jsonb_build_object('id',f.id,'name',f.nome_completo,'birthDate',f.data_nascimento,'age',f.event_age,
 'school',s.nome,'className',f.turma,'status',f.situacao,'eligible',f.eligible,'assigned',exists(select 1 from public.evento_alunos p where p.evento_id=e.id and p.aluno_id=f.id)) order by f.nome_completo,f.id)
 from filtered f left join public.escolas s on s.id=f.escola_id),'[]'),
 'schools',coalesce((select jsonb_agg(jsonb_build_object('id',s.id,'name',s.nome) order by s.nome) from public.escolas s where exists(select 1 from public.alunos a where a.escola_id=s.id)),'[]'),
 'classes',coalesce((select jsonb_agg(distinct turma order by turma) from public.alunos where turma is not null),'[]'))
$$;

create function public.clube_eventos(op text,args jsonb default '{}') returns jsonb language plpgsql security definer set search_path='' as $$
declare e public.eventos_leitura;student uuid;pid uuid;ids text[];chosen text[];signature text;sample_size integer;tries integer;idx integer;lid uuid;sid uuid;item record;result jsonb;name_value text;created integer:=0;existing integer:=0;found_count integer;comb integer[];cursor integer;j integer;
begin
 if op in ('mine','enter') then
  student:=clube_private.aluno_atual();if student is null then raise exception 'Aluno não identificado' using errcode='42501';end if;
  if op='mine' then
   return coalesce((select jsonb_agg((clube_private.evento_json(x)-'storyIds'-'recipients')||jsonb_build_object('level',p.nivel,'minAge',p.idade_min,'maxAge',p.idade_max,'total',(select count(*) from public.evento_leituras l where l.participante_id=p.id),
    'completed',(select count(*) from public.evento_leituras l join public.tentativas t on t.id=l.tentativa_id where l.participante_id=p.id and t.status='completed'),
    'ongoing',exists(select 1 from public.evento_leituras l join public.tentativas t on t.id=l.tentativa_id where l.participante_id=p.id and t.status='started')) order by x.inicio,x.id)
    from public.eventos_leitura x join public.evento_alunos p on p.evento_id=x.id and p.aluno_id=student where clube_private.evento_disponivel(x.id,student)),'[]');
  end if;
  select * into e from public.eventos_leitura where id=(args->>'id')::uuid for share;
  if not clube_private.evento_disponivel(e.id,student) then raise exception 'Este evento não está disponível para você neste período.' using errcode='42501';end if;
  perform 1 from public.alunos where id=student for update;
  select id into pid from public.evento_alunos where evento_id=e.id and aluno_id=student for update;
  select l.* into item from public.evento_leituras l left join public.tentativas t on t.id=l.tentativa_id where l.participante_id=pid and (t.id is null or t.status<>'completed') order by l.ordem limit 1 for update of l;
  if item.id is null then return jsonb_build_object('attempt',null,'complete',true);end if;
  if item.tentativa_id is null then
   insert into public.tentativas(aluno_id,texto_id,nivel,evento_participante_id) select student,item.texto_id,p.nivel,p.id from public.evento_alunos p where p.id=pid returning id into sid;
   update clube_private.conteudos_tentativas s set atividade=c.atividade,gabarito=c.gabarito from clube_private.evento_conteudos c where s.tentativa_id=sid and c.leitura_id=item.id;
   update public.evento_leituras set tentativa_id=sid where id=item.id;
  else sid:=item.tentativa_id;end if;
  return jsonb_build_object('attempt',(select clube_private.leitura_tentativa(t)||jsonb_build_object('eventId',e.id) from public.tentativas t where t.id=sid),'complete',false);
 end if;
 if not clube_private.administrador() then raise exception 'Administrador obrigatório' using errcode='42501';end if;
 if op='list' then
  return coalesce((select jsonb_agg(data order by data->>'startsAt',data->>'name') from(select clube_private.evento_json(x) as data from public.eventos_leitura x
   where not x.arquivado and (coalesce(args->>'search','')='' or strpos(lower(x.nome),lower(args->>'search'))>0)
   and (coalesce(args->>'level','')='' or x.nivel=args->>'level') and (coalesce(args->>'age','')='' or (args->>'age')::integer between x.idade_min and x.idade_max)) s
   where coalesce(args->>'status','')='' or data->>'status'=args->>'status'),'[]');
 elsif op='eligible_stories' then
  return coalesce((select jsonb_agg(jsonb_build_object('id',t.id,'title',t.titulo,'author',t.autor,'level',t.nivel,'age',t.faixa_etaria,'active',t.ativo,
   'eligible',t.ativo and clube_private.texto_pronto(t.id) and clube_private.evento_faixa(t.faixa_etaria,(args->>'minAge')::integer,(args->>'maxAge')::integer)) order by t.ordem,t.titulo,t.id)
   from public.textos t where t.nivel=args->>'level'),'[]');
 elsif op='save' then
  if not(args ? 'id') and args ? 'requestId' then
   perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended(args->>'requestId',0));
   select * into e from public.eventos_leitura where id=(args->>'requestId')::uuid for update;
   if e.id is not null then return clube_private.evento_json(e);end if;
  end if;
  if args ? 'id' then select * into e from public.eventos_leitura where id=(args->>'id')::uuid for update;
   if e.id is null then raise exception 'Evento não encontrado' using errcode='P0002';end if;
   if exists(select 1 from public.evento_alunos where evento_id=e.id) and not coalesce((args->>'confirmChanges')::boolean,false) then raise exception 'Confirme a edição: as seleções já enviadas serão preservadas e a nova configuração valerá para novos destinatários.' using errcode='22023';end if;
  end if;
  if length(trim(coalesce(args->>'name',''))) not between 2 and 160 or length(trim(coalesce(args->>'description',''))) not between 1 and 4000
   or args->>'level' is null or args->>'level' not in ('facil','medio','dificil') or (args->>'minAge')::integer not between 4 and 19
   or (args->>'maxAge')::integer not between (args->>'minAge')::integer and 19 or (args->>'endsAt')::timestamptz<=(args->>'startsAt')::timestamptz
   or args->>'mode' is null or args->>'mode' not in ('ordem','sorteio') or jsonb_typeof(args->'storyIds') is distinct from 'array'
   or (args->>'quantity')::integer<1 then raise exception 'Confira nome, descrição, nível, faixa etária, datas e quantidade.' using errcode='22023';end if;
  select array_agg(v order by ord),count(distinct v) into ids,found_count from jsonb_array_elements_text(args->'storyIds') with ordinality as x(v,ord);
  if coalesce(cardinality(ids),0)=0 or cardinality(ids)<>found_count or (args->>'quantity')::integer>cardinality(ids) then raise exception 'Selecione histórias suficientes, sem duplicatas, para a quantidade por aluno.' using errcode='22023';end if;
  if exists(select 1 from unnest(ids) as candidate(story_id) where not exists(select 1 from public.textos t where t.id=candidate.story_id and t.nivel=args->>'level' and t.ativo and clube_private.texto_pronto(t.id) and clube_private.evento_faixa(t.faixa_etaria,(args->>'minAge')::integer,(args->>'maxAge')::integer))) then raise exception 'Selecione somente histórias publicadas, corrigíveis e compatíveis com o nível e toda a faixa etária.' using errcode='22023';end if;
  insert into public.eventos_leitura(id,nome,descricao,capa_url,nivel,idade_min,idade_max,inicio,fim,ativo,modo,quantidade)
   values(coalesce(e.id,(args->>'requestId')::uuid,gen_random_uuid()),trim(args->>'name'),trim(args->>'description'),nullif(args->>'cover',''),args->>'level',(args->>'minAge')::integer,(args->>'maxAge')::integer,(args->>'startsAt')::timestamptz,(args->>'endsAt')::timestamptz,(args->>'active')::boolean,args->>'mode',case when args->>'mode'='ordem' then cardinality(ids) else (args->>'quantity')::integer end)
   on conflict(id) do update set nome=excluded.nome,descricao=excluded.descricao,capa_url=excluded.capa_url,nivel=excluded.nivel,idade_min=excluded.idade_min,idade_max=excluded.idade_max,inicio=excluded.inicio,fim=excluded.fim,ativo=excluded.ativo,modo=excluded.modo,quantidade=excluded.quantidade,atualizado_em=now() returning * into e;
  delete from public.evento_historias where evento_id=e.id;
  insert into public.evento_historias(evento_id,texto_id,ordem) select e.id,id,ord::integer-1 from unnest(ids) with ordinality x(id,ord);
  return clube_private.evento_json(e);
 end if;
 select * into e from public.eventos_leitura where id=(args->>'id')::uuid for update;
 if e.id is null then raise exception 'Evento não encontrado' using errcode='P0002';end if;
 if op='get' then return clube_private.evento_json(e);
 elsif op='status' then
  update public.eventos_leitura set ativo=(args->>'active')::boolean,atualizado_em=now() where id=e.id returning * into e;return clube_private.evento_json(e);
 elsif op='delete' then
  if exists(select 1 from public.evento_alunos where evento_id=e.id) then
   update public.eventos_leitura set ativo=false,arquivado=true,atualizado_em=now() where id=e.id;return jsonb_build_object('archived',true);
  end if;
  delete from public.evento_historias where evento_id=e.id;delete from public.eventos_leitura where id=e.id;return jsonb_build_object('deleted',true);
 elsif op='recipients' then return clube_private.evento_destinatarios(e,args);
 elsif op='send' then
  if e.arquivado then raise exception 'Evento arquivado' using errcode='22023';end if;
  if jsonb_typeof(args->'studentIds') is distinct from 'array' then raise exception 'Selecione os destinatários.' using errcode='22023';end if;
  if jsonb_array_length(args->'studentIds')=0 and not coalesce((args->>'allFiltered')::boolean,false) then raise exception 'Selecione ao menos um aluno.' using errcode='22023';end if;
  -- Revalida e trava o conteúdo antes de capturar a versão enviada.
  perform 1 from public.textos t join public.evento_historias h on h.texto_id=t.id where h.evento_id=e.id order by t.id for share of t;
  select array_agg(h.texto_id order by h.ordem) into ids from public.evento_historias h join public.textos t on t.id=h.texto_id where h.evento_id=e.id
   and t.ativo and t.nivel=e.nivel and clube_private.texto_pronto(t.id) and clube_private.evento_faixa(t.faixa_etaria,e.idade_min,e.idade_max);
  if coalesce(cardinality(ids),0)<e.quantidade or cardinality(ids)<>(select count(*) from public.evento_historias where evento_id=e.id) then raise exception 'Revise as histórias do evento: há conteúdo indisponível ou quantidade insuficiente.' using errcode='22023';end if;
  if coalesce((args->>'allFiltered')::boolean,false) then
   args:=args||jsonb_build_object('studentIds',coalesce((select jsonb_agg(x->>'id') from jsonb_array_elements(clube_private.evento_destinatarios(e,args||jsonb_build_object('eligibleOnly',true))->'students') x),'[]'));
  end if;
  if jsonb_array_length(args->'studentIds')=0 then raise exception 'Nenhum aluno elegível nos filtros.' using errcode='22023';end if;
  if exists(select 1 from jsonb_array_elements_text(args->'studentIds') x where not exists(select 1 from public.alunos a where a.id=x::uuid and (exists(select 1 from public.evento_alunos p where p.evento_id=e.id and p.aluno_id=a.id) or clube_private.evento_elegivel(e,a)))) then raise exception 'Há alunos inexistentes, inativos ou incompatíveis com a idade ou o nível.' using errcode='22023';end if;
  for student in select distinct x::uuid from jsonb_array_elements_text(args->'studentIds') x order by 1 loop
   perform 1 from public.alunos where id=student for update;
   if exists(select 1 from public.evento_alunos where evento_id=e.id and aluno_id=student) then existing:=existing+1;continue;end if;
   if not exists(select 1 from public.alunos a where a.id=student and clube_private.evento_elegivel(e,a)) then raise exception 'Aluno não é mais elegível. Atualize os destinatários.' using errcode='22023';end if;
   sample_size:=case when e.modo='ordem' then cardinality(ids) else e.quantidade end;
   chosen:=ids;
   if e.modo='sorteio' then
    tries:=0;
    loop
     select array_agg(story_id order by rank) into chosen from(select candidate.story_id,row_number() over(order by exists(select 1 from public.tentativas done where done.aluno_id=student and done.texto_id=candidate.story_id and done.status='completed'),random()) as rank from unnest(ids) as candidate(story_id)) ranked where rank<=sample_size;
     select jsonb_agg(id order by id)::text into signature from unnest(chosen) id;
     exit when not exists(select 1 from public.evento_alunos where evento_id=e.id and assinatura=signature);
     tries:=tries+1;exit when tries>=32;
    end loop;
    if tries>=32 then
     -- Busca uma combinação ainda não usada; só repete quando todas já existem.
     select array_agg(n order by n) into comb from generate_series(1,sample_size) n;
     loop
      select array_agg(ids[n] order by ord) into chosen from unnest(comb) with ordinality as c(n,ord);
      select jsonb_agg(x order by x)::text into signature from unnest(chosen) x;
      exit when not exists(select 1 from public.evento_alunos p where p.evento_id=e.id and p.assinatura=signature);
      cursor:=sample_size;
      while cursor>0 loop
       exit when comb[cursor]<cardinality(ids)-sample_size+cursor;
       cursor:=cursor-1;
      end loop;
      if cursor=0 then
       select array_agg(x order by random()) into chosen from(select x from unnest(ids) x order by random() limit sample_size) s;
       exit;
      end if;
      comb[cursor]:=comb[cursor]+1;
      if cursor<sample_size then for j in cursor+1..sample_size loop comb[j]:=comb[j-1]+1;end loop;end if;
     end loop;
    end if;
   end if;
   select jsonb_agg(x order by x)::text into signature from unnest(chosen) x;
   insert into public.evento_alunos(evento_id,aluno_id,nivel,idade_min,idade_max,referencia,assinatura) values(e.id,student,e.nivel,e.idade_min,e.idade_max,(e.inicio at time zone 'America/Fortaleza')::date,signature) returning id into pid;
   for idx in 1..cardinality(chosen) loop
    insert into public.evento_leituras(participante_id,texto_id,ordem) values(pid,chosen[idx],idx-1) returning id into lid;
    insert into clube_private.evento_conteudos(leitura_id,atividade,gabarito)
     select lid,jsonb_build_object('id',t.id,'title',t.titulo,'author',t.autor,'cover',t.capa_url,'minutes',t.tempo_leitura_minutos,'content',t.conteudo,'age',t.faixa_etaria,'level',t.nivel,'questions',
      (select jsonb_agg(jsonb_build_object('id',q.id,'prompt',q.enunciado,'options',q.alternativas) order by q.id) from public.questoes q where q.texto_id=t.id and q.ativo)),
      (select jsonb_object_agg(q.id,jsonb_build_object('correct',g.correta,'points',coalesce(q.valor,n.pontos))) from public.questoes q join clube_private.gabaritos g on g.questao_id=q.id where q.texto_id=t.id and q.ativo)
     from public.textos t join public.niveis n on n.id=t.nivel where t.id=chosen[idx];
   end loop;
   created:=created+1;
  end loop;
  return jsonb_build_object('created',created,'existing',existing);
 end if;
 raise exception 'Operação inválida' using errcode='22023';
end $$;

-- O contexto do evento evita eliminar conclusões legítimas do mesmo texto em eventos distintos.
create or replace view clube_private.admin_resultados_validos as
 select distinct on(t.aluno_id,coalesce(t.evento_participante_id,t.jornada_id),t.texto_id) t.* from public.tentativas t
 cross join lateral(select count(*)::integer as answers,count(*) filter(where r.correta)::integer as hits,coalesce(sum(r.pontos),0) as points,
 bool_and(q.texto_id=t.texto_id and r.correta is not null and r.pontos is not null and r.pontos>=0 and (r.correta or r.pontos=0)) as corrected from public.respostas r join public.questoes q on q.id=r.questao_id where r.tentativa_id=t.id) v
 where t.status='completed' and t.concluida_em is not null and t.pontuacao>=0 and v.answers>0
 and v.answers=(select jsonb_array_length(s.atividade->'questions') from clube_private.conteudos_tentativas s where s.tentativa_id=t.id)
 and v.corrected and t.acertos=v.hits and t.pontuacao=v.points and abs(t.percentual-(100.0*v.hits/nullif(v.answers,0)))<0.0001
 order by t.aluno_id,coalesce(t.evento_participante_id,t.jornada_id),t.texto_id,t.concluida_em,t.id;

alter function public.clube_leitura(text,jsonb) rename to leitura_com_eventos_base;
alter function public.leitura_com_eventos_base(text,jsonb) set schema clube_private;
revoke all on function clube_private.leitura_com_eventos_base(text,jsonb) from public,anon,authenticated;
create function public.clube_leitura(op text,args jsonb default '{}') returns jsonb language plpgsql security definer set search_path='' as $$
declare student uuid;a public.tentativas;s clube_private.conteudos_tentativas;event_id uuid;qid integer;choice integer;total integer;idx integer;
begin
 student:=clube_private.aluno_atual();
 if student is null then raise exception 'Aluno não identificado' using errcode='42501';end if;
 if op not in ('get','stage','answer','finish') then return clube_private.leitura_com_eventos_base(op,args);end if;
 select * into a from public.tentativas where id=(args->>'id')::uuid and aluno_id=student;
 if a.id is null then raise exception 'Tentativa não encontrada' using errcode='42501';end if;
 if a.evento_participante_id is null then return clube_private.leitura_com_eventos_base(op,args);end if;
 select evento_id into event_id from public.evento_alunos where id=a.evento_participante_id and aluno_id=student;
 -- A mesma ordem de locks de enter/send impede correção concorrente e deadlocks.
 perform 1 from public.eventos_leitura where id=event_id for share;
 perform 1 from public.alunos where id=student for update;
 select * into a from public.tentativas where id=a.id for update;
 if a.status='completed' and op in ('get','finish') then return clube_private.leitura_tentativa(a)||jsonb_build_object('eventId',event_id);end if;
 if not clube_private.evento_disponivel(event_id,student) then raise exception 'Evento indisponível neste período; seu progresso está salvo.' using errcode='42501';end if;
 if op='get' then return clube_private.leitura_tentativa(a)||jsonb_build_object('eventId',event_id);end if;
 if a.status='completed' then raise exception 'Leitura já concluída' using errcode='22023';end if;
 select * into s from clube_private.conteudos_tentativas where tentativa_id=a.id;total:=jsonb_array_length(s.atividade->'questions');
 if op='stage' then
  if args->>'stage' is null or args->>'stage' not in ('leitura','questoes') then raise exception 'Etapa inválida' using errcode='22023';end if;
  update public.tentativas set etapa=args->>'stage' where id=a.id returning * into a;
 elsif op='answer' then
  qid:=(args->>'questionId')::integer;choice:=(args->>'selected')::integer;
  if a.etapa<>'questoes' or choice is null or choice not between 0 and 3 or not exists(select 1 from jsonb_array_elements(s.atividade->'questions') q where (q->>'id')::integer=qid) then raise exception 'Resposta inválida' using errcode='22023';end if;
  insert into public.respostas(tentativa_id,questao_id,selecionada) values(a.id,qid,choice) on conflict(tentativa_id,questao_id) do update set selecionada=excluded.selecionada;
  select ord::integer-1 into idx from jsonb_array_elements(s.atividade->'questions') with ordinality as x(q,ord) where not exists(select 1 from public.respostas r where r.tentativa_id=a.id and r.questao_id=(q->>'id')::integer) order by ord limit 1;
  update public.tentativas set questao_atual=coalesce(idx,greatest(total-1,0)) where id=a.id returning * into a;
 elsif op='finish' then
  if total=0 or (select count(*) from public.respostas where tentativa_id=a.id)<>total or (select count(*) from jsonb_object_keys(s.gabarito))<>total then raise exception 'Responda a todas as questões' using errcode='22023';end if;
  update public.respostas r set correta=r.selecionada=(s.gabarito->r.questao_id::text->>'correct')::integer,pontos=case when r.selecionada=(s.gabarito->r.questao_id::text->>'correct')::integer then (s.gabarito->r.questao_id::text->>'points')::integer else 0 end where r.tentativa_id=a.id;
  update public.tentativas set status='completed',etapa='resultado',concluida_em=now(),acertos=(select count(*) from public.respostas where tentativa_id=a.id and correta),pontuacao=(select coalesce(sum(pontos),0) from public.respostas where tentativa_id=a.id),percentual=(select 100.0*count(*) filter(where correta)/count(*) from public.respostas where tentativa_id=a.id) where id=a.id returning * into a;
 end if;
 return clube_private.leitura_tentativa(a)||jsonb_build_object('eventId',event_id);
end $$;
revoke all on function public.clube_leitura(text,jsonb),public.clube_eventos(text,jsonb) from public,anon;
grant execute on function public.clube_leitura(text,jsonb),public.clube_eventos(text,jsonb) to authenticated;
revoke all on function clube_private.evento_disponivel(uuid,uuid),clube_private.evento_json(public.eventos_leitura),clube_private.evento_faixa(text,integer,integer),clube_private.evento_elegivel(public.eventos_leitura,public.alunos),clube_private.evento_destinatarios(public.eventos_leitura,jsonb) from public,anon,authenticated;
-- O endpoint legado não pode contornar o período e a autorização do evento.
alter function public.clube_api(text,jsonb) rename to api_antes_eventos;
alter function public.api_antes_eventos(text,jsonb) set schema clube_private;
revoke all on function clube_private.api_antes_eventos(text,jsonb) from public,anon,authenticated;
create function public.clube_api(op text,args jsonb default '{}') returns jsonb language plpgsql security definer set search_path='' as $$
begin
 if op in ('get','answer','finish') and exists(select 1 from public.tentativas where id=(args->>'id')::uuid and evento_participante_id is not null) then
  return public.clube_leitura(op,args);
 end if;
 return clube_private.api_antes_eventos(op,args);
end $$;
revoke all on function public.clube_api(text,jsonb) from public,anon;
grant execute on function public.clube_api(text,jsonb) to authenticated;
notify pgrst,'reload schema';
commit;
