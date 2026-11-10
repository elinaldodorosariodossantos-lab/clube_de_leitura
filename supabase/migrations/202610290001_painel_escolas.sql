begin;
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
commit;
