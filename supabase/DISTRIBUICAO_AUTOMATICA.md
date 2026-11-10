# Distribuicao automatica de historias

Execute o arquivo completo supabase/instalar-eventos.sql no SQL Editor do Supabase. A etapa nova e 202611040003_distribuicao_automatica.sql. Publique tambem o frontend e o backend atualizados. Nenhuma alteracao foi aplicada automaticamente ao banco remoto.

No cadastro, informe apenas idade e quantidades em Facil, Medio e Dificil. Zero desativa o nivel; cada idade deve ter pelo menos um nivel utilizado. A biblioteca e consultada automaticamente; o salvamento valida no PostgreSQL quantidades inteiras e historias suficientes. Historias precisam estar ativas, publicadas, nao excluidas, com perguntas e gabaritos, e compativeis com idade e nivel.

O cadastro de historias e compartilhado pelo sistema, sem uma tabela de propriedade exclusiva por evento. Ao salvar, o evento recebe seu proprio conjunto elegivel em configuracoes/evento_historias. O sorteio usa somente esse conjunto, revalidado antes da atribuicao. Novos livros entram no conjunto quando o administrador salva novamente o evento.

Eventos novos salvos pelo formulario atualizado usam automatic:true. Para converter um evento antigo, abra e salve sua configuracao de quantidades. Eventos antigos nao sao convertidos silenciosamente; participantes anteriores nunca perdem suas atribuicoes.

O evento aparece para alunos ativos de escolas vinculadas, na idade cadastrada, durante o periodo ativo. Apenas listar o painel nao sorteia. No primeiro clique em Comecar leitura, o banco trava evento e aluno, procura participacao existente e, se necessario, sorteia todos os niveis configurados. O envio administrativo tambem pode antecipar essa atribuicao. A leitura respeita a ordem Facil, Medio, Dificil e a conclusao dos niveis anteriores atribuidos; um nivel isolado continua sujeito a liberacao pedagogica existente.

As tabelas existentes evento_alunos, evento_leituras e evento_conteudos guardam idade, configuracao, versao, IDs, ordem e snapshots. Unique(evento_id,aluno_id), unique(participante_id,texto_id) e unique(participante_id,ordem), junto dos locks e da transacao, impedem atribuicoes duplicadas. Reentrar, atualizar, responder e trocar de pagina nao repetem o sorteio.

A versao aumenta quando o conjunto/configuracao muda. A configuracao nova vale somente para alunos ainda sem distribuicao. Nem mesmo uma participacao sem respostas e substituida automaticamente. Respostas, progresso, pontos, moedas, imagens e conteudo historico ficam preservados. Os RPCs continuam autenticados, auxiliares privados sem grants, RLS mantida e sem service_role no cliente.

Validacao: supabase/tests/automatic-distribution.test.mjs cria 20 historias por nivel e tres alunos de 4 anos, atribui 5/3/5, verifica unicidade, persistencia, pedidos simultaneos, idade/escola, conclusao dos tres niveis (195 pontos e moedas com uma pergunta correta por historia), edicao e versoes. PGlite serializa suas consultas numa conexao; o teste de Promise.all verifica idempotencia de pedidos sobrepostos, e os locks SQL protegem a operacao em conexoes PostgreSQL distintas. Conferencia visual usa mocks de interface, sem afirmar acesso a dados remotos.
