// Run: gjs -m tide-sidebar/tests/native_notes_spec.js
// Requires an available GTK display, but NEVER maps/presents a window.
// Imports the real view; transport, clipboard and notifications are memory-only mocks.
// No user storage, helper process, active timer or real clipboard is accessed.
// Native IME is retained by TextView; live preedit/candidate placement is a separate manual check.
import Gtk from 'gi://Gtk?version=4.0';
import Gdk from 'gi://Gdk?version=4.0';
import GLib from 'gi://GLib';
import Pango from 'gi://Pango';
import * as UI from '../native/ui.js';
import {NoteDraftStore, createNotes} from '../native/views/notes.js';

let passed = 0, failed = 0, assertions = 0;
function check(value, message) {
    assertions++;
    if (!value) throw new Error(message);
}
function equal(actual, expected, message) { check(actual === expected, message); }
function test(name, run) {
    try { run(); passed++; }
    catch (error) { failed++; printerr('FAIL ' + name + ': ' + error.message); }
}
function model(revision, body = 'A', activeId = 'note-1') {
    return {version: 1, revision, nextId: 3, activeId, notes: [
        {id: 'note-1', title: 'Alpha', body, createdAt: 0, updatedAt: 0},
        {id: 'note-2', title: 'Beta', body: 'two', createdAt: 0, updatedAt: 0},
    ], trash: []};
}
function find(widget, predicate) {
    if (!widget) return null;
    if (predicate(widget)) return widget;
    for (let child = widget.get_first_child(); child; child = child.get_next_sibling()) {
        const found = find(child, predicate);
        if (found) return found;
    }
    return null;
}
function text(buffer) {
    const [start, end] = buffer.get_bounds();
    return buffer.get_text(start, end, true);
}

// These races need no native widget and can never access a service or a file.
test('draft acknowledgements cannot overwrite a newer edit or undo', () => {
    const store = new NoteDraftStore();
    check(store.accept(model(1)), 'initial snapshot rejected');
    store.edit('note-1', 'B'); store.sent('note-1', 'B');
    store.edit('note-1', 'A'); store.accept(model(1, 'A'));
    check(store.get('note-1').dirty, 'old A incorrectly acknowledged an undo while B was in flight');
    store.accept(model(2, 'B'));
    equal(store.get('note-1').body, 'A', 'B replaced the newer local undo');
    store.sent('note-1', 'A'); store.accept(model(3, 'A'));
    check(!store.get('note-1').dirty, 'new A acknowledgement did not settle');
    check(!store.accept(model(2, 'B')), 'older revision accepted');
    store.edit('note-1', 'after-reconnect'); store.sent('note-1', 'after-reconnect');
    store.reconnect(); store.accept(model(1, 'older-disk'));
    equal(store.get('note-1').body, 'after-reconnect', 'reconnect discarded a local draft');
    store.sent('note-1', 'after-reconnect'); store.accept(model(2, 'after-reconnect'));
    check(!store.get('note-1').dirty, 'reconnect acknowledgement remained stuck');
});

Gtk.init();
const stylesheet = GLib.build_filenamev([
    GLib.path_get_dirname(GLib.filename_from_uri(import.meta.url)[0]), '..', 'native', 'style.css',
]);
const provider = new Gtk.CssProvider();
const cssErrors = [];
provider.connect('parsing-error', (_provider, _section, error) => cssErrors.push(error.message));
provider.load_from_path(stylesheet);
test('the complete application stylesheet parses', () => {
    check(cssErrors.length === 0, 'stylesheet rejected: ' + cssErrors.join('; '));
});
// Same process-local priority as main.js. APPLICATION alone loses to this desktop's
// user GTK palette; all the rules are still scoped beneath .tide-window.
Gtk.StyleContext.add_provider_for_display(Gdk.Display.get_default(), provider, Gtk.STYLE_PROVIDER_PRIORITY_USER + 1);

