import Gtk from 'gi://Gtk?version=4.0';
import GLib from 'gi://GLib';
import Pango from 'gi://Pango';

// Widgets are constructed once. Updates touch labels, sensitivity and existing
// window rows only; secrets never enter ctx.send(), shared snapshots or logs.
const clean = (value, limit = 500) => typeof value === 'string'
    ? value.replace(/[\u0000-\u001f\u007f-\u009f]/g, ' ').slice(0, limit) : '';
const validId = value => typeof value === 'string' && /^[0-9]{1,20}$/.test(value)
    && (value.length < 20 || value <= '18446744073709551615');
const show = (widget, value) => { if (widget.get_visible() !== !!value) widget.set_visible(!!value); };
const sensitive = (widget, value) => { if (widget.get_sensitive() !== !!value) widget.set_sensitive(!!value); };
function css(widget, name, enabled) {
    if (widget.has_css_class(name) === !!enabled) return;
    if (enabled) widget.add_css_class(name); else widget.remove_css_class(name);
}
function paragraph(ui, text, names = ['muted']) {
    const label = ui.label(text, names);
    label.set_wrap(true);
    label.set_wrap_mode(Pango.WrapMode.WORD_CHAR);
    label.set_ellipsize(Pango.EllipsizeMode.NONE);
    return label;
}
function namedButton(ui, text, glyph, handler, names = []) {
    const button = ui.button('', glyph, handler, names);
    const label = ui.label(text);
    button.get_child().append(label);
    return {button, label};
}
function pageHeader(ui, title, onRefresh) {
    const row = ui.box('horizontal', 8, ['page-header', 'scroll-gutter']);
    const label = ui.label(title, ['page-title']);
    label.set_hexpand(true);
    const refresh = ui.iconButton('refresh', onRefresh, '刷新');
    row.append(label); row.append(refresh);
    return {row, refresh};
}
function scrolled(child) {
    const scroll = new Gtk.ScrolledWindow({hexpand: true, vexpand: true,
        hscrollbar_policy: Gtk.PolicyType.NEVER, propagate_natural_width: false, vscrollbar_policy: Gtk.PolicyType.AUTOMATIC});
    scroll.set_child(child);
    return scroll;
}

