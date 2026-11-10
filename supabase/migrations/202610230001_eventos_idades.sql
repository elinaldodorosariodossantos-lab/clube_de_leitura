begin;
-- Extensão aditiva: eventos e distribuições anteriores permanecem válidos.
alter table public.eventos_leitura add column configuracoes jsonb not null default '[]' check(jsonb_typeof(configuracoes)='array');
alter table public.evento_alunos add column idade_referencia integer check(idade_referencia between 4 and 19),add column configuracao jsonb not null default '[]' check(jsonb_typeof(configuracao)='array');
update public.evento_alunos p set idade_referencia=extract(year from age(p.referencia,a.data_nascimento))::integer from public.alunos a where a.id=p.aluno_id and a.data_nascimento is not null and extract(year from age(p.referencia,a.data_nascimento)) between 4 and 19;

create function clube_private.evento_config_estado(configs jsonb) returns jsonb language sql stable security definer set search_path='' as $$
 select coalesce(jsonb_agg(jsonb_build_object('age',(a->>'age')::integer,'level',l->>'level','requested',(l->>'quantity')::integer,'selected',jsonb_array_length(l->'storyIds'),
 'available',(select count(*) from public.textos t where t.id in(select jsonb_array_elements_text(l->'storyIds')) and t.nivel=l->>'level' and t.ativo and clube_private.texto_pronto(t.id) and clube_private.evento_faixa(t.faixa_etaria,(a->>'age')::integer,(a->>'age')::integer))) order by (a->>'age')::integer,l->>'level'),'[]')
 from jsonb_array_elements(configs) a cross join lateral jsonb_array_elements(a->'levels') l
$$;
create or replace function clube_private.evento_json(e public.eventos_leitura) returns jsonb language sql stable security definer set search_path='' as $$
 select jsonb_build_object('id',e.id,'name',e.nome,'description',e.descricao,'cover',coalesce(e.capa_url,''),'level',e.nivel,'minAge',e.idade_min,'maxAge',e.idade_max,
 'startsAt',e.inicio,'endsAt',e.fim,'active',e.ativo,'archived',e.arquivado,'mode',e.modo,'quantity',e.quantidade,'ageConfigs',e.configuracoes,
 'status',case when e.arquivado then 'arquivado' when not e.ativo then 'inativo' when now()<e.inicio then 'programado' when now()>=e.fim then 'encerrado' else 'ativo' end,
 'storyIds',coalesce((select jsonb_agg(h.texto_id order by h.ordem) from public.evento_historias h where h.evento_id=e.id),'[]'),'recipients',(select count(*) from public.evento_alunos where evento_id=e.id))
$$;
create or replace function clube_private.evento_elegivel(e public.eventos_leitura,a public.alunos) returns boolean language sql stable security definer set search_path='' as $$
 select a.situacao='ativo' and a.data_nascimento is not null and case when jsonb_array_length(e.configuracoes)=0 then
 extract(year from age((e.inicio at time zone 'America/Fortaleza')::date,a.data_nascimento)) between e.idade_min and e.idade_max and clube_private.nivel_liberado(a.id,e.nivel)
 else exists(select 1 from jsonb_array_elements(e.configuracoes) c cross join lateral jsonb_array_elements(c->'levels') l
 where (c->>'age')::integer=extract(year from age((e.inicio at time zone 'America/Fortaleza')::date,a.data_nascimento)) and clube_private.nivel_liberado(a.id,l->>'level')) end
$$;

