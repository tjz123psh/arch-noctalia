#!/usr/bin/env -S gjs -m
// Run: gjs -m tide-sidebar/tests/native_system_spec.js
// Requires a GTK4 display backend, but never creates/presents a Gtk.Window.
// These are the previously run 23 + 13 assertions, now reproducible as a module.
// Every helper, service command, private-file write and clipboard operation is
// mocked. Fixture credentials are invented; no user data is opened or changed.
import Gtk from 'gi://Gtk?version=4.0';
import * as UI from '../native/ui.js';
import {createHotspot, createWindows} from '../native/views/system.js';

Gtk.init();
let checks = 0;
const FAKE_SECRET = 'UNIT-ONLY-PASSPHRASE';

function assert(value, message) {
    if (!value) throw new Error(message);
    checks++;
}
function walk(root) {
    const all = [];
    function visit(widget) {
        all.push(widget);
        for (let child = widget.get_first_child(); child; child = child.get_next_sibling()) visit(child);
    }
    visit(root);
    return all;
}
function byTip(root, tooltip) {
    const button = walk(root).find(widget => widget instanceof Gtk.Button && widget.get_tooltip_text() === tooltip);
    if (!button) throw new Error('Missing fixture control: ' + tooltip);
    return button;
}
function context(ui = UI, allowWrite = true) {
    const ctx = {ui, allowWrite, sends: [], helpers: [], writes: [], copies: [], notices: []};
    ctx.send = (action, values = {}) => ctx.sends.push({action, ...values});
    ctx.toast = (text, error) => ctx.notices.push({text, error});
    ctx.copy = text => ctx.copies.push(text);
    ctx.close = () => {};
    ctx.runHelper = (args, callback) => {
        ctx.helpers.push({args, callback});
        if (args[0] === 'discard-request') callback({ok: true});
    };
    ctx.writePrivateRequest = (path, value) => {
        ctx.writes.push({path, value: {...value}});
        return ctx.allowWrite;
    };
    // Plugin settings the view reads through ctx.config(); empty means "all defaults".
    ctx.configValues = null;
    ctx.config = () => ctx.configValues || {};
    return ctx;
}
function baseState() {
    return {
        system: {
            hotspot: {available: true, on: false, ssid: 'Test AP', iface: 'test0', gateway: '',
                band: null, desiredBand: 'bg', pending: false, clients: null, busy: false},
            windows: [], windowsError: null, loading: false,
        },
        preferences: {reducedMotion: true},
    };
}
function lastHelper(ctx, name) { return ctx.helpers.findLast(item => item.args[0] === name); }
function secretFields(page) {
    return {
        draft: walk(page.widget).find(widget => widget instanceof Gtk.PasswordEntry),
        saved: walk(page.widget).find(widget => widget instanceof Gtk.Entry
            && widget.get_tooltip_text() === '临时显示的已保存密码'),
    };
}
function confirmPower(page) {
    byTip(page.widget, '开启或关闭热点').emit('clicked');
    byTip(page.widget, '确认热点操作').emit('clicked');
}

