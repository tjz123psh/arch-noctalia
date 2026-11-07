// Palette bridge: turn Noctalia's generated GTK colours into sidebar tokens.
//
// Noctalia rewrites ~/.config/gtk-4.0/noctalia.css on every wallpaper/palette
// change; it contains plain `@define-color name #rrggbb;` entries (accent,
// window/card/popover surfaces, foreground, error). We read that file, derive a
// small design-token set (three surface steps, two text steps, borders, accent
// tints) and emit `@define-color t_*` lines that style.css references.
//
// Why derive instead of hardcoding: GTK CSS has no var()/calc(), so the only way
// to get layered surfaces from one palette is to compute the steps in JS and
// feed them in as named colours. Everything adapts when the wallpaper changes,
// light palettes included.

import GLib from 'gi://GLib';

const PALETTE_CANDIDATES = [
    GLib.build_filenamev([GLib.get_user_config_dir(), 'gtk-4.0', 'noctalia.css']),
    GLib.build_filenamev([GLib.get_user_config_dir(), 'gtk-3.0', 'noctalia.css']),
];

// Fallback: a neutral dark palette so the sidebar still renders if Noctalia's
// template output is missing (fresh machine, first boot, template disabled).
const FALLBACK = {
    window_bg_color: '#161311',
    window_fg_color: '#efe6dc',
    card_bg_color: '#211d19',
    popover_bg_color: '#211d19',
    view_bg_color: '#161311',
    accent_bg_color: '#e8a08c',
    accent_fg_color: '#2b1210',
    error_bg_color: '#f2b8b5',
};

const clamp = (v, lo, hi) => Math.min(hi, Math.max(lo, v));

function parseHex(value) {
    if (typeof value !== 'string') return null;
    let s = value.trim().replace(/;$/, '');
    if (s.startsWith('#')) s = s.slice(1);
    if (s.length === 3) s = s.split('').map(c => c + c).join('');
    if (!/^[0-9a-fA-F]{6}([0-9a-fA-F]{2})?$/.test(s)) return null;
    return {
        r: parseInt(s.slice(0, 2), 16),
        g: parseInt(s.slice(2, 4), 16),
        b: parseInt(s.slice(4, 6), 16),
    };
}

