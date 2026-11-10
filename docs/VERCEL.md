# Publicação na Vercel

Use `frontend` como Root Directory, Vite como framework, `npm run build` como build e `dist` como saída.
Nas configurações de build, habilite a inclusão dos arquivos fora do Root Directory: a função em `frontend/api/portal/[...path].ts` reutiliza `backend/src`.
Instale as dependências de todos os workspaces (comando de instalação: `cd .. && npm ci`).

Em Settings > Environment Variables, configure para Production:

- `SUPABASE_URL`: URL do projeto Supabase.
- `SUPABASE_ANON_KEY`: chave anon do projeto Supabase.
- `APP_ORIGIN`: `https://clube-de-leitura-beta.vercel.app`.
- `PUBLIC_APP_URL`: `https://clube-de-leitura-beta.vercel.app`.
- `ACCESS_CREDENTIALS_KEY`: mesma chave hexadecimal de 64 caracteres usada no backend local; preserve-a para recuperar as credenciais já emitidas.

Não envie o arquivo `.env` ao GitHub. Após alterar variáveis, faça um Redeploy.
Verifique `/api/portal/health` e `/api/portal/session`: ambos devem retornar JSON.
As migrações SQL e o Anonymous Sign-Ins do Supabase também precisam estar configurados.
