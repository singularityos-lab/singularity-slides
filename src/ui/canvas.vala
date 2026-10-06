using Gtk;

namespace Singularity.Apps.Slides {

    public enum DragMode {
        NONE,
        MOVE,
        RESIZE,
        ROTATE,
        RUBBER,
        LINE_START,
        LINE_END,
        CROP,
        CROP_PAN,
        TABLE_COL,
        TABLE_ROW,
        INK,
        SCRIBBLE,
        ADJUST,
        POINT,
        GUIDE,
        COMMENT
    }

    public enum CanvasTool {
        SELECT,
        INK_PEN,
        INK_HIGHLIGHTER,
        INK_ERASER,
        FREEFORM,
        SCRIBBLE,
        MOTION_PATH,
        PAINTER
    }

    public class FormatClip {
        public Fill? fill = null;
        public Line? line = null;
        public Shadow? shadow = null;
        public ShapeEffects? effects = null;
        public TextRun? run = null;
        public Paragraph? para = null;

        public static FormatClip from (Element e) {
            var c = new FormatClip ();
            c.line = e.line.clone ();
            c.shadow = e.shadow.clone ();
            var s = e as ShapeElement;
            if (s != null) {
                c.fill = s.fill.clone ();
                c.effects = s.effects.clone ();
                if (s.text != null && s.text.paragraphs.size > 0) {
                    c.para = s.text.paragraphs[0].clone ();
                    var r = new TextRun ();
                    s.text.first_run_format (r);
                    c.run = r;
                }
            }
            return c;
        }

        public void apply (Element e) {
            if (line != null) e.line = line.clone ();
            if (shadow != null) e.shadow = shadow.clone ();
            var s = e as ShapeElement;
            if (s == null) return;
            if (fill != null && s.shape != ShapeKind.LINE) s.fill = fill.clone ();
            if (effects != null) s.effects = effects.clone ();
            if (run != null && s.text != null) {
                var fmt = run;
                s.text.apply_to_runs ((r) => {
                    string t = r.text;
                    string link = r.link;
                    string field = r.field;
                    r.copy_format (fmt);
                    r.text = t;
                    r.link = link;
                    r.field = field;
                });
            }
            if (para != null && s.text != null) {
                foreach (var p in s.text.paragraphs) {
                    p.align = para.align;
                    p.line_spacing = para.line_spacing;
                    p.space_before = para.space_before;
                    p.space_after = para.space_after;
                }
            }
        }
    }

    private class Snapshot0 {
        public Element element;
        public double x;
        public double y;
        public double w;
        public double h;
        public double rotation;
        public Element copy;

        public Snapshot0 (Element e) {
            element = e;
            x = e.x;
            y = e.y;
            w = e.w;
            h = e.h;
            rotation = e.rotation;
            copy = e.clone ();
        }
    }

    public class SlideCanvas : Widget {
        public signal void selection_changed ();
        public signal void edited ();
        public signal void context_requested (double x, double y);
        public signal void zoom_changed ();
        public signal void editing_changed ();
        public signal void page_requested (int delta);
        public signal void double_clicked_empty ();

        public Document? doc = null;
        public Slide? slide = null;
        public Layout? layout = null;
        public Master? master = null;
        public Gee.ArrayList<Element> selection = new Gee.ArrayList<Element> ();
        public Renderer renderer = new Renderer ();
        public double zoom = 0;
        public double scale = 1;
        public double ox = 0;
        public double oy = 0;
        public bool snap = true;
        public bool show_badges = false;
        public TextEditor? editor = null;
        private TextEditor? editor_instance = null;
        private bool edit_select_all = true;
        private int edit_cursor = -1;
        public bool crop_mode = false;
        public int cell_r1 = -1;
        public int cell_c1 = -1;
        public int cell_r2 = -1;
        public int cell_c2 = -1;

        private const double MARGIN = 36;
        private const double HANDLE = 8;
        private DragMode mode = DragMode.NONE;
        private int handle_x = 0;
        private int handle_y = 0;
        private double press_x = 0;
        private double press_y = 0;
        private double last_x = 0;
        private double last_y = 0;
        private bool drag_started = false;
        private bool drag_copy = false;
        private Gee.ArrayList<Snapshot0> drag_orig = new Gee.ArrayList<Snapshot0> ();
        private double rubber_x2 = 0;
        private double rubber_y2 = 0;
        private Gee.ArrayList<double?> vguides = new Gee.ArrayList<double?> ();
        private Gee.ArrayList<double?> hguides = new Gee.ArrayList<double?> ();
        private Gee.ArrayList<double?> spacing_marks = new Gee.ArrayList<double?> ();
        private Element? hover = null;
        private int table_line = -1;
        private double table_orig = 0;
        private double table_next = 0;
        private GestureDrag drag_gesture;
        private int edit_click_x = -1;
        private int edit_click_y = -1;


        public CanvasTool tool = CanvasTool.SELECT;
        public string ink_color = "#d32f2f";
        public double ink_width = 3;
        public bool points_mode = false;
        public bool show_comments = false;
        public Comment? active_comment = null;
        public Animation? path_animation = null;
        public FormatClip? painter = null;
        public bool painter_sticky = false;
        public signal void comment_clicked (Comment c);
        public signal void tool_changed ();
        private InkElement? live_ink = null;
        private InkStroke? live_stroke = null;
        private Gee.ArrayList<double?> free_pts = new Gee.ArrayList<double?> ();
        private int adjust_index = -1;
        private int point_index = -1;
        private double guide_orig = 0;
        private int guide_index = -1;
        private Comment? drag_comment = null;
        private double hover_x = -1;
        private double hover_y = -1;

        public void set_tool (CanvasTool t) {
            if (tool == t && t != CanvasTool.SELECT) t = CanvasTool.SELECT;
            finish_freeform (false);
            tool = t;
            live_ink = null;
            live_stroke = null;
            if (t != CanvasTool.SELECT) {
                commit_edit ();
                clear_selection ();
            }
            set_cursor_from_name (t == CanvasTool.SELECT ? "default" : "crosshair");
            tool_changed ();
            queue_draw ();
        }

        private Gee.ArrayList<AdjustHandle> adjust_handles () {
            if (selection.size != 1) return new Gee.ArrayList<AdjustHandle> ();
            var s = selection[0] as ShapeElement;
            if (s == null || s.locked || !Geometry.uses_preset (s) || s.shape == ShapeKind.RECT) return new Gee.ArrayList<AdjustHandle> ();
            double x, y, w, h;
            geometry_of (s, out x, out y, out w, out h);
            return PresetGeometry.handles (s.preset_name (), x, y, w, h, Geometry.adjust_of (s));
        }

        private void handle_to_slide (Element e, double px, double py, out double sx, out double sy) {
            double x, y, w, h;
            geometry_of (e, out x, out y, out w, out h);
            double cx = x + w / 2, cy = y + h / 2;
            if (e.flip_h) px = 2 * cx - px;
            if (e.flip_v) py = 2 * cy - py;
            rotate_point (e, px, py, out sx, out sy);
        }

        private int hit_adjust (double wx, double wy) {
            if (selection.size != 1 || editor != null) return -1;
            var list = adjust_handles ();
            for (int i = 0; i < list.size; i++) {
                double sx, sy, a, b;
                handle_to_slide (selection[0], list[i].px, list[i].py, out sx, out sy);
                to_widget (sx, sy, out a, out b);
                if (Math.fabs (a - wx) <= HANDLE && Math.fabs (b - wy) <= HANDLE) return i;
            }
            return -1;
        }

        private void unrotate (Element e, double sx, double sy, out double lx, out double ly) {
            double x, y, w, h;
            geometry_of (e, out x, out y, out w, out h);
            double cx = x + w / 2, cy = y + h / 2;
            double a = -e.rotation * Math.PI / 180;
            double dx = sx - cx, dy = sy - cy;
            lx = cx + dx * Math.cos (a) - dy * Math.sin (a);
            ly = cy + dx * Math.sin (a) + dy * Math.cos (a);
            if (e.flip_h) lx = 2 * cx - lx;
            if (e.flip_v) ly = 2 * cy - ly;
        }

        private double solve_adjust (ShapeElement s, string gd, double min, double max, bool polar, bool use_x, double target_x, double target_y) {
            double x, y, w, h;
            geometry_of (s, out x, out y, out w, out h);
            var adj = Geometry.adjust_of (s);
            double best = adj.has_key (gd) ? adj[gd] : (min + max) / 2;
            double best_d = double.MAX;
            int steps = 96;
            double lo = min, hi = max;
            for (int round = 0; round < 3; round++) {
                double step = (hi - lo) / steps;
                if (step <= 0) break;
                for (int i = 0; i <= steps; i++) {
                    double v = lo + step * i;
                    adj[gd] = v;
                    var hs = PresetGeometry.handles (s.preset_name (), x, y, w, h, adj);
                    foreach (var hh in hs) {
                        if (hh.polar ? (hh.gd_r != gd && hh.gd_ang != gd) : (hh.gd_x != gd && hh.gd_y != gd)) continue;
                        double d;
                        if (polar) d = Math.hypot (hh.px - target_x, hh.py - target_y);
                        else d = use_x ? Math.fabs (hh.px - target_x) : Math.fabs (hh.py - target_y);
                        if (d < best_d) {
                            best_d = d;
                            best = v;
                        }
                    }
                }
                lo = double.max (min, best - step * 2);
                hi = double.min (max, best + step * 2);
            }
            return best;
        }

        private void drag_adjust (double sx, double sy) {
            var s = selection[0] as ShapeElement;
            if (s == null) return;
            var list = adjust_handles ();
            if (adjust_index < 0 || adjust_index >= list.size) return;
            var hd = list[adjust_index];
            double lx, ly;
            unrotate (s, sx, sy, out lx, out ly);
            if (hd.polar) {
                if (hd.gd_ang != null) s.adjust_values[hd.gd_ang] = solve_adjust (s, hd.gd_ang, hd.min_ang, hd.max_ang, true, false, lx, ly);
                if (hd.gd_r != null) s.adjust_values[hd.gd_r] = solve_adjust (s, hd.gd_r, hd.min_r, hd.max_r, true, false, lx, ly);
            } else {
                if (hd.gd_x != null) s.adjust_values[hd.gd_x] = solve_adjust (s, hd.gd_x, hd.min_x, hd.max_x, false, true, lx, ly);
                if (hd.gd_y != null) s.adjust_values[hd.gd_y] = solve_adjust (s, hd.gd_y, hd.min_y, hd.max_y, false, false, lx, ly);
            }
            if (s.shape == ShapeKind.ROUND_RECT && s.adjust_values.has_key ("adj")) {
                s.corner = s.adjust_values["adj"] / 100000;
                s.adjust_values.unset ("adj");
            }
        }

        private void draw_adjust_handles (Cairo.Context cr) {
            if (selection.size != 1 || editor != null || tool != CanvasTool.SELECT || points_mode) return;
            foreach (var hd in adjust_handles ()) {
                double sx, sy, a, b;
                handle_to_slide (selection[0], hd.px, hd.py, out sx, out sy);
                to_widget (sx, sy, out a, out b);
                cr.new_path ();
                cr.move_to (a, b - 6);
                cr.line_to (a + 6, b);
                cr.line_to (a, b + 6);
                cr.line_to (a - 6, b);
                cr.close_path ();
                cr.set_source_rgb (1, 0.8, 0.1);
                cr.fill_preserve ();
                cr.set_source_rgba (0, 0, 0, 0.6);
                cr.set_line_width (1);
                cr.stroke ();
            }
        }

        private class PointRef {
            public int cmd;
            public int idx;
            public bool control;

            public PointRef (int cmd, int idx, bool control) {
                this.cmd = cmd;
                this.idx = idx;
                this.control = control;
            }
        }

        private Gee.ArrayList<PointRef> point_refs (ShapeElement s) {
            var list = new Gee.ArrayList<PointRef> ();
            for (int i = 0; i < s.path.size; i++) {
                var c = s.path[i];
                if (c.op == 'Z') continue;
                int n = c.pts.length / 2;
                for (int k = 0; k < n; k++) list.add (new PointRef (i, k, k < n - 1));
            }
            return list;
        }

        private void point_slide (ShapeElement s, PointRef r, out double sx, out double sy) {
            double x, y, w, h;
            geometry_of (s, out x, out y, out w, out h);
            var c = s.path[r.cmd];
            handle_to_slide (s, x + c.pts[r.idx * 2] * w, y + c.pts[r.idx * 2 + 1] * h, out sx, out sy);
        }

        private int hit_point (double wx, double wy) {
            if (!points_mode || selection.size != 1) return -1;
            var s = selection[0] as ShapeElement;
            if (s == null || s.shape != ShapeKind.CUSTOM) return -1;
            var refs = point_refs (s);
            for (int i = refs.size - 1; i >= 0; i--) {
                double sx, sy, a, b;
                point_slide (s, refs[i], out sx, out sy);
                to_widget (sx, sy, out a, out b);
                if (Math.fabs (a - wx) <= HANDLE && Math.fabs (b - wy) <= HANDLE) return i;
            }
            return -1;
        }

