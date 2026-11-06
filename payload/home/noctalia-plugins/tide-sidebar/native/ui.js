import Gtk from 'gi://Gtk?version=4.0';
import Pango from 'gi://Pango';
import GLib from 'gi://GLib';

const icons = {
    home: 'go-home-symbolic',
    theme: 'display-brightness-symbolic',
    moon: 'weather-clear-night-symbolic',
    sun: 'weather-clear-symbolic',
    terminal: 'utilities-terminal-symbolic',
    music: 'audio-x-generic-symbolic',
    note: 'document-edit-symbolic', calculator: 'accessories-calculator-symbolic',
    hourglass: 'alarm-symbolic', timer: 'alarm-symbolic', wifi: 'network-wireless-symbolic',
    apps: 'view-grid-symbolic', windows: 'focus-windows-symbolic', tools: 'applications-utilities-symbolic',
    plus: 'list-add-symbolic', trash: 'user-trash-symbolic', pencil: 'document-edit-symbolic',
    history: 'document-open-recent-symbolic', refresh: 'view-refresh-symbolic',
    x: 'window-close-symbolic', close: 'window-close-symbolic', check: 'object-select-symbolic',
    copy: 'edit-copy-symbolic', eye: 'view-reveal-symbolic', 'eye-off': 'view-conceal-symbolic',
    'chevron-left': 'go-previous-symbolic', 'chevron-right': 'go-next-symbolic',
    'chevron-up': 'go-up-symbolic', 'chevron-down': 'go-down-symbolic',
    'arrow-up': 'go-up-symbolic', 'arrow-down': 'go-down-symbolic',
    'arrow-up-right': 'go-jump-symbolic', 'arrow-back-up': 'edit-undo-symbolic',
    'player-play': 'media-playback-start-symbolic', 'player-pause': 'media-playback-pause-symbolic',
    'rotate-clockwise': 'view-refresh-symbolic', power: 'system-shutdown-symbolic',
    'grip-vertical': 'list-drag-handle-symbolic', wind: 'preferences-desktop-accessibility-symbolic',
};
// Motion vocabulary: one duration per intent. GTK CSS has no variables, so the
// CSS side mirrors these values in style.css and --reduced-motion zeroes both.
export const DURATION = {fast: 120, reveal: 160, page: 220, toast: 180, drawerOpen: 620, drawerClose: 560};
export function motionMs(reduced, name) {
    return reduced === true ? 0 : (DURATION[name] ?? DURATION.reveal);
}
export function classes(widget, names = []) {
    for (const name of typeof names === 'string' ? names.split(/\s+/) : names)
        if (name) widget.add_css_class(name);
    return widget;
}
export function icon(name, size = 18) {
    const image = new Gtk.Image({icon_name: icons[name] || name, pixel_size: size});
    return image;
}
export function label(text = '', names = []) {
    return classes(new Gtk.Label({label: String(text), xalign: 0, ellipsize: Pango.EllipsizeMode.END}), names);
}
export function box(orientation = Gtk.Orientation.VERTICAL, spacing = 0, names = []) {
    if (typeof orientation === 'string') orientation = orientation === 'horizontal' ? Gtk.Orientation.HORIZONTAL : Gtk.Orientation.VERTICAL;
    return classes(new Gtk.Box({orientation, spacing}), names);
}
export function button(text, glyph, onClick, names = []) {
    const result = classes(new Gtk.Button(), ['glass-button', ...names]);
    const content = new Gtk.Box({orientation: Gtk.Orientation.HORIZONTAL, spacing: 6, halign: Gtk.Align.CENTER});
    if (glyph) content.append(icon(glyph));
    if (text) content.append(new Gtk.Label({label: String(text)}));
    result.set_child(content);
    if (onClick) result.connect('clicked', onClick);
    return result;
}
export function iconButton(glyph, onClick, tooltip = '', names = []) {
    const result = button('', glyph, onClick, ['icon-button', ...names]);
    if (tooltip) result.set_tooltip_text(tooltip);
    return result;
}
export function card(names = []) { return box(Gtk.Orientation.VERTICAL, 10, ['card', ...names]); }
export function clear(container) {
    for (let child = container.get_first_child(); child;) {
        const next = child.get_next_sibling();
        container.remove(child);
        child = next;
    }
}
export function setLabel(widget, value) {
    value = String(value ?? '');
    if (widget.get_label() !== value) widget.set_label(value);
}

