// Real GTK widgets with an isolated mock backend. A never-realized/presented
// window is used only for native focus dispatch; send/copy/toast stay mocked.
// From tide-sidebar/:
// env LD_PRELOAD=/usr/lib/libgtk4-layer-shell.so GDK_BACKEND=wayland G_DEBUG=fatal-warnings gjs -m tests/native_tools_spec.js
import Gtk from 'gi://Gtk?version=4.0';
import Gdk from 'gi://Gdk?version=4.0';
import GLib from 'gi://GLib';
import System from 'system';
import * as ui from '../native/ui.js';
import {createTools} from '../native/views/tools.js';

const EXPECTED_ASSERTIONS = 113;
const TIMEOUT_MS = 10000;
const originalDateNow = Date.now;
const loop = new GLib.MainLoop(null, false);
const views = [];
const windows = [];
const pendingDelays = new Set();
let checks = 0;
let completed = false;
let failure = null;

function assert(condition, message) {
    if (!condition) throw new Error('Assertion ' + (checks + 1) + ': ' + message);
    checks++;
}
function delay(ms) {
    return new Promise(resolve => {
        const source = GLib.timeout_add(GLib.PRIORITY_DEFAULT, ms, () => {
            pendingDelays.delete(source);
            resolve();
            return GLib.SOURCE_REMOVE;
        });
        pendingDelays.add(source);
    });
}
function walk(root) {
    const all = [root];
    for (let child = root.get_first_child(); child; child = child.get_next_sibling())
        all.push(...walk(child));
    // A collapsed Gtk.Expander still owns its child, but GTK unparents it.
    if (root instanceof Gtk.Expander && root.get_child() && !all.includes(root.get_child()))
        all.push(...walk(root.get_child()));
    return all;
}

