import Gtk from 'gi://Gtk?version=4.0';
import Gdk from 'gi://Gdk?version=4.0';
import Gio from 'gi://Gio';
import GLib from 'gi://GLib';
import Layer from 'gi://Gtk4LayerShell?version=1.0';
import System from 'system';
import * as UI from '../native/ui.js';
import {createNotes} from '../native/views/notes.js';
if (!ARGV.includes('--allow-test-window')) throw new Error('explicit --allow-test-window required');
const app = new Gtk.Application({application_id: 'org.noctalia.SidebarPopupTest', flags: Gio.ApplicationFlags.NON_UNIQUE});
let window, view, error = '', guard = 0;
const sent = [];
function find(widget, predicate) {
    if (predicate(widget)) return widget;
    for (let child = widget.get_first_child(); child; child = child.get_next_sibling()) { const hit = find(child, predicate); if (hit) return hit; }
    return null;
}
function finish(reason = '') {
    error = reason;
    if (guard) { GLib.source_remove(guard); guard = 0; }
    view?.onHide?.(); window?.destroy(); app.quit();
}
function later(ms, fn) { GLib.timeout_add(GLib.PRIORITY_DEFAULT, ms, () => { try { fn(); } catch (e) { finish(e.message); } return GLib.SOURCE_REMOVE; }); }
app.connect('activate', () => {
    try {
        const provider = new Gtk.CssProvider();
        const dir = GLib.path_get_dirname(GLib.filename_from_uri(import.meta.url)[0]);
        provider.load_from_path(GLib.build_filenamev([dir, '..', 'native', 'style.css']));
        Gtk.StyleContext.add_provider_for_display(Gdk.Display.get_default(), provider, Gtk.STYLE_PROVIDER_PRIORITY_USER + 1);
        window = new Gtk.ApplicationWindow({application: app, title: '侧栏弹层测试（模拟数据）', default_width: 450, decorated: false});
        window.add_css_class('tide-window');
        if (!Layer.is_supported()) throw new Error('layer shell unavailable');
        Layer.init_for_window(window); Layer.set_layer(window, Layer.Layer.TOP);
        Layer.set_namespace(window, 'tide-sidebar-popup-test');
        Layer.set_anchor(window, Layer.Edge.LEFT, true); Layer.set_anchor(window, Layer.Edge.TOP, true); Layer.set_anchor(window, Layer.Edge.BOTTOM, true);
        Layer.set_margin(window, Layer.Edge.LEFT, 8); Layer.set_margin(window, Layer.Edge.TOP, 8); Layer.set_margin(window, Layer.Edge.BOTTOM, 8);
        Layer.set_keyboard_mode(window, Layer.KeyboardMode.ON_DEMAND);
        const shell = UI.box(Gtk.Orientation.VERTICAL, 8, ['sidebar-shell']);
        shell.append(UI.label('临时界面检查 · 不保存测试内容', ['caption']));
        view = createNotes({ui: UI, send: (action, value) => sent.push({action, ...value}), toast: () => {}, copy: () => true});
        shell.append(view.widget); window.set_child(shell);
        view.update({notes: {ready: true, saving: false, error: '', warning: '', model: {version: 1, revision: 1, nextId: 3, activeId: 'note-1',
            notes: [{id: 'note-1', title: '新便签', body: '', createdAt: 0, updatedAt: 0}, {id: 'note-2', title: '切换测试', body: '', createdAt: 0, updatedAt: 0}], trash: []}}});
        window.present();
        guard = GLib.timeout_add(GLib.PRIORITY_DEFAULT, 5000, () => { guard = 0; finish('popup test timed out'); return GLib.SOURCE_REMOVE; });
        later(350, () => {
            view.onShow();
            const selector = find(view.widget, item => item instanceof Gtk.MenuButton && item.has_css_class('note-selector'));
            if (!selector) throw new Error('native selector not found');
            const editor = find(view.widget, item => item instanceof Gtk.TextView);
            const heightBefore = editor.get_height();
            selector.popup();
            later(250, () => {
                const popup = selector.get_popover();
                if (!popup.get_mapped() || popup.get_width() <= 0 || popup.get_height() <= 0) throw new Error('popover did not map as a native popup');
                if (editor.get_height() !== heightBefore) throw new Error('opening selector resized note editor');
                // The dropdown must be as wide as the selector it drops from.
                if (popup.get_width() < 280) throw new Error('note picker collapsed to ' + popup.get_width() + 'px');
                const title = find(popup.get_child(), item => item instanceof Gtk.Label && item.has_css_class('note-list-title'));
                if (!title || title.get_width() < 120) throw new Error('note titles squeezed inside the popup');
                popup.popdown();
                later(180, () => {
                    if (popup.get_visible()) throw new Error('popover did not close');
                    if (sent.some(item => item.action.startsWith('note-'))) throw new Error('opening/closing popup modified a note');
                    print('native-popup-spec: real Wayland popup mapped and closed; editor height unchanged; no real notes or data operations');
                    finish();
                });
            });
        });
    } catch (e) { finish(e.message); }
});
app.run([]);
if (error) { printerr('native-popup-spec: ' + error); System.exit(1); }
