namespace Singularity.Apps.Slides {

    public enum PrintWhat {
        SLIDES,
        NOTES,
        HANDOUT_1,
        HANDOUT_2,
        HANDOUT_3,
        HANDOUT_4,
        HANDOUT_6,
        HANDOUT_9,
        OUTLINE;

        public string label () {
            switch (this) {
                case NOTES: return _("Notes Pages");
                case HANDOUT_1: return _("Handouts, 1 Slide per Page");
                case HANDOUT_2: return _("Handouts, 2 Slides per Page");
                case HANDOUT_3: return _("Handouts, 3 Slides with Lines");
                case HANDOUT_4: return _("Handouts, 4 Slides per Page");
                case HANDOUT_6: return _("Handouts, 6 Slides per Page");
                case HANDOUT_9: return _("Handouts, 9 Slides per Page");
                case OUTLINE: return _("Outline");
                default: return _("Full Page Slides");
            }
        }

        public string key () {
            switch (this) {
                case NOTES: return "notes";
                case HANDOUT_1: return "handout1";
                case HANDOUT_2: return "handout2";
                case HANDOUT_3: return "handout3";
                case HANDOUT_4: return "handout4";
                case HANDOUT_6: return "handout6";
                case HANDOUT_9: return "handout9";
                case OUTLINE: return "outline";
                default: return "slides";
            }
        }

        public static PrintWhat from_key (string k) {
            foreach (var w in ALL) if (w.key () == k) return w;
            return SLIDES;
        }

        public int per_page () {
            switch (this) {
                case HANDOUT_2: return 2;
                case HANDOUT_3: return 3;
                case HANDOUT_4: return 4;
                case HANDOUT_6: return 6;
                case HANDOUT_9: return 9;
                default: return 1;
            }
        }

        public const PrintWhat[] ALL = { SLIDES, NOTES, HANDOUT_1, HANDOUT_2, HANDOUT_3, HANDOUT_4, HANDOUT_6, HANDOUT_9, OUTLINE };
    }

    public class PrintLayout {
        public Presentation pres;
        public PrintWhat what = PrintWhat.SLIDES;
        public bool frame_slides = false;
        public bool include_hidden = false;
        public bool include_comments = false;
        public bool footer_numbers = true;
        public Gee.ArrayList<Slide> slides = new Gee.ArrayList<Slide> ();
        private Gee.ArrayList<string> outline_lines = new Gee.ArrayList<string> ();
        private Gee.ArrayList<int> outline_levels = new Gee.ArrayList<int> ();
        private Gee.ArrayList<int> outline_breaks = new Gee.ArrayList<int> ();

        public PrintLayout (Presentation pres) {
            this.pres = pres;
        }

        public void collect () {
            slides.clear ();
            foreach (var s in pres.slides) if (include_hidden || !s.hidden) slides.add (s);
        }

        public int pages (double w, double h) {
            collect ();
            if (slides.size == 0) return 0;
            switch (what) {
                case PrintWhat.SLIDES:
                case PrintWhat.NOTES:
                case PrintWhat.HANDOUT_1:
                    return slides.size + (include_comments ? comment_pages () : 0);
                case PrintWhat.OUTLINE:
                    return paginate_outline (w, h);
                default:
                    int per = what.per_page ();
                    return (slides.size + per - 1) / per;
            }
        }

        private int comment_pages () {
            int n = 0;
            foreach (var s in slides) if (s.comments.size > 0) n++;
            return n;
        }

        private Pango.Layout text_layout (Cairo.Context cr, string font, double width) {
            var l = Pango.cairo_create_layout (cr);
            Pango.cairo_context_set_resolution (l.get_context (), 72);
            l.set_font_description (Pango.FontDescription.from_string (font));
            if (width > 0) {
                l.set_width ((int) (width * Pango.SCALE));
                l.set_wrap (Pango.WrapMode.WORD_CHAR);
            }
            return l;
        }

