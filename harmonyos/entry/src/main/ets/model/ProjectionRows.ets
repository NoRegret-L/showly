// A complete ordered result is still published as an array. The unchanged
// objects are retained; changed rows are supplied by the same full resolver.
export function replaceProjectionRows<T>(prior:T[],delta:T[],ids:Set<string>,idOf:(row:T)=>string):T[]{
  const replacements=new Map<string,T>();
  for(const row of delta){replacements.set(idOf(row),row);}
  const result:T[]=[];
  for(const row of prior){
    const id=idOf(row);
    if(!ids.has(id)){result.push(row);}
    else {const next=replacements.get(id);if(next!==undefined){result.push(next);}}
  }
  return result;
}
export function sameProjectionMembers<T>(rows:T[],ids:Set<string>,idOf:(row:T)=>string):boolean{
  if(rows.length!==ids.size){return false;}
  const seen=new Set<string>();
  for(const row of rows){const id=idOf(row);if(!ids.has(id)||seen.has(id)){return false;}seen.add(id);}
  return true;
}
export function utf8ProjectionBytes(raw:string):number{
  let bytes=0;
  for(let i=0;i<raw.length;i++){
    const c=raw.charCodeAt(i);
    if(c<0x80){bytes++;}
    else if(c<0x800){bytes+=2;}
    else if(c>=0xd800&&c<=0xdbff&&i+1<raw.length&&raw.charCodeAt(i+1)>=0xdc00&&raw.charCodeAt(i+1)<=0xdfff){bytes+=4;i++;}
    else{bytes+=3;}
  }
  return bytes;
}

// Full union source precedence: explicit records, watchlist, remote shows,
// then local catalog IDs in SQLite's lexical order. A rank only exists for
// the first three stable sources. Scope excludes movies from projection rows.
export class ProjectionMemberOrder{
  private ranks:Map<string,number>=new Map<string,number>();
  seed(records:string[],queue:string[],remote:string[]):void{
    this.ranks.clear();
    for(const ids of [records,queue,remote]){for(const id of ids){if(!this.ranks.has(id)){this.ranks.set(id,this.ranks.size);}}}
  }
  compare(a:string,b:string):number{
    const x=this.ranks.get(a),y=this.ranks.get(b);
    if(x!==undefined&&y!==undefined){return x-y;}
    if(x!==undefined){return -1;}if(y!==undefined){return 1;}
    return a<b?-1:a>b?1:0;
  }
}
export function mergeProjectionMembers<T>(prior:T[],delta:T[],ids:Set<string>,idOf:(row:T)=>string,order:ProjectionMemberOrder):T[]{
  const kept=prior.filter((row:T)=>!ids.has(idOf(row)));
  const changes=delta.slice().sort((a:T,b:T)=>order.compare(idOf(a),idOf(b)));
  const result:T[]=[];let i=0,j=0;
  while(i<kept.length&&j<changes.length){
    if(order.compare(idOf(kept[i]),idOf(changes[j]))<0){result.push(kept[i++]);}
    else{result.push(changes[j++]);}
  }
  while(i<kept.length){result.push(kept[i++]);}
  while(j<changes.length){result.push(changes[j++]);}
  return result;
}
export function scopedProjectionMembers<T>(rows:T[],ids:Set<string>,idOf:(row:T)=>string):boolean{
  const seen=new Set<string>();
  for(const row of rows){const id=idOf(row);if(!ids.has(id)||seen.has(id)){return false;}seen.add(id);}
  return true;
}
