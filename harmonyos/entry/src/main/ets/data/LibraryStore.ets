import { preferences } from '@kit.ArkData';
import { common } from '@kit.AbilityKit';
import { Library, Media } from '../model/Media';

export class LibraryStore {
  private storage: preferences.Preferences;

  constructor(context: common.UIAbilityContext) {
    this.storage = preferences.getPreferencesSync(context, { name: 'showly_library' });
  }

  load(): Media[] {
    const raw = this.storage.getSync('library', '');
    if (typeof raw !== 'string') {
      throw new Error('Invalid library storage');
    }
    if (raw === '') {
      return [];
    }
    const parsed = JSON.parse(raw) as Library;
    if (parsed.schema !== 1 || !Array.isArray(parsed.items)) {
      throw new Error('Unknown library schema');
    }
    const ids: Set<string> = new Set<string>();
    for (const item of parsed.items) {
      if (typeof item.id !== 'string' || typeof item.title !== 'string' ||
          typeof item.kind !== 'string' || typeof item.year !== 'number' ||
          typeof item.watched !== 'boolean' || ids.has(item.id)) {
        throw new Error('Invalid library record');
      }
      ids.add(item.id);
    }
    return parsed.items;
  }

  async save(items: Media[]): Promise<void> {
    const snapshot: Library = { schema: 1, items: items };
    await this.storage.put('library', JSON.stringify(snapshot));
    await this.storage.flush();
  }
}