function fixture(run) {
    const sends = [], copies = [], notices = [];
    const view = createNotes({
        ui: UI,
        send(action, values = {}) { sends.push({action, values}); return true; },
        copy(value) { copies.push(value); return true; },
        toast(value, isError = false) { notices.push({value, isError}); },
    });
    const root = new Gtk.Window();
    root.add_css_class('tide-window'); root.set_child(view.widget);
    const h = {
        view, root, sends, copies, notices,
        update(nextModel) {
            view.update({notes: {ready: true, model: nextModel, saving: false, error: '', warning: ''},
                preferences: {reducedMotion: true}});
        },
        button(tooltip) { return find(view.widget, item => item instanceof Gtk.Button && item.get_tooltip_text() === tooltip); },
        edits() { return sends.filter(item => item.action === 'note-edit'); },
    };
    try { run(h); }
    finally { root.destroy(); }
}

test('real GTK editor preserves selection, undo and independent note buffers', () => fixture(h => {
    h.update(model(1));
    const editor = find(h.view.widget, item => item instanceof Gtk.TextView);
    check(!!editor, 'native TextView is missing');
    check(editor.get_vexpand(), 'editor does not fill the remaining vertical space');
    check(!h.root.get_mapped(), 'test mapped a window');
    const buffer = editor.get_buffer();
    equal(text(buffer), 'A', 'initial content is missing');
    buffer.set_text('draft中', -1);
    check(h.sends.at(-1).action === 'note-edit' && h.sends.at(-1).values.body === 'draft中',
        'changed did not immediately send the full draft');
    buffer.place_cursor(buffer.get_end_iter());
    buffer.begin_user_action(); buffer.insert_at_cursor('!', -1); buffer.end_user_action();
    equal(text(buffer), 'draft中!', 'native insertion failed');
    check(buffer.get_can_undo(), 'native undo is unavailable');
    buffer.undo(); equal(text(buffer), 'draft中', 'native undo changed the wrong body');
    buffer.select_range(buffer.get_iter_at_offset(1), buffer.get_iter_at_offset(3));
    h.update(model(1, 'A'));
    equal(text(buffer), 'draft中', 'old snapshot replaced live editor content');
    const selection = buffer.get_selection_bounds();
    check(selection[0] && selection[1].get_offset() === 1 && selection[2].get_offset() === 3,
        'snapshot update lost the native selection');
    h.view.onHide();
    equal(h.sends.at(-1).action, 'flush', 'hide did not flush');
    check(h.sends.at(-2).action === 'note-edit' && h.sends.at(-2).values.body === 'draft中',
        'hide did not send the final draft before flush');
    h.update(model(2, 'draft中'));
    const firstBuffer = editor.get_buffer();
    h.update(model(3, 'draft中', 'note-2'));
    check(editor.get_buffer() !== firstBuffer, 'notes share one mutable buffer');
    h.update(model(4, 'draft中'));
    check(editor.get_buffer() === firstBuffer, 'switching notes rebuilt a buffer');
    const color = editor.get_color();
    check(Math.abs(color.red - 51 / 255) < 0.01 && Math.abs(color.green - 45 / 255) < 0.01
        && Math.abs(color.blue - 31 / 255) < 0.01, 'the native editor lost the approved #332D1F ink');
    const footer = find(h.view.widget, item => item instanceof Gtk.Overlay && item.has_css_class('note-footer-layer'));
    check(footer && footer.get_child() instanceof Gtk.DrawingArea, 'the footer is not backed by the shared natural wave');
    equal(footer.get_child().get_content_height(), 54, 'footer wave height diverged from the approved layout');
    check(!footer.get_child().get_can_target(), 'decorative wave must not intercept editor or footer input');

    h.button('复制正文').emit('clicked');
    equal(h.copies.at(-1), 'draft中', 'copy did not use the local draft');
    h.button('下移').emit('clicked');
    check(h.sends.at(-1).action === 'note-move' && h.sends.at(-1).values.to === 2,
        'ordering did not dispatch a one-based destination');
    h.button('移到回收站').emit('clicked');
    equal(h.sends.at(-1).action, 'note-delete', 'delete was not dispatched');
    // This old snapshot used to swallow the later deletion acknowledgement.
    h.update(model(4, 'draft中'));
    const deleted = model(5, 'draft中', 'note-2');
    deleted.trash = [deleted.notes[0]]; deleted.notes = [deleted.notes[1]];
    h.update(deleted);
    const undoNotice = find(h.view.widget, item => item instanceof Gtk.Revealer
        && !!find(item.get_child(), child => child instanceof Gtk.Label && child.get_label() === '已移到回收站'));
    check(undoNotice && undoNotice.get_reveal_child(), 'old snapshot swallowed the delete acknowledgement');
    h.button('关闭提示').emit('clicked'); h.update(deleted);
    check(!undoNotice.get_reveal_child(), 'dismissed undo notice reappeared');
    h.button('恢复').emit('clicked');
    equal(h.sends.at(-1).action, 'note-restore', 'restore was not sent');
    check(!h.sends.some(item => item.action.startsWith('timer-') || item.action === 'hotspot'),
        'notes sent an unrelated system operation');
}));

