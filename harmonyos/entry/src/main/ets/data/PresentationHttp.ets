import { PresentationGate, PresentationFailure, httpPresentationFailure } from '../model/PresentationPolicy';
export const presentationGate: PresentationGate=new PresentationGate();
export function traktPresentationService(client: string): string { return 'trakt:'+client; }
export function checkPresentationService(service: string): void { presentationGate.check(service,Date.now()); }
export function presentationHttpError(service: string,status: number,rawHeaders: string,auth: boolean): PresentationFailure {
  let retry='';
  try {
    const headers=JSON.parse(rawHeaders) as Record<string,string>;
    for (const name of Object.keys(headers)) {
      if (name.toLowerCase()==='retry-after') { retry=String(headers[name]); break; }
    }
  } catch (error) {}
  const failure=httpPresentationFailure(status,retry,Date.now());
  presentationGate.record(service,failure,auth);
  return failure;
}
