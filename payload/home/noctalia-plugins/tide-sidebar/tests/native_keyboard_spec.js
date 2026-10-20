import Gtk from 'gi://Gtk?version=4.0';
import Gdk from 'gi://Gdk?version=4.0';
import Gio from 'gi://Gio';
import GLib from 'gi://GLib';
import System from 'system';
import * as UI from '../native/ui.js';
import {createTools} from '../native/views/tools.js';

if (!ARGV.includes('--allow-test-window')) throw new Error('explicit --allow-test-window required');
const appId = 'org.noctalia.SidebarTypingTest';
const app = new Gtk.Application({application_id: appId, flags: Gio.ApplicationFlags.NON_UNIQUE});
let view, win, failed = '', safety = 0;
const sent = [];
const timer = {version: 1, status: 'idle', durationMs: 1500000, remainingMs: 1500000};
function walk(widget, predicate, out = []) {
    if (predicate(widget)) out.push(widget);
    for (let child = widget.get_first_child(); child; child = child.get_next_sibling()) walk(child, predicate, out);
    return out;
}
function labelOf(widget) {
    return walk(widget, item => item instanceof Gtk.Label).map(item => item.get_label()).join('');
}
function finish(error = '') {
    if (error) failed = error;
    if (safety) { GLib.source_remove(safety); safety = 0; }
    view?.onHide?.();
    win?.destroy();
    app.quit();
}
function after(ms, callback) {
    GLib.timeout_add(GLib.PRIORITY_DEFAULT, ms, () => {
        try { callback(); } catch (error) { finish(error.message); }
        return GLib.SOURCE_REMOVE;
    });
}
app.connect('activate', () => {
    try {
        const provider = new Gtk.CssProvider();
        const css = GLib.build_filenamev([GLib.path_get_dirname(GLib.filename_from_uri(import.meta.url)[0]), '..', 'native', 'style.css']);
        provider.load_from_path(css);
        Gtk.StyleContext.add_provider_for_display(Gdk.Display.get_default(), provider, Gtk.STYLE_PROVIDER_PRIORITY_USER + 1);
        win = new Gtk.ApplicationWindow({application: app, title: '侧栏输入检查（测试数据）', default_width: 450, default_height: 950});
        win.add_css_class('tide-window');
        view = createTools({ui: UI, send: (action, values) => sent.push({action, ...values}), toast: () => {}, copy: () => true});
        win.set_child(view.widget);
        view.update({timer: {ready: true, timer, error: ''}, calc: {expression: '', result: '0', error: '', history: [], requestId: ''},
            stopwatch: {ready: true, stopwatch: {version: 1, status: 'idle', elapsedMs: 0, laps: []}, error: ''}});
        win.present();
        safety = GLib.timeout_add(GLib.PRIORITY_DEFAULT, 6000, () => { safety = 0; finish('test window timed out'); return GLib.SOURCE_REMOVE; });
        after(400, () => {
            view.onShow();
            const fields = walk(view.widget, item => item instanceof Gtk.Entry && item.has_css_class('duration-field'));
            if (fields.length !== 3) throw new Error('three real duration entries required');
            fields[1].grab_focus();
            after(120, () => {
                if (!win.is_active) throw new Error('temporary test window is not focused; no keys injected');
                const proc = Gio.Subprocess.new(['niri', 'msg', '--json', 'focused-window'], Gio.SubprocessFlags.STDOUT_PIPE | Gio.SubprocessFlags.STDERR_SILENCE);
                const [, stdout] = proc.communicate_utf8(null, null);
                const focused = JSON.parse(stdout);
                if (!String(focused?.app_id || '').startsWith(appId)) throw new Error('focused window is not test-owned; no keys injected');
                const selection = fields[1].get_selection_bounds();
                if (!selection[0] || selection[1] !== 0 || selection[2] !== 2) throw new Error('initial duration was not selected for replacement');
                const typer = Gio.Subprocess.new(['wtype', '45'], Gio.SubprocessFlags.STDOUT_SILENCE | Gio.SubprocessFlags.STDERR_PIPE);
                typer.wait_async(null, (process, result) => {
                    try {
                        process.wait_finish(result);
                        if (!process.get_successful()) throw new Error('native keyboard helper failed');
                        after(120, () => {
                            if (fields[1].get_text() !== '45') throw new Error('real keyboard input did not replace 25 with 45');
                            const start = walk(view.widget, item => item instanceof Gtk.Button && item.get_visible() && labelOf(item) === '开始')[0];
                            if (!start) throw new Error('countdown start action missing');
                            start.emit('clicked');
                            const command = sent.find(item => item.action === 'timer-start');
                            if (!command || command.durationMs !== 2700000) throw new Error('typed 45 minutes did not produce the correct start request');
                            print('native-keyboard-spec: mapped real Gtk.Entry received wtype 45; mock start request = 2700000ms; no production timer changed');
                            finish();
                        });
                    } catch (error) { finish(error.message); }
                });
            });
        });
    } catch (error) { finish(error.message); }
});
app.run([]);
if (failed) { printerr('native-keyboard-spec: ' + failed); System.exit(1); }
