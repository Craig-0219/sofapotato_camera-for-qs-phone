-- ============================================================
--  sp_camera / client/camera.lua
--  截圖核心邏輯：取得上傳設定、呼叫 screenshot-basic、解析回應
--  必須在 client/main.lua 之前載入（fxmanifest client_scripts 順序）
-- ============================================================

-- ──────────────────────────────────────────────
--  取得上傳設定（依 Config.UploadProvider）
-- ──────────────────────────────────────────────
local function getUploadConfig()
    local p = Config.UploadProvider

    if p == 'fivemanage' then
        return {
            url     = Config.Fivemanage.Endpoint,
            field   = Config.Fivemanage.Field,
            headers = { Authorization = Config.Fivemanage.ApiKey },
        }

    elseif p == 'imgbb' then
        return {
            url     = ('https://api.imgbb.com/1/upload?key=%s'):format(Config.Imgbb.ApiKey),
            field   = 'image',
            headers = {},
        }

    elseif p == 'discord' then
        return {
            url     = Config.Discord.WebhookUrl,
            field   = 'files[]',
            headers = {},
        }

    elseif p == 'custom' then
        return {
            url     = Config.Custom.Url,
            field   = Config.Custom.Field,
            headers = Config.Custom.Headers or {},
        }
    end

    print('[sp_camera] [ERROR] 未知的 UploadProvider: ' .. tostring(p))
    return nil
end

-- ──────────────────────────────────────────────
--  從上傳回應中解析圖片 URL
--  各 provider 的 response 結構不同，分別處理
-- ──────────────────────────────────────────────
local function parseUploadResponse(rawData, provider)
    if not rawData or rawData == '' then
        print('[sp_camera] [ERROR] 上傳回應為空字串')
        return nil
    end

    local ok, resp = pcall(json.decode, rawData)
    if not ok or type(resp) ~= 'table' then
        print('[sp_camera] [ERROR] 無法解析 JSON 回應: ' .. tostring(rawData):sub(1, 200))
        return nil
    end

    provider = provider or Config.UploadProvider

    if provider == 'fivemanage' then
        -- { data: { id: '...', url: '...' }, status: 'ok' }
        if resp.data and resp.data.url then
            return resp.data.url
        end
        print('[sp_camera] [ERROR] Fivemanage: 找不到 data.url | ' .. json.encode(resp))

    elseif provider == 'imgbb' then
        -- { data: { url: '...', display_url: '...' }, success: true }
        if resp.data and resp.data.url then
            return resp.data.url
        end
        print('[sp_camera] [ERROR] imgbb: 找不到 data.url | ' .. json.encode(resp))

    elseif provider == 'discord' then
        -- { attachments: [{ url: '...', proxy_url: '...' }] }
        if resp.attachments and resp.attachments[1] then
            return resp.attachments[1].proxy_url or resp.attachments[1].url
        end
        print('[sp_camera] [ERROR] Discord: 找不到 attachments[1].url | ' .. json.encode(resp))

    elseif provider == 'custom' then
        -- 支援 dot-path，例如 'data.image.url'
        local path = Config.Custom.ResponsePath or 'url'
        local val  = resp
        for segment in path:gmatch('[^%.]+') do
            if type(val) ~= 'table' then
                print('[sp_camera] [ERROR] Custom ResponsePath 解析在 "' .. segment .. '" 中斷')
                return nil
            end
            val = val[segment]
        end
        if type(val) == 'string' then
            return val
        end
        print('[sp_camera] [ERROR] Custom: ResponsePath="' .. path .. '" 解析結果非字串 | ' .. json.encode(resp))
    end

    return nil
end

