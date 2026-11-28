export interface RatingTarget{kind:string;id:number;label:string;}
export interface RatingRecord{id:number;value:number;ratedAt?:number;}
export interface RatingSnapshot{known:boolean;activity:string;rows:RatingRecord[];}
export interface RatingState{known:boolean;value:number;ratedAt?:number;pending:boolean;fresh:boolean;}
export interface RatingReceipt{target:RatingTarget;desired:number;before:number;beforeAt?:number;createdAt:number;}
export interface RatingDelta{upserts:RatingRecord[];removed:number[];}
export function ratingKind(kind:string):boolean{return ['show','movie','season','episode'].includes(kind);}
export function validRatingTarget(t:RatingTarget):boolean{return !!t&&ratingKind(t.kind)&&Number.isSafeInteger(t.id)&&t.id>0;}
export function validRatingValue(n:number):boolean{return Number.isInteger(n)&&n>=0&&n<=10;}
export function validRatingRecord(r:RatingRecord):boolean{return !!r&&Number.isSafeInteger(r.id)&&r.id>0&&validRatingValue(r.value)&&r.value>0&&(r.ratedAt===undefined||(Number.isFinite(r.ratedAt)&&r.ratedAt>0));}
export function validRatingRows(rows:RatingRecord[]):boolean{const ids=new Set<number>();for(const r of rows){if(!validRatingRecord(r)||ids.has(r.id)){return false;}ids.add(r.id);}return true;}
export function equalRating(a:RatingRecord|undefined,b:RatingRecord|undefined):boolean{return a?.value===b?.value&&a?.ratedAt===b?.ratedAt;}
export function ratingDelta(old:RatingRecord[],next:RatingRecord[]):RatingDelta{
  const prior=new Map<number,RatingRecord>();for(const r of old){prior.set(r.id,r);}
  const upserts:RatingRecord[]=[];for(const r of next){if(!equalRating(prior.get(r.id),r)){upserts.push(r);}prior.delete(r.id);}
  return {upserts:upserts,removed:Array.from(prior.keys())};
}
export function ratingState(snapshot:RatingSnapshot,id:number,pending:boolean,fresh:boolean):RatingState{
  const row=snapshot.rows.find((r:RatingRecord)=>r.id===id);
  return {known:snapshot.known,value:row?.value??0,ratedAt:row?.ratedAt,pending:pending,fresh:fresh};
}
export function ratingDecision(expected:RatingState,actual:RatingState,desired:number):string{
  if(!validRatingValue(desired)||!actual.known||!actual.fresh||actual.pending){return 'blocked';}
  if(!expected.known||!expected.fresh||expected.pending||expected.value!==actual.value||expected.ratedAt!==actual.ratedAt){return 'conflict';}
  return actual.value===desired?'match':'write';
}
export function receiptSatisfied(receipt:RatingReceipt,state:RatingState):boolean{return state.known&&state.fresh&&state.value===receipt.desired;}
interface RatingIds{trakt:number;}
interface RatingWire{ids:RatingIds;rating?:number;rated_at?:string;}
interface RatingBody{shows?:RatingWire[];movies?:RatingWire[];seasons?:RatingWire[];episodes?:RatingWire[];}
export function ratingBody(t:RatingTarget,value:number,at:number):string{
  if(!validRatingTarget(t)||!validRatingValue(value)||!Number.isFinite(at)||at<=0){throw new Error('Invalid rating intent');}
  const row:RatingWire=value===0?{ids:{trakt:t.id}}:{ids:{trakt:t.id},rating:value,rated_at:new Date(at).toISOString()};
  const body:RatingBody={};if(t.kind==='show'){body.shows=[row];}else if(t.kind==='movie'){body.movies=[row];}else if(t.kind==='season'){body.seasons=[row];}else{body.episodes=[row];}
  return JSON.stringify(body);
}
