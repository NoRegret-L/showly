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
