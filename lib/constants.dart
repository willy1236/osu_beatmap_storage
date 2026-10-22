/// osu!lazer 資料目錄的預設路徑（使用者未選取時的 fallback）
const kDefaultOsuDir = r'D:\osu!lazer';
const kDownloadBaseUrl = 'https://osu.direct/api/d/';
const kDownloadInterDelay = Duration(seconds: 3);

const kStatusLabel = <int, String>{
  -3: 'Unknown',
  -2: '墓地',
  -1: 'WIP',
  0: 'Pending',
  1: 'Ranked',
  2: 'Approved',
  3: 'Qualified',
  4: 'Loved',
};

/// 析域帳號（Ory Hydra）的位置與桌面 client 的識別
const kAuthIssuer = 'https://auth.domalyze.net';
const kAuthClientId = 'osu-beatmap-storage';
const kAuthScope = 'openid offline_access profile';
