# Clube da Leitura 2026 — primeira etapa

## Executar

Na raiz do repositório, com Node.js 22.12 ou superior:

```powershell
npm.cmd install
npm.cmd run dev
```

Abra a URL indicada pelo Vite, normalmente http://127.0.0.1:5173. O backend usa a porta 3001 e o proxy Vite encaminha `/api`. Para verificar:

```powershell
npm.cmd run build
npm.cmd test
```

Os testes compilam o backend e executam os arquivos JavaScript, evitando uma falha do `tsx` ao consultar o usuário Windows neste ambiente.

## Configuração Supabase necessária

Ainda não foram fornecidas credenciais nem um banco conectado. A página pública funciona sem elas; o novo portal exige Supabase e não usa o modo demo para salvar alunos.

1. Copie `backend/.env.example` para `backend/.env`. Informe `SUPABASE_URL`, `SUPABASE_ANON_KEY` e `DATA_MODE=supabase`. Nenhuma chave `service_role` é necessária. Em produção, defina `NODE_ENV=production` e `APP_ORIGIN` como a origem HTTPS exata da aplicação.
2. Se o banco ainda não foi inicializado, execute `supabase/migrations/202610120001_clube.sql`. Se suas tabelas já existem, **não execute novamente** essa migração inicial.
3. Execute `supabase/migrations/202610140001_portal.sql` uma única vez no SQL Editor. Ela amplia `alunos`, reutiliza `perfis`, cria escolas, jornadas e estruturas privadas de acesso, sem apagar cadastros ou tentativas. O seed do módulo de leitura é opcional para esta etapa.
4. Em Authentication, habilite **Anonymous Sign-Ins** para a identificação dos alunos. Ajuste os limites de criação de usuários do Supabase à capacidade da feira: os pedidos de autenticação são encaminhados pelo backend. Se ativar CAPTCHA no provedor, será necessário integrar o widget e seu token antes de usar o cadastro; esse recurso não está implementado.
5. Crie a conta administrativa em Authentication usando e-mail e senha. Como responsável pelo banco, conceda o papel em `public.perfis`, com o UUID real da conta:

```sql
insert into public.perfis(id,nome,papel)
values ('UUID_REAL_DA_CONTA', 'Nome do administrador', 'admin')
on conflict(id) do update set papel='admin';
```

Não use o UUID de um aluno. A função também recusa usuários anônimos como administradores. O papel não pode ser alterado pelo frontend.

6. Reinicie o backend depois de configurar o `.env`.

As variáveis `VITE_SUPABASE_URL` e `VITE_SUPABASE_ANON_KEY` continuam opcionais e só são necessárias para o módulo legado. O portal novo centraliza a conexão no servidor.

## Fluxos e segurança

Após cadastro ou retorno por código, o aluno entra diretamente em `/#/leitura`, a página principal da sua área de leitura. Uma sessão já identificada também segue para essa página ao abrir o acesso de aluno. Os menus usam `/#/jornada`, `/#/progresso` e `/#/perfil`, preservando a aba ao recarregar e permitindo voltar pelo navegador. `/#/inicio` continua aceito e redireciona para `/#/leitura`. A disponibilidade de textos e questionários continua no escopo da próxima etapa.