        private void drag_point (double sx, double sy) {
            var s = selection[0] as ShapeElement;
            if (s == null) return;
            var refs = point_refs (s);
            if (point_index < 0 || point_index >= refs.size) return;
            var r = refs[point_index];
            double x, y, w, h;
            geometry_of (s, out x, out y, out w, out h);
            double lx, ly;
            unrotate (s, sx, sy, out lx, out ly);
            double nx = w > 0 ? (lx - x) / w : 0, ny = h > 0 ? (ly - y) / h : 0;
            var c = s.path[r.cmd];
            double dx = nx - c.pts[r.idx * 2], dy = ny - c.pts[r.idx * 2 + 1];
            var pts = c.pts;
            pts[r.idx * 2] = nx;
            pts[r.idx * 2 + 1] = ny;
            if (!r.control) {
                if (c.op == 'C' && pts.length >= 6) {
                    pts[2] += dx;
                    pts[3] += dy;
                }
                if (r.cmd + 1 < s.path.size && s.path[r.cmd + 1].op == 'C') {
                    var np = s.path[r.cmd + 1].pts;
                    np[0] += dx;
                    np[1] += dy;
                    s.path[r.cmd + 1] = new PathCommand ('C', np);
                }
            }
            s.path[r.cmd] = new PathCommand (c.op, pts);
        }

        public void normalize_custom (ShapeElement s) {
            double x1 = double.MAX, y1 = double.MAX, x2 = -double.MAX, y2 = -double.MAX;
            foreach (var c in s.path) {
                for (int i = 0; i + 1 < c.pts.length; i += 2) {
                    x1 = double.min (x1, c.pts[i]);
                    y1 = double.min (y1, c.pts[i + 1]);
                    x2 = double.max (x2, c.pts[i]);
                    y2 = double.max (y2, c.pts[i + 1]);
                }
            }
            if (x1 > x2) return;
            if (x1 >= -1e-6 && y1 >= -1e-6 && x2 <= 1 + 1e-6 && y2 <= 1 + 1e-6 && x2 - x1 > 0.999 && y2 - y1 > 0.999) return;
            double rw = double.max (x2 - x1, 1e-4), rh = double.max (y2 - y1, 1e-4);
            double nx = s.x + x1 * s.w, ny = s.y + y1 * s.h, nw = rw * s.w, nh = rh * s.h;
            for (int k = 0; k < s.path.size; k++) {
                var c = s.path[k];
                var pts = c.pts;
                for (int i = 0; i + 1 < pts.length; i += 2) {
                    pts[i] = (pts[i] - x1) / rw;
                    pts[i + 1] = (pts[i + 1] - y1) / rh;
                }
                s.path[k] = new PathCommand (c.op, pts);
            }
            s.set_geometry (nx, ny, double.max (nw, 1), double.max (nh, 1));
        }

        public void delete_point (int index) {
            var s = selection.size == 1 ? selection[0] as ShapeElement : null;
            if (s == null) return;
            var refs = point_refs (s);
            if (index < 0 || index >= refs.size || refs[index].control) return;
            int vertices = 0;
            foreach (var r in refs) if (!r.control) vertices++;
            if (vertices <= 2) return;
            doc.checkpoint (_("Delete Point"));
            int cmd = refs[index].cmd;
            if (s.path[cmd].op == 'M') {
                if (cmd + 1 < s.path.size && s.path[cmd + 1].op != 'Z') {
                    var nx = s.path[cmd + 1];
                    s.path[cmd + 1] = new PathCommand ('M', { nx.pts[nx.pts.length - 2], nx.pts[nx.pts.length - 1] });
                }
            }
            s.path.remove_at (cmd);
            normalize_custom (s);
            doc.touch ();
            edited ();
            queue_draw ();
        }

        public void add_point_near (double sx, double sy) {
            var s = selection.size == 1 ? selection[0] as ShapeElement : null;
            if (s == null || s.shape != ShapeKind.CUSTOM) return;
            double x, y, w, h;
            geometry_of (s, out x, out y, out w, out h);
            double lx, ly;
            unrotate (s, sx, sy, out lx, out ly);
            double nx = (lx - x) / double.max (w, 1), ny = (ly - y) / double.max (h, 1);
            int best = -1;
            double best_d = double.MAX;
            double px = 0, py = 0;
            for (int i = 0; i < s.path.size; i++) {
                var c = s.path[i];
                if (c.op == 'M' || c.op == 'Z' || c.pts.length < 2) {
                    if (c.pts.length >= 2) {
                        px = c.pts[c.pts.length - 2];
                        py = c.pts[c.pts.length - 1];
                    }
                    continue;
                }
                double ex = c.pts[c.pts.length - 2], ey = c.pts[c.pts.length - 1];
                double mx = (px + ex) / 2, my = (py + ey) / 2;
                double d = Math.hypot (mx - nx, my - ny);
                if (d < best_d) {
                    best_d = d;
                    best = i;
                }
                px = ex;
                py = ey;
            }
            if (best < 0) return;
            doc.checkpoint (_("Add Point"));
            var cmd = s.path[best];
            double sx0 = 0, sy0 = 0;
            for (int i = best - 1; i >= 0; i--) {
                if (s.path[i].pts.length >= 2) {
                    sx0 = s.path[i].pts[s.path[i].pts.length - 2];
                    sy0 = s.path[i].pts[s.path[i].pts.length - 1];
                    break;
                }
            }
            if (cmd.op == 'C') {
                double[] p = cmd.pts;
                double ax = (sx0 + p[0]) / 2, ay = (sy0 + p[1]) / 2;
                double bx = (p[0] + p[2]) / 2, by = (p[1] + p[3]) / 2;
                double cx = (p[2] + p[4]) / 2, cy = (p[3] + p[5]) / 2;
                double dx = (ax + bx) / 2, dy = (ay + by) / 2;
                double ex = (bx + cx) / 2, ey = (by + cy) / 2;
                double mx = (dx + ex) / 2, my = (dy + ey) / 2;
                s.path[best] = new PathCommand ('C', { ax, ay, dx, dy, mx, my });
                s.path.insert (best + 1, new PathCommand ('C', { ex, ey, cx, cy, p[4], p[5] }));
            } else {
                double ex = cmd.pts[cmd.pts.length - 2], ey = cmd.pts[cmd.pts.length - 1];
                s.path.insert (best, new PathCommand ('L', { (sx0 + ex) / 2, (sy0 + ey) / 2 }));
            }
            doc.touch ();
            edited ();
            queue_draw ();
        }

        private void draw_points (Cairo.Context cr, Gdk.RGBA acc) {
            if (!points_mode || selection.size != 1) return;
            var s = selection[0] as ShapeElement;
            if (s == null || s.shape != ShapeKind.CUSTOM) return;
            var refs = point_refs (s);
            double lastx = 0, lasty = 0;
            for (int i = 0; i < refs.size; i++) {
                double sx, sy, a, b;
                point_slide (s, refs[i], out sx, out sy);
                to_widget (sx, sy, out a, out b);
                if (refs[i].control) {
                    cr.set_source_rgba (acc.red, acc.green, acc.blue, 0.6);
                    cr.set_line_width (1);
                    var c = s.path[refs[i].cmd];
                    int n = c.pts.length / 2;
                    double vx, vy, va, vb;
                    if (refs[i].idx == 0) {
                        va = lastx;
                        vb = lasty;
                    } else {
                        point_slide (s, new PointRef (refs[i].cmd, n - 1, false), out vx, out vy);
                        to_widget (vx, vy, out va, out vb);
                    }
                    cr.move_to (va, vb);
                    cr.line_to (a, b);
                    cr.stroke ();
                    cr.arc (a, b, 3.5, 0, 2 * Math.PI);
                    cr.set_source_rgb (1, 1, 1);
                    cr.fill_preserve ();
                    cr.set_source_rgba (acc.red, acc.green, acc.blue, 1);
                    cr.stroke ();
                } else {
                    cr.rectangle (a - 4, b - 4, 8, 8);
                    cr.set_source_rgba (0, 0, 0, 0.85);
                    cr.fill_preserve ();
                    cr.set_source_rgb (1, 1, 1);
                    cr.set_line_width (1);
                    cr.stroke ();
                    lastx = a;
                    lasty = b;
                }
            }
        }

        private void begin_tool_drag (double sx, double sy) {
            switch (tool) {
                case CanvasTool.INK_PEN:
                case CanvasTool.INK_HIGHLIGHTER:
                    live_stroke = new InkStroke ();
                    live_stroke.color = tool == CanvasTool.INK_HIGHLIGHTER ? "#fff176" : ink_color;
                    live_stroke.width = tool == CanvasTool.INK_HIGHLIGHTER ? double.max (ink_width * 4, 12) : ink_width;
                    live_stroke.highlighter = tool == CanvasTool.INK_HIGHLIGHTER;
                    live_stroke.pts.add (sx);
                    live_stroke.pts.add (sy);
                    mode = DragMode.INK;
                    break;
                case CanvasTool.INK_ERASER:
                    erase_ink_at (sx, sy);
                    mode = DragMode.INK;
                    break;
                case CanvasTool.SCRIBBLE:
                case CanvasTool.MOTION_PATH:
                    free_pts.clear ();
                    free_pts.add (sx);
                    free_pts.add (sy);
                    mode = DragMode.SCRIBBLE;
                    break;
                case CanvasTool.FREEFORM:
                    if (free_pts.size == 0) {
                        free_pts.add (sx);
                        free_pts.add (sy);
                    }
                    free_pts.add (sx);
                    free_pts.add (sy);
                    mode = DragMode.SCRIBBLE;
                    break;
                default:
                    mode = DragMode.NONE;
                    break;
            }
        }

        private void update_tool_drag (double sx, double sy) {
            switch (mode) {
                case DragMode.INK:
                    if (tool == CanvasTool.INK_ERASER) {
                        erase_ink_at (sx, sy);
                    } else if (live_stroke != null) {
                        double lx = live_stroke.pts[live_stroke.pts.size - 2], ly = live_stroke.pts[live_stroke.pts.size - 1];
                        if (Math.hypot (sx - lx, sy - ly) * scale >= 1.5) {
                            live_stroke.pts.add (sx);
                            live_stroke.pts.add (sy);
                        }
                    }
                    break;
                case DragMode.SCRIBBLE:
                    double px = free_pts[free_pts.size - 2], py = free_pts[free_pts.size - 1];
                    if (Math.hypot (sx - px, sy - py) * scale >= 2) {
                        free_pts.add (sx);
                        free_pts.add (sy);
                    }
                    break;
                default:
                    break;
            }
            queue_draw ();
        }

        private void end_tool_drag () {
            if (mode == DragMode.INK && live_stroke != null && live_stroke.pts.size >= 4) {
                var stroke = live_stroke;
                live_stroke = null;
                var target = live_ink;
                bool fresh = target == null || !elements ().contains (target);
                doc.checkpoint (_("Ink"));
                if (fresh) {
                    target = new InkElement ();
                    target.name = _("Ink");
                    pres.assign_ids (target);
                    elements ().add (target);
                    live_ink = target;
                }
                target.strokes.add (stroke);
                target.fit ();
                doc.touch ();
                edited ();
            } else if (mode == DragMode.SCRIBBLE && tool == CanvasTool.SCRIBBLE) {
                finish_scribble ();
            } else if (mode == DragMode.SCRIBBLE && tool == CanvasTool.MOTION_PATH) {
                finish_motion_path ();
            }
            live_stroke = null;
            mode = DragMode.NONE;
            queue_draw ();
        }

        private void erase_ink_at (double sx, double sy) {
            var list = elements ();
            for (int i = list.size - 1; i >= 0; i--) {
                var ink = list[i] as InkElement;
                if (ink == null) continue;
                for (int k = ink.strokes.size - 1; k >= 0; k--) {
                    var st = ink.strokes[k];
                    bool hit_stroke = false;
                    for (int j = 0; j + 1 < st.pts.size; j += 2) {
                        if (Math.hypot (st.pts[j] - sx, st.pts[j + 1] - sy) <= st.width / 2 + 6 / scale) {
                            hit_stroke = true;
                            break;
                        }
                    }
                    if (!hit_stroke) continue;
                    doc.checkpoint (_("Erase Ink"), "erase-ink");
                    ink.strokes.remove_at (k);
                    if (ink.strokes.size == 0) list.remove_at (i);
                    else ink.fit ();
                    doc.touch ();
                    edited ();
                    break;
                }
            }
        }

        private void finish_scribble () {
            if (free_pts.size < 6) return;
            var poly = ShapeOps.simplify_stroke (free_pts, 1.5 / scale);
            var curve = ShapeOps.smooth (poly);
            var ops = new Gee.ArrayList<PathOp> ();
            foreach (var c in curve) ops.add (new PathOp (c.op, c.pts));
            double fx = free_pts[0], fy = free_pts[1];
            double lx = free_pts[free_pts.size - 2], ly = free_pts[free_pts.size - 1];
            bool closed = Math.hypot (fx - lx, fy - ly) * scale < 12;
            if (closed) ops.add (new PathOp ('Z', {}));
            var style = Factory.shape (pres, ShapeKind.RECT, 0, 0, 10, 10);
            if (!closed) style.fill = new Fill.none ();
            if (style.line.color == "") {
                style.line.color = "accent1";
                style.line.width = 2;
            }
            var s = ShapeOps.from_ops (ops, style);
            free_pts.clear ();
            if (s == null) return;
            s.name = _("Freeform");
            doc.checkpoint (_("Scribble"));
            pres.assign_ids (s);
            elements ().add (s);
            doc.touch ();
            select (s);
            edited ();
        }

