import Gtk from 'gi://Gtk?version=4.0';
import Gdk from 'gi://Gdk?version=4.0';
import Gio from 'gi://Gio';
import GLib from 'gi://GLib';
import Layer from 'gi://Gtk4LayerShell?version=1.0';
import * as UI from './ui.js';
import {encodePackets} from './transport.mjs';
import {paletteFor} from './palette.js';
import {createHome} from './views/home.js';
import {createNotes} from './views/notes.js';
import {createTools} from './views/tools.js';
import {createHotspot, createWindows} from './views/system.js';

// The required loader override is local to this already-loaded process, not its helper children.
GLib.unsetenv('LD_PRELOAD');
const argv = ARGV.slice();
const option = name => { const i = argv.indexOf(name); return i >= 0 ? argv[i + 1] : null; };
const checkOnly = argv.includes('--check');
const bridgeDir = option('--bridge-dir');
const instance = option('--instance') || 'check';
const pluginDir = GLib.path_get_dirname(GLib.filename_from_uri(import.meta.url)[0]);
const helperPath = GLib.build_filenamev([pluginDir, '..', 'helpers', 'system.py']);
if (!checkOnly && (!bridgeDir || !instance)) throw new Error('Missing private frontend transport');

const channels = ['notes', 'timer', 'stopwatch', 'system', 'calc', 'preferences', 'feedback', 'control', 'config'];
// Every snapshot channel the service may publish: an unlisted name is never read.
const pageNames = ['home', 'notes', 'tools', 'hotspot', 'windows'];
const pageAliases = {calculator: 'tools', timer: 'tools'};
let state = {
    notes: {ready: false, model: null, error: ''},
    timer: {ready: false, timer: {version: 1, status: 'idle', durationMs: 1500000, remainingMs: 1500000}},
    system: {loading: true, hotspot: {available: false, on: null}, windows: []},
    stopwatch: {ready: false, stopwatch: {version: 1, status: 'idle', elapsedMs: 0, laps: []}, error: ''},
    calc: {expression: '', result: '0', error: '', history: [], requestId: ''},
    preferences: {tab: 'home', reducedMotion: false},
    config: {panelWidth: 450, timerPresets: [5, 15, 25, 60], timerDefaultMinutes: 25,
        confirmWindowClose: true, hotspotDefaultSsid: '', hotspotDefaultBand: 'bg', defaultTab: 'home'},
};
let sequence = 0, visible = false, currentPage = 'home', lastControl = -1;
let window, stack, toastRevealer, toastLabel, toastTimer = 0;
let views = {}, pageHosts = {}, navigation = {}, fileMonitor = null, pendingRead = 0, heartbeat = 0;
let drawerTimer = 0, drawerAnim = null;
const DRAWER_OPEN_MS = UI.DURATION.drawerOpen, DRAWER_CLOSE_MS = UI.DURATION.drawerClose, DRAWER_OPEN_MARGIN = -1;
let viewFactory = null;
let ensureView = () => null;
let shellBox = null, appliedWidth = 0;
let exiting = false, startupFailed = false;
const dirtyFiles = new Set();
const helperProcesses = new Set();
const applicationId = 'org.noctalia.TideSidebar.r' + instance.replace(/[^A-Za-z0-9_]/g, '_');
const app = new Gtk.Application({application_id: applicationId, flags: 0});

