import {useEffect,useState} from 'react';

// Result screens present coins already credited to the wallet; they never play audio.
export function useCoinCelebration(id:string,celebrate:boolean,coins:number){
 const [started,setStarted]=useState<string|null>(null);
 useEffect(()=>{
  setStarted(null);
  if(!celebrate||coins<=0)return;
  const frame=requestAnimationFrame(()=>setStarted(id));
  return()=>cancelAnimationFrame(frame);
 },[id,celebrate,coins]);
 return !celebrate||coins<=0||started===id;
}
