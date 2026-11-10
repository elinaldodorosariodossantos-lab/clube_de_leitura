begin;
-- Consultas administrativas sobre estruturas existentes; nenhum cadastro é alterado.
create index if not exists tentativas_admin_concluidas_idx on public.tentativas(aluno_id,jornada_id,texto_id,concluida_em,id) where status='completed';

-- Uma conclusão válida por aluno/ciclo/texto. Sem ciclo, usa o grupo legado aluno/texto.
-- Não recalcula gabaritos históricos: confere a consistência da correção armazenada.
create view clube_private.admin_resultados_validos as
 select distinct on(t.aluno_id,t.jornada_id,t.texto_id) t.*
 from public.tentativas t
 cross join lateral (
  select count(*)::integer as answers,count(*) filter(where r.correta)::integer as hits,coalesce(sum(r.pontos),0) as points,
   bool_and(q.texto_id=t.texto_id and r.correta is not null and r.pontos is not null and r.pontos>=0 and (r.correta or r.pontos=0)) as corrected
  from public.respostas r join public.questoes q on q.id=r.questao_id where r.tentativa_id=t.id
 ) v
 where t.status='completed' and t.concluida_em is not null and t.pontuacao>=0
 and v.answers>0 and v.answers=(select count(*) from public.questoes q where q.texto_id=t.texto_id)
 and v.corrected and t.acertos=v.hits and t.pontuacao=v.points
 and abs(t.percentual-(100.0*v.hits/nullif(v.answers,0)))<0.0001
 order by t.aluno_id,t.jornada_id,t.texto_id,t.concluida_em,t.id;

create view clube_private.admin_alunos as
 select a.id,coalesce(a.nome_completo,p.nome) as name,a.idade as age,e.nome as school,a.escola_id as "schoolId",coalesce(a.turma,'') as "className",
 a.criado_em as "createdAt",a.situacao as status,coalesce(v.completed,0) as completed,coalesce(v.points,0) as points
 from public.alunos a left join public.escolas e on e.id=a.escola_id left join public.perfis p on p.id=a.perfil_id
 left join (select aluno_id,count(*) as completed,sum(pontuacao) as points from clube_private.admin_resultados_validos group by aluno_id) v on v.aluno_id=a.id;
revoke all on clube_private.admin_resultados_validos,clube_private.admin_alunos from public,anon,authenticated;

create function public.clube_admin(op text,args jsonb default '{}') returns jsonb language plpgsql security definer set search_path='' as $$
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
   'attempts',coalesce((select jsonb_agg(jsonb_build_object('id',t.id,'title',tx.titulo,'level',t.nivel,'cycle',j.ciclo,'status',t.status,
     'stage',coalesce(to_jsonb(t)->>'etapa',case when t.status='completed' then 'resultado' else 'leitura' end),
     'answered',(select count(*) from public.respostas r where r.tentativa_id=t.id),
     'totalQuestions',(select count(*) from public.questoes q where q.texto_id=t.texto_id),
     'includedInTotals',exists(select 1 from clube_private.admin_resultados_validos v where v.id=t.id),
     'points',(select v.pontuacao from clube_private.admin_resultados_validos v where v.id=t.id),'completedAt',t.concluida_em)
     order by t.concluida_em desc nulls first,t.id) from public.tentativas t join public.textos tx on tx.id=t.texto_id left join public.jornadas j on j.id=t.jornada_id where t.aluno_id=student),'[]'),
   'updatedAt',now());
 end if;
 raise exception 'Operação inválida' using errcode='22023';
end $$;
revoke all on function public.clube_admin(text,jsonb) from public,anon,authenticated;
grant execute on function public.clube_admin(text,jsonb) to authenticated;
notify pgrst,'reload schema';
commit;
