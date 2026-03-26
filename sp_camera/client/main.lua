-- ============================================================
--  sp_camera / client/main.lua
--  客戶端主程式
--  整合方式：參照 custom-app-template 官方模式
-- ============================================================

-- ──────────────────────────────────────────────
--  Payload Builder
--  注意：以下欄位目前為推測與橋接用途
--  實際仍需依 qs-smartphone-pro 的
--  qs-smartphone:server:savePhoto handler 原始碼校正
--  不可視為官方已確認格式
-- ──────────────────────────────────────────────
local function buildPhotoPayload(url)
    return {
        -- 必填（推測）：照片 URL
        url         = url,

        -- TODO: 確認 qs-smartphone-pro 是否使用此欄位
        type        = 'image',

        -- TODO: 確認來源識別欄位名稱（可能是 app / source / resourceName）
        source      = GetCurrentResourceName(),

        -- TODO: 確認 app 識別欄位是否需要
        app         = 'sp_camera',

        -- TODO: 確認日期格式（epoch / ISO string / 其他）
        date        = os.date('%Y-%m-%d %H:%M:%S'),
        uploadedAt  = os.time(),

        -- TODO: 確認 metadata 結構；目前全部填 nil（未知）
        metadata = {
            width  = nil,
            height = nil,
            size   = nil,
        },
    }
end

-- ──────────────────────────────────────────────
--  App 註冊
--  等待 qs-smartphone-pro 啟動後掛載 app
--  TODO: 確認 export 函式名稱是 addCustomApp 還是 addApp
--  TODO: 確認 icon / ui 路徑格式（nui:// 或相對路徑）
--  TODO: 確認是否需要額外欄位（badge, color, age, notifications...）
-- ──────────────────────────────────────────────
local function registerApp()
    -- 等待手機資源啟動
    while GetResourceState('qs-smartphone-pro') ~= 'started' do
        Wait(500)
    end

    local resourceName = GetCurrentResourceName()

    -- 沿用官方 custom-app-template 的 addCustomApp export 模式
    exports['qs-smartphone-pro']:addCustomApp({
        app         = 'sp_camera',
        label       = 'Camera',
        description = 'Custom camera app — qs-smartphone-pro integration test',

        -- TODO: 確認 icon 路徑格式
        icon        = ('nui://%s/ui/icon.png'):format(resourceName),

        -- TODO: 確認 UI 路徑格式（有些版本用相對路徑）
        ui          = ('nui://%s/ui/index.html'):format(resourceName),

        -- TODO: 確認 category 可用值（social / media / tools / ...）
        category    = 'social',

        -- TODO: 確認是否需要 age / notifications / color 等欄位
    })

    print(('[sp_camera] App 已成功註冊至 qs-smartphone-pro | resource: %s'):format(resourceName))
end

-- ──────────────────────────────────────────────
--  NUI 回呼：儲存照片
--  流程：NUI → client Lua → TriggerServerEvent
-- ──────────────────────────────────────────────
RegisterNUICallback('savePhoto', function(data, cb)
    local url = data and data.url

    -- 基本驗證
    if not url or url == '' then
        print('[sp_camera] [ERROR] savePhoto：URL 為空，中止')
        cb({ success = false, error = 'URL is empty' })
        return
    end

    -- 組裝 payload
    local payload = buildPhotoPayload(url)

    -- Debug：完整印出 payload（方便校正欄位）
    print('[sp_camera] [CLIENT] savePhoto payload:')
    print(json.encode(payload, { indent = true }))

    -- 橋接到官方 event
    -- TODO: 確認此 server event 所需完整欄位後更新 buildPhotoPayload
    TriggerServerEvent('qs-smartphone:server:savePhoto', payload)
    print('[sp_camera] [CLIENT] 已觸發 qs-smartphone:server:savePhoto')

    cb({ success = true, payload = json.encode(payload) })
end)

-- ──────────────────────────────────────────────
--  NUI 回呼：關閉 App
-- ──────────────────────────────────────────────
RegisterNUICallback('closeApp', function(data, cb)
    SetNuiFocus(false, false)
    SendNUIMessage({ action = 'resetUI' })
    cb({ success = true })
end)

-- ──────────────────────────────────────────────
--  測試指令：/testsavephoto [url]
--  不開手機 UI 也能直接測試 savePhoto event
--  用法：/testsavephoto https://i.imgur.com/yourimage.jpg
-- ──────────────────────────────────────────────
RegisterCommand('testsavephoto', function(source, args, rawCommand)
    -- 預設使用 placeholder URL
    local testUrl = args[1] or 'https://placehold.co/400x300/1a1a2e/ffffff?text=sp_camera+test'

    local payload = buildPhotoPayload(testUrl)

    print('[sp_camera] [CMD] /testsavephoto 觸發')
    print('[sp_camera] [CMD] 測試 URL: ' .. testUrl)
    print('[sp_camera] [CMD] 完整 Payload:')
    print(json.encode(payload, { indent = true }))

    -- 直接觸發 server event
    TriggerServerEvent('qs-smartphone:server:savePhoto', payload)

    print('[sp_camera] [CMD] 已觸發 qs-smartphone:server:savePhoto')
    print('[sp_camera] [CMD] 請查看 server console 確認是否被 qs-smartphone-pro 正確處理')
end, false)

-- ──────────────────────────────────────────────
--  手機資源重啟時自動重新註冊
--  與官方 template 模式一致
-- ──────────────────────────────────────────────
AddEventHandler('onClientResourceStart', function(resourceName)
    if resourceName == 'qs-smartphone-pro' then
        print('[sp_camera] 偵測到 qs-smartphone-pro 重啟，重新註冊 App...')
        registerApp()
    end
end)

-- ──────────────────────────────────────────────
--  初始化入口
-- ──────────────────────────────────────────────
CreateThread(function()
    registerApp()
end)
