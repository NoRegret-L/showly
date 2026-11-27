// Original Android TmdbImage ranking and provider fallback semantics. This
// module performs no network I/O; callers must supply legally obtained candidates.
export interface ArtworkCandidate {
  source: string; type: string; path: string; language: string | null; average: number; votes: number;
}
export interface ArtworkOptions {
  custom?: ArtworkCandidate; posters: ArtworkCandidate[]; backdrops: ArtworkCandidate[];
  aws?: ArtworkCandidate; episode?: ArtworkCandidate;
}
export interface DecodeSize { width: number; height: number; }
export function artworkIdentity(source: string,type: string,mediaId: string,url: string): string {
  return JSON.stringify([source,type,mediaId,url]);
}
export function legacyPosterName(url: string): string {
  const path=url.split('?')[0]; return path.substring(path.lastIndexOf('/')+1);
}
export function decodeSize(width: number,height: number): DecodeSize {
  return {width:Number.isFinite(width)&&width>0?Math.ceil(width):0,height:Number.isFinite(height)&&height>0?Math.ceil(height):0};
}
export function voteScore(candidate: ArtworkCandidate): number {
  const n=candidate.votes;
  if (!Number.isFinite(n) || n<=0 || !Number.isFinite(candidate.average) || candidate.average<0 || candidate.average>10) { return 0; }
  const z=1.96; // exact upstream 95% Wilson lower confidence bound
  const p=candidate.average/10;
  return (p+z*z/(2*n)-z*Math.sqrt((p*(1-p)+z*z/(4*n))/n))/(1+z*z/n);
}
function languageRank(candidate: ArtworkCandidate,language: string,type: string): number[] {
  const same=candidate.language===language?1:0,english=candidate.language==='en'?1:0,plain=candidate.language===null?1:0;
  return type==='poster'?[same,english,plain]:[plain,same,english];
}
export function bestArtwork(rows: ArtworkCandidate[],language: string,type: string): ArtworkCandidate | undefined {
  let best: ArtworkCandidate | undefined;
  for (const row of rows) {
    if (!best) { best=row; continue; }
    const x=languageRank(row,language,type),y=languageRank(best,language,type);
    let cmp=0;
    for(let i=0;i<x.length;i++){ if(x[i]!==y[i]) {cmp=x[i]-y[i];break;} }
    if(cmp>0 || (cmp===0 && voteScore(row)>voteScore(best))) { best=row; }
  }
  return best;
}
export function chooseArtwork(kind: string,type: string,language: string,options: ArtworkOptions): ArtworkCandidate | undefined {
  if (options.custom?.source==='custom' && options.custom.type===type) { return options.custom; }
  if (type==='poster') {
    return bestArtwork(options.posters,language,type) ?? (kind==='show' ? bestArtwork(options.backdrops,language,type) ?? options.aws : undefined);
  }
  return bestArtwork(options.backdrops,language,type) ?? (kind==='show' ? options.aws ?? options.episode : undefined);
}

export function episodeLookupNumbers(number: number,absolute?: number): number[] {
  return absolute!==undefined && Number.isSafeInteger(absolute) && absolute>0 && absolute!==number ? [number,absolute] : [number];
}
// One recovery transition per URI, then wait for an explicit retry or new
// residency. This is a state-machine termination rule, not a time threshold.
export class ArtworkRecovery {
  private attempted: Set<string>=new Set<string>();
  private blocked: Set<string>=new Set<string>();
  reject(mediaId: string,uri: string): boolean {
    const key=JSON.stringify([mediaId,uri]);
    if (this.attempted.has(key)) { this.blocked.add(mediaId); return false; }
    this.attempted.add(key); return true;
  }
  allowed(mediaId: string): boolean { return !this.blocked.has(mediaId); }
  clear(): void { this.attempted.clear(); this.blocked.clear(); }
}