// A rule-style wave: one stroked line, no filled body. This is the shape the
// 2026-11 redesign uses as a separator (notes footer, calculator mid-rule);
// a filled block at low contrast is what made the old design read as "cheap".
// `color` may be a hex string or a getter: the accent comes from the live
// wallpaper palette, so a captured string would keep the old hue after the
// wallpaper changes (the stylesheet hot-reloads, the captured value does not).
export function waveRule(color = '#F1D68B', height = 8) {
    const area = new Gtk.DrawingArea({content_height: height, hexpand: true, can_target: false});
    const currentRgb = () => {
        const value = typeof color === 'function' ? color() : color;
        const hex = String(value || '#888888').replace('#', '');
        return {
            r: parseInt(hex.slice(0, 2), 16) / 255,
            g: parseInt(hex.slice(2, 4), 16) / 255,
            b: parseInt(hex.slice(4, 6), 16) / 255,
        };
    };
    let phase = 0;
    let tick = 0;
    let pulse = 0;
    let pulseTick = 0;
    area.set_draw_func((_widget, cr, width, h) => {
        if (width < 2 || h < 2) return;
        const y = h * 0.5;
        const amp = Math.min(2.6, h * 0.32) * (1 + pulse * 1.6);
        cr.moveTo(0, y);
        cr.curveTo(width * .18, y - amp * Math.cos(phase), width * .34, y + amp * Math.sin(phase * .9), width * .52, y + amp * .25);
        cr.curveTo(width * .70, y - amp, width * .86, y + amp * .6, width, y - amp * .2);
        cr.setLineWidth(1.3);
        cr.setLineCap(1);
        const rgb = currentRgb();
        cr.setSourceRGBA(rgb.r, rgb.g, rgb.b, 0.42);
        cr.stroke();
    });
    area.startBreathe = () => {
        if (tick || !Gtk.Settings.get_default().gtk_enable_animations) return;
        tick = GLib.timeout_add(GLib.PRIORITY_DEFAULT, 55, () => {
            if (!area.get_mapped()) { tick = 0; return GLib.SOURCE_REMOVE; }
            phase = (phase + 0.03) % (Math.PI * 2);
            area.queue_draw();
            return GLib.SOURCE_CONTINUE;
        });
    };
    area.stopBreathe = () => {
        if (tick) { GLib.source_remove(tick); tick = 0; }
    };
    // Short damped kick: commits (=) and saves used to ripple the old filled
    // wave; keep the feedback without the block.
    area.pulse = (durationMs = 420, intensity = 1) => {
        if (!Gtk.Settings.get_default().gtk_enable_animations) return;
        if (pulseTick) { GLib.source_remove(pulseTick); pulseTick = 0; }
        const start = GLib.get_monotonic_time();
        const span = Math.max(1, durationMs) * 1000;
        pulse = Math.min(1.2, intensity);
        pulseTick = GLib.timeout_add(GLib.PRIORITY_DEFAULT, 24, () => {
            const t = Math.min(1, (GLib.get_monotonic_time() - start) / span);
            pulse = Math.min(1.2, intensity) * Math.exp(-3.0 * t) * (1 - t);
            area.queue_draw();
            if (t >= 1) { pulseTick = 0; pulse = 0; area.queue_draw(); return GLib.SOURCE_REMOVE; }
            return GLib.SOURCE_CONTINUE;
        });
    };
    area.connect('unmap', () => {
        area.stopBreathe();
        if (pulseTick) { GLib.source_remove(pulseTick); pulseTick = 0; pulse = 0; }
    });
    return area;
}


