begin;
-- Reutiliza as tabelas existentes; não remove tentativas nem respostas.
alter table public.tentativas add column etapa text not null default 'leitura' check(etapa in ('leitura','questoes','resultado')),
 add column questao_atual integer not null default 0 check(questao_atual>=0);
create index tentativas_ciclo_texto_idx on public.tentativas(jornada_id,texto_id,status);

-- Conteúdo pedagógico inicial. ON CONFLICT preserva conteúdos já cadastrados.
insert into public.textos(id,titulo,conteudo,faixa_etaria,nivel) values
('passarinho','O passarinho e a árvore','Era uma vez um passarinho chamado Léo que vivia em uma árvore perto de uma escola. Todas as manhãs, ele cantava para as crianças. Certo dia, encontrou um pequeno ninho caído no chão. Com a ajuda de outros pássaros, encontrou um lugar seguro para o ninho. Léo ficou feliz porque ajudou sua família.','6 a 8 anos','facil'),
('biblioteca-bairro','A biblioteca do bairro','Na praça do bairro, uma pequena biblioteca estava quase sempre vazia. Clara percebeu que muitos vizinhos nem sabiam que podiam pegar livros emprestados ali. Em vez de concluir que ninguém gostava de ler, ela conversou com a bibliotecária e ouviu os moradores. Alguns não conheciam os horários; outros achavam que precisavam pagar. Juntas, Clara e a bibliotecária criaram cartazes com informações claras e organizaram uma tarde de troca de recomendações. Na semana seguinte, mais pessoas visitaram a biblioteca. Clara entendeu que ouvir as dificuldades dos outros pode ser o primeiro passo para transformar uma comunidade.','9 a 12 anos','medio'),
('agua-comunidade','Uma decisão sobre a água','Durante uma estiagem, o conselho de um bairro discutiu como reduzir o consumo de água. Uma proposta defendia limitar igualmente o uso em todas as casas. Outra sugeria considerar o número de moradores e as necessidades de cada família. Embora a primeira parecesse mais simples, os participantes perceberam que tratar situações diferentes de maneira idêntica poderia produzir injustiças. Antes de decidir, consultaram registros de consumo e ouviram moradores, comerciantes e profissionais de saúde. Os dados mostraram que consertar vazamentos na rede evitaria um desperdício maior do que várias restrições domésticas juntas. O conselho aprovou os reparos e uma campanha de uso responsável, com acompanhamento dos resultados. A decisão não eliminou todos os conflitos, mas mostrou que argumentos sustentados por evidências e diálogo podem melhorar escolhas coletivas.','13 anos ou mais','dificil') on conflict(id) do nothing;
insert into public.questoes(id,texto_id,enunciado,alternativas) values
(1,'passarinho','Qual era o nome do passarinho?','["Léo","Pedro","Tico","Azulão"]'),
(2,'passarinho','O que o passarinho encontrou no chão?','["Uma folha seca","Um pequeno ninho","Uma semente","Um brinquedo"]'),
(3,'passarinho','Quem ajudou Léo a encontrar um lugar seguro?','["Os alunos","Outros pássaros","O professor","As crianças"]'),
(4,'passarinho','Como Léo se sentiu no final?','["Triste","Com medo","Feliz","Cansado"]'),
(5,'passarinho','Qual é a principal mensagem da história?','["Cantar é perigoso.","Ajudar o outro faz bem.","Devemos abandonar os ninhos.","A escola deve ficar vazia."]'),
(201,'biblioteca-bairro','Por que algumas pessoas não visitavam a biblioteca?','["Não havia livros.","Faltavam informações sobre o funcionamento.","A praça estava fechada.","Clara proibia a entrada."]'),
(202,'biblioteca-bairro','O que Clara fez antes de propor uma solução?','["Ouviu os moradores e a bibliotecária.","Fechou a biblioteca.","Cobrou uma taxa.","Retirou os cartazes."]'),
(203,'biblioteca-bairro','O aumento de visitantes indica que os cartazes e o encontro…','["resolveram todos os problemas do bairro.","tornaram os empréstimos pagos.","ajudaram a aproximar a comunidade da biblioteca.","substituíram a necessidade de livros."]'),
(204,'biblioteca-bairro','Qual conclusão Clara evitou tirar sem investigar?','["A biblioteca emprestava livros.","Os moradores tinham dúvidas.","A bibliotecária podia ajudar.","Ninguém gostava de ler."]'),
(205,'biblioteca-bairro','Qual atitude é mais valorizada pelo texto?','["Decidir sozinho rapidamente.","Ouvir dificuldades para construir soluções.","Ignorar opiniões diferentes.","Competir por mais visitantes."]'),
(301,'agua-comunidade','Qual tensão orienta a discussão inicial?','["Aplicar uma regra igual ou considerar necessidades diferentes.","Fechar escolas ou abrir bibliotecas.","Trocar os moradores do bairro.","Aumentar o desperdício doméstico."]'),
(302,'agua-comunidade','Que evidência mudou a prioridade da decisão?','["Uma opinião sem fonte.","A preferência de um único morador.","Os registros indicavam grande desperdício por vazamentos.","A ausência completa de conflitos."]'),
(303,'agua-comunidade','Por que uma limitação idêntica poderia ser injusta?','["Porque toda regra simples é injusta.","Porque as famílias tinham necessidades e tamanhos diferentes.","Porque nenhuma família usava água.","Porque os dados não foram consultados."]'),
(304,'agua-comunidade','O acompanhamento dos resultados permite…','["dispensar futuras avaliações.","garantir que não haverá outra estiagem.","impedir a participação dos moradores.","verificar a eficácia das medidas e ajustar decisões."]'),
(305,'agua-comunidade','Qual afirmação é sustentada pelo texto?','["Diálogo e evidências podem melhorar decisões sem eliminar todos os conflitos.","A maioria dispensa qualquer evidência.","A solução mais simples é sempre a mais justa.","Somente as famílias causavam desperdício."]') on conflict(id) do nothing;
insert into clube_private.gabaritos(questao_id,correta) values (1,0),(2,1),(3,1),(4,2),(5,1),(201,1),(202,0),(203,2),(204,3),(205,1),(301,0),(302,2),(303,1),(304,3),(305,0) on conflict(questao_id) do nothing;

