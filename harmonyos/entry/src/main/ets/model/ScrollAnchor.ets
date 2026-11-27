// A navigation anchor is a few scalars, not a retained list or media payload.
// The native List has one header item before the virtual data source.
export interface ScrollRows {
  totalCount(): number;
  idAt(index: number): string;
  indexOfId(id: string): number;
}
export interface ScrollAnchor {
  context: string;
  id: string;
  index: number;
  offset: number;
}
export interface ScrollTarget { index: number; offset: number; }
export function captureAnchor(context: string,rows: ScrollRows,index: number,offset: number): ScrollAnchor {
  const at=Math.max(0,index);
  return {context:context,id:at>0?rows.idAt(at-1):'',index:at,offset:Number.isFinite(offset)?offset:0};
}
export function resolveAnchor(anchor: ScrollAnchor,context: string,rows: ScrollRows): ScrollTarget | undefined {
  if (anchor.context!==context || (anchor.index>0 && !rows.totalCount())) { return undefined; }
  if (!anchor.index) { return {index:0,offset:anchor.offset}; }
  const found=rows.indexOfId(anchor.id);
  // Preserve identity across inserts/reorders. If the item was removed,
  // use its nearest surviving ordinal, not the top of the list.
  return {index:found>=0?found+1:Math.min(anchor.index,rows.totalCount()),offset:anchor.offset};
}
export class ScrollAnchors {
  private anchors: Map<string,ScrollAnchor>=new Map<string,ScrollAnchor>();
  save(slot: string,anchor: ScrollAnchor): void { this.anchors.set(slot,anchor); }
  has(slot: string): boolean { return this.anchors.has(slot); }
  pending(slot: string,context: string): ScrollAnchor | undefined {
    const anchor=this.anchors.get(slot);
    if (anchor && anchor.context!==context) { this.anchors.delete(slot); return undefined; }
    return anchor;
  }
  consume(slot: string,anchor: ScrollAnchor): void { if (this.anchors.get(slot)===anchor) { this.anchors.delete(slot); } }
  clear(): void { this.anchors.clear(); }
}
