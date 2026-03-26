/* ============================================================
   sp_camera / ui/app.js
   完整相機 App 前端邏輯
   整合方式：參照 custom-app-template 的 NUI 通訊模式
   ============================================================ */

'use strict';

// ═══════════════════════════════════════════════════════
//  NUI Fetch 工具
// ═══════════════════════════════════════════════════════

/** 取得 resource 名稱（FiveM 環境） */
function getResourceName() {
    return typeof GetParentResourceName === 'function'
        ? GetParentResourceName()
        : 'sp_camera';
}

/**
 * 向 Lua client 發送 NUI callback 請求
 * @param {string} endpoint - 對應 RegisterNUICallback 的名稱
 * @param {object} body     - 送出的資料
 * @returns {Promise<any>}
 */
async function nuiFetch(endpoint, body = {}) {
    const url = `https://${getResourceName()}/${endpoint}`;
    try {
        const res = await fetch(url, {
            method:  'POST',
            headers: { 'Content-Type': 'application/json' },
            body:    JSON.stringify(body),
        });
        return await res.json();
    } catch (err) {
        // Browser 測試環境下 fetch 會失敗，這是預期行為
        if (!window.__isFiveM) {
            console.warn(`[sp_camera] nuiFetch("${endpoint}") 失敗（非 FiveM 環境）:`, err.message);
        } else {
            console.error(`[sp_camera] nuiFetch("${endpoint}") 失敗:`, err);
        }
        return null;
    }
}

// ═══════════════════════════════════════════════════════
//  狀態
// ═══════════════════════════════════════════════════════
const State = {
    view:           'camera',   // 'camera' | 'url'
    resultOpen:     false,
    settingsOpen:   false,
    isCapturing:    false,
    isLive:         false,      // 相機 Live 模式（角色可移動 + 鼠標視角）
    capturedUrl:    null,       // 截圖後待儲存的 URL
    sessionPhotos:  [],         // { url }
    config: {
        provider:  'fivemanage',
        debug:     true,
        encoding:  'jpg',
        quality:   0.92,
        hidePhone: false,
    },
};

// ═══════════════════════════════════════════════════════
//  DOM 參照
// ═══════════════════════════════════════════════════════
const $ = id => document.getElementById(id);

const Dom = {
    // Views
    viewCamera:         $('view-camera'),
    viewUrl:            $('view-url'),
    // Camera view
    vfIdle:             $('vf-idle'),
    vfProviderHint:     $('vf-provider-hint'),
    vfLiveHint:         $('vf-live-hint'),
    vfLiveBadge:        $('vf-live-badge'),
    vfUploading:        $('vf-uploading'),
    vfShotBadge:        $('vf-shot-badge'),
    viewfinder:         document.getElementById('viewfinder'),
    bottombarCamera:    $('bottombar-camera'),
    zoomBadge:          $('zoom-badge'),
    zoomSlider:         $('zoom-slider'),
    btnFlash:           $('btn-flash'),
    btnTimer:           $('btn-timer'),
    btnSettings:        $('btn-settings'),
    btnCloseCamera:     $('btn-close-camera'),
    btnShutter:         $('btn-shutter'),
    shutterCore:        $('shutter-core'),
    shutterRing:        document.querySelector('.shutter-ring'),
    btnLastThumb:       $('btn-last-thumb'),
    lastThumbImg:       $('last-thumb-img'),
    thumbPlaceholder:   $('thumb-placeholder'),
    btnToUrl:           $('btn-to-url'),
    galleryStrip:       $('gallery-strip'),
    galleryStripInner:  $('gallery-strip-inner'),
    focusRing:          $('focus-ring'),
    // URL view
    btnBackToCamera:    $('btn-back-to-camera'),
    btnCloseUrl:        $('btn-close-url'),
    urlPh:              $('url-ph'),
    urlPreviewImg:      $('url-preview-img'),
    urlInput:           $('url-input'),
    btnUrlPreview:      $('btn-url-preview'),
    btnUrlSave:         $('btn-url-save'),
    btnDebugToggle:     $('btn-debug-toggle'),
    debugPanel:         $('debug-panel'),
    debugToggleArrow:   $('debug-toggle-arrow'),
    debugPayload:       $('debug-payload'),
    // Result overlay
    resultOverlay:      $('result-overlay'),
    resultImg:          $('result-img'),
    resultLoading:      $('result-loading'),
    resultSavedBadge:   $('result-saved-badge'),
    btnRetake:          $('btn-retake'),
    btnRetake2:         $('btn-retake2'),
    btnResultSave:      $('btn-result-save'),
    btnCopyUrl:         $('btn-copy-url'),
    // Settings
    settingsBackdrop:   $('settings-backdrop'),
    settingsPanel:      $('settings-panel'),
    btnSettingsClose:   $('btn-settings-close'),
    settingProvider:    $('setting-provider'),
    settingKeyRow:      $('setting-key-row'),
    settingKeyLabel:    $('setting-key-label'),
    settingApiKey:      $('setting-api-key'),
    btnToggleKeyVis:    $('btn-toggle-key-vis'),
    settingQuality:     $('setting-quality'),
    qualityVal:         $('quality-val'),
    settingEncoding:    $('setting-encoding'),
    settingDebug:       $('setting-debug'),
    btnSaveSettings:    $('btn-save-settings'),
    // Flash / Misc
    captureFlash:       $('capture-flash'),
    toastContainer:     $('toast-container'),
};

