namespace Singularity.Apps.Slides {

    public interface PathSink : Object {
        public abstract void move_to (double x, double y);
        public abstract void line_to (double x, double y);
        public abstract void curve_to (double x1, double y1, double x2, double y2, double x3, double y3);
        public abstract void close_path ();
    }

    public class CairoSink : Object, PathSink {
        private Cairo.Context cr;

        public CairoSink (Cairo.Context cr) {
            this.cr = cr;
        }

        public void move_to (double x, double y) {
            cr.move_to (x, y);
        }

        public void line_to (double x, double y) {
            cr.line_to (x, y);
        }

        public void curve_to (double x1, double y1, double x2, double y2, double x3, double y3) {
            cr.curve_to (x1, y1, x2, y2, x3, y3);
        }

        public void close_path () {
            cr.close_path ();
        }
    }

    public class PresetPath {
        public bool fill;
        public bool stroke;
        public string fill_mode;
        public bool extrusion_ok;
    }

    public class AdjustHandle {
        public bool polar;
        public string? gd_x;
        public string? gd_y;
        public string? gd_r;
        public string? gd_ang;
        public double min_x;
        public double max_x;
        public double min_y;
        public double max_y;
        public double min_r;
        public double max_r;
        public double min_ang;
        public double max_ang;
        public double px;
        public double py;
    }

    public delegate void PathCallback (PresetPath info);

    internal class PresetGuide {
        public string name;
        public string[] fmla;
    }

    internal class PresetRow {
        public string[] t;

        public PresetRow (string[] t) {
            this.t = t;
        }
    }

    internal class PresetPathDef {
        public double w;
        public double h;
        public string fill_mode;
        public bool stroke;
        public bool extrusion_ok;
        public Gee.ArrayList<PresetRow> commands = new Gee.ArrayList<PresetRow> ();
    }

    internal class PresetShape {
        public Gee.ArrayList<PresetGuide> av = new Gee.ArrayList<PresetGuide> ();
        public Gee.ArrayList<PresetGuide> gd = new Gee.ArrayList<PresetGuide> ();
        public Gee.ArrayList<PresetRow> handles = new Gee.ArrayList<PresetRow> ();
        public Gee.ArrayList<PresetRow> cxn = new Gee.ArrayList<PresetRow> ();
        public string[]? rect;
        public Gee.ArrayList<PresetPathDef> paths = new Gee.ArrayList<PresetPathDef> ();
    }

    internal class PresetEval {
        private Gee.HashMap<string, double?> vars = new Gee.HashMap<string, double?> ();
        private double w;
        private double h;

        public PresetEval (PresetShape shape, double w, double h, Gee.Map<string, double?>? adjust) {
            this.w = w;
            this.h = h;
            foreach (var g in shape.av) {
                double? v = adjust != null && adjust.has_key (g.name) ? adjust[g.name] : null;
                vars[g.name] = v != null ? v : formula (g.fmla);
            }
            foreach (var g in shape.gd) vars[g.name] = formula (g.fmla);
        }

        public double get (string token) {
            double? v = vars[token];
            if (v != null) return v;
            double ss = double.min (w, h), n;
            switch (token) {
                case "w":
                case "r":
                    return w;
                case "h":
                case "b":
                    return h;
                case "l":
                case "t":
                    return 0;
                case "hc":
                    return w / 2;
                case "vc":
                    return h / 2;
                case "ss":
                    return ss;
                case "ls":
                    return double.max (w, h);
            }
            if (double.try_parse (token, out n)) return n;
            if (token.has_prefix ("ssd") && double.try_parse (token.substring (3), out n)) return ss / n;
            if (token.has_prefix ("wd") && double.try_parse (token.substring (2), out n)) return w / n;
            if (token.has_prefix ("hd") && double.try_parse (token.substring (2), out n)) return h / n;
            int i = token.index_of ("cd");
            if (i >= 0 && double.try_parse (token.substring (i + 2), out n)) {
                double k = i == 0 ? 1 : double.parse (token.substring (0, i));
                return k * 21600000 / n;
            }
            return 0;
        }