        public void finish_freeform (bool closed) {
            if (tool != CanvasTool.FREEFORM || free_pts.size < 6) {
                free_pts.clear ();
                return;
            }
            var ops = new Gee.ArrayList<PathOp> ();
            for (int i = 0; i + 1 < free_pts.size; i += 2) {
                if (i > 0 && Math.hypot (free_pts[i] - free_pts[i - 2], free_pts[i + 1] - free_pts[i - 1]) < 0.5) continue;
                ops.add (new PathOp (i == 0 ? 'M' : 'L', { free_pts[i], free_pts[i + 1] }));
            }
            if (closed) ops.add (new PathOp ('Z', {}));
            var style = Factory.shape (pres, ShapeKind.RECT, 0, 0, 10, 10);
            if (!closed) style.fill = new Fill.none ();
            if (style.line.color == "") {
                style.line.color = "accent1";
                style.line.width = 2;
            }
            var s = ShapeOps.from_ops (ops, style);
            free_pts.clear ();
            if (s == null) return;
            s.name = _("Freeform");
            doc.checkpoint (_("Freeform"));
            pres.assign_ids (s);
            elements ().add (s);
            doc.touch ();
            tool = CanvasTool.SELECT;
            tool_changed ();
            select (s);
            edited ();
        }

        private void finish_motion_path () {
            var target = path_animation;
            if (free_pts.size < 4 || slide == null) {
                free_pts.clear ();
                return;
            }
            Element? e = null;
            if (target != null) e = slide.find (target.target);
            else if (selection.size == 1) e = selection[0];
            if (e == null) {
                free_pts.clear ();
                return;
            }
            var poly = ShapeOps.simplify_stroke (free_pts, 2 / scale);
            double ox0 = free_pts[0], oy0 = free_pts[1];
            var path = new Gee.ArrayList<PathCommand> ();
            foreach (var c in ShapeOps.smooth (poly)) {
                var pts = new double[c.pts.length];
                for (int i = 0; i + 1 < c.pts.length; i += 2) {
                    pts[i] = (c.pts[i] - ox0) / pres.width;
                    pts[i + 1] = (c.pts[i + 1] - oy0) / pres.height;
                }
                path.add (new PathCommand (c.op, pts));
            }
            free_pts.clear ();
            doc.checkpoint (_("Custom Motion Path"));
            if (target == null) {
                target = new Animation (e.id);
                target.anim_class = AnimClass.PATH;
                target.effect = AnimEffect.MOTION_PATH;
                target.duration = 2;
                slide.animations.add (target);
            }
            target.path.clear ();
            target.path.add_all (path);
            target.path_preset = MotionPreset.CUSTOM;
            path_animation = target;
            doc.touch ();
            tool = CanvasTool.SELECT;
            tool_changed ();
            edited ();
        }

        private void draw_tool_overlay (Cairo.Context cr, Gdk.RGBA acc) {
            cr.save ();
            cr.translate (ox, oy);
            cr.scale (scale, scale);
            if (live_stroke != null) Renderer.stroke_ink (cr, null, live_stroke);
            if (free_pts.size >= 2) {
                cr.move_to (free_pts[0], free_pts[1]);
                for (int i = 2; i + 1 < free_pts.size; i += 2) cr.line_to (free_pts[i], free_pts[i + 1]);
                if (tool == CanvasTool.FREEFORM && hover_x >= 0) cr.line_to (hover_x, hover_y);
                cr.set_source_rgba (acc.red, acc.green, acc.blue, 0.9);
                cr.set_line_width (2 / scale);
                cr.stroke ();
            }
            if (slide != null && path_animation != null) {
                var e = slide.find (path_animation.target);
                if (e != null && path_animation.path.size > 0) {
                    double bx = e.x + e.w / 2, by = e.y + e.h / 2;
                    var pts = PathSampler.flatten (path_animation.path);
                    cr.move_to (bx + pts[0] * pres.width, by + pts[1] * pres.height);
                    for (int i = 2; i + 1 < pts.size; i += 2) cr.line_to (bx + pts[i] * pres.width, by + pts[i + 1] * pres.height);
                    double[] dash = { 6 / scale, 4 / scale };
                    cr.set_dash (dash, 0);
                    cr.set_source_rgba (0.2, 0.2, 0.2, 0.8);
                    cr.set_line_width (1.5 / scale);
                    cr.stroke ();
                    cr.set_dash (null, 0);
                    cr.arc (bx + pts[0] * pres.width, by + pts[1] * pres.height, 5 / scale, 0, 2 * Math.PI);
                    cr.set_source_rgb (0.2, 0.7, 0.3);
                    cr.fill ();
                    cr.arc (bx + pts[pts.size - 2] * pres.width, by + pts[pts.size - 1] * pres.height, 5 / scale, 0, 2 * Math.PI);
                    cr.set_source_rgb (0.85, 0.2, 0.2);
                    cr.fill ();
                }
            }
            cr.restore ();
            if (pres.show_grid) {
                cr.save ();
                cr.set_source_rgba (0.5, 0.5, 0.5, 0.35);
                cr.set_line_width (1);
                double g = double.max (pres.grid_spacing, 2);
                for (double gx = g; gx < pres.width; gx += g) {
                    double a, b;
                    to_widget (gx, 0, out a, out b);
                    cr.move_to (Math.round (a) + 0.5, oy);
                    cr.line_to (Math.round (a) + 0.5, oy + pres.height * scale);
                }
                for (double gy = g; gy < pres.height; gy += g) {
                    double a, b;
                    to_widget (0, gy, out a, out b);
                    cr.move_to (ox, Math.round (b) + 0.5);
                    cr.line_to (ox + pres.width * scale, Math.round (b) + 0.5);
                }
                double[] dots = { 1, 3 };
                cr.set_dash (dots, 0);
                cr.stroke ();
                cr.restore ();
            }
            if (pres.show_guides) {
                cr.save ();
                cr.set_source_rgba (0.95, 0.55, 0.1, 0.9);
                cr.set_line_width (1);
                double[] dash = { 5, 3 };
                cr.set_dash (dash, 0);
                foreach (var gx in pres.guides_x) {
                    double a, b;
                    to_widget (gx, 0, out a, out b);
                    cr.move_to (Math.round (a) + 0.5, oy - 12);
                    cr.line_to (Math.round (a) + 0.5, oy + pres.height * scale + 12);
                }
                foreach (var gy in pres.guides_y) {
                    double a, b;
                    to_widget (0, gy, out a, out b);
                    cr.move_to (ox - 12, Math.round (b) + 0.5);
                    cr.line_to (ox + pres.width * scale + 12, Math.round (b) + 0.5);
                }
                cr.stroke ();
                cr.restore ();
            }
            if (pres.show_ruler) draw_rulers (cr, acc);
            if (show_comments && slide != null) {
                int n = 0;
                foreach (var c in slide.comments) {
                    n++;
                    double a, b;
                    to_widget (c.x, c.y, out a, out b);
                    Geometry.round_rect (cr, a, b, 24, 20, 5);
                    bool active = c == active_comment;
                    cr.set_source_rgba (active ? acc.red : 1, active ? acc.green : 0.85, active ? acc.blue : 0.2, 0.95);
                    cr.fill_preserve ();
                    cr.set_source_rgba (0, 0, 0, 0.45);
                    cr.set_line_width (1);
                    cr.stroke ();
                    var l = create_pango_layout (c.initials != "" ? c.initials : n.to_string ());
                    int lw, lh;
                    l.get_pixel_size (out lw, out lh);
                    cr.set_source_rgb (active ? 1 : 0.1, active ? 1 : 0.1, active ? 1 : 0.1);
                    cr.move_to (a + (24 - lw) / 2.0, b + (20 - lh) / 2.0);
                    Pango.cairo_show_layout (cr, l);
                }
            }
        }

        private void draw_rulers (Cairo.Context cr, Gdk.RGBA acc) {
            double cm = 72.0 / 2.54;
            cr.save ();
            var fg = get_color ();
            cr.set_source_rgba (fg.red, fg.green, fg.blue, 0.08);
            cr.rectangle (ox, oy - 22, pres.width * scale, 18);
            cr.rectangle (ox - 22, oy, 18, pres.height * scale);
            cr.fill ();
            cr.set_source_rgba (fg.red, fg.green, fg.blue, 0.6);
            cr.set_line_width (1);
            double center_x = pres.width / 2, center_y = pres.height / 2;
            for (int i = -60; i <= 60; i++) {
                double sx = center_x + i * cm / 2;
                if (sx < 0 || sx > pres.width) continue;
                double a, b;
                to_widget (sx, 0, out a, out b);
                double len = i % 2 == 0 ? 8 : 4;
                cr.move_to (Math.round (a) + 0.5, oy - 4);
                cr.line_to (Math.round (a) + 0.5, oy - 4 - len);
                if (i % 2 == 0 && i != 0 && scale * cm > 18) {
                    var l = create_pango_layout ((i.abs () / 2).to_string ());
                    l.set_font_description (Pango.FontDescription.from_string ("Inter 7"));
                    cr.move_to (a + 2, oy - 22);
                    Pango.cairo_show_layout (cr, l);
                }
            }
            for (int i = -60; i <= 60; i++) {
                double sy = center_y + i * cm / 2;
                if (sy < 0 || sy > pres.height) continue;
                double a, b;
                to_widget (0, sy, out a, out b);
                double len = i % 2 == 0 ? 8 : 4;
                cr.move_to (ox - 4, Math.round (b) + 0.5);
                cr.line_to (ox - 4 - len, Math.round (b) + 0.5);
            }
            cr.stroke ();
            if (selection.size == 1) {
                var e = selection[0];
                double a, b, c, d;
                to_widget (e.x, e.y, out a, out b);
                to_widget (e.x + e.w, e.y + e.h, out c, out d);
                cr.set_source_rgba (acc.red, acc.green, acc.blue, 0.35);
                cr.rectangle (a, oy - 22, c - a, 18);
                cr.rectangle (ox - 22, b, 18, d - b);
                cr.fill ();
            }
            cr.restore ();
        }

        private int hit_guide (double wx, double wy, out bool vertical) {
            vertical = true;
            if (!pres.show_guides) return -1;
            for (int i = 0; i < pres.guides_x.size; i++) {
                double a, b;
                to_widget (pres.guides_x[i], 0, out a, out b);
                if (Math.fabs (a - wx) <= 4) return i;
            }
            vertical = false;
            for (int i = 0; i < pres.guides_y.size; i++) {
                double a, b;
                to_widget (0, pres.guides_y[i], out a, out b);
                if (Math.fabs (b - wy) <= 4) return i;
            }
            return -1;
        }

        private Comment? hit_comment (double wx, double wy) {
            if (!show_comments || slide == null) return null;
            for (int i = slide.comments.size - 1; i >= 0; i--) {
                var c = slide.comments[i];
                double a, b;
                to_widget (c.x, c.y, out a, out b);
                if (wx >= a && wx <= a + 24 && wy >= b && wy <= b + 20) return c;
            }
            return null;
        }

        public void apply_painter (Element target) {
            if (painter == null) return;
            doc.checkpoint (_("Format Painter"));
            painter.apply (target);
            doc.touch ();
            if (!painter_sticky) {
                painter = null;
                tool = CanvasTool.SELECT;
                tool_changed ();
            }
            edited ();
            queue_draw ();
        }

        public double snap_grid (double v) {
            if (pres == null || !pres.snap_to_grid) return v;
            double g = double.max (pres.grid_spacing, 1);
            return Math.round (v / g) * g;
        }

        public SlideCanvas () {
            focusable = true;
            can_focus = true;
            hexpand = true;
            vexpand = true;
            renderer.edit_mode = true;
            var click = new GestureClick ();
            click.button = 0;
            click.pressed.connect (on_pressed);
            add_controller (click);
            drag_gesture = new GestureDrag ();
            drag_gesture.button = Gdk.BUTTON_PRIMARY;
            drag_gesture.drag_begin.connect (on_drag_begin);
            drag_gesture.drag_update.connect (on_drag_update);
            drag_gesture.drag_end.connect (on_drag_end);
            add_controller (drag_gesture);
            var motion = new EventControllerMotion ();
            motion.motion.connect (on_motion);
            add_controller (motion);
            var keys = new EventControllerKey ();
            keys.key_pressed.connect (on_key);
            add_controller (keys);
            var scroll = new EventControllerScroll (EventControllerScrollFlags.VERTICAL);
            scroll.scroll.connect ((dx, dy) => {
                var state = scroll.get_current_event_state ();
                if ((state & Gdk.ModifierType.CONTROL_MASK) == 0) return false;
                zoom_to (scale * (dy < 0 ? 1.1 : 1 / 1.1));
                return true;
            });
            add_controller (scroll);
        }

        public Presentation? pres {
            owned get { return doc != null ? doc.pres : null; }
        }

        public Gee.List<Element> elements () {
            if (slide != null) return slide.elements;
            if (layout != null) return layout.elements;
            if (master != null) return master.elements;
            return new Gee.ArrayList<Element> ();
        }

        public RenderContext context () {
            if (slide != null) return new RenderContext (pres, slide, pres.layout_for (slide), pres.master_for (slide));
            var m = master ?? pres.master;
            return new RenderContext (pres, null, layout, m);
        }

        public void show_slide (Slide? s) {
            commit_edit ();
            crop_mode = false;
            slide = s;
            layout = null;
            master = null;
            clear_selection ();
            queue_resize ();
            queue_draw ();
        }

        public void show_master (Master m, Layout? l) {
            commit_edit ();
            crop_mode = false;
            slide = null;
            master = m;
            layout = l;
            clear_selection ();
            queue_draw ();
        }

