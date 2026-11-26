import { common } from '@kit.AbilityKit';
import { Media, mediaLabel, setWatched } from '../model/Media';
import { LibraryStore } from '../data/LibraryStore';
import { searchTrakt } from '../data/TraktSearch';

@Entry
@Component
struct Index {
  @State title: string = '';
  @State clientId: string = '';
  @State items: Media[] = [];
  @State results: Media[] = [];
  @State ready: boolean = false;
  @State saving: boolean = false;
  @State searching: boolean = false;
  @State libraryStatus: string = '';
  @State searchStatus: string = '';
  private store?: LibraryStore;

  aboutToAppear(): void {
    try {
      const context = this.getUIContext().getHostContext() as common.UIAbilityContext;
      this.store = new LibraryStore(context);
      this.items = this.store.load();
      this.ready = true;
    } catch (error) {
      this.libraryStatus = '本地记录读取失败，已停止写入以保护原数据。';
    }
  }

  private async save(next: Media[]): Promise<void> {
    if (!this.ready || this.saving || !this.store) {
      return;
    }
    this.saving = true;
    try {
      await this.store.save(next);
      this.items = next;
      this.libraryStatus = '已保存到本机';
    } catch (error) {
      this.libraryStatus = '保存失败，已停止写入，请重启应用检查记录。';
      this.ready = false;
    } finally {
      this.saving = false;
    }
  }

  private add(item: Media): void {
    if (!this.ready || this.saving || this.items.some((value: Media) => value.id === item.id)) {
      return;
    }
    this.save([...this.items, item]);
  }

  private async search(): Promise<void> {
    if (this.searching || this.title.trim().length === 0 || this.clientId.trim().length === 0) {
      return;
    }
    this.searching = true;
    this.results = [];
    this.searchStatus = '搜索中…';
    try {
      this.results = await searchTrakt(this.title.trim(), this.clientId.trim());
      this.searchStatus = this.results.length === 0 ? '没有搜索结果' : '搜索完成';
    } catch (error) {
      this.searchStatus = '搜索失败：请检查网络、Client ID 或 Trakt API 权限与限额。';
    } finally {
      this.searching = false;
    }
  }

  @Builder
  libraryRow(item: Media) {
    Row({ space: 8 }) {
      Text(mediaLabel(item)).layoutWeight(1)
      Button(item.watched ? '撤销' : '已看')
        .enabled(this.ready && !this.saving)
        .onClick(() => { this.save(setWatched(this.items, item.id, !item.watched)); })
    }.width('100%')
  }

  build() {
    Scroll() {
      Column({ space: 14 }) {
        Text('Showly Preview').fontSize(30).fontWeight(FontWeight.Bold)
        Text('本地影视清单 · Trakt 搜索').fontSize(16)
        Text('非官方应用，使用 Trakt，但未获 Trakt 认可或认证。')
          .fontSize(12).fontColor('#687887')
        Text('搜索（可选）').fontSize(20).fontWeight(FontWeight.Medium)
        TextInput({ placeholder: 'Trakt Client ID（仅本次会话）', text: this.clientId })
          .type(InputType.Password)
          .onChange((value: string) => { this.clientId = value; })
        TextInput({ placeholder: '电影或剧集名称', text: this.title })
          .onChange((value: string) => { this.title = value; })
        Row({ space: 8 }) {
          Button('搜索 Trakt').layoutWeight(1)
            .enabled(!this.searching && this.title.trim().length > 0 && this.clientId.trim().length > 0)
            .onClick(() => { this.search(); })
          Button('手动添加').layoutWeight(1)
            .enabled(this.ready && !this.saving && this.title.trim().length > 0)
            .onClick(() => {
              const title: string = this.title.trim();
              const item: Media = { id: 'local:' + title.toLowerCase(), title: title,
                kind: 'manual', year: 0, watched: false };
              this.add(item);
            })
        }.width('100%')
        Text(this.searchStatus).fontSize(13)
        ForEach(this.results, (item: Media) => {
          Row({ space: 8 }) {
            Text(mediaLabel(item)).layoutWeight(1)
            Button(this.items.some((value: Media) => value.id === item.id) ? '已添加' : '添加')
              .enabled(this.ready && !this.saving && !this.items.some((value: Media) => value.id === item.id))
              .onClick(() => { this.add(item); })
          }.width('100%')
        }, (item: Media) => item.id)
        Divider()
        Text(this.libraryStatus).fontSize(13)
        Text('待看 (' + this.items.filter((item: Media) => !item.watched).length + ')')
          .fontSize(20).fontWeight(FontWeight.Medium)
        ForEach(this.items.filter((item: Media) => !item.watched), (item: Media) => {
          this.libraryRow(item)
        }, (item: Media) => item.id)
        Text('已看 (' + this.items.filter((item: Media) => item.watched).length + ')')
          .fontSize(20).fontWeight(FontWeight.Medium)
        ForEach(this.items.filter((item: Media) => item.watched), (item: Media) => {
          this.libraryRow(item)
        }, (item: Media) => item.id)
      }.width('100%').padding(24)
    }.width('100%').height('100%')
  }
}
