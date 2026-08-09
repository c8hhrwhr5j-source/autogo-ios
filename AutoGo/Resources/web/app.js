/**
 * AutoGo Web 控制台 — 前端应用
 */

const API = {
    base: '/',

    async call(path, params = {}) {
        const qs = new URLSearchParams(
            Object.fromEntries(
                Object.entries(params).filter(([_, v]) => v !== undefined && v !== '')
            )
        ).toString();
        const url = this.base + path + (qs ? '?' + qs : '');
        try {
            const r = await fetch(url);
            return await r.json();
        } catch (e) {
            return { success: false, error: e.message };
        }
    },

    async post(path, body = {}) {
        try {
            const r = await fetch(this.base + path, {
                method: 'POST',
                headers: { 'Content-Type': 'application/json' },
                body: JSON.stringify(body)
            });
            return await r.json();
        } catch (e) {
            return { success: false, error: e.message };
        }
    }
};

// ============================================
// 日志
// ============================================
const Log = {
    output: document.getElementById('logOutput'),

    _line(level, msg) {
        const time = new Date().toLocaleTimeString();
        const div = document.createElement('div');
        div.className = `log-entry ${level}`;
        div.innerHTML = `<span class="log-time">${time}</span>${msg}`;
        if (this.output) {
            this.output.prepend(div);
            // 限制最多保留 200 条
            while (this.output.children.length > 200) {
                this.output.lastChild.remove();
            }
        }
    },

    info(msg) { this._line('', msg); },
    json(data) {
        const s = JSON.stringify(data, null, 2);
        this._line('', `<pre style="margin:0;font-size:11px">${s}</pre>`);
    },
    error(msg) { this._line('error', msg); },
    warn(msg) { this._line('warn', msg); }
};

