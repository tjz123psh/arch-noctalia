import Gtk from 'gi://Gtk?version=4.0';
import GLib from 'gi://GLib';
import Pango from 'gi://Pango';

const HISTORY_POINTS = 24;
const WEEKDAYS = ['星期日', '星期一', '星期二', '星期三', '星期四', '星期五', '星期六'];

const CONFIG_DIR = GLib.build_filenamev([GLib.get_user_config_dir(), 'noctalia']);
const WORKSPACES_FILE = GLib.build_filenamev([CONFIG_DIR, 'workspaces.json']);

const DEFAULT_HUB_CONFIG = {
    workspaces: [
        {
            name: 'arch-noctalia',
            path: '~/Projects/arch-noctalia',
            desc: '系统与侧边栏工程',
            icon: '🌟'
        },
        {
            name: '桌面配置',
            path: '~/.config',
            desc: '~/.config 桌面配置目录',
            icon: '⚙️'
        },
        {
            name: '插件开发',
            path: '~/noctalia-plugins',
            desc: 'Noctalia 插件源码',
            icon: '🧩'
        }
    ],
    bookmarks: [
        {
            name: '雨课堂',
            url: 'https://www.yuketang.cn/web',
            icon: '🎓'
        },
        {
            name: 'GitHub',
            url: 'https://github.com',
            icon: '🐙'
        },
        {
            name: '哔哩哔哩',
            url: 'https://www.bilibili.com',
            icon: '📺'
        },
        {
            name: 'DevDocs',
            url: 'https://devdocs.io',
            icon: '📚'
        }
    ]
};

function resolvePath(p) {
    if (!p) return GLib.get_home_dir();
    if (p.startsWith('~/')) {
        return GLib.build_filenamev([GLib.get_home_dir(), p.slice(2)]);
    }
    return p;
}

function ensureWorkspaceConfig() {
    try {
        if (!GLib.file_test(WORKSPACES_FILE, GLib.FileTest.EXISTS)) {
            GLib.mkdir_with_parents(CONFIG_DIR, 0o755);
            GLib.file_set_contents(WORKSPACES_FILE, JSON.stringify(DEFAULT_HUB_CONFIG, null, 2));
        }
    } catch (_) {}
}

function loadHubData() {
    try {
        ensureWorkspaceConfig();
        const [ok, bytes] = GLib.file_get_contents(WORKSPACES_FILE);
        if (!ok) return DEFAULT_HUB_CONFIG;
        const text = new TextDecoder().decode(bytes);
        const parsed = JSON.parse(text);
        if (Array.isArray(parsed)) {
            return {
                workspaces: parsed,
                bookmarks: DEFAULT_HUB_CONFIG.bookmarks
            };
        }
        if (parsed && typeof parsed === 'object') {
            return {
                workspaces: Array.isArray(parsed.workspaces) ? parsed.workspaces : DEFAULT_HUB_CONFIG.workspaces,
                bookmarks: Array.isArray(parsed.bookmarks) ? parsed.bookmarks : DEFAULT_HUB_CONFIG.bookmarks
            };
        }
        return DEFAULT_HUB_CONFIG;
    } catch (_) {
        return DEFAULT_HUB_CONFIG;
    }
}

function readProcStat() {
    try {
        const [ok, bytes] = GLib.file_get_contents('/proc/stat');
        if (!ok) return null;
        const lines = new TextDecoder().decode(bytes).split('\n');
        // Total CPU
        const totalParts = lines[0].trim().split(/\s+/).slice(1).map(Number);
        const totalIdle = totalParts[3] + (totalParts[4] || 0);
        const totalAll = totalParts.reduce((a, b) => a + b, 0);

        // Per-core CPU
        const cores = [];
        for (const line of lines) {
            if (/^cpu\d+/.test(line)) {
                const parts = line.trim().split(/\s+/).slice(1).map(Number);
                const idle = parts[3] + (parts[4] || 0);
                const total = parts.reduce((a, b) => a + b, 0);
                cores.push({idle, total});
            }
        }
        return {total: {idle: totalIdle, total: totalAll}, cores};
    } catch (_) { return null; }
}

function readProcMeminfo() {
    try {
        const [ok, bytes] = GLib.file_get_contents('/proc/meminfo');
        if (!ok) return null;
        const text = new TextDecoder().decode(bytes);
        let total = 0, avail = 0, cached = 0, buffers = 0;
        for (const line of text.split('\n')) {
            if (line.startsWith('MemTotal:')) total = parseInt(line.replace(/[^0-9]/g, ''), 10) * 1024;
            else if (line.startsWith('MemAvailable:')) avail = parseInt(line.replace(/[^0-9]/g, ''), 10) * 1024;
            else if (line.startsWith('Cached:')) cached = parseInt(line.replace(/[^0-9]/g, ''), 10) * 1024;
            else if (line.startsWith('Buffers:')) buffers = parseInt(line.replace(/[^0-9]/g, ''), 10) * 1024;
        }
        const used = Math.max(0, total - avail);
        return {
            total, used, avail,
            cache: cached + buffers,
            percent: total > 0 ? (used / total) * 100 : 0
        };
    } catch (_) { return null; }
}

