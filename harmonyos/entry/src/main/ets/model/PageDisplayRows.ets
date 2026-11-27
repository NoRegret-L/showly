import { LazyRows } from './LazyRows';
import { ListDiffInput,ListEdit } from './ListDiff';
// Scope and publication generation belong to each derived display owner;
// global account/transaction validation remains in the coordinator.
export class PageDisplayRows<T> extends LazyRows<T> {
  private scope:string='';
  private generation:number=0;
  constructor(dependenciesOf?: (row:T)=>string[]){super(dependenciesOf);}
  activate(scope:string):void {
    if(this.scope===scope){return;}
    this.scope=scope;this.generation++;super.replace([],[],[]);
  }
  replace(rows:T[],ids:string[],keys:string[]):void {
    this.generation++;super.replace(rows,ids,keys);
  }
  async submit(rows:T[],ids:string[],keys:string[],differ:(input:ListDiffInput)=>Promise<ListEdit[]>,current:()=>boolean):Promise<boolean>{
    const generation=++this.generation;
    return super.submit(rows,ids,keys,differ,()=>generation===this.generation&&current());
  }
}