-- ──────────────────────────────────────────────
--  主要截圖 + 上傳函式（全域，供 main.lua 呼叫）
--
--  @param onStart   function()              -- 截圖前呼叫（可用來隱藏 UI）
--  @param onResult  function(ok, url, err)  -- 上傳完成後呼叫
-- ──────────────────────────────────────────────
function CaptureAndUpload(onStart, onResult)
    -- 確認 screenshot-basic 已啟動
    if GetResourceState('screenshot-basic') ~= 'started' then
        local msg = 'screenshot-basic resource 未運行\n請在 server.cfg 加入 ensure screenshot-basic'
        print('[sp_camera] [ERROR] ' .. msg)
        if onResult then onResult(false, nil, msg) end
        return
    end

    local uploadCfg = getUploadConfig()
    if not uploadCfg then
        if onResult then onResult(false, nil, '上傳設定錯誤，請確認 Config.UploadProvider') end
        return
    end

    if Config.Debug then
        print('[sp_camera] [CAMERA] 開始截圖')
        print('[sp_camera] [CAMERA] Provider : ' .. Config.UploadProvider)
        print('[sp_camera] [CAMERA] Endpoint : ' .. uploadCfg.url)
        print('[sp_camera] [CAMERA] Field    : ' .. uploadCfg.field)
        print('[sp_camera] [CAMERA] Encoding : ' .. Config.Screenshot.encoding)
        print('[sp_camera] [CAMERA] Quality  : ' .. tostring(Config.Screenshot.quality))
    end

    -- 截圖前回呼（可在此隱藏 UI）
    if onStart then onStart() end

    -- 截圖 + 上傳
    CreateThread(function()
        local done      = false
        local timedOut  = false

        exports['screenshot-basic']:requestScreenshotUpload(
            uploadCfg.url,
            uploadCfg.field,
            {
                encoding = Config.Screenshot.encoding,
                quality  = Config.Screenshot.quality,
                headers  = uploadCfg.headers,
            },
            function(rawData)
                -- 已逾時則忽略（避免 double callback）
                if timedOut then return end

                if Config.Debug then
                    -- 只印前 300 字元，避免 log 太長
                    print('[sp_camera] [CAMERA] 上傳回應 (前300字): ' .. tostring(rawData):sub(1, 300))
                end

                local photoUrl = parseUploadResponse(rawData, Config.UploadProvider)

                if photoUrl then
                    print('[sp_camera] [CAMERA] 上傳成功 → ' .. photoUrl)
                    if onResult then onResult(true, photoUrl, nil) end
                else
                    local errMsg = '解析上傳回應失敗，請確認 API Key 與 Provider 設定'
                    if onResult then onResult(false, nil, errMsg) end
                end

                done = true
            end
        )

        -- 逾時保護（30 秒）
        local elapsed = 0
        while not done do
            Wait(500)
            elapsed = elapsed + 500
            if elapsed >= 30000 then
                timedOut = true
                local errMsg = '上傳逾時（30s），請確認網路連線或 API Key'
                print('[sp_camera] [CAMERA] ' .. errMsg)
                if onResult then onResult(false, nil, errMsg) end
                break
            end
        end
    end)
end

-- ============================================================
--  相機模式（Live Mode）
--  SetNuiFocus(false,false) → 角色可移動 + 鼠標控制方向
--  E         = 拍照
--  滾輪上/下 = 放大/縮小（調整 FOV）
--  Backspace  = 退出相機模式
-- ============================================================

local isCameraActive = false   -- 相機模式是否啟動
local isShootLocked  = false   -- 防止連拍鎖
local liveFov        = 60.0    -- 當前 FOV
local DEFAULT_FOV    = 60.0
local MIN_FOV        = 20.0    -- 最大放大（FOV 最小）
local MAX_FOV        = 90.0    -- 最小放大（FOV 最大）

-- FOV 值換算為顯示用的縮放倍率文字
local function fovToLabel(fov)
    local z = math.floor((DEFAULT_FOV / fov) * 10 + 0.5) / 10
    return string.format('%.1f', z) .. '×'
end

