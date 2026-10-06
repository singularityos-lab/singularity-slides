namespace Singularity.Apps.Slides {

    public class ImageCache {
        private class Entry {
            public Bytes data;
            public Gdk.Pixbuf? pixbuf;
            public Cairo.ImageSurface? surface;
            public string filter_key = "";
            public Cairo.ImageSurface? filtered;
            public int64 used;
        }

        private static Gee.HashMap<string, Entry>? entries = null;
        private const int LIMIT = 48;

        private static string key_of (Bytes b) {
            return "%p:%zu".printf (b, b.get_size ());
        }

        private static Entry? entry (Bytes data) {
            if (entries == null) entries = new Gee.HashMap<string, Entry> ();
            string k = key_of (data);
            var e = entries[k];
            if (e != null && e.data == data) {
                e.used = get_monotonic_time ();
                return e;
            }
            e = new Entry ();
            e.data = data;
            e.used = get_monotonic_time ();
            e.pixbuf = decode (data);
            if (e.pixbuf != null) e.surface = to_surface (e.pixbuf);
            if (entries.size >= LIMIT) evict ();
            entries[k] = e;
            return e;
        }

        private static void evict () {
            string? oldest = null;
            int64 t = int64.MAX;
            foreach (var kv in entries.entries) {
                if (kv.value.used < t) {
                    t = kv.value.used;
                    oldest = kv.key;
                }
            }
            if (oldest != null) entries.unset (oldest);
        }

        public static Gdk.Pixbuf? decode (Bytes data) {
            try {
                var loader = new Gdk.PixbufLoader ();
                loader.size_prepared.connect ((w, h) => {
                    int mx = int.max (w, h);
                    if (mx > 4096) {
                        double f = 4096.0 / mx;
                        loader.set_size ((int) (w * f), (int) (h * f));
                    } else if (mx < 1024 && loader.get_format () != null && loader.get_format ().get_name () == "svg") {
                        double f = 1600.0 / int.max (mx, 1);
                        loader.set_size ((int) (w * f), (int) (h * f));
                    }
                });
                loader.write (data.get_data ());
                loader.close ();
                var pb = loader.get_pixbuf ();
                if (pb == null) return null;
                var rotated = pb.apply_embedded_orientation ();
                return rotated ?? pb;
            } catch (Error e) {
                return null;
            }
        }

        public static Cairo.ImageSurface to_surface (Gdk.Pixbuf pb) {
            var surf = new Cairo.ImageSurface (Cairo.Format.ARGB32, pb.width, pb.height);
            var cr = new Cairo.Context (surf);
            Gdk.cairo_set_source_pixbuf (cr, pb, 0, 0);
            cr.paint ();
            surf.flush ();
            return surf;
        }

        public static bool size_of (Bytes data, out int w, out int h) {
            var e = entry (data);
            if (e == null || e.pixbuf == null) {
                w = 0;
                h = 0;
                return false;
            }
            w = e.pixbuf.width;
            h = e.pixbuf.height;
            return true;
        }

        public static Cairo.ImageSurface? surface (Bytes data) {
            var e = entry (data);
            return e != null ? e.surface : null;
        }

        public static Cairo.ImageSurface? filtered (ImageElement img) {
            var e = entry (img.data);
            if (e == null || e.surface == null) return null;
            if (!img.has_filters ()) return e.surface;
            string fk = "%g/%g/%g/%s/%g".printf (img.brightness, img.contrast, img.saturation, img.sepia.to_string (), img.blur);
            if (e.filtered != null && e.filter_key == fk) return e.filtered;
            e.filtered = apply_filters (e.surface, img.brightness, img.contrast, img.saturation, img.sepia, img.blur);
            e.filter_key = fk;
            return e.filtered;
        }

        public static Cairo.ImageSurface apply_filters (Cairo.ImageSurface src, double brightness, double contrast, double saturation, bool sepia, double blur) {
            int w = src.get_width (), h = src.get_height ();
            var dst = new Cairo.ImageSurface (Cairo.Format.ARGB32, w, h);
            var cr = new Cairo.Context (dst);
            cr.set_source_surface (src, 0, 0);
            cr.paint ();
            dst.flush ();
            unowned uint8[] px = dst.get_data ();
            int stride = dst.get_stride ();
            double cf = contrast >= 0 ? 1 + contrast * 3 : 1 + contrast;
            double bo = brightness * 255;
            for (int y = 0; y < h; y++) {
                int row = y * stride;
                for (int x = 0; x < w; x++) {
                    int i = row + x * 4;
                    double a = px[i + 3];
                    if (a == 0) continue;
                    double b = px[i] * 255.0 / a, g = px[i + 1] * 255.0 / a, r = px[i + 2] * 255.0 / a;
                    if (saturation != 1 || sepia) {
                        double l = 0.299 * r + 0.587 * g + 0.114 * b;
                        r = l + (r - l) * saturation;
                        g = l + (g - l) * saturation;
                        b = l + (b - l) * saturation;
                        if (sepia) {
                            double sr = r * 0.393 + g * 0.769 + b * 0.189;
                            double sg = r * 0.349 + g * 0.686 + b * 0.168;
                            double sb = r * 0.272 + g * 0.534 + b * 0.131;
                            r = sr;
                            g = sg;
                            b = sb;
                        }
                    }
                    r = (r - 128) * cf + 128 + bo;
                    g = (g - 128) * cf + 128 + bo;
                    b = (b - 128) * cf + 128 + bo;
                    px[i] = (uint8) (b.clamp (0, 255) * a / 255.0);
                    px[i + 1] = (uint8) (g.clamp (0, 255) * a / 255.0);
                    px[i + 2] = (uint8) (r.clamp (0, 255) * a / 255.0);
                }
            }
            dst.mark_dirty ();
            if (blur > 0) Effects.blur (dst, (int) Math.round (blur * double.max (w, h) / 400.0));
            return dst;
        }

        public static void clear () {
            if (entries != null) entries.clear ();
        }
    }

    public class Effects {
        private class ShadowEntry {
            public string key;
            public Cairo.ImageSurface surface;
            public double ox;
            public double oy;
        }

        private static Gee.LinkedList<ShadowEntry>? shadows = null;

        public static void blur (Cairo.ImageSurface surf, int radius) {
            if (radius < 1) return;
            surf.flush ();
            int w = surf.get_width (), h = surf.get_height ();
            int stride = surf.get_stride ();
            unowned uint8[] px = surf.get_data ();
            uint8[] tmp = new uint8[stride * h];
            for (int pass = 0; pass < 3; pass++) {
                box (px, tmp, w, h, stride, radius, true);
                box (tmp, px, w, h, stride, radius, false);
            }
            surf.mark_dirty ();
        }

        private static void box (uint8[] src, uint8[] dst, int w, int h, int stride, int r, bool horizontal) {
            int outer = horizontal ? h : w;
            int inner = horizontal ? w : h;
            double div = 2 * r + 1;
            for (int o = 0; o < outer; o++) {
                for (int ch = 0; ch < 4; ch++) {
                    double sum = 0;
                    for (int k = -r; k <= r; k++) {
                        int idx = k.clamp (0, inner - 1);
                        sum += src[horizontal ? o * stride + idx * 4 + ch : idx * stride + o * 4 + ch];
                    }
                    for (int i = 0; i < inner; i++) {
                        int di = horizontal ? o * stride + i * 4 + ch : i * stride + o * 4 + ch;
                        dst[di] = (uint8) (sum / div).clamp (0, 255);
                        int add = (i + r + 1).clamp (0, inner - 1);
                        int rem = (i - r).clamp (0, inner - 1);
                        sum += src[horizontal ? o * stride + add * 4 + ch : add * stride + o * 4 + ch];
                        sum -= src[horizontal ? o * stride + rem * 4 + ch : rem * stride + o * 4 + ch];
                    }
                }
            }
        }

        public delegate void PathFunc (Cairo.Context cr);

        public static void shadow (Cairo.Context cr, string key, double x, double y, double w, double h, Rgba color, double blur, double dx, double dy, PathFunc path, bool stroke_only, double line_width) {
            if (shadows == null) shadows = new Gee.LinkedList<ShadowEntry> ();
            double sx, sy;
            device_scale (cr, out sx, out sy);
            double scale = double.min (double.max (sx, sy), 4);
            if (scale <= 0) scale = 1;
            double pad = blur * 2 + 2;
            string full = "%s|%g|%g|%g|%g|%g|%s|%g".printf (key, w, h, blur, scale, color.a, color.to_hex (), line_width);
            ShadowEntry? found = null;
            foreach (var e in shadows) {
                if (e.key == full) {
                    found = e;
                    break;
                }
            }
            if (found == null) {
                int iw = (int) Math.ceil ((w + pad * 2) * scale), ih = (int) Math.ceil ((h + pad * 2) * scale);
                if (iw <= 0 || ih <= 0 || iw > 6000 || ih > 6000) return;
                var surf = new Cairo.ImageSurface (Cairo.Format.ARGB32, iw, ih);
                var sc = new Cairo.Context (surf);
                sc.scale (scale, scale);
                sc.translate (pad - x, pad - y);
                path (sc);
                sc.set_source_rgba (color.r, color.g, color.b, color.a);
                if (stroke_only) {
                    sc.set_line_width (line_width);
                    sc.stroke ();
                } else {
                    sc.fill ();
                }
                surf.flush ();
                Effects.blur (surf, (int) Math.round (blur * scale / 2));
                found = new ShadowEntry ();
                found.key = full;
                found.surface = surf;
                found.ox = x - pad;
                found.oy = y - pad;
                shadows.insert (0, found);
                if (shadows.size > 64) shadows.remove_at (shadows.size - 1);
            }
            cr.save ();
            cr.translate (x - pad + dx, y - pad + dy);
            cr.scale (1 / scale, 1 / scale);
            cr.set_source_surface (found.surface, 0, 0);
            cr.paint ();
            cr.restore ();
        }

        public static Cairo.ImageSurface? soft_mask (double x, double y, double w, double h, double radius, double scale, PathFunc path) {
            double pad = radius * 2 + 2;
            int iw = (int) Math.ceil ((w + pad * 2) * scale), ih = (int) Math.ceil ((h + pad * 2) * scale);
            if (iw <= 0 || ih <= 0 || iw > 6000 || ih > 6000) return null;
            var surf = new Cairo.ImageSurface (Cairo.Format.ARGB32, iw, ih);
            var sc = new Cairo.Context (surf);
            sc.scale (scale, scale);
            sc.translate (pad - x, pad - y);
            path (sc);
            sc.set_source_rgba (1, 1, 1, 1);
            sc.fill_preserve ();
            sc.set_operator (Cairo.Operator.CLEAR);
            sc.set_line_width (radius);
            sc.stroke ();
            surf.flush ();
            blur (surf, (int) Math.round (radius * scale / 2));
            return surf;
        }

        public static void device_scale (Cairo.Context cr, out double sx, out double sy) {
            var m = cr.get_matrix ();
            sx = Math.sqrt (m.xx * m.xx + m.yx * m.yx);
            sy = Math.sqrt (m.xy * m.xy + m.yy * m.yy);
        }
    }
}