-- Vincula uma atividade legada aberta, sem apagar ou refazer respostas existentes.
insert into public.jornadas(aluno_id,ciclo)
 select a.id,1 from public.alunos a where not exists(select 1 from public.jornadas j where j.aluno_id=a.id);
with antigas as (
 select distinct on(t.aluno_id) t.id,j.id as jornada from public.tentativas t
 join public.jornadas j on j.aluno_id=t.aluno_id and j.status<>'concluida'
 where t.status='started' and t.jornada_id is null
 and not exists(select 1 from public.tentativas x where x.jornada_id=j.id and x.status='started')
 order by t.aluno_id,t.id
) update public.tentativas t set jornada_id=a.jornada from antigas a where t.id=a.id;
update public.tentativas t set etapa=case when status='completed' then 'resultado' when exists(select 1 from public.respostas r where r.tentativa_id=t.id) then 'questoes' else 'leitura' end,
 questao_atual=coalesce((select pos-1 from (select q.id,row_number() over(order by q.id)::integer as pos from public.questoes q where q.texto_id=t.texto_id) ordered where not exists(select 1 from public.respostas r where r.tentativa_id=t.id and r.questao_id=ordered.id) order by pos limit 1),greatest(0,(select count(*)::integer-1 from public.questoes q where q.texto_id=t.texto_id)));

create function clube_private.leitura_tentativa(a public.tentativas) returns jsonb language sql stable security definer set search_path='' as $$
 select clube_private.attempt_json(a)||jsonb_build_object('journeyId',a.jornada_id,'level',a.nivel,'stage',a.etapa,'index',a.questao_atual,'activity',
 (select jsonb_build_object('id',t.id,'title',t.titulo,'content',t.conteudo,'age',t.faixa_etaria,'level',t.nivel,'questions',(select coalesce(jsonb_agg(jsonb_build_object('id',q.id,'prompt',q.enunciado,'options',q.alternativas) order by q.id),'[]') from public.questoes q where q.texto_id=t.id)) from public.textos t where t.id=a.texto_id))
