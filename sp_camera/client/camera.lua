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
--  手機畫面 = 觀景窗，角色可移動，鼠標控制視角
--  支援正拍 + 自拍（Selfie）
--
--  按鍵對照：
--    E          = 拍照
--    F          = 切換自拍 / 正拍
--    滾輪上/下  = 放大 / 縮小
--    Backspace  = 退出相機模式
-- ============================================================

-- ── 狀態變數 ──
local isCameraActive = false
local isShootLocked  = false
local isSelfieMode   = false
local liveFov        = 60.0
local DEFAULT_FOV    = 60.0
local MIN_FOV        = 20.0
local MAX_FOV        = 90.0

-- ── 實體 ──
local phoneProp    = -1   -- 附加到手的手機 prop
local selfieCamera = -1   -- CreateCam 建立的自拍相機

-- ──────────────────────────────────────────────
--  輔助：資源載入等待
-- ──────────────────────────────────────────────
local function awaitModel(hash)
    if not IsModelValid(hash) then return false end
    RequestModel(hash)
    local t = 0
    while not HasModelLoaded(hash) do
        Wait(10); t = t + 10
        if t > 3000 then return false end
    end
    return true
end

local function awaitAnim(dict)
    RequestAnimDict(dict)
    local t = 0
    while not HasAnimDictLoaded(dict) do
        Wait(10); t = t + 10
        if t > 3000 then return false end
    end
    return HasAnimDictLoaded(dict)
end

-- ──────────────────────────────────────────────
--  FOV 換算顯示文字
-- ──────────────────────────────────────────────
local function fovToLabel(fov)
    local z = math.floor((DEFAULT_FOV / fov) * 10 + 0.5) / 10
    return string.format('%.1f', z) .. '×'
end

-- ──────────────────────────────────────────────
--  手機 Prop 操作
--  TODO: 若伺服器限制 model stream，確認 prop_npc_phone_02 可用性
--  TODO: 骨骼 offset/rotation 可依實際 prop 外觀在遊戲內微調
-- ──────────────────────────────────────────────
local PHONE_MODEL = GetHashKey('prop_npc_phone_02')

local function spawnPhoneProp(ped)
    if not awaitModel(PHONE_MODEL) then
        print('[sp_camera] [WARN] 無法載入手機 prop，跳過附加')
        return
    end
    phoneProp = CreateObject(PHONE_MODEL, 0.0, 0.0, 0.0, true, true, false)
    -- 右手骨骼：SKEL_R_Hand (28422)
    AttachEntityToEntity(
        phoneProp, ped, GetPedBoneIndex(ped, 28422),
        0.0,  0.04, 0.0,      -- 位置偏移（TODO: 微調）
        10.0, 180.0, 170.0,   -- 旋轉偏移（TODO: 微調）
        true, true, false, true, 1, true
    )
    SetModelAsNoLongerNeeded(PHONE_MODEL)
end

local function removePhoneProp()
    if phoneProp ~= -1 and DoesEntityExist(phoneProp) then
        DetachEntity(phoneProp, true, true)
        DeleteObject(phoneProp)
        phoneProp = -1
    end
end

-- ──────────────────────────────────────────────
--  動畫操作
--  正拍：cellphone@photo / picture_photo  — 持手機朝前
--  自拍：cellphone@selfie / base          — 持手機朝自己
-- ──────────────────────────────────────────────
local ANIM_PHOTO  = { dict = 'cellphone@photo',   name = 'picture_photo' }
local ANIM_SELFIE = { dict = 'cellphone@selfie',  name = 'base'          }

local function playAnim(ped, anim)
    if awaitAnim(anim.dict) then
        -- flag 49 = loop + upperbody only，不影響腳部移動
        TaskPlayAnim(ped, anim.dict, anim.name, 8.0, -8.0, -1, 49, 0.0, false, false, false)
    end
end

