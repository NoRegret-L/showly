import { common } from '@kit.AbilityKit';
import { relationalStore } from '@kit.ArkData';
import { CustomList, ListDocument, ListCommand, emptyListDocument, validateListDocument, applyListCommand, replaceRemoteLists } from '../model/CustomLists';
function validScope(scope:string):boolean{return scope==='device'||(scope.startsWith('account:')&&scope.length>8&&scope.trim()===scope);}
// Separate private database. A single SQLite statement atomically commits the
// complete list/member/timestamp document; no sync-table migration or fallback
// to volatile data. Serialize same-scope writers to avoid lost updates.
export class CustomListsRepository{
  private db:relationalStore.RdbStore;
  private tails:Map<string,Promise<void>>=new Map<string,Promise<void>>();
  private docs:Map<string,ListDocument>=new Map<string,ListDocument>();
  constructor(db:relationalStore.RdbStore){this.db=db;}
  async read(scope:string,current:()=>boolean):Promise<ListDocument>{
    if(!validScope(scope)||!current()){throw new Error('List scope changed');}
    const cached=this.docs.get(scope);if(cached){return cached;}
    const result=await this.db.querySql('SELECT payload FROM list_document WHERE scope=?',[scope]);
    try{
      if(!current()){throw new Error('List scope changed');}
      const doc=result.goToFirstRow()?JSON.parse(result.getString(0)) as ListDocument:emptyListDocument();
      if(!validateListDocument(doc)){throw new Error('Invalid local list document');}
      const prior=this.docs.get(scope);if(prior){return prior;}
      this.docs.set(scope,doc);return doc;
    }finally{result.close();}
  }
  private async write(scope:string,current:()=>boolean,mutate:(doc:ListDocument)=>ListDocument):Promise<ListDocument>{
    if(!validScope(scope)||!current()){throw new Error('List scope changed');}
    const prior=this.tails.get(scope)??Promise.resolve();
    const task=prior.catch(()=>{}).then(async():Promise<void>=>{
      const old=await this.read(scope,current),next=mutate(old);
      if(!current()||!validateListDocument(next)){throw new Error('Invalid list commit or account changed');}
      if(next!==old){
        await this.db.executeSql('INSERT OR REPLACE INTO list_document(scope,payload) VALUES(?,?)',[scope,JSON.stringify(next)]);
        // Commit belongs to captured scope even if UI disappears during SQL.
        this.docs.set(scope,next);
      }
    });
    this.tails.set(scope,task);
    try{await task;if(!current()){throw new Error('List scope changed');}return await this.read(scope,current);}
    finally{if(this.tails.get(scope)===task){this.tails.delete(scope);}}
  }
  edit(scope:string,command:ListCommand,current:()=>boolean):Promise<ListDocument>{return this.write(scope,current,(doc:ListDocument)=>applyListCommand(doc,command,Date.now()));}
  importRemote(scope:string,rows:CustomList[],current:()=>boolean):Promise<ListDocument>{
    if(!scope.startsWith('account:')){return Promise.reject(new Error('Verified account required'));}
    return this.write(scope,current,(doc:ListDocument)=>replaceRemoteLists(doc,rows));
  }
  release():void{this.docs.clear();}
}
let opening:Promise<CustomListsRepository>|undefined;
export function openCustomLists(context:common.UIAbilityContext):Promise<CustomListsRepository>{
  if(!opening){opening=relationalStore.getRdbStore(context,{name:'showly_custom_lists.db',securityLevel:relationalStore.SecurityLevel.S1}).then(async(db:relationalStore.RdbStore):Promise<CustomListsRepository>=>{
    await db.executeSql('CREATE TABLE IF NOT EXISTS list_document (scope TEXT PRIMARY KEY,payload TEXT NOT NULL)');return new CustomListsRepository(db);
  }).catch((error:Error):CustomListsRepository=>{opening=undefined;throw error;});}
  return opening;
}