        private static double rad (double a) {
            return a / 60000 * Math.PI / 180;
        }

        private static double div (double a, double b) {
            return b == 0 ? 0 : a / b;
        }

        private double formula (string[] f) {
            double x = f.length > 1 ? get (f[1]) : 0;
            double y = f.length > 2 ? get (f[2]) : 0;
            double z = f.length > 3 ? get (f[3]) : 0;
            switch (f[0]) {
                case "*/":
                    return div (x * y, z);
                case "+-":
                    return x + y - z;
                case "+/":
                    return div (x + y, z);
                case "?:":
                    return x > 0 ? y : z;
                case "abs":
                    return x.abs ();
                case "at2":
                    return Math.atan2 (y, x) * 180 / Math.PI * 60000;
                case "cat2":
                    return x * Math.cos (Math.atan2 (z, y));
                case "sat2":
                    return x * Math.sin (Math.atan2 (z, y));
                case "cos":
                    return x * Math.cos (rad (y));
                case "sin":
                    return x * Math.sin (rad (y));
                case "tan":
                    return x * Math.tan (rad (y));
                case "max":
                    return double.max (x, y);
                case "min":
                    return double.min (x, y);
                case "mod":
                    return Math.sqrt (x * x + y * y + z * z);
                case "pin":
                    return y < x ? x : (y > z ? z : y);
                case "sqrt":
                    return Math.sqrt (double.max (x, 0));
                default:
                    return x;
            }
        }
    }

    internal class PresetEmitter {
        private PathSink sink;
        private double ox;
        private double oy;
        private double sx = 1;
        private double sy = 1;
        private double cx;
        private double cy;
        private double start_x;
        private double start_y;
        private bool open;

        public PresetEmitter (PathSink sink, double ox, double oy) {
            this.sink = sink;
            this.ox = ox;
            this.oy = oy;
        }

        public void begin (double sx, double sy) {
            this.sx = sx;
            this.sy = sy;
            cx = cy = start_x = start_y = 0;
            open = false;
        }

        private void ensure () {
            if (open) return;
            sink.move_to (ox + cx * sx, oy + cy * sy);
            start_x = cx;
            start_y = cy;
            open = true;
        }

        public void move (double x, double y) {
            cx = start_x = x;
            cy = start_y = y;
            sink.move_to (ox + x * sx, oy + y * sy);
            open = true;
        }

        public void line (double x, double y) {
            ensure ();
            cx = x;
            cy = y;
            sink.line_to (ox + x * sx, oy + y * sy);
        }

        public void cubic (double x1, double y1, double x2, double y2, double x3, double y3) {
            ensure ();
            cx = x3;
            cy = y3;
            sink.curve_to (ox + x1 * sx, oy + y1 * sy, ox + x2 * sx, oy + y2 * sy, ox + x3 * sx, oy + y3 * sy);
        }

        public void quad (double qx, double qy, double x, double y) {
            double x0 = cx, y0 = cy;
            cubic (x0 + 2.0 / 3 * (qx - x0), y0 + 2.0 / 3 * (qy - y0), x + 2.0 / 3 * (qx - x), y + 2.0 / 3 * (qy - y), x, y);
        }

        private static double param (double a, double rx, double ry) {
            return Math.atan2 (rx * Math.sin (a), ry * Math.cos (a));
        }