function primaryFixture() {
    let factoryCount = 0;
    const counted = {...UI};
    for (const name of ['box', 'card', 'label', 'button', 'iconButton']) {
        counted[name] = (...args) => { factoryCount++; return UI[name](...args); };
    }
    const ctx = context(counted);
    const page = createHotspot(ctx);
    const state = baseState();
    let windows = null;
    try {
        page.update(state); page.onShow();
        const {draft, saved} = secretFields(page);
        assert(draft && saved, 'Real GTK entries are required');

        draft.set_text(FAKE_SECRET);
        byTip(page.widget, '开启或关闭热点').emit('clicked');
        assert(ctx.sends.every(item => item.action !== 'hotspot'), 'Opening confirmation must not change network');
        byTip(page.widget, '确认热点操作').emit('clicked');
        let request = lastHelper(ctx, 'prepare-request');
        assert(!!request, 'Confirmed start prepares private request');
        page.onHide();
        request.callback({ok: true, path: '/mock/private/request-aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa.json'});
        assert(ctx.helpers.at(-1).args[0] === 'discard-request', 'Late preparation is discarded');
        assert(ctx.writes.length === 0 && ctx.sends.every(item => item.action !== 'hotspot'), 'Late preparation does not write or submit');
        assert(draft.get_text() === '' && saved.get_text() === '', 'Hiding clears secret fields');

        page.onShow(); draft.set_text(FAKE_SECRET); confirmPower(page);
        request = lastHelper(ctx, 'prepare-request');
        request.callback({ok: true, path: '/mock/private/request-bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb.json'});
        const action = ctx.sends.findLast(item => item.action === 'hotspot');
        assert(action.kind === 'on' && typeof action.path === 'string', 'Confirmed start only sends kind and path');
        assert(!JSON.stringify(ctx.sends).includes(FAKE_SECRET), 'Service commands contain no password');
        assert(ctx.writes.at(-1).value.password === FAKE_SECRET && draft.get_text() === '', 'Password is private-request-only then cleared');
        state.system.hotspot.busy = true; page.update(state);
        state.system.hotspot.busy = false; page.update(state);

        byTip(page.widget, '查看或隐藏已保存密码').emit('clicked');
        const lateReveal = lastHelper(ctx, 'reveal'); page.onHide();
        const lateValue = {ok: true, password: FAKE_SECRET};
        lateReveal.callback(lateValue);
        assert(saved.get_text() === '' && lateValue.password === '', 'Late reveal cannot expose a password');
        page.onShow();
        byTip(page.widget, '查看或隐藏已保存密码').emit('clicked');
        lastHelper(ctx, 'reveal').callback({ok: true, password: FAKE_SECRET});
        assert(saved.get_text() === FAKE_SECRET, 'Explicit reveal displays only locally');
        byTip(page.widget, '复制已显示的密码').emit('clicked');
        assert(ctx.copies.length === 1, 'Copy requires explicit button action');
        page.onHide();
        assert(saved.get_text() === '' && draft.get_text() === '', 'Hiding clears revealed and draft passwords');
        assert(!JSON.stringify(ctx.sends).includes(FAKE_SECRET) && !JSON.stringify(ctx.notices).includes(FAKE_SECRET), 'No secret in service pipe or toasts');

        const windowContext = context(counted);
        windows = createWindows(windowContext);
        const windowState = baseState();
        windowState.system.windows = [{id: '18446744073709551615', title: 'First title',
            appId: 'test.App', workspaceId: '1', focused: false}];
        windows.update(windowState); windows.onShow();
        const row = walk(windows.widget).find(widget => widget.has_css_class('window-row'));
        const before = factoryCount;
        for (let i = 0; i < 40; i++) {
            windowState.system.windows[0].title = 'Title ' + i;
            windows.update(windowState);
        }
        assert(walk(windows.widget).find(widget => widget.has_css_class('window-row')) === row, 'Title changes preserve row identity');
        assert(factoryCount === before, 'Title-only updates allocate no new widget factories');
        row.get_first_child().emit('clicked');
        assert(windowContext.sends.at(-1).action === 'window-focus'
            && windowContext.sends.at(-1).id === '18446744073709551615', 'Focus preserves full uint64 string');

        byTip(windows.widget, '关闭此窗口').emit('clicked');
        assert(windowContext.sends.every(item => item.action !== 'window-close'), 'Close first click only opens confirmation');
        const close = byTip(windows.widget, '确认关闭所选窗口');
        assert(close.get_sensitive(), 'Close confirmation is immediately usable');
        close.emit('clicked');
        assert(windowContext.sends.filter(item => item.action === 'window-close').length === 1, 'Explicit confirmation sends one close');
        close.emit('clicked');
        assert(windowContext.sends.filter(item => item.action === 'window-close').length === 1, 'Repeated confirmation cannot close another window');
        byTip(windows.widget, '关闭此窗口').emit('clicked');
        windowState.system.windows = []; windows.update(windowState); close.emit('clicked');
        assert(windowContext.sends.filter(item => item.action === 'window-close').length === 1, 'Disappeared target is never acted on');
        windowState.system.windows = [{id: '1; unsafe', title: 'Invalid', appId: 'bad'}];
        windows.update(windowState);
        assert(walk(windows.widget).filter(widget => widget.has_css_class('window-row')).length === 0, 'Invalid IDs are excluded');
    } finally {
        page.onHide();
        windows?.onHide();
    }
}

