import Gtk from 'gi://Gtk?version=4.0';
import Gdk from 'gi://Gdk?version=4.0';
import Gio from 'gi://Gio';
import GLib from 'gi://GLib';
import Layer from 'gi://Gtk4LayerShell?version=1.0';
import * as UI from './ui.js';
import {encodePackets} from './transport.mjs';
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
const pageNames = ['notes', 'tools', 'hotspot', 'windows'];
const pageAliases = {home: 'notes', calculator: 'tools', timer: 'tools'};
let state = {
    notes: {ready: false, model: null, error: ''},
    timer: {ready: false, timer: {version: 1, status: 'idle', durationMs: 1500000, remainingMs: 1500000}},
    system: {loading: true, hotspot: {available: false, on: null}, windows: []},
    stopwatch: {ready: false, stopwatch: {version: 1, status: 'idle', elapsedMs: 0, laps: []}, error: ''},
    calc: {expression: '', result: '0', error: '', history: [], requestId: ''},
    preferences: {tab: 'notes', reducedMotion: false},
    config: {panelWidth: 450, timerPresets: [5, 15, 25, 60], timerDefaultMinutes: 25,
        confirmWindowClose: true, hotspotDefaultSsid: '', hotspotDefaultBand: 'bg', defaultTab: 'notes'},
};
let sequence = 0, visible = false, currentPage = 'notes', lastControl = -1;
let window, rootRevealer, stack, toastRevealer, toastLabel, toastTimer = 0;
let views = {}, navigation = {}, fileMonitor = null, pendingRead = 0, closeSource = 0, heartbeat = 0;
let shellBox = null, appliedWidth = 0;
let exiting = false, startupFailed = false;
const dirtyFiles = new Set();
const helperProcesses = new Set();
const applicationId = 'org.noctalia.TideSidebar.r' + instance.replace(/[^A-Za-z0-9_]/g, '_');
const app = new Gtk.Application({application_id: applicationId, flags: 0});