        public void clear_selection () {
            if (selection.size == 0 && cell_r1 < 0) return;
            selection.clear ();
            cell_r1 = -1;
            crop_mode = false;
            selection_changed ();
            queue_draw ();
        }

        public void select (Element? e, bool add = false) {
            if (!add) selection.clear ();
            if (e != null) {
                if (add && selection.contains (e)) selection.remove (e);
                else if (!selection.contains (e)) selection.add (e);
            }
            cell_r1 = -1;
            crop_mode = false;
            selection_changed ();
            queue_draw ();
        }

        public void select_all () {
            selection.clear ();
            selection.add_all (elements ());
            selection_changed ();
            queue_draw ();
        }

        public void reselect_by_ids (int[] ids) {
            selection.clear ();
            foreach (int id in ids) {
                foreach (var e in elements ()) if (e.id == id) selection.add (e);
            }
            selection_changed ();
            queue_draw ();
        }

        public int[] selected_ids () {
            int[] ids = {};
            foreach (var e in selection) ids += e.id;
            return ids;
        }

        public void zoom_to (double z) {
            zoom = z.clamp (0.1, 8);
            queue_resize ();
            zoom_changed ();
        }

        public void zoom_fit () {
            zoom = 0;
            queue_resize ();
            zoom_changed ();
        }

        protected override SizeRequestMode get_request_mode () {
            return SizeRequestMode.CONSTANT_SIZE;
        }

        protected override void measure (Orientation orientation, int for_size, out int minimum, out int natural, out int minimum_baseline, out int natural_baseline) {
            minimum_baseline = -1;
            natural_baseline = -1;
            if (pres == null || zoom <= 0) {
                minimum = 120;
                natural = 400;
                return;
            }
            double size = orientation == Orientation.HORIZONTAL ? pres.width : pres.height;
            minimum = (int) (size * zoom + MARGIN * 2);
            natural = minimum;
        }

        protected override void size_allocate (int width, int height, int baseline) {
            layout_geometry (width, height);
            if (editor != null) place_editor ();
        }

        private void layout_geometry (int width, int height) {
            if (pres == null) return;
            double old = scale;
            if (zoom <= 0) {
                scale = double.min ((width - MARGIN * 2) / pres.width, (height - MARGIN * 2) / pres.height);
                if (scale <= 0.01) scale = 0.01;
            } else {
                scale = zoom;
            }
            ox = Math.floor ((width - pres.width * scale) / 2);
            oy = Math.floor ((height - pres.height * scale) / 2);
            if (old != scale) {
                if (editor != null) restart_edit ();
                zoom_changed ();
            }
        }

        public void to_slide (double wx, double wy, out double sx, out double sy) {
            sx = (wx - ox) / scale;
            sy = (wy - oy) / scale;
        }

        public void to_widget (double sx, double sy, out double wx, out double wy) {
            wx = ox + sx * scale;
            wy = oy + sy * scale;
        }

        private static Gdk.RGBA accent () {
            var c = Gdk.RGBA ();
            c.parse (Singularity.Style.StyleManager.get_default ().accent_hex);
            return c;
        }

        protected override void snapshot (Snapshot snap) {
            int w = get_width (), h = get_height ();
            if (pres == null) return;
            layout_geometry (w, h);
            var rect = Graphene.Rect ();
            rect.init (0, 0, w, h);
            var cr = snap.append_cairo (rect);
            double sw = pres.width * scale, sh = pres.height * scale;
            cr.save ();
            for (int i = 3; i >= 1; i--) {
                cr.set_source_rgba (0, 0, 0, 0.06);
                Geometry.round_rect (cr, ox - i, oy - i + 2, sw + i * 2, sh + i * 2, 2 + i);
                cr.fill ();
            }
            cr.translate (ox, oy);
            cr.scale (scale, scale);
            if (slide != null) {
                renderer.draw_slide (cr, pres, slide);
            } else if (master != null) {
                renderer.draw_master_view (cr, pres, master, layout);
            }
            cr.restore ();
            draw_overlay (cr);
            if (editor != null) snapshot_child (editor, snap);
        }

        private void element_frame (Cairo.Context cr, Element e) {
            double x, y, w, h;
            geometry_of (e, out x, out y, out w, out h);
            cr.save ();
            cr.translate (ox, oy);
            cr.scale (scale, scale);
            if (e.rotation != 0) {
                cr.translate (x + w / 2, y + h / 2);
                cr.rotate (e.rotation * Math.PI / 180);
                cr.translate (-(x + w / 2), -(y + h / 2));
            }
        }

        public void geometry_of (Element e, out double x, out double y, out double w, out double h) {
            if (slide != null) pres.effective_geometry (slide, pres.layout_for (slide), pres.master_for (slide), e, out x, out y, out w, out h);
            else pres.effective_geometry (null, layout, master ?? pres.master, e, out x, out y, out w, out h);
        }

        private void handle_points (Element e, out double[] hx, out double[] hy) {
            double x, y, w, h;
            geometry_of (e, out x, out y, out w, out h);
            hx = new double[9];
            hy = new double[9];
            int i = 0;
            for (int j = -1; j <= 1; j++) {
                for (int k = -1; k <= 1; k++) {
                    if (j == 0 && k == 0) continue;
                    double lx = x + w / 2 + k * w / 2, ly = y + h / 2 + j * h / 2;
                    rotate_point (e, lx, ly, out hx[i], out hy[i]);
                    i++;
                }
            }
            double rx, ry;
            rotate_point (e, x + w / 2, y - 24 / scale, out rx, out ry);
            hx[8] = rx;
            hy[8] = ry;
        }

        private void rotate_point (Element e, double px, double py, out double rx, out double ry) {
            double x, y, w, h;
            geometry_of (e, out x, out y, out w, out h);
            double cx = x + w / 2, cy = y + h / 2;
            double a = e.rotation * Math.PI / 180;
            double dx = px - cx, dy = py - cy;
            rx = cx + dx * Math.cos (a) - dy * Math.sin (a);
            ry = cy + dx * Math.sin (a) + dy * Math.cos (a);
        }

        private static int[] handle_dirs (int i) {
            int[,] dirs = { { -1, -1 }, { 0, -1 }, { 1, -1 }, { -1, 0 }, { 1, 0 }, { -1, 1 }, { 0, 1 }, { 1, 1 } };
            return { dirs[i, 0], dirs[i, 1] };
        }

        private void line_ends (ShapeElement s, out double x1, out double y1, out double x2, out double y2) {
            x1 = s.flip_h ? s.x + s.w : s.x;
            y1 = s.flip_v ? s.y + s.h : s.y;
            x2 = s.flip_h ? s.x : s.x + s.w;
            y2 = s.flip_v ? s.y : s.y + s.h;
        }

        private bool is_line (Element e) {
            var s = e as ShapeElement;
            return s != null && s.shape == ShapeKind.LINE;
        }

        private void draw_handle (Cairo.Context cr, double sx, double sy, Gdk.RGBA acc, bool round = false) {
            double wx, wy;
            to_widget (sx, sy, out wx, out wy);
            cr.new_path ();
            if (round) cr.arc (wx, wy, HANDLE / 2 + 1, 0, 2 * Math.PI);
            else Geometry.round_rect (cr, wx - HANDLE / 2, wy - HANDLE / 2, HANDLE, HANDLE, 2);
            cr.set_source_rgb (1, 1, 1);
            cr.fill_preserve ();
            cr.set_source_rgba (acc.red, acc.green, acc.blue, 1);
            cr.set_line_width (1.5);
            cr.stroke ();
        }

        private void draw_overlay (Cairo.Context cr) {
            var acc = accent ();
            draw_tool_overlay (cr, acc);
            draw_points (cr, acc);
            draw_adjust_handles (cr);
            cr.save ();
            if (hover != null && !selection.contains (hover) && editor == null && mode == DragMode.NONE) {
                element_frame (cr, hover);
                double x, y, w, h;
                geometry_of (hover, out x, out y, out w, out h);
                cr.rectangle (x, y, w, h);
                cr.restore ();
                cr.set_source_rgba (acc.red, acc.green, acc.blue, 0.5);
                cr.set_line_width (1);
                cr.stroke ();
                cr.save ();
            }
            if (crop_mode && selection.size == 1 && selection[0] is ImageElement) {
                draw_crop (cr, (ImageElement) selection[0], acc);
                cr.restore ();
                return;
            }
            foreach (var e in selection) {
                double x, y, w, h;
                geometry_of (e, out x, out y, out w, out h);
                if (is_line (e)) {
                    double x1, y1, x2, y2;
                    line_ends ((ShapeElement) e, out x1, out y1, out x2, out y2);
                    draw_handle (cr, x1, y1, acc, true);
                    draw_handle (cr, x2, y2, acc, true);
                    continue;
                }
                element_frame (cr, e);
                cr.rectangle (x, y, w, h);
                cr.restore ();
                cr.set_source_rgba (acc.red, acc.green, acc.blue, 1);
                cr.set_line_width (1.5);
                if (e.locked) {
                    double[] dash = { 4, 3 };
                    cr.set_dash (dash, 0);
                }
                cr.stroke ();
                cr.set_dash (null, 0);
                cr.save ();
                if (selection.size == 1 && editor == null && !e.locked && !points_mode) {
                    double[] hx, hy;
                    handle_points (e, out hx, out hy);
                    double tx, ty;
                    rotate_point (e, x + w / 2, y, out tx, out ty);
                    double w1x, w1y, w2x, w2y;
                    to_widget (tx, ty, out w1x, out w1y);
                    to_widget (hx[8], hy[8], out w2x, out w2y);
                    cr.move_to (w1x, w1y);
                    cr.line_to (w2x, w2y);
                    cr.set_source_rgba (acc.red, acc.green, acc.blue, 1);
                    cr.set_line_width (1);
                    cr.stroke ();
                    for (int i = 0; i < 8; i++) draw_handle (cr, hx[i], hy[i], acc);
                    draw_handle (cr, hx[8], hy[8], acc, true);
                }
                var t = e as TableElement;
                if (t != null && cell_r1 >= 0 && selection.size == 1) {
                    int r1 = int.min (cell_r1, cell_r2), r2 = int.max (cell_r1, cell_r2);
                    int c1 = int.min (cell_c1, cell_c2), c2 = int.max (cell_c1, cell_c2);
                    double cx1 = t.col_x (c1), cy1 = t.row_y (r1);
                    double cx2 = t.col_x (c2 + 1), cy2 = t.row_y (r2 + 1);
                    double a, b, c, d;
                    to_widget (cx1, cy1, out a, out b);
                    to_widget (cx2, cy2, out c, out d);
                    cr.rectangle (a, b, c - a, d - b);
                    cr.set_source_rgba (acc.red, acc.green, acc.blue, 0.18);
                    cr.fill_preserve ();
                    cr.set_source_rgba (acc.red, acc.green, acc.blue, 1);
                    cr.set_line_width (2);
                    cr.stroke ();
                }
            }
            cr.restore ();
            if (show_badges && slide != null) draw_badges (cr, acc);
            if (mode == DragMode.RUBBER && drag_started) {
                double a, b;
                to_widget (press_x, press_y, out a, out b);
                double c, d;
                to_widget (rubber_x2, rubber_y2, out c, out d);
                cr.rectangle (double.min (a, c), double.min (b, d), Math.fabs (c - a), Math.fabs (d - b));
                cr.set_source_rgba (acc.red, acc.green, acc.blue, 0.12);
                cr.fill_preserve ();
                cr.set_source_rgba (acc.red, acc.green, acc.blue, 0.8);
                cr.set_line_width (1);
                cr.stroke ();
            }
            if (drag_started && (mode == DragMode.MOVE || mode == DragMode.RESIZE)) {
                cr.set_source_rgba (0.95, 0.2, 0.55, 0.95);
                cr.set_line_width (1);
                foreach (var gx in vguides) {
                    double a, b;
                    to_widget (gx, 0, out a, out b);
                    cr.move_to (Math.round (a) + 0.5, oy);
                    cr.line_to (Math.round (a) + 0.5, oy + pres.height * scale);
                }
                foreach (var gy in hguides) {
                    double a, b;
                    to_widget (0, gy, out a, out b);
                    cr.move_to (ox, Math.round (b) + 0.5);
                    cr.line_to (ox + pres.width * scale, Math.round (b) + 0.5);
                }
                cr.stroke ();
                for (int i = 0; i + 3 < spacing_marks.size; i += 4) {
                    double a, b, c, d;
                    to_widget (spacing_marks[i], spacing_marks[i + 1], out a, out b);
                    to_widget (spacing_marks[i + 2], spacing_marks[i + 3], out c, out d);
                    cr.move_to (a, b);
                    cr.line_to (c, d);
                    cr.stroke ();
                    if (b == d) {
                        cr.move_to (a, b - 4);
                        cr.line_to (a, b + 4);
                        cr.move_to (c, d - 4);
                        cr.line_to (c, d + 4);
                    } else {
                        cr.move_to (a - 4, b);
                        cr.line_to (a + 4, b);
                        cr.move_to (c - 4, d);
                        cr.line_to (c + 4, d);
                    }
                    cr.stroke ();
                }
            }
        }

