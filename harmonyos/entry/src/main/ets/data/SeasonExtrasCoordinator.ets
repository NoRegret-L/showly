import { Media } from '../model/Media';
import { SeasonPresentationOwner, parseSeasonPresentation } from '../model/SeasonPresentation';
import { ReadCancel } from '../model/ReadFlight';
import { PresentationRepository } from './PresentationRepository';
import { readSeasonPresentation } from './DetailSectionsRepository';
import { readPartRatings, CloudLibrary } from './TraktLibrary';
import { traktAuth } from './TraktAuth';
export class SeasonExtrasCoordinator{
  readonly presentation:SeasonPresentationOwner=new SeasonPresentationOwner();
  publicStatus:string='';ratingStatus:string='';
  private publicBusy:boolean=false;private ratingBusy:boolean=false;private generation:number=0;
  clear():void{this.generation++;this.presentation.clear();this.publicStatus='';this.ratingStatus='';this.publicBusy=false;this.ratingBusy=false;}
  async load(item:Media,client:string,scope:string,consumer:ReadCancel,repository:PresentationRepository|undefined,refresh:boolean,source:()=>CloudLibrary|undefined,ratingScope:()=>string,canRate:()=>boolean,allowed:()=>boolean,publish:()=>void):Promise<void>{
    const generation=this.generation,current=():boolean=>generation===this.generation&&allowed()&&!consumer.cancelled();
    if(!current()){return;}
    if(!this.publicBusy){
      this.publicBusy=true;this.publicStatus='正在读取季集资料…';publish();
      try{
        let raw='';
        try{raw=await repository?.readDetailSection(item,'seasons-trakt',consumer)??'';}catch(error){consumer.check();}
        if(!current()){return;}
        let cached=false;
        if(raw){try{this.presentation.replace(scope,parseSeasonPresentation(raw));cached=true;this.publicStatus='本地季集资料';publish();}catch(error){}}
        if(client&&(!cached||refresh)){
          const network=await readSeasonPresentation(item,client,consumer);if(!current()){return;}
          this.presentation.replace(scope,parseSeasonPresentation(network));this.publicStatus='';publish();
          try{await repository?.saveDetailSection(item,'seasons-trakt',network,consumer);}catch(error){}
        }else if(!cached){this.publicStatus='离线季集资料不可用';}
      }catch(error){if(current()){this.publicStatus='季集资料读取失败，可重试';}}
      finally{if(current()){this.publicBusy=false;publish();}}
    }
    if(!current()||this.ratingBusy){return;}
    const session=traktAuth.session(client),snapshot=source(),rating=ratingScope();
    if(!snapshot||!session||!canRate()){this.presentation.clearRatings();this.ratingStatus='个人评分需验证账户';publish();return;}
    this.ratingBusy=true;this.presentation.clearRatings();this.ratingStatus='正在读取个人评分…';publish();
    try{
      const seasons=await readPartRatings(session,'seasons',snapshot.activity),episodes=await readPartRatings(session,'episodes',snapshot.activity);
      if(current()&&rating===ratingScope()&&snapshot===source()&&traktAuth.isCurrent(session.clientId,session.generation)){
        this.presentation.setRatings(scope,rating,seasons,episodes);this.ratingStatus='';
      }
    }catch(error){if(current()){this.ratingStatus='个人评分读取失败，可重试';}}
    finally{if(current()){this.ratingBusy=false;publish();}}
  }
}
