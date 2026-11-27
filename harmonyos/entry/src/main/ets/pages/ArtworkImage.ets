import { decodeSize } from '../model/ArtworkRules';
// Native Image owns its asynchronous decode, reuse and disposal; no resident
// app-level PixelMap pool. sourceSize expects vp, not physical px. The native
// pipeline applies the density conversion to the actual laid-out component.
@Component
export struct ArtworkImage {
  @Prop uri: string='';
  @Prop widthValue: Length='100%';
  @Prop ratio: number=2/3;
  @Prop corner: number=6;
  @Prop contain: boolean=false;
  @State targetWidth: number=0;
  @State targetHeight: number=0;
  @State failed: string='';
  onFailure: (uri: string)=>void=()=>{};
  @Builder
  decoded(uri: string) {
    Image(uri)
      .width('100%').height('100%')
      .syncLoad(false).autoResize(true)
      .sourceSize({width:this.targetWidth,height:this.targetHeight})
      .objectFit(this.contain?ImageFit.Contain:ImageFit.Cover)
      .onError(()=>{
        if (this.uri===uri && this.failed!==uri) { this.failed=uri; this.onFailure(uri); }
      })
  }
  build() {
    Stack() {
      Text('海报').fontSize(12).fontColor($r('app.color.showly_secondary'))
      if (this.uri && this.failed!==this.uri && this.targetWidth>0 && this.targetHeight>0) {
        this.decoded(this.uri)
      }
    }.width(this.widthValue).aspectRatio(this.ratio)
      .borderRadius(this.corner).clip(true)
      .backgroundColor($r('app.color.showly_placeholder'))
      .onAreaChange((_old: Area,next: Area)=>{
        const size=decodeSize(Number(next.width),Number(next.height));
        if (this.targetWidth!==size.width) { this.targetWidth=size.width; }
        if (this.targetHeight!==size.height) { this.targetHeight=size.height; }
      })
  }
}
