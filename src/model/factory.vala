namespace Singularity.Apps.Slides {

    public class Factory {

        private static ShapeElement placeholder (PlaceholderKind k, int idx, double x, double y, double w, double h) {
            var s = new ShapeElement (ShapeKind.RECT);
            s.placeholder = k;
            s.placeholder_idx = idx;
            s.set_geometry (x, y, w, h);
            s.text = new TextBody ();
            s.text.paragraphs.add (new Paragraph ());
            string label = "Content";
            if (k.is_title ()) label = "Title";
            else if (k == PlaceholderKind.SUBTITLE) label = "Subtitle";
            else if (k.is_meta ()) label = k.to_ooxml ();
            s.name = label;
            return s;
        }

        private static LevelStyle level (TextStyle ts, int i) {
            return ts.levels[i];
        }

        private static TextStyle single_level (TextAlign align, BulletKind bullet, double size = 0) {
            var ts = new TextStyle ();
            var l = ts.levels[0];
            l.align = align;
            l.bullet = bullet;
            if (bullet == BulletKind.NONE) {
                l.margin = 0;
                l.indent = 0;
            }
            if (size > 0) l.size = size;
            return ts;
        }

        public static bool is_dark (Theme t, string bg) {
            return t.resolve (bg).luminance () < 0.5;
        }

        public static Master build_master (ThemePreset preset, double W, double H) {
            var m = new Master ();
            m.id = "master1";
            m.name = preset.name;
            m.theme = preset.build ();
            if (preset.background2 != "") m.background = new Fill.gradient (preset.background, preset.background2, 90);
            else m.background = new Fill.solid (preset.background);
            bool dark = is_dark (m.theme, preset.background);
            string text = dark ? "lt1" : "dk1";
            string title_color = dark ? "lt1" : "dk2";
            double k = H / 540;

            var ts = m.title_style.levels[0];
            ts.size = Math.round (44 * k);
            ts.font = "+mj-lt";
            ts.color = title_color;
            ts.bold = preset.major == "Georgia" ? 0 : 1;
            ts.align = TextAlign.LEFT;
            ts.line_spacing = 0.9;
            ts.bullet = BulletKind.NONE;
            ts.margin = 0;
            ts.indent = 0;

            string dash = ((unichar) 0x2013).to_string ();
            string[] chars = { "•", dash, "•", dash, "•", dash, "•", dash, "•" };
            double[] sizes = { 28, 24, 20, 18, 18, 18, 18, 18, 18 };
            for (int i = 0; i < 9; i++) {
                var l = level (m.body_style, i);
                l.size = Math.round (sizes[i] * k);
                l.font = "+mn-lt";
                l.color = text;
                l.bullet = BulletKind.CHAR;
                l.bullet_char = chars[i];
                l.margin = 24 + 36 * i;
                l.indent = -24;
                l.space_before = 8 * k;
                l.line_spacing = 1.0;
                l.align = TextAlign.LEFT;
                var o = level (m.other_style, i);
                o.size = Math.round (18 * k);
                o.font = "+mn-lt";
                o.color = text;
                o.margin = 0;
                o.indent = 0;
            }

            double mx = 60 * W / 960;
            var title = placeholder (PlaceholderKind.TITLE, -1, mx, 30 * k, W - 2 * mx, 90 * k);
            title.text.anchor = TextAnchor.MIDDLE;
            title.text.anchor_set = true;
            m.elements.add (title);
            var body = placeholder (PlaceholderKind.BODY, 1, mx, 140 * k, W - 2 * mx, H - 200 * k);
            body.text.anchor = TextAnchor.TOP;
            body.text.anchor_set = true;
            m.elements.add (body);
            var dt = placeholder (PlaceholderKind.DATE, 10, mx, H - 44 * k, 200 * k, 28 * k);
            dt.list_style = single_level (TextAlign.LEFT, BulletKind.NONE, Math.round (11 * k));
            dt.list_style.levels[0].color = ColorSpec.with_alpha (text, 0.6);
            m.elements.add (dt);
            var ftr = placeholder (PlaceholderKind.FOOTER, 11, W / 2 - 200 * k, H - 44 * k, 400 * k, 28 * k);
            ftr.list_style = single_level (TextAlign.CENTER, BulletKind.NONE, Math.round (11 * k));
            ftr.list_style.levels[0].color = ColorSpec.with_alpha (text, 0.6);
            m.elements.add (ftr);
            var num = placeholder (PlaceholderKind.SLIDE_NUMBER, 12, W - mx - 120 * k, H - 44 * k, 120 * k, 28 * k);
            num.list_style = single_level (TextAlign.RIGHT, BulletKind.NONE, Math.round (11 * k));
            num.list_style.levels[0].color = ColorSpec.with_alpha (text, 0.6);
            num.text.paragraphs[0].runs.add (field_run ("slidenum", "‹#›"));
            m.elements.add (num);

            add_decoration (m, preset.decoration, W, H);
            build_layouts (m, W, H, dark, preset.background.has_prefix ("accent1") ? "lt1" : "accent1");
            return m;
        }

        public static TextRun field_run (string field, string text) {
            var r = new TextRun (text);
            r.field = field;
            return r;
        }

        private static ShapeElement deco (ShapeKind kind, double x, double y, double w, double h, string color) {
            var s = new ShapeElement (kind);
            s.set_geometry (x, y, w, h);
            s.fill = new Fill.solid (color);
            s.name = "Decoration";
            return s;
        }

        private static void add_decoration (Master m, int style, double W, double H) {
            switch (style) {
                case 1:
                    var glow = deco (ShapeKind.ELLIPSE, W * 0.62, -H * 0.55, W * 0.7, W * 0.7, "accent1@0.18");
                    glow.fill = new Fill.gradient ("accent1@0.35", "accent1@0", 0, true);
                    m.elements.add (glow);
                    break;
                case 2:
                    m.elements.add (deco (ShapeKind.RECT, 0, 0, W * 0.018, H, "accent1"));
                    break;
                case 3:
                    m.elements.add (deco (ShapeKind.RECT, 0, H - H * 0.035, W, H * 0.035, "accent1"));
                    m.elements.add (deco (ShapeKind.RECT, 0, H - H * 0.035, W * 0.3, H * 0.035, "accent2"));
                    break;
                case 4:
                    m.elements.add (deco (ShapeKind.RECT, W * 0.0625, H * 0.04, W * 0.08, H * 0.008, "accent1"));
                    break;
                case 5:
                    m.elements.add (deco (ShapeKind.RECT, W * 0.0625, H * 0.9, W * 0.875, 1, "dk1@0.35"));
                    break;
                case 6:
                    m.elements.add (deco (ShapeKind.ELLIPSE, -W * 0.12, H * 0.55, W * 0.4, W * 0.4, "lt1@0.08"));
                    m.elements.add (deco (ShapeKind.ELLIPSE, W * 0.78, -H * 0.2, W * 0.32, W * 0.32, "lt1@0.1"));
                    break;
                case 7:
                    m.elements.add (deco (ShapeKind.RECT, W * 0.0625, H * 0.235, W * 0.05, H * 0.008, "dk1"));
                    break;
                default:
                    break;
            }
        }

        private static Layout layout (Master m, string name, LayoutKind kind) {
            var l = new Layout ();
            l.id = "layout%d".printf (m.layouts.size + 1);
            l.name = name;
            l.kind = kind;
            m.layouts.add (l);
            return l;
        }

        private static void add_meta (Master m, Layout l) {
            foreach (var e in m.elements) {
                if (!e.placeholder.is_meta ()) continue;
                var c = (ShapeElement) e.clone ();
                c.inherit_geometry = true;
                c.list_style = null;
                l.elements.add (c);
            }
        }

        private static ShapeElement title_of (Master m) {
            var t = (ShapeElement) m.find_placeholder (PlaceholderKind.TITLE).clone ();
            t.inherit_geometry = true;
            t.text = new TextBody ();
            t.text.paragraphs.add (new Paragraph ());
            return t;
        }

        private static void build_layouts (Master m, double W, double H, bool dark, string highlight) {
            double k = H / 540;
            double mx = 60 * W / 960;
            double cw = W - 2 * mx;

            var title = layout (m, _("Title Slide"), LayoutKind.TITLE);
            var ct = placeholder (PlaceholderKind.CENTER_TITLE, -1, W * 0.1, H * 0.25, W * 0.8, H * 0.28);
            ct.text.anchor = TextAnchor.BOTTOM;
            ct.text.anchor_set = true;
            ct.list_style = single_level (TextAlign.CENTER, BulletKind.NONE, Math.round (60 * k));
            title.elements.add (ct);
            var sub = placeholder (PlaceholderKind.SUBTITLE, 1, W * 0.15, H * 0.56, W * 0.7, H * 0.18);
            sub.list_style = single_level (TextAlign.CENTER, BulletKind.NONE, Math.round (24 * k));
            sub.list_style.levels[0].space_before = 0;
            title.elements.add (sub);
            add_meta (m, title);

            var tc = layout (m, _("Title and Content"), LayoutKind.TITLE_CONTENT);
            tc.elements.add (title_of (m));
            var body = placeholder (PlaceholderKind.OBJECT, 1, mx, 140 * k, cw, H - 200 * k);
            body.inherit_geometry = true;
            tc.elements.add (body);
            add_meta (m, tc);

            var sec = layout (m, _("Section Header"), LayoutKind.SECTION);
            var st = placeholder (PlaceholderKind.TITLE, -1, mx, H * 0.3, cw * 0.85, H * 0.3);
            st.text.anchor = TextAnchor.BOTTOM;
            st.text.anchor_set = true;
            st.list_style = single_level (TextAlign.LEFT, BulletKind.NONE, Math.round (54 * k));
            sec.elements.add (st);
            var sb = placeholder (PlaceholderKind.BODY, 1, mx, H * 0.62, cw * 0.85, H * 0.15);
            sb.list_style = single_level (TextAlign.LEFT, BulletKind.NONE, Math.round (24 * k));
            sb.list_style.levels[0].color = ColorSpec.with_alpha (dark ? "lt1" : "dk1", 0.7);
            sec.elements.add (sb);
            add_meta (m, sec);

            var two = layout (m, _("Two Content"), LayoutKind.TWO_CONTENT);
            two.elements.add (title_of (m));
            double half = (cw - 30 * k) / 2;
            two.elements.add (placeholder (PlaceholderKind.OBJECT, 1, mx, 140 * k, half, H - 200 * k));
            two.elements.add (placeholder (PlaceholderKind.OBJECT, 2, mx + half + 30 * k, 140 * k, half, H - 200 * k));
            add_meta (m, two);

            var cmp = layout (m, _("Comparison"), LayoutKind.COMPARISON);
            cmp.elements.add (title_of (m));
            var h1 = placeholder (PlaceholderKind.BODY, 1, mx, 135 * k, half, 44 * k);
            h1.list_style = single_level (TextAlign.LEFT, BulletKind.NONE, Math.round (24 * k));
            h1.list_style.levels[0].bold = 1;
            h1.text.anchor = TextAnchor.BOTTOM;
            h1.text.anchor_set = true;
            cmp.elements.add (h1);
            cmp.elements.add (placeholder (PlaceholderKind.OBJECT, 2, mx, 185 * k, half, H - 245 * k));
            var h2 = (ShapeElement) h1.clone ();
            h2.placeholder_idx = 3;
            h2.x = mx + half + 30 * k;
            cmp.elements.add (h2);
            cmp.elements.add (placeholder (PlaceholderKind.OBJECT, 4, mx + half + 30 * k, 185 * k, half, H - 245 * k));
            add_meta (m, cmp);

            var to = layout (m, _("Title Only"), LayoutKind.TITLE_ONLY);
            to.elements.add (title_of (m));
            add_meta (m, to);

            var blank = layout (m, _("Blank"), LayoutKind.BLANK);
            add_meta (m, blank);

            var cc = layout (m, _("Content with Caption"), LayoutKind.CONTENT_CAPTION);
            var cct = placeholder (PlaceholderKind.TITLE, -1, mx, 40 * k, cw * 0.36, 110 * k);
            cct.text.anchor = TextAnchor.BOTTOM;
            cct.text.anchor_set = true;
            cct.list_style = single_level (TextAlign.LEFT, BulletKind.NONE, Math.round (30 * k));
            cc.elements.add (cct);
            cc.elements.add (placeholder (PlaceholderKind.OBJECT, 1, mx + cw * 0.42, 40 * k, cw * 0.58, H - 100 * k));
            var cap = placeholder (PlaceholderKind.BODY, 2, mx, 165 * k, cw * 0.36, H - 225 * k);
            cap.list_style = single_level (TextAlign.LEFT, BulletKind.NONE, Math.round (16 * k));
            cc.elements.add (cap);
            add_meta (m, cc);

            var pc = layout (m, _("Picture with Caption"), LayoutKind.PICTURE_CAPTION);
            var pt = placeholder (PlaceholderKind.TITLE, -1, mx, 40 * k, cw * 0.36, 110 * k);
            pt.text.anchor = TextAnchor.BOTTOM;
            pt.text.anchor_set = true;
            pt.list_style = single_level (TextAlign.LEFT, BulletKind.NONE, Math.round (30 * k));
            pc.elements.add (pt);
            var pic = placeholder (PlaceholderKind.PICTURE, 1, mx + cw * 0.42, 40 * k, cw * 0.58, H - 100 * k);
            pic.list_style = single_level (TextAlign.CENTER, BulletKind.NONE);
            pc.elements.add (pic);
            var pcap = placeholder (PlaceholderKind.BODY, 2, mx, 165 * k, cw * 0.36, H - 225 * k);
            pcap.list_style = single_level (TextAlign.LEFT, BulletKind.NONE, Math.round (16 * k));
            pc.elements.add (pcap);
            add_meta (m, pc);

            var quote = layout (m, _("Quote"), LayoutKind.QUOTE);
            var qb = placeholder (PlaceholderKind.BODY, 1, W * 0.12, H * 0.2, W * 0.76, H * 0.45);
            qb.list_style = single_level (TextAlign.CENTER, BulletKind.NONE, Math.round (34 * k));
            qb.list_style.levels[0].italic = 1;
            qb.list_style.levels[0].font = "+mj-lt";
            qb.text.anchor = TextAnchor.MIDDLE;
            qb.text.anchor_set = true;
            quote.elements.add (qb);
            var qa = placeholder (PlaceholderKind.BODY, 2, W * 0.12, H * 0.68, W * 0.76, H * 0.1);
            qa.list_style = single_level (TextAlign.CENTER, BulletKind.NONE, Math.round (18 * k));
            qa.list_style.levels[0].color = highlight;
            quote.elements.add (qa);
            add_meta (m, quote);

            var big = layout (m, _("Big Number"), LayoutKind.BIG_NUMBER);
            var bn = placeholder (PlaceholderKind.TITLE, -1, mx, H * 0.18, cw, H * 0.42);
            bn.list_style = single_level (TextAlign.CENTER, BulletKind.NONE, Math.round (120 * k));
            bn.list_style.levels[0].color = highlight;
            bn.text.anchor = TextAnchor.BOTTOM;
            bn.text.anchor_set = true;
            big.elements.add (bn);
            var bl = placeholder (PlaceholderKind.BODY, 1, mx, H * 0.62, cw, H * 0.14);
            bl.list_style = single_level (TextAlign.CENTER, BulletKind.NONE, Math.round (24 * k));
            big.elements.add (bl);
            add_meta (m, big);
        }

        public static Presentation new_presentation (ThemePreset preset, double W = 960, double H = 540) {
            var p = new Presentation ();
            p.width = W;
            p.height = H;
            p.masters.add (build_master (preset, W, H));
            add_slide (p, p.master.layout_of_kind (LayoutKind.TITLE), 0);
            return p;
        }

        public static Slide add_slide (Presentation p, Layout? layout, int index) {
            var s = new Slide ();
            if (layout != null) {
                s.layout_id = layout.id;
                foreach (var e in layout.elements) {
                    if (e.placeholder == PlaceholderKind.NONE || e.placeholder.is_meta ()) continue;
                    var c = e.clone ();
                    c.inherit_geometry = true;
                    var sh = c as ShapeElement;
                    if (sh != null) {
                        sh.list_style = null;
                        sh.text = new TextBody ();
                        sh.text.paragraphs.add (new Paragraph ());
                        sh.fill = new Fill ();
                    }
                    p.assign_ids (c);
                    double x, y, w, h;
                    p.effective_geometry (s, layout, p.master_for (s), c, out x, out y, out w, out h);
                    c.set_geometry (x, y, w, h);
                    s.elements.add (c);
                }
            }
            p.slides.insert (index.clamp (0, p.slides.size), s);
            return s;
        }

        public static void apply_layout (Presentation p, Slide s, Layout layout) {
            var old = new Gee.ArrayList<Element> ();
            old.add_all (s.elements);
            s.layout_id = layout.id;
            s.elements.clear ();
            var used = new Gee.HashSet<Element> ();
            foreach (var e in layout.elements) {
                if (e.placeholder == PlaceholderKind.NONE || e.placeholder.is_meta ()) continue;
                Element? match = null;
                foreach (var o in old) {
                    if (used.contains (o) || o.placeholder == PlaceholderKind.NONE) continue;
                    if (o.placeholder.matches (e.placeholder) && (o.placeholder.is_title () || o.placeholder_idx == e.placeholder_idx)) {
                        match = o;
                        break;
                    }
                }
                if (match == null) {
                    foreach (var o in old) {
                        if (used.contains (o) || o.placeholder == PlaceholderKind.NONE || o.placeholder.is_meta ()) continue;
                        if (o.placeholder.matches (e.placeholder)) {
                            match = o;
                            break;
                        }
                    }
                }
                Element c;
                if (match != null) {
                    used.add (match);
                    c = match;
                    c.placeholder = e.placeholder;
                    c.placeholder_idx = e.placeholder_idx;
                } else {
                    c = e.clone ();
                    var sh = c as ShapeElement;
                    if (sh != null) {
                        sh.list_style = null;
                        sh.text = new TextBody ();
                        sh.text.paragraphs.add (new Paragraph ());
                        sh.fill = new Fill ();
                    }
                    p.assign_ids (c);
                }
                c.inherit_geometry = true;
                double x, y, w, h;
                p.effective_geometry (s, layout, p.master_for (s), c, out x, out y, out w, out h);
                c.set_geometry (x, y, w, h);
                s.elements.add (c);
            }
            foreach (var o in old) {
                if (used.contains (o)) continue;
                var body = o.text_body ();
                bool empty_ph = o.placeholder != PlaceholderKind.NONE && (body == null || body.is_empty ()) && o.kind == ElementKind.SHAPE;
                if (empty_ph) {
                    s.remove_animations_for (o.id);
                    continue;
                }
                if (o.placeholder != PlaceholderKind.NONE && !o.placeholder.is_meta ()) {
                    o.inherit_geometry = false;
                    if (o.placeholder != PlaceholderKind.PICTURE) o.placeholder = PlaceholderKind.NONE;
                    var sh = o as ShapeElement;
                    if (sh != null && sh.text != null) sh.text_box = true;
                }
                s.elements.add (o);
            }
        }

        public static void refresh_inherited (Presentation p) {
            foreach (var s in p.slides) {
                var layout = p.layout_for (s);
                var m = p.master_for (s);
                foreach (var e in s.elements) {
                    if (!e.inherit_geometry) continue;
                    double x, y, w, h;
                    p.effective_geometry (s, layout, m, e, out x, out y, out w, out h);
                    e.set_geometry (x, y, w, h);
                }
            }
            foreach (var m in p.masters) {
                foreach (var l in m.layouts) {
                    foreach (var e in l.elements) {
                        if (!e.inherit_geometry) continue;
                        double x, y, w, h;
                        p.effective_geometry (null, l, m, e, out x, out y, out w, out h);
                        e.set_geometry (x, y, w, h);
                    }
                }
            }
        }

        public static void apply_theme (Presentation p, ThemePreset preset) {
            foreach (var m in p.masters) {
                var fresh = build_master (preset, p.width, p.height);
                m.theme = fresh.theme;
                m.background = fresh.background;
                m.title_style = fresh.title_style;
                m.body_style = fresh.body_style;
                m.other_style = fresh.other_style;
                for (int i = m.elements.size - 1; i >= 0; i--) {
                    if (m.elements[i].placeholder == PlaceholderKind.NONE && m.elements[i].name == "Decoration") m.elements.remove_at (i);
                }
                int at = 0;
                foreach (var e in fresh.elements) {
                    if (e.placeholder == PlaceholderKind.NONE) m.elements.insert (at++, e);
                }
                foreach (var e in m.elements) {
                    var sh = e as ShapeElement;
                    if (sh == null || !sh.placeholder.is_meta ()) continue;
                    var fe = fresh.find_placeholder (sh.placeholder) as ShapeElement;
                    if (fe != null) sh.list_style = fe.list_style != null ? fe.list_style.clone () : null;
                }
                foreach (var l in m.layouts) {
                    var fl = fresh.layout_of_kind (l.kind);
                    if (fl == null) continue;
                    foreach (var e in l.elements) {
                        var sh = e as ShapeElement;
                        if (sh == null || sh.placeholder == PlaceholderKind.NONE || sh.placeholder.is_meta ()) continue;
                        var fe = fl.find_placeholder (sh.placeholder, sh.placeholder_idx) as ShapeElement;
                        if (fe != null) sh.list_style = fe.list_style != null ? fe.list_style.clone () : null;
                    }
                }
            }
        }

        public static ShapeElement text_box (Presentation p, double x, double y, double w, string text, double size = 0) {
            var s = new ShapeElement (ShapeKind.RECT);
            s.text_box = true;
            s.set_geometry (x, y, w, 40);
            s.text = new TextBody.with_text (text);
            s.text.autofit = AutoFit.RESIZE;
            s.text.anchor_set = true;
            if (size > 0) foreach (var par in s.text.paragraphs) foreach (var r in par.runs) r.size = size;
            p.assign_ids (s);
            return s;
        }

        public static ShapeElement shape (Presentation p, ShapeKind kind, double x, double y, double w, double h) {
            var s = new ShapeElement (kind);
            s.set_geometry (x, y, w, h);
            if (kind == ShapeKind.LINE) {
                s.line.color = "tx1";
                s.line.width = 2;
            } else {
                s.fill = new Fill.solid ("accent1");
                s.ensure_text ();
                s.text.anchor_set = true;
                foreach (var par in s.text.paragraphs) par.end_format.color = "lt1";
            }
            s.corner = 0.16;
            p.assign_ids (s);
            return s;
        }
    }
}
