-- Clube da Leitura: instala somente as etapas ainda ausentes de gestão e eventos.
-- Execute o arquivo completo no SQL Editor do Supabase após a migração de sequência.
-- A operação é transacional e não apaga cadastros ou resultados existentes.
begin;
do $instalar_eventos$
begin
 if not exists(select 1 from information_schema.columns where table_schema='public' and table_name='textos' and column_name='ordem') then
  raise exception 'Execute primeiro 202610190001_progressao.sql e 202610190002_sequencia.sql, caso ainda não tenham sido aplicadas.';
 end if;
 if to_regprocedure('public.clube_gestao(text,jsonb)') is null then
 execute $etapa_202610190003$
-- Requer as migrações de progressão e sequência. Preserva cadastros e tentativas.
do $preflight$ begin
 if to_regprocedure('clube_private.clube_leitura(text,jsonb)') is null or not exists(select 1 from information_schema.columns where table_schema='public' and table_name='textos' and column_name='ordem') then
  raise exception 'Aplique 202610190001_progressao.sql e 202610190002_sequencia.sql antes desta migração';
 end if;
end $preflight$;
alter table public.alunos add column data_nascimento date,add column responsavel text,add column ano_letivo integer not null default extract(year from current_date)::integer check(ano_letivo between 2000 and 2100);
update public.alunos set ano_letivo=extract(year from criado_em)::integer;
alter table clube_private.acessos add column codigo_curto_hash text unique,add column credencial_cifrada text;
alter table clube_private.acessos add constraint codigo_curto_formato check(codigo_curto_hash is null or codigo_curto_hash ~ '^[a-f0-9]{64}$'),
 add constraint credenciais_completas check((codigo_curto_hash is null)=(credencial_cifrada is null));
create table clube_private.tentativas_acesso(usuario_id uuid primary key references auth.users(id),inicio timestamptz not null default now(),quantidade integer not null default 0);
alter table clube_private.tentativas_acesso enable row level security;
revoke all on clube_private.tentativas_acesso from public,anon,authenticated;
alter table public.textos add column autor text not null default '';
alter table public.questoes add column ativo boolean not null default true;
create index questoes_ativas_texto_idx on public.questoes(texto_id,id) where ativo;
create sequence clube_private.questoes_ids;
revoke all on sequence clube_private.questoes_ids from public,anon,authenticated;
select setval('clube_private.questoes_ids',greatest(1,coalesce((select max(id) from public.questoes),0)),true);
create table clube_private.conteudos_tentativas(
 tentativa_id uuid primary key references public.tentativas(id),atividade jsonb not null,gabarito jsonb not null);
alter table clube_private.conteudos_tentativas enable row level security;
revoke all on clube_private.conteudos_tentativas from public,anon,authenticated;

create function clube_private.snapshot_leitura() returns trigger language plpgsql security definer set search_path='' as $$
begin
 insert into clube_private.conteudos_tentativas(tentativa_id,atividade,gabarito)
 select new.id,jsonb_build_object('id',t.id,'title',t.titulo,'author',t.autor,'cover',t.capa_url,'minutes',t.tempo_leitura_minutos,'content',t.conteudo,'age',t.faixa_etaria,'level',t.nivel,'questions',
  coalesce((select jsonb_agg(jsonb_build_object('id',q.id,'prompt',q.enunciado,'options',q.alternativas) order by q.id) from public.questoes q where q.texto_id=t.id and q.ativo),'[]')),
  coalesce((select jsonb_object_agg(q.id,jsonb_build_object('correct',g.correta,'points',coalesce(q.valor,n.pontos))) from public.questoes q join clube_private.gabaritos g on g.questao_id=q.id where q.texto_id=t.id and q.ativo),'{}')
 from public.textos t join public.niveis n on n.id=t.nivel where t.id=new.texto_id;
 return new;
end $$;
create trigger snapshot_leitura after insert on public.tentativas for each row execute function clube_private.snapshot_leitura();
-- Captura o conteúdo atual de todas as tentativas anteriores antes de permitir edição.
insert into clube_private.conteudos_tentativas(tentativa_id,atividade,gabarito)
 select a.id,jsonb_build_object('id',t.id,'title',t.titulo,'author',t.autor,'cover',t.capa_url,'minutes',t.tempo_leitura_minutos,'content',t.conteudo,'age',t.faixa_etaria,'level',t.nivel,'questions',
 coalesce((select jsonb_agg(jsonb_build_object('id',q.id,'prompt',q.enunciado,'options',q.alternativas) order by q.id) from public.questoes q where q.texto_id=t.id),'[]')),
 coalesce((select jsonb_object_agg(q.id,jsonb_build_object('correct',g.correta,'points',coalesce(q.valor,n.pontos))) from public.questoes q join clube_private.gabaritos g on g.questao_id=q.id where q.texto_id=t.id),'{}')
 from public.tentativas a join public.textos t on t.id=a.texto_id join public.niveis n on n.id=a.nivel;

create or replace function clube_private.texto_pronto(text_id text) returns boolean language sql stable security definer set search_path='' as $$
 select exists(select 1 from public.questoes where texto_id=text_id and ativo) and not exists(select 1 from public.questoes q where q.texto_id=text_id and q.ativo and not exists(select 1 from clube_private.gabaritos g where g.questao_id=q.id))
$$;
create or replace function clube_private.attempt_json(a public.tentativas) returns jsonb language sql stable security definer set search_path='' as $$
 select jsonb_build_object('id',a.id,'status',a.status,'completedAt',a.concluida_em,'answers',coalesce((select jsonb_object_agg(r.questao_id,r.selecionada) from public.respostas r where r.tentativa_id=a.id),'{}'),
 'result',case when a.status='completed' then jsonb_build_object('hits',a.acertos,'points',a.pontuacao,'percentage',a.percentual,'details',
 coalesce((select jsonb_agg(q||jsonb_build_object('selected',r.selecionada,'correct',(s.gabarito->(q->>'id')->>'correct')::integer,'points',r.pontos) order by ord)
 from clube_private.conteudos_tentativas s cross join lateral jsonb_array_elements(s.atividade->'questions') with ordinality as items(q,ord)
 join public.respostas r on r.tentativa_id=a.id and r.questao_id=(q->>'id')::integer where s.tentativa_id=a.id),'[]')) else null end)
$$;
create or replace function clube_private.leitura_tentativa(a public.tentativas) returns jsonb language sql stable security definer set search_path='' as $$
 select clube_private.attempt_json(a)||jsonb_build_object('journeyId',a.jornada_id,'level',a.nivel,'stage',a.etapa,'index',a.questao_atual,
 'activity',(select atividade from clube_private.conteudos_tentativas where tentativa_id=a.id))
$$;
-- Correção das tentativas usa o gabarito privado capturado ao iniciar, não a edição atual.
alter function clube_private.clube_leitura(text,jsonb) rename to clube_leitura_anterior;
create function clube_private.clube_leitura(op text,args jsonb default '{}') returns jsonb language plpgsql security definer set search_path='' as $$
declare student uuid;a public.tentativas;s clube_private.conteudos_tentativas;qid integer;choice integer;total integer;idx integer;
begin
 if op not in ('stage','answer','finish') then return clube_private.clube_leitura_anterior(op,args);end if;
 student:=clube_private.aluno_atual();if student is null then raise exception 'Aluno não identificado' using errcode='42501';end if;
 perform 1 from public.alunos where id=student for update;
 select * into a from public.tentativas where id=(args->>'id')::uuid and aluno_id=student for update;
 if a.id is null then raise exception 'Tentativa não encontrada' using errcode='42501';end if;
 if a.status='completed' and op='finish' then return clube_private.leitura_tentativa(a);end if;
 if a.status='completed' then raise exception 'Atividade já concluída' using errcode='22023';end if;
 if not clube_private.texto_autorizado(student,a.texto_id) or a.jornada_id is distinct from (select id from public.jornadas where aluno_id=student order by ciclo desc limit 1) then raise exception 'Leitura indisponível; progresso preservado' using errcode='42501';end if;
 select * into s from clube_private.conteudos_tentativas where tentativa_id=a.id;total:=jsonb_array_length(s.atividade->'questions');
 if op='stage' then
  if args->>'stage' is null or args->>'stage' not in ('leitura','questoes') then raise exception 'Etapa inválida' using errcode='22023';end if;
  update public.tentativas set etapa=args->>'stage' where id=a.id returning * into a;
 elsif op='answer' then
  qid:=(args->>'questionId')::integer;choice:=(args->>'selected')::integer;
  if a.etapa<>'questoes' or choice is null or choice not between 0 and 3 or not exists(select 1 from jsonb_array_elements(s.atividade->'questions') q where (q->>'id')::integer=qid) then raise exception 'Resposta inválida' using errcode='22023';end if;
  insert into public.respostas(tentativa_id,questao_id,selecionada) values(a.id,qid,choice) on conflict(tentativa_id,questao_id) do update set selecionada=excluded.selecionada;
  select ord::integer-1 into idx from jsonb_array_elements(s.atividade->'questions') with ordinality as items(q,ord) where not exists(select 1 from public.respostas r where r.tentativa_id=a.id and r.questao_id=(q->>'id')::integer) order by ord limit 1;
  update public.tentativas set questao_atual=coalesce(idx,greatest(total-1,0)) where id=a.id returning * into a;
 else
  if total=0 or (select count(*) from public.respostas where tentativa_id=a.id)<>total or (select count(*) from jsonb_object_keys(s.gabarito))<>total then raise exception 'Responda a todas as questões' using errcode='22023';end if;
  update public.respostas r set correta=r.selecionada=(s.gabarito->r.questao_id::text->>'correct')::integer,
   pontos=case when r.selecionada=(s.gabarito->r.questao_id::text->>'correct')::integer then (s.gabarito->r.questao_id::text->>'points')::integer else 0 end where r.tentativa_id=a.id;
  update public.tentativas set status='completed',etapa='resultado',concluida_em=now(),acertos=(select count(*) from public.respostas where tentativa_id=a.id and correta),pontuacao=(select sum(pontos) from public.respostas where tentativa_id=a.id),percentual=(select 100.0*count(*) filter(where correta)/count(*) from public.respostas where tentativa_id=a.id) where id=a.id returning * into a;
  update public.jornadas set status=case when clube_private.jornada_completa(student) then 'concluida' else 'em_andamento' end,concluida_em=case when clube_private.jornada_completa(student) then now() else null end,texto_atual_id=null,nivel_atual=null where id=a.jornada_id;
 end if;
 return clube_private.leitura_tentativa(a);
end $$;
-- Mantém os mesmos critérios administrativos, com a quantidade histórica de perguntas.
create or replace view clube_private.admin_resultados_validos as
 select distinct on(t.aluno_id,t.jornada_id,t.texto_id) t.* from public.tentativas t
 cross join lateral(select count(*)::integer as answers,count(*) filter(where r.correta)::integer as hits,coalesce(sum(r.pontos),0) as points,
 bool_and(q.texto_id=t.texto_id and r.correta is not null and r.pontos is not null and r.pontos>=0 and (r.correta or r.pontos=0)) as corrected from public.respostas r join public.questoes q on q.id=r.questao_id where r.tentativa_id=t.id) v
 where t.status='completed' and t.concluida_em is not null and t.pontuacao>=0 and v.answers>0
 and v.answers=coalesce((select jsonb_array_length(s.atividade->'questions') from clube_private.conteudos_tentativas s where s.tentativa_id=t.id),(select count(*)::integer from public.questoes q where q.texto_id=t.texto_id and q.ativo))
 and v.corrected and t.acertos=v.hits and t.pontuacao=v.points and abs(t.percentual-(100.0*v.hits/nullif(v.answers,0)))<0.0001
 order by t.aluno_id,t.jornada_id,t.texto_id,t.concluida_em,t.id;
create or replace view clube_private.admin_alunos as
 select a.id,coalesce(a.nome_completo,p.nome) as name,a.idade as age,e.nome as school,a.escola_id as "schoolId",coalesce(a.turma,'') as "className",a.criado_em as "createdAt",a.situacao as status,coalesce(v.completed,0) as completed,coalesce(v.points,0) as points,
 a.data_nascimento as "birthDate",a.responsavel as guardian,a.ano_letivo as "schoolYear"
 from public.alunos a left join public.escolas e on e.id=a.escola_id left join public.perfis p on p.id=a.perfil_id
 left join(select aluno_id,count(*) as completed,sum(pontuacao) as points from clube_private.admin_resultados_validos group by aluno_id) v on v.aluno_id=a.id;

create function public.clube_gestao(op text,args jsonb default '{}') returns jsonb language plpgsql security definer set search_path='' as $$
declare student uuid;school uuid;profile uuid;birth date;age_years integer;year_value integer;story text;q jsonb;question_id integer;nm text;status_value text;
begin
 if not clube_private.administrador() then raise exception 'Administrador obrigatório' using errcode='42501';end if;
 if op='schools' then return coalesce((select jsonb_agg(jsonb_build_object('id',id,'name',nome) order by nome) from public.escolas),'[]');
 elsif op='school_save' then
  nm:=trim(regexp_replace(args->>'name','\s+',' ','g'));if nm is null or length(nm) not between 2 and 160 then raise exception 'Escola inválida' using errcode='22023';end if;
  insert into public.escolas(nome) values(nm) on conflict(nome_normalizado) do update set nome=public.escolas.nome returning id into school;return jsonb_build_object('id',school,'name',(select nome from public.escolas where id=school));
 elsif op='students' then
  return (with filtered as(select * from clube_private.admin_alunos a where (coalesce(args->>'search','')='' or strpos(lower(a.name),lower(args->>'search'))>0) and (coalesce(args->>'schoolId','')='' or a."schoolId"::text=args->>'schoolId') and (coalesce(args->>'className','')='' or a."className"=args->>'className') and (coalesce(args->>'status','')='' or a.status=args->>'status'))
   select jsonb_build_object('students',coalesce((select jsonb_agg(to_jsonb(p)-'position' order by p.position) from (select *,row_number() over(order by case when args->>'sort'='points_desc' then points end desc,case when args->>'sort'='points_asc' then points end asc,case when args->>'sort'='name_desc' then name end desc,name,id) as position from filtered order by case when args->>'sort'='points_desc' then points end desc,case when args->>'sort'='points_asc' then points end asc,case when args->>'sort'='name_desc' then name end desc,name,id limit least(100,greatest(1,coalesce((args->>'pageSize')::integer,20))) offset greatest(0,coalesce((args->>'page')::integer,1)-1)*least(100,greatest(1,coalesce((args->>'pageSize')::integer,20)))) p),'[]'),'total',(select count(*) from filtered),'schools',(select coalesce(jsonb_agg(jsonb_build_object('id',id,'name',nome) order by nome),'[]') from public.escolas),'classes',(select coalesce(jsonb_agg(turma order by turma),'[]') from(select distinct turma from public.alunos where turma is not null and trim(turma)<>'') c)));
 elsif op in ('student_save','student_status','credentials','credentials_save') then
  student:=nullif(args->>'id','')::uuid;
  if op='student_save' then
   nm:=trim(regexp_replace(args->>'name','\s+',' ','g'));birth:=(args->>'birthDate')::date;age_years:=extract(year from age(current_date,birth));year_value:=coalesce((args->>'schoolYear')::integer,(select ano_letivo from public.alunos where id=student),extract(year from current_date)::integer);school:=(args->>'schoolId')::uuid;
   if nm is null or length(nm) not between 3 and 120 or position(' ' in nm)=0 or birth is null or birth>current_date or age_years not between 4 and 19 or year_value not between 2000 and 2100 or length(trim(coalesce(args->>'guardian',''))) not between 3 and 160 or length(trim(coalesce(args->>'className',''))) not between 1 and 60 or not exists(select 1 from public.escolas where id=school) then raise exception 'Confira nome, nascimento (4 a 19 anos), responsável, escola e série' using errcode='22023';end if;
   if student is null then
    profile:=(args->>'profileId')::uuid;
    if not exists(select 1 from auth.users u where u.id=profile and coalesce((to_jsonb(u)->>'is_anonymous')::boolean,false)) then raise exception 'Identidade de aluno inválida' using errcode='22023';end if;
    insert into public.perfis(id,nome) values(profile,nm);
    insert into public.alunos(perfil_id,nome_completo,idade,escola_id,turma,data_nascimento,responsavel,ano_letivo) values(profile,nm,age_years,school,trim(args->>'className'),birth,trim(args->>'guardian'),year_value) returning id into student;
    insert into public.jornadas(aluno_id,ciclo) values(student,1);
    insert into clube_private.acessos(aluno_id,codigo_hash,codigo_curto_hash,credencial_cifrada) values(student,args->>'tokenHash',args->>'shortHash',args->>'encrypted');
   else
    update public.alunos set nome_completo=nm,idade=age_years,escola_id=school,turma=trim(args->>'className'),data_nascimento=birth,responsavel=trim(args->>'guardian'),ano_letivo=year_value,atualizado_em=now() where id=student returning perfil_id into profile;
    if profile is null then raise exception 'Aluno não encontrado' using errcode='P0002';end if;
    update public.perfis set nome=nm where id=profile;
   end if;
  elsif op='student_status' then
   status_value:=args->>'status';if status_value is null or status_value not in ('ativo','inativo') then raise exception 'Situação inválida' using errcode='22023';end if;
   update public.alunos set situacao=status_value,atualizado_em=now() where id=student;
   if not found then raise exception 'Aluno não encontrado' using errcode='P0002';end if;
   if status_value='inativo' then delete from clube_private.sessoes where aluno_id=student;end if;
  elsif op='credentials_save' then
   if not exists(select 1 from public.alunos where id=student) then raise exception 'Aluno não encontrado' using errcode='P0002';end if;
   insert into clube_private.acessos(aluno_id,codigo_hash,codigo_curto_hash,credencial_cifrada) values(student,args->>'tokenHash',args->>'shortHash',args->>'encrypted') on conflict(aluno_id) do update set codigo_hash=excluded.codigo_hash,codigo_curto_hash=excluded.codigo_curto_hash,credencial_cifrada=excluded.credencial_cifrada;
   delete from clube_private.sessoes where aluno_id=student;
  end if;
  return (select to_jsonb(a)||jsonb_build_object('encrypted',(select credencial_cifrada from clube_private.acessos where aluno_id=student)) from clube_private.admin_alunos a where id=student);
 elsif op='stories' then
  return coalesce((select jsonb_agg(to_jsonb(s) order by case s.level when 'facil' then 1 when 'medio' then 2 else 3 end,s.ordering,s.id) from(select t.id,t.titulo as title,t.autor as author,t.nivel as level,t.faixa_etaria as age,t.capa_url as cover,t.ativo as active,t.obrigatorio as required,t.ordem as ordering,(select count(*) from public.questoes q where q.texto_id=t.id and q.ativo) as questions from public.textos t where (coalesce(args->>'search','')='' or strpos(lower(t.titulo||' '||t.autor),lower(args->>'search'))>0) and (coalesce(args->>'level','')='' or t.nivel=args->>'level') and (coalesce(args->>'status','')='' or t.ativo=(args->>'status'='ativo'))) s),'[]');
 elsif op='story' then
  return (select jsonb_build_object('id',t.id,'title',t.titulo,'author',t.autor,'level',t.nivel,'age',t.faixa_etaria,'cover',coalesce(t.capa_url,''),'active',t.ativo,'required',t.obrigatorio,'ordering',t.ordem,'content',t.conteudo,'summary',coalesce(t.resumo,''),'minutes',t.tempo_leitura_minutos,'questions',coalesce((select jsonb_agg(jsonb_build_object('prompt',q.enunciado,'options',q.alternativas,'correct',g.correta,'value',q.valor) order by q.id) from public.questoes q left join clube_private.gabaritos g on g.questao_id=q.id where q.texto_id=t.id and q.ativo),'[]')) from public.textos t where t.id=args->>'id');
 elsif op='story_status' then
  story:=args->>'id';if (args->>'active')::boolean and not clube_private.texto_pronto(story) then raise exception 'Complete as perguntas e os gabaritos antes de ativar' using errcode='22023';end if;
  update public.textos set ativo=(args->>'active')::boolean where id=story;if not found then raise exception 'História não encontrada' using errcode='P0002';end if;return jsonb_build_object('id',story);
 elsif op='story_save' then
  story:=coalesce(nullif(args->>'id',''),gen_random_uuid()::text);
  if length(trim(coalesce(args->>'title',''))) not between 2 and 200 or length(trim(coalesce(args->>'content','')))=0 or length(coalesce(args->>'author',''))>160 or args->>'level' not in ('facil','medio','dificil') or length(trim(coalesce(args->>'age','')))=0 or (args->>'ordering')::integer<0 or jsonb_typeof(args->'questions') is distinct from 'array' then raise exception 'Dados da história inválidos' using errcode='22023';end if;
  if (args->>'active')::boolean and jsonb_array_length(args->'questions')=0 then raise exception 'Adicione perguntas antes de ativar' using errcode='22023';end if;
  for q in select value from jsonb_array_elements(args->'questions') loop
   if length(trim(coalesce(q->>'prompt','')))=0 or jsonb_typeof(q->'options') is distinct from 'array' or jsonb_array_length(q->'options')<>4 or exists(select 1 from jsonb_array_elements_text(q->'options') o where length(trim(o))=0) or (q->>'correct') is null or (q->>'correct')::integer not between 0 and 3 then raise exception 'Complete enunciado, quatro alternativas e gabarito' using errcode='22023';end if;
  end loop;
  insert into public.textos(id,titulo,conteudo,faixa_etaria,nivel,ativo,obrigatorio,ordem,resumo,capa_url,tempo_leitura_minutos,autor)
   values(story,trim(args->>'title'),args->>'content',trim(args->>'age'),args->>'level',(args->>'active')::boolean,(args->>'required')::boolean,(args->>'ordering')::integer,nullif(args->>'summary',''),nullif(args->>'cover',''),nullif(args->>'minutes','')::integer,coalesce(args->>'author',''))
   on conflict(id) do update set titulo=excluded.titulo,conteudo=excluded.conteudo,faixa_etaria=excluded.faixa_etaria,nivel=excluded.nivel,ativo=excluded.ativo,obrigatorio=excluded.obrigatorio,ordem=excluded.ordem,resumo=excluded.resumo,capa_url=excluded.capa_url,tempo_leitura_minutos=excluded.tempo_leitura_minutos,autor=excluded.autor;
  update public.questoes set ativo=false where texto_id=story;
  for q in select value from jsonb_array_elements(args->'questions') loop
   question_id:=nextval('clube_private.questoes_ids');insert into public.questoes(id,texto_id,enunciado,alternativas,valor) values(question_id,story,q->>'prompt',q->'options',nullif(q->>'value','')::integer);insert into clube_private.gabaritos values(question_id,(q->>'correct')::integer);
  end loop;return jsonb_build_object('id',story);
 end if;
 raise exception 'Operação inválida' using errcode='22023';
end $$;
revoke all on function public.clube_gestao(text,jsonb) from public,anon;
grant execute on function public.clube_gestao(text,jsonb) to authenticated;

alter function public.clube_portal(text,jsonb) set schema clube_private;
revoke all on function clube_private.clube_portal(text,jsonb) from public,anon,authenticated;
create function public.clube_portal(op text,args jsonb default '{}') returns jsonb language plpgsql security definer set search_path='' as $$
declare code text;student uuid;tries integer;
begin
 if op<>'return' then return clube_private.clube_portal(op,args);end if;
 if auth.uid() is null or not coalesce((auth.jwt()->>'is_anonymous')::boolean,false) or exists(select 1 from clube_private.sessoes where usuario_id=auth.uid()) or exists(select 1 from public.alunos where perfil_id=auth.uid()) then raise exception 'Retorno não permitido' using errcode='42501';end if;
 insert into clube_private.tentativas_acesso(usuario_id,quantidade) values(auth.uid(),1) on conflict(usuario_id) do update set
 quantidade=case when clube_private.tentativas_acesso.inicio<now()-interval '15 minutes' then 1 else clube_private.tentativas_acesso.quantidade+1 end,
 inicio=case when clube_private.tentativas_acesso.inicio<now()-interval '15 minutes' then now() else clube_private.tentativas_acesso.inicio end returning quantidade into tries;
 -- Retorna um erro de domínio em JSON para confirmar o contador mesmo nas falhas.
 if tries>12 then return jsonb_build_object('accessError','rate_limited');end if;
 code:=upper(regexp_replace(coalesce(args->>'code',''),'[\s-]','','g'));
 if code ~ '^[A-HJ-NP-Z2-9]{6}$' then
  select a.aluno_id into student from clube_private.acessos a join public.alunos s on s.id=a.aluno_id where a.codigo_curto_hash=encode(sha256(convert_to(code,'UTF8')),'hex') and s.situacao='ativo' for update of a;
 elsif code ~ '^([A-F0-9]{32}|[A-F0-9]{64})$' then
  select a.aluno_id into student from clube_private.acessos a join public.alunos s on s.id=a.aluno_id where a.codigo_hash=encode(sha256(convert_to(lower(code),'UTF8')),'hex') and s.situacao='ativo' for update of a;
 end if;
 if student is null then return jsonb_build_object('accessError','invalid');end if;
 delete from clube_private.sessoes where aluno_id=student;insert into clube_private.sessoes values(auth.uid(),student);
 return jsonb_build_object('student',clube_private.aluno_json(student));
