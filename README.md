# osu_beatmap_storage
一個osu小程式，可以記錄下載的osu圖譜，方便在換電腦後不會遺失原有的圖譜。
只是隨便做的小程式，做的不好還請見諒~

## 運作原理
此程式分為 "保存" 及 "載入" 兩部分。

保存：讀取給定路徑中的圖譜，並將名稱保存至`save.txt`中。
載入：以`save.txt`的資料，自動從網路下載圖譜至電腦中。

## 使用方法
啟動及關閉程式：雙擊運行即可執行程式；將視窗關閉即可關閉程式。

保存圖譜：打開並複製圖譜資料夾的路徑，貼至輸入框後按下"生成紀錄"按鈕，生成的`save.txt`即為結果。

載入圖譜：將`save.txt`放入與程式同層的資料夾中，按下"下載圖譜"，程式將自動完成下載。

## 注意事項
* 載入圖譜為從網路下載圖譜，為避免下載過於頻繁，每個檔案下載後會有3秒的等待時間，若圖譜很多，將會需要一段時間進行下載。

* 下載時程式會將`.osz`檔下載至資料夾內，需自行手動開啟。

* 下載期間可使用電腦，但要注意不要將程式關閉，不然就只能重頭下載了。

## 版本紀錄
* Ver.1.0 程式推出
* Ver.1.1 移除執行程式時出現的黑窗、調整UI布局
* Ver.1.2 匯出的資料改以圖譜資料夾建立時間排序
