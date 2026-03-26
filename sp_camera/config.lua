-- ============================================================
--  sp_camera / config.lua
--  所有可調整設定集中在這裡
--  shared_script：client 與 server 都能讀取
-- ============================================================

Config = {}

-- ──────────────────────────────────────────────
--  Debug 模式
-- ──────────────────────────────────────────────
Config.Debug = true   -- true = 在 console 印出詳細 log

-- ──────────────────────────────────────────────
--  截圖品質
-- ──────────────────────────────────────────────
Config.Screenshot = {
    encoding = 'jpg',   -- 'jpg' | 'png' | 'webp'
    quality  = 0.92,    -- 0.0（最低）~ 1.0（最高），jpg 建議 0.85~0.95
}

-- ──────────────────────────────────────────────
--  拍照前是否嘗試隱藏手機 UI
--  TODO: 完整隱藏需要 qs-smartphone-pro 提供 hidePhone export
--        目前僅能隱藏 sp_camera 自身的 iframe 內容
-- ──────────────────────────────────────────────
Config.HidePhoneBeforeCapture = false
Config.HidePhoneDelay         = 300    -- ms（等待 UI 消失後再截圖）

-- ──────────────────────────────────────────────
--  上傳服務（選一個）
--  可用值：'fivemanage' | 'imgbb' | 'discord' | 'custom'
-- ──────────────────────────────────────────────
Config.UploadProvider = 'fivemanage'

-- Fivemanage（推薦，FiveM 生態圈最常用）
-- 申請：https://fivemanage.com
Config.Fivemanage = {
    ApiKey   = 'YOUR_FIVEMANAGE_API_KEY',   -- TODO: 填入你的 API Key
    Endpoint = 'https://api.fivemanage.com/api/v3/file',
    Field    = 'file',
    -- response 結構：{ data: { url: '...' }, status: 'ok' }
}

-- imgbb（免費方案可用）
-- 申請：https://api.imgbb.com
Config.Imgbb = {
    ApiKey = 'YOUR_IMGBB_API_KEY',   -- TODO: 填入你的 API Key
    -- response 結構：{ data: { url: '...' }, success: true }
}

-- Discord Webhook（最快速，但 CDN URL 可能有時效性）
Config.Discord = {
    WebhookUrl = 'YOUR_DISCORD_WEBHOOK_URL',  -- TODO: 填入 Webhook URL
    -- response 結構：{ attachments: [{ proxy_url: '...' }] }
}

-- 自訂 API
Config.Custom = {
    Url          = 'https://your-api.example.com/upload',
    Field        = 'image',
    Headers      = {},
    -- ResponsePath：從 response JSON 取 URL 的路徑，支援 dot-path，例如 'data.image.url'
    ResponsePath = 'url',
}

-- ──────────────────────────────────────────────
--  Payload Builder 預設值
--  TODO: 拿到 qs-smartphone-pro handler 原始碼後在此校正欄位
-- ──────────────────────────────────────────────
Config.PayloadDefaults = {
    type   = 'image',   -- TODO: 確認是否需要
    app    = 'sp_camera',
    source = 'sp_camera',
}
