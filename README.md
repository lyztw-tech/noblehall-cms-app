# Noblehall CMS（iOS）

與 **constructionApp** 相同策略設定後端網址，實作於 `noblehall-cms-app/Core/Config/AppConfiguration.swift`。

## API 網址（`API_BASE_URL`）

- **完整 API root**，須含路徑 **`/api`**（對齊 Noblehall CMS 後端 `app.use('/api', …)`）。
- 例（本機）：`http://127.0.0.1:3000/api`
- 例（區網）：`http://192.168.1.50:3000/api`
- 例（正式）：`https://你的網域/api`

### 優先順序

1. 行程環境變數 **`API_BASE_URL`**（Xcode **Scheme → Run → Arguments → Environment Variables**）
2. **DEBUG** 且 **`FORCE_PRODUCTION_API=1`** → 使用 Release 預設字串（方便對正式站 smoke test）
3. 否則：**Debug** 用程式內 `debugDefaultAPIRootURLString`；**Release** 用 `productionAPIRootURLString`（上架前務必改成真實正式 URL，或改用 `.xcconfig` 注入）

### 與 Web 前端

| 客戶端 | 變數 | 內容 |
|--------|------|------|
| Web | `VITE_API_BASE_URL` | 通常為 origin，例如 `http://localhost:3000` |
| iOS | `API_BASE_URL` | **完整** root，例如 `http://127.0.0.1:3000/api` |

### HTTPS 檢查

`APIClient` 每次請求前會呼叫 `AppConfiguration.validateAPIBaseIsSecureForRequests()`：**Release 僅允許 https**；**Debug** 允許 `localhost` / `127.0.0.1` 與 RFC1918 區網的 **http**。

### ATS

正式環境請用 **HTTPS**。僅開發連本機／區網 **http** 時，若遇 ATS 擋連線，需在 Xcode **Info** 為開發組態設定例外（上架請用 HTTPS）。

## 登入「無法連線／Could not connect to the server」

1. 看登入頁 **「環境」** 列：目前 API root 是否與後端一致。  
2. **實機**：`127.0.0.1`／`localhost` 指向手機自己，**請勿使用**。請在 Xcode **Scheme → Run → Environment Variables** 新增 **`API_BASE_URL`**，值與前端 `.env.development` 的 **`VITE_API_BASE_URL`** 相同（例如 `http://192.168.0.71:3000/api`）。  
3. **模擬器**：預設 `http://127.0.0.1:3000/api` 通常可連 Mac 本機後端；若失敗，請確認後端已啟動、埠正確，或同樣用 `API_BASE_URL` 覆寫。  
4. **後端**：需監聽 **`0.0.0.0`**（或區網介面），否則實機用區網 IP 會連不到。  
5. 登入失敗時 App 會顯示較詳細的錯誤（含嘗試的 URL），請一併對照。