// ═══════════════════════════════════════════════════════
//  Toast 通知
// ═══════════════════════════════════════════════════════
/**
 * @param {'success'|'error'|'info'|'warning'} type
 * @param {string} message
 * @param {number} duration ms
 */
function toast(type, message, duration = 3000) {
    const el = document.createElement('div');
    el.className = `toast toast--${type}`;

    const icons = { success: '✓', error: '✕', info: 'ℹ', warning: '⚠' };
    el.innerHTML = `<span>${icons[type] || '·'}</span><span>${message}</span>`;

    Dom.toastContainer.appendChild(el);

    setTimeout(() => {
        el.classList.add('toast-dismiss');
        el.addEventListener('animationend', () => el.remove());
    }, duration);
}

// ═══════════════════════════════════════════════════════
//  View 切換
// ═══════════════════════════════════════════════════════
function setView(view) {
    State.view = view;

    if (view === 'camera') {
        Dom.viewCamera.classList.add('active');
        Dom.viewCamera.classList.remove('slide-out-left');
        Dom.viewUrl.classList.remove('active');
        Dom.viewUrl.classList.add('slide-out-left');
    } else if (view === 'url') {
        Dom.viewUrl.classList.add('active');
        Dom.viewUrl.classList.remove('slide-out-left');
        Dom.viewCamera.classList.remove('active');
        Dom.viewCamera.classList.add('slide-out-left');
    }
}

// ═══════════════════════════════════════════════════════
//  Result Overlay
// ═══════════════════════════════════════════════════════
function showResult(url) {
    State.resultOpen  = true;
    State.capturedUrl = url;

    Dom.resultImg.src = url;
    Dom.resultImg.onload = () => {
        Dom.resultLoading.classList.add('hidden');
    };
    Dom.resultImg.onerror = () => {
        Dom.resultLoading.classList.add('hidden');
        toast('error', '圖片載入失敗');
    };

    Dom.resultSavedBadge.classList.add('hidden');
    Dom.resultLoading.classList.add('hidden');
    Dom.btnResultSave.disabled = false;
    Dom.resultOverlay.classList.remove('hidden');
}

function hideResult() {
    State.resultOpen  = false;
    State.capturedUrl = null;
    Dom.resultOverlay.classList.add('hidden');
    Dom.resultImg.src = '';
}

// ═══════════════════════════════════════════════════════
//  快門閃光動畫
// ═══════════════════════════════════════════════════════
function triggerFlash() {
    return new Promise(resolve => {
        const fl = Dom.captureFlash;
        fl.classList.add('flash-in');
        setTimeout(() => {
            fl.classList.remove('flash-in');
            fl.classList.add('flash-out');
            fl.addEventListener('transitionend', function handler() {
                fl.classList.remove('flash-out');
                fl.removeEventListener('transitionend', handler);
                resolve();
            });
        }, 60);
    });
}

