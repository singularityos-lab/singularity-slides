namespace Singularity.Apps.Slides {

    public enum MergeMode {
        UNION,
        COMBINE,
        FRAGMENT,
        INTERSECT,
        SUBTRACT
    }

    public class PathOp {
        public char op;
        public double[] pts;

        public PathOp (char op, double[] pts) {
            this.op = op;
            this.pts = pts;
        }
    }

    public class Contour {
        public Gee.ArrayList<double?> pts = new Gee.ArrayList<double?> ();

        public int size {
            get { return pts.size / 2; }
        }

        public double px (int i) {
            return pts[2 * i];
        }

        public double py (int i) {
            return pts[2 * i + 1];
        }

        public void add_point (double x, double y) {
            pts.add (x);
            pts.add (y);
        }

        public double area () {
            double a = 0;
            int n = size;
            for (int i = 0; i < n; i++) {
                int j = (i + 1) % n;
                a += px (i) * py (j) - px (j) * py (i);
            }
            return a / 2;
        }

        public Contour reversed () {
            var c = new Contour ();
            for (int i = size - 1; i >= 0; i--) c.add_point (px (i), py (i));
            return c;
        }

        public Contour clone () {
            var c = new Contour ();
            c.pts.add_all (pts);
            return c;
        }
    }

    public class Outline {
        public Gee.ArrayList<Contour> contours = new Gee.ArrayList<Contour> ();

        public Outline () {
        }

        public Outline.from_commands (Gee.List<PathOp> ops, double tolerance = 0.25) {
            contours.add_all (PathOps.flatten (ops, tolerance).contours);
        }

        public double area () {
            double a = 0;
            foreach (var c in contours) a += c.area ();
            return a;
        }

        public bool is_empty () {
            return contours.size == 0;
        }

        public Outline clone () {
            var o = new Outline ();
            foreach (var c in contours) o.contours.add (c.clone ());
            return o;
        }
    }

    public class PathOps {
        public static Outline flatten (Gee.List<PathOp> ops, double tolerance) {
            var o = new Outline ();
            double tol = tolerance > 0 ? tolerance : 0.25;
            Contour? cur = null;
            double cx = 0, cy = 0, sx = 0, sy = 0;
            foreach (var op in ops) {
                double[] p = op.pts;
                switch (op.op) {
                    case 'M':
                        if (p.length < 2) break;
                        finish (o, cur);
                        cur = new Contour ();
                        cx = sx = p[0];
                        cy = sy = p[1];
                        cur.add_point (cx, cy);
                        break;
                    case 'L':
                        if (p.length < 2) break;
                        cur = begin (cur, cx, cy, ref sx, ref sy);
                        push (cur, p[0], p[1]);
                        cx = p[0];
                        cy = p[1];
                        break;
                    case 'C':
                        if (p.length < 6) break;
                        cur = begin (cur, cx, cy, ref sx, ref sy);
                        cubic (cur, cx, cy, p[0], p[1], p[2], p[3], p[4], p[5], tol, 0);
                        cx = p[4];
                        cy = p[5];
                        break;
                    case 'Q':
                        if (p.length < 4) break;
                        cur = begin (cur, cx, cy, ref sx, ref sy);
                        double q1x = cx + 2.0 / 3.0 * (p[0] - cx), q1y = cy + 2.0 / 3.0 * (p[1] - cy);
                        double q2x = p[2] + 2.0 / 3.0 * (p[0] - p[2]), q2y = p[3] + 2.0 / 3.0 * (p[1] - p[3]);
                        cubic (cur, cx, cy, q1x, q1y, q2x, q2y, p[2], p[3], tol, 0);
                        cx = p[2];
                        cy = p[3];
                        break;
                    case 'Z':
                        finish (o, cur);
                        cur = null;
                        cx = sx;
                        cy = sy;
                        break;
                    default:
                        break;
                }
            }
            finish (o, cur);
            return o;
        }

        public static Gee.ArrayList<Outline> merge (Gee.List<Outline> shapes, MergeMode mode) {
            if (shapes.size == 0) return new Gee.ArrayList<Outline> ();
            return new PathOpsArrangement (shapes).merge (mode);
        }

        public static Gee.ArrayList<PathOp> to_ops (Outline o) {
            var ops = new Gee.ArrayList<PathOp> ();
            foreach (var c in o.contours) {
                var s = simplify (c, extent_of (c) * 1e-6);
                if (s.size < 3) continue;
                ops.add (new PathOp ('M', { s.px (0), s.py (0) }));
                for (int i = 1; i < s.size; i++) ops.add (new PathOp ('L', { s.px (i), s.py (i) }));
                ops.add (new PathOp ('Z', new double[0]));
            }
            return ops;
        }

        public static int winding (Contour c, double x, double y) {
            int w = 0;
            int n = c.size;
            for (int i = 0; i < n; i++) {
                int j = (i + 1) % n;
                w += crossing (c.px (i), c.py (i), c.px (j), c.py (j), x, y);
            }
            return w;
        }

        public static bool contains (Outline o, double x, double y) {
            int w = 0;
            foreach (var c in o.contours) w += winding (c, x, y);
            return w != 0;
        }

        internal static int crossing (double ax, double ay, double bx, double by, double x, double y) {
            if (ay <= y) {
                if (by > y && (bx - ax) * (y - ay) - (x - ax) * (by - ay) > 0) return 1;
            } else if (by <= y && (bx - ax) * (y - ay) - (x - ax) * (by - ay) < 0) {
                return -1;
            }
            return 0;
        }

        internal static double extent_of (Contour c) {
            if (c.size == 0) return 1;
            double x0 = c.px (0), x1 = x0, y0 = c.py (0), y1 = y0;
            for (int i = 1; i < c.size; i++) {
                x0 = double.min (x0, c.px (i));
                x1 = double.max (x1, c.px (i));
                y0 = double.min (y0, c.py (i));
                y1 = double.max (y1, c.py (i));
            }
            return double.max (double.max (x1 - x0, y1 - y0), 1);
        }

        internal static Contour simplify (Contour c, double tol) {
            double[] xs = {};
            double[] ys = {};
            for (int i = 0; i < c.size; i++) {
                double x = c.px (i), y = c.py (i);
                while (xs.length >= 2 && collinear (xs[xs.length - 2], ys[ys.length - 2], xs[xs.length - 1], ys[ys.length - 1], x, y, tol)) {
                    xs.resize (xs.length - 1);
                    ys.resize (ys.length - 1);
                }
                xs += x;
                ys += y;
            }
            int first = 0;
            int last = xs.length - 1;
            bool changed = true;
            while (changed && last - first >= 2) {
                changed = false;
                if (collinear (xs[last - 1], ys[last - 1], xs[last], ys[last], xs[first], ys[first], tol)) {
                    last--;
                    changed = true;
                } else if (collinear (xs[last], ys[last], xs[first], ys[first], xs[first + 1], ys[first + 1], tol)) {
                    first++;
                    changed = true;
                }
            }
            var r = new Contour ();
            if (last - first < 2) return r;
            for (int i = first; i <= last; i++) r.add_point (xs[i], ys[i]);
            return r;
        }

        static bool collinear (double ax, double ay, double bx, double by, double cx, double cy, double tol) {
            double dx = cx - ax, dy = cy - ay;
            double l = Math.sqrt (dx * dx + dy * dy);
            if (l <= tol) return true;
            return Math.fabs (dx * (by - ay) - dy * (bx - ax)) / l <= tol;
        }

        static Contour begin (Contour? cur, double cx, double cy, ref double sx, ref double sy) {
            if (cur != null) return cur;
            var c = new Contour ();
            c.add_point (cx, cy);
            sx = cx;
            sy = cy;
            return c;
        }

        static void push (Contour c, double x, double y) {
            int n = c.size;
            if (n > 0 && c.px (n - 1) == x && c.py (n - 1) == y) return;
            c.add_point (x, y);
        }

        static void finish (Outline o, Contour? c) {
            if (c == null) return;
            int n = c.size;
            while (n > 1 && c.px (n - 1) == c.px (0) && c.py (n - 1) == c.py (0)) {
                c.pts.remove_at (c.pts.size - 1);
                c.pts.remove_at (c.pts.size - 1);
                n--;
            }
            if (n >= 3) o.contours.add (c);
        }

        static void cubic (Contour c, double x0, double y0, double x1, double y1, double x2, double y2, double x3, double y3, double tol, int depth) {
            double dx = x3 - x0, dy = y3 - y0;
            double l2 = dx * dx + dy * dy;
            bool flat;
            if (l2 < 1e-18) {
                double e1 = (x1 - x0) * (x1 - x0) + (y1 - y0) * (y1 - y0);
                double e2 = (x2 - x0) * (x2 - x0) + (y2 - y0) * (y2 - y0);
                flat = double.max (e1, e2) <= tol * tol;
            } else {
                double d1 = Math.fabs ((x1 - x3) * dy - (y1 - y3) * dx);
                double d2 = Math.fabs ((x2 - x3) * dy - (y2 - y3) * dx);
                flat = (d1 + d2) * (d1 + d2) <= tol * tol * l2;
            }
            if (flat || depth >= 16) {
                push (c, x3, y3);
                return;
            }
            double ax = (x0 + x1) / 2, ay = (y0 + y1) / 2;
            double bx = (x1 + x2) / 2, by = (y1 + y2) / 2;
            double cx = (x2 + x3) / 2, cy = (y2 + y3) / 2;
            double abx = (ax + bx) / 2, aby = (ay + by) / 2;
            double bcx = (bx + cx) / 2, bcy = (by + cy) / 2;
            double mx = (abx + bcx) / 2, my = (aby + bcy) / 2;
            cubic (c, x0, y0, ax, ay, abx, aby, mx, my, tol, depth + 1);
            cubic (c, mx, my, bcx, bcy, cx, cy, x3, y3, tol, depth + 1);
        }
    }

    internal class PathOpsSplit {
        public double t;
        public double x;
        public double y;

        public PathOpsSplit (double t, double x, double y) {
            this.t = t;
            this.x = x;
            this.y = y;
        }
    }

    internal class PathOpsLoops {
        public Gee.ArrayList<int> from = new Gee.ArrayList<int> ();
        public Gee.ArrayList<int> to = new Gee.ArrayList<int> ();

        public void add (int a, int b) {
            from.add (a);
            to.add (b);
        }
    }

    internal class PathOpsArrangement {
        int shape_count;
        double eps = 1e-9;
        double[] sx0 = {};
        double[] sy0 = {};
        double[] sx1 = {};
        double[] sy1 = {};
        int[] sshape = {};
        double[] vx = {};
        double[] vy = {};
        int[] ea = {};
        int[] eb = {};
        int[] ewind = {};
        Gee.HashMap<string, Gee.ArrayList<int>> cells = new Gee.HashMap<string, Gee.ArrayList<int>> ();
        Gee.HashMap<string, int> edge_index = new Gee.HashMap<string, int> ();

        public PathOpsArrangement (Gee.List<Outline> shapes) {
            shape_count = shapes.size;
            double minx = double.MAX, miny = double.MAX, maxx = -double.MAX, maxy = -double.MAX;
            for (int s = 0; s < shapes.size; s++) {
                foreach (var c in shapes[s].contours) {
                    int n = c.size;
                    if (n < 3) continue;
                    for (int i = 0; i < n; i++) {
                        int j = (i + 1) % n;
                        double x0 = c.px (i), y0 = c.py (i), x1 = c.px (j), y1 = c.py (j);
                        if (x0 == x1 && y0 == y1) continue;
                        sx0 += x0;
                        sy0 += y0;
                        sx1 += x1;
                        sy1 += y1;
                        sshape += s;
                        minx = double.min (minx, double.min (x0, x1));
                        maxx = double.max (maxx, double.max (x0, x1));
                        miny = double.min (miny, double.min (y0, y1));
                        maxy = double.max (maxy, double.max (y0, y1));
                    }
                }
            }
            int ns = sx0.length;
            if (ns == 0) return;
            eps = double.max (double.max (maxx - minx, maxy - miny), 1) * 1e-7;
            var splits = new Gee.ArrayList<Gee.ArrayList<PathOpsSplit>> ();
            for (int i = 0; i < ns; i++) {
                var l = new Gee.ArrayList<PathOpsSplit> ();
                l.add (new PathOpsSplit (0, sx0[i], sy0[i]));
                l.add (new PathOpsSplit (1, sx1[i], sy1[i]));
                splits.add (l);
            }
            for (int i = 0; i < ns; i++) {
                double ix0 = double.min (sx0[i], sx1[i]) - eps, ix1 = double.max (sx0[i], sx1[i]) + eps;
                double iy0 = double.min (sy0[i], sy1[i]) - eps, iy1 = double.max (sy0[i], sy1[i]) + eps;
                for (int j = i + 1; j < ns; j++) {
                    if (double.max (sx0[j], sx1[j]) < ix0 || double.min (sx0[j], sx1[j]) > ix1) continue;
                    if (double.max (sy0[j], sy1[j]) < iy0 || double.min (sy0[j], sy1[j]) > iy1) continue;
                    intersect (i, j, splits);
                }
            }
            for (int i = 0; i < ns; i++) {
                var l = splits[i];
                l.sort ((a, b) => a.t < b.t ? -1 : (a.t > b.t ? 1 : 0));
                int prev = -1;
                foreach (var p in l) {
                    int v = vertex (p.x, p.y);
                    if (prev >= 0 && v != prev) add_edge (prev, v, sshape[i]);
                    prev = v;
                }
            }
        }

        void intersect (int i, int j, Gee.ArrayList<Gee.ArrayList<PathOpsSplit>> splits) {
            double rx = sx1[i] - sx0[i], ry = sy1[i] - sy0[i];
            double qx = sx1[j] - sx0[j], qy = sy1[j] - sy0[j];
            double rl = Math.sqrt (rx * rx + ry * ry), ql = Math.sqrt (qx * qx + qy * qy);
            double den = rx * qy - ry * qx;
            if (Math.fabs (den) > 1e-12 * rl * ql) {
                double wx = sx0[j] - sx0[i], wy = sy0[j] - sy0[i];
                double t = (wx * qy - wy * qx) / den;
                double u = (wx * ry - wy * rx) / den;
                double tt = eps / rl, tu = eps / ql;
                if (t > -tt && t < 1 + tt && u > -tu && u < 1 + tu) {
                    double px = sx0[i] + t * rx, py = sy0[i] + t * ry;
                    splits[i].add (new PathOpsSplit (t.clamp (0, 1), px, py));
                    splits[j].add (new PathOpsSplit (u.clamp (0, 1), px, py));
                }
            }
            on_segment (i, sx0[j], sy0[j], splits);
            on_segment (i, sx1[j], sy1[j], splits);
            on_segment (j, sx0[i], sy0[i], splits);
            on_segment (j, sx1[i], sy1[i], splits);
        }

        void on_segment (int i, double x, double y, Gee.ArrayList<Gee.ArrayList<PathOpsSplit>> splits) {
            double rx = sx1[i] - sx0[i], ry = sy1[i] - sy0[i];
            double l2 = rx * rx + ry * ry;
            if (l2 <= 0) return;
            double t = ((x - sx0[i]) * rx + (y - sy0[i]) * ry) / l2;
            if (t <= 0 || t >= 1) return;
            double d = Math.fabs (rx * (y - sy0[i]) - ry * (x - sx0[i])) / Math.sqrt (l2);
            if (d <= eps) splits[i].add (new PathOpsSplit (t, x, y));
        }

        int vertex (double x, double y) {
            int64 cx = (int64) Math.floor (x / eps);
            int64 cy = (int64) Math.floor (y / eps);
            int best = -1;
            double bd = eps * eps;
            for (int64 dx = -1; dx <= 1; dx++) {
                for (int64 dy = -1; dy <= 1; dy++) {
                    var list = cells[(cx + dx).to_string () + ":" + (cy + dy).to_string ()];
                    if (list == null) continue;
                    foreach (int v in list) {
                        double d = (vx[v] - x) * (vx[v] - x) + (vy[v] - y) * (vy[v] - y);
                        if (d <= bd) {
                            bd = d;
                            best = v;
                        }
                    }
                }
            }
            if (best >= 0) return best;
            int id = vx.length;
            vx += x;
            vy += y;
            string key = cx.to_string () + ":" + cy.to_string ();
            var cell = cells[key];
            if (cell == null) {
                cell = new Gee.ArrayList<int> ();
                cells[key] = cell;
            }
            cell.add (id);
            return id;
        }

        void add_edge (int a, int b, int shape) {
            int lo = int.min (a, b), hi = int.max (a, b);
            string key = lo.to_string () + ":" + hi.to_string ();
            int e;
            if (edge_index.has_key (key)) {
                e = edge_index[key];
            } else {
                e = ea.length;
                ea += lo;
                eb += hi;
                for (int s = 0; s < shape_count; s++) ewind += 0;
                edge_index[key] = e;
            }
            ewind[e * shape_count + shape] += a == lo ? 1 : -1;
        }

        int[] winding_at (double x, double y) {
            var w = new int[shape_count];
            for (int e = 0; e < ea.length; e++) {
                int c = PathOps.crossing (vx[ea[e]], vy[ea[e]], vx[eb[e]], vy[eb[e]], x, y);
                if (c == 0) continue;
                int row = e * shape_count;
                for (int s = 0; s < shape_count; s++) w[s] += c * ewind[row + s];
            }
            return w;
        }

        bool accepts (MergeMode mode, int[] w) {
            int count = 0;
            for (int s = 0; s < shape_count; s++) if (w[s] != 0) count++;
            switch (mode) {
                case MergeMode.UNION: return count > 0;
                case MergeMode.INTERSECT: return count == shape_count;
                case MergeMode.SUBTRACT: return w[0] != 0 && count == 1;
                case MergeMode.COMBINE: return count % 2 == 1;
                default: return false;
            }
        }

        string membership (int[] w) {
            var sb = new StringBuilder ();
            bool any = false;
            for (int s = 0; s < shape_count; s++) {
                sb.append_c (w[s] != 0 ? '1' : '0');
                if (w[s] != 0) any = true;
            }
            return any ? sb.str : "";
        }

        public Gee.ArrayList<Outline> merge (MergeMode mode) {
            var result = new Gee.ArrayList<Outline> ();
            var main = new PathOpsLoops ();
            var sets = new Gee.HashMap<string, PathOpsLoops> ();
            var order = new Gee.ArrayList<string> ();
            double off = eps * 0.1;
            for (int e = 0; e < ea.length; e++) {
                int a = ea[e], b = eb[e];
                double dx = vx[b] - vx[a], dy = vy[b] - vy[a];
                double l = Math.sqrt (dx * dx + dy * dy);
                if (l <= 0) continue;
                double mx = (vx[a] + vx[b]) / 2, my = (vy[a] + vy[b]) / 2;
                var wl = winding_at (mx - dy / l * off, my + dx / l * off);
                var wr = new int[shape_count];
                for (int s = 0; s < shape_count; s++) wr[s] = wl[s] - ewind[e * shape_count + s];
                if (mode == MergeMode.FRAGMENT) {
                    string kl = membership (wl), kr = membership (wr);
                    if (kl == kr) continue;
                    if (kl != "") loops_for (kl, sets, order).add (a, b);
                    if (kr != "") loops_for (kr, sets, order).add (b, a);
                } else {
                    bool pl = accepts (mode, wl), pr = accepts (mode, wr);
                    if (pl == pr) continue;
                    if (pl) main.add (a, b);
                    else main.add (b, a);
                }
            }
            if (mode == MergeMode.FRAGMENT) {
                foreach (var key in order) regions (chain (sets[key]), result);
            } else {
                var o = new Outline ();
                o.contours.add_all (chain (main));
                if (!o.is_empty ()) result.add (o);
            }
            return result;
        }

        PathOpsLoops loops_for (string key, Gee.HashMap<string, PathOpsLoops> sets, Gee.ArrayList<string> order) {
            var l = sets[key];
            if (l == null) {
                l = new PathOpsLoops ();
                sets[key] = l;
                order.add (key);
            }
            return l;
        }

        Gee.ArrayList<Contour> chain (PathOpsLoops loops) {
            var res = new Gee.ArrayList<Contour> ();
            int m = loops.from.size;
            var outs = new Gee.HashMap<int, Gee.ArrayList<int>> ();
            for (int i = 0; i < m; i++) {
                var l = outs[loops.from[i]];
                if (l == null) {
                    l = new Gee.ArrayList<int> ();
                    outs[loops.from[i]] = l;
                }
                l.add (i);
            }
            var used = new bool[m];
            for (int s = 0; s < m; s++) {
                if (used[s]) continue;
                var c = new Contour ();
                int e = s;
                int guard = 0;
                while (guard++ <= m) {
                    used[e] = true;
                    c.add_point (vx[loops.from[e]], vy[loops.from[e]]);
                    var cands = outs[loops.to[e]];
                    int next = pick (e, cands, used, loops, false);
                    if (next == s) break;
                    if (next < 0 || used[next]) next = pick (e, cands, used, loops, true);
                    if (next < 0) break;
                    e = next;
                }
                var sc = PathOps.simplify (c, eps);
                if (sc.size >= 3 && Math.fabs (sc.area ()) > eps * eps) res.add (sc);
            }
            return res;
        }

        int pick (int e, Gee.ArrayList<int>? cands, bool[] used, PathOpsLoops loops, bool unused_only) {
            if (cands == null) return -1;
            int u = loops.from[e], v = loops.to[e];
            double back = Math.atan2 (vy[u] - vy[v], vx[u] - vx[v]);
            int best = -1;
            double bt = 0;
            foreach (int c in cands) {
                if (unused_only && used[c]) continue;
                int w = loops.to[c];
                double cw = back - Math.atan2 (vy[w] - vy[v], vx[w] - vx[v]);
                while (cw <= 1e-12) cw += 2 * Math.PI;
                while (cw > 2 * Math.PI + 1e-12) cw -= 2 * Math.PI;
                if (best < 0 || cw < bt) {
                    best = c;
                    bt = cw;
                }
            }
            return best;
        }

        void regions (Gee.ArrayList<Contour> cs, Gee.ArrayList<Outline> result) {
            var outers = new Gee.ArrayList<Contour> ();
            var holes = new Gee.ArrayList<Contour> ();
            foreach (var c in cs) {
                if (c.area () > 0) outers.add (c);
                else holes.add (c);
            }
            var outs = new Gee.ArrayList<Outline> ();
            foreach (var c in outers) {
                var o = new Outline ();
                o.contours.add (c);
                outs.add (o);
            }
            foreach (var h in holes) {
                int n = h.size;
                int bi = 0;
                double bl = -1;
                for (int i = 0; i < n; i++) {
                    int j = (i + 1) % n;
                    double dx = h.px (j) - h.px (i), dy = h.py (j) - h.py (i);
                    double l = dx * dx + dy * dy;
                    if (l > bl) {
                        bl = l;
                        bi = i;
                    }
                }
                int bj = (bi + 1) % n;
                double dx = h.px (bj) - h.px (bi), dy = h.py (bj) - h.py (bi);
                double l = Math.sqrt (bl);
                double x = (h.px (bi) + h.px (bj)) / 2 - dy / l * eps * 0.1;
                double y = (h.py (bi) + h.py (bj)) / 2 + dx / l * eps * 0.1;
                int best = -1;
                double ba = 0;
                for (int k = 0; k < outers.size; k++) {
                    if (PathOps.winding (outers[k], x, y) == 0) continue;
                    double a = outers[k].area ();
                    if (best < 0 || a < ba) {
                        best = k;
                        ba = a;
                    }
                }
                if (best < 0 && outs.size > 0) best = 0;
                if (best >= 0) outs[best].contours.add (h);
            }
            result.add_all (outs);
        }
    }
}