create function clube_private.evento_sortear(event_id uuid,student uuid,student_age integer,level_id text,pool text[],amount integer) returns text[] language plpgsql security definer set search_path='' as $$
declare chosen text[];signature text;tries integer:=0;comb integer[];cursor integer;j integer;
begin
 if amount<1 or amount>coalesce(cardinality(pool),0) then raise exception 'Histórias insuficientes para % anos / %: disponíveis %, solicitadas %.',student_age,level_id,coalesce(cardinality(pool),0),amount using errcode='22023';end if;
 loop
  select array_agg(story_id order by pos) into chosen from(select candidate.story_id,row_number() over(order by exists(select 1 from public.tentativas d where d.aluno_id=student and d.texto_id=candidate.story_id and d.status='completed'),random()) pos from unnest(pool) candidate(story_id)) ranked where pos<=amount;
  select jsonb_agg(x order by x)::text into signature from unnest(chosen) x;
  exit when not exists(select 1 from public.evento_alunos p cross join lateral jsonb_array_elements(p.configuracao) c where p.evento_id=event_id and p.idade_referencia=student_age and c->>'level'=level_id and c->>'signature'=signature);
  tries:=tries+1;exit when tries>=32;
 end loop;
 if tries>=32 then
  select array_agg(n order by n) into comb from generate_series(1,amount) n;
  loop
   select array_agg(pool[n] order by ord) into chosen from unnest(comb) with ordinality as c(n,ord);
   select jsonb_agg(x order by x)::text into signature from unnest(chosen) x;
   exit when not exists(select 1 from public.evento_alunos p cross join lateral jsonb_array_elements(p.configuracao) c where p.evento_id=event_id and p.idade_referencia=student_age and c->>'level'=level_id and c->>'signature'=signature);
   cursor:=amount;
   while cursor>0 loop exit when comb[cursor]<cardinality(pool)-amount+cursor;cursor:=cursor-1;end loop;
   if cursor=0 then select array_agg(x order by random()) into chosen from(select x from unnest(pool) x order by random() limit amount) s;exit;end if;
   comb[cursor]:=comb[cursor]+1;
   if cursor<amount then for j in cursor+1..amount loop comb[j]:=comb[j-1]+1;end loop;end if;
  end loop;
 end if;
 return chosen;
end $$;
create function clube_private.evento_guardar_leitura(pid uuid,story_id text,item_order integer) returns void language plpgsql security definer set search_path='' as $$
declare lid uuid;
begin
 insert into public.evento_leituras(participante_id,texto_id,ordem) values(pid,story_id,item_order) returning id into lid;
 insert into clube_private.evento_conteudos(leitura_id,atividade,gabarito)
 select lid,jsonb_build_object('id',t.id,'title',t.titulo,'author',t.autor,'cover',t.capa_url,'minutes',t.tempo_leitura_minutos,'content',t.conteudo,'age',t.faixa_etaria,'level',t.nivel,'questions',
 (select jsonb_agg(jsonb_build_object('id',q.id,'prompt',q.enunciado,'options',q.alternativas) order by q.id) from public.questoes q where q.texto_id=t.id and q.ativo)),
 (select jsonb_object_agg(q.id,jsonb_build_object('correct',g.correta,'points',coalesce(q.valor,n.pontos))) from public.questoes q join clube_private.gabaritos g on g.questao_id=q.id where q.texto_id=t.id and q.ativo)
 from public.textos t join public.niveis n on n.id=t.nivel where t.id=story_id;
end $$;

