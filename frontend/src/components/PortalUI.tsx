import {BookOpen,ArrowRight} from 'lucide-react';
import type {ReactNode} from 'react';
export function Brand(){return <a className="club-brand" href="#/"><span><BookOpen size={27}/></span><div>Clube da Leitura<small>2026 · cada página, uma descoberta</small></div></a>;}
export function Footer(){return <footer className="club-footer"><Brand/><p>Ler é descobrir um mundo novo!</p><small>Projeto educacional · Clube da Leitura 2026</small></footer>;}
export function Notice({children,error=false}:{children:ReactNode;error?:boolean}){return <div className={'club-notice '+(error?'is-error':'')} role={error?'alert':'status'}>{children}</div>;}
export function JourneyLink({children='Começar minha jornada'}:{children?:ReactNode}){return <a className="club-button" href="#/aluno">{children}<ArrowRight size={18}/></a>;}
export function Preparation(){return <div className="club-card preparation"><BookOpen size={44}/><span className="club-tag">O próximo capítulo está chegando</span><h2>Seu mundo de histórias está esperando por você!</h2><p>A área de leitura será disponibilizada na próxima etapa. Seu cadastro já está salvo para continuar sua jornada.</p></div>;}
