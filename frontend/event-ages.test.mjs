import {test} from 'node:test';
import assert from 'node:assert/strict';
import {readFile} from 'node:fs/promises';
import ts from 'typescript';
const source=(await readFile(new URL('./src/services/eventAges.ts',import.meta.url),'utf8')).replace("import {levelNames} from '../components/ReadingLevels';","const levelNames={facil:'Fácil',medio:'Médio',dificil:'Difícil'};");
const code=ts.transpileModule(source,{compilerOptions:{target:ts.ScriptTarget.ES2022,module:ts.ModuleKind.ESNext}}).outputText;
const {initialAgeConfigs,ageConfigError,ageSummary,withLevelQuantity}=await import('data:text/javascript;base64,'+Buffer.from(code).toString('base64'));
test('formulário de idades: conversão legada, conjuntos e validação',()=>{
 const legacy={id:'legado',minAge:6,maxAge:8,level:'facil',mode:'ordem',quantity:1,storyIds:['a','b']};const converted=initialAgeConfigs(legacy);
 assert.deepEqual(converted.map(c=>c.age),[6,7,8]);assert.ok(converted.every(c=>c.levels[0].quantity===2));assert.equal(ageConfigError(converted),'');
 assert.match(ageConfigError([...converted,converted[0]]),/repita idades/);assert.equal(ageConfigError([{age:7,levels:[{level:'facil',quantity:3,storyIds:[]}]}]),'');
 assert.match(ageConfigError([{age:5,levels:[]}]),/Habilite/);assert.match(ageConfigError([{age:20,levels:converted[0].levels}]),/4 e 19/);
 const saved=[{age:5,levels:[{level:'facil',quantity:1,storyIds:['a']}]},{age:9,levels:[{level:'medio',quantity:2,storyIds:['b','c']}]}];assert.deepEqual(initialAgeConfigs({...legacy,ageConfigs:saved}),saved);assert.match(ageSummary(saved),/5 anos: Fácil \(1\).*9 anos: Médio \(2\)/);
 assert.equal(initialAgeConfigs({...legacy,id:undefined}).length,1,'Novos eventos começam com uma idade editável');
});

 test('quantidades por nivel: independentes, zero desativa e invalidos bloqueados',()=>{
  let config={age:5,levels:[]};
  for(const level of ['facil','medio','dificil'])config=withLevelQuantity(config,level,5);
  assert.deepEqual(config.levels.map(l=>l.quantity),[5,5,5]);
  config={...config,age:6,levels:config.levels.map(l=>({...l,storyIds:['a','b','c','d','e','f','g','h']}))};
  config=withLevelQuantity(config,'facil',8);config=withLevelQuantity(config,'dificil',3);
  assert.deepEqual(config.levels.map(l=>l.quantity),[8,5,3]);assert.equal(ageConfigError([config]),'');
  assert.deepEqual(initialAgeConfigs({ageConfigs:[config]}),[config]);
  const disabled=withLevelQuantity(config,'medio',0);assert.deepEqual(disabled.levels.map(l=>l.level),['facil','dificil']);
  assert.equal(config.levels.length,3,'Nao altera a configuracao original');
  for(const value of [-1,1.5,NaN,Infinity])assert.throws(()=>withLevelQuantity(config,'facil',value),RangeError);
 });
