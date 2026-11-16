begin;
-- Retorna o resultado do contexto exato da tentativa, mesmo se ja foi apresentado.
-- Consultas nao reivindicam recompensas, nao recalculam pontos e nao creditam moedas.
alter function public.clube_leitura(text,jsonb) rename to leitura_antes_resultado_persistente;
alter function public.leitura_antes_resultado_persistente(text,jsonb) set schema clube_private;
create function public.clube_leitura(op text,args jsonb default '{}') returns jsonb
language plpgsql security definer set search_path='' as $$
declare result jsonb;a public.tentativas;c clube_private.conquistas_niveis;final_id uuid;
begin
 result:=clube_private.leitura_antes_resultado_persistente(op,args);
 if op in('get','finish') then
  select * into a from public.tentativas where id=(args->>'id')::uuid and aluno_id=clube_private.aluno_atual();
  if a.id is not null and a.status='completed' then
   select * into c from clube_private.conquistas_niveis
    where aluno_id=a.aluno_id and contexto_id=coalesce(a.evento_participante_id,a.jornada_id)
     and evento=(a.evento_participante_id is not null) and nivel=a.nivel;
   select id into final_id from clube_private.conclusoes_jornadas
    where aluno_id=a.aluno_id and contexto_id=coalesce(a.evento_participante_id,a.jornada_id)
     and evento=(a.evento_participante_id is not null);
   result:=result||jsonb_build_object('achievementId',c.id,'journeyCompletionId',final_id);
   if c.id is not null then result:=result||jsonb_build_object('levelScore',clube_private.conquista_json(c));end if;
  end if;
 end if;
 return result;
end $$;
revoke all on function clube_private.leitura_antes_resultado_persistente(text,jsonb) from public,anon,authenticated;
revoke all on function public.clube_leitura(text,jsonb) from public,anon;
grant execute on function public.clube_leitura(text,jsonb) to authenticated;
notify pgrst,'reload schema';
commit;
