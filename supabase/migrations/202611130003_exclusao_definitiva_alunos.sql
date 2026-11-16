begin;
-- Mudanca de contrato: excluir aluno apaga seus dados, inclusive exclusoes antigas.
-- Escolas, turmas, biblioteca e dados de outros alunos permanecem intactos.
create function clube_private.excluir_aluno_definitivamente(student uuid) returns void
language plpgsql security definer set search_path='' as $$
declare person public.alunos;identities uuid[];
begin
 select * into person from public.alunos where id=student for update;
 if person.id is null then return;end if;
 if exists(select 1 from public.perfis where id=person.perfil_id and papel<>'aluno') then
  raise exception 'Este cadastro esta vinculado a um perfil de equipe. Desvincule-o antes de excluir o aluno.' using errcode='22023';
 end if;
 select array_agg(id) into identities from(
  select usuario_id id from clube_private.sessoes where aluno_id=student union select person.perfil_id) ids;
 delete from clube_private.sessoes where aluno_id=student;
 delete from clube_private.acessos where aluno_id=student;
 delete from clube_private.recompensas_moedas where aluno_id=student;
 delete from clube_private.avaliacoes_niveis where aluno_id=student;
 delete from clube_private.conquistas_niveis where aluno_id=student;
 delete from clube_private.conclusoes_jornadas where aluno_id=student;
 delete from clube_private.pontuacao_legada where aluno_id=student;
 delete from clube_private.autorizacoes_reinicio_jornada where aluno_id=student;
 delete from clube_private.atribuicoes_jornada where aluno_id=student;
 delete from clube_private.evento_conteudos s using public.evento_leituras l,public.evento_alunos p
  where s.leitura_id=l.id and l.participante_id=p.id and p.aluno_id=student;
 delete from public.evento_leituras l using public.evento_alunos p where l.participante_id=p.id and p.aluno_id=student;
 delete from public.respostas r using public.tentativas t where r.tentativa_id=t.id and t.aluno_id=student;
 delete from clube_private.conteudos_tentativas s using public.tentativas t where s.tentativa_id=t.id and t.aluno_id=student;
 delete from public.tentativas where aluno_id=student;
 delete from public.evento_alunos where aluno_id=student;
 delete from public.jornadas where aluno_id=student;
 delete from public.alunos where id=student;
 delete from public.perfis where id=person.perfil_id and papel='aluno';
 -- Remove identidades exclusivas deste aluno; nunca remove outra conta ou equipe.
 delete from clube_private.tentativas_acesso t where t.usuario_id=any(identities)
  and not exists(select 1 from public.perfis p where p.id=t.usuario_id)
  and not exists(select 1 from clube_private.sessoes s where s.usuario_id=t.usuario_id);
 delete from auth.users u where u.id=any(identities)
  and (u.id=person.perfil_id or coalesce((to_jsonb(u)->>'is_anonymous')::boolean,false))
  and not exists(select 1 from public.perfis p where p.id=u.id)
  and not exists(select 1 from clube_private.sessoes s where s.usuario_id=u.id)
  and not exists(select 1 from clube_private.autorizacoes_reinicio_jornada r where r.administrador_id=u.id);
end $$;
revoke all on function clube_private.excluir_aluno_definitivamente(uuid) from public,anon,authenticated;

alter function public.clube_gestao(text,jsonb) rename to gestao_antes_exclusao_definitiva;
alter function public.gestao_antes_exclusao_definitiva(text,jsonb) set schema clube_private;
create function public.clube_gestao(op text,args jsonb default '{}') returns jsonb
language plpgsql security definer set search_path='' as $$
declare student uuid;
begin
 if not clube_private.administrador() then raise exception 'Administrador obrigatorio' using errcode='42501';end if;
 if op<>'student_delete' then return clube_private.gestao_antes_exclusao_definitiva(op,args);end if;
 student:=nullif(args->>'id','')::uuid;
 if student is null then raise exception 'Informe o aluno que sera excluido.' using errcode='22023';end if;
 perform clube_private.excluir_aluno_definitivamente(student);
 return jsonb_build_object('deleted',true,'permanent',true,'historyPreserved',false);
end $$;
revoke all on function clube_private.gestao_antes_exclusao_definitiva(text,jsonb) from public,anon,authenticated;
revoke all on function public.clube_gestao(text,jsonb) from public,anon;
grant execute on function public.clube_gestao(text,jsonb) to authenticated;

-- Limpa tambem alunos ocultados pela antiga exclusao logica e seus rankings.
do $purge$ declare student uuid;begin
 for student in select id from public.alunos where excluido_em is not null order by id loop
  perform clube_private.excluir_aluno_definitivamente(student);
 end loop;
end $purge$;
notify pgrst,'reload schema';
commit;
