# iOS App Development Playbook

這份文件整理 NobleHall CMS App 從建立到目前為止踩過的坑、必要基礎、設定需求與操作流程。目標是：下次建立類似 App 時，先把環境、簽名、通知、後端串接、UI 規範與驗證流程一次準備好，之後主要專注在使用者需求與產品流程。

## 核心原則

- **環境不要靠分支管理**：Alpha、Beta、Production 應使用同一份程式碼，透過 Xcode Scheme、Build Configuration、`.xcconfig`、Bundle ID 與後端環境變數切換。
- **業務通知只走後端/APNs**：任務指派、待審核、退回、通過、到期提醒、badge 更新都應由後端建立通知並發送 APNs。
- **本機通知只處理裝置狀態**：離線後恢復連線、離線資料同步完成/失敗等，才由 App local notification 發送，不寫入後端通知中心，也不影響未讀數。
- **UI 規範要先抽成共用元件**：背景色、列表、表單、sheet、狀態 tag、toast、loading、empty state 都應先規格化，避免每個頁面各自實作。
- **錯誤訊息要前端轉譯**：不要直接顯示後端技術錯誤，App 應轉成使用者看得懂的中文訊息。
- **驗證要分層**：程式能編譯、API 能通、權限正確、通知會跳、badge 正確、前景/背景/滑掉 App 都要分開驗證。

## 建立時先準備的基礎

### App 專案基礎

- 建立清楚的模組結構，例如 `Core`、`Services`、`Features`、`UI`、`Config`。
- 建立共用 `APIClient`，統一處理 base URL、session cookie、headers、cache policy、錯誤解析。
- 建立 `AppConfiguration`，集中讀取 API URL、環境名稱、Bundle ID、App version。
- 建立共用 theme，例如背景色、狀態顏色、按鈕樣式、列表樣式、表單樣式。
- 建立全域 session store、root view、tab navigation、deep link coordinator。
- 建立 user-facing error translator，避免技術訊息直接出現在畫面上。

### 後端基礎

- API 需支援 App session / auth。
- 通知需有資料表、列表 API、未讀數 API、已讀 API、全部已讀 API、清除 API。
- 推播需有 device token 儲存表。
- 後端需能依 userId 找出所有推播訂閱，包含 Web Push 與 APNs token。
- 通知 API 不應被 HTTP cache 影響，需避免 `304 Not Modified` 造成 App 誤判。

### 環境基礎

- 建立 Alpha、Beta、Production 三種環境的後端 API URL。
- App 使用 Xcode Scheme / Build Configuration / `.xcconfig` 切換環境。
- 每個可安裝版本都應有明確 Bundle ID，例如：
  - Local / Debug
  - Alpha
  - Beta
  - Production
- App 顯示名稱也應可區分，例如 NobleHall Alpha、NobleHall Beta、NobleHall。
- Alpha / Beta 若要給測試者使用，應走 Archive / TestFlight 或正式內部分發流程，不應只靠 Xcode Build/Run。

## 必要需求

### 登入與 Session

- 登入後要建立 session。
- App 啟動時要能 bootstrap 使用者狀態。
- session 過期要導回登入，並顯示友善錯誤。
- 不要在登入鍵盤上加不必要的自訂工具列，例如多餘的「完成」按鈕。

### 任務與審核流程

- 我的任務與任務管理要與 Web 邏輯一致。
- 任務狀態 tab 要依權限與角色顯示資料，例如是否可指派、是否可審核。
- 執行中任務需支援「完成提交」，且只有執行人可操作。
- 進入負責人確認或待審核階段後，不可再新增執行紀錄。
- 負責人確認與審查人審查需有通過/退回 UI。
- 審核 bottom sheet 需支援回覆意見與照片。
- 進入審查階段或完成後，仍要能查看既有執行紀錄。
- 任務完成、提交、審核後，來源列表要刷新，避免回到列表看到舊狀態。

### 通知

- App 要能取得 APNs device token。
- App 登入後要把 token、environment、bundleId、appVersion、deviceName 上傳後端。
- 後端要儲存 token 並可更新 `lastSeenAt`。
- 後端建立業務通知後，要同時寫入通知資料與發送 APNs。
- 未讀數要同步到 App icon badge 與 tab badge。
- 通知點擊要能 deep link 到正確頁面，例如任務詳情。
- 無法解析 deep link 時，至少要導到通知列表。
- 全部已讀與清除通知要同步 badge 為 0。

### UI / UX

