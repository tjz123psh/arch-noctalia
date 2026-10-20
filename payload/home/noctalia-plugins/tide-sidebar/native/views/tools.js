import Gtk from 'gi://Gtk?version=4.0';
import GLib from 'gi://GLib';
import Pango from 'gi://Pango';

const MAX_DURATION_MS = (99 * 3600 + 59 * 60 + 59) * 1000;
const HISTORY_LIMIT = 8; // The service keeps the latest eight committed calculations.
const PREVIEW_DELAY_MS = 160;
const PRESET_SLOTS = 6;
const TIMER_STATUSES = new Set(['idle', 'running', 'paused', 'finished']);
const STOPWATCH_STATUSES = new Set(['idle', 'running', 'paused']);
const STOPWATCH_REFRESH_MS = 50;
const VISIBLE_STOPWATCH_LAPS = 8;
const MAX_STOPWATCH_LAPS = 100;

function setLabel(widget, value) {
    const text = String(value ?? '');
    if (widget.get_label() !== text) widget.set_label(text);
}
function setVisible(widget, value) {
    if (widget.get_visible() !== value) widget.set_visible(value);
}
function setSensitive(widget, value) {
    if (widget.get_sensitive() !== value) widget.set_sensitive(value);
}
function setClass(widget, name, enabled) {
    if (widget.has_css_class(name) !== enabled) {
        if (enabled) widget.add_css_class(name);
        else widget.remove_css_class(name);
    }
}
function durationParts(durationMs) {
    const seconds = Math.max(0, Math.ceil(durationMs / 1000));
    return [Math.floor(seconds / 3600), Math.floor(seconds / 60) % 60, seconds % 60];
}
function clockText(durationMs) {
    const parts = durationParts(durationMs);
    return (parts[0] > 0 ? parts : parts.slice(1))
        .map(value => String(value).padStart(2, '0')).join(':');
}

function stopwatchText(elapsedMs) {
    const centiseconds = Math.max(0, Math.floor(elapsedMs / 10));
    const seconds = Math.floor(centiseconds / 100);
    const hours = Math.floor(seconds / 3600);
    const parts = [Math.floor(seconds / 60) % 60, seconds % 60];
    if (hours > 0) parts.unshift(hours);
    return parts.map(value => String(value).padStart(2, '0')).join(':')
        + '.' + String(centiseconds % 100).padStart(2, '0');
}

