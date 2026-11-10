import {useState} from 'react';
import {portalApi} from '../services/portal';
import type {Student} from '../types/portal';
import './student-login.css';

export function StudentLogin({onIdentified}:{onIdentified:(student:Student)=>void}){
 const [code,setCode]=useState(''),[busy,setBusy]=useState(false),[error,setError]=useState('');
 const valid=/^[A-HJ-NP-Z2-9]{6}$/.test(code.trim());
 async function submit(event:React.FormEvent){
  event.preventDefault();if(busy)return;
  if(!valid){setError('Digite os 6 caracteres do código fornecido pela escola.');return;}
  setBusy(true);setError('');
  try{const result=await portalApi<{student:Student}>('/return',{code:code.trim()});onIdentified(result.student);}
  catch(cause){const message=(cause as Error).message;setError(/inválido|inativo|desativado|Confira os dados ou o código/i.test(message)?'Código inválido. Confira o código fornecido pela escola e tente novamente.':message);}
  finally{setBusy(false);}
 }
 return <main className="student-login"><section className="student-login-card" aria-labelledby="student-login-title"><h1 id="student-login-title">Clube da Leitura</h1><p>Digite seu código de acesso para começar sua aventura de leitura.</p><form onSubmit={submit} aria-busy={busy}><label htmlFor="student-login-code">Código de acesso</label><input id="student-login-code" name="code" type="text" value={code} onChange={event=>{setCode(event.target.value.trim().toUpperCase().replace(/[^A-Z0-9]/g,'').slice(0,6));setError('');}} maxLength={6} minLength={6} required autoComplete="off" autoCapitalize="characters" spellCheck={false} placeholder="Ex.: A7K2M9" disabled={busy} aria-invalid={!!error} aria-describedby={error?'student-login-error':undefined}/>{error&&<p className="student-login-error" id="student-login-error" role="alert">{error}</p>}<button type="submit" disabled={busy||!valid}>{busy?'Validando…':'Entrar'}</button></form></section></main>;
}
