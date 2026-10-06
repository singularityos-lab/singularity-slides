namespace Singularity.Apps.Slides {

    public class Geometry {

        private static void poly (Cairo.Context cr, double x, double y, double[] pts) {
            cr.move_to (x + pts[0], y + pts[1]);
            for (int i = 2; i + 1 < pts.length; i += 2) cr.line_to (x + pts[i], y + pts[i + 1]);
            cr.close_path ();
        }

        private static void star (Cairo.Context cr, double x, double y, double w, double h, int points, double inner) {
            double cx = x + w / 2, cy = y + h / 2;
            for (int i = 0; i < points * 2; i++) {
                double a = -Math.PI / 2 + i * Math.PI / points;
                double r = i % 2 == 0 ? 1 : inner;
                double px = cx + Math.cos (a) * w / 2 * r;
                double py = cy + Math.sin (a) * h / 2 * r;
                if (i == 0) cr.move_to (px, py);
                else cr.line_to (px, py);
            }
            cr.close_path ();
        }

        private static void regular (Cairo.Context cr, double x, double y, double w, double h, int sides) {
            double cx = x + w / 2, cy = y + h / 2;
            for (int i = 0; i < sides; i++) {
                double a = -Math.PI / 2 + i * 2 * Math.PI / sides;
                double px = cx + Math.cos (a) * w / 2;
                double py = cy + Math.sin (a) * h / 2;
                if (sides == 5) py = y + (Math.sin (a) + 1) / (1 + Math.sin (3 * Math.PI / 10)) * h;
                if (i == 0) cr.move_to (px, py);
                else cr.line_to (px, py);
            }
            cr.close_path ();
        }

        public static void ellipse (Cairo.Context cr, double x, double y, double w, double h) {
            if (w <= 0 || h <= 0) return;
            cr.save ();
            cr.translate (x + w / 2, y + h / 2);
            cr.scale (w / 2, h / 2);
            cr.new_sub_path ();
            cr.arc (0, 0, 1, 0, 2 * Math.PI);
            cr.close_path ();
            cr.restore ();
        }

        public static void round_rect (Cairo.Context cr, double x, double y, double w, double h, double r) {
            r = double.min (r, double.min (w, h) / 2);
            if (r <= 0.01) {
                cr.rectangle (x, y, w, h);
                return;
            }
            cr.new_sub_path ();
            cr.arc (x + w - r, y + r, r, -Math.PI / 2, 0);
            cr.arc (x + w - r, y + h - r, r, 0, Math.PI / 2);
            cr.arc (x + r, y + h - r, r, Math.PI / 2, Math.PI);
            cr.arc (x + r, y + r, r, Math.PI, 3 * Math.PI / 2);
            cr.close_path ();
        }

        public static bool uses_preset (ShapeElement s) {
            return s.shape != ShapeKind.CUSTOM && s.shape != ShapeKind.LINE && PresetGeometry.has (s.preset_name ());
        }

        public static Gee.HashMap<string, double?> adjust_of (ShapeElement s) {
            var m = new Gee.HashMap<string, double?> ();
            foreach (var e in s.adjust_values.entries) m[e.key] = e.value;
            if (s.shape == ShapeKind.ROUND_RECT && !m.has_key ("adj")) m["adj"] = s.corner.clamp (0, 0.5) * 100000;
            return m;
        }

        public static void path (Cairo.Context cr, ShapeElement s, double x, double y, double w, double h) {
            if (uses_preset (s)) {
                PresetGeometry.build (s.preset_name (), x, y, w, h, adjust_of (s), new CairoSink (cr));
                return;
            }
            double ss = double.min (w, h);
            switch (s.shape) {
                case ShapeKind.RECT:
                    cr.rectangle (x, y, w, h);
                    break;
                case ShapeKind.ROUND_RECT:
                    round_rect (cr, x, y, w, h, s.corner.clamp (0, 0.5) * ss);
                    break;
                case ShapeKind.ELLIPSE:
                    ellipse (cr, x, y, w, h);
                    break;
                case ShapeKind.TRIANGLE:
                    poly (cr, x, y, { w / 2, 0, w, h, 0, h });
                    break;
                case ShapeKind.RIGHT_TRIANGLE:
                    poly (cr, x, y, { 0, 0, w, h, 0, h });
                    break;
                case ShapeKind.DIAMOND:
                    poly (cr, x, y, { w / 2, 0, w, h / 2, w / 2, h, 0, h / 2 });
                    break;
                case ShapeKind.PARALLELOGRAM:
                    double a = ss * 0.25;
                    poly (cr, x, y, { a, 0, w, 0, w - a, h, 0, h });
                    break;
                case ShapeKind.TRAPEZOID:
                    double t = ss * 0.25;
                    poly (cr, x, y, { t, 0, w - t, 0, w, h, 0, h });
                    break;
                case ShapeKind.PENTAGON:
                    regular (cr, x, y, w, h, 5);
                    break;
                case ShapeKind.HEXAGON:
                    double hx = ss * 0.25;
                    poly (cr, x, y, { hx, 0, w - hx, 0, w, h / 2, w - hx, h, hx, h, 0, h / 2 });
                    break;
                case ShapeKind.OCTAGON:
                    double o = ss * 0.29289;
                    poly (cr, x, y, { o, 0, w - o, 0, w, o, w, h - o, w - o, h, o, h, 0, h - o, 0, o });
                    break;
                case ShapeKind.STAR4:
                    star (cr, x, y, w, h, 4, 0.25);
                    break;
                case ShapeKind.STAR5:
                    star (cr, x, y, w, h, 5, 0.38);
                    break;
                case ShapeKind.STAR6:
                    star (cr, x, y, w, h, 6, 0.55);
                    break;
                case ShapeKind.ARROW_RIGHT:
                    double hl = double.min (ss * 0.5, w);
                    poly (cr, x, y, { 0, h * 0.25, w - hl, h * 0.25, w - hl, 0, w, h / 2, w - hl, h, w - hl, h * 0.75, 0, h * 0.75 });
                    break;
                case ShapeKind.ARROW_LEFT:
                    double hl2 = double.min (ss * 0.5, w);
                    poly (cr, x, y, { w, h * 0.25, hl2, h * 0.25, hl2, 0, 0, h / 2, hl2, h, hl2, h * 0.75, w, h * 0.75 });
                    break;
                case ShapeKind.ARROW_UP:
                    double hu = double.min (ss * 0.5, h);
                    poly (cr, x, y, { w * 0.25, h, w * 0.25, hu, 0, hu, w / 2, 0, w, hu, w * 0.75, hu, w * 0.75, h });
                    break;
                case ShapeKind.ARROW_DOWN:
                    double hd = double.min (ss * 0.5, h);
                    poly (cr, x, y, { w * 0.25, 0, w * 0.75, 0, w * 0.75, h - hd, w, h - hd, w / 2, h, 0, h - hd, w * 0.25, h - hd });
                    break;
                case ShapeKind.ARROW_LEFT_RIGHT:
                    double hb = double.min (ss * 0.5, w / 2);
                    poly (cr, x, y, { 0, h / 2, hb, 0, hb, h * 0.25, w - hb, h * 0.25, w - hb, 0, w, h / 2, w - hb, h, w - hb, h * 0.75, hb, h * 0.75, hb, h });
                    break;
                case ShapeKind.CHEVRON:
                    double c = double.min (ss * 0.5, w / 2);
                    poly (cr, x, y, { 0, 0, w - c, 0, w, h / 2, w - c, h, 0, h, c, h / 2 });
                    break;
                case ShapeKind.HOME_PLATE:
                    double hp = double.min (ss * 0.5, w);
                    poly (cr, x, y, { 0, 0, w - hp, 0, w, h / 2, w - hp, h, 0, h });
                    break;
                case ShapeKind.PLUS:
                    double p = ss * 0.25;
                    double px1 = (w - (w - 2 * p)) / 2, py1 = p;
                    poly (cr, x, y, { px1, 0, w - px1, 0, w - px1, py1, w, py1, w, h - py1, w - px1, h - py1, w - px1, h, px1, h, px1, h - py1, 0, h - py1, 0, py1, px1, py1 });
                    break;
                case ShapeKind.HEART:
                    cr.move_to (x + w / 2, y + h * 0.25);
                    cr.curve_to (x + w / 2, y - h * 0.05, x + w * 1.05, y - h * 0.05, x + w * 0.98, y + h * 0.32);
                    cr.curve_to (x + w * 0.92, y + h * 0.6, x + w * 0.6, y + h * 0.78, x + w / 2, y + h);
                    cr.curve_to (x + w * 0.4, y + h * 0.78, x + w * 0.08, y + h * 0.6, x + w * 0.02, y + h * 0.32);
                    cr.curve_to (x - w * 0.05, y - h * 0.05, x + w / 2, y - h * 0.05, x + w / 2, y + h * 0.25);
                    cr.close_path ();
                    break;
                case ShapeKind.CLOUD:
                    int bumps = 9;
                    double cx = x + w / 2, cy = y + h / 2;
                    double rx = w * 0.42, ry = h * 0.38;
                    for (int i = 0; i <= bumps; i++) {
                        double a0 = 2 * Math.PI * i / bumps;
                        double px = cx + Math.cos (a0) * rx, py = cy + Math.sin (a0) * ry;
                        if (i == 0) {
                            cr.move_to (px, py);
                            continue;
                        }
                        double am = 2 * Math.PI * (i - 0.5) / bumps;
                        double qx = cx + Math.cos (am) * rx * 1.42, qy = cy + Math.sin (am) * ry * 1.42;
                        double lx, ly;
                        cr.get_current_point (out lx, out ly);
                        cr.curve_to (lx + (qx - lx) * 0.9, ly + (qy - ly) * 0.9, px + (qx - px) * 0.9, py + (qy - py) * 0.9, px, py);
                    }
                    cr.close_path ();
                    break;
                case ShapeKind.DONUT:
                    double d = ss * 0.25;
                    ellipse (cr, x, y, w, h);
                    cr.save ();
                    cr.translate (x + w / 2, y + h / 2);
                    cr.scale ((w / 2 - d), (h / 2 - d));
                    cr.new_sub_path ();
                    cr.arc_negative (0, 0, 1, 2 * Math.PI, 0);
                    cr.close_path ();
                    cr.restore ();
                    break;
                case ShapeKind.CALLOUT:
                    double r = ss * 0.16;
                    double bh = h;
                    double tx1 = x + w * 0.2, tx2 = x + w * 0.36;
                    double tipx = x + w * 0.1, tipy = y + h * 1.25;
                    cr.new_sub_path ();
                    cr.arc (x + w - r, y + r, r, -Math.PI / 2, 0);
                    cr.arc (x + w - r, y + bh - r, r, 0, Math.PI / 2);
                    cr.line_to (tx2, y + bh);
                    cr.line_to (tipx, tipy);
                    cr.line_to (tx1, y + bh);
                    cr.arc (x + r, y + bh - r, r, Math.PI / 2, Math.PI);
                    cr.arc (x + r, y + r, r, Math.PI, 3 * Math.PI / 2);
                    cr.close_path ();
                    break;
                case ShapeKind.LINE:
                    double x1 = s.flip_h ? x + w : x, y1 = s.flip_v ? y + h : y;
                    double x2 = s.flip_h ? x : x + w, y2 = s.flip_v ? y : y + h;
                    cr.move_to (x1, y1);
                    cr.line_to (x2, y2);
                    break;
                case ShapeKind.CUSTOM:
                    custom (cr, s.path, x, y, w, h);
                    break;
                case ShapeKind.PRESET:
                    cr.rectangle (x, y, w, h);
                    break;
            }
        }

        public static void custom (Cairo.Context cr, Gee.List<PathCommand> cmds, double x, double y, double w, double h) {
            foreach (var c in cmds) {
                switch (c.op) {
                    case 'M':
                        cr.move_to (x + c.pts[0] * w, y + c.pts[1] * h);
                        break;
                    case 'L':
                        cr.line_to (x + c.pts[0] * w, y + c.pts[1] * h);
                        break;
                    case 'C':
                        cr.curve_to (x + c.pts[0] * w, y + c.pts[1] * h, x + c.pts[2] * w, y + c.pts[3] * h, x + c.pts[4] * w, y + c.pts[5] * h);
                        break;
                    case 'Q':
                        double lx, ly;
                        if (!cr.has_current_point ()) cr.move_to (x, y);
                        cr.get_current_point (out lx, out ly);
                        double qx = x + c.pts[0] * w, qy = y + c.pts[1] * h;
                        double ex = x + c.pts[2] * w, ey = y + c.pts[3] * h;
                        cr.curve_to (lx + 2.0 / 3 * (qx - lx), ly + 2.0 / 3 * (qy - ly), ex + 2.0 / 3 * (qx - ex), ey + 2.0 / 3 * (qy - ey), ex, ey);
                        break;
                    case 'Z':
                        cr.close_path ();
                        break;
                }
            }
        }

        public static bool is_closed (ShapeElement s) {
            if (s.shape == ShapeKind.LINE) return false;
            if (s.shape != ShapeKind.CUSTOM) return true;
            foreach (var c in s.path) if (c.op == 'Z') return true;
            return false;
        }

        public static void text_rect (ShapeElement s, double x, double y, double w, double h, out double tx, out double ty, out double tw, out double th) {
            tx = x;
            ty = y;
            tw = w;
            th = h;
            if (s.shape != ShapeKind.RECT && s.shape != ShapeKind.ROUND_RECT && uses_preset (s) && !s.text_box) {
                double rx, ry, rw, rh;
                if (PresetGeometry.text_rect (s.preset_name (), x, y, w, h, adjust_of (s), out rx, out ry, out rw, out rh) && rw > 1 && rh > 1) {
                    tx = rx;
                    ty = ry;
                    tw = rw;
                    th = rh;
                }
                return;
            }
            switch (s.shape) {
                case ShapeKind.ELLIPSE:
                case ShapeKind.CLOUD:
                    tx = x + w * 0.146;
                    ty = y + h * 0.146;
                    tw = w * 0.708;
                    th = h * 0.708;
                    break;
                case ShapeKind.TRIANGLE:
                    tx = x + w * 0.25;
                    ty = y + h * 0.5;
                    tw = w * 0.5;
                    th = h * 0.5;
                    break;
                case ShapeKind.DIAMOND:
                    tx = x + w * 0.25;
                    ty = y + h * 0.25;
                    tw = w * 0.5;
                    th = h * 0.5;
                    break;
                case ShapeKind.CALLOUT:
                    break;
                case ShapeKind.STAR5:
                case ShapeKind.STAR6:
                case ShapeKind.STAR4:
                    tx = x + w * 0.25;
                    ty = y + h * 0.3;
                    tw = w * 0.5;
                    th = h * 0.45;
                    break;
                default:
                    break;
            }
        }

        public static void arrow_head (Cairo.Context cr, ArrowKind kind, double x, double y, double from_x, double from_y, double width) {
            if (kind == ArrowKind.NONE) return;
            double a = Math.atan2 (y - from_y, x - from_x);
            double len = double.max (width * 3.5, 6);
            double half = len * 0.5;
            cr.save ();
            cr.translate (x, y);
            cr.rotate (a);
            cr.new_path ();
            switch (kind) {
                case ArrowKind.TRIANGLE:
                    cr.move_to (0, 0);
                    cr.line_to (-len, -half);
                    cr.line_to (-len, half);
                    cr.close_path ();
                    cr.fill ();
                    break;
                case ArrowKind.ARROW:
                    cr.move_to (-len, -half);
                    cr.line_to (0, 0);
                    cr.line_to (-len, half);
                    cr.set_line_width (width);
                    cr.stroke ();
                    break;
                case ArrowKind.OVAL:
                    cr.arc (-half * 0.6, 0, half * 0.7, 0, 2 * Math.PI);
                    cr.fill ();
                    break;
                case ArrowKind.DIAMOND:
                    cr.move_to (0, 0);
                    cr.line_to (-half, -half);
                    cr.line_to (-len, 0);
                    cr.line_to (-half, half);
                    cr.close_path ();
                    cr.fill ();
                    break;
                default:
                    break;
            }
            cr.restore ();
        }
    }
}