test('native editing transactions and 64KiB limits never leak a temporary empty body', () => fixture(h => {
    h.update(model(1, 'original'));
    const editor = find(h.view.widget, item => item instanceof Gtk.TextView);
    const buffer = editor.get_buffer();
    function replace(body) {
        const before = h.edits().length;
        buffer.begin_user_action();
        const [start, end] = buffer.get_bounds(); buffer.delete(start, end);
        equal(h.edits().length, before, 'intermediate deletion escaped the native user action');
        buffer.insert_at_cursor(body, -1);
        equal(h.edits().length, before, 'partial insertion escaped the native user action');
        buffer.end_user_action();
    }
    replace('replacement');
    equal(h.edits().length, 1, 'one user action did not yield one final message');
    equal(h.sends.at(-1).values.body, 'replacement', 'wrong final replacement');
    buffer.undo();
    equal(text(buffer), 'original', 'native undo failed after grouping');
    equal(h.sends.at(-1).values.body, 'original', 'undo was not sent immediately');
    const maximum = '中'.repeat(21845) + 'a';
    equal(new TextEncoder().encode(maximum).length, 65536, 'fixture is not exactly 64KiB');
    const beforeMaximum = h.edits().length;
    replace(maximum);
    equal(h.edits().length, beforeMaximum + 1, 'a 64KiB body was rejected');
    equal(h.sends.at(-1).values.body, maximum, 'the maximum-sized body was altered');
    const beforeOversize = h.edits().length;
    replace('z'.repeat(65537));
    equal(h.edits().length, beforeOversize, 'oversized paste sent an empty or partial replacement');
    h.update(model(2, maximum));
    equal(text(buffer).length, 65537, 'old acknowledgement replaced the oversized local draft');
    h.view.onHide();
    equal(h.edits().length, beforeOversize, 'hide leaked an oversized or temporary body');
    equal(h.sends.at(-1).action, 'flush', 'hide did not flush the backend');
    replace('short');
    equal(h.sends.at(-1).values.body, 'short', 'shortening the body did not recover sending');
    h.update(model(3, 'short'));
    equal(text(buffer), 'short', 'valid acknowledgement changed the current text');
    check(!h.root.get_mapped(), 'test mapped a window');
    equal(editor.get_color().to_string(), 'rgb(51,45,31)', 'approved flat editor ink regressed');
}));

