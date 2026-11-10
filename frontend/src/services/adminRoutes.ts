import type {AdminTab} from '../types/admin';
export const adminPaths:Record<AdminTab,string>={overview:'admin/visao-geral',students:'admin/alunos',events:'admin/eventos',stories:'admin/historias',schools:'admin/escolas',reports:'admin/relatorios',settings:'admin/configuracoes'};
export function parseAdminRoute(route:string):{tab:AdminTab;studentId?:string;schoolId?:string;classId?:string;schoolSection?:'list'|'classes'|'dashboard';notFound?:boolean}{
 if(route==='admin'||route==='admin/entrar')return {tab:'overview'};
 for(const [tab,path] of Object.entries(adminPaths))if(route===path)return {tab:tab as AdminTab};
 if(route==='admin/escolas/listar')return {tab:'schools',schoolSection:'list'};
 if(route==='admin/escolas/turmas')return {tab:'schools',schoolSection:'classes'};
 const dashboard=route.match(/^admin\/escolas\/painel\/([^/]+)(?:\/alunos\/([^/]+))?$/);if(dashboard)return {tab:'schools',schoolSection:'dashboard',schoolId:dashboard[1],...(dashboard[2]?{studentId:dashboard[2]}:{})};
 const school=route.match(/^admin\/escolas\/ver\/([^/]+)(?:\/turma\/([^/]+))?$/);if(school)return {tab:'schools',schoolId:school[1],...(school[2]?{classId:school[2],schoolSection:'classes' as const}:{})};
 const schoolDetail=route.match(/^admin\/escolas\/alunos\/([^/]+)$/);if(schoolDetail)return {tab:'schools',studentId:schoolDetail[1]};
 const detail=route.match(/^admin\/alunos\/([^/]+)$/);if(detail)return {tab:'students',studentId:detail[1]};
 return {tab:'overview',notFound:true};
}