// ═══════════════════════════════════════════════════════
//  對焦動畫
// ═══════════════════════════════════════════════════════
function showFocusRing(x, y) {
    const ring = Dom.focusRing;
    ring.style.left = `${x}px`;
    ring.style.top  = `${y}px`;
    ring.classList.add('show');
    clearTimeout(ring._timer);
    ring._timer = setTimeout(() => ring.classList.remove('show'), 800);
}

// ═══════════════════════════════════════════════════════
//  Session 相簿
// ═══════════════════════════════════════════════════════
function addSessionPhoto(url) {
    State.sessionPhotos.unshift({ url });
    if (State.sessionPhotos.length > 10) State.sessionPhotos.pop();

    // 更新縮圖按鈕
    Dom.lastThumbImg.src = url;
    Dom.lastThumbImg.classList.remove('hidden');
    Dom.thumbPlaceholder.classList.add('hidden');

    // 更新 gallery strip
    updateGalleryStrip();
    Dom.galleryStrip.classList.remove('hidden');
}

function updateGalleryStrip() {
    Dom.galleryStripInner.innerHTML = '';
    State.sessionPhotos.forEach(({ url }) => {
        const item = document.createElement('div');
        item.className = 'gallery-strip-item';
        const img = document.createElement('img');
        img.src = url;
        img.alt = '拍攝照片';
        img.loading = 'lazy';
        item.appendChild(img);
        item.addEventListener('click', () => showResult(url));
        Dom.galleryStripInner.appendChild(item);
    });
}

// ═══════════════════════════════════════════════════════
//  Settings 面板
// ═══════════════════════════════════════════════════════
const providerKeyLabels = {
    fivemanage: 'Fivemanage API Key',
    imgbb:      'imgbb API Key',
    discord:    'Discord Webhook URL',
    custom:     'Custom API URL',
};

function openSettings() {
    State.settingsOpen = true;
    Dom.settingsBackdrop.classList.remove('hidden');
    Dom.settingsPanel.classList.remove('hidden');

    // 同步當前 config 到 UI
    Dom.settingProvider.value  = State.config.provider;
    Dom.settingQuality.value   = Math.round(State.config.quality * 100);
    Dom.qualityVal.textContent = `${Dom.settingQuality.value}%`;
    Dom.settingEncoding.value  = State.config.encoding;
    Dom.settingDebug.checked   = State.config.debug;
    Dom.settingApiKey.value    = '';
    updateKeyLabel(State.config.provider);
}

function closeSettings() {
    State.settingsOpen = false;
    Dom.settingsBackdrop.classList.add('hidden');
    Dom.settingsPanel.classList.add('hidden');
}

function updateKeyLabel(provider) {
    Dom.settingKeyLabel.textContent = providerKeyLabels[provider] || 'API Key';
    Dom.settingApiKey.placeholder   =
        provider === 'discord' ? 'https://discord.com/api/webhooks/...' : '輸入後按儲存…';
}

// ═══════════════════════════════════════════════════════
//  URL 模式：圖片預覽
// ═══════════════════════════════════════════════════════
function previewUrlImage(url) {
    if (!url || !url.trim()) {
        Dom.urlPreviewImg.classList.add('hidden');
        Dom.urlPh.classList.remove('hidden');
        return;
    }

    Dom.urlPreviewImg.onload = () => {
        Dom.urlPh.classList.add('hidden');
        Dom.urlPreviewImg.classList.remove('hidden');
    };
    Dom.urlPreviewImg.onerror = () => {
        Dom.urlPreviewImg.classList.add('hidden');
        Dom.urlPh.classList.remove('hidden');
        toast('error', '圖片載入失敗，請確認 URL 是否正確');
    };
    Dom.urlPreviewImg.src = url.trim();
}

// ═══════════════════════════════════════════════════════
//  Debug Payload 更新
// ═══════════════════════════════════════════════════════
function setDebugPayload(data) {
    try {
        Dom.debugPayload.textContent =
            typeof data === 'string' ? data : JSON.stringify(data, null, 2);
    } catch (_) {
        Dom.debugPayload.textContent = String(data);
    }
}