-- 拍照並儲存（相機模式內部呼叫）
local function liveShoot()
    if isShootLocked then return end
    isShootLocked = true

    -- 通知 NUI 播放閃光
    SendNUIMessage({ action = 'captureFlash' })

    CaptureAndUpload(
        nil,  -- onStart（相機模式下不需要額外隱藏操作）
        function(success, photoUrl, errMsg)
            isShootLocked = false

            if success and photoUrl then
                -- 組裝 payload 並觸發 savePhoto
                local payload = {
                    url        = photoUrl,
                    type       = Config.PayloadDefaults.type,
                    source     = Config.PayloadDefaults.source,
                    app        = Config.PayloadDefaults.app,
                    date       = os.date('%Y-%m-%d %H:%M:%S'),
                    uploadedAt = os.time(),
                    metadata   = { width = nil, height = nil, size = nil },
                }

                if Config.Debug then
                    print('[sp_camera] [LIVE] 拍照成功 → ' .. photoUrl)
                end

                TriggerServerEvent('qs-smartphone:server:savePhoto', payload)

                -- 通知 NUI 顯示拍照結果
                SendNUIMessage({
                    action  = 'captureResult',
                    success = true,
                    url     = photoUrl,
                    payload = json.encode(payload),
                })
            else
                print('[sp_camera] [LIVE] 拍照失敗: ' .. tostring(errMsg))
                SendNUIMessage({
                    action  = 'captureResult',
                    success = false,
                    error   = errMsg or '未知錯誤',
                })
            end
        end
    )
end

-- ──────────────────────────────────────────────
--  EnterCameraMode()
--  全域函式，供 main.lua 的 NUI callback 呼叫
-- ──────────────────────────────────────────────
function EnterCameraMode()
    if isCameraActive then return end
    isCameraActive = true
    isShootLocked  = false
    liveFov        = DEFAULT_FOV

    -- 釋放 NUI 焦點 → 遊戲接管所有鍵盤 + 鼠標輸入
    -- 角色可以用 WASD 移動、鼠標控制視角
    SetNuiFocus(false, false)

    -- 通知 NUI 切換到透明觀景窗模式
    SendNUIMessage({
        action    = 'cameraMode',
        active    = true,
        zoomLabel = fovToLabel(liveFov),
    })

    print('[sp_camera] ═══ 相機模式啟動 ═══')
    print('[sp_camera] E 鍵 = 拍照 | 滾輪 = 縮放 | Backspace = 退出')

    -- 按鍵監聽迴圈
    CreateThread(function()
        while isCameraActive do
            Wait(0)

            -- [E]（control ID 38）：拍照
            if IsControlJustReleased(0, 38) then
                liveShoot()
            end

            -- [Backspace]（control ID 177）：退出相機模式
            if IsControlJustReleased(0, 177) then
                ExitCameraMode()
                break
            end

            -- [滾輪向上]（control ID 15）：放大（FOV 減小）
            if IsControlJustPressed(0, 15) then
                liveFov = math.max(liveFov - 5.0, MIN_FOV)
                SetGameplayCamFov(liveFov)
                SendNUIMessage({ action = 'updateZoom', zoomLabel = fovToLabel(liveFov) })
            end

            -- [滾輪向下]（control ID 14）：縮小（FOV 增大）
            if IsControlJustPressed(0, 14) then
                liveFov = math.min(liveFov + 5.0, MAX_FOV)
                SetGameplayCamFov(liveFov)
                SendNUIMessage({ action = 'updateZoom', zoomLabel = fovToLabel(liveFov) })
            end
        end
    end)
end

-- ──────────────────────────────────────────────
--  ExitCameraMode()
--  全域函式，供 main.lua 的 NUI callback 呼叫
-- ──────────────────────────────────────────────
function ExitCameraMode()
    if not isCameraActive then return end
    isCameraActive = false
    isShootLocked  = false

    -- 恢復預設 FOV
    liveFov = DEFAULT_FOV
    SetGameplayCamFov(DEFAULT_FOV)

    -- 通知 NUI 退出透明模式、恢復正常 UI
    SendNUIMessage({ action = 'cameraMode', active = false })

    print('[sp_camera] ═══ 相機模式結束 ═══')
end
