import { common } from '@kit.AbilityKit';
import { cryptoFramework } from '@kit.CryptoArchitectureKit';
import { util } from '@kit.ArkTS';
import { http } from '@kit.NetworkKit';
import { TRAKT_REDIRECT_URI } from '../config/TraktConfig';
import { loadRefresh, saveRefresh, removeRefresh, tryVaultLock, releaseVaultLock, clearBackgroundGrant, BackgroundGrant, newBackgroundGrantId, readBackgroundGrant, writeBackgroundGrant } from './TokenVault';

interface PendingLogin {
  state: string;
  verifier: string;
  clientId: string;
  generation: number;
}

interface TokenResponse {
  access_token: string;
  refresh_token?: string;
  expires_in: number;
  token_type: string;
}

interface OAuthFailure {
  error: string;
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
  await md.update({ data: new util.TextEncoder().encodeInto(verifier) });
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

export interface TraktSession {
  clientId: string;
  token: string;
  generation: number;
}

class TraktAuth {
  private pending?: PendingLogin;
  private generation: number = 0;
  private accessToken: string = '';
  private expiresAt: number = 0;
  private busy: boolean = false;
  private clientId: string = '';
  private attemptedRestore: boolean = false;

  session(clientId: string): TraktSession | undefined {
    if (this.busy || this.clientId !== clientId || !this.accessToken || Date.now() >= this.expiresAt) {
      return undefined;
    }
    return { clientId: clientId, token: this.accessToken, generation: this.generation };
  }

  isCurrent(clientId: string, generation: number): boolean {
    return this.session(clientId)?.generation === generation;
  }

  // The foreground must verify the UUID before calling this. No refresh
  // token is duplicated and no grant is created on automatic renewal.
  setBackgroundRead(clientId: string, uuid: string, enabled: boolean, renew: boolean = false): boolean {
    const lease = tryVaultLock();
    if (!lease) { return false; }
    try {
      if (!enabled) { clearBackgroundGrant(); return true; }
      const session = this.session(clientId);
      if (!session || !uuid) { return false; }
      const old = readBackgroundGrant();
      if (renew && (!old || old.uuid !== uuid || old.clientId !== clientId)) { return false; }
      const id = old && old.uuid === uuid && old.clientId === clientId ? old.id : newBackgroundGrantId();
      const grant: BackgroundGrant = {uuid:uuid,clientId:clientId,token:session.token,expiresAt:this.expiresAt,id:id};
      writeBackgroundGrant(grant);
      return true;
    } catch (error) { return false; }
    finally { releaseVaultLock(lease); }
  }

  private status(message: string): void {
    AppStorage.setOrCreate<string>('traktAuthStatus', message);
    AppStorage.setOrCreate<boolean>('traktAuthBusy', this.busy);
    AppStorage.setOrCreate<boolean>('traktSignedIn', this.accessToken.length > 0 && Date.now() < this.expiresAt);
  }