function send(action, values = {}) {
    if (checkOnly || exiting) return false;
    // stdout is the private pipe owned by Noctalia's runStream, never a log.
    const packetId = String(++sequence);
    const message = {protocol: 1, instance, action, packetId, requestId: packetId, controlSerial: lastControl, ...values};
    try { for (const line of encodePackets(message)) print(line); return true; }
    catch (_) { toast('请求内容过大，尚未保存', true); return false; }
}
const reducedMotion = () => state.preferences?.reducedMotion === true;
function toast(text, isError = false) {
    if (!toastLabel) return;
    toastLabel.set_label(String(text || ''));
    if (text) toastRevealer.set_visible(true);
    toastRevealer.set_reveal_child(!!text);
    toastRevealer.remove_css_class(isError ? 'success' : 'error');
    toastRevealer.add_css_class(isError ? 'error' : 'success');
    if (toastTimer) GLib.source_remove(toastTimer);
    const stay = isError ? 6000 : 3600;
    toastTimer = GLib.timeout_add(GLib.PRIORITY_DEFAULT, stay, () => { toastTimer = 0; toastRevealer.set_reveal_child(false); return GLib.SOURCE_REMOVE; });
}
function copy(text) {
    // Verified on this machine: GJS boxes the JS string into the GValue that
    // gdk_clipboard_set_value expects, and the text reads back unchanged.
    try {
        Gdk.Display.get_default().get_clipboard().set(String(text));
        return true;
    } catch (_) { return false; }
}
function clearClipboardIf(text) {
    if (!text) return;
    try {
        const clipboard = Gdk.Display.get_default()?.get_clipboard();
        if (!clipboard) return;
        clipboard.read_text_async(null, (source, result) => {
            try { if (source.read_text_finish(result) === text) source.set(''); } catch (_) {}
        });
    } catch (_) {}
}
function runHelper(args, callback, timeoutMs = 5000) {
    if (checkOnly) { callback({ok: false, message: '检查模式不执行系统操作'}); return; }
    if (!['prepare-request', 'discard-request', 'reveal'].includes(args[0])) {
        callback({ok: false, message: '不支持的界面辅助操作'}); return;
    }
    let proc;
    try {
        proc = Gio.Subprocess.new(['python3', helperPath, ...args.map(String)], Gio.SubprocessFlags.STDOUT_PIPE | Gio.SubprocessFlags.STDERR_SILENCE);
        helperProcesses.add(proc);
    } catch (_) { callback({ok: false, message: '无法启动辅助工具'}); return; }
    let timeout = GLib.timeout_add(GLib.PRIORITY_DEFAULT, timeoutMs, () => { timeout = 0; proc.force_exit(); return GLib.SOURCE_REMOVE; });
    proc.communicate_utf8_async(null, null, (process, result) => {
        if (timeout) GLib.source_remove(timeout);
        helperProcesses.delete(process);
        try {
            const [, output] = process.communicate_utf8_finish(result);
            if (output.length > 1048576) throw new Error('oversize');
            const value = JSON.parse(output);
            callback(value && typeof value === 'object' ? value : {ok: false, message: '辅助工具未返回有效结果'});
        } catch (_) { callback({ok: false, message: '辅助工具未完成操作'}); }
    });
}
function writePrivateRequest(path, value) {
    const runtime = GLib.getenv('XDG_RUNTIME_DIR') || GLib.get_user_cache_dir();
    const expected = GLib.build_filenamev([runtime, 'noctalia-tide-sidebar']);
    if (GLib.path_get_dirname(path) !== expected || !/^request-[0-9a-f]{32}\.json$/.test(GLib.path_get_basename(path)))
        return false;
    try {
        const file = Gio.File.new_for_path(path);
        const info = file.query_info('standard::type,standard::is-symlink,unix::mode', Gio.FileQueryInfoFlags.NOFOLLOW_SYMLINKS, null);
        if (info.get_file_type() !== Gio.FileType.REGULAR || info.get_is_symlink() || (info.get_attribute_uint32('unix::mode') & 0o777) !== 0o600) return false;
        file.replace_contents(new TextEncoder().encode(JSON.stringify(value)), null, false, Gio.FileCreateFlags.PRIVATE, null);
        return true;
    } catch (_) { return false; }
}
function applyConfig() {
    const wanted = Number(state.config?.panelWidth);
    const width = Number.isFinite(wanted) ? Math.min(640, Math.max(380, Math.round(wanted))) : 450;
    if (width === appliedWidth || !shellBox) return;
    appliedWidth = width;
    // The layer surface follows the widget's request, so the shell carries the width.
    shellBox.set_size_request(width, -1);
    window.set_default_size(width, -1);
    if (!visible && !drawerAnim) setDrawer(drawerClosedOffset());
}
function normalizePage(page) { return pageNames.includes(page) ? page : (pageAliases[page] || 'home'); }
function updatePage(force = false, changed = []) {
    const needed = {home: ['notes', 'timer', 'stopwatch', 'system'], notes: ['notes'], tools: ['timer', 'calc', 'stopwatch'], hotspot: ['system', 'feedback'], windows: ['system']};
    const view = views[currentPage];
    if (visible && view && (force || changed.some(name => needed[currentPage].includes(name)))) view.update(state);
}
function selectPage(name, save = true) {
    name = normalizePage(name);
    if (name === currentPage && stack?.get_visible_child_name() === name) { updatePage(true); return; }
    if (visible) views[currentPage]?.onHide?.();
    ensureView(name);
    currentPage = name;
    // Hidden page switches must not queue a 220ms slide for the next open.
    stack.set_transition_duration(visible ? UI.motionMs(reducedMotion(), 'page') : 0);
    stack.set_visible_child_name(name);
    for (const [page, button] of Object.entries(navigation)) {
        if (page === name) button.add_css_class('selected'); else button.remove_css_class('selected');
    }
    updatePage(true);
    if (visible) { views[name]?.onShow?.(); send('visibility', {open: true, tab: name}); reportGeometrySoon(); }
    if (save) send('preferences', {tab: name, reducedMotion: state.preferences?.reducedMotion === true});
}
let geometrySource = 0;

