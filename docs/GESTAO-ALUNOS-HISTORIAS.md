# Administração de alunos, acessos e histórias

Atualização de 19/10/2026. Mantém o dashboard, o login administrativo e o fluxo direto de leitura do aluno. A administração usa as rotas `/#/admin/alunos` e `/#/admin/historias`, com formulários e fichas em diálogos protegidos.

## Instalação no projeto Supabase existente

1. Conferir se as migrações anteriores, inclusive `202610190001_progressao.sql` e `202610190002_sequencia.sql`, já foram aplicadas. Não reaplicar scripts já executados.
2. Executar **uma vez** `supabase/migrations/202610190003_gestao.sql` no SQL Editor. O script é transacional e interrompe se a sequência anterior não estiver instalada. Não executar novamente o setup inicial.
3. Configurar `ACCESS_CREDENTIALS_KEY` no backend: 32 bytes aleatórios representados por 64 caracteres hexadecimais. No ambiente local desta implementação, a chave foi gerada no arquivo ignorado `backend/.env`, sem exibir o segredo. Para outra instalação, `node backend/scripts/configure-access-key.mjs` configura uma chave sem imprimir seu valor e preserva uma configuração existente.
4. Em produção, definir `PUBLIC_APP_URL` com a URL HTTPS real do frontend. `APP_ORIGIN` continua sendo a origem autorizada das requisições. Sem URL de produção configurada, a emissão de fichas é recusada; não são gerados links locais de produção. Em desenvolvimento, o endereço vem do host do frontend, incluindo sua porta. Para testar QR em outro dispositivo, configurar um endereço acessível por ele; `127.0.0.1` só funciona no próprio dispositivo.
5. Reiniciar a API e abrir o painel com uma conta existente autorizada em `perfis.papel='admin'`, autenticada por e-mail/senha. Não é usada chave `service_role`.

Mantenha a chave de cifragem estável e em segredo. Ela permite reemitir as fichas. Não a coloque no frontend nem no controle de versão. Se for perdida, restaurá-la ou regenerar explicitamente as credenciais dos alunos; não substituir silenciosamente a chave durante a inicialização.

## Alunos e acesso

O formulário exige nome completo, nascimento, responsável, escola existente e série/turma. O cadastro respeita a faixa atual de 4 a 19 anos das tabelas existentes. Escolas podem ser incluídas pelo próprio formulário; a normalização existente evita duplicatas de maiúsculas/minúsculas e espaços.

O backend cria uma identidade anônima isolada no Supabase Auth, sem trocar a sessão administrativa, e registra o perfil/aluno pelas funções autorizadas. A identidade persistente do aluno é reutilizada nos acessos seguintes.

Novas credenciais administrativas usam um token de 256 bits e um código de seis caracteres, com alfabeto sem O/0 e I/1. Ambos são gerados criptograficamente no backend. As buscas usam SHA-256; o material necessário para reimprimir a ficha é cifrado com AES-256-GCM em tabela privada. Restrições únicas no banco impedem colisões inclusive entre requisições simultâneas. O backend tenta novamente a reserva e retorna erro compreensível se não conseguir.

O QR representa o link `/#/acesso/<token>`. O token fica no fragmento da URL, não na query enviada ao servidor. O aluno confirma o acesso e segue para a leitura; ao entrar, a navegação substitui o link pela tela de níveis. Se já houver outra conta conectada, a troca exige confirmação. O formulário de retorno também aceita o código curto e mantém a compatibilidade com os códigos antigos de 32 caracteres.

Todas as formas de acesso validam a situação ativa e recuperam o mesmo aluno e progresso. Há limite por IP no backend e contador privado por identidade anônima no banco, inclusive para RPC direta. Erros de credencial não revelam nomes, escolas ou a existência do cadastro.

A tabela administrativa oferece busca, filtros de escola/série/situação, ordenação por nome ou pontos, paginação, edição, ativação/inativação, progresso e ficha individual. O código fica oculto na lista e é mostrado na ficha solicitada. Editar dados não altera credenciais. Desativar ou regenerar revoga os vínculos de sessão; respostas e pontuações permanecem.

A ficha mostra escola real, nome, série, ano letivo cadastrado, QR, código e link. Tem cópia, impressão com CSS próprio e download PNG. O ano letivo é salvo no cadastro e pode ser alterado no formulário. Cadastros anteriores recebem inicialmente o ano de criação. A impressão remove menu e botões. Capacidade de download e diálogo físico de impressão dependem do navegador; o QR e a ficha também podem ser impressos.

## Histórias e preservação

O formulário permite título, autor, capa, nível, recomendação etária, resumo, duração, texto com parágrafos, situação, obrigatoriedade e ordem. As perguntas são dinâmicas, com quatro alternativas, gabarito, remoção e reordenação. Não há uma quantidade fixa de perguntas ou histórias; o tamanho total das requisições tem limite operacional de segurança.

Ativa corresponde ao `ativo=true` já existente: publicada e disponível segundo as regras de progressão. A publicação exige questões completas. A ordem usa o campo existente `textos.ordem`, com desempate pelo identificador. Histórias opcionais não entram no percurso obrigatório automático.

