# osu! Beatmap Storage

一個基於 Flutter 的 osu!lazer 圖譜管理工具，可直接讀取本機 `client.realm` 資料庫，瀏覽、搜尋、匯出並下載圖譜集。

## 功能特色

- **即時讀取** — 直接解析 osu!lazer 的 `client.realm`，無需額外匯出
- **全文搜尋** — 依標題（含日文/中文）、藝術家即時篩選
- **匯出 CSV** — 含 UTF-8 BOM，可直接以 Excel 開啟（含中文不亂碼）
- **匯入 CSV** — 讀取先前匯出的 CSV，在不同電腦上也能重現圖譜清單
- **一鍵下載** — 透過 [osu.direct](https://osu.direct) 下載 `.osz`，支援斷點重試
- **批量下載** — 將整個清單（或篩選後的結果）一次性加入下載佇列
- **下載佇列管理** — 即時進度條、取消、重試、略過（已存在）功能
- **回放轉影片** — 支援將 osu!lazer 回放檔轉換為 `.mp4`，並可自選 skin
- **圖譜加入日期** — 圖譜查看頁面顯示圖譜加入收藏的日期

## 系統需求

| 項目 | 需求 |
|------|------|
| 作業系統 | Windows 10 / 11 |
| Flutter | 3.x 以上 |
| osu!lazer | 任意已安裝版本 |

## 專案架構

```
lib/
├── main.dart                 # 應用程式入口
├── app.dart                  # MaterialApp 設定
├── constants.dart            # 全域常數（Realm 路徑、下載 URL、狀態標籤）
├── models/
│   ├── osu_realm_models.dart        # Realm 資料模型定義
│   ├── osu_realm_models.realm.dart  # Realm 自動生成程式碼
│   ├── csv_row.dart                 # CSV 列資料類別
│   └── download_job.dart            # 下載任務狀態 & 資料類別
├── utils/
│   └── csv_parser.dart       # CSV 解析工具（RFC 4180 相容）
├── services/
│   ├── realm_service.dart    # Realm 開啟邏輯（自動偵測 schema 版本）
│   ├── download_service.dart # 下載佇列服務（ChangeNotifier）
│   └── prefs_service.dart    # 使用者偏好設定（持久化 Realm 路徑）
├── widgets/
│   ├── beatmap_set_tile.dart      # 圖譜集列表項目
│   ├── beatmap_detail_sheet.dart  # 難度清單 Bottom Sheet
│   ├── difficulty_tile.dart       # 單一難度項目
│   ├── mode_icon.dart             # 遊戲模式圖示
│   ├── download_button.dart       # 下載狀態按鈕
│   ├── download_job_tile.dart     # 下載佇列項目
│   ├── csv_picker_dialog.dart     # CSV 檔案選擇對話框
│   └── csv_row_tile.dart          # CSV 圖譜集列表項目
└── pages/
    ├── beatmap_list_page.dart  # 主頁（圖譜列表）
    ├── csv_import_page.dart    # CSV 匯入頁面
    └── download_queue_page.dart # 下載佇列頁面
```

## 銘謝

- 回放轉影片功能由 [danser-go](https://github.com/Wieku/danser-go) 提供支援，感謝 [Wieku](https://github.com/Wieku) 的出色開源工具。

## 注意事項

- 下載來源為第三方映像站 [osu.direct](https://osu.direct)，若遇到 404 或連線失敗會自動重試最多 3 次
- 每筆下載之間有 3 秒延遲，避免對映像站造成過大壓力
- 下載的 `.osz` 檔案存放於程式執行目錄下的 `osu_downloads/` 資料夾，需自行手動開啟匯入 osu!

## 版本紀錄

見 [CHANGELOG.md](CHANGELOG.md)。