export function createTools(ctx) {
    const {ui} = ctx;
    const page = ui.box(Gtk.Orientation.VERTICAL, 20, ['tools-page', 'scroll-gutter']);
    page.set_valign(Gtk.Align.FILL);
    page.set_hexpand(true);
    page.set_vexpand(true);
    const widget = new Gtk.ScrolledWindow({
        hscrollbar_policy: Gtk.PolicyType.NEVER,
        vscrollbar_policy: Gtk.PolicyType.AUTOMATIC,
        hexpand: true, vexpand: true,
    });
    widget.add_css_class('list-scroll');
    widget.set_child(page);

    // Build the calculator and its history rows once. Snapshots only change text/state.
    const calculator = ui.card(['tools-card']);
    calculator.set_spacing(0);
    const calcDisplayPane = ui.box(Gtk.Orientation.VERTICAL, 4, ['calc-display-pane']);
    calculator.append(calcDisplayPane);
    const calcHeader = ui.box(Gtk.Orientation.HORIZONTAL, 6);
    const calcTitle = ui.label('计算器', ['section-title']);
    calcTitle.set_hexpand(true);
    calcHeader.append(calcTitle);
    let copyValue = '0';
    const copyButton = ui.iconButton('copy', () => {
        if (copyValue === null) return;
        if (ctx.copy(copyValue) !== false) ctx.toast('结果已复制');
    }, '复制计算结果');
    calcHeader.append(copyButton);
    calcDisplayPane.append(calcHeader);

    const expression = new Gtk.Entry({
        placeholder_text: '输入算式，如 (12 + 3) × 4',
        hexpand: true, max_length: 1024, width_chars: 10,
    });
    expression.add_css_class('calc-expression');
    expression.set_tooltip_text('支持 + − × ÷、括号、幂 ^、π、e、Ans、sqrt()、abs()；% 表示 ÷100；Enter 计算');
    calcDisplayPane.append(expression);
    const result = ui.label('0', ['result-display']);
    result.set_xalign(1);
    result.set_selectable(true);
    result.set_ellipsize(Pango.EllipsizeMode.MIDDLE);
    calcDisplayPane.append(result);
    const calcMessage = ui.label('', ['caption']);
    calcMessage.set_wrap(true);
    calcMessage.set_ellipsize(Pango.EllipsizeMode.NONE);
    calcMessage.set_visible(false);
    calcDisplayPane.append(calcMessage);
    const calcWave = ui.waveBand('#F1D68B', 20);
    calcWave.add_css_class('calc-wave');
    calculator.append(calcWave);

    let requestSequence = 0;
    let currentRequest = null;
    let previewSource = 0;
    let previewQueued = false;
    let waitingForResult = false;
    let syncingExpression = false;
    let expressionEdited = false;
    let shownOnce = false;
    let historySignature = '';

    function cancelPreview() {
        if (previewSource) GLib.source_remove(previewSource);
        previewSource = 0;
    }
    function pendingResult() {
        copyValue = null;
        setSensitive(copyButton, false);
        setLabel(result, expression.get_text().trim() ? '…' : '0');
        result.set_tooltip_text(null);
        setLabel(calcMessage, '');
        setVisible(calcMessage, false);
        setClass(calcMessage, 'status-error', false);
    }
    function newRequest(commit) {
        // Reserve the id immediately, before debounce: an older reply must not
        // become visible after the user has already edited the next expression.
        currentRequest = {
            expression: expression.get_text(), commit,
            requestId: String(++requestSequence),
        };
        waitingForResult = true;
        pendingResult();
        return currentRequest;
    }
    function sendRequest(request) {
        if (request !== currentRequest) return;
        previewQueued = false;
        ctx.send('calc-evaluate', request);
    }
    function schedulePreview() {
        cancelPreview();
        const request = currentRequest;
        if (!previewQueued || !request) return;
        previewSource = GLib.timeout_add(GLib.PRIORITY_DEFAULT, PREVIEW_DELAY_MS, () => {
            previewSource = 0;
            sendRequest(request);
            return GLib.SOURCE_REMOVE;
        });
    }
    function evaluate() {
        if (waitingForResult && currentRequest?.commit && currentRequest.expression === expression.get_text()) return;
        cancelPreview();
        previewQueued = false;
        sendRequest(newRequest(true));
        calcWave.pulse();
    }
    expression.connect('changed', () => {
        if (syncingExpression) return;
        expressionEdited = true;
        cancelPreview();
        newRequest(false);
        previewQueued = true;
        schedulePreview();
    });
    // Let Gtk.Entry/IME own keyboard editing; its native activation commits.
    expression.connect('activate', evaluate);

    function focusExpression() {
        if (expression.get_root()) expression.grab_focus_without_selecting();
    }
    function insertToken(token) {
        const [selected, start, end] = expression.get_selection_bounds();
        let position = selected ? start : expression.get_position();
        if (selected) expression.delete_text(start, end);
        position = expression.insert_text(token, -1, position);
        expression.set_position(position);
        focusExpression();
    }
    function eraseCharacter() {
        const [selected, start, end] = expression.get_selection_bounds();
        const position = expression.get_position();
        if (selected) {
            expression.delete_text(start, end);
            expression.set_position(start);
        } else if (position > 0) {
            expression.delete_text(position - 1, position);
            expression.set_position(position - 1);
        }
        focusExpression();
    }
    const keypadPane = ui.box(Gtk.Orientation.HORIZONTAL, 12, ['calc-keypad-pane']);
    const numberKeypad = new Gtk.Grid({column_homogeneous: true, row_homogeneous: true, hexpand: true});
    numberKeypad.add_css_class('number-keypad');
    const operatorColumn = ui.box(Gtk.Orientation.VERTICAL, 0, ['operator-column']);
    operatorColumn.set_hexpand(false);
    operatorColumn.set_size_request(58, -1);
    operatorColumn.set_homogeneous(true);
    const numberKeys = [
        ['C', null, '清空算式'], ['(', '(', '左括号'], [')', ')', '右括号'],
        ['7', '7'], ['8', '8'], ['9', '9'],
        ['4', '4'], ['5', '5'], ['6', '6'],
        ['1', '1'], ['2', '2'], ['3', '3'],
        ['0', '0'], ['.', '.'], ['%', '%', '百分比（除以 100）'],
        ['Ans', 'Ans', '上次确认的计算结果'], ['√', 'sqrt(', '平方根'], ['^', '^', '乘方'],
    ];
    const operatorKeys = [
        ['⌫', null, '退格'], ['÷', '÷'], ['×', '×'], ['−', '−'], ['+', '+'], ['=', null, '计算并记入历史'],
    ];
    function makeKey([text, token, tooltip], isOperator) {
        const classes = ['key-button', isOperator ? 'operator-key' : 'number-key'];
        if (text === '=') classes.push('equals-button', 'primary-button', 'primary');
        if (text === 'Ans') classes.push('key-memory');
        const button = ui.button(text, null, () => {
            if (text === '=') evaluate();
            else if (text === '⌫') eraseCharacter();
            else if (text === 'C') {
                expression.set_text('');
                focusExpression();
            } else insertToken(token);
        }, classes);
        button.set_hexpand(!isOperator);
        button.set_focus_on_click(false);
        if (tooltip) button.set_tooltip_text(tooltip);
        return button;
    }
    numberKeys.forEach((key, index) => numberKeypad.attach(makeKey(key, false), index % 3, Math.floor(index / 3), 1, 1));
    operatorKeys.forEach(key => operatorColumn.append(makeKey(key, true)));
    keypadPane.append(numberKeypad);
    keypadPane.append(operatorColumn);
    calculator.append(keypadPane);

    const history = new Gtk.Expander({expanded: false});
    const historyHeading = ui.label('历史记录', ['caption']);
    history.set_label_widget(historyHeading);
    history.add_css_class('tools-history');
    history.add_css_class('calc-history-pane');
    const historyScroll = new Gtk.ScrolledWindow({
        hscrollbar_policy: Gtk.PolicyType.NEVER,
        vscrollbar_policy: Gtk.PolicyType.AUTOMATIC,
        propagate_natural_height: true, max_content_height: 158,
    });
    historyScroll.add_css_class('list-scroll');
    const historyList = ui.box(Gtk.Orientation.VERTICAL, 4);
    const emptyHistory = ui.label('暂无计算记录', ['caption']);
    historyList.append(emptyHistory);
    const historyRows = Array.from({length: HISTORY_LIMIT}, () => {
        const row = {value: null};
        row.button = ui.button('', null, () => {
            if (!row.value) return;
            expression.set_text(row.value.expression);
            expression.set_position(-1);
            focusExpression();
        }, ['history-row']);
        const body = ui.box(Gtk.Orientation.VERTICAL, 1);
        row.expression = ui.label('', ['caption']);
        row.expression.set_ellipsize(Pango.EllipsizeMode.MIDDLE);
        row.result = ui.label('');
        row.result.set_xalign(1);
        row.result.set_ellipsize(Pango.EllipsizeMode.MIDDLE);
        body.append(row.expression);
        body.append(row.result);
        row.button.set_child(body);
        row.button.set_visible(false);
        historyList.append(row.button);
        return row;
    });
    historyScroll.set_child(historyList);
    history.set_child(historyScroll);
    calculator.append(history);
    page.append(calculator);

    function updateCalculation(calc) {
        if (!calc || typeof calc !== 'object') return;
        const replyId = String(calc.requestId ?? '');
        const replyExpression = String(calc.expression ?? '');
        if (currentRequest && (replyId !== currentRequest.requestId || replyExpression !== currentRequest.expression)) return;
        if (!expressionEdited && !currentRequest) {
            // Initial service snapshot only; never replace an expression being edited.
            syncingExpression = true;
            if (expression.get_text() !== replyExpression) {
                expression.set_text(replyExpression);
                expression.set_position(-1);
            }
            syncingExpression = false;
            const existingSequence = Number(replyId);
            if (Number.isSafeInteger(existingSequence) && existingSequence > requestSequence) requestSequence = existingSequence;
        }
        waitingForResult = false;
        const error = String(calc.error ?? '');
        copyValue = error ? null : String(calc.result ?? '0');
        setLabel(result, error ? '—' : copyValue);
        if (result.get_tooltip_text() !== copyValue) result.set_tooltip_text(copyValue);
        setSensitive(copyButton, !error);
        setLabel(calcMessage, error);
        setVisible(calcMessage, !!error);
        setClass(calcMessage, 'status-error', !!error);

        const records = (Array.isArray(calc.history) ? calc.history : []).slice(0, HISTORY_LIMIT)
            .filter(item => item && typeof item.expression === 'string' && typeof item.result === 'string')
            .map(item => ({expression: item.expression, result: item.result}));
        const signature = JSON.stringify(records);
        if (signature === historySignature) return;
        historySignature = signature;
        setLabel(historyHeading, records.length ? '历史记录 · ' + records.length : '历史记录');
        setVisible(emptyHistory, records.length === 0);
        historyRows.forEach((row, index) => {
            row.value = records[index] || null;
            setVisible(row.button, !!row.value);
            if (!row.value) return;
            setLabel(row.expression, row.value.expression);
            setLabel(row.result, '= ' + row.value.result);
            const tooltip = row.value.expression + ' = ' + row.value.result + ' · 点击复用算式';
            if (row.button.get_tooltip_text() !== tooltip) row.button.set_tooltip_text(tooltip);
        });
    }

    // This is only a view of the service-owned timer. There is no local ticking
    // source: the backend publishes once per changed second, even when hidden.
    const timerCard = ui.box(Gtk.Orientation.HORIZONTAL, 0, ['card', 'timer-card']);
    const timerLabelPane = ui.box(Gtk.Orientation.VERTICAL, 8, ['timer-label-pane']);
    const timerContentPane = ui.box(Gtk.Orientation.VERTICAL, 8, ['timer-content-pane']);
    timerContentPane.set_hexpand(true);
    const timerTitle = ui.label('倒计时', ['section-title', 'timer-title']);
    timerTitle.set_ellipsize(Pango.EllipsizeMode.NONE);
    const timerStatus = ui.label('加载中', ['caption', 'timer-status']);
    timerLabelPane.append(timerTitle);
    timerLabelPane.append(new Gtk.Box({vexpand: true}));
    timerLabelPane.append(timerStatus);
    timerCard.append(timerLabelPane);
    timerCard.append(timerContentPane);
    const timerDisplay = ui.label('25:00', ['timer-display']);
    timerDisplay.set_xalign(0.5);
    timerContentPane.append(timerDisplay);
    const progress = new Gtk.ProgressBar({fraction: 1, hexpand: true, show_text: false});
    progress.add_css_class('timer-progress');
    timerContentPane.append(progress);
    let lastFraction = 1;
    let timerReady = false;
    let timerModel = {status: 'idle', durationMs: 1500000, remainingMs: 1500000};
    let timerLoaded = false;
    let durationEdited = false;
    let settingDuration = false;
    let timerErrorText = '';
    const durationSelectionSources = new Map();
    const durationControllers = [];

    function cancelDurationSelection(field) {
        const source = durationSelectionSources.get(field);
        if (source) GLib.source_remove(source);
        durationSelectionSources.delete(field);
    }
    function selectDurationAfterInteraction(field) {
        if (durationSelectionSources.has(field)) return;
        const source = GLib.idle_add(GLib.PRIORITY_DEFAULT_IDLE, () => {
            durationSelectionSources.delete(field);
            const focused = field.get_root()?.get_focus();
            // Run after native pointer caret placement, without swallowing input
            // events or replacing a selection the user has dragged themselves.
            if ((focused === field || focused?.is_ancestor(field)) && !field.get_selection_bounds()[0])
                field.select_region(0, -1);
            return GLib.SOURCE_REMOVE;
        });
        durationSelectionSources.set(field, source);
    }

    function bindDurationController(binding) {
        if (binding.enter) return;
        const {field, focus} = binding;
        // Once per focus entry only: later clicks, caret moves and dragged
        // selections inside the same field remain entirely native.
        binding.enter = focus.connect('enter', () => selectDurationAfterInteraction(field));
        binding.leave = focus.connect('leave', () => cancelDurationSelection(field));
    }
    function unbindDurationControllers() {
        for (const binding of durationControllers) {
            if (!binding.enter) continue;
            binding.focus.disconnect(binding.enter);
            binding.focus.disconnect(binding.leave);
            binding.enter = binding.leave = 0;
        }
    }

    const durationRow = ui.box(Gtk.Orientation.HORIZONTAL, 8, ['timer-duration-row']);
    durationRow.set_homogeneous(true);
    const fields = ['时', '分', '秒'].map((unit, index) => {
        const group = ui.box(Gtk.Orientation.VERTICAL, 3);
        const field = new Gtk.Entry({
            text: index === 1 ? '25' : '00',
            max_length: 2, width_chars: 2, max_width_chars: 2,
            xalign: 0.5, hexpand: true, input_purpose: Gtk.InputPurpose.DIGITS,
        });
        field.add_css_class('duration-field');
        field.set_tooltip_text(['小时，0 至 99', '分钟，0 至 59', '秒，0 至 59'][index] + '；点击后可直接输入替换');
        const focus = new Gtk.EventControllerFocus();
        field.add_controller(focus);
        const binding = {field, focus, enter: 0, leave: 0};
        durationControllers.push(binding);
        bindDurationController(binding);
        const unitLabel = ui.label(unit, ['caption']);
        unitLabel.set_xalign(0.5);
        unitLabel.set_mnemonic_widget(field);
        group.append(field);
        group.append(unitLabel);
        durationRow.append(group);
        return field;
    });
    timerContentPane.append(durationRow);
    const presets = ui.box(Gtk.Orientation.HORIZONTAL, 5, ['timer-presets']);
    presets.set_homogeneous(true);
    // Fixed pool: the plugin setting can list 1..PRESET_SLOTS lengths, so slots are
    // relabelled in place and every widget keeps its identity across updates.
    const presetButtons = Array.from({length: PRESET_SLOTS}, () => {
        const entry = {durationMs: 0, button: null, label: null};
        entry.button = ui.button('', null, () => { if (entry.durationMs > 0) setDuration(entry.durationMs, true); }, ['preset-button']);
        // An owned label keeps the button's child identity stable: Gtk.Button.set_label()
        // would swap the internal label widget on every update.
        entry.label = ui.label('');
        entry.button.set_child(entry.label);
        entry.button.set_visible(false);
        entry.button.set_hexpand(true);
        presets.append(entry.button);
        return entry;
    });
    function applyPresets(list) {
        const wanted = (Array.isArray(list) ? list : [])
            .map(value => Number(value))
            .filter(value => Number.isFinite(value) && value >= 1)
            .slice(0, PRESET_SLOTS);
        const minutes = wanted.length ? wanted : [5, 15, 25, 60];
        presetButtons.forEach((entry, index) => {
            const valid = index < minutes.length;
            const durationMs = valid ? Math.round(minutes[index]) * 60000 : 0;
            if (entry.durationMs !== durationMs) entry.durationMs = durationMs;
            if (entry.button.get_visible() !== valid) entry.button.set_visible(valid);
            if (!valid) return;
            const text = Math.round(minutes[index]) + ' 分';
            if (entry.label.get_label() !== text) entry.label.set_label(text);
            const tooltip = '填入 ' + text + '，不会启动或改变当前倒计时';
            if (entry.button.get_tooltip_text() !== tooltip) entry.button.set_tooltip_text(tooltip);
        });
        updateDurationForm();
    }
    const timerActions = ui.box(Gtk.Orientation.HORIZONTAL, 7, ['timer-actions']);
    const startButton = ui.button('开始', 'player-play', startTimer, ['primary-button']);
    const pauseButton = ui.button('暂停', 'player-pause', () => {
        cancelDurationReplacement();
        if (timerReady && timerModel.status === 'running') ctx.send('timer-pause', {});
    }, ['primary-button']);
    const resumeButton = ui.button('继续', 'player-play', () => {
        cancelDurationReplacement();
        if (timerReady && timerModel.status === 'paused') ctx.send('timer-resume', {});
    }, ['primary-button']);
    const resetButton = ui.button('重置', 'rotate-clockwise', () => {
        cancelDurationReplacement();
        if (timerReady && timerModel.status !== 'idle') ctx.send('timer-reset', {});
    }, ['timer-reset', 'soft-button']);
    resetButton.set_tooltip_text('停止当前倒计时，恢复它原来的设定时长');
    for (const button of [startButton, pauseButton, resumeButton, resetButton]) {
        button.set_hexpand(true);
        timerActions.append(button);
    }
    timerContentPane.append(new Gtk.Box({vexpand: true}));
    timerContentPane.append(timerActions);
    let pendingDuration = null;
    function timerIdentity() {
        return [timerModel.status, timerModel.durationMs, timerModel.deadlineMs ?? ''].join(':');
    }
    function cancelDurationReplacement() {
        pendingDuration = null;
        durationConfirmation.set_reveal_child(false);
        if (!durationConfirmation.get_child_revealed()) durationConfirmation.set_visible(false);
    }
    const applyDurationButton = ui.button('按新时长开始', 'player-play', () => {
        if (!timerReady || !['running', 'paused'].includes(timerModel.status)) return;
        const draft = readDuration();
        if (draft.error || draft.durationMs === timerModel.durationMs) return;
        pendingDuration = {durationMs: draft.durationMs, timer: timerIdentity()};
        setLabel(durationConfirmationText, '替换当前倒计时，从 ' + clockText(draft.durationMs) + ' 重新开始？');
        durationConfirmation.set_visible(true);
        durationConfirmation.set_reveal_child(true);
    }, ['soft-button', 'timer-apply-duration']);
    applyDurationButton.set_visible(false);
    applyDurationButton.set_tooltip_text('确认后才会替换当前倒计时；只改输入不会改变正在运行或暂停的计时');
    timerContentPane.append(applyDurationButton);
    const durationConfirmation = new Gtk.Revealer({transition_type: Gtk.RevealerTransitionType.SLIDE_DOWN, transition_duration: 160});
    durationConfirmation.add_css_class('timer-apply-confirmation');
    durationConfirmation.set_visible(false);
    durationConfirmation.connect('notify::child-revealed', () => {
        if (!durationConfirmation.get_reveal_child() && !durationConfirmation.get_child_revealed())
            durationConfirmation.set_visible(false);
    });
    const confirmationBody = ui.box(Gtk.Orientation.VERTICAL, 6, ['inline-notice']);
    const durationConfirmationText = ui.label('', ['caption']);
    durationConfirmationText.set_wrap(true);
    durationConfirmationText.set_ellipsize(Pango.EllipsizeMode.NONE);
    confirmationBody.append(durationConfirmationText);
    const confirmationActions = ui.box(Gtk.Orientation.HORIZONTAL, 6);
    confirmationActions.append(ui.button('确认开始', 'player-play', () => {
        const requested = pendingDuration;
        const draft = readDuration();
        cancelDurationReplacement();
        if (!requested || !timerReady || requested.timer !== timerIdentity() || draft.error
            || requested.durationMs !== draft.durationMs || !['running', 'paused'].includes(timerModel.status)) return;
        setDuration(requested.durationMs, true);
        ctx.send('timer-start', {durationMs: requested.durationMs});
    }, ['primary-button', 'timer-confirm-start']));
    confirmationActions.append(ui.button('取消', null, cancelDurationReplacement, ['soft-button', 'timer-cancel-start']));
    confirmationBody.append(confirmationActions);
    durationConfirmation.set_child(confirmationBody);
    timerContentPane.append(durationConfirmation);
    const durationHint = ui.label('', ['caption']);
    durationHint.set_wrap(true);
    durationHint.set_ellipsize(Pango.EllipsizeMode.NONE);
    durationHint.set_visible(false);
    timerContentPane.append(durationHint);
    const timerError = ui.label('', ['caption', 'status-error']);
    timerError.set_wrap(true);
    timerError.set_ellipsize(Pango.EllipsizeMode.NONE);
    timerError.set_visible(false);
    timerContentPane.append(timerError);
    page.append(timerCard);
    page.append(presets);

    function readDuration() {
        const raw = fields.map(field => field.get_text().trim());
        const parts = raw.map(text => text === '' ? 0 : Number(text));
        const invalid = raw.map((text, index) => !/^\d{0,2}$/.test(text) || parts[index] > (index === 0 ? 99 : 59));
        if (invalid.some(Boolean)) return {durationMs: 0, invalid, error: '小时填 0–99，分、秒填 0–59'};
        const durationMs = (parts[0] * 3600 + parts[1] * 60 + parts[2]) * 1000;
        if (durationMs < 1000 || durationMs > MAX_DURATION_MS) return {durationMs, invalid, error: '倒计时至少 1 秒，最长 99:59:59'};
        return {durationMs, invalid, error: ''};
    }
    function updateDurationForm() {
        const draft = readDuration();
        fields.forEach((field, index) => setClass(field, 'error', draft.invalid[index]));
        presetButtons.forEach(({button, durationMs}) => setClass(button, 'selected', !draft.error && durationMs === draft.durationMs));
        const active = timerModel.status === 'running' || timerModel.status === 'paused';
        const changedDuration = active && !draft.error && draft.durationMs !== timerModel.durationMs;
        if (pendingDuration && (!timerReady || !changedDuration || pendingDuration.durationMs !== draft.durationMs
            || pendingDuration.timer !== timerIdentity())) cancelDurationReplacement();
        setVisible(applyDurationButton, changedDuration);
        setSensitive(applyDurationButton, timerReady && changedDuration);
        const hint = active ? '当前计时保持不变；点击“按新时长开始”才会应用输入并重新计时' : '预设只填入时长；点击开始后计时';
        if (durationRow.get_tooltip_text() !== hint) durationRow.set_tooltip_text(hint);
        setLabel(durationHint, draft.error);
        setVisible(durationHint, !!draft.error);
        setClass(durationHint, 'status-error', !!draft.error);
        setSensitive(startButton, timerReady && !draft.error && !active);
    }
    function setDuration(durationMs, edited = false) {
        settingDuration = true;
        durationParts(durationMs).forEach((value, index) => {
            const text = String(value).padStart(2, '0');
            if (fields[index].get_text() !== text) fields[index].set_text(text);
        });
        settingDuration = false;
        if (edited) durationEdited = true;
        updateDurationForm();
    }
    function startTimer() {
        if (!timerReady || timerModel.status === 'running' || timerModel.status === 'paused') return;
        const draft = readDuration();
        if (draft.error) { ctx.toast(draft.error, true); return; }
        // Only this explicit user action commits the local input to the service.
        setDuration(draft.durationMs, true);
        ctx.send('timer-start', {durationMs: draft.durationMs});
    }
    fields.forEach(field => {
        field.connect('changed', () => {
            if (settingDuration) return;
            durationEdited = true;
            updateDurationForm();
        });
        field.connect('activate', startTimer);
    });

    function renderTimer() {
        const {status, durationMs} = timerModel;
        const remaining = status === 'finished' ? 0 : Math.max(0, Math.min(durationMs,
            status === 'running' && Number.isFinite(timerModel.deadlineMs)
                ? timerModel.deadlineMs - Date.now() : timerModel.remainingMs));
        setLabel(timerDisplay, clockText(remaining));
        // Quantize to displayed seconds, not fractions of a second from an
        // unrelated calculator reply. No duplicate progress invalidations.
        const fraction = Math.min(1, Math.ceil(remaining / 1000) / Math.max(1, Math.ceil(durationMs / 1000)));
        if (fraction !== lastFraction) { progress.set_fraction(fraction); lastFraction = fraction; }
        setLabel(timerStatus, timerReady ? ({idle: '未开始', running: '计时中', paused: '已暂停', finished: '已完成'}[status]) : '加载中');
        setVisible(startButton, status !== 'running' && status !== 'paused');
        setVisible(pauseButton, status === 'running');
        setVisible(resumeButton, status === 'paused');
        setSensitive(pauseButton, timerReady && status === 'running');
        setSensitive(resumeButton, timerReady && status === 'paused');
        setSensitive(resetButton, timerReady && status !== 'idle');
        setLabel(timerError, timerErrorText);
        setVisible(timerError, !!timerErrorText);
        updateDurationForm();
    }
    function updateTimer(snapshot) {
        if (!snapshot || typeof snapshot !== 'object') return;
        const next = snapshot.timer;
        const valid = next && TIMER_STATUSES.has(next.status) && Number.isFinite(next.durationMs)
            && next.durationMs >= 1000 && next.durationMs <= MAX_DURATION_MS && Number.isFinite(next.remainingMs);
        timerReady = snapshot.ready === true && !!valid;
        timerErrorText = String(snapshot.error || (snapshot.ready && !valid ? '倒计时状态暂不可用' : ''));
        if (valid) timerModel = next;
        if (timerReady && !timerLoaded) {
            timerLoaded = true;
            if (!durationEdited) setDuration(timerModel.durationMs);
        }
        renderTimer();
    }
    renderTimer();

    // The service owns the stopwatch anchor and laps. Only this one label
    // refreshes locally, and only while the tools page is visible and running.
    let toolsVisible = false;
    let stopwatchSource = 0;
    let stopwatchReady = false;
    let stopwatchModel = {version: 1, status: 'idle', elapsedMs: 0, laps: []};
    let stopwatchSnapshot = null;
    let stopwatchErrorText = '';
    let stopwatchLapsSignature = '';
    const stopwatchCard = ui.card(['stopwatch-card']);
    stopwatchCard.set_spacing(6);
    stopwatchCard.set_vexpand(true);
    const stopwatchHeader = ui.box(Gtk.Orientation.HORIZONTAL, 8);
    const stopwatchTitle = ui.label('秒表', ['section-title']);
    stopwatchTitle.set_hexpand(true);
    const stopwatchStatus = ui.label('加载中', ['caption', 'stopwatch-status']);
    stopwatchHeader.append(stopwatchTitle);
    stopwatchHeader.append(stopwatchStatus);
    stopwatchCard.append(stopwatchHeader);
    const stopwatchDisplay = ui.label('00:00.00', ['timer-display', 'stopwatch-display']);
    // Keep this secondary clock compact without changing the approved palette
    // or the main countdown style (32px under the existing 40px display rule).
    const stopwatchType = new Pango.AttrList();
    stopwatchType.insert(Pango.attr_scale_new(0.8));
    stopwatchDisplay.set_attributes(stopwatchType);
    stopwatchDisplay.set_xalign(0.5);
    stopwatchDisplay.set_vexpand(true);
    stopwatchCard.append(stopwatchDisplay);
    const stopwatchActions = ui.box(Gtk.Orientation.HORIZONTAL, 6, ['stopwatch-actions']);
    stopwatchActions.set_homogeneous(true);
    function startStopwatch() {
        if (stopwatchReady && stopwatchModel.status !== 'running') ctx.send('stopwatch-start', {});
    }
    const stopwatchStart = ui.button('开始', 'player-play', startStopwatch, ['primary-button', 'stopwatch-start']);
    const stopwatchPause = ui.button('暂停', 'player-pause', () => {
        if (stopwatchReady && stopwatchModel.status === 'running') ctx.send('stopwatch-pause', {});
    }, ['primary-button', 'stopwatch-pause']);
    const stopwatchResume = ui.button('继续', 'player-play', startStopwatch, ['primary-button', 'stopwatch-resume']);
    const stopwatchLap = ui.button('计次', null, () => {
        if (stopwatchReady && stopwatchModel.status === 'running' && stopwatchModel.laps.length < MAX_STOPWATCH_LAPS)
            ctx.send('stopwatch-lap', {});
    }, ['soft-button', 'stopwatch-lap']);
    stopwatchLap.set_tooltip_text('记录累计与本段用时；最多 100 次，旧记录不会被丢弃');
    const stopwatchReset = ui.button('重置', 'rotate-clockwise', () => {
        if (stopwatchReady && (stopwatchModel.status !== 'idle' || stopwatchModel.elapsedMs > 0 || stopwatchModel.laps.length))
            ctx.send('stopwatch-reset', {});
    }, ['soft-button', 'stopwatch-reset']);
    stopwatchReset.set_tooltip_text('将秒表归零并清空计次；不影响倒计时');
    for (const button of [stopwatchStart, stopwatchPause, stopwatchResume, stopwatchLap, stopwatchReset]) {
        button.set_hexpand(true);
        stopwatchActions.append(button);
    }
    stopwatchCard.append(stopwatchActions);
    const stopwatchError = ui.label('', ['caption', 'status-error', 'stopwatch-error']);
    stopwatchError.set_wrap(true);
    stopwatchError.set_ellipsize(Pango.EllipsizeMode.NONE);
    stopwatchError.set_visible(false);
    stopwatchCard.append(stopwatchError);
    const stopwatchHistory = new Gtk.Expander({expanded: false});
    stopwatchHistory.add_css_class('stopwatch-history');
    stopwatchHistory.set_visible(false);
    const stopwatchHistoryHeading = ui.label('计次', ['caption']);
    stopwatchHistory.set_label_widget(stopwatchHistoryHeading);
    const stopwatchLapScroll = new Gtk.ScrolledWindow({
        hscrollbar_policy: Gtk.PolicyType.NEVER, vscrollbar_policy: Gtk.PolicyType.AUTOMATIC,
        propagate_natural_height: true, max_content_height: 132,
    });
    stopwatchLapScroll.add_css_class('list-scroll');
    const stopwatchLapList = ui.box(Gtk.Orientation.VERTICAL, 5);
    const noStopwatchLaps = ui.label('暂无计次', ['caption']);
    stopwatchLapList.append(noStopwatchLaps);
    const stopwatchLapRows = Array.from({length: VISIBLE_STOPWATCH_LAPS}, () => {
        const row = ui.box(Gtk.Orientation.HORIZONTAL, 8, ['stopwatch-lap-row']);
        const index = ui.label('', ['caption']);
        const total = ui.label('', ['caption']);
        total.set_hexpand(true);
        total.set_xalign(1);
        const split = ui.label('', ['caption']);
        split.set_xalign(1);
        row.append(index); row.append(total); row.append(split);
        row.set_visible(false);
        stopwatchLapList.append(row);
        return {row, index, total, split};
    });
    stopwatchLapScroll.set_child(stopwatchLapList);
    stopwatchHistory.set_child(stopwatchLapScroll);
    stopwatchCard.append(stopwatchHistory);
    page.append(stopwatchCard);

    function stopwatchElapsed() {
        return stopwatchModel.elapsedMs + (stopwatchModel.status === 'running'
            ? Math.max(0, Date.now() - stopwatchModel.startedAtMs) : 0);
    }
    function updateStopwatchClock() {
        setLabel(stopwatchDisplay, stopwatchText(stopwatchElapsed()));
    }
    function cancelStopwatchRefresh() {
        if (stopwatchSource) GLib.source_remove(stopwatchSource);
        stopwatchSource = 0;
    }
    function syncStopwatchRefresh() {
        if (!toolsVisible || !stopwatchReady || stopwatchModel.status !== 'running') {
            cancelStopwatchRefresh();
            return;
        }
        if (stopwatchSource) return;
        stopwatchSource = GLib.timeout_add(GLib.PRIORITY_DEFAULT, STOPWATCH_REFRESH_MS, () => {
            if (!toolsVisible || !stopwatchReady || stopwatchModel.status !== 'running') {
                stopwatchSource = 0;
                return GLib.SOURCE_REMOVE;
            }
            updateStopwatchClock();
            return GLib.SOURCE_CONTINUE;
        });
    }
    function updateStopwatchLaps() {
        const laps = stopwatchModel.laps.filter(lap => lap && Number.isSafeInteger(lap.index) && lap.index > 0
            && Number.isFinite(lap.totalMs) && lap.totalMs >= 0 && Number.isFinite(lap.splitMs) && lap.splitMs >= 0);
        const records = laps.slice(-VISIBLE_STOPWATCH_LAPS).reverse();
        const signature = JSON.stringify({count: laps.length, records});
        if (signature === stopwatchLapsSignature) return;
        stopwatchLapsSignature = signature;
        setLabel(stopwatchHistoryHeading, laps.length ? '计次 · ' + laps.length
            + (laps.length > VISIBLE_STOPWATCH_LAPS ? '（显示最近 8 次）' : '') : '计次');
        setVisible(noStopwatchLaps, laps.length === 0);
        setVisible(stopwatchHistory, laps.length > 0);
        if (!laps.length && stopwatchHistory.get_expanded()) stopwatchHistory.set_expanded(false);
        stopwatchLapRows.forEach((item, index) => {
            const lap = records[index];
            setVisible(item.row, !!lap);
            if (!lap) return;
            setLabel(item.index, '#' + String(lap.index).padStart(2, '0'));
            setLabel(item.total, stopwatchText(lap.totalMs));
            setLabel(item.split, '+' + stopwatchText(lap.splitMs));
        });
    }
    function renderStopwatch() {
        updateStopwatchClock();
        const status = stopwatchModel.status;
        setLabel(stopwatchStatus, stopwatchReady ? {idle: '未开始', running: '计时中', paused: '已暂停'}[status] : '加载中');
        setVisible(stopwatchStart, status === 'idle');
        setVisible(stopwatchPause, status === 'running');
        setVisible(stopwatchResume, status === 'paused');
        setSensitive(stopwatchStart, stopwatchReady && status === 'idle');
        setSensitive(stopwatchPause, stopwatchReady && status === 'running');
        setSensitive(stopwatchResume, stopwatchReady && status === 'paused');
        setSensitive(stopwatchLap, stopwatchReady && status === 'running' && stopwatchModel.laps.length < MAX_STOPWATCH_LAPS);
        setSensitive(stopwatchReset, stopwatchReady && (status !== 'idle' || stopwatchModel.elapsedMs > 0 || stopwatchModel.laps.length > 0));
        setLabel(stopwatchError, stopwatchErrorText);
        setVisible(stopwatchError, !!stopwatchErrorText);
        updateStopwatchLaps();
    }
    function updateStopwatch(snapshot) {
        if (!snapshot || typeof snapshot !== 'object' || snapshot === stopwatchSnapshot) return;
        stopwatchSnapshot = snapshot;
        const next = snapshot.stopwatch;
        // API32 encodes an empty Lua table as {}; normalize only this known list field.
        const rawLaps = next?.laps;
        const laps = Array.isArray(rawLaps) ? rawLaps
            : (rawLaps && typeof rawLaps === 'object' && Object.keys(rawLaps).length === 0 ? [] : null);
        const valid = next && next.version === 1 && STOPWATCH_STATUSES.has(next.status)
            && Number.isFinite(next.elapsedMs) && next.elapsedMs >= 0 && laps !== null
            && (next.status !== 'running' || (Number.isFinite(next.startedAtMs) && next.startedAtMs >= 0));
        stopwatchReady = snapshot.ready === true && !!valid;
        stopwatchErrorText = String(snapshot.error || (snapshot.ready && !valid ? '秒表状态暂不可用' : ''));
        if (valid) stopwatchModel = {...next, laps};
        renderStopwatch();
        syncStopwatchRefresh();
    }
    renderStopwatch();

    return {
        widget,
        update(state) {
            applyPresets(state?.config?.timerPresets);
            updateCalculation(state?.calc);
            updateTimer(state?.timer);
            updateStopwatch(state?.stopwatch);
        },
        onShow() {
            for (const binding of durationControllers) bindDurationController(binding);
            toolsVisible = true;
            renderStopwatch();
            syncStopwatchRefresh();
            if (!shownOnce && expression.get_root()) { focusExpression(); shownOnce = true; }
            renderTimer();
            calcWave.pulse();
            if (previewQueued) schedulePreview();
        },
        onHide() {
            toolsVisible = false;
            cancelStopwatchRefresh();
            // A pending preview can resume on showing; this never pauses or
            // resets the actual service-owned countdown.
            cancelPreview();
            // Controllers are reused on show; detach JS callbacks before hidden
            // focused widgets can be finalized during GJS garbage collection.
            unbindDurationControllers();
            for (const field of durationSelectionSources.keys()) cancelDurationSelection(field);
            cancelDurationReplacement();
        },
        handleEscape() {
            if (pendingDuration) { cancelDurationReplacement(); return true; }
            if (stopwatchHistory.get_visible() && stopwatchHistory.get_expanded()) { stopwatchHistory.set_expanded(false); return true; }
            if (!history.get_expanded()) return false;
            history.set_expanded(false);
            return true;
        },
    };
}
