namespace Singularity.Apps.Slides {

    public class AccessibilityCheck {
        public enum Kind {
            ALT_TEXT,
            NO_TITLE,
            DUPLICATE_TITLE,
            CONTRAST,
            TABLE_HEADER,
            MEDIA_CAPTIONS,
            LINK_TEXT,
            READING_ORDER
        }

        public class Issue {
            public Kind kind;
            public int severity;
            public int slide;
            public Element? element;
            public string title;
            public string detail;

            public Issue (Kind kind, int severity, int slide, Element? element, string title, string detail) {
                this.kind = kind;
                this.severity = severity;
                this.slide = slide;
                this.element = element;
                this.title = title;
                this.detail = detail;
            }
        }

        public static double contrast (Rgba a, Rgba b) {
            double la = rel (a), lb = rel (b);
            double hi = double.max (la, lb), lo = double.min (la, lb);
            return (hi + 0.05) / (lo + 0.05);
        }

        private static double chan (double c) {
            return c <= 0.03928 ? c / 12.92 : Math.pow ((c + 0.055) / 1.055, 2.4);
        }

        private static double rel (Rgba c) {
            return 0.2126 * chan (c.r) + 0.7152 * chan (c.g) + 0.0722 * chan (c.b);
        }

        private static bool needs_alt (Element e) {
            if (e.placeholder != PlaceholderKind.NONE) return false;
            if (e is ImageElement || e is ChartElement || e is MediaElement || e is DiagramElement || e is EquationElement || e is ZoomElement) return true;
            if (e is GroupElement) return true;
            var s = e as ShapeElement;
            if (s != null && (s.text == null || s.text.is_empty ()) && s.fill.kind == FillKind.IMAGE) return true;
            return false;
        }

        public static Gee.ArrayList<Issue> run (Presentation p) {
            var list = new Gee.ArrayList<Issue> ();
            var titles = new Gee.HashMap<string, int> ();
            for (int i = 0; i < p.slides.size; i++) {
                var s = p.slides[i];
                string t = s.title ().strip ();
                if (t == "") {
                    list.add (new Issue (Kind.NO_TITLE, 0, i, null, _("Missing Slide Title"), _("Give every slide a unique title")));
                } else if (titles.has_key (t.down ())) {
                    list.add (new Issue (Kind.DUPLICATE_TITLE, 1, i, s.placeholder (PlaceholderKind.TITLE), _("Duplicate Slide Title"), _("Same title as slide %d").printf (titles[t.down ()] + 1)));
                } else {
                    titles[t.down ()] = i;
                }
                var master = p.master_for (s);
                var layout = p.layout_for (s);
                Rgba bg = p.theme.resolve ("lt1");
                var bf = p.background_for (s);
                if (bf.kind == FillKind.SOLID) bg = master.theme.resolve (bf.color);
                foreach (var e in s.elements) {
                    if (needs_alt (e) && e.description.strip () == "") {
                        list.add (new Issue (Kind.ALT_TEXT, 0, i, e, _("Missing Alternative Text"), e.display_name ()));
                    }
                    var tb = e as TableElement;
                    if (tb != null && !tb.first_row) list.add (new Issue (Kind.TABLE_HEADER, 0, i, e, _("No Header Row"), _("Mark the first row of the table as a header")));
                    var m = e as MediaElement;
                    if (m != null && m.is_video) list.add (new Issue (Kind.MEDIA_CAPTIONS, 2, i, e, _("Check Video Captions"), _("Make sure the video includes captions")));
                    var sh = e as ShapeElement;
                    if (sh == null || sh.text == null || sh.text.is_empty ()) continue;
                    Rgba back = bg;
                    if (sh.fill.kind == FillKind.SOLID) back = master.theme.resolve (sh.fill.color);
                    bool low = false, vague = false;
                    foreach (var para in sh.text.paragraphs) {
                        var ls = p.level_style (s, layout, master, e, para.level);
                        foreach (var r in para.runs) {
                            if (r.text.strip () == "") continue;
                            var rs = p.run_style (ls, r, master.theme);
                            double need = rs.size >= 18 || (rs.bold && rs.size >= 14) ? 3.0 : 4.5;
                            if (rs.color.a > 0.5 && contrast (rs.color, back) < need) low = true;
                            if (r.link != "") {
                                string lt = r.text.strip ().down ();
                                if (lt == "click here" || lt == "here" || lt == "link" || lt == "more" || lt.has_prefix ("http")) vague = true;
                            }
                        }
                    }
                    if (low) list.add (new Issue (Kind.CONTRAST, 1, i, e, _("Hard-to-Read Text Contrast"), e.display_name ()));
                    if (vague) list.add (new Issue (Kind.LINK_TEXT, 1, i, e, _("Unclear Hyperlink Text"), _("Use link text that describes the destination")));
                }
            }
            return list;
        }
    }
}