// Allocate real widgets before checking text: construction alone cannot detect clipping.
test('selector Chinese ink and logical bounds fit the allocated native row', () => fixture(h => {
    const data = model(1); data.notes[0].title = '新便签';
    h.update(data);
    h.view.widget.measure(Gtk.Orientation.HORIZONTAL, -1);
    h.view.widget.measure(Gtk.Orientation.VERTICAL, 365);
    h.view.widget.allocate(365, 1032, -1, null);
    const selector = find(h.view.widget, item => item.has_css_class('note-selector'));
    const label = find(selector, item => item instanceof Gtk.Label && item.has_css_class('note-selector-title'));
    check(selector instanceof Gtk.MenuButton, 'selector is not a native MenuButton');
    check(label.get_allocated_height() > 0, 'glyph check ran without a real allocation');
    equal(label.get_label(), '新便签', 'fixture text did not reach the selector');
    const [ink, logical] = label.get_layout().get_pixel_extents();
    const [offsetX, offsetY] = label.get_layout_offsets();
    check(offsetY + ink.y >= 0 && offsetY + ink.y + ink.height <= label.get_allocated_height(),
        'selector ink extends above or below its allocation');
    check(offsetY + logical.y >= 0 && offsetY + logical.y + logical.height <= label.get_allocated_height(),
        'selector logical line extends above or below its allocation');
    check(offsetX + ink.x >= 0 && offsetX + ink.x + ink.width <= label.get_allocated_width(),
        'short Chinese title is clipped horizontally');
    check(label.get_parent().get_allocated_height() >= label.get_allocated_height(), 'row is shorter than its label');
    equal(selector.get_allocated_height(), label.get_allocated_height() + 10, 'selector added padding twice or expanded into the paper');
    equal(label.get_tooltip_text(), '新便签', 'selector lacks the complete title tooltip');
    check(!h.root.get_mapped() && !h.root.get_realized(), 'text fixture affected a real window');
    equal(h.sends.length, 0, 'text geometry check sent a backend command');
}));

test('native list popup ownership and content changes do not resize the paper', () => fixture(h => {
    const longTitle = '这是一条检查完整标题提示的便签名称';
    const data = model(1); data.notes[0].title = longTitle;
    h.update(data);
    const selector = find(h.view.widget, item => item instanceof Gtk.MenuButton && item.has_css_class('note-selector'));
    const popup = selector.get_popover();
    check(popup instanceof Gtk.Popover, 'MenuButton does not own a native Popover');
    check(popup.get_parent() !== null && popup.get_root() === h.root, 'popup is orphaned or attached to another root');
    equal(selector.get_tooltip_text(), longTitle, 'long selector tooltip was shortened');
    const selectorLabel = find(selector, item => item instanceof Gtk.Label && item.has_css_class('note-selector-title'));
    equal(selectorLabel.get_tooltip_text(), longTitle, 'long visible title lost its complete tooltip');
    const editor = find(h.view.widget, item => item instanceof Gtk.TextView);
    const allocate = () => {
        const [, natural] = h.view.widget.measure(Gtk.Orientation.VERTICAL, 365);
        h.view.widget.allocate(365, 1032, -1, null);
        return {natural, paper: editor.get_allocated_height()};
    };
    const before = allocate();
    const more = model(2); more.notes[0].title = longTitle;
    for (let index = 3; index <= 30; index++) more.notes.push({id: 'note-' + index,
        title: 'Fixture ' + index, body: '', createdAt: 0, updatedAt: 0});
    more.nextId = 31;
    h.update(more);
    const after = allocate();
    equal(after.natural, before.natural, 'popup list length changed page natural height');
    equal(after.paper, before.paper, 'popup list length squeezed the editor');
    const trashTab = find(popup, item => item instanceof Gtk.Button
        && !!find(item, child => child instanceof Gtk.Label && child.get_label() === '回收站'));
    trashTab.emit('clicked');
    const trashView = allocate();
    equal(trashView.paper, before.paper, 'switching to recycle view resized the paper');
    const notesTab = find(popup, item => item instanceof Gtk.Button
        && !!find(item, child => child instanceof Gtk.Label && child.get_label() === '便签'));
    notesTab.emit('clicked');
    h.button('Beta').emit('clicked');
    check(h.sends.at(-1).action === 'note-select' && h.sends.at(-1).values.id === 'note-2',
        'native popup row did not use the original selection callback');
    equal(text(editor.get_buffer()), 'two', 'native popup selection displayed the wrong note');
    popup.popdown(); h.view.onHide();
    check(!popup.get_mapped(), 'popup remained mapped after hide');
    equal(h.sends.at(-1).action, 'flush', 'hide no longer flushes the existing backend');
    check(selector.get_popover() === popup, 'closing or selecting replaced the owned popup');
    check(!h.root.get_mapped() && !h.root.get_realized(), 'popup fixture presented a window');
    // fixture() destroys the owning Window. Fatal GTK warnings catch bad parent/finalize paths.
}));

