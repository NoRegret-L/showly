import { http } from '@kit.NetworkKit';
import { APP_VERSION_CODE, RELEASES_URL, UPSTREAM_BASELINE } from '../config/BuildInfo';

interface ReleaseAsset {
  name: string;
  state: string;
  size: number;
  digest?: string;
  browser_download_url: string;
}
interface ReleaseRow {
  tag_name: string;
  draft: boolean;
  prerelease: boolean;
  assets: ReleaseAsset[];
}
interface UpstreamCommit { sha: string; }
export interface UpdateInfo {
  version: string;
  versionCode: number;
  url: string;
  digest: string;
}
export interface UpstreamInfo { sha: string; changed: boolean; url: string; }

async function readPublic(url: string): Promise<string> {
  const request = http.createHttp();
  try {
    const response = await request.request(url, {
      method: http.RequestMethod.GET,
      header: { 'Accept': 'application/vnd.github+json', 'X-GitHub-Api-Version': '2022-11-28',
        'User-Agent': 'Showly-HarmonyOS-Update/0.9.3.1' },
      expectDataType: http.HttpDataType.STRING
    });
    if (response.responseCode !== 200 || typeof response.result !== 'string') {
      throw new Error('GitHub HTTP ' + response.responseCode);
    }
    return response.result;
  } finally { request.destroy(); }
}

// The Android upstream releases and unrelated tags are deliberately ignored.
// Compare versionCode, not lexical strings or release publication timestamps.
function parseRelease(row: ReleaseRow): UpdateInfo | undefined {
  if (row.draft !== false || row.prerelease !== true || typeof row.tag_name !== 'string' ||
      !Array.isArray(row.assets)) { return undefined; }
  const match = /^harmonyos-v([0-9]+\.[0-9]+\.[0-9]+(?:\.[0-9]+)?)-b([1-9][0-9]*)$/.exec(row.tag_name);
  if (!match) { return undefined; }
  const version = match[1];
  const code = Number(match[2]);
  if (!Number.isSafeInteger(code) || code <= 0) { return undefined; }
  const hapName = 'showly-' + row.tag_name + '-unsigned.hap';
  const prefix = RELEASES_URL + '/download/' + row.tag_name + '/';
  const hap = row.assets.find((asset: ReleaseAsset) => asset.name === hapName && asset.state === 'uploaded' &&
    Number.isSafeInteger(asset.size) && asset.size > 0 && asset.browser_download_url === prefix + hapName);
  const checksum = row.assets.find((asset: ReleaseAsset) => asset.name === 'SHA256SUMS.txt' &&
    asset.state === 'uploaded' && asset.size > 0 && asset.browser_download_url === prefix + 'SHA256SUMS.txt');
  const metadata = row.assets.find((asset: ReleaseAsset) => asset.name === 'release-info.json' &&
    asset.state === 'uploaded' && asset.size > 0 && asset.browser_download_url === prefix + 'release-info.json');
  if (!hap || !checksum || !metadata || typeof hap.digest !== 'string' ||
      !/^sha256:[0-9a-f]{64}$/.test(hap.digest)) { return undefined; }
  return { version: version, versionCode: code, url: RELEASES_URL + '/tag/' + row.tag_name,
    digest: hap.digest };
}

export async function checkRelease(): Promise<UpdateInfo | undefined> {
  let best: UpdateInfo | undefined;
  // API returns newest releases first, including prereleases. Examine every
  // page; a full page is not evidence of an exhaustive result.
  for (let page = 1; ; page++) {
    const body = await readPublic('https://api.github.com/repos/NoRegret-L/showly/releases?per_page=100&page=' + page);
    const rows = JSON.parse(body) as ReleaseRow[];
    if (!Array.isArray(rows)) { throw new Error('Invalid release list'); }
    for (const row of rows) {
      const info = parseRelease(row);
      if (info && (!best || info.versionCode > best.versionCode)) { best = info; }
    }
    if (rows.length < 100) { break; }
  }
  return best && best.versionCode > APP_VERSION_CODE ? best : undefined;
}

export async function checkUpstream(): Promise<UpstreamInfo> {
  const body = await readPublic('https://api.github.com/repos/trakt/showly/commits/master');
  const commit = JSON.parse(body) as UpstreamCommit;
  if (typeof commit.sha !== 'string' || !/^[0-9a-f]{40}$/.test(commit.sha)) {
    throw new Error('Invalid upstream revision');
  }
  const changed = commit.sha !== UPSTREAM_BASELINE;
  return { sha: commit.sha, changed: changed, url: changed ?
    'https://github.com/trakt/showly/compare/' + UPSTREAM_BASELINE + '...' + commit.sha :
    'https://github.com/trakt/showly/commit/' + commit.sha };
}