export function createHotspot(ctx) {
    const ui = ctx.ui;
    let shown = false, generation = 0, revealGeneration = 0, secretCopied = '', lastFeedback = 0;
    let current = {loading: true, hotspot: {available: false, on: null}};
    let initialized = false, editing = false, settingFields = false, desiredBand = 'bg';
    let intent = null, preparing = false, ownedPath = null, operation = null;
    let secretVisible = false, revealing = false, secretTimer = 0, operationTimer = 0;

    const widget = ui.box('vertical', 10);
    widget.set_vexpand(true); widget.set_hexpand(true);
    const header = pageHeader(ui, '热点', () => { if (shown) ctx.send('refresh'); });
    widget.append(header.row);
    const body = ui.box('vertical', 12, ['scroll-gutter']);
    widget.append(scrolled(body));

    const statusCard = ui.card(['hotspot-card', 'rise', 'rise-0']);
    const summary = ui.box('horizontal', 10, ['status-summary']);
    summary.append(ui.icon('wifi', 22));
    const summaryText = ui.box('vertical', 4);
    summaryText.set_hexpand(true);
    const status = ui.label('正在获取状态', ['section-title', 'status']);
    const networkName = ui.label('—');
    summaryText.append(status); summaryText.append(networkName); summary.append(summaryText);
    statusCard.append(summary);
    function detail(name) {
        const row = ui.box('horizontal', 12, ['status-row']);
        if (statusCard.get_last_child()) row.add_css_class('mac-sep');
        row.add_css_class('rise');
        row.add_css_class('rise-2');
        const caption = ui.label(name, ['muted']); caption.set_hexpand(true);
        const value = ui.label('—'); value.set_xalign(1);
        row.append(caption); row.append(value); statusCard.append(row);
        return {row, value};
    }
    const actualBand = detail('实际频段');
    const iface = detail('无线网卡');
    const gateway = detail('热点网关');
    const clients = detail('已连接设备');
    show(clients.row, false);
    const power = namedButton(ui, '开启热点', 'power', () => openConfirmation(current.hotspot?.on === true ? 'off' : 'on'), ['primary']);
    power.button.set_tooltip_text('开启或关闭热点');
    statusCard.append(power.button);
    const statusError = paragraph(ui, '', ['warning']); show(statusError, false);
    statusCard.append(statusError);
    body.append(statusCard);

    const form = ui.card(['hotspot-card', 'rise', 'rise-1']);
    form.append(ui.label('热点设置', ['section-title']));
    form.append(ui.label('热点名称', ['field-label']));
    const ssid = ui.classes(new Gtk.Entry({hexpand: true, placeholder_text: '热点名称'}), ['field-muted']);
    ssid.set_tooltip_text('热点名称，最多 32 个 UTF-8 字节');
    form.append(ssid);
    form.append(ui.label('新密码', ['field-label']));
    const password = ui.classes(new Gtk.PasswordEntry({hexpand: true, show_peek_icon: true,
        placeholder_text: '留空沿用已保存密码'}), ['field-muted']);
    password.set_tooltip_text('新密码只留在本页，离开后清除');
    form.append(password);
    form.append(ui.label('期望频段', ['field-label']));
    const bands = ui.box('horizontal', 8, ['segmented']);
    const band24 = ui.classes(new Gtk.ToggleButton({label: '2.4 GHz', hexpand: true}), ['glass-button']);
    const band5 = ui.classes(new Gtk.ToggleButton({label: '5 GHz', hexpand: true}), ['glass-button']);
    band5.set_group(band24);
    band24.set_active(true);
    band24.set_tooltip_text('2.4 GHz · 兼容性更好');
    band5.set_tooltip_text('5 GHz · 启动失败时脚本可能回落到 2.4 GHz');
    bands.append(band24); bands.append(band5); form.append(bands);
    const pending = paragraph(ui, '修改后需应用到正在运行的热点。', ['muted']);
    form.append(pending);
    const formActions = ui.box('horizontal', 8);
    const apply = ui.button('应用设置', 'check', () => openConfirmation('apply'), ['primary']);
    apply.set_hexpand(true);
    // Labelled, not icon-only: with the hotspot off the apply button is hidden
    // and a lone glyph at the bottom of the card read as a random refresh icon.
    const reset = ui.button('恢复已保存', 'rotate-clockwise', resetFields, ['soft-button']);
    reset.set_tooltip_text('使用当前设置');
    formActions.append(apply); formActions.append(reset); form.append(formActions);
    body.append(form);

    const confirm = new Gtk.Revealer({transition_type: Gtk.RevealerTransitionType.SLIDE_DOWN, transition_duration: ui.DURATION.reveal});
    const confirmCard = ui.card(['hotspot-card']);
    const confirmTitle = ui.label('', ['section-title']);
    const confirmDescription = paragraph(ui, '', ['warning']);
    confirmCard.append(confirmTitle); confirmCard.append(confirmDescription);
    const confirmButtons = ui.box('horizontal', 8);
    const cancel = ui.button('取消', null, cancelConfirmation);
    cancel.set_hexpand(true);
    const accept = namedButton(ui, '继续', 'check', submitConfirmation, ['primary']);
    accept.button.set_hexpand(true); accept.button.set_tooltip_text('确认热点操作');
    confirmButtons.append(cancel); confirmButtons.append(accept.button);
    confirmCard.append(confirmButtons); confirm.set_child(confirmCard); body.append(confirm);

    const saved = ui.card(['hotspot-card', 'rise', 'rise-2']);
    saved.append(ui.label('已保存密码', ['section-title']));
    const savedButtons = ui.box('horizontal', 8);
    const revealButton = namedButton(ui, '查看密码', 'eye', toggleSecret);
    revealButton.button.set_hexpand(true); revealButton.button.set_tooltip_text('查看或隐藏已保存密码');
    const copy = ui.iconButton('copy', () => {
        if (!shown || !secretVisible) return;
        try {
            const text = savedPassword.get_text();
            if (ctx.copy(text) !== false) { secretCopied = text; ctx.toast('密码已复制到剪贴板'); }
        }
        catch (_) { ctx.toast('未能复制密码', true); }
    }, '复制已显示的密码');
    savedButtons.append(revealButton.button); savedButtons.append(copy); saved.append(savedButtons);
    const secretBox = new Gtk.Revealer({transition_type: Gtk.RevealerTransitionType.SLIDE_DOWN, transition_duration: ui.DURATION.reveal});
    const savedPassword = ui.classes(new Gtk.Entry({editable: false, hexpand: true}), ['field-muted']);
    savedPassword.set_tooltip_text('临时显示的已保存密码');
    secretBox.set_child(savedPassword); saved.append(secretBox);
    body.append(saved);
    const operationWarning = paragraph(ui, '', ['warning']); show(operationWarning, false);
    body.append(operationWarning);

    const hot = () => current.hotspot || {};
    const configDefaults = () => ctx.config?.() || {};
    // A name/band the user configured but the backend never recorded is still the
    // baseline: prefilling it must not look like an unsaved edit.
    function baselineSsid() {
        const backend = typeof hot().ssid === 'string' ? hot().ssid : '';
        if (hot().desiredSsidKnown === true) return backend;
        const wanted = configDefaults().hotspotDefaultSsid;
        return typeof wanted === 'string' && wanted ? wanted : backend;
    }
    function baselineBand() {
        const backend = hot().desiredBand === 'a' ? 'a' : 'bg';
        if (hot().desiredBandKnown === true) return backend;
        const wanted = configDefaults().hotspotDefaultBand;
        return wanted === 'a' || wanted === 'bg' ? wanted : backend;
    }
    const busy = () => hot().busy === true || preparing || operation !== null;
    const backendBusy = () => hot().busy === true;
    function hasChanges() {
        return ssid.get_text() !== baselineSsid()
            || desiredBand !== baselineBand() || password.get_text() !== '';
    }
    function cancelTimer(which) {
        const id = which === 'secret' ? secretTimer : operationTimer;
        if (id) GLib.source_remove(id);
        if (which === 'secret') secretTimer = 0; else operationTimer = 0;
    }
    function discard(path) {
        if (typeof path !== 'string' || !path) return;
        // Helper validates ownership, mode, exact directory and exact filename.
        try { ctx.runHelper(['discard-request', path], () => {}); } catch (_) {}
    }
    function clearSecret() {
        revealGeneration++;
        revealing = false; secretVisible = false;
        cancelTimer('secret');
        if (secretCopied) { ctx.clearClipboard?.(secretCopied); secretCopied = ''; }
        savedPassword.set_text(''); secretBox.set_reveal_child(false);
        updateControls();
    }
    function resetFields() {
        if (busy()) return;
        settingFields = true;
        const name = baselineSsid();
        if (ssid.get_text() !== name) ssid.set_text(name);
        if (password.get_text()) password.set_text('');
        desiredBand = baselineBand();
        if (band24.get_active() !== (desiredBand === 'bg')) band24.set_active(desiredBand === 'bg');
        if (band5.get_active() !== (desiredBand === 'a')) band5.set_active(desiredBand === 'a');
        settingFields = false; initialized = true; editing = false;
        updateControls();
    }
    function fieldChanged() {
        if (settingFields) return;
        editing = true;
        updateControls();
    }
    ssid.connect('changed', fieldChanged);
    password.connect('changed', fieldChanged);
    for (const [button, value] of [[band24, 'bg'], [band5, 'a']]) {
        button.connect('toggled', () => {
            if (settingFields || !button.get_active()) return;
            desiredBand = value; editing = true; updateControls();
        });
    }
    function validateFields() {
        const name = ssid.get_text(), secret = password.get_text();
        if (!name || new TextEncoder().encode(name).length > 32 || /[\u0000-\u001f\u007f]/.test(name)) {
            ctx.toast('热点名称须为 1–32 个 UTF-8 字节，不能含换行', true); return false;
        }
        if (secret && !/^[\x20-\x7e]{8,63}$/.test(secret) && !/^[0-9a-fA-F]{64}$/.test(secret)) {
            ctx.toast('密码须为 8–63 个可打印 ASCII 字符，或 64 位十六进制密钥', true); return false;
        }
        return true;
    }
    function stateAllows(kind) {
        if (hot().available !== true || backendBusy()) return false;
        return kind === 'on' ? hot().on === false : hot().on === true;
    }
    function openConfirmation(kind) {
        if (!shown || busy() || !stateAllows(kind)) return;
        if (kind !== 'off' && !validateFields()) return;
        clearSecret();
        intent = kind;
        ui.setLabel(confirmTitle, kind === 'off' ? '关闭热点？' : kind === 'apply' ? '应用并重启热点？' : '开启热点？');
        ui.setLabel(confirmDescription, kind === 'off'
            ? '已连接的设备会断开，随后尝试恢复原 Wi-Fi；可能需要重新认证。'
            : kind === 'apply'
                ? '正在使用热点的设备会短暂断开。更改频段或名称后，需要重新连接。'
                : '这会断开当前 Wi-Fi；有线连接不受影响。关闭热点后会尝试恢复原 Wi-Fi。');
        ui.setLabel(accept.label, kind === 'off' ? '关闭热点' : kind === 'apply' ? '确认应用' : '确认开启');
        css(accept.button, 'danger', kind === 'off');
        css(accept.button, 'primary', kind !== 'off');
        confirm.set_reveal_child(true); updateControls();
    }
    function cancelConfirmation() {
        intent = null; confirm.set_reveal_child(false); updateControls();
    }
    function beginOperation(kind, path = null) {
        const seen = Number(ctx.getState?.()?.feedback?.sequence);
        operation = {kind, sawBusy: backendBusy(), feedbackAt: Number.isFinite(seen) ? seen : lastFeedback};
        cancelTimer('operation');
        operationTimer = GLib.timeout_add(GLib.PRIORITY_DEFAULT, 65000, () => {
            operationTimer = 0; operation = null;
            password.set_text(''); clearSecret();
            if (shown) { ctx.send('refresh'); ctx.toast('尚未确认操作结果，请检查状态；不会自动重试', true); }
            updateControls(); return GLib.SOURCE_REMOVE;
        });
        try {
            // Only kind and the private path go into the service pipe. No credentials.
            if (ctx.send('hotspot', path ? {kind, path} : {kind}) === false) throw new Error('transport closed');
            ownedPath = null; // Ownership transfers to the service/helper, even if hidden next.
            // Keep the password until this operation's feedback arrives: a busy
            // helper must not destroy the user's just-typed secret.
            ctx.toast(kind === 'off' ? '正在关闭热点…' : kind === 'apply' ? '正在应用设置…' : '正在开启热点…');
        } catch (_) {
            cancelTimer('operation'); operation = null;
            if (ownedPath) discard(ownedPath);
            ownedPath = null; password.set_text('');
            ctx.toast('无法确认请求已发送，请刷新状态', true);
        }
        updateControls();
    }
    function submitConfirmation() {
        const kind = intent;
        if (!shown || !kind || busy()) return;
        if (!stateAllows(kind)) {
            cancelConfirmation(); ctx.toast('热点状态已变化，请刷新后重新确认', true); return;
        }
        if (kind !== 'off' && !validateFields()) return;
        cancelConfirmation();
        if (kind === 'off') { beginOperation(kind); return; }
        preparing = true;
        const mine = generation;
        updateControls();
        try {
            ctx.runHelper(['prepare-request'], result => {
                const path = result?.ok === true && typeof result.path === 'string' ? result.path : null;
                if (!shown || mine !== generation) { if (path) discard(path); return; }
                if (!path) {
                    preparing = false; password.set_text(''); updateControls();
                    ctx.toast('无法创建私有请求，未执行热点操作', true); return;
                }
                ownedPath = path;
                if (!stateAllows(kind)) {
                    discard(path); ownedPath = null; preparing = false; password.set_text(''); updateControls();
                    ctx.toast('热点状态已变化，请重新确认', true); return;
                }
                let written = false;
                try {
                    written = ctx.writePrivateRequest(path, {ssid: ssid.get_text(), password: password.get_text(), band: desiredBand}) === true;
                } catch (_) {}
                preparing = false;
                if (!written) {
                    discard(path); ownedPath = null; password.set_text(''); updateControls();
                    ctx.toast('无法安全写入请求，未执行热点操作', true); return;
                }
                beginOperation(kind, path);
            });
        } catch (_) {
            preparing = false; password.set_text(''); updateControls();
            ctx.toast('无法启动私有请求工具', true);
        }
    }
    function toggleSecret() {
        if (!shown) return;
        if (secretVisible || revealing) { clearSecret(); return; }
        if (busy() || intent) return;
        const mine = generation, revealMine = ++revealGeneration;
        revealing = true; updateControls();
        try {
            ctx.runHelper(['reveal'], result => {
                if (!shown || generation !== mine || revealGeneration !== revealMine) {
                    if (result && typeof result === 'object') result.password = '';
                    return;
                }
                revealing = false;
                if (result?.ok !== true || typeof result.password !== 'string' || !result.password) {
                    if (result && typeof result === 'object') result.password = '';
                    clearSecret(); ctx.toast('尚无可安全读取的已保存密码，请先开启热点', true); return;
                }
                savedPassword.set_text(result.password);
                result.password = '';
                secretVisible = true; secretBox.set_reveal_child(true);
                cancelTimer('secret');
                secretTimer = GLib.timeout_add_seconds(GLib.PRIORITY_DEFAULT, 30, () => {
                    secretTimer = 0; clearSecret(); return GLib.SOURCE_REMOVE;
                });
                updateControls();
            });
        } catch (_) {
            clearSecret(); ctx.toast('未能读取已保存密码', true);
        }
    }
    function updateControls() {
        const h = hot(), inFlight = busy(), known = typeof h.on === 'boolean';
        sensitive(power.button, shown && !inFlight && !intent && known && h.available === true);
        ui.setLabel(power.label, inFlight ? '正在处理…' : h.on === true ? '关闭热点' : '开启热点');
        css(power.button, 'danger', h.on === true);
        css(power.button, 'primary', h.on !== true);
        sensitive(header.refresh, shown && !inFlight);
        for (const control of [ssid, password, band24, band5, reset]) sensitive(control, !inFlight && !intent);
        show(apply, h.on === true);
        sensitive(apply, shown && !inFlight && !intent && h.available === true && hasChanges());
        sensitive(accept.button, shown && !!intent && !inFlight && stateAllows(intent));
        sensitive(cancel, !preparing);
        sensitive(revealButton.button, shown && !inFlight && !intent);
        sensitive(copy, shown && secretVisible && !inFlight && !intent);
        ui.setLabel(revealButton.label, secretVisible ? '隐藏密码' : revealing ? '取消读取' : '查看密码');
        const pendingText = hasChanges() || h.pending === true
            ? (h.on === true ? '有修改尚未应用；应用时会重启热点。' : '这些设置将在开启热点时使用。')
            : '';
        ui.setLabel(pending, pendingText);
        // An empty wrapped label still reserves 18px, which left a hole above
        // the actions row whenever nothing needed saying.
        show(pending, pendingText !== '');
    }
    function update(state) {
        current = state?.system || {hotspot: {}, windows: [], loading: true};
        const h = hot();
        const feedback = state?.feedback;
        if (Number.isFinite(feedback?.sequence)) lastFeedback = feedback.sequence;
        if (h.busy === true && (secretVisible || revealing)) clearSecret();
        if (operation) {
            if (h.busy === true) operation.sawBusy = true;
            const sameAction = !feedback?.hotspotAction || feedback.hotspotAction === operation.kind;
            const finished = feedback?.scope === 'hotspot' && sameAction && Number(feedback.sequence) > operation.feedbackAt;
            if (finished || (operation.sawBusy && h.busy !== true)) {
                cancelTimer('operation'); operation = null;
                if (!feedback || feedback.ok === true) { password.set_text(''); clearSecret(); }
            }
        }
        if ((!initialized || !editing) && !busy() && !intent && typeof h.ssid === 'string' && h.ssid) resetFields();
        if (initialized && !hasChanges()) editing = false;
        ui.setLabel(status, busy() ? '正在处理热点操作' : h.on === true ? '热点已开启' : h.on === false ? '热点已关闭' : current.loading ? '正在读取热点状态…' : '暂时无法确认状态');
        css(statusCard, 'hotspot-active', h.on === true);
        ui.setLabel(networkName, clean(h.ssid) || (current.loading ? '正在获取网络信息…' : '尚未设置热点名称'));
        ui.setLabel(actualBand.value, h.on === true ? (h.band === 'a' ? '5 GHz' : h.band === 'bg' ? '2.4 GHz' : '未知') : '—');
        ui.setLabel(iface.value, clean(h.iface) || '—');
        ui.setLabel(gateway.value, clean(h.gateway) || '—');
        const countKnown = Number.isInteger(h.clients) && h.clients >= 0;
        show(clients.row, h.on === true && countKnown);
        if (countKnown) ui.setLabel(clients.value, h.clients + ' 台');
        ui.setLabel(statusError, clean(h.error)); show(statusError, !!clean(h.error));
        const warnings = [...new Set([clean(h.warning), clean(h.operationWarning)].filter(Boolean))].join('\n');
        ui.setLabel(operationWarning, warnings); show(operationWarning, !!warnings);
        const duration = ui.motionMs(state?.preferences?.reducedMotion === true, 'reveal');
        confirm.set_transition_duration(duration); secretBox.set_transition_duration(duration);
        if (intent && !stateAllows(intent)) cancelConfirmation();
        updateControls();
    }
    function onShow() { shown = true; updateControls(); ctx.send('refresh'); }
    function onHide() {
        shown = false; generation++;
        preparing = false; intent = null; operation = null;
        cancelTimer('operation'); confirm.set_reveal_child(false);
        if (ownedPath) discard(ownedPath);
        ownedPath = null;
        password.set_text(''); clearSecret(); updateControls();
    }
    function handleEscape() {
        if (preparing) { generation++; preparing = false; if (ownedPath) discard(ownedPath); ownedPath = null; password.set_text(''); updateControls(); return true; }
        if (intent) { cancelConfirmation(); return true; }
        if (secretVisible || revealing) { clearSecret(); return true; }
        if (password.get_text()) { password.set_text(''); return true; }
        return false;
    }
    updateControls();
    return {widget, update, onShow, onHide, handleEscape};
}

