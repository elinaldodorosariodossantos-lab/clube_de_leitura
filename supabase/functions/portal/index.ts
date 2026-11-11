import process from 'node:process';
process.env.NODE_ENV='production';
if(!process.env.APP_ORIGIN)throw new Error('Configure APP_ORIGIN com o domínio HTTPS do frontend.');
const {app}=await import('./generated/edge-app.js');
app.listen(8000);
