import {lazy,Suspense} from 'react';
import {createRoot} from 'react-dom/client';
const Application=window.location.pathname==='/leitura-legada'?lazy(()=>import('./LegacyApp')):lazy(()=>import('./PortalApp').then(m=>({default:m.PortalApp})));
createRoot(document.getElementById('root')!).render(<Suspense fallback={<p role="status">Preparando o Clube da Leitura…</p>}><Application/></Suspense>);
