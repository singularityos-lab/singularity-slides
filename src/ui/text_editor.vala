using Gtk;

namespace Singularity.Apps.Slides {

    public class TextEditor : TextView {
        public Element element;
        public TextBody source;
        public int cell_row = -1;
        public int cell_col = -1;
        private RenderContext ctx;
        private string default_color;
        private double scale;
        private double font_scale;
        private TextRun? typing = null;
        private Gee.ArrayList<TextTag> pending = new Gee.ArrayList<TextTag> ();
        private bool loading = false;
        private Paragraph last_format = new Paragraph ();
        private bool bold_default = false;
        private const double DPI = 72.0 / 96.0;

        public signal void content_changed ();
        public signal void format_changed ();

        public TextEditor () {
            add_css_class ("slides-text-editor");
            accepts_tab = false;
            top_margin = 0;
            bottom_margin = 0;
            left_margin = 0;
            right_margin = 0;
            input_hints = InputHints.SPELLCHECK;
            buffer.insert_text.connect (before_insert);
            buffer.insert_text.connect_after (after_insert);
            buffer.changed.connect (() => {
                if (!loading) content_changed ();
            });
            buffer.notify["cursor-position"].connect (() => {
                if (!loading) {
                    typing = null;
                    format_changed ();
                }
            });
        }

        public void configure (RenderContext ctx, Element element, TextBody body, double scale, string default_color, bool bold_default) {
            this.ctx = ctx;
            this.element = element;
            this.source = body;
            this.scale = scale;
            this.font_scale = body.autofit == AutoFit.SHRINK ? body.font_scale : 1;
            this.default_color = default_color;
            this.bold_default = bold_default;
            cell_row = -1;
            cell_col = -1;
            typing = null;
            wrap_mode = body.wrap ? WrapMode.WORD_CHAR : WrapMode.NONE;
            buffer.enable_undo = false;
            var dead = new Gee.ArrayList<TextTag> ();
            buffer.tag_table.foreach ((t) => {
                if (t.name != null && (t.name.has_prefix ("para|") || is_run_tag (t.name))) dead.add (t);
            });
            loading = true;
            buffer.text = "";
            loading = false;
            foreach (var t in dead) buffer.tag_table.remove (t);
            load (body);
            buffer.enable_undo = true;
        }

        public void rescale (double new_scale) {
            var current = to_body ();
            TextIter a, b;
            buffer.get_selection_bounds (out a, out b);
            int so = a.get_offset (), eo = b.get_offset ();
            var original = source;
            scale = new_scale;
            var keep_typing = typing;
            var dead = new Gee.ArrayList<TextTag> ();
            buffer.tag_table.foreach ((t) => {
                if (t.name != null && (t.name.has_prefix ("para|") || is_run_tag (t.name))) dead.add (t);
            });
            bool undo = buffer.enable_undo;
            buffer.enable_undo = false;
            loading = true;
            buffer.text = "";
            loading = false;
            foreach (var t in dead) buffer.tag_table.remove (t);
            load (current);
            source = original;
            buffer.enable_undo = undo;
            typing = keep_typing;
            TextIter na, nb;
            buffer.get_iter_at_offset (out na, so);
            buffer.get_iter_at_offset (out nb, eo);
            buffer.select_range (na, nb);
        }

        private LevelStyle level_style (Paragraph p) {
            var ls = ctx.pres.level_style (ctx.slide, ctx.layout, ctx.master, element, p.level);
            if (default_color != "") ls.color = default_color;
            if (bold_default && ls.bold < 0) ls.bold = 1;
            return ls;
        }

        private static string para_key (Paragraph p) {
            return "para|%d|%d|%d|%s|%s|%d|%d|%s|%s|%s".printf ((int) p.align, p.level, (int) p.bullet, p.bullet_char, p.bullet_color,
                (int) p.number_style, p.number_start, Num.fmt (p.space_before), Num.fmt (p.space_after), Num.fmt (p.line_spacing));
        }

