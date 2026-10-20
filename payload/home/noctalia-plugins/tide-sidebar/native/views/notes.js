import Gtk from 'gi://Gtk?version=4.0';
import Gdk from 'gi://Gdk?version=4.0';
import GLib from 'gi://GLib';
import GObject from 'gi://GObject';
import Pango from 'gi://Pango';

const MAX_BODY_BYTES = 64 * 1024;
const encoder = new TextEncoder();
const byteLength = text => encoder.encode(text).length;
const records = list => Array.isArray(list) ? list.filter(item => item && typeof item.id === 'string') : [];

// Pure state machine, exported so race cases can be tested without a display or real data.
export class NoteDraftStore {
    constructor() { this.entries = new Map(); this.revision = -1; }
    get(id) { return this.entries.get(id); }
    accept(model) {
        const revision = Number(model?.revision);
        if (!Number.isSafeInteger(revision) || revision < 0 || revision < this.revision) return false;
        this.revision = revision;
        for (const note of records(model.notes)) {
            const body = typeof note.body === 'string' ? note.body : '';
            let draft = this.entries.get(note.id);
            if (!draft) {
                draft = {body, serverBody: body, dirty: false, generation: 0,
                    sentBody: null, sentGeneration: -1, sentAfterRevision: -1};
                this.entries.set(note.id, draft);
            } else {
                // Matching an OLD snapshot is not an acknowledgement: the user may
                // have typed B, sent B, then undone to A before old A arrives.
                const acknowledged = draft.sentBody !== null && draft.sentBody === draft.body
                    && draft.sentGeneration === draft.generation && body === draft.body
                    && revision > draft.sentAfterRevision;
                if (acknowledged) {
                    draft.dirty = false;
                    draft.sentBody = null;
                    draft.sentGeneration = -1;
                } else if (!draft.dirty) {
                    draft.body = body;
                }
                draft.serverBody = body;
            }
        }
        return true;
    }
    edit(id, body) {
        const draft = this.entries.get(id);
        if (!draft || draft.body === body) return false;
        draft.body = body;
        draft.generation++;
        draft.dirty = draft.sentBody !== null || body !== draft.serverBody;
        return true;
    }
    sent(id, body) {
        const draft = this.entries.get(id);
        if (!draft) return;
        draft.sentBody = body;
        draft.sentGeneration = draft.generation;
        draft.sentAfterRevision = this.revision;
        draft.dirty = true;
    }
    reconnect() {
        this.revision = -1;
        for (const draft of this.entries.values()) {
            draft.sentBody = null;
            draft.sentGeneration = -1;
            draft.sentAfterRevision = -1;
        }
    }
}