export function readDefines(paths = PALETTE_CANDIDATES) {
    for (const path of paths) {
        try {
            const [ok, bytes] = GLib.file_get_contents(path);
            if (!ok) continue;
            const text = new TextDecoder().decode(bytes);
            const out = {};
            for (const line of text.split('\n')) {
                const match = line.match(/^\s*@define-color\s+([a-z0-9_]+)\s+(#[0-9a-fA-F]{3,8})\s*;/);
                if (match) out[match[1]] = match[2];
            }
            if (Object.keys(out).length) return out;
        } catch (_) { /* try the next candidate */ }
    }
    return {};
}

const hex = ({r, g, b}) => '#' + [r, g, b].map(v => clamp(Math.round(v), 0, 255).toString(16).padStart(2, '0')).join('');
const rgba = ({r, g, b}, a) => `rgba(${clamp(Math.round(r), 0, 255)}, ${clamp(Math.round(g), 0, 255)}, ${clamp(Math.round(b), 0, 255)}, ${a})`;
const mix = (a, b, t) => ({r: a.r + (b.r - a.r) * t, g: a.g + (b.g - a.g) * t, b: a.b + (b.b - a.b) * t});

const luminance = ({r, g, b}) => {
    const f = v => { v /= 255; return v <= 0.03928 ? v / 12.92 : ((v + 0.055) / 1.055) ** 2.4; };
    return 0.2126 * f(r) + 0.7152 * f(g) + 0.0722 * f(b);
};

// Perceptual-ish saturation boost in HSL space: keeps the hue Noctalia picked
// from the wallpaper, only makes the accent read as an accent on a flat surface.
function boost(color, satGain, lightShift = 0) {
    const r = color.r / 255, g = color.g / 255, b = color.b / 255;
    const max = Math.max(r, g, b), min = Math.min(r, g, b);
    let h = 0, s = 0;
    const l = (max + min) / 2;
    const d = max - min;
    if (d !== 0) {
        s = d / (1 - Math.abs(2 * l - 1));
        switch (max) {
            case r: h = ((g - b) / d) % 6; break;
            case g: h = (b - r) / d + 2; break;
            default: h = (r - g) / d + 4;
        }
        h *= 60;
        if (h < 0) h += 360;
    }
    const S = clamp(s * satGain, 0, 1);
    const L = clamp(l + lightShift, 0, 1);
    const c = (1 - Math.abs(2 * L - 1)) * S;
    const x = c * (1 - Math.abs(((h / 60) % 2) - 1));
    const m = L - c / 2;
    let rgb;
    if (h < 60) rgb = [c, x, 0];
    else if (h < 120) rgb = [x, c, 0];
    else if (h < 180) rgb = [0, c, x];
    else if (h < 240) rgb = [0, x, c];
    else if (h < 300) rgb = [x, 0, c];
    else rgb = [c, 0, x];
    return {r: (rgb[0] + m) * 255, g: (rgb[1] + m) * 255, b: (rgb[2] + m) * 255};
}

export function buildTokens(defines = {}) {
    const pick = (name) => parseHex(defines[name]) || parseHex(FALLBACK[name]);
    const bg = pick('window_bg_color') || parseHex(FALLBACK.window_bg_color);
    const fg = pick('window_fg_color') || parseHex(FALLBACK.window_fg_color);
    const card = pick('card_bg_color') || mix(bg, fg, 0.06);
    const popover = pick('popover_bg_color') || card;
    const accentRaw = pick('accent_bg_color') || parseHex(FALLBACK.accent_bg_color);
    const accentFg = pick('accent_fg_color') || bg;
    const danger = pick('error_bg_color') || {r: 242, g: 184, b: 181};

    const dark = luminance(bg) < 0.35;
    // Three surface steps: base (window), card (Noctalia's card colour), and two
    // steps inside a card for rows/controls. On dark palettes we climb towards
    // the foreground; on light palettes we descend towards the shadow side.
    const away = dark ? fg : {r: 0, g: 0, b: 0};
    const toward = dark ? 1 : 1;
    const surf0 = mix(bg, away, dark ? 0.045 : 0.03);
    const surf1 = mix(card, away, dark ? 0.085 * toward : 0.02);
    const surf2 = mix(card, away, dark ? 0.16 * toward : 0.05);
    const line = mix(bg, away, dark ? 0.16 : 0.10);
    const lineStrong = mix(bg, away, dark ? 0.26 : 0.18);
    const accent = boost(accentRaw, 1.18, 0);
    const success = dark ? {r: 0x6f, g: 0xd0, b: 0x9b} : {r: 0x2c, g: 0x7d, b: 0x52};
    const warning = dark ? {r: 0xe3, g: 0xb3, b: 0x41} : {r: 0x9a, g: 0x6a, b: 0x00};
    const highlight = dark ? rgba({r: 255, g: 255, b: 255}, 0.055) : rgba({r: 255, g: 255, b: 255}, 0.65);
    // Glass is only honest when something actually blurs behind the surface.
    // niri exports NIRI_SOCKET and its layer-rule blurs this namespace; on any
    // other compositor we fall back to nearly opaque panels instead of showing
    // a washed-out wallpaper through a "glass" that is not frosted.
    const blurred = Boolean(GLib.getenv('NIRI_SOCKET'));
    const body = dark ? 0 : 0.12;           // light palettes need more substance
    // The frame is smoked glass: a darker base than the cards so the panels
    // read as frosted sheets laid on top, while 18% of the blurred wallpaper
    // still tints it.
    const shellInk = mix(bg, fg, dark ? 0.11 : 0.03);
    const shellAlpha = Math.min(0.99, (blurred ? 0.72 : 0.97) + body);
    const cardAlpha = Math.min(0.99, (blurred ? 0.97 : 0.99) + body);
    const railAlpha = Math.min(0.99, (blurred ? 0.20 : 0.94) + body);
    const readAlpha = blurred ? 0.92 : 1;
    const data = rgba(fg, 0.22);

    const tokens = {
        t_bg: hex(bg),
        t_surf0: hex(surf0),
        t_surf1: hex(surf1),
        t_surf2: hex(surf2),
        t_popover: hex(popover),
        t_fg: hex(fg),
        t_fg_dim: hex(mix(fg, bg, dark ? 0.34 : 0.40)),
        t_fg_faint: hex(mix(fg, bg, dark ? 0.52 : 0.56)),
        t_border: rgba(line, 0.9),
        t_border_strong: rgba(lineStrong, 0.95),
        t_accent: hex(accent),
        t_accent_fg: hex(accentFg),
        t_accent_soft: rgba(accent, 0.16),
        t_accent_ghost: rgba(accent, 0.08),
        t_accent_line: rgba(accent, 0.55),
        t_danger: hex(danger),
        t_danger_soft: rgba(danger, 0.16),
        t_success: hex(success),
        t_warning: hex(warning),
        t_highlight: highlight,
        // Glass surfaces. Shell = the floating card, Card = a panel on top of it,
        // Rail = the navigation strip, Read = surfaces that must stay legible
        // (note editor, calculator display).
        t_glass: rgba(shellInk, shellAlpha),
        t_glass_card: rgba(surf1, cardAlpha),
        t_glass_rail: rgba(surf0, railAlpha),
        t_glass_read: rgba(surf1, readAlpha),
        t_sheen: dark ? rgba({r: 255, g: 255, b: 255}, 0.012) : rgba({r: 255, g: 255, b: 255}, 0.25),
        t_vignette: dark ? rgba({r: 0, g: 0, b: 0}, 0.16) : rgba({r: 60, g: 40, b: 30}, 0.05),
        // macOS-style category colours: fixed by meaning, tuned per mode so they
        // stay saturated without glowing on dark glass.
        t_mod_tools: dark ? '#4C86E8' : '#2F6FD0',
        t_mod_windows: dark ? '#8C6BE8' : '#6D4DD0',
        // Group plates sit one step above the glass; rows only get hairlines.
        t_group: dark ? rgba({r: 255, g: 255, b: 255}, 0.085) : rgba({r: 255, g: 255, b: 255}, 0.88),
        t_row_hover: dark ? rgba({r: 255, g: 255, b: 255}, 0.04) : rgba({r: 0, g: 0, b: 0}, 0.035),
        t_row_active: dark ? rgba({r: 255, g: 255, b: 255}, 0.085) : rgba({r: 0, g: 0, b: 0}, 0.07),
        t_separator: dark ? rgba({r: 255, g: 255, b: 255}, 0.075) : rgba({r: 0, g: 0, b: 0}, 0.14),
        // Static data ink: neutral on purpose, so the accent stays a state and
        // not a decoration. Peaks switch to @t_accent explicitly.
        t_data: data,
        t_shadow: dark ? rgba({r: 0, g: 0, b: 0}, 0.45) : rgba({r: 60, g: 40, b: 30}, 0.12),
        t_shadow_lift: dark ? rgba({r: 0, g: 0, b: 0}, 0.55) : rgba({r: 60, g: 40, b: 30}, 0.20),
        t_shadow_soft: dark ? rgba({r: 0, g: 0, b: 0}, 0.28) : rgba({r: 60, g: 40, b: 30}, 0.07),
    };
    return {tokens, dark};
}

export function cssPrelude(tokens) {
    return Object.entries(tokens).map(([name, value]) => `@define-color ${name} ${value};`).join('\n') + '\n';
}

export function paletteFor(configPath = null) {
    const defines = readDefines(configPath ? [configPath] : PALETTE_CANDIDATES);
    const {tokens, dark} = buildTokens(defines);
    return {css: cssPrelude(tokens), tokens, dark, defines};
}
