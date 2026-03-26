-- ============================================================
--  sp_camera / client/main.lua
--  App 註冊、所有 NUI 回呼、測試指令
--  依賴：config.lua（shared）、client/camera.lua
-- ============================================================

-- ──────────────────────────────────────────────
--  Payload Builder
--  注意：以下欄位目前為推測與橋接用途
--  實際仍需依 qs-smartphone-pro 的 savePhoto handler 原始碼校正
--  取得原始碼後請修改此函式
-- ──────────────────────────────────────────────
local function buildPhotoPayload(url)
    return {
        -- 必填（推測）
        url        = url,

        -- TODO: 確認以下欄位是否被 handler 使用
        type       = Config.PayloadDefaults.type,
        source     = Config.PayloadDefaults.source,
        app        = Config.PayloadDefaults.app,
        date       = os.date('%Y-%m-%d %H:%M:%S'),
        uploadedAt = os.time(),

        -- TODO: 確認 metadata 結構，目前全部填 nil
        metadata = {
            width  = nil,
            height = nil,
            size   = nil,
        },
    }
end

-- ──────────────────────────────────────────────
--  儲存照片（共用邏輯）
--  payload 組裝 → server event → debug log
-- ──────────────────────────────────────────────
local function doSavePhoto(url)
    local payload = buildPhotoPayload(url)

    if Config.Debug then
        print('[sp_camera] [CLIENT] 觸發 savePhoto')
        print('[sp_camera] [CLIENT] Payload:')
        print(json.encode(payload, { indent = true }))
    end

    -- 橋接到官方 event
    -- TODO: 若 handler 需要額外欄位，在 buildPhotoPayload 中補上
    TriggerServerEvent('qs-smartphone:server:savePhoto', payload)

    return payload
end

-- ──────────────────────────────────────────────
--  App 註冊
--  TODO: 確認 addCustomApp export 正確名稱
--  TODO: 確認 icon / ui 路徑格式
-- ──────────────────────────────────────────────
local function registerApp()
    while GetResourceState('qs-smartphone-pro') ~= 'started' do
        Wait(500)
    end

    local rn = GetCurrentResourceName()

    exports['qs-smartphone-pro']:addCustomApp({
        app         = 'sp_camera',
        label       = 'Camera',
        description = 'Take photos and save to your gallery',
        icon        = ('nui://%s/ui/icon.png'):format(rn),
        ui          = ('nui://%s/ui/index.html'):format(rn),
        category    = 'social',
        -- TODO: 確認是否需要額外欄位（badge, color, age...）
    })

    print('[sp_camera] App 已成功註冊至 qs-smartphone-pro')
end

-- ──────────────────────────────────────────────
--  NUI 回呼：拍照（截圖模式）
-- ──────────────────────────────────────────────
RegisterNUICallback('takePhoto', function(data, cb)
    -- 立即回應避免 NUI 逾時
    cb({ acknowledged = true })

    CaptureAndUpload(

        -- onStart：準備截圖前呼叫
        function()
            if Config.HidePhoneBeforeCapture then
                -- 隱藏 sp_camera iframe 內容
                SendNUIMessage({ action = 'setVisible', visible = false })

                -- TODO: 確認 qs-smartphone-pro 是否提供隱藏手機 API
                -- 若有，在此呼叫：
                -- pcall(function() exports['qs-smartphone-pro']:hidePhone() end)

                Wait(Config.HidePhoneDelay)
            end
        end,

        -- onResult：上傳完成後呼叫
        function(success, photoUrl, errorMsg)
            -- 恢復手機顯示
            if Config.HidePhoneBeforeCapture then
                SendNUIMessage({ action = 'setVisible', visible = true })
                -- TODO: 若呼叫了 hidePhone，在此恢復：
                -- pcall(function() exports['qs-smartphone-pro']:showPhone() end)
            end

            if success and photoUrl then
                local payload = doSavePhoto(photoUrl)
                SendNUIMessage({
                    action  = 'captureResult',
                    success = true,
                    url     = photoUrl,
                    payload = json.encode(payload),
                })
            else
                print('[sp_camera] [CLIENT] 截圖失敗: ' .. tostring(errorMsg))
                SendNUIMessage({
                    action  = 'captureResult',
                    success = false,
                    error   = errorMsg or '未知錯誤',
                })
            end
        end
    )
end)

-- ──────────────────────────────────────────────
--  NUI 回呼：儲存照片（URL 手動模式）
-- ──────────────────────────────────────────────
RegisterNUICallback('savePhoto', function(data, cb)
    local url = data and data.url

    if not url or url == '' then
        cb({ success = false, error = 'URL 為空' })
        return
    end

    local payload = doSavePhoto(url)
    cb({ success = true, payload = json.encode(payload) })
end)

-- ──────────────────────────────────────────────
--  NUI 回呼：進入相機模式
--  按下「進入相機模式」按鈕時觸發
--  → SetNuiFocus(false,false)，角色可移動 + 鼠標控制視角
-- ──────────────────────────────────────────────
RegisterNUICallback('enterCameraMode', function(data, cb)
    cb({ acknowledged = true })  -- 立即回應，避免 NUI 等待
    EnterCameraMode()
end)