end $$;
revoke all on function public.clube_portal(text,jsonb) from public;
grant execute on function public.clube_portal(text,jsonb) to anon,authenticated;
drop policy questoes_ativas on public.questoes;
create policy questoes_ativas on public.questoes for select to authenticated using(ativo and public.clube_texto_permitido(texto_id));
create function public.clube_admin_autorizado() returns boolean language sql stable security definer set search_path='' as $$select clube_private.administrador()$$;
revoke all on function public.clube_admin_autorizado() from public,anon;
grant execute on function public.clube_admin_autorizado() to anon,authenticated;
do $storage$ begin
 if to_regclass('storage.buckets') is not null then
  execute $sql$insert into storage.buckets(id,name,public,file_size_limit,allowed_mime_types) values('clube-capas','clube-capas',true,5242880,array['image/png','image/jpeg','image/webp']) on conflict(id) do nothing$sql$;
  execute $sql$create policy clube_capas_admin_insert on storage.objects for insert to authenticated with check(bucket_id='clube-capas' and public.clube_admin_autorizado())$sql$;
  execute $sql$create policy clube_capas_admin_select on storage.objects for select to authenticated using(bucket_id='clube-capas' and public.clube_admin_autorizado())$sql$;
  execute $sql$create policy clube_capas_admin_update on storage.objects for update to authenticated using(bucket_id='clube-capas' and public.clube_admin_autorizado()) with check(bucket_id='clube-capas' and public.clube_admin_autorizado())$sql$;
  execute $sql$create policy clube_capas_admin_delete on storage.objects for delete to authenticated using(bucket_id='clube-capas' and public.clube_admin_autorizado())$sql$;
  -- Restringe apenas este bucket, mesmo se já houver políticas permissivas globais.
  execute $sql$create policy clube_capas_guard_insert on storage.objects as restrictive for insert to anon,authenticated with check(bucket_id<>'clube-capas' or case when auth.uid() is null then false else public.clube_admin_autorizado() end)$sql$;
  execute $sql$create policy clube_capas_guard_update on storage.objects as restrictive for update to anon,authenticated using(bucket_id<>'clube-capas' or case when auth.uid() is null then false else public.clube_admin_autorizado() end) with check(bucket_id<>'clube-capas' or case when auth.uid() is null then false else public.clube_admin_autorizado() end)$sql$;
  execute $sql$create policy clube_capas_guard_delete on storage.objects as restrictive for delete to anon,authenticated using(bucket_id<>'clube-capas' or case when auth.uid() is null then false else public.clube_admin_autorizado() end)$sql$;
 end if;
end $storage$;
revoke all on function clube_private.snapshot_leitura(),clube_private.clube_leitura(text,jsonb) from public,anon,authenticated;
-- Compatibilidade do modulo legado com perguntas e resultados preservados.
create or replace function public.clube_api(op text,args jsonb default '{}') returns jsonb language plpgsql security definer set search_path='' as $$
declare student uuid; a public.tentativas; qid integer; choice integer; value integer;
begin
 if auth.uid() is null then raise exception 'Autenticação obrigatória' using errcode='42501'; end if;
 select id into student from public.alunos where perfil_id=auth.uid() and situacao='ativo';
 if student is null then raise exception 'Aluno não cadastrado pela escola' using errcode='42501'; end if;
 if op='activity' then
 return (select jsonb_build_object('id',t.id,'title',t.titulo,'author',t.autor,'cover',t.capa_url,'minutes',t.tempo_leitura_minutos,'content',t.conteudo,'age',t.faixa_etaria,'level',t.nivel,'questions',(select jsonb_agg(jsonb_build_object('id',q.id,'prompt',q.enunciado,'options',q.alternativas) order by q.id) from public.questoes q where q.texto_id=t.id and q.ativo)) from public.textos t where t.id='passarinho' and t.ativo);
 elsif op='start' then
 insert into public.tentativas(aluno_id,texto_id,nivel) select student,id,nivel from public.textos where id='passarinho' and ativo returning * into a;
 if a.id is null then raise exception 'Atividade indisponível'; end if;
 return clube_private.attempt_json(a);
 elsif op='history' then
 return coalesce((select jsonb_agg(clube_private.attempt_json(t) order by t.concluida_em desc) from public.tentativas t where t.aluno_id=student and t.status='completed'),'[]'::jsonb);
 end if;
 select * into a from public.tentativas where id=(args->>'id')::uuid and aluno_id=student for update;
 if a.id is null then raise exception 'Tentativa não encontrada' using errcode='42501'; end if;
 if op='get' then return clube_private.attempt_json(a); end if;
 if op='finish' and a.status='completed' then return clube_private.attempt_json(a); end if;
 if a.status='completed' then raise exception 'Tentativa já concluída'; end if;
 if op='answer' then
 qid:=(args->>'questionId')::integer; choice:=(args->>'selected')::integer;
 if choice is null or choice not between 0 and 3 or not exists(select 1 from clube_private.conteudos_tentativas snap cross join lateral jsonb_array_elements(snap.atividade->'questions') item where snap.tentativa_id=a.id and (item->>'id')::integer=qid) then raise exception 'Alternativa inválida'; end if;
 insert into public.respostas(tentativa_id,questao_id,selecionada) values(a.id,qid,choice) on conflict(tentativa_id,questao_id) do update set selecionada=excluded.selecionada;
 elsif op='finish' then
 if (select count(*) from public.respostas where tentativa_id=a.id)<>(select jsonb_array_length(atividade->'questions') from clube_private.conteudos_tentativas where tentativa_id=a.id) then raise exception 'Responda a todas as questões'; end if;
 select pontos into value from public.niveis where id=a.nivel;
 update public.respostas r set correta=(r.selecionada=(snap.gabarito->r.questao_id::text->>'correct')::integer),pontos=case when r.selecionada=(snap.gabarito->r.questao_id::text->>'correct')::integer then (snap.gabarito->r.questao_id::text->>'points')::integer else 0 end from clube_private.conteudos_tentativas snap where snap.tentativa_id=a.id and r.tentativa_id=a.id;
 update public.tentativas set status='completed',concluida_em=now(),acertos=(select count(*) from public.respostas where tentativa_id=a.id and correta),pontuacao=(select sum(pontos) from public.respostas where tentativa_id=a.id),percentual=(select 100.0*count(*) filter(where correta)/count(*) from public.respostas where tentativa_id=a.id) where id=a.id returning * into a;
 else raise exception 'Operação inválida'; end if;
 return clube_private.attempt_json(a);
end $$;
-- Os detalhes administrativos também usam a quantidade histórica de questões.
create or replace function public.clube_admin(op text,args jsonb default '{}') returns jsonb language plpgsql security definer set search_path='' as $$
declare search text;school_filter uuid;ordering text;page_number integer;page_size integer;student uuid;profile jsonb;
begin
 if not clube_private.administrador() then raise exception 'Administrador obrigatório' using errcode='42501';end if;
 if op='overview' then
  return jsonb_build_object('totalStudents',(select count(*) from public.alunos),
   'totalSchools',(select count(distinct e.nome_normalizado) from public.escolas e join public.alunos a on a.escola_id=e.id),
   'completed',(select count(*) from clube_private.admin_resultados_validos),
   'points',(select coalesce(sum(pontuacao),0) from clube_private.admin_resultados_validos),'updatedAt',now());
 elsif op='students' then
  search:=trim(coalesce(args->>'search',''));school_filter:=nullif(args->>'schoolId','')::uuid;
  ordering:=coalesce(args->>'sort','name_asc');page_number:=coalesce((args->>'page')::integer,1);page_size:=coalesce((args->>'pageSize')::integer,20);
  if length(search)>120 or ordering not in ('name_asc','name_desc','points_desc','points_asc') or page_number not between 1 and 1000000 or page_size not between 1 and 100 then raise exception 'Filtros inválidos' using errcode='22023';end if;
  return (
   with filtered as (select a.* from clube_private.admin_alunos a where (search='' or strpos(lower(coalesce(a.name,'')),lower(search))>0) and (school_filter is null or a."schoolId"=school_filter)),
   ordered as (select f.*,row_number() over(order by
    case when ordering='name_asc' then lower(f.name) end asc,
    case when ordering='name_desc' then lower(f.name) end desc,
    case when ordering='points_desc' then f.points end desc,
    case when ordering='points_asc' then f.points end asc,
    lower(f.name),f.id) as position from filtered f),
   paged as (select * from ordered order by position offset (page_number-1)*page_size limit page_size)
   select jsonb_build_object('students',coalesce((select jsonb_agg(to_jsonb(p)-'position' order by p.position) from paged p),'[]'),
    'total',(select count(*) from filtered),'page',page_number,'pageSize',page_size,
    'schools',coalesce((select jsonb_agg(jsonb_build_object('id',e.id,'name',e.nome) order by e.nome) from public.escolas e where exists(select 1 from public.alunos a where a.escola_id=e.id)),'[]'),'updatedAt',now())
  );
 elsif op='student' then
  student:=(args->>'id')::uuid;select to_jsonb(a) into profile from clube_private.admin_alunos a where a.id=student;
  if profile is null then raise exception 'Aluno não encontrado' using errcode='P0002';end if;
  return jsonb_build_object('student',profile,
   'journeys',coalesce((select jsonb_agg(jsonb_build_object('id',j.id,'cycle',j.ciclo,'status',j.status,'createdAt',j.criado_em,'completedAt',j.concluida_em,
     'completed',(select count(*) from clube_private.admin_resultados_validos v where v.jornada_id=j.id),
     'points',(select coalesce(sum(pontuacao),0) from clube_private.admin_resultados_validos v where v.jornada_id=j.id)) order by j.ciclo desc) from public.jornadas j where j.aluno_id=student),'[]'),
   'attempts',coalesce((select jsonb_agg(jsonb_build_object('id',t.id,'title',coalesce((select s.atividade->>'title' from clube_private.conteudos_tentativas s where s.tentativa_id=t.id),tx.titulo),'level',t.nivel,'cycle',j.ciclo,'status',t.status,
     'stage',coalesce(to_jsonb(t)->>'etapa',case when t.status='completed' then 'resultado' else 'leitura' end),
     'answered',(select count(*) from public.respostas r where r.tentativa_id=t.id),
     'totalQuestions',coalesce((select jsonb_array_length(s.atividade->'questions') from clube_private.conteudos_tentativas s where s.tentativa_id=t.id),(select count(*) from public.questoes q where q.texto_id=t.texto_id and q.ativo)),
     'includedInTotals',exists(select 1 from clube_private.admin_resultados_validos v where v.id=t.id),
     'points',(select v.pontuacao from clube_private.admin_resultados_validos v where v.id=t.id),'completedAt',t.concluida_em)
     order by t.concluida_em desc nulls first,t.id) from public.tentativas t join public.textos tx on tx.id=t.texto_id left join public.jornadas j on j.id=t.jornada_id where t.aluno_id=student),'[]'),
   'updatedAt',now());
 end if;
 raise exception 'Operação inválida' using errcode='22023';
end $$;
notify pgrst,'reload schema';

$etapa_202610190003$;
 end if;
 if not exists(select 1 from information_schema.columns where table_schema='public' and table_name='alunos' and column_name='cadastro_requisicao') then
 execute $etapa_202610190004$
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

$etapa_202610190004$;
 end if;
 if to_regprocedure('public.clube_eventos(text,jsonb)') is null then
 execute $etapa_202610200001$
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

$etapa_202610200001$;
 end if;
 if not exists(select 1 from information_schema.columns where table_schema='public' and table_name='eventos_leitura' and column_name='configuracoes') then
 execute $etapa_202610230001$
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

$etapa_202610230001$;
 end if;
 if to_regprocedure('clube_private.alternativa_valida(jsonb,integer)') is null then
 execute $etapa_202610230002$
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

$etapa_202610230002$;
 end if;
 if not exists(select 1 from information_schema.columns where table_schema='public' and table_name='alunos' and column_name='excluido_em') then
 execute $etapa_202610230003$
-- Exclusão da lista e do acesso; resultados permanecem disponíveis no histórico.
alter table public.alunos add column excluido_em timestamptz;
do $filter$
declare definition text;updated text;
begin
 definition:=pg_get_functiondef('clube_private.clube_gestao(text,jsonb)'::regprocedure);
 updated:=replace(definition,'from clube_private.admin_alunos a where (coalesce(args->>''search''',
 'from clube_private.admin_alunos a where not exists(select 1 from public.alunos deleted where deleted.id=a.id and deleted.excluido_em is not null) and (coalesce(args->>''search''');
 if updated=definition then raise exception 'Aplique primeiro a migração de gestão de alunos.';end if;
 execute updated;
end $filter$;
alter function public.clube_gestao(text,jsonb) rename to gestao_antes_exclusao;
alter function public.gestao_antes_exclusao(text,jsonb) set schema clube_private;
revoke all on function clube_private.gestao_antes_exclusao(text,jsonb) from public,anon,authenticated;
create function public.clube_gestao(op text,args jsonb default '{}') returns jsonb language plpgsql security definer set search_path='' as $$
declare student public.alunos;
begin
 if not clube_private.administrador() then raise exception 'Administrador obrigatório' using errcode='42501';end if;
 if op in ('student_delete','student_save','student_status','credentials','credentials_save') and coalesce(args->>'id','')<>'' then
  select * into student from public.alunos where id=(args->>'id')::uuid for update;
  if student.id is null then raise exception 'Aluno não encontrado' using errcode='P0002';end if;
  if op='student_delete' then
   update public.alunos set excluido_em=coalesce(excluido_em,now()),situacao='inativo',atualizado_em=now() where id=student.id;
   delete from clube_private.sessoes where aluno_id=student.id;
   return jsonb_build_object('deleted',true,'historyPreserved',true);
  end if;
  if student.excluido_em is not null then raise exception 'Aluno excluído da lista. Histórico preservado.' using errcode='22023';end if;
 end if;
 return clube_private.gestao_antes_exclusao(op,args);
end $$;
revoke all on function public.clube_gestao(text,jsonb) from public,anon;
grant execute on function public.clube_gestao(text,jsonb) to authenticated;
notify pgrst,'reload schema';

$etapa_202610230003$;
 end if;
 if not exists(select 1 from information_schema.columns where table_schema='public' and table_name='textos' and column_name='paginas_livro') then
 execute $etapa_202610230004$
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

$etapa_202610230004$;
 end if;
 if not exists(select 1 from information_schema.columns where table_schema='public' and table_name='textos' and column_name='excluido_em') then
 execute $etapa_202610230005$
-- Retira histórias do cadastro sem apagar referências, eventos e resultados.
alter table public.textos add column excluido_em timestamptz;
alter function public.clube_gestao(text,jsonb) rename to gestao_antes_exclusao_historias;
alter function public.gestao_antes_exclusao_historias(text,jsonb) set schema clube_private;
revoke all on function clube_private.gestao_antes_exclusao_historias(text,jsonb) from public,anon,authenticated;
create function public.clube_gestao(op text,args jsonb default '{}') returns jsonb language plpgsql security definer set search_path='' as $$
declare story public.textos;result jsonb;
begin
 if not clube_private.administrador() then raise exception 'Administrador obrigatório' using errcode='42501';end if;
 if op='stories' then
  result:=clube_private.gestao_antes_exclusao_historias(op,args);
  return coalesce((select jsonb_agg(x order by ord) from jsonb_array_elements(result) with ordinality as rows(x,ord)
   join public.textos t on t.id=x->>'id' where t.excluido_em is null),'[]');
 end if;
 if op in ('story_delete','story_save','story_status','story') and coalesce(args->>'id','')<>'' then
  select * into story from public.textos where id=args->>'id' for update;
  if op='story_delete' then
   if story.id is null then raise exception 'História não encontrada' using errcode='P0002';end if;
   update public.textos set ativo=false,excluido_em=coalesce(excluido_em,now()) where id=story.id;
   return jsonb_build_object('deleted',true,'historyPreserved',true);
  end if;
  if story.excluido_em is not null then
   if op='story' then return null;end if;
   raise exception 'História excluída da lista. Histórico preservado.' using errcode='22023';
  end if;
 end if;
 return clube_private.gestao_antes_exclusao_historias(op,args);
end $$;
revoke all on function public.clube_gestao(text,jsonb) from public,anon;
grant execute on function public.clube_gestao(text,jsonb) to authenticated;
notify pgrst,'reload schema';

$etapa_202610230005$;
 end if;
 if to_regprocedure('clube_private.nome_ordenacao(text)') is null then
 execute $etapa_202610230006$
create function clube_private.nome_ordenacao(nome text) returns text language sql immutable set search_path='' as $$
 select translate(lower(trim(coalesce(nome,''))),'áàâãäéèêëíìîïóòôõöúùûüçñ','aaaaaeeeeiiiiooooouuuucn')
$$;
revoke all on function clube_private.nome_ordenacao(text) from public,anon,authenticated;
-- Ordena antes de paginar, para manter A–Z entre todas as páginas e filtros.
do $alphabetical$
declare definition text;updated text;old_order text;
begin
 definition:=pg_get_functiondef('clube_private.clube_gestao(text,jsonb)'::regprocedure);
 old_order:='case when args->>''sort''=''points_desc'' then points end desc,case when args->>''sort''=''points_asc'' then points end asc,case when args->>''sort''=''name_desc'' then name end desc,name,id';
 updated:=replace(definition,old_order,'clube_private.nome_ordenacao(name) collate "C",lower(name) collate "C",id');
 if updated=definition then raise exception 'Aplique primeiro as migrações de gestão de alunos.';end if;
 execute updated;
end $alphabetical$;
notify pgrst,'reload schema';

$etapa_202610230006$;
 end if;
 if to_regprocedure('clube_private.idade_aluno(uuid)') is null then
 execute $etapa_202610230007$
-- A data civil da escola é usada também quando o servidor está em UTC.
create function clube_private.hoje_leitura() returns date language sql stable set search_path='' as $$select (now() at time zone 'America/Fortaleza')::date$$;
create function clube_private.idade_em(nascimento date,referencia date) returns integer language sql immutable set search_path='' as $$
 select case when nascimento is null or not isfinite(nascimento) or nascimento>referencia or nascimento<referencia-interval '120 years' then null else extract(year from age(referencia,nascimento))::integer end
$$;
create function clube_private.idade_aluno(student uuid) returns integer language sql stable security definer set search_path='' as $$
 select clube_private.idade_em(data_nascimento,clube_private.hoje_leitura()) from public.alunos where id=student
$$;
create function clube_private.faixa_idades(faixa text) returns integer[] language plpgsql immutable set search_path='' as $$
declare parts text[];lo integer;hi integer;
begin
 parts:=regexp_match(lower(trim(faixa)),'^(de\s+)?([0-9]{1,2})\s*(a|até|ate|[-–])\s*([0-9]{1,2})(\s*anos?)?$');
 if parts is not null then lo:=parts[2]::integer;hi:=parts[4]::integer;
 else
  parts:=regexp_match(lower(trim(faixa)),'^([0-9]{1,2})(\s*anos?)?(\s*(ou\s+mais|e\s+mais|\+))?$');
  if parts is null then return null;end if;
  lo:=parts[1]::integer;hi:=case when parts[3] is not null then 19 else lo end;
 end if;
 if lo<4 or hi>19 or hi<lo then return null;end if;
 return array[lo,hi];
end $$;
create or replace function clube_private.evento_faixa(age_text text,min_age integer,max_age integer) returns boolean language sql immutable set search_path='' as $$
 select coalesce(min_age>=bounds[1] and max_age<=bounds[2] and max_age>=min_age,false) from (select clube_private.faixa_idades(age_text) bounds) s
$$;
create function clube_private.historia_idade(student uuid,faixa text) returns boolean language sql stable security definer set search_path='' as $$
 select clube_private.evento_faixa(faixa,clube_private.idade_aluno(student),clube_private.idade_aluno(student))
