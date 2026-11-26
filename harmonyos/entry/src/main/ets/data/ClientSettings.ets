import { preferences } from '@kit.ArkData';
import { common } from '@kit.AbilityKit';
import { http } from '@kit.NetworkKit';

export class ClientSettings {
  private storage: preferences.Preferences;
  constructor(context: common.UIAbilityContext) {
    this.storage = preferences.getPreferencesSync(context, { name: 'showly_trakt_settings' });
  }
  load(): string {
    const value = this.storage.getSync('client_id', '');
    return typeof value === 'string' ? value : '';
  }
  async save(value: string): Promise<void> {
    await this.storage.put('client_id', value);
    await this.storage.flush();
  }
}

export async function validateClientId(clientId: string): Promise<number> {
  const request = http.createHttp();
  try {
    const response = await request.request('https://api.trakt.tv/movies/trending?limit=1', {
      method: http.RequestMethod.GET,
      header: { 'Content-Type': 'application/json', 'trakt-api-version': '2', 'trakt-api-key': clientId },
      expectDataType: http.HttpDataType.STRING
    });
    return response.responseCode;
  } finally {
    request.destroy();
  }
}
