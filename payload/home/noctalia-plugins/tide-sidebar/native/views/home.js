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
            icon: 'emblem-system'
        },
        {
            name: '插件开发',
            path: '~/noctalia-plugins',
            icon: 'application-x-addon'
        }
    ],
    bookmarks: [
        {
            name: 'GitHub',
            url: 'https://github.com',
            icon: 'web-browser'
        },
        {
            name: '哔哩哔哩',
            url: 'https://www.bilibili.com',
            icon: 'video-display'
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


const EMOJI = /[\u{1F300}-\u{1FAFF}\u{2600}-\u{27BF}]/u;

// Symbolic icon names resolve from Adwaita; emoji stay supported because the
// workspaces.json contract always allowed them.
function isSymbolicIcon(value) { return /^[a-z0-9-]+(?:-symbolic)?$/.test(String(value || '')); }
function symbolicName(value) {
    const raw = String(value || '').trim();
    if (!isSymbolicIcon(raw)) return null;
    return raw.endsWith('-symbolic') ? raw : raw + '-symbolic';
}

function parseAccent(ctx) {
    const value = String(ctx.palette?.()?.t_accent || '#e8a08c').replace('#', '');
    return {
        red: parseInt(value.slice(0, 2), 16) / 255,
        green: parseInt(value.slice(2, 4), 16) / 255,
        blue: parseInt(value.slice(4, 6), 16) / 255,
    };
}

function present(bin) {
    return Boolean(GLib.find_program_in_path(bin))
        || ['/usr/bin/', '/usr/local/bin/', '/bin/'].some(dir => GLib.file_test(dir + bin, GLib.FileTest.IS_EXECUTABLE));
}

function editorChoice(config) {
    const configured = String(config?.editorCommand || '').trim();
    if (configured) {
        const bin = configured.split(/\s+/)[0];
        if (GLib.find_program_in_path(bin)) return {command: configured, label: bin};
        return {command: '', label: bin, missing: true};
    }
    for (const [bin, label] of [['code', 'Code'], ['codium', 'VSCodium'], ['zed', 'Zed']]) {
        if (present(bin)) return {command: bin, label};
    }
    if (present('kitty') && present('nvim')) {
        return {command: 'kitty -e nvim', label: 'nvim'};
    }
    return null;
}

const quote = value => "'" + String(value).replace(/'/g, "'\\''") + "'";

function launch(command, path) {
    try {
        GLib.spawn_command_line_async(command + ' ' + quote(path));
        return true;
    } catch (_) { return false; }
}

function fractionBar(ui, {height = 6, names = []} = {}) {
    const area = new Gtk.DrawingArea({content_height: height, hexpand: true, can_target: false});
    area.add_css_class('home-fraction');
    if (names.length) ui.classes(area, names);
    area.fraction = 0;
    area.set_draw_func((_w, cr, width, h) => {
        if (width < 2) return;
        const radius = h / 2;
        const acc = area.get_color();
        const dim = acc.copy();
        dim.alpha = 0.16;
        cr.save();
        cr.arc(radius, radius, radius, Math.PI / 2, Math.PI * 1.5);
        cr.arc(Math.max(radius, width - radius), radius, radius, Math.PI * 1.5, Math.PI / 2);
        cr.setSourceRGBA(dim.red, dim.green, dim.blue, dim.alpha);
        cr.fill();
        cr.restore();
        const filled = Math.max(0, Math.min(1, area.fraction)) * width;
        if (filled < 2) return;
        const r2 = Math.min(radius, filled / 2);
        cr.save();
        cr.arc(r2, radius, r2, Math.PI / 2, Math.PI * 1.5);
        cr.arc(Math.max(r2, filled - r2), radius, r2, Math.PI * 1.5, Math.PI / 2);
        cr.setSourceRGBA(acc.red, acc.green, acc.blue, 1);
        cr.fill();
        cr.restore();
    });
    return area;
}

function sparkline(ui, values, {height = 26, alpha = 0.85, ceiling = null} = {}) {
    const area = new Gtk.DrawingArea({content_height: height, hexpand: true, can_target: false});
    area.add_css_class('home-sparkline');
    area.set_draw_func((_w, cr, width, h) => {
        if (width < 4 || h < 4) return;
        const top = ceiling ?? Math.max(1, ...values);
        const step = width / Math.max(1, values.length - 1);
        const y = v => h - 2 - Math.min(1, v / top) * (h - 4);
        const acc = area.get_color();
        cr.moveTo(0, h);
        cr.lineTo(0, y(values[0] || 0));
        values.forEach((v, i) => cr.lineTo(i * step, y(v)));
        cr.lineTo(width, y(values[values.length - 1] || 0));
        cr.lineTo(width, h);
        cr.closePath();
        cr.setSourceRGBA(acc.red, acc.green, acc.blue, 0.18 * alpha);
        cr.fill();
        cr.moveTo(0, y(values[0] || 0));
        values.forEach((v, i) => cr.lineTo(i * step, y(v)));
        cr.setLineWidth(1.6);
        cr.setLineJoin(1);
        cr.setSourceRGBA(acc.red, acc.green, acc.blue, alpha);
        cr.stroke();
    });
    return area;
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
    const diskReadHistory = new Array(HISTORY_POINTS).fill(0);

    let currentCpuPercent = 0;
    let tidePhase = 0;
    let taskSampleCounter = 0;

    const page = ui.box(Gtk.Orientation.VERTICAL, 10, ['home-page', 'scroll-gutter']);
    page.set_hexpand(true); page.set_vexpand(true);
    const widget = new Gtk.ScrolledWindow({
        hscrollbar_policy: Gtk.PolicyType.NEVER,
        vscrollbar_policy: Gtk.PolicyType.AUTOMATIC,
        hexpand: true, vexpand: true,
    });
    widget.add_css_class('list-scroll');
    widget.set_child(page);

    // =========================================================
    // 1. 时钟卡：日期 + 大号时间 + 电池/运行时长 + 潮汐
    // =========================================================
    const clockCard = ui.card(['home-clock-card', 'card-stagger-1']);
    clockCard.set_spacing(0);

    const clockContent = ui.box(Gtk.Orientation.VERTICAL, 4, ['home-clock-content']);
    const dateRow = ui.box(Gtk.Orientation.HORIZONTAL, 8);
    const dateLabel = ui.label('', ['home-date-label']);
    dateLabel.set_hexpand(true);
    dateLabel.set_xalign(0);
    const statusBadge = ui.box(Gtk.Orientation.HORIZONTAL, 5, ['home-live-badge']);
    const statusDot = ui.label('●', ['home-pulse-dot']);
    const statusText = ui.label('在线', ['caption']);
    statusBadge.append(statusDot); statusBadge.append(statusText);
    dateRow.append(dateLabel); dateRow.append(statusBadge);

    const timeRow = ui.box(Gtk.Orientation.HORIZONTAL, 2, ['home-time-row']);
    timeRow.set_valign(Gtk.Align.END);
    const timeMain = ui.label('--:--', ['home-time-main']);
    const timeSec = ui.label(':--', ['home-time-sec']);
    timeSec.set_valign(Gtk.Align.END);
    timeRow.append(timeMain); timeRow.append(timeSec);

    clockContent.append(dateRow);
    clockContent.append(timeRow);
    clockCard.append(clockContent);

    const tideArea = new Gtk.DrawingArea({content_height: 28, hexpand: true, can_target: false});
    tideArea.add_css_class('home-clock-wave');
    tideArea.set_draw_func((_w, cr, width, h) => {
        if (width < 2 || h < 2) return;
        const acc = parseAccent(ctx);
        const stroke = (offset, amplitude, widthPx, alpha) => {
            const y = h * offset;
            cr.moveTo(0, y);
            cr.curveTo(width * .16, y - amplitude * Math.cos(tidePhase), width * .34, y + amplitude * Math.sin(tidePhase * 0.9),
                width * .52, y + amplitude * 0.35);
            cr.curveTo(width * .70, y - amplitude, width * .86, y + amplitude * 0.6, width, y - amplitude * 0.2);
            cr.setLineWidth(widthPx);
            cr.setLineCap(1);
            cr.setSourceRGBA(acc.red, acc.green, acc.blue, alpha);
            cr.stroke();
        };
        stroke(0.42, 3.4, 1.8, 0.9);
        stroke(0.70, 2.4, 1.2, 0.42);
    });
    clockCard.append(tideArea);
    page.append(clockCard);

    // =========================================================
    // 2. 系统概览：CPU / 内存 / NVMe / 网络 四行 + Top 任务
    // =========================================================
    const sysCard = ui.card(['home-cpu-card', 'card-stagger-2']);
    sysCard.set_spacing(10);

    const sysHeader = ui.box(Gtk.Orientation.HORIZONTAL, 8);
    const sysTitle = ui.label('系统概览', ['section-title']);
    sysTitle.set_hexpand(true);
    const tempDot = ui.label('●', ['home-temp-dot']);
    const tempLabel = ui.label('--°C', ['home-temp-label']);
    sysHeader.append(sysTitle); sysHeader.append(tempDot); sysHeader.append(tempLabel);
    sysCard.append(sysHeader);

    const row = (name) => {
        const box = ui.box(Gtk.Orientation.HORIZONTAL, 8, ['home-hw-row']);
        const label = ui.label(name, ['home-hw-name']);
        label.set_size_request(42, -1);
        const value = ui.label('', ['home-hw-value']);
        value.set_xalign(1);
        value.set_size_request(104, -1);
        box.append(label); box.append(value);
        return {box, label, value};
    };

    const cpuRow = row('CPU');
    const cpuSpark = sparkline(ui, cpuHistory, {height: 22, ceiling: 100});
    cpuRow.box.insert_child_after(cpuSpark, cpuRow.label);
    const coreStrip = new Gtk.DrawingArea({content_height: 8, hexpand: true, can_target: false});
    coreStrip.add_css_class('home-core-bars');
    coreStrip.set_draw_func((_w, cr, width, h) => {
        if (width < 8) return;
        const acc = coreStrip.get_color();
        const gap = 3;
        const cell = (width - gap * 15) / 16;
        for (let i = 0; i < 16; i++) {
            const pct = corePercents[i] / 100;
            cr.setSourceRGBA(acc.red, acc.green, acc.blue, 0.10 + 0.80 * pct);
            cr.rectangle(i * (cell + gap), 0, cell, h);
            cr.fill();
        }
    });
    sysCard.append(cpuRow.box);
    sysCard.append(coreStrip);

    const ramRow = row('内存');
    const ramBar = fractionBar(ui, {height: 8, names: ['home-progress']});
    ramBar.set_valign(Gtk.Align.CENTER);
    ramRow.box.insert_child_after(ramBar, ramRow.label);
    sysCard.append(ramRow.box);

    const diskRow = row('NVMe');
    const diskSpark = sparkline(ui, diskReadHistory, {height: 22});
    diskRow.box.insert_child_after(diskSpark, diskRow.label);
    sysCard.append(diskRow.box);

    const netRow = row('网络');
    const netSpark = sparkline(ui, netRxHistory, {height: 22});
    netRow.box.insert_child_after(netSpark, netRow.label);
    sysCard.append(netRow.box);

    const divider = new Gtk.Separator({orientation: Gtk.Orientation.HORIZONTAL});
    sysCard.append(divider);

    const taskRows = [];
    for (let i = 0; i < 3; i++) {
        const line = ui.box(Gtk.Orientation.HORIZONTAL, 8, ['home-task-row']);
        const name = ui.label('—', ['home-task-name']);
        name.set_size_request(88, -1);
        name.set_ellipsize(Pango.EllipsizeMode.END);
        const meter = fractionBar(ui, {height: 6, names: ['home-task-meter']});
        meter.set_valign(Gtk.Align.CENTER);
        const cpu = ui.label('0.0%', ['home-task-cpu']);
        cpu.set_xalign(1);
        cpu.set_size_request(46, -1);
        line.append(name); line.append(meter); line.append(cpu);
        sysCard.append(line);
        taskRows.push({name, meter, cpu});
    }
    page.append(sysCard);

    // =========================================================
    // 3. 工作台：工程 + 书签（接口驱动，编辑器自动探测）
    // =========================================================
    const hubCard = ui.card(['home-launcher-card', 'card-stagger-3']);
    hubCard.set_spacing(8);

    const hubHeader = ui.box(Gtk.Orientation.HORIZONTAL, 8);
    const hubTitle = ui.label('工作台', ['section-title']);
    hubTitle.set_hexpand(true);
    const editConfigBtn = ui.iconButton('document-edit', () => {
        ensureWorkspaceConfig();
        const ed = editorChoice(ctx.config?.());
        if (ed && ed.command && launch(ed.command, WORKSPACES_FILE)) {
            if (ctx.toast) ctx.toast('已在 ' + ed.label + ' 打开工作区配置');
        } else if (launch('xdg-open', WORKSPACES_FILE)) {
            if (ctx.toast) ctx.toast('已用默认程序打开工作区配置');
        } else {
            if (ctx.toast) ctx.toast('打不开配置文件：没有可用的编辑器', true);
        }
    }, '编辑工作区配置 (JSON)', ['launcher-edit-btn']);
    hubHeader.append(hubTitle); hubHeader.append(editConfigBtn);
    hubCard.append(hubHeader);

    const projectList = ui.box(Gtk.Orientation.VERTICAL, 6);
    hubCard.append(projectList);
    const bookmarkGrid = new Gtk.Grid({column_homogeneous: true, row_homogeneous: true, column_spacing: 6, row_spacing: 6});
    hubCard.append(bookmarkGrid);

    function clearBox(box) {
        for (let child = box.get_first_child(); child;) {
            const next = child.get_next_sibling();
            box.remove(child);
            child = next;
        }
    }

    function renderHub() {
        clearBox(projectList);
        clearBox(bookmarkGrid);
        const data = loadHubData();
        const editor = editorChoice(ctx.config?.());

        for (const project of data.workspaces || []) {
            const line = ui.box(Gtk.Orientation.HORIZONTAL, 8, ['launcher-item-row']);
            const iconName = symbolicName(project.icon) || 'folder-symbolic';
            const glyph = ui.icon(iconName, 18);
            const name = ui.label(project.name || project.path || '未命名', ['launcher-item-name']);
            name.set_hexpand(true);
            name.set_ellipsize(Pango.EllipsizeMode.END);
            name.set_xalign(0);
            line.append(glyph); line.append(name);

            const resolved = resolvePath(project.path);
            if (present('kitty')) {
                const term = ui.button('终端', null, () => {
                    if (launch('kitty --directory', resolved)) {
                        if (ctx.toast) ctx.toast('已在终端打开 ' + (project.name || resolved));
                    } else if (ctx.toast) ctx.toast('无法启动终端', true);
                }, ['launcher-action-pill', 'icon-button']);
                term.set_tooltip_text('在终端打开 ' + resolved);
                line.append(term);
            }
            if (editor) {
                const open = ui.button(editor.label, null, () => {
                    if (launch(editor.command, resolved)) {
                        if (ctx.toast) ctx.toast('已在 ' + editor.label + ' 打开 ' + (project.name || resolved));
                    } else if (ctx.toast) {
                        ctx.toast(editor.missing
                            ? '找不到 ' + editor.label + '：请在插件设置里改“编辑器命令”'
                            : '无法启动 ' + editor.label, true);
                    }
                }, ['launcher-action-pill']);
                open.set_tooltip_text('用 ' + editor.label + ' 打开 ' + resolved);
                line.append(open);
            }
            projectList.append(line);
        }

        (data.bookmarks || []).forEach((bookmark, index) => {
            const iconName = symbolicName(bookmark.icon);
            const button = ui.button(bookmark.name || '网址', iconName, () => {
                if (launch('xdg-open', bookmark.url)) {
                    if (ctx.toast) ctx.toast('正在打开 ' + (bookmark.name || bookmark.url));
                } else if (ctx.toast) ctx.toast('无法打开 ' + (bookmark.name || bookmark.url), true);
            }, ['bookmark-pill']);
            button.set_tooltip_text(bookmark.url || '');
            bookmarkGrid.attach(button, index % 2, Math.floor(index / 2), 1, 1);
        });
    }

    page.append(hubCard);

    // =========================================================
    // 采样循环
    // =========================================================
    function updateClock() {
        const now = new Date();
        timeMain.set_label(String(now.getHours()).padStart(2, '0') + ':' + String(now.getMinutes()).padStart(2, '0'));
        timeSec.set_label(':' + String(now.getSeconds()).padStart(2, '0'));
        dateLabel.set_label((now.getMonth() + 1) + '月' + now.getDate() + '日 ' + WEEKDAYS[now.getDay()]);

        const battery = readBattery();
        const uptime = readProcUptime();
        if (battery) {
            const symbol = battery.isCharging ? '⚡ ' : '';
            statusText.set_label(symbol + battery.cap + '% · ' + (uptime || '在线'));
        } else {
            statusText.set_label(uptime || '在线');
        }
    }

    function sampleHardware() {
        const now = GLib.get_monotonic_time();
        const delta = Math.max(0.5, (now - lastSampleTime) / 1e6);
        lastSampleTime = now;

        const stat = readProcStat();
        if (lastStat && stat) {
            const idle = stat.total.idle - lastStat.total.idle;
            const total = stat.total.total - lastStat.total.total;
            if (total > 0) currentCpuPercent = Math.max(0, Math.min(100, Math.round(((total - idle) / total) * 100)));
            for (let i = 0; i < 16; i++) {
                if (!stat.cores[i] || !lastStat.cores[i]) continue;
                const ci = stat.cores[i].idle - lastStat.cores[i].idle;
                const ct = stat.cores[i].total - lastStat.cores[i].total;
                if (ct > 0) corePercents[i] = Math.max(0, Math.min(100, Math.round(((ct - ci) / ct) * 100)));
            }
        }
        lastStat = stat;
        cpuHistory.shift(); cpuHistory.push(currentCpuPercent);
        cpuRow.value.set_label(currentCpuPercent + '%');
        cpuSpark.queue_draw();
        coreStrip.queue_draw();

        const temp = readHwmonTemp();
        if (temp !== null) {
            tempLabel.set_label(temp + '°C');
            tempDot.remove_css_class('warm'); tempDot.remove_css_class('hot');
            if (temp > 75) tempDot.add_css_class('hot');
            else if (temp > 55) tempDot.add_css_class('warm');
        }

        const mem = readProcMeminfo();
        if (mem && mem.total > 0) {
            const pct = Math.round(mem.percent);
            ramRow.value.set_label(formatBytes(mem.used) + ' / ' + formatBytes(mem.total));
            ramBar.fraction = Math.max(0.01, Math.min(1, pct / 100));
            ramBar.queue_draw();
            ramRow.label.set_tooltip_text('可用 ' + formatBytes(mem.avail) + ' · 缓存 ' + formatBytes(mem.cache));
        }

        const disk = readProcDisk();
        let read = 0, write = 0;
        if (lastDisk && disk) {
            read = Math.max(0, Math.round((disk.readBytes - lastDisk.readBytes) / delta));
            write = Math.max(0, Math.round((disk.writeBytes - lastDisk.writeBytes) / delta));
        }
        lastDisk = disk;
        diskReadHistory.shift(); diskReadHistory.push(read);
        diskRow.value.set_label('读 ' + formatSpeed(read) + ' · 写 ' + formatSpeed(write));
        diskSpark.queue_draw();

        const net = readProcNet();
        let rx = 0, tx = 0;
        if (lastNet && net) {
            rx = Math.max(0, Math.round((net.rx - lastNet.rx) / delta));
            tx = Math.max(0, Math.round((net.tx - lastNet.tx) / delta));
        }
        lastNet = net;
        netRxHistory.shift(); netRxHistory.push(rx);
        netRow.value.set_label('↓ ' + formatSpeed(rx) + ' ↑ ' + formatSpeed(tx));
        netSpark.queue_draw();

        // `ps` is the only fork in this loop: sample it every other tick.
        taskSampleCounter++;
        if (taskSampleCounter % 2 === 1) {
            const tasks = readTopTasks();
            taskRows.forEach((rowItem, index) => {
                const task = tasks[index];
                if (task) {
                    rowItem.name.set_label(task.name);
                    rowItem.cpu.set_label(task.cpu.toFixed(1) + '%');
                    rowItem.meter.fraction = Math.max(0.02, Math.min(1, task.cpu / 100));
                    rowItem.meter.queue_draw();
                } else {
                    rowItem.name.set_label('—');
                    rowItem.cpu.set_label('0.0%');
                    rowItem.meter.fraction = 0;
                    rowItem.meter.queue_draw();
                }
            });
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
            hardwareTimer = GLib.timeout_add(GLib.PRIORITY_DEFAULT, 1600, () => {
                if (!shown) { hardwareTimer = 0; return GLib.SOURCE_REMOVE; }
                sampleHardware();
                return GLib.SOURCE_CONTINUE;
            });
        }
        if (!waveTick) {
            waveTick = tideArea.add_tick_callback(() => {
                if (!shown) { waveTick = 0; return GLib.SOURCE_REMOVE; }
                tidePhase = (tidePhase + 0.02) % (Math.PI * 2);
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
        update() {},
        onShow() {
            shown = true;
            renderHub();
            startLoops();
        },
        onHide() {
            shown = false;
            stopLoops();
        },
        handleEscape() { return false; },
    };
}
