type Answer={questionId:number;selected:number;version:number};
/** Serialize saves while allowing the child to continue to the next question. */
export class AnswerSaveQueue<T>{
 private answers=new Map<number,Answer>();
 private version=0;
 private task:Promise<void>|null=null;
 private closed=false;
 error:Error|null=null;
 constructor(private send:(questionId:number,selected:number)=>Promise<T>,private saved:(result:T,pending:Record<string,number>)=>void,private changed:()=>void){}
 get pending(){return this.answers.size>0;}
 drafts(){return Object.fromEntries([...this.answers.values()].map(a=>[a.questionId,a.selected]));}
 enqueue(questionId:number,selected:number){
  if(this.closed)return;
  this.answers.set(questionId,{questionId,selected,version:++this.version});this.error=null;this.changed();void this.run();
 }
 private run():Promise<void>{
  if(this.task)return this.task;
  this.task=(async()=>{
   while(!this.closed&&this.answers.size&&!this.error){
    const answer=this.answers.values().next().value!;
    let result:T;
    try{result=await this.send(answer.questionId,answer.selected);}
    catch(error){if(!this.closed){this.error=error instanceof Error?error:new Error('Não foi possível salvar a resposta.');this.changed();}return;}
    if(this.closed)return;
    if(this.answers.get(answer.questionId)?.version===answer.version)this.answers.delete(answer.questionId);
    this.saved(result,this.drafts());this.changed();
   }
  })().finally(()=>{this.task=null;});
  return this.task;
 }
 async flush(){while(!this.closed&&this.pending){if(this.error)throw this.error;await this.run();}if(this.error)throw this.error;}
 async retry(){if(this.closed)return;this.error=null;this.changed();await this.flush();}
 dispose(){this.closed=true;this.answers.clear();}
}