function send(action, values = {}) {
    if (checkOnly || exiting) return;
    // stdout is the private pipe owned by Noctalia's runStream, never a log.
    const packetId = String(++sequence);
    const message = {protocol: 1, instance, action, packetId, requestId: packetId, controlSerial: lastControl, ...values};
    try { for (const line of encodePackets(message)) print(line); }
    catch (_) { toast('请求内容过大，尚未保存', true); }
}
function toast(text, isError = false) {
    if (!toastLabel) return;
    toastLabel.set_label(String(text || ''));
    if (text) toastRevealer.set_visible(true);
    toastRevealer.set_reveal_child(!!text);
    toastRevealer.remove_css_class(isError ? 'success' : 'error');
    toastRevealer.add_css_class(isError ? 'error' : 'success');
    if (toastTimer) GLib.source_remove(toastTimer);
    toastTimer = GLib.timeout_add(GLib.PRIORITY_DEFAULT, 5000, () => { toastTimer = 0; toastRevealer.set_reveal_child(false); return GLib.SOURCE_REMOVE; });
}
function copy(text) {
    // Verified on this machine: GJS boxes the JS string into the GValue that
    // gdk_clipboard_set_value expects, and the text reads back unchanged.
    try {
        Gdk.Display.get_default().get_clipboard().set(String(text));
        return true;
    } catch (_) { return false; }
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
}
function normalizePage(page) { return pageNames.includes(page) ? page : (pageAliases[page] || 'notes'); }
function updatePage(force = false, changed = []) {
    const needed = {notes: ['notes'], tools: ['timer', 'calc', 'stopwatch'], hotspot: ['system'], windows: ['system']};
    if (visible && (force || changed.some(name => needed[currentPage].includes(name)))) views[currentPage].update(state);
}
function selectPage(name, save = true) {
    name = normalizePage(name);
    if (name === currentPage && stack?.get_visible_child_name() === name) { updatePage(true); return; }
    if (visible) views[currentPage]?.onHide?.();
    currentPage = name;
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
    geometrySource = GLib.timeout_add(GLib.PRIORITY_DEFAULT, 450, () => {
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

function setVisible(wanted, page = null) {
    if (page) selectPage(page, false);
    if (wanted === visible) return;
    visible = wanted;
    if (closeSource) { GLib.source_remove(closeSource); closeSource = 0; }
    if (visible) {
        window.present();
        updatePage(true);
        views[currentPage]?.onShow?.();
        rootRevealer.set_reveal_child(true);
        send('visibility', {open: true, tab: currentPage});
        reportGeometrySoon();
    } else {
        views[currentPage]?.onHide?.();
        send('flush');
        send('visibility', {open: false, tab: currentPage});
        rootRevealer.set_reveal_child(false);
        closeSource = GLib.timeout_add(GLib.PRIORITY_DEFAULT, state.preferences?.reducedMotion ? 1 : 190, () => {
            closeSource = 0;
            if (!visible) window.hide();
            return GLib.SOURCE_REMOVE;
        });
    }
}
function applyControl(control) {
    if (!control || Number(control.serial) <= lastControl) return;
    lastControl = Number(control.serial);
    if (control.quit) { shutdown(); return; }
    const reduced = control.reducedMotion === true;
    Gtk.Settings.get_default().gtk_enable_animations = !reduced;
    stack.set_transition_duration(reduced ? 0 : 220);
    rootRevealer.set_transition_duration(reduced ? 0 : 180);
    setVisible(control.visible === true, control.page || currentPage);
}
function readChannel(name) {
    try {
        const [ok, bytes] = Gio.File.new_for_path(GLib.build_filenamev([bridgeDir, name + '.json'])).load_contents(null);
        if (!ok || bytes.length > 8388608) return false;
        const packet = JSON.parse(new TextDecoder().decode(bytes));
        if (packet.instance !== instance) {
            if (name === 'control' && !checkOnly) shutdown();
            return false;
        }
        if (name === 'control') applyControl(packet.data);
        else if (name === 'feedback') {
            const reply = packet.data;
            if (reply?.message && visible) toast(reply.message, reply.ok !== true);
            // Focusing a window used to hide the sidebar. The user asked for the panel to
            // stay open so several windows can be picked in a row; hiding is manual now
            // (chevron, Super+Shift+W) or by clicking outside.
        } else state[name] = packet.data;
        return true;
    } catch (_) { return false; }
}
function flushReads() {
    pendingRead = 0;
    const names = [...dirtyFiles]; dirtyFiles.clear();
    // State before control: opening never renders old data from the preceding service instance.
    names.sort((a, b) => (a === 'control' ? 1 : 0) - (b === 'control' ? 1 : 0));
    const changed = names.filter(readChannel);
    applyConfig();
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
    views[currentPage]?.onHide?.();
    send('flush'); send('visibility', {open: false, tab: currentPage});
    exiting = true;
    fileMonitor?.cancel();
    if (heartbeat) GLib.source_remove(heartbeat);
    if (pendingRead) GLib.source_remove(pendingRead);
    if (closeSource) GLib.source_remove(closeSource);
    if (geometrySource) GLib.source_remove(geometrySource);
    for (const proc of helperProcesses) proc.force_exit();
    app.quit();
}
app.connect('startup', () => {
  try {
    const provider = new Gtk.CssProvider();
    const cssErrors = [];
    provider.connect('parsing-error', (_provider, _section, error) => cssErrors.push(error.message));
    provider.load_from_path(GLib.build_filenamev([pluginDir, 'style.css']));
    if (cssErrors.length) throw new Error('Invalid sidebar stylesheet: ' + cssErrors.join('; '));
    Gtk.StyleContext.add_provider_for_display(Gdk.Display.get_default(), provider, Gtk.STYLE_PROVIDER_PRIORITY_USER + 1);
    app.hold();
    window = new Gtk.ApplicationWindow({application: app, title: '侧边栏', decorated: false, default_width: 450});
    window.add_css_class('tide-window');
    if (!Layer.is_supported()) throw new Error('Wayland layer-shell unavailable; check the local loader command');
    Layer.init_for_window(window);
    if (!Layer.is_layer_window(window)) throw new Error('Unable to create a Wayland layer surface');
    Layer.set_namespace(window, 'noctalia-tide-sidebar');
    Layer.set_layer(window, Layer.Layer.TOP);
    Layer.set_anchor(window, Layer.Edge.LEFT, true);
    Layer.set_anchor(window, Layer.Edge.TOP, true);
    Layer.set_anchor(window, Layer.Edge.BOTTOM, true);
    Layer.set_margin(window, Layer.Edge.LEFT, 8);
    Layer.set_margin(window, Layer.Edge.TOP, 8);
    Layer.set_margin(window, Layer.Edge.BOTTOM, 8);
    Layer.set_keyboard_mode(window, Layer.KeyboardMode.ON_DEMAND);
    Layer.set_exclusive_zone(window, 0);
    window.connect('close-request', () => { setVisible(false); return true; });
    const ctx = {ui: UI, send, toast, copy, runHelper, writePrivateRequest, close: () => setVisible(false), getState: () => state, isVisible: () => visible, config: () => state.config};
    views = {notes: createNotes(ctx), tools: createTools(ctx), hotspot: createHotspot(ctx), windows: createWindows(ctx)};
    const shell = UI.box(Gtk.Orientation.HORIZONTAL, 10, ['sidebar-shell']);
    shellBox = shell;
    shell.set_size_request(450, -1);
    applyConfig();
    const rail = UI.box(Gtk.Orientation.VERTICAL, 7, ['tab-rail']);
    rail.set_size_request(42, -1);
    const descriptions = {notes: ['便签', 'note'], tools: ['工具', 'calculator'], hotspot: ['热点', 'wifi'], windows: ['窗口', 'apps']};
    for (const page of pageNames) {
        const [text, glyph] = descriptions[page];
        const button = UI.classes(new Gtk.Button({tooltip_text: text}), ['nav-button', 'nav-' + page]);
        const child = UI.box(Gtk.Orientation.VERTICAL, 4);
        child.set_halign(Gtk.Align.CENTER); child.append(UI.icon(glyph, 21)); child.append(UI.label(text, ['nav-label']));
        button.set_child(child); button.connect('clicked', () => selectPage(page));
        navigation[page] = button; rail.append(button);
    }
    rail.append(new Gtk.Box({vexpand: true}));
    rail.append(UI.iconButton('chevron-left', () => setVisible(false), '收起 · Super+Shift+W', ['close-button']));
    const right = UI.box(Gtk.Orientation.VERTICAL, 6, ['content-column']);
    right.set_hexpand(true); right.set_vexpand(true);
    stack = new Gtk.Stack({hexpand: true, vexpand: true, transition_type: Gtk.StackTransitionType.SLIDE_LEFT_RIGHT, transition_duration: 220});
    for (const name of pageNames) stack.add_named(views[name].widget, name);
    right.append(stack);
    toastRevealer = new Gtk.Revealer({transition_type: Gtk.RevealerTransitionType.SLIDE_UP, transition_duration: 180});
    toastRevealer.add_css_class('toast');
    toastRevealer.set_visible(false);
    toastRevealer.connect('notify::child-revealed', () => { if (!toastRevealer.get_reveal_child() && !toastRevealer.get_child_revealed()) toastRevealer.set_visible(false); });
    toastLabel = new Gtk.Label({wrap: true, xalign: 0}); toastRevealer.set_child(toastLabel); right.append(toastRevealer);
    shell.append(rail); shell.append(right);
    rootRevealer = new Gtk.Revealer({transition_type: Gtk.RevealerTransitionType.CROSSFADE, transition_duration: 180, hexpand: true, vexpand: true});
    rootRevealer.set_child(shell); window.set_child(rootRevealer);
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
        for (const name of pageNames) views[name].update(state);
        print('native-check: GTK widgets and CSS constructed successfully');
        GLib.idle_add(GLib.PRIORITY_DEFAULT_IDLE, () => { app.quit(); return GLib.SOURCE_REMOVE; });
    } else {
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