        private static Paragraph parse_para (string name) {
            var p = new Paragraph ();
            string[] f = name.split ("|");
            if (f.length < 11) return p;
            p.align = (TextAlign) int.parse (f[1]);
            p.level = int.parse (f[2]);
            p.bullet = (BulletKind) int.parse (f[3]);
            p.bullet_char = f[4];
            p.bullet_color = f[5];
            p.number_style = (NumberStyle) int.parse (f[6]);
            p.number_start = int.parse (f[7]);
            p.space_before = double.parse (f[8]);
            p.space_after = double.parse (f[9]);
            p.line_spacing = double.parse (f[10]);
            return p;
        }

        private TextTag para_tag (Paragraph p) {
            string key = para_key (p);
            var table = buffer.tag_table;
            var tag = table.lookup (key);
            if (tag != null) return tag;
            tag = new TextTag (key);
            var ls = level_style (p);
            var ps = ctx.pres.para_style (ls, p, ctx.theme);
            var rs = ctx.pres.run_style (ls, new TextRun (), ctx.theme);
            tag.family = rs.font;
            tag.size_points = rs.size * scale * font_scale * DPI;
            tag.weight = rs.bold ? 700 : 400;
            tag.style = rs.italic ? Pango.Style.ITALIC : Pango.Style.NORMAL;
            tag.foreground_rgba = rgba (rs.color);
            switch (ps.align) {
                case TextAlign.CENTER: tag.justification = Justification.CENTER; break;
                case TextAlign.RIGHT: tag.justification = Justification.RIGHT; break;
                case TextAlign.JUSTIFY: tag.justification = Justification.FILL; break;
                default: tag.justification = Justification.LEFT; break;
            }
            double margin = ps.margin;
            double indent = ps.indent;
            if (ps.bullet != BulletKind.NONE) {
                var bl = new Pango.Layout (Renderer.context ());
                bl.set_font_description (Renderer.font_for (rs, font_scale));
                bl.set_text (bullet_text (ps, p, 1) + " ", -1);
                int bw, bh;
                bl.get_size (out bw, out bh);
                double bullet_end = margin + indent + bw / (double) Pango.SCALE;
                tag.left_margin = (int) Math.round (margin * scale);
                tag.indent = bullet_end > margin ? (int) Math.round ((bullet_end - margin) * scale) : 0;
            } else {
                tag.left_margin = (int) Math.round (margin * scale);
                tag.indent = (int) Math.round (indent * scale);
            }
            tag.pixels_above_lines = (int) Math.round (ps.space_before * scale * font_scale);
            tag.pixels_below_lines = (int) Math.round (ps.space_after * scale * font_scale);
            double lsp = ps.line_spacing * (1 - source.line_reduction);
            if (Math.fabs (lsp - 1) > 0.001) tag.line_height = (float) lsp;
            table.add (tag);
            tag.set_priority (0);
            return tag;
        }

        private static string bullet_text (ParaStyle ps, Paragraph p, int n) {
            if (ps.bullet == BulletKind.NUMBER) return p.number_style.label (p.number_start - 1 + n);
            return ps.bullet_char;
        }

        private static Gdk.RGBA rgba (Rgba c) {
            var g = Gdk.RGBA ();
            g.red = (float) c.r;
            g.green = (float) c.g;
            g.blue = (float) c.b;
            g.alpha = (float) c.a;
            return g;
        }