export function createWindows(ctx) {
    const ui = ctx.ui;
    let shown = false, current = {windows: [], loading: true}, pendingId = null;
    let reducedMotion = false, staggerPending = false, rowStaggerSource = 0;
    let signature = '', ordered = [], rows = new Map(), query = '';
    const widget = ui.box('vertical', 10);
    widget.set_vexpand(true); widget.set_hexpand(true);
    const header = pageHeader(ui, '窗口', () => { if (shown) ctx.send('refresh'); });
    const count = ui.label('0', ['status']);
    header.row.insert_child_after(count, header.row.get_first_child());
    widget.append(header.row);
    // Everything below the header scrolls as one page. Anything left outside
    // (the confirm card's wrapped title was one) pushes its natural width into
    // the layer-shell surface and the panel silently grows past 450px.
    const page = ui.box('vertical', 10, ['scroll-gutter']);
    const search = ui.classes(new Gtk.SearchEntry({hexpand: true, placeholder_text: '搜索应用或窗口'}), ['field-muted']);
    page.append(search);

    // Niri 桌面中控卡片
    const niriCard = ui.card(['card', 'niri-control-card', 'rise', 'rise-1']);
    niriCard.set_spacing(8);

    const niriHeader = ui.box(Gtk.Orientation.HORIZONTAL, 6);
    const niriTitle = ui.label('工作区与平铺调度', ['section-title']);
    niriTitle.set_hexpand(true);
    niriHeader.append(niriTitle);
    niriCard.append(niriHeader);

    // 6 个工作区微型胶囊
    const wsRow = ui.box(Gtk.Orientation.HORIZONTAL, 5);
    wsRow.set_homogeneous(true);
    const wsButtons = [];
    for (let ws = 1; ws <= 6; ws++) {
        const wsBtn = ui.button(String(ws), null, () => {
            try { GLib.spawn_command_line_async(`niri msg action focus-workspace ${ws}`); } catch (_) {}
        }, ['dev-pill', 'ws-pill']);
        wsBtn.set_tooltip_text(`切换到工作区 ${ws}`);
        wsRow.append(wsBtn);
        wsButtons.push(wsBtn);
    }
    niriCard.append(wsRow);

    // 快速调度栏
    const actionRow = ui.box(Gtk.Orientation.HORIZONTAL, 6);
    actionRow.set_homogeneous(true);
    const btnFullscreen = ui.button('全屏切换', null, () => {
        try { GLib.spawn_command_line_async('niri msg action fullscreen-window'); } catch (_) {}
    }, ['dev-pill']);
    btnFullscreen.set_tooltip_text('切换当前窗口全屏 (niri fullscreen)');

    const btnCenter = ui.button('窗口居中', null, () => {
        try { GLib.spawn_command_line_async('niri msg action center-column'); } catch (_) {}
    }, ['dev-pill']);
    btnCenter.set_tooltip_text('将当前列居中显示 (niri center-column)');

    actionRow.append(btnFullscreen);
    actionRow.append(btnCenter);
    niriCard.append(actionRow);

    page.append(niriCard);
    const errorLabel = paragraph(ui, '', ['warning']); show(errorLabel, false); page.append(errorLabel);

    const confirmation = new Gtk.Revealer({transition_type: Gtk.RevealerTransitionType.SLIDE_DOWN, transition_duration: ui.DURATION.reveal});
    const confirmCard = ui.card(['window-card']);
    confirmCard.append(ui.label('关闭这个窗口？', ['section-title']));
    const confirmName = paragraph(ui, '', []); confirmCard.append(confirmName);
    confirmCard.append(paragraph(ui, '未保存内容可能丢失，应用也可能先要求保存。此操作不会强杀进程。'));
    const confirmButtons = ui.box('horizontal', 8);
    const cancel = ui.button('取消', null, cancelClose); cancel.set_hexpand(true);
    const close = ui.button('关闭窗口', 'x', () => {
        const id = pendingId;
        if (!shown || !id || !rows.has(id) || current.windowsError) return;
        cancelClose();
        ctx.send('window-close', {id});
        // Do not optimistically remove a row: the app may show a save dialog.
    }, ['danger']);
    close.set_hexpand(true); close.set_tooltip_text('确认关闭所选窗口');
    confirmButtons.append(cancel); confirmButtons.append(close); confirmCard.append(confirmButtons);
    confirmation.set_child(confirmCard); page.append(confirmation);

    const content = ui.box('vertical', 0, ['mac-group', 'rise', 'rise-2']);
    function staggerRows() {
        if (reducedMotion) return;
        if (rowStaggerSource) { GLib.source_remove(rowStaggerSource); rowStaggerSource = 0; }
        const targets = [];
        let index = 0;
        for (let child = list.get_first_child(); child; child = child.get_next_sibling()) {
            if (!child.has_css_class('window-row')) continue;
            child.remove_css_class('row-in');
            for (let n = 0; n < 8; n++) child.remove_css_class('row-in-' + n);
            child.add_css_class('row-in');
            child.add_css_class('row-in-' + Math.min(index, 7));
            index += 1; targets.push(child);
        }
        if (!targets.length) return 0;
        rowStaggerSource = GLib.timeout_add(GLib.PRIORITY_DEFAULT, 380, () => {
            rowStaggerSource = 0;
            for (const child of targets) child.remove_css_class('row-in');
            return GLib.SOURCE_REMOVE;
        });
        return targets.length;
    }
    const list = ui.box('vertical', 8); content.append(list);
    const empty = ui.card(['window-card']);
    empty.append(ui.icon('apps', 32));
    const emptyTitle = ui.label('正在获取窗口', ['section-title']); empty.append(emptyTitle);
    const emptyText = paragraph(ui, '窗口列表会在状态更新后显示。'); empty.append(emptyText);
    content.append(empty); page.append(content); widget.append(scrolled(page));
    function cancelClose() { pendingId = null; confirmation.set_reveal_child(false); sensitive(close, false); }
    function openClose(id) {
        if (!shown || !rows.has(id) || current.windowsError) return;
        if (ctx.config?.()?.confirmWindowClose === false) { ctx.send('window-close', {id}); return; }
        pendingId = id;
        ui.setLabel(confirmName, rows.get(id).data.title || rows.get(id).data.appId || '未命名窗口');
        confirmation.set_reveal_child(true); sensitive(close, true);
    }
    function makeRow(data) {
        const row = ui.box('horizontal', 8, ['mac-row', 'window-row']);
        const focus = ui.button('', null, () => {
            if (shown && rows.has(data.id) && !current.windowsError) ctx.send('window-focus', {id: data.id});
        });
        focus.add_css_class('window-focus');
        focus.set_hexpand(true);
        const inner = ui.box('horizontal', 9);
        inner.append(ui.icon('apps', 22));
        const text = ui.box('vertical', 4); text.set_hexpand(true);
        const title = ui.label(''); const subtitle = ui.label('', ['muted']);
        text.append(title); text.append(subtitle); inner.append(text); focus.set_child(inner);
        const remove = ui.iconButton('x', () => openClose(data.id), '关闭此窗口', ['danger']);
        row.append(focus); row.append(remove);
        return {widget: row, focus, remove, title, subtitle, data};
    }
    function updateRow(row, data) {
        row.data = data;
        ui.setLabel(row.title, data.title || data.appId || '未命名窗口');
        const workspace = data.workspaceId ? ' · 工作区 ' + data.workspaceId : '';
        ui.setLabel(row.subtitle, (data.appId || '未知应用') + workspace + (data.focused ? ' · 当前' : ''));
        const tooltip = (data.title || data.appId || '未命名窗口') + '\n点击回到此窗口';
        if (row.focus.get_tooltip_text() !== tooltip) row.focus.set_tooltip_text(tooltip);
        css(row.widget, 'selected', data.focused);
        sensitive(row.focus, shown && !current.windowsError);
        sensitive(row.remove, shown && !current.windowsError);
    }
    function applyFilter() {
        let visibleCount = 0;
        for (const id of ordered) {
            const row = rows.get(id);
            const matches = !query || (row.data.title + '\n' + row.data.appId).toLowerCase().includes(query);
            show(row.widget, matches); if (matches) visibleCount++;
        }
        ui.setLabel(count, query ? visibleCount + ' / ' + ordered.length : ordered.length + ' 个');
        show(empty, visibleCount === 0);
        ui.setLabel(emptyTitle, current.loading && !ordered.length ? '正在获取窗口' : query ? '没有匹配的窗口' : '没有打开的窗口');
        ui.setLabel(emptyText, current.windowsError ? '查询未完成，可点击右上角重新获取。'
            : query ? '试试应用名称，或清空搜索。' : current.loading ? '窗口列表会在状态更新后显示。' : '打开应用后，它会出现在这里。');
    }
    search.connect('search-changed', () => { query = search.get_text().trim().toLowerCase(); applyFilter(); });
    function update(state) {
        current = state?.system || {windows: [], loading: true};
        const unique = new Set();
        const data = (Array.isArray(current.windows) ? current.windows : []).filter(row => {
            if (!row || !validId(row.id) || unique.has(row.id)) return false;
            unique.add(row.id); return true;
        }).map(row => ({id: row.id, title: clean(row.title, 240), appId: clean(row.appId, 160),
            workspaceId: validId(row.workspaceId) ? row.workspaceId : null, focused: row.focused === true}));
        const next = data.map(row => row.id).join(',');
        if (next !== signature) {
            for (const [id, row] of rows) {
                if (!unique.has(id)) { list.remove(row.widget); rows.delete(id); }
            }
            let previous = null;
            for (const item of data) {
                let row = rows.get(item.id);
                if (!row) { row = makeRow(item); rows.set(item.id, row); list.append(row.widget); }
                list.reorder_child_after(row.widget, previous); previous = row.widget;
            }
            ordered = data.map(row => row.id); signature = next;
            let firstRow = true;
            for (const [id] of rows) {
                const row = rows.get(id);
                if (!row) continue;
                row.widget.remove_css_class('mac-sep');
                if (firstRow) firstRow = false;
                else row.widget.add_css_class('mac-sep');
            }
        }
        for (const item of data) updateRow(rows.get(item.id), item);
        if (pendingId) {
            if (!rows.has(pendingId) || current.windowsError) cancelClose();
            else ui.setLabel(confirmName, rows.get(pendingId).data.title || rows.get(pendingId).data.appId || '未命名窗口');
        }
        if (ctx.config?.()?.confirmWindowClose === false && pendingId) cancelClose();
        const error = clean(current.windowsError);
        ui.setLabel(errorLabel, error); show(errorLabel, !!error);
        sensitive(header.refresh, shown);
        sensitive(close, shown && !!pendingId && !error);
        confirmation.set_transition_duration(ui.motionMs(state?.preferences?.reducedMotion === true, 'reveal'));
        // Highlight active workspace
        const activeWin = data.find(w => w.focused);
        const activeWs = activeWin ? parseInt(activeWin.workspaceId, 10) : 0;
        wsButtons.forEach((btn, idx) => {
            if (idx + 1 === activeWs) btn.add_css_class('selected');
            else btn.remove_css_class('selected');
        });
        applyFilter();
        if (staggerPending && shown && staggerRows()) staggerPending = false;
    }
    function onShow() {
        shown = true; staggerPending = true;
        for (const row of rows.values()) updateRow(row, row.data);
        sensitive(header.refresh, true); ctx.send('refresh');
    }
    function onHide() { shown = false; cancelClose(); for (const row of rows.values()) updateRow(row, row.data); }
    function handleEscape() {
        if (pendingId) { cancelClose(); return true; }
        if (search.get_text()) { search.set_text(''); query = ''; applyFilter(); return true; }
        return false;
    }
    return {widget, update, onShow, onHide, handleEscape};
}
