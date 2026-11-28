import { Media } from '../model/Media';
import { ReadCancel } from '../model/ReadFlight';
import { cachedPoster, cachePoster, readDetails, rejectPosterUri } from './TraktDetails';
import { ClientSettings } from './ClientSettings';
// Public, rebuildable artwork data, independent of the authoritative library.
export class CollectionFanartOwner{
  private tasks:Map<string,ReadCancel>=new Map<string,ReadCancel>();
  private attempted:Set<string>=new Set<string>();
  private rows:Map<string,string>=new Map<string,string>();
  clear():void{for(const task of this.tasks.values()){task.cancel();}this.tasks.clear();this.attempted.clear();this.rows.clear();}
  snapshot():Map<string,string>{return new Map<string,string>(this.rows);}
  hide(id:string):void{const task=this.tasks.get(id);if(task){task.cancel();this.tasks.delete(id);}}
  failed(id:string,uri:string):boolean{
    if(this.rows.get(id)!==uri){return false;}
    rejectPosterUri(uri);this.rows.delete(id);return true;
  }
  async visible(item:Media,client:string,dir:string,settings:ClientSettings|undefined,current:()=>boolean,publish:(rows:Map<string,string>)=>void):Promise<void>{
    if(!current()||this.rows.has(item.id)||this.tasks.has(item.id)||this.attempted.has(item.id)){return;}
    const signal=new ReadCancel();this.tasks.set(item.id,signal);
    try{
      let urls=settings?.loadFanartUrls(item.id)??[];
      let uri=await cachedPoster(dir,item,urls,signal,'fanart');signal.check();
      if(!uri&&client){
        if(!urls.length){
          urls=(await readDetails(item,client,false,signal)).fanartUrls??[];signal.check();
          if(urls.length&&current()){try{await settings?.saveFanartUrls(item.id,urls);}catch(error){}}
        }
        if(urls.length){uri=(await cachePoster(dir,item,urls,signal,'fanart')).uri;}
      }
      signal.check();
      if(!current()||this.tasks.get(item.id)!==signal){return;}
      this.attempted.add(item.id);
      if(uri){this.rows.set(item.id,uri);publish(this.snapshot());}
    }catch(error){/* Optional artwork must not fail the business page. */}
    finally{if(this.tasks.get(item.id)===signal){this.tasks.delete(item.id);}}
  }
}