        private TextTag? run_tag (string key) {
            var table = buffer.tag_table;
            var tag = table.lookup (key);
            if (tag != null) return tag;
            tag = new TextTag (key);
            int colon = key.index_of (":");
            string kind = key.substring (0, colon);
            string val = key.substring (colon + 1);
            switch (kind) {
                case "b":
                    tag.weight = val == "1" ? 700 : 400;
                    break;
                case "i":
                    tag.style = val == "1" ? Pango.Style.ITALIC : Pango.Style.NORMAL;
                    break;
                case "u":
                    tag.underline = val == "1" ? Pango.Underline.SINGLE : Pango.Underline.NONE;
                    break;
                case "s":
                    tag.strikethrough = val == "1";
                    break;
                case "size":
                    tag.size_points = double.parse (val) * scale * font_scale * DPI;
                    break;
                case "font":
                    tag.family = ctx.theme.resolve_font (val);
                    break;
                case "color":
                    tag.foreground_rgba = rgba (ctx.theme.resolve (val));
                    break;
                case "hl":
                    tag.background_rgba = rgba (ctx.theme.resolve (val));
                    break;
                case "base":
                    int b = int.parse (val);
                    tag.rise = (int) (b > 0 ? 8 * scale * Pango.SCALE : -3 * scale * Pango.SCALE);
                    tag.scale = 0.66;
                    break;
                case "link":
                    tag.underline = Pango.Underline.SINGLE;
                    tag.foreground_rgba = rgba (ctx.theme.resolve ("hlink"));
                    break;
                case "field":
                    tag.background_rgba = rgba (Rgba (0.5, 0.5, 0.5, 0.18));
                    break;
                default:
                    return null;
            }
            table.add (tag);
            return tag;
        }

        private static string[] run_keys (TextRun r) {
            string[] keys = {};
            if (r.bold >= 0) keys += "b:%d".printf (r.bold);
            if (r.italic >= 0) keys += "i:%d".printf (r.italic);
            if (r.underline >= 0) keys += "u:%d".printf (r.underline);
            if (r.strike >= 0) keys += "s:%d".printf (r.strike);
            if (r.size > 0) keys += "size:" + Num.fmt (r.size);
            if (r.font != "") keys += "font:" + r.font;
            if (r.color != "") keys += "color:" + r.color;
            if (r.highlight != "") keys += "hl:" + r.highlight;
            if (r.baseline != 0) keys += "base:%d".printf (r.baseline);
            if (r.link != "") keys += "link:" + r.link;
            if (r.field != "") keys += "field:" + r.field;
            return keys;
        }

        private static bool is_run_tag (string? name) {
            if (name == null) return false;
            foreach (string p in new string[] { "b:", "i:", "u:", "s:", "size:", "font:", "color:", "hl:", "base:", "link:", "field:" }) {
                if (name.has_prefix (p)) return true;
            }
            return false;
        }

        private static void apply_key (TextRun r, string name) {
            int colon = name.index_of (":");
            string kind = name.substring (0, colon);
            string val = name.substring (colon + 1);
            switch (kind) {
                case "b": r.bold = int.parse (val); break;
                case "i": r.italic = int.parse (val); break;
                case "u": r.underline = int.parse (val); break;
                case "s": r.strike = int.parse (val); break;
                case "size": r.size = double.parse (val); break;
                case "font": r.font = val; break;
                case "color": r.color = val; break;
                case "hl": r.highlight = val; break;
                case "base": r.baseline = int.parse (val); break;
                case "link": r.link = val; break;
                case "field": r.field = val; break;
            }
        }

        private void insert_run (ref TextIter it, string text, TextRun r, TextTag ptag) {
            int start_off = it.get_offset ();
            buffer.insert (ref it, text, -1);
            TextIter s;
            buffer.get_iter_at_offset (out s, start_off);
            buffer.apply_tag (ptag, s, it);
            foreach (string k in run_keys (r)) {
                var t = run_tag (k);
                if (t != null) buffer.apply_tag (t, s, it);
            }
        }

        public void load (TextBody body) {
            loading = true;
            buffer.text = "";
            TextIter it;
            buffer.get_end_iter (out it);
            for (int i = 0; i < body.paragraphs.size; i++) {
                var p = body.paragraphs[i];
                var ptag = para_tag (p);
                foreach (var r in p.runs) {
                    string text = r.field != "" ? new Renderer ().field_text (ctx, r) : r.text.replace ("\v", " ").replace ("\n", " ");
                    if (text == "") continue;
                    insert_run (ref it, text, r, ptag);
                }
                if (i < body.paragraphs.size - 1) {
                    insert_run (ref it, "\n", p.end_format, ptag);
                } else {
                    last_format = p.clone ();
                    last_format.runs.clear ();
                }
            }
            if (body.paragraphs.size > 0) {
                var lp = body.paragraphs[body.paragraphs.size - 1];
                if (lp.text () == "") typing = lp.end_format.clone ();
            }
            loading = false;
        }

