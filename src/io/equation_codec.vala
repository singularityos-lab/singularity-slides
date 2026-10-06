namespace Singularity.Apps.Slides {

    public class EquationCodec {
        public static string signature (EquationElement q) {
            return "%s|%s|%s|%.2f|%.2f|%.2f|%.2f|%.2f|%u".printf (q.latex, q.mathml, q.color, q.x, q.y, q.w, q.h, q.rotation, q.image != null ? q.image.hash () : 0);
        }

        public static string omml_for (EquationElement q) {
            if (q.mathml != "") {
                var eq = new Singularity.Equations.Equation.from_mathml (q.mathml);
                return eq.to_omml ();
            }
            return q.omml;
        }

        public static string mathml_from_omml (string omml) {
            var eq = Singularity.Equations.Equation.from_omml (omml);
            return eq != null ? eq.mathml : "";
        }

        public static Bytes png_for (EquationElement q) {
            if (q.image_mime == "image/png") return q.image;
            var pb = ImageCache.decode (q.image);
            int w = int.max (1, (int) Math.ceil (q.w * 3)), h = int.max (1, (int) Math.ceil (q.h * 3));
            var surf = new Cairo.ImageSurface (Cairo.Format.ARGB32, w, h);
            if (pb != null) {
                var cr = new Cairo.Context (surf);
                var src = ImageCache.to_surface (pb);
                cr.scale ((double) w / pb.width, (double) h / pb.height);
                cr.set_source_surface (src, 0, 0);
                cr.paint ();
            }
            var bytes = new ByteArray ();
            surf.write_to_png_stream ((data) => {
                bytes.append (data);
                return Cairo.Status.SUCCESS;
            });
            return ByteArray.free_to_bytes ((owned) bytes);
        }
    }
}
