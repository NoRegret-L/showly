import { common } from '@kit.AbilityKit';
import { relationalStore } from '@kit.ArkData';
import { http } from '@kit.NetworkKit';
import { PersonRow } from '../model/DetailSections';
import { PersonProfile,PersonCredit,personKey,parsePerson,parsePersonCredits } from '../model/PeopleRules';
import { ConsumerReadFlight,ReadCancel } from '../model/ReadFlight';
import { checkPresentationService,presentationHttpError,traktPresentationService } from './PresentationHttp';
export interface PersonRead{profile:PersonProfile;cached:boolean;}
export interface CreditsRead{rows:PersonCredit[];cached:boolean;}
export class PeopleRepository{
  private db:relationalStore.RdbStore;
  private flights:ConsumerReadFlight<string>=new ConsumerReadFlight<string>();
  constructor(db:relationalStore.RdbStore){this.db=db;}
  private async read(person:PersonRow,lane:string,consumer:ReadCancel):Promise<string>{
    consumer.check();const result=await this.db.querySql('SELECT payload FROM person_section WHERE identity=? AND lane=?',[personKey(person),lane]);
    try{consumer.check();return result.goToFirstRow()?result.getString(0):'';}finally{result.close();}
  }
  private async remote(person:PersonRow,lane:string,client:string,consumer:ReadCancel):Promise<string>{
    const key=personKey(person);
    return this.flights.run(JSON.stringify([client,key,lane]),async(signal:ReadCancel):Promise<string>=>{
      if(!client||!['profile','show:cast','show:crew','movie:cast','movie:crew'].includes(lane)){throw new Error('Invalid person request');}
      const service=traktPresentationService(client);checkPresentationService(service);signal.check();
      const req=http.createHttp();let closed=false;const close=():void=>{if(!closed){closed=true;req.destroy();}};signal.subscribe(close);
      try{
        const suffix=lane==='profile'?'':lane.startsWith('show:')?'/shows':'/movies';
        const response=await req.request('https://api.trakt.tv/people/'+person.personId+suffix+'?extended=full',{method:http.RequestMethod.GET,header:{'Content-Type':'application/json','trakt-api-version':'2','trakt-api-key':client},expectDataType:http.HttpDataType.STRING});
        signal.check();if(response.responseCode!==200||typeof response.result!=='string'){throw presentationHttpError(service,response.responseCode,JSON.stringify(response.header),true);}
        const raw=response.result;if(lane==='profile'){parsePerson(raw,person);}else{parsePersonCredits(raw,lane.startsWith('show:')?'show':'movie',lane.endsWith(':cast'));}
        signal.check();await this.db.executeSql('INSERT OR REPLACE INTO person_section(identity,lane,payload) VALUES(?,?,?)',[key,lane,raw]);signal.check();return raw;
      }finally{signal.unsubscribe(close);close();}
    },consumer);
  }
  async profile(person:PersonRow,client:string,refresh:boolean,consumer:ReadCancel):Promise<PersonRead>{
    const old=await this.read(person,'profile',consumer);
    if(old&&!refresh){try{return {profile:parsePerson(old,person),cached:true};}catch(error){}}
    try{return {profile:parsePerson(await this.remote(person,'profile',client,consumer),person),cached:false};}
    catch(error){consumer.check();if(old){return {profile:parsePerson(old,person),cached:true};}throw new Error('Person unavailable');}
  }
  private async creditsLane(person:PersonRow,kind:string,client:string,refresh:boolean,consumer:ReadCancel):Promise<CreditsRead>{
    const acting=person.department==='Acting',lane=kind+(acting?':cast':':crew'),old=await this.read(person,lane,consumer);
    if(old&&!refresh){try{return {rows:parsePersonCredits(old,kind,acting),cached:true};}catch(error){}}
    try{return {rows:parsePersonCredits(await this.remote(person,lane,client,consumer),kind,acting),cached:false};}
    catch(error){consumer.check();if(old){return {rows:parsePersonCredits(old,kind,acting),cached:true};}throw new Error('Credits unavailable');}
  }
  async credits(person:PersonRow,client:string,refresh:boolean,consumer:ReadCancel):Promise<CreditsRead>{
    const parts=await Promise.all([this.creditsLane(person,'show',client,refresh,consumer),this.creditsLane(person,'movie',client,refresh,consumer)]);
    consumer.check();return {rows:parts[0].rows.concat(parts[1].rows),cached:parts[0].cached||parts[1].cached};
  }
}
let opening:Promise<PeopleRepository>|undefined;
export function openPeople(context:common.UIAbilityContext):Promise<PeopleRepository>{
  if(!opening){opening=relationalStore.getRdbStore(context,{name:'showly_people.db',securityLevel:relationalStore.SecurityLevel.S1}).then(async(db:relationalStore.RdbStore):Promise<PeopleRepository>=>{
    await db.executeSql('CREATE TABLE IF NOT EXISTS person_section(identity TEXT NOT NULL,lane TEXT NOT NULL,payload TEXT NOT NULL,PRIMARY KEY(identity,lane))');
    return new PeopleRepository(db);
  }).catch((error:Error):PeopleRepository=>{opening=undefined;throw error;});}return opening;
}
