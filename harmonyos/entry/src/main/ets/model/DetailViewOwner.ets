import { CollectionSpoilers, defaultCollectionSpoilers } from './CollectionViewOwner';
// Derived page state. No authority, tokens or durable writes are owned here.
export interface DetailSnapshot<T> {
  revision:number; summary?:T; summaryBusy:boolean; summaryStatus:string;
  fanart:string; artBusy:boolean; artStatus:string;
  rating?:number; ratingBusy:boolean; ratingStatus:string;
  spoilers:CollectionSpoilers; descriptionRevealed:boolean; ratingRevealed:boolean;
}
export function emptyDetail<T>():DetailSnapshot<T>{
  return {revision:0,summaryBusy:false,summaryStatus:'',fanart:'',artBusy:false,artStatus:'',
    ratingBusy:false,ratingStatus:'',spoilers:defaultCollectionSpoilers(),descriptionRevealed:false,ratingRevealed:false};
}
export class DetailViewOwner<T>{
  private scope:string='';private id:string='';private generation:number=0;
  private value:DetailSnapshot<T>=emptyDetail<T>();
  begin(scope:string,id:string,spoilers:CollectionSpoilers):number{
    this.clear();this.scope=scope;this.id=id;
    this.value.spoilers={description:spoilers.description,rating:spoilers.rating,reveal:spoilers.reveal};
    return this.generation;
  }
  token():number{return this.generation;}
  current(token:number,scope:string,id:string):boolean{return token===this.generation&&scope===this.scope&&id===this.id&&!!id;}
  snapshot():DetailSnapshot<T>{return this.value;}
  clear():void{this.generation++;this.scope='';this.id='';this.value=emptyDetail<T>();}
  private next():DetailSnapshot<T>{
    const v=this.value;
    return {revision:v.revision+1,summary:v.summary,summaryBusy:v.summaryBusy,summaryStatus:v.summaryStatus,
      fanart:v.fanart,artBusy:v.artBusy,artStatus:v.artStatus,rating:v.rating,ratingBusy:v.ratingBusy,ratingStatus:v.ratingStatus,
      spoilers:v.spoilers,descriptionRevealed:v.descriptionRevealed,ratingRevealed:v.ratingRevealed};
  }
  summary(token:number,value:T|undefined,busy:boolean,status:string):void{
    if(token!==this.generation||!this.id){return;}
    const v=this.value;if(v.summary===value&&v.summaryBusy===busy&&v.summaryStatus===status){return;}
    const next=this.next();next.summary=value;next.summaryBusy=busy;next.summaryStatus=status;this.value=next;
  }
  artwork(token:number,uri:string,busy:boolean,status:string):void{
    if(token!==this.generation||!this.id){return;}
    const v=this.value;if(v.fanart===uri&&v.artBusy===busy&&v.artStatus===status){return;}
    const next=this.next();next.fanart=uri;next.artBusy=busy;next.artStatus=status;this.value=next;
  }
  personalRating(token:number,rating:number|undefined,busy:boolean,status:string):void{
    if(token!==this.generation||!this.id){return;}
    const v=this.value;if(v.rating===rating&&v.ratingBusy===busy&&v.ratingStatus===status){return;}
    const next=this.next();next.rating=rating;next.ratingBusy=busy;next.ratingStatus=status;this.value=next;
  }
  setSpoilers(token:number,settings:CollectionSpoilers):void{
    if(token!==this.generation||!this.id){return;}
    const next=this.next();next.spoilers={description:settings.description,rating:settings.rating,reveal:settings.reveal};
    next.descriptionRevealed=false;next.ratingRevealed=false;this.value=next;
  }
  reveal(token:number,field:string):void{
    if(token!==this.generation||!this.id||!this.value.spoilers.reveal){return;}
    const next=this.next();
    if(field==='description'&&!next.descriptionRevealed){next.descriptionRevealed=true;}
    else if(field==='rating'&&!next.ratingRevealed){next.ratingRevealed=true;}
    else{return;}
    this.value=next;
  }
}
