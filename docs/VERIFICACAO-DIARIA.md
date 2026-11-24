# Verificação diária do banco

O workflow `.github/workflows/database-ping.yml` consulta o banco todos os dias às **07:00 de Fortaleza**, usando `0 10 * * *` em UTC. Ele chama `/api/portal/settings`, cuja implementação consulta `public.clube_portal('config')` e lê a configuração do PostgreSQL. `/health` não é usado porque sua resposta é estática.

Não exige senha, token administrativo, chave de serviço ou novo SQL. Não altera cadastros ou resultados. Respostas precisam conter a configuração esperada; falhas de rede, HTTP 429 e erros 5xx recebem até três tentativas, com intervalo de cinco segundos. Uma falha definitiva deixa a execução do GitHub Actions como falha.

## Ativar

1. Envie os arquivos para a branch padrão do repositório, `main`.
2. Abra **GitHub → Actions → Verificar banco diariamente**. Habilite Actions, se necessário.
3. Use **Run workflow** para testar uma execução manual.
4. O endereço padrão é `https://clube-de-leitura-edu.vercel.app`. Para mudar, configure a variável de repositório `APP_URL` em **Settings → Secrets and variables → Actions → Variables**.

Teste manual local: `node backend/scripts/ping-database.mjs`. Os registros mostram apenas sucesso, horário ou erro, sem dados dos alunos.

O computador do administrador não precisa ficar ligado. O GitHub pode atrasar execuções agendadas; não é um serviço de horário exato. Em repositórios públicos, os agendamentos podem ser desativados após 60 dias sem atividade no repositório. Nesse caso, reative em Actions.

O Supabase pode pausar projetos gratuitos com pouca atividade. A consulta diária ajuda a gerar atividade e detectar falhas, mas não garante disponibilidade nem retoma um projeto que já foi pausado. Planos pagos não sofrem pausa automática por inatividade.

Fontes: [Supabase — Project Pausing](https://supabase.com/docs/guides/platform/free-project-pausing) e [GitHub — Schedule](https://docs.github.com/en/actions/reference/workflows-and-actions/events-that-trigger-workflows#schedule).
