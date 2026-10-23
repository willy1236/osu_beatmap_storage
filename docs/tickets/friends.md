# 好友系統 任務拆解

規格：[docs/specs/friends.md](../specs/friends.md)

後端的實作設計與 API 契約在 domalyze-api repo 的 [後端任務](https://github.com/willy1236/domalyze-api/blob/main/docs/tickets/social-friends.md)，這份的卡片只寫桌面程式，後端部分以卡號對照。純後端的卡（T-02、T-11）只列在總覽。

## 現況與前提

- 技術棧
  - 桌面程式：Flutter（Windows），狀態用 `StatefulWidget` 加單例 `ChangeNotifier`，設定存在執行目錄的 `config.json`（`PrefsService`），呼叫後端一律經 `ApiClient`（自動帶 token、401 時 refresh 重試一次）
  - 後端：`domalyze-api` 的 `social` 模組（好友、邀請、封鎖、上線狀態、即時事件）與 `osu` 模組（好友瀏覽清單、推送）
- 既有相關機制
  - `HomePage` 用 `NavigationRail`（圖譜查看、回放匯出）＋`IndexedStack`；側欄底部是 `UpdateButton` 與帳號選單 `_AccountTile`
  - `CloudListPage` 是可重用的清單頁（`loader`、`localIds`、`canDelete`、`extraActionsBuilder`），已有勾選與下載；`ShareLinkOpener.open(token)` 用它開啟唯讀的別人清單，`SharedCopyButton` 負責複製
  - `CloudPresenceService` 是「登入後自動讀取、登出或換帳號時清空」的單例寫法範例
  - `AppLinkService` 接收 `osu-storage://` 連結並分派；`windows/runner/main.cpp` 用 app_links 的 `SendAppLinkToInstance()` 把連結轉給已開啟的執行個體
  - `BeatmapListPage` 沒有勾選模式；`_exportCsv` 從 `BeatmapSetInfo` 算出雲端欄位
  - 目前沒有系統匣、沒有 Windows 通知、沒有設定頁
- 這次會動到的既有部位
  - `lib/pages/home_page.dart`、`lib/pages/beatmap_list_page.dart`、`lib/pages/cloud_list_page.dart`
  - `lib/services/share_link_opener.dart`、`lib/services/app_link_service.dart`、`lib/services/prefs_service.dart`、`lib/widgets/open_share_link_dialog.dart`
  - `lib/main.dart`、`windows/runner/main.cpp`、`pubspec.yaml`
- 已定案的技術前提
  - 好友資料都在 `domalyze-api`，auth server 不存好友資料
  - 邀請、推送、上線狀態由後端用 SSE 即時送達，不定時查詢
  - 分享連結保留，與好友瀏覽並存
  - 好友邀請連結是自訂 URI scheme `osu-storage://friend/<token>`，跟分享連結共用 scheme

## 實作順序總覽

| # | 卡號 | 標題 | 依賴 | 並行組 | 備註 |
|---|---|---|---|---|---|
| 1 | T-01 | 域民能從分享清單頁送好友邀請，對方接受後雙方出現在好友列表 | 無 | 0 | 骨架切片：第一次端到端跑通；後端同卡號 |
| 2 | T-02 | [共用] 用代號查域民、批次查域民 | 無 | 0 | 純後端（含 domalyze-identity），T-03 依賴 |
| 3 | T-08 | 程式能縮到系統匣、開機自動啟動 | 無 | 0 | 純桌面，跟好友無關 |
| 4 | T-12 | [共用] 即時事件通道（SSE） | 無 | 0 | 桌面＋後端；T-09、T-10 依賴 |
| 5 | T-06 | 域民能瀏覽好友的雲端清單，也能關掉自己的公開 | T-01 | A | |
| 6 | T-07 | 域民能推送圖譜給好友，收到的人在收件匣處理 | T-01 | A | |
| 7 | T-03 | 域民能輸入代號送出好友邀請 | T-01、T-02 | A | |
| 8 | T-04 | 域民能用一次性好友邀請連結直接加好友 | T-01 | A | |
| 9 | T-05 | 域民能刪除好友、封鎖與解除封鎖 | T-01 | A | |
| 10 | T-10 | 好友看得到我正在玩 osu!lazer，好友列表能搜尋、排序 | T-01、T-12 | A | |
| 11 | T-09 | 收到好友邀請或推送時，看到紅點與 Windows 通知 | T-07、T-08、T-12 | B | |
| 12 | T-11 | 域民刪除、停權、合併時，好友資料跟著處理 | T-05、T-07 | B | 純後端＋identity 設定 |

```mermaid
flowchart LR
  T01[T-01 骨架] --> T06 & T07 & T03 & T04 & T05 & T10
  T02[T-02 identity 查詢] --> T03[T-03]
  T12[T-12 即時通道] --> T10[T-10 上線狀態] & T09
  T07 --> T09[T-09 通知]
  T08[T-08 系統匣] --> T09
  T05 --> T11[T-11 帳號事件]
  T07 --> T11
```

並行組 A 的卡都會在好友頁（`friends_page.dart`）加東西，但各自是不同區塊（新增按鈕、列表項目選單、分頁），git 可自動合併。

## 任務卡

### T-01 域民能從分享清單頁送好友邀請，對方接受後雙方出現在好友列表

**使用者價值**：第一次能建立好友關係，也是整個好友系統的骨架：好友頁、`FriendService`、桌面與 `social` 模組的串接都在這張跑通。挑「從分享清單頁加」當第一條路徑，是因為它不需要等 auth server 的反查 API（T-02）。

**範圍**
- 包含：好友頁（好友列表、收到的邀請、送出的邀請）、分享清單頁的「加好友」按鈕、側欄新增「好友」入口
- 不包含：其他加好友方式（T-03、T-04）、刪除好友與封鎖（T-05）、上線狀態與搜尋排序（T-10）、紅點、通知與自動更新列表（T-09）

**驗收條件**
- [ ] A 用分享連結開啟 B 的清單，按「加好友」後，A 的好友頁「送出的邀請」出現 B，B 的好友頁「收到的邀請」出現 A（B 重新整理後）
- [ ] B 接受後，雙方的好友列表都出現對方，顯示對方目前的代號
- [x] B 拒絕、或 A 取消邀請後，雙方的邀請列表都不再出現這筆
- [x] A 邀請 B 時 B 已邀請過 A，兩人直接成為好友
- [x] 對已是好友的人、對自己送邀請時，按鈕顯示對應狀態或錯誤，不重複建立
- [x] 任一方好友已達 500 人時，送出或接受都失敗並顯示「好友已達上限」
- [x] 24 小時內送出第 51 筆好友邀請時失敗，顯示「今天送出的邀請太多，請稍後再試」
- [x] 未登入時看不到「好友」入口內容，只提示登入

**實作設計**
- 前端
  - `lib/services/friend_service.dart`：單例 `ChangeNotifier`，保存好友、收到與送出的邀請；提供讀取、送出、接受、拒絕、取消；登出或換帳號時清空（參考 `CloudPresenceService` 的寫法）
  - `lib/pages/friends_page.dart`：好友列表、收到的邀請（接受、拒絕）、送出的邀請（取消），有重新整理按鈕
  - `HomePage` 的 `NavigationRail` 新增「好友」destination
  - `ShareLinkOpener.open` 開啟的 `CloudListPage` 用 `extraActionsBuilder` 加「加好友」按鈕，呼叫 `/osu/shared/{token}/friend-request`；已是好友、已送出時按鈕顯示對應狀態
  - 錯誤碼對應的提示文字：`already_friends`、`friend_limit`、`cannot_friend_self`、`rate_limited`
- 後端：見後端 T-01

**依賴**：無（後端 T-01 要先上線才能端到端驗收）

**實作決定**
- 分享清單頁按鈕狀態：後端 `GET /osu/shared/{token}` 的 owner 帶 `account_id`（後端已上線），開頁即比對好友與送出的邀請，顯示「已是好友」「已送出邀請」「這是你自己」。後端沒給 `account_id` 時，按鈕維持「加好友」，按下後依回應顯示狀態。
- `FriendService` 在 `main()` 提早建立，登入後預載。
- 好友列表與兩種邀請列表顯示圓形頭像，沒有圖時用預設圖示；代號為空字串時顯示「（未知的域民）」。
- 錯誤碼除了卡上列的四個，另補 `blocked_by_you`、`not_found`、`unavailable` 的提示文字。
- 送出邀請後一律重讀 `/social/requests`，不樂觀更新。對方已封鎖送出者時，後端會回假的 `sent`，列表以重讀結果為準。
- 對方已邀請我時，按鈕仍顯示「加好友」，按下後兩人互送，直接成為好友。
- 審查修正：429 提示只有送出邀請（`sendViaShare`、`sendToAccount`）顯示「今天送出的邀請太多，請稍後再試」；其他操作與讀取列表顯示「請求太頻繁，請稍後再試」。

**進度**：實作完成（2026-10-23）。單元／widget 測試已過；全套 CI（376 tests、`flutter build windows` 成功、analyze 無新增）與三輪獨立審查已完成並修正；人工驗證待做
- commit：f70bf98、f8ad185、9af091a、118500a、d8ff7a5（feat/friends）
- 未驗：A、B 兩個帳號對真實後端的端到端：驗收 1（B 重新整理後「收到的邀請」出現 A）、驗收 2（B 接受後雙方好友列表）

### T-03 域民能輸入代號送出好友邀請

**使用者價值**：不必先拿到對方的分享連結，知道代號就能加好友。

**範圍**
- 包含：好友頁「加好友」對話框、代號查詢、確認畫面
- 不包含：好友搜尋建議或模糊搜尋

**驗收條件**
- [x] 在好友頁按「加好友」，輸入代號後顯示對方的代號（有頭像時一併顯示），按確認才送出邀請
- [x] 輸入不存在的代號、或停權中域民的代號，顯示「找不到這位域民」
- [x] 輸入自己的代號、已是好友的代號，顯示對應提示，不送出
- [x] 後端暫時連不上時顯示「請稍後再試」，不顯示「找不到」
- [x] 送出後對方出現在「送出的邀請」

**實作設計**
- 前端：`friends_page.dart` 新增「加好友」按鈕與對話框（輸入 → `GET /social/lookup` → 確認 → `FriendService` 送出）
- 後端：見後端 T-03

**依賴**：T-01（好友頁、送邀請）、T-02（代號反查，後端）

**實作決定**
- `ApiClient.send` 已支援 JSON body，`ApiClient` 不動。代號查詢放新檔 `lib/services/friend_lookup.dart`，`FriendService` 只新增 `sendToAccount`。
- `GET /social/lookup` 的 503 與 404 分開處理：503 與連線例外顯示「請稍後再試」，404 顯示「找不到這位域民」。`POST /social/requests` 回 404 時同樣顯示「找不到這位域民」。
- 代號先去掉前後空白再查，空字串不查。
- 查到的人已先邀請我時，顯示「對方已邀請你，按確認將直接成為好友」並允許送出。
- 查到的人已在「送出的邀請」時，顯示「已送出邀請，等待對方回應」並停用確認。

**進度**：實作完成（2026-10-23）。單元／widget 測試已過；全套 CI（376 tests、`flutter build windows` 成功、analyze 無新增）與三輪獨立審查已完成並修正；人工驗證待做
- commit：ec90418、9178909、261be44、3a9cbfc、9a08ea2（feat/friends）
- 未驗：真實後端端到端；加好友對話框的頭像顯示沒有測試

### T-04 域民能用一次性好友邀請連結直接加好友

**使用者價值**：把連結丟給朋友，對方點一下就成為好友，不用再按接受；連結用過就失效，外流也不怕。

**範圍**
- 包含：產生一次性好友邀請連結、列出還沒用過的連結並撤銷；`osu-storage://friend/<token>` 連結開啟；貼上連結開啟
- 不包含：有期限的連結

**驗收條件**
- [ ] 在好友頁產生邀請連結並複製；B 點連結後程式開啟，提示「要和 A 成為好友嗎」，確認後雙方的好友列表都出現對方
- [ ] 同一條連結被用過一次後，再開啟時顯示「邀請連結已失效」，A 的未使用連結列表不再出現它
- [x] 可以連續產生多條連結分給不同人；撤銷其中一條後，那條開啟時顯示「邀請連結已失效」，其他條不受影響
- [x] B 開啟連結但取消確認時，連結仍然有效
- [x] B 未登入時點連結，先提示登入，登入完成後繼續加好友（跟分享連結相同）
- [x] 用自己的連結、已是好友時，顯示對應提示
- [x] 任一方好友已達 500 人時顯示「好友已達上限」
- [ ] 被 A 封鎖的 B 用 A 的連結時，看起來跟成功一樣，但不會成為好友（T-05 完成後驗證）

**實作設計**
- 前端
  - `friends_page.dart` 加邀請連結區塊：產生並複製新連結、列出未使用的連結（顯示產生時間）與撤銷
  - `AppLinkService` 分派 `osu-storage://friend/<token>`；新增 `FriendLinkOpener`，登入提示流程照 `ShareLinkOpener`
  - 開啟時先用 `GET /social/invite-links/{token}` 取得擁有者顯示確認，確認後才呼叫 accept，所以取消不會消耗連結
  - 貼上連結開啟：`OpenShareLinkDialog` 一併辨識 `friend/` 連結
- 後端：見後端 T-04

**依賴**：T-01（好友頁）

**實作決定**
- 帳號選單與貼上對話框的項目改名「開啟連結」，輸入框 hint 寫 `share/…` 或 `friend/…`。
- 後端限制每人未使用的邀請連結最多 20 條（`invite_link_limit`）。好友頁的邀請連結區塊顯示「n/20」，滿 20 條時停用產生並提示先撤銷。
- 登入暫存邏輯複製一份到 `FriendLinkOpener`，`ShareLinkOpener` 不動。
- 邀請連結的 API 放新檔 `lib/services/invite_link_service.dart`，`friend_service.dart` 不動。
- 確認前先比對自己的連結與已是好友的情況，先行提示，不呼叫 accept。
- 審查修正：`InviteLinkService.refresh` 改為 `_running`／`_again` 合併，讀取中的重讀不再被吞掉。
- `blocked_by_you` 提示已統一為「你已封鎖這位域民，請先到封鎖名單解除封鎖」，與 `FriendService` 一致（原「文案不一致」已解決）。

**進度**：實作完成（2026-10-23）。單元／widget 測試已過；全套 CI（376 tests、`flutter build windows` 成功、analyze 無新增）與三輪獨立審查已完成並修正；人工驗證待做
- commit：c8fe198、40bd036、a2ca450、9f63f7c、79dccf5、40c8765（feat/friends）
- 未驗：真實後端端到端：驗收 1（雙方好友列表）、驗收 2（A 的未使用連結列表不再出現）、驗收 8（被擁有者封鎖者用連結）；併發 accept；程式已開啟時點 friend 連結，由既有執行個體接手

### T-05 域民能刪除好友、封鎖與解除封鎖

**使用者價值**：能結束不想要的關係，擋掉騷擾的人。

**範圍**
- 包含：刪除好友、封鎖（好友、送邀請來的人、分享清單頁的擁有者）、封鎖名單與解除封鎖
- 不包含：封鎖對分享連結的影響（規格決定不影響）

**驗收條件**
- [ ] 在好友列表刪除 B 後，雙方的好友列表都不再出現對方；先前互相收到的推送仍在收件匣
- [x] 封鎖好友 B：好友關係解除，B 出現在我的封鎖名單
- [x] 可以從「收到的邀請」直接封鎖送邀請的人，那筆邀請一併移除
- [ ] 被封鎖的 B 對我送邀請、用我的邀請連結時，B 看到的結果跟正常送出一樣，但我收不到邀請、也不會成為好友
- [x] 對自己封鎖的人送邀請時，提示先解除封鎖
- [x] 解除封鎖後，B 可以重新送邀請；好友關係不會自動恢復
- [ ] 被封鎖的 B 仍能用我的分享連結看清單

**實作設計**
- 前端：好友列表與收到的邀請加選單（刪除好友、封鎖，兩者都要確認）；好友頁新增封鎖名單（解除封鎖）；`blocked_by_you` 的提示文字
- 後端：見後端 T-05

**依賴**：T-01（好友頁）

**實作決定**
- 分享清單頁新增「封鎖擁有者」按鈕，按下先確認。封鎖後以 SnackBar 顯示「已封鎖」，頁面不顯示已封鎖狀態，也不改 `FriendRelation`。沒有 `ownerAccountId` 或擁有者是自己時不顯示這個按鈕。
- 封鎖名單從好友頁 AppBar 的按鈕開獨立頁，進頁才讀取。名單不顯示封鎖時間，因為後端不回。
- `blocked_by_you` 的提示為「你已封鎖這位域民，請先到封鎖名單解除封鎖」。後端另有 `cannot_block_self`，提示為「不能封鎖自己」。
- 審查修正：429 提示與 T-01 相同，只有送出邀請說「邀請太多」，刪除好友、封鎖等操作用「請求太頻繁，請稍後再試」。

**進度**：實作完成（2026-10-23）。單元／widget 測試已過；全套 CI（376 tests、`flutter build windows` 成功、analyze 無新增）與三輪獨立審查已完成並修正；人工驗證待做
- commit：90c877a、f8b828e、318e603、6d7193b、3b4b8c4、97945c7（feat/friends）
- 未驗：真實後端端到端：驗收 1（對方的好友列表不再出現我、先前推送仍在收件匣）、驗收 4（被封鎖者送邀請與用連結的結果）、驗收 7（被封鎖者仍能用分享連結看清單）

### T-06 域民能瀏覽好友的雲端清單，也能關掉自己的公開

**使用者價值**：這是好友系統的主要目的：不必再傳分享連結，好友點進去就能看到對方的整份清單。

**範圍**
- 包含：從好友列表開啟好友的清單（瀏覽、下載、複製進自己的清單）、清單公開開關、好友列表只在對方開放時顯示入口
- 不包含：逐位好友設定（規格不做）

**驗收條件**
- [x] 在好友列表點好友 B 的「看清單」，開啟 B 的整份雲端清單，內容和 B 的分享連結看到的相同，即時反映 B 的增刪
- [x] 能勾選下載、一鍵複製進自己的雲端清單，複製受每分鐘一次的頻率限制
- [ ] B 關掉公開後，我的好友列表不再顯示 B 的「看清單」入口；已開著的頁面重新整理時顯示「無法瀏覽」
- [x] 公開開關預設開啟，切換後重開程式仍維持
- [ ] 公開開關和分享連結互不影響：關掉公開，B 的分享連結照樣能用

**實作設計**
- 前端
  - `FriendService` 讀好友時一併讀 `/osu/friends/browsable`，好友項目帶 `canBrowse`
  - 好友列表的「看清單」開啟唯讀 `CloudListPage`（照 `ShareLinkOpener` 的寫法），複製按鈕沿用 `SharedCopyButton` 的行為，改呼叫好友端點
  - 公開開關（`/osu/settings`）放在 T-08 的設定入口；T-08 還沒做時先放好友頁頂端
- 後端：見後端 T-06

**依賴**：T-01（好友列表）

**實作決定**
- 「看清單」入口只在重新讀取時更新：開好友頁、按重新整理、`FriendService.refresh`。後端沒有公開開關變動的即時事件。
- `CloudListPage` 的 AppBar 加重新整理按鈕，自己的清單、分享清單、好友清單都有。
- 複製按鈕新寫 `FriendCopyButton`，`SharedCopyButton` 不動。
- 403 的提示為「無法瀏覽：對方未開放，或你們已不是好友」，並隱藏重試按鈕。
- 公開開關經 `OsuSettingsService` 讀寫後端 `/osu/settings`，不存在 `config.json`。開關放在 T-08 的設定對話框。
- `/osu/friends/browsable` 讀取失敗時視為沒有人開放，好友列表照常載入，不報錯。
- 從好友列表開清單時，不跳「尚未載入本機圖譜」確認對話框。
- `FriendsPage` 每次開頁一律重讀。
- 審查修正：好友頁常駐在 `IndexedStack`，`initState` 只跑一次，所以改由 `HomePage` 切到好友頁時（含點通知、重按已選中的好友頁）呼叫 `FriendService.refresh()`；`FriendsPage.initState` 不再重讀。

**進度**：實作完成（2026-10-23）。單元／widget 測試已過；全套 CI（376 tests、`flutter build windows` 成功、analyze 無新增）與三輪獨立審查已完成並修正；人工驗證待做
- commit：63a8fc9、ecb81da、d69c87c、e593521、91b7ca9（feat/friends）
- 未驗：雙帳號與真實後端端到端：驗收 2 的真後端 429 訊息、驗收 3（B 關掉公開後入口消失與「無法瀏覽」）、驗收 5（公開開關與分享連結互不影響）

### T-07 域民能推送圖譜給好友，收到的人在收件匣處理

**使用者價值**：只想給朋友看幾張圖時，不必分享整份清單，直接挑好送過去。

**範圍**
- 包含：從雲端清單頁與圖譜查看頁挑圖推送（最多 100 張、附言 200 字、多位好友）、圖譜查看頁的勾選模式、收件匣（列表、下載、收進雲端清單、標為已讀、刪除）
- 不包含：紅點與 Windows 通知（T-09）

**驗收條件**
- [ ] 在自己的雲端清單頁勾選圖譜後按「推送給好友」，選一位或多位好友、寫附言，送出後每位好友的收件匣都出現這筆推送
- [ ] 在圖譜查看頁進入勾選模式、勾選本機圖譜後也能推送，包括還沒上傳到雲端的圖；沒有 OnlineID 的圖不能勾選
- [x] 超過 100 張或附言超過 200 字時無法送出，畫面提示原因
- [x] 收件匣顯示送出者目前的代號、附言、時間與圖譜清單，未讀的有標示
- [x] 收件人能勾選下載、把整筆推送收進自己的雲端清單（合併規則同上傳，受每分鐘一次的限制）、標為已讀、刪除；刪除只影響自己的收件匣
- [ ] 雙方刪除好友後，已收到的推送仍在
- [x] 推送給非好友（例如送出前對方剛刪掉我）時整筆失敗，提示哪些人不是好友

**實作設計**
- 前端
  - 推送對話框：選好友（多選，來自 `FriendService`）、附言、送出；雲端清單頁（`CloudListPage` 既有勾選，自己的清單才顯示推送按鈕）與圖譜查看頁共用
  - `BeatmapListPage` 新增勾選模式（AppBar 切換），勾選後可推送；推送的欄位用 `_exportCsv` 同一套計算
  - 收件匣：好友頁新增「收件匣」分頁；點開一筆推送用 `CloudListPage` 顯示其圖譜（可勾選下載），另加「收進我的清單」「刪除」；開啟時標為已讀
  - `lib/services/push_service.dart`：單例 `ChangeNotifier`，保存收件匣與未讀數（T-09 依賴未讀數）
- 後端：見後端 T-07

**依賴**：T-01（好友列表）

**風險 / 實作注意**：`_exportCsv` 的欄位計算若還是頁面內的私有方法，抽成兩處都能用的函式（自動上傳也可能已抽過，先看 `cloud_sync_service.dart`）

**實作決定**
- 收件匣是好友頁 AppBar 的圖示開出的新頁 `InboxPage`，不是好友頁上的分頁。
- 收件匣一次讀全部，不傳 `limit`。常數 `kInboxLimit` 保留，日後要分頁時調整。
- 推送的圖譜欄位用 `toCloudEntry` 產生，不用 `_exportCsv`，因為後端要結構化的 `BeatmapEntry`。因此「風險 / 實作注意」提到的抽函式不需要。
- `CloudListPage` 新增 `selectionActionsBuilder` 參數，依勾選項目產生動作，自己的清單用它放「推送給好友」按鈕。
- `PushService` 不在 `main()` 預載，預載留給 T-09。公開介面為 `items`、`unreadCount`、`loaded`、`loading`、`error`、`refresh()`、`send()`、`markRead()`、`collect()`、`delete()`，T-09 依此取得未讀數。
- 推送給非好友時，後端的 description 只有 id。前端抽出 UUID，用 `FriendService` 反查代號顯示，查不到顯示 id。
- 好友頁的收件匣圖示不顯示未讀紅點，歸 T-09。
- 從收件匣點開一筆推送的 `CloudListPage`，標題為「<代號> 的推送」。
- 圖譜查看頁勾選模式下，推送全部已勾選的圖譜，包含被搜尋暫時隱藏的。這與 `CloudListPage` 的行為不同，待使用者確認是否要統一。
- 審查修正：`PushService` 訂閱 `resyncRequested`，重連時整份重讀。`markRead` 與在途 `refresh` 競態時，以 `_readHold` 保留已讀，成功後補讀一次。

**進度**：實作完成（2026-10-23）。單元／widget 測試已過；全套 CI（376 tests、`flutter build windows` 成功、analyze 無新增）與三輪獨立審查已完成並修正；人工驗證待做
- commit：a7e3cea、5e74ee3、922e7c0、c008eab、7fb2d79、59ab8e9（feat/friends）
- 未驗：雙帳號端到端：驗收 1（每位好友的收件匣出現這筆推送）、驗收 6（雙方刪除好友後推送仍在）；驗收 2 的圖譜查看頁勾選模式與推送沒有頁面層級的測試，只有勾選列元件測試；勾選模式推送的範圍待使用者確認（見實作決定最後一條）

### T-08 程式能縮到系統匣、開機自動啟動

**使用者價值**：程式可以在背景常駐，上線狀態與通知才有意義；不想常駐的人照舊關掉就結束。

**範圍**
- 包含：關閉視窗時的選擇與記住、系統匣圖示與右鍵「結束」、點系統匣圖示還原視窗、開機自動啟動開關、設定入口
- 不包含：系統匣選單的其他項目

**驗收條件**
- [x] 第一次關閉視窗時詢問「縮到系統匣／結束程式」，附「記住我的選擇」；勾選後下次不再詢問
- [ ] 選縮到系統匣：視窗消失、系統匣出現圖示；點圖示還原視窗；右鍵選單只有「結束」，按下後程式結束
- [x] 設定裡可以更改關閉行為（每次詢問／縮到系統匣／結束程式）
- [ ] 開機自動啟動預設關閉；打開後重開機程式會自動啟動，直接縮在系統匣、不開視窗
- [ ] 程式縮在系統匣時，點 `osu-storage://` 連結或再執行一次 exe，會還原既有視窗，不會開第二個程式
- [x] 以上設定重開程式後維持

**實作設計**
- 前端
  - 套件：`window_manager`（攔截關閉、隱藏與還原）、`tray_manager`（系統匣）、`launch_at_startup`（開機啟動，寫 HKCU Run）；版本由實作挑選
  - `PrefsService` 新增 `closeAction`（`ask`／`tray`／`exit`，預設 `ask`）、`launchAtStartup`（預設 false）
  - 開機啟動時帶一個啟動參數（例如 `--autostart`），`main()` 看到就不顯示視窗、直接進系統匣
  - 設定入口：側欄底部新增設定按鈕，開啟設定對話框；T-06、T-10 的開關也放進來
  - `windows/runner/main.cpp`：沒帶連結時再次執行 exe 也要找到既有視窗並還原，而不是開第二個執行個體
- 邊界：新增 `TrayService` 包住 `tray_manager` 與 `window_manager`，其他程式只看到「隱藏到系統匣」「還原」「結束」

**依賴**：無

**風險 / 實作注意**
- app_links 的 `SendAppLinkToInstance()` 只在有連結參數時運作，且視窗隱藏時是否會還原要實測；不行就在 `main.cpp` 自己用 mutex＋`FindWindow` 處理
- 系統匣圖示用既有 app icon

**實作決定**
- 套件版本：`tray_manager` 用 `^0.5.3`，新版與 Flutter 3.44.4 不相容，升到 Flutter 3.47 以上後再換新版。`launch_at_startup` 用 `^0.5.1`，`window_manager` 用 `^0.5.2`。
- 開機自動啟動時，`windows/runner/flutter_window.cpp` 不呼叫 Show，視窗完全不閃現。實測成立。
- 關閉詢問對話框按叉或取消，視為不關閉。
- 帶 `--autostart` 啟動時，把工作目錄改回 exe 所在資料夾，`config.json` 才讀得到。啟動時把 Run 登錄值對齊目前 exe 路徑。
- 系統匣圖示以 asset 宣告 `windows/runner/resources/app_icon.ico`。
- 設定對話框用 `SettingsEntry` 清單組成，T-06、T-10 的開關以加項目的方式放入，不改對話框本身。
- 「風險 / 實作注意」第一條的結論：app_links 的 `SendAppLinkToInstance` 在沒有連結參數時，也會找到隱藏中的視窗並還原，所以 `windows/runner/main.cpp` 不需要改。實測再執行 exe 會還原原視窗。
- 後續事項：`PrefsService` 的 read-modify-write 沒有鎖，有競態；系統匣圖示的 asset 路徑依賴 `flutter_assets` 的目錄結構。
- 側欄底部只留設定齒輪與帳號頭像，自動上傳也搬進設定對話框（未登入時停用並顯示「登入後才能設定」）。
- 審查修正：`TrayService.start({minimized})`；系統匣初始化失敗只記 log、程式照常啟動；開機自動啟動時初始化失敗，改為顯示視窗，避免程式無視窗也無圖示。

**進度**：實作完成（2026-10-23）。單元／widget 測試已過；全套 CI（376 tests、`flutter build windows` 成功、analyze 無新增）與三輪獨立審查已完成並修正；人工驗證待做
- commit：63d6b4e、e3f9726、25e451d、4e5e465、ecd0a2e、7a0578a、3eabe47、7b1cc00、f953f93（feat/friends）
- 未驗：實機操作：驗收 2（系統匣圖示、點擊還原、右鍵結束）、驗收 4（重開機後自動啟動且縮在系統匣）、驗收 5（縮在系統匣時點連結或再執行 exe 會還原既有視窗）；首次關閉詢問的實際畫面；最大化後隱藏再還原

### T-09 收到好友邀請或推送時，看到紅點與 Windows 通知

**使用者價值**：不必自己去翻好友頁，也知道有人邀請或推圖給你。

**範圍**
- 包含：收到即時事件後更新列表與紅點、發 Windows 系統通知、點通知開啟對應畫面
- 不包含：程式沒開期間收到的內容補發 Windows 通知（規格決定只顯示紅點）

**驗收條件**
- [ ] 程式開著時（含縮在系統匣），收到新的好友邀請或推送後幾秒內跳出 Windows 通知，內容含對方代號；推送通知含附言開頭
- [x] 對方接受我的邀請後，我的好友列表幾秒內出現對方，不用手動重新整理
- [x] 側欄「好友」入口出現紅點，好友頁的「收到的邀請」「收件匣」顯示數量
- [ ] 點通知會還原視窗並切到對應分頁
- [x] 處理完邀請、推送都標為已讀後，紅點消失
- [x] 程式沒開期間收到的內容，下次開啟只顯示紅點，不跳 Windows 通知
- [x] 未登入時不顯示紅點

**實作設計**
- 前端
  - `lib/services/notification_service.dart`：訂閱 `RealtimeService`（T-12）的 `friend_request`、`friend_added`、`push`，更新 `FriendService`、`PushService` 並發通知。啟動或重連時的整份重新讀取只更新列表與紅點，不發通知
  - 套件：Windows toast 用 `local_notifier` 或同類套件，由實作挑選
  - `HomePage` 的「好友」destination 加 `Badge`；好友頁分頁標題帶數量
  - 點通知：透過 `TrayService` 還原視窗，切到好友頁對應分頁
- 後端：見後端 T-09

**依賴**：T-07（推送與未讀數；T-07 已依賴 T-01 的邀請）、T-08（縮在系統匣時的行為與還原視窗）、T-12（即時通道）

**實作決定**
- 〔使用者〕toast 套件用 `local_notifier ^0.1.6`，以 `ToastPlatform` 抽象包起來；第一次 `show` 才 `setup(appName: 'osu! Beatmap Viewer')`，點擊或關閉後 `destroy`。
- 〔使用者〕好友頁沒有分頁，卡上「切到對應分頁」「分頁標題帶數量」改解讀為：邀請通知切到好友頁並捲到「收到的邀請」，推送通知切到好友頁並開 `InboxPage`；「收到的邀請」header 原本就帶 (n)，收件匣圖示加 `Badge`。
- 〔使用者〕側欄好友 `Badge` 的數字為收到的邀請數加未讀推送數，超過 99 顯示 `99+`；未登入為 0。
- 〔使用者〕通知文案：邀請標題「{代號} 想加你為好友」、內文「點擊查看收到的邀請」；推送標題「{代號} 推送了圖譜給你」、內文為附言前 40 字（超過加 …），無附言時為「N 張圖譜」。每個事件各發一則；視窗在前景也發。
- 〔使用者〕點通知時若最上層是對話框或彈出選單，只還原視窗，不切頁也不 pop（避免輸入中的內容消失）；上層是一般頁面時，先 `popUntil` 回首頁層再切過去。
- 〔主〕不依賴 SSE payload 的內容：收到 `friend_request`、`push` 後，先記下重讀前的 id 集合，`refresh` 完以差集決定通知；推送只通知未讀；列表尚未載入時只重讀不通知。
- 〔實作〕已通知集合只由列表變動時的 prune 維護（該筆離開 incoming／inbox 就移除），換帳號時列表清空，集合隨之清掉。
- 〔實作〕重連重讀：`FriendService`、`PushService` 各自訂閱 `resyncRequested` 整份重讀（`PresenceService` 不再負責）。`NotificationService` 在重連時取兩者的 `loadInFlight`（在途讀取的 Future），事件處理先等它結束再取基準，所以斷線期間的項目不發 toast。已知限制：新項目若在重連重讀的 GET 之前就已存在於伺服器，會被當作斷線期間的項目，只顯示紅點。
- 〔實作〕`NotificationService.intent`（`ValueNotifier<NotificationTarget?>`，值為 invites／inbox）：點通知後先 `TrayService.restore()` 再設 intent，`HomePage` 切頁、`FriendsPage` 消費。

**進度**：實作完成（2026-10-23）。單元／widget 測試已過；全套 CI（376 tests、`flutter build windows` 成功、analyze 無新增）與三輪獨立審查已完成並修正；人工驗證待做
- commit：cd2b809、8ca80dc、8b83b56、6b6174d（feat/t09-notifications，已併入 feat/friends）；審查修正 7a1a74c、bfc79a5、a8bc48b、50f6b70、727ff3b、11970cf
- 已驗證（測試）：驗收 2、3、5、6、7 有單元／widget 測試；驗收 1、4 程式完成且有測試，但實機與雙帳號端到端未驗，故未勾
- 未驗（待人工）：toast 外觀與 AppUserModelID（開發版可能顯示預設名稱）、Focus Assist；縮在系統匣時收到通知與點通知還原；開著對話框時點通知只還原視窗；斷網恢復後紅點更新且不跳 toast；換帳號後同一人再邀會再通知

### T-10 好友看得到我正在玩 osu!lazer，好友列表能搜尋、排序

**使用者價值**：一眼看出哪些好友正在玩，好友多了也找得到人。

**範圍**
- 包含：偵測 osu!lazer 是否在執行並回報、上線狀態公開開關、好友列表顯示「遊玩中」、依遊玩中優先再依代號排序、用代號搜尋
- 不包含：正在玩哪張圖、只開桌面程式的狀態（規格決定只顯示遊玩中）

**驗收條件**
- [ ] A 開著桌面程式並啟動 osu!lazer，B 的好友列表幾秒內顯示 A「遊玩中」，並排到最前面，不用手動重新整理
- [ ] A 關掉 osu!lazer 或關掉桌面程式後，B 那邊幾秒內不再顯示遊玩中；程式異常結束或斷網時，最晚在連線逾時後不再顯示
- [x] 只開 osu! stable 不算遊玩中
- [ ] A 關掉上線狀態後，B 那邊不顯示 A 的狀態；開關預設開啟，重開程式後維持
- [x] 好友列表能用代號搜尋，排序為遊玩中優先，其餘依代號

**實作設計**
- 前端
  - `lib/services/presence_service.dart`：登入且開關開啟時，定期偵測 osu!lazer 程序（間隔由實作決定，數秒即可），狀態改變才回報 `PUT /social/presence`；關閉開關或登出時回報 `idle`
  - 偵測：依程序的執行檔路徑判斷是 lazer（預設安裝在 `%LOCALAPPDATA%\osulazer\`），避免把 stable 的 `osu!.exe` 算進去
  - 訂閱 `RealtimeService` 的 `presence` 更新 `FriendService` 的好友狀態
  - 好友頁：好友項目顯示遊玩中、搜尋框、排序；上線狀態開關（`/social/settings`）放在 T-08 的設定入口，T-08 還沒做時先放好友頁
- 後端：見後端 T-10

**依賴**：T-01（好友列表）、T-12（即時通道）

**風險 / 實作注意**：lazer 也可能裝在自訂位置；路徑判斷不可靠時，可改用 `PrefsService` 已設定的 osu 資料夾推算

**實作決定**
- `RealtimeService` 新增 `connected`（Listenable，每次連上都通知，含第一次）與 `isConnected`。`PresenceService` 每次連上都補送目前狀態，因為後端在 SSE 斷線時立刻視為 idle，且要先連上 SSE 才能 `PUT /social/presence`。
- `PresenceService` 讀到 `/social/settings` 之前不回報，避免開關是關的卻先送出 playing。
- 登出時不回報 idle，因為 token 已清除，後端靠 SSE 斷線處理。
- lazer 判定為執行檔路徑在 `%LOCALAPPDATA%\osulazer\` 底下，或同資料夾有 `osu.Game.dll`。不用 `PrefsService` 的 osu 資料夾推算，那是資料位置，推不出安裝位置。
- `win32`、`ffi` 宣告為直接依賴，沿用 lock 檔的版本。
- 上線狀態開關放在 T-08 的設定對話框。

**進度**：實作完成（2026-10-23）。單元／widget 測試已過；全套 CI（376 tests、`flutter build windows` 成功、analyze 無新增）與三輪獨立審查已完成並修正；人工驗證待做
- commit：23bd53d、ba454be、242d154、29e4b53、4a4e934（feat/friends）
- 未驗：雙帳號端到端：驗收 1（B 幾秒內看到 A 遊玩中並排最前）、驗收 2（A 關掉 lazer 或程式後消失，異常結束時逾時消失）、驗收 4（A 關掉上線狀態後 B 不顯示）；程式縮在系統匣時偵測 Timer 是否照跑；好友列表一列同時有遊玩中、看清單、選單時的版面

### T-12 [共用] 即時事件通道（SSE）

**使用者價值**：共用卡。T-09 的通知與 T-10 的上線狀態都要後端主動把事件送到桌面；後端也用「有沒有連線」判斷程式是否開著。

**範圍**
- 包含：桌面的 SSE 連線、重連與事件分派
- 不包含：任何事件型別的處理（T-09、T-10）

**驗收條件**
- [x] 登入後程式一直保持一條連線；登出或換帳號時斷開，換帳號後連到新帳號
- [x] 後端發的事件幾秒內分派給訂閱該型別的處理者
- [x] 斷網或後端重啟後自動重連（退避重試加隨機抖動），重連成功後發出「需要重新讀取」訊號
- [x] access token refresh 後，下次重連用新的 token
- [x] 連線失敗不彈窗、不影響其他功能

**實作設計**
- 前端
  - `lib/services/realtime_service.dart`：單例，登入後連 `GET /social/events`、登出或換帳號時斷開；解析 SSE 事件並依型別分派；斷線退避重連
  - SSE 用 `http` 套件的串流回應自行解析，不必另加套件；token 從 `AuthService` 取
- 介面
  - `RealtimeService.instance.on(String type, void Function(Map<String, dynamic>) handler)`：回傳取消訂閱的函式
  - `Listenable RealtimeService.instance.resyncRequested`：重連成功時通知，訂閱者整份重新讀取
- 後端：見後端 T-12

**依賴**：無（後端 T-12 要先上線才能端到端驗收）

**實作決定**
- 第一次連線不發 `resyncRequested`，只在重連成功時發。
- 加 idle watchdog：約 90 秒沒收到任何資料就強制重連。後端每 30 秒送一次 ping，連線逾時為 30 秒。
- 連續 401 只做退避重試，不呼叫 `markReloginRequired`。
- 串流正常結束（EOF）也視為斷線並重連。
- `RealtimeService.instance` 在 `main.dart` 建立。
- 換帳號的測試用兩個獨立的 `AuthService` 模擬。
- 審查修正：計時測試改用 `fake_async`（idle 計時改由自管 Timer），補「refresh 後用新 token 重連」「同一實例換帳號」測試。原註記的測試弱點與計時 flaky 已解決。

**進度**：實作完成（2026-10-23）。單元／widget 測試已過；全套 CI（376 tests、`flutter build windows` 成功、analyze 無新增）與三輪獨立審查已完成並修正；人工驗證待做
- commit：3ed755f、cdd82ac、3202afa（feat/friends）
- 未驗：經 Cloudflare Tunnel 閒置 5 分鐘是否被切斷（後端要求實測回報）；睡眠喚醒後重連

## 開工前待決

無。

拍板紀錄（2026-10-23）：推送可從雲端清單頁與圖譜查看頁挑圖；好友邀請連結為一次性；邀請、推送、上線狀態用後端推播（SSE）即時送達；開機自動啟動時直接縮在系統匣；好友代號由 auth server 批次查詢；好友邀請每人 24 小時最多 50 筆；關閉視窗第一次詢問，詢問前預設結束程式。
