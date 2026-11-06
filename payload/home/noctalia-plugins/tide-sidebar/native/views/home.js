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
    area.reveal = 1;
    area.set_draw_func((_w, cr, width, h) => {
        if (width < 2) return;
        const radius = h / 2;
        const acc = area.get_color();
        const dim = acc.copy();
        dim.alpha = acc.alpha * 0.16;
        cr.save();
        cr.arc(radius, radius, radius, Math.PI / 2, Math.PI * 1.5);
        cr.arc(Math.max(radius, width - radius), radius, radius, Math.PI * 1.5, Math.PI / 2);
        cr.setSourceRGBA(dim.red, dim.green, dim.blue, dim.alpha);
        cr.fill();
        cr.restore();
        const filled = Math.max(0, Math.min(1, area.fraction)) * width * Math.max(0, area.reveal);
        if (filled < 2) return;
        const r2 = Math.min(radius, filled / 2);
        cr.save();
        cr.arc(r2, radius, r2, Math.PI / 2, Math.PI * 1.5);
        cr.arc(Math.max(r2, filled - r2), radius, r2, Math.PI * 1.5, Math.PI / 2);
        // Respect the token's alpha: @t_data is fg at 22%, and forcing 1.0
        // painted the neutral bars as solid white.
        cr.setSourceRGBA(acc.red, acc.green, acc.blue, acc.alpha);
        cr.fill();
        cr.restore();
    });
    return area;
}

function sparkline(ui, values, {height = 26, alpha = 0.85, ceiling = null} = {}) {
    const area = new Gtk.DrawingArea({content_height: height, hexpand: true, can_target: false});
    area.add_css_class('home-sparkline');
    area.reveal = 1;
    area.set_draw_func((_w, cr, width, h) => {
        if (width < 4 || h < 4) return;
        cr.save();
        if (area.reveal < 1) { cr.rectangle(0, 0, width * Math.max(0, area.reveal), h); cr.clip(); }
        const top = ceiling ?? Math.max(1, ...values);
        const step = width / Math.max(1, values.length - 1);
        const y = v => h - 2 - Math.min(1, v / top) * (h - 4);
        const acc = area.get_color();
        // Idle rows draw nothing: a flat series pinned to the bottom edge reads
        // as a stray divider between two metrics, not as a chart.
        if (Math.max(...values, 0) < 1) return;
        cr.moveTo(0, h);
        cr.lineTo(0, y(values[0] || 0));
        values.forEach((v, i) => cr.lineTo(i * step, y(v)));
        cr.lineTo(width, y(values[values.length - 1] || 0));
        cr.lineTo(width, h);
        cr.closePath();
        cr.setSourceRGBA(acc.red, acc.green, acc.blue, 0.16 * alpha);
        cr.fill();
        cr.moveTo(0, y(values[0] || 0));
        values.forEach((v, i) => cr.lineTo(i * step, y(v)));
        cr.setLineWidth(1.5);
        cr.setLineJoin(1);
        cr.setSourceRGBA(acc.red, acc.green, acc.blue, alpha);
        cr.stroke();
        cr.restore();
    });
    return area;
}