- 每個 page、sheet、form、list 都要使用規範背景色。
- 狀態要使用狀態 tag 原本顏色，不要只顯示純文字。
- 列表資訊呈現要符合情境，例如已選「指派自己」時不必再顯示執行人。
- 空資料、錯誤、loading 要有一致樣式。
- App 啟動需有合理 loading 畫面，避免突兀空白。
- 圖面點位沒有座標數字時，應用較小的點，不要使用圖釘樣式。

## 操作需求

### 本機開發

- 使用 Xcode Run 到實機測試 Debug。
- Debug APNs 使用 `aps-environment = development`，後端 token environment 應為 `sandbox`。
- 每次改 capability、entitlement、Bundle ID、provisioning profile 後，建議刪除 App、Clean Build Folder，再重新安裝。
- 若要測 APNs，必須使用實機，Simulator 不適合作為最終驗證。

### Alpha / Beta 發佈

- 使用對應 Scheme Archive。
- 使用對應 Bundle ID。
- 使用正確 signing certificate 與 provisioning profile。
- 若透過 TestFlight，APNs 通常走 production gateway，不是 sandbox。
- 發佈前確認 App 顯示名稱、API base URL、Bundle ID、APNs environment 都正確。
- 不要用單純 Xcode Build/Run 當 Alpha / Beta 分發方式。

### 通知驗證

- 前景：確認 banner、通知列表、tab badge、App icon badge。
- 背景：觸發業務通知，確認系統通知會跳。
- App 被滑掉：確認 APNs alert notification 仍可送達。
- 全部已讀：確認未讀數與 badge 歸零，不應再因舊輪詢跳通知。
- 清除通知：確認列表清空、未讀數歸零、badge 歸零。
- Deep link：確認點擊通知能進入指定任務或通知列表 fallback。

### 後端驗證

- 確認 `/api/notifications/unread-count` 回 `200`，不要回 `304`。
- 確認 APNs token 已寫入 `apns_device_tokens`。
- 確認 token 的 `environment` 與實際 App 簽名一致。
- 確認 APNs 失敗時後端會記錄錯誤，例如 `BadDeviceToken`、`DeviceTokenNotForTopic`。
- 確認 invalid token 會被清理，避免後續一直重送失敗。

## 設定類需求

### Xcode / Apple Developer

- Apple Developer 帳號。
- Bundle ID 開啟 Push Notifications。
- App Target 加入 `Push Notifications` capability。
- App Target 加入 `Background Modes`，並勾選 `Remote notifications`。
- Entitlements 需包含 `aps-environment`。
- `APS_ENVIRONMENT` 要在 Debug / Release / Alpha / Beta / Production 都有明確值。
- Provisioning profile 必須包含 push entitlement。

### APNs 後端

- 建立 APNs Auth Key (`.p8`)。
- `.p8` 放在後端本機或部署環境的安全位置，例如 `secrets/`，不可提交 Git。
- `.gitignore` 需忽略 `secrets/` 與 `*.p8`。
- `.env` 需設定：
  - `APNS_KEY_ID`
  - `APNS_TEAM_ID`
  - `APNS_PRIVATE_KEY_PATH`
  - Alpha / Beta / Production 對應 Bundle ID
- 後端需依 token environment 選擇 APNs sandbox 或 production endpoint。

### HTTP / Cache

- App 的 API request 應避免通知 API 被本機 cache。
- 後端 notification routes 應設定 `Cache-Control: no-store`。
- 後端應忽略或清掉 notification API 的 `If-None-Match`、`If-Modified-Since`。

### 權限

- App 請求通知權限時要包含 `.alert`、`.sound`、`.badge`。
- 若已授權但 badgeSetting 不是 enabled，需提醒使用者到 iOS 設定開啟 Badges。
- 任務審核 UI 必須依使用者權限與任務角色顯示，不是所有人都可看到。

## 這次踩過的坑

### APNs entitlement 不完整

問題：App 註冊 APNs 時出現「找不到有效 aps-environment 授權字串」。

原因：只有部分 xcconfig 有設定 `APS_ENVIRONMENT`，但 Debug / Release build setting 沒有完整設定。

解法：確認所有 build configuration 都有 `APS_ENVIRONMENT`，並確認 entitlements 使用 `$(APS_ENVIRONMENT)`。

### APNs token 有拿到，但後端送不出去

可能原因：

- `.p8` path 放錯。
- `APNS_KEY_ID` 或 `APNS_TEAM_ID` 不正確。
- token environment 與 APNs endpoint 不一致。
- bundleId 與 `apns-topic` 不一致。
- TestFlight 使用 production APNs，但後端當成 sandbox 送。

### App icon badge 不出現

可能原因：