        private Paragraph para_at (TextIter line_start) {
            foreach (var t in line_start.get_tags ()) {
                if (t.name != null && t.name.has_prefix ("para|")) return parse_para (t.name);
            }
            if (line_start.is_end ()) return last_format.clone ();
            var prev = line_start;
            if (prev.backward_char ()) {
                foreach (var t in prev.get_tags ()) {
                    if (t.name != null && t.name.has_prefix ("para|")) return parse_para (t.name);
                }
            }
            return last_format.clone ();
        }

        public TextBody to_body () {
            var body = source.clone ();
            body.paragraphs.clear ();
            int lines = buffer.get_line_count ();
            for (int ln = 0; ln < lines; ln++) {
                TextIter start, end;
                buffer.get_iter_at_line (out start, ln);
                end = start;
                if (!end.ends_line ()) end.forward_to_line_end ();
                var p = para_at (start);
                var seg = start;
                while (seg.compare (end) < 0) {
                    var next = seg;
                    next.forward_to_tag_toggle (null);
                    if (next.compare (end) > 0 || next.compare (seg) <= 0) next = end;
                    var r = new TextRun ();
                    foreach (var t in seg.get_tags ()) if (is_run_tag (t.name)) apply_key (r, t.name);
                    r.text = seg.get_text (next).replace (" ", "\v");
                    if (r.field == "slidenum") r.text = "‹#›";
                    p.runs.add (r);
                    seg = next;
                }
                var endfmt = new TextRun ();
                var probe = end;
                if (!probe.is_end ()) {
                    foreach (var t in probe.get_tags ()) if (is_run_tag (t.name)) apply_key (endfmt, t.name);
                } else if (p.runs.size > 0) {
                    endfmt.copy_format (p.runs[p.runs.size - 1]);
                } else if (typing != null) {
                    endfmt.copy_format (typing);
                }
                endfmt.field = "";
                p.end_format = endfmt;
                p.normalize ();
                body.paragraphs.add (p);
            }
            if (body.paragraphs.size == 0) body.paragraphs.add (new Paragraph ());
            return body;
        }

        private void before_insert (ref TextIter pos, string text, int len) {
            pending.clear ();
            if (loading) return;
            if (typing != null) {
                foreach (string k in run_keys (typing)) {
                    var t = run_tag (k);
                    if (t != null) pending.add (t);
                }
                var ln = pos;
                ln.set_line_offset (0);
                pending.add (para_tag (para_at (ln)));
                return;
            }
            var probe = pos;
            bool use_prev = !pos.starts_line () && probe.backward_char ();
            if (!use_prev) probe = pos;
            foreach (var t in probe.get_tags ()) {
                if (t.name == null) continue;
                if (t.name.has_prefix ("para|") || (is_run_tag (t.name) && !t.name.has_prefix ("field:") && !t.name.has_prefix ("link:"))) pending.add (t);
            }
            bool has_para = false;
            foreach (var t in pending) if (t.name.has_prefix ("para|")) has_para = true;
            if (!has_para) {
                var ln = pos;
                ln.set_line_offset (0);
                pending.add (para_tag (para_at (ln)));
            }
        }

        private void after_insert (ref TextIter pos, string text, int len) {
            if (!loading && text.contains ("\n") && pos.is_end ()) {
                var prev = pos;
                prev.backward_char ();
                prev.set_line_offset (0);
                last_format = para_at (prev);
                last_format.runs.clear ();
            }
            if (loading || pending.size == 0) return;
            var start = pos;
            start.backward_chars (text.char_count ());
            foreach (var t in start.get_tags ()) {
                if (t.name != null && (is_run_tag (t.name) || t.name.has_prefix ("para|"))) buffer.remove_tag (t, start, pos);
            }
            foreach (var t in pending) buffer.apply_tag (t, start, pos);
        }

