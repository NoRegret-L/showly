// Only recorded, parseable instants qualify; never substitute confirmation time.
export function actualWatchTime(value?:string):string {
  if (!value) { return ''; }
  const at=Date.parse(value);
  return Number.isFinite(at)&&at>0&&at<=Date.now()?new Date(at).toISOString():'';
}
export function missingMemberIds(local:string[],remote:string[]):string[]{
  const known=new Set<string>(remote);
  const seen=new Set<string>();
  const result:string[]=[];
  for(const id of local){
    if(!/^(show|movie):[1-9][0-9]*$/.test(id)||!Number.isSafeInteger(Number(id.substring(id.indexOf(':')+1)))){throw new Error('Invalid member identity');}
    if(!known.has(id)&&!seen.has(id)){seen.add(id);result.push(id);}
  }
  return result;
}
export function membersSatisfied(expected:string[],remote:string[]):boolean{
  const known=new Set<string>(remote);
  return expected.every((id:string)=>known.has(id));
}