local function stopAnim(ped, anim)
    if IsEntityPlayingAnim(ped, anim.dict, anim.name, 3) then
        StopAnimTask(ped, anim.dict, anim.name, 1.0)
    end
    RemoveAnimDict(anim.dict)
end

-- ──────────────────────────────────────────────
--  自拍相機：在角色正前方建立往後看的 scripted camera
--  每幀跟隨角色位置與面向，模擬「拿手機自拍」
-- ──────────────────────────────────────────────
local function startSelfieCamera()
    if selfieCamera ~= -1 then return end

    selfieCamera = CreateCam('DEFAULT_SCRIPTED_CAMERA', true)
    SetCamFov(selfieCamera, liveFov)
    SetCamActive(selfieCamera, true)
    -- 平滑切換到自拍相機（300ms 過渡）
    RenderScriptCams(true, true, 300, true, false)

    -- 每幀更新相機位置，跟隨角色
    CreateThread(function()
        while isSelfieMode and isCameraActive do
            Wait(0)
            if selfieCamera == -1 then break end

            local ped    = PlayerPedId()
            local pos    = GetEntityCoords(ped)
            local hRad   = math.rad(GetEntityHeading(ped))

            -- 相機定位：角色正前方 1.2m、頭部高度約 0.62m
            SetCamCoord(selfieCamera,
                pos.x + math.sin(-hRad) * 1.2,
                pos.y + math.cos(-hRad) * 1.2,
                pos.z + 0.62
            )

            -- 鏡頭對準頭部骨骼（SKEL_Head = 0x796e）
            local headBone   = GetPedBoneIndex(ped, 0x796e)
            local headCoords = GetWorldPositionOfEntityBone(ped, headBone)
            PointCamAtCoord(selfieCamera, headCoords.x, headCoords.y, headCoords.z)

            -- 跟隨縮放設定
            SetCamFov(selfieCamera, liveFov)
        end
    end)

    print('[sp_camera] 自拍相機已啟動（相機在角色前方對準臉部）')
end

local function stopSelfieCamera()
    if selfieCamera == -1 then return end
    -- 平滑切回 gameplay 相機
    RenderScriptCams(false, true, 300, true, false)
    SetCamActive(selfieCamera, false)
    DestroyCam(selfieCamera, false)
    selfieCamera = -1
    print('[sp_camera] 自拍相機已停止')
end

-- ──────────────────────────────────────────────
--  拍照（相機模式內部）
-- ──────────────────────────────────────────────
local function liveShoot()
    if isShootLocked then return end
    isShootLocked = true

    SendNUIMessage({ action = 'captureFlash' })

    CaptureAndUpload(nil, function(success, photoUrl, errMsg)
        isShootLocked = false

        if success and photoUrl then
            local payload = {
                url        = photoUrl,
                type       = Config.PayloadDefaults.type,
                source     = Config.PayloadDefaults.source,
                app        = Config.PayloadDefaults.app,
                selfie     = isSelfieMode,  -- 記錄是否為自拍
                date       = os.date('%Y-%m-%d %H:%M:%S'),
                uploadedAt = os.time(),
                metadata   = { width = nil, height = nil, size = nil },
            }
            if Config.Debug then
                local tag = isSelfieMode and '[自拍]' or '[正拍]'
                print('[sp_camera] [LIVE] 拍照成功 ' .. tag .. ' → ' .. photoUrl)
            end
            TriggerServerEvent('qs-smartphone:server:savePhoto', payload)
            SendNUIMessage({
                action  = 'captureResult',
                success = true,
                url     = photoUrl,
                payload = json.encode(payload),
            })
        else
            print('[sp_camera] [LIVE] 拍照失敗: ' .. tostring(errMsg))
            SendNUIMessage({ action = 'captureResult', success = false, error = errMsg or '未知錯誤' })
        end
    end)
end

-- ══════════════════════════════════════════════
--  公開函式
-- ══════════════════════════════════════════════

