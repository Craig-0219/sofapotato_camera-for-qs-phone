-- ============================================================
--  sp_camera / server/main.lua
--  Server 端 — debug 旁聽 + 基本防護
--
--  架構說明：
--    client/main.lua 直接 TriggerServerEvent 到 qs-smartphone:server:savePhoto
--    qs-smartphone-pro 的 handler 負責實際寫入相簿
--    本 handler 旁聽同一個 event，僅做 log，不干涉原流程
--
--  FiveM 機制：同一個 server event 可有多個 handler 同時執行
-- ============================================================

-- ──────────────────────────────────────────────
--  旁聽 savePhoto event（debug 用）
--  TODO: 若 qs-smartphone-pro handler 有來源驗證（resource name / identifier check），
--        本 handler 不會影響，但需確認官方機制
-- ──────────────────────────────────────────────
AddEventHandler('qs-smartphone:server:savePhoto', function(data)
    if not Config or not Config.Debug then return end

    local playerId = source

    print('[sp_camera] ══════════════════════════════════════')
    print(('[sp_camera] [SERVER] savePhoto event 收到 | 玩家 ID: %s'):format(tostring(playerId)))

    -- 嘗試取得玩家識別碼（如果 ESX/QBCore 可用）
    local identifiers = GetPlayerIdentifiers(playerId)
    if identifiers and #identifiers > 0 then
        print('[sp_camera] [SERVER] 玩家識別碼:')
        for _, v in ipairs(identifiers) do
            print('  ' .. v)
        end
    end

    -- 印出完整 payload
    local ok, encoded = pcall(json.encode, data, { indent = true })
    if ok then
        print('[sp_camera] [SERVER] Payload:')
        print(encoded)
    else
        print('[sp_camera] [SERVER] Payload encode 失敗，原始值: ' .. tostring(data))
    end

    print('[sp_camera] [SERVER] ——')
    print('[sp_camera] [SERVER] 注意：實際儲存由 qs-smartphone-pro handler 負責')
    print('[sp_camera] [SERVER] 若相簿沒有更新，請確認：')
    print('[sp_camera] [SERVER]   1. payload 欄位是否符合 handler 預期')
    print('[sp_camera] [SERVER]   2. 玩家是否擁有有效的手機 item / metadata')
    print('[sp_camera] [SERVER]   3. handler 是否有來源 resource 驗證')
    print('[sp_camera] ══════════════════════════════════════')
end)

print('[sp_camera] [SERVER] Server 端已載入（debug 旁聽模式）')