async function runSuite() {
    Gtk.init();
    const actions = [], copied = [], notices = [];
    const view = createTools({
        ui,
        send: (action, values) => actions.push({action, ...values}),
        toast: (text, error) => notices.push({text, error}),
        copy: text => { copied.push(text); return true; },
    });
    views.push(view);
    assert(actions.length === 0, 'Construction must not issue commands');
    const widgets = walk(view.widget);
    const findClass = name => widgets.find(w => w.has_css_class(name));
    const expression = findClass('calc-expression');
    const result = findClass('result-display');
    const history = findClass('tools-history');
    const fields = widgets.filter(w => w.has_css_class('duration-field'));
    const timerDisplay = findClass('timer-display');
    const progress = widgets.find(w => w instanceof Gtk.ProgressBar);
    const buttons = widgets.filter(w => w instanceof Gtk.Button);
    const buttonText = b => walk(b).filter(w => w instanceof Gtk.Label).map(w => w.get_label()).join('');
    const button = text => buttons.find(b => buttonText(b) === text);
    const key = text => buttons.find(b => b.has_css_class('key-button') && buttonText(b) === text);
    const timerActions = () => actions.filter(a => a.action.startsWith('timer-'));
    const calcActions = () => actions.filter(a => a.action === 'calc-evaluate');

    // Lifecycle, bounded native controls and service readiness.
    const idle = {ready: true, error: '', timer: {status: 'idle', durationMs: 600000, remainingMs: 600000}};
    const blankCalc = {expression: '', result: '0', error: '', history: [], requestId: ''};
    view.update({calc: blankCalc, timer: idle});
    view.onShow(); view.onHide();
    assert(actions.length === 0, 'Update/show/hide must not issue commands');
    assert(fields.map(f => f.get_text()).join(':') === '00:10:00', 'Initial duration must come from snapshot');
    assert(button('开始').get_sensitive(), 'Ready valid timer must enable start');
    assert(!button('暂停').get_visible() && !button('继续').get_visible(), 'Inactive controls must be hidden');
    assert(widgets.filter(w => w.has_css_class('key-button')).length === 24, 'Approved keypad must have 24 native keys');
    const numberKeypad = findClass('number-keypad');
    const numberKeys = ['C', '(', ')', '7', '8', '9', '4', '5', '6', '1', '2', '3', '0', '.', '%', 'Ans', '√', '^'];
    assert(numberKeypad instanceof Gtk.Grid && numberKeys.every((text, index) => buttonText(numberKeypad.get_child_at(index % 3, Math.floor(index / 3))) === text), 'Number keypad must match the approved three-column six-row layout');
    const operatorColumn = findClass('operator-column');
    const operatorKeys = walk(operatorColumn).filter(w => w instanceof Gtk.Button);
    assert(operatorColumn.get_orientation() === Gtk.Orientation.VERTICAL && operatorColumn.get_homogeneous() && operatorKeys.map(buttonText).join(',') === '⌫,÷,×,−,+,=' && operatorKeys.at(-1).has_css_class('equals-button') && operatorKeys.at(-1).has_css_class('primary'), 'Operators must share one ordered vertical column ending in the primary equals button');
    const timerCard = findClass('timer-card');
    const timerContentPane = findClass('timer-content-pane');
    assert(timerCard.get_orientation() === Gtk.Orientation.HORIZONTAL && findClass('timer-label-pane').get_parent() === timerCard && timerContentPane.get_parent() === timerCard && timerDisplay.get_parent() === timerContentPane && findClass('timer-presets').get_parent() === findClass('tools-page'), 'Timer must use two horizontal panes with presets outside the card');
    const wave = findClass('calc-wave');
    assert(wave instanceof Gtk.DrawingArea && wave.get_content_height() === 20 && wave.get_prev_sibling() === findClass('calc-display-pane') && wave.get_next_sibling() === findClass('calc-keypad-pane'), 'A single small native wave must separate display and keypad');
    assert(widgets.filter(w => w.has_css_class('history-row')).length === 8, 'History row pool must be bounded at 8');
    assert(!history.get_expanded(), 'History must begin collapsed');
    button('5 分').emit('clicked');
    assert(fields.map(f => f.get_text()).join(':') === '00:05:00', 'Preset must fill input only');
    assert(timerActions().length === 0, 'Preset must never mutate actual timer');

    // The service owns the actual timer; editing only prepares the next start.
    let now = 1900000000000;
    Date.now = () => now;
    const running = {ready: true, error: '', timer: {status: 'running', durationMs: 1500000, remainingMs: 60000, deadlineMs: now + 60000}};
    view.update({timer: running});
    assert(timerDisplay.get_label() === '01:00', 'Running display must use the absolute deadline and omit zero hours');
    assert(fields.map(f => f.get_text()).join(':') === '00:05:00', 'Timer snapshots must preserve edited duration');
    assert(button('暂停').get_visible() && !button('开始').get_visible(), 'Running timer must show pause only');
    button('60 分').emit('clicked');
    assert(fields.map(f => f.get_text()).join(':') === '01:00:00', '60 minute preset must normalize to an hour');
    fields[0].set_text('99'); fields[1].set_text('59'); fields[2].set_text('59');
    fields[2].emit('activate');
    assert(timerActions().length === 0, 'Active timer cannot be restarted by editing or Entry activate');
    button('暂停').emit('clicked');
    assert(timerActions().at(-1).action === 'timer-pause', 'Pause must explicitly send the pause action');
    const paused = {ready: true, error: '', timer: {status: 'paused', durationMs: 1500000, remainingMs: 59000}};
    view.update({timer: paused});
    assert(button('继续').get_visible(), 'Paused timer must show resume');
    button('继续').emit('clicked');
    assert(timerActions().at(-1).action === 'timer-resume', 'Resume must explicitly send the resume action');
    button('重置').emit('clicked');
    assert(timerActions().at(-1).action === 'timer-reset' && !('durationMs' in timerActions().at(-1)), 'Reset must not smuggle draft duration into timer');

    // Custom duration endpoints and invalid native text.
    view.update({timer: idle});
    button('开始').emit('clicked');
    assert(timerActions().at(-1).durationMs === 359999000, 'Maximum 99:59:59 must be accepted exactly');
    view.update({timer: {ready: true, error: '', timer: {status: 'idle', durationMs: 359999000, remainingMs: 359999000}}});
    assert(timerDisplay.get_label() === '99:59:59', 'Non-zero hours must keep the complete hours/minutes/seconds display');
    view.update({timer: idle});
    const afterMax = timerActions().length;
    fields.forEach(f => f.set_text('00'));
    assert(!button('开始').get_sensitive(), 'Zero duration must disable start');
    button('开始').emit('clicked');
    assert(timerActions().length === afterMax, 'Zero duration must never be sent');
    fields[2].set_text('01'); button('开始').emit('clicked');
    assert(timerActions().at(-1).durationMs === 1000, 'One second must be accepted');
    fields[1].set_text('60');
    assert(!button('开始').get_sensitive(), '60 in minutes field must be rejected');
    fields[1].set_text('00'); fields[2].set_text('a');
    assert(!button('开始').get_sensitive(), 'Non-numeric native input must be rejected');
    fields[2].set_text('01');
    view.update({timer: {...idle, ready: false}});
    assert(!button('开始').get_sensitive(), 'Unready service must disable start');
    const beforeUnready = timerActions().length;
    button('开始').emit('clicked');
    assert(timerActions().length === beforeUnready, 'Unready service cannot receive timer mutation');

    // Exact native notifications and object identities, not a simulated DOM.
    view.update({timer: running});
    let labelChanges = 0, progressChanges = 0;
    timerDisplay.connect('notify::label', () => labelChanges++);
    progress.connect('notify::fraction', () => progressChanges++);
    for (let i = 0; i < 100; i++) view.update({timer: running, calc: blankCalc});
    assert(labelChanges === 0 && progressChanges === 0, 'Identical snapshots must not invalidate display/progress');
    const timerCountBeforeLifecycle = timerActions().length;
    for (let i = 0; i < 30; i++) { now += 1000; view.update({timer: running}); }
    assert(labelChanges === 30 && progressChanges === 30, 'Each changed second must update only relevant display values');
    view.onShow(); view.onHide();
    assert(timerActions().length === timerCountBeforeLifecycle, 'Ticks and lifecycle must never mutate actual timer');
    const afterTicks = walk(view.widget);
    assert(afterTicks.length === widgets.length && afterTicks.every((w, i) => w === widgets[i]), 'No widgets may be rebuilt during updates');
    Date.now = originalDateNow;

    // Real Gtk.Entry selection, Unicode insertion/backspace and clearing.
    expression.set_text('12+34'); expression.select_region(3, 5); key('7').emit('clicked');
    assert(expression.get_text() === '12+7' && expression.get_position() === 4, 'Keypad insertion must replace native selection');
    expression.set_text('1π3'); expression.select_region(1, 2); key('⌫').emit('clicked');
    assert(expression.get_text() === '13' && expression.get_position() === 1, 'Backspace must respect Unicode selection');
    expression.set_position(expression.insert_text('π', -1, expression.get_position()));
    assert(expression.get_text() === '1π3', 'Unicode insertion must respect the caret');
    expression.set_position(2); key('⌫').emit('clicked');
    assert(expression.get_text() === '13', 'Backspace must remove a whole Unicode character');
    key('C').emit('clicked');
    assert(expression.get_text() === '', 'C must keep the original calculator-only clear behavior');

    // Async preview ids, stale replies, selection preservation and explicit commit.
    expression.set_text('2+2'); await delay(190);
    const first = calcActions().at(-1);
    assert(first.expression === '2+2' && first.commit === false && typeof first.requestId === 'string', 'Preview must send expression to backend with string id');
    expression.set_text('3+3');
    view.update({calc: {expression: '2+2', result: '999', error: '', history: [], requestId: first.requestId}});
    assert(result.get_label() !== '999' && expression.get_text() === '3+3', 'Stale reply must be ignored even before debounce fires');
    await delay(190);
    const second = calcActions().at(-1);
    assert(Number(second.requestId) > Number(first.requestId), 'Request ids must increase');
    expression.select_region(0, 2);
    const selection = JSON.stringify(expression.get_selection_bounds());
    view.update({calc: {expression: '3+3', result: '6', error: '', history: [], requestId: second.requestId}});
    assert(result.get_label() === '6', 'Matching backend reply must update result');
    assert(JSON.stringify(expression.get_selection_bounds()) === selection, 'Reply must preserve native input selection');
    buttons.find(b => b.get_tooltip_text() === '复制计算结果').emit('clicked');
    assert(copied.at(-1) === '6', 'Copy must use accepted result only');
    expression.emit('activate');
    const commit = calcActions().at(-1);
    assert(commit.commit === true && Number(commit.requestId) > Number(second.requestId), 'Enter must explicitly commit through backend');
    view.update({calc: {expression: '3+3', result: '6', error: '', history: [{expression: '3+3', result: '6'}], requestId: commit.requestId}});
    assert(widgets.filter(w => w.has_css_class('history-row') && w.get_visible()).length === 1, 'History must update pooled rows');
    history.set_expanded(true);
    assert(view.handleEscape() && !history.get_expanded() && !view.handleEscape(), 'Escape must fold history before closing the page');
    expression.set_text('2/0'); expression.emit('activate');
    const failing = calcActions().at(-1);
    view.update({calc: {expression: '2/0', result: '6', error: '不能除以零', history: [], requestId: failing.requestId}});
    assert(result.get_label() === '—' && !buttons.find(b => b.get_tooltip_text() === '复制计算结果').get_sensitive(), 'Parser errors must hide stale result and disable copying');
    expression.set_text('7+1'); view.onHide();
    const beforeHidden = calcActions().length;
    await delay(190);
    assert(calcActions().length === beforeHidden, 'Hidden page must cancel queued preview');
    view.onShow(); await delay(190);
    assert(calcActions().at(-1).expression === '7+1' && !calcActions().at(-1).commit, 'Showing must resume pending preview without committing');
    view.onHide();
    assert(timerActions().length === timerCountBeforeLifecycle, 'Calculator operations must never mutate actual timer');

    // The eleven additional checks already included in the proven 60-check run.
    const afterCalc = walk(view.widget);
    assert(afterCalc.length === widgets.length && afterCalc.every((w, i) => w === widgets[i]), 'History updates must also preserve every widget object');
    const latest = calcActions().at(-1);
    const manyRecords = Array.from({length: 18}, (_, i) => ({expression: i + '+' + i, result: String(i * 2)}));
    view.update({calc: {expression: latest.expression, result: '8', error: '', history: manyRecords, requestId: latest.requestId}});
    const visibleHistory = widgets.filter(w => w.has_css_class('history-row') && w.get_visible());
    assert(visibleHistory.length === 8, 'Oversized histories must remain bounded at the service limit');
    const afterLargeHistory = walk(view.widget);
    assert(afterLargeHistory.length === widgets.length && afterLargeHistory.every((w, i) => w === widgets[i]), 'History limit handling must not create new widgets');
    const commitsBeforeHistory = calcActions().filter(a => a.commit).length;
    history.set_expanded(true); visibleHistory[0].emit('clicked');
    assert(expression.get_text() === '0+0', 'History row must reuse its expression in the native Entry');
    assert(calcActions().filter(a => a.commit).length === commitsBeforeHistory, 'Reusing history must not automatically commit');
    view.handleEscape(); view.onHide();
    view.update({timer: {ready: true, error: '', timer: {status: 'finished', durationMs: 60000, remainingMs: 0}}});
    assert(timerDisplay.get_label() === '00:00' && progress.get_fraction() === 0, 'Finished timer must display zero without client-side mutation');
    assert(button('开始').get_visible() && !button('暂停').get_visible(), 'Finished timer must offer explicit start');
    view.update({timer: {ready: true, error: '', timer: {status: 'running', durationMs: 60000, remainingMs: 1000, deadlineMs: Date.now() - 1000}}});
    assert(timerDisplay.get_label() === '00:00' && button('暂停').get_visible(), 'Expired display must not pretend it owns the backend status transition');
    assert(timerActions().length === timerCountBeforeLifecycle, 'Expired/finished updates must issue no timer actions');
    const isolatedActions = [];
    const secondView = createTools({
        ui, send: (action, values) => isolatedActions.push({action, values}),
        toast: () => {}, copy: () => true,
    });
    views.push(secondView);
    const secondFields = walk(secondView.widget).filter(w => w.has_css_class('duration-field'));
    secondFields[1].set_text('01');
    secondView.update({timer: {ready: true, error: '', timer: {status: 'idle', durationMs: 900000, remainingMs: 900000}}});
    assert(secondFields.map(f => f.get_text()).join(':') === '00:01:00', 'First ready snapshot must preserve an already edited duration');
    secondView.onShow(); secondView.onHide();
    assert(isolatedActions.length === 0, 'Early local edits and readiness must not issue commands');
    await runTimingExtensions();
}