        public void arc (double rx, double ry, double st, double sw) {
            ensure ();
            double a0 = st / 60000 * Math.PI / 180;
            double da = sw / 60000 * Math.PI / 180;
            double t0 = param (a0, rx, ry);
            double dt = param (a0 + da, rx, ry) - t0;
            dt += 2 * Math.PI * Math.round ((da - dt) / (2 * Math.PI));
            if (dt == 0) return;
            double ex = cx - rx * Math.cos (t0), ey = cy - ry * Math.sin (t0);
            int n = int.max (1, (int) Math.ceil (dt.abs () / (Math.PI / 2) - 1e-9));
            double step = dt / n, k = 4.0 / 3 * Math.tan (step / 4);
            for (int i = 0; i < n; i++) {
                double u0 = t0 + step * i, u1 = u0 + step;
                double c0 = Math.cos (u0), s0 = Math.sin (u0), c1 = Math.cos (u1), s1 = Math.sin (u1);
                cubic (ex + rx * (c0 - k * s0), ey + ry * (s0 + k * c0), ex + rx * (c1 + k * s1), ey + ry * (s1 - k * c1), ex + rx * c1, ey + ry * s1);
            }
        }

        public void close () {
            if (!open) return;
            sink.close_path ();
            cx = start_x;
            cy = start_y;
            open = false;
        }
    }

    public class PresetGeometry {
        private static Gee.HashMap<string, PresetShape>? shapes;
        private static Gee.ArrayList<string> order;

        private static void load () {
            if (shapes != null) return;
            shapes = new Gee.HashMap<string, PresetShape> ();
            order = new Gee.ArrayList<string> ();
            PresetShape? shape = null;
            PresetPathDef? path = null;
            foreach (string line in PresetData.DATA.split ("\n")) {
                if (line == "") continue;
                if (line[0] == '#') {
                    string name = line.substring (1);
                    shape = new PresetShape ();
                    path = null;
                    shapes[name] = shape;
                    order.add (name);
                    continue;
                }
                string[] parts = line.split (" ");
                string[] args = parts[1:parts.length];
                switch (parts[0]) {
                    case "a":
                    case "g":
                        var g = new PresetGuide ();
                        g.name = args[0];
                        g.fmla = args[1:args.length];
                        (parts[0] == "a" ? shape.av : shape.gd).add (g);
                        break;
                    case "x":
                    case "p":
                        shape.handles.add (new PresetRow (parts));
                        break;
                    case "c":
                        shape.cxn.add (new PresetRow (args));
                        break;
                    case "r":
                        shape.rect = args;
                        break;
                    case "P":
                        path = new PresetPathDef ();
                        path.w = double.parse (args[0]);
                        path.h = double.parse (args[1]);
                        path.fill_mode = fill_mode (args[2]);
                        path.stroke = args[3] == "1";
                        path.extrusion_ok = args[4] == "1";
                        shape.paths.add (path);
                        break;
                    default:
                        path.commands.add (new PresetRow (parts));
                        break;
                }
            }
        }

        private static string fill_mode (string code) {
            switch (code) {
                case "x":
                    return "none";
                case "l":
                    return "lighten";
                case "L":
                    return "lightenLess";
                case "d":
                    return "darken";
                case "D":
                    return "darkenLess";
                default:
                    return "norm";
            }
        }

        private static PresetShape? lookup (string name) {
            load ();
            return shapes[name];
        }

        public static bool has (string name) {
            return lookup (name) != null;
        }

        public static string[] names () {
            load ();
            return order.to_array ();
        }

        public static Gee.HashMap<string, double?> defaults (string name) {
            var map = new Gee.HashMap<string, double?> ();
            var shape = lookup (name);
            if (shape == null) return map;
            var ev = new PresetEval (shape, 0, 0, null);
            foreach (var g in shape.av) map[g.name] = ev.get (g.name);
            return map;
        }

        public static Gee.ArrayList<PresetPath> build (string name, double x, double y, double w, double h, Gee.Map<string, double?>? adjust, PathSink sink) {
            var list = new Gee.ArrayList<PresetPath> ();
            build_each (name, x, y, w, h, adjust, sink, (info) => list.add (info));
            return list;
        }