        private int paginate_outline (double w, double h) {
            outline_lines.clear ();
            outline_levels.clear ();
            outline_breaks.clear ();
            var surf = new Cairo.ImageSurface (Cairo.Format.ARGB32, 1, 1);
            var cr = new Cairo.Context (surf);
            double y = 0;
            double avail = h - 60;
            outline_breaks.add (0);
            for (int i = 0; i < slides.size; i++) {
                var s = slides[i];
                string title = s.title ();
                add_outline (cr, "%d  %s".printf (pres.slides.index_of (s) + 1, title != "" ? title : _("Untitled Slide")), 0, w, avail, ref y);
                foreach (var e in s.elements) {
                    if (e.placeholder.is_title ()) continue;
                    var b = e.text_body ();
                    if (b == null || b.is_empty ()) continue;
                    foreach (var p in b.paragraphs) {
                        string t = p.text ().strip ();
                        if (t != "") add_outline (cr, t, p.level + 1, w, avail, ref y);
                    }
                }
            }
            return outline_breaks.size;
        }

        private void add_outline (Cairo.Context cr, string text, int level, double w, double avail, ref double y) {
            var l = text_layout (cr, level == 0 ? "Inter Bold 13" : "Inter 11", w - 24 * level);
            l.set_text (text, -1);
            int lw, lh;
            l.get_pixel_size (out lw, out lh);
            double need = lh + (level == 0 ? 10 : 4);
            if (y + need > avail && y > 0) {
                outline_breaks.add (outline_lines.size);
                y = 0;
            }
            outline_lines.add (text);
            outline_levels.add (level);
            y += need;
        }

        private void draw_slide_box (Cairo.Context cr, Slide s, double x, double y, double w, double h) {
            double sw = w, sh = sw * pres.height / pres.width;
            if (sh > h) {
                sh = h;
                sw = sh * pres.width / pres.height;
            }
            double ox = x + (w - sw) / 2, oy = y + (h - sh) / 2;
            cr.save ();
            cr.translate (ox, oy);
            cr.rectangle (0, 0, sw, sh);
            cr.clip ();
            cr.scale (sw / pres.width, sh / pres.height);
            new Renderer ().draw_slide (cr, pres, s);
            cr.restore ();
            if (frame_slides || what != PrintWhat.SLIDES) {
                cr.save ();
                cr.rectangle (ox - 0.5, oy - 0.5, sw + 1, sh + 1);
                cr.set_source_rgb (0.6, 0.6, 0.6);
                cr.set_line_width (0.75);
                cr.stroke ();
                cr.restore ();
            }
        }

        private void footer (Cairo.Context cr, double x, double y, double w, double h, int n, int total) {
            if (!footer_numbers) return;
            var l = text_layout (cr, "Inter 8", 0);
            l.set_text ("%d / %d".printf (n, total), -1);
            int lw, lh;
            l.get_pixel_size (out lw, out lh);
            cr.save ();
            cr.set_source_rgb (0.45, 0.45, 0.45);
            cr.move_to (x + w - lw, y + h - lh);
            Pango.cairo_show_layout (cr, l);
            cr.restore ();
        }

        private void comments_page (Cairo.Context cr, Slide s, double x, double y, double w, double h) {
            var l = text_layout (cr, "Inter Bold 14", w);
            l.set_text (_("Comments on Slide %d").printf (pres.slides.index_of (s) + 1), -1);
            cr.set_source_rgb (0.1, 0.1, 0.1);
            cr.move_to (x, y);
            Pango.cairo_show_layout (cr, l);
            double cy = y + 30;
            foreach (var c in s.comments) {
                foreach (var item in thread (c)) {
                    var t = text_layout (cr, "Inter 10", w - (item == c ? 0 : 24));
                    t.set_markup ("<b>%s</b>  %s\n%s".printf (Markup.escape_text (item.author), Markup.escape_text (item.display_date ()), Markup.escape_text (item.text)), -1);
                    int tw, th;
                    t.get_pixel_size (out tw, out th);
                    if (cy + th > y + h) return;
                    cr.move_to (x + (item == c ? 0 : 24), cy);
                    Pango.cairo_show_layout (cr, t);
                    cy += th + 10;
                }
            }
        }

        private static Gee.ArrayList<Comment> thread (Comment c) {
            var list = new Gee.ArrayList<Comment> ();
            list.add (c);
            list.add_all (c.replies);
            return list;
        }

