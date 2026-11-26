@Entry
@Component
struct Index {
  @State title: string = '';
  @State queue: string[] = [];
  @State watched: string[] = [];

  build() {
    Scroll() {
      Column({ space: 16 }) {
        Text('Showly Preview').fontSize(30).fontWeight(FontWeight.Bold)
        Text('非官方鸿蒙原生构建预览').fontSize(16)
        Text('当前仅支持临时手动追剧列表；退出应用后不保留数据，尚未连接 Trakt。')
          .fontSize(14).fontColor('#687887')
        TextInput({ placeholder: '输入电影或剧集名称', text: this.title })
          .onChange((value: string) => { this.title = value; })
        Button('加入待看')
          .enabled(this.title.trim().length > 0)
          .onClick(() => {
            const value: string = this.title.trim();
            if (value.length > 0 && !this.queue.includes(value) && !this.watched.includes(value)) {
              this.queue = [...this.queue, value];
            }
            this.title = '';
          })
        Text('待看 (' + this.queue.length + ')').fontSize(20).fontWeight(FontWeight.Medium)
        ForEach(this.queue, (item: string) => {
          Row({ space: 8 }) {
            Text(item).layoutWeight(1)
            Button('已看').onClick(() => {
              this.queue = this.queue.filter((value: string) => value !== item);
              this.watched = [...this.watched, item];
            })
          }.width('100%')
        }, (item: string) => item)
        Text('已看 (' + this.watched.length + ')').fontSize(20).fontWeight(FontWeight.Medium)
        ForEach(this.watched, (item: string) => {
          Row({ space: 8 }) {
            Text(item).layoutWeight(1)
            Button('撤销').onClick(() => {
              this.watched = this.watched.filter((value: string) => value !== item);
              this.queue = [...this.queue, item];
            })
          }.width('100%')
        }, (item: string) => item)
      }.width('100%').padding(24)
    }.width('100%').height('100%')
  }
}
