const pointsFormatter=new Intl.NumberFormat('pt-BR',{minimumFractionDigits:2,maximumFractionDigits:2});
export function formatPoints(value:number){return pointsFormatter.format(value);}