        public bool has_selection () {
            TextIter a, b;
            return buffer.get_selection_bounds (out a, out b);
        }

        public TextRun current_format () {
            var r = new TextRun ();
            if (typing != null && !has_selection ()) {
                r.copy_format (typing);
                return r;
            }
            TextIter it;
            TextIter a, b;
            if (buffer.get_selection_bounds (out a, out b)) it = a;
            else {
                buffer.get_iter_at_mark (out it, buffer.get_insert ());
                if (!it.starts_line ()) it.backward_char ();
            }
            foreach (var t in it.get_tags ()) if (is_run_tag (t.name)) apply_key (r, t.name);
            return r;
        }

        public Paragraph current_paragraph () {
            TextIter it;
            buffer.get_iter_at_mark (out it, buffer.get_insert ());
            it.set_line_offset (0);
            return para_at (it);
        }

        public RunStyle current_style () {
            var p = current_paragraph ();
            var ls = level_style (p);
            return ctx.pres.run_style (ls, current_format (), ctx.theme);
        }

        public void apply_run (RunEdit edit) {
            TextIter a, b;
            if (!buffer.get_selection_bounds (out a, out b)) {
                var t = current_format ();
                edit (t);
                typing = t;
                format_changed ();
                return;
            }
            int so = a.get_offset (), eo = b.get_offset ();
            var runs = new Gee.ArrayList<TextRun> ();
            var offsets = new Gee.ArrayList<int> ();
            var seg = a;
            while (seg.get_offset () < eo) {
                var next = seg;
                next.forward_to_tag_toggle (null);
                if (next.get_offset () > eo || next.compare (seg) <= 0) buffer.get_iter_at_offset (out next, eo);
                var r = new TextRun ();
                foreach (var t in seg.get_tags ()) if (is_run_tag (t.name)) apply_key (r, t.name);
                edit (r);
                runs.add (r);
                offsets.add (seg.get_offset ());
                seg = next;
            }
            offsets.add (eo);
            loading = true;
            for (int i = 0; i < runs.size; i++) {
                TextIter s, e;
                buffer.get_iter_at_offset (out s, offsets[i]);
                buffer.get_iter_at_offset (out e, offsets[i + 1]);
                var remove = new Gee.ArrayList<TextTag> ();
                var probe = s;
                while (probe.compare (e) < 0) {
                    foreach (var t in probe.get_tags ()) if (is_run_tag (t.name) && !remove.contains (t)) remove.add (t);
                    if (!probe.forward_to_tag_toggle (null)) break;
                }
                foreach (var t in remove) buffer.remove_tag (t, s, e);
                foreach (string k in run_keys (runs[i])) {
                    var t = run_tag (k);
                    if (t != null) buffer.apply_tag (t, s, e);
                }
            }
            loading = false;
            TextIter ns, ne;
            buffer.get_iter_at_offset (out ns, so);
            buffer.get_iter_at_offset (out ne, eo);
            buffer.select_range (ns, ne);
            content_changed ();
            format_changed ();
        }

        public void apply_paragraph (ParagraphEdit edit) {
            TextIter a, b;
            if (!buffer.get_selection_bounds (out a, out b)) {
                buffer.get_iter_at_mark (out a, buffer.get_insert ());
                b = a;
            }
            int first = a.get_line (), last = b.get_line ();
            loading = true;
            for (int ln = first; ln <= last; ln++) {
                TextIter s, e;
                buffer.get_iter_at_line (out s, ln);
                var p = para_at (s);
                edit (p);
                e = s;
                e.forward_line ();
                if (e.compare (s) == 0 || (ln == buffer.get_line_count () - 1)) buffer.get_end_iter (out e);
                var remove = new Gee.ArrayList<TextTag> ();
                var probe = s;
                while (probe.compare (e) < 0) {
                    foreach (var t in probe.get_tags ()) if (t.name != null && t.name.has_prefix ("para|") && !remove.contains (t)) remove.add (t);
                    if (!probe.forward_to_tag_toggle (null)) break;
                }
                foreach (var t in remove) buffer.remove_tag (t, s, e);
                var tag = para_tag (p);
                buffer.apply_tag (tag, s, e);
                if (ln == buffer.get_line_count () - 1) {
                    last_format = p.clone ();
                    last_format.runs.clear ();
                }
            }
            loading = false;
            content_changed ();
            format_changed ();
            queue_draw ();
        }

