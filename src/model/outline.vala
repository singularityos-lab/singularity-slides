namespace Singularity.Apps.Slides {

    public class OutlineItem {
        public int slide;
        public int level;
        public string text;
        public Element? element;
        public int paragraph;

        public OutlineItem (int slide, int level, string text, Element? element, int paragraph) {
            this.slide = slide;
            this.level = level;
            this.text = text;
            this.element = element;
            this.paragraph = paragraph;
        }
    }

    public class DeckOutline {
        public static Element? body_of (Slide s) {
            foreach (var e in s.elements) {
                if (e.placeholder == PlaceholderKind.BODY || e.placeholder == PlaceholderKind.OBJECT || e.placeholder == PlaceholderKind.SUBTITLE) return e;
            }
            return null;
        }

        public static Gee.ArrayList<OutlineItem> items (Presentation p) {
            var list = new Gee.ArrayList<OutlineItem> ();
            for (int i = 0; i < p.slides.size; i++) {
                var s = p.slides[i];
                var t = s.placeholder (PlaceholderKind.TITLE);
                list.add (new OutlineItem (i, 0, s.title (), t, 0));
                var b = body_of (s);
                if (b == null || b.text_body () == null) continue;
                var body = b.text_body ();
                for (int k = 0; k < body.paragraphs.size; k++) {
                    string text = body.paragraphs[k].text ().replace ("\v", " ").strip ();
                    if (text == "" && body.paragraphs.size == 1) continue;
                    list.add (new OutlineItem (i, body.paragraphs[k].level + 1, text, b, k));
                }
            }
            return list;
        }

        public static string to_text (Presentation p) {
            var sb = new StringBuilder ();
            foreach (var it in items (p)) {
                for (int i = 0; i < it.level; i++) sb.append ("\t");
                sb.append (it.text);
                sb.append ("\n");
            }
            return sb.str;
        }

        private static string rtf_escape (string s) {
            var sb = new StringBuilder ();
            unichar c;
            int i = 0;
            while (s.get_next_char (ref i, out c)) {
                if (c == '\\' || c == '{' || c == '}') {
                    sb.append_c ('\\');
                    sb.append_unichar (c);
                } else if (c < 128) {
                    sb.append_unichar (c);
                } else if (c < 0x10000) {
                    int v = (int) c;
                    if (v > 32767) v -= 65536;
                    sb.append ("\\u%d?".printf (v));
                } else {
                    int u = (int) c - 0x10000;
                    int hi = 0xD800 + (u >> 10), lo = 0xDC00 + (u & 0x3FF);
                    sb.append ("\\u%d?\\u%d?".printf (hi - 65536, lo - 65536));
                }
            }
            return sb.str;
        }

        public static string to_rtf (Presentation p) {
            var sb = new StringBuilder ();
            sb.append ("{\\rtf1\\ansi\\ansicpg1252\\deff0{\\fonttbl{\\f0\\fswiss ");
            sb.append (rtf_escape (p.theme.minor_font));
            sb.append (";}}\n");
            foreach (var it in items (p)) {
                if (it.level == 0) {
                    sb.append ("\\pard\\sb240\\sa60\\b\\fs32 ");
                    sb.append (rtf_escape (it.text != "" ? it.text : _("Slide %d").printf (it.slide + 1)));
                    sb.append ("\\b0\\par\n");
                } else {
                    sb.append ("\\pard\\li%d\\fi-240\\sa40\\fs24 \\bullet\\tab ".printf (360 * it.level));
                    sb.append (rtf_escape (it.text));
                    sb.append ("\\par\n");
                }
            }
            sb.append ("}\n");
            return sb.str;
        }

        public static void apply (Presentation p, string text) {
            var titles = new Gee.ArrayList<string> ();
            var bodies = new Gee.ArrayList<Gee.ArrayList<OutlineItem>> ();
            var lines = text.replace ("\r", "").split ("\n");
            int count = lines.length;
            if (count > 0 && lines[count - 1] == "") count--;
            for (int li = 0; li < count; li++) {
                string line = lines[li];
                if (line.strip () == "" && line.has_prefix ("\t")) continue;
                int level = 0;
                while (level < line.length && line[level] == '\t') level++;
                string content = line.substring (level).strip ();
                if (level == 0 || titles.size == 0) {
                    titles.add (content);
                    bodies.add (new Gee.ArrayList<OutlineItem> ());
                    continue;
                }
                bodies[bodies.size - 1].add (new OutlineItem (titles.size - 1, level, content, null, 0));
            }
            var master = p.master;
            var layout = master.layout_of_kind (LayoutKind.TITLE_CONTENT) ?? (master.layouts.size > 0 ? master.layouts[0] : null);
            for (int i = 0; i < titles.size; i++) {
                Slide s = i < p.slides.size ? p.slides[i] : Factory.add_slide (p, layout, i);
                var t = s.placeholder (PlaceholderKind.TITLE);
                if (t != null && t.text_body () != null && s.title () != titles[i]) t.text_body ().set_plain (titles[i]);
                var b = body_of (s);
                if (b == null || b.text_body () == null) continue;
                var body = b.text_body ();
                var cur = new StringBuilder ();
                foreach (var para in body.paragraphs) {
                    string pt = para.text ().replace ("\v", " ").strip ();
                    if (pt == "" && body.paragraphs.size == 1) continue;
                    cur.append ("%d:%s\n".printf (para.level + 1, pt));
                }
                var want = new StringBuilder ();
                foreach (var it in bodies[i]) want.append ("%d:%s\n".printf (it.level, it.text));
                if (cur.str == want.str) continue;
                var old = new Gee.ArrayList<Paragraph> ();
                old.add_all (body.paragraphs);
                body.paragraphs.clear ();
                for (int k = 0; k < bodies[i].size; k++) {
                    var it = bodies[i][k];
                    Paragraph para;
                    if (k < old.size && old[k].text ().replace ("\v", " ").strip () == it.text) {
                        para = old[k];
                    } else {
                        para = new Paragraph (it.text);
                        if (k < old.size) {
                            para.copy_format (old[k]);
                            if (old[k].runs.size > 0) {
                                var r = old[k].runs[0].clone ();
                                r.text = it.text;
                                para.runs.clear ();
                                para.runs.add (r);
                            }
                        }
                    }
                    para.level = (it.level - 1).clamp (0, 8);
                    body.paragraphs.add (para);
                }
                if (body.paragraphs.size == 0) body.paragraphs.add (new Paragraph (""));
            }
            while (p.slides.size > titles.size && p.slides.size > 1) p.slides.remove_at (p.slides.size - 1);
        }

        public static Presentation from_text (string text, Presentation template) {
            var p = template.clone ();
            p.slides.clear ();
            var master = p.master;
            var title_layout = master.layout_of_kind (LayoutKind.TITLE_CONTENT) ?? (master.layouts.size > 0 ? master.layouts[0] : null);
            Slide? cur = null;
            foreach (string raw in text.split ("\n")) {
                string line = raw.replace ("\r", "");
                if (line.strip () == "") continue;
                int level = 0;
                while (level < line.length && line[level] == '\t') level++;
                string content = line.substring (level).strip ();
                if (level == 0 || cur == null) {
                    cur = Factory.add_slide (p, title_layout, p.slides.size);
                    var t = cur.placeholder (PlaceholderKind.TITLE);
                    if (t != null && t.text_body () != null) t.text_body ().set_plain (content);
                    continue;
                }
                var b = body_of (cur);
                if (b == null || b.text_body () == null) continue;
                var body = b.text_body ();
                if (body.is_empty ()) body.paragraphs.clear ();
                var para = new Paragraph (content);
                para.level = (level - 1).clamp (0, 8);
                body.paragraphs.add (para);
            }
            if (p.slides.size == 0) Factory.add_slide (p, title_layout, 0);
            return p;
        }
    }
}
