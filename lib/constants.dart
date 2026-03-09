/// osu!lazer client.realm 的預設路徑（使用者未選取時的 fallback）
const kDefaultRealmPath = r'D:\osu!lazer\client.realm';
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