Para evitar que uma edição mude provas anteriores, cada tentativa recebe uma cópia privada de texto, autor, capa, duração, perguntas, gabarito e valores. Tentativas anteriores são copiadas antes de habilitar as edições. Perguntas removidas do catálogo ficam inativas, sem apagar as respostas que as referenciam. A edição altera as próximas tentativas; as tentativas iniciadas continuam com sua versão e correção originais. O módulo legado também utiliza os gabaritos capturados.

A migração inicial só pode copiar o conteúdo que existe no banco naquele momento; alterações manuais feitas antes dessa cópia não podem ser reconstruídas. As pontuações gravadas são preservadas, e a view de resultados válidos passa a conferir a quantidade histórica de perguntas, mantendo a deduplicação anterior.

Inativar impede novas leituras e suspende a continuidade de uma tentativa existente sem apagar respostas. Republicar na mesma jornada permite retomá-la. Mudanças de ordem preservam a atividade em andamento. Mudanças no catálogo obrigatório recalculam os bloqueios dinamicamente. O aluno continua entrando diretamente na leitura, sem lista intermediária.

## Estruturas e segurança

- Reutilizadas: `perfis`, `alunos`, `escolas`, `textos`, `questoes`, `tentativas`, `respostas`, `jornadas`, níveis, gabaritos, acessos e sessões.
- Colunas novas: `alunos.data_nascimento`, `alunos.responsavel`, `alunos.ano_letivo`, `textos.autor`, `questoes.ativo`, `acessos.codigo_curto_hash` e `acessos.credencial_cifrada`.
- Tabelas privadas novas: `conteudos_tentativas`, para versões históricas, e `tentativas_acesso`, para limitação de acesso. Ambas têm RLS e nenhuma leitura direta concedida aos clientes.
- Índices/restrições: unicidade e formato do hash curto, consistência dos campos de credencial, perguntas ativas por texto, chave da cópia por tentativa e contador por identidade. Uma sequência privada gera IDs de perguntas com segurança em concorrência.
- Funções: `clube_gestao` exige administrador não anônimo em todas as operações; `clube_portal` continua compatível e valida os novos formatos; leitura/correção são adaptadas à versão histórica. Funções internas ficam privadas e sem execução para clientes.
- Views administrativas: acrescidas de nascimento/responsável e adaptadas às perguntas históricas, sem alterar os critérios de soma e deduplicação.
- Storage: a migração cria/reutiliza `clube-capas`, com limite de 5 MB e PNG/JPEG/WebP. Upload, alteração e exclusão exigem administrador; o bucket de capas é público. Usar apenas imagens de capa, sem dados pessoais. Se o bucket já existir com configuração diferente, conferir sua configuração no Storage. A aplicação remove/substitui a referência da capa sem apagar arquivos antigos automaticamente.

## Verificações e arquivos

Comandos: `npm run build`, `npm test` e `npm run test:sql`. Os testes cobrem geração/cifragem, colisões, QR decodificável, autorização, edição sem rotação, inativação, regeneração, retorno pelo mesmo aluno, limitação RPC e preservação de gabaritos/pontos após edição. O teste SQL também verifica as políticas de escrita do Storage em schema local compatível.

O QA de navegador usa somente banco e autenticação locais, em `.qa/management-preview.mjs` e `.qa/management-browser.mjs`. Nenhuma criança ou história de teste é cadastrada no Supabase remoto. A ficha PDF e capturas de QA ficam em `.qa`, com dados fictícios exclusivos de teste. As verificações não substituem a aplicação da migração e a conferência do Storage no projeto real.

Resultado: TypeScript/build e 16 testes automatizados aprovados. As rodadas de navegador verificaram cadastro/edição, ativação/inativação, guarda de alterações não salvas, perguntas dinâmicas, upload/prévia, ordenação, cópia, regeneração e os acessos por código e link ao mesmo aluno. A ficha PDF foi gerada com os controles administrativos ocultos. O QR foi decodificado e seu PNG conferido; o acionamento do download e os bytes gerados foram verificados, mas a gravação pelo gerenciador nativo de downloads do Edge automatizado não pôde ser confirmada nesta execução. A prévia responsiva está em `.qa/gestao-historias.png`. Os scripts de retomada de QA são `.qa/management-tail-browser.mjs` e `.qa/management-layout-browser.mjs`.

Arquivos principais desta etapa:

- `supabase/migrations/202610190003_gestao.sql`, `supabase/tests/management.test.mjs`.
- `backend/src/management.ts`, `credentials.ts`, `management.test.ts`, `credentials.test.ts`, `admin.ts`, `portal.ts`, `server.ts`; `backend/.env.example`; script de configuração da chave; dependências/lockfile.
- `frontend/src/pages/ManageStudents.tsx`, `ManageStories.tsx`, `StudentAccess.tsx`, `Admin.tsx`, `Identification.tsx`; `components/StudentAccessCard.tsx`; `hooks/useUnsavedForm.ts`, `useModalFocus.ts`; `services/management.ts`, `adminRoutes.ts`, `portal.ts`; `types/management.ts`, `admin.ts`; `PortalApp.tsx`, `components/ReadingActivity.tsx`, `types/portal.ts`, `reading.css` e `admin.css`.
- Este guia, README e scripts/artefatos locais de QA. O segredo de desenvolvimento permanece apenas no arquivo ignorado do backend.