$$;
create function clube_private.leitura_estado(student uuid) returns jsonb language sql stable security definer set search_path='' as $$
 select jsonb_build_object('student',clube_private.aluno_json(student),'journey',
 (select jsonb_build_object('id',j.id,'cycle',j.ciclo,'status',j.status) from public.jornadas j where j.aluno_id=student order by j.ciclo desc limit 1),
 'levels',(select jsonb_agg(jsonb_build_object('id',n.id,'available',(select count(*) from public.textos t where t.nivel=n.id and t.ativo and exists(select 1 from public.questoes q where q.texto_id=t.id)),
 'completed',(select count(distinct a.texto_id) from public.tentativas a join public.jornadas j on j.id=a.jornada_id where j.aluno_id=student and j.ciclo=(select max(ciclo) from public.jornadas where aluno_id=student) and a.nivel=n.id and a.status='completed')) order by n.pontos) from public.niveis n),
 'active',(select clube_private.leitura_tentativa(a) from public.tentativas a join public.jornadas j on j.id=a.jornada_id where a.aluno_id=student and j.status<>'concluida' and a.status='started' order by j.ciclo desc,a.id limit 1),
 'history',coalesce((select jsonb_agg(jsonb_build_object('id',a.id,'title',t.titulo,'level',a.nivel,'cycle',j.ciclo,'points',a.pontuacao,'completedAt',a.concluida_em) order by a.concluida_em desc) from public.tentativas a join public.textos t on t.id=a.texto_id left join public.jornadas j on j.id=a.jornada_id where a.aluno_id=student and a.status='completed'),'[]'))
$$;