function readProcNet() {
    try {
        const [ok, bytes] = GLib.file_get_contents('/proc/net/dev');
        if (!ok) return null;
        const lines = new TextDecoder().decode(bytes).split('\n');
        let rx = 0, tx = 0;
        for (const line of lines) {
            const trimmed = line.trim();
            if (trimmed.startsWith('lo:') || !trimmed.includes(':')) continue;
            const parts = trimmed.split(':')[1].trim().split(/\s+/).map(Number);
            rx += parts[0] || 0;
            tx += parts[8] || 0;
        }
        return {rx, tx};
    } catch (_) { return null; }
}

function readProcDisk() {
    try {
        const [ok, bytes] = GLib.file_get_contents('/proc/diskstats');
        if (!ok) return null;
        const lines = new TextDecoder().decode(bytes).split('\n');
        let readBytes = 0, writeBytes = 0;
        for (const line of lines) {
            const parts = line.trim().split(/\s+/);
            const dev = parts[2] || '';
            if (/^(nvme\d+n\d+|sd[a-z])$/.test(dev)) {
                readBytes += (Number(parts[5]) || 0) * 512;
                writeBytes += (Number(parts[9]) || 0) * 512;
            }
        }
        return {readBytes, writeBytes};
    } catch (_) { return null; }
}

function readHwmonTemp() {
    try {
        for (let i = 0; i < 15; i++) {
            const path = '/sys/class/hwmon/hwmon' + i + '/temp1_input';
            if (GLib.file_test(path, GLib.FileTest.EXISTS)) {
                const [ok, c] = GLib.file_get_contents(path);
                if (ok) {
                    const val = parseInt(new TextDecoder().decode(c).trim(), 10) / 1000;
                    if (val > 20 && val < 115) return Math.round(val);
                }
            }
        }
    } catch (_) {}
    return null;
}

function readBattery() {
    try {
        const [okC, bC] = GLib.file_get_contents('/sys/class/power_supply/BAT1/capacity');
        const [okS, bS] = GLib.file_get_contents('/sys/class/power_supply/BAT1/status');
        if (!okC) return null;
        const cap = parseInt(new TextDecoder().decode(bC).trim(), 10);
        const status = okS ? new TextDecoder().decode(bS).trim() : '';
        const isCharging = status === 'Charging';
        const isFull = status === 'Full';
        return {cap, status, isCharging, isFull};
    } catch (_) { return null; }
}

function readProcUptime() {
    try {
        const [ok, bytes] = GLib.file_get_contents('/proc/uptime');
        if (!ok) return '';
        const seconds = Math.floor(parseFloat(new TextDecoder().decode(bytes).split(' ')[0]) || 0);
        const days = Math.floor(seconds / 86400);
        const hours = Math.floor((seconds % 86400) / 3600);
        const mins = Math.floor((seconds % 3600) / 60);
        if (days > 0) return `运行 ${days}天${hours}时`;
        if (hours > 0) return `运行 ${hours}小时${mins}分`;
        return `运行 ${mins}分钟`;
    } catch (_) { return ''; }
}

function readTopTasks() {
    try {
        const [ok, out] = GLib.spawn_command_line_sync('ps -eo comm,%cpu --sort=-%cpu');
        if (!ok) return [];
        const lines = new TextDecoder().decode(out).trim().split('\n').slice(1);
        const tasks = [];
        for (const line of lines) {
            const parts = line.trim().split(/\s+/);
            const name = parts[0];
            if (name === 'ps' || name === 'sh') continue;
            const cpu = parseFloat(parts[1]) || 0;
            tasks.push({name, cpu});
            if (tasks.length >= 3) break;
        }
        return tasks;
    } catch (_) { return []; }
}

function formatBytes(bytes) {
    const gib = bytes / (1024 * 1024 * 1024);
    return gib.toFixed(1) + ' GiB';
}

function formatSpeed(bytesPerSec) {
    if (bytesPerSec < 1024) return bytesPerSec + ' B/s';
    if (bytesPerSec < 1024 * 1024) return (bytesPerSec / 1024).toFixed(1) + ' KB/s';
    return (bytesPerSec / (1024 * 1024)).toFixed(1) + ' MB/s';
}