-- ──────────────────────────────────────────────
--  ToggleSelfieMode()
--  在正拍 ↔ 自拍之間切換
--  全域函式，供 main.lua NUI callback 呼叫
-- ──────────────────────────────────────────────
function ToggleSelfieMode()
    if not isCameraActive then return end

    local ped = PlayerPedId()

    if isSelfieMode then
        -- 自拍 → 正拍
        isSelfieMode = false
        stopSelfieCamera()
        SetGameplayCamFov(liveFov)
        stopAnim(ped, ANIM_SELFIE)
        playAnim(ped, ANIM_PHOTO)
        SendNUIMessage({ action = 'selfieMode', active = false })
        print('[sp_camera] 切換至正拍模式')
    else
        -- 正拍 → 自拍
        isSelfieMode = true
        stopAnim(ped, ANIM_PHOTO)
        playAnim(ped, ANIM_SELFIE)
        startSelfieCamera()
        SendNUIMessage({ action = 'selfieMode', active = true })
        print('[sp_camera] 切換至自拍模式')
    end
end

-- ──────────────────────────────────────────────
--  EnterCameraMode()
--  全域函式，供 main.lua NUI callback 呼叫
-- ──────────────────────────────────────────────
function EnterCameraMode()
    if isCameraActive then return end
    isCameraActive = true
    isShootLocked  = false
    isSelfieMode   = false
    liveFov        = DEFAULT_FOV

    -- 釋放 NUI 焦點 → 遊戲接管鍵盤 + 鼠標
    SetNuiFocus(false, false)

    local ped = PlayerPedId()
    spawnPhoneProp(ped)
    playAnim(ped, ANIM_PHOTO)  -- 預設正拍姿勢

    SendNUIMessage({
        action    = 'cameraMode',
        active    = true,
        zoomLabel = fovToLabel(liveFov),
        selfie    = false,
    })

    print('[sp_camera] ═══ 相機模式啟動 ═══')
    print('[sp_camera] E 拍照 | F 自拍切換 | 滾輪縮放 | Backspace 退出')

    -- 按鍵監聽迴圈
    CreateThread(function()
        while isCameraActive do
            Wait(0)

            -- [E] (38)：拍照
            if IsControlJustReleased(0, 38) then
                liveShoot()
            end

            -- [F] (23)：切換自拍 / 正拍
            if IsControlJustReleased(0, 23) then
                ToggleSelfieMode()
            end

            -- [Backspace] (177)：退出
            if IsControlJustReleased(0, 177) then
                ExitCameraMode()
                break
            end

            -- 滾輪縮放
            if IsControlJustPressed(0, 15) then
                liveFov = math.max(liveFov - 5.0, MIN_FOV)
                if not isSelfieMode then SetGameplayCamFov(liveFov) end
                SendNUIMessage({ action = 'updateZoom', zoomLabel = fovToLabel(liveFov) })
            end

            if IsControlJustPressed(0, 14) then
                liveFov = math.min(liveFov + 5.0, MAX_FOV)
                if not isSelfieMode then SetGameplayCamFov(liveFov) end
                SendNUIMessage({ action = 'updateZoom', zoomLabel = fovToLabel(liveFov) })
            end
        end
    end)
end

-- ──────────────────────────────────────────────
--  ExitCameraMode()
--  全域函式，供 main.lua NUI callback 呼叫
-- ──────────────────────────────────────────────
function ExitCameraMode()
    if not isCameraActive then return end
    isCameraActive = false
    isShootLocked  = false

    -- 停止自拍相機
    if isSelfieMode then
        isSelfieMode = false
        stopSelfieCamera()
    end

    -- 清除 prop + 動畫
    local ped = PlayerPedId()
    stopAnim(ped, ANIM_PHOTO)
    stopAnim(ped, ANIM_SELFIE)
    removePhoneProp()

    -- 恢復 FOV
    liveFov = DEFAULT_FOV
    SetGameplayCamFov(DEFAULT_FOV)

    SendNUIMessage({ action = 'cameraMode', active = false })
    print('[sp_camera] ═══ 相機模式結束 ═══')
end