        private void draw_badges (Cairo.Context cr, Gdk.RGBA acc) {
            int n = 0;
            var seen = new Gee.HashMap<int, string> ();
            for (int i = 0; i < slide.animations.size; i++) {
                var a = slide.animations[i];
                if (a.trigger == AnimTrigger.ON_CLICK || i == 0) n++;
                string label = seen.has_key (a.target) ? seen[a.target] + "," + n.to_string () : n.to_string ();
                seen[a.target] = label;
            }
            foreach (var kv in seen.entries) {
                var e = slide.find (kv.key);
                if (e == null) continue;
                double x, y, w, h;
                geometry_of (e, out x, out y, out w, out h);
                double wx, wy;
                to_widget (x, y, out wx, out wy);
                var layout = create_pango_layout (kv.value);
                int lw, lh;
                layout.get_pixel_size (out lw, out lh);
                double bw = double.max (lw + 10, 20), bh = 20;
                Geometry.round_rect (cr, wx - bw - 4, wy, bw, bh, 10);
                cr.set_source_rgba (acc.red, acc.green, acc.blue, 0.95);
                cr.fill ();
                cr.set_source_rgb (1, 1, 1);
                cr.move_to (wx - bw - 4 + (bw - lw) / 2, wy + (bh - lh) / 2);
                Pango.cairo_show_layout (cr, layout);
            }
        }

        private void crop_full_rect (ImageElement img, out double fx, out double fy, out double fw, out double fh) {
            double vw = 1 - img.crop_left - img.crop_right, vh = 1 - img.crop_top - img.crop_bottom;
            fw = img.w / double.max (vw, 0.01);
            fh = img.h / double.max (vh, 0.01);
            fx = img.x - img.crop_left * fw;
            fy = img.y - img.crop_top * fh;
        }

        private void draw_crop (Cairo.Context cr, ImageElement img, Gdk.RGBA acc) {
            double fx, fy, fw, fh;
            crop_full_rect (img, out fx, out fy, out fw, out fh);
            var surf = ImageCache.filtered (img);
            cr.save ();
            cr.translate (ox, oy);
            cr.scale (scale, scale);
            if (surf != null) {
                cr.save ();
                cr.rectangle (fx, fy, fw, fh);
                cr.clip ();
                cr.translate (fx, fy);
                cr.scale (fw / surf.get_width (), fh / surf.get_height ());
                cr.set_source_surface (surf, 0, 0);
                cr.paint_with_alpha (0.35);
                cr.restore ();
            }
            cr.restore ();
            double a, b, c, d;
            to_widget (fx, fy, out a, out b);
            to_widget (fx + fw, fy + fh, out c, out d);
            cr.rectangle (a, b, c - a, d - b);
            cr.set_source_rgba (acc.red, acc.green, acc.blue, 0.6);
            cr.set_line_width (1);
            double[] dash = { 4, 4 };
            cr.set_dash (dash, 0);
            cr.stroke ();
            cr.set_dash (null, 0);
            to_widget (img.x, img.y, out a, out b);
            to_widget (img.x + img.w, img.y + img.h, out c, out d);
            cr.rectangle (a, b, c - a, d - b);
            cr.set_source_rgba (acc.red, acc.green, acc.blue, 1);
            cr.set_line_width (2);
            cr.stroke ();
            double[] xs = { a, (a + c) / 2, c };
            double[] ys = { b, (b + d) / 2, d };
            cr.set_line_width (4);
            for (int i = 0; i < 3; i++) {
                for (int j = 0; j < 3; j++) {
                    if (i == 1 && j == 1) continue;
                    double px = xs[i], py = ys[j];
                    double lx = i == 0 ? 10 : (i == 2 ? -10 : 8), ly = j == 0 ? 10 : (j == 2 ? -10 : 8);
                    cr.set_source_rgb (0.1, 0.1, 0.1);
                    if (i != 1) {
                        cr.move_to (px, py - (j == 1 ? 8 : 0));
                        cr.line_to (px, py + (j == 1 ? 8 : ly));
                    }
                    if (j != 1) {
                        cr.move_to (px - (i == 1 ? 8 : 0), py);
                        cr.line_to (px + (i == 1 ? 8 : lx), py);
                    }
                    cr.stroke ();
                }
            }
        }

        public Element? hit (double sx, double sy) {
            var list = elements ();
            double tol = 4 / scale;
            for (int i = list.size - 1; i >= 0; i--) {
                var e = list[i];
                if (is_line (e)) {
                    double x1, y1, x2, y2;
                    line_ends ((ShapeElement) e, out x1, out y1, out x2, out y2);
                    if (distance_to_segment (sx, sy, x1, y1, x2, y2) <= double.max (tol * 1.5, e.line.width)) return e;
                    continue;
                }
                double x, y, w, h;
                geometry_of (e, out x, out y, out w, out h);
                double lx = sx, ly = sy;
                if (e.rotation != 0) {
                    double a = -e.rotation * Math.PI / 180;
                    double cx = x + w / 2, cy = y + h / 2;
                    double dx = sx - cx, dy = sy - cy;
                    lx = cx + dx * Math.cos (a) - dy * Math.sin (a);
                    ly = cy + dx * Math.sin (a) + dy * Math.cos (a);
                }
                if (lx >= x - tol && lx <= x + w + tol && ly >= y - tol && ly <= y + h + tol) return e;
            }
            return null;
        }

        private static double distance_to_segment (double px, double py, double x1, double y1, double x2, double y2) {
            double dx = x2 - x1, dy = y2 - y1;
            double len = dx * dx + dy * dy;
            double t = len > 0 ? ((px - x1) * dx + (py - y1) * dy) / len : 0;
            t = t.clamp (0, 1);
            double cx = x1 + t * dx - px, cy = y1 + t * dy - py;
            return Math.sqrt (cx * cx + cy * cy);
        }

        private int hit_handle (double wx, double wy) {
            if (selection.size != 1 || editor != null) return -1;
            var e = selection[0];
            if (e.locked) return -1;
            if (is_line (e)) {
                double x1, y1, x2, y2;
                line_ends ((ShapeElement) e, out x1, out y1, out x2, out y2);
                double a, b;
                to_widget (x1, y1, out a, out b);
                if (Math.fabs (a - wx) <= HANDLE && Math.fabs (b - wy) <= HANDLE) return 10;
                to_widget (x2, y2, out a, out b);
                if (Math.fabs (a - wx) <= HANDLE && Math.fabs (b - wy) <= HANDLE) return 11;
                return -1;
            }
            double[] hx, hy;
            handle_points (e, out hx, out hy);
            for (int i = 8; i >= 0; i--) {
                double a, b;
                to_widget (hx[i], hy[i], out a, out b);
                if (Math.fabs (a - wx) <= HANDLE && Math.fabs (b - wy) <= HANDLE) return i;
            }
            return -1;
        }

        private int hit_crop_handle (double wx, double wy) {
            var img = selection[0];
            double[] xs = { img.x, img.x + img.w / 2, img.x + img.w };
            double[] ys = { img.y, img.y + img.h / 2, img.y + img.h };
            int idx = 0;
            for (int j = 0; j < 3; j++) {
                for (int i = 0; i < 3; i++) {
                    if (i == 1 && j == 1) continue;
                    double a, b;
                    to_widget (xs[i], ys[j], out a, out b);
                    if (Math.fabs (a - wx) <= HANDLE + 4 && Math.fabs (b - wy) <= HANDLE + 4) return idx;
                    idx++;
                }
            }
            return -1;
        }

        private int hit_table_line (TableElement t, double sx, double sy, out bool is_col) {
            is_col = true;
            double tol = 4 / scale;
            if (sy >= t.y && sy <= t.y + t.h) {
                for (int c = 1; c <= t.cols; c++) {
                    if (Math.fabs (sx - t.col_x (c)) <= tol) return c;
                }
            }
            is_col = false;
            if (sx >= t.x && sx <= t.x + t.w) {
                for (int r = 1; r <= t.rows; r++) {
                    if (Math.fabs (sy - t.row_y (r)) <= tol) return r;
                }
            }
            return -1;
        }

        private void on_motion (double x, double y) {
            if (pres == null || mode != DragMode.NONE) return;
            double sx, sy;
            to_slide (x, y, out sx, out sy);
            if (tool != CanvasTool.SELECT) {
                hover_x = sx;
                hover_y = sy;
                if (tool == CanvasTool.FREEFORM && free_pts.size > 0) queue_draw ();
                set_cursor_from_name (tool == CanvasTool.PAINTER ? "copy" : "crosshair");
                return;
            }
            if (hit_adjust (x, y) >= 0 || hit_point (x, y) >= 0) {
                set_cursor_from_name ("pointer");
                return;
            }
            bool gv;
            if (hit_guide (x, y, out gv) >= 0) {
                set_cursor_from_name (gv ? "col-resize" : "row-resize");
                return;
            }
            int hnd = hit_handle (x, y);
            string cursor = "default";
            if (tool != CanvasTool.SELECT) {
                if (tool != CanvasTool.PAINTER) begin_tool_drag (sx, sy);
                return;
            }
            var cm = hit_comment (x, y);
            if (cm != null) {
                drag_comment = cm;
                guide_orig = cm.x;
                mode = DragMode.COMMENT;
                return;
            }
            int pnt = hit_point (x, y);
            if (pnt >= 0) {
                point_index = pnt;
                mode = DragMode.POINT;
                snapshot_selection ();
                return;
            }
            int adj = hit_adjust (x, y);
            if (adj >= 0) {
                adjust_index = adj;
                mode = DragMode.ADJUST;
                snapshot_selection ();
                return;
            }
            bool gvert;
            int gi = hit_guide (x, y, out gvert);
            if (gi >= 0) {
                guide_index = gvert ? gi : -gi - 1;
                mode = DragMode.GUIDE;
                return;
            }
            if (crop_mode && selection.size == 1) {
                int ch = hit_crop_handle (x, y);
                cursor = ch >= 0 ? "crosshair" : "move";
            } else if (hnd == 8) {
                cursor = "grab";
            } else if (hnd >= 10) {
                cursor = "crosshair";
            } else if (hnd >= 0) {
                int[] d = handle_dirs (hnd);
                if (d[0] == 0) cursor = "ns-resize";
                else if (d[1] == 0) cursor = "ew-resize";
                else cursor = d[0] == d[1] ? "nwse-resize" : "nesw-resize";
            } else {
                var e = hit (sx, sy);
                var t = selection.size == 1 ? selection[0] as TableElement : null;
                bool col = false;
                if (t != null && hit_table_line (t, sx, sy, out col) >= 0) cursor = col ? "col-resize" : "row-resize";
                else if (e != null && selection.contains (e) && e.text_body () != null) cursor = "move";
                else if (e != null) cursor = "pointer";
                if (e != hover) {
                    hover = e;
                    queue_draw ();
                }
            }
            set_cursor_from_name (cursor);
        }

        private void on_pressed (GestureClick g, int n, double x, double y) {
            if (pres == null) return;
            grab_focus ();
            double sx, sy;
            to_slide (x, y, out sx, out sy);
            uint button = g.get_current_button ();
            var state = g.get_current_event_state ();
            bool shift = (state & Gdk.ModifierType.SHIFT_MASK) != 0;
            bool ctrl = (state & Gdk.ModifierType.CONTROL_MASK) != 0;
            if (editor != null) commit_edit ();
            if (tool == CanvasTool.FREEFORM && button == Gdk.BUTTON_PRIMARY) {
                if (n == 2) {
                    bool closed = free_pts.size >= 6 && Math.hypot (free_pts[0] - sx, free_pts[1] - sy) * scale < 12;
                    finish_freeform (closed);
                }
                return;
            }
            if (tool == CanvasTool.PAINTER && button == Gdk.BUTTON_PRIMARY) {
                var pe = hit (sx, sy);
                if (pe != null) apply_painter (pe);
                return;
            }
            if (tool != CanvasTool.SELECT) return;
            var cm = hit_comment (x, y);
            if (cm != null && button == Gdk.BUTTON_PRIMARY) {
                active_comment = cm;
                comment_clicked (cm);
                queue_draw ();
                return;
            }
            if (points_mode && button == Gdk.BUTTON_SECONDARY) {
                int pi = hit_point (x, y);
                if (pi >= 0) {
                    delete_point (pi);
                    return;
                }
            }
            if (points_mode && n == 2 && button == Gdk.BUTTON_PRIMARY && selection.size == 1) {
                add_point_near (sx, sy);
                return;
            }
            if (button == Gdk.BUTTON_SECONDARY) {
                var e = hit (sx, sy);
                if (e != null && !selection.contains (e)) select (e);
                if (e == null && selection.size > 0) clear_selection ();
                context_requested (x, y);
                return;
            }
            if (button != Gdk.BUTTON_PRIMARY) return;
            if (crop_mode) {
                if (selection.size == 1 && hit_crop_handle (x, y) < 0) {
                    var img = (ImageElement) selection[0];
                    double fx, fy, fw, fh;
                    crop_full_rect (img, out fx, out fy, out fw, out fh);
                    if (sx < fx || sx > fx + fw || sy < fy || sy > fy + fh) {
                        crop_mode = false;
                        queue_draw ();
                    }
                }
                return;
            }
            var e = hit (sx, sy);
            if (n == 2 && e != null) {
                activate_element (e, sx, sy, x, y);
                return;
            }
            if (n == 2 && e == null && slide != null) {
                double_clicked_empty ();
                return;
            }
            if (hit_handle (x, y) >= 0) return;
            var t = e as TableElement;
            if (t != null && selection.contains (t) && selection.size == 1) {
                int r, c;
                t.cell_at (sx, sy, out r, out c);
                bool col = false;
                if (hit_table_line (t, sx, sy, out col) < 0 && r >= 0) {
                    if (shift && cell_r1 >= 0) {
                        cell_r2 = r;
                        cell_c2 = c;
                    } else {
                        cell_r1 = cell_r2 = r;
                        cell_c1 = cell_c2 = c;
                    }
                    selection_changed ();
                    queue_draw ();
                    return;
                }
            }
            if (e == null) {
                if (!shift && !ctrl) clear_selection ();
                return;
            }
            if (shift || ctrl) {
                if (!drag_copy) select (e, true);
            } else if (!selection.contains (e)) {
                select (e);
            }
        }