function reportGeometrySoon() {
    if (checkOnly || !visible || geometrySource) return;
    geometrySource = GLib.timeout_add(GLib.PRIORITY_DEFAULT, 560, () => {
        geometrySource = 0;
        if (!visible) return GLib.SOURCE_REMOVE;
        const value = {page: currentPage, windowWidth: window.get_width(), windowHeight: window.get_height(), stackHeight: stack.get_height()};
        function visit(widget) {
            if (!widget?.get_mapped()) return;
            if (widget instanceof Gtk.TextView) {
                let parent = widget.get_parent();
                while (parent && !(parent instanceof Gtk.ScrolledWindow)) parent = parent.get_parent();
                if (parent) {
                    value.editorViewportHeight = parent.get_height();
                    const [valid, rect] = parent.compute_bounds(window);
                    if (valid) { value.editorTop = rect.get_y(); value.editorBottom = rect.get_y() + rect.get_height(); }
                }
            }
            for (let child = widget.get_first_child(); child; child = child.get_next_sibling()) visit(child);
        }
        visit(views[currentPage].widget);
        send('frontend-geometry', value);
        return GLib.SOURCE_REMOVE;
    });
}

function drawerClosedOffset() { return -Math.max(0, appliedWidth - 1); }
function easeOutCubic(t) { return 1 - (1 - t) ** 3; }
function easeInOutCubic(t) { return t < 0.5 ? 4 * t * t * t : 1 - ((-2 * t + 2) ** 3) / 2; }
function setDrawer(value) {
    Layer.set_margin(window, Layer.Edge.LEFT, Math.round(value));
}
function cancelDrawer() {
    if (drawerTimer) { GLib.source_remove(drawerTimer); drawerTimer = 0; }
    drawerAnim = null;
}
// Move the layer surface itself. The compositor translates the already-rendered
// buffer, so glyphs and shadows are never re-rasterized mid-flight (no shimmer).
// The closed surface keeps one almost-transparent pixel on screen: a fully
// off-screen layer is not composited, and the first show would then paint at
// the open position. The 7ms timer matches this 144 Hz output (a 16ms timer
// visibly repeats margins); elapsed time is capped so a stall pauses the drawer
// instead of skipping it.
function animateDrawer(from, to, duration, easing, done) {
    cancelDrawer();
    setDrawer(from);
    if (!duration || from === to) { setDrawer(to); if (done) done(); return; }
    const anim = {from, to, elapsed: 0, last: 0, duration, easing, done};
    drawerAnim = anim;
    drawerTimer = GLib.timeout_add(GLib.PRIORITY_DEFAULT, 7, () => {
        if (drawerAnim !== anim) { drawerTimer = 0; return GLib.SOURCE_REMOVE; }
        const now = GLib.get_monotonic_time();
        const delta = anim.last ? Math.min(14000, now - anim.last) : 7000;
        anim.last = now;
        anim.elapsed = Math.min(anim.duration * 1000, anim.elapsed + delta);
        const t = Math.min(1, anim.elapsed / (anim.duration * 1000));
        setDrawer(anim.from + (anim.to - anim.from) * anim.easing(t));
        if (t >= 1) {
            drawerTimer = 0; drawerAnim = null;
            if (anim.done) anim.done();
            return GLib.SOURCE_REMOVE;
        }
        return GLib.SOURCE_CONTINUE;
    });
}
function setVisible(wanted, page = null) {
    if (page) selectPage(page, false);
    if (wanted === visible) return;
    visible = wanted;
    if (visible) {
        window.remove_css_class('sidebar-hidden');
        Layer.set_keyboard_mode(window, Layer.KeyboardMode.ON_DEMAND);
        window.set_can_target(true);
        if (!window.get_mapped()) window.present();
        updatePage(true);
        views[currentPage]?.onShow?.();
        const from = Math.min(Layer.get_margin(window, Layer.Edge.LEFT), DRAWER_OPEN_MARGIN);
        animateDrawer(from, DRAWER_OPEN_MARGIN, reducedMotion() ? 0 : DRAWER_OPEN_MS, easeInOutCubic);
        send('visibility', {open: true, tab: currentPage});
        reportGeometrySoon();
    } else {
        // The surface stays mapped off-screen; without this the hidden editor
        // keeps keyboard focus and its input is written to disk.
        window.add_css_class('sidebar-hidden');
        window.set_focus(null);
        Layer.set_keyboard_mode(window, Layer.KeyboardMode.NONE);
        views[currentPage]?.onHide?.();
        send('flush');
        send('visibility', {open: false, tab: currentPage});
        animateDrawer(Layer.get_margin(window, Layer.Edge.LEFT), drawerClosedOffset(), reducedMotion() ? 0 : DRAWER_CLOSE_MS, easeInOutCubic, () => {
            if (!visible) {
                window.set_can_target(false);
                try { imports.system.gc(); } catch (_) { try { globalThis.gc?.(); } catch (_) {} }
            }
        });
    }
}
function applyControl(control) {
    const serial = Number(control?.serial);
    if (!Number.isFinite(serial) || serial <= lastControl) return;
    lastControl = serial;
    if (control.quit) { shutdown(); return; }
    const reduced = control.reducedMotion === true;
    Gtk.Settings.get_default().gtk_enable_animations = !reduced;
    if (reduced) window.add_css_class('reduced-motion'); else window.remove_css_class('reduced-motion');
    stack.set_transition_duration(UI.motionMs(reduced, 'page'));
    toastRevealer.set_transition_duration(UI.motionMs(reduced, 'toast'));
    setVisible(control.visible === true, control.page || currentPage);
    // A visibility report can be dropped while a newer control serial is being
    // written; echo the settled state so the service's lastControl catches up.
    send('visibility', {open: visible, tab: currentPage});
}
function readChannel(name) {
    let packet;
    try {
        const [ok, bytes] = Gio.File.new_for_path(GLib.build_filenamev([bridgeDir, name + '.json'])).load_contents(null);
        if (!ok) return false;
        if (bytes.length > 16777216) { printerr('sidebar: ' + name + '.json exceeds 16 MiB; ignored'); return false; }
        packet = JSON.parse(new TextDecoder().decode(bytes));
    } catch (_) { return false; }
    if (packet.instance !== instance) {
        if (name === 'control' && !checkOnly) shutdown();
        return false;
    }
    try {
        if (name === 'control') applyControl(packet.data);
        else if (name === 'feedback') {
            const reply = packet.data;
            state.feedback = reply;
            if (reply?.message && visible) toast(reply.message, reply.ok !== true);
            // Focusing a window used to hide the sidebar. The user asked for the panel to
            // stay open so several windows can be picked in a row; hiding is manual now
            // (chevron, Super+Shift+W) or by clicking outside.
        } else {
            state[name] = packet.data;
        }
        return true;
    } catch (error) {
        printerr('sidebar: failed to apply ' + name + ': ' + error.message);
        return false;
    }
}
function flushReads() {
    pendingRead = 0;
    const names = [...dirtyFiles]; dirtyFiles.clear();
    // State before control: opening never renders old data from the preceding service instance.
    names.sort((a, b) => (a === 'control' ? 1 : 0) - (b === 'control' ? 1 : 0));
    const changed = [];
    for (const name of names) {
        if (name === 'control') continue;
        if (readChannel(name)) changed.push(name);
    }
    // Width first: the control packet below may present the window; applying the
    // configured width afterwards would map at 450 and then resize.
    applyConfig();
    if (names.includes('control')) readChannel('control');
    updatePage(false, changed);
    return GLib.SOURCE_REMOVE;
}
function watchBridge() {
    fileMonitor = Gio.File.new_for_path(bridgeDir).monitor_directory(Gio.FileMonitorFlags.WATCH_MOVES, null);
    fileMonitor.connect('changed', (_monitor, file, other) => {
        for (const item of [other, file]) {
            const basename = item?.get_basename();
            const name = basename?.replace(/\.json$/, '');
            if (channels.includes(name)) dirtyFiles.add(name);
        }
        if (dirtyFiles.size && !pendingRead) pendingRead = GLib.idle_add(GLib.PRIORITY_DEFAULT_IDLE, flushReads);
    });
    for (const name of channels) dirtyFiles.add(name);
    flushReads();
}
function shutdown() {
    if (exiting) return;
    for (const view of Object.values(views)) {
        try { view?.onHide?.(); } catch (error) { printerr('sidebar: view cleanup failed: ' + error.message); }
    }
    send('flush'); send('visibility', {open: false, tab: currentPage});
    exiting = true;
    fileMonitor?.cancel();
    paletteMonitor?.cancel();
    if (heartbeat) GLib.source_remove(heartbeat);
    if (pendingRead) GLib.source_remove(pendingRead);
    if (geometrySource) GLib.source_remove(geometrySource);
    cancelDrawer();
    for (const proc of helperProcesses) proc.force_exit();
    app.quit();
}
let paletteState = null;
let paletteProvider = null;
let paletteMonitor = null;
app.connect('startup', () => {
  try {
    const sheetPath = GLib.build_filenamev([pluginDir, 'style.css']);
    const readSheet = () => {
        const [ok, bytes] = GLib.file_get_contents(sheetPath);
        if (!ok) throw new Error('cannot read ' + sheetPath);
        return new TextDecoder().decode(bytes);
    };
    const applyStylesheet = () => {
        const palette = paletteFor();
        paletteState = palette;
        const css = palette.css + readSheet();
        const provider = new Gtk.CssProvider();
        const cssErrors = [];
        provider.connect('parsing-error', (_provider, _section, error) => cssErrors.push(error.message));
        provider.load_from_data(css, -1);
        if (cssErrors.length) throw new Error('Invalid sidebar stylesheet: ' + cssErrors.join('; '));
        const display = Gdk.Display.get_default();
        if (paletteProvider) Gtk.StyleContext.remove_provider_for_display(display, paletteProvider);
        Gtk.StyleContext.add_provider_for_display(display, provider, Gtk.STYLE_PROVIDER_PRIORITY_USER + 1);
        paletteProvider = provider;
        if (window) {
            if (palette.dark) { window.add_css_class('palette-dark'); window.remove_css_class('palette-light'); }
            else { window.add_css_class('palette-light'); window.remove_css_class('palette-dark'); }
        }
    };
    applyStylesheet();
    // Wallpaper change -> Noctalia rewrites noctalia.css -> re-derive tokens.
    // Debounced: the template processor may write twice in a row.
    let paletteReload = 0;
    const watchPalette = () => {
        try {
            const file = Gio.File.new_for_path(GLib.build_filenamev([GLib.get_user_config_dir(), 'gtk-4.0', 'noctalia.css']));
            paletteMonitor = file.monitor_file(Gio.FileMonitorFlags.NONE, null);
            paletteMonitor.connect('changed', () => {
                if (paletteReload) GLib.source_remove(paletteReload);
                paletteReload = GLib.timeout_add(GLib.PRIORITY_DEFAULT, 120, () => {
                    paletteReload = 0;
                    try { applyStylesheet(); } catch (error) { printerr('sidebar: palette reload failed: ' + error.message); }
                    return GLib.SOURCE_REMOVE;
                });
            });
        } catch (error) {
            printerr('sidebar: palette watch unavailable: ' + error.message);
        }
    };
    // All icons in this panel are *-symbolic and resolve from GTK's built-in
    // Adwaita theme anyway; naming it explicitly keeps the session's Papirus
    // icon caches (2 x ~3 MiB) out of this process. No visual change.
    Gtk.Settings.get_default().set_property('gtk-icon-theme-name', 'Adwaita');
    app.hold();
    window = new Gtk.ApplicationWindow({application: app, title: '侧边栏', decorated: false, default_width: 450});
    window.add_css_class('tide-window');
    window.add_css_class('sidebar-hidden');
    if (!Layer.is_supported()) throw new Error('Wayland layer-shell unavailable; check the local loader command');
    Layer.init_for_window(window);
    if (!Layer.is_layer_window(window)) throw new Error('Unable to create a Wayland layer surface');
    Layer.set_namespace(window, 'noctalia-tide-sidebar');
    Layer.set_layer(window, Layer.Layer.TOP);
    Layer.set_anchor(window, Layer.Edge.LEFT, true);
    Layer.set_anchor(window, Layer.Edge.TOP, true);
    Layer.set_anchor(window, Layer.Edge.BOTTOM, true);
    // The drawer is attached to the screen edge: no top/bottom/side breathing
    // room; the shell's left corners are square and its right corners rounded.
    Layer.set_margin(window, Layer.Edge.LEFT, 0);
    Layer.set_margin(window, Layer.Edge.TOP, 0);
    Layer.set_margin(window, Layer.Edge.BOTTOM, 0);
    Layer.set_keyboard_mode(window, Layer.KeyboardMode.ON_DEMAND);
    Layer.set_exclusive_zone(window, 0);
    watchPalette();
    window.connect('close-request', () => { setVisible(false); return true; });
    window.connect('destroy', () => shutdown());
    const ctx = {ui: UI, send, toast, copy, selectPage: page => selectPage(page), clearClipboard: clearClipboardIf, runHelper, writePrivateRequest, close: () => setVisible(false), getState: () => state, isVisible: () => visible, config: () => state.config, palette: () => paletteState?.tokens};
    // Pages are built on first use: the common home-only open skips the other
    // four widget trees (about 25 ms of construction on this machine).
    viewFactory = {home: () => createHome(ctx), notes: () => createNotes(ctx), tools: () => createTools(ctx), hotspot: () => createHotspot(ctx), windows: () => createWindows(ctx)};
    views = {};
    // Every page gets a permanent host in navigation order. The heavy view is
    // still built on first use; this keeps Stack's child order stable so
    // SLIDE_LEFT_RIGHT always follows the rail/Ctrl+1–4 direction.
    ensureView = name => {
        if (views[name]) return views[name];
        const view = viewFactory[name]();
        views[name] = view;
        const host = pageHosts[name];
        if (host) host.append(view.widget);
        // selectPage()/--check update right after creation; doing it here twice
        // built the initial notes page against an empty snapshot for nothing.
        return view;
    };
    const shell = UI.box(Gtk.Orientation.HORIZONTAL, 12, ['sidebar-shell']);
    shellBox = shell;
    shell.set_size_request(450, -1);
    applyConfig();
    const rail = UI.box(Gtk.Orientation.VERTICAL, 7, ['tab-rail']);
    rail.set_size_request(56, -1);
    const descriptions = {home: ['首页', 'home'], notes: ['便签', 'note'], tools: ['工具', 'calculator'], hotspot: ['热点', 'wifi'], windows: ['窗口', 'apps']};
    for (const page of pageNames) {
        const [text, glyph] = descriptions[page];
        const button = UI.classes(new Gtk.Button({tooltip_text: text}), ['nav-button', 'nav-' + page]);
        const child = UI.box(Gtk.Orientation.VERTICAL, 4);
        child.set_halign(Gtk.Align.CENTER); child.append(UI.icon(glyph, 24)); child.append(UI.label(text, ['nav-label']));
        button.set_child(child); button.connect('clicked', () => selectPage(page));
        navigation[page] = button; rail.append(button);
    }
    rail.append(new Gtk.Box({vexpand: true}));
    rail.append(UI.iconButton('chevron-left', () => setVisible(false), '收起 · Super+Shift+W', ['close-button']));
    const right = UI.box(Gtk.Orientation.VERTICAL, 6, ['content-column']);
    right.set_hexpand(true); right.set_vexpand(true);
    stack = new Gtk.Stack({hexpand: true, vexpand: true, transition_type: Gtk.StackTransitionType.SLIDE_LEFT_RIGHT, transition_duration: UI.DURATION.page});
    pageHosts = {};
    for (const page of pageNames) {
        const host = UI.box(Gtk.Orientation.VERTICAL, 0);
        host.set_hexpand(true); host.set_vexpand(true);
        pageHosts[page] = host;
        stack.add_named(host, page);
    }
    right.append(stack);
    toastRevealer = new Gtk.Revealer({transition_type: Gtk.RevealerTransitionType.SLIDE_UP, transition_duration: UI.DURATION.toast});
    toastRevealer.add_css_class('toast');
    toastRevealer.set_visible(false);
    toastRevealer.connect('notify::child-revealed', () => { if (!toastRevealer.get_reveal_child() && !toastRevealer.get_child_revealed()) toastRevealer.set_visible(false); });
    toastLabel = new Gtk.Label({wrap: true, xalign: 0}); toastRevealer.set_child(toastLabel); right.append(toastRevealer);
    shell.append(rail); shell.append(right);
    window.set_child(shell);
    const keyboard = new Gtk.EventControllerKey();
    keyboard.set_propagation_phase(Gtk.PropagationPhase.CAPTURE);
    keyboard.connect('key-pressed', (_controller, key, _code, mods) => {
        if (key === Gdk.KEY_Escape) { if (!views[currentPage]?.handleEscape?.()) setVisible(false); return true; }
        if (mods & Gdk.ModifierType.CONTROL_MASK) {
            const index = key - Gdk.KEY_1;
            if (index >= 0 && index < pageNames.length) { selectPage(pageNames[index]); return true; }
        }
        return false;
    });
    window.add_controller(keyboard);
    selectPage('notes', false);
    if (checkOnly) {
        for (const name of pageNames) { ensureView(name); views[name].update(state); }
        print('native-check: GTK widgets and CSS constructed successfully');
        GLib.idle_add(GLib.PRIORITY_DEFAULT_IDLE, () => { app.quit(); return GLib.SOURCE_REMOVE; });
    } else {
        setDrawer(drawerClosedOffset());
        window.connect('map', () => { if (!visible) setDrawer(drawerClosedOffset()); });
        window.set_can_target(false);
        window.present();
        watchBridge();
        send('frontend-ready');
        heartbeat = GLib.timeout_add_seconds(GLib.PRIORITY_DEFAULT, 4, () => {
            send('frontend-heartbeat', {open: visible, tab: currentPage});
            if (visible) send('visibility', {open: true, tab: currentPage});
            return GLib.SOURCE_CONTINUE;
        });
        GLib.unix_signal_add(GLib.PRIORITY_HIGH, 15, () => { shutdown(); return GLib.SOURCE_REMOVE; });
        GLib.unix_signal_add(GLib.PRIORITY_HIGH, 2, () => { shutdown(); return GLib.SOURCE_REMOVE; });
    }
  } catch (error) {
    startupFailed = true;
    printerr(checkOnly ? 'native-check: ' + error.message : 'sidebar: native initialization failed');
    app.quit();
  }
});
app.connect('activate', () => {});
app.run([]);
if (startupFailed) throw new Error('native sidebar initialization failed');