async function runTimingExtensions() {
    // A root is needed to exercise real Gtk focus dispatch. It is never
    // realized/presented, so these controls cannot receive desktop input.
    const css = new Gtk.CssProvider();
    css.load_from_path(GLib.build_filenamev([GLib.path_get_dirname(GLib.filename_from_uri(import.meta.url)[0]), '..', 'native', 'style.css']));
    Gtk.StyleContext.add_provider_for_display(Gdk.Display.get_default(), css, Gtk.STYLE_PROVIDER_PRIORITY_USER + 1);
    const inputActions = [];
    const inputView = createTools({ui, send: (action, values) => inputActions.push({action, ...values}), toast: () => {}, copy: () => true});
    views.push(inputView);
    const inputRoot = new Gtk.Window();
    windows.push(inputRoot);
    inputRoot.add_css_class('tide-window');
    inputRoot.set_child(inputView.widget);
    const paused = {ready: true, error: '', timer: {status: 'paused', durationMs: 1500000, remainingMs: 1499000}};
    inputView.update({timer: paused});
    const inputNodes = walk(inputView.widget);
    const inputFind = name => inputNodes.find(widget => widget.has_css_class(name));
    const fields = inputNodes.filter(widget => widget.has_css_class('duration-field'));
    const page = inputFind('tools-page');
    const minimumWidth = page.measure(Gtk.Orientation.HORIZONTAL, -1)[0];
    const naturalHeight = page.measure(Gtk.Orientation.VERTICAL, 365)[1];
    inputView.widget.allocate(365, 989, -1, null);
    const [hasBounds, actionBounds] = inputFind('stopwatch-actions').compute_bounds(inputView.widget);
    const actionBottom = actionBounds.get_y() + actionBounds.get_height();
    assert(minimumWidth <= 365 && naturalHeight <= 989 && hasBounds && actionBottom <= 989, 'Empty stopwatch page/actions must fit 365x989; measured ' + minimumWidth + 'x' + naturalHeight + ', actions bottom=' + actionBottom);
    print('native_tools_spec: empty stopwatch page minimum width=' + minimumWidth + ', natural height at 365=' + naturalHeight + ', actions bottom=' + actionBottom);
    const minute = fields[1];
    function nativeType(field, value) {
        const nativeText = walk(field).find(widget => widget instanceof Gtk.Text);
        // Gtk.Text's insert-at-cursor action itself does not remove selection;
        // mirror native IME replacement through the actual Editable interface.
        const [selected, start, end] = field.get_selection_bounds();
        if (selected) field.delete_text(start, end);
        for (const character of value) nativeText.emit('insert-at-cursor', character);
    }
    assert(fields.map(field => field.get_text()).join(':') === '00:25:00', 'Native input regression must begin with the actual padded defaults');
    minute.grab_focus_without_selecting();
    await delay(20);
    assert(JSON.stringify(minute.get_selection_bounds()) === '[true,0,2]', 'Real focus entry must select the existing two-character duration without test-side selection');
    nativeType(minute, '45');
    assert(minute.get_text() === '45' && inputActions.length === 0, 'Native insertion must replace a focused padded value without issuing timer commands');
    minute.set_position(1);
    await delay(20);
    assert(minute.get_position() === 1 && !minute.get_selection_bounds()[0], 'Later caret edits in an already focused field must not be forced into select-all');
    minute.select_region(1, 2);
    inputView.update({timer: paused});
    await delay(20);
    assert(minute.get_text() === '45' && JSON.stringify(minute.get_selection_bounds()) === '[true,1,2]', 'Existing partial selection and edited draft must survive old timer snapshots');
    const apply = inputFind('timer-apply-duration');
    const confirmation = inputFind('timer-apply-confirmation');
    const confirm = inputFind('timer-confirm-start');
    assert(apply.get_visible() && apply.get_sensitive(), 'An active timer must offer an explicit action for the changed duration');
    apply.emit('clicked');
    assert(confirmation.get_reveal_child() && inputActions.length === 0, 'Applying a changed active duration must ask for confirmation before sending');
    inputView.update({timer: {...paused, timer: {...paused.timer, remainingMs: 1498000}}});
    assert(confirmation.get_reveal_child() && inputActions.length === 0, 'Paused remaining-time updates alone must not revoke a replacement confirmation');
    inputFind('timer-cancel-start').emit('clicked');
    assert(!confirmation.get_reveal_child() && inputActions.length === 0, 'Cancel must preserve the current timer');
    apply.emit('clicked');
    minute.select_region(0, -1);
    nativeType(minute, '30');
    assert(!confirmation.get_reveal_child() && inputActions.length === 0, 'Editing the draft must invalidate a stale replacement confirmation');
    apply.emit('clicked');
    const runningTimer = {ready: true, error: '', timer: {status: 'running', durationMs: 1500000, remainingMs: 1499000, deadlineMs: Date.now() + 1499000}};
    inputView.update({timer: runningTimer});
    assert(!confirmation.get_reveal_child() && inputActions.length === 0, 'A changed active timer identity must invalidate the confirmation');
    apply.emit('clicked');
    inputView.update({timer: {...runningTimer, timer: {...runningTimer.timer, remainingMs: 1498000}}});
    assert(confirmation.get_reveal_child() && inputActions.length === 0, 'Running second ticks with unchanged deadline must keep the confirmation open');
    inputView.onHide();
    assert(!confirmation.get_reveal_child() && inputActions.length === 0, 'Hiding the page must cancel replacement without resetting the timer');
    inputView.onShow();
    inputView.update({timer: paused});
    apply.emit('clicked');
    confirm.emit('clicked');
    assert(inputActions.length === 1 && inputActions[0].action === 'timer-start' && inputActions[0].durationMs === 1800000, 'Only confirming the current draft may replace the timer');
    confirm.emit('clicked');
    assert(inputActions.length === 1, 'A consumed confirmation must not start the timer twice');
    assert(!inputRoot.get_visible() && !inputRoot.get_realized(), 'Native focus tests must never create a visible or realized test window');
    inputView.onHide();

    const actions = [];
    const stopwatchView = createTools({ui, send: (action, values) => actions.push({action, ...values}), toast: () => {}, copy: () => true});
    views.push(stopwatchView);
    const nodes = walk(stopwatchView.widget);
    const find = name => nodes.find(widget => widget.has_css_class(name));
    const clock = find('stopwatch-display');
    const history = find('stopwatch-history');
    const state = model => ({ready: true, error: '', stopwatch: {version: 1, status: 'idle', elapsedMs: 0, laps: [], ...model}});
    assert(!find('stopwatch-start').get_sensitive(), 'Stopwatch controls must wait for service readiness');
    stopwatchView.update({stopwatch: state({})});
    stopwatchView.onShow(); stopwatchView.onHide();
    assert(actions.length === 0 && clock.get_label() === '00:00.00', 'Stopwatch construction, snapshots and lifecycle must issue no commands');
    assert(!history.get_visible(), 'An empty stopwatch must not occupy space with an empty lap expander');
    find('stopwatch-start').emit('clicked');
    assert(actions.at(-1).action === 'stopwatch-start', 'Only explicit stopwatch Start may send start');
    let now = 1900000000000;
    Date.now = () => now;
    const running = state({status: 'running', elapsedMs: 2345, startedAtMs: now - 1000});
    stopwatchView.update({stopwatch: running});
    assert(clock.get_label() === '00:03.34', 'Running stopwatch must add the absolute anchor delta to the saved elapsed base');
    let clockChanges = 0;
    clock.connect('notify::label', () => clockChanges++);
    now += 500;
    await delay(120);
    assert(clockChanges === 0 && clock.get_label() === '00:03.34', 'A hidden running stopwatch must not have a local refresh source');
    stopwatchView.onShow();
    assert(clock.get_label() === '00:03.84', 'Showing must catch up to the absolute anchor without starting the backend');
    const epoch = now, wall = originalDateNow();
    Date.now = () => epoch + originalDateNow() - wall;
    let timerChanges = 0, calcChanges = 0;
    find('timer-display').connect('notify::label', () => timerChanges++);
    find('result-display').connect('notify::label', () => calcChanges++);
    clockChanges = 0;
    for (let i = 0; i < 20; i++) stopwatchView.update({stopwatch: running});
    const refreshStarted = GLib.get_monotonic_time();
    await delay(260);
    const refreshElapsed = Math.round((GLib.get_monotonic_time() - refreshStarted) / 1000);
    print('native_tools_spec: stopwatch label changes=' + clockChanges + ' over ' + refreshElapsed + 'ms; countdown=' + timerChanges + ', calculator=' + calcChanges);
    assert(clockChanges >= 3 && clockChanges <= 7, 'Visible running stopwatch must refresh roughly at 20Hz without duplicate sources');
    assert(timerChanges === 0 && calcChanges === 0, 'Stopwatch ticks must update only its clock, not the calculator or countdown');
    const beforeHide = clock.get_label();
    clockChanges = 0;
    stopwatchView.onHide();
    await delay(140);
    assert(clockChanges === 0 && clock.get_label() === beforeHide && actions.length === 1, 'Hide must stop local updates without sending stopwatch-pause');
    stopwatchView.onShow();
    assert(clock.get_label() !== beforeHide && actions.length === 1, 'Reopening must catch up while leaving the running backend untouched');
    stopwatchView.update({stopwatch: state({status: 'paused', elapsedMs: 12345})});
    assert(clock.get_label() === '00:12.34' && find('stopwatch-resume').get_visible(), 'Paused stopwatch must show the stored elapsed value and Resume');
    clockChanges = 0;
    await delay(120);
    assert(clockChanges === 0, 'Paused stopwatch must cancel its local refresh source');
    find('stopwatch-resume').emit('clicked');
    assert(actions.at(-1).action === 'stopwatch-start', 'Resume must use the locked stopwatch-start contract, not a separate resume action');
    const laps = Array.from({length: 11}, (_, i) => ({index: i + 1, totalMs: (i + 1) * 1000, splitMs: 1000}));
    stopwatchView.update({stopwatch: state({status: 'running', elapsedMs: 0, startedAtMs: Date.now() - 20000, laps})});
    const rows = nodes.filter(widget => widget.has_css_class('stopwatch-lap-row'));
    assert(history.get_visible() && rows.length === 8 && rows.every(row => row.get_visible()), 'Stopwatch lap history must reuse a fixed pool of eight recent rows');
    const rowLabels = row => walk(row).filter(widget => widget instanceof Gtk.Label).map(label => label.get_label());
    assert(rowLabels(rows[0])[0] === '#11' && rowLabels(rows.at(-1))[0] === '#04' && laps[0].index === 1 && laps.length === 11, 'Recent-first lap display must not reorder or truncate the backend records');
    history.set_expanded(true);
    assert(stopwatchView.handleEscape() && !history.get_expanded(), 'Escape must collapse stopwatch laps without stopping any timer');
    find('stopwatch-lap').emit('clicked');
    assert(actions.at(-1).action === 'stopwatch-lap', 'Only explicit Lap may record a split');
    find('stopwatch-pause').emit('clicked');
    assert(actions.at(-1).action === 'stopwatch-pause', 'Only explicit Pause may pause the stopwatch');
    const fullLaps = Array.from({length: 100}, (_, i) => ({index: i + 1, totalMs: (i + 1) * 1000, splitMs: 1000}));
    stopwatchView.update({stopwatch: state({status: 'running', elapsedMs: 0, startedAtMs: Date.now() - 120000, laps: fullLaps})});
    const beforeLimit = actions.length;
    find('stopwatch-lap').emit('clicked');
    assert(!find('stopwatch-lap').get_sensitive() && actions.length === beforeLimit && fullLaps.length === 100, 'The 100-lap limit must not drop old records or send another lap');
    find('stopwatch-reset').emit('clicked');
    assert(actions.at(-1).action === 'stopwatch-reset', 'Only explicit Reset may clear the stopwatch');
    stopwatchView.update({stopwatch: state({})});
    assert(clock.get_label() === '00:00.00' && !history.get_visible() && rows.every(row => !row.get_visible()), 'Reset snapshot must clear the displayed laps without rebuilding rows');
    const after = walk(stopwatchView.widget);
    assert(after.length === nodes.length && after.every((widget, index) => widget === nodes[index]), 'All stopwatch controls and history rows must retain object identity');
    stopwatchView.update({stopwatch: {...state({}), ready: false, error: '测试服务未就绪'}});
    find('stopwatch-start').emit('clicked');
    assert(find('stopwatch-error').get_visible() && !find('stopwatch-start').get_sensitive(), 'Unready stopwatch must display service errors and block start');
    assert(actions.map(action => action.action).join(',') === 'stopwatch-start,stopwatch-start,stopwatch-lap,stopwatch-pause,stopwatch-reset', 'All backend stopwatch commands must correspond exactly to explicit tested clicks');
    stopwatchView.onHide();

    // API32's JSON encoder emits an empty Lua laps table as {}, not [].
    // Keep the parsed wire shape intact so this catches strict-array regressions.
    const wireCommands = actions.length;
    Date.now = () => 1900001000000;
    const idleWire = JSON.parse('{"ready":true,"error":"","stopwatch":{"version":1,"status":"idle","elapsedMs":0,"laps":{}}}');
    stopwatchView.update({stopwatch: idleWire});
    assert(find('stopwatch-start').get_visible() && find('stopwatch-start').get_sensitive()
        && !find('stopwatch-error').get_visible() && !history.get_visible() && clock.get_label() === '00:00.00',
    'Actual idle wire laps:{} must normalize to an empty list and remain ready');
    const runningWire = JSON.parse('{"ready":true,"error":"","stopwatch":{"version":1,"status":"running","elapsedMs":2500,"startedAtMs":1900000999000,"laps":{}}}');
    stopwatchView.update({stopwatch: runningWire});
    assert(find('stopwatch-pause').get_visible() && find('stopwatch-pause').get_sensitive()
        && find('stopwatch-lap').get_sensitive() && !find('stopwatch-error').get_visible()
        && !history.get_visible() && clock.get_label() === '00:03.50',
    'Actual running wire laps:{} must preserve the anchor and usable controls');
    const invalidWire = JSON.parse('{"ready":true,"error":"","stopwatch":{"version":1,"status":"running","elapsedMs":2500,"startedAtMs":1900000999000,"laps":{"1":{"index":1,"totalMs":1000,"splitMs":1000}}}}');
    stopwatchView.update({stopwatch: invalidWire});
    assert(find('stopwatch-error').get_visible() && !find('stopwatch-start').get_sensitive()
        && !find('stopwatch-pause').get_sensitive() && !find('stopwatch-lap').get_sensitive()
        && actions.length === wireCommands,
    'Non-empty object laps must stay invalid; wire normalization must issue no commands');
    Date.now = originalDateNow;

    // Plugin settings drive the preset row without rebuilding any widget.
    const presetView = createTools({ui, send: () => true, toast: () => {}, copy: () => true});
    views.push(presetView);
    const idleTimer = {ready: true, error: '', timer: {version: 1, status: 'idle', durationMs: 1500000, remainingMs: 1500000}};
    const noCalc = {expression: '', result: '0', error: '', history: [], requestId: ''};
    const presetButtons = () => walk(presetView.widget).filter(widget => widget.has_css_class('preset-button'));
    presetView.update({calc: noCalc, timer: idleTimer, config: {timerPresets: [3, 9]}});
    const configured = presetButtons().filter(button => button.get_visible());
    assert(configured.length === 2 && configured[0].get_child().get_label() === '3 分'
        && configured[1].get_child().get_label() === '9 分',
    'Configured countdown presets must be applied by relabelling the existing slots');
    const identity = presetButtons();
    presetView.update({calc: noCalc, timer: idleTimer, config: {timerPresets: []}});
    const fallback = presetButtons().filter(button => button.get_visible());
    assert(fallback.length === 4 && fallback.map(button => button.get_child().get_label()).join(',') === '5 分,15 分,25 分,60 分',
    'An empty preset list must fall back to the approved four lengths');
    assert(presetButtons().every((button, index) => button === identity[index]),
    'Preset slots must keep their widget identity across updates');
}