export function createNotes(ctx) {
    const U = ctx.ui;
    const drafts = new NoteDraftStore();
    const buffers = new Map();
    const rows = new Map(), trashRows = new Map();
    let snapshot = {}, model = null, notes = [], trash = [];
    let activeId = '', requestedId = '', renameId = '', deletedId = '';
    let awaitingDelete = false, undoDismissed = false;
    let ready = false, wasReady = false, shown = false, localError = '';
    let pendingAdd = null, pendingAddSource = 0;
    const setLabel = (widget, text) => { text = String(text ?? ''); if (widget.get_label() !== text) widget.set_label(text); };
    const mark = (widget, name, enabled) => enabled ? widget.add_css_class(name) : widget.remove_css_class(name);
    const current = () => notes.find(note => note.id === activeId);
    const textOf = buffer => { const [start, end] = buffer.get_bounds(); return buffer.get_text(start, end, true); };

    function send(action, values = {}) {
        try {
            if (ctx.send(action, values) === false) throw new Error('transport unavailable');
            return true;
        } catch (_) {
            localError = '后台暂不可用，草稿仍保留在窗口中';
            ctx.toast(localError, true);
            refreshStatus();
            return false;
        }
    }
    function sendDraft(id, force = false) {
        const draft = drafts.get(id);
        if (!draft?.dirty || !notes.some(note => note.id === id)) return true;
        if (byteLength(draft.body) > MAX_BODY_BYTES) {
            localError = '正文超过 64 KiB，草稿仍保留；缩短后才能保存';
            refreshStatus();
            return false;
        }
        if (!force && draft.sentBody === draft.body && draft.sentGeneration === draft.generation) return true;
        if (!send('note-edit', {id, body: draft.body})) return false;
        drafts.sent(id, draft.body);
        return true;
    }
    function flushAll() {
        let accepted = true;
        for (const [id, draft] of drafts.entries) if (draft.dirty) accepted = sendDraft(id, true) && accepted;
        send('flush');
        refreshStatus();
        return accepted;
    }
    function ensureBuffer(id) {
        const draft = drafts.get(id);
        if (!draft) return null;
        let record = buffers.get(id);
        if (!record) {
            const buffer = new Gtk.TextBuffer();
            buffer.set_text(draft.body, -1);
            buffer.set_enable_undo(true);
            record = {buffer, suppressed: false, actionDepth: 0};
            buffers.set(id, record);
            record.beginSignal = buffer.connect('begin-user-action', () => record.actionDepth++);
            record.endSignal = buffer.connect('end-user-action', () => {
                record.actionDepth = Math.max(0, record.actionDepth - 1);
                if (!record.suppressed && record.actionDepth === 0) { sendDraft(id); refreshStatus(); }
            });
            record.signal = buffer.connect('changed', () => {
                if (record.suppressed) return;
                const body = textOf(buffer);
                if (!drafts.edit(id, body)) return;
                localError = '';
                // Send immediately, or at the end of this synchronous GTK user action.
                // A replace-selection/paste must not send its intermediate empty body.
                // No timer delay: the service alone owns the 500ms disk debounce.
                if (record.actionDepth === 0) sendDraft(id);
                refreshStatus();
            });
        } else if (!draft.dirty && textOf(record.buffer) !== draft.body) {
            record.suppressed = true;
            record.buffer.begin_irreversible_action();
            record.buffer.set_text(draft.body, -1);
            record.buffer.end_irreversible_action();
            record.suppressed = false;
        }
        return record.buffer;
    }

    const page = U.box(Gtk.Orientation.VERTICAL, 9, ['notes-page']);
    page.set_vexpand(true);
    const header = U.box(Gtk.Orientation.HORIZONTAL, 7, ['page-header']);
    const heading = U.label('便签', ['title']); heading.set_hexpand(true);
    const listButton = new Gtk.MenuButton({hexpand: true, tooltip_text: '切换便签与查看回收站'});
    listButton.set_always_show_arrow(false);
    listButton.add_css_class('note-selector');
    const selectorRow = U.box(Gtk.Orientation.HORIZONTAL, 8);
    const selectorTitle = U.label('便签', ['note-selector-title']); selectorTitle.set_hexpand(true);
    selectorRow.append(selectorTitle);
    selectorRow.append(U.icon('chevron-down', 15));
    listButton.set_child(selectorRow);
    const addButton = U.iconButton('plus', addNote, '新建便签', ['note-add-button']);
    addButton.set_child(U.icon('plus', 24));
    header.append(heading); header.append(addButton); page.append(header); page.append(listButton);

    // Owned by MenuButton, not parented manually: popup lifetime is native GTK's.
    const listPopover = new Gtk.Popover({has_arrow: false, autohide: true, position: Gtk.PositionType.BOTTOM});
    listPopover.add_css_class('notes-picker');
    listButton.set_popover(listPopover);
    const listShell = U.box(Gtk.Orientation.VERTICAL, 6, ['notes-list-shell']);
    // A popover is sized by its content, and Gtk.ScrolledWindow does not propagate
    // natural width: the list used to collapse to a few characters wide and every
    // title was ellipsized to "新…". Keep a readable floor and then match the
    // selector's own width, which is what the dropdown lines up with.
    listShell.set_size_request(300, -1);
    function sizeList() {
        const width = listButton.get_width();
        if (width >= 240) listShell.set_size_request(width, -1);
    }
    listPopover.connect('show', sizeList);
    const listTabs = U.box(Gtk.Orientation.HORIZONTAL, 5);
    const normalTab = U.button('便签', null, () => selectList('notes'), ['list-tab', 'active']);
    const trashTab = U.button('回收站', null, () => selectList('trash'), ['list-tab']);
    const listCount = U.label('', ['caption']); listCount.set_hexpand(true); listCount.set_xalign(1);
    listTabs.append(normalTab); listTabs.append(trashTab); listTabs.append(listCount); listShell.append(listTabs);
    const listStack = new Gtk.Stack({transition_type: Gtk.StackTransitionType.CROSSFADE, transition_duration: 120});
    const normalList = U.box(Gtk.Orientation.VERTICAL, 3), recycleList = U.box(Gtk.Orientation.VERTICAL, 3);
    const emptyList = U.label('还没有便签', ['caption']), emptyTrash = U.label('回收站是空的', ['caption']);
    normalList.append(emptyList); recycleList.append(emptyTrash);
    function listScroller(child) {
        const scroller = new Gtk.ScrolledWindow({hexpand: true, propagate_natural_height: true, max_content_height: 174});
        scroller.set_policy(Gtk.PolicyType.NEVER, Gtk.PolicyType.AUTOMATIC);
        scroller.add_css_class('list-scroll'); scroller.set_child(child);
        return scroller;
    }
    listStack.add_named(listScroller(normalList), 'notes');
    listStack.add_named(listScroller(recycleList), 'trash');
    listStack.set_visible_child_name('notes');
    listShell.append(listStack); listPopover.set_child(listShell);

    const noticeRevealer = new Gtk.Revealer({transition_type: Gtk.RevealerTransitionType.SLIDE_DOWN, transition_duration: 140});
    const noticeBox = U.box(Gtk.Orientation.VERTICAL, 0, ['inline-notice']);
    const noticeText = U.label('', ['caption']); noticeText.set_wrap(true); noticeText.set_ellipsize(Pango.EllipsizeMode.NONE);
    noticeBox.append(noticeText); noticeRevealer.set_child(noticeBox); page.append(noticeRevealer);

    const card = U.card(['notes-card']); card.set_spacing(0); card.set_vexpand(true); page.append(card);
    const toolbar = U.box(Gtk.Orientation.HORIZONTAL, 0, ['notes-toolbar']);
    const title = U.label('', ['note-title']); title.set_hexpand(true); title.set_max_width_chars(23);
    toolbar.append(title); card.append(toolbar);
    // Keep the paper uncluttered: the reference's bottom pencil opens native actions.
    const editPopover = new Gtk.Popover({has_arrow: false, autohide: true});
    const actions = U.box(Gtk.Orientation.VERTICAL, 3, ['note-actions']);
    const renameButton = U.button('重命名', 'pencil', () => { editPopover.popdown(); beginRename(); }, ['note-menu-action']);
    renameButton.set_tooltip_text('重命名便签');
    const copyButton = U.button('复制正文', 'copy', () => { editPopover.popdown(); copyBody(); }, ['note-menu-action']);
    copyButton.set_tooltip_text('复制正文');
    const deleteButton = U.button('移到回收站', 'trash', () => { editPopover.popdown(); deleteNote(); }, ['note-menu-action', 'danger-button']);
    deleteButton.set_tooltip_text('移到回收站');
    actions.append(renameButton); actions.append(copyButton); actions.append(deleteButton); editPopover.set_child(actions);

    const renameRevealer = new Gtk.Revealer({transition_type: Gtk.RevealerTransitionType.SLIDE_DOWN, transition_duration: 150});
    const renameRow = U.box(Gtk.Orientation.HORIZONTAL, 5, ['rename-row']);
    const renameEntry = new Gtk.Entry({hexpand: true, placeholder_text: '便签名称'});
    renameEntry.connect('activate', commitRename);
    renameRow.append(renameEntry); renameRow.append(U.button('保存', null, commitRename, ['primary-button']));
    renameRow.append(U.iconButton('x', cancelRename, '取消重命名'));
    renameRevealer.set_child(renameRow); card.append(renameRevealer);

    const bodyStack = new Gtk.Stack({vexpand: true, hexpand: true, hhomogeneous: false, vhomogeneous: false});
    const paper = U.box(Gtk.Orientation.VERTICAL, 0, ['notes-paper-shell']); paper.set_vexpand(true);
    const editorScroll = new Gtk.ScrolledWindow({vexpand: true, hexpand: true, min_content_height: 140});
    editorScroll.set_policy(Gtk.PolicyType.NEVER, Gtk.PolicyType.AUTOMATIC); editorScroll.add_css_class('editor-scroll');
    const editor = new Gtk.TextView({vexpand: true, hexpand: true, wrap_mode: Gtk.WrapMode.WORD_CHAR,
        left_margin: 18, right_margin: 18, top_margin: 12, bottom_margin: 12, pixels_above_lines: 2, pixels_below_lines: 3});
    editor.add_css_class('notes-paper'); editor.set_editable(false);
    editorScroll.set_child(editor); paper.append(editorScroll); bodyStack.add_named(paper, 'editor');
    const empty = U.box(Gtk.Orientation.VERTICAL, 12, ['empty-state']); empty.set_valign(Gtk.Align.CENTER);
    const emptyTitle = U.label('还没有便签', ['empty-title']); emptyTitle.set_xalign(0.5);
    const emptyHint = U.label('新建一条，直接开始记录', ['caption']); emptyHint.set_xalign(0.5);
    const emptyAdd = U.button('新建便签', 'plus', addNote, ['primary-button']); emptyAdd.set_halign(Gtk.Align.CENTER);
    empty.append(emptyTitle); empty.append(emptyHint); empty.append(emptyAdd); bodyStack.add_named(empty, 'empty');
    bodyStack.set_visible_child_name('empty'); card.append(bodyStack);

    const footerLayer = new Gtk.Overlay({hexpand: true}); footerLayer.add_css_class('note-footer-layer');
    const footerWave = U.waveFooter('#F0DDA1', 54, 22); footerWave.add_css_class('note-footer-wave');
    footerLayer.set_child(footerWave);
    const footer = U.box(Gtk.Orientation.HORIZONTAL, 10, ['note-footer']);
    footer.set_halign(Gtk.Align.FILL); footer.set_valign(Gtk.Align.END);
    const count = U.label('0 字', ['caption']);
    const status = U.label('正在连接…', ['status-label']); status.set_hexpand(true); status.set_xalign(1);
    const actionsButton = new Gtk.MenuButton({tooltip_text: '便签操作'});
    actionsButton.add_css_class('note-actions-button'); actionsButton.set_icon_name('document-edit-symbolic');
    actionsButton.set_always_show_arrow(false); actionsButton.set_popover(editPopover);
    footer.append(count); footer.append(status); footer.append(actionsButton);
    footerLayer.add_overlay(footer); footerLayer.set_measure_overlay(footer, false); card.append(footerLayer);
    const undoRevealer = new Gtk.Revealer({transition_type: Gtk.RevealerTransitionType.SLIDE_DOWN, transition_duration: 160});
    const undoRow = U.box(Gtk.Orientation.HORIZONTAL, 7, ['undo-row']);
    const undoText = U.label('已移到回收站', ['caption']); undoText.set_hexpand(true);
    undoRow.append(undoText); undoRow.append(U.button('撤销', 'arrow-back-up', () => restoreNote(deletedId), ['soft-button']));
    undoRow.append(U.iconButton('x', () => { undoDismissed = true; undoRevealer.set_reveal_child(false); }, '关闭提示'));
    undoRevealer.set_child(undoRow); page.append(undoRevealer);

    const keys = new Gtk.EventControllerKey();
    keys.connect('key-pressed', (_controller, keyval, _keycode, modifiers) => {
        if ((modifiers & Gdk.ModifierType.CONTROL_MASK) && (keyval === Gdk.KEY_s || keyval === Gdk.KEY_S)) {
            flushAll(); return true;
        }
        return false;
    });
    editor.add_controller(keys);
    const renameKeys = new Gtk.EventControllerKey();
    renameKeys.connect('key-pressed', (_controller, keyval) => {
        if (keyval !== Gdk.KEY_Escape) return false;
        cancelRename(); return true;
    });
    renameEntry.add_controller(renameKeys);

    function selectList(name) {
        listStack.set_visible_child_name(name);
        mark(normalTab, 'active', name === 'notes'); mark(trashTab, 'active', name === 'trash');
        setLabel(listCount, name === 'notes' ? notes.length + ' 条' : trash.length + ' 条可恢复');
    }
    function cancelRename() { renameId = ''; renameRevealer.set_reveal_child(false); }
    function beginRename() {
        if (!ready || !current()) return;
        renameId = activeId; renameEntry.set_text(String(current().title || ''));
        renameRevealer.set_reveal_child(true); renameEntry.grab_focus(); renameEntry.select_region(0, -1);
    }
    function commitRename() {
        if (!renameId || !ready) return;
        const name = renameEntry.get_text().replace(/[\r\n\t]/g, ' ').trim();
        if (!name || byteLength(name) > 180 || name.includes('\0')) {
            ctx.toast('名称不能为空，且最多 60 个汉字', true); return;
        }
        if (!flushAll()) return;
        if (send('note-rename', {id: renameId, title: name})) cancelRename();
    }
    function selectNote(id) {
        listPopover.popdown();
        if (!ready || !notes.some(note => note.id === id) || id === activeId) return;
        if (!flushAll()) { ctx.toast('请先处理未保存的正文', true); return; }
        cancelRename(); requestedId = id; showNote(id);
        if (!send('note-select', {id})) requestedId = '';
        syncLists();
    }
    function addNote() {
        if (!ready || pendingAdd || notes.length >= 80 || !flushAll()) return;
        pendingAdd = {ids: new Set(notes.map(note => note.id))};
        if (!send('note-add')) { pendingAdd = null; return; }
        refreshStatus();
        if (pendingAddSource) GLib.source_remove(pendingAddSource);
        pendingAddSource = GLib.timeout_add(GLib.PRIORITY_DEFAULT, 4000, () => {
            pendingAddSource = 0;
            if (pendingAdd) { pendingAdd = null; ctx.toast('后台尚未确认新便签，请稍候再试', true); refreshStatus(); }
            return GLib.SOURCE_REMOVE;
        });
    }
    function deleteNote() {
        if (!ready || !current() || trash.length >= 80 || !flushAll()) return;
        cancelRename(); deletedId = activeId; awaitingDelete = true; undoDismissed = false;
        if (!send('note-delete', {id: activeId})) { deletedId = ''; awaitingDelete = false; }
    }
    function restoreNote(id) {
        if (!ready || !id || notes.length >= 80 || !flushAll()) return;
        if (send('note-restore', {id})) { listPopover.popdown(); requestedId = ''; undoDismissed = true; undoRevealer.set_reveal_child(false); selectList('notes'); }
    }
    function moveNote(id, to) {
        if (!ready || to < 1 || to > notes.length || !flushAll()) return false;
        return send('note-move', {id, to});
    }
    function copyBody() {
        const draft = drafts.get(activeId);
        if (!draft?.body) { ctx.toast('这条便签还是空的'); return; }
        try { if (ctx.copy(draft.body) !== false) ctx.toast('正文已复制'); }
        catch (_) { ctx.toast('复制未完成，请重试', true); }
    }
    function showNote(id) {
        const changedNote = activeId !== (id || '');
        activeId = id || '';
        const note = current(), buffer = note && ensureBuffer(id);
        if (buffer && editor.get_buffer() !== buffer) editor.set_buffer(buffer);
        bodyStack.set_visible_child_name(buffer ? 'editor' : 'empty');
        setLabel(title, note?.title || (ready ? '便签' : '正在加载…'));
        setLabel(selectorTitle, note?.title || (ready ? '选择便签' : '正在加载…'));
        selectorTitle.set_tooltip_text(note?.title || '');
        title.set_tooltip_text(note?.title || '');
        listButton.set_tooltip_text(note?.title || '切换便签与查看回收站');
        if (changedNote) footerWave.pulse();
        refreshStatus();
    }
    function refreshStatus() {
        const note = current(), draft = drafts.get(activeId);
        const problem = localError || snapshot.error || '';
        const info = problem || snapshot.warning || (!ready ? '正在连接便签服务…' : '');
        setLabel(noticeText, info); mark(noticeBox, 'error', !!problem); noticeRevealer.set_reveal_child(!!info);
        const label = problem ? '未保存' : pendingAdd ? '正在新建…' : !ready ? '尚未就绪'
            : draft?.dirty ? '等待后台确认…' : snapshot.saving ? '保存中…' : '已保存';
        setLabel(status, label); mark(status, 'status-error', !!problem);
        setLabel(count, (note ? editor.get_buffer().get_char_count() : 0) + ' 字');
        editor.set_editable(ready && !!note && !pendingAdd);
        editor.set_cursor_visible(ready && !!note && !pendingAdd);
        addButton.set_sensitive(ready && !pendingAdd && notes.length < 80);
        emptyAdd.set_sensitive(ready && !pendingAdd && notes.length < 80);
        renameButton.set_sensitive(ready && !!note && !pendingAdd);
        copyButton.set_sensitive(ready && !!note);
        actionsButton.set_sensitive(ready && !!note && !pendingAdd);
        deleteButton.set_sensitive(ready && !!note && trash.length < 80 && !pendingAdd);
    }
    function newRow(note, recycled) {
        const row = U.box(Gtk.Orientation.HORIZONTAL, 3, ['note-row']);
        const titleLabel = U.label(note.title || '', ['note-list-title']); titleLabel.set_hexpand(true); titleLabel.set_max_width_chars(22);
        const select = new Gtk.Button({hexpand: true}); select.add_css_class('note-select-button'); select.set_child(titleLabel);
        if (!recycled) {
            const grip = U.box(Gtk.Orientation.HORIZONTAL, 0, ['note-grip']);
            grip.append(new Gtk.Image({icon_name: 'list-drag-handle-symbolic', pixel_size: 13}));
            grip.set_tooltip_text('拖动调整顺序，也可使用上移和下移按钮');
            const source = new Gtk.DragSource({actions: Gdk.DragAction.MOVE});
            source.connect('prepare', () => {
                if (!ready) return null;
                const value = new GObject.Value(); value.init(GObject.TYPE_STRING); value.set_string(note.id);
                return Gdk.ContentProvider.new_for_value(value);
            });
            grip.add_controller(source); row.append(grip);
            select.connect('clicked', () => selectNote(note.id));
            row.append(select);
            const up = U.iconButton('arrow-up', () => moveNote(note.id, notes.findIndex(item => item.id === note.id)), '上移');
            const down = U.iconButton('arrow-down', () => moveNote(note.id, notes.findIndex(item => item.id === note.id) + 2), '下移');
            row.append(up); row.append(down);
            const target = Gtk.DropTarget.new(GObject.TYPE_STRING, Gdk.DragAction.MOVE);
            target.connect('enter', () => { mark(row, 'drop-target', ready); return ready ? Gdk.DragAction.MOVE : 0; });
            target.connect('leave', () => mark(row, 'drop-target', false));
            target.connect('drop', (_target, value, _x, y) => {
                mark(row, 'drop-target', false);
                const from = notes.findIndex(item => item.id === String(value));
                const destination = notes.findIndex(item => item.id === note.id);
                if (from < 0 || destination < 0 || from === destination) return false;
                let insertion = destination + (y >= row.get_height() / 2 ? 1 : 0);
                if (from < insertion) insertion--;
                return moveNote(String(value), Math.max(1, Math.min(notes.length, insertion + 1)));
            });
            row.add_controller(target);
            return {row, title: titleLabel, select, up, down};
        }
        select.connect('clicked', () => restoreNote(note.id));
        select.set_tooltip_text('恢复这条便签'); row.append(select);
        const restore = U.iconButton('arrow-back-up', () => restoreNote(note.id), '恢复'); row.append(restore);
        return {row, title: titleLabel, select, restore};
    }
    function reconcileRows(container, cache, items, recycled, emptyLabel) {
        const wanted = new Set(items.map(note => note.id));
        for (const [id, row] of cache) if (!wanted.has(id)) { container.remove(row.row); cache.delete(id); }
        emptyLabel.set_visible(items.length === 0);
        let previous = emptyLabel;
        items.forEach((note, index) => {
            let row = cache.get(note.id);
            if (!row) { row = newRow(note, recycled); cache.set(note.id, row); container.append(row.row); }
            setLabel(row.title, note.title || '未命名便签');
            row.title.set_tooltip_text(note.title || '');
            row.select.set_tooltip_text(note.title || '未命名便签');
            mark(row.row, 'active', !recycled && note.id === activeId);
            row.select.set_sensitive(ready && (!recycled || notes.length < 80));
            if (row.up) { row.up.set_sensitive(ready && index > 0); row.down.set_sensitive(ready && index < items.length - 1); }
            if (row.restore) row.restore.set_sensitive(ready && notes.length < 80);
            if (row.row.get_prev_sibling() !== previous) container.reorder_child_after(row.row, previous);
            previous = row.row;
        });
    }
    function syncLists() {
        reconcileRows(normalList, rows, notes, false, emptyList);
        reconcileRows(recycleList, trashRows, trash, true, emptyTrash);
        selectList(listStack.get_visible_child_name() || 'notes');
    }
    function update(state) {
        const next = state?.notes || {};
        const reduced = state?.preferences?.reducedMotion === true;
        listStack.set_transition_duration(reduced ? 0 : 120);
        const nextReady = next.ready === true && !!next.model;
        if (!nextReady) {
            if (wasReady) drafts.reconnect();
            ready = false; wasReady = false; snapshot = next;
            refreshStatus(); return;
        }
        if (!drafts.accept(next.model)) return;
        const reconnecting = !wasReady;
        ready = true; wasReady = true; snapshot = next; model = next.model;
        notes = records(model.notes); trash = records(model.trash);
        let focusNew = false;
        if (pendingAdd) {
            const added = notes.find(note => !pendingAdd.ids.has(note.id));
            if (added || snapshot.error) {
                pendingAdd = null;
                if (pendingAddSource) { GLib.source_remove(pendingAddSource); pendingAddSource = 0; }
                if (added) { requestedId = added.id; focusNew = true; listPopover.popdown(); }
            }
        }
        if (requestedId && !notes.some(note => note.id === requestedId)) requestedId = '';
        const selected = requestedId || (notes.some(note => note.id === model.activeId) ? model.activeId : notes[0]?.id) || '';
        if (requestedId === model.activeId) requestedId = '';
        if (selected !== activeId) cancelRename();
        showNote(selected);
        if (focusNew && shown) editor.grab_focus();
        syncLists();
        if (deletedId && trash.some(note => note.id === deletedId)) {
            awaitingDelete = false;
            if (!undoDismissed) undoRevealer.set_reveal_child(true);
        } else if (deletedId && !awaitingDelete && notes.some(note => note.id === deletedId)) {
            deletedId = ''; undoDismissed = false; undoRevealer.set_reveal_child(false);
        }
        if (reconnecting) for (const [id, draft] of drafts.entries) if (draft.dirty) sendDraft(id);
        const live = new Set([...notes, ...trash].map(note => note.id));
        for (const [id, record] of buffers) if (!live.has(id) && !drafts.get(id)?.dirty) {
            record.buffer.disconnect(record.signal);
            record.buffer.disconnect(record.beginSignal);
            record.buffer.disconnect(record.endSignal);
            buffers.delete(id); drafts.entries.delete(id);
        }
        refreshStatus();
    }
    return {
        widget: page,
        update,
        onShow() { shown = true; if (ready && current()) editor.grab_focus(); footerWave.pulse(); },
        onHide() { shown = false; flushAll(); cancelRename(); editPopover.popdown(); listPopover.popdown(); },
        handleEscape() {
            if (editPopover.get_mapped()) { editPopover.popdown(); return true; }
            if (listPopover.get_mapped()) { listPopover.popdown(); return true; }
            if (renameRevealer.get_reveal_child()) { cancelRename(); return true; }
            return false;
        },
    };
}
