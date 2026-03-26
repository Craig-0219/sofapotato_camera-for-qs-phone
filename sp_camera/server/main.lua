-- ============================================================
--  sp_camera / server/main.lua
--  伺服器端 — 僅做 debug 監控
--
--  架構說明：
--    client/main.lua 直接 TriggerServerEvent('qs-smartphone:server:savePhoto', payload)
--    qs-smartphone-pro 的 server handler 負責實際儲存邏輯
--    本檔案只是「旁聽」同一個 event，印出 log，不干涉原有流程
--
--  重要：FiveM server event 允許多個 handler 同時監聽
--        本 handler 不會阻止 qs-smartphone-pro 的 handler 執行
-- ============================================================

-- ──────────────────────────────────────────────
--  旁聽 savePhoto event（僅 debug 用）
--  TODO: 如果 qs-smartphone-pro 官方 handler 有來源驗證，
--        確認是否會因為多個 handler 而出現問題
-- ──────────────────────────────────────────────
AddEventHandler('qs-smartphone:server:savePhoto', function(data)
    local playerId = source

    print('[sp_camera] [SERVER] ═══════════════════════════════')
    print(('[sp_camera] [SERVER] 偵測到 savePhoto event | 玩家 ID: %s'):format(tostring(playerId)))
    print('[sp_camera] [SERVER] 收到 Payload:')

    -- 嘗試 encode；若 qs-smartphone-pro 傳的不是 table 也能看到
    local ok, encoded = pcall(json.encode, data, { indent = true })
    if ok then
        print(encoded)
    else
        print('[sp_camera] [SERVER] Payload encode 失敗，原始值: ' .. tostring(data))
    end

    print('[sp_camera] [SERVER] ═══════════════════════════════')
    print('[sp_camera] [SERVER] 注意：實際儲存由 qs-smartphone-pro 的 handler 負責')
    print('[sp_camera] [SERVER] 若相簿沒有更新，請確認：')
    print('[sp_camera] [SERVER]   1. event 名稱是否正確')
    print('[sp_camera] [SERVER]   2. payload 欄位是否符合 qs-smartphone-pro 預期')
    print('[sp_camera] [SERVER]   3. 官方 handler 是否有玩家驗證機制')
end)

print('[sp_camera] Server 端已載入（debug 模式）')