// Bound the GLib loop. Exit outside async callbacks, which otherwise can leave
// a GLib.MainLoop running after an assertion failure has already been reported.
let deadlineSource = GLib.timeout_add(GLib.PRIORITY_DEFAULT, TIMEOUT_MS, () => {
    deadlineSource = 0;
    failure = new Error('Native tools fixture exceeded ' + TIMEOUT_MS + ' ms');
    loop.quit();
    return GLib.SOURCE_REMOVE;
});
runSuite().then(() => {
    if (checks !== EXPECTED_ASSERTIONS)
        throw new Error('Expected ' + EXPECTED_ASSERTIONS + ' assertions, ran ' + checks);
    completed = true;
    loop.quit();
}).catch(error => {
    failure = error;
    loop.quit();
});
loop.run();

Date.now = originalDateNow;
if (deadlineSource) GLib.source_remove(deadlineSource);
for (const view of views) {
    try { view.onHide(); }
    catch (error) { if (!failure) failure = error; }
}
for (const window of windows) window.destroy();
for (const source of pendingDelays) GLib.source_remove(source);
pendingDelays.clear();
if (failure || !completed) {
    printerr('native_tools_spec: FAIL after ' + checks + ' assertions: ' + (failure?.message || 'suite did not finish'));
    if (failure?.stack) printerr(failure.stack);
    System.exit(1);
}
print('native_tools_spec: ' + checks + ' assertions passed; no real timer, clipboard, window or system actions');