export function createHome(ctx) {
    const {ui} = ctx;
    let shown = false;
    let clockTimer = 0;
    let hardwareTimer = 0;

    let lastStat = readProcStat();
    let lastNet = readProcNet();
    let lastDisk = readProcDisk();
    let lastSampleTime = GLib.get_monotonic_time();

    const cpuHistory = new Array(HISTORY_POINTS).fill(0);
    const corePercents = new Array(16).fill(0);
    const netRxHistory = new Array(HISTORY_POINTS).fill(0);
    const diskReadHistory = new Array(HISTORY_POINTS).fill(0);

    let currentCpuPercent = 0;
    let taskSampleCounter = 0;

    const page = ui.box(Gtk.Orientation.VERTICAL, 10, ['home-page', 'scroll-gutter']);
    page.set_hexpand(true); page.set_vexpand(true);
    const widget = new Gtk.ScrolledWindow({
        hscrollbar_policy: Gtk.PolicyType.NEVER, propagate_natural_width: false,
        vscrollbar_policy: Gtk.PolicyType.AUTOMATIC,
        hexpand: true, vexpand: true,
    });
    widget.add_css_class('list-scroll');
    widget.set_child(page);

    // =========================================================
    // macOS 分组列表：hero + 「系统」「进程」「工作台」三组
    // =========================================================
    const sectionRow = (text) => {
        const row = ui.box(Gtk.Orientation.HORIZONTAL, 6, ['mac-section-row']);
        const label = ui.label(text, ['mac-section']);
        label.set_hexpand(true);
        row.append(label);
        return row;
    };

    // hero：日期 + 大号时间 + 电池/运行时长
    const hero = ui.box(Gtk.Orientation.VERTICAL, 2, ['mac-group', 'home-hero']);
    const heroTop = ui.box(Gtk.Orientation.HORIZONTAL, 8);
    const dateLabel = ui.label('', ['home-date-label']);
    dateLabel.set_hexpand(true);
    const statusBadge = ui.box(Gtk.Orientation.HORIZONTAL, 5, ['home-live-badge']);
    const statusIcon = ui.icon('battery-good-symbolic', 13);
    statusIcon.add_css_class('home-battery-icon');
    const statusText = ui.label('在线', ['caption']);
    statusBadge.append(statusIcon); statusBadge.append(statusText);
    heroTop.append(dateLabel); heroTop.append(statusBadge);
    const timeRow = ui.box(Gtk.Orientation.HORIZONTAL, 2, ['home-time-row']);
    timeRow.set_valign(Gtk.Align.END);
    const timeMain = ui.label('--:--', ['home-time-main']);
    const timeSec = ui.label(':--', ['home-time-sec']);
    timeSec.set_valign(Gtk.Align.END);
    timeRow.append(timeMain); timeRow.append(timeSec);
    hero.append(heroTop);
    hero.append(timeRow);
    page.append(hero);

    // 系统
    const sysSection = sectionRow('系统');
    const tempLabel = ui.label('--°C', ['home-temp-label']);
    sysSection.append(tempLabel);
    page.append(sysSection);

    const sysGroup = ui.box(Gtk.Orientation.VERTICAL, 0, ['mac-group']);
    let sysRowIndex = 0;
    const hwRow = (name) => {
        const box = ui.box(Gtk.Orientation.VERTICAL, 5, ['mac-row']);
        box.add_css_class('row-in-' + Math.min(sysRowIndex++, 8));
        if (sysGroup.get_first_child()) box.add_css_class('mac-sep');
        const head = ui.box(Gtk.Orientation.HORIZONTAL, 8);
        const label = ui.label(name, ['mac-label']);
        label.set_hexpand(true);
        const value = ui.label('', ['mac-value']);
        head.append(label); head.append(value);
        box.append(head);
        sysGroup.append(box);
        return {box, head, label, value};
    };

    const cpuRow = hwRow('CPU');
    const cpuSpark = sparkline(ui, cpuHistory, {height: 22, ceiling: 100});
    cpuRow.box.append(cpuSpark);

    const coreRow = hwRow('核心');
    const coreStrip = new Gtk.DrawingArea({content_height: 20, hexpand: true, can_target: false});
    coreStrip.add_css_class('home-core-bars');
    coreStrip.set_draw_func((_w, cr, width, h) => {
        if (width < 16) return;
        const base = coreStrip.get_color();
        const accent = parseAccent(ctx);
        const cell = width / 16;
        const barW = Math.max(2, Math.min(4, cell * 0.34));
        cr.setSourceRGBA(base.red, base.green, base.blue, 0.10);
        cr.rectangle(0, h - 1, width, 1);
        cr.fill();
        for (let i = 0; i < 16; i++) {
            const pct = Math.max(0, Math.min(1, corePercents[i] / 100));
            const barH = (8 + pct * (h - 10)) * coreReveal;
            const x = cell * i + (cell - barW) / 2;
            const hot = pct > 0.7;
            cr.setSourceRGBA(hot ? accent.red : base.red, hot ? accent.green : base.green,
                hot ? accent.blue : base.blue, hot ? 0.9 : 0.30 + pct * 0.45);
            cr.rectangle(x, h - 1 - barH, barW, barH);
            cr.fill();
        }
    });
    coreRow.box.append(coreStrip);

    const ramRow = hwRow('内存');
    const ramBar = fractionBar(ui, {height: 6, names: ['home-progress']});
    ramRow.box.append(ramBar);

    const diskRow = hwRow('NVMe');
    const diskSpark = sparkline(ui, diskReadHistory, {height: 16});
    diskRow.box.append(diskSpark);

    const netRow = hwRow('网络');
    const netSpark = sparkline(ui, netRxHistory, {height: 16});
    netRow.box.append(netSpark);
    page.append(sysGroup);

    // 进程
    page.append(sectionRow('进程'));
    const procGroup = ui.box(Gtk.Orientation.VERTICAL, 0, ['mac-group']);
    const taskRows = [];
    for (let i = 0; i < 3; i++) {
        const line = ui.box(Gtk.Orientation.HORIZONTAL, 8, ['mac-row', 'home-task-row']);
        line.add_css_class('row-in-' + Math.min(5 + i, 8));
        if (procGroup.get_first_child()) line.add_css_class('mac-sep');
        const name = ui.label('—', ['mac-label', 'home-task-name']);
        name.set_hexpand(true);
        name.set_ellipsize(Pango.EllipsizeMode.END);
        const meter = fractionBar(ui, {height: 5, names: ['home-task-meter']});
        meter.set_size_request(70, -1);
        meter.set_valign(Gtk.Align.CENTER);
        const cpu = ui.label('0.0%', ['mac-value', 'home-task-cpu']);
        cpu.set_xalign(1);
        cpu.set_size_request(46, -1);
        line.append(name); line.append(meter); line.append(cpu);
        if (i === 0) line.add_css_class('leader');
        procGroup.append(line);
        taskRows.push({name, meter, cpu});
    }
    page.append(procGroup);

    // 工作台
    const hubSection = sectionRow('工作台');
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
    hubSection.append(editConfigBtn);
    page.append(hubSection);

    const hubGroup = ui.box(Gtk.Orientation.VERTICAL, 0, ['mac-group']);
    const projectList = ui.box(Gtk.Orientation.VERTICAL, 0);
    hubGroup.append(projectList);
    page.append(hubGroup);

    function clearBox(box) {
        for (let child = box.get_first_child(); child;) {
            const next = child.get_next_sibling();
            box.remove(child);
            child = next;
        }
    }

    let hubRowIndex = 0;
    function addHubRow(build) {
        const row = ui.box(Gtk.Orientation.HORIZONTAL, 10, ['mac-row', 'hub-row']);
        row.add_css_class('row-in-' + Math.min(6 + hubRowIndex++, 10));
        if (projectList.get_first_child()) row.add_css_class('mac-sep');
        build(row);
        projectList.append(row);
        return row;
    }

    function hubGlyph(iconName, colorClass) {
        const glyph = ui.icon(iconName, 18);
        glyph.add_css_class(colorClass);
        return glyph;
    }

    function renderHub() {
        clearBox(projectList);
        const data = loadHubData();
        const editor = editorChoice(ctx.config?.());

        for (const project of data.workspaces || []) {
            addHubRow(row => {
                const iconName = symbolicName(project.icon) || 'folder-symbolic';
                const name = ui.label(project.name || project.path || '未命名', ['mac-label']);
                name.set_hexpand(true);
                name.set_ellipsize(Pango.EllipsizeMode.END);
                name.set_xalign(0);
                row.append(hubGlyph(iconName, 'hub-icon-tool'));
                row.append(name);

                const resolved = resolvePath(project.path);
                if (present('kitty')) {
                    const term = ui.button('终端', null, () => {
                        if (launch('kitty --directory', resolved)) {
                            if (ctx.toast) ctx.toast('已在终端打开 ' + (project.name || resolved));
                        } else if (ctx.toast) ctx.toast('无法启动终端', true);
                    }, ['launcher-action-pill', 'icon-button']);
                    term.set_tooltip_text('在终端打开 ' + resolved);
                    row.append(term);
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
                    row.append(open);
                }
            });
        }

        for (const bookmark of data.bookmarks || []) {
            addHubRow(row => {
                const iconName = symbolicName(bookmark.icon) || 'web-browser-symbolic';
                const link = ui.classes(new Gtk.Button(), ['hub-link']);
                const inner = ui.box(Gtk.Orientation.HORIZONTAL, 10);
                inner.set_hexpand(true);
                const name = ui.label(bookmark.name || '网址', ['mac-label']);
                name.set_hexpand(true);
                name.set_xalign(0);
                inner.append(hubGlyph(iconName, 'hub-icon-link'));
                inner.append(name);
                inner.append(ui.icon('chevron-right', 14));
                link.set_child(inner);
                link.connect('clicked', () => {
                    if (launch('xdg-open', bookmark.url)) {
                        if (ctx.toast) ctx.toast('正在打开 ' + (bookmark.name || bookmark.url));
                    } else if (ctx.toast) ctx.toast('无法打开 ' + (bookmark.name || bookmark.url), true);
                });
                link.set_tooltip_text(bookmark.url || '');
                row.append(link);
                link.set_hexpand(true);
            });
        }
    }

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
            const charge = battery.isCharging ? '充电 ' : '';
            statusText.set_label(charge + battery.cap + '% · ' + (uptime || '在线'));
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
            tempLabel.remove_css_class('warm'); tempLabel.remove_css_class('hot');
            if (temp > 75) tempLabel.add_css_class('hot');
            else if (temp > 55) tempLabel.add_css_class('warm');
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

    let introSource = 0;
    let coreReveal = 1;
    let introRun = 0;
    function playIntro() {
        if (!shown) return;
        introRun += 1;
        const run = introRun;
        // Restart the CSS entrance: drop the class, re-add it on the next idle so
        // the animation runs again every time the page is shown.
        page.remove_css_class('playing');
        GLib.idle_add(GLib.PRIORITY_DEFAULT_IDLE, () => {
            if (shown && run === introRun) page.add_css_class('playing');
            return GLib.SOURCE_REMOVE;
        });
        const start = GLib.get_monotonic_time();
        if (introSource) GLib.source_remove(introSource);
        cpuSpark.reveal = diskSpark.reveal = netSpark.reveal = 0;
        ramBar.reveal = 0;
        taskRows.forEach(rowItem => { rowItem.meter.reveal = 0; });
        coreReveal = 0;
        const paint = () => {
            cpuSpark.queue_draw(); diskSpark.queue_draw(); netSpark.queue_draw();
            ramBar.queue_draw();
            taskRows.forEach(rowItem => rowItem.meter.queue_draw());
            coreStrip.queue_draw();
        };
        introSource = GLib.timeout_add(GLib.PRIORITY_DEFAULT, 16, () => {
            if (!shown || run !== introRun) { introSource = 0; return GLib.SOURCE_REMOVE; }
            const t = Math.min(1, (GLib.get_monotonic_time() - start) / 720000);
            const e = 1 - (1 - t) ** 3;
            cpuSpark.reveal = diskSpark.reveal = netSpark.reveal = e;
            ramBar.reveal = e;
            taskRows.forEach(rowItem => { rowItem.meter.reveal = e; });
            coreReveal = e;
            paint();
            if (t >= 1) { introSource = 0; return GLib.SOURCE_REMOVE; }
            return GLib.SOURCE_CONTINUE;
        });
    }

    function startLoops() {
        if (!shown) return;
        playIntro();
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
    }

    function stopLoops() {
        if (introSource) { GLib.source_remove(introSource); introSource = 0; }
        page.remove_css_class('playing');
        if (clockTimer) { GLib.source_remove(clockTimer); clockTimer = 0; }
        if (hardwareTimer) { GLib.source_remove(hardwareTimer); hardwareTimer = 0; }
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
