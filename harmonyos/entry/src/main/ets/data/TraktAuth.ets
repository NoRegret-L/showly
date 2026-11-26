import { common } from '@kit.AbilityKit';
import { cryptoFramework } from '@kit.CryptoArchitectureKit';
import { buffer, util } from '@kit.ArkTS';
import { http } from '@kit.NetworkKit';
import { TRAKT_CLIENT_ID, TRAKT_REDIRECT_URI } from '../config/TraktConfig';

interface PendingLogin {
  state: string;
  verifier: string;
  generation: number;
}

interface TokenResponse {
  access_token: string;
  refresh_token?: string;
  expires_in: number;
  token_type: string;
}

interface Account {
  username: string;
}

interface SettingsResponse {
  user: Account;
}

function base64url(bytes: Uint8Array): string {
  return new util.Base64Helper().encodeToStringSync(bytes, util.Type.BASIC_URL_SAFE).replace(/=+$/, '');
}

function randomValue(): string {
  return base64url(cryptoFramework.createRandom().generateRandomSync(32).data);
}

async function challenge(verifier: string): Promise<string> {
  const md = cryptoFramework.createMd('SHA256');
  await md.update({ data: new Uint8Array(buffer.from(verifier, 'utf-8').buffer) });
  return base64url((await md.digest()).data);
}

function queryParameters(uri: string): Map<string, string> {
  const values: Map<string, string> = new Map<string, string>();
  if (!uri.startsWith(TRAKT_REDIRECT_URI + '?') || uri.includes('#')) {
    return values;
  }
  const query = uri.substring(TRAKT_REDIRECT_URI.length + 1);
  for (const pair of query.split('&')) {
    const eq = pair.indexOf('=');
    if (eq < 0) {
      continue;
    }
    const key = decodeURIComponent(pair.substring(0, eq).replace(/\+/g, ' '));
    const value = decodeURIComponent(pair.substring(eq + 1).replace(/\+/g, ' '));
    if (values.has(key)) {
      throw new Error('Duplicate callback parameter');
    }
    values.set(key, value);
  }
  return values;
}

class TraktAuth {
  private pending?: PendingLogin;
  private generation: number = 0;
  private accessToken: string = '';
  private expiresAt: number = 0;
  private busy: boolean = false;

  private status(message: string): void {
    AppStorage.setOrCreate<string>('traktAuthStatus', message);
    AppStorage.setOrCreate<boolean>('traktAuthBusy', this.busy);
    AppStorage.setOrCreate<boolean>('traktSignedIn', this.accessToken.length > 0 && Date.now() < this.expiresAt);
  }

  async begin(context: common.UIAbilityContext): Promise<void> {
    if (this.busy || TRAKT_CLIENT_ID.length === 0) {
      return;
    }
    const generation: number = ++this.generation;
    this.busy = true;
    this.status('正在打开 Trakt 官方授权页面…');
    try {
      const state: string = randomValue();
      const verifier: string = randomValue();
      const codeChallenge: string = await challenge(verifier);
      if (generation !== this.generation) {
        return;
      }
      this.pending = { state: state, verifier: verifier, generation: generation };
      const authorize = 'https://auth.trakt.tv/oauth/authorize?response_type=code' +
        '&client_id=' + encodeURIComponent(TRAKT_CLIENT_ID) +
        '&redirect_uri=' + encodeURIComponent(TRAKT_REDIRECT_URI) +
        '&state=' + encodeURIComponent(state) +
        '&code_challenge=' + encodeURIComponent(codeChallenge) + '&code_challenge_method=S256';
      await context.startAbility({ action: 'ohos.want.action.viewData', uri: authorize });
      if (generation === this.generation && this.pending) {
        this.status('请在浏览器授权，然后返回应用。');
      }
    } catch (error) {
      if (generation === this.generation) {
        this.pending = undefined;
        this.busy = false;
        this.status('无法打开授权页面，请重试。');
      }
    }
  }

  async receive(uri: string): Promise<void> {
    if (!uri.startsWith(TRAKT_REDIRECT_URI + '?')) {
      return;
    }
    const pending = this.pending;
    if (!pending) {
      return;
    }
    let values: Map<string, string>;
    try {
      values = queryParameters(uri);
    } catch (error) {
      return;
    }
    if (values.get('state') !== pending.state) {
      return;
    }
    this.pending = undefined;
    const code = values.get('code');
    if (values.has('error') || !code) {
      this.busy = false;
      this.status('授权已取消或被拒绝。');
      return;
    }
    this.status('正在确认授权…');
    const request = http.createHttp();
    try {
      const response = await request.request('https://auth.trakt.tv/oauth/token', {
        method: http.RequestMethod.POST,
        header: { 'Content-Type': 'application/json' },
        extraData: JSON.stringify({ code: code, client_id: TRAKT_CLIENT_ID,
          redirect_uri: TRAKT_REDIRECT_URI, grant_type: 'authorization_code',
          code_verifier: pending.verifier }),
        expectDataType: http.HttpDataType.STRING
      });
      if (pending.generation !== this.generation) {
        return;
      }
      if (response.responseCode !== 200 || typeof response.result !== 'string') {
        throw new Error('Token exchange failed');
      }
      const tokens = JSON.parse(response.result) as TokenResponse;
      if (typeof tokens.access_token !== 'string' || tokens.access_token.length === 0 ||
          typeof tokens.expires_in !== 'number' || !Number.isFinite(tokens.expires_in) || tokens.expires_in <= 0 ||
          typeof tokens.token_type !== 'string' || tokens.token_type.toLowerCase() !== 'bearer') {
        throw new Error('Invalid token response');
      }
      this.accessToken = tokens.access_token;
      this.expiresAt = Date.now() + tokens.expires_in * 1000;
      const username = await this.accountName();
      if (pending.generation === this.generation) {
        this.status(username.length > 0 ? '已登录 Trakt：' + username : '已授权 Trakt（账户名称暂不可用）');
      }
    } catch (error) {
      if (pending.generation === this.generation) {
        this.accessToken = '';
        this.expiresAt = 0;
        this.status('授权失败，请检查应用配置、回调地址及网络后重试。');
      }
    } finally {
      request.destroy();
      if (pending.generation === this.generation) {
        this.busy = false;
        AppStorage.setOrCreate<boolean>('traktAuthBusy', false);
      }
    }
  }

  private async accountName(): Promise<string> {
    const request = http.createHttp();
    try {
      const response = await request.request('https://api.trakt.tv/users/settings', {
        method: http.RequestMethod.GET,
        header: { 'Content-Type': 'application/json', 'trakt-api-version': '2',
          'trakt-api-key': TRAKT_CLIENT_ID, 'Authorization': 'Bearer ' + this.accessToken },
        expectDataType: http.HttpDataType.STRING
      });
      if (response.responseCode === 200 && typeof response.result === 'string') {
        const account = JSON.parse(response.result) as SettingsResponse;
        return typeof account.user?.username === 'string' ? account.user.username : '';
      }
      return '';
    } catch (error) {
      return '';
    } finally {
      request.destroy();
    }
  }

  disconnect(): void {
    ++this.generation;
    this.pending = undefined;
    this.accessToken = '';
    this.expiresAt = 0;
    this.busy = false;
    this.status('本机已断开登录；未撤销 Trakt 网站上的授权。');
  }
}

export const traktAuth = new TraktAuth();