// ═══════════════════════════════════════════════════════
//  儲存照片（共用流程）
// ═══════════════════════════════════════════════════════
async function savePhoto(url) {
    if (!url) return;

    Dom.btnResultSave.disabled = true;
    Dom.btnUrlSave.disabled    = true;

    // 顯示上傳中蒙版
    Dom.resultLoading.classList.remove('hidden');

    const result = await nuiFetch('savePhoto', { url });

    Dom.resultLoading.classList.add('hidden');
    Dom.btnResultSave.disabled = false;
    Dom.btnUrlSave.disabled    = false;

    if (result && result.success) {
        toast('success', '已儲存至手機相簿 ✓');
        addSessionPhoto(url);

        // Result overlay 顯示已儲存標記
        Dom.resultSavedBadge.classList.remove('hidden');

        // 更新 debug payload
        if (result.payload) {
            setDebugPayload(result.payload);
        }

        // 3 秒後自動關閉 result overlay（若開著）
        if (State.resultOpen) {
            setTimeout(() => {
                hideResult();
                setView('camera');
            }, 2500);
        }
    } else {
        const errMsg = (result && result.error) ? result.error : '未知錯誤';
        toast('error', `儲存失敗：${errMsg}`);
    }
}

// ═══════════════════════════════════════════════════════
//  進入 Live 相機模式
//  → 通知 Lua SetNuiFocus(false,false)
//  → Lua 開始監聽 E / Backspace / 滾輪
//  → NUI 切換到透明觀景窗 + 控制提示
// ═══════════════════════════════════════════════════════
async function enterLiveCameraMode() {
    if (State.isLive) return;

    const ack = await nuiFetch('enterCameraMode', {});
    if (!ack && !window.__isFiveM) {
        // Browser 測試：模擬進入 live 模式
        handleCameraModeChange({ active: true, zoomLabel: '1.0×' });
        toast('info', 'Browser 測試模式：模擬 Live 相機', 3000);
    }
    // 實際的 UI 切換由 Lua SendNUIMessage({ action: 'cameraMode', active: true }) 觸發
}

// ═══════════════════════════════════════════════════════
//  切換 Live 模式 UI 狀態
// ═══════════════════════════════════════════════════════
function handleCameraModeChange(data) {
    State.isLive = data.active;

    if (data.active) {
        // ── 進入 Live 模式 ──
        // 觀景窗透明 → 遊戲畫面就是觀景窗
        Dom.viewfinder.classList.add('is-live');
        Dom.bottombarCamera && Dom.bottombarCamera.classList.add('is-live');
        Dom.shutterRing     && Dom.shutterRing.classList.add('is-live');

        // 顯示 LIVE 標示 + 控制提示，隱藏待機畫面
        Dom.vfIdle.classList.add('hidden');
        Dom.vfLiveBadge.classList.remove('hidden');
        Dom.vfLiveHint.classList.remove('hidden');

        // 更新縮放顯示
        if (data.zoomLabel) Dom.zoomBadge.textContent = data.zoomLabel;

        // 快門變紅（代表 Live / 錄影模式感）
        Dom.btnShutter.classList.add('is-live');

        // 頂部按鈕在 Live 模式下仍可見但不可互動（NUI 無焦點）
        toast('info', '已進入相機模式 · E 拍照 · ⌫ 退出', 4000);

    } else {
        // ── 退出 Live 模式 ──
        Dom.viewfinder.classList.remove('is-live');
        Dom.bottombarCamera && Dom.bottombarCamera.classList.remove('is-live');
        Dom.shutterRing     && Dom.shutterRing.classList.remove('is-live');

        Dom.vfIdle.classList.remove('hidden');
        Dom.vfLiveBadge.classList.add('hidden');
        Dom.vfLiveHint.classList.add('hidden');
        Dom.vfUploading.classList.add('hidden');
        Dom.vfShotBadge.classList.add('hidden');

        Dom.btnShutter.classList.remove('is-live');
        Dom.btnShutter.disabled = false;
        State.isCapturing = false;

        // 縮放重設
        Dom.zoomBadge.textContent = '1.0×';
        Dom.zoomSlider.value = 1;
    }
}

