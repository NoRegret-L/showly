import { parseSeasonPresentation } from '../model/SeasonPresentation';
import { http } from '@kit.NetworkKit';
import { Media } from '../model/Media';
import { ReadCancel, ConsumerReadFlight } from '../model/ReadFlight';
import { CreditResponse, CreditRow, CreditCrew, PersonRow, RelatedRow, RelatedWire, projectPeople, parseRelated } from '../model/DetailSections';
import { checkPresentationService, presentationHttpError, traktPresentationService } from './PresentationHttp';
import { canReadDetails } from './TraktDetails';
interface PersonIds {trakt:number;tmdb?:number;}
interface PersonImages {headshot?:string[];}
interface WirePerson {name:string;ids:PersonIds;images?:PersonImages;}
interface WireCredit {person:WirePerson;character?:string;characters?:string[];job?:string;jobs?:string[];}
interface WireCrew {directing?:WireCredit[];writing?:WireCredit[];sound?:WireCredit[];}
interface WirePeople {cast?:WireCredit[];crew?:WireCrew;}
const peopleFlights=new ConsumerReadFlight<PersonRow[]>();
const relatedFlights=new ConsumerReadFlight<RelatedRow[]>();
const seasonFlights=new ConsumerReadFlight<string>();
function mapCredits(rows:WireCredit[]):CreditRow[]{
  return rows.filter((r:WireCredit)=>!!r.person?.ids).map((r:WireCredit):CreditRow=>({person:{id:r.person.ids.trakt,tmdb:r.person.ids.tmdb,name:r.person.name,headshots:r.person.images?.headshot},character:r.character,characters:r.characters,job:r.job,jobs:r.jobs}));
}
async function fetchPublic(item:Media,client:string,section:string,scope:ReadCancel):Promise<string>{
  if(!canReadDetails(item)||!client||!['people','related','seasons'].includes(section)){throw new Error('Invalid detail section');}
  const service=traktPresentationService(client);checkPresentationService(service);scope.check();
  const request=http.createHttp();let closed=false;
  const close=():void=>{if(!closed){closed=true;request.destroy();}};
  scope.subscribe(close);
  try{
    scope.check();
    const response=await request.request('https://api.trakt.tv/'+(item.kind==='show'?'shows/':'movies/')+item.id.substring(item.kind.length+1)+'/'+section+(section==='seasons'?'?extended=full,episodes':'?extended=full'),{
      method:http.RequestMethod.GET,header:{'Content-Type':'application/json','trakt-api-version':'2','trakt-api-key':client,'User-Agent':'Showly-HarmonyOS-Personal/0.7.0'},expectDataType:http.HttpDataType.STRING});
    scope.check();
    if(response.responseCode!==200||typeof response.result!=='string'){throw presentationHttpError(service,response.responseCode,JSON.stringify(response.header),true);}
    return response.result;
  }finally{scope.unsubscribe(close);close();}
}
export function readPeople(item:Media,client:string,consumer:ReadCancel):Promise<PersonRow[]>{
  return peopleFlights.run(JSON.stringify([client,item.id]),async(scope:ReadCancel):Promise<PersonRow[]>=>{
    const data=JSON.parse(await fetchPublic(item,client,'people',scope)) as WirePeople;
    if(!data||(!Array.isArray(data.cast)&&!data.crew)){throw new Error('Invalid people response');}
    const crew:CreditCrew={directing:mapCredits(data.crew?.directing??[]),writing:mapCredits(data.crew?.writing??[]),sound:mapCredits(data.crew?.sound??[])};
    const input:CreditResponse={cast:mapCredits(data.cast??[]),crew:crew};return projectPeople(input,true);
  },consumer);
}
export function readRelated(item:Media,client:string,consumer:ReadCancel):Promise<RelatedRow[]>{
  return relatedFlights.run(JSON.stringify([client,item.id]),async(scope:ReadCancel):Promise<RelatedRow[]>=>{
    const rows=JSON.parse(await fetchPublic(item,client,'related',scope)) as RelatedWire[];
    if(!Array.isArray(rows)){throw new Error('Invalid related response');}return parseRelated(rows,item.kind);
  },consumer);
}

export function readSeasonPresentation(item:Media,client:string,consumer:ReadCancel):Promise<string>{
  return seasonFlights.run(JSON.stringify([client,item.id]),async(scope:ReadCancel):Promise<string>=>{
    const raw=await fetchPublic(item,client,'seasons',scope);parseSeasonPresentation(raw);return raw;
  },consumer);
}