$$;
-- As funções existentes passam a filtrar ANTES de contar, sortear e paginar.
do $age_functions$
declare target regprocedure;definition text;updated text;
begin
 foreach target in array array['clube_private.progresso_niveis(uuid)'::regprocedure,'clube_private.leitura_com_eventos_base(text,jsonb)'::regprocedure,'clube_private.clube_leitura_anterior(text,jsonb)'::regprocedure] loop
  definition:=pg_get_functiondef(target);
  updated:=replace(definition,'t.ativo and','t.ativo and clube_private.historia_idade(student,t.faixa_etaria) and');
  updated:=replace(updated,'and status=''started'' and clube_private.texto_autorizado(student,texto_id)','and status=''started'' and exists(select 1 from clube_private.conteudos_tentativas s where s.tentativa_id=public.tentativas.id and clube_private.historia_idade(student,s.atividade->>''age'')) and clube_private.texto_autorizado(student,texto_id)');
  if updated=definition then raise exception 'Função % incompatível com a migração de idades.',target;end if;
  execute updated;
 end loop;
 foreach target in array array['public.clube_eventos(text,jsonb)'::regprocedure,'clube_private.eventos_antes_idades(text,jsonb)'::regprocedure,'clube_private.evento_destinatarios(public.eventos_leitura,jsonb)'::regprocedure,'clube_private.evento_elegivel(public.eventos_leitura,public.alunos)'::regprocedure] loop
  definition:=pg_get_functiondef(target);
  updated:=replace(definition,'(e.inicio at time zone ''America/Fortaleza'')::date','clube_private.hoje_leitura()');
  updated:=replace(updated,'extract(year from age(clube_private.hoje_leitura(),a.data_nascimento))::integer','clube_private.idade_aluno(a.id)');
  updated:=replace(updated,'extract(year from age(clube_private.hoje_leitura(),student_row.data_nascimento))','clube_private.idade_aluno(student_row.id)');
  if updated=definition then raise exception 'Função de evento % incompatível.',target;end if;
  execute updated;
 end loop;
 definition:=pg_get_functiondef('clube_private.aluno_json(uuid)'::regprocedure);
 execute replace(definition,'''age'',a.idade','''age'',clube_private.idade_aluno(a.id)');
 definition:=pg_get_functiondef('clube_private.leitura_estado(uuid)'::regprocedure);
 execute replace(definition,'and a.status=''started''','and a.status=''started'' and exists(select 1 from clube_private.conteudos_tentativas s where s.tentativa_id=a.id and clube_private.historia_idade(student,s.atividade->>''age''))');
end $age_functions$;
create or replace function clube_private.evento_elegivel(e public.eventos_leitura,a public.alunos) returns boolean language sql stable security definer set search_path='' as $$
 select coalesce(a.situacao='ativo' and clube_private.idade_aluno(a.id) is not null and case when jsonb_array_length(e.configuracoes)=0 then
 clube_private.idade_aluno(a.id) between e.idade_min and e.idade_max and clube_private.nivel_liberado(a.id,e.nivel)
 else exists(select 1 from jsonb_array_elements(e.configuracoes) c cross join lateral jsonb_array_elements(c->'levels') l where (c->>'age')::integer=clube_private.idade_aluno(a.id) and clube_private.nivel_liberado(a.id,l->>'level')) end,false)
$$;
create or replace function clube_private.texto_autorizado(student uuid,text_id text) returns boolean language sql stable security definer set search_path='' as $$
 select exists(select 1 from public.textos t where t.id=text_id and t.ativo and t.excluido_em is null and clube_private.historia_idade(student,t.faixa_etaria) and clube_private.texto_pronto(t.id) and clube_private.nivel_liberado(student,t.nivel))
$$;
alter function clube_private.nivel_liberado(uuid,text) rename to nivel_antes_nascimento;
create function clube_private.nivel_liberado(student uuid,level_id text) returns boolean language sql stable security definer set search_path='' as $$
 select clube_private.idade_aluno(student) is not null and exists(select 1 from clube_private.progresso_niveis(student) where id=level_id and available>0) and clube_private.nivel_antes_nascimento(student,level_id)
$$;
-- Estado público: apenas blocos com conteúdo compatível; histórico de pontos permanece.
alter function clube_private.leitura_estado(uuid) rename to estado_antes_nascimento;
-- Toda resposta que inclui um snapshot passa pela mesma verificação, inclusive retomadas.
create or replace function clube_private.leitura_tentativa(a public.tentativas) returns jsonb language sql stable security definer set search_path='' as $$
 select clube_private.attempt_json(a)||jsonb_build_object('journeyId',a.jornada_id,'level',a.nivel,'stage',a.etapa,'index',a.questao_atual,'pageIndex',a.pagina_atual,
 'activity',(select case when clube_private.historia_idade(a.aluno_id,atividade->>'age') then atividade else jsonb_build_object('id',a.texto_id,'title',atividade->>'title','content','','pages','[]'::jsonb,'questions','[]'::jsonb,'level',a.nivel,'age','') end from clube_private.conteudos_tentativas where tentativa_id=a.id))
$$;
create function clube_private.leitura_estado(student uuid) returns jsonb language sql stable security definer set search_path='' as $$
 select result||jsonb_build_object('levels',coalesce((select jsonb_agg(x order by ord) from jsonb_array_elements(result->'levels') with ordinality as rows(x,ord) where (x->>'available')::integer>0),'[]'),
 'ageAccessError',case when clube_private.idade_aluno(student) is null then 'Peça à escola para corrigir sua data de nascimento no cadastro para acessar as histórias.' else null end)
 from (select clube_private.estado_antes_nascimento(student) result) s
$$;
-- Mantém período e vínculos; uma atribuição nunca é refeita em um aniversário.
create or replace function clube_private.evento_disponivel(event_id uuid,student uuid) returns boolean language sql stable security definer set search_path='' as $$
 select student is not null and clube_private.idade_aluno(student) is not null and exists(
  select 1 from public.eventos_leitura e join public.evento_alunos p on p.evento_id=e.id join public.alunos a on a.id=p.aluno_id
  where e.id=event_id and p.aluno_id=student and a.situacao='ativo' and e.ativo and not e.arquivado and now()>=e.inicio and now()<e.fim
  and clube_private.idade_aluno(student) between e.idade_min and e.idade_max
  and (jsonb_array_length(e.configuracoes)=0 or exists(select 1 from jsonb_array_elements(e.configuracoes) c where (c->>'age')::integer=clube_private.idade_aluno(student)))
  and not exists(select 1 from public.evento_leituras l join clube_private.evento_conteudos s on s.leitura_id=l.id left join public.tentativas t on t.id=l.tentativa_id
   where l.participante_id=p.id and coalesce(t.status,'started')<>'completed' and (not clube_private.historia_idade(student,s.atividade->>'age') or not clube_private.nivel_liberado(student,s.atividade->>'level'))))
$$;
alter function public.clube_leitura(text,jsonb) rename to leitura_antes_nascimento;
alter function public.leitura_antes_nascimento(text,jsonb) set schema clube_private;
create function public.clube_leitura(op text,args jsonb default '{}') returns jsonb language plpgsql security definer set search_path='' as $$
declare student uuid;a public.tentativas;result jsonb;compatible boolean;
begin
 student:=clube_private.aluno_atual();if student is null then raise exception 'Aluno não identificado' using errcode='42501';end if;
 if op='state' then return clube_private.leitura_antes_nascimento(op,args);end if;
 if op in ('get','page','stage','answer','finish') then
  select * into a from public.tentativas where id=(args->>'id')::uuid and aluno_id=student;
  if a.id is null then raise exception 'Tentativa não encontrada' using errcode='42501';end if;
  select clube_private.historia_idade(student,atividade->>'age') into compatible from clube_private.conteudos_tentativas where tentativa_id=a.id;
  if a.status='completed' and op in ('get','finish') then
   result:=clube_private.leitura_antes_nascimento(op,args);
   if not coalesce(compatible,false) then result:=jsonb_set(result,'{activity}',jsonb_build_object('id',a.texto_id,'title',result->'activity'->>'title','content','','pages','[]'::jsonb,'questions','[]'::jsonb,'level',a.nivel,'age',''));end if;
   return result;
  end if;
  if clube_private.idade_aluno(student) is null then raise exception 'Peça à escola para corrigir sua data de nascimento no cadastro para acessar as histórias.' using errcode='22023';end if;
  if not coalesce(compatible,false) then
   raise exception 'Esta história não está disponível para sua idade atual. Seu progresso está preservado.' using errcode='22023';end if;
 end if;
 if clube_private.idade_aluno(student) is null then raise exception 'Peça à escola para corrigir sua data de nascimento no cadastro para acessar as histórias.' using errcode='22023';end if;
 return clube_private.leitura_antes_nascimento(op,args);
end $$;
revoke all on function public.clube_leitura(text,jsonb) from public,anon;
grant execute on function public.clube_leitura(text,jsonb) to authenticated;
-- O módulo legado e consultas manipuladas também respeitam a data confiável.
alter function public.clube_api(text,jsonb) rename to api_antes_nascimento;
alter function public.api_antes_nascimento(text,jsonb) set schema clube_private;
create function public.clube_api(op text,args jsonb default '{}') returns jsonb language plpgsql security definer set search_path='' as $$
declare student uuid;a public.tentativas;
begin
 student:=coalesce(clube_private.aluno_atual(),(select id from public.alunos where perfil_id=auth.uid() and situacao='ativo'));
 if student is null then raise exception 'Aluno não identificado' using errcode='42501';end if;
 if op='history' then return clube_private.api_antes_nascimento(op,args);end if;
 if op in ('get','answer','finish') then
  select * into a from public.tentativas where id=(args->>'id')::uuid and aluno_id=student;
  if a.id is null then raise exception 'Tentativa não encontrada' using errcode='42501';end if;
  if not (a.status='completed' and op in ('get','finish')) and not exists(select 1 from clube_private.conteudos_tentativas s where s.tentativa_id=a.id and clube_private.historia_idade(student,s.atividade->>'age')) then raise exception 'História incompatível com sua idade atual.' using errcode='22023';end if;
 elsif not exists(select 1 from public.textos where id='passarinho' and clube_private.historia_idade(student,faixa_etaria)) then raise exception 'História incompatível com sua idade atual. Confira sua data de nascimento com a escola.' using errcode='22023';end if;
 return clube_private.api_antes_nascimento(op,args);
end $$;
revoke all on function public.clube_api(text,jsonb) from public,anon;
grant execute on function public.clube_api(text,jsonb) to authenticated;
-- Faixas inválidas não podem ser salvas ou publicadas pela administração.
alter function public.clube_gestao(text,jsonb) rename to gestao_antes_nascimento;
alter function public.gestao_antes_nascimento(text,jsonb) set schema clube_private;
create function public.clube_gestao(op text,args jsonb default '{}') returns jsonb language plpgsql security definer set search_path='' as $$
begin
 if not clube_private.administrador() then raise exception 'Administrador obrigatório' using errcode='42501';end if;
 if op='story_save' and clube_private.faixa_idades(args->>'age') is null then raise exception 'Informe uma idade de 4 a 19 anos ou faixa válida, como 5 a 7 anos.' using errcode='22023';end if;
 return clube_private.gestao_antes_nascimento(op,args);
end $$;
revoke all on function public.clube_gestao(text,jsonb) from public,anon;
grant execute on function public.clube_gestao(text,jsonb) to authenticated;
revoke all on function clube_private.hoje_leitura(),clube_private.idade_em(date,date),clube_private.idade_aluno(uuid),clube_private.faixa_idades(text),clube_private.historia_idade(uuid,text),clube_private.nivel_antes_nascimento(uuid,text),clube_private.nivel_liberado(uuid,text),clube_private.estado_antes_nascimento(uuid),clube_private.leitura_estado(uuid),clube_private.leitura_antes_nascimento(text,jsonb),clube_private.api_antes_nascimento(text,jsonb),clube_private.gestao_antes_nascimento(text,jsonb) from public,anon,authenticated;
notify pgrst,'reload schema';

$etapa_202610230007$;
 end if;
 if to_regprocedure('public.clube_escolas(text,jsonb)') is null then
 execute $etapa_202610290001$
-- Somente consultas: reutiliza escolas, alunos, credenciais e resultados existentes.
create function public.clube_escolas(op text,args jsonb default '{}') returns jsonb language plpgsql security definer set search_path='' as $$
declare school_filter text:=coalesce(args->>'schoolId','');search text:=trim(coalesce(args->>'search',''));class_filter text:=coalesce(args->>'className','');
 age_filter integer:=nullif(args->>'age','')::integer;period text:=coalesce(args->>'period','any');ordering text:=coalesce(args->>'sort','name_asc');
 page_number integer:=coalesce((args->>'page')::integer,1);page_size integer:=coalesce((args->>'pageSize')::integer,20);
 first_day date;last_day date;student uuid;result jsonb;
begin
 if not clube_private.administrador() then raise exception 'Administrador obrigatório' using errcode='42501';end if;
 if page_number not between 1 and 1000000 or page_size not between 1 and 100 then raise exception 'Paginação inválida' using errcode='22023';end if;
 if op in ('student','responses') then
  student:=(args->>'id')::uuid;
  if not exists(select 1 from public.alunos where id=student) then raise exception 'Aluno não encontrado' using errcode='P0002';end if;
  if op='student' then
   result:=public.clube_admin('student',jsonb_build_object('id',student));
   return jsonb_set(result,'{student,age}',coalesce(to_jsonb(clube_private.idade_aluno(student)),'null'::jsonb));
  end if;
  return (with answered as (
   select r.tentativa_id as "attemptId",r.questao_id as "questionId",coalesce(s.atividade->>'title',tx.titulo) as title,t.status,t.concluida_em as "completedAt",
    q->>'prompt' as prompt,q->'options' as options,r.selecionada as selected,r.correta as correct,r.pontos as points
   from public.respostas r join public.tentativas t on t.id=r.tentativa_id join public.textos tx on tx.id=t.texto_id
   join clube_private.conteudos_tentativas s on s.tentativa_id=t.id
   cross join lateral jsonb_array_elements(s.atividade->'questions') q
   where t.aluno_id=student and (q->>'id')::integer=r.questao_id),
   paged as(select * from answered order by "completedAt" desc nulls first,"attemptId","questionId" offset (page_number-1)*page_size limit page_size)
   select jsonb_build_object('responses',coalesce((select jsonb_agg(to_jsonb(p)) from paged p),'[]'),'total',(select count(*) from answered),'page',page_number,'pageSize',page_size));
 end if;
 if op<>'dashboard' then raise exception 'Operação inválida' using errcode='22023';end if;
 if length(search)>120 or length(class_filter)>60 or ordering not in ('name_asc','name_desc','created_desc','created_asc') or period not in ('any','today','7days','30days','custom')
  or (age_filter is not null and age_filter not between 0 and 120) or (school_filter<>'' and school_filter<>'none' and not exists(select 1 from public.escolas where id::text=school_filter)) then
  raise exception 'Filtros inválidos' using errcode='22023';end if;
 if period='today' then first_day:=clube_private.hoje_leitura();last_day:=first_day;
 elsif period='7days' then last_day:=clube_private.hoje_leitura();first_day:=last_day-6;
 elsif period='30days' then last_day:=clube_private.hoje_leitura();first_day:=last_day-29;
 elsif period='custom' then
  first_day:=(args->>'from')::date;last_day:=(args->>'to')::date;
  if first_day is null or last_day is null or not isfinite(first_day) or not isfinite(last_day) or last_day<first_day then raise exception 'Intervalo inválido' using errcode='22023';end if;
 end if;
 return (with base as (
  select a.*,clube_private.idade_aluno(a.id) as "currentAge",s.criado_em as registered
  from clube_private.admin_alunos a join public.alunos s on s.id=a.id where s.excluido_em is null),
 filtered as(select a.* from base a where
  (school_filter='' or (school_filter='none' and a."schoolId" is null) or a."schoolId"::text=school_filter)
  and (class_filter='' or a."className"=class_filter) and (age_filter is null or a."currentAge"=age_filter)
  and (first_day is null or (a.registered>=(first_day::timestamp at time zone 'America/Fortaleza') and a.registered<((last_day+1)::timestamp at time zone 'America/Fortaleza')))
  and (search='' or strpos(clube_private.nome_ordenacao(a.name),clube_private.nome_ordenacao(search))>0
   or exists(select 1 from clube_private.acessos access where access.aluno_id=a.id and (access.codigo_curto_hash=args->>'codeHash' or access.codigo_hash=args->>'codeHash')))),
 ordered as(select f.*,row_number() over(order by
   case when ordering='created_desc' then registered end desc,case when ordering='created_asc' then registered end asc,
   case when ordering='name_desc' then clube_private.nome_ordenacao(name) end collate "C" desc,
   clube_private.nome_ordenacao(name) collate "C",id) pos from filtered f),
 paged as(select * from ordered order by pos offset (page_number-1)*page_size limit page_size)
 select jsonb_build_object('students',coalesce((select jsonb_agg((to_jsonb(p)-'pos'-'currentAge'-'registered')||jsonb_build_object('age',p."currentAge",'encrypted',(select credencial_cifrada from clube_private.acessos where aluno_id=p.id)) order by p.pos) from paged p),'[]'),
 'total',(select count(*) from filtered),'page',page_number,'pageSize',page_size,
 'summary',jsonb_build_object('students',(select count(*) from filtered),'schools',(select count(*) from public.escolas where school_filter='' or id::text=school_filter),
  'completed',(select coalesce(sum(completed),0) from filtered),'points',(select coalesce(sum(points),0) from filtered),
  'registeredInPeriod',case when period<>'any' then (select count(*) from filtered) else null end),
 'schools',coalesce((select jsonb_agg(jsonb_build_object('id',id,'name',nome) order by nome,id) from public.escolas),'[]'),
 'classes',coalesce((select jsonb_agg(class order by class) from(select distinct "className" class from base where "className"<>'') c),'[]'),
 'updatedAt',now()));
end $$;
revoke all on function public.clube_escolas(text,jsonb) from public,anon;
grant execute on function public.clube_escolas(text,jsonb) to authenticated;
create index if not exists alunos_cadastro_escola_idx on public.alunos(escola_id,criado_em) where excluido_em is null;
notify pgrst,'reload schema';

$etapa_202610290001$;
 end if;
 if to_regclass('clube_private.conquistas_niveis') is null then
 execute $etapa_202611010001$
-- Conquistas por jornada ou seleção individual de evento. Nenhuma resposta é alterada.
create table clube_private.conquistas_niveis(
 id uuid primary key default gen_random_uuid(),aluno_id uuid not null references public.alunos(id),
 contexto_id uuid not null,evento boolean not null,nivel text not null references public.niveis(id),
 pontos bigint not null check(pontos>=0),proximo_nivel text references public.niveis(id),
 concluida_em timestamptz not null default now(),apresentada_em timestamptz,
 unique(aluno_id,contexto_id,evento,nivel));
alter table clube_private.conquistas_niveis enable row level security;
revoke all on clube_private.conquistas_niveis from public,anon,authenticated;

-- Usa a correção existente e exige uma resposta corrigida para cada pergunta do snapshot.
create function clube_private.resultado_completo(attempt_id uuid) returns boolean language sql stable security definer set search_path='' as $$
 select exists(select 1 from clube_private.admin_resultados_validos v
 join clube_private.conteudos_tentativas s on s.tentativa_id=v.id where v.id=attempt_id
 and jsonb_array_length(s.atividade->'questions')>0
 and not exists(select 1 from jsonb_array_elements(s.atividade->'questions') q where not exists(
 select 1 from public.respostas r where r.tentativa_id=v.id and r.questao_id=(q->>'id')::integer and r.correta is not null and r.pontos is not null)))
$$;

-- A sequência comum atribui as histórias obrigatórias compatíveis com o nascimento.
-- Leituras já iniciadas também impedem a conquista enquanto estiverem pendentes.
create or replace function clube_private.progresso_niveis(student uuid) returns table(id text,available bigint,completed bigint,required bigint,required_completed bigint,complete boolean) language sql stable security definer set search_path='' as $$
 with latest as(select j.id from public.jornadas j where aluno_id=student order by ciclo desc limit 1),counts as(
 select n.id,count(t.id) as available,
 count(t.id) filter(where exists(select 1 from public.tentativas a where a.aluno_id=student and a.jornada_id=(select id from latest) and a.texto_id=t.id and clube_private.resultado_completo(a.id))) as completed,
 count(t.id) filter(where t.obrigatorio) as required,
 count(t.id) filter(where t.obrigatorio and exists(select 1 from public.tentativas a where a.aluno_id=student and a.jornada_id=(select id from latest) and a.texto_id=t.id and clube_private.resultado_completo(a.id))) as required_completed
 from public.niveis n left join public.textos t on t.nivel=n.id and t.ativo and t.excluido_em is null and clube_private.historia_idade(student,t.faixa_etaria) group by n.id)
 select c.*,c.required>0 and c.required=c.required_completed and not exists(
 select 1 from public.tentativas a join clube_private.conteudos_tentativas s on s.tentativa_id=a.id
 where a.aluno_id=student and a.jornada_id=(select id from latest) and a.nivel=c.id
 and clube_private.historia_idade(student,s.atividade->>'age') and not clube_private.resultado_completo(a.id)) from counts c
$$;

-- Uma jornada pode terminar no último nível que tem atribuições para esta idade.
-- Um nível isolado após uma lacuna continua bloqueado pela regra pedagógica.
create or replace function clube_private.jornada_completa(student uuid) returns boolean language sql stable security definer set search_path='' as $$
 with p as(select * from clube_private.progresso_niveis(student))
 select coalesce((select complete from p where id='facil'),false)
 and not exists(select 1 from p where required>0 and not complete and
 (id='facil' or (id='medio' and exists(select 1 from p where id='facil' and required>0)) or
 (id='dificil' and (select count(*)=2 from p where id in('facil','medio') and required>0))))
$$;

create function clube_private.conquista_proximo(student uuid,context_id uuid,is_event boolean,level_id text) returns text language sql stable security definer set search_path='' as $$
 with candidate as(select id,ord from unnest(array['facil','medio','dificil']) with ordinality as levels(id,ord)
 where ord>array_position(array['facil','medio','dificil'],level_id))
 select c.id from candidate c where clube_private.nivel_liberado(student,c.id) and
 case when is_event then exists(select 1 from public.evento_alunos p join public.evento_leituras l on l.participante_id=p.id
 join clube_private.evento_conteudos s on s.leitura_id=l.id where p.id=context_id and p.aluno_id=student
 and clube_private.evento_disponivel(p.evento_id,student) and s.atividade->>'level'=c.id
 and clube_private.historia_idade(student,s.atividade->>'age') and not clube_private.resultado_completo(l.tentativa_id))
 else context_id=(select id from public.jornadas where aluno_id=student order by ciclo desc limit 1)
 and exists(select 1 from clube_private.progresso_niveis(student) p where p.id=c.id and p.required>0 and not p.complete) end
 order by c.ord limit 1
$$;

create function clube_private.conquista_registrar(a public.tentativas) returns uuid language plpgsql security definer set search_path='' as $$
declare context_id uuid;is_event boolean;amount bigint;done bigint;score bigint;achievement_id uuid;
begin
 if not clube_private.resultado_completo(a.id) then return null;end if;
 is_event:=a.evento_participante_id is not null;context_id:=coalesce(a.evento_participante_id,a.jornada_id);
 if context_id is null then return null;end if;
 if is_event then
  select count(*),count(*) filter(where clube_private.resultado_completo(l.tentativa_id)),coalesce(sum(v.pontuacao),0)
  into amount,done,score from public.evento_leituras l join clube_private.evento_conteudos s on s.leitura_id=l.id
  left join clube_private.admin_resultados_validos v on v.id=l.tentativa_id
  where l.participante_id=context_id and s.atividade->>'level'=a.nivel;
  if amount=0 or done<>amount then return null;end if;
 else
  if context_id is distinct from (select id from public.jornadas where aluno_id=a.aluno_id order by ciclo desc limit 1)
   or not coalesce((select complete from clube_private.progresso_niveis(a.aluno_id) where id=a.nivel),false) then return null;end if;
  select coalesce(sum(v.pontuacao),0) into score from clube_private.admin_resultados_validos v
  where v.aluno_id=a.aluno_id and v.jornada_id=context_id and v.nivel=a.nivel and clube_private.resultado_completo(v.id);
 end if;
 insert into clube_private.conquistas_niveis(aluno_id,contexto_id,evento,nivel,pontos,proximo_nivel)
 values(a.aluno_id,context_id,is_event,a.nivel,score,clube_private.conquista_proximo(a.aluno_id,context_id,is_event,a.nivel))
 on conflict(aluno_id,contexto_id,evento,nivel) do nothing;
 select id into achievement_id from clube_private.conquistas_niveis where aluno_id=a.aluno_id and contexto_id=context_id and evento=is_event and nivel=a.nivel and apresentada_em is null;
 return achievement_id;
end $$;

-- Também registra conclusões feitas pelo endpoint legado, na mesma transação.
create function clube_private.registrar_conquista_conclusao() returns trigger language plpgsql security definer set search_path='' as $$
begin
 perform clube_private.conquista_registrar(new);
 return new;
end $$;
create trigger registrar_conquista_conclusao after update of status on public.tentativas
 for each row when(new.status='completed' and old.status is distinct from new.status)
 execute function clube_private.registrar_conquista_conclusao();
revoke all on function clube_private.registrar_conquista_conclusao() from public,anon,authenticated;

create function clube_private.conquista_json(c clube_private.conquistas_niveis) returns jsonb language sql stable security definer set search_path='' as $$
 select jsonb_build_object('id',c.id,'level',c.nivel,'points',c.pontos,'percentage',100,
 'nextLevel',clube_private.conquista_proximo(c.aluno_id,c.contexto_id,c.evento,c.nivel),
 'eventId',case when c.evento then (select evento_id from public.evento_alunos where id=c.contexto_id) end)
$$;

alter function public.clube_leitura(text,jsonb) rename to leitura_antes_conquistas;
alter function public.leitura_antes_conquistas(text,jsonb) set schema clube_private;
revoke all on function clube_private.leitura_antes_conquistas(text,jsonb) from public,anon,authenticated;
create function public.clube_leitura(op text,args jsonb default '{}') returns jsonb language plpgsql security definer set search_path='' as $$
declare student uuid;result jsonb;a public.tentativas;c clube_private.conquistas_niveis;achievement_id uuid;
begin
 student:=clube_private.aluno_atual();if student is null then raise exception 'Aluno não identificado' using errcode='42501';end if;
 if op in ('achievement_claim','achievement_continue') then
  select * into c from clube_private.conquistas_niveis where id=(args->>'id')::uuid and aluno_id=student for update;
  if c.id is null then raise exception 'Conquista não encontrada' using errcode='42501';end if;
  if op='achievement_claim' then
   if c.apresentada_em is not null then return jsonb_build_object('achievement',null);end if;
   update clube_private.conquistas_niveis set apresentada_em=now() where id=c.id;
  end if;
  return jsonb_build_object('achievement',clube_private.conquista_json(c));
 end if;
 -- A autorização, correção e ordem dos locks continuam nas funções existentes.
 result:=clube_private.leitura_antes_conquistas(op,args);
 if op='finish' then
  select * into a from public.tentativas where id=(args->>'id')::uuid and aluno_id=student;
  achievement_id:=clube_private.conquista_registrar(a);
  return result||jsonb_build_object('achievementId',achievement_id);
 elsif op='state' then
  select id into achievement_id from clube_private.conquistas_niveis where aluno_id=student and apresentada_em is null
  and (evento or contexto_id=(result->'journey'->>'id')::uuid) order by concluida_em,id limit 1;
  return result||jsonb_build_object('achievementId',achievement_id);
 end if;
 return result;
end $$;
revoke all on function public.clube_leitura(text,jsonb) from public,anon;
grant execute on function public.clube_leitura(text,jsonb) to authenticated;
revoke all on function clube_private.resultado_completo(uuid),clube_private.conquista_proximo(uuid,uuid,boolean,text),clube_private.conquista_registrar(public.tentativas),clube_private.conquista_json(clube_private.conquistas_niveis) from public,anon,authenticated;
notify pgrst,'reload schema';

$etapa_202611010001$;
 end if;
 if to_regclass('clube_private.avaliacoes_niveis') is null then
 execute $etapa_202611020001$
-- Unidades racionais: cada nível vale 40/3; somar unidades antes de dividir evita 39,99 na jornada.
-- A nova avaliação complementa os snapshots e a correção existentes; não reescreve respostas.
create table clube_private.pontuacao_legada(
 aluno_id uuid not null,contexto_id uuid not null,evento boolean not null,nivel text not null,
 primary key(aluno_id,contexto_id,evento,nivel));
insert into clube_private.pontuacao_legada
 select distinct aluno_id,coalesce(evento_participante_id,jornada_id),evento_participante_id is not null,nivel
 from public.tentativas where status='completed' and coalesce(evento_participante_id,jornada_id) is not null
 union select aluno_id,contexto_id,evento,nivel from clube_private.conquistas_niveis;
alter table clube_private.conquistas_niveis alter column pontos type numeric;
create table clube_private.avaliacoes_niveis(
 conquista_id uuid primary key references clube_private.conquistas_niveis(id),
 aluno_id uuid not null references public.alunos(id),contexto_id uuid not null,evento boolean not null,
 nivel text not null references public.niveis(id),historias integer not null check(historias>0),
 questoes integer not null check(questoes>0),acertos integer not null check(acertos between 0 and questoes),
 unidades_leitura numeric not null check(unidades_leitura=20),unidades_questoes numeric not null check(unidades_questoes between 0 and 20),
 unidades numeric not null check(unidades between 0 and 40),faixa_grupo text,concluida_em timestamptz not null default now(),
 unique(aluno_id,contexto_id,evento,nivel),check(unidades=unidades_leitura+unidades_questoes));
create table clube_private.recompensas_moedas(
 conquista_id uuid primary key references clube_private.avaliacoes_niveis(conquista_id),
 aluno_id uuid not null references public.alunos(id),valor_unidades numeric not null check(valor_unidades between 0 and 40),
 criada_em timestamptz not null default now());
alter table clube_private.pontuacao_legada enable row level security;
alter table clube_private.avaliacoes_niveis enable row level security;
alter table clube_private.recompensas_moedas enable row level security;
revoke all on clube_private.pontuacao_legada,clube_private.avaliacoes_niveis,clube_private.recompensas_moedas from public,anon,authenticated;
create index avaliacoes_ranking_idx on clube_private.avaliacoes_niveis(contexto_id,faixa_grupo,nivel,unidades desc) where evento;
create index recompensas_aluno_idx on clube_private.recompensas_moedas(aluno_id);

create function clube_private.avaliacao_calcular(student uuid,context_id uuid,is_event boolean,level_id text) returns jsonb
language sql stable security definer set search_path='' as $$
 with assigned as(
  select l.texto_id,l.tentativa_id,s.atividade from public.evento_alunos p
  join public.evento_leituras l on l.participante_id=p.id join clube_private.evento_conteudos s on s.leitura_id=l.id
  where is_event and p.id=context_id and p.aluno_id=student and s.atividade->>'level'=level_id
  union all
  select t.id,saved.id,coalesce(snap.atividade,jsonb_build_object('questions',coalesce((select jsonb_agg(jsonb_build_object('id',q.id)) from public.questoes q where q.texto_id=t.id and q.ativo),'[]'::jsonb)))
  from public.textos t
  left join lateral(select a.id from public.tentativas a where a.aluno_id=student and a.jornada_id=context_id and a.texto_id=t.id order by clube_private.resultado_completo(a.id) desc,a.id limit 1) saved on true
  left join clube_private.conteudos_tentativas snap on snap.tentativa_id=saved.id
  where not is_event and exists(select 1 from public.jornadas j where j.id=context_id and j.aluno_id=student)
  and t.nivel=level_id and ((t.ativo and t.excluido_em is null and t.obrigatorio and clube_private.historia_idade(student,t.faixa_etaria))
  or (saved.id is not null and clube_private.historia_idade(student,snap.atividade->>'age')))
 ), books as(select *,clube_private.resultado_completo(tentativa_id) as done from assigned),
 questions as(select b.tentativa_id,q->>'id' as qid,b.done from books b cross join lateral jsonb_array_elements(b.atividade->'questions') q),
 totals as(select (select count(*) from books)::integer as stories,(select count(*) from books where done)::integer as completed,
 count(*)::integer as total,count(*) filter(where exists(select 1 from public.respostas r where r.tentativa_id=q.tentativa_id and r.questao_id=q.qid::integer))::integer as answered,
 count(*) filter(where q.done and exists(select 1 from public.respostas r where r.tentativa_id=q.tentativa_id and r.questao_id=q.qid::integer and r.correta))::integer as hits,
 count(*) filter(where q.done)::integer as corrected from questions q),
 score as(select *,case when stories>0 then 20::numeric*completed/stories else 0 end as reading_points,
 case when total>0 then 20::numeric*hits/total else 0 end as question_points from totals)
 select jsonb_build_object('version',2,'maxPoints',40::numeric/3,'stories',stories,'completedStories',completed,'questions',total,'answered',answered,'corrected',corrected,
 'hits',hits,'wrong',corrected-hits,'readingPoints',reading_points/3,'questionPoints',question_points/3,'points',(reading_points+question_points)/3,'pointUnits',reading_points+question_points,'pointDivisor',3,
 'lostPoints',case when total>0 then 20::numeric*(corrected-hits)/(total*3) else 0 end,
 'readingUnit',jsonb_build_object('numerator',20,'denominator',stories*3),'questionUnit',jsonb_build_object('numerator',20,'denominator',total*3),
 'questionPointValue',case when total>0 then 20::numeric/(total*3) else 0 end,
 'complete',stories>0 and completed=stories and total>0 and answered=total and corrected=total) from score
$$;

alter function clube_private.conquista_registrar(public.tentativas) rename to conquista_antes_moedas;
create function clube_private.conquista_registrar(a public.tentativas) returns uuid language plpgsql security definer set search_path='' as $$
declare achievement_id uuid;c clube_private.conquistas_niveis;stats jsonb;group_value text;
begin
 achievement_id:=clube_private.conquista_antes_moedas(a);
 select * into c from clube_private.conquistas_niveis where aluno_id=a.aluno_id and contexto_id=coalesce(a.evento_participante_id,a.jornada_id) and evento=(a.evento_participante_id is not null) and nivel=a.nivel;
 if c.id is null or exists(select 1 from clube_private.pontuacao_legada l where l.aluno_id=c.aluno_id and l.contexto_id=c.contexto_id and l.evento=c.evento and l.nivel=c.nivel) then return achievement_id;end if;
 if not exists(select 1 from clube_private.avaliacoes_niveis where conquista_id=c.id) then
  stats:=clube_private.avaliacao_calcular(c.aluno_id,c.contexto_id,c.evento,c.nivel);
  if not coalesce((stats->>'complete')::boolean,false) then raise exception 'Há leituras ou questões pendentes neste nível.' using errcode='22023';end if;
  if c.evento then select case when jsonb_array_length(configuracao)>0 then 'idade:'||idade_referencia else 'faixa:'||idade_min||':'||idade_max end into group_value from public.evento_alunos where id=c.contexto_id;end if;
  insert into clube_private.avaliacoes_niveis(conquista_id,aluno_id,contexto_id,evento,nivel,historias,questoes,acertos,unidades_leitura,unidades_questoes,unidades,faixa_grupo)
  values(c.id,c.aluno_id,c.contexto_id,c.evento,c.nivel,(stats->>'stories')::integer,(stats->>'questions')::integer,(stats->>'hits')::integer,20,(stats->>'pointUnits')::numeric-20,(stats->>'pointUnits')::numeric,group_value)
  on conflict(conquista_id) do nothing;
  update clube_private.conquistas_niveis set pontos=(select unidades/3 from clube_private.avaliacoes_niveis where conquista_id=c.id) where id=c.id;
 end if;
 insert into clube_private.recompensas_moedas(conquista_id,aluno_id,valor_unidades) select conquista_id,aluno_id,unidades from clube_private.avaliacoes_niveis where conquista_id=c.id on conflict(conquista_id) do nothing;
 return achievement_id;
end $$;

create function clube_private.saldo_moedas(student uuid) returns numeric language sql stable security definer set search_path='' as $$
 select coalesce(sum(valor_unidades),0)/3 from clube_private.recompensas_moedas where aluno_id=student
$$;
create function clube_private.ranking_conquista(achievement uuid) returns jsonb language sql stable security definer set search_path='' as $$
 with current_score as(select * from clube_private.avaliacoes_niveis where conquista_id=achievement and evento),
 ranked as(select v.unidades,v.aluno_id,v.concluida_em,
 row_number() over(order by v.unidades desc,v.concluida_em,v.aluno_id) as position
 from clube_private.avaliacoes_niveis v join public.evento_alunos p on p.id=v.contexto_id
 join current_score c on c.nivel=v.nivel and c.faixa_grupo=v.faixa_grupo
 join public.evento_alunos current_participant on current_participant.id=c.contexto_id and current_participant.evento_id=p.evento_id
 where v.evento)
 select coalesce(jsonb_agg(jsonb_build_object('position',r.position,'name',coalesce(a.nome_completo,p.nome),'school',e.nome,'points',r.unidades/3,'self',r.aluno_id=(select aluno_id from current_score)) order by r.position),'[]')
 from ranked r join public.alunos a on a.id=r.aluno_id left join public.perfis p on p.id=a.perfil_id left join public.escolas e on e.id=a.escola_id where r.position<=3
$$;

alter function clube_private.conquista_json(clube_private.conquistas_niveis) rename to conquista_json_antes_moedas;
create function clube_private.conquista_json(c clube_private.conquistas_niveis) returns jsonb language sql stable security definer set search_path='' as $$
 select clube_private.conquista_json_antes_moedas(c)||coalesce((select jsonb_build_object('scoreVersion',2,'points',v.unidades/3,'maxPoints',40::numeric/3,
 'percentage',100,'performance',v.unidades*100/40,'stories',v.historias,'completedStories',v.historias,'questions',v.questoes,'hits',v.acertos,'wrong',v.questoes-v.acertos,
 'readingPoints',v.unidades_leitura/3,'questionPoints',v.unidades_questoes/3,'lostPoints',(20-v.unidades_questoes)/3,'pointUnits',v.unidades,'pointDivisor',3,
 'questionPointValue',20::numeric/(v.questoes*3),'coins',r.valor_unidades/3,'coinBalance',clube_private.saldo_moedas(c.aluno_id),'ranking',clube_private.ranking_conquista(c.id))
 from clube_private.avaliacoes_niveis v join clube_private.recompensas_moedas r on r.conquista_id=v.conquista_id where v.conquista_id=c.id),jsonb_build_object('scoreVersion',1,'coinBalance',clube_private.saldo_moedas(c.aluno_id),'ranking','[]'::jsonb))
$$;

-- Total acadêmico: usa os novos critérios nos contextos novos e os valores antigos nos legados.
create function clube_private.total_academico(student uuid) returns numeric language sql stable security definer set search_path='' as $$
 with contexts as(select distinct coalesce(evento_participante_id,jornada_id) as context_id,evento_participante_id is not null as is_event,nivel
 from public.tentativas where aluno_id=student and coalesce(evento_participante_id,jornada_id) is not null),
 new_contexts as(select c.* from contexts c where not exists(select 1 from clube_private.pontuacao_legada l where l.aluno_id=student and l.contexto_id=c.context_id and l.evento=c.is_event and l.nivel=c.nivel)),
 units as(select coalesce(v.unidades,(clube_private.avaliacao_calcular(student,c.context_id,c.is_event,c.nivel)->>'pointUnits')::numeric) as value
 from new_contexts c left join clube_private.avaliacoes_niveis v on v.aluno_id=student and v.contexto_id=c.context_id and v.evento=c.is_event and v.nivel=c.nivel)
 select coalesce((select sum(value)/3 from units),0)+coalesce((select sum(a.pontuacao) from clube_private.admin_resultados_validos a where a.aluno_id=student and
 not exists(select 1 from new_contexts c where c.context_id=coalesce(a.evento_participante_id,a.jornada_id) and c.nivel=a.nivel and c.is_event=(a.evento_participante_id is not null))),0)
$$;

-- Consulta autenticada para retomar resultados sem repetir a animação nem o crédito.
alter function public.clube_leitura(text,jsonb) rename to leitura_antes_recompensas;
alter function public.leitura_antes_recompensas(text,jsonb) set schema clube_private;
create function public.clube_leitura(op text,args jsonb default '{}') returns jsonb language plpgsql security definer set search_path='' as $$
declare student uuid;result jsonb;a public.tentativas;c clube_private.conquistas_niveis;context_id uuid;is_event boolean;level_id text;summary jsonb;
begin
 student:=clube_private.aluno_atual();if student is null then raise exception 'Aluno não identificado' using errcode='42501';end if;
 if op='achievement_get' then
  select * into c from clube_private.conquistas_niveis where id=(args->>'id')::uuid and aluno_id=student;
  if c.id is null then raise exception 'Conquista não encontrada' using errcode='42501';end if;
  return jsonb_build_object('achievement',clube_private.conquista_json(c));
 end if;
 result:=clube_private.leitura_antes_recompensas(op,args);
 if op='state' then
  select coalesce(jsonb_agg(clube_private.conquista_json(x) order by x.concluida_em desc,x.id),'[]') into summary from clube_private.conquistas_niveis x where aluno_id=student;
  return jsonb_set(result,'{student,points}',to_jsonb(clube_private.total_academico(student)))||jsonb_build_object('coinBalance',clube_private.saldo_moedas(student),'achievements',summary);
 elsif op in ('get','finish') then
  select * into a from public.tentativas where id=(args->>'id')::uuid and aluno_id=student;
  context_id:=coalesce(a.evento_participante_id,a.jornada_id);is_event:=a.evento_participante_id is not null;level_id:=a.nivel;
  select * into c from clube_private.conquistas_niveis where aluno_id=student and contexto_id=context_id and evento=is_event and nivel=level_id;
  if c.id is not null then return result||jsonb_build_object('levelScore',clube_private.conquista_json(c));end if;
  if context_id is not null and not exists(select 1 from clube_private.pontuacao_legada l where l.aluno_id=student and l.contexto_id=context_id and l.evento=is_event and l.nivel=level_id) then
   return result||jsonb_build_object('levelScore',clube_private.avaliacao_calcular(student,context_id,is_event,level_id));
  end if;
 end if;
 return result;
end $$;
revoke all on function public.clube_leitura(text,jsonb) from public,anon;
grant execute on function public.clube_leitura(text,jsonb) to authenticated;
revoke all on function clube_private.total_academico(uuid),clube_private.avaliacao_calcular(uuid,uuid,boolean,text),clube_private.conquista_antes_moedas(public.tentativas),clube_private.conquista_registrar(public.tentativas),clube_private.saldo_moedas(uuid),clube_private.ranking_conquista(uuid),clube_private.conquista_json_antes_moedas(clube_private.conquistas_niveis),clube_private.conquista_json(clube_private.conquistas_niveis),clube_private.leitura_antes_recompensas(text,jsonb) from public,anon,authenticated;
notify pgrst,'reload schema';

$etapa_202611020001$;
 end if;
 if to_regclass('clube_private.conclusoes_jornadas') is null then
 execute $etapa_202611020002$
-- Resumo final imutável. Não altera respostas, avaliações, pontos ou moedas.
alter table clube_private.configuracao add column certificado_instituicao text not null default '' check(length(certificado_instituicao)<=160),
 add column certificado_identificacao text not null default '' check(length(certificado_identificacao)<=160);
create table clube_private.conclusoes_jornadas(
 id uuid primary key default gen_random_uuid(),aluno_id uuid not null references public.alunos(id),
 contexto_id uuid not null,evento_id uuid references public.eventos_leitura(id),evento boolean not null,
 faixa_grupo text,niveis text[] not null,resumo jsonb not null,
 concluida_em timestamptz not null,apresentada_em timestamptz,
 unique(aluno_id,contexto_id,evento));
create index conclusoes_ranking_idx on clube_private.conclusoes_jornadas(evento_id,faixa_grupo) where evento;
alter table clube_private.conclusoes_jornadas enable row level security;
revoke all on clube_private.conclusoes_jornadas from public,anon,authenticated;

create function clube_private.jornada_registrar(student uuid,context_id uuid,is_event boolean) returns uuid
language plpgsql security definer set search_path='' as $$
declare final_id uuid;level_id text;levels text[];stats jsonb;items jsonb:='[]';c clube_private.conquistas_niveis;
 v clube_private.avaliacoes_niveis;points numeric;maximum numeric;coins numeric;coin_units numeric;finished timestamptz;
 event_id uuid;group_value text;event_name text;person jsonb;issuer jsonb;legacy boolean:=false;
begin
 if context_id is null then return null;end if;
 if is_event then
  select p.evento_id,e.nome,case when jsonb_array_length(p.configuracao)>0 then 'idade:'||p.idade_referencia else 'faixa:'||p.idade_min||':'||p.idade_max end
  into event_id,event_name,group_value from public.evento_alunos p join public.eventos_leitura e on e.id=p.evento_id where p.id=context_id and p.aluno_id=student;
  if event_id is null then return null;end if;
 else
  if not exists(select 1 from public.jornadas where id=context_id and aluno_id=student) then return null;end if;
 end if;
 select id into final_id from clube_private.conclusoes_jornadas where aluno_id=student and contexto_id=context_id and evento=is_event;
 if final_id is not null then return final_id;end if;
 -- A mesma ordem de locks das operações de leitura serializa a conclusão.
 perform 1 from public.alunos where id=student for update;
 if is_event then
  if not exists(select 1 from public.evento_leituras where participante_id=context_id) or exists(
   select 1 from public.evento_leituras where participante_id=context_id and not clube_private.resultado_completo(tentativa_id)) then return null;end if;
  select array_agg(level order by array_position(array['facil','medio','dificil'],level)) into levels
  from(select distinct s.atividade->>'level' as level from public.evento_leituras l join clube_private.evento_conteudos s on s.leitura_id=l.id where l.participante_id=context_id) x;
 else
  if context_id is distinct from(select id from public.jornadas where aluno_id=student order by ciclo desc limit 1) or not clube_private.jornada_completa(student) then return null;end if;
  select array_agg(id order by array_position(array['facil','medio','dificil'],id)) into levels from clube_private.progresso_niveis(student)
  where required>0 and clube_private.nivel_liberado(student,id);
 end if;
 if coalesce(cardinality(levels),0)=0 then return null;end if;
 foreach level_id in array levels loop
  -- Conta as atribuições e todas as perguntas corrigidas, nunca somente o status visual.
  stats:=clube_private.avaliacao_calcular(student,context_id,is_event,level_id);
  if not coalesce((stats->>'complete')::boolean,false) then return null;end if;
  select * into c from clube_private.conquistas_niveis where aluno_id=student and contexto_id=context_id and evento=is_event and nivel=level_id;
  if c.id is null then return null;end if;
  select * into v from clube_private.avaliacoes_niveis where conquista_id=c.id;
  if v.conquista_id is not null then
   points:=v.unidades/3;maximum:=40::numeric/3;
   select valor_unidades into coin_units from clube_private.recompensas_moedas where conquista_id=c.id;
   coins:=coalesce(coin_units,0)/3;
   stats:=jsonb_build_object('stories',v.historias,'questions',v.questoes,'hits',v.acertos,'wrong',v.questoes-v.acertos);
  else
   legacy:=true;points:=c.pontos;coins:=0;coin_units:=0;
   -- O máximo legado é derivado do gabarito capturado, sem reavaliar as respostas.
   select coalesce(sum((answer.value->>'points')::numeric),0) into maximum
   from public.tentativas a join clube_private.conteudos_tentativas s on s.tentativa_id=a.id
   cross join lateral jsonb_each(s.gabarito) answer
   where a.aluno_id=student and coalesce(a.evento_participante_id,a.jornada_id)=context_id and a.nivel=level_id and clube_private.resultado_completo(a.id);
  end if;
  items:=items||jsonb_build_array(stats||jsonb_build_object('level',level_id,'points',points,'maxPoints',maximum,'coins',coalesce(coins,0),'legacy',v.conquista_id is null,
   'pointUnits',v.unidades,'coinUnits',coalesce(coin_units,0),
   'performance',case when maximum>0 then points*100/maximum else 0 end));
  finished:=greatest(finished,c.concluida_em);
 end loop;
 select jsonb_build_object('name',coalesce(a.nome_completo,p.nome),'school',e.nome) into person
 from public.alunos a left join public.perfis p on p.id=a.perfil_id left join public.escolas e on e.id=a.escola_id where a.id=student;
 select jsonb_build_object('institution',certificado_instituicao,'identification',certificado_identificacao) into issuer from clube_private.configuracao where id;
 insert into clube_private.conclusoes_jornadas(aluno_id,contexto_id,evento_id,evento,faixa_grupo,niveis,concluida_em,resumo)
 values(student,context_id,event_id,is_event,group_value,levels,finished,
  person||jsonb_build_object('eventName',event_name,'issuer',issuer,'levels',items,'legacy',legacy,
  'stories',(select sum((x->>'stories')::integer) from jsonb_array_elements(items) x),
  'questions',(select sum((x->>'questions')::integer) from jsonb_array_elements(items) x),
  'hits',(select sum((x->>'hits')::integer) from jsonb_array_elements(items) x),
  'wrong',(select sum((x->>'wrong')::integer) from jsonb_array_elements(items) x),
  'points',case when legacy then (select sum((x->>'points')::numeric) from jsonb_array_elements(items) x) else (select sum((x->>'pointUnits')::numeric)/3 from jsonb_array_elements(items) x) end,
  'maxPoints',case when legacy then (select sum((x->>'maxPoints')::numeric) from jsonb_array_elements(items) x) else cardinality(levels)*40::numeric/3 end,
  'coins',(select sum((x->>'coinUnits')::numeric)/3 from jsonb_array_elements(items) x)))
 on conflict(aluno_id,contexto_id,evento) do nothing;
 select id into final_id from clube_private.conclusoes_jornadas where aluno_id=student and contexto_id=context_id and evento=is_event;
 return final_id;
end $$;

create function clube_private.jornada_final_json(c clube_private.conclusoes_jornadas) returns jsonb
language sql stable security definer set search_path='' as $$
 with ranked as(select f.id,f.aluno_id,f.resumo,row_number() over(order by (f.resumo->>'points')::numeric desc,f.concluida_em,f.aluno_id) as position
 from clube_private.conclusoes_jornadas f where c.evento and f.evento_id=c.evento_id and f.faixa_grupo=c.faixa_grupo and f.niveis=c.niveis and f.resumo->>'legacy'=c.resumo->>'legacy')
 select c.resumo||jsonb_build_object('id',c.id,'eventId',c.evento_id,'completedAt',c.concluida_em,'coinBalance',clube_private.saldo_moedas(c.aluno_id),
 'performance',case when (c.resumo->>'maxPoints')::numeric>0 then (c.resumo->>'points')::numeric*100/(c.resumo->>'maxPoints')::numeric else 0 end,
 'ranking',coalesce((select jsonb_agg(jsonb_build_object('position',r.position,'name',r.resumo->>'name','school',r.resumo->>'school','points',(r.resumo->>'points')::numeric,'self',r.aluno_id=c.aluno_id) order by r.position)
 from ranked r where r.position<=3 or r.aluno_id=c.aluno_id),'[]'))
$$;

alter function public.clube_leitura(text,jsonb) rename to leitura_antes_final_jornada;
alter function public.leitura_antes_final_jornada(text,jsonb) set schema clube_private;
create function public.clube_leitura(op text,args jsonb default '{}') returns jsonb language plpgsql security definer set search_path='' as $$
declare student uuid;result jsonb;a public.tentativas;c clube_private.conclusoes_jornadas;final_id uuid;pid uuid;celebrate boolean;
begin
 student:=clube_private.aluno_atual();if student is null then raise exception 'Aluno não identificado' using errcode='42501';end if;
 if op in ('journey_get','journey_claim') then
  select * into c from clube_private.conclusoes_jornadas where id=(args->>'id')::uuid and aluno_id=student for update;
  if c.id is null then raise exception 'Conclusão não encontrada' using errcode='42501';end if;
  celebrate:=op='journey_claim' and c.apresentada_em is null;
  if celebrate then
   update clube_private.conclusoes_jornadas set apresentada_em=now() where id=c.id;
   update clube_private.conquistas_niveis set apresentada_em=coalesce(apresentada_em,now()) where aluno_id=student and contexto_id=c.contexto_id and evento=c.evento;
  end if;
  return jsonb_build_object('completion',clube_private.jornada_final_json(c),'celebrate',celebrate);
 end if;
 result:=clube_private.leitura_antes_final_jornada(op,args);
 if op='finish' then
  select * into a from public.tentativas where id=(args->>'id')::uuid and aluno_id=student;
  final_id:=clube_private.jornada_registrar(student,coalesce(a.evento_participante_id,a.jornada_id),a.evento_participante_id is not null);
  return result||jsonb_build_object('journeyCompletionId',final_id);
 elsif op='state' then
  -- Retomada de conclusões anteriores: congela os valores já existentes, sem recalcular notas.
  perform clube_private.jornada_registrar(student,(result->'journey'->>'id')::uuid,false);
  for pid in select p.id from public.evento_alunos p where p.aluno_id=student and exists(select 1 from public.evento_leituras l where l.participante_id=p.id)
   and not exists(select 1 from public.evento_leituras l where l.participante_id=p.id and not clube_private.resultado_completo(l.tentativa_id)) loop
   perform clube_private.jornada_registrar(student,pid,true);
  end loop;
  select id into final_id from clube_private.conclusoes_jornadas where aluno_id=student and apresentada_em is null order by concluida_em,id limit 1;
  return result||jsonb_build_object('journeyCompletionId',final_id,'journeyCompletions',coalesce((select jsonb_agg(jsonb_build_object('id',x.id,'eventName',x.resumo->>'eventName','completedAt',x.concluida_em,'points',x.resumo->'points') order by x.concluida_em desc,x.id) from clube_private.conclusoes_jornadas x where aluno_id=student),'[]'));
 end if;
 return result;
end $$;
revoke all on function public.clube_leitura(text,jsonb) from public,anon;
grant execute on function public.clube_leitura(text,jsonb) to authenticated;

alter function public.clube_gestao(text,jsonb) rename to gestao_antes_certificado;
alter function public.gestao_antes_certificado(text,jsonb) set schema clube_private;
create function public.clube_gestao(op text,args jsonb default '{}') returns jsonb language plpgsql security definer set search_path='' as $$
begin
 if not clube_private.administrador() then raise exception 'Administrador obrigatório' using errcode='42501';end if;
 if op='certificate_settings_save' then
  if length(coalesce(args->>'institution',''))>160 or length(coalesce(args->>'identification',''))>160 then raise exception 'Identificação institucional inválida' using errcode='22023';end if;
  update clube_private.configuracao set certificado_instituicao=trim(coalesce(args->>'institution','')),certificado_identificacao=trim(coalesce(args->>'identification','')) where id;
 end if;
 if op in ('certificate_settings','certificate_settings_save') then return(select jsonb_build_object('institution',certificado_instituicao,'identification',certificado_identificacao) from clube_private.configuracao where id);end if;
 return clube_private.gestao_antes_certificado(op,args);
end $$;
revoke all on function public.clube_gestao(text,jsonb) from public,anon;
grant execute on function public.clube_gestao(text,jsonb) to authenticated;
revoke all on function clube_private.jornada_registrar(uuid,uuid,boolean),clube_private.jornada_final_json(clube_private.conclusoes_jornadas),clube_private.leitura_antes_final_jornada(text,jsonb),clube_private.gestao_antes_certificado(text,jsonb) from public,anon,authenticated;
notify pgrst,'reload schema';

$etapa_202611020002$;
 end if;
 if to_regprocedure('clube_private.regra_contexto(uuid,uuid,boolean)') is null then
 execute $etapa_202611020003$
-- Contextos existentes continuam nas regras antigas; somente contextos novos usam 20 por história.
alter table public.jornadas add column regra_pontos smallint not null default 2 check(regra_pontos in(2,3));
alter table public.jornadas alter column regra_pontos set default 3;
alter table public.evento_alunos add column regra_pontos smallint not null default 2 check(regra_pontos in(2,3));
alter table public.evento_alunos alter column regra_pontos set default 3;
alter table public.tentativas add column leitura_concluida_em timestamptz,add column avaliacao_historia jsonb;
alter table public.tentativas add constraint avaliacao_historia_consistente check(avaliacao_historia is null or coalesce(jsonb_typeof(avaliacao_historia)='object' and avaliacao_historia->>'version'='3' and (avaliacao_historia->>'maxPoints')::numeric=20 and (avaliacao_historia->>'points')::numeric between 0 and 20 and (avaliacao_historia->>'points')::numeric=(avaliacao_historia->>'readingPoints')::numeric+(avaliacao_historia->>'questionPoints')::numeric,false));
-- Somente contextos sem tentativas, conquistas ou certificados podem adotar a regra nova.
update public.jornadas j set regra_pontos=3 where not exists(select 1 from public.tentativas a where a.jornada_id=j.id) and not exists(select 1 from clube_private.conquistas_niveis c where c.contexto_id=j.id and not c.evento) and not exists(select 1 from clube_private.conclusoes_jornadas f where f.contexto_id=j.id and not f.evento);
update public.evento_alunos p set regra_pontos=3 where not exists(select 1 from public.tentativas a where a.evento_participante_id=p.id) and not exists(select 1 from clube_private.conquistas_niveis c where c.contexto_id=p.id and c.evento) and not exists(select 1 from clube_private.conclusoes_jornadas f where f.contexto_id=p.id and f.evento);
alter table clube_private.avaliacoes_niveis add column regra_pontos smallint not null default 2 check(regra_pontos in(2,3));
alter table clube_private.avaliacoes_niveis drop constraint avaliacoes_niveis_unidades_leitura_check,
 drop constraint avaliacoes_niveis_unidades_questoes_check,drop constraint avaliacoes_niveis_unidades_check;
alter table clube_private.avaliacoes_niveis add constraint avaliacao_regra_valores check(
 (regra_pontos=2 and unidades_leitura=20 and unidades_questoes between 0 and 20 and unidades between 0 and 40) or
 (regra_pontos=3 and unidades_leitura=10*historias and unidades_questoes between 0 and 10*historias and unidades between 0 and 20*historias));
alter table clube_private.recompensas_moedas drop constraint recompensas_moedas_valor_unidades_check,
 add constraint recompensa_nao_negativa check(valor_unidades>=0);
create table clube_private.atribuicoes_jornada(
 jornada_id uuid not null references public.jornadas(id),aluno_id uuid not null references public.alunos(id),
 texto_id text not null references public.textos(id),nivel text not null references public.niveis(id),ordem integer not null,
 atividade jsonb not null,gabarito jsonb not null,primary key(jornada_id,texto_id),unique(jornada_id,nivel,ordem));
create index atribuicoes_jornada_aluno_idx on clube_private.atribuicoes_jornada(aluno_id,jornada_id,nivel);
alter table clube_private.atribuicoes_jornada enable row level security;
revoke all on clube_private.atribuicoes_jornada from public,anon,authenticated;

create function clube_private.regra_contexto(student uuid,context_id uuid,is_event boolean) returns integer language sql stable security definer set search_path='' as $$
 select coalesce(case when is_event then(select regra_pontos from public.evento_alunos where id=context_id and aluno_id=student)
 else(select regra_pontos from public.jornadas where id=context_id and aluno_id=student) end,2)
$$;
-- Os pesos antigos n?o controlam a nota nova nem podem causar overflow da corre??o legada.
create function clube_private.gabarito_historia_v3() returns trigger language plpgsql security definer set search_path='' as $$
declare a public.tentativas;
begin
 select * into a from public.tentativas where id=new.tentativa_id;
 if clube_private.regra_contexto(a.aluno_id,coalesce(a.evento_participante_id,a.jornada_id),a.evento_participante_id is not null)=3 then
  select coalesce(jsonb_object_agg(key,value||jsonb_build_object('originalPoints',coalesce(value->'originalPoints',value->'points'),'points',1)),'{}') into new.gabarito from jsonb_each(new.gabarito);
 end if;return new;
end $$;
create trigger gabarito_historia_v3 before insert or update on clube_private.conteudos_tentativas for each row execute function clube_private.gabarito_historia_v3();
revoke all on function clube_private.gabarito_historia_v3() from public,anon,authenticated;
create function clube_private.atribuir_jornada(student uuid,context_id uuid) returns void language plpgsql security definer set search_path='' as $$
begin
 if clube_private.regra_contexto(student,context_id,false)<>3 then return;end if;
 perform 1 from public.alunos where id=student for update;
 if exists(select 1 from clube_private.atribuicoes_jornada where jornada_id=context_id) then return;end if;
 perform 1 from public.textos t where t.ativo and t.obrigatorio and t.excluido_em is null order by t.id for share;
 insert into clube_private.atribuicoes_jornada(jornada_id,aluno_id,texto_id,nivel,ordem,atividade,gabarito)
 select context_id,student,t.id,t.nivel,row_number() over(partition by t.nivel order by t.ordem,t.id)::integer-1,
 jsonb_build_object('id',t.id,'title',t.titulo,'author',t.autor,'cover',t.capa_url,'minutes',t.tempo_leitura_minutos,'content',t.conteudo,'pages',t.paginas_livro,'age',t.faixa_etaria,'level',t.nivel,'questions',
 (select jsonb_agg(jsonb_build_object('id',q.id,'prompt',q.enunciado,'options',q.alternativas) order by q.id) from public.questoes q where q.texto_id=t.id and q.ativo)),
 (select jsonb_object_agg(q.id,jsonb_build_object('correct',g.correta,'points',coalesce(q.valor,n.pontos))) from public.questoes q join clube_private.gabaritos g on g.questao_id=q.id where q.texto_id=t.id and q.ativo)
 from public.textos t join public.niveis n on n.id=t.nivel
 where t.ativo and t.obrigatorio and t.excluido_em is null and clube_private.historia_idade(student,t.faixa_etaria) and clube_private.texto_pronto(t.id)
 and (t.nivel='facil' or(t.nivel='medio' and exists(select 1 from public.textos e where e.nivel='facil' and e.ativo and e.obrigatorio and e.excluido_em is null and clube_private.historia_idade(student,e.faixa_etaria) and clube_private.texto_pronto(e.id)))
 or(t.nivel='dificil' and(select count(distinct e.nivel)=2 from public.textos e where e.nivel in('facil','medio') and e.ativo and e.obrigatorio and e.excluido_em is null and clube_private.historia_idade(student,e.faixa_etaria) and clube_private.texto_pronto(e.id))));
end $$;

create function clube_private.historia_avaliar(attempt_id uuid) returns jsonb language sql stable security definer set search_path='' as $$
 with a as(select t.*,s.atividade from public.tentativas t join clube_private.conteudos_tentativas s on s.tentativa_id=t.id where t.id=attempt_id),
 counts as(select a.id,a.status,a.leitura_concluida_em,count(q)::integer total,
 count(r.questao_id)::integer answered,count(r.questao_id) filter(where r.correta is not null and r.pontos is not null)::integer corrected,
 count(r.questao_id) filter(where r.correta)::integer hits
 from a cross join lateral jsonb_array_elements(a.atividade->'questions') q
 left join public.respostas r on r.tentativa_id=a.id and r.questao_id=(q->>'id')::integer group by a.id,a.status,a.leitura_concluida_em),
 calculated as(select *,case when leitura_concluida_em is not null then 10 else 0 end reading,
 case when total>0 then 10::numeric*hits/total else 0 end questions from counts)
 select jsonb_build_object('version',3,'scoreVersion',3,'maxPoints',20,'readingComplete',leitura_concluida_em is not null,
 'stories',1,'completedStories',case when status='completed' and leitura_concluida_em is not null then 1 else 0 end,
 'questions',total,'answered',answered,'corrected',corrected,'hits',hits,'wrong',corrected-hits,'readingPoints',reading,'questionPoints',questions,
 'points',reading+questions,'questionPointValue',case when total>0 then 10::numeric/total else 0 end,
 'questionUnit',jsonb_build_object('numerator',10,'denominator',total),
 'lostPoints',case when total>0 then 10::numeric*(corrected-hits)/total else 0 end,
 'complete',status='completed' and leitura_concluida_em is not null and total>0 and answered=total and corrected=total and clube_private.resultado_completo(id)) from calculated
$$;

alter function clube_private.avaliacao_calcular(uuid,uuid,boolean,text) rename to avaliacao_calcular_v2;
create function clube_private.avaliacao_calcular(student uuid,context_id uuid,is_event boolean,level_id text) returns jsonb language plpgsql stable security definer set search_path='' as $$
declare result jsonb;
begin
 if clube_private.regra_contexto(student,context_id,is_event)<>3 then return clube_private.avaliacao_calcular_v2(student,context_id,is_event,level_id);end if;
 with assigned as(
 select l.tentativa_id,s.atividade from public.evento_leituras l join public.evento_alunos p on p.id=l.participante_id join clube_private.evento_conteudos s on s.leitura_id=l.id
 where is_event and p.aluno_id=student and p.id=context_id and s.atividade->>'level'=level_id
 union all
 select t.id,x.atividade from clube_private.atribuicoes_jornada x left join public.tentativas t on t.jornada_id=x.jornada_id and t.texto_id=x.texto_id and t.aluno_id=student
 where not is_event and x.jornada_id=context_id and x.aluno_id=student and x.nivel=level_id),
 scores as(select coalesce(t.avaliacao_historia,clube_private.historia_avaliar(t.id),jsonb_build_object('complete',false,'readingComplete',false,'questions',jsonb_array_length(a.atividade->'questions'),'answered',0,'corrected',0,'hits',0,'wrong',0,'readingPoints',0,'questionPoints',0,'points',0,'lostPoints',0)) s
 from assigned a left join public.tentativas t on t.id=a.tentativa_id),
 totals as(select count(*)::integer stories,count(*) filter(where(s->>'readingComplete')::boolean)::integer read,
 count(*) filter(where(s->>'complete')::boolean)::integer completed,coalesce(sum((s->>'questions')::integer),0) questions,
 coalesce(sum((s->>'answered')::integer),0) answered,coalesce(sum((s->>'corrected')::integer),0) corrected,
 coalesce(sum((s->>'hits')::integer),0) hits,coalesce(sum((s->>'wrong')::integer),0) wrong,
 coalesce(sum((s->>'readingPoints')::numeric),0) reading,coalesce(sum((s->>'questionPoints')::numeric),0) points,coalesce(sum((s->>'lostPoints')::numeric),0) lost from scores)
 select jsonb_build_object('version',3,'scoreVersion',3,'maxPoints',20*stories,'stories',stories,'completedStories',completed,'readStories',read,
 'questions',questions,'answered',answered,'corrected',corrected,'hits',hits,'wrong',wrong,'readingPoints',reading,'questionPoints',points,'points',reading+points,
 'pointUnits',reading+points,'pointDivisor',1,'lostPoints',lost,'complete',stories>0 and completed=stories and questions>0 and answered=questions and corrected=questions) into result from totals;
 return result;
end $$;

alter function clube_private.progresso_niveis(uuid) rename to progresso_niveis_v2;
create function clube_private.progresso_niveis(student uuid) returns table(id text,available bigint,completed bigint,required bigint,required_completed bigint,complete boolean)
language plpgsql stable security definer set search_path='' as $$
declare context_id uuid;
begin
 select j.id into context_id from public.jornadas j where j.aluno_id=student order by j.ciclo desc limit 1;
 if clube_private.regra_contexto(student,context_id,false)<>3 or not exists(select 1 from clube_private.atribuicoes_jornada x where x.jornada_id=context_id) then
 return query select * from clube_private.progresso_niveis_v2(student);return;end if;
 return query with counts as(select n.id level_id,count(x.texto_id) amount,count(x.texto_id) filter(where coalesce((t.avaliacao_historia->>'complete')::boolean,false)) done
 from public.niveis n left join clube_private.atribuicoes_jornada x on x.nivel=n.id and x.jornada_id=context_id and clube_private.historia_idade(student,x.atividade->>'age')
 left join public.tentativas t on t.jornada_id=x.jornada_id and t.texto_id=x.texto_id and t.aluno_id=student group by n.id)
 select level_id,amount,done,amount,done,amount>0 and amount=done from counts;
end $$;
alter function clube_private.texto_autorizado(uuid,text) rename to texto_autorizado_v2;
create function clube_private.texto_autorizado(student uuid,text_id text) returns boolean language sql stable security definer set search_path='' as $$
 select case when exists(select 1 from public.jornadas j where j.aluno_id=student and j.regra_pontos=3 and j.id=(select id from public.jornadas where aluno_id=student order by ciclo desc limit 1)) and exists(select 1 from clube_private.atribuicoes_jornada x where x.aluno_id=student and x.jornada_id=(select id from public.jornadas where aluno_id=student order by ciclo desc limit 1))
 then exists(select 1 from clube_private.atribuicoes_jornada x where x.aluno_id=student and x.texto_id=text_id and x.jornada_id=(select id from public.jornadas where aluno_id=student order by ciclo desc limit 1)
 and clube_private.historia_idade(student,x.atividade->>'age') and clube_private.nivel_liberado(student,x.nivel))
 else clube_private.texto_autorizado_v2(student,text_id) end
$$;

alter function clube_private.conquista_registrar(public.tentativas) rename to conquista_registrar_v2;
create function clube_private.conquista_registrar(a public.tentativas) returns uuid language plpgsql security definer set search_path='' as $$
declare stats jsonb;context_id uuid;is_event boolean;c clube_private.conquistas_niveis;group_value text;
begin
 context_id:=coalesce(a.evento_participante_id,a.jornada_id);is_event:=a.evento_participante_id is not null;
 if clube_private.regra_contexto(a.aluno_id,context_id,is_event)<>3 then return clube_private.conquista_registrar_v2(a);end if;
 if not clube_private.resultado_completo(a.id) then return null;end if;
 if a.leitura_concluida_em is null then raise exception 'Conclua a leitura antes de finalizar.' using errcode='22023';end if;
 update public.tentativas set avaliacao_historia=clube_private.historia_avaliar(a.id) where id=a.id and avaliacao_historia is null;
 stats:=clube_private.avaliacao_calcular(a.aluno_id,context_id,is_event,a.nivel);
 if not coalesce((stats->>'complete')::boolean,false) then return null;end if;
 insert into clube_private.conquistas_niveis(aluno_id,contexto_id,evento,nivel,pontos,proximo_nivel)
 values(a.aluno_id,context_id,is_event,a.nivel,(stats->>'points')::numeric,clube_private.conquista_proximo(a.aluno_id,context_id,is_event,a.nivel)) on conflict(aluno_id,contexto_id,evento,nivel) do nothing;
 select * into c from clube_private.conquistas_niveis where aluno_id=a.aluno_id and contexto_id=context_id and evento=is_event and nivel=a.nivel;
 if is_event then select case when jsonb_array_length(configuracao)>0 then 'idade:'||idade_referencia else 'faixa:'||idade_min||':'||idade_max end into group_value from public.evento_alunos where id=context_id;end if;
 insert into clube_private.avaliacoes_niveis(conquista_id,aluno_id,contexto_id,evento,nivel,historias,questoes,acertos,unidades_leitura,unidades_questoes,unidades,faixa_grupo,regra_pontos)
 values(c.id,a.aluno_id,context_id,is_event,a.nivel,(stats->>'stories')::integer,(stats->>'questions')::integer,(stats->>'hits')::integer,(stats->>'readingPoints')::numeric,(stats->>'questionPoints')::numeric,(stats->>'points')::numeric,group_value,3) on conflict(conquista_id) do nothing;
 insert into clube_private.recompensas_moedas(conquista_id,aluno_id,valor_unidades) select conquista_id,aluno_id,unidades from clube_private.avaliacoes_niveis where conquista_id=c.id on conflict(conquista_id) do nothing;
 return case when c.apresentada_em is null then c.id else null end;
end $$;

create function clube_private.validar_recompensa() returns trigger language plpgsql security definer set search_path='' as $$
begin
 if not exists(select 1 from clube_private.avaliacoes_niveis v where v.conquista_id=new.conquista_id and v.aluno_id=new.aluno_id and v.unidades=new.valor_unidades) then raise exception 'Recompensa divergente da avaliação oficial.' using errcode='22023';end if;return new;
end $$;
create trigger validar_recompensa before insert or update on clube_private.recompensas_moedas for each row execute function clube_private.validar_recompensa();
create or replace function clube_private.saldo_moedas(student uuid) returns numeric language sql stable security definer set search_path='' as $$
 select coalesce(sum(amount/divisor),0) from(select sum(r.valor_unidades) amount,case when v.regra_pontos=3 then 1 else 3 end divisor
 from clube_private.recompensas_moedas r join clube_private.avaliacoes_niveis v on v.conquista_id=r.conquista_id where r.aluno_id=student group by v.regra_pontos) x
$$;

create or replace function clube_private.ranking_conquista(achievement uuid) returns jsonb language sql stable security definer set search_path='' as $$
 with current_score as(select * from clube_private.avaliacoes_niveis where conquista_id=achievement and evento),
 ranked as(select v.aluno_id,v.unidades/case when v.regra_pontos=3 then 1 else 3 end points,
 row_number() over(order by v.unidades desc,v.concluida_em,v.aluno_id) position
 from clube_private.avaliacoes_niveis v join public.evento_alunos p on p.id=v.contexto_id
 join current_score c on c.nivel=v.nivel and c.faixa_grupo=v.faixa_grupo and c.regra_pontos=v.regra_pontos
 join public.evento_alunos cp on cp.id=c.contexto_id and cp.evento_id=p.evento_id where v.evento)
 select coalesce(jsonb_agg(jsonb_build_object('position',r.position,'name',coalesce(a.nome_completo,p.nome),'school',e.nome,'points',r.points,'self',r.aluno_id=(select aluno_id from current_score)) order by r.position),'[]')
 from ranked r join public.alunos a on a.id=r.aluno_id left join public.perfis p on p.id=a.perfil_id left join public.escolas e on e.id=a.escola_id where r.position<=3 or r.aluno_id=(select aluno_id from current_score)
$$;
alter function clube_private.conquista_json(clube_private.conquistas_niveis) rename to conquista_json_v2;
create function clube_private.conquista_json(c clube_private.conquistas_niveis) returns jsonb language plpgsql stable security definer set search_path='' as $$
declare v clube_private.avaliacoes_niveis;
begin
 select * into v from clube_private.avaliacoes_niveis where conquista_id=c.id;
 if v.regra_pontos is distinct from 3 then return clube_private.conquista_json_v2(c);end if;
 return clube_private.conquista_json_antes_moedas(c)||jsonb_build_object('scoreVersion',3,'points',v.unidades,'maxPoints',20*v.historias,'performance',v.unidades*100/(20*v.historias),
 'stories',v.historias,'completedStories',v.historias,'questions',v.questoes,'hits',v.acertos,'wrong',v.questoes-v.acertos,'readingPoints',v.unidades_leitura,'questionPoints',v.unidades_questoes,
 'lostPoints',10*v.historias-v.unidades_questoes,'pointUnits',v.unidades,'pointDivisor',1,'coins',(select valor_unidades from clube_private.recompensas_moedas where conquista_id=c.id),
 'coinBalance',clube_private.saldo_moedas(c.aluno_id),'ranking',clube_private.ranking_conquista(c.id));
end $$;

create or replace function clube_private.total_academico(student uuid) returns numeric language sql stable security definer set search_path='' as $$
 with contexts as(select distinct coalesce(evento_participante_id,jornada_id) context_id,evento_participante_id is not null is_event,nivel from public.tentativas where aluno_id=student and coalesce(evento_participante_id,jornada_id) is not null),
 normalized as(select c.*,case when clube_private.regra_contexto(student,c.context_id,c.is_event)=3 then 1 else 3 end divisor,
 case when clube_private.regra_contexto(student,c.context_id,c.is_event)=3 then coalesce(v.unidades,0) else coalesce(v.unidades,(clube_private.avaliacao_calcular(student,c.context_id,c.is_event,c.nivel)->>'pointUnits')::numeric) end amount
 from contexts c left join clube_private.avaliacoes_niveis v on v.aluno_id=student and v.contexto_id=c.context_id and v.evento=c.is_event and v.nivel=c.nivel
 where not exists(select 1 from clube_private.pontuacao_legada l where l.aluno_id=student and l.contexto_id=c.context_id and l.evento=c.is_event and l.nivel=c.nivel))
 select coalesce((select sum(amount/divisor) from(select sum(amount) amount,divisor from normalized group by divisor) g),0)+coalesce((select sum(a.pontuacao) from clube_private.admin_resultados_validos a where a.aluno_id=student and not exists(select 1 from normalized c where c.context_id=coalesce(a.evento_participante_id,a.jornada_id) and c.nivel=a.nivel and c.is_event=(a.evento_participante_id is not null))),0)
$$;

alter function clube_private.attempt_json(public.tentativas) rename to attempt_json_v2;
create function clube_private.attempt_json(a public.tentativas) returns jsonb language plpgsql stable security definer set search_path='' as $$
declare result jsonb;grade jsonb;total integer;
begin
 result:=clube_private.attempt_json_v2(a);
 if clube_private.regra_contexto(a.aluno_id,coalesce(a.evento_participante_id,a.jornada_id),a.evento_participante_id is not null)<>3 then return result;end if;
 grade:=coalesce(a.avaliacao_historia,clube_private.historia_avaliar(a.id));result:=result||jsonb_build_object('storyScore',grade);
 if a.status='completed' then
  total:=(grade->>'questions')::integer;
  result:=jsonb_set(result,'{result,points}',grade->'points');
  result:=jsonb_set(result,'{result,details}',coalesce((select jsonb_agg(q||jsonb_build_object('points',case when q->>'selected'=q->>'correct' then 10::numeric/nullif(total,0) else 0 end) order by ord)
  from jsonb_array_elements(result->'result'->'details') with ordinality as items(q,ord)),'[]'));
 end if;return result;
end $$;

-- O resumo final permanece imutável. Somente novos resumos recebem o divisor correto por regra.
do $final$ declare definition text;begin
 definition:=pg_get_functiondef('clube_private.jornada_registrar(uuid,uuid,boolean)'::regprocedure);
 definition:=replace(definition,'points:=v.unidades/3;maximum:=40::numeric/3;','points:=v.unidades/case when v.regra_pontos=3 then 1 else 3 end;maximum:=case when v.regra_pontos=3 then 20*v.historias else 40::numeric/3 end;');
 definition:=replace(definition,'coins:=coalesce(coin_units,0)/3;','coins:=coalesce(coin_units,0)/case when v.regra_pontos=3 then 1 else 3 end;');
 definition:=replace(definition,'''pointUnits'',v.unidades,','''scoreVersion'',coalesce(v.regra_pontos,1),''pointDivisor'',case when v.regra_pontos=3 then 1 else 3 end,''pointUnits'',v.unidades,');
 definition:=replace(definition,'sum((x->>''pointUnits'')::numeric)/3','sum((x->>''pointUnits'')::numeric)/min((x->>''pointDivisor'')::numeric)');
 definition:=replace(definition,'cardinality(levels)*40::numeric/3','(select sum((x->>''maxPoints'')::numeric) from jsonb_array_elements(items) x)');
 definition:=replace(definition,'sum((x->>''coinUnits'')::numeric)/3','sum((x->>''coinUnits'')::numeric/case when x->>''scoreVersion''=''3'' then 1 else 3 end)');execute definition;
 definition:=pg_get_functiondef('clube_private.jornada_final_json(clube_private.conclusoes_jornadas)'::regprocedure);
 definition:=replace(definition,'f.resumo->>''legacy''=c.resumo->>''legacy''','f.resumo->>''legacy''=c.resumo->>''legacy'' and coalesce(f.resumo->''levels''->0->>''scoreVersion'',''2'')=coalesce(c.resumo->''levels''->0->>''scoreVersion'',''2'')');execute definition;
end $final$;

alter function public.clube_leitura(text,jsonb) rename to leitura_antes_pontos_historia;
alter function public.leitura_antes_pontos_historia(text,jsonb) set schema clube_private;
create function public.clube_leitura(op text,args jsonb default '{}') returns jsonb language plpgsql security definer set search_path='' as $$
declare student uuid;context_id uuid;result jsonb;a public.tentativas;chosen clube_private.atribuicoes_jornada;level_id text;modern boolean;
begin
 student:=clube_private.aluno_atual();if student is null then raise exception 'Aluno não identificado' using errcode='42501';end if;
 if op in('enter','start') then
  select id into context_id from public.jornadas where aluno_id=student order by ciclo desc limit 1;
  if clube_private.regra_contexto(student,context_id,false)=3 then
   if clube_private.idade_aluno(student) is null then raise exception 'Confira a data de nascimento com a escola.' using errcode='22023';end if;
   level_id:=args->>'level';if level_id is null or level_id not in('facil','medio','dificil') then raise exception 'Nível inválido' using errcode='22023';end if;
   perform clube_private.atribuir_jornada(student,context_id);
   if not clube_private.nivel_liberado(student,level_id) then raise exception 'Conclua o nível anterior.' using errcode='42501';end if;
   select * into a from public.tentativas where aluno_id=student and jornada_id=context_id and status='started' and clube_private.texto_autorizado(student,texto_id) order by(nivel=level_id) desc,id limit 1 for update;
   if a.id is null then
    select x.* into chosen from clube_private.atribuicoes_jornada x where x.jornada_id=context_id and x.nivel=level_id and clube_private.historia_idade(student,x.atividade->>'age')
    and not exists(select 1 from public.tentativas t where t.jornada_id=context_id and t.texto_id=x.texto_id and(t.avaliacao_historia->>'complete')::boolean) order by x.ordem limit 1;
    if chosen.texto_id is not null then
     if args?'storyId' and args->>'storyId' is distinct from chosen.texto_id then raise exception 'Siga a sequência atribuída.' using errcode='42501';end if;
     insert into public.tentativas(aluno_id,jornada_id,texto_id,nivel) values(student,context_id,chosen.texto_id,chosen.nivel) returning * into a;
     update clube_private.conteudos_tentativas set atividade=chosen.atividade,gabarito=chosen.gabarito where tentativa_id=a.id;
     update public.jornadas set status='em_andamento',texto_atual_id=a.texto_id,nivel_atual=a.nivel where id=context_id;
    end if;
   elsif args?'storyId' and args->>'storyId' is distinct from a.texto_id then raise exception 'Siga a sequência atribuída.' using errcode='42501';end if;
   if op='start' then if a.id is null then raise exception 'Nenhuma história atribuída pendente.' using errcode='22023';end if;return clube_private.leitura_tentativa(a);end if;
   return jsonb_build_object('attempt',case when a.id is not null then clube_private.leitura_tentativa(a) else null end,'empty',a.id is null,'levelComplete',coalesce((select complete from clube_private.progresso_niveis(student) where id=level_id),false),'journeyComplete',clube_private.jornada_completa(student));
  end if;
 end if;
 if op in('get','page','stage','answer','finish') then
  select * into a from public.tentativas where id=(args->>'id')::uuid and aluno_id=student;
  if a.id is null then raise exception 'Tentativa não encontrada' using errcode='42501';end if;
  modern:=clube_private.regra_contexto(student,coalesce(a.evento_participante_id,a.jornada_id),a.evento_participante_id is not null)=3;
  if modern and op='finish' and a.leitura_concluida_em is null then raise exception 'Conclua a leitura antes de finalizar.' using errcode='22023';end if;
 end if;
 result:=clube_private.leitura_antes_pontos_historia(op,args);
 if modern and op='stage' and args->>'stage'='questoes' then
  update public.tentativas set leitura_concluida_em=coalesce(leitura_concluida_em,now()) where id=a.id;
  return result||jsonb_build_object('storyScore',clube_private.historia_avaliar(a.id));
 end if;
 if op='state' then
  result:=jsonb_set(result,'{history}',coalesce((select jsonb_agg(x||jsonb_build_object('points',coalesce(t.avaliacao_historia->'points',x->'points')) order by ord) from jsonb_array_elements(result->'history') with ordinality as h(x,ord) join public.tentativas t on t.id=(x->>'id')::uuid),'[]'));
 end if;
 return result;
end $$;
revoke all on function public.clube_leitura(text,jsonb) from public,anon;
grant execute on function public.clube_leitura(text,jsonb) to authenticated;
-- O endpoint legado continua disponível para históricos, mas não contorna a regra nova.
alter function public.clube_api(text,jsonb) rename to api_antes_pontos_historia;
alter function public.api_antes_pontos_historia(text,jsonb) set schema clube_private;
create function public.clube_api(op text,args jsonb default '{}') returns jsonb language plpgsql security definer set search_path='' as $$
begin
 if op in('get','answer','finish') and exists(select 1 from public.tentativas a where a.id=(args->>'id')::uuid and clube_private.regra_contexto(a.aluno_id,coalesce(a.evento_participante_id,a.jornada_id),a.evento_participante_id is not null)=3) then return public.clube_leitura(op,args);end if;
 return clube_private.api_antes_pontos_historia(op,args);
end $$;
revoke all on function public.clube_api(text,jsonb) from public,anon;
grant execute on function public.clube_api(text,jsonb) to authenticated;
-- Funções antigas ficam privadas apenas para interpretar contextos históricos.
revoke all on function clube_private.regra_contexto(uuid,uuid,boolean),clube_private.atribuir_jornada(uuid,uuid),clube_private.historia_avaliar(uuid),clube_private.avaliacao_calcular_v2(uuid,uuid,boolean,text),
 clube_private.progresso_niveis_v2(uuid),clube_private.texto_autorizado_v2(uuid,text),clube_private.conquista_registrar_v2(public.tentativas),clube_private.validar_recompensa(),
 clube_private.conquista_json_v2(clube_private.conquistas_niveis),clube_private.attempt_json_v2(public.tentativas),clube_private.leitura_antes_pontos_historia(text,jsonb),clube_private.api_antes_pontos_historia(text,jsonb)
 from public,anon,authenticated;
revoke all on function clube_private.avaliacao_calcular(uuid,uuid,boolean,text),clube_private.progresso_niveis(uuid),clube_private.texto_autorizado(uuid,text),clube_private.conquista_registrar(public.tentativas),clube_private.conquista_json(clube_private.conquistas_niveis),clube_private.attempt_json(public.tentativas) from public,anon,authenticated;
-- Cadastro, login e relatórios consultam o mesmo total acadêmico.
alter function clube_private.aluno_json(uuid) rename to aluno_json_antes_pontos_historia;
create function clube_private.aluno_json(student uuid) returns jsonb language sql stable security definer set search_path='' as $$
 select clube_private.aluno_json_antes_pontos_historia(student)||jsonb_build_object('points',clube_private.total_academico(student),'completed',(select count(*) from clube_private.admin_resultados_validos where aluno_id=student))
$$;
alter view clube_private.admin_alunos rename to admin_alunos_historicos;
create view clube_private.admin_alunos as select a.id,a.name,clube_private.idade_aluno(a.id) as age,a.school,a."schoolId",a."className",a."createdAt",a.status,a.completed,
 clube_private.total_academico(a.id) as points,a."birthDate",a.guardian,a."schoolYear" from clube_private.admin_alunos_historicos a;
revoke all on clube_private.admin_alunos from public,anon,authenticated;
create function clube_private.pontuacao_contexto(student uuid,context_id uuid,is_event boolean) returns numeric language sql stable security definer set search_path='' as $$
 with levels as(select distinct nivel from public.tentativas where aluno_id=student and coalesce(evento_participante_id,jornada_id)=context_id and(evento_participante_id is not null)=is_event),
 totals as(select l.nivel,
 case when exists(select 1 from clube_private.pontuacao_legada p where p.aluno_id=student and p.contexto_id=context_id and p.evento=is_event and p.nivel=l.nivel)
 then(select coalesce(sum(t.pontuacao),0) from clube_private.admin_resultados_validos t where t.aluno_id=student and coalesce(t.evento_participante_id,t.jornada_id)=context_id and t.nivel=l.nivel)
 when clube_private.regra_contexto(student,context_id,is_event)=3 then coalesce(v.unidades,0)
 else coalesce(v.unidades,(clube_private.avaliacao_calcular(student,context_id,is_event,l.nivel)->>'pointUnits')::numeric)/3 end amount
 from levels l left join clube_private.avaliacoes_niveis v on v.aluno_id=student and v.contexto_id=context_id and v.evento=is_event and v.nivel=l.nivel)
 select coalesce(sum(amount),0) from totals
$$;
create function clube_private.pontos_validos_tentativa(attempt_id uuid) returns numeric language plpgsql stable security definer set search_path='' as $$
declare stats jsonb;context_id uuid;is_event boolean;a public.tentativas;
begin
 select * into a from public.tentativas where id=attempt_id;
 context_id:=coalesce(a.evento_participante_id,a.jornada_id);is_event:=a.evento_participante_id is not null;
 if clube_private.regra_contexto(a.aluno_id,context_id,is_event)=3 then return(a.avaliacao_historia->>'points')::numeric;end if;
 if context_id is null or exists(select 1 from clube_private.pontuacao_legada p where p.aluno_id=a.aluno_id and p.contexto_id=context_id and p.evento=is_event and p.nivel=a.nivel) then return a.pontuacao;end if;
 stats:=clube_private.avaliacao_calcular(a.aluno_id,context_id,is_event,a.nivel);
 return 20::numeric/(nullif((stats->>'stories')::numeric,0)*3)+20::numeric*a.acertos/(nullif((stats->>'questions')::numeric,0)*3);
end $$;
do $reports$
declare target regprocedure;definition text;
begin
 -- Recompila as consultas que dependem da view oficial e conserva filtros/paginação.
 foreach target in array array['clube_private.clube_gestao(text,jsonb)'::regprocedure,'public.clube_admin(text,jsonb)'::regprocedure,'public.clube_escolas(text,jsonb)'::regprocedure,'public.clube_eventos(text,jsonb)'::regprocedure] loop
  definition:=pg_get_functiondef(target);
  definition:=replace(definition,'''points'',(select coalesce(sum(pontuacao),0) from clube_private.admin_resultados_validos)', '''points'',(select coalesce(sum(clube_private.total_academico(id)),0) from public.alunos)');
  definition:=replace(definition,'(select coalesce(sum(pontuacao),0) from clube_private.admin_resultados_validos v where v.jornada_id=j.id)','clube_private.pontuacao_contexto(student,j.id,false)');
  definition:=replace(definition,'(select v.pontuacao from clube_private.admin_resultados_validos v where v.id=t.id)','(select clube_private.pontos_validos_tentativa(v.id) from clube_private.admin_resultados_validos v where v.id=t.id)');
  definition:=replace(definition,'coalesce(sum(v.pontuacao),0)','coalesce(sum(clube_private.pontos_validos_tentativa(v.id)),0)');
  definition:=replace(definition,'r.pontos as points', 'case when clube_private.regra_contexto(t.aluno_id,coalesce(t.evento_participante_id,t.jornada_id),t.evento_participante_id is not null)=3 then case when r.correta then 10::numeric/nullif(jsonb_array_length(s.atividade->''questions''),0) when r.correta is null then null else 0 end else r.pontos end as points');
  execute definition;
 end loop;
end $reports$;
revoke all on function clube_private.aluno_json(uuid),clube_private.aluno_json_antes_pontos_historia(uuid),clube_private.pontuacao_contexto(uuid,uuid,boolean),clube_private.pontos_validos_tentativa(uuid) from public,anon,authenticated;

notify pgrst,'reload schema';

$etapa_202611020003$;
 end if;
 if to_regprocedure('clube_private.sincronizar_catalogo(uuid)') is null then
 execute $etapa_202611030001$
-- Atualiza o catalogo comum sem reescrever notas, snapshots ou selecoes de eventos.
alter table clube_private.conclusoes_jornadas add column atual boolean not null default true;
alter table clube_private.conclusoes_jornadas drop constraint conclusoes_jornadas_aluno_id_contexto_id_evento_key;
create unique index conclusao_jornada_atual_idx on clube_private.conclusoes_jornadas(aluno_id,contexto_id,evento) where atual;
create function clube_private.sincronizar_catalogo(student uuid) returns void language plpgsql security definer set search_path='' as $$
declare context_id uuid;added integer;
begin
 perform 1 from public.alunos where id=student for update;
 select id into context_id from public.jornadas where aluno_id=student order by ciclo desc limit 1;
 if clube_private.regra_contexto(student,context_id,false)<>3 then return;end if;
 if not exists(select 1 from clube_private.atribuicoes_jornada where jornada_id=context_id) then return;end if;
 insert into clube_private.atribuicoes_jornada(jornada_id,aluno_id,texto_id,nivel,ordem,atividade,gabarito)
 select context_id,student,t.id,t.nivel,coalesce((select max(x.ordem)+1 from clube_private.atribuicoes_jornada x where x.jornada_id=context_id and x.nivel=t.nivel),0)+row_number() over(partition by t.nivel order by t.ordem,t.id)::integer-1,
 jsonb_build_object('id',t.id,'title',t.titulo,'author',t.autor,'cover',t.capa_url,'minutes',t.tempo_leitura_minutos,'content',t.conteudo,'pages',t.paginas_livro,'age',t.faixa_etaria,'level',t.nivel,'questions',
 (select jsonb_agg(jsonb_build_object('id',q.id,'prompt',q.enunciado,'options',q.alternativas) order by q.id) from public.questoes q where q.texto_id=t.id and q.ativo)),
 (select jsonb_object_agg(q.id,jsonb_build_object('correct',g.correta,'points',coalesce(q.valor,n.pontos))) from public.questoes q join clube_private.gabaritos g on g.questao_id=q.id where q.texto_id=t.id and q.ativo)
 from public.textos t join public.niveis n on n.id=t.nivel
 where t.ativo and t.obrigatorio and t.excluido_em is null and clube_private.historia_idade(student,t.faixa_etaria) and clube_private.texto_pronto(t.id)
 and not exists(select 1 from clube_private.atribuicoes_jornada x where x.jornada_id=context_id and x.texto_id=t.id)
 and not exists(select 1 from clube_private.conquistas_niveis c where c.aluno_id=student and c.contexto_id=context_id and not c.evento and c.nivel=t.nivel)
 and (t.nivel='facil' or (t.nivel='medio' and exists(select 1 from clube_private.atribuicoes_jornada x where x.jornada_id=context_id and x.nivel='facil')) or(t.nivel='dificil' and(select count(distinct x.nivel)=2 from clube_private.atribuicoes_jornada x where x.jornada_id=context_id and x.nivel in('facil','medio'))));
 get diagnostics added=row_count;
 if added>0 then
  update clube_private.conclusoes_jornadas set atual=false where aluno_id=student and contexto_id=context_id and not evento and atual;
  update public.jornadas set status='em_andamento',concluida_em=null where id=context_id;
 end if;
end $$;
-- Certificados anteriores continuam consultaveis; a jornada ampliada recebe um novo resumo ao terminar.
do $patch$ declare definition text;begin
 definition:=pg_get_functiondef('clube_private.jornada_registrar(uuid,uuid,boolean)'::regprocedure);
 definition:=replace(definition,'from clube_private.conclusoes_jornadas where aluno_id=student and contexto_id=context_id and evento=is_event','from clube_private.conclusoes_jornadas where aluno_id=student and contexto_id=context_id and evento=is_event and atual');
 definition:=replace(definition,'on conflict(aluno_id,contexto_id,evento) do nothing','on conflict(aluno_id,contexto_id,evento) where atual do nothing');execute definition;
 definition:=pg_get_functiondef('clube_private.leitura_antes_pontos_historia(text,jsonb)'::regprocedure);
 definition:=replace(definition,'where aluno_id=student and apresentada_em is null','where aluno_id=student and atual and apresentada_em is null');execute definition;
end $patch$;
alter function public.clube_leitura(text,jsonb) rename to leitura_antes_catalogo;
alter function public.leitura_antes_catalogo(text,jsonb) set schema clube_private;
create function public.clube_leitura(op text,args jsonb default '{}') returns jsonb language plpgsql security definer set search_path='' as $$
declare student uuid;
begin
 student:=clube_private.aluno_atual();if student is null then raise exception 'Aluno nao identificado' using errcode='42501';end if;
 if op in('state','enter','start','finish') then
  perform clube_private.sincronizar_catalogo(student);
  -- Segunda passagem permite incorporar Medio e Dificil publicados juntos.
  perform clube_private.sincronizar_catalogo(student);
 end if;
 return clube_private.leitura_antes_catalogo(op,args);
end $$;
revoke all on function public.clube_leitura(text,jsonb) from public,anon;
grant execute on function public.clube_leitura(text,jsonb) to authenticated;
revoke all on function clube_private.sincronizar_catalogo(uuid),clube_private.leitura_antes_catalogo(text,jsonb) from public,anon,authenticated;
notify pgrst,'reload schema';

$etapa_202611030001$;
 end if;
 if to_regprocedure('clube_private.pontuacao_resumo(uuid)') is null then
 execute $etapa_202611030002$
-- Regra oficial: 10 por leitura concluida + 5 por acerto. Historicos permanecem imutaveis.
alter table public.jornadas drop constraint jornadas_regra_pontos_check, add constraint jornadas_regra_pontos_check check(regra_pontos in(2,3,4));
alter table public.evento_alunos drop constraint evento_alunos_regra_pontos_check, add constraint evento_alunos_regra_pontos_check check(regra_pontos in(2,3,4));
alter table clube_private.avaliacoes_niveis drop constraint avaliacoes_niveis_regra_pontos_check, add constraint avaliacoes_niveis_regra_pontos_check check(regra_pontos in(2,3,4));
alter table public.jornadas alter column regra_pontos set default 4;
alter table public.evento_alunos alter column regra_pontos set default 4;
update public.jornadas j set regra_pontos=4 where not exists(select 1 from public.tentativas t where t.jornada_id=j.id) and not exists(select 1 from clube_private.conquistas_niveis c where c.contexto_id=j.id and not c.evento) and not exists(select 1 from clube_private.conclusoes_jornadas c where c.contexto_id=j.id and not c.evento);
update public.evento_alunos p set regra_pontos=4 where not exists(select 1 from public.tentativas t where t.evento_participante_id=p.id) and not exists(select 1 from clube_private.conquistas_niveis c where c.contexto_id=p.id and c.evento) and not exists(select 1 from clube_private.conclusoes_jornadas c where c.contexto_id=p.id and c.evento);
alter table public.tentativas drop constraint avaliacao_historia_consistente;
alter table public.tentativas add constraint avaliacao_historia_consistente check(avaliacao_historia is null or coalesce(
 jsonb_typeof(avaliacao_historia)='object' and avaliacao_historia->>'version' in('3','4') and
 (avaliacao_historia->>'maxPoints')::numeric=case when avaliacao_historia->>'version'='4' then 10+5*(avaliacao_historia->>'questions')::integer else 20 end and
 (avaliacao_historia->>'points')::numeric between 0 and (avaliacao_historia->>'maxPoints')::numeric and
 (avaliacao_historia->>'points')::numeric=(avaliacao_historia->>'readingPoints')::numeric+(avaliacao_historia->>'questionPoints')::numeric,false));
alter table clube_private.avaliacoes_niveis drop constraint avaliacao_regra_valores;
alter table clube_private.avaliacoes_niveis add constraint avaliacao_regra_valores check(
 (regra_pontos=2 and unidades_leitura=20 and unidades_questoes between 0 and 20 and unidades between 0 and 40) or
 (regra_pontos=3 and unidades_leitura=10*historias and unidades_questoes between 0 and 10*historias and unidades between 0 and 20*historias) or
 (regra_pontos=4 and unidades_leitura=10*historias and unidades_questoes=5*acertos and unidades=10*historias+5*acertos));

-- Reutiliza as mesmas funcoes de autorizacao, atribuicao e persistencia nas regras por historia.
do $routing$
declare target regprocedure;definition text;
begin
 foreach target in array array[
 'clube_private.gabarito_historia_v3()'::regprocedure,'clube_private.atribuir_jornada(uuid,uuid)'::regprocedure,
 'clube_private.sincronizar_catalogo(uuid)'::regprocedure,'clube_private.progresso_niveis(uuid)'::regprocedure,
 'clube_private.texto_autorizado(uuid,text)'::regprocedure,'clube_private.conquista_registrar(public.tentativas)'::regprocedure,
 'clube_private.attempt_json(public.tentativas)'::regprocedure,'clube_private.leitura_antes_catalogo(text,jsonb)'::regprocedure,
 'public.clube_api(text,jsonb)'::regprocedure,'clube_private.saldo_moedas(uuid)'::regprocedure,
 'clube_private.ranking_conquista(uuid)'::regprocedure,'clube_private.total_academico(uuid)'::regprocedure,
 'clube_private.pontuacao_contexto(uuid,uuid,boolean)'::regprocedure,'clube_private.pontos_validos_tentativa(uuid)'::regprocedure,
 'clube_private.jornada_registrar(uuid,uuid,boolean)'::regprocedure,'clube_private.conquista_json(clube_private.conquistas_niveis)'::regprocedure,
 'public.clube_escolas(text,jsonb)'::regprocedure] loop
  definition:=pg_get_functiondef(target);
  definition:=replace(replace(replace(definition,'<>3','<3'),')=3',')>=3'),'regra_pontos=3','regra_pontos>=3');
  definition:=replace(definition,'v.regra_pontos is distinct from 3','(v.regra_pontos is null or v.regra_pontos < 3)');
  execute definition;
 end loop;
end $routing$;

create or replace function clube_private.historia_avaliar(attempt_id uuid) returns jsonb language sql stable security definer set search_path='' as $$
 with a as(select t.*,s.atividade,clube_private.regra_contexto(t.aluno_id,coalesce(t.evento_participante_id,t.jornada_id),t.evento_participante_id is not null) rule
 from public.tentativas t join clube_private.conteudos_tentativas s on s.tentativa_id=t.id where t.id=attempt_id),
 counts as(select a.id,a.status,a.leitura_concluida_em,a.rule,count(q)::integer total,
 count(r.questao_id)::integer answered,count(r.questao_id) filter(where r.correta is not null and r.pontos is not null)::integer corrected,
 count(r.questao_id) filter(where r.correta)::integer hits
 from a cross join lateral jsonb_array_elements(a.atividade->'questions') q
 left join public.respostas r on r.tentativa_id=a.id and r.questao_id=(q->>'id')::integer group by a.id,a.status,a.leitura_concluida_em,a.rule),
 calculated as(select *,case when leitura_concluida_em is not null then 10 else 0 end reading,
 case when rule=4 then 5::numeric when total>0 then 10::numeric/total else 0 end unit from counts)
 select jsonb_build_object('version',rule,'scoreVersion',rule,'maxPoints',case when rule=4 then 10+5*total else 20 end,
 'readingComplete',leitura_concluida_em is not null,'stories',1,'completedStories',case when status='completed' and leitura_concluida_em is not null then 1 else 0 end,
 'questions',total,'answered',answered,'corrected',corrected,'hits',hits,'wrong',corrected-hits,'readingPoints',reading,'questionPoints',case when rule=4 then 5*hits else 10::numeric*hits/nullif(total,0) end,
 'points',reading+case when rule=4 then 5*hits else 10::numeric*hits/nullif(total,0) end,'questionPointValue',unit,
 'questionUnit',jsonb_build_object('numerator',case when rule=4 then 5 else 10 end,'denominator',case when rule=4 then 1 else total end),
 'lostPoints',case when rule=4 then 5*(corrected-hits) else 10::numeric*(corrected-hits)/nullif(total,0) end,
 'complete',status='completed' and leitura_concluida_em is not null and total>0 and answered=total and corrected=total and clube_private.resultado_completo(id)) from calculated
$$;

-- Maximo variavel: 10 por historia atribuida + 5 por pergunta atribuida.
do $calculations$ declare definition text;begin
 definition:=pg_get_functiondef('clube_private.gabarito_historia_v3()'::regprocedure);
 definition:=replace(definition,'''points'',1','''points'',case when clube_private.regra_contexto(a.aluno_id,coalesce(a.evento_participante_id,a.jornada_id),a.evento_participante_id is not null)=4 then 5 else 1 end');execute definition;
 definition:=pg_get_functiondef('clube_private.avaliacao_calcular(uuid,uuid,boolean,text)'::regprocedure);
 definition:=replace(definition,'<>3','<3');
 definition:=replace(definition,'''version'',3,''scoreVersion'',3,''maxPoints'',20*stories', '''version'',clube_private.regra_contexto(student,context_id,is_event),''scoreVersion'',clube_private.regra_contexto(student,context_id,is_event),''maxPoints'',case when clube_private.regra_contexto(student,context_id,is_event)=4 then 10*stories+5*questions else 20*stories end');execute definition;
 definition:=pg_get_functiondef('clube_private.conquista_registrar(public.tentativas)'::regprocedure);
 definition:=replace(definition,'group_value,3)','group_value,clube_private.regra_contexto(a.aluno_id,context_id,is_event))');execute definition;
 definition:=pg_get_functiondef('clube_private.conquista_json(clube_private.conquistas_niveis)'::regprocedure);
 definition:=replace(definition,'''scoreVersion'',3', '''scoreVersion'',v.regra_pontos');
 definition:=replace(definition,'20*v.historias','(case when v.regra_pontos=4 then 10*v.historias+5*v.questoes else 20*v.historias end)');
 definition:=replace(definition,'10*v.historias-v.unidades_questoes','case when v.regra_pontos=4 then 5*v.questoes-v.unidades_questoes else 10*v.historias-v.unidades_questoes end');execute definition;
 definition:=pg_get_functiondef('clube_private.attempt_json(public.tentativas)'::regprocedure);
 definition:=replace(definition,'10::numeric/nullif(total,0)','(grade->>''questionPointValue'')::numeric');execute definition;
 definition:=pg_get_functiondef('clube_private.jornada_registrar(uuid,uuid,boolean)'::regprocedure);
 definition:=replace(definition,'then 20*v.historias else','then case when v.regra_pontos=4 then 10*v.historias+5*v.questoes else 20*v.historias end else');
 definition:=replace(definition,'''wrong'',v.questoes-v.acertos)', '''wrong'',v.questoes-v.acertos,''readingPoints'',v.unidades_leitura/case when v.regra_pontos>=3 then 1 else 3 end,''questionPoints'',v.unidades_questoes/case when v.regra_pontos>=3 then 1 else 3 end)');
 definition:=replace(definition,'when x->>''scoreVersion''=''3''','when x->>''scoreVersion'' in(''3'',''4'')');execute definition;
 definition:=pg_get_functiondef('public.clube_escolas(text,jsonb)'::regprocedure);
 definition:=replace(definition,'then 10::numeric/nullif(jsonb_array_length(s.atividade->''questions''),0)','then case when clube_private.regra_contexto(t.aluno_id,coalesce(t.evento_participante_id,t.jornada_id),t.evento_participante_id is not null)=4 then 5::numeric else 10::numeric/nullif(jsonb_array_length(s.atividade->''questions''),0) end');execute definition;
 -- A nota academica nova inclui leituras efetivamente concluidas antes da recompensa de nivel.
 definition:=pg_get_functiondef('clube_private.total_academico(uuid)'::regprocedure);
 definition:=replace(definition,'then coalesce(v.unidades,0)','then coalesce(v.unidades,case when clube_private.regra_contexto(student,c.context_id,c.is_event)=4 then (clube_private.avaliacao_calcular(student,c.context_id,c.is_event,c.nivel)->>''points'')::numeric else 0 end)');execute definition;
 definition:=pg_get_functiondef('clube_private.pontuacao_contexto(uuid,uuid,boolean)'::regprocedure);
 definition:=replace(definition,'then coalesce(v.unidades,0)','then coalesce(v.unidades,case when clube_private.regra_contexto(student,context_id,is_event)=4 then (clube_private.avaliacao_calcular(student,context_id,is_event,l.nivel)->>''points'')::numeric else 0 end)');execute definition;
end $calculations$;

-- Resumo por nivel usa os mesmos resultados oficiais; nunca recebe pontos do navegador.
create function clube_private.pontuacao_resumo(student uuid) returns jsonb language sql stable security definer set search_path='' as $$
 with scores as(
 select t.nivel,clube_private.pontos_validos_tentativa(t.id) points,t.avaliacao_historia grade from clube_private.admin_resultados_validos v join public.tentativas t on t.id=v.id where t.aluno_id=student
 union all
 select t.nivel,(clube_private.historia_avaliar(t.id)->>'points')::numeric,clube_private.historia_avaliar(t.id) from public.tentativas t
 where t.aluno_id=student and t.status='started' and clube_private.regra_contexto(student,coalesce(t.evento_participante_id,t.jornada_id),t.evento_participante_id is not null)=4)
 select jsonb_agg(jsonb_build_object('level',n.id,'points',coalesce(s.points,0),'readingPoints',s.reading,'questionPoints',s.questions) order by array_position(array['facil','medio','dificil'],n.id))
 from public.niveis n left join(select nivel,sum(points) points,case when bool_and(grade is not null) then sum((grade->>'readingPoints')::numeric) end reading,case when bool_and(grade is not null) then sum((grade->>'questionPoints')::numeric) end questions from scores group by nivel) s on s.nivel=n.id
$$;
revoke all on function clube_private.pontuacao_resumo(uuid) from public,anon,authenticated;
do $state$ declare definition text;begin
 definition:=pg_get_functiondef('public.clube_leitura(text,jsonb)'::regprocedure);
 definition:=replace(definition,'declare student uuid;','declare student uuid;result jsonb;');
 definition:=replace(definition,'return clube_private.leitura_antes_catalogo(op,args);', 'result:=clube_private.leitura_antes_catalogo(op,args); if op=''state'' then result:=result||jsonb_build_object(''scoresByLevel'',clube_private.pontuacao_resumo(student));end if;return result;');execute definition;
end $state$;
notify pgrst,'reload schema';

$etapa_202611030002$;
 end if;
 if to_regclass('public.evento_escolas') is null then
 execute $etapa_202611040001$
-- Reutiliza escolas/alunos e as selecoes individuais existentes.
create table public.evento_escolas(
 evento_id uuid not null references public.eventos_leitura(id),escola_id uuid not null references public.escolas(id),
 criado_em timestamptz not null default now(),primary key(evento_id,escola_id));
create index evento_escolas_escola_idx on public.evento_escolas(escola_id,evento_id);
alter table public.evento_escolas enable row level security;
revoke all on public.evento_escolas from public,anon,authenticated;
alter table public.eventos_leitura add column escolas_revisar boolean not null default true;
alter table public.eventos_leitura alter column escolas_revisar set default false;
-- Migra somente escolas de participantes existentes. Nunca libera todas as escolas.
insert into public.evento_escolas(evento_id,escola_id)
 select distinct p.evento_id,a.escola_id from public.evento_alunos p join public.alunos a on a.id=p.aluno_id where a.escola_id is not null;

create function clube_private.evento_escola_permitida(event_id uuid,student uuid) returns boolean language sql stable security definer set search_path='' as $$
 select exists(select 1 from public.alunos a join public.evento_escolas v on v.escola_id=a.escola_id
 where a.id=student and a.situacao='ativo' and a.excluido_em is null and v.evento_id=event_id)
$$;
create policy evento_escolas_autorizadas on public.evento_escolas for select to authenticated using(
 clube_private.administrador() or clube_private.evento_escola_permitida(evento_id,clube_private.aluno_atual()));
-- Sem grants diretos: a consulta e o gerenciamento passam pelos RPCs autenticados.
alter function clube_private.evento_disponivel(uuid,uuid) rename to evento_disponivel_antes_escolas;
create function clube_private.evento_disponivel(event_id uuid,student uuid) returns boolean language sql stable security definer set search_path='' as $$
 select clube_private.evento_escola_permitida(event_id,student) and clube_private.evento_disponivel_antes_escolas(event_id,student)
 and exists(select 1 from public.evento_alunos p join public.evento_leituras l on l.participante_id=p.id where p.evento_id=event_id and p.aluno_id=student)
$$;
-- As policies referenciam OIDs; reatribui explicitamente a funcao apos o rename.
alter policy eventos_autorizados on public.eventos_leitura using(clube_private.administrador() or clube_private.evento_disponivel(id,clube_private.aluno_atual()));
alter policy participantes_proprios on public.evento_alunos using(clube_private.administrador() or(aluno_id=clube_private.aluno_atual() and clube_private.evento_disponivel(evento_id,clube_private.aluno_atual())));
alter policy leituras_proprias on public.evento_leituras using(clube_private.administrador() or exists(select 1 from public.evento_alunos p where p.id=participante_id and p.aluno_id=clube_private.aluno_atual() and clube_private.evento_disponivel(p.evento_id,clube_private.aluno_atual())));
alter function clube_private.evento_elegivel(public.eventos_leitura,public.alunos) rename to evento_elegivel_antes_escolas;
create function clube_private.evento_elegivel(e public.eventos_leitura,a public.alunos) returns boolean language sql stable security definer set search_path='' as $$
 select e.ativo and not e.arquivado and clube_private.evento_escola_permitida(e.id,a.id) and clube_private.evento_elegivel_antes_escolas(e,a)
$$;
alter function clube_private.evento_json(public.eventos_leitura) rename to evento_json_antes_escolas;
create function clube_private.evento_json(e public.eventos_leitura) returns jsonb language sql stable security definer set search_path='' as $$
 select clube_private.evento_json_antes_escolas(e)||jsonb_build_object(
 'schoolIds',coalesce((select jsonb_agg(v.escola_id order by v.escola_id) from public.evento_escolas v where v.evento_id=e.id),'[]'),
 'schools',coalesce((select jsonb_agg(jsonb_build_object('id',s.id,'name',s.nome) order by s.nome,s.id) from public.evento_escolas v join public.escolas s on s.id=v.escola_id where v.evento_id=e.id),'[]'),
 'schoolsNeedReview',e.escolas_revisar or not exists(select 1 from public.evento_escolas v where v.evento_id=e.id))
$$;

alter function public.clube_eventos(text,jsonb) rename to eventos_antes_escolas;
alter function public.eventos_antes_escolas(text,jsonb) set schema clube_private;
create function public.clube_eventos(op text,args jsonb default '{}') returns jsonb language plpgsql security definer set search_path='' as $$
declare result jsonb;e public.eventos_leitura;school_ids uuid[];event_id uuid;replayed boolean:=false;
begin
 if op='mine' then
  result:=clube_private.eventos_antes_escolas(op,args);
  return coalesce((select jsonb_agg(x-'schoolIds'-'schools'-'schoolsNeedReview' order by ord) from jsonb_array_elements(result) with ordinality r(x,ord)),'[]');
 end if;
 if op='enter' then return clube_private.eventos_antes_escolas(op,args);end if;
 if not clube_private.administrador() then raise exception 'Administrador obrigatorio' using errcode='42501';end if;
 if op='school_options' then return public.clube_gestao('schools');end if;
 if op in('save','schools_save') then
  if op='schools_save' or coalesce(args->>'id','')<>'' then
   select * into e from public.eventos_leitura where id=(args->>'id')::uuid for update;
   if e.id is null then raise exception 'Evento nao encontrado' using errcode='P0002';end if;
  elsif args?'requestId' then
   perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended(args->>'requestId',0));
   select * into e from public.eventos_leitura where id=(args->>'requestId')::uuid for update;
   replayed:=e.id is not null;
  end if;
  if not(args?'schoolIds') then
   if e.id is null then raise exception 'Selecione as escolas participantes do evento.' using errcode='22023';end if;
   select coalesce(jsonb_agg(escola_id),'[]') into result from public.evento_escolas where evento_id=e.id;
   args:=args||jsonb_build_object('schoolIds',result);
  end if;
  if jsonb_typeof(args->'schoolIds') is distinct from 'array' or jsonb_array_length(args->'schoolIds')>10000 then raise exception 'Escolas participantes invalidas.' using errcode='22023';end if;
  if exists(select 1 from jsonb_array_elements_text(args->'schoolIds') x where x is null or x!~*'^[a-f0-9]{8}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{12}$') then raise exception 'Escola invalida.' using errcode='22023';end if;
  select coalesce(array_agg(x::uuid),array[]::uuid[]) into school_ids from jsonb_array_elements_text(args->'schoolIds') x;
  if (select count(distinct x) from unnest(school_ids) x)<>cardinality(school_ids) or exists(select 1 from unnest(school_ids) x where not exists(select 1 from public.escolas s where s.id=x)) then raise exception 'Selecione escolas cadastradas, sem duplicatas.' using errcode='22023';end if;
  if replayed then return clube_private.evento_json(e);end if;
  if op='save' then
   if coalesce((args->>'active')::boolean,false) and cardinality(school_ids)=0 then raise exception 'Selecione ao menos uma escola antes de ativar o evento.' using errcode='22023';end if;
   result:=clube_private.eventos_antes_escolas(op,args);event_id:=(result->>'id')::uuid;
  else event_id:=e.id;end if;
  delete from public.evento_escolas v where v.evento_id=event_id and not(v.escola_id=any(school_ids));
  insert into public.evento_escolas(evento_id,escola_id) select event_id,x from unnest(school_ids) x on conflict do nothing;
  update public.eventos_leitura set escolas_revisar=false,atualizado_em=now() where id=event_id returning * into e;
  return clube_private.evento_json(e);
 end if;
 if op in('send','status','delete') then
  select * into e from public.eventos_leitura where id=(args->>'id')::uuid for update;
  if e.id is null then raise exception 'Evento nao encontrado' using errcode='P0002';end if;
  if op='send' then
   if not e.ativo or e.arquivado then raise exception 'Ative o evento antes de distribuir as historias.' using errcode='22023';end if;
   if exists(select 1 from jsonb_array_elements_text(args->'studentIds') x where not clube_private.evento_escola_permitida(e.id,x::uuid)) then raise exception 'Ha alunos de escolas nao vinculadas ao evento. Atualize os destinatarios.' using errcode='22023';end if;
  elsif op='status' and coalesce((args->>'active')::boolean,false) and not exists(select 1 from public.evento_escolas where evento_id=e.id) then
   raise exception 'Selecione as escolas participantes antes de ativar o evento.' using errcode='22023';
  elsif op='delete' and not exists(select 1 from public.evento_alunos where evento_id=e.id) then delete from public.evento_escolas where evento_id=e.id;
  end if;
 end if;
 return clube_private.eventos_antes_escolas(op,args);
end $$;
revoke all on function public.clube_eventos(text,jsonb) from public,anon;
grant execute on function public.clube_eventos(text,jsonb) to authenticated;

-- Revalida todos os endpoints de tentativa, inclusive atividades ja concluidas.
alter function public.clube_leitura(text,jsonb) rename to leitura_antes_escolas;
alter function public.leitura_antes_escolas(text,jsonb) set schema clube_private;
create function public.clube_leitura(op text,args jsonb default '{}') returns jsonb language plpgsql security definer set search_path='' as $$
declare student uuid;event_id uuid;
begin
 student:=clube_private.aluno_atual();if student is null then raise exception 'Aluno nao identificado' using errcode='42501';end if;
 if op in('get','page','stage','answer','finish') then
  select p.evento_id into event_id from public.tentativas t join public.evento_alunos p on p.id=t.evento_participante_id where t.id=(args->>'id')::uuid and t.aluno_id=student;
  if event_id is not null and not clube_private.evento_disponivel(event_id,student) then raise exception 'Este evento nao esta disponivel no momento. Seu progresso esta salvo.' using errcode='42501';end if;
 end if;
 return clube_private.leitura_antes_escolas(op,args);
end $$;
revoke all on function public.clube_leitura(text,jsonb) from public,anon;
grant execute on function public.clube_leitura(text,jsonb) to authenticated;
alter function public.clube_api(text,jsonb) rename to api_antes_escolas;
alter function public.api_antes_escolas(text,jsonb) set schema clube_private;
create function public.clube_api(op text,args jsonb default '{}') returns jsonb language plpgsql security definer set search_path='' as $$
begin
 if op in('get','answer','finish') and exists(select 1 from public.tentativas where id=(args->>'id')::uuid and evento_participante_id is not null) then return public.clube_leitura(op,args);end if;
 return clube_private.api_antes_escolas(op,args);
end $$;
revoke all on function public.clube_api(text,jsonb) from public,anon;
grant execute on function public.clube_api(text,jsonb) to authenticated;
alter function clube_private.leitura_tentativa(public.tentativas) rename to tentativa_antes_escolas;
create function clube_private.leitura_tentativa(a public.tentativas) returns jsonb language plpgsql stable security definer set search_path='' as $$
declare result jsonb;event_id uuid;
begin
 result:=clube_private.tentativa_antes_escolas(a);
 if a.evento_participante_id is not null then
  select evento_id into event_id from public.evento_alunos where id=a.evento_participante_id;
  if not clube_private.evento_disponivel(event_id,a.aluno_id) then
   result:=jsonb_set(result,'{activity}',jsonb_build_object('id',a.texto_id,'title',result->'activity'->>'title','content','','pages','[]'::jsonb,'questions','[]'::jsonb,'level',a.nivel,'age',''));
  end if;
 end if;return result;
end $$;
revoke all on function clube_private.evento_escola_permitida(uuid,uuid),clube_private.evento_disponivel_antes_escolas(uuid,uuid),clube_private.evento_disponivel(uuid,uuid),clube_private.evento_elegivel_antes_escolas(public.eventos_leitura,public.alunos),clube_private.evento_elegivel(public.eventos_leitura,public.alunos),clube_private.evento_json_antes_escolas(public.eventos_leitura),clube_private.evento_json(public.eventos_leitura),clube_private.eventos_antes_escolas(text,jsonb),clube_private.leitura_antes_escolas(text,jsonb),clube_private.api_antes_escolas(text,jsonb),clube_private.tentativa_antes_escolas(public.tentativas),clube_private.leitura_tentativa(public.tentativas) from public,anon,authenticated;
-- As politicas existentes de textos e questoes reutilizam esta mesma autorizacao.
-- Um texto tambem atribuido na jornada comum continua acessivel nessa jornada.
create or replace function public.clube_texto_permitido(text_id text) returns boolean language sql stable security definer set search_path='' as $$
 with identity as(select clube_private.aluno_atual() student)
 select clube_private.administrador() or exists(select 1 from identity i where
 (clube_private.texto_autorizado(i.student,text_id) and (
 exists(select 1 from public.textos t where t.id=text_id and t.obrigatorio)
 or exists(select 1 from clube_private.atribuicoes_jornada x where x.aluno_id=i.student and x.texto_id=text_id and x.jornada_id=(select id from public.jornadas where aluno_id=i.student order by ciclo desc limit 1))
 or exists(select 1 from public.tentativas t where t.aluno_id=i.student and t.texto_id=text_id and t.evento_participante_id is null)
 or(not exists(select 1 from public.evento_historias h where h.texto_id=text_id) and not exists(select 1 from public.evento_leituras l where l.texto_id=text_id))))
 or exists(select 1 from public.evento_alunos p join public.evento_leituras l on l.participante_id=p.id where p.aluno_id=i.student and l.texto_id=text_id and clube_private.evento_disponivel(p.evento_id,i.student)))
$$;
notify pgrst,'reload schema';

$etapa_202611040001$;
 end if;
 if to_regclass('clube_private.autorizacoes_reinicio_jornada') is null then
 execute $etapa_202611040002$
-- Nova jornada somente por autorizacao administrativa, sem apagar historicos.
create table clube_private.autorizacoes_reinicio_jornada(
 jornada_origem uuid primary key references public.jornadas(id),aluno_id uuid not null references public.alunos(id),
 nova_jornada uuid not null unique references public.jornadas(id),administrador_id uuid not null references auth.users(id),
 autorizado_em timestamptz not null default now());
alter table clube_private.autorizacoes_reinicio_jornada enable row level security;
revoke all on clube_private.autorizacoes_reinicio_jornada from public,anon,authenticated;
alter function public.clube_leitura(text,jsonb) rename to leitura_antes_reinicio_admin;
alter function public.leitura_antes_reinicio_admin(text,jsonb) set schema clube_private;
create function public.clube_leitura(op text,args jsonb default '{}') returns jsonb language plpgsql security definer set search_path='' as $$
begin
 if op='new_journey' then raise exception 'Somente a administracao pode autorizar uma nova jornada.' using errcode='42501';end if;
 return clube_private.leitura_antes_reinicio_admin(op,args);
end $$;
revoke all on function public.clube_leitura(text,jsonb) from public,anon;
grant execute on function public.clube_leitura(text,jsonb) to authenticated;
-- O endpoint legado tambem nao pode criar tentativas independentes para repetir leituras.
alter function public.clube_api(text,jsonb) rename to api_antes_reinicio_admin;
alter function public.api_antes_reinicio_admin(text,jsonb) set schema clube_private;
create function public.clube_api(op text,args jsonb default '{}') returns jsonb language plpgsql security definer set search_path='' as $$
begin
 if op in('start','new_journey') then raise exception 'Inicie as atividades pelo painel do aluno. Uma nova jornada exige autorizacao administrativa.' using errcode='42501';end if;
 return clube_private.api_antes_reinicio_admin(op,args);
end $$;
revoke all on function public.clube_api(text,jsonb) from public,anon;
grant execute on function public.clube_api(text,jsonb) to authenticated;
revoke all on function clube_private.api_antes_reinicio_admin(text,jsonb) from public,anon,authenticated;
alter function public.clube_gestao(text,jsonb) rename to gestao_antes_reinicio_admin;
alter function public.gestao_antes_reinicio_admin(text,jsonb) set schema clube_private;
create function public.clube_gestao(op text,args jsonb default '{}') returns jsonb language plpgsql security definer set search_path='' as $$
declare student public.alunos;source public.jornadas;target uuid;
begin
 if not clube_private.administrador() then raise exception 'Administrador obrigatorio' using errcode='42501';end if;
 if op<>'student_journey_restart' then return clube_private.gestao_antes_reinicio_admin(op,args);end if;
 select * into student from public.alunos where id=(args->>'id')::uuid for update;
 if student.id is null or student.excluido_em is not null or student.situacao<>'ativo' then raise exception 'Aluno ativo nao encontrado.' using errcode='22023';end if;
 select * into source from public.jornadas where id=(args->>'journeyId')::uuid and aluno_id=student.id for update;
 if source.id is null then raise exception 'Jornada do aluno nao encontrada.' using errcode='22023';end if;
 select nova_jornada into target from clube_private.autorizacoes_reinicio_jornada where jornada_origem=source.id and aluno_id=student.id;
 if target is not null then return jsonb_build_object('sourceJourneyId',source.id,'newJourneyId',target,'alreadyAuthorized',true);end if;
 if source.id is distinct from(select id from public.jornadas where aluno_id=student.id order by ciclo desc limit 1) then raise exception 'Atualize os dados: esta nao e a jornada atual do aluno.' using errcode='22023';end if;
 perform clube_private.sincronizar_catalogo(student.id);perform clube_private.sincronizar_catalogo(student.id);
 if not clube_private.jornada_completa(student.id) or exists(select 1 from public.tentativas t where t.jornada_id=source.id and t.status='started' and clube_private.texto_autorizado(student.id,t.texto_id)) then
 raise exception 'A jornada atual deve estar concluida antes de autorizar outra.' using errcode='22023';end if;
 update public.jornadas set status='concluida',concluida_em=coalesce(concluida_em,now()),texto_atual_id=null,nivel_atual=null where id=source.id;
 insert into public.jornadas(aluno_id,ciclo) values(student.id,source.ciclo+1) returning id into target;
 insert into clube_private.autorizacoes_reinicio_jornada(jornada_origem,aluno_id,nova_jornada,administrador_id) values(source.id,student.id,target,auth.uid());
 return jsonb_build_object('sourceJourneyId',source.id,'newJourneyId',target,'alreadyAuthorized',false);
end $$;
revoke all on function public.clube_gestao(text,jsonb) from public,anon;
grant execute on function public.clube_gestao(text,jsonb) to authenticated;
revoke all on function clube_private.leitura_antes_reinicio_admin(text,jsonb),clube_private.gestao_antes_reinicio_admin(text,jsonb) from public,anon,authenticated;
notify pgrst,'reload schema';

$etapa_202611040002$;
 end if;
 if to_regprocedure('clube_private.evento_pool(integer,text)') is null then
 execute $etapa_202611040003$
alter table public.eventos_leitura add column distribuicao_automatica boolean not null default false,add column versao_configuracao integer not null default 1;
alter table public.evento_alunos add column versao_configuracao integer not null default 1;
-- O catalogo e compartilhado; cada evento conserva seu proprio conjunto e snapshots.
create function clube_private.evento_pool(age_value integer,level_id text) returns text[] language sql stable security definer set search_path='' as $$
 select coalesce(array_agg(t.id order by t.id),array[]::text[]) from public.textos t where t.ativo and t.excluido_em is null and t.paginas_publicadas
 and t.nivel=level_id and clube_private.evento_faixa(t.faixa_etaria,age_value,age_value) and clube_private.texto_pronto(t.id)
$$;
create function clube_private.evento_config_automatica(configs jsonb) returns jsonb language plpgsql security definer set search_path='' as $$
declare a jsonb;l jsonb;pool text[];items jsonb;result jsonb:='[]';amount numeric;age_value integer;
begin
 if jsonb_typeof(configs) is distinct from 'array' or jsonb_array_length(configs) not between 1 and 16 then raise exception 'Configure as idades do evento.' using errcode='22023';end if;
 for a in select value from jsonb_array_elements(configs) loop
  if coalesce(a->>'age','')!~'^[0-9]+$' or (a->>'age')::integer not between 4 and 19 or jsonb_typeof(a->'levels') is distinct from 'array' then raise exception 'Idade ou niveis invalidos.' using errcode='22023';end if;
  age_value:=(a->>'age')::integer;items:='[]';
  for l in select value from jsonb_array_elements(a->'levels') loop
   if l->>'level' is null or l->>'level' not in('facil','medio','dificil') or jsonb_typeof(l->'quantity') is distinct from 'number' then raise exception 'Quantidade ou nivel invalido.' using errcode='22023';end if;
   amount:=(l->>'quantity')::numeric;
   if amount<0 or amount<>trunc(amount) or amount>2147483647 then raise exception 'Informe uma quantidade inteira maior ou igual a zero.' using errcode='22023';end if;
   if amount=0 then continue;end if;
   pool:=clube_private.evento_pool(age_value,l->>'level');
   if cardinality(pool)<amount then raise exception 'Existem apenas % historias disponiveis para % anos no nivel %. Cadastre mais historias ou reduza a quantidade solicitada.',cardinality(pool),age_value,case l->>'level' when 'facil' then 'Facil' when 'medio' then 'Medio' else 'Dificil' end using errcode='22023';end if;
   items:=items||jsonb_build_array(jsonb_build_object('level',l->>'level','quantity',amount,'storyIds',to_jsonb(pool)));
  end loop;
  if jsonb_array_length(items)=0 then raise exception 'Habilite ao menos um nivel para % anos.',age_value using errcode='22023';end if;
  result:=result||jsonb_build_array(jsonb_build_object('age',age_value,'levels',items));
 end loop;return result;
end $$;
create function clube_private.evento_auto_elegivel(e public.eventos_leitura,student uuid) returns boolean language sql stable security definer set search_path='' as $$
 select e.distribuicao_automatica and e.ativo and not e.arquivado and now()>=e.inicio and now()<e.fim and clube_private.evento_escola_permitida(e.id,student)
 and exists(select 1 from jsonb_array_elements(e.configuracoes) c where (c->>'age')::integer=clube_private.idade_aluno(student))
$$;
create function clube_private.evento_auto_atribuir(event_id uuid,student uuid) returns uuid language plpgsql security definer set search_path='' as $$
declare e public.eventos_leitura;pid uuid;age_value integer;l jsonb;pool text[];chosen text[];all_ids text[]:=array[]::text[];cfg jsonb:='[]';signature text;i integer;
begin
 -- Evento antes de aluno: mesma ordem usada no envio e na leitura.
 select * into e from public.eventos_leitura where id=event_id for update;
 perform 1 from public.alunos where id=student for update;
 if not clube_private.evento_auto_elegivel(e,student) then raise exception 'Evento indisponivel para sua escola, idade ou periodo.' using errcode='42501';end if;
 select id into pid from public.evento_alunos where evento_id=event_id and aluno_id=student;
 if pid is not null then return pid;end if;
 age_value:=clube_private.idade_aluno(student);
 -- Trava a biblioteca antes de validar e capturar os snapshots.
 perform 1 from public.textos where ativo and excluido_em is null order by id for share;
 for l in select v from jsonb_array_elements(e.configuracoes) c cross join lateral jsonb_array_elements(c->'levels') v where (c->>'age')::integer=age_value order by array_position(array['facil','medio','dificil'],v->>'level') loop
  -- Revalida o conjunto deste evento; nunca usa IDs enviados pelo aluno.
  select coalesce(array_agg(id order by id),array[]::text[]) into pool from unnest(clube_private.evento_pool(age_value,l->>'level')) id where id in(select jsonb_array_elements_text(l->'storyIds'));
  if cardinality(pool)<(l->>'quantity')::integer then raise exception 'Historias insuficientes para % anos / %. Solicite a escola para revisar o evento.',age_value,l->>'level' using errcode='22023';end if;
  chosen:=clube_private.evento_sortear(e.id,student,age_value,l->>'level',pool,(l->>'quantity')::integer);
  select jsonb_agg(x order by x)::text into signature from unnest(chosen) x;
  cfg:=cfg||jsonb_build_array(jsonb_build_object('level',l->>'level','quantity',cardinality(chosen),'storyIds',to_jsonb(chosen),'signature',signature,'configurationVersion',e.versao_configuracao));all_ids:=all_ids||chosen;
 end loop;
 insert into public.evento_alunos(evento_id,aluno_id,nivel,idade_min,idade_max,referencia,assinatura,idade_referencia,configuracao,versao_configuracao)
 values(e.id,student,cfg->0->>'level',age_value,age_value,clube_private.hoje_leitura(),to_jsonb(all_ids)::text,age_value,cfg,e.versao_configuracao) returning id into pid;
 for i in 1..cardinality(all_ids) loop perform clube_private.evento_guardar_leitura(pid,all_ids[i],i-1);end loop;
 return pid;
end $$;
-- Niveis futuros atribuidos nao bloqueiam todo o evento; a sequencia e verificada ao entrar.
create or replace function clube_private.evento_disponivel(event_id uuid,student uuid) returns boolean language sql stable security definer set search_path='' as $$
 select case when e.distribuicao_automatica then clube_private.evento_auto_elegivel(e,student)
 and exists(select 1 from public.evento_alunos p where p.evento_id=e.id and p.aluno_id=student)
 and not exists(select 1 from public.evento_alunos p join public.evento_leituras l on l.participante_id=p.id join clube_private.evento_conteudos s on s.leitura_id=l.id left join public.tentativas t on t.id=l.tentativa_id where p.evento_id=e.id and p.aluno_id=student and coalesce(t.status,'started')<>'completed' and not clube_private.historia_idade(student,s.atividade->>'age'))
 else clube_private.evento_escola_permitida(event_id,student) and clube_private.evento_disponivel_antes_escolas(event_id,student) and exists(select 1 from public.evento_alunos p join public.evento_leituras l on l.participante_id=p.id where p.evento_id=event_id and p.aluno_id=student) end from public.eventos_leitura e where e.id=event_id
$$;
-- A progressao da competicao usa os niveis atribuidos neste evento.
create function clube_private.evento_nivel_liberado(pid uuid,level_id text) returns boolean language sql stable security definer set search_path='' as $$
 select exists(select 1 from public.evento_alunos p where p.id=pid and exists(select 1 from jsonb_array_elements(p.configuracao) c where c->>'level'=level_id)
 and (level_id='facil' or clube_private.nivel_liberado(p.aluno_id,level_id) or (
 exists(select 1 from jsonb_array_elements(p.configuracao) c where array_position(array['facil','medio','dificil'],c->>'level')<array_position(array['facil','medio','dificil'],level_id))
 and not exists(select 1 from public.evento_leituras l join clube_private.evento_conteudos s on s.leitura_id=l.id where l.participante_id=p.id and array_position(array['facil','medio','dificil'],s.atividade->>'level')<array_position(array['facil','medio','dificil'],level_id) and not clube_private.resultado_completo(l.tentativa_id)))))
$$;
alter function clube_private.conquista_proximo(uuid,uuid,boolean,text) rename to proximo_antes_automatico;
create function clube_private.conquista_proximo(student uuid,context_id uuid,is_event boolean,level_id text) returns text language plpgsql stable security definer set search_path='' as $$
begin
 if is_event and exists(select 1 from public.evento_alunos p join public.eventos_leitura e on e.id=p.evento_id where p.id=context_id and p.aluno_id=student and e.distribuicao_automatica) then
 return (select c->>'level' from public.evento_alunos p cross join lateral jsonb_array_elements(p.configuracao) c where p.id=context_id and p.aluno_id=student and array_position(array['facil','medio','dificil'],c->>'level')>array_position(array['facil','medio','dificil'],level_id) and clube_private.evento_nivel_liberado(p.id,c->>'level') and clube_private.evento_disponivel(p.evento_id,student) order by array_position(array['facil','medio','dificil'],c->>'level') limit 1);
 end if;return clube_private.proximo_antes_automatico(student,context_id,is_event,level_id);
end $$;
alter function public.clube_eventos(text,jsonb) rename to eventos_antes_automatico;
alter function public.eventos_antes_automatico(text,jsonb) set schema clube_private;
create function public.clube_eventos(op text,args jsonb default '{}') returns jsonb language plpgsql security definer set search_path='' as $$
declare e public.eventos_leitura;result jsonb;student uuid;pid uuid;l record;configs jsonb;created integer:=0;kept integer:=0;old_version integer;old_configs jsonb;replayed boolean:=false;
begin
 if op in('mine','enter') then
  student:=clube_private.aluno_atual();if student is null then raise exception 'Aluno nao identificado' using errcode='42501';end if;
  if op='mine' then
   result:=clube_private.eventos_antes_automatico(op,args);
   for e in select x.* from public.eventos_leitura x where clube_private.evento_auto_elegivel(x,student) and not exists(select 1 from public.evento_alunos p where p.evento_id=x.id and p.aluno_id=student) order by x.inicio,x.id loop
    select c->'levels' into configs from jsonb_array_elements(e.configuracoes) c where (c->>'age')::integer=clube_private.idade_aluno(student);
    result:=result||jsonb_build_array((clube_private.evento_json(e)-'storyIds'-'ageConfigs'-'recipients'-'schoolIds'-'schools'-'schoolsNeedReview')||jsonb_build_object('age',clube_private.idade_aluno(student),'total',(select sum((x->>'quantity')::integer) from jsonb_array_elements(configs) x),'completed',0,'ongoing',false,'assignedLevels',(select jsonb_agg(x-'storyIds') from jsonb_array_elements(configs) x)));
   end loop;
   -- So divulga titulos das historias que pertencem a esta distribuicao.
   return coalesce((select jsonb_agg(x||jsonb_build_object('assignedStories',coalesce((select jsonb_agg(jsonb_build_object('id',r.texto_id,'title',s.atividade->>'title','level',s.atividade->>'level','order',r.ordem,'completed',coalesce(t.status='completed',false)) order by r.ordem) from public.evento_alunos p join public.evento_leituras r on r.participante_id=p.id join clube_private.evento_conteudos s on s.leitura_id=r.id left join public.tentativas t on t.id=r.tentativa_id where p.evento_id=(x->>'id')::uuid and p.aluno_id=student),'[]'))) from jsonb_array_elements(result) x),'[]');
  end if;
  select * into e from public.eventos_leitura where id=(args->>'id')::uuid;
  if e.distribuicao_automatica then
   pid:=clube_private.evento_auto_atribuir(e.id,student);
   select s.atividade->>'level' level into l from public.evento_leituras r join clube_private.evento_conteudos s on s.leitura_id=r.id left join public.tentativas t on t.id=r.tentativa_id where r.participante_id=pid and coalesce(t.status,'started')<>'completed' order by r.ordem limit 1;
   if l.level is not null and not clube_private.evento_nivel_liberado(pid,l.level) then raise exception 'Conclua o nivel anterior.' using errcode='42501';end if;
  end if;
  return clube_private.eventos_antes_automatico(op,args);
 end if;
 if not clube_private.administrador() then raise exception 'Administrador obrigatorio' using errcode='42501';end if;
 if op='save' and coalesce((args->>'automatic')::boolean,false) then
  if args?'id' then select versao_configuracao,configuracoes into old_version,old_configs from public.eventos_leitura where id=(args->>'id')::uuid for update;
  elsif args?'requestId' then
   perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended(args->>'requestId',0));
   select * into e from public.eventos_leitura where id=(args->>'requestId')::uuid;
   if e.id is not null then return clube_private.evento_json(e);end if;
  end if;
  perform 1 from public.textos where ativo and excluido_em is null order by id for share;
  configs:=clube_private.evento_config_automatica(args->'ageConfigs');
  result:=clube_private.eventos_antes_automatico(op,args||jsonb_build_object('ageConfigs',configs));
  update public.eventos_leitura set distribuicao_automatica=true,versao_configuracao=coalesce(old_version,1)+case when old_configs is not null and old_configs is distinct from configs then 1 else 0 end where id=(result->>'id')::uuid;
  return result;
 end if;
 if op='send' then
  select * into e from public.eventos_leitura where id=(args->>'id')::uuid for update;
  if e.distribuicao_automatica then
   if jsonb_typeof(args->'studentIds') is distinct from 'array' or jsonb_array_length(args->'studentIds')=0 then raise exception 'Selecione os alunos.' using errcode='22023';end if;
   for student in select distinct x::uuid from jsonb_array_elements_text(args->'studentIds') x order by 1 loop
    if exists(select 1 from public.evento_alunos where evento_id=e.id and aluno_id=student) then kept:=kept+1;end if;
    pid:=clube_private.evento_auto_atribuir(e.id,student);created:=created+1;
   end loop;return jsonb_build_object('created',created-kept,'existing',kept);
  end if;
 end if;
 return clube_private.eventos_antes_automatico(op,args);
end $$;
revoke all on function public.clube_eventos(text,jsonb) from public,anon;
grant execute on function public.clube_eventos(text,jsonb) to authenticated;
revoke all on function clube_private.eventos_antes_automatico(text,jsonb),clube_private.evento_pool(integer,text),clube_private.evento_config_automatica(jsonb),clube_private.evento_auto_elegivel(public.eventos_leitura,uuid),clube_private.evento_auto_atribuir(uuid,uuid) from public,anon,authenticated;
-- Bloqueia acesso direto a um nivel futuro mesmo com IDs de tentativa conhecidos.
alter function public.clube_leitura(text,jsonb) rename to leitura_antes_automatico;
alter function public.leitura_antes_automatico(text,jsonb) set schema clube_private;
create function public.clube_leitura(op text,args jsonb default '{}') returns jsonb language plpgsql security definer set search_path='' as $$
declare a public.tentativas;
begin
 if op in('get','page','stage','answer','finish') then
 select t.* into a from public.tentativas t join public.evento_alunos p on p.id=t.evento_participante_id join public.eventos_leitura e on e.id=p.evento_id where t.id=(args->>'id')::uuid and t.aluno_id=clube_private.aluno_atual() and e.distribuicao_automatica;
 if a.id is not null and not clube_private.evento_nivel_liberado(a.evento_participante_id,a.nivel) then raise exception 'Conclua o nivel anterior.' using errcode='42501';end if;
 end if;return clube_private.leitura_antes_automatico(op,args);
end $$;
revoke all on function public.clube_leitura(text,jsonb) from public,anon;
grant execute on function public.clube_leitura(text,jsonb) to authenticated;
-- Mantem o OID usado pelas policies de textos e questoes.
do $policy$ declare definition text;updated text;begin
 definition:=pg_get_functiondef('public.clube_texto_permitido(text)'::regprocedure);
 updated:=replace(definition,'and clube_private.evento_disponivel(p.evento_id,i.student)',
 'and clube_private.evento_disponivel(p.evento_id,i.student) and (not exists(select 1 from public.eventos_leitura e where e.id=p.evento_id and e.distribuicao_automatica) or clube_private.evento_nivel_liberado(p.id,(select s.atividade->>''level'' from clube_private.evento_conteudos s where s.leitura_id=l.id)))');
 if updated=definition then raise exception 'Politica de textos incompativel. Aplique eventos_escolas primeiro.';end if;execute updated;
end $policy$;
revoke all on function clube_private.evento_nivel_liberado(uuid,text),clube_private.proximo_antes_automatico(uuid,uuid,boolean,text),clube_private.conquista_proximo(uuid,uuid,boolean,text),clube_private.leitura_antes_automatico(text,jsonb) from public,anon,authenticated;
notify pgrst,'reload schema';

$etapa_202611040003$;
 end if;
 if to_regclass('public.turmas') is null then
 execute $etapa_202611050001$
-- Escolas existentes permanecem; datas historicas desconhecidas ficam nulas.
alter table public.escolas add column municipio text check(municipio is null or length(trim(municipio)) between 2 and 160),add column criado_em timestamptz;
alter table public.escolas alter column criado_em set default now();
create table public.turmas(id uuid primary key default gen_random_uuid(),escola_id uuid not null references public.escolas(id),nome text not null check(length(trim(nome)) between 1 and 60),nome_normalizado text generated always as(lower(trim(regexp_replace(nome,'\s+',' ','g')))) stored,ano_letivo integer not null check(ano_letivo between 2000 and 2100),criado_em timestamptz not null default now(),unique(escola_id,nome_normalizado,ano_letivo));
alter table public.alunos add column turma_id uuid references public.turmas(id);
insert into public.turmas(escola_id,nome,ano_letivo) select distinct on(escola_id,lower(trim(regexp_replace(turma,'\s+',' ','g'))),ano_letivo) escola_id,trim(regexp_replace(turma,'\s+',' ','g')),ano_letivo from public.alunos where escola_id is not null and trim(coalesce(turma,''))<>'' order by escola_id,lower(trim(regexp_replace(turma,'\s+',' ','g'))),ano_letivo,id;
update public.alunos a set turma_id=t.id from public.turmas t where t.escola_id=a.escola_id and t.ano_letivo=a.ano_letivo and t.nome_normalizado=lower(trim(regexp_replace(a.turma,'\s+',' ','g')));
create index turmas_escola_ano_idx on public.turmas(escola_id,ano_letivo);
create index alunos_turma_idx on public.alunos(turma_id);
alter table public.turmas enable row level security;
revoke all on public.turmas from public,anon,authenticated;
create function clube_private.sincronizar_turma_aluno() returns trigger language plpgsql security definer set search_path='' as $$
declare c public.turmas;
begin
 if new.turma_id is not null and (tg_op='INSERT' or new.turma_id is distinct from old.turma_id) then
  select * into c from public.turmas where id=new.turma_id;
  if c.id is null or c.escola_id is distinct from new.escola_id then raise exception 'A turma precisa pertencer a escola do aluno.' using errcode='22023';end if;
  new.turma:=c.nome;new.ano_letivo:=c.ano_letivo;return new;
 end if;
 if new.escola_id is null or trim(coalesce(new.turma,''))='' then new.turma_id:=null;return new;end if;
 insert into public.turmas(escola_id,nome,ano_letivo) values(new.escola_id,trim(regexp_replace(new.turma,'\s+',' ','g')),new.ano_letivo) on conflict(escola_id,nome_normalizado,ano_letivo) do update set nome=public.turmas.nome returning * into c;
 new.turma_id:=c.id;new.turma:=c.nome;return new;
end $$;
create trigger sincronizar_turma_aluno before insert or update of escola_id,turma,ano_letivo,turma_id on public.alunos for each row execute function clube_private.sincronizar_turma_aluno();
revoke all on function clube_private.sincronizar_turma_aluno() from public,anon,authenticated;
alter function public.clube_escolas(text,jsonb) rename to escolas_antes_modulo;
alter function public.escolas_antes_modulo(text,jsonb) set schema clube_private;
revoke all on function clube_private.escolas_antes_modulo(text,jsonb) from public,anon,authenticated;
create function public.clube_escolas(op text,args jsonb default '{}') returns jsonb language plpgsql security definer set search_path='' as $$
declare sid uuid;cid uuid;nm text;city text;year_value integer;page_number integer:=coalesce((args->>'page')::integer,1);page_size integer:=coalesce((args->>'pageSize')::integer,20);search text:=trim(coalesce(args->>'search',''));result jsonb;c public.turmas;e public.escolas;first_day date;last_day date;
begin
 if not clube_private.administrador() then raise exception 'Administrador obrigatorio' using errcode='42501';end if;
 if page_number not between 1 and 1000000 or page_size not between 1 and 100 or length(search)>120 then raise exception 'Filtros invalidos.' using errcode='22023';end if;
 if op='schools_list' then
  return (with filtered as(select s.id,s.nome as name,s.municipio as municipality,s.criado_em as "createdAt",(select count(*) from public.alunos a where a.escola_id=s.id and a.excluido_em is null) as students from public.escolas s where (search='' or strpos(clube_private.nome_ordenacao(s.nome),clube_private.nome_ordenacao(search))>0) and (coalesce(args->>'municipality','')='' or s.municipio=args->>'municipality')),paged as(select * from filtered order by clube_private.nome_ordenacao(name),id limit page_size offset (page_number-1)*page_size) select jsonb_build_object('schools',coalesce((select jsonb_agg(to_jsonb(p) order by clube_private.nome_ordenacao(p.name),p.id) from paged p),'[]'),'total',(select count(*) from filtered),'municipalities',coalesce((select jsonb_agg(municipio order by municipio) from(select distinct municipio from public.escolas where municipio is not null) x),'[]')));
 end if;
 if op in('school_get','school_update','school_delete','school_students','credentials') then
  sid:=(args->>'schoolId')::uuid;select * into e from public.escolas where id=sid for update;
  if e.id is null then raise exception 'Escola nao encontrada.' using errcode='P0002';end if;
  if op='school_update' then
   nm:=trim(regexp_replace(args->>'name','\s+',' ','g'));city:=nullif(trim(args->>'municipality'),'');
   if nm is null or length(nm) not between 2 and 160 or (city is not null and length(city) not between 2 and 160) then raise exception 'Confira o nome e municipio.' using errcode='22023';end if;
   update public.escolas set nome=nm,municipio=city where id=sid returning * into e;
  elsif op='school_delete' then
   if exists(select 1 from public.alunos where escola_id=sid) or exists(select 1 from public.turmas where escola_id=sid) or exists(select 1 from public.evento_escolas where escola_id=sid) then raise exception 'A escola possui alunos, turmas ou eventos vinculados e nao pode ser excluida.' using errcode='22023';end if;
   delete from public.escolas where id=sid;return jsonb_build_object('deleted',true);
  end if;
  if op in('school_get','school_update') then return jsonb_build_object('id',e.id,'name',e.nome,'municipality',e.municipio,'createdAt',e.criado_em,'classes',coalesce((select jsonb_agg(jsonb_build_object('id',id,'name',nome,'schoolYear',ano_letivo) order by ano_letivo desc,clube_private.nome_ordenacao(nome),id) from public.turmas where escola_id=sid),'[]'));end if;
  cid:=nullif(args->>'classId','')::uuid;
  if cid is not null and not exists(select 1 from public.turmas where id=cid and escola_id=sid) then raise exception 'Turma nao pertence a escola selecionada.' using errcode='22023';end if;
  if op='credentials' then
   return jsonb_build_object('school',e.nome,'students',coalesce((select jsonb_agg(jsonb_build_object('id',a.id,'name',coalesce(a.nome_completo,p.nome),'className',coalesce(nullif(a.turma,''),'Sem turma'),'schoolYear',a.ano_letivo,'encrypted',x.credencial_cifrada) order by clube_private.nome_ordenacao(coalesce(a.nome_completo,p.nome)),a.id) from public.alunos a left join public.perfis p on p.id=a.perfil_id left join clube_private.acessos x on x.aluno_id=a.id where a.escola_id=sid and a.excluido_em is null and (cid is null or a.turma_id=cid)),'[]'));
  end if;
  if args->>'period'='today' then first_day:=clube_private.hoje_leitura();last_day:=first_day;
  elsif args->>'period'='7days' then last_day:=clube_private.hoje_leitura();first_day:=last_day-6;
  elsif args->>'period'='30days' then last_day:=clube_private.hoje_leitura();first_day:=last_day-29;
  elsif args->>'period'='custom' then first_day:=(args->>'from')::date;last_day:=(args->>'to')::date;if first_day is null or last_day is null or last_day<first_day then raise exception 'Intervalo invalido.' using errcode='22023';end if;end if;
  return (with filtered as(select a.id,coalesce(a.nome_completo,p.nome) name,a.data_nascimento as "birthDate",clube_private.idade_aluno(a.id) age,coalesce(nullif(a.turma,''),'Sem turma') as "className",a.turma_id as "classId",a.ano_letivo as "schoolYear",a.criado_em as "createdAt",a.situacao status,x.credencial_cifrada encrypted from public.alunos a left join public.perfis p on p.id=a.perfil_id left join clube_private.acessos x on x.aluno_id=a.id where a.escola_id=sid and a.excluido_em is null and (cid is null or a.turma_id=cid) and (coalesce(args->>'age','')='' or clube_private.idade_aluno(a.id)=(args->>'age')::integer) and (search='' or strpos(clube_private.nome_ordenacao(coalesce(a.nome_completo,p.nome)),clube_private.nome_ordenacao(search))>0) and (first_day is null or(a.criado_em>=first_day::timestamp at time zone 'America/Fortaleza' and a.criado_em<(last_day+1)::timestamp at time zone 'America/Fortaleza'))),paged as(select * from filtered order by clube_private.nome_ordenacao(name),id limit page_size offset (page_number-1)*page_size) select jsonb_build_object('students',coalesce((select jsonb_agg(to_jsonb(p) order by clube_private.nome_ordenacao(p.name),p.id) from paged p),'[]'),'total',(select count(*) from filtered)));
 end if;
 if op='classes_list' then
  return (with filtered as(select t.id,t.escola_id as "schoolId",s.nome school,t.nome name,t.ano_letivo as "schoolYear",(select count(*) from public.alunos a where a.turma_id=t.id and a.excluido_em is null) as students from public.turmas t join public.escolas s on s.id=t.escola_id where (coalesce(args->>'schoolId','')='' or t.escola_id=(args->>'schoolId')::uuid) and (coalesce(args->>'schoolYear','')='' or t.ano_letivo=(args->>'schoolYear')::integer) and (search='' or strpos(clube_private.nome_ordenacao(t.nome||' '||s.nome),clube_private.nome_ordenacao(search))>0)),paged as(select * from filtered order by clube_private.nome_ordenacao(school),clube_private.nome_ordenacao(name),"schoolYear" desc,id limit page_size offset (page_number-1)*page_size) select jsonb_build_object('classes',coalesce((select jsonb_agg(to_jsonb(p) order by clube_private.nome_ordenacao(p.school),clube_private.nome_ordenacao(p.name),p."schoolYear" desc,p.id) from paged p),'[]'),'total',(select count(*) from filtered),'schools',(select coalesce(jsonb_agg(jsonb_build_object('id',id,'name',nome) order by clube_private.nome_ordenacao(nome)),'[]') from public.escolas)));
 end if;
 if op in('class_save','class_delete') then
  cid:=nullif(args->>'id','')::uuid;
  if cid is not null then select * into c from public.turmas where id=cid for update;if c.id is null then raise exception 'Turma nao encontrada.' using errcode='P0002';end if;end if;
  if op='class_delete' then
   if exists(select 1 from public.alunos where turma_id=cid) then raise exception 'A turma possui alunos vinculados e nao pode ser excluida.' using errcode='22023';end if;
   delete from public.turmas where id=cid;return jsonb_build_object('deleted',true);
  end if;
  sid:=(args->>'schoolId')::uuid;nm:=trim(regexp_replace(args->>'name','\s+',' ','g'));year_value:=(args->>'schoolYear')::integer;
  if nm is null or length(nm) not between 1 and 60 or year_value is null or year_value not between 2000 and 2100 or not exists(select 1 from public.escolas where id=sid) then raise exception 'Dados da turma invalidos.' using errcode='22023';end if;
  if c.id is not null and c.escola_id<>sid and exists(select 1 from public.alunos where turma_id=c.id) then raise exception 'Nao e permitido mover uma turma com alunos para outra escola.' using errcode='22023';end if;
  if exists(select 1 from public.turmas t where t.escola_id=sid and t.nome_normalizado=lower(nm) and t.ano_letivo=year_value and t.id is distinct from cid) then raise exception 'Esta turma ja existe nesta escola e ano letivo.' using errcode='22023';end if;
  insert into public.turmas(id,escola_id,nome,ano_letivo) values(coalesce(cid,gen_random_uuid()),sid,nm,year_value) on conflict(id) do update set escola_id=excluded.escola_id,nome=excluded.nome,ano_letivo=excluded.ano_letivo returning * into c;
  update public.alunos set turma=c.nome,ano_letivo=c.ano_letivo where turma_id=c.id;
  return jsonb_build_object('id',c.id,'schoolId',c.escola_id,'name',c.nome,'schoolYear',c.ano_letivo);
 end if;
 return clube_private.escolas_antes_modulo(op,args);
end $$;
revoke all on function public.clube_escolas(text,jsonb) from public,anon;
grant execute on function public.clube_escolas(text,jsonb) to authenticated;
notify pgrst,'reload schema';

$etapa_202611050001$;
 end if;
end $instalar_eventos$;
notify pgrst, 'reload schema';
commit;