create function public.clube_leitura(op text,args jsonb default '{}') returns jsonb language plpgsql security definer set search_path='' as $$
declare student uuid;j public.jornadas;a public.tentativas;txt public.textos;qid integer;choice integer;amount integer;total integer;idx integer;
begin
 student:=clube_private.aluno_atual();
 if student is null then raise exception 'Aluno não identificado' using errcode='42501';end if;
 if op='state' then return clube_private.leitura_estado(student);end if;
 -- Todas as mutações do aluno são serializadas para impedir tentativas/ciclos duplicados.
 perform 1 from public.alunos where id=student for update;
 select * into j from public.jornadas where aluno_id=student order by ciclo desc limit 1 for update;
 if op='new_journey' then
  if j.id is null or j.status<>'concluida' then raise exception 'Conclua a jornada atual antes de iniciar outra' using errcode='22023';end if;
  insert into public.jornadas(aluno_id,ciclo) values(student,j.ciclo+1);
  return clube_private.leitura_estado(student);
 elsif op='start' then
  if args->>'level' is null or args->>'level' not in ('facil','medio','dificil') then raise exception 'Nível inválido' using errcode='22023';end if;
  if j.id is null or j.status='concluida' then raise exception 'Inicie uma nova jornada explicitamente' using errcode='22023';end if;
  select * into a from public.tentativas where aluno_id=student and jornada_id=j.id and status='started' order by id limit 1;
  if a.id is not null then return clube_private.leitura_tentativa(a);end if;
  select * into txt from public.textos t where t.nivel=args->>'level' and t.ativo and exists(select 1 from public.questoes q where q.texto_id=t.id)
   and not exists(select 1 from public.tentativas done where done.jornada_id=j.id and done.texto_id=t.id and done.status='completed') order by t.id limit 1;
  if txt.id is null then raise exception 'Nenhuma leitura pendente neste nível' using errcode='22023';end if;
  insert into public.tentativas(aluno_id,jornada_id,texto_id,nivel) values(student,j.id,txt.id,txt.nivel) returning * into a;
  update public.jornadas set status='em_andamento',texto_atual_id=txt.id,nivel_atual=txt.nivel where id=j.id;
  return clube_private.leitura_tentativa(a);
 end if;
 select * into a from public.tentativas where id=(args->>'id')::uuid and aluno_id=student for update;
 if a.id is null then raise exception 'Tentativa não encontrada' using errcode='42501';end if;
 if op='get' then return clube_private.leitura_tentativa(a);end if;
 if op='finish' and a.status='completed' then return clube_private.leitura_tentativa(a);end if;
 if a.status='completed' then raise exception 'Atividade já concluída' using errcode='22023';end if;
 if a.jornada_id is null or a.jornada_id<>j.id or j.status='concluida' then raise exception 'Jornada inválida' using errcode='42501';end if;
 select count(*) into total from public.questoes where texto_id=a.texto_id;
 if op='stage' then
  if args->>'stage' is null or args->>'stage' not in ('leitura','questoes') then raise exception 'Etapa inválida' using errcode='22023';end if;
  update public.tentativas set etapa=args->>'stage' where id=a.id returning * into a;
 elsif op='answer' then
  qid:=(args->>'questionId')::integer;choice:=(args->>'selected')::integer;
  if a.etapa<>'questoes' or choice is null or choice not between 0 and 3 or not exists(select 1 from public.questoes where id=qid and texto_id=a.texto_id) then raise exception 'Resposta inválida' using errcode='22023';end if;
  insert into public.respostas(tentativa_id,questao_id,selecionada) values(a.id,qid,choice) on conflict(tentativa_id,questao_id) do update set selecionada=excluded.selecionada;
  select pos-1 into idx from (select q.id,row_number() over(order by q.id)::integer as pos from public.questoes q where q.texto_id=a.texto_id) ordered
   where not exists(select 1 from public.respostas r where r.tentativa_id=a.id and r.questao_id=ordered.id) order by pos limit 1;
  update public.tentativas set questao_atual=coalesce(idx,greatest(0,total-1)) where id=a.id returning * into a;
 elsif op='finish' then
  if total=0 or (select count(*) from public.respostas where tentativa_id=a.id)<>total then raise exception 'Responda a todas as questões' using errcode='22023';end if;
  if (select count(*) from public.questoes q join clube_private.gabaritos g on g.questao_id=q.id where q.texto_id=a.texto_id)<>total then raise exception 'Atividade sem correção configurada' using errcode='22023';end if;
  select pontos into amount from public.niveis where id=a.nivel;
  update public.respostas r set correta=r.selecionada=g.correta,pontos=case when r.selecionada=g.correta then coalesce(q.valor,amount) else 0 end
   from public.questoes q join clube_private.gabaritos g on g.questao_id=q.id where r.tentativa_id=a.id and r.questao_id=q.id;
  update public.tentativas set status='completed',etapa='resultado',concluida_em=now(),
   acertos=(select count(*) from public.respostas where tentativa_id=a.id and correta),
   pontuacao=(select coalesce(sum(pontos),0) from public.respostas where tentativa_id=a.id),
   percentual=(select 100.0*count(*) filter(where correta)/count(*) from public.respostas where tentativa_id=a.id) where id=a.id returning * into a;
  if (select count(distinct nivel) from public.tentativas where jornada_id=j.id and status='completed')=3
   and not exists(select 1 from public.textos t where t.ativo and exists(select 1 from public.questoes q where q.texto_id=t.id)
    and not exists(select 1 from public.tentativas done where done.jornada_id=j.id and done.texto_id=t.id and done.status='completed')) then
   update public.jornadas set status='concluida',concluida_em=now(),texto_atual_id=null,nivel_atual=null where id=j.id;
  else update public.jornadas set texto_atual_id=null,nivel_atual=null where id=j.id;end if;
 else raise exception 'Operação inválida' using errcode='22023';end if;
 return clube_private.leitura_tentativa(a);
end $$;
revoke all on function clube_private.leitura_tentativa(public.tentativas),clube_private.leitura_estado(uuid) from public,anon,authenticated;
revoke all on function public.clube_leitura(text,jsonb) from public,anon;
grant execute on function public.clube_leitura(text,jsonb) to authenticated;
notify pgrst,'reload schema';
commit;
