import { Media } from './Media';
export const MEDIA_GALLERY_LIMIT:number=20;
export const PEOPLE_GALLERY_AGE:number=7*86400000;
export const GALLERY_NEIGHBORS:number=2;
export interface GalleryTarget{item:Media;type:string;tmdb?:number;hints:string[];initialUri:string;}
export interface GalleryImage{url:string;source:string;}
interface WireImage{file_path:string;}
interface WireGallery{id:number;posters?:WireImage[];backdrops?:WireImage[];profiles?:WireImage[];}
export function galleryKey(t:GalleryTarget):string{
 if(!['show','movie','person'].includes(t.item.kind)||!new RegExp('^'+t.item.kind+':[1-9][0-9]*$').test(t.item.id)||!Number.isSafeInteger(Number(t.item.id.substring(t.item.kind.length+1)))||
 (t.item.kind==='person'?t.type!=='profile':!['poster','fanart'].includes(t.type))){throw new Error('Invalid gallery identity');}
 return JSON.stringify([t.item.id,t.type]);
}
export function tmdbArtworkUrl(raw:string):string{
 return /^https:\/\/image\.tmdb\.org\/t\/p\/(?:original|w[1-9][0-9]*)\/[A-Za-z0-9_-]+\.(?:jpg|jpeg|png|webp)$/i.test(raw)?raw:'';
}
export function galleryTraktUrl(raw:string):string{
 const value=raw.trim(),url=/^https:\/\//i.test(value)?'https://'+value.substring(8):value.startsWith('//')?'https:'+value:'https://'+value;
 if(!/^https:\/\/[a-z0-9.-]+\.trakt\.tv\/[A-Za-z0-9._~/-]+(?:\?[A-Za-z0-9._~%=&-]+)?$/i.test(url)||url.split('?')[0].split('/').some((p:string)=>p==='.'||p==='..')){return '';}
 const host=url.substring(8,url.indexOf('/',8)),path=url.substring(url.indexOf('/',8)).split('?')[0];
 return path.startsWith('/images/')||(/^(?:media|walter(?:-[a-z0-9-]+)?)\.trakt\.tv$/i.test(host)&&/\.(?:jpg|jpeg|png|webp)$/i.test(path))?url:'';
}
export function parseGallery(raw:string,id:number,type:string):GalleryImage[]{
 const row=JSON.parse(raw) as WireGallery;if(!row||row.id!==id){throw new Error('Gallery identity mismatch');}
 const input=type==='poster'?row.posters:type==='fanart'?row.backdrops:type==='profile'?row.profiles:undefined;
 if(!Array.isArray(input)){throw new Error('Invalid gallery response');}
 const out:GalleryImage[]=[];for(const r of input){if(typeof r.file_path!=='string'||!/^\/[A-Za-z0-9_-]+\.(jpg|jpeg|png|webp)$/i.test(r.file_path)){continue;}out.push({url:'https://image.tmdb.org/t/p/original'+r.file_path,source:'tmdb'});}return out;
}
export function galleryRows(t:GalleryTarget,initial:GalleryImage|undefined,remote:GalleryImage[],fallback:GalleryImage[]):GalleryImage[]{
 galleryKey(t);const out:GalleryImage[]=[],seen=new Set<string>();
 for(const row of (initial?[initial]:[]).concat(remote,fallback)){
  const url=row.source==='tmdb'?tmdbArtworkUrl(row.url):row.source==='trakt'?galleryTraktUrl(row.url):row.source==='local'&&row.url===t.initialUri?row.url:'';
  if(!url||seen.has(url)){continue;}seen.add(url);out.push({url:url,source:row.source});if(t.item.kind!=='person'&&out.length===MEDIA_GALLERY_LIMIT){break;}
 }return out;
}
export function galleryIndex(rows:GalleryImage[],previous:string):number{const i=rows.findIndex((r:GalleryImage)=>r.url===previous);return i<0?0:i;}
