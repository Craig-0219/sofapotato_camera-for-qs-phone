# sp_camera — 安裝與測試說明

## 檔案樹

```
sp_camera/
├── fxmanifest.lua          # resource 描述與檔案清單
├── client/
│   └── main.lua            # 客戶端：App 註冊、NUI 回呼、測試指令
├── server/
│   └── main.lua            # 伺服器端：debug log（旁聽 savePhoto event）
└── ui/
    ├── index.html          # NUI 頁面（手機內的 App UI）
    ├── style.css           # 樣式（暗色相機風格）
    ├── app.js              # 前端邏輯（NUI ↔ Lua 通訊）
    └── icon.png            # App 圖示（需替換為實際 PNG）
```

---

## 安裝步驟

1. 把整個 `sp_camera/` 資料夾複製到 FiveM server 的 resources 目錄
2. 在 `server.cfg` 加入：
   ```
   ensure sp_camera
   ```
   > 必須在 `qs-smartphone-pro` **之後** ensure
3. 替換 `ui/icon.png`（建議 96×96 PNG，深色背景）
4. 重啟 server 或執行 `refresh` + `ensure sp_camera`

---

## 測試流程

### 方法 A：透過手機 UI 測試
1. 在遊戲內打開手機
2. 找到 **Camera** app（category: social）
3. 輸入任意圖片 URL，例如：
   ```
   https://placehold.co/400x300/1a1a2e/ffffff?text=sp_camera+test
   ```
4. 按「預覽」確認 URL 有效
5. 按「儲存至手機相簿」
6. 觀察 console log + 手機相簿是否出現照片

### 方法 B：指令測試（不需開手機）
在遊戲內聊天框輸入：
```
/testsavephoto https://i.imgur.com/yourimage.jpg
```
省略 URL 時使用內建 placeholder URL。

---

## Debug 重點

### Client Console 應該看到：
```
[sp_camera] App 已成功註冊至 qs-smartphone-pro
[sp_camera] [CLIENT] savePhoto payload:
{
  "url": "...",
  "type": "image",
  ...
}
[sp_camera] [CLIENT] 已觸發 qs-smartphone:server:savePhoto
```

### Server Console 應該看到：
```
[sp_camera] [SERVER] 偵測到 savePhoto event | 玩家 ID: X
[sp_camera] [SERVER] 收到 Payload: { ... }
```

若 server 有 log 但相簿沒更新 → payload 欄位需校正（見下）

---

## 常見問題排查

| 問題 | 可能原因 | 解法 |
|------|----------|------|
| App 沒出現在手機 | `addCustomApp` export 名稱錯誤 | 確認官方 export 函式名稱 |
| App 出現但點進去空白 | `ui` 路徑格式不對 | 改為相對路徑或確認 `nui://` 格式 |
| Server 無 log | event 名稱不對 | 確認 `qs-smartphone:server:savePhoto` 拼寫 |
| Server 有 log 但相簿沒更新 | payload 欄位格式不符 | 比對官方 handler 原始碼調整 `buildPhotoPayload` |
| NUI 無法關閉 | `closeApp` callback 問題 | 確認 `SetNuiFocus(false, false)` 有無效 |

---

## 取得 handler 原始碼後的調整方式

拿到 `qs-smartphone-pro` 的 `savePhoto` server handler 後：

1. 對照 handler 期望的 payload 欄位
2. 修改 `client/main.lua` 中的 `buildPhotoPayload(url)` 函式
3. 移除不需要的欄位，補上缺少的欄位
4. 更新 `ui/app.js` 中的 debug payload 顯示邏輯（如有需要）

---

## 未來升級成真正相機

詳見各檔案中的 `TODO` 註解，整體升級路徑：

1. **開啟遊戲相機**：使用 FiveM 原生相機 API（`SetCamActive` 等）
2. **擷取截圖**：`exports['screenshot-basic']:requestScreenshotUpload(...)` 或 Fivemanage API
3. **取得 URL**：callback 回傳上傳後的圖片 URL
4. **自動填入並儲存**：直接呼叫 `TriggerServerEvent('qs-smartphone:server:savePhoto', payload)`

---

## 待確認項目（TODO 清單）

- [ ] `addCustomApp` export 正確名稱（可能是 `addApp`）
- [ ] icon / ui 路徑格式（`nui://` vs 相對路徑）
- [ ] `savePhoto` payload 完整欄位格式
- [ ] 是否需要 `playerIdentifier` / `citizenid` 等玩家識別欄位
- [ ] 官方 handler 是否有來源驗證（只接受指定 resource 的 event）
- [ ] 相簿是否需要額外 refresh event
- [ ] category 可用值列表
