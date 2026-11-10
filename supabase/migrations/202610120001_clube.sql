begin;
create schema if not exists clube_private;
revoke all on schema clube_private from public, anon, authenticated;
create table public.perfis(id uuid primary key references auth.users(id),nome text not null,papel text not null default 'aluno' check(papel in ('aluno','professor','admin')),criado_em timestamptz not null default now());
create table public.alunos(id uuid primary key default gen_random_uuid(),perfil_id uuid not null unique references public.perfis(id),faixa_etaria text,turma text);
create table public.niveis(id text primary key,pontos integer not null check(pontos>0));
insert into public.niveis values ('facil',10),('medio',15),('dificil',20);
create table public.textos(id text primary key,titulo text not null,conteudo text not null,faixa_etaria text not null,nivel text not null references public.niveis(id),ativo boolean not null default true);
create table public.questoes(id integer primary key,texto_id text not null references public.textos(id),enunciado text not null,alternativas jsonb not null check(jsonb_array_length(alternativas)=4),valor integer check(valor>0));
create table clube_private.gabaritos(questao_id integer primary key references public.questoes(id),correta integer not null check(correta between 0 and 3));
create table public.tentativas(id uuid primary key default gen_random_uuid(),aluno_id uuid not null references public.alunos(id),texto_id text not null references public.textos(id),nivel text not null references public.niveis(id),acertos integer,pontuacao integer,percentual numeric,status text not null default 'started' check(status in ('started','completed')),concluida_em timestamptz);
create table public.respostas(id uuid primary key default gen_random_uuid(),tentativa_id uuid not null references public.tentativas(id),questao_id integer not null references public.questoes(id),selecionada integer not null check(selecionada between 0 and 3),correta boolean,pontos integer,unique(tentativa_id,questao_id));
create index on public.questoes(texto_id);
create index on public.tentativas(aluno_id,concluida_em desc);
create index on public.respostas(tentativa_id);
alter table public.perfis enable row level security;
alter table public.alunos enable row level security;
alter table public.niveis enable row level security;
alter table public.textos enable row level security;
alter table public.questoes enable row level security;
alter table public.tentativas enable row level security;
alter table public.respostas enable row level security;
alter table clube_private.gabaritos enable row level security;
create policy perfil_proprio on public.perfis for select to authenticated using(id=auth.uid());
create policy aluno_proprio on public.alunos for select to authenticated using(perfil_id=auth.uid());
create policy niveis_leitura on public.niveis for select to authenticated using(true);
create policy textos_ativos on public.textos for select to authenticated using(ativo);
create policy questoes_ativas on public.questoes for select to authenticated using(exists(select 1 from public.textos t where t.id=texto_id and t.ativo));
create policy tentativas_proprias on public.tentativas for select to authenticated using(exists(select 1 from public.alunos a where a.id=aluno_id and a.perfil_id=auth.uid()));
create policy respostas_proprias on public.respostas for select to authenticated using(exists(select 1 from public.tentativas t where t.id=tentativa_id));
revoke all on public.perfis,public.alunos,public.niveis,public.textos,public.questoes,public.tentativas,public.respostas from anon,authenticated;
grant select on public.perfis,public.alunos,public.niveis,public.textos,public.questoes,public.tentativas,public.respostas to authenticated;
create function clube_private.attempt_json(a public.tentativas) returns jsonb language sql stable security definer set search_path='' as $$
select jsonb_build_object('id',a.id,'status',a.status,'completedAt',a.concluida_em,'answers',coalesce((select jsonb_object_agg(r.questao_id,r.selecionada) from public.respostas r where r.tentativa_id=a.id),'{}'::jsonb),'result',case when a.status='completed' then jsonb_build_object('hits',a.acertos,'points',a.pontuacao,'percentage',a.percentual,'details',(select jsonb_agg(jsonb_build_object('id',q.id,'prompt',q.enunciado,'options',q.alternativas,'selected',r.selecionada,'correct',g.correta,'points',r.pontos) order by q.id) from public.respostas r join public.questoes q on q.id=r.questao_id join clube_private.gabaritos g on g.questao_id=q.id where r.tentativa_id=a.id)) else null end)
$$;
create function public.clube_api(op text,args jsonb default '{}') returns jsonb language plpgsql security definer set search_path='' as $$
declare student uuid; a public.tentativas; qid integer; choice integer; value integer;
begin
 if auth.uid() is null then raise exception 'Autenticação obrigatória' using errcode='42501'; end if;
 select id into student from public.alunos where perfil_id=auth.uid();
 if student is null then raise exception 'Aluno não cadastrado pela escola' using errcode='42501'; end if;
 if op='activity' then
 return (select jsonb_build_object('id',t.id,'title',t.titulo,'content',t.conteudo,'age',t.faixa_etaria,'level',t.nivel,'questions',(select jsonb_agg(jsonb_build_object('id',q.id,'prompt',q.enunciado,'options',q.alternativas) order by q.id) from public.questoes q where q.texto_id=t.id)) from public.textos t where t.id='passarinho' and t.ativo);
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
 if choice is null or choice not between 0 and 3 or not exists(select 1 from public.questoes where id=qid and texto_id=a.texto_id) then raise exception 'Alternativa inválida'; end if;
 insert into public.respostas(tentativa_id,questao_id,selecionada) values(a.id,qid,choice) on conflict(tentativa_id,questao_id) do update set selecionada=excluded.selecionada;
 elsif op='finish' then
 if (select count(*) from public.respostas where tentativa_id=a.id)<>(select count(*) from public.questoes where texto_id=a.texto_id) then raise exception 'Responda a todas as questões'; end if;
 select pontos into value from public.niveis where id=a.nivel;
 update public.respostas r set correta=(r.selecionada=g.correta),pontos=case when r.selecionada=g.correta then coalesce(q.valor,value) else 0 end from clube_private.gabaritos g,public.questoes q where r.tentativa_id=a.id and g.questao_id=r.questao_id and q.id=r.questao_id;
 update public.tentativas set status='completed',concluida_em=now(),acertos=(select count(*) from public.respostas where tentativa_id=a.id and correta),pontuacao=(select sum(pontos) from public.respostas where tentativa_id=a.id),percentual=(select 100.0*count(*) filter(where correta)/count(*) from public.respostas where tentativa_id=a.id) where id=a.id returning * into a;
 else raise exception 'Operação inválida'; end if;
 return clube_private.attempt_json(a);
end $$;
revoke all on function clube_private.attempt_json(public.tentativas) from public,anon,authenticated;
revoke all on function public.clube_api(text,jsonb) from public,anon;
grant execute on function public.clube_api(text,jsonb) to authenticated;
commit;
