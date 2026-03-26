/* ============================================================
   sp_camera / ui/app.js
   NUI 前端邏輯
   整合方式：參照 custom-app-template 的 app.js / main.js 模式
   ============================================================ */

'use strict';

// ── DOM 元素 ──────────────────────────────────────────────
const urlInput       = document.getElementById('url-input');
const btnPreview     = document.getElementById('btn-preview');
const previewImg     = document.getElementById('preview-img');
const previewPH      = document.getElementById('preview-placeholder');
const btnSave        = document.getElementById('btn-save');
const btnClose       = document.getElementById('btn-close');
const statusBox      = document.getElementById('status-box');
const statusIcon     = document.getElementById('status-icon');
const statusText     = document.getElementById('status-text');
const btnToggleDebug = document.getElementById('btn-toggle-debug');
const debugPanel     = document.getElementById('debug-panel');
const debugPayload   = document.getElementById('debug-payload');

// ── 工具：向 Lua client 發送 NUI fetch 請求 ──────────────
// 官方 template 使用 fetch(`https://${GetParentResourceName()}/...`)
// 在 FiveM NUI 環境中，resource name 可從 window.GetParentResourceName() 取得
// 若不在 FiveM 環境則 fallback 為 'sp_camera'（方便 browser 測試）
function getResourceName() {
    if (typeof GetParentResourceName === 'function') {
        return GetParentResourceName();
    }
    return 'sp_camera';
}

/**
 * 送出 NUI callback 到 Lua client
 * @param {string} endpoint  - callback 名稱（對應 RegisterNUICallback）
 * @param {object} payload   - 要傳送的資料
 * @returns {Promise<object>} - Lua cb() 回傳的資料
 */
async function nuiFetch(endpoint, payload = {}) {
    const url = `https://${getResourceName()}/${endpoint}`;
    const res = await fetch(url, {
        method:  'POST',
        headers: { 'Content-Type': 'application/json' },
        body:    JSON.stringify(payload),
    });
    return res.json();
}

// ── UI 狀態控制 ───────────────────────────────────────────
/** 顯示狀態訊息
 * @param {'success'|'error'|'loading'} type
 * @param {string} icon  - emoji
 * @param {string} text  - 顯示文字
 */
function showStatus(type, icon, text) {
    statusBox.className = `status-box ${type}`;
    statusIcon.textContent = icon;
    statusText.textContent = text;
    statusBox.classList.remove('hidden');
}

function hideStatus() {
    statusBox.classList.add('hidden');
}

/** 更新 debug payload 預覽 */
function updateDebugPayload(data) {
    try {
        debugPayload.textContent = JSON.stringify(data, null, 2);
    } catch (e) {
        debugPayload.textContent = String(data);
    }
}

/** 顯示圖片預覽 */
function showPreview(url) {
    if (!url || url.trim() === '') {
        previewImg.classList.add('hidden');
        previewPH.classList.remove('hidden');
        return;
    }

    previewImg.onload = () => {
        previewPH.classList.add('hidden');
        previewImg.classList.remove('hidden');
    };

    previewImg.onerror = () => {
        previewPH.classList.remove('hidden');
        previewImg.classList.add('hidden');
        showStatus('error', '⚠️', '圖片載入失敗，請確認 URL 是否正確');
    };

    previewImg.src = url.trim();
}

/** 重設 UI 到初始狀態（收到 resetUI action 時呼叫） */
function resetUI() {
    urlInput.value = '';
    previewImg.src = '';
    previewImg.classList.add('hidden');
    previewPH.classList.remove('hidden');
    hideStatus();
    debugPayload.textContent = '（尚未發送）';
    btnSave.disabled = false;
}

// ── 事件綁定 ──────────────────────────────────────────────

// 預覽按鈕
btnPreview.addEventListener('click', () => {
    showPreview(urlInput.value);
});

// URL 輸入框 Enter 鍵觸發預覽
urlInput.addEventListener('keydown', (e) => {
    if (e.key === 'Enter') {
        e.preventDefault();
        showPreview(urlInput.value);
    }
});

// 儲存按鈕：核心流程
btnSave.addEventListener('click', async () => {
    const url = urlInput.value.trim();

    if (!url) {
        showStatus('error', '❌', '請輸入圖片 URL');
        return;
    }

    // 鎖定按鈕，防止重複送出
    btnSave.disabled = true;
    showStatus('loading', '⏳', '正在儲存至手機相簿...');

    // 準備送給 Lua 的資料（只傳 url，payload 組裝在 Lua 端）
    const data = { url };

    // 更新 debug 預覽（顯示送出前的資料）
    updateDebugPayload({
        _note: '以下為 NUI 送出資料，完整 payload 由 client/main.lua 組裝',
        sent:  data,
    });

    try {
        // 送出 NUI fetch → 觸發 RegisterNUICallback('savePhoto', ...)
        const result = await nuiFetch('savePhoto', data);

        console.log('[sp_camera] savePhoto 回應:', result);

        if (result && result.success) {
            showStatus('success', '✅', '已送出！請至手機相簿確認是否出現');

            // 顯示 Lua 端組裝好的 payload（供 debug）
            if (result.payload) {
                try {
                    updateDebugPayload(JSON.parse(result.payload));
                } catch (_) {
                    updateDebugPayload(result.payload);
                }
            }
        } else {
            const errMsg = (result && result.error) ? result.error : '未知錯誤';
            showStatus('error', '❌', `儲存失敗：${errMsg}`);
        }
    } catch (err) {
        console.error('[sp_camera] nuiFetch 錯誤:', err);
        showStatus('error', '❌', `連線失敗：${err.message || '請確認 resource 是否正常運行'}`);
    } finally {
        btnSave.disabled = false;
    }
});

// 關閉按鈕
btnClose.addEventListener('click', async () => {
    try {
        await nuiFetch('closeApp', {});
    } catch (_) {
        // 忽略錯誤（在 browser 測試環境下 fetch 會失敗）
    }
});

// Debug 面板開關
btnToggleDebug.addEventListener('click', () => {
    const isHidden = debugPanel.classList.toggle('hidden');
    btnToggleDebug.textContent = isHidden ? '🔍 顯示 Payload' : '🔼 隱藏 Payload';
});

// ── 來自 qs-smartphone-pro 的訊息監聽 ───────────────────
// 官方 template 的 main.js 以 window.addEventListener('message') 接收
// phone-load：手機開啟時觸發
// app-opened：使用者點入此 app 時觸發
// resetUI：自訂事件，由 Lua SendNUIMessage 觸發

window.addEventListener('message', (event) => {
    const { action, data } = event.data || {};

    switch (action) {

        // 手機 NUI 框架載入時（可做初始化）
        case 'phone-load':
            console.log('[sp_camera] phone-load 收到，手機已載入');
            // TODO: 若有需要可在此做 app 初始化
            break;

        // 使用者打開此 app 時
        case 'app-opened':
            console.log('[sp_camera] app-opened 收到，app 已被打開');
            resetUI();
            hideStatus();
            break;

        // Lua 端要求重設 UI
        case 'resetUI':
            resetUI();
            break;

        // TODO: 可在此加入更多 action 處理
        default:
            break;
    }
});

// ── Browser 測試模式 ─────────────────────────────────────
// 非 FiveM 環境下提示開發者
if (typeof GetParentResourceName === 'undefined') {
    console.info('[sp_camera] 非 FiveM 環境，nuiFetch 呼叫會失敗，僅供 UI 測試');
    showStatus(
        'loading',
        '🔧',
        'Browser 測試模式 — nuiFetch 不可用，可測試 UI 介面'
    );
}