// ═══════════════════════════════════════════════════════
//  快門觸發（從 UI 按鈕按下 → 進入 Live 模式）
//  Live 模式中的實際拍照由 Lua 的 E 鍵處理
// ═══════════════════════════════════════════════════════
async function triggerShutter() {
    if (State.isLive) {
        // Live 模式中快門按鈕沒有 NUI 焦點，不會觸發
        // 實際由 Lua 監聽 E 鍵
        return;
    }

    if (State.isCapturing) return;

    // 尚未進入 Live 模式 → 進入相機模式
    await enterLiveCameraMode();
}

// ═══════════════════════════════════════════════════════
//  處理 Lua 送來的 captureResult
//  Live 模式和一般模式共用
// ═══════════════════════════════════════════════════════
function handleCaptureResult(data) {
    State.isCapturing = false;
    Dom.btnShutter.disabled = false;
    Dom.btnShutter.classList.remove('capturing');

    // 隱藏上傳中提示
    Dom.vfUploading.classList.add('hidden');

    if (data.success && data.url) {
        addSessionPhoto(data.url);

        if (State.isLive) {
            // ── Live 模式：在觀景窗上方顯示成功提示（不離開相機模式）
            Dom.vfShotBadge.classList.remove('hidden');
            setTimeout(() => Dom.vfShotBadge.classList.add('hidden'), 2500);
            toast('success', '已儲存至相簿 ✓', 2500);
        } else {
            // ── 一般模式：顯示 Result overlay
            showResult(data.url);
        }

        // Debug payload
        if (data.payload) {
            try { setDebugPayload(JSON.parse(data.payload)); }
            catch (_) { setDebugPayload(data.payload); }
        }
    } else {
        const err = data.error || '截圖/上傳失敗';

        if (State.isLive) {
            toast('error', err, 5000);
        } else {
            toast('error', err, 5000);
        }
        console.error('[sp_camera] captureResult 失敗:', err);
    }
}