// ============================================
// 操作
// ============================================
const actions = {

    // ---- 触摸 ----
    async tap() {
        const x = val('tapX'), y = val('tapY'), delay = val('tapDelay');
        const r = await API.call('touch/tap', { x, y, delay });
        Log.json(r);
        if (r.success) toast('点击成功');
    },

    async swipe() {
        const r = await API.call('touch/swipe', {
            x1: val('swX1'), y1: val('swY1'),
            x2: val('swX2'), y2: val('swY2'),
            duration: val('swDuration')
        });
        Log.json(r);
        if (r.success) toast('滑动完成');
    },

    async longPress() {
        const r = await API.call('touch/longpress', {
            x: val('tapX'), y: val('tapY'),
            duration: val('lpDuration') || 800
        });
        Log.json(r);
    },

    async pinch() {
        const r = await API.call('touch/pinch', {
            cx: val('tapX'), cy: val('tapY'),
            startDistance: 80, endDistance: 160
        });
        Log.json(r);
    },

    // ---- 找色 ----
    async findColor() {
        const hex = (val('colorHex') || '').replace('#', '').replace('0x', '');
        const tolerance = val('colorTolerance') || 5;
        const r = await API.call('screen/findcolor', { color: hex, tolerance });

        const resultDiv = document.getElementById('colorResult');
        resultDiv.style.display = 'block';

        if (r.found && r.best) {
            resultDiv.innerHTML = `<span class="found">✅ 找到 ${r.count} 个匹配点</span><br>
                最佳位置: <span class="coord" onclick="useCoord(${Math.round(r.best.x)},${Math.round(r.best.y)})">
                (${Math.round(r.best.x)}, ${Math.round(r.best.y)})</span>
                ${r.points.slice(0,5).map(p => `<br>· (${Math.round(p.x)}, ${Math.round(p.y)})`).join('')}`;
            // 自动填入坐标
            setVal('tapX', Math.round(r.best.x));
            setVal('tapY', Math.round(r.best.y));
        } else {
            resultDiv.innerHTML = '<span class="not-found">❌ 未找到匹配颜色</span>';
        }
        Log.json(r);
    },

    // ---- OCR ----
    async ocrAll() {
        Log.info('🔍 OCR 识别中...');
        const r = await API.call('ocr/recognize');
        const resultDiv = document.getElementById('ocrResult');
        resultDiv.style.display = 'block';
        resultDiv.innerHTML = r.text ? `<pre style="margin:0;font-size:11px;white-space:pre-wrap">${r.text}</pre>` : '未识别到文字';
        Log.json({ ...r, text: r.text ? r.text.substring(0, 200) + '...' : '' });
    },

    async findText() {
        const keyword = val('ocrKeyword');
        if (!keyword) return toast('请输入搜索关键字');
        Log.info(`🔍 搜索: "${keyword}"`);
        const r = await API.call('ocr/findtext', { keyword });
        if (r.found) {
            const resultDiv = document.getElementById('ocrResult');
            resultDiv.style.display = 'block';
            resultDiv.innerHTML = `<span class="found">✅ 找到 "${keyword}"</span><br>
                位置: <span class="coord" onclick="useCoord(${Math.round(r.x)},${Math.round(r.y)})">
                (${Math.round(r.x)}, ${Math.round(r.y)})</span>`;
            setVal('tapX', Math.round(r.x));
            setVal('tapY', Math.round(r.y));
        } else {
            toast('未找到匹配文字');
        }
        Log.json(r);
    },

    // ---- 截图 ----
    async screenshot() {
        Log.info('📷 截屏中...');
        const r = await API.call('screen/screenshot');
        if (r.base64) {
            const container = document.getElementById('screenshotContainer');
            const img = document.getElementById('screenshotImg');
            img.src = 'data:image/png;base64,' + r.base64;
            container.style.display = 'block';
            img.onclick = function(e) {
                const rect = img.getBoundingClientRect();
                const x = (e.clientX - rect.left) / rect.width * img.naturalWidth;
                const y = (e.clientY - rect.top) / rect.height * img.naturalHeight;
                const scale = UIScreen?.scale || 2;
                useCoord(Math.round(x / scale), Math.round(y / scale));
            };
        }
        const logData = { ...r };
        if (logData.base64) logData.base64 = logData.base64.substring(0, 40) + '...(已截断)';
        Log.json(logData);
    },

    // ---- 应用信息 ----
    async foreground() {
        const r = await API.call('app/foreground');
        const badge = document.getElementById('foregroundApp');
        if (badge && r.success) {
            badge.textContent = (r.name || r.bundleID || '未知');
            badge.title = r.bundleID || '';
        }
    },

    // ---- 系统信息 ----
    async systemInfo() {
        const r = await API.call('system/info');
        Log.json(r);
    },

    // ---- 取色 ----
    async getPixel() {
        const r = await API.call('screen/getpixel', {
            x: val('tapX'), y: val('tapY')
        });
        Log.json(r);
        if (r.color) {
            setVal('colorHex', r.color);
            document.getElementById('colorPicker').value = r.color;
        }
    }
};

// ============================================
// 辅助函数
// ============================================
function val(id) { return document.getElementById(id)?.value || ''; }
function setVal(id, v) {
    const el = document.getElementById(id);
    if (el) el.value = v;
}

function useCoord(x, y) {
    setVal('tapX', Math.round(x));
    setVal('tapY', Math.round(y));
    toast(`坐标已设为 (${Math.round(x)}, ${Math.round(y)})`);
}

function syncColorPicker() {
    setVal('colorHex', document.getElementById('colorPicker').value);
}

function clearLog() {
    const el = document.getElementById('logOutput');
    if (el) el.innerHTML = '';
}

function toast(msg) {
    const el = document.createElement('div');
    el.className = 'toast';
    el.textContent = msg;
    document.body.appendChild(el);
    setTimeout(() => el.remove(), 2500);
}

// 截图画布点击坐标转换（已内联到 screenshot 处理中）

// ============================================
// 初始化
// ============================================
document.addEventListener('DOMContentLoaded', () => {
    // 初始加载
    actions.foreground();
    actions.systemInfo();

    // 定时刷新前台应用（3秒）
    setInterval(() => actions.foreground(), 3000);

    // 键盘快捷键
    document.addEventListener('keydown', (e) => {
        if (e.key === 'Enter' && e.target.tagName === 'INPUT') {
            const parent = e.target.closest('.card');
            if (!parent) return;
            // 找到最近的按钮并触发
            const btn = parent.querySelector('.btn-primary');
            if (btn) btn.click();
        }
    });

    Log.info('✅ AutoGo 控制台已就绪');
    Log.info(`屏幕: ${window.screen.width}x${window.screen.height} @${window.devicePixelRatio}x`);
});