        private void activate_element (Element e, double sx, double sy, double wx, double wy) {
            var win0 = get_root () as SlidesWindow;
            if (e is EquationElement) {
                select (e);
                if (win0 != null) win0.edit_equation.begin ((EquationElement) e);
                return;
            }
            if (e is DiagramElement || e is MediaElement || e is ZoomElement || e is ForeignElement || e is InkElement) {
                select (e);
                if (win0 != null) win0.show_format_panel ();
                return;
            }
            if (e is ImageElement) {
                select (e);
                crop_mode = true;
                queue_draw ();
                return;
            }
            if (e is ChartElement) {
                select (e);
                var win = get_root () as SlidesWindow;
                if (win != null) win.edit_chart_data ((ChartElement) e);
                return;
            }
            if (e is GroupElement) {
                var g = (GroupElement) e;
                for (int i = g.children.size - 1; i >= 0; i--) {
                    if (g.children[i].contains (sx, sy) && g.children[i].text_body () != null) {
                        select (e);
                        return;
                    }
                }
                return;
            }
            var t = e as TableElement;
            if (t != null) {
                int r, c;
                if (t.cell_at (sx, sy, out r, out c)) {
                    select (e);
                    begin_edit (e, r, c, (int) wx, (int) wy);
                }
                return;
            }
            var s = e as ShapeElement;
            if (s != null && s.shape != ShapeKind.LINE) {
                select (e);
                begin_edit (e, -1, -1, (int) wx, (int) wy);
            }
        }

        private void on_drag_begin (double x, double y) {
            if (pres == null || editor != null) {
                mode = DragMode.NONE;
                return;
            }
            double sx, sy;
            to_slide (x, y, out sx, out sy);
            press_x = sx;
            press_y = sy;
            last_x = sx;
            last_y = sy;
            drag_started = false;
            drag_copy = (drag_gesture.get_current_event_state () & Gdk.ModifierType.ALT_MASK) != 0;
            vguides.clear ();
            hguides.clear ();
            spacing_marks.clear ();
            if (crop_mode && selection.size == 1) {
                int ch = hit_crop_handle (x, y);
                if (ch >= 0) {
                    int[] map = { 0, 1, 2, 3, 5, 6, 7, 8 };
                    int idx = map[ch];
                    handle_x = idx % 3 - 1;
                    handle_y = idx / 3 - 1;
                    mode = DragMode.CROP;
                } else {
                    mode = DragMode.CROP_PAN;
                }
                snapshot_selection ();
                return;
            }
            int hnd = hit_handle (x, y);
            if (hnd == 8) {
                mode = DragMode.ROTATE;
                snapshot_selection ();
                return;
            }
            if (hnd == 10 || hnd == 11) {
                mode = hnd == 10 ? DragMode.LINE_START : DragMode.LINE_END;
                snapshot_selection ();
                return;
            }
            if (hnd >= 0) {
                int[] d = handle_dirs (hnd);
                handle_x = d[0];
                handle_y = d[1];
                mode = DragMode.RESIZE;
                snapshot_selection ();
                return;
            }
            var t = selection.size == 1 ? selection[0] as TableElement : null;
            if (t != null) {
                bool col = false;
                int line = hit_table_line (t, sx, sy, out col);
                if (line >= 0) {
                    mode = col ? DragMode.TABLE_COL : DragMode.TABLE_ROW;
                    table_line = line;
                    table_orig = col ? t.col_widths[line - 1] : t.row_heights[line - 1];
                    table_next = col && line < t.cols ? t.col_widths[line] : (!col && line < t.rows ? t.row_heights[line] : 0);
                    snapshot_selection ();
                    return;
                }
                if (cell_r1 >= 0) {
                    int r, c;
                    if (t.cell_at (sx, sy, out r, out c)) {
                        mode = DragMode.NONE;
                        return;
                    }
                }
            }
            var e = hit (sx, sy);
            if (e != null) {
                bool adding = (drag_gesture.get_current_event_state () & (Gdk.ModifierType.SHIFT_MASK | Gdk.ModifierType.CONTROL_MASK)) != 0;
                if (!selection.contains (e)) {
                    if (adding) {
                        mode = DragMode.NONE;
                        return;
                    }
                    select (e);
                }
                mode = DragMode.MOVE;
                foreach (var s in selection) if (s.locked) mode = DragMode.NONE;
                snapshot_selection ();
            } else {
                mode = DragMode.RUBBER;
                rubber_x2 = sx;
                rubber_y2 = sy;
            }
        }

        private void snapshot_selection () {
            drag_orig.clear ();
            foreach (var e in selection) drag_orig.add (new Snapshot0 (e));
        }

        private void start_change () {
            if (drag_started) return;
            drag_started = true;
            if (mode == DragMode.RUBBER) return;
            string label;
            switch (mode) {
                case DragMode.MOVE: label = drag_copy ? _("Duplicate") : _("Move"); break;
                case DragMode.ADJUST: label = _("Adjust Shape"); break;
                case DragMode.POINT: label = _("Edit Points"); break;
                case DragMode.GUIDE: label = _("Move Guide"); break;
                case DragMode.COMMENT: label = _("Move Comment"); break;
                case DragMode.RESIZE: label = _("Resize"); break;
                case DragMode.ROTATE: label = _("Rotate"); break;
                case DragMode.CROP: case DragMode.CROP_PAN: label = _("Crop"); break;
                default: label = _("Change"); break;
            }
            foreach (var o in drag_orig) {
                o.element.x = o.x;
                o.element.y = o.y;
                o.element.w = o.w;
                o.element.h = o.h;
            }
            doc.checkpoint (label);
            if (drag_copy && mode == DragMode.MOVE) {
                var copies = new Gee.ArrayList<Element> ();
                var list = elements ();
                foreach (var o in drag_orig) {
                    var c = o.element.clone ();
                    pres.assign_ids (c);
                    c.placeholder = PlaceholderKind.NONE;
                    list.add (c);
                    copies.add (c);
                }
                selection.clear ();
                selection.add_all (copies);
                snapshot_selection ();
            }
            foreach (var e in selection) e.inherit_geometry = false;
        }

        private void on_drag_update (double dx, double dy) {
            if (mode == DragMode.NONE || pres == null) return;
            double sx = press_x + dx / scale, sy = press_y + dy / scale;
            if (mode == DragMode.INK || mode == DragMode.SCRIBBLE) {
                update_tool_drag (sx, sy);
                return;
            }
            if (!drag_started && Math.fabs (dx) < 3 && Math.fabs (dy) < 3) return;
            start_change ();
            var state = drag_gesture.get_current_event_state ();
            bool shift = (state & Gdk.ModifierType.SHIFT_MASK) != 0;
            bool nosnap = (state & Gdk.ModifierType.CONTROL_MASK) != 0 || !snap;
            vguides.clear ();
            hguides.clear ();
            spacing_marks.clear ();
            switch (mode) {
                case DragMode.RUBBER:
                    rubber_x2 = sx;
                    rubber_y2 = sy;
                    break;
                case DragMode.MOVE:
                    drag_move (sx - press_x, sy - press_y, shift, nosnap);
                    break;
                case DragMode.RESIZE:
                    drag_resize (sx, sy, shift, nosnap);
                    break;
                case DragMode.ROTATE:
                    drag_rotate (sx, sy, shift);
                    break;
                case DragMode.LINE_START:
                case DragMode.LINE_END:
                    drag_line (sx, sy, shift, nosnap);
                    break;
                case DragMode.CROP:
                    drag_crop (sx - press_x, sy - press_y);
                    break;
                case DragMode.CROP_PAN:
                    drag_crop_pan (sx - press_x, sy - press_y);
                    break;
                case DragMode.TABLE_COL:
                case DragMode.TABLE_ROW:
                    drag_table (mode == DragMode.TABLE_COL ? sx - press_x : sy - press_y);
                    break;
                case DragMode.ADJUST:
                    drag_adjust (sx, sy);
                    break;
                case DragMode.POINT:
                    drag_point (sx, sy);
                    break;
                case DragMode.GUIDE:
                    if (guide_index >= 0 && guide_index < pres.guides_x.size) pres.guides_x[guide_index] = snap_grid (sx).clamp (0, pres.width);
                    else if (guide_index < 0 && -guide_index - 1 < pres.guides_y.size) pres.guides_y[-guide_index - 1] = snap_grid (sy).clamp (0, pres.height);
                    break;
                case DragMode.COMMENT:
                    if (drag_comment != null) {
                        drag_comment.x = sx;
                        drag_comment.y = sy;
                    }
                    break;
                default:
                    break;
            }
            queue_draw ();
            if (mode != DragMode.RUBBER) edited ();
        }

        private void on_drag_end (double dx, double dy) {
            if (mode == DragMode.INK || mode == DragMode.SCRIBBLE) {
                end_tool_drag ();
                return;
            }
            if (mode == DragMode.POINT && drag_started && selection.size == 1) normalize_custom ((ShapeElement) selection[0]);
            if (mode == DragMode.GUIDE && drag_started) {
                if (guide_index >= 0 && guide_index < pres.guides_x.size && (pres.guides_x[guide_index] <= 1 || pres.guides_x[guide_index] >= pres.width - 1)) pres.guides_x.remove_at (guide_index);
                else if (guide_index < 0 && -guide_index - 1 < pres.guides_y.size) {
                    double gy = pres.guides_y[-guide_index - 1];
                    if (gy <= 1 || gy >= pres.height - 1) pres.guides_y.remove_at (-guide_index - 1);
                }
            }
            if (mode == DragMode.RUBBER && drag_started) {
                double x1 = double.min (press_x, rubber_x2), x2 = double.max (press_x, rubber_x2);
                double y1 = double.min (press_y, rubber_y2), y2 = double.max (press_y, rubber_y2);
                var state = drag_gesture.get_current_event_state ();
                if ((state & (Gdk.ModifierType.SHIFT_MASK | Gdk.ModifierType.CONTROL_MASK)) == 0) selection.clear ();
                foreach (var e in elements ()) {
                    double bx, by, bw, bh;
                    e.bounds (out bx, out by, out bw, out bh);
                    if (bx >= x1 && by >= y1 && bx + bw <= x2 && by + bh <= y2 && !selection.contains (e)) selection.add (e);
                }
                selection_changed ();
            } else if (drag_started && mode != DragMode.NONE) {
                foreach (var e in selection) fit_text_box (e);
                doc.touch ();
            }
            mode = DragMode.NONE;
            drag_started = false;
            vguides.clear ();
            hguides.clear ();
            spacing_marks.clear ();
            queue_draw ();
            edited ();
        }

        private void snap_targets (out Gee.ArrayList<double?> xs, out Gee.ArrayList<double?> ys) {
            xs = new Gee.ArrayList<double?> ();
            ys = new Gee.ArrayList<double?> ();
            xs.add (0);
            xs.add (pres.width / 2);
            xs.add (pres.width);
            ys.add (0);
            ys.add (pres.height / 2);
            ys.add (pres.height);
            if (pres.show_guides) {
                xs.add_all (pres.guides_x);
                ys.add_all (pres.guides_y);
            }
            foreach (var e in elements ()) {
                if (selection.contains (e)) continue;
                double bx, by, bw, bh;
                e.bounds (out bx, out by, out bw, out bh);
                xs.add (bx);
                xs.add (bx + bw / 2);
                xs.add (bx + bw);
                ys.add (by);
                ys.add (by + bh / 2);
                ys.add (by + bh);
            }
        }

        private double best_snap (double[] edges, Gee.List<double?> targets, Gee.List<double?> guides) {
            double thr = 6 / scale;
            double best = double.MAX;
            foreach (double e in edges) {
                foreach (double? t in targets) {
                    double d = t - e;
                    if (Math.fabs (d) < Math.fabs (best) && Math.fabs (d) <= thr) best = d;
                }
            }
            if (best == double.MAX) return 0;
            foreach (double e in edges) {
                foreach (double? t in targets) {
                    if (Math.fabs (t - (e + best)) < 0.01 && !guides.contains (t)) guides.add (t);
                }
            }
            return best;
        }

        private void selection_bounds_from (Gee.List<Snapshot0> list, out double x1, out double y1, out double x2, out double y2) {
            x1 = double.MAX;
            y1 = double.MAX;
            x2 = -double.MAX;
            y2 = -double.MAX;
            foreach (var o in list) {
                double bx, by, bw, bh;
                o.copy.bounds (out bx, out by, out bw, out bh);
                x1 = double.min (x1, bx);
                y1 = double.min (y1, by);
                x2 = double.max (x2, bx + bw);
                y2 = double.max (y2, by + bh);
            }
        }

