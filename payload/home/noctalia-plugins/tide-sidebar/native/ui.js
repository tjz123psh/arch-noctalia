import Gtk from 'gi://Gtk?version=4.0';
import Pango from 'gi://Pango';
import GLib from 'gi://GLib';

const icons = {
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

// Flat liquid-color boundaries. Only this small drawing area repaints during a short pulse.
function makeWave(color, height, cornerRadius) {
    const area = new Gtk.DrawingArea({content_height: height, hexpand: true, can_target: false});
    const red = parseInt(color.slice(1, 3), 16) / 255;
    const green = parseInt(color.slice(3, 5), 16) / 255;
    const blue = parseInt(color.slice(5, 7), 16) / 255;
    let phase = 0, from = 0, start = 0, tick = 0;
    area.set_draw_func((_widget, cr, width, h) => {
        if (width < 2 || h < 2) return;
        const y = h * 0.32, a = Math.min(4, h * 0.20);
        cr.moveTo(0, y);
        cr.curveTo(width * .13, y - a * Math.cos(phase), width * .23, y + a, width * .36, y + a * .25);
        cr.curveTo(width * .49, y - a, width * .57, y - a * Math.cos(phase + .6), width * .70, y);
        cr.curveTo(width * .84, y + a, width * .90, y - a * .7, width, y - a * .15);
        const radius = Math.min(cornerRadius, h * .5, width * .5);
        if (radius > 0) {
            cr.lineTo(width, h - radius);
            cr.curveTo(width, h - radius * .45, width - radius * .45, h, width - radius, h);
            cr.lineTo(radius, h);
            cr.curveTo(radius * .45, h, 0, h - radius * .45, 0, h - radius);
        } else { cr.lineTo(width, h); cr.lineTo(0, h); }
        cr.closePath();
        cr.setSourceRGBA(red, green, blue, 1);
        cr.fill();
    });
    area.pulse = () => {
        if (!area.get_mapped() || !Gtk.Settings.get_default().gtk_enable_animations) return;
        from = phase; start = GLib.get_monotonic_time();
        if (tick) return;
        tick = area.add_tick_callback((_widget, clock) => {
            const t = Math.min(1, (clock.get_frame_time() - start) / 320000);
            const ease = 1 - (1 - t) ** 3;
            phase = from * (1 - ease) + Math.sin(Math.PI * ease) * .65;
            area.queue_draw();
            if (t >= 1) { tick = 0; phase = 0; return GLib.SOURCE_REMOVE; }
            return GLib.SOURCE_CONTINUE;
        });
    };
    area.connect('unmap', () => { if (tick) area.remove_tick_callback(tick); tick = 0; phase = 0; });
    return area;
}
export function waveBand(color = '#F1D68B', height = 22) { return makeWave(color, height, 0); }
export function waveFooter(color = '#ECD081', height = 54, radius = 22) { return makeWave(color, height, radius); }

