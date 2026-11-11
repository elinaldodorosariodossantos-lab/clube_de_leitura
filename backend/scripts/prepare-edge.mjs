import {readFile,mkdir,writeFile} from 'node:fs/promises';
import ts from 'typescript';

const source=new URL('../src/',import.meta.url),output=new URL('../../supabase/functions/portal/generated/',import.meta.url);
const visited=new Set();
await mkdir(output,{recursive:true});
async function emit(name){
 if(visited.has(name))return;
 visited.add(name);
 const code=await readFile(new URL(name,source),'utf8');
 for(const item of ts.preProcessFile(code).importedFiles){
  if(item.fileName.startsWith('./'))await emit(item.fileName.slice(2).replace(/\.js$/,'.ts'));
 }
 const result=ts.transpileModule(code,{compilerOptions:{target:ts.ScriptTarget.ES2022,module:ts.ModuleKind.ESNext}});
 await writeFile(new URL(name.replace(/\.ts$/,'.js'),output),'// Gerado por backend/scripts/prepare-edge.mjs; edite backend/src.\nimport process from "node:process";\nimport {Buffer} from "node:buffer";\n'+result.outputText);
}
await emit('edge-app.ts');
console.log(`Backend Supabase preparado: ${visited.size} módulos.`);
