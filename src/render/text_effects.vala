namespace Singularity.Apps.Slides {

    public class TextEffects {
        private static void warp_at (string warp, double u, double v, double w, double h, out double dx, out double dy, out double rot, out double sy) {
            dx = 0;
            dy = 0;
            rot = 0;
            sy = 1;
            double c = u - 0.5;
            switch (warp) {
                case "textArchUp":
                case "textCanUp":
                case "textButton":
                    dy = -h * 0.5 * (1 - 4 * c * c) * (warp == "textCanUp" ? 0.35 : 0.8);
                    rot = Math.atan (-h * 0.5 * (-8 * c) * (warp == "textCanUp" ? 0.35 : 0.8) / w);
                    break;
                case "textArchDown":
                case "textCanDown":
                    dy = h * 0.5 * (1 - 4 * c * c) * (warp == "textCanDown" ? 0.35 : 0.8);
                    rot = Math.atan (h * 0.5 * (-8 * c) * (warp == "textCanDown" ? 0.35 : 0.8) / w);
                    break;
                case "textCircle":
                    double ang = -Math.PI / 2 + (u - 0.5) * Math.PI * 1.6;
                    double r = double.min (w, h) * 0.45;
                    dx = r * Math.cos (ang) - (u - 0.5) * w;
                    dy = r * Math.sin (ang) + h * 0.2;
                    rot = ang + Math.PI / 2;
                    break;
                case "textWave1":
                case "textWave2":
                case "textDoubleWave1":
                    double k = warp == "textDoubleWave1" ? 4 : 2;
                    double sgn = warp == "textWave2" ? -1 : 1;
                    dy = sgn * h * 0.12 * Math.sin (u * Math.PI * k);
                    rot = Math.atan (sgn * h * 0.12 * Math.PI * k * Math.cos (u * Math.PI * k) / w);
                    break;
                case "textInflate":
                    sy = 1 + 0.6 * (1 - 4 * c * c);
                    break;
                case "textDeflate":
                    sy = 1 - 0.4 * (1 - 4 * c * c);
                    break;
                case "textSlantUp":
                    dy = -h * 0.3 * c * 2;
                    rot = Math.atan (-h * 0.6 / w);
                    break;
                case "textSlantDown":
                    dy = h * 0.3 * c * 2;
                    rot = Math.atan (h * 0.6 / w);
                    break;
                case "textTriangle":
                    dy = -h * 0.3 * (1 - Math.fabs (c) * 2);
                    break;
                case "textTriangleInverted":
                    dy = h * 0.3 * (1 - Math.fabs (c) * 2);
                    break;
                case "textChevron":
                    dy = -h * 0.25 * (1 - Math.fabs (c) * 2);
                    rot = c < 0 ? -0.3 : 0.3;
                    break;
                case "textChevronInverted":
                    dy = h * 0.25 * (1 - Math.fabs (c) * 2);
                    rot = c < 0 ? 0.3 : -0.3;
                    break;
                case "textFadeRight":
                    sy = 1 - 0.5 * u;
                    break;
                case "textFadeLeft":
                    sy = 0.5 + 0.5 * u;
                    break;
                case "textFadeUp":
                case "textStop":
                    sy = 1.2;
                    break;
                case "textFadeDown":
                    sy = 0.8;
                    break;
                case "textCurveUp":
                    dy = -h * 0.3 * Math.sin (u * Math.PI / 2);
                    rot = Math.atan (-h * 0.3 * Math.PI / 2 * Math.cos (u * Math.PI / 2) / w);
                    break;
                case "textCurveDown":
                    dy = h * 0.3 * Math.sin (u * Math.PI / 2);
                    rot = Math.atan (h * 0.3 * Math.PI / 2 * Math.cos (u * Math.PI / 2) / w);
                    break;
                default:
                    break;
            }
        }

        private static void text_path (Cairo.Context cr, TextLayout tl, double ox, double oy) {
            foreach (var pl in tl.paras) {
                cr.move_to (ox + pl.x, oy + pl.y);
                Pango.cairo_layout_path (cr, pl.layout);
            }
        }

        public static void draw (Renderer r, Cairo.Context cr, RenderContext ctx, ShapeElement s, double x, double y, double w, double h, string default_color) {
            var body = s.text;
            var fx = s.effects;
            var tl = r.fit_text (ctx, s, body, w, h, default_color);
            var anchor = ctx.pres.effective_anchor (ctx.slide, ctx.layout, ctx.master, s, body);
            double avail = h - body.inset_top - body.inset_bottom;
            double oy = y + body.inset_top;
            if (anchor == TextAnchor.MIDDLE) oy += (avail - tl.height) / 2;
            else if (anchor == TextAnchor.BOTTOM) oy += avail - tl.height;
            double ox = x + body.inset_left;
            double iw = w - body.inset_left - body.inset_right;
            if (fx.text_shadow) {
                Effects.shadow (cr, "ts%d:%s:%g:%g".printf (s.id, body.plain_text (), w, h), x, y, w, h, Rgba (0, 0, 0, 0.45), 4, 2, 2.5, (c) => {
                    text_path (c, tl, ox, oy);
                }, false, 0);
            }
            if (fx.text_glow != "" && fx.text_glow_radius > 0) {
                var gc = ctx.theme.resolve (fx.text_glow);
                gc.a *= 0.7;
                Effects.shadow (cr, "tg%d:%s:%g:%g:%g".printf (s.id, body.plain_text (), w, h, fx.text_glow_radius), x, y, w, h, gc, fx.text_glow_radius, 0, 0, (c) => {
                    text_path (c, tl, ox, oy);
                }, true, fx.text_glow_radius * 2);
            }
            if (fx.text_reflection) {
                cr.save ();
                cr.push_group ();
                double base_y = oy + tl.height;
                cr.translate (0, 2 * base_y);
                cr.scale (1, -1);
                paint_text (cr, ctx, tl, ox, oy, iw, fx);
                var pat = cr.pop_group ();
                var mask = new Cairo.Pattern.linear (0, base_y, 0, base_y + tl.height * 0.6);
                mask.add_color_stop_rgba (0, 0, 0, 0, 0.45);
                mask.add_color_stop_rgba (1, 0, 0, 0, 0);
                cr.set_source (pat);
                cr.mask (mask);
                cr.restore ();
            }
            if (fx.text_warp != "" && fx.text_warp != "textPlain") {
                warped (cr, ctx, tl, ox, oy, iw, double.max (tl.height, avail), fx);
                return;
            }
            paint_text (cr, ctx, tl, ox, oy, iw, fx);
        }

        private static void paint_text (Cairo.Context cr, RenderContext ctx, TextLayout tl, double ox, double oy, double iw, ShapeEffects fx) {
            cr.save ();
            if (fx.text_fill != "") {
                text_path (cr, tl, ox, oy);
                var f = fx.text_fill;
                if (f.contains (">")) {
                    string[] parts = f.split (">");
                    var g = new Cairo.Pattern.linear (ox, oy, ox, oy + tl.height);
                    var a = ctx.theme.resolve (parts[0]), b = ctx.theme.resolve (parts[1]);
                    g.add_color_stop_rgba (0, a.r, a.g, a.b, a.a);
                    g.add_color_stop_rgba (1, b.r, b.g, b.b, b.a);
                    cr.set_source (g);
                } else {
                    Renderer.set_source (cr, ctx.theme.resolve (f));
                }
                cr.fill ();
            } else {
                foreach (var pl in tl.paras) {
                    cr.move_to (ox + pl.x, oy + pl.y);
                    Pango.cairo_show_layout (cr, pl.layout);
                }
            }
            if (fx.text_outline != "") {
                text_path (cr, tl, ox, oy);
                Renderer.set_source (cr, ctx.theme.resolve (fx.text_outline));
                cr.set_line_width (fx.text_outline_width);
                cr.set_line_join (Cairo.LineJoin.ROUND);
                cr.stroke ();
            }
            cr.restore ();
        }

        private static void warped (Cairo.Context cr, RenderContext ctx, TextLayout tl, double ox, double oy, double iw, double ih, ShapeEffects fx) {
            foreach (var pl in tl.paras) {
                unowned string text = pl.layout.get_text ();
                int idx = 0;
                unichar ch;
                int prev = 0;
                while (text.get_next_char (ref idx, out ch)) {
                    if (ch == '\n' || ch == ' ') {
                        prev = idx;
                        continue;
                    }
                    var rect = pl.layout.index_to_pos (prev);
                    double cx0 = rect.x / (double) Pango.SCALE, cy0 = rect.y / (double) Pango.SCALE;
                    double cw = rect.width / (double) Pango.SCALE, chh = rect.height / (double) Pango.SCALE;
                    if (cw < 0) {
                        cx0 += cw;
                        cw = -cw;
                    }
                    double gx = ox + pl.x + cx0, gy = oy + pl.y + cy0;
                    double u = iw > 0 ? (pl.x + cx0 + cw / 2) / iw : 0.5;
                    double v = (pl.y + cy0) / double.max (ih, 1);
                    double dx, dy, rot, sy;
                    warp_at (fx.text_warp, u.clamp (0, 1), v, iw, ih, out dx, out dy, out rot, out sy);
                    cr.save ();
                    cr.translate (gx + cw / 2 + dx, gy + chh + dy);
                    cr.rotate (rot);
                    cr.scale (1, sy);
                    cr.translate (-(gx + cw / 2), -(gy + chh));
                    cr.rectangle (gx - 1, gy - chh * 0.3, cw + 2, chh * 1.6);
                    cr.clip ();
                    var one = new TextLayout ();
                    one.paras.add (pl);
                    one.height = pl.height;
                    paint_text (cr, ctx, one, ox, oy, iw, fx);
                    cr.restore ();
                    prev = idx;
                }
            }
        }
    }
}