        public void draw_page (Cairo.Context cr, int index, double x, double y, double w, double h) {
            if (slides.size == 0) collect ();
            if (slides.size == 0) return;
            switch (what) {
                case PrintWhat.SLIDES:
                case PrintWhat.NOTES:
                case PrintWhat.HANDOUT_1:
                    int k = index;
                    int si = 0;
                    Slide? s = null;
                    bool comment_page = false;
                    foreach (var sl in slides) {
                        if (k == 0) {
                            s = sl;
                            break;
                        }
                        k--;
                        if (include_comments && sl.comments.size > 0) {
                            if (k == 0) {
                                s = sl;
                                comment_page = true;
                                break;
                            }
                            k--;
                        }
                        si++;
                    }
                    if (s == null) return;
                    if (comment_page) {
                        comments_page (cr, s, x, y, w, h);
                        return;
                    }
                    if (what == PrintWhat.SLIDES) {
                        draw_slide_box (cr, s, x, y, w, h);
                    } else if (what == PrintWhat.HANDOUT_1) {
                        draw_slide_box (cr, s, x, y, w, h * 0.85);
                        footer (cr, x, y, w, h, si + 1, slides.size);
                    } else {
                        double sh = h * 0.45;
                        draw_slide_box (cr, s, x, y, w, sh);
                        var l = text_layout (cr, "Inter 12", w);
                        l.set_text (s.notes, -1);
                        cr.save ();
                        cr.set_source_rgb (0.1, 0.1, 0.1);
                        cr.rectangle (x, y + sh + 24, w, h - sh - 48);
                        cr.clip ();
                        cr.move_to (x, y + sh + 24);
                        Pango.cairo_show_layout (cr, l);
                        cr.restore ();
                        footer (cr, x, y, w, h, si + 1, slides.size);
                    }
                    break;
                case PrintWhat.OUTLINE:
                    if (outline_breaks.size == 0) paginate_outline (w, h);
                    if (index >= outline_breaks.size) return;
                    int start = outline_breaks[index];
                    int end = index + 1 < outline_breaks.size ? outline_breaks[index + 1] : outline_lines.size;
                    double oy = y;
                    cr.set_source_rgb (0.1, 0.1, 0.1);
                    for (int i = start; i < end; i++) {
                        int lv = outline_levels[i];
                        var l = text_layout (cr, lv == 0 ? "Inter Bold 13" : "Inter 11", w - 24 * lv);
                        l.set_text ((lv > 0 ? "• " : "") + outline_lines[i], -1);
                        if (lv == 0 && i > start) oy += 6;
                        cr.move_to (x + 24 * lv, oy);
                        Pango.cairo_show_layout (cr, l);
                        int lw, lh;
                        l.get_pixel_size (out lw, out lh);
                        oy += lh + (lv == 0 ? 4 : 4);
                    }
                    footer (cr, x, y, w, h, index + 1, outline_breaks.size);
                    break;
                default:
                    int per = what.per_page ();
                    int cols = per == 9 ? 3 : (per == 4 || per == 6 ? 2 : 1);
                    int rows = (per + cols - 1) / cols;
                    double gap = 18;
                    double body_h = h - 24;
                    double cell_w = per == 3 ? w * 0.48 : (w - (cols - 1) * gap) / cols;
                    double cell_h = (body_h - (rows - 1) * gap) / rows;
                    for (int k = 0; k < per; k++) {
                        int si = index * per + k;
                        if (si >= slides.size) break;
                        int c = k % cols, r = k / cols;
                        double cx = x + c * (cell_w + gap), cy = y + r * (cell_h + gap);
                        draw_slide_box (cr, slides[si], cx, cy, cell_w, cell_h);
                        if (per == 3) {
                            cr.save ();
                            cr.set_source_rgb (0.75, 0.75, 0.75);
                            cr.set_line_width (0.5);
                            for (int ln = 1; ln <= 6; ln++) {
                                double ly = cy + cell_h * ln / 7;
                                cr.move_to (x + cell_w + 24, ly);
                                cr.line_to (x + w, ly);
                            }
                            cr.stroke ();
                            cr.restore ();
                        }
                    }
                    footer (cr, x, y, w, h, index + 1, (slides.size + per - 1) / per);
                    break;
            }
        }
    }
}
