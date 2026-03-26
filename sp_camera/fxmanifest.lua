-- ============================================================
--  sp_camera / fxmanifest.lua
--  基於 quasar-store-organizations/custom-app-template 改造
--  整合目標：qs-smartphone-pro 自訂 App
-- ============================================================

fx_version 'cerulean'
games { 'gta5' }

name        'sp_camera'
description 'Custom Camera App for qs-smartphone-pro'
version     '1.0.0'
author      'sofapotato'

-- 客戶端 Lua
client_script 'client/main.lua'

-- 伺服器端 Lua（僅做 debug log，實際儲存邏輯在 qs-smartphone-pro）
server_script 'server/main.lua'

-- NUI 頁面（手機內 app 的 UI，由 qs-smartphone-pro 載入為 iframe）
ui_page 'ui/index.html'

-- 把整個 ui/ 資料夾納入打包
files {
    'ui/index.html',
    'ui/style.css',
    'ui/app.js',
    'ui/icon.png',  -- TODO: 放一張實際 icon 圖（建議 96x96 PNG）
}
