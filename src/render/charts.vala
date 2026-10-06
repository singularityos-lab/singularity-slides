namespace Singularity.Apps.Slides {

    public class ChartPainter {

        public static string series_color (ChartElement ch, int i) {
            if (i < ch.series.size && ch.series[i].color != "") return ch.series[i].color;
            return palette (i);
        }

        public static string palette (int i) {
            string baseline = "accent%d".printf (i % 6 + 1);
            int round = i / 6;
            if (round == 0) return baseline;
            return ColorSpec.tint (baseline, round % 2 == 1 ? 0.6 : 0.8, round % 2 == 1 ? 0 : 0.2);
        }

        private static Pango.Layout label (string text, double size, bool bold = false) {
            var l = new Pango.Layout (Renderer.context ());
            var fd = new Pango.FontDescription ();
            fd.set_family ("Inter");
            fd.set_size ((int) (size * Pango.SCALE));
            if (bold) fd.set_weight (Pango.Weight.BOLD);
            l.set_font_description (fd);
            l.set_text (text, -1);
            return l;
        }

        private static void text_size (Pango.Layout l, out double w, out double h) {
            int iw, ih;
            l.get_size (out iw, out ih);
            w = iw / (double) Pango.SCALE;
            h = ih / (double) Pango.SCALE;
        }

        private static void show (Cairo.Context cr, Pango.Layout l, double x, double y) {
            cr.move_to (x, y);
            Pango.cairo_show_layout (cr, l);
        }

        public static void nice_scale (double min, double max, out double lo, out double hi, out double step) {
            if (min == max) {
                max = min + 1;
                if (min > 0) min = 0;
            }
            double range = max - min;
            double rough = range / 5;
            double mag = Math.pow (10, Math.floor (Math.log10 (rough)));
            double norm = rough / mag;
            double s;
            if (norm < 1.5) s = 1;
            else if (norm < 3) s = 2;
            else if (norm < 7) s = 5;
            else s = 10;
            step = s * mag;
            lo = Math.floor (min / step) * step;
            hi = Math.ceil (max / step) * step;
            if (hi == lo) hi = lo + step;
        }

        public static string format_value (double v) {
            if (Math.fabs (v) >= 1000000) return "%gM".printf (Math.round (v / 100000) / 10);
            if (Math.fabs (v) >= 10000) return "%gK".printf (Math.round (v / 100) / 10);
            if (v == Math.floor (v)) return "%.0f".printf (v);
            return "%g".printf (Math.round (v * 100) / 100);
        }

        public static void draw (Cairo.Context cr, RenderContext ctx, ChartElement ch, double x, double y, double w, double h) {
            if (ch.chart.uses_engine ()) {
                ChartBridge.draw (cr, ctx, ch, x, y, w, h);
                return;
            }
            Rgba fg = ch.text_color != "" ? ctx.theme.resolve (ch.text_color) : (ctx.dark ? ctx.theme.resolve ("lt1") : ctx.theme.resolve ("dk1"));
            double base_size = (h * 0.05).clamp (8, 24);
            double pad = base_size * 0.6;
            cr.save ();
            double top = y + pad, bottom = y + h - pad, left = x + pad, right = x + w - pad;
            if (ch.title != "") {
                var tl = label (ch.title, base_size * 1.35, true);
                tl.set_width ((int) ((w - 2 * pad) * Pango.SCALE));
                tl.set_alignment (Pango.Alignment.CENTER);
                double tw, th;
                text_size (tl, out tw, out th);
                Renderer.set_source (cr, fg);
                show (cr, tl, x + pad, top);
                top += th + pad;
            }
            bool radial = ch.chart.is_radial ();
            int entries = radial ? ch.categories.size : ch.series.size;
            if (ch.legend != LegendPosition.NONE && entries > 0) {
                double sw = base_size * 0.8;
                var names = new Gee.ArrayList<string> ();
                for (int i = 0; i < entries; i++) names.add (radial ? ch.categories[i] : ch.series[i].name);
                if (ch.legend == LegendPosition.BOTTOM || ch.legend == LegendPosition.TOP) {
                    double total = 0;
                    var widths = new double[entries];
                    double lh = 0;
                    for (int i = 0; i < entries; i++) {
                        var l = label (names[i], base_size);
                        double tw, th;
                        text_size (l, out tw, out th);
                        widths[i] = sw + base_size * 0.4 + tw + base_size * 1.2;
                        total += widths[i];
                        lh = double.max (lh, th);
                    }
                    double lx = x + (w - total) / 2;
                    double ly = ch.legend == LegendPosition.BOTTOM ? bottom - lh : top;
                    for (int i = 0; i < entries; i++) {
                        Renderer.set_source (cr, ctx.theme.resolve (radial ? palette (i) : series_color (ch, i)));
                        Geometry.round_rect (cr, lx, ly + (lh - sw) / 2, sw, sw, sw * 0.2);
                        cr.fill ();
                        Renderer.set_source (cr, fg, 0.85);
                        show (cr, label (names[i], base_size), lx + sw + base_size * 0.4, ly);
                        lx += widths[i];
                    }
                    if (ch.legend == LegendPosition.BOTTOM) bottom -= lh + pad;
                    else top += lh + pad;
                } else {
                    double maxw = 0, lh = 0;
                    for (int i = 0; i < entries; i++) {
                        double tw, th;
                        text_size (label (names[i], base_size), out tw, out th);
                        maxw = double.max (maxw, tw);
                        lh = double.max (lh, th);
                    }
                    double colw = sw + base_size * 0.4 + maxw;
                    double lx = ch.legend == LegendPosition.RIGHT ? right - colw : left;
                    double ly = top + (bottom - top - entries * lh * 1.3) / 2;
                    for (int i = 0; i < entries; i++) {
                        Renderer.set_source (cr, ctx.theme.resolve (radial ? palette (i) : series_color (ch, i)));
                        Geometry.round_rect (cr, lx, ly + (lh - sw) / 2, sw, sw, sw * 0.2);
                        cr.fill ();
                        Renderer.set_source (cr, fg, 0.85);
                        show (cr, label (names[i], base_size), lx + sw + base_size * 0.4, ly);
                        ly += lh * 1.3;
                    }
                    if (ch.legend == LegendPosition.RIGHT) right -= colw + pad * 2;
                    else left += colw + pad * 2;
                }
            }
            if (right - left < 10 || bottom - top < 10) {
                cr.restore ();
                return;
            }
            if (radial) draw_pie (cr, ctx, ch, left, top, right - left, bottom - top, fg, base_size);
            else draw_axes (cr, ctx, ch, left, top, right - left, bottom - top, fg, base_size);
            cr.restore ();
        }

        private static void draw_pie (Cairo.Context cr, RenderContext ctx, ChartElement ch, double x, double y, double w, double h, Rgba fg, double fs) {
            if (ch.series.size == 0) return;
            var s = ch.series[0];
            double total = 0;
            int n = int.max (ch.categories.size, s.values.size);
            for (int i = 0; i < n; i++) total += Math.fabs (s.value_at (i));
            if (total <= 0) return;
            double r = double.min (w, h) / 2;
            double cx = x + w / 2, cy = y + h / 2;
            double inner = ch.chart == ChartKind.DOUGHNUT ? r * 0.55 : 0;
            double a = -Math.PI / 2;
            var bg = ctx.dark ? ctx.theme.resolve ("dk1") : ctx.theme.resolve ("lt1");
            for (int i = 0; i < n; i++) {
                double v = Math.fabs (s.value_at (i));
                double sweep = v / total * 2 * Math.PI;
                cr.new_path ();
                if (inner > 0) {
                    cr.arc (cx, cy, r, a, a + sweep);
                    cr.arc_negative (cx, cy, inner, a + sweep, a);
                } else {
                    cr.move_to (cx, cy);
                    cr.arc (cx, cy, r, a, a + sweep);
                }
                cr.close_path ();
                Renderer.set_source (cr, ctx.theme.resolve (palette (i)));
                cr.fill_preserve ();
                Renderer.set_source (cr, bg);
                cr.set_line_width (double.max (r * 0.012, 0.5));
                cr.stroke ();
                if (ch.data_labels && v > 0) {
                    double mid = a + sweep / 2;
                    double lr = inner > 0 ? (r + inner) / 2 : r * 0.65;
                    var l = label ("%.0f%%".printf (v / total * 100), fs, true);
                    double tw, th;
                    text_size (l, out tw, out th);
                    var sc = ctx.theme.resolve (palette (i));
                    Renderer.set_source (cr, ctx.theme.resolve (sc.luminance () < 0.55 ? "lt1" : "dk1"));
                    show (cr, l, cx + Math.cos (mid) * lr - tw / 2, cy + Math.sin (mid) * lr - th / 2);
                }
                a += sweep;
            }
        }

        private delegate double ToPx (double v);

        private class Scale {
            public double lo;
            public double hi;
            public double step;
            public bool log;
            public double log_base;
            public bool reverse;
            public ChartAxis axis;
            public bool percent;

            public double t (double v) {
                double r;
                if (log) {
                    double a = Math.log (double.max (lo, 1e-12)), b = Math.log (double.max (hi, 1e-12));
                    r = b > a ? (Math.log (double.max (v, 1e-12)) - a) / (b - a) : 0;
                } else {
                    r = hi > lo ? (v - lo) / (hi - lo) : 0;
                }
                return reverse ? 1 - r : r;
            }

            public Gee.ArrayList<double?> ticks () {
                var list = new Gee.ArrayList<double?> ();
                if (log) {
                    for (double v = lo; v <= hi * 1.0001; v *= log_base) list.add (v);
                    return list;
                }
                int n = 0;
                for (double v = lo; v <= hi + step / 2 && n < 200; v += step, n++) list.add (Math.fabs (v) < step * 1e-9 ? 0 : v);
                return list;
            }

            public string label (double v) {
                string f = axis.format_value (v);
                if (f != "") return f;
                return format_value (v) + (percent ? "%" : "");
            }
        }

        private static Scale make_scale (ChartAxis axis, double vmin, double vmax, bool percent) {
            var sc = new Scale ();
            sc.axis = axis;
            sc.percent = percent;
            sc.reverse = axis.reverse;
            if (axis.log_base > 1) {
                sc.log = true;
                sc.log_base = axis.log_base;
                double lo = Math.pow (axis.log_base, Math.floor (Math.log (double.max (vmin > 0 ? vmin : 1, 1e-12)) / Math.log (axis.log_base)));
                double hi = Math.pow (axis.log_base, Math.ceil (Math.log (double.max (vmax, lo * axis.log_base)) / Math.log (axis.log_base)));
                sc.lo = !axis.min.is_nan () && axis.min > 0 ? axis.min : lo;
                sc.hi = !axis.max.is_nan () && axis.max > sc.lo ? axis.max : double.max (hi, sc.lo * axis.log_base);
                sc.step = 0;
                return sc;
            }
            double lo, hi, step;
            nice_scale (!axis.min.is_nan () ? axis.min : vmin, !axis.max.is_nan () ? axis.max : vmax, out lo, out hi, out step);
            if (percent) {
                lo = double.min (lo, 0);
                hi = double.min (hi, 100);
                step = 20;
            }
            if (!axis.min.is_nan ()) lo = axis.min;
            if (!axis.max.is_nan ()) hi = axis.max;
            if (axis.major > 0) step = axis.major;
            if (hi <= lo) hi = lo + (step > 0 ? step : 1);
            if (step <= 0 || (hi - lo) / step > 100) step = (hi - lo) / 5;
            sc.lo = lo;
            sc.hi = hi;
            sc.step = step;
            return sc;
        }

        private static void range_of (ChartElement ch, Gee.List<ChartSeries> list, int ncat, bool stacked, bool percent, out double vmin, out double vmax) {
            vmin = 0;
            vmax = 0;
            bool any = false;
            for (int c = 0; c < ncat; c++) {
                var pos = new double[4];
                var neg = new double[4];
                double tot = 0;
                foreach (var s in list) tot += Math.fabs (s.value_at (c));
                foreach (var s in list) {
                    if (c >= s.values.size || s.values[c] == null) continue;
                    double v = s.value_at (c);
                    if (percent) v = tot > 0 ? v / tot * 100 : 0;
                    int k = (int) ch.series_kind (s);
                    if (stacked) {
                        if (v >= 0) pos[k] += v;
                        else neg[k] += v;
                        vmax = double.max (vmax, pos[k]);
                        vmin = double.min (vmin, neg[k]);
                    } else {
                        if (!any) {
                            vmin = double.min (0, v);
                            vmax = double.max (0, v);
                            any = true;
                        }
                        vmin = double.min (vmin, v);
                        vmax = double.max (vmax, v);
                    }
                }
            }
        }

        private static void axis_title (Cairo.Context cr, string text, double x, double y, double fs, Rgba fg, double angle) {
            var l = label (text, fs, true);
            double tw, th;
            text_size (l, out tw, out th);
            cr.save ();
            cr.translate (x, y);
            cr.rotate (angle);
            Renderer.set_source (cr, fg, 0.8);
            show (cr, l, -tw / 2, -th / 2);
            cr.restore ();
        }

        private static void draw_axes (Cairo.Context cr, RenderContext ctx, ChartElement ch, double x, double y, double w, double h, Rgba fg, double fs) {
            int ncat = ch.categories.size;
            foreach (var s in ch.series) ncat = int.max (ncat, s.values.size);
            if (ncat == 0 || ch.series.size == 0) return;
            if (ch.chart == ChartKind.RADAR) {
                draw_radar (cr, ctx, ch, x, y, w, h, fg, fs, ncat);
                return;
            }
            bool xy = ch.chart == ChartKind.SCATTER || ch.chart == ChartKind.BUBBLE;
            bool stacked = ch.grouping != ChartGrouping.CLUSTERED && !xy;
            bool percent = ch.grouping == ChartGrouping.PERCENT && !xy;
            bool secondary = ch.has_secondary ();
            var prim = new Gee.ArrayList<ChartSeries> ();
            var sec = new Gee.ArrayList<ChartSeries> ();
            foreach (var s in ch.series) {
                if (secondary && s.secondary) sec.add (s);
                else prim.add (s);
            }
            double vmin, vmax;
            range_of (ch, prim, ncat, stacked, percent, out vmin, out vmax);
            var ps = make_scale (ch.val_axis, vmin, vmax, percent);
            Scale? ss = null;
            if (sec.size > 0) {
                range_of (ch, sec, ncat, stacked, percent, out vmin, out vmax);
                ss = make_scale (ch.sec_axis, vmin, vmax, percent);
            }
            bool horizontal = ch.chart == ChartKind.BAR;
            double label_w = 0;
            foreach (var v in ps.ticks ()) {
                double tw, th;
                text_size (label (ps.label (v), fs * 0.9), out tw, out th);
                label_w = double.max (label_w, tw);
            }
            double sec_w = 0;
            if (ss != null) {
                foreach (var v in ss.ticks ()) {
                    double tw, th;
                    text_size (label (ss.label (v), fs * 0.9), out tw, out th);
                    sec_w = double.max (sec_w, tw);
                }
            }
            double cat_h = fs * 1.6;
            double cat_w = 0;
            if (horizontal) {
                foreach (string c in ch.categories) {
                    double tw, th;
                    text_size (label (c, fs * 0.9), out tw, out th);
                    cat_w = double.max (cat_w, tw);
                }
            }
            double title_band = fs * 1.6;
            double left_pad = (horizontal ? cat_w : label_w) + fs * 0.6;
            double bottom_pad = cat_h;
            if (horizontal ? ch.cat_axis.title != "" : ch.val_axis.title != "") left_pad += title_band;
            if (horizontal ? ch.val_axis.title != "" : ch.cat_axis.title != "") bottom_pad += title_band;
            double right_pad = ss != null ? sec_w + fs * 0.8 + (ch.sec_axis.title != "" ? title_band : 0) : fs * 0.4;
            double px = x + left_pad;
            double py = y + fs * 0.4;
            double pw = x + w - px - right_pad;
            double ph = y + h - py - bottom_pad;
            if (pw < 10 || ph < 10) return;
            string lt = horizontal ? ch.cat_axis.title : ch.val_axis.title;
            string bt = horizontal ? ch.val_axis.title : ch.cat_axis.title;
            if (lt != "") axis_title (cr, lt, x + fs * 0.7, py + ph / 2, fs, fg, -Math.PI / 2);
            if (bt != "") axis_title (cr, bt, px + pw / 2, y + h - fs * 0.7, fs, fg, 0);
            if (ss != null && ch.sec_axis.title != "") axis_title (cr, ch.sec_axis.title, x + w - fs * 0.7, py + ph / 2, fs, fg, Math.PI / 2);
            cr.set_line_width (double.max (fs * 0.05, 0.5));
            if (ch.val_axis.visible) {
                foreach (var v in ps.ticks ()) {
                    double t = ps.t (v);
                    var l = label (ps.label (v), fs * 0.9);
                    double tw, th;
                    text_size (l, out tw, out th);
                    if (horizontal) {
                        double gx = px + t * pw;
                        if (ch.gridlines) {
                            Renderer.set_source (cr, fg, 0.14);
                            cr.move_to (gx, py);
                            cr.line_to (gx, py + ph);
                            cr.stroke ();
                        }
                        Renderer.set_source (cr, fg, 0.7);
                        show (cr, l, gx - tw / 2, py + ph + fs * 0.3);
                    } else {
                        double gy = py + ph - t * ph;
                        if (ch.gridlines) {
                            Renderer.set_source (cr, fg, 0.14);
                            cr.move_to (px, gy);
                            cr.line_to (px + pw, gy);
                            cr.stroke ();
                        }
                        Renderer.set_source (cr, fg, 0.7);
                        show (cr, l, px - tw - fs * 0.4, gy - th / 2);
                    }
                }
            }
            if (ss != null && ch.sec_axis.visible) {
                foreach (var v in ss.ticks ()) {
                    double gy = py + ph - ss.t (v) * ph;
                    var l = label (ss.label (v), fs * 0.9);
                    double tw, th;
                    text_size (l, out tw, out th);
                    Renderer.set_source (cr, fg, 0.7);
                    show (cr, l, px + pw + fs * 0.4, gy - th / 2);
                }
            }
            double zero_t = ps.log ? 0 : ps.t (double.max (ps.lo, double.min (0, ps.hi)));
            Renderer.set_source (cr, fg, 0.45);
            if (horizontal) {
                cr.move_to (px + zero_t * pw, py);
                cr.line_to (px + zero_t * pw, py + ph);
            } else {
                cr.move_to (px, py + ph - zero_t * ph);
                cr.line_to (px + pw, py + ph - zero_t * ph);
            }
            cr.stroke ();
            bool any_bars = false;
            if (!xy) foreach (var s in ch.series) if (ch.series_kind (s) == SeriesKind.COLUMN) any_bars = true;
            bool centered = any_bars;
            double band = (horizontal ? ph : pw) / ncat;
            double[] xnum = new double[ncat];
            double xmin = 0, xmax = 0;
            bool xnumeric = xy && numeric_x (ch, ncat, xnum, out xmin, out xmax);
            if (xy && xnumeric) {
                double lo2, hi2, st2;
                nice_scale (!ch.cat_axis.min.is_nan () ? ch.cat_axis.min : xmin, !ch.cat_axis.max.is_nan () ? ch.cat_axis.max : xmax, out lo2, out hi2, out st2);
                if (!ch.cat_axis.min.is_nan ()) lo2 = ch.cat_axis.min;
                if (!ch.cat_axis.max.is_nan ()) hi2 = ch.cat_axis.max;
                if (ch.cat_axis.major > 0) st2 = ch.cat_axis.major;
                if (hi2 <= lo2) hi2 = lo2 + 1;
                xmin = lo2;
                xmax = hi2;
                for (double v = lo2; v <= hi2 + st2 / 2 && st2 > 0; v += st2) {
                    string txt = ch.cat_axis.format_value (v);
                    var l = label (txt != "" ? txt : format_value (v), fs * 0.9);
                    double tw, th;
                    text_size (l, out tw, out th);
                    double gx = px + (v - xmin) / (xmax - xmin) * pw;
                    Renderer.set_source (cr, fg, 0.75);
                    show (cr, l, gx - tw / 2, py + ph + fs * 0.3);
                }
            } else if (ch.cat_axis.visible) {
                for (int c = 0; c < ncat && c < ch.categories.size; c++) {
                    var l = label (ch.categories[c], fs * 0.9);
                    double tw, th;
                    text_size (l, out tw, out th);
                    Renderer.set_source (cr, fg, 0.75);
                    int cc = ch.cat_axis.reverse ? ncat - 1 - c : c;
                    if (horizontal) show (cr, l, px - tw - fs * 0.4, py + band * cc + band / 2 - th / 2);
                    else if (!centered) {
                        double cxp = ncat > 1 ? px + pw * cc / (ncat - 1) : px + pw / 2;
                        show (cr, l, cxp - tw / 2, py + ph + fs * 0.3);
                    } else show (cr, l, px + band * cc + band / 2 - tw / 2, py + ph + fs * 0.3);
                }
            }
            var bar_series = new Gee.ArrayList<int> ();
            for (int i = 0; i < ch.series.size; i++) if (!xy && (horizontal || ch.series_kind (ch.series[i]) == SeriesKind.COLUMN)) bar_series.add (i);
            if (bar_series.size > 0) {
                int nb = bar_series.size;
                double gap = band * 0.25;
                double group = band - gap;
                double bw = stacked ? group : group / nb;
                for (int c = 0; c < ncat; c++) {
                    double pos = 0, neg = 0, tot = 0, spos = 0, sneg = 0;
                    foreach (int i in bar_series) tot += Math.fabs (ch.series[i].value_at (c));
                    int cc = ch.cat_axis.reverse ? ncat - 1 - c : c;
                    for (int k = 0; k < nb; k++) {
                        int i = bar_series[k];
                        var se = ch.series[i];
                        var sc = secondary && se.secondary && ss != null ? ss : ps;
                        double v = se.value_at (c);
                        if (percent) v = tot > 0 ? v / tot * 100 : 0;
                        double v0 = 0, v1 = v;
                        if (stacked) {
                            bool on_sec = sc == ss;
                            double pb = on_sec ? spos : pos, nbv = on_sec ? sneg : neg;
                            if (v >= 0) {
                                v0 = pb;
                                v1 = pb + v;
                                if (on_sec) spos = v1;
                                else pos = v1;
                            } else {
                                v0 = nbv;
                                v1 = nbv + v;
                                if (on_sec) sneg = v1;
                                else neg = v1;
                            }
                        }
                        if (sc.log) v0 = sc.lo;
                        double t0 = sc.t (v0).clamp (0, 1), t1 = sc.t (v1).clamp (0, 1);
                        double off = band * cc + gap / 2 + (stacked ? 0 : bw * k);
                        Renderer.set_source (cr, ctx.theme.resolve (series_color (ch, i)));
                        double rx, ry, rw, rh;
                        if (horizontal) {
                            rx = px + double.min (t0, t1) * pw;
                            rw = Math.fabs (t1 - t0) * pw;
                            ry = py + off;
                            rh = bw * 0.92;
                        } else {
                            rx = px + off;
                            rw = bw * 0.92;
                            ry = py + ph - double.max (t0, t1) * ph;
                            rh = Math.fabs (t1 - t0) * ph;
                        }
                        cr.rectangle (rx, ry, rw, rh);
                        cr.fill ();
                        if (ch.data_labels && v != 0) {
                            var l = label (sc.axis.format_value (v) != "" ? sc.axis.format_value (v) : format_value (v), fs * 0.8);
                            double tw, th;
                            text_size (l, out tw, out th);
                            Renderer.set_source (cr, fg, 0.9);
                            if (horizontal) show (cr, l, rx + rw + fs * 0.2, ry + rh / 2 - th / 2);
                            else show (cr, l, rx + rw / 2 - tw / 2, ry - th);
                        }
                    }
                }
            }
            var base_prim = new double[ncat];
            var base_sec = new double[ncat];
            for (int i = 0; i < ch.series.size; i++) {
                if (bar_series.contains (i)) continue;
                var s = ch.series[i];
                var kind = xy ? SeriesKind.LINE : ch.series_kind (s);
                var sc = secondary && s.secondary && ss != null ? ss : ps;
                var basev = sc == ss ? base_sec : base_prim;
                var col = ctx.theme.resolve (series_color (ch, i));
                double[] xs = new double[ncat];
                double[] ys = new double[ncat];
                double[] bs = new double[ncat];
                for (int c = 0; c < ncat; c++) {
                    double v = s.value_at (c);
                    if (percent) {
                        double tot = 0;
                        foreach (var o in ch.series) if (!bar_series.contains (ch.series.index_of (o))) tot += Math.fabs (o.value_at (c));
                        v = tot > 0 ? v / tot * 100 : 0;
                    }
                    bs[c] = basev[c];
                    if (stacked) {
                        v += basev[c];
                        basev[c] = v;
                    }
                    int cc = ch.cat_axis.reverse ? ncat - 1 - c : c;
                    if (xy && xnumeric) xs[c] = px + (xnum[c] - xmin) / (xmax - xmin) * pw;
                    else if (centered) xs[c] = px + band * cc + band / 2;
                    else xs[c] = ncat > 1 ? px + pw * cc / (ncat - 1) : px + pw / 2;
                    ys[c] = py + ph - sc.t (v) * ph;
                }
                if (kind == SeriesKind.AREA) {
                    cr.new_path ();
                    cr.move_to (xs[0], ys[0]);
                    for (int c = 1; c < ncat; c++) cr.line_to (xs[c], ys[c]);
                    for (int c = ncat - 1; c >= 0; c--) cr.line_to (xs[c], py + ph - sc.t (stacked ? bs[c] : double.max (sc.lo, 0)) * ph);
                    cr.close_path ();
                    Renderer.set_source (cr, col, 0.75);
                    cr.fill ();
                } else {
                    if (ch.chart != ChartKind.BUBBLE) {
                        cr.new_path ();
                        cr.move_to (xs[0], ys[0]);
                        for (int c = 1; c < ncat; c++) {
                            if (ch.smooth) {
                                double mx = (xs[c - 1] + xs[c]) / 2;
                                cr.curve_to (mx, ys[c - 1], mx, ys[c], xs[c], ys[c]);
                            } else {
                                cr.line_to (xs[c], ys[c]);
                            }
                        }
                        Renderer.set_source (cr, col);
                        cr.set_line_width (double.max (fs * 0.18, 1));
                        cr.set_line_join (Cairo.LineJoin.ROUND);
                        cr.stroke ();
                    }
                    double smax = 0;
                    if (ch.chart == ChartKind.BUBBLE) foreach (var o in ch.series) foreach (var z in o.sizes) if (z != null) smax = double.max (smax, Math.fabs (z));
                    for (int c = 0; c < ncat; c++) {
                        cr.new_path ();
                        double rad = double.max (fs * 0.28, 1.5);
                        if (ch.chart == ChartKind.BUBBLE) {
                            double z = c < s.sizes.size && s.sizes[c] != null ? Math.fabs (s.sizes[c]) : 1;
                            rad = smax > 0 ? Math.sqrt (z / smax) * double.min (pw, ph) * 0.12 : rad;
                        }
                        cr.arc (xs[c], ys[c], rad, 0, 2 * Math.PI);
                        Renderer.set_source (cr, col, ch.chart == ChartKind.BUBBLE ? 0.7 : 1);
                        cr.fill ();
                        if (ch.data_labels) {
                            var l = label (format_value (s.value_at (c)), fs * 0.8);
                            double tw, th;
                            text_size (l, out tw, out th);
                            Renderer.set_source (cr, fg, 0.9);
                            show (cr, l, xs[c] - tw / 2, ys[c] - th - fs * 0.3);
                        }
                    }
                }
            }
            for (int i = 0; i < ch.series.size; i++) {
                var s = ch.series[i];
                if (s.trend == TrendKind.NONE || horizontal) continue;
                var sc = secondary && s.secondary && ss != null ? ss : ps;
                double[] tx = new double[ncat];
                double[] ty = new double[ncat];
                for (int c = 0; c < ncat; c++) {
                    tx[c] = xy && xnumeric ? xnum[c] : c + 1;
                    ty[c] = c < s.values.size && s.values[c] != null ? s.values[c] : double.NAN;
                }
                double lo_x = xy && xnumeric ? xmin : 1, hi_x = xy && xnumeric ? xmax : ncat;
                ToPx to_px = (vx) => {
                    if (xy && xnumeric) return px + (vx - xmin) / (xmax - xmin) * pw;
                    double cc = vx - 1;
                    if (ch.cat_axis.reverse) cc = ncat - 1 - cc;
                    if (centered) return px + band * cc + band / 2;
                    return ncat > 1 ? px + pw * cc / (ncat - 1) : px + pw / 2;
                };
                var col = ctx.theme.resolve (series_color (ch, i));
                cr.save ();
                cr.rectangle (px, py, pw, ph);
                cr.clip ();
                cr.new_path ();
                Renderer.set_source (cr, col);
                cr.set_line_width (double.max (fs * 0.12, 1));
                double[] dash = { fs * 0.5, fs * 0.3 };
                cr.set_dash (dash, 0);
                var fit = TrendFit.fit (tx, ty, s.trend, s.trend_order, s.trend_period);
                if (s.trend == TrendKind.MOVING_AVERAGE) {
                    var ma = TrendFit.moving_average (ty, int.max (s.trend_period, 2));
                    bool started = false;
                    for (int c = 0; c < ncat; c++) {
                        if (ma[c].is_nan ()) continue;
                        double sx = to_px (tx[c]), sy = py + ph - sc.t (ma[c]) * ph;
                        if (!started) cr.move_to (sx, sy);
                        else cr.line_to (sx, sy);
                        started = true;
                    }
                } else if (fit.ok) {
                    bool started = false;
                    for (int k = 0; k <= 80; k++) {
                        double vx = lo_x + (hi_x - lo_x) * k / 80.0;
                        double vy = fit.eval (vx);
                        if (vy.is_nan () || vy.is_infinity () != 0) continue;
                        double sx = to_px (vx), sy = py + ph - sc.t (vy) * ph;
                        if (!started) cr.move_to (sx, sy);
                        else cr.line_to (sx, sy);
                        started = true;
                    }
                }
                cr.stroke ();
                cr.restore ();
                if (fit.ok && (s.trend_equation || s.trend_r2) && s.trend != TrendKind.MOVING_AVERAGE) {
                    var sb = new StringBuilder ();
                    if (s.trend_equation) sb.append (fit.equation ());
                    if (s.trend_r2) {
                        if (sb.len > 0) sb.append ("\n");
                        sb.append ("R² = %.4f".printf (fit.r2));
                    }
                    var l = label (sb.str, fs * 0.8);
                    double tw, th;
                    text_size (l, out tw, out th);
                    double lx = px + pw - tw - fs * 0.3, ly = py + fs * 0.3 + i * th * 1.1;
                    Renderer.set_source (cr, ctx.dark ? ctx.theme.resolve ("dk1") : ctx.theme.resolve ("lt1"), 0.85);
                    Geometry.round_rect (cr, lx - fs * 0.2, ly - fs * 0.1, tw + fs * 0.4, th + fs * 0.2, fs * 0.2);
                    cr.fill ();
                    Renderer.set_source (cr, col);
                    show (cr, l, lx, ly);
                }
            }
        }

        private static bool numeric_x (ChartElement ch, int ncat, double[] vals, out double mn, out double mx) {
            mn = double.MAX;
            mx = -double.MAX;
            for (int c = 0; c < ncat; c++) {
                double v = 0;
                if (c >= ch.categories.size || !double.try_parse (ch.categories[c], out v)) return false;
                vals[c] = v;
                mn = double.min (mn, v);
                mx = double.max (mx, v);
            }
            return mx > mn;
        }

        private static void draw_radar (Cairo.Context cr, RenderContext ctx, ChartElement ch, double x, double y, double w, double h, Rgba fg, double fs, int ncat) {
            double vmin, vmax;
            range_of (ch, ch.series, ncat, false, false, out vmin, out vmax);
            var sc = make_scale (ch.val_axis, double.min (vmin, 0), vmax, false);
            double lab_h = fs * 1.4;
            double r = double.min (w, h) / 2 - lab_h;
            if (r < 5) return;
            double cx = x + w / 2, cy = y + h / 2;
            cr.set_line_width (double.max (fs * 0.05, 0.5));
            foreach (var v in sc.ticks ()) {
                double rr = sc.t (v) * r;
                cr.new_path ();
                for (int c = 0; c <= ncat; c++) {
                    double a = -Math.PI / 2 + 2 * Math.PI * (c % ncat) / ncat;
                    if (c == 0) cr.move_to (cx + Math.cos (a) * rr, cy + Math.sin (a) * rr);
                    else cr.line_to (cx + Math.cos (a) * rr, cy + Math.sin (a) * rr);
                }
                Renderer.set_source (cr, fg, 0.14);
                cr.stroke ();
                var l = label (sc.label (v), fs * 0.8);
                double tw, th;
                text_size (l, out tw, out th);
                Renderer.set_source (cr, fg, 0.6);
                show (cr, l, cx + fs * 0.2, cy - rr - th / 2);
            }
            for (int c = 0; c < ncat; c++) {
                double a = -Math.PI / 2 + 2 * Math.PI * c / ncat;
                Renderer.set_source (cr, fg, 0.2);
                cr.move_to (cx, cy);
                cr.line_to (cx + Math.cos (a) * r, cy + Math.sin (a) * r);
                cr.stroke ();
                if (c < ch.categories.size) {
                    var l = label (ch.categories[c], fs * 0.9);
                    double tw, th;
                    text_size (l, out tw, out th);
                    Renderer.set_source (cr, fg, 0.75);
                    show (cr, l, cx + Math.cos (a) * (r + lab_h * 0.6) - tw / 2, cy + Math.sin (a) * (r + lab_h * 0.6) - th / 2);
                }
            }
            for (int i = 0; i < ch.series.size; i++) {
                var s = ch.series[i];
                var col = ctx.theme.resolve (series_color (ch, i));
                cr.new_path ();
                for (int c = 0; c <= ncat; c++) {
                    int k = c % ncat;
                    double a = -Math.PI / 2 + 2 * Math.PI * k / ncat;
                    double rr = sc.t (s.value_at (k)).clamp (0, 1) * r;
                    if (c == 0) cr.move_to (cx + Math.cos (a) * rr, cy + Math.sin (a) * rr);
                    else cr.line_to (cx + Math.cos (a) * rr, cy + Math.sin (a) * rr);
                }
                cr.close_path ();
                if (ch.grouping == ChartGrouping.STACKED) {
                    Renderer.set_source (cr, col, 0.35);
                    cr.fill_preserve ();
                }
                Renderer.set_source (cr, col);
                cr.set_line_width (double.max (fs * 0.16, 1));
                cr.stroke ();
            }
        }
    }
}
