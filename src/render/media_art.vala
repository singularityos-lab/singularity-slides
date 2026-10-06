namespace Singularity.Apps.Slides {

    public class MediaArt {
        public static void draw (Cairo.Context cr, MediaElement m, double x, double y, double w, double h) {
            cr.save ();
            if (m.is_video) {
                cr.rectangle (x, y, w, h);
                cr.set_source_rgb (0.08, 0.08, 0.1);
                cr.fill ();
            }
            double s = double.min (w, h) * (m.is_video ? 0.28 : 0.8);
            double cx = x + w / 2, cy = y + h / 2;
            if (m.is_video) {
                cr.arc (cx, cy, s / 2, 0, 2 * Math.PI);
                cr.set_source_rgba (1, 1, 1, 0.9);
                cr.fill ();
                cr.move_to (cx - s * 0.14, cy - s * 0.22);
                cr.line_to (cx + s * 0.24, cy);
                cr.line_to (cx - s * 0.14, cy + s * 0.22);
                cr.close_path ();
                cr.set_source_rgb (0.08, 0.08, 0.1);
                cr.fill ();
            } else {
                double u = s / 10;
                cr.move_to (cx - u * 4, cy - u * 1.5);
                cr.line_to (cx - u * 2, cy - u * 1.5);
                cr.line_to (cx + u * 0.5, cy - u * 4);
                cr.line_to (cx + u * 0.5, cy + u * 4);
                cr.line_to (cx - u * 2, cy + u * 1.5);
                cr.line_to (cx - u * 4, cy + u * 1.5);
                cr.close_path ();
                cr.set_source_rgb (0.25, 0.45, 0.85);
                cr.fill ();
                cr.set_line_width (u * 0.7);
                cr.set_line_cap (Cairo.LineCap.ROUND);
                for (int i = 1; i <= 2; i++) {
                    cr.arc (cx + u * 0.5, cy, u * (1.6 * i + 0.4), -Math.PI / 4, Math.PI / 4);
                    cr.stroke ();
                }
            }
            cr.restore ();
        }

        public static Bytes poster_png (MediaElement m) {
            double w = double.max (m.w, 16), h = double.max (m.h, 16);
            double scale = double.min (2, 1280 / w);
            int pw = int.max (1, (int) (w * scale)), ph = int.max (1, (int) (h * scale));
            var surf = new Cairo.ImageSurface (Cairo.Format.ARGB32, pw, ph);
            var cr = new Cairo.Context (surf);
            cr.scale (scale, scale);
            draw (cr, m, 0, 0, w, h);
            var bytes = new ByteArray ();
            surf.write_to_png_stream ((data) => {
                bytes.append (data);
                return Cairo.Status.SUCCESS;
            });
            return ByteArray.free_to_bytes ((owned) bytes);
        }
    }
}