export function createHome(ctx) {
    const {ui} = ctx;
    let shown = false;
    let clockTimer = 0;
    let hardwareTimer = 0;
    let waveTick = 0;

    let lastStat = readProcStat();
    let lastNet = readProcNet();
    let lastDisk = readProcDisk();
    let lastSampleTime = GLib.get_monotonic_time();

    const cpuHistory = new Array(HISTORY_POINTS).fill(0);
    const corePercents = new Array(16).fill(0);
    const netRxHistory = new Array(HISTORY_POINTS).fill(0);
    const netTxHistory = new Array(HISTORY_POINTS).fill(0);
    const diskReadHistory = new Array(HISTORY_POINTS).fill(0);
    const diskWriteHistory = new Array(HISTORY_POINTS).fill(0);

    let currentCpuPercent = 0;
    let currentTemp = 36;
    let sparkAnim = 0;
    let tideWavePhase1 = 0;
    let tideWavePhase2 = 1.2;

    const page = ui.box(Gtk.Orientation.VERTICAL, 14, ['home-page', 'scroll-gutter']);
    page.set_hexpand(true);
    page.set_vexpand(true);
    const widget = new Gtk.ScrolledWindow({
        hscrollbar_policy: Gtk.PolicyType.NEVER,
        vscrollbar_policy: Gtk.PolicyType.AUTOMATIC,
        hexpand: true, vexpand: true,
    });
    widget.add_css_class('list-scroll');
    widget.set_child(page);

    // =========================================================
    // 1. 顶部时间与双层交错流波卡片
    // =========================================================
    const clockCard = ui.card(['home-clock-card', 'card-stagger-1']);
    clockCard.set_spacing(0);

    const clockContent = ui.box(Gtk.Orientation.VERTICAL, 6, ['home-clock-content']);
    const dateRow = ui.box(Gtk.Orientation.HORIZONTAL, 6);
    const dateLabel = ui.label('正在加载日期…', ['home-date-label']);
    dateLabel.set_hexpand(true);

    const liveBadge = ui.box(Gtk.Orientation.HORIZONTAL, 5, ['home-live-badge']);
    const pulseDot = ui.label('●', ['home-pulse-dot']);
    const statusBadgeText = ui.label('在线', ['caption']);
    liveBadge.append(pulseDot);
    liveBadge.append(statusBadgeText);
    dateRow.append(dateLabel);
    dateRow.append(liveBadge);
    clockContent.append(dateRow);

    const timeRow = ui.box(Gtk.Orientation.HORIZONTAL, 2, ['home-time-row']);
    const timeMain = ui.label('00:00', ['home-time-main']);
    const timeSec = ui.label(':00', ['home-time-sec']);
    timeSec.set_valign(Gtk.Align.BASELINE);
    timeRow.append(timeMain);
    timeRow.append(timeSec);
    clockContent.append(timeRow);

    clockCard.append(clockContent);

    // 双层自然流动潮汐水波
    const tideArea = new Gtk.DrawingArea({content_height: 38, hexpand: true, can_target: false});
    tideArea.add_css_class('home-clock-wave');
    tideArea.set_draw_func((_w, cr, width, h) => {
        if (width < 2 || h < 2) return;
        const cornerRadius = 18;

        // Wave Layer 1 (Under - Pale Yellow #F6E0A0)
        const y1 = h * 0.35, a1 = 3.5;
        cr.moveTo(0, y1);
        cr.curveTo(width * .15, y1 - a1 * Math.cos(tideWavePhase1), width * .30, y1 + a1, width * .48, y1 + a1 * .2);
        cr.curveTo(width * .62, y1 - a1, width * .78, y1 - a1 * Math.cos(tideWavePhase1 + .8), width, y1 + a1 * .3);
        cr.lineTo(width, h - cornerRadius);
        cr.curveTo(width, h - cornerRadius * .45, width - cornerRadius * .45, h, width - cornerRadius, h);
        cr.lineTo(cornerRadius, h);
        cr.curveTo(cornerRadius * .45, h, 0, h - cornerRadius * .45, 0, h - cornerRadius);
        cr.closePath();
        cr.setSourceRGBA(0.96, 0.88, 0.63, 0.70);
        cr.fill();

        // Wave Layer 2 (Over - Deep Warm Gold #ECD081)
        const y2 = h * 0.45, a2 = 2.5;
        cr.moveTo(0, y2);
        cr.curveTo(width * .18, y2 + a2 * Math.sin(tideWavePhase2), width * .38, y2 - a2, width * .55, y2 + a2 * .4);
        cr.curveTo(width * .72, y2 - a2, width * .86, y2 + a2 * Math.cos(tideWavePhase2 + .5), width, y2 - a2 * .2);
        cr.lineTo(width, h - cornerRadius);
        cr.curveTo(width, h - cornerRadius * .45, width - cornerRadius * .45, h, width - cornerRadius, h);
        cr.lineTo(cornerRadius, h);
        cr.curveTo(cornerRadius * .45, h, 0, h - cornerRadius * .45, 0, h - cornerRadius);
        cr.closePath();
        cr.setSourceRGBA(0.92, 0.82, 0.51, 0.90);
        cr.fill();
    });
    clockCard.append(tideArea);
    page.append(clockCard);

    // =========================================================
    // 2. CPU 计算核心与 16 线程动态律动矩阵
    // =========================================================
    const cpuCard = ui.card(['home-cpu-card', 'card-stagger-2']);
    cpuCard.set_spacing(10);

    const cpuHeader = ui.box(Gtk.Orientation.HORIZONTAL, 8);
    const cpuTitle = ui.label('CPU 计算引擎', ['section-title']);
    cpuTitle.set_hexpand(true);

    const cpuSubBox = ui.box(Gtk.Orientation.HORIZONTAL, 6);
    const tempDot = ui.label('●', ['home-temp-dot']);
    const tempLabel = ui.label('35°C', ['caption', 'home-temp-label']);
    const cpuValue = ui.label('0%', ['home-hw-value']);
    cpuSubBox.append(tempDot);
    cpuSubBox.append(tempLabel);
    cpuSubBox.append(cpuValue);
    cpuHeader.append(cpuTitle);
    cpuHeader.append(cpuSubBox);
    cpuCard.append(cpuHeader);

    // 总体 CPU 脉冲波形图
    const sparkline = new Gtk.DrawingArea({content_height: 42, hexpand: true, can_target: false});
    sparkline.add_css_class('home-sparkline');
    sparkline.set_draw_func((_w, cr, width, height) => {
        if (width < 10 || height < 10) return;
        const padY = 5;
        const graphH = height - padY * 2;
        const stepX = width / (HISTORY_POINTS - 1);

        cr.setLineWidth(2.0);
        cr.setLineJoin(1);
        cr.setLineCap(1);

        const points = [];
        for (let i = 0; i < HISTORY_POINTS; i++) {
            const raw = Math.max(0, Math.min(100, cpuHistory[i]));
            const idleWave = raw < 4 ? (Math.sin(i * 0.7 + sparkAnim) * 2.2 + 3.8) : raw;
            const val = Math.max(2, Math.min(100, idleWave));
            const x = i * stepX;
            const y = height - padY - (val / 100) * graphH;
            points.push({x, y});
        }

        cr.moveTo(points[0].x, points[0].y);
        for (let i = 1; i < HISTORY_POINTS; i++) {
            const prev = points[i - 1];
            const curr = points[i];
            const midX = (prev.x + curr.x) / 2;
            cr.curveTo(midX, prev.y, midX, curr.y, curr.x, curr.y);
        }

        // Fill
        cr.save();
        cr.lineTo(width, height);
        cr.lineTo(0, height);
        cr.closePath();
        cr.setSourceRGBA(0.43, 0.37, 0.11, 0.12);
        cr.fill();
        cr.restore();

        // Stroke
        cr.setSourceRGBA(0.43, 0.37, 0.11, 0.85);
        cr.stroke();

        // End pulse dot
        const last = points[HISTORY_POINTS - 1];
        cr.arc(last.x - 2, last.y, 4, 0, Math.PI * 2);
        cr.setSourceRGBA(0.43, 0.37, 0.11, 0.25);
        cr.fill();
        cr.arc(last.x - 2, last.y, 2.5, 0, Math.PI * 2);
        cr.setSourceRGBA(0.43, 0.37, 0.11, 1.0);
        cr.fill();
    });
    cpuCard.append(sparkline);

    // 16 核心多线程动态律动矩阵
    const coreSection = ui.box(Gtk.Orientation.VERTICAL, 4);
    const coreHeader = ui.box(Gtk.Orientation.HORIZONTAL, 6);
    const coreTitle = ui.label('多核线程分布 (16 Cores)', ['caption']);
    coreTitle.set_hexpand(true);
    coreHeader.append(coreTitle);
    coreSection.append(coreHeader);

    const coreBars = new Gtk.DrawingArea({content_height: 24, hexpand: true, can_target: false});
    coreBars.add_css_class('home-core-bars');
    coreBars.set_draw_func((_w, cr, width, height) => {
        if (width < 20 || height < 8) return;
        const count = 16;
        const gap = 3;
        const barWidth = Math.max(3, (width - gap * (count - 1)) / count);

        for (let i = 0; i < count; i++) {
            const x = i * (barWidth + gap);
            const val = Math.max(0.06, Math.min(1.0, (corePercents[i] || 0) / 100));
            const barH = val * (height - 2);

            // Background slot
            cr.setSourceRGBA(0.43, 0.37, 0.11, 0.10);
            cr.rectangle(x, 1, barWidth, height - 2);
            cr.fill();

            // Active bar
            cr.setSourceRGBA(0.43, 0.37, 0.11, 0.75 + val * 0.25);
            cr.rectangle(x, height - 1 - barH, barWidth, barH);
            cr.fill();
        }
    });
    coreSection.append(coreBars);
    cpuCard.append(coreSection);

    page.append(cpuCard);

    // =========================================================
    // 3. 内存与缓存监控卡片
    // =========================================================
    const memCard = ui.card(['home-mem-card', 'card-stagger-2']);
    memCard.set_spacing(8);

    const memHeader = ui.box(Gtk.Orientation.HORIZONTAL, 8);
    const memTitle = ui.label('内存占用 (RAM)', ['section-title']);
    memTitle.set_hexpand(true);
    const memValue = ui.label('0 GiB / 0 GiB', ['home-hw-sub']);
    memHeader.append(memTitle);
    memHeader.append(memValue);
    memCard.append(memHeader);

    // 内存胶囊进度条
    const memTrack = ui.box(Gtk.Orientation.HORIZONTAL, 0, ['home-progress-track']);
    memTrack.set_size_request(-1, 8);
    const memFill = ui.box(Gtk.Orientation.HORIZONTAL, 0, ['home-progress-fill']);
    memFill.set_hexpand(false);
    memTrack.append(memFill);
    memCard.append(memTrack);

    const memDetail = ui.box(Gtk.Orientation.HORIZONTAL, 8);
    const memAvailLabel = ui.label('可用: —', ['caption']);
    memAvailLabel.set_hexpand(true);
    const memCacheLabel = ui.label('缓存: —', ['caption']);
    memDetail.append(memAvailLabel);
    memDetail.append(memCacheLabel);
    memCard.append(memDetail);

    page.append(memCard);

    // =========================================================
    // 4. NVMe 磁盘实时读写动态对冲示波器
    // =========================================================
    const diskCard = ui.card(['home-disk-card', 'card-stagger-3']);
    diskCard.set_spacing(10);

    const diskHeader = ui.box(Gtk.Orientation.HORIZONTAL, 8);
    const diskTitle = ui.label('NVMe 存储吞吐', ['section-title']);
    diskTitle.set_hexpand(true);

    const diskSpeedBox = ui.box(Gtk.Orientation.HORIZONTAL, 12, ['home-net-speed-box']);
    const diskReadLabel = ui.label('读 ↓ 0 B/s', ['home-speed-rx']);
    const diskWriteLabel = ui.label('写 ↑ 0 B/s', ['home-speed-tx']);
    diskSpeedBox.append(diskReadLabel);
    diskSpeedBox.append(diskWriteLabel);
    diskHeader.append(diskTitle);
    diskHeader.append(diskSpeedBox);
    diskCard.append(diskHeader);

    // 双向对冲脉冲图 (Read up / Write down)
    const diskGraph = new Gtk.DrawingArea({content_height: 44, hexpand: true, can_target: false});
    diskGraph.add_css_class('home-net-graph');
    diskGraph.set_draw_func((_w, cr, width, height) => {
        if (width < 10 || height < 10) return;
        const midY = height * 0.5;
        const stepX = width / (HISTORY_POINTS - 1);
        const maxVal = Math.max(1024 * 1024, ...diskReadHistory, ...diskWriteHistory);

        // Center baseline
        cr.setLineWidth(1.0);
        cr.setSourceRGBA(0.43, 0.37, 0.11, 0.15);
        cr.moveTo(0, midY);
        cr.lineTo(width, midY);
        cr.stroke();

        // 1. Read Stream (pulsing upwards)
        cr.setLineWidth(1.8);
        cr.moveTo(0, midY);
        for (let i = 0; i < HISTORY_POINTS; i++) {
            const val = diskReadHistory[i] || 0;
            const h = (val / maxVal) * (midY - 3);
            const x = i * stepX;
            const y = midY - Math.max(0, h);
            cr.lineTo(x, y);
        }
        cr.lineTo(width, midY);
        cr.setSourceRGBA(0.28, 0.50, 0.35, 0.85);
        cr.stroke();

        // 2. Write Stream (pulsing downwards)
        cr.moveTo(0, midY);
        for (let i = 0; i < HISTORY_POINTS; i++) {
            const val = diskWriteHistory[i] || 0;
            const h = (val / maxVal) * (midY - 3);
            const x = i * stepX;
            const y = midY + Math.max(0, h);
            cr.lineTo(x, y);
        }
        cr.lineTo(width, midY);
        cr.setSourceRGBA(0.75, 0.45, 0.18, 0.85);
        cr.stroke();
    });
    diskCard.append(diskGraph);
    page.append(diskCard);

    // =========================================================
    // 5. 实时网络流量动态水流卡片
    // =========================================================
    const netCard = ui.card(['home-net-card', 'card-stagger-3']);
    netCard.set_spacing(10);

    const netHeader = ui.box(Gtk.Orientation.HORIZONTAL, 8);
    const netTitle = ui.label('实时网络吞吐', ['section-title']);
    netTitle.set_hexpand(true);

    const speedBox = ui.box(Gtk.Orientation.HORIZONTAL, 12, ['home-net-speed-box']);
    const rxLabel = ui.label('↓ 0 B/s', ['home-speed-rx']);
    const txLabel = ui.label('↑ 0 B/s', ['home-speed-tx']);
    speedBox.append(rxLabel);
    speedBox.append(txLabel);
    netHeader.append(netTitle);
    netHeader.append(speedBox);
    netCard.append(netHeader);

    // 双流波形图 (Rx / Tx Sparkline)
    const netFlowGraph = new Gtk.DrawingArea({content_height: 44, hexpand: true, can_target: false});
    netFlowGraph.add_css_class('home-net-graph');
    netFlowGraph.set_draw_func((_w, cr, width, height) => {
        if (width < 10 || height < 10) return;
        const padY = 4;
        const graphH = height - padY * 2;
        const stepX = width / (HISTORY_POINTS - 1);

        const maxRx = Math.max(50 * 1024, ...netRxHistory);
        const maxTx = Math.max(50 * 1024, ...netTxHistory);
        const scaleCeil = Math.max(maxRx, maxTx);

        function drawStream(data, r, g, b) {
            cr.setLineWidth(1.8);
            cr.setLineJoin(1);
            cr.setLineCap(1);

            const points = [];
            for (let i = 0; i < HISTORY_POINTS; i++) {
                const val = data[i] || 0;
                const ripple = val < 1024 ? (Math.sin(i * 0.8 + sparkAnim) * 1.5 + 2) : (val / scaleCeil) * 100;
                const normalized = Math.max(2, Math.min(100, ripple));
                const x = i * stepX;
                const y = height - padY - (normalized / 100) * graphH;
                points.push({x, y});
            }

            cr.moveTo(points[0].x, points[0].y);
            for (let i = 1; i < HISTORY_POINTS; i++) {
                const prev = points[i - 1];
                const curr = points[i];
                const midX = (prev.x + curr.x) / 2;
                cr.curveTo(midX, prev.y, midX, curr.y, curr.x, curr.y);
            }

            cr.save();
            cr.lineTo(width, height);
            cr.lineTo(0, height);
            cr.closePath();
            cr.setSourceRGBA(r, g, b, 0.12);
            cr.fill();
            cr.restore();

            cr.setSourceRGBA(r, g, b, 0.85);
            cr.stroke();

            const last = points[HISTORY_POINTS - 1];
            cr.arc(last.x - 2, last.y, 2.5, 0, Math.PI * 2);
            cr.setSourceRGBA(r, g, b, 1.0);
            cr.fill();
        }

        drawStream(netRxHistory, 0.28, 0.50, 0.35);
        drawStream(netTxHistory, 0.55, 0.45, 0.15);
    });
    netCard.append(netFlowGraph);
    page.append(netCard);

    // =========================================================
    // 6. 前台活跃任务雷达 (Top Active Tasks)
    // =========================================================
    const taskCard = ui.card(['home-task-card', 'card-stagger-3']);
    taskCard.set_spacing(8);

    const taskHeader = ui.box(Gtk.Orientation.HORIZONTAL, 6);
    const taskTitle = ui.label('前台活跃任务 (Top Tasks)', ['section-title']);
    taskTitle.set_hexpand(true);
    taskHeader.append(taskTitle);
    taskCard.append(taskHeader);

    const taskRows = [];
    for (let i = 0; i < 3; i++) {
        const row = ui.box(Gtk.Orientation.HORIZONTAL, 8, ['home-task-row']);
        const nameLabel = ui.label('—', ['home-task-name']);
        nameLabel.set_hexpand(true);

        const meterTrack = ui.box(Gtk.Orientation.HORIZONTAL, 0, ['home-task-meter-track']);
        meterTrack.set_size_request(90, 6);
        const meterFill = ui.box(Gtk.Orientation.HORIZONTAL, 0, ['home-task-meter-fill']);
        meterTrack.append(meterFill);

        const cpuLabel = ui.label('0.0%', ['caption', 'home-task-cpu']);
        cpuLabel.set_size_request(42, -1);
        cpuLabel.set_xalign(1);

        row.append(nameLabel);
        row.append(meterTrack);
        row.append(cpuLabel);
        taskCard.append(row);
        taskRows.push({nameLabel, meterFill, cpuLabel});
    }
    page.append(taskCard);

    // =========================================================
    // 6. 极速工作台与网址书签 (Workspaces & Bookmarks - 动态接口驱动)
    // =========================================================
    const launcherCard = ui.card(['home-launcher-card', 'card-stagger-3']);
    launcherCard.set_spacing(10);

    const launcherHeader = ui.box(Gtk.Orientation.HORIZONTAL, 8);
    const launcherTitle = ui.label('工作台与书签', ['section-title']);
    launcherTitle.set_hexpand(true);

    const editConfigBtn = ui.iconButton('document-edit', () => {
        ensureWorkspaceConfig();
        GLib.spawn_command_line_async(`code "${WORKSPACES_FILE}" || xdg-open "${WORKSPACES_FILE}"`);
        if (ctx.toast) ctx.toast('已打开配置接口: workspaces.json');
    }, '编辑工程与书签列表 (JSON 接口)');
    editConfigBtn.add_css_class('launcher-edit-btn');

    launcherHeader.append(launcherTitle);
    launcherHeader.append(editConfigBtn);
    launcherCard.append(launcherHeader);

    // --- 分组 1: 项目列表 ---
    const wsSubHeader = ui.label('项目列表 · Projects', ['caption']);
    wsSubHeader.set_xalign(0);
    launcherCard.append(wsSubHeader);

    const projectListBox = ui.box(Gtk.Orientation.VERTICAL, 6);
    launcherCard.append(projectListBox);

    // --- 分组 2: 常用网址 ---
    const bookmarkSubHeader = ui.label('常用网址 · Bookmarks', ['caption']);
    bookmarkSubHeader.set_xalign(0);
    launcherCard.append(bookmarkSubHeader);

    const bookmarkGrid = new Gtk.Grid({column_homogeneous: true, row_homogeneous: true, column_spacing: 6, row_spacing: 6});
    launcherCard.append(bookmarkGrid);

    function renderHub() {
        ui.clear(projectListBox);
        for (let child = bookmarkGrid.get_first_child(); child;) {
            const next = child.get_next_sibling();
            bookmarkGrid.remove(child);
            child = next;
        }

        const data = loadHubData();
        const projects = data.workspaces || [];
        const bookmarks = data.bookmarks || [];

        projects.forEach(p => {
            const row = ui.box(Gtk.Orientation.HORIZONTAL, 6, ['launcher-item-row']);
            const info = ui.box(Gtk.Orientation.VERTICAL, 1);
            info.set_hexpand(true);
            const titleText = (p.icon ? p.icon + ' ' : '') + (p.name || '未命名工程');
            const nameLabel = ui.label(titleText, ['launcher-item-name']);
            nameLabel.set_xalign(0);
            const descLabel = ui.label(p.desc || p.path || '', ['caption', 'launcher-item-desc']);
            descLabel.set_xalign(0);
            info.append(nameLabel);
            info.append(descLabel);
            row.append(info);

            const resolved = resolvePath(p.path);

            const termBtn = ui.button('终端', null, () => {
                GLib.spawn_command_line_async(`kitty --directory "${resolved}"`);
                if (ctx.toast) ctx.toast(`已在终端打开: ${p.name}`);
            }, ['dev-pill', 'launcher-action-pill']);
            termBtn.set_tooltip_text(`在 Kitty 终端打开: ${resolved}`);

            const codeBtn = ui.button('Code', null, () => {
                GLib.spawn_command_line_async(`code "${resolved}"`);
                if (ctx.toast) ctx.toast(`已在 VS Code 打开: ${p.name}`);
            }, ['dev-pill', 'launcher-action-pill']);
            codeBtn.set_tooltip_text(`在 VS Code 打开: ${resolved}`);

            row.append(termBtn);
            row.append(codeBtn);
            projectListBox.append(row);
        });

        bookmarks.forEach((bm, i) => {
            const labelText = (bm.icon ? bm.icon + ' ' : '') + (bm.name || bm.label || '网址');
            const btn = ui.button(labelText, null, () => {
                GLib.spawn_command_line_async(`xdg-open "${bm.url}"`);
                if (ctx.toast) ctx.toast(`正在打开: ${labelText}`);
            }, ['dev-pill', 'bookmark-pill']);
            btn.set_tooltip_text(bm.url || '');
            bookmarkGrid.attach(btn, i % 2, Math.floor(i / 2), 1, 1);
        });
    }

    renderHub();
    page.append(launcherCard);

    // =========================================================
    // 动态采样与时钟循环
    // =========================================================
    function updateClock() {
        const now = new Date();
        const hh = String(now.getHours()).padStart(2, '0');
        const mm = String(now.getMinutes()).padStart(2, '0');
        const ss = String(now.getSeconds()).padStart(2, '0');
        timeMain.set_label(`${hh}:${mm}`);
        timeSec.set_label(`:${ss}`);

        const month = now.getMonth() + 1;
        const date = now.getDate();
        const weekday = WEEKDAYS[now.getDay()];
        dateLabel.set_label(`${month}月${date}日 ${weekday}`);

        const bat = readBattery();
        const uptime = readProcUptime();
        if (bat) {
            const symbol = bat.isCharging ? '⚡ ' : '';
            statusBadgeText.set_label(`${symbol}${bat.cap}% · ${uptime || '正常'}`);
        } else {
            statusBadgeText.set_label(uptime || '在线');
        }
    }

    function sampleHardware() {
        const nowTime = GLib.get_monotonic_time();
        const deltaSec = Math.max(0.5, (nowTime - lastSampleTime) / 1000000);
        lastSampleTime = nowTime;

        // 1. CPU & Temperature
        const nextStat = readProcStat();
        if (lastStat && nextStat) {
            const idleDelta = nextStat.total.idle - lastStat.total.idle;
            const totalDelta = nextStat.total.total - lastStat.total.total;
            if (totalDelta > 0) {
                currentCpuPercent = Math.max(0, Math.min(100, Math.round(((totalDelta - idleDelta) / totalDelta) * 100)));
            }

            for (let i = 0; i < 16; i++) {
                if (nextStat.cores[i] && lastStat.cores[i]) {
                    const cIdle = nextStat.cores[i].idle - lastStat.cores[i].idle;
                    const cTotal = nextStat.cores[i].total - lastStat.cores[i].total;
                    if (cTotal > 0) {
                        corePercents[i] = Math.max(0, Math.min(100, Math.round(((cTotal - cIdle) / cTotal) * 100)));
                    }
                }
            }
        }
        lastStat = nextStat;
        cpuHistory.shift();
        cpuHistory.push(currentCpuPercent);
        cpuValue.set_label(`${currentCpuPercent}%`);

        const temp = readHwmonTemp();
        if (temp !== null) {
            currentTemp = temp;
            tempLabel.set_label(`${currentTemp}°C`);
            if (currentTemp > 75) {
                tempDot.remove_css_class('warm'); tempDot.add_css_class('hot');
            } else if (currentTemp > 55) {
                tempDot.remove_css_class('hot'); tempDot.add_css_class('warm');
            } else {
                tempDot.remove_css_class('hot'); tempDot.remove_css_class('warm');
            }
        }

        sparkAnim = (sparkAnim + 0.35) % (Math.PI * 2);
        sparkline.queue_draw();
        coreBars.queue_draw();

        // 2. Memory
        const mem = readProcMeminfo();
        if (mem && mem.total > 0) {
            const memPercent = Math.round(mem.percent);
            memValue.set_label(`${formatBytes(mem.used)} / ${formatBytes(mem.total)} (${memPercent}%)`);
            memAvailLabel.set_label(`可用: ${formatBytes(mem.avail)}`);
            memCacheLabel.set_label(`缓存: ${formatBytes(mem.cache)}`);

            const fraction = Math.max(0.02, Math.min(1.0, memPercent / 100));
            memFill.set_size_request(Math.max(8, Math.round(fraction * 360)), 8);
        }

        // 3. Disk I/O
        const nextDisk = readProcDisk();
        let rSpeed = 0, wSpeed = 0;
        if (lastDisk && nextDisk) {
            rSpeed = Math.max(0, Math.round((nextDisk.readBytes - lastDisk.readBytes) / deltaSec));
            wSpeed = Math.max(0, Math.round((nextDisk.writeBytes - lastDisk.writeBytes) / deltaSec));
        }
        lastDisk = nextDisk;
        diskReadHistory.shift();
        diskReadHistory.push(rSpeed);
        diskWriteHistory.shift();
        diskWriteHistory.push(wSpeed);

        diskReadLabel.set_label(`读 ↓ ${formatSpeed(rSpeed)}`);
        diskWriteLabel.set_label(`写 ↑ ${formatSpeed(wSpeed)}`);
        diskGraph.queue_draw();

        // 4. Network
        const nextNet = readProcNet();
        let rxSpeed = 0, txSpeed = 0;
        if (lastNet && nextNet) {
            rxSpeed = Math.max(0, Math.round((nextNet.rx - lastNet.rx) / deltaSec));
            txSpeed = Math.max(0, Math.round((nextNet.tx - lastNet.tx) / deltaSec));
        }
        lastNet = nextNet;
        netRxHistory.shift();
        netRxHistory.push(rxSpeed);
        netTxHistory.shift();
        netTxHistory.push(txSpeed);

        rxLabel.set_label(`↓ ${formatSpeed(rxSpeed)}`);
        txLabel.set_label(`↑ ${formatSpeed(txSpeed)}`);
        netFlowGraph.queue_draw();

        // 5. Top Tasks
        const tasks = readTopTasks();
        for (let i = 0; i < 3; i++) {
            const row = taskRows[i];
            const t = tasks[i];
            if (t) {
                row.nameLabel.set_label(t.name);
                row.cpuLabel.set_label(t.cpu.toFixed(1) + '%');
                const fraction = Math.max(0.04, Math.min(1.0, t.cpu / 100));
                row.meterFill.set_size_request(Math.round(fraction * 90), 6);
            } else {
                row.nameLabel.set_label('—');
                row.cpuLabel.set_label('0.0%');
                row.meterFill.set_size_request(4, 6);
            }
        }
    }

    function startLoops() {
        if (!shown) return;
        updateClock();
        sampleHardware();
        if (!clockTimer) {
            clockTimer = GLib.timeout_add(GLib.PRIORITY_DEFAULT, 1000, () => {
                if (!shown) { clockTimer = 0; return GLib.SOURCE_REMOVE; }
                updateClock();
                return GLib.SOURCE_CONTINUE;
            });
        }
        if (!hardwareTimer) {
            hardwareTimer = GLib.timeout_add(GLib.PRIORITY_DEFAULT, 1200, () => {
                if (!shown) { hardwareTimer = 0; return GLib.SOURCE_REMOVE; }
                sampleHardware();
                return GLib.SOURCE_CONTINUE;
            });
        }
        if (!waveTick) {
            waveTick = tideArea.add_tick_callback(() => {
                if (!shown) { waveTick = 0; return GLib.SOURCE_REMOVE; }
                tideWavePhase1 = (tideWavePhase1 + 0.024) % (Math.PI * 2);
                tideWavePhase2 = (tideWavePhase2 + 0.032) % (Math.PI * 2);
                tideArea.queue_draw();
                return GLib.SOURCE_CONTINUE;
            });
        }
    }

    function stopLoops() {
        if (clockTimer) { GLib.source_remove(clockTimer); clockTimer = 0; }
        if (hardwareTimer) { GLib.source_remove(hardwareTimer); hardwareTimer = 0; }
        if (waveTick) { tideArea.remove_tick_callback(waveTick); waveTick = 0; }
    }

    return {
        widget,
        update(_state) {},
        onShow() {
            shown = true;
            renderHub();
            startLoops();
        },
        onHide() {
            shown = false;
            stopLoops();
        },
        handleEscape() {
            return false;
        },
    };
}
