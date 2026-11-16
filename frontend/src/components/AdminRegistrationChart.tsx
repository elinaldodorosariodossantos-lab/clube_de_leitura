import {useId} from 'react';
import {registrationSeries} from '../services/admin-overview';
import type {AdminStudent} from '../types/admin';

export function AdminRegistrationChart({readers,days,updatedAt}:{readers:AdminStudent[];days:number;updatedAt:string}){
 const id=useId().replaceAll(':',''),series=registrationSeries(readers,days,updatedAt);
 const total=series.reduce((sum,d)=>sum+d.count,0),max=Math.max(4,...series.map(d=>d.count));
 const ceiling=Math.ceil(max/4)*4,left=38,right=632,top=14,bottom=174;
 const points=series.map((d,index)=>({x:left+index*(right-left)/Math.max(1,series.length-1),y:bottom-d.count/ceiling*(bottom-top),...d}));
 const line=points.map(p=>`${p.x},${p.y}`).join(' ');
 return <div className="admin-registration-chart"><div className="admin-chart-summary"><strong>{total.toLocaleString('pt-BR')}</strong><span>novos cadastros nos últimos {days} dias</span></div>
 {total?<svg viewBox="0 0 650 207" role="img" aria-labelledby={id+'-title'}><title id={id+'-title'}>Cadastros diários no clube nos últimos {days} dias: {total} alunos</title><defs><linearGradient id={id+'-fill'} x2="0" y2="1"><stop stopColor="#1989ff" stopOpacity=".32"/><stop offset="1" stopColor="#1989ff" stopOpacity=".025"/></linearGradient></defs>{[0,1,2,3,4].map(step=>{const y=bottom-step*(bottom-top)/4;return <g key={step}><path d={`M${left} ${y}H${right}`} stroke="#e6eefb"/><text x="26" y={y+4} textAnchor="end">{ceiling*step/4}</text></g>;})}<path d={`M${left} ${bottom}L${line.replaceAll(' ',' L')}L${right} ${bottom}Z`} fill={`url(#${id}-fill)`}/><polyline points={line} fill="none" stroke="#0877ff" strokeWidth="3" strokeLinejoin="round" strokeLinecap="round"/>{points.map((p,index)=><g key={p.day}><circle cx={p.x} cy={p.y} r={days>30?2:3.5} fill="white" stroke="#0877ff" strokeWidth="2"><title>{p.label}: {p.count} cadastros</title></circle>{[0,Math.round((days-1)/3),Math.round(2*(days-1)/3),days-1].includes(index)&&<text x={p.x} y="198" textAnchor="middle">{p.label}</text>}</g>)}</svg>:<div className="admin-chart-empty"><span>Nenhum cadastro neste período</span><p>Selecione outro intervalo para acompanhar a evolução do clube.</p></div>}
 <details className="admin-chart-table"><summary>Consultar dados do gráfico</summary><div><table><caption>Cadastros por dia · horário de Fortaleza</caption><thead><tr><th>Data</th><th>Alunos cadastrados</th></tr></thead><tbody>{series.map(d=><tr key={d.day}><td>{d.label}</td><td>{d.count}</td></tr>)}</tbody></table></div></details></div>;
}