function boundaryFixture() {
    const ctx = context(UI, false);
    const page = createHotspot(ctx);
    const state = baseState();
    try {
        page.update(state); page.onShow();
        const {draft, saved} = secretFields(page);
        draft.set_text(FAKE_SECRET); confirmPower(page);
        lastHelper(ctx, 'prepare-request').callback({ok: true, path: '/mock/private/request-cccccccccccccccccccccccccccccccc.json'});
        assert(ctx.helpers.at(-1).args[0] === 'discard-request', 'Write failure discards the exact file');
        assert(!ctx.sends.some(item => item.action === 'hotspot'), 'Write failure never sends operation');
        assert(draft.get_text() === '', 'Write failure clears draft password');

        byTip(page.widget, '查看或隐藏已保存密码').emit('clicked');
        let result = lastHelper(ctx, 'reveal');
        byTip(page.widget, '查看或隐藏已保存密码').emit('clicked');
        const stale = {ok: true, password: FAKE_SECRET}; result.callback(stale);
        assert(saved.get_text() === '' && stale.password === '', 'Canceled reveal stays hidden');
        byTip(page.widget, '查看或隐藏已保存密码').emit('clicked');
        lastHelper(ctx, 'reveal').callback({ok: true, password: FAKE_SECRET});
        assert(saved.get_text() === FAKE_SECRET, 'Explicit reveal works');
        state.system.hotspot.busy = true; page.update(state);
        assert(saved.get_text() === '', 'A new operation clears previously revealed password');
        state.system.hotspot.busy = false; page.update(state);

        draft.set_text(FAKE_SECRET); confirmPower(page);
        result = lastHelper(ctx, 'prepare-request');
        assert(page.handleEscape() === true, 'Escape cancels preparation');
        result.callback({ok: true, path: '/mock/private/request-dddddddddddddddddddddddddddddddd.json'});
        assert(ctx.helpers.at(-1).args[0] === 'discard-request', 'Canceled preparation discards late file');
        assert(!ctx.sends.some(item => item.action === 'hotspot'), 'Canceled preparation does not execute');

        state.system.hotspot.on = true; state.system.hotspot.band = 'bg'; page.update(state);
        draft.set_text('bad'); const helperCount = ctx.helpers.length; confirmPower(page);
        assert(ctx.sends.at(-1).kind === 'off', 'Off works independently of invalid unused password draft');
        assert(ctx.helpers.length === helperCount, 'Off does not create or read a credential request');
        assert(!JSON.stringify(ctx.sends).includes(FAKE_SECRET), 'No request password is sent through the pipe');
        page.onHide();
        ctx.sends = []; state.system.hotspot.on = null; page.update(state); page.onShow(); confirmPower(page);
        assert(!ctx.sends.some(item => item.action === 'hotspot'), 'Unknown network state cannot trigger a toggle');
    } finally {
        page.onHide();
    }
}

function settingsFixture() {
    // confirm_window_close=false closes straight away; the default still asks first.
    const quickContext = context(UI, true);
    quickContext.configValues = {confirmWindowClose: false};
    const quick = createWindows(quickContext);
    const windowState = baseState();
    windowState.system.windows = [{id: '7', title: 'Quick', appId: 'test.App', workspaceId: '1', focused: false}];
    quick.update(windowState); quick.onShow();
    quickContext.sends = [];
    byTip(quick.widget, '关闭此窗口').emit('clicked');
    assert(quickContext.sends.length === 1 && quickContext.sends[0].action === 'window-close' && quickContext.sends[0].id === '7',
        'With the confirmation disabled the close button must send the action directly');
    quick.onHide();

    const carefulContext = context(UI, true);
    const careful = createWindows(carefulContext);
    careful.update(windowState); careful.onShow();
    carefulContext.sends = [];
    byTip(careful.widget, '关闭此窗口').emit('clicked');
    assert(!carefulContext.sends.some(item => item.action === 'window-close'),
        'The default must still ask before closing a window');
    careful.onHide();

    // Hotspot defaults apply only while the script never recorded a name or band.
    const defaultsContext = context(UI, true);
    defaultsContext.configValues = {hotspotDefaultSsid: 'Tide 默认', hotspotDefaultBand: 'a'};
    const form = createHotspot(defaultsContext);
    const formState = baseState();
    formState.system.hotspot = {...formState.system.hotspot, ssid: 'host-fallback',
        desiredSsidKnown: false, desiredBandKnown: false, desiredBand: 'bg'};
    form.update(formState); form.onShow();
    const ssidField = walk(form.widget).find(widget => widget instanceof Gtk.Entry
        && widget.get_tooltip_text() === '热点名称，最多 32 个 UTF-8 字节');
    assert(!!ssidField && ssidField.get_text() === 'Tide 默认',
        'A configured default name must prefill a hotspot the script never recorded');
    const band5 = walk(form.widget).find(widget => widget instanceof Gtk.ToggleButton && widget.get_label() === '5 GHz');
    assert(!!band5 && band5.get_active(), 'A configured default band must be preselected');
    form.onHide();
}

primaryFixture();
boundaryFixture();
settingsFixture();
print('native-system-spec: ' + checks + ' assertions passed (23 + 13 + 4); no windows presented; helpers, network, window and clipboard actions mocked');