        public void insert_field (string field) {
            var r = current_format ();
            r.field = field;
            TextIter it;
            buffer.delete_selection (true, true);
            buffer.get_iter_at_mark (out it, buffer.get_insert ());
            var ln = it;
            ln.set_line_offset (0);
            var ptag = para_tag (para_at (ln));
            loading = true;
            var probe = new TextRun ();
            probe.field = field;
            string text = field == "slidenum" ? ctx.number.to_string () : new Renderer ().field_text (ctx, probe);
            insert_run (ref it, text, r, ptag);
            loading = false;
            buffer.place_cursor (it);
            content_changed ();
        }

        public void set_link (string url) {
            apply_run ((r) => r.link = url);
        }

        public void select_offsets (int start, int end) {
            TextIter a, b;
            buffer.get_iter_at_offset (out a, start);
            buffer.get_iter_at_offset (out b, end);
            buffer.select_range (a, b);
        }

        public static int offset_in_body (TextBody body, int paragraph, int index) {
            int off = 0;
            for (int i = 0; i < paragraph && i < body.paragraphs.size; i++) off += body.paragraphs[i].text ().char_count () + 1;
            return off + index;
        }

        public override void snapshot_layer (TextViewLayer layer, Snapshot snapshot) {
            if (layer != TextViewLayer.BELOW_TEXT) return;
            int lines = buffer.get_line_count ();
            int[] counters = new int[9];
            int prev_level = -1;
            for (int ln = 0; ln < lines; ln++) {
                TextIter it;
                buffer.get_iter_at_line (out it, ln);
                var p = para_at (it);
                var ls = level_style (p);
                var ps = ctx.pres.para_style (ls, p, ctx.theme);
                var end = it;
                if (!end.ends_line ()) end.forward_to_line_end ();
                bool empty = it.equal (end);
                string bullet = "";
                if (ps.bullet == BulletKind.CHAR && !empty) bullet = ps.bullet_char;
                if (ps.bullet == BulletKind.NUMBER && !empty) {
                    int lv = p.level.clamp (0, 8);
                    if (prev_level < 0 || prev_level < lv) counters[lv] = 0;
                    for (int k = lv + 1; k < 9; k++) counters[k] = 0;
                    counters[lv]++;
                    bullet = p.number_style.label (p.number_start - 1 + counters[lv]);
                } else if (!empty) {
                    counters[p.level.clamp (0, 8)] = 0;
                }
                prev_level = p.level;
                if (bullet == "") continue;
                var r = new TextRun ();
                foreach (var t in it.get_tags ()) if (is_run_tag (t.name)) apply_key (r, t.name);
                var rs = ctx.pres.run_style (ls, r, ctx.theme);
                int line_y, line_h;
                get_line_yrange (it, out line_y, out line_h);
                var fd = Renderer.font_for (rs, scale * font_scale * DPI);
                var layout = create_pango_layout (bullet);
                layout.set_font_description (fd);
                var probe_layout = create_pango_layout ("X");
                probe_layout.set_font_description (fd);
                var col = ps.bullet_color != "" ? ctx.theme.resolve (ps.bullet_color) : rs.color;
                int above = (int) Math.round (ps.space_before * scale * font_scale);
                double baseline = line_y + above + probe_layout.get_baseline () / (double) Pango.SCALE;
                double bx = (ps.margin + ps.indent) * scale;
                snapshot.save ();
                var point = Graphene.Point ();
                point.init ((float) bx, (float) (baseline - layout.get_baseline () / (double) Pango.SCALE));
                snapshot.translate (point);
                snapshot.append_layout (layout, rgba (col));
                snapshot.restore ();
            }
        }
    }
}
