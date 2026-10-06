namespace Singularity.Apps.Slides {

    public class RecordSink : Object, PathSink {
        public Gee.ArrayList<PathOp> ops = new Gee.ArrayList<PathOp> ();

        public void move_to (double x, double y) {
            ops.add (new PathOp ('M', { x, y }));
        }

        public void line_to (double x, double y) {
            ops.add (new PathOp ('L', { x, y }));
        }

        public void curve_to (double x1, double y1, double x2, double y2, double x3, double y3) {
            ops.add (new PathOp ('C', { x1, y1, x2, y2, x3, y3 }));
        }

        public void close_path () {
            ops.add (new PathOp ('Z', {}));
        }
    }

    public class ShapeOps {
        public static Gee.ArrayList<PathOp> local_ops (ShapeElement s) {
            var sink = new RecordSink ();
            double x = s.x, y = s.y, w = s.w, h = s.h;
            if (s.shape == ShapeKind.CUSTOM) {
                foreach (var c in s.path) {
                    var pts = new double[c.pts.length];
                    for (int i = 0; i + 1 < c.pts.length; i += 2) {
                        pts[i] = x + c.pts[i] * w;
                        pts[i + 1] = y + c.pts[i + 1] * h;
                    }
                    if (c.op == 'Q' && pts.length >= 4) {
                        var last = sink.ops.size > 0 ? sink.ops[sink.ops.size - 1] : null;
                        double lx = last != null && last.pts.length >= 2 ? last.pts[last.pts.length - 2] : x;
                        double ly = last != null && last.pts.length >= 2 ? last.pts[last.pts.length - 1] : y;
                        sink.curve_to (lx + 2.0 / 3 * (pts[0] - lx), ly + 2.0 / 3 * (pts[1] - ly), pts[2] + 2.0 / 3 * (pts[0] - pts[2]), pts[3] + 2.0 / 3 * (pts[1] - pts[3]), pts[2], pts[3]);
                        continue;
                    }
                    sink.ops.add (new PathOp (c.op == 'M' ? 'M' : (c.op == 'L' ? 'L' : (c.op == 'C' ? 'C' : 'Z')), pts));
                }
            } else if (Geometry.uses_preset (s)) {
                PresetGeometry.build (s.preset_name (), x, y, w, h, Geometry.adjust_of (s), sink);
            } else {
                sink.move_to (x, y);
                sink.line_to (x + w, y);
                sink.line_to (x + w, y + h);
                sink.line_to (x, y + h);
                sink.close_path ();
            }
            return sink.ops;
        }

        public static Gee.ArrayList<PathOp> slide_ops (ShapeElement s) {
            var ops = local_ops (s);
            double cx = s.x + s.w / 2, cy = s.y + s.h / 2;
            double a = s.rotation * Math.PI / 180;
            double ca = Math.cos (a), sa = Math.sin (a);
            foreach (var op in ops) {
                for (int i = 0; i + 1 < op.pts.length; i += 2) {
                    double px = op.pts[i], py = op.pts[i + 1];
                    if (s.flip_h) px = 2 * cx - px;
                    if (s.flip_v) py = 2 * cy - py;
                    double dx = px - cx, dy = py - cy;
                    op.pts[i] = cx + dx * ca - dy * sa;
                    op.pts[i + 1] = cy + dx * sa + dy * ca;
                }
            }
            return ops;
        }

        public static ShapeElement? from_ops (Gee.List<PathOp> ops, ShapeElement style) {
            double x1 = double.MAX, y1 = double.MAX, x2 = -double.MAX, y2 = -double.MAX;
            foreach (var op in ops) {
                for (int i = 0; i + 1 < op.pts.length; i += 2) {
                    x1 = double.min (x1, op.pts[i]);
                    y1 = double.min (y1, op.pts[i + 1]);
                    x2 = double.max (x2, op.pts[i]);
                    y2 = double.max (y2, op.pts[i + 1]);
                }
            }
            if (x1 > x2 || y1 > y2) return null;
            double w = double.max (x2 - x1, 0.5), h = double.max (y2 - y1, 0.5);
            var s = new ShapeElement (ShapeKind.CUSTOM);
            s.set_geometry (x1, y1, w, h);
            s.fill = style.fill.clone ();
            s.line = style.line.clone ();
            s.shadow = style.shadow.clone ();
            s.effects = style.effects.clone ();
            if (style.text != null && !style.text.is_empty ()) s.text = style.text.clone ();
            foreach (var op in ops) {
                var pts = new double[op.pts.length];
                for (int i = 0; i + 1 < op.pts.length; i += 2) {
                    pts[i] = (op.pts[i] - x1) / w;
                    pts[i + 1] = (op.pts[i + 1] - y1) / h;
                }
                s.path.add (new PathCommand (op.op, pts));
            }
            return s;
        }

        public static ShapeElement? to_freeform (ShapeElement s) {
            if (s.shape == ShapeKind.CUSTOM || s.shape == ShapeKind.LINE) return null;
            var ops = local_ops (s);
            var r = from_ops (ops, s);
            if (r == null) return null;
            r.id = s.id;
            r.name = s.name;
            r.description = s.description;
            r.set_geometry (s.x, s.y, s.w, s.h);
            r.path.clear ();
            foreach (var op in ops) {
                var pts = new double[op.pts.length];
                for (int i = 0; i + 1 < op.pts.length; i += 2) {
                    pts[i] = s.w > 0 ? (op.pts[i] - s.x) / s.w : 0;
                    pts[i + 1] = s.h > 0 ? (op.pts[i + 1] - s.y) / s.h : 0;
                }
                r.path.add (new PathCommand (op.op, pts));
            }
            r.rotation = s.rotation;
            r.flip_h = s.flip_h;
            r.flip_v = s.flip_v;
            r.text = s.text != null ? s.text.clone () : null;
            r.list_style = s.list_style != null ? s.list_style.clone () : null;
            r.click = s.click;
            return r;
        }

        public static Gee.ArrayList<ShapeElement> merge (Gee.List<ShapeElement> shapes, MergeMode mode) {
            var outlines = new Gee.ArrayList<Outline> ();
            foreach (var s in shapes) outlines.add (PathOps.flatten (slide_ops (s), 0.2));
            var result = new Gee.ArrayList<ShapeElement> ();
            foreach (var o in PathOps.merge (outlines, mode)) {
                var ops = PathOps.to_ops (o);
                var sh = from_ops (ops, shapes[0]);
                if (sh != null) result.add (sh);
            }
            return result;
        }

        public static Gee.ArrayList<PathCommand> simplify_stroke (Gee.List<double?> pts, double tolerance) {
            var keep = new bool[pts.size / 2];
            int n = pts.size / 2;
            if (n == 0) return new Gee.ArrayList<PathCommand> ();
            keep[0] = true;
            keep[n - 1] = true;
            rdp (pts, 0, n - 1, tolerance, keep);
            var list = new Gee.ArrayList<PathCommand> ();
            bool first = true;
            for (int i = 0; i < n; i++) {
                if (!keep[i]) continue;
                list.add (new PathCommand (first ? 'M' : 'L', { pts[i * 2], pts[i * 2 + 1] }));
                first = false;
            }
            return list;
        }

        private static void rdp (Gee.List<double?> pts, int a, int b, double tol, bool[] keep) {
            if (b <= a + 1) return;
            double ax = pts[a * 2], ay = pts[a * 2 + 1], bx = pts[b * 2], by = pts[b * 2 + 1];
            double best = -1;
            int idx = -1;
            double len = Math.hypot (bx - ax, by - ay);
            for (int i = a + 1; i < b; i++) {
                double px = pts[i * 2], py = pts[i * 2 + 1];
                double d = len > 0 ? Math.fabs ((bx - ax) * (ay - py) - (ax - px) * (by - ay)) / len : Math.hypot (px - ax, py - ay);
                if (d > best) {
                    best = d;
                    idx = i;
                }
            }
            if (best > tol && idx > 0) {
                keep[idx] = true;
                rdp (pts, a, idx, tol, keep);
                rdp (pts, idx, b, tol, keep);
            }
        }

        public static Gee.ArrayList<PathCommand> smooth (Gee.List<PathCommand> poly) {
            var out_list = new Gee.ArrayList<PathCommand> ();
            if (poly.size < 3) {
                out_list.add_all (poly);
                return out_list;
            }
            out_list.add (poly[0]);
            for (int i = 1; i < poly.size; i++) {
                var p0 = poly[i - 1].pts;
                var p1 = poly[i].pts;
                var pm = i >= 2 ? poly[i - 2].pts : p0;
                var pn = i + 1 < poly.size ? poly[i + 1].pts : p1;
                double c1x = p0[0] + (p1[0] - pm[0]) / 6, c1y = p0[1] + (p1[1] - pm[1]) / 6;
                double c2x = p1[0] - (pn[0] - p0[0]) / 6, c2y = p1[1] - (pn[1] - p0[1]) / 6;
                out_list.add (new PathCommand ('C', { c1x, c1y, c2x, c2y, p1[0], p1[1] }));
            }
            return out_list;
        }
    }
}