// ═══════════════════════════════════════════════════════
//  事件綁定
// ═══════════════════════════════════════════════════════
function bindEvents() {

    // ── Camera View ──

    // 觀景窗點擊對焦
    document.getElementById('viewfinder').addEventListener('click', e => {
        const rect = e.currentTarget.getBoundingClientRect();
        showFocusRing(e.clientX - rect.left, e.clientY - rect.top);
    });

    // 縮放滑桿
    Dom.zoomSlider.addEventListener('input', () => {
        const val = parseFloat(Dom.zoomSlider.value).toFixed(1);
        Dom.zoomBadge.textContent = `${val}×`;
    });

    // 閃光燈循環（off → on → auto）
    Dom.btnFlash.addEventListener('click', () => {
        const modes  = ['off', 'on', 'auto'];
        const labels = ['OFF', 'ON', 'AUTO'];
        const cur    = Dom.btnFlash.dataset.flash || 'off';
        const next   = modes[(modes.indexOf(cur) + 1) % modes.length];
        Dom.btnFlash.dataset.flash = next;
        toast('info', `閃光燈：${labels[modes.indexOf(next)]}`, 1200);
    });

    // 定時器循環（off → 3s → 10s）
    Dom.btnTimer.addEventListener('click', () => {
        const modes  = ['off', '3', '10'];
        const labels = ['關閉', '3 秒', '10 秒'];
        const cur    = Dom.btnTimer.dataset.timer || 'off';
        const next   = modes[(modes.indexOf(cur) + 1) % modes.length];
        Dom.btnTimer.dataset.timer = next;
        toast('info', `定時器：${labels[modes.indexOf(next)]}`, 1200);
    });

    // 快門
    Dom.btnShutter.addEventListener('click', triggerShutter);

    // 最後縮圖 → 開啟 Result overlay
    Dom.btnLastThumb.addEventListener('click', () => {
        if (State.sessionPhotos.length > 0) {
            showResult(State.sessionPhotos[0].url);
        }
    });

    // 切換到 URL 模式
    Dom.btnToUrl.addEventListener('click', () => setView('url'));

    // 設定按鈕
    Dom.btnSettings.addEventListener('click', openSettings);

    // 關閉（相機模式）
    Dom.btnCloseCamera.addEventListener('click', async () => {
        await nuiFetch('closeApp', {});
    });

    // ── URL View ──

    // 返回相機
    Dom.btnBackToCamera.addEventListener('click', () => setView('camera'));

    // 關閉（URL 模式）
    Dom.btnCloseUrl.addEventListener('click', async () => {
        await nuiFetch('closeApp', {});
    });

    // URL 預覽
    Dom.btnUrlPreview.addEventListener('click', () => {
        previewUrlImage(Dom.urlInput.value);
    });

    Dom.urlInput.addEventListener('keydown', e => {
        if (e.key === 'Enter') {
            e.preventDefault();
            previewUrlImage(Dom.urlInput.value);
        }
    });

    // URL 儲存
    Dom.btnUrlSave.addEventListener('click', async () => {
        const url = Dom.urlInput.value.trim();
        if (!url) {
            toast('error', '請輸入圖片 URL');
            return;
        }
        await savePhoto(url);
    });

    // Debug 面板開關
    Dom.btnDebugToggle.addEventListener('click', () => {
        const hidden = Dom.debugPanel.classList.toggle('hidden');
        Dom.debugToggleArrow.textContent = hidden ? '▼' : '▲';
    });

    // ── Result Overlay ──

    Dom.btnRetake.addEventListener('click',  hideResult);
    Dom.btnRetake2.addEventListener('click', hideResult);

    Dom.btnResultSave.addEventListener('click', async () => {
        if (State.capturedUrl) await savePhoto(State.capturedUrl);
    });

    Dom.btnCopyUrl.addEventListener('click', () => {
        if (!State.capturedUrl) return;
        if (navigator.clipboard) {
            navigator.clipboard.writeText(State.capturedUrl)
                .then(() => toast('success', 'URL 已複製', 1800))
                .catch(() => toast('error', '複製失敗'));
        } else {
            toast('warning', '此環境不支援複製');
        }
    });

    // ── Settings ──

    Dom.settingsBackdrop.addEventListener('click', closeSettings);
    Dom.btnSettingsClose.addEventListener('click', closeSettings);

    Dom.settingProvider.addEventListener('change', () => {
        updateKeyLabel(Dom.settingProvider.value);
    });

    Dom.settingQuality.addEventListener('input', () => {
        Dom.qualityVal.textContent = `${Dom.settingQuality.value}%`;
    });

    Dom.btnToggleKeyVis.addEventListener('click', () => {
        Dom.settingApiKey.type =
            Dom.settingApiKey.type === 'password' ? 'text' : 'password';
    });

    Dom.btnSaveSettings.addEventListener('click', async () => {
        const provider   = Dom.settingProvider.value;
        const quality    = parseInt(Dom.settingQuality.value) / 100;
        const encoding   = Dom.settingEncoding.value;
        const debug      = Dom.settingDebug.checked;
        const apiKeyVal  = Dom.settingApiKey.value.trim();

        const updateData = { provider, quality, encoding, debug };

        if (apiKeyVal) {
            if (provider === 'fivemanage') updateData.fivemanageKey = apiKeyVal;
            if (provider === 'imgbb')      updateData.imgbbKey      = apiKeyVal;
            if (provider === 'discord')    updateData.discordWebhook = apiKeyVal;
        }

        const result = await nuiFetch('updateConfig', updateData);

        if (result && result.success) {
            // 更新本地 state
            State.config.provider  = provider;
            State.config.quality   = quality;
            State.config.encoding  = encoding;
            State.config.debug     = debug;

            Dom.vfProviderHint.textContent =
                `截圖後上傳至 ${provider.charAt(0).toUpperCase() + provider.slice(1)}`;

            toast('success', '設定已儲存（本 session 有效）');
            closeSettings();
        } else {
            toast('error', '設定儲存失敗');
        }
    });
}

