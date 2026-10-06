namespace Singularity.Apps.Slides {

    public enum PdfLayout {
        SLIDES,
        NOTES,
        HANDOUT_2,
        HANDOUT_3,
        HANDOUT_6
    }

    public class Exporter {
        public Presentation pres;
        public bool include_hidden = false;
        public bool final_state = true;

        public Exporter (Presentation pres) {
            this.pres = pres;
        }

        public Gee.ArrayList<Slide> visible_slides () {
            var list = new Gee.ArrayList<Slide> ();
            foreach (var s in pres.slides) if (include_hidden || !s.hidden) list.add (s);
            return list;
        }

        private Renderer renderer () {
            return new Renderer ();
        }

        public void draw_slide (Cairo.Context cr, Slide s) {
            var r = renderer ();
            r.draw_slide (cr, pres, s);
        }

        public void export_pdf (string path, PdfLayout layout = PdfLayout.SLIDES) throws Error {
            PrintWhat what;
            switch (layout) {
                case PdfLayout.NOTES: what = PrintWhat.NOTES; break;
                case PdfLayout.HANDOUT_2: what = PrintWhat.HANDOUT_2; break;
                case PdfLayout.HANDOUT_3: what = PrintWhat.HANDOUT_3; break;
                case PdfLayout.HANDOUT_6: what = PrintWhat.HANDOUT_6; break;
                default: what = PrintWhat.SLIDES; break;
            }
            export_layout (path, what, false);
        }

        public void export_layout (string path, PrintWhat what, bool comments) throws Error {
            var pl = new PrintLayout (pres);
            pl.what = what;
            pl.include_hidden = include_hidden;
            pl.include_comments = comments;
            bool full = what == PrintWhat.SLIDES;
            double pw = full ? pres.width : 595.28, ph = full ? pres.height : 841.89;
            double margin = full ? 0 : 48;
            int n = pl.pages (pw - margin * 2, ph - margin * 2);
            if (n == 0) throw new FileError.INVAL (_("There are no slides to export."));
            var surf = new Cairo.PdfSurface (path, pw, ph);
            set_metadata (surf);
            var cr = new Cairo.Context (surf);
            for (int i = 0; i < n; i++) {
                pl.draw_page (cr, i, margin, margin, pw - margin * 2, ph - margin * 2);
                cr.show_page ();
            }
            surf.finish ();
            check (surf);
        }

        private void check (Cairo.Surface surf) throws Error {
            if (surf.status () != Cairo.Status.SUCCESS) throw new FileError.FAILED (_("Could not write the PDF file."));
        }

        private void set_metadata (Cairo.PdfSurface surf) {
            if (pres.properties.title != "") surf.set_metadata (Cairo.PdfMetadata.TITLE, pres.properties.title);
            if (pres.properties.author != "") surf.set_metadata (Cairo.PdfMetadata.AUTHOR, pres.properties.author);
            surf.set_metadata (Cairo.PdfMetadata.CREATOR, "Singularity Slides");
        }

        public Cairo.ImageSurface render (Slide s, int width) {
            int height = (int) Math.round (width * pres.height / pres.width);
            var surf = new Cairo.ImageSurface (Cairo.Format.ARGB32, width, height);
            var cr = new Cairo.Context (surf);
            cr.scale (width / pres.width, height / pres.height);
            draw_slide (cr, s);
            surf.flush ();
            return surf;
        }

        public static Gdk.Pixbuf to_pixbuf (Cairo.ImageSurface surf) {
            surf.flush ();
            int w = surf.get_width (), h = surf.get_height ();
            var pb = new Gdk.Pixbuf (Gdk.Colorspace.RGB, false, 8, w, h);
            unowned uint8[] src = surf.get_data ();
            unowned uint8[] dst = pb.get_pixels ();
            int ss = surf.get_stride (), ds = pb.rowstride;
            for (int y = 0; y < h; y++) {
                for (int x = 0; x < w; x++) {
                    int i = y * ss + x * 4, o = y * ds + x * 3;
                    double a = src[i + 3] / 255.0;
                    dst[o] = (uint8) (src[i + 2] + 255 * (1 - a));
                    dst[o + 1] = (uint8) (src[i + 1] + 255 * (1 - a));
                    dst[o + 2] = (uint8) (src[i] + 255 * (1 - a));
                }
            }
            return pb;
        }

        public void export_image (Slide s, string path, int width) throws Error {
            var surf = render (s, width);
            string low = path.down ();
            if (low.has_suffix (".jpg") || low.has_suffix (".jpeg")) {
                var pb = to_pixbuf (surf);
                pb.save (path, "jpeg", "quality", "92");
                return;
            }
            if (surf.write_to_png (path) != Cairo.Status.SUCCESS) throw new FileError.FAILED (_("Could not write \"%s\".").printf (path));
        }

        public int export_images (string folder, string base_name, string ext, int width) throws Error {
            var slides = visible_slides ();
            int n = 0;
            for (int i = 0; i < slides.size; i++) {
                string name = "%s %0*d.%s".printf (base_name, slides.size >= 100 ? 3 : 2, i + 1, ext);
                export_image (slides[i], Path.build_filename (folder, name), width);
                n++;
            }
            return n;
        }

        public void export_svg (Slide s, string path) throws Error {
            var surf = new Cairo.SvgSurface (path, pres.width, pres.height);
            var cr = new Cairo.Context (surf);
            draw_slide (cr, s);
            surf.finish ();
            check (surf);
        }
    }
}