-- ──────────────────────────────────────────────
--  NUI 回呼：退出相機模式（從 NUI 按鈕觸發）
-- ──────────────────────────────────────────────
RegisterNUICallback('exitCameraMode', function(data, cb)
    cb({ acknowledged = true })
    ExitCameraMode()
end)

-- ──────────────────────────────────────────────
--  NUI 回呼：切換自拍 / 正拍
--  同步 F 鍵行為，供 NUI 自拍按鈕呼叫
-- ──────────────────────────────────────────────
RegisterNUICallback('toggleSelfie', function(data, cb)
    cb({ acknowledged = true })
    ToggleSelfieMode()
end)

-- ──────────────────────────────────────────────
--  NUI 回呼：關閉 App
-- ──────────────────────────────────────────────
RegisterNUICallback('closeApp', function(data, cb)
    -- 若在相機模式中關閉，先退出相機模式
    ExitCameraMode()
    SetNuiFocus(false, false)
    cb({ success = true })
end)

-- ──────────────────────────────────────────────
--  NUI 回呼：取得當前 Config（傳給前端顯示）
-- ──────────────────────────────────────────────
RegisterNUICallback('getConfig', function(data, cb)
    cb({
        provider  = Config.UploadProvider,
        debug     = Config.Debug,
        encoding  = Config.Screenshot.encoding,
        quality   = Config.Screenshot.quality,
        hidePhone = Config.HidePhoneBeforeCapture,
    })
end)

-- ──────────────────────────────────────────────
--  NUI 回呼：從前端更新 Config（當局 session 有效）
--  永久修改請直接編輯 config.lua
-- ──────────────────────────────────────────────
RegisterNUICallback('updateConfig', function(data, cb)
    if data.provider       then Config.UploadProvider             = data.provider       end
    if data.debug ~= nil   then Config.Debug                      = data.debug          end
    if data.encoding       then Config.Screenshot.encoding        = data.encoding       end
    if data.quality        then Config.Screenshot.quality         = tonumber(data.quality) end
    if data.hidePhone ~= nil then Config.HidePhoneBeforeCapture   = data.hidePhone      end

    -- API Key 更新（session 有效）
    if data.fivemanageKey and data.fivemanageKey ~= '' then
        Config.Fivemanage.ApiKey = data.fivemanageKey
        print('[sp_camera] Fivemanage API Key 已更新（僅限本 session）')
    end
    if data.imgbbKey and data.imgbbKey ~= '' then
        Config.Imgbb.ApiKey = data.imgbbKey
        print('[sp_camera] imgbb API Key 已更新（僅限本 session）')
    end
    if data.discordWebhook and data.discordWebhook ~= '' then
        Config.Discord.WebhookUrl = data.discordWebhook
        print('[sp_camera] Discord Webhook 已更新（僅限本 session）')
    end

    print('[sp_camera] Config 已更新')
    if Config.Debug then
        print('[sp_camera] 當前 Config:')
        print('  Provider : ' .. Config.UploadProvider)
        print('  Debug    : ' .. tostring(Config.Debug))
        print('  Encoding : ' .. Config.Screenshot.encoding)
        print('  Quality  : ' .. tostring(Config.Screenshot.quality))
    end

    cb({ success = true })
end)

-- ──────────────────────────────────────────────
--  測試指令：/testsavephoto [url]
--  不開手機 UI 直接測試 savePhoto event
-- ──────────────────────────────────────────────
RegisterCommand('testsavephoto', function(source, args, rawCommand)
    local url = args[1] or 'https://placehold.co/400x300/1a1a2e/ffffff?text=sp_camera+test'

    print('[sp_camera] [CMD] /testsavephoto')
    print('[sp_camera] [CMD] URL: ' .. url)

    local payload = doSavePhoto(url)

    print('[sp_camera] [CMD] 已觸發 qs-smartphone:server:savePhoto')
    print('[sp_camera] [CMD] 請觀察 server console 確認是否被正確處理')
end, false)

-- ──────────────────────────────────────────────
--  測試指令：/testcamera
--  直接觸發截圖 + 上傳流程，不需要開手機
-- ──────────────────────────────────────────────
RegisterCommand('testcamera', function()
    print('[sp_camera] [CMD] /testcamera — 開始截圖上傳測試')
    print('[sp_camera] [CMD] Provider: ' .. Config.UploadProvider)

    CaptureAndUpload(
        function()
            print('[sp_camera] [CMD] 準備截圖...')
        end,
        function(success, photoUrl, errorMsg)
            if success then
                print('[sp_camera] [CMD] 截圖成功 → ' .. photoUrl)
                doSavePhoto(photoUrl)
                print('[sp_camera] [CMD] savePhoto event 已觸發')
            else
                print('[sp_camera] [CMD] 截圖失敗: ' .. tostring(errorMsg))
            end
        end
    )
end, false)

-- ──────────────────────────────────────────────
--  手機資源重啟時重新註冊
-- ──────────────────────────────────────────────
AddEventHandler('onClientResourceStart', function(resourceName)
    if resourceName == 'qs-smartphone-pro' then
        print('[sp_camera] 偵測到 qs-smartphone-pro 重啟，重新註冊 App...')
        registerApp()
    end
end)

-- ──────────────────────────────────────────────
--  初始化
-- ──────────────────────────────────────────────
CreateThread(function()
    registerApp()
end)