  async begin(context: common.UIAbilityContext, clientId: string): Promise<void> {
    if (this.busy || clientId.length === 0) {
      return;
    }
    // A new login cannot inherit a previous account's background consent.
    const revokeLease = tryVaultLock();
    if (!revokeLease) { this.status('后台核对正在进行，请稍后授权。'); return; }
    try { clearBackgroundGrant(); }
    catch (error) { this.status('无法撤销旧后台授权，未开始登录。'); return; }
    finally { releaseVaultLock(revokeLease); }
    const generation: number = ++this.generation;
    this.clientId = clientId;
    this.busy = true;
    this.status('正在打开 Trakt 官方授权页面…');
    try {
      const state: string = randomValue();
      const verifier: string = randomValue();
      const codeChallenge: string = await challenge(verifier);
      if (generation !== this.generation) {
        return;
      }
      this.pending = { state: state, verifier: verifier, clientId: clientId, generation: generation };
      const authorize = 'https://auth.trakt.tv/oauth/authorize?response_type=code' +
        '&client_id=' + encodeURIComponent(clientId) +
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
    const lease = tryVaultLock();
    if (!lease) { this.busy = false; this.status('授权存储正在使用，请重新授权。'); return; }
    this.status('正在确认授权…');
    let request: http.HttpRequest | undefined;
    try {
      request = http.createHttp();
      const response = await request.request('https://auth.trakt.tv/oauth/token', {
        method: http.RequestMethod.POST,
        header: { 'Content-Type': 'application/json' },
        extraData: JSON.stringify({ code: code, client_id: pending.clientId,
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
      const saved = this.persistRefresh(pending.clientId, tokens.refresh_token);
      const username = await this.accountName(pending.clientId);
      if (pending.generation === this.generation) {
        this.status((username.length > 0 ? '已登录 Trakt：' + username : '已授权 Trakt（账户名称暂不可用）') + (saved ? '' : '；安全保存失败，重启后需重新登录。'));
      }
    } catch (error) {
      if (pending.generation === this.generation) {
        this.accessToken = '';
        this.expiresAt = 0;
        this.status('授权失败，请检查应用配置、回调地址及网络后重试。');
      }
    } finally {
      if (request) { request.destroy(); }
      releaseVaultLock(lease);
      if (pending.generation === this.generation) {
        this.busy = false;
        AppStorage.setOrCreate<boolean>('traktAuthBusy', false);
      }
    }
  }

  private async accountName(clientId: string): Promise<string> {
    const request = http.createHttp();
    try {
      const response = await request.request('https://api.trakt.tv/users/settings', {
        method: http.RequestMethod.GET,
        header: { 'Content-Type': 'application/json', 'trakt-api-version': '2',
          'trakt-api-key': clientId, 'Authorization': 'Bearer ' + this.accessToken },
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

  private persistRefresh(clientId: string, token?: string): boolean {
    try {
      if (!token) {
        removeRefresh();
        return false;
      }
      saveRefresh(clientId, token);
      return true;
    } catch (error) {
      return false;
    }
  }

  async restore(clientId: string, manual: boolean = false): Promise<void> {
    if (!clientId || this.busy || (!manual && this.attemptedRestore && Date.now() < this.expiresAt)) {
      return;
    }
    if (this.accessToken && this.clientId === clientId && Date.now() < this.expiresAt) {
      return;
    }
    if (this.attemptedRestore && !manual && this.expiresAt === 0) {
      return;
    }
    const lease = tryVaultLock();
    if (!lease) { this.status('授权存储正在使用，保留本机记录。'); return; }
    this.attemptedRestore = true;
    this.clientId = clientId;
    const generation = ++this.generation;
    this.busy = true;
    this.status('正在恢复 Trakt 登录…');
    let request: http.HttpRequest | undefined;
    try {
      const refreshToken = loadRefresh(clientId);
      if (!refreshToken) {
        this.status('尚未登录 Trakt');
        return;
      }
      request = http.createHttp();
      const response = await request.request('https://auth.trakt.tv/oauth/token', {
        method: http.RequestMethod.POST,
        header: { 'Content-Type': 'application/json' },
        extraData: JSON.stringify({ refresh_token: refreshToken, client_id: clientId,
          redirect_uri: TRAKT_REDIRECT_URI, grant_type: 'refresh_token' }),
        expectDataType: http.HttpDataType.STRING
      });
      if (generation !== this.generation) {
        return;
      }
      if (response.responseCode !== 200 || typeof response.result !== 'string') {
        if (response.responseCode === 400 && typeof response.result === 'string') {
          const failure = JSON.parse(response.result) as OAuthFailure;
          if (failure.error === 'invalid_grant') {
            clearBackgroundGrant();
            removeRefresh();
            this.accessToken = '';
            this.expiresAt = 0;
            this.status('授权已失效，请重新登录 Trakt。');
            return;
          }
        }
        throw new Error('Refresh failed');
      }
      const tokens = JSON.parse(response.result) as TokenResponse;
      if (typeof tokens.access_token !== 'string' || !tokens.access_token ||
          typeof tokens.expires_in !== 'number' || !Number.isFinite(tokens.expires_in) ||
          tokens.expires_in <= 0 || typeof tokens.token_type !== 'string' ||
          tokens.token_type.toLowerCase() !== 'bearer') {
        throw new Error('Invalid refresh response');
      }
      this.accessToken = tokens.access_token;
      this.expiresAt = Date.now() + tokens.expires_in * 1000;
      const saved = this.persistRefresh(clientId, tokens.refresh_token);
      const username = await this.accountName(clientId);
      if (generation === this.generation) {
        this.status((username ? '已登录 Trakt：' + username : '已恢复 Trakt 授权') +
          (saved ? '' : '；安全保存失败，重启后需重新登录。'));
      }
    } catch (error) {
      if (generation === this.generation) {
        this.accessToken = '';
        this.expiresAt = 0;
        this.status('登录恢复失败，可重试恢复或重新授权。');
      }
    } finally {
      if (request) {
        request.destroy();
      }
      releaseVaultLock(lease);
      if (generation === this.generation) {
        this.busy = false;
        AppStorage.setOrCreate<boolean>('traktAuthBusy', false);
      }
    }
  }

  cancel(): void {
    ++this.generation;
    this.pending = undefined;
    this.busy = false;
    this.status('本次操作已取消。');
  }

  disconnect(): boolean {
    const lease = tryVaultLock();
    if (!lease) { this.status('授权正在处理，请稍后断开。'); return false; }
    try {
      clearBackgroundGrant();
      removeRefresh();
    } catch (error) {
      this.status('无法删除安全存储中的授权，请解锁设备后重试。');
      return false;
    } finally { releaseVaultLock(lease); }
    ++this.generation;
    this.pending = undefined;
    this.accessToken = '';
    this.expiresAt = 0;
    this.busy = false;
    this.clientId = '';
    this.attemptedRestore = true;
    this.status('本机已断开登录；未撤销 Trakt 网站上的授权。');
    return true;
  }
}

export const traktAuth = new TraktAuth();