namespace Singularity.Apps.Slides {

    public class BackgroundRemover {
        private static void lab (uint8 r, uint8 g, uint8 b, out double l, out double a, out double bb) {
            double rr = r / 255.0, gg = g / 255.0, b2 = b / 255.0;
            l = 0.299 * rr + 0.587 * gg + 0.114 * b2;
            a = rr - gg;
            bb = (rr + gg) / 2 - b2;
        }

        public static Cairo.ImageSurface? run (Cairo.ImageSurface src, double tolerance) {
            int w = src.get_width (), h = src.get_height ();
            if (w <= 2 || h <= 2) return null;
            var out_s = new Cairo.ImageSurface (Cairo.Format.ARGB32, w, h);
            var cr = new Cairo.Context (out_s);
            cr.set_source_surface (src, 0, 0);
            cr.paint ();
            out_s.flush ();
            unowned uint8[] d = out_s.get_data ();
            int stride = out_s.get_stride ();
            var samples = new Gee.ArrayList<double?> ();
            for (int x = 0; x < w; x += int.max (1, w / 64)) {
                foreach (int y in new int[] { 0, h - 1 }) {
                    int o = y * stride + x * 4;
                    double l, a, b;
                    lab (d[o + 2], d[o + 1], d[o], out l, out a, out b);
                    samples.add (l);
                    samples.add (a);
                    samples.add (b);
                }
            }
            for (int y = 0; y < h; y += int.max (1, h / 64)) {
                foreach (int x in new int[] { 0, w - 1 }) {
                    int o = y * stride + x * 4;
                    double l, a, b;
                    lab (d[o + 2], d[o + 1], d[o], out l, out a, out b);
                    samples.add (l);
                    samples.add (a);
                    samples.add (b);
                }
            }
            var mask = new uint8[w * h];
            var queue = new Gee.ArrayQueue<int> ();
            for (int x = 0; x < w; x++) {
                queue.offer (x);
                queue.offer ((h - 1) * w + x);
            }
            for (int y = 0; y < h; y++) {
                queue.offer (y * w);
                queue.offer (y * w + w - 1);
            }
            double tol = tolerance * tolerance;
            while (!queue.is_empty) {
                int idx = queue.poll ();
                if (mask[idx] != 0) continue;
                int x = idx % w, y = idx / w;
                int o = y * stride + x * 4;
                if (d[o + 3] < 8) {
                    mask[idx] = 1;
                } else {
                    double l, a, b;
                    lab (d[o + 2], d[o + 1], d[o], out l, out a, out b);
                    bool bg = false;
                    for (int k = 0; k + 2 < samples.size; k += 3) {
                        double dl = l - samples[k], da = a - samples[k + 1], db = b - samples[k + 2];
                        if (dl * dl + da * da + db * db <= tol) {
                            bg = true;
                            break;
                        }
                    }
                    if (!bg) {
                        mask[idx] = 2;
                        continue;
                    }
                    mask[idx] = 1;
                }
                if (x > 0 && mask[idx - 1] == 0) queue.offer (idx - 1);
                if (x < w - 1 && mask[idx + 1] == 0) queue.offer (idx + 1);
                if (y > 0 && mask[idx - w] == 0) queue.offer (idx - w);
                if (y < h - 1 && mask[idx + w] == 0) queue.offer (idx + w);
            }
            for (int y = 0; y < h; y++) {
                for (int x = 0; x < w; x++) {
                    int idx = y * w + x;
                    int o = y * stride + x * 4;
                    if (mask[idx] == 1) {
                        d[o] = d[o + 1] = d[o + 2] = d[o + 3] = 0;
                        continue;
                    }
                    int near_bg = 0;
                    if (x > 0 && mask[idx - 1] == 1) near_bg++;
                    if (x < w - 1 && mask[idx + 1] == 1) near_bg++;
                    if (y > 0 && mask[idx - w] == 1) near_bg++;
                    if (y < h - 1 && mask[idx + w] == 1) near_bg++;
                    if (near_bg > 0) {
                        double f = 1 - near_bg * 0.18;
                        for (int c = 0; c < 4; c++) d[o + c] = (uint8) (d[o + c] * f);
                    }
                }
            }
            out_s.mark_dirty ();
            return out_s;
        }

        public static Bytes png (Cairo.ImageSurface s) {
            var bytes = new ByteArray ();
            s.write_to_png_stream ((data) => {
                bytes.append (data);
                return Cairo.Status.SUCCESS;
            });
            return ByteArray.free_to_bytes ((owned) bytes);
        }
    }
}
