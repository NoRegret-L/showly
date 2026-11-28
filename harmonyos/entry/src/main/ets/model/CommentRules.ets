export interface CommentTarget{kind:string;id:number;showId?:number;season?:number;episode?:number;label:string;}
export interface CommentRow{id:number;parent:number;text:string;spoiler:boolean;rating:number;replies:number;created:number;updated:number;username:string;avatar:string;uuid:string;}
interface UserIds{uuid?:string;}
interface Avatar{full?:string;}
interface UserImages{avatar?:Avatar;}
interface WireUser{username?:string;ids?:UserIds;images?:UserImages;}
interface WireComment{id:number;parent_id?:number;comment:string;spoiler?:boolean;user_rating?:number;replies?:number;created_at?:string;updated_at?:string;user?:WireUser;}
interface Ids{trakt:number;}
interface Subject{ids:Ids;}
interface PostBody{show?:Subject;movie?:Subject;episode?:Subject;comment:string;spoiler:boolean;}
export interface CommentPage{rows:CommentRow[];next:number;cached:boolean;}
export interface CommentReceipt{action:string;target:string;parent:number;id:number;created:number;}
export function positiveCommentId(n:number):boolean{return Number.isSafeInteger(n)&&n>0;}
export function targetKey(t:CommentTarget):string{
 if(!positiveCommentId(t.id)||!['show','movie','episode'].includes(t.kind)){throw new Error('Invalid comment subject');}
 if(t.kind==='episode'&&(!positiveCommentId(t.showId??0)||!Number.isSafeInteger(t.season)||t.season===undefined||t.season<0||!positiveCommentId(t.episode??0))){throw new Error('Invalid episode route');}
 return t.kind+':'+t.id;
}
export function commentPath(t:CommentTarget):string{targetKey(t);return t.kind==='episode'?'shows/'+t.showId+'/seasons/'+t.season+'/episodes/'+t.episode+'/comments/newest':(t.kind==='show'?'shows/':'movies/')+t.id+'/comments/newest';}
export function commentLimit(t:CommentTarget):number{return t.kind==='episode'?50:100;}
export function validComment(text:string):boolean{return text.trim().split(' ').filter((w:string)=>!w.startsWith('@')&&w.length>1).length>=5;}
export function hasSpoiler(row:CommentRow):boolean{return row.spoiler||row.text.toLowerCase().includes('spoiler');}
export function ownComment(row:CommentRow,uuid:string,username:string):boolean{return !!uuid&&!!username&&(row.uuid?row.uuid===uuid:row.username===username);}
export function canDeleteComment(row:CommentRow,uuid:string,username:string,now:number):boolean{return ownComment(row,uuid,username)&&row.replies===0&&row.created>0&&now>=row.created&&now-row.created<13*86400000;}
function safeAvatar(value?:string):string{return typeof value==='string'&&/^https:\/\/(?:walter-r2\.trakt\.tv|walter\.trakt\.tv|images\.trakt\.tv|www\.gravatar\.com|secure\.gravatar\.com)\/[A-Za-z0-9/._?=&%-]+$/.test(value)?value:'';}
function instant(s?:string):number{const n=Date.parse(s??'');return Number.isFinite(n)&&n>0?n:0;}
export function parseComment(raw:string):CommentRow{
 const w=JSON.parse(raw) as WireComment;if(!w||!positiveCommentId(w.id)||typeof w.comment!=='string'||!w.user||typeof w.user.username!=='string'||!w.user.username||!Number.isSafeInteger(w.replies)||w.replies===undefined||w.replies<0){throw new Error('Invalid comment row');}
 const p=w.parent_id??0;if(!Number.isSafeInteger(p)||p< -1){throw new Error('Invalid parent');}
 return {id:w.id,parent:p>0?p:0,text:w.comment,spoiler:w.spoiler===true,rating:Number.isInteger(w.user_rating)&&w.user_rating!==undefined&&w.user_rating>=1&&w.user_rating<=10?w.user_rating:0,replies:w.replies,created:instant(w.created_at),updated:instant(w.updated_at),username:w.user.username,uuid:w.user.ids?.uuid??'',avatar:safeAvatar(w.user.images?.avatar?.full)};
}
export function parseComments(raw:string,parent:number):CommentRow[]{
 const rows=JSON.parse(raw) as WireComment[];if(!Array.isArray(rows)){throw new Error('Invalid comment page');}
 const out:CommentRow[]=[],seen=new Set<number>();for(const item of rows){const r=parseComment(JSON.stringify(item));if(r.parent!==parent){if(parent===0){continue;}throw new Error('Reply parent mismatch');}if(!seen.has(r.id)){seen.add(r.id);out.push(r);}}return out;
}
export function postBody(t:CommentTarget,parent:number,text:string,spoiler:boolean):string{
 targetKey(t);if(!validComment(text)||!Number.isSafeInteger(parent)||parent<0){throw new Error('Invalid comment intent');}
 const body:PostBody={comment:text.trim(),spoiler:spoiler};if(!parent){const subject:Subject={ids:{trakt:t.id}};if(t.kind==='show'){body.show=subject;}else if(t.kind==='movie'){body.movie=subject;}else{body.episode=subject;}}return JSON.stringify(body);
}
export function nextCommentPage(page:number,headers:string):number{
 const data=JSON.parse(headers) as Record<string,string>;let count=0,actual=0;
 for(const key of Object.keys(data)){if(key.toLowerCase()==='x-pagination-page-count'){count=Number(data[key]);}if(key.toLowerCase()==='x-pagination-page'){actual=Number(data[key]);}}
 return Number.isSafeInteger(count)&&Number.isSafeInteger(actual)&&actual===page&&count>page?page+1:0;
}
export class CommentIndex{
 private roots:Map<number,CommentRow>=new Map<number,CommentRow>();private children:Map<number,Map<number,CommentRow>>=new Map<number,Map<number,CommentRow>>();
 private revealed:Map<number,string>=new Map<number,string>();
 revision:number=0;
 clear():void{this.roots.clear();this.children.clear();this.revealed.clear();this.revision++;}
 append(rows:CommentRow[],parent:number):void{
  let map=this.roots;if(parent){if(!this.roots.has(parent)){throw new Error('Missing parent');}let children=this.children.get(parent);if(!children){children=new Map<number,CommentRow>();this.children.set(parent,children);}map=children;}
  for(const row of rows){if(row.parent!==parent){throw new Error('Parent mismatch');}const previous=map.get(row.id);if(previous&&previous.text!==row.text){this.revealed.delete(row.id);}map.set(row.id,row);}this.revision++;
 }
 loaded(parent:number):boolean{return this.children.has(parent);}
 reveal(row:CommentRow):void{this.revealed.set(row.id,row.text);}
 isRevealed(row:CommentRow):boolean{return this.revealed.get(row.id)===row.text;}
 project(uuid:string,username:string):CommentRow[]{
  const mine:CommentRow[]=[],others:CommentRow[]=[];for(const r of this.roots.values()){(ownComment(r,uuid,username)?mine:others).push(r);}
  const out:CommentRow[]=[];for(const r of mine.concat(others)){out.push(r);const replies=this.children.get(r.id);if(replies){out.push(...Array.from(replies.values()).sort((a:CommentRow,b:CommentRow)=>a.created-b.created));}}return out;
 }
 remove(row:CommentRow):void{if(row.parent){this.children.get(row.parent)?.delete(row.id);}else{this.roots.delete(row.id);this.children.delete(row.id);}this.revealed.delete(row.id);this.revision++;}
}