- Página pública: `/`. Cadastro: `/#/aluno`. Retorno: `/#/retornar`. Área do aluno: `/#/inicio`. Administração: `/#/admin`.
- O cadastro valida nome completo, idade e escola. A escola é normalizada quanto a espaços e maiúsculas/minúsculas no PostgreSQL. Turma é opcional.
- A faixa etária padrão é 4–19. Pode ser restringida pelo responsável no banco em `clube_private.configuracao`; os limites físicos da tabela permanecem 4–19. Interface e função SQL usam a configuração. O backend também impede valores fora desse intervalo físico.
- O Supabase cria uma identidade anônima real. Um código individual de 32 caracteres hexadecimais (UUID aleatório com 122 bits de aleatoriedade) permite recuperar o aluno. O código é exibido uma vez e pode ser baixado sem incluir os dados pessoais. Somente o hash SHA-256 fica no banco, em schema privado. Conhecer nome, idade ou escola não concede acesso.
- O código é uma credencial: quem o possui pode entrar no cadastro. Não deve ser divulgado. A equipe deve orientar seu armazenamento pelo responsável. Recuperação por código revoga os vínculos anteriores do portal; não apaga histórico. Recuperação de código perdido pela equipe e alteração de cadastros não fazem parte desta etapa.
- As sessões de acesso e renovação ficam em cookies `HttpOnly`, `SameSite=Strict`, restritos a `/api/portal`; em produção usam `Secure`. Nome, idade, escola, código e desempenho não são armazenados em `localStorage`. Saia ou troque de aluno ao terminar em um dispositivo compartilhado.
- O servidor verifica o usuário no Supabase antes de consultas protegidas. Login administrativo usa e-mail/senha Supabase. A função SQL exige `perfis.papel='admin'` e uma conta não anônima a cada consulta administrativa.
- RLS está habilitada. As novas tabelas não têm concessões de acesso direto a `anon` ou `authenticated`: o bloqueio padrão da RLS e os privilégios negam leitura/escrita direta. A única entrada é `clube_portal`, uma função com `search_path` vazio, identidade verificada e operações delimitadas. Escolas e limites de idade são os únicos dados públicos retornados. As políticas existentes permanecem intactas.
- O backend verifica a origem das mutações e limita cadastros a 120 por IP/15 minutos por padrão; login e retorno a 20 por IP/15 minutos. Os limites em memória valem para uma instância. Em hospedagem com várias instâncias, configure limitação compartilhada no proxy. Configure `APP_ORIGIN` em produção; o proxy deve preservar cookies e usar HTTPS.
- Erros não expõem respostas internas do PostgreSQL, tokens ou senhas. Dados administrativos são carregados apenas após autorização.

## Continuidade e compatibilidade

`jornadas` tem aluno, ciclo, estado, texto e nível atuais. `tentativas.jornada_id` permite associar respostas e resultados existentes a ciclos futuros. Uma restrição impede duas jornadas abertas por aluno; ciclos são únicos por aluno. A implementação futura deve retomar a jornada aberta e criar explicitamente outro ciclo após a conclusão, preservando tentativas anteriores.

O novo menu não inicia textos nem questionários. A área de leitura mostra um estado de preparação. Totais usam `tentativas` reais e retornam zero quando não há conclusões. Os registros anteriores permanecem no banco. Cadastros legados podem não ter idade/escola; a interface identifica campos ausentes.

O módulo anterior permanece disponível em `/leitura-legada`, com seu fluxo e APIs anteriores. Ele tem autenticação própria e não compartilha a sessão do portal novo. Os arquivos e dados de demonstração anteriores não foram apagados. Não utilize dados reais de alunos no modo demo legado.

## Verificação

Os testes automatizados verificam validação, exclusão de campos de papel enviados pelo cliente, origem, falta de configuração, exigência de sessão, recusa de administrador não autorizado, cookies e logout. O provedor Supabase é simulado somente nos testes do portal. Os testes do módulo anterior verificam pontuação, autorização entre alunos, idempotência, edição após conclusão e persistência.

A apresentação foi inspecionada no Edge em desktop e em viewport móvel de 390 px. O formulário móvel também foi inspecionado; ambas as páginas têm largura de documento igual à viewport, sem rolagem horizontal. As capturas estão em `.qa/`. A inspeção visual não substitui a validação do cadastro no banco real.

**Ainda é necessário validar no Supabase real:** executar a migração; cadastrar dois alunos; guardar seus códigos; sair e retornar em outra sessão; confirmar preservação de dados; verificar isolamento entre alunos; negar o painel para uma conta comum e autorizar uma conta com papel administrativo; conferir os totais reais. Testes com provedor simulado não validam a execução das funções SQL nem as políticas em um banco conectado.

## Arquivos

- `frontend/src/main.tsx`: seleciona o portal novo ou a aplicação legada com carregamento separado.
- `frontend/src/PortalApp.tsx`: rotas, sessão e proteção da interface.
- `frontend/src/pages/`: apresentação, identificação, área do aluno e administração.
- `frontend/src/components/PortalUI.tsx`: componentes reutilizáveis.
- `frontend/src/services/portal.ts`, `frontend/src/types/portal.ts`: API e contratos.
- `frontend/src/portal.css`, `frontend/index.html`: identidade visual responsiva e metadados.
- `frontend/src/LegacyApp.tsx`: conteúdo do antigo `main.tsx`, preservado.
- `backend/src/portal.ts`, `backend/src/server.ts`: conexão, autenticação e rotas.
- `backend/src/portal.test.ts`, `backend/src/api.test.ts`, `backend/package.json`: verificações e execução dos testes.
- `backend/.env.example`: configuração.
- `supabase/migrations/202610140001_portal.sql`: modelagem e operações protegidas.
