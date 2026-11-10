import {test} from 'node:test';
import assert from 'node:assert/strict';
import {readFile} from 'node:fs/promises';
import ts from 'typescript';
const code=ts.transpileModule(await readFile(new URL('./src/services/adminRoutes.ts',import.meta.url),'utf8'),{compilerOptions:{target:ts.ScriptTarget.ES2022,module:ts.ModuleKind.ESNext}}).outputText;
const {adminPaths,parseAdminRoute}=await import('data:text/javascript;base64,'+Buffer.from(code).toString('base64'));
test('rotas administrativas: abas próprias, acesso direto e detalhes mantêm o menu ativo',()=>{
 for(const [tab,path] of Object.entries(adminPaths))assert.deepEqual(parseAdminRoute(path),{tab});
 assert.deepEqual(parseAdminRoute('admin'),{tab:'overview'});assert.deepEqual(parseAdminRoute('admin/entrar'),{tab:'overview'});
 assert.deepEqual(parseAdminRoute('admin/alunos/00000000-0000-4000-8000-000000000001'),{tab:'students',studentId:'00000000-0000-4000-8000-000000000001'});
 assert.deepEqual(parseAdminRoute('admin/escolas/alunos/00000000-0000-4000-8000-000000000001'),{tab:'schools',studentId:'00000000-0000-4000-8000-000000000001'});
 assert.deepEqual(parseAdminRoute('admin/escolas/painel/escola-id'),{tab:'schools',schoolSection:'dashboard',schoolId:'escola-id'});
 assert.deepEqual(parseAdminRoute('admin/escolas/painel/escola-id/alunos/aluno-id'),{tab:'schools',schoolSection:'dashboard',schoolId:'escola-id',studentId:'aluno-id'});
 assert.equal(parseAdminRoute('admin/unknown').notFound,true);
});

test('escolas: listar turmas e detalhe da escola mantem o submenu correto',()=>{assert.deepEqual(parseAdminRoute('admin/escolas/listar'),{tab:'schools',schoolSection:'list'});assert.deepEqual(parseAdminRoute('admin/escolas/turmas'),{tab:'schools',schoolSection:'classes'});assert.deepEqual(parseAdminRoute('admin/escolas/ver/escola/turma/turma'),{tab:'schools',schoolId:'escola',classId:'turma',schoolSection:'classes'});});
