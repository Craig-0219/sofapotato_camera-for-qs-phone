-- ============================================================
--  sp_camera / fxmanifest.lua
--  基於 quasar-store-organizations/custom-app-template 改造
-- ============================================================

fx_version 'cerulean'
games { 'gta5' }

name        'sp_camera'
description 'Complete Camera App for qs-smartphone-pro'
version     '2.0.0'
author      'sofapotato'

-- 設定檔（共用）
shared_script 'config.lua'

-- 客戶端
client_scripts {
    'client/camera.lua',  -- 截圖 / 上傳核心邏輯
    'client/main.lua',    -- App 註冊 / NUI 回呼 / 指令
}

-- 伺服器端（debug log）
server_script 'server/main.lua'

-- NUI 頁面
ui_page 'ui/index.html'

-- 打包 ui/ 所有檔案
files {
    'ui/index.html',
    'ui/style.css',
    'ui/app.js',
    'ui/icon.png',
}

-- screenshot-basic 需在 server.cfg 中 ensure
-- 建議順序：screenshot-basic → qs-smartphone-pro → sp_camera
