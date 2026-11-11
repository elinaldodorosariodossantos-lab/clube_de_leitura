# Frontend na Vercel e backend no Supabase

A Vercel serve o frontend e encaminha `/api/portal/*` para a Edge Function `portal`. Os cookies HttpOnly continuam no domínio do frontend, com caminho `/api/portal`.

## Publicar o backend primeiro

Na raiz do repositório:

```powershell
node backend/scripts/prepare-edge.mjs
npx supabase login
npx supabase secrets set --project-ref lbwswawfosddkmhgcoej APP_ORIGIN=https://clube-de-leitura-beta.vercel.app PUBLIC_APP_URL=https://clube-de-leitura-beta.vercel.app
npx supabase functions deploy portal --project-ref lbwswawfosddkmhgcoej
```

No Supabase, em Edge Functions > Secrets, configure `ACCESS_CREDENTIALS_KEY` com a mesma chave hexadecimal de 64 caracteres usada anteriormente. Preserve essa chave para recuperar credenciais já emitidas. Não a envie ao GitHub. `SUPABASE_URL` e `SUPABASE_ANON_KEY` são fornecidas pelo ambiente das Edge Functions.

`verify_jwt=false` permite alcançar login e consultas públicas. A API valida as sessões e os RPCs mantêm as verificações de autorização. Não utiliza service role. As migrações SQL e Anonymous Sign-Ins também precisam estar configurados.

Edite `backend/src` e execute o script de preparação antes de publicar alterações. Os módulos em `supabase/functions/portal/generated` são gerados para publicação sem arquivos externos à pasta da função.

## Publicar o frontend depois

Na Vercel: Root Directory `frontend`, framework Vite, build `npm run build` e saída `dist`. `vercel.json` define instalação e encaminhamento da API. Publique depois de a Edge Function estar disponível.

As variáveis do backend ficam no Supabase. A Vercel não precisa de `SUPABASE_URL`, `SUPABASE_ANON_KEY` ou `ACCESS_CREDENTIALS_KEY` para executar o portal.

## Verificar

Abra `https://clube-de-leitura-beta.vercel.app/api/portal/health` e `/api/portal/session`: ambos devem retornar JSON. Valide login administrativo, retorno do aluno, upload de capa e fichas PDF. Confirme o encaminhamento dos cookies na publicação real.

Referência: https://supabase.com/docs/guides/functions/routing
