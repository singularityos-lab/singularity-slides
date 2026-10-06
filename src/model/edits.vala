namespace Singularity.Apps.Slides {

    public class TextSpot {
        public int slide;
        public int element;
        public int row = -1;
        public int col = -1;
        public bool notes = false;
        public TextBody? body;
        public int start;
        public int length;

        public TextSpot (int slide, int element) {
            this.slide = slide;
            this.element = element;
        }
    }

    public class TextWalker {
        public delegate void Visit (TextSpot spot, string text);

        public static void walk (Presentation p, Visit visit) {
            for (int i = 0; i < p.slides.size; i++) {
                var s = p.slides[i];
                foreach (var e in s.elements) walk_element (i, e, visit);
                var ns = new TextSpot (i, -1);
                ns.notes = true;
                visit (ns, s.notes);
            }
        }

        private static void walk_element (int slide, Element e, Visit visit) {
            var g = e as GroupElement;
            if (g != null) {
                foreach (var c in g.children) walk_element (slide, c, visit);
                return;
            }
            var t = e as TableElement;
            if (t != null) {
                for (int r = 0; r < t.rows; r++) {
                    for (int c = 0; c < t.cols; c++) {
                        if (t.cells[r][c].covered) continue;
                        var spot = new TextSpot (slide, e.id);
                        spot.row = r;
                        spot.col = c;
                        spot.body = t.cells[r][c].text;
                        visit (spot, spot.body.plain_text ());
                    }
                }
                return;
            }
            var body = e.text_body ();
            if (body == null) return;
            var spot = new TextSpot (slide, e.id);
            spot.body = body;
            visit (spot, body.plain_text ());
        }
    }

    public class SpotEdit {
        public static bool replace (Presentation p, TextSpot m, string replacement) {
            var s = p.slides[m.slide];
            if (m.notes) {
                int bs = s.notes.index_of_nth_char (m.start), be = s.notes.index_of_nth_char (m.start + m.length);
                s.notes = s.notes.substring (0, bs) + replacement + s.notes.substring (be);
                return true;
            }
            var body = m.body;
            if (body == null) return false;
            int pos = 0;
            foreach (var par in body.paragraphs) {
                int plen = par.text ().char_count ();
                if (m.start >= pos && m.start + m.length <= pos + plen) {
                    int local = m.start - pos;
                    int acc = 0;
                    for (int ri = 0; ri < par.runs.size; ri++) {
                        var r = par.runs[ri];
                        int rl = r.text.char_count ();
                        if (local >= acc && local < acc + rl) {
                            int remaining = m.length;
                            int off = local - acc;
                            int take = int.min (rl - off, remaining);
                            int bs = r.text.index_of_nth_char (off), be = r.text.index_of_nth_char (off + take);
                            r.text = r.text.substring (0, bs) + replacement + r.text.substring (be);
                            remaining -= take;
                            int k = ri + 1;
                            while (remaining > 0 && k < par.runs.size) {
                                var nr = par.runs[k];
                                int nl = nr.text.char_count ();
                                int t2 = int.min (nl, remaining);
                                nr.text = nr.text.substring (nr.text.index_of_nth_char (t2));
                                remaining -= t2;
                                k++;
                            }
                            par.normalize ();
                            return true;
                        }
                        acc += rl;
                    }
                }
                pos += plen + 1;
            }
            return false;
        }
    }

    public class HeaderFooter {
        public static void set_meta (Presentation p, PlaceholderKind kind, bool on, string text) {
            foreach (var s in p.slides) {
                Element? existing = null;
                foreach (var e in s.elements) if (e.placeholder == kind) existing = e;
                if (!on) {
                    if (existing != null) s.elements.remove (existing);
                    continue;
                }
                if (existing == null) {
                    var layout = p.layout_for (s);
                    Element? src = layout != null ? layout.find_placeholder (kind, -1) : null;
                    if (src == null) src = p.master_for (s).find_placeholder (kind);
                    if (src == null) continue;
                    var c = (ShapeElement) src.clone ();
                    c.inherit_geometry = true;
                    c.list_style = null;
                    p.assign_ids (c);
                    double x, y, w, h;
                    p.effective_geometry (s, layout, p.master_for (s), c, out x, out y, out w, out h);
                    c.set_geometry (x, y, w, h);
                    c.text = new TextBody ();
                    var para = new Paragraph ();
                    if (kind == PlaceholderKind.SLIDE_NUMBER) para.runs.add (Factory.field_run ("slidenum", "‹#›"));
                    else if (kind == PlaceholderKind.DATE) para.runs.add (Factory.field_run ("datetime1", ""));
                    c.text.paragraphs.add (para);
                    s.elements.add (c);
                    existing = c;
                }
                if (kind == PlaceholderKind.FOOTER) ((ShapeElement) existing).text.set_plain (text);
            }
        }
    }

    public class SlideSize {
        public static void resize (Presentation p, double w, double h) {
            double sx = w / p.width, sy = h / p.height;
            double s = double.min (sx, sy);
            double ox = (w - p.width * s) / 2, oy = (h - p.height * s) / 2;
            foreach (var sl in p.slides) foreach (var e in sl.elements) scale_element (e, s, ox, oy);
            foreach (var m in p.masters) {
                foreach (var e in m.elements) scale_element (e, s, ox, oy);
                foreach (var l in m.layouts) foreach (var e in l.elements) scale_element (e, s, ox, oy);
                if (w != p.width) {
                    foreach (var e in m.elements) if (e.placeholder != PlaceholderKind.NONE || e.w >= p.width * s * 0.98) stretch (e, p.width * s, w, ox);
                    foreach (var l in m.layouts) foreach (var e in l.elements) if (e.placeholder != PlaceholderKind.NONE) stretch (e, p.width * s, w, ox);
                }
            }
            p.width = w;
            p.height = h;
            Factory.refresh_inherited (p);
        }

        private static void stretch (Element e, double old_w, double new_w, double ox) {
            double rel_x = (e.x - ox) / old_w, rel_w = e.w / old_w;
            e.scale_into (rel_x * new_w, e.y, rel_w * new_w, e.h);
        }

        private static void scale_element (Element e, double s, double ox, double oy) {
            e.scale_into (e.x * s + ox, e.y * s + oy, e.w * s, e.h * s);
            e.line.width *= s;
            var body = e.text_body ();
            if (body != null && s != 1) body.apply_to_runs ((r) => {
                if (r.size > 0) r.size = Math.round (r.size * s * 2) / 2;
            });
        }
    }
}
