-- Instalador das migrações 202610190003 e 202610190004.
-- Aplicar após 202610190002_sequencia.sql, somente se o gerenciamento ainda não foi instalado.
-- Copie ESTE ARQUIVO COMPLETO para o SQL Editor do projeto lbwswawfosddkmhgcoej.
-- Não executar novamente após sucesso. Não apaga cadastros existentes.

begin;
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
commit;


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