alter function public.clube_eventos(text,jsonb) rename to eventos_antes_idades;
alter function public.eventos_antes_idades(text,jsonb) set schema clube_private;
revoke all on function clube_private.eventos_antes_idades(text,jsonb) from public,anon,authenticated;
create function public.clube_eventos(op text,args jsonb default '{}') returns jsonb language plpgsql security definer set search_path='' as $$
declare e public.eventos_leitura;a jsonb;l jsonb;configs jsonb;cfg jsonb;states jsonb;bad jsonb;pool text[];chosen text[];all_ids text[];student uuid;participant_row public.evento_alunos;student_row public.alunos;age_value integer;age_min integer;age_max integer;quantity_max integer;amount integer;item_order integer;sid uuid;item record;result jsonb;signature text;created integer:=0;kept integer:=0;
begin
 if op='mine' then
  result:=clube_private.eventos_antes_idades(op,args);
  return coalesce((select jsonb_agg((x-'ageConfigs')||jsonb_build_object('age',p.idade_referencia,'assignedLevels',coalesce((select jsonb_agg(jsonb_build_object('level',c->>'level','quantity',(c->>'quantity')::integer)) from jsonb_array_elements(p.configuracao) c),'[]')) order by ord)
   from jsonb_array_elements(result) with ordinality as r(x,ord) join public.evento_alunos p on p.evento_id=(x->>'id')::uuid and p.aluno_id=clube_private.aluno_atual()),'[]');
 end if;
 if op='enter' then
  student:=clube_private.aluno_atual();if student is null then raise exception 'Aluno não identificado' using errcode='42501';end if;
  select * into e from public.eventos_leitura where id=(args->>'id')::uuid for share;
  if not clube_private.evento_disponivel(e.id,student) then raise exception 'Evento indisponível neste período.' using errcode='42501';end if;
  perform 1 from public.alunos where id=student for update;
  select * into participant_row from public.evento_alunos where evento_id=e.id and aluno_id=student for update;
  if jsonb_array_length(participant_row.configuracao)=0 then return clube_private.eventos_antes_idades(op,args);end if;
  select r.* into item from public.evento_leituras r left join public.tentativas t on t.id=r.tentativa_id where r.participante_id=participant_row.id and (t.id is null or t.status<>'completed') order by r.ordem limit 1 for update of r;
  if item.id is null then return jsonb_build_object('attempt',null,'complete',true);end if;
  if item.tentativa_id is null then
   insert into public.tentativas(aluno_id,texto_id,nivel,evento_participante_id) select student,item.texto_id,c.atividade->>'level',participant_row.id from clube_private.evento_conteudos c where c.leitura_id=item.id returning id into sid;
   update clube_private.conteudos_tentativas t set atividade=c.atividade,gabarito=c.gabarito from clube_private.evento_conteudos c where t.tentativa_id=sid and c.leitura_id=item.id;
   update public.evento_leituras set tentativa_id=sid where id=item.id;
  else sid:=item.tentativa_id;end if;
  return jsonb_build_object('attempt',(select clube_private.leitura_tentativa(t)||jsonb_build_object('eventId',e.id) from public.tentativas t where t.id=sid),'complete',false);
 end if;
 if not clube_private.administrador() then raise exception 'Administrador obrigatório' using errcode='42501';end if;
 if op='age_config_ready' then return 'true'::jsonb;end if;
 if op='recipients' then
  select * into e from public.eventos_leitura where id=(args->>'id')::uuid;
  if e.id is null then raise exception 'Evento não encontrado' using errcode='P0002';end if;
  result:=clube_private.evento_destinatarios(e,args);
  return jsonb_set(result,'{students}',coalesce((select jsonb_agg(x||jsonb_build_object('eligibleLevels',case when jsonb_array_length(e.configuracoes)=0 then case when (x->>'eligible')::boolean then jsonb_build_array(jsonb_build_object('level',e.nivel,'quantity',e.quantidade)) else '[]'::jsonb end else
   coalesce((select jsonb_agg(jsonb_build_object('level',v->>'level','quantity',(v->>'quantity')::integer)) from jsonb_array_elements(e.configuracoes) c cross join lateral jsonb_array_elements(c->'levels') v where c->>'age'=x->>'age' and clube_private.nivel_liberado((x->>'id')::uuid,v->>'level')),'[]') end) order by ord)
   from jsonb_array_elements(result->'students') with ordinality as row(x,ord)),'[]'));
 end if;
 if op='list' then
  return coalesce((select jsonb_agg(data order by data->>'startsAt',data->>'name') from(select clube_private.evento_json(x) data from public.eventos_leitura x where not x.arquivado
   and (coalesce(args->>'search','')='' or strpos(lower(x.nome),lower(args->>'search'))>0)
   and (coalesce(args->>'level','')='' or (jsonb_array_length(x.configuracoes)=0 and x.nivel=args->>'level') or exists(select 1 from jsonb_array_elements(x.configuracoes) c cross join lateral jsonb_array_elements(c->'levels') v where v->>'level'=args->>'level'))
   and (coalesce(args->>'age','')='' or (jsonb_array_length(x.configuracoes)=0 and (args->>'age')::integer between x.idade_min and x.idade_max) or exists(select 1 from jsonb_array_elements(x.configuracoes) c where c->>'age'=args->>'age'))) r
   where coalesce(args->>'status','')='' or data->>'status'=args->>'status'),'[]');
 end if;
 if op='eligible_stories' then
  result:=clube_private.eventos_antes_idades(op,args);
  return coalesce((select jsonb_agg(x) from jsonb_array_elements(result) x where (x->>'eligible')::boolean),'[]');
 end if;
 if op='save' and args ? 'ageConfigs' then
  configs:=args->'ageConfigs';
  if jsonb_typeof(configs) is distinct from 'array' or jsonb_array_length(configs) not between 1 and 16 then raise exception 'Adicione de 1 a 16 idades, entre 4 e 19 anos.' using errcode='22023';end if;
  if (select count(distinct c->>'age') from jsonb_array_elements(configs) c)<>jsonb_array_length(configs) then raise exception 'Não repita idades no evento.' using errcode='22023';end if;
  for a in select value from jsonb_array_elements(configs) loop
   age_value:=(a->>'age')::integer;
   if age_value is null or age_value not between 4 and 19 or jsonb_typeof(a->'levels') is distinct from 'array' or jsonb_array_length(a->'levels') not between 1 and 3 then raise exception 'Cada idade precisa de ao menos um nível configurado (4 a 19 anos).' using errcode='22023';end if;
   if (select count(distinct x->>'level') from jsonb_array_elements(a->'levels') x)<>jsonb_array_length(a->'levels') then raise exception 'Não repita níveis na mesma idade.' using errcode='22023';end if;
   for l in select value from jsonb_array_elements(a->'levels') loop
    amount:=(l->>'quantity')::integer;
    if l->>'level' is null or l->>'level' not in ('facil','medio','dificil') or amount is null or amount<1 or jsonb_typeof(l->'storyIds') is distinct from 'array' then raise exception 'Configure um nível válido, o conjunto e histórias por aluno.' using errcode='22023';end if;
    if (select count(distinct x) from jsonb_array_elements_text(l->'storyIds') x)<>jsonb_array_length(l->'storyIds') then raise exception 'Não repita histórias no conjunto.' using errcode='22023';end if;
   end loop;
  end loop;
  states:=clube_private.evento_config_estado(configs);
  select x into bad from jsonb_array_elements(states) x where (x->>'available')::integer<(x->>'requested')::integer or (x->>'available')::integer<>(x->>'selected')::integer limit 1;
  if bad is not null then raise exception '% anos / %: % histórias elegíveis no conjunto; % solicitadas. Revise as histórias selecionadas.',bad->>'age',bad->>'level',bad->>'available',bad->>'requested' using errcode='22023';end if;
  if length(trim(coalesce(args->>'name',''))) not between 2 and 160 or length(trim(coalesce(args->>'description',''))) not between 1 and 4000 or (args->>'startsAt')::timestamptz is null or (args->>'endsAt')::timestamptz is null or (args->>'endsAt')::timestamptz<=(args->>'startsAt')::timestamptz then raise exception 'Confira nome, descrição e período do evento.' using errcode='22023';end if;
  if args ? 'id' then
   select * into e from public.eventos_leitura where id=(args->>'id')::uuid for update;
   if e.id is null then raise exception 'Evento não encontrado' using errcode='P0002';end if;
   if exists(select 1 from public.evento_alunos where evento_id=e.id) and not coalesce((args->>'confirmChanges')::boolean,false) then raise exception 'Confirme a edição. Configurações anteriores já distribuídas serão preservadas.' using errcode='22023';end if;
  else
   if args->>'requestId' is null then raise exception 'Identificador do cadastro obrigatório' using errcode='22023';end if;
   perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended(args->>'requestId',0));
   select * into e from public.eventos_leitura where id=(args->>'requestId')::uuid for update;
   if e.id is not null then return clube_private.evento_json(e);end if;
  end if;
  select min((c->>'age')::integer),max((c->>'age')::integer),max((select sum((x->>'quantity')::integer) from jsonb_array_elements(c->'levels') x)) into age_min,age_max,quantity_max from jsonb_array_elements(configs) c;
  insert into public.eventos_leitura(id,nome,descricao,capa_url,nivel,idade_min,idade_max,inicio,fim,ativo,modo,quantidade,configuracoes)
   values(coalesce(e.id,(args->>'requestId')::uuid),trim(args->>'name'),trim(args->>'description'),nullif(args->>'cover',''),configs->0->'levels'->0->>'level',age_min,age_max,(args->>'startsAt')::timestamptz,(args->>'endsAt')::timestamptz,(args->>'active')::boolean,'sorteio',quantity_max,configs)
   on conflict(id) do update set nome=excluded.nome,descricao=excluded.descricao,capa_url=excluded.capa_url,nivel=excluded.nivel,idade_min=excluded.idade_min,idade_max=excluded.idade_max,inicio=excluded.inicio,fim=excluded.fim,ativo=excluded.ativo,modo=excluded.modo,quantidade=excluded.quantidade,configuracoes=excluded.configuracoes,atualizado_em=now() returning * into e;
  delete from public.evento_historias where evento_id=e.id;
  insert into public.evento_historias(evento_id,texto_id,ordem) select e.id,story_id,row_number() over(order by story_id)::integer-1 from(select distinct jsonb_array_elements_text(v->'storyIds') story_id from jsonb_array_elements(configs) c cross join lateral jsonb_array_elements(c->'levels') v) s;
  return clube_private.evento_json(e);
 end if;
 if op in ('distribution_check','send','report') then
  select * into e from public.eventos_leitura where id=(args->>'id')::uuid for update;
  if e.id is null then raise exception 'Evento não encontrado' using errcode='P0002';end if;
  if op='report' then
   return coalesce((with groups as(select p.id,p.idade_referencia as age,c->>'level' as level,(c->>'quantity')::integer as assigned from public.evento_alunos p cross join lateral jsonb_array_elements(case when jsonb_array_length(p.configuracao)>0 then p.configuracao else jsonb_build_array(jsonb_build_object('level',p.nivel,'quantity',(select count(*) from public.evento_leituras r where r.participante_id=p.id))) end) c where p.evento_id=e.id)
    select jsonb_agg(to_jsonb(s) order by s.age,s.level) from(select age,level,count(*) as students,sum(assigned) as assigned,
    (select count(*) from clube_private.admin_resultados_validos v join public.evento_alunos p on p.id=v.evento_participante_id where p.evento_id=e.id and p.idade_referencia is not distinct from g.age and v.nivel=g.level) as completed,
    (select coalesce(sum(v.pontuacao),0) from clube_private.admin_resultados_validos v join public.evento_alunos p on p.id=v.evento_participante_id where p.evento_id=e.id and p.idade_referencia is not distinct from g.age and v.nivel=g.level) as points
    from groups g group by age,level) s),'[]');
  end if;
  if jsonb_array_length(e.configuracoes)=0 then
   if op='send' then
    result:=clube_private.eventos_antes_idades(op,args);
    update public.evento_alunos p set idade_referencia=extract(year from age(p.referencia,a.data_nascimento))::integer from public.alunos a where p.evento_id=e.id and a.id=p.aluno_id and p.idade_referencia is null and a.data_nascimento is not null;
    return result;
   end if;
   return jsonb_build_object('valid',(select count(*)>=e.quantidade from public.evento_historias h join public.textos t on t.id=h.texto_id where h.evento_id=e.id and t.ativo and clube_private.texto_pronto(t.id) and t.nivel=e.nivel and clube_private.evento_faixa(t.faixa_etaria,e.idade_min,e.idade_max)),'groups','[]'::jsonb);
  end if;
  -- Trava o conteúdo para a revalidação e a captura serem consistentes.
  perform 1 from public.textos t join public.evento_historias h on h.texto_id=t.id where h.evento_id=e.id order by t.id for share of t;
  states:=clube_private.evento_config_estado(e.configuracoes);
  select x into bad from jsonb_array_elements(states) x where (x->>'available')::integer<(x->>'requested')::integer or (x->>'available')::integer<>(x->>'selected')::integer limit 1;
  if op='distribution_check' then return jsonb_build_object('valid',bad is null,'groups',states);end if;
  if bad is not null then raise exception '% anos / %: % histórias disponíveis no conjunto; % solicitadas. Corrija antes de distribuir.',bad->>'age',bad->>'level',bad->>'available',bad->>'requested' using errcode='22023';end if;
  if e.arquivado then raise exception 'Evento arquivado' using errcode='22023';end if;
  if jsonb_typeof(args->'studentIds') is distinct from 'array' or jsonb_array_length(args->'studentIds')=0 then raise exception 'Selecione os alunos.' using errcode='22023';end if;
  if exists(select 1 from jsonb_array_elements_text(args->'studentIds') x where not exists(select 1 from public.alunos a where a.id=x::uuid)) then raise exception 'Aluno não encontrado. Atualize os destinatários.' using errcode='22023';end if;
  for student in select distinct x::uuid from jsonb_array_elements_text(args->'studentIds') x order by 1 loop
   select * into student_row from public.alunos where id=student for update;
   if exists(select 1 from public.evento_alunos where evento_id=e.id and aluno_id=student) then kept:=kept+1;continue;end if;
   if not clube_private.evento_elegivel(e,student_row) then raise exception 'Aluno não elegível: confira nascimento, idade configurada, situação e níveis liberados.' using errcode='22023';end if;
   age_value:=extract(year from age((e.inicio at time zone 'America/Fortaleza')::date,student_row.data_nascimento));cfg:='[]';all_ids:=array[]::text[];
   for l in select v from jsonb_array_elements(e.configuracoes) c cross join lateral jsonb_array_elements(c->'levels') v where (c->>'age')::integer=age_value and clube_private.nivel_liberado(student,v->>'level') order by case v->>'level' when 'facil' then 1 when 'medio' then 2 else 3 end loop
    select array_agg(x order by ord) into pool from jsonb_array_elements_text(l->'storyIds') with ordinality as y(x,ord);
    chosen:=clube_private.evento_sortear(e.id,student,age_value,l->>'level',pool,(l->>'quantity')::integer);
    select jsonb_agg(x order by x)::text into signature from unnest(chosen) x;
    cfg:=cfg||jsonb_build_array(jsonb_build_object('level',l->>'level','quantity',cardinality(chosen),'storyIds',to_jsonb(chosen),'signature',signature));all_ids:=all_ids||chosen;
   end loop;
   insert into public.evento_alunos(evento_id,aluno_id,nivel,idade_min,idade_max,referencia,assinatura,idade_referencia,configuracao)
    values(e.id,student,cfg->0->>'level',age_value,age_value,(e.inicio at time zone 'America/Fortaleza')::date,to_jsonb(all_ids)::text,age_value,cfg) returning * into participant_row;
   for item_order in 1..cardinality(all_ids) loop perform clube_private.evento_guardar_leitura(participant_row.id,all_ids[item_order],item_order-1);end loop;
   created:=created+1;
  end loop;
  return jsonb_build_object('created',created,'existing',kept);
 end if;
 if op='save' and args ? 'id' and exists(select 1 from public.eventos_leitura where id=(args->>'id')::uuid and jsonb_array_length(configuracoes)>0) then
  raise exception 'Este evento usa configurações por idade. Reabra o formulário atualizado para preservar os conjuntos.' using errcode='22023';
 end if;
 return clube_private.eventos_antes_idades(op,args);
end $$;
revoke all on function public.clube_eventos(text,jsonb) from public,anon;
grant execute on function public.clube_eventos(text,jsonb) to authenticated;
revoke all on function clube_private.evento_config_estado(jsonb),clube_private.evento_sortear(uuid,uuid,integer,text,text[],integer),clube_private.evento_guardar_leitura(uuid,text,integer) from public,anon,authenticated;
notify pgrst,'reload schema';
commit;