        private void drag_move (double dx, double dy, bool shift, bool nosnap) {
            if (shift) {
                if (Math.fabs (dx) > Math.fabs (dy)) dy = 0;
                else dx = 0;
            }
            double x1, y1, x2, y2;
            selection_bounds_from (drag_orig, out x1, out y1, out x2, out y2);
            if (!nosnap) {
                Gee.ArrayList<double?> xs, ys;
                snap_targets (out xs, out ys);
                double w = x2 - x1, h = y2 - y1;
                double[] ex = { x1 + dx, x1 + dx + w / 2, x1 + dx + w };
                double[] ey = { y1 + dy, y1 + dy + h / 2, y1 + dy + h };
                double sdx = best_snap (ex, xs, vguides);
                double sdy = best_snap (ey, ys, hguides);
                if (sdx == 0) sdx = equal_spacing (x1 + dx, y1 + dy, w, h, true);
                if (sdy == 0) sdy = equal_spacing (x1 + dx, y1 + dy, w, h, false);
                if (!shift || dx != 0) dx += sdx;
                if (!shift || dy != 0) dy += sdy;
                if (pres.snap_to_grid && sdx == 0) dx = snap_grid (x1 + dx) - x1;
                if (pres.snap_to_grid && sdy == 0) dy = snap_grid (y1 + dy) - y1;
            }
            foreach (var o in drag_orig) {
                if (!(o.element is GroupElement)) {
                    o.element.move_by (dx - (o.element.x - o.x), dy - (o.element.y - o.y));
                    continue;
                }
                o.element.x = o.x;
                o.element.y = o.y;
                if (o.element is GroupElement) {
                    var g = (GroupElement) o.element;
                    var orig = (GroupElement) o.copy;
                    for (int i = 0; i < g.children.size && i < orig.children.size; i++) restore_group_child (g.children[i], orig.children[i]);
                }
                o.element.move_by (dx, dy);
            }
        }

        private void restore_group_child (Element e, Element orig) {
            e.x = orig.x;
            e.y = orig.y;
            e.w = orig.w;
            e.h = orig.h;
            var g = e as GroupElement;
            var og = orig as GroupElement;
            if (g != null && og != null) for (int i = 0; i < g.children.size && i < og.children.size; i++) restore_group_child (g.children[i], og.children[i]);
            var t = e as TableElement;
            var ot = orig as TableElement;
            if (t != null && ot != null) {
                for (int i = 0; i < t.col_widths.size && i < ot.col_widths.size; i++) t.col_widths[i] = ot.col_widths[i];
                for (int i = 0; i < t.row_heights.size && i < ot.row_heights.size; i++) t.row_heights[i] = ot.row_heights[i];
            }
        }

        private double equal_spacing (double x, double y, double w, double h, bool horizontal) {
            double thr = 6 / scale;
            Element? before = null, after = null;
            double gap_b = double.MAX, gap_a = double.MAX;
            foreach (var e in elements ()) {
                if (selection.contains (e)) continue;
                double bx, by, bw, bh;
                e.bounds (out bx, out by, out bw, out bh);
                bool overlap = horizontal ? (by < y + h && by + bh > y) : (bx < x + w && bx + bw > x);
                if (!overlap) continue;
                if (horizontal) {
                    if (bx + bw <= x + thr && x - (bx + bw) < gap_b) {
                        gap_b = x - (bx + bw);
                        before = e;
                    }
                    if (bx >= x + w - thr && bx - (x + w) < gap_a) {
                        gap_a = bx - (x + w);
                        after = e;
                    }
                } else {
                    if (by + bh <= y + thr && y - (by + bh) < gap_b) {
                        gap_b = y - (by + bh);
                        before = e;
                    }
                    if (by >= y + h - thr && by - (y + h) < gap_a) {
                        gap_a = by - (y + h);
                        after = e;
                    }
                }
            }
            if (before == null || after == null) return 0;
            double delta = (gap_a - gap_b) / 2;
            if (Math.fabs (delta) > thr) return 0;
            double bx, by, bw, bh, ax, ay, aw, ah;
            before.bounds (out bx, out by, out bw, out bh);
            after.bounds (out ax, out ay, out aw, out ah);
            double gap = (gap_a + gap_b) / 2;
            if (horizontal) {
                double my = y + h / 2;
                double nx = x + delta;
                spacing_marks.add (bx + bw);
                spacing_marks.add (my);
                spacing_marks.add (nx);
                spacing_marks.add (my);
                spacing_marks.add (nx + w);
                spacing_marks.add (my);
                spacing_marks.add (nx + w + gap);
                spacing_marks.add (my);
            } else {
                double mx = x + w / 2;
                double ny = y + delta;
                spacing_marks.add (mx);
                spacing_marks.add (by + bh);
                spacing_marks.add (mx);
                spacing_marks.add (ny);
                spacing_marks.add (mx);
                spacing_marks.add (ny + h);
                spacing_marks.add (mx);
                spacing_marks.add (ny + h + gap);
            }
            return delta;
        }

        private void drag_resize (double sx, double sy, bool shift, bool nosnap) {
            if (drag_orig.size == 0) return;
            var o = drag_orig[0];
            var e = o.element;
            double a = o.rotation * Math.PI / 180;
            double cx = o.x + o.w / 2, cy = o.y + o.h / 2;
            double ax = cx - handle_x * o.w / 2 * Math.cos (a) + handle_y * o.h / 2 * Math.sin (a);
            double ay = cy - handle_x * o.w / 2 * Math.sin (a) - handle_y * o.h / 2 * Math.cos (a);
            double vx = sx - ax, vy = sy - ay;
            double lx = vx * Math.cos (-a) - vy * Math.sin (-a);
            double ly = vx * Math.sin (-a) + vy * Math.cos (-a);
            double nw = handle_x != 0 ? lx * handle_x : o.w;
            double nh = handle_y != 0 ? ly * handle_y : o.h;
            bool keep = shift || (e is ImageElement && handle_x != 0 && handle_y != 0) || (e is GroupElement && handle_x != 0 && handle_y != 0);
            if (keep && o.w > 0 && o.h > 0) {
                double ratio = o.w / o.h;
                if (handle_x == 0) nw = nh * ratio;
                else if (handle_y == 0) nh = nw / ratio;
                else if (nw / ratio > nh) nh = nw / ratio;
                else nw = nh * ratio;
            }
            nw = double.max (nw, 4);
            nh = double.max (nh, 4);
            if (!nosnap && o.rotation == 0) {
                Gee.ArrayList<double?> xs, ys;
                snap_targets (out xs, out ys);
                if (handle_x != 0) {
                    double edge = handle_x > 0 ? ax + nw : ax - nw;
                    double d = best_snap ({ edge }, xs, vguides);
                    nw += d * handle_x;
                }
                if (handle_y != 0) {
                    double edge = handle_y > 0 ? ay + nh : ay - nh;
                    double d = best_snap ({ edge }, ys, hguides);
                    nh += d * handle_y;
                }
            }
            double hx = handle_x * nw / 2;
            double hy = handle_y * nh / 2;
            double ncx = ax + (hx * Math.cos (a) - hy * Math.sin (a));
            double ncy = ay + (hx * Math.sin (a) + hy * Math.cos (a));
            if (e is GroupElement || e is TableElement) {
                restore_group_child (e, o.copy);
                e.scale_into (ncx - nw / 2, ncy - nh / 2, nw, nh);
            } else {
                e.set_geometry (ncx - nw / 2, ncy - nh / 2, nw, nh);
            }
            fit_text_box (e);
        }

        public void fit_text_box (Element e) {
            var s = e as ShapeElement;
            if (s == null || s.text == null || s.text.autofit != AutoFit.RESIZE) return;
            var ctx = context ();
            double h = renderer.text_height (ctx, s, s.text, s.w);
            if (Math.fabs (h - s.h) > 0.5) s.h = h;
        }

        private void drag_rotate (double sx, double sy, bool shift) {
            foreach (var o in drag_orig) {
                double cx = o.x + o.w / 2, cy = o.y + o.h / 2;
                double ang = Math.atan2 (sy - cy, sx - cx) * 180 / Math.PI + 90;
                if (shift) ang = Math.round (ang / 15) * 15;
                else if (snap) {
                    foreach (double k in new double[] { 0, 90, 180, 270, 360, -90 }) if (Math.fabs (ang - k) < 3) ang = k;
                }
                ang = Math.fmod (ang + 360, 360);
                o.element.rotation = Math.round (ang * 10) / 10;
            }
        }

        private void drag_line (double sx, double sy, bool shift, bool nosnap) {
            var s = (ShapeElement) drag_orig[0].element;
            var o = (ShapeElement) drag_orig[0].copy;
            double x1, y1, x2, y2;
            line_ends (o, out x1, out y1, out x2, out y2);
            double fx = mode == DragMode.LINE_START ? x2 : x1, fy = mode == DragMode.LINE_START ? y2 : y1;
            if (shift) {
                double ang = Math.atan2 (sy - fy, sx - fx);
                double len = Math.sqrt ((sx - fx) * (sx - fx) + (sy - fy) * (sy - fy));
                ang = Math.round (ang / (Math.PI / 4)) * (Math.PI / 4);
                sx = fx + Math.cos (ang) * len;
                sy = fy + Math.sin (ang) * len;
            } else if (!nosnap) {
                Gee.ArrayList<double?> xs, ys;
                snap_targets (out xs, out ys);
                sx += best_snap ({ sx }, xs, vguides);
                sy += best_snap ({ sy }, ys, hguides);
            }
            double ax = mode == DragMode.LINE_START ? sx : fx, ay = mode == DragMode.LINE_START ? sy : fy;
            double bx = mode == DragMode.LINE_START ? fx : sx, by = mode == DragMode.LINE_START ? fy : sy;
            s.flip_h = bx < ax;
            s.flip_v = by < ay;
            s.set_geometry (double.min (ax, bx), double.min (ay, by), Math.fabs (bx - ax), Math.fabs (by - ay));
        }

        private void drag_crop (double dx, double dy) {
            var img = (ImageElement) drag_orig[0].element;
            var o = (ImageElement) drag_orig[0].copy;
            double fw = o.w / double.max (1 - o.crop_left - o.crop_right, 0.01);
            double fh = o.h / double.max (1 - o.crop_top - o.crop_bottom, 0.01);
            img.crop_left = o.crop_left;
            img.crop_right = o.crop_right;
            img.crop_top = o.crop_top;
            img.crop_bottom = o.crop_bottom;
            img.set_geometry (o.x, o.y, o.w, o.h);
            if (handle_x < 0) {
                double d = dx.clamp (-o.crop_left * fw, o.w - 8);
                img.crop_left = o.crop_left + d / fw;
                img.x = o.x + d;
                img.w = o.w - d;
            } else if (handle_x > 0) {
                double d = dx.clamp (-(o.w - 8), o.crop_right * fw);
                img.crop_right = o.crop_right - d / fw;
                img.w = o.w + d;
            }
            if (handle_y < 0) {
                double d = dy.clamp (-o.crop_top * fh, o.h - 8);
                img.crop_top = o.crop_top + d / fh;
                img.y = o.y + d;
                img.h = o.h - d;
            } else if (handle_y > 0) {
                double d = dy.clamp (-(o.h - 8), o.crop_bottom * fh);
                img.crop_bottom = o.crop_bottom - d / fh;
                img.h = o.h + d;
            }
        }

        private void drag_crop_pan (double dx, double dy) {
            var img = (ImageElement) drag_orig[0].element;
            var o = (ImageElement) drag_orig[0].copy;
            double fw = o.w / double.max (1 - o.crop_left - o.crop_right, 0.01);
            double fh = o.h / double.max (1 - o.crop_top - o.crop_bottom, 0.01);
            double ddx = (-dx / fw).clamp (-o.crop_left, o.crop_right);
            double ddy = (-dy / fh).clamp (-o.crop_top, o.crop_bottom);
            img.crop_left = o.crop_left + ddx;
            img.crop_right = o.crop_right - ddx;
            img.crop_top = o.crop_top + ddy;
            img.crop_bottom = o.crop_bottom - ddy;
        }

        private void drag_table (double d) {
            var t = (TableElement) drag_orig[0].element;
            int i = table_line - 1;
            if (mode == DragMode.TABLE_COL) {
                double nw = double.max (table_orig + d, 12);
                if (table_line < t.cols) {
                    double total = table_orig + table_next;
                    nw = double.min (nw, total - 12);
                    t.col_widths[i] = nw;
                    t.col_widths[i + 1] = total - nw;
                } else {
                    t.col_widths[i] = nw;
                }
            } else {
                double nh = double.max (table_orig + d, 12);
                t.row_heights[i] = nh;
            }
            t.sync_size ();
        }

        public void nudge (double dx, double dy) {
            if (selection.size == 0) return;
            doc.checkpoint (_("Move"), "nudge");
            foreach (var e in selection) {
                if (e.locked) continue;
                e.inherit_geometry = false;
                e.move_by (dx, dy);
            }
            doc.touch ();
            queue_draw ();
            edited ();
        }