        public static void build_each (string name, double x, double y, double w, double h, Gee.Map<string, double?>? adjust, PathSink sink, PathCallback after_each) {
            var shape = lookup (name);
            if (shape == null) return;
            var ev = new PresetEval (shape, w, h, adjust);
            var em = new PresetEmitter (sink, x, y);
            foreach (var p in shape.paths) {
                em.begin (p.w > 0 ? w / p.w : 1, p.h > 0 ? h / p.h : 1);
                foreach (var row in p.commands) {
                    unowned string[] c = row.t;
                    switch (c[0]) {
                        case "M":
                            em.move (ev.get (c[1]), ev.get (c[2]));
                            break;
                        case "L":
                            em.line (ev.get (c[1]), ev.get (c[2]));
                            break;
                        case "A":
                            em.arc (ev.get (c[1]), ev.get (c[2]), ev.get (c[3]), ev.get (c[4]));
                            break;
                        case "Q":
                            em.quad (ev.get (c[1]), ev.get (c[2]), ev.get (c[3]), ev.get (c[4]));
                            break;
                        case "C":
                            em.cubic (ev.get (c[1]), ev.get (c[2]), ev.get (c[3]), ev.get (c[4]), ev.get (c[5]), ev.get (c[6]));
                            break;
                        case "Z":
                            em.close ();
                            break;
                    }
                }
                var info = new PresetPath ();
                info.fill_mode = p.fill_mode;
                info.fill = p.fill_mode != "none";
                info.stroke = p.stroke;
                info.extrusion_ok = p.extrusion_ok;
                after_each (info);
            }
        }

        public static bool text_rect (string name, double x, double y, double w, double h, Gee.Map<string, double?>? adjust, out double tx, out double ty, out double tw, out double th) {
            tx = x;
            ty = y;
            tw = w;
            th = h;
            var shape = lookup (name);
            if (shape == null || shape.rect == null) return false;
            var ev = new PresetEval (shape, w, h, adjust);
            double l = ev.get (shape.rect[0]), t = ev.get (shape.rect[1]);
            tx = x + l;
            ty = y + t;
            tw = ev.get (shape.rect[2]) - l;
            th = ev.get (shape.rect[3]) - t;
            return true;
        }

        private static double limit (PresetEval ev, string token) {
            return token == "-" ? 0 : ev.get (token);
        }

        private static string? ref_name (string token) {
            return token == "-" ? null : token;
        }

        public static Gee.ArrayList<AdjustHandle> handles (string name, double x, double y, double w, double h, Gee.Map<string, double?>? adjust) {
            var list = new Gee.ArrayList<AdjustHandle> ();
            var shape = lookup (name);
            if (shape == null) return list;
            var ev = new PresetEval (shape, w, h, adjust);
            foreach (var row in shape.handles) {
                unowned string[] d = row.t;
                var a = new AdjustHandle ();
                a.polar = d[0] == "p";
                if (a.polar) {
                    a.gd_r = ref_name (d[1]);
                    a.min_r = limit (ev, d[2]);
                    a.max_r = limit (ev, d[3]);
                    a.gd_ang = ref_name (d[4]);
                    a.min_ang = limit (ev, d[5]);
                    a.max_ang = limit (ev, d[6]);
                } else {
                    a.gd_x = ref_name (d[1]);
                    a.min_x = limit (ev, d[2]);
                    a.max_x = limit (ev, d[3]);
                    a.gd_y = ref_name (d[4]);
                    a.min_y = limit (ev, d[5]);
                    a.max_y = limit (ev, d[6]);
                }
                a.px = x + ev.get (d[7]);
                a.py = y + ev.get (d[8]);
                list.add (a);
            }
            return list;
        }

        public static Gee.ArrayList<double?> connection_sites (string name, double x, double y, double w, double h, Gee.Map<string, double?>? adjust) {
            var list = new Gee.ArrayList<double?> ();
            var shape = lookup (name);
            if (shape == null) return list;
            var ev = new PresetEval (shape, w, h, adjust);
            foreach (var c in shape.cxn) {
                list.add (x + ev.get (c.t[1]));
                list.add (y + ev.get (c.t[2]));
            }
            return list;
        }
    }
}
