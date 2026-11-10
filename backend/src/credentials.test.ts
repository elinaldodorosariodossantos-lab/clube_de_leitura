import {test} from 'node:test';
import assert from 'node:assert/strict';
import {createCredentials,readCredentials,hashCredential} from './credentials.js';
test('credenciais criptográficas: formato, unicidade, hash e cifragem autenticada',()=>{
 const previous=process.env.ACCESS_CREDENTIALS_KEY;process.env.ACCESS_CREDENTIALS_KEY='a'.repeat(64);
 try{const seen=new Set<string>();for(let i=0;i<100;i++){const value=createCredentials(),decoded=readCredentials(value.encrypted);assert.match(decoded.code,/^[A-HJ-NP-Z2-9]{6}$/);assert.match(decoded.token,/^[a-f0-9]{64}$/);assert.equal(value.tokenHash,hashCredential(decoded.token));assert.equal(value.shortHash,hashCredential(decoded.code));assert.ok(!seen.has(decoded.token));seen.add(decoded.token);assert.ok(!value.encrypted.includes(decoded.token));}
 const c=createCredentials();assert.throws(()=>readCredentials(c.encrypted.slice(0,-2)+(parseInt(c.encrypted.slice(-2),16)^1).toString(16).padStart(2,'0')));process.env.ACCESS_CREDENTIALS_KEY='b'.repeat(64);assert.throws(()=>readCredentials(c.encrypted));
 }finally{if(previous===undefined)delete process.env.ACCESS_CREDENTIALS_KEY;else process.env.ACCESS_CREDENTIALS_KEY=previous;}
});