        private bool on_key (uint keyval, uint keycode, Gdk.ModifierType state) {
            if (pres == null || editor != null) return false;
            bool shift = (state & Gdk.ModifierType.SHIFT_MASK) != 0;
            bool ctrl = (state & Gdk.ModifierType.CONTROL_MASK) != 0;
            double step = shift ? 10 : 1;
            switch (keyval) {
                case Gdk.Key.Left:
                    if (selection.size == 0) {
                        page_requested (-1);
                        return true;
                    }
                    nudge (-step, 0);
                    return true;
                case Gdk.Key.Right:
                    if (selection.size == 0) {
                        page_requested (1);
                        return true;
                    }
                    nudge (step, 0);
                    return true;
                case Gdk.Key.Up:
                    if (selection.size == 0) {
                        page_requested (-1);
                        return true;
                    }
                    nudge (0, -step);
                    return true;
                case Gdk.Key.Down:
                    if (selection.size == 0) {
                        page_requested (1);
                        return true;
                    }
                    nudge (0, step);
                    return true;
                case Gdk.Key.Page_Up:
                    page_requested (-1);
                    return true;
                case Gdk.Key.Page_Down:
                    page_requested (1);
                    return true;
                case Gdk.Key.Delete:
                case Gdk.Key.BackSpace:
                    if (selection.size == 0) return false;
                    activate_action ("win.delete", null);
                    return true;
                case Gdk.Key.Escape:
                    if (tool == CanvasTool.FREEFORM && free_pts.size >= 6) {
                        finish_freeform (false);
                        return true;
                    }
                    if (tool != CanvasTool.SELECT) {
                        set_tool (CanvasTool.SELECT);
                        return true;
                    }
                    if (points_mode) {
                        points_mode = false;
                        queue_draw ();
                        return true;
                    }
                    if (crop_mode) {
                        crop_mode = false;
                        queue_draw ();
                        return true;
                    }
                    if (selection.size > 0) {
                        clear_selection ();
                        return true;
                    }
                    return false;
                case Gdk.Key.Tab:
                case Gdk.Key.ISO_Left_Tab:
                    var list = elements ();
                    if (list.size == 0) return true;
                    int idx = selection.size > 0 ? list.index_of (selection[0]) : -1;
                    idx = shift || keyval == Gdk.Key.ISO_Left_Tab ? (idx <= 0 ? list.size - 1 : idx - 1) : (idx + 1) % list.size;
                    select (list[idx]);
                    return true;
                case Gdk.Key.Return:
                case Gdk.Key.KP_Enter:
                case Gdk.Key.F2:
                    if (tool == CanvasTool.FREEFORM) {
                        finish_freeform (true);
                        return true;
                    }
                    if (crop_mode) {
                        crop_mode = false;
                        queue_draw ();
                        return true;
                    }
                    if (selection.size == 1) {
                        var e = selection[0];
                        if (e is ImageElement) {
                            crop_mode = true;
                            queue_draw ();
                        } else if (e is TableElement) {
                            begin_edit (e, int.max (cell_r1, 0), int.max (cell_c1, 0), -1, -1);
                        } else if (e is ChartElement) {
                            var win = get_root () as SlidesWindow;
                            if (win != null) win.edit_chart_data ((ChartElement) e);
                        } else if (!is_line (e) && e is ShapeElement) {
                            begin_edit (e, -1, -1, -1, -1);
                        }
                        return true;
                    }
                    return false;
                default:
                    break;
            }
            if (ctrl || (state & Gdk.ModifierType.ALT_MASK) != 0) return false;
            unichar ch = Gdk.keyval_to_unicode (keyval);
            if (ch >= 32 && selection.size == 1 && selection[0] is ShapeElement && !is_line (selection[0])) {
                edit_select_all = false;
                begin_edit (selection[0], -1, -1, -1, -1);
                if (editor != null) {
                    editor.buffer.text = "";
                    editor.buffer.insert_at_cursor (ch.to_string (), -1);
                }
                return true;
            }
            return false;
        }

        public void editor_rect (out double x, out double y, out double w, out double h) {
            x = 0;
            y = 0;
            w = 0;
            h = 0;
            if (editor == null) return;
            var e = editor.element;
            double ex, ey, ew, eh;
            geometry_of (e, out ex, out ey, out ew, out eh);
            var t = e as TableElement;
            if (t != null) {
                int r = editor.cell_row, c = editor.cell_col;
                var cell = t.cells[r][c];
                double cw = 0, ch = 0;
                for (int k = c; k < c + cell.col_span && k < t.cols; k++) cw += t.col_widths[k];
                for (int k = r; k < r + cell.row_span && k < t.rows; k++) ch += t.row_heights[k];
                x = ex + (t.col_x (c) - t.x);
                y = ey + (t.row_y (r) - t.y);
                w = cw;
                h = ch;
                return;
            }
            var s = e as ShapeElement;
            if (s != null) {
                Geometry.text_rect (s, ex, ey, ew, eh, out x, out y, out w, out h);
                return;
            }
            x = ex;
            y = ey;
            w = ew;
            h = eh;
        }

        private void place_editor () {
            double x, y, w, h;
            editor_rect (out x, out y, out w, out h);
            var body = editor.source;
            double ix = x + body.inset_left, iy = y + body.inset_top;
            double iw = double.max (w - body.inset_left - body.inset_right, 4);
            double ih = h - body.inset_top - body.inset_bottom;
            int pw = (int) Math.ceil (iw * scale);
            int min_h, nat_h, mb, nb;
            editor.measure (Orientation.VERTICAL, pw, out min_h, out nat_h, out mb, out nb);
            double th = nat_h / scale;
            var ctx = context ();
            var anchor = editor.cell_row >= 0 ? ((TableElement) editor.element).cells[editor.cell_row][editor.cell_col].anchor : pres.effective_anchor (ctx.slide, ctx.layout, ctx.master, editor.element, body);
            double top = iy;
            if (anchor == TextAnchor.MIDDLE) top = iy + (ih - th) / 2;
            else if (anchor == TextAnchor.BOTTOM) top = iy + ih - th;
            double wx, wy;
            to_widget (ix, top, out wx, out wy);
            var alloc = Gtk.Allocation ();
            alloc.x = (int) Math.round (wx);
            alloc.y = (int) Math.round (wy);
            alloc.width = pw;
            alloc.height = int.max (nat_h, (int) (12 * scale));
            editor.allocate_size (alloc, -1);
        }

        public bool is_editing () {
            return editor != null;
        }

        public void begin_edit (Element e, int row, int col, int click_x, int click_y) {
            commit_edit ();
            var ctx = context ();
            TextBody body;
            string color = renderer.default_text_color (ctx, e);
            bool bold = false;
            var t = e as TableElement;
            if (t != null) {
                if (row < 0 || col < 0 || row >= t.rows || col >= t.cols) return;
                if (t.cells[row][col].covered) return;
                body = t.cells[row][col].text;
                var fill = ctx.theme.resolve (renderer.table_cell_fill (t, row, col));
                color = fill.a > 0.3 ? Renderer.contrast_for (ctx, fill) : "";
                bold = renderer.table_cell_bold (t, row, col);
                cell_r1 = cell_r2 = row;
                cell_c1 = cell_c2 = col;
            } else {
                var s = e as ShapeElement;
                if (s == null || s.shape == ShapeKind.LINE) return;
                if (s.text == null) {
                    s.ensure_text ();
                    s.text.anchor_set = true;
                }
                body = s.text;
            }
            doc.checkpoint (_("Typing"));
            if (editor_instance == null) {
                editor_instance = new TextEditor ();
                editor_instance.content_changed.connect (on_editor_changed);
                var ek = new EventControllerKey ();
                ek.propagation_phase = PropagationPhase.CAPTURE;
                ek.key_pressed.connect (on_editor_key);
                editor_instance.add_controller (ek);
            }
            editor_instance.configure (ctx, e, body, scale, color, bold);
            editor = editor_instance;
            editor.cell_row = row;
            editor.cell_col = col;
            renderer.hidden_text_id = e.id;
            renderer.hidden_cell_row = row;
            renderer.hidden_cell_col = col;
            editor.set_parent (this);
            edit_click_x = click_x;
            edit_click_y = click_y;
            queue_allocate ();
            queue_draw ();
            editor.grab_focus ();
            Idle.add (() => {
                if (editor == null) return Source.REMOVE;
                if (edit_click_x >= 0) {
                    double lx = edit_click_x, ly = edit_click_y;
                    Graphene.Point src = Graphene.Point ();
                    src.init ((float) lx, (float) ly);
                    Graphene.Point dst;
                    if (compute_point (editor, src, out dst)) {
                        int bx, by;
                        editor.window_to_buffer_coords (TextWindowType.TEXT, (int) dst.x, (int) dst.y, out bx, out by);
                        TextIter it;
                        if (editor.get_iter_at_location (out it, bx, by)) editor.buffer.place_cursor (it);
                        else {
                            editor.buffer.get_end_iter (out it);
                            editor.buffer.place_cursor (it);
                        }
                    }
                } else if (edit_cursor >= 0) {
                    TextIter p;
                    editor.buffer.get_iter_at_offset (out p, edit_cursor);
                    editor.buffer.place_cursor (p);
                } else if (edit_select_all) {
                    TextIter a, b;
                    editor.buffer.get_bounds (out a, out b);
                    editor.buffer.select_range (a, b);
                } else {
                    TextIter end;
                    editor.buffer.get_end_iter (out end);
                    editor.buffer.place_cursor (end);
                }
                edit_select_all = true;
                edit_cursor = -1;
                return Source.REMOVE;
            });
            editing_changed ();
        }

        private void on_editor_changed () {
            if (editor == null) return;
            var s = editor.element as ShapeElement;
            if (s != null && s.text != null && s.text.autofit == AutoFit.RESIZE) {
                var body = editor.to_body ();
                double h = renderer.text_height (context (), s, body, s.w);
                if (Math.fabs (h - s.h) > 0.5) {
                    s.h = h;
                    s.inherit_geometry = false;
                    queue_draw ();
                }
            }
            var t = editor.element as TableElement;
            if (t != null) {
                var body = editor.to_body ();
                double need = renderer.text_height (context (), t, body, t.col_widths[editor.cell_col]);
                if (need > t.row_heights[editor.cell_row]) {
                    t.row_heights[editor.cell_row] = Math.ceil (need);
                    t.sync_size ();
                    queue_draw ();
                }
            }
            queue_allocate ();
            edited ();
        }

        private bool on_editor_key (uint keyval, uint keycode, Gdk.ModifierType state) {
            if (editor == null) return false;
            bool shift = (state & Gdk.ModifierType.SHIFT_MASK) != 0;
            if (keyval == Gdk.Key.Escape) {
                var e = editor.element;
                commit_edit ();
                select (e);
                grab_focus ();
                return true;
            }
            if (keyval == Gdk.Key.Tab || keyval == Gdk.Key.ISO_Left_Tab) {
                var t = editor.element as TableElement;
                if (t != null) {
                    int r = editor.cell_row, c = editor.cell_col;
                    bool back = shift || keyval == Gdk.Key.ISO_Left_Tab;
                    commit_edit ();
                    do {
                        if (back) {
                            c--;
                            if (c < 0) {
                                c = t.cols - 1;
                                r--;
                            }
                        } else {
                            c++;
                            if (c >= t.cols) {
                                c = 0;
                                r++;
                            }
                        }
                    } while (r >= 0 && r < t.rows && t.cells[r][c].covered);
                    if (r >= t.rows) {
                        doc.checkpoint (_("Insert Row"));
                        t.insert_row (t.rows);
                        doc.touch ();
                        edited ();
                    }
                    if (r < 0) r = 0;
                    begin_edit (t, r, c, -1, -1);
                    return true;
                }
                editor.apply_paragraph ((p) => p.level = (p.level + (shift || keyval == Gdk.Key.ISO_Left_Tab ? -1 : 1)).clamp (0, 8));
                return true;
            }
            return false;
        }

        private uint rescale_id = 0;

        private void restart_edit () {
            if (editor == null || rescale_id != 0) return;
            rescale_id = Idle.add (() => {
                rescale_id = 0;
                if (editor != null) {
                    editor.rescale (scale);
                    queue_allocate ();
                }
                return Source.REMOVE;
            });
        }

        public void commit_edit () {
            if (editor == null) return;
            var ed = editor;
            editor = null;
            var body = ed.to_body ();
            bool changed = !same_text (body, ed.source);
            var t = ed.element as TableElement;
            if (t != null) {
                if (changed) t.cells[ed.cell_row][ed.cell_col].text = body;
            } else {
                var s = ed.element as ShapeElement;
                if (s != null && changed) s.text = body;
                if (s != null && s.text != null && s.text.autofit == AutoFit.RESIZE) fit_text_box (s);
            }
            if (t != null) renderer.fit_table_rows (context (), t);
            renderer.hidden_text_id = -1;
            renderer.hidden_cell_row = -1;
            ed.unparent ();
            if (changed) doc.touch ();
            else doc.drop_checkpoint ();
            queue_draw ();
            edited ();
            editing_changed ();
        }

        public static bool same_text (TextBody a, TextBody b) {
            if (a.paragraphs.size != b.paragraphs.size) return false;
            for (int i = 0; i < a.paragraphs.size; i++) {
                var pa = a.paragraphs[i];
                var pb = b.paragraphs[i];
                if (pa.text () != pb.text () || pa.align != pb.align || pa.level != pb.level || pa.bullet != pb.bullet) return false;
                if (pa.runs.size != pb.runs.size) return false;
                for (int k = 0; k < pa.runs.size; k++) if (!pa.runs[k].same_format (pb.runs[k]) || pa.runs[k].text != pb.runs[k].text || pa.runs[k].field != pb.runs[k].field) return false;
            }
            return true;
        }

        public override void dispose () {
            if (editor != null) {
                editor.unparent ();
                editor = null;
            }
            editor_instance = null;
            base.dispose ();
        }
    }
}