- iOS App 通知設定中 Badges 被關閉。
- App 一開始請求通知權限時沒有包含 `.badge`。
- unread count API 被 cache 成 `304`。
- App 沒有成功呼叫 `setBadgeCount`。
- 後端未讀數與 App 本地狀態不同步。

### 全部已讀後又跳通知

原因：可能是舊 APNs 已送到 Apple 佇列，iOS 晚一點才顯示；或 App 輪詢/SSE 用舊基準值補發本機通知。

解法：業務通知不要由 App 本機補發，全部已讀只同步 unread count 與 badge。

### 同一筆通知跳兩次

原因：同一筆業務通知同時由後端 APNs 顯示一次，App 前景 SSE 又補發 local notification 一次。

解法：業務通知只走後端/APNs。SSE / polling 只刷新畫面、列表與 badge。

### 通知列表只有一筆，但 banner 跳兩次

這是同一筆通知有兩個顯示來源，不是資料建立兩筆。修正方式同上。

### Deep link 打不開任務

原因：後端通知 link 格式與 App parser 支援格式不一致。

解法：App deep link parser 需支援所有後端可能發出的 link，例如 `/projects/{projectCode}/quality/task-management/{taskId}`。

### 已讀數 API 回 304

問題：App 把 `304 Not Modified` 當錯誤，導致 unread count 被重設或不同步。

解法：通知 API 禁用 HTTP cache，App request 也加上 no-cache policy。

### Prisma client type 沒更新

問題：新增 Prisma model 後，dev server 還使用舊 Prisma Client type。

解法：重新 generate Prisma Client，必要時重啟 dev server 或觸發 nodemon 完整重啟。

### Xcode command line tool 無法 build

問題：本機只有 CommandLineTools，`xcodebuild` 需要完整 Xcode developer directory。

解法：可先用 `plutil`、`xmllint` 做靜態檢查；真正 build/archive 需在 Xcode 或正確 developer directory 下執行。

### 權限 UI 顯示太寬

問題：待指派、待審核、審核按鈕等 UI 對所有人顯示。

解法：App 要依後端權限、任務角色、任務狀態共同判斷，不只看狀態。

### 任務操作後列表沒刷新

問題：在 detail 完成提交或審核後，回列表仍看到舊狀態。

解法：Detail view 需提供 `onTaskChanged` callback，父層列表收到後重新 load。

### 審查階段仍可新增執行紀錄

問題：App 邏輯與 Web 不一致。

解法：負責人確認、待審核、已完成等階段應禁止新增執行紀錄，但仍允許查看既有紀錄。

### UI 背景不一致

問題：SwiftUI `List`、`Form`、sheet 常會顯示系統預設背景。

解法：建立 `.nobleHallScreen()`、`.nobleHallGroupedListStyle()`、`.nobleHallFormStyle()` 等共用 modifier，所有頁面都套用。

### 後端錯誤直接顯示給使用者

問題：技術錯誤不適合給使用者看。

解法：App 建立 user-facing error mapping，將常見 HTTP status 與後端錯誤轉成中文友善描述。

## 下次開新 App 的建議順序

1. 建立 App 專案結構、theme、APIClient、session、navigation。
2. 建立環境設定：Debug / Alpha / Beta / Production。
3. 建立 Bundle ID、display name、scheme、xcconfig。
4. 設定 Apple Developer、signing、entitlements、capabilities。
5. 建立後端通知資料表與 API。
6. 建立 APNs token registration 與後端 APNs sending。
7. 建立通知列表、未讀數、badge、deep link。
8. 建立錯誤訊息轉譯層。
9. 建立核心業務頁面與權限判斷。
10. 補上前景、背景、滑掉 App、全部已讀、清除通知的驗證清單。
11. Alpha / Beta 走 Archive / TestFlight，確認 APNs production gateway 行為。
12. 最後才開始大量堆使用者需求，避免邊做功能邊補環境地基。

## AI 可優先協助的工作

- 建立共用 API client、config、theme、錯誤轉譯。
- 建立 Xcode config / scheme / xcconfig 的初版。
- 建立後端資料表、migration、repository、service、controller、route。
- 建立 App 通知流程、device token upload、deep link parser。
- 建立文件與驗證 checklist。
- 對照 Web 行為補齊 App UI 與權限邏輯。
- 排查 log、API response、APNs error、badge 不同步問題。

## 人需要先準備的資料

- Apple Developer 帳號與 Team ID。
- Bundle ID 命名規則。
- Alpha / Beta / Production 後端 URL。
- APNs Auth Key (`.p8`) 與 Key ID。
- App display name 規則。
- 哪些通知屬於業務通知，哪些屬於本機裝置通知。
- 權限規則與角色定義。
- 測試帳號與測試資料。
