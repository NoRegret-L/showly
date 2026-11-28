import { common } from '@kit.AbilityKit';
import { picker,fileIo } from '@kit.CoreFileKit';
import { buffer } from '@kit.ArkTS';
import { sha256,readFile } from './LocalBackup';
import { ListDocument } from '../model/CustomLists';
import { validStorageDocument,localListBackup } from '../model/ListPersistence';
interface ListEnvelope{format:string;sha256:string;payload:string;}
const FORMAT='showly-local-lists-v1';
async function decode(raw:string):Promise<ListDocument>{
  const e=JSON.parse(raw) as ListEnvelope;
  if(!e||e.format!==FORMAT||typeof e.payload!=='string'||typeof e.sha256!=='string'||await sha256(e.payload)!==e.sha256){throw new Error('Invalid list backup checksum');}
  const doc=JSON.parse(e.payload) as ListDocument;if(!validStorageDocument(doc)||doc.remote.length){throw new Error('Invalid local list backup');}
  return localListBackup(doc);
}
export async function exportCustomListBackup(context:common.UIAbilityContext,doc:ListDocument):Promise<boolean>{
  const payload=JSON.stringify(localListBackup(doc)),e:ListEnvelope={format:FORMAT,sha256:await sha256(payload),payload:payload},raw=JSON.stringify(e),size=buffer.from(raw,'utf-8').length;
  if(size>32*1024*1024){throw new Error('List backup exceeds 32 MiB');}
  const opts=new picker.DocumentSaveOptions();opts.newFileNames=['Showly-Lists-'+Date.now()+'.json'];const uris=await new picker.DocumentViewPicker(context).save(opts);
  if(!uris.length){return false;}if(uris.length!==1){throw new Error('Invalid selection');}
  const file=fileIo.openSync(uris[0],fileIo.OpenMode.READ_WRITE|fileIo.OpenMode.TRUNC);
  try{if(await fileIo.write(file.fd,raw)!==size||fileIo.statSync(file.fd).size!==size){throw new Error('Incomplete list backup');}fileIo.fsyncSync(file.fd);}finally{fileIo.closeSync(file);}
  const check=await readFile(uris[0]);if(check!==raw){throw new Error('List backup readback mismatch');}await decode(check);return true;
}
export async function selectCustomListBackup(context:common.UIAbilityContext):Promise<ListDocument|undefined>{
  const opts=new picker.DocumentSelectOptions();opts.maxSelectNumber=1;const uris=await new picker.DocumentViewPicker(context).select(opts);
  if(!uris.length){return undefined;}if(uris.length!==1){throw new Error('Invalid selection');}return decode(await readFile(uris[0]));
}
