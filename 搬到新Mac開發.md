# 在新 Mac 繼續開發 VELO

此包是 2026-09-17 当前工作樹的完整原生 iOS 專案快照，包含未提交的最新修改。

1. 解壓縮後，把 speed_project 資料夾放到你的開發目錄。
2. 安裝 Xcode（此前驗證版本為 26.0.1，Swift 6），並安裝 iOS 模擬器 runtime。
3. 開啟 ios/Velo.xcodeproj，選擇 Velo Scheme 和可用的 iPhone 模擬器，按 Run。
4. 真機開發時，在 Xcode 登入 Apple 開發者帳號，在 Signing & Capabilities 選擇自己的 Team；按需要調整 Bundle Identifier。新 Mac 的簽名證書由 Xcode 管理。
5. Product → Test 可執行測試。最近一次驗證為 2026-09-14，37 項 XCTest 全部通過；本次僅打包，沒有重新測試。

## 包含內容

- Xcode 工程與共用 Scheme、全部 Swift 原始碼、測試、圖示素材、啟動畫面、Info.plist 與隱私清單。
- 最新白底 V logo 啟動動畫、設定與關閉圖示、留言接口／WebView、自動取得新 URL、下拉刷新。
- README.md、PROJECT_HANDOFF.md、ios/README.md、ios/FEEDBACK_WEBVIEW.md 和 .gitignore。

## 搬機注意

- 無第三方套件，無需 npm、CocoaPods 或額外服務才能使用原生測速。
- 真實接口配置目前留空；需要联网接口功能時，在 ios/Velo/Services/FeedbackAPIClient.swift 填入真实配置，協議見 ios/FEEDBACK_WEBVIEW.md。
- 不包含可重建的 ios/.build 編譯產物、Xcode 個人狀態，以及指向舊 Mac 的 .git 工作樹連結。此 ZIP 不含 Git 歷史，可在新位置自行 git init。
- 不包含舊 Mac 的鑰匙圈、簽名證書、模擬器及手機內的 App 資料。
- 交接文件內舊 Mac 的絕對路徑、裝置 ID 和 .build 測試結果路徑只是歷史紀錄，新 Mac 請以解壓目錄與自己的裝置為準。