// ═══════════════════════════════════════════════════════
//  NUI Message 監聽（來自 Lua SendNUIMessage）
// ═══════════════════════════════════════════════════════
window.addEventListener('message', e => {
    const { action, ...data } = e.data || {};

    switch (action) {

        // 手機開啟時
        case 'phone-load':
            console.log('[sp_camera] phone-load');
            init();
            break;

        // 使用者點開此 App
        case 'app-opened':
            console.log('[sp_camera] app-opened');
            resetAppUI();
            break;

        // 截圖結果（由 client/main.lua SendNUIMessage 觸發）
        case 'captureResult':
            handleCaptureResult(data);
            break;

        // ── Live 相機模式切換 ──
        // Lua EnterCameraMode() / ExitCameraMode() 後觸發
        case 'cameraMode':
            handleCameraModeChange(data);
            break;

        // ── 縮放更新（滾輪縮放時 Lua 觸發） ──
        case 'updateZoom':
            if (data.zoomLabel) {
                Dom.zoomBadge.textContent = data.zoomLabel;
                Dom.zoomSlider.value = parseFloat(data.zoomLabel) || 1;
            }
            break;

        // ── 閃光動畫（Live 模式中 Lua 拍照時觸發） ──
        case 'captureFlash':
            triggerFlash();
            // 顯示上傳中提示
            Dom.vfUploading.classList.remove('hidden');
            Dom.vfShotBadge.classList.add('hidden');
            break;

        // Lua 要求重設 UI（例如 closeApp 後）
        case 'resetUI':
            resetAppUI();
            break;

        // 截圖前隱藏 / 截圖後恢復
        case 'setVisible':
            document.getElementById('app').style.opacity = data.visible ? '1' : '0';
            break;

        default:
            break;
    }
});

// ═══════════════════════════════════════════════════════
//  初始化 / 重設
// ═══════════════════════════════════════════════════════
async function init() {
    // 從 Lua 取得當前 Config
    const cfg = await nuiFetch('getConfig', {});
    if (cfg) {
        State.config = { ...State.config, ...cfg };
        Dom.settingProvider.value  = cfg.provider  || 'fivemanage';
        Dom.settingEncoding.value  = cfg.encoding  || 'jpg';
        Dom.settingQuality.value   = Math.round((cfg.quality || 0.92) * 100);
        Dom.qualityVal.textContent = `${Dom.settingQuality.value}%`;
        Dom.settingDebug.checked   = cfg.debug;
        Dom.vfProviderHint.textContent =
            `截圖後上傳至 ${(cfg.provider || 'fivemanage').charAt(0).toUpperCase() + (cfg.provider || 'fivemanage').slice(1)}`;
    }
}

function resetAppUI() {
    // 若在 Live 模式中，先退出（通知 Lua）
    if (State.isLive) {
        nuiFetch('exitCameraMode', {});
        handleCameraModeChange({ active: false });
    }

    // 回到相機 view
    setView('camera');
    hideResult();
    closeSettings();

    // 清除 URL 輸入
    Dom.urlInput.value = '';
    Dom.urlPreviewImg.classList.add('hidden');
    Dom.urlPh.classList.remove('hidden');
    Dom.debugPayload.textContent = '（尚未發送）';
    Dom.debugPanel.classList.add('hidden');
    Dom.debugToggleArrow.textContent = '▼';

    // 重設快門狀態
    State.isCapturing = false;
    Dom.btnShutter.disabled = false;
    Dom.btnShutter.classList.remove('capturing');
}

// ═══════════════════════════════════════════════════════
//  啟動
// ═══════════════════════════════════════════════════════
(function bootstrap() {
    // 偵測是否在 FiveM NUI 環境中
    window.__isFiveM = typeof GetParentResourceName === 'function';

    // 綁定所有事件
    bindEvents();

    // 初始化 view 狀態
    Dom.viewCamera.classList.add('active');
    Dom.viewUrl.classList.add('slide-out-left');

    // 嘗試取得 config
    init();

    if (!window.__isFiveM) {
        console.info('[sp_camera] Browser 測試模式 — nuiFetch 會失敗，僅供 UI 開發用');
        toast('info', 'Browser 測試模式（NUI 功能不可用）', 4000);
    } else {
        console.log('[sp_camera] FiveM NUI 環境 — 載入完成');
    }
})();