test('scrollbar and progress native chains have consistent reset geometry', () => {
    const root = new Gtk.Window(); root.add_css_class('tide-window');
    try {
        const box = new Gtk.Box({orientation: Gtk.Orientation.VERTICAL}); root.set_child(box);
        const scroll = new Gtk.ScrolledWindow({hscrollbar_policy: Gtk.PolicyType.NEVER,
            vscrollbar_policy: Gtk.PolicyType.AUTOMATIC});
        scroll.set_child(new Gtk.Box({height_request: 1200, width_request: 180})); box.append(scroll);
        scroll.measure(Gtk.Orientation.HORIZONTAL, -1); scroll.measure(Gtk.Orientation.VERTICAL, 300);
        scroll.allocate(300, 400, -1, null);
        const scrollbar = scroll.get_vscrollbar();
        const range = find(scrollbar, item => item.get_css_name() === 'range');
        const trough = find(scrollbar, item => item.get_css_name() === 'trough');
        const slider = find(scrollbar, item => item.get_css_name() === 'slider');
        check(scroll.get_overlay_scrolling(), 'overlay scrolling was disabled');
        check(scrollbar.get_child_visible(), 'genuine overflow was forcibly hidden');
        equal(scrollbar.get_allocated_width(), 6, 'scrollbar container is not six logical pixels');
        equal(range.get_allocated_width(), 6, 'range and scrollbar disagree in width');
        equal(trough.get_allocated_width(), 6, 'trough and range disagree in width');
        equal(slider.get_width(), 4, 'thumb paint is not four logical pixels');
        equal(slider.get_allocated_width(), 6, 'thumb is squeezed into a smaller parent slot');
        equal(scrollbar.get_style_context().get_border().left, 0, 'legacy theme edge border survived');
        const margin = slider.get_style_context().get_margin();
        check(margin.left === 1 && margin.right === 1, 'thumb centering margin is incorrect');
        const progress = new Gtk.ProgressBar({fraction: 0.5, hexpand: true});
        progress.add_css_class('timer-progress'); box.append(progress);
        const [, natural] = progress.measure(Gtk.Orientation.VERTICAL, 300);
        progress.allocate(300, natural, -1, null);
        const fill = find(progress, item => item.get_css_name() === 'progress');
        equal(natural, 2, 'timer track is not two logical pixels');
        equal(fill.get_height(), 2, 'timer fill height differs from its track');
        const fillMargin = fill.get_style_context().get_margin();
        check(fillMargin.left === 0 && fillMargin.right === 0, 'negative legacy fill margins survived');
        check(!root.get_mapped() && !root.get_realized(), 'style geometry fixture affected a real window');
    } finally { root.destroy(); }
});

test('the note picker stays readable once it is a popup', () => fixture(h => {
    h.update(model(1, 'A'));
    const selector = find(h.view.widget, item => item instanceof Gtk.MenuButton && item.has_css_class('note-selector'));
    check(!!selector, 'the selector MenuButton is missing');
    const shell = selector.get_popover()?.get_child();
    check(!!shell && shell.has_css_class('notes-list-shell'), 'the picker shell is missing');
    // A popover is sized by its content and Gtk.ScrolledWindow does not propagate
    // natural width, so this used to collapse to a few characters wide and every
    // title was ellipsized to a single character.
    const [minimum] = shell.measure(Gtk.Orientation.HORIZONTAL, -1);
    check(minimum >= 280, 'the note picker collapsed to ' + minimum + 'px');
    const title = find(shell, item => item instanceof Gtk.Label && item.has_css_class('note-list-title'));
    check(!!title, 'note rows carry no title label');
    equal(title.get_ellipsize(), Pango.EllipsizeMode.END, 'long titles would overflow instead of ellipsizing');
}));

print('native_notes_spec: ' + passed + ' passed, ' + failed + ' failed, ' + assertions + ' assertions; no mapped windows, all transport/copy mocked');
if (failed) throw new Error('native_notes_spec failed');
