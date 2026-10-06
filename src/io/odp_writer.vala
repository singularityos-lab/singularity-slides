namespace Singularity.Apps.Slides {

    public class OdpStyleSet {
        public string prefix;
        public StringBuilder output = new StringBuilder ();
        private Gee.HashMap<string, string> names = new Gee.HashMap<string, string> ();
        private Gee.HashMap<string, int> counters = new Gee.HashMap<string, int> ();

        public OdpStyleSet (string prefix) {
            this.prefix = prefix;
        }

        private string next (string abbrev) {
            int n = (counters.has_key (abbrev) ? counters[abbrev] : 0) + 1;
            counters[abbrev] = n;
            return prefix + abbrev + n.to_string ();
        }

        public string add (string family, string abbrev, string inner, string parent = "") {
            string key = family + "\n" + parent + "\n" + inner;
            if (names.has_key (key)) return names[key];
            string name = next (abbrev);
            names[key] = name;
            output.append ("<style:style style:name=\"%s\" style:family=\"%s\"".printf (name, family));
            if (parent != "") output.append (" style:parent-style-name=\"%s\"".printf (XmlOut.esc (parent)));
            output.append (">");
            output.append (inner);
            output.append ("</style:style>");
            return name;
        }

        public string add_list (string inner) {
            string key = "list\n" + inner;
            if (names.has_key (key)) return names[key];
            string name = next ("L");
            names[key] = name;
            output.append ("<text:list-style style:name=\"%s\">%s</text:list-style>".printf (name, inner));
            return name;
        }
    }

    public class OdpAttrs {
        public StringBuilder sb = new StringBuilder ();

        public OdpAttrs a (string name, string val) {
            sb.append (" ");
            sb.append (name);
            sb.append ("=\"");
            sb.append (XmlOut.esc (val));
            sb.append ("\"");
            return this;
        }

        public string str () {
            return sb.str;
        }

        public bool empty () {
            return sb.len == 0;
        }
    }

    public class OdpWriter {
        private Presentation pres;
        public bool include_private = true;
        private Renderer renderer = new Renderer ();
        private StringBuilder common = new StringBuilder ();
        private Gee.HashMap<string, string> common_names = new Gee.HashMap<string, string> ();
        private int common_counter = 0;
        private Gee.HashMap<string, string> image_hrefs = new Gee.HashMap<string, string> ();
        private Gee.ArrayList<string> image_paths = new Gee.ArrayList<string> ();
        private Gee.ArrayList<Bytes> image_data = new Gee.ArrayList<Bytes> ();
        private Gee.ArrayList<string> image_mimes = new Gee.ArrayList<string> ();
        private Gee.ArrayList<string> chart_names = new Gee.ArrayList<string> ();
        private Gee.ArrayList<string> extra_paths = new Gee.ArrayList<string> ();
        private Gee.ArrayList<Bytes> extra_data = new Gee.ArrayList<Bytes> ();
        private Gee.ArrayList<string> extra_mimes = new Gee.ArrayList<string> ();
        private Gee.ArrayList<string> formula_names = new Gee.ArrayList<string> ();
        private Gee.ArrayList<string> formula_docs = new Gee.ArrayList<string> ();
        private Gee.HashMap<int, string> page_names = new Gee.HashMap<int, string> ();

        private string media_href (Bytes data, string mime, string ext) {
            for (int i = 0; i < extra_paths.size; i++) if (extra_data[i] == data) return extra_paths[i];
            string href = "Media/media%d.%s".printf (extra_paths.size + 1, ext);
            extra_paths.add (href);
            extra_data.add (data);
            extra_mimes.add (mime);
            return href;
        }

        private Bytes png_of (Cairo.ImageSurface surf) {
            var bytes = new ByteArray ();
            surf.write_to_png_stream ((data) => {
                bytes.append (data);
                return Cairo.Status.SUCCESS;
            });
            return ByteArray.free_to_bytes ((owned) bytes);
        }

        private void event_listeners (XmlOut x, Element e) {
            if (e.click == null || e.click.kind == ActionKind.NONE) return;
            var a = e.click;
            x.start ("office:event-listeners").start ("presentation:event-listener").a ("script:event-name", "dom:click");
            switch (a.kind) {
                case ActionKind.NEXT_SLIDE: x.a ("presentation:action", "next-page"); break;
                case ActionKind.PREVIOUS_SLIDE: x.a ("presentation:action", "previous-page"); break;
                case ActionKind.FIRST_SLIDE: x.a ("presentation:action", "first-page"); break;
                case ActionKind.LAST_SLIDE: x.a ("presentation:action", "last-page"); break;
                case ActionKind.END_SHOW: x.a ("presentation:action", "stop"); break;
                case ActionKind.SLIDE:
                    x.a ("presentation:action", "show").a ("xlink:href", "#" + (page_names[a.slide_uid] ?? "")).a ("xlink:type", "simple");
                    break;
                case ActionKind.URL:
                case ActionKind.FILE:
                    x.a ("presentation:action", "show").a ("xlink:href", a.target).a ("xlink:type", "simple");
                    break;
                case ActionKind.PROGRAM:
                    x.a ("presentation:action", "execute").a ("xlink:href", a.target).a ("xlink:type", "simple");
                    break;
                default:
                    x.a ("presentation:action", "none");
                    break;
            }
            x.end ().end ();
        }
        private Gee.ArrayList<string> chart_docs = new Gee.ArrayList<string> ();
        private OdpStyleSet content_styles = new OdpStyleSet ("");
        private OdpStyleSet master_styles = new OdpStyleSet ("M");
        private Gee.HashMap<Layout, string> layout_pages = new Gee.HashMap<Layout, string> ();
        private Gee.HashMap<Master, string> master_pages = new Gee.HashMap<Master, string> ();
        private Gee.HashMap<string, string> page_layout_names = new Gee.HashMap<string, string> ();

        private class Ctx {
            public Theme theme;
            public OdpStyleSet styles;
            public Slide? slide;
            public Layout? layout;
            public Master master;
            public bool on_master;
            public string mp;
            public string layer;
            public string origin = "";
            public RenderContext rctx;
        }

        public OdpWriter (Presentation pres) {
            this.pres = pres;
        }

        private string common_def (string key, string element_xml_fmt, string base_name) {
            if (common_names.has_key (key)) return common_names[key];
            common_counter++;
            string name = "%s_%d".printf (base_name, common_counter);
            common_names[key] = name;
            common.append (element_xml_fmt.replace ("@NAME@", name));
            return name;
        }

        private string image_href (Bytes data, string mime) {
            string key = "%p:%zu".printf (data, data.get_size ());
            if (image_hrefs.has_key (key)) return image_hrefs[key];
            string m = mime != "" ? mime : Odf.sniff_mime (data, "");
            string href = "Pictures/image%d.%s".printf (image_paths.size + 1, Odf.ext_for_mime (m));
            image_hrefs[key] = href;
            image_paths.add (href);
            image_data.add (data);
            image_mimes.add (m);
            return href;
        }

        private void color_attrs (OdpAttrs at, string attr, string opacity_attr, string spec, Theme t) {
            var c = t.resolve (spec);
            at.a (attr, Odf.hex (c));
            if (c.a < 0.999 && opacity_attr != "") at.a (opacity_attr, Odf.pct (c.a));
        }

        private string gradient_name (Fill f, Theme t) {
            var c1 = t.resolve (f.stops.size > 0 ? f.stops[0].color : f.color);
            var c2 = t.resolve (f.stops.size > 1 ? f.stops[f.stops.size - 1].color : f.color);
            double odf_angle = ((90 - f.angle) % 360 + 360) % 360;
            string style = f.radial ? "radial" : "linear";
            string key = "grad|%s|%s|%s|%s".printf (style, Odf.hex (c1), Odf.hex (c2), Odf.fixed (odf_angle, 2));
            string xml = "<draw:gradient draw:name=\"@NAME@\" draw:style=\"%s\" draw:cx=\"50%%\" draw:cy=\"50%%\" draw:start-color=\"%s\" draw:end-color=\"%s\" draw:start-intensity=\"100%%\" draw:end-intensity=\"100%%\" draw:angle=\"%sdeg\" draw:border=\"0%%\"/>".printf (
                style, Odf.hex (c1), Odf.hex (c2), Odf.fixed (odf_angle, 2));
            return common_def (key, xml, "Gradient");
        }

        private string fill_image_name (Bytes data, string mime) {
            string href = image_href (data, mime);
            string xml = "<draw:fill-image draw:name=\"@NAME@\" xlink:href=\"%s\" xlink:type=\"simple\" xlink:show=\"embed\" xlink:actuate=\"onLoad\"/>".printf (href);
            return common_def ("img|" + href, xml, "Bitmap");
        }

        private void fill_attrs (OdpAttrs at, Fill f, Theme t) {
            switch (f.kind) {
                case FillKind.SOLID:
                    at.a ("draw:fill", "solid");
                    color_attrs (at, "draw:fill-color", "draw:opacity", f.color, t);
                    break;
                case FillKind.GRADIENT:
                    at.a ("draw:fill", "gradient");
                    at.a ("draw:fill-gradient-name", gradient_name (f, t));
                    var c1 = t.resolve (f.stops.size > 0 ? f.stops[0].color : f.color);
                    at.a ("draw:fill-color", Odf.hex (c1));
                    var c2 = t.resolve (f.stops.size > 1 ? f.stops[f.stops.size - 1].color : f.color);
                    if (c1.a < 0.999 || c2.a < 0.999) {
                        double odf_angle = ((90 - f.angle) % 360 + 360) % 360;
                        string style = f.radial ? "radial" : "linear";
                        string key = "opacity|%s|%s|%s|%s".printf (style, Odf.pct (c1.a), Odf.pct (c2.a), Odf.fixed (odf_angle, 2));
                        string xml = "<draw:opacity draw:name=\"@NAME@\" draw:style=\"%s\" draw:cx=\"50%%\" draw:cy=\"50%%\" draw:start=\"%s\" draw:end=\"%s\" draw:angle=\"%sdeg\" draw:border=\"0%%\"/>".printf (
                            style, Odf.pct (c1.a), Odf.pct (c2.a), Odf.fixed (odf_angle, 2));
                        at.a ("draw:opacity-name", common_def (key, xml, "Transparency"));
                    }
                    break;
                case FillKind.IMAGE:
                    if (f.image == null) {
                        at.a ("draw:fill", "none");
                        break;
                    }
                    at.a ("draw:fill", "bitmap");
                    at.a ("draw:fill-image-name", fill_image_name (f.image, f.image_mime));
                    at.a ("style:repeat", f.tile ? "repeat" : "stretch");
                    break;
                default:
                    at.a ("draw:fill", "none");
                    break;
            }
        }

        private string dash_name (DashKind d) {
            string key = "dash|" + ((int) d).to_string ();
            string xml;
            switch (d) {
                case DashKind.DOT:
                    xml = "<draw:stroke-dash draw:name=\"@NAME@\" draw:display-name=\"Dot\" draw:style=\"rect\" draw:dots1=\"1\" draw:dots1-length=\"100%\" draw:distance=\"100%\"/>";
                    break;
                case DashKind.DASH_DOT:
                    xml = "<draw:stroke-dash draw:name=\"@NAME@\" draw:display-name=\"Dash Dot\" draw:style=\"rect\" draw:dots1=\"1\" draw:dots1-length=\"400%\" draw:dots2=\"1\" draw:dots2-length=\"100%\" draw:distance=\"200%\"/>";
                    break;
                case DashKind.LONG_DASH:
                    xml = "<draw:stroke-dash draw:name=\"@NAME@\" draw:display-name=\"Long Dash\" draw:style=\"rect\" draw:dots1=\"1\" draw:dots1-length=\"800%\" draw:distance=\"300%\"/>";
                    break;
                default:
                    xml = "<draw:stroke-dash draw:name=\"@NAME@\" draw:display-name=\"Dash\" draw:style=\"rect\" draw:dots1=\"1\" draw:dots1-length=\"400%\" draw:distance=\"300%\"/>";
                    break;
            }
            return common_def (key, xml, "Dash");
        }

        private string marker_name (ArrowKind k) {
            string key = "marker|" + ((int) k).to_string ();
            string xml;
            switch (k) {
                case ArrowKind.ARROW:
                    xml = "<draw:marker draw:name=\"@NAME@\" draw:display-name=\"Line Arrow\" svg:viewBox=\"0 0 20 30\" svg:d=\"M10 0L20 26L17 30L10 10L3 30L0 26Z\"/>";
                    return common_def (key, xml, "Line_Arrow");
                case ArrowKind.OVAL:
                    var sb = new StringBuilder ();
                    for (int i = 0; i < 16; i++) {
                        double a = i * Math.PI / 8;
                        sb.append ("%s%s %s".printf (i == 0 ? "M" : "L", Odf.fixed (10 + 10 * Math.cos (a), 2), Odf.fixed (10 + 10 * Math.sin (a), 2)));
                    }
                    xml = "<draw:marker draw:name=\"@NAME@\" draw:display-name=\"Circle\" svg:viewBox=\"0 0 20 20\" svg:d=\"%sZ\"/>".printf (sb.str);
                    return common_def (key, xml, "Circle");
                case ArrowKind.DIAMOND:
                    xml = "<draw:marker draw:name=\"@NAME@\" draw:display-name=\"Diamond\" svg:viewBox=\"0 0 20 20\" svg:d=\"M10 0L20 10L10 20L0 10Z\"/>";
                    return common_def (key, xml, "Diamond");
                default:
                    xml = "<draw:marker draw:name=\"@NAME@\" draw:display-name=\"Arrow\" svg:viewBox=\"0 0 20 30\" svg:d=\"M10 0L0 30H20Z\"/>";
                    return common_def (key, xml, "Arrow");
            }
        }

        private void stroke_attrs (OdpAttrs at, Line l, Theme t) {
            if (!l.visible ()) {
                at.a ("draw:stroke", "none");
                return;
            }
            if (l.dash == DashKind.SOLID) {
                at.a ("draw:stroke", "solid");
            } else {
                at.a ("draw:stroke", "dash");
                at.a ("draw:stroke-dash", dash_name (l.dash));
            }
            color_attrs (at, "svg:stroke-color", "svg:stroke-opacity", l.color, t);
            at.a ("svg:stroke-width", Odf.cm (l.width));
            if (l.head != ArrowKind.NONE) {
                at.a ("draw:marker-start", marker_name (l.head));
                at.a ("draw:marker-start-width", Odf.cm (double.max (l.width * 3.5, 6)));
            }
            if (l.tail != ArrowKind.NONE) {
                at.a ("draw:marker-end", marker_name (l.tail));
                at.a ("draw:marker-end-width", Odf.cm (double.max (l.width * 3.5, 6)));
            }
        }

        private void shadow_attrs (OdpAttrs at, Shadow s, Theme t) {
            if (!s.enabled) {
                at.a ("draw:shadow", "hidden");
                return;
            }
            at.a ("draw:shadow", "visible");
            at.a ("draw:shadow-offset-x", Odf.cm (s.dx ()));
            at.a ("draw:shadow-offset-y", Odf.cm (s.dy ()));
            var c = t.resolve (s.color);
            at.a ("draw:shadow-color", Odf.hex (c));
            at.a ("draw:shadow-opacity", Odf.pct (s.opacity * c.a));
            at.a ("loext:shadow-blur", Odf.cm (s.blur));
        }

        private void body_attrs (OdpAttrs at, Ctx c, Element e, TextBody b) {
            at.a ("fo:padding-left", Odf.cm (b.inset_left));
            at.a ("fo:padding-top", Odf.cm (b.inset_top));
            at.a ("fo:padding-right", Odf.cm (b.inset_right));
            at.a ("fo:padding-bottom", Odf.cm (b.inset_bottom));
            var anchor = pres.effective_anchor (c.slide, c.layout, c.master, e, b);
            at.a ("draw:textarea-vertical-align", anchor == TextAnchor.MIDDLE ? "middle" : (anchor == TextAnchor.BOTTOM ? "bottom" : "top"));
            at.a ("draw:textarea-horizontal-align", "justify");
            at.a ("fo:wrap-option", b.wrap ? "wrap" : "no-wrap");
            at.a ("draw:auto-grow-height", b.autofit == AutoFit.RESIZE ? "true" : "false");
            at.a ("draw:auto-grow-width", "false");
            if (b.autofit == AutoFit.SHRINK) {
                at.a ("draw:fit-to-size", "shrink-to-fit");
                at.a ("style:shrink-to-fit", "true");
            } else {
                at.a ("draw:fit-to-size", "false");
            }
        }

        private void geometry (XmlOut x, Element e) {
            if (e.rotation == 0) {
                x.a ("svg:x", Odf.cm (e.x)).a ("svg:y", Odf.cm (e.y));
                x.a ("svg:width", Odf.cm (e.w)).a ("svg:height", Odf.cm (e.h));
                return;
            }
            double a = -e.rotation * Math.PI / 180;
            double hw = e.w / 2, hh = e.h / 2;
            double rx = hw * Math.cos (a) + hh * Math.sin (a);
            double ry = -hw * Math.sin (a) + hh * Math.cos (a);
            double tx = e.cx () - rx, ty = e.cy () - ry;
            x.a ("svg:width", Odf.cm (e.w)).a ("svg:height", Odf.cm (e.h));
            x.a ("draw:transform", "rotate (%s) translate (%s %s)".printf (Odf.fixed (a, 10), Odf.cm (tx), Odf.cm (ty)));
        }

        private void common_attrs (XmlOut x, Element e, Ctx c) {
            if (e.name != "") x.a ("draw:name", e.name);
            write_id (x, e, c);
            x.a ("draw:layer", c.layer);
        }

        private Gee.HashSet<string> used_ids = new Gee.HashSet<string> ();

        private void write_id (XmlOut x, Element e, Ctx c) {
            if (c.on_master) return;
            string id = "id%d".printf (e.id);
            if (used_ids.contains (id)) return;
            used_ids.add (id);
            x.a ("draw:id", id).a ("xml:id", id);
        }

        private void private_attrs (XmlOut x, Element e, Ctx c) {
            if (!include_private) return;
            x.a ("sgs:id", e.id.to_string ());
            x.a ("sgs:geom", Odf.geom_code (e));
            x.a ("sgs:line", Odf.line_code (e.line));
            x.a ("sgs:shadow", Odf.shadow_code (e.shadow));
            if (e.placeholder != PlaceholderKind.NONE) x.a ("sgs:ph", "%d|%d|%s".printf ((int) e.placeholder, e.placeholder_idx, e.inherit_geometry ? "1" : "0"));
            if (e.locked) x.a ("sgs:locked", "1");
            if (e.click != null) x.a ("sgs:click", Odf.action_code (e.click));
            if (e.hover != null) x.a ("sgs:hover", Odf.action_code (e.hover));
            if (c.origin != "") x.a ("sgs:origin", c.origin);
        }

        private void description (XmlOut x, Element e) {
            if (e.description != "") x.element ("svg:desc", e.description);
            event_listeners (x, e);
        }

        private RunStyle resolved_run (Ctx c, Element e, Paragraph p, TextRun r, string default_color) {
            var ls = pres.level_style (c.slide, c.layout, c.master, e, p.level);
            if (default_color != "") ls.color = default_color;
            return pres.run_style (ls, r, c.theme);
        }

        private string span_style (Ctx c, Element e, Paragraph p, TextRun r, bool resolve, string default_color, bool force_bold) {
            var at = new OdpAttrs ();
            if (resolve) {
                var rs = resolved_run (c, e, p, r, default_color);
                at.a ("fo:font-size", Odf.pt (rs.size));
                at.a ("fo:font-family", rs.font).a ("style:font-name", rs.font);
                at.a ("fo:font-weight", rs.bold || force_bold ? "bold" : "normal");
                at.a ("fo:font-style", rs.italic ? "italic" : "normal");
                at.a ("fo:color", Odf.hex (rs.color));
                if (rs.underline) at.a ("style:text-underline-style", "solid").a ("style:text-underline-width", "auto").a ("style:text-underline-color", "font-color");
                if (rs.strike) at.a ("style:text-line-through-style", "solid");
                if (rs.baseline != 0) at.a ("style:text-position", rs.baseline > 0 ? "super 58%" : "sub 58%");
                if (rs.highlight != "") at.a ("fo:background-color", Odf.hex (c.theme.resolve (rs.highlight)));
            } else {
                if (r.size > 0) at.a ("fo:font-size", Odf.pt (r.size));
                if (r.font != "") {
                    string f = c.theme.resolve_font (r.font);
                    at.a ("fo:font-family", f).a ("style:font-name", f);
                }
                if (r.bold >= 0 || force_bold) at.a ("fo:font-weight", r.bold == 1 || (force_bold && r.bold != 0) ? "bold" : "normal");
                if (r.italic >= 0) at.a ("fo:font-style", r.italic == 1 ? "italic" : "normal");
                if (r.color != "") at.a ("fo:color", Odf.hex (c.theme.resolve (r.color)));
                if (r.underline >= 0) at.a ("style:text-underline-style", r.underline == 1 ? "solid" : "none");
                if (r.strike >= 0) at.a ("style:text-line-through-style", r.strike == 1 ? "solid" : "none");
                if (r.baseline != 0) at.a ("style:text-position", r.baseline > 0 ? "super 58%" : "sub 58%");
                if (r.highlight != "") at.a ("fo:background-color", Odf.hex (c.theme.resolve (r.highlight)));
            }
            if (at.empty ()) return "";
            return c.styles.add ("text", "T", "<style:text-properties%s/>".printf (at.str ()));
        }

        private string para_style (Ctx c, Paragraph p) {
            var at = new OdpAttrs ();
            switch (p.align) {
                case TextAlign.LEFT: at.a ("fo:text-align", "start"); break;
                case TextAlign.CENTER: at.a ("fo:text-align", "center"); break;
                case TextAlign.RIGHT: at.a ("fo:text-align", "end"); break;
                case TextAlign.JUSTIFY: at.a ("fo:text-align", "justify"); break;
                default: break;
            }
            if (p.space_before >= 0) at.a ("fo:margin-top", Odf.cm (p.space_before));
            if (p.space_after >= 0) at.a ("fo:margin-bottom", Odf.cm (p.space_after));
            if (p.line_spacing > 0) at.a ("fo:line-height", Odf.pct (p.line_spacing));
            if (at.empty ()) return "";
            return c.styles.add ("paragraph", "P", "<style:paragraph-properties%s/>".printf (at.str ()));
        }

        private string list_level_xml (int level, BulletKind kind, string ch, NumberStyle ns, int start, double margin, double indent, string color_hex) {
            var sb = new StringBuilder ();
            string props = "<style:list-level-properties text:list-level-position-and-space-mode=\"label-alignment\"><style:list-level-label-alignment text:label-followed-by=\"listtab\" fo:margin-left=\"%s\" fo:text-indent=\"%s\"/></style:list-level-properties>".printf (
                Odf.cm (double.max (margin, 0)), Odf.cm (indent));
            if (kind == BulletKind.NUMBER) {
                string fmt = "1", suffix = ".", prefix = "";
                switch (ns) {
                    case NumberStyle.ARABIC_PAREN: suffix = ")"; break;
                    case NumberStyle.ALPHA_LOWER: fmt = "a"; break;
                    case NumberStyle.ALPHA_UPPER: fmt = "A"; break;
                    case NumberStyle.ROMAN_LOWER: fmt = "i"; break;
                    case NumberStyle.ROMAN_UPPER: fmt = "I"; break;
                    default: break;
                }
                sb.append ("<text:list-level-style-number text:level=\"%d\" style:num-format=\"%s\" style:num-suffix=\"%s\" style:num-prefix=\"%s\" text:start-value=\"%d\">%s</text:list-level-style-number>".printf (
                    level + 1, fmt, suffix, prefix, int.max (start, 1), props));
            } else {
                string color = color_hex != "" ? "<style:text-properties fo:color=\"%s\"/>".printf (color_hex) : "";
                sb.append ("<text:list-level-style-bullet text:level=\"%d\" text:bullet-char=\"%s\">%s%s</text:list-level-style-bullet>".printf (
                    level + 1, XmlOut.esc (ch != "" ? ch : "•"), props, color));
            }
            return sb.str;
        }

        private void write_run_text (XmlOut x, string text) {
            var buf = new StringBuilder ();
            int spaces = 0;
            bool at_start = true;
            unichar ch;
            int i = 0;
            while (text.get_next_char (ref i, out ch)) {
                if (ch == ' ') {
                    if (at_start || (buf.len > 0 && buf.str.has_suffix (" ")) || spaces > 0) {
                        if (buf.len > 0) {
                            x.text (buf.str);
                            buf.truncate ();
                        }
                        spaces++;
                        at_start = false;
                        continue;
                    }
                    buf.append_c (' ');
                    at_start = false;
                    continue;
                }
                if (spaces > 0) {
                    x.start ("text:s");
                    if (spaces > 1) x.a ("text:c", spaces.to_string ());
                    x.end ();
                    spaces = 0;
                }
                if (ch == '\n' || ch == '\v' || ch == '\t') {
                    if (buf.len > 0) {
                        x.text (buf.str);
                        buf.truncate ();
                    }
                    x.empty (ch == '\t' ? "text:tab" : "text:line-break");
                    at_start = ch != '\t';
                    continue;
                }
                buf.append_unichar (ch);
                at_start = false;
            }
            if (buf.len > 0) x.text (buf.str);
            if (spaces > 0) {
                x.start ("text:s");
                if (spaces > 1) x.a ("text:c", spaces.to_string ());
                x.end ();
            }
        }

        private void write_paragraph (XmlOut x, Ctx c, Element e, Paragraph p, bool resolve, string default_color, bool force_bold) {
            x.start ("text:p");
            string ps = para_style (c, p);
            if (ps != "") x.a ("text:style-name", ps);
            if (include_private) {
                x.a ("sgs:para", Odf.para_code (p));
                x.a ("sgs:end", Odf.run_code (p.end_format));
            }
            foreach (var r in p.runs) {
                if (r.text == "" && r.field == "") continue;
                bool link = r.link != "";
                if (link) x.start ("text:a").a ("xlink:type", "simple").a ("xlink:href", r.link);
                string ts = span_style (c, e, p, r, resolve, default_color, force_bold);
                x.start ("text:span");
                if (ts != "") x.a ("text:style-name", ts);
                if (include_private) x.a ("sgs:run", Odf.run_code (r));
                if (r.field == "slidenum") {
                    x.start ("text:page-number").a ("text:select-page", "current");
                    x.text (r.text != "" ? r.text : "<number>");
                    x.end ();
                } else if (r.field.has_prefix ("datetime")) {
                    x.start ("text:date");
                    x.text (r.text);
                    x.end ();
                } else {
                    write_run_text (x, r.text);
                }
                x.end ();
                if (link) x.end ();
            }
            if (p.runs.size == 0) {
                var at = new OdpAttrs ();
                var rs = resolved_run (c, e, p, p.end_format, default_color);
                at.a ("fo:font-size", Odf.pt (rs.size));
                string ts = c.styles.add ("text", "T", "<style:text-properties%s/>".printf (at.str ()));
                if (p.runs.size == 0) x.start ("text:span").a ("text:style-name", ts).end ();
            }
            x.end ();
        }

        private bool outline_class (Element e) {
            var k = e.placeholder;
            return k == PlaceholderKind.BODY || k == PlaceholderKind.OBJECT;
        }

        private void write_body (XmlOut x, Ctx c, Element e, TextBody body, string default_color = "", bool force_bold = false) {
            bool resolve = e.placeholder == PlaceholderKind.NONE;
            bool prev_list = false;
            int[] counters = new int[9];
            foreach (var p in body.paragraphs) {
                var ls = pres.level_style (c.slide, c.layout, c.master, e, p.level);
                BulletKind kind = p.bullet != BulletKind.INHERIT ? p.bullet : ls.bullet;
                bool in_list = kind == BulletKind.CHAR || kind == BulletKind.NUMBER || (p.bullet == BulletKind.INHERIT && outline_class (e) && ls.bullet != BulletKind.NONE);
                if (!in_list) {
                    write_paragraph (x, c, e, p, resolve, default_color, force_bold);
                    prev_list = false;
                    continue;
                }
                string style_name = "";
                if (p.bullet == BulletKind.CHAR || p.bullet == BulletKind.NUMBER || resolve) {
                    var sb = new StringBuilder ();
                    string ch = p.bullet == BulletKind.CHAR && p.bullet_char != "" ? p.bullet_char : (ls.bullet_char != "" ? ls.bullet_char : "•");
                    string bc = p.bullet_color != "" ? Odf.hex (c.theme.resolve (p.bullet_color)) : "";
                    for (int lv = 0; lv < 9; lv++) {
                        var lls = pres.level_style (c.slide, c.layout, c.master, e, lv);
                        double margin = lls.margin >= 0 ? lls.margin : 0;
                        if (lv == p.level) sb.append (list_level_xml (lv, kind, ch, p.number_style, p.number_start, margin, lls.indent, bc));
                        else sb.append (list_level_xml (lv, lls.bullet == BulletKind.NUMBER ? BulletKind.NUMBER : BulletKind.CHAR, lls.bullet_char, NumberStyle.ARABIC_PERIOD, 1, margin, lls.indent, ""));
                    }
                    style_name = c.styles.add_list (sb.str);
                }
                x.start ("text:list");
                if (style_name != "") x.a ("text:style-name", style_name);
                if (prev_list) x.a ("text:continue-numbering", "true");
                x.start ("text:list-item");
                for (int lv = 0; lv < p.level; lv++) x.start ("text:list").start ("text:list-item");
                write_paragraph (x, c, e, p, resolve, default_color, force_bold);
                for (int lv = 0; lv < p.level; lv++) x.end ().end ();
                x.end ();
                x.end ();
                prev_list = true;
                counters[p.level.clamp (0, 8)]++;
            }
        }

        private string enhanced_path (ShapeElement s, out string viewbox) {
            double vw = Math.fmax (Math.round (s.w * 100), 1), vh = Math.fmax (Math.round (s.h * 100), 1);
            viewbox = "0 0 %s %s".printf (Odf.fixed (vw, 0), Odf.fixed (vh, 0));
            var surf = new Cairo.ImageSurface (Cairo.Format.ARGB32, 1, 1);
            var cr = new Cairo.Context (surf);
            Geometry.path (cr, s, 0, 0, vw, vh);
            var path = cr.copy_path ();
            void* raw = (void*) path.data;
            int* ints = (int*) raw;
            double* dbls = (double*) raw;
            var sb = new StringBuilder ();
            int i = 0;
            while (i < path.num_data) {
                int type = ints[i * 4];
                int len = ints[i * 4 + 1];
                if (len <= 0) break;
                switch (type) {
                    case 0:
                        if (sb.len > 0 && !sb.str.has_suffix ("Z ")) sb.append ("N ");
                        sb.append ("M %s %s ".printf (Odf.fixed (dbls[(i + 1) * 2], 1), Odf.fixed (dbls[(i + 1) * 2 + 1], 1)));
                        break;
                    case 1:
                        sb.append ("L %s %s ".printf (Odf.fixed (dbls[(i + 1) * 2], 1), Odf.fixed (dbls[(i + 1) * 2 + 1], 1)));
                        break;
                    case 2:
                        sb.append ("C %s %s %s %s %s %s ".printf (Odf.fixed (dbls[(i + 1) * 2], 1), Odf.fixed (dbls[(i + 1) * 2 + 1], 1),
                            Odf.fixed (dbls[(i + 2) * 2], 1), Odf.fixed (dbls[(i + 2) * 2 + 1], 1),
                            Odf.fixed (dbls[(i + 3) * 2], 1), Odf.fixed (dbls[(i + 3) * 2 + 1], 1)));
                        break;
                    case 3:
                        sb.append ("Z ");
                        break;
                }
                i += len;
            }
            if (!Geometry.is_closed (s)) sb.append ("F ");
            sb.append ("N");
            return sb.str;
        }

        private string graphic_style (Ctx c, Element e, Fill? fill, TextBody? body, string extra = "") {
            var at = new OdpAttrs ();
            if (fill != null) fill_attrs (at, fill, c.theme);
            else at.a ("draw:fill", "none");
            stroke_attrs (at, e.line, c.theme);
            shadow_attrs (at, e.shadow, c.theme);
            if (body != null) body_attrs (at, c, e, body);
            var sh = e as ShapeElement;
            if (sh != null && sh.effects.glow_color != "" && sh.effects.glow_radius > 0) {
                at.a ("loext:glow-radius", Odf.cm (sh.effects.glow_radius)).a ("loext:glow-color", Odf.hex (c.theme.resolve (sh.effects.glow_color)));
            }
            if (sh != null && sh.effects.soft_edge > 0) at.a ("loext:softedge-radius", Odf.cm (sh.effects.soft_edge));
            string inner = "<style:graphic-properties%s%s/>".printf (at.str (), extra);
            return c.styles.add ("graphic", "gr", inner);
        }

        private string placeholder_parent (Ctx c, Element e) {
            switch (e.placeholder) {
                case PlaceholderKind.TITLE: case PlaceholderKind.CENTER_TITLE: return c.mp + "-title";
                case PlaceholderKind.SUBTITLE: return c.mp + "-subtitle";
                case PlaceholderKind.BODY: case PlaceholderKind.OBJECT: return c.mp + "-outline1";
                default: return "";
            }
        }

        private void write_element (XmlOut x, Element e, Ctx c) {
            switch (e.kind) {
                case ElementKind.SHAPE:
                    write_shape (x, (ShapeElement) e, c);
                    break;
                case ElementKind.IMAGE:
                    write_image (x, (ImageElement) e, c);
                    break;
                case ElementKind.TABLE:
                    write_table (x, (TableElement) e, c);
                    break;
                case ElementKind.CHART:
                    write_chart (x, (ChartElement) e, c);
                    break;
                case ElementKind.GROUP:
                    var g = (GroupElement) e;
                    x.start ("draw:g");
                    if (g.name != "") x.a ("draw:name", g.name);
                    write_id (x, g, c);
                    private_attrs (x, g, c);
                    foreach (var child in g.children) write_element (x, child, c);
                    x.end ();
                    break;
                case ElementKind.FOREIGN:
                    var f = (ForeignElement) e;
                    if (f.preview != null) write_element (x, f.preview, c);
                    break;
                case ElementKind.MEDIA:
                    write_media (x, (MediaElement) e, c);
                    break;
                case ElementKind.INK:
                    write_ink (x, (InkElement) e, c);
                    break;
                case ElementKind.ZOOM:
                    write_zoom (x, (ZoomElement) e, c);
                    break;
                case ElementKind.DIAGRAM:
                    var d = (DiagramElement) e;
                    x.start ("draw:g");
                    if (d.name != "") x.a ("draw:name", d.name);
                    write_id (x, d, c);
                    private_attrs (x, d, c);
                    if (include_private) x.a ("sgs:diagram", Odf.diagram_code (d));
                    foreach (var child in d.build ()) write_element (x, child, c);
                    x.end ();
                    break;
                case ElementKind.EQUATION:
                    write_equation (x, (EquationElement) e, c);
                    break;
                case ElementKind.MODEL3D:
                    write_model (x, (Model3DElement) e, c);
                    break;
            }
        }

        private void write_model (XmlOut x, Model3DElement m, Ctx c) {
            var png = MeshPainter.png (m, int.max ((int) (m.w * 2), 16), int.max ((int) (m.h * 2), 16)) ?? m.preview;
            x.start ("draw:frame");
            common_attrs (x, m, c);
            geometry (x, m);
            private_attrs (x, m, c);
            if (include_private) {
                string href = m.data != null ? media_href (m.data, m.format == "obj" ? "model/obj" : "model/gltf-binary", m.format) : "";
                x.a ("sgs:model3d", "%s|%s|%s|%s|%s|%s".printf (Odf.enc (href), m.format, Odf.dbl (m.rot_x), Odf.dbl (m.rot_y), Odf.dbl (m.rot_z), Odf.dbl (m.zoom)));
            }
            if (png != null) x.start ("draw:image").a ("xlink:href", image_href (png, "image/png")).a ("xlink:type", "simple").a ("xlink:show", "embed").a ("xlink:actuate", "onLoad").end ();
            description (x, m);
            x.end ();
        }

        private void write_annotation (XmlOut x, Comment cm, string parent) {
            x.start ("officeooo:annotation").a ("svg:x", Odf.cm (cm.x)).a ("svg:y", Odf.cm (cm.y)).a ("svg:width", "0.5cm").a ("svg:height", "0.5cm");
            if (include_private) x.a ("sgs:comment", "%s|%s|%s".printf (Odf.enc (cm.id), Odf.enc (parent), cm.resolved ? "1" : "0"));
            x.element ("dc:creator", cm.author);
            x.element ("dc:date", cm.date != "" ? cm.date : Comment.now ());
            if (cm.initials != "") x.element ("meta:creator-initials", cm.initials);
            foreach (string line in cm.text.split ("\n")) {
                x.start ("text:p");
                write_run_text (x, line);
                x.end ();
            }
            x.end ();
        }

        private void write_media (XmlOut x, MediaElement m, Ctx c) {
            string st = c.styles.add ("graphic", "gr", "<style:graphic-properties draw:stroke=\"none\" draw:fill=\"none\"/>");
            x.start ("draw:frame").a ("draw:style-name", st);
            common_attrs (x, m, c);
            geometry (x, m);
            private_attrs (x, m, c);
            if (include_private) x.a ("sgs:media", Odf.media_code (m));
            string href = m.data != null ? media_href (m.data, m.mime, m.extension ()) : m.link;
            x.start ("draw:plugin").a ("xlink:href", href).a ("xlink:type", "simple").a ("xlink:show", "embed").a ("xlink:actuate", "onLoad").a ("draw:mime-type", "application/vnd.sun.star.media");
            x.start ("draw:param").a ("draw:name", "Loop").a ("draw:value", m.loop ? "true" : "false").end ();
            x.start ("draw:param").a ("draw:name", "Mute").a ("draw:value", m.muted ? "true" : "false").end ();
            x.start ("draw:param").a ("draw:name", "VolumeDB").a ("draw:value", ((int) Math.round (20 * Math.log10 (double.max (m.volume, 0.001)))).to_string ()).end ();
            x.start ("draw:param").a ("draw:name", "Zoom").a ("draw:value", "fit").end ();
            x.end ();
            var poster = m.poster ?? MediaArt.poster_png (m);
            x.start ("draw:image").a ("xlink:href", image_href (poster, m.poster != null ? m.poster_mime : "image/png")).a ("xlink:type", "simple").a ("xlink:show", "embed").a ("xlink:actuate", "onLoad").end ();
            description (x, m);
            x.end ();
        }

        private void write_ink (XmlOut x, InkElement ink, Ctx c) {
            x.start ("draw:g");
            if (ink.name != "") x.a ("draw:name", ink.name);
            write_id (x, ink, c);
            private_attrs (x, ink, c);
            if (include_private) x.a ("sgs:ink", Odf.ink_code (ink));
            foreach (var s in ink.strokes) {
                if (s.pts.size < 4) continue;
                var col = c.theme.resolve (s.color);
                string gst = c.styles.add ("graphic", "gr", "<style:graphic-properties draw:stroke=\"solid\" svg:stroke-color=\"%s\" svg:stroke-width=\"%s\" svg:stroke-opacity=\"%s\" draw:stroke-linejoin=\"round\" svg:stroke-linecap=\"round\" draw:fill=\"none\"/>".printf (Odf.hex (col), Odf.cm (s.width), Odf.pct (s.highlighter ? 0.4 : s.opacity)));
                double x1 = double.MAX, y1 = double.MAX, x2 = -double.MAX, y2 = -double.MAX;
                for (int i = 0; i + 1 < s.pts.size; i += 2) {
                    x1 = double.min (x1, s.pts[i]);
                    y1 = double.min (y1, s.pts[i + 1]);
                    x2 = double.max (x2, s.pts[i]);
                    y2 = double.max (y2, s.pts[i + 1]);
                }
                double bw = double.max (x2 - x1, 0.5), bh = double.max (y2 - y1, 0.5);
                var sb = new StringBuilder ();
                for (int i = 0; i + 1 < s.pts.size; i += 2) {
                    sb.append ("%s%d %d ".printf (i == 0 ? "M" : "L", (int) Math.round ((s.pts[i] - x1) * 100), (int) Math.round ((s.pts[i + 1] - y1) * 100)));
                }
                x.start ("draw:path").a ("draw:style-name", gst).a ("draw:layer", c.layer);
                x.a ("svg:x", Odf.cm (x1)).a ("svg:y", Odf.cm (y1)).a ("svg:width", Odf.cm (bw)).a ("svg:height", Odf.cm (bh));
                x.a ("svg:viewBox", "0 0 %d %d".printf ((int) Math.round (bw * 100), (int) Math.round (bh * 100))).a ("svg:d", sb.str.strip ());
                x.end ();
            }
            x.end ();
        }

        private void write_zoom (XmlOut x, ZoomElement z, Ctx c) {
            var target = z.target (pres);
            Bytes? img = z.image;
            if (img == null && target != null) img = png_of (renderer.thumbnail (pres, target, (int) Math.ceil (double.max (z.w, 64) * 2)));
            if (img == null) return;
            string st = c.styles.add ("graphic", "gr", "<style:graphic-properties draw:stroke=\"solid\" svg:stroke-color=\"#bfbfbf\" svg:stroke-width=\"0.02cm\" draw:fill=\"none\"/>");
            x.start ("draw:frame").a ("draw:style-name", st);
            common_attrs (x, z, c);
            geometry (x, z);
            private_attrs (x, z, c);
            if (include_private) x.a ("sgs:zoom", "%d|%d|%s|%s|%s|%s|%s".printf ((int) z.zoom, z.target_uid, Odf.enc (z.section_id), z.return_to_zoom ? "1" : "0", z.zoom_transition ? "1" : "0", Odf.dbl (z.transition_duration), z.image != null ? "1" : "0"));
            x.start ("draw:image").a ("xlink:href", image_href (img, z.image != null ? z.image_mime : "image/png")).a ("xlink:type", "simple").a ("xlink:show", "embed").a ("xlink:actuate", "onLoad").end ();
            if (target != null) {
                x.start ("office:event-listeners").start ("presentation:event-listener").a ("script:event-name", "dom:click").a ("presentation:action", "show")
                    .a ("xlink:href", "#" + (page_names[target.uid] ?? "")).a ("xlink:type", "simple").end ().end ();
            }
            x.end ();
        }

        private void write_equation (XmlOut x, EquationElement q, Ctx c) {
            string mml = q.mathml != "" ? q.mathml : (q.omml != "" ? EquationCodec.mathml_from_omml (q.omml) : "");
            x.start ("draw:frame");
            common_attrs (x, q, c);
            geometry (x, q);
            private_attrs (x, q, c);
            if (include_private) x.a ("sgs:equation", "%s|%s".printf (Odf.enc (q.latex), Odf.enc (q.color)));
            if (mml != "") {
                string name = "Object %d".printf (1000 + formula_names.size + 1);
                formula_names.add (name);
                formula_docs.add ("<?xml version=\"1.0\" encoding=\"UTF-8\"?>\n" + mml);
                x.start ("draw:object").a ("xlink:href", "./" + name).a ("xlink:type", "simple").a ("xlink:show", "embed").a ("xlink:actuate", "onLoad").end ();
            }
            if (q.image != null) {
                x.start ("draw:image").a ("xlink:href", image_href (EquationCodec.png_for (q), "image/png")).a ("xlink:type", "simple").a ("xlink:show", "embed").a ("xlink:actuate", "onLoad").end ();
            }
            description (x, q);
            x.end ();
        }

        private void write_shape (XmlOut x, ShapeElement s, Ctx c) {
            string default_color = s.placeholder == PlaceholderKind.NONE ? renderer.default_text_color (c.rctx, s) : "";
            if (s.shape == ShapeKind.LINE && s.placeholder == PlaceholderKind.NONE && !s.text_box) {
                string st = graphic_style (c, s, null, null);
                double x1 = s.flip_h ? s.x + s.w : s.x, y1 = s.flip_v ? s.y + s.h : s.y;
                double x2 = s.flip_h ? s.x : s.x + s.w, y2 = s.flip_v ? s.y : s.y + s.h;
                x.start ("draw:line").a ("draw:style-name", st);
                common_attrs (x, s, c);
                x.a ("svg:x1", Odf.cm (x1)).a ("svg:y1", Odf.cm (y1)).a ("svg:x2", Odf.cm (x2)).a ("svg:y2", Odf.cm (y2));
                private_attrs (x, s, c);
                shape_private (x, s);
                description (x, s);
                if (s.text != null && !s.text.is_empty ()) write_body (x, c, s, s.text, default_color);
                x.end ();
                return;
            }
            bool frame = s.placeholder != PlaceholderKind.NONE || s.text_box;
            if (frame) {
                string st;
                var at = new OdpAttrs ();
                fill_attrs (at, s.fill, c.theme);
                stroke_attrs (at, s.line, c.theme);
                shadow_attrs (at, s.shadow, c.theme);
                var body = s.text ?? new TextBody ();
                body_attrs (at, c, s, body);
                string inner = "<style:graphic-properties%s/>".printf (at.str ());
                string parent = placeholder_parent (c, s);
                x.start ("draw:frame");
                if (s.placeholder != PlaceholderKind.NONE && parent != "") {
                    st = c.styles.add ("presentation", "pr", inner, parent);
                    x.a ("presentation:style-name", st);
                } else {
                    st = c.styles.add ("graphic", "gr", inner);
                    x.a ("draw:style-name", st);
                }
                if (s.placeholder != PlaceholderKind.NONE) {
                    x.a ("presentation:class", Odf.class_of (s.placeholder));
                    if (s.text == null || s.text.is_empty ()) x.a ("presentation:placeholder", "true");
                    x.a ("presentation:user-transformed", "true");
                }
                common_attrs (x, s, c);
                geometry (x, s);
                private_attrs (x, s, c);
                shape_private (x, s);
                x.start ("draw:text-box");
                if (s.text != null) write_body (x, c, s, s.text, default_color);
                x.end ();
                description (x, s);
                x.end ();
                return;
            }
            string st = graphic_style (c, s, s.fill, s.text ?? new TextBody ());
            x.start ("draw:custom-shape").a ("draw:style-name", st);
            common_attrs (x, s, c);
            geometry (x, s);
            private_attrs (x, s, c);
            shape_private (x, s);
            description (x, s);
            if (s.text != null) write_body (x, c, s, s.text, default_color);
            string vb;
            string path;
            if (s.shape == ShapeKind.CUSTOM) {
                vb = "0 0 21600 21600";
                var sb = new StringBuilder ();
                foreach (var cmd in s.path) {
                    switch (cmd.op) {
                        case 'M': sb.append ("M %s %s ".printf (Odf.fixed (cmd.pts[0] * 21600, 1), Odf.fixed (cmd.pts[1] * 21600, 1))); break;
                        case 'L': sb.append ("L %s %s ".printf (Odf.fixed (cmd.pts[0] * 21600, 1), Odf.fixed (cmd.pts[1] * 21600, 1))); break;
                        case 'C':
                            sb.append ("C");
                            for (int k = 0; k < 6; k++) sb.append (" " + Odf.fixed (cmd.pts[k] * 21600, 1));
                            sb.append (" ");
                            break;
                        case 'Q':
                            sb.append ("Q");
                            for (int k = 0; k < 4; k++) sb.append (" " + Odf.fixed (cmd.pts[k] * 21600, 1));
                            sb.append (" ");
                            break;
                        case 'Z': sb.append ("Z "); break;
                    }
                }
                if (!Geometry.is_closed (s)) sb.append ("F ");
                sb.append ("N");
                path = sb.str;
            } else {
                path = enhanced_path (s, out vb);
            }
            x.start ("draw:enhanced-geometry").a ("svg:viewBox", vb).a ("draw:type", s.shape == ShapeKind.PRESET ? Odf.lo_of_preset (s.preset_name ()) : Odf.shape_type (s.shape));
            if (s.shape == ShapeKind.ROUND_RECT) x.a ("draw:modifiers", Odf.fixed (s.corner * 21600, 0));
            if (s.flip_h) x.a ("draw:mirror-horizontal", "true");
            if (s.flip_v) x.a ("draw:mirror-vertical", "true");
            x.a ("draw:enhanced-path", path);
            x.end ();
            x.end ();
        }

        private void shape_private (XmlOut x, ShapeElement s) {
            if (!include_private) return;
            x.a ("sgs:shape", "%d|%s|%s|%s|%s".printf ((int) s.shape, Odf.dbl (s.corner), Odf.dbl (s.adjust), s.text_box ? "1" : "0", Odf.enc (Odf.path_code (s.path))));
            if (s.shape == ShapeKind.PRESET || s.adjust_values.size > 0) {
                var sb = new StringBuilder (s.preset);
                foreach (var e in s.adjust_values.entries) sb.append ("|%s|%s".printf (e.key, Odf.dbl (e.value)));
                x.a ("sgs:preset", sb.str);
            }
            x.a ("sgs:fill", Odf.fill_code (s.fill));
            if (s.text != null) x.a ("sgs:body", Odf.body_code (s.text));
            else x.a ("sgs:body", "none");
            if (s.list_style != null) x.a ("sgs:liststyle", Odf.style_code (s.list_style));
            if (s.effects.has_shape_effects () || s.effects.has_text_effects ()) x.a ("sgs:fx", Odf.fx_code (s.effects));
        }

        private void write_image (XmlOut x, ImageElement img, Ctx c) {
            var at = new OdpAttrs ();
            at.a ("draw:fill", "none");
            stroke_attrs (at, img.line, c.theme);
            shadow_attrs (at, img.shadow, c.theme);
            if (img.brightness != 0) at.a ("draw:luminance", Odf.pct (img.brightness));
            if (img.contrast != 0) at.a ("draw:contrast", Odf.pct (img.contrast));
            if (img.saturation == 0) at.a ("draw:color-mode", "greyscale");
            if (img.opacity < 1) at.a ("draw:image-opacity", Odf.pct (img.opacity));
            if (img.flip_h || img.flip_v) at.a ("style:mirror", img.flip_h && img.flip_v ? "horizontal vertical" : (img.flip_h ? "horizontal" : "vertical"));
            int pw = img.pixel_width, ph = img.pixel_height;
            if (pw <= 0 || ph <= 0) ImageCache.size_of (img.data, out pw, out ph);
            if ((img.crop_left + img.crop_top + img.crop_right + img.crop_bottom) > 0 && pw > 0 && ph > 0) {
                double nw = pw * 0.75, nh = ph * 0.75;
                at.a ("fo:clip", "rect(%s, %s, %s, %s)".printf (Odf.cm (img.crop_top * nh), Odf.cm (img.crop_right * nw), Odf.cm (img.crop_bottom * nh), Odf.cm (img.crop_left * nw)));
            }
            string inner = "<style:graphic-properties%s/>".printf (at.str ());
            string st = c.styles.add ("graphic", "gr", inner);
            x.start ("draw:frame").a ("draw:style-name", st);
            if (img.placeholder != PlaceholderKind.NONE) x.a ("presentation:class", "graphic").a ("presentation:user-transformed", "true");
            common_attrs (x, img, c);
            geometry (x, img);
            private_attrs (x, img, c);
            if (include_private) {
                x.a ("sgs:image", "%s|%s|%s|%s|%s|%s|%s|%s|%s|%s|%s|%d|%d".printf (Odf.dbl (img.crop_left), Odf.dbl (img.crop_top), Odf.dbl (img.crop_right), Odf.dbl (img.crop_bottom),
                    Odf.dbl (img.brightness), Odf.dbl (img.contrast), Odf.dbl (img.saturation), img.sepia ? "1" : "0", Odf.dbl (img.opacity), Odf.dbl (img.blur), Odf.dbl (img.corner), img.pixel_width, img.pixel_height));
            }
            string href = image_href (img.data, img.mime);
            x.start ("draw:image").a ("xlink:href", href).a ("xlink:type", "simple").a ("xlink:show", "embed").a ("xlink:actuate", "onLoad").a ("draw:mime-type", img.mime);
            x.start ("text:p").end ();
            x.end ();
            description (x, img);
            x.end ();
        }

        private void write_table (XmlOut x, TableElement t, Ctx c) {
            x.start ("draw:frame");
            if (t.placeholder != PlaceholderKind.NONE) x.a ("presentation:class", "table");
            common_attrs (x, t, c);
            geometry (x, t);
            private_attrs (x, t, c);
            if (include_private) {
                x.a ("sgs:table", "%s|%s|%s|%s|%s|%s".printf (t.first_row ? "1" : "0", t.first_col ? "1" : "0", t.last_row ? "1" : "0", t.banded_rows ? "1" : "0", t.banded_cols ? "1" : "0", Odf.enc (t.style_color)));
                x.a ("sgs:border", Odf.line_code (t.border));
            }
            x.start ("table:table");
            x.a ("table:use-first-row-styles", t.first_row ? "true" : "false");
            x.a ("table:use-last-row-styles", t.last_row ? "true" : "false");
            x.a ("table:use-first-column-styles", t.first_col ? "true" : "false");
            x.a ("table:use-banding-rows-styles", t.banded_rows ? "true" : "false");
            x.a ("table:use-banding-columns-styles", t.banded_cols ? "true" : "false");
            for (int col = 0; col < t.cols; col++) {
                string cs = c.styles.add ("table-column", "co", "<style:table-column-properties style:column-width=\"%s\"/>".printf (Odf.cm (t.col_widths[col])));
                x.start ("table:table-column").a ("table:style-name", cs).end ();
            }
            for (int r = 0; r < t.rows; r++) {
                string rs = c.styles.add ("table-row", "ro", "<style:table-row-properties style:row-height=\"%s\"/>".printf (Odf.cm (t.row_heights[r])));
                x.start ("table:table-row").a ("table:style-name", rs);
                for (int col = 0; col < t.cols; col++) {
                    var cell = t.cells[r][col];
                    if (cell.covered) {
                        x.empty ("table:covered-table-cell");
                        continue;
                    }
                    string fill = renderer.table_cell_fill (t, r, col);
                    var fc = c.theme.resolve (fill);
                    var at = new OdpAttrs ();
                    at.a ("draw:fill", "solid").a ("draw:fill-color", Odf.hex (fc));
                    if (fc.a < 0.999) at.a ("draw:opacity", Odf.pct (fc.a));
                    at.a ("draw:textarea-vertical-align", cell.anchor == TextAnchor.MIDDLE ? "middle" : (cell.anchor == TextAnchor.BOTTOM ? "bottom" : "top"));
                    at.a ("fo:padding-left", Odf.cm (cell.text.inset_left)).a ("fo:padding-right", Odf.cm (cell.text.inset_right));
                    at.a ("fo:padding-top", Odf.cm (cell.text.inset_top)).a ("fo:padding-bottom", Odf.cm (cell.text.inset_bottom));
                    var border = t.border.visible () ? "%s solid %s".printf (Odf.cm (t.border.width), Odf.hex (c.theme.resolve (t.border.color))) : "none";
                    string inner = "<style:graphic-properties%s/><style:table-cell-properties fo:border=\"%s\" style:vertical-align=\"%s\"/>".printf (at.str (), border,
                        cell.anchor == TextAnchor.MIDDLE ? "middle" : (cell.anchor == TextAnchor.BOTTOM ? "bottom" : "top"));
                    string ce = c.styles.add ("table-cell", "ce", inner);
                    x.start ("table:table-cell").a ("table:style-name", ce);
                    if (cell.col_span > 1) x.a ("table:number-columns-spanned", cell.col_span.to_string ());
                    if (cell.row_span > 1) x.a ("table:number-rows-spanned", cell.row_span.to_string ());
                    if (include_private) {
                        x.a ("sgs:fill", Odf.enc (cell.fill));
                        x.a ("sgs:anchor", ((int) cell.anchor).to_string ());
                        x.a ("sgs:body", Odf.body_code (cell.text));
                    }
                    string col_hex = fc.a > 0.3 ? Renderer.contrast_for (c.rctx, fc) : "";
                    write_body (x, c, t, cell.text, col_hex, renderer.table_cell_bold (t, r, col));
                    x.end ();
                }
                x.end ();
            }
            x.end ();
            x.end ();
        }

        private string chart_class (ChartKind k) {
            switch (k) {
                case ChartKind.LINE: return "chart:line";
                case ChartKind.PIE: return "chart:circle";
                case ChartKind.DOUGHNUT: return "chart:ring";
                case ChartKind.AREA: return "chart:area";
                case ChartKind.SCATTER: return "chart:scatter";
                case ChartKind.RADAR: return "chart:radar";
                case ChartKind.BUBBLE: return "chart:bubble";
                default: return "chart:bar";
            }
        }

        private string series_class (ChartElement ch, ChartSeries s) {
            if (ch.chart == ChartKind.RADAR && ch.grouping == ChartGrouping.STACKED) return "chart:filled-radar";
            if (ch.chart.is_radial () || ch.chart == ChartKind.SCATTER || ch.chart == ChartKind.BUBBLE || ch.chart == ChartKind.RADAR) return chart_class (ch.chart);
            switch (ch.series_kind (s)) {
                case SeriesKind.LINE: return "chart:line";
                case SeriesKind.AREA: return "chart:area";
                default: return "chart:bar";
            }
        }

        private static string axis_props (ChartAxis ax) {
            var sb = new StringBuilder ();
            if (!ax.min.is_nan ()) sb.append (" chart:minimum=\"%s\"".printf (Odf.dbl (ax.min)));
            if (!ax.max.is_nan ()) sb.append (" chart:maximum=\"%s\"".printf (Odf.dbl (ax.max)));
            if (ax.major > 0) sb.append (" chart:interval-major=\"%s\"".printf (Odf.dbl (ax.major)));
            if (ax.log_base > 1) sb.append (" chart:logarithmic=\"true\"");
            if (ax.reverse) sb.append (" chart:reverse-direction=\"true\"");
            sb.append (" chart:display-label=\"%s\"".printf (ax.visible ? "true" : "false"));
            return sb.str;
        }

        private static string col_letter (int c) {
            var sb = new StringBuilder ();
            int n = c + 1;
            while (n > 0) {
                int r = (n - 1) % 26;
                sb.prepend_c ((char) ('A' + r));
                n = (n - 1) / 26;
            }
            return sb.str;
        }

        private string chart_document (ChartElement ch, Theme t) {
            var x = new XmlOut ();
            x.raw ("<office:document-content" + Odf.ns_decls () + ">");
            x.start ("office:automatic-styles");
            var cp = new OdpAttrs ();
            if (ch.grouping == ChartGrouping.STACKED) cp.a ("chart:stacked", "true");
            if (ch.grouping == ChartGrouping.PERCENT) cp.a ("chart:percentage", "true");
            if (ch.chart == ChartKind.BAR) cp.a ("chart:vertical", "true");
            if (ch.smooth) cp.a ("chart:interpolation", "cubic-spline");
            if (ch.chart == ChartKind.LINE || ch.chart == ChartKind.SCATTER) cp.a ("chart:symbol-type", "automatic");
            if (ch.data_labels) cp.a ("chart:data-label-number", ch.chart.is_radial () ? "percentage" : "value");
            if (ch.chart == ChartKind.COLUMN || ch.chart == ChartKind.BAR) cp.a ("chart:gap-width", "50").a ("chart:overlap", ch.grouping == ChartGrouping.CLUSTERED ? "0" : "100");
            x.raw ("<style:style style:name=\"ch1\" style:family=\"chart\"><style:graphic-properties draw:fill=\"none\" draw:stroke=\"none\"/></style:style>");
            x.raw ("<style:style style:name=\"ch2\" style:family=\"chart\"><style:chart-properties%s/></style:style>".printf (cp.str ()));
            Rgba fg = ch.text_color != "" ? t.resolve (ch.text_color) : t.resolve ("dk1");
            x.raw ("<style:style style:name=\"ch3\" style:family=\"chart\"><style:text-properties fo:color=\"%s\"/></style:style>".printf (Odf.hex (fg)));
            x.raw ("<style:style style:name=\"ch4\" style:family=\"chart\"><style:chart-properties chart:display-label=\"true\"/><style:text-properties fo:color=\"%s\"/></style:style>".printf (Odf.hex (fg)));
            string[] ax_names = { "ax1", "ax2", "ax3" };
            ChartAxis[] axes = { ch.cat_axis, ch.val_axis, ch.sec_axis };
            for (int k = 0; k < 3; k++) x.raw ("<style:style style:name=\"%s\" style:family=\"chart\"><style:chart-properties%s/><style:text-properties fo:color=\"%s\"/></style:style>".printf (ax_names[k], axis_props (axes[k]), Odf.hex (fg)));
            for (int i = 0; i < ch.series.size; i++) {
                var se = ch.series[i];
                if (se.trend == TrendKind.NONE) continue;
                var rc = new StringBuilder (" chart:regression-type=\"%s\"".printf (se.trend.to_odf ()));
                if (se.trend == TrendKind.POLYNOMIAL) rc.append (" chart:regression-max-degree=\"%d\"".printf (se.trend_order));
                if (se.trend == TrendKind.MOVING_AVERAGE) rc.append (" chart:regression-period=\"%d\"".printf (se.trend_period));
                var col = t.resolve (ChartPainter.series_color (ch, i));
                x.raw ("<style:style style:name=\"cr%d\" style:family=\"chart\"><style:chart-properties%s/><style:graphic-properties svg:stroke-color=\"%s\" draw:stroke=\"dash\"/></style:style>".printf (i + 1, rc.str, Odf.hex (col)));
            }
            int nser = ch.series.size;
            if (ch.chart.is_radial ()) {
                for (int i = 0; i < ch.categories.size; i++) {
                    var col = t.resolve (ChartPainter.palette (i));
                    x.raw ("<style:style style:name=\"cp%d\" style:family=\"chart\"><style:graphic-properties draw:fill=\"solid\" draw:fill-color=\"%s\"/></style:style>".printf (i + 1, Odf.hex (col)));
                }
            }
            for (int i = 0; i < nser; i++) {
                var col = t.resolve (ChartPainter.series_color (ch, i));
                x.raw ("<style:style style:name=\"cs%d\" style:family=\"chart\"><style:graphic-properties draw:fill=\"solid\" draw:fill-color=\"%s\" svg:stroke-color=\"%s\" svg:stroke-width=\"0.08cm\"/></style:style>".printf (i + 1, Odf.hex (col), Odf.hex (col)));
            }
            x.end ();
            x.start ("office:body").start ("office:chart");
            x.start ("chart:chart").a ("svg:width", Odf.cm (ch.w)).a ("svg:height", Odf.cm (ch.h)).a ("chart:class", chart_class (ch.chart)).a ("chart:style-name", "ch1");
            if (include_private) {
                var colors = new StringBuilder ();
                for (int i = 0; i < ch.series.size; i++) {
                    if (i > 0) colors.append (",");
                    colors.append (Odf.enc (ch.series[i].color));
                }
                x.a ("sgs:chart", "%d|%d|%s|%d|%s|%s|%s|%s|%s".printf ((int) ch.chart, (int) ch.grouping, Odf.enc (ch.title), (int) ch.legend, ch.data_labels ? "1" : "0",
                    ch.gridlines ? "1" : "0", ch.smooth ? "1" : "0", Odf.enc (ch.text_color), colors.str));
                x.a ("sgs:chartx", Odf.chart_extra (ch));
            }
            if (ch.title != "") x.start ("chart:title").a ("chart:style-name", "ch3").start ("text:p").text (ch.title).end ().end ();
            if (ch.legend != LegendPosition.NONE) {
                string pos;
                switch (ch.legend) {
                    case LegendPosition.RIGHT: pos = "end"; break;
                    case LegendPosition.TOP: pos = "top"; break;
                    case LegendPosition.LEFT: pos = "start"; break;
                    default: pos = "bottom"; break;
                }
                x.start ("chart:legend").a ("chart:legend-position", pos).a ("chart:style-name", "ch3").end ();
            }
            int ncat = ch.categories.size;
            foreach (var s in ch.series) ncat = int.max (ncat, s.values.size);
            bool bubble = ch.chart == ChartKind.BUBBLE;
            string last_col = col_letter (bubble ? nser * 2 : nser);
            x.start ("chart:plot-area").a ("chart:style-name", "ch2").a ("chart:data-source-has-labels", "both");
            x.a ("table:cell-range-address", "local-table.$A$1:.$%s$%d".printf (last_col, ncat + 1));
            if (!ch.chart.is_radial ()) {
                x.start ("chart:axis").a ("chart:dimension", "x").a ("chart:name", "primary-x").a ("chart:style-name", "ax1");
                if (ch.cat_axis.title != "") x.start ("chart:title").a ("chart:style-name", "ch3").start ("text:p").text (ch.cat_axis.title).end ().end ();
                x.start ("chart:categories").a ("table:cell-range-address", "local-table.$A$2:.$A$%d".printf (ncat + 1)).end ();
                x.end ();
                x.start ("chart:axis").a ("chart:dimension", "y").a ("chart:name", "primary-y").a ("chart:style-name", "ax2");
                if (ch.val_axis.title != "") x.start ("chart:title").a ("chart:style-name", "ch3").start ("text:p").text (ch.val_axis.title).end ().end ();
                if (ch.gridlines) x.start ("chart:grid").a ("chart:class", "major").end ();
                x.end ();
                if (ch.has_secondary ()) {
                    x.start ("chart:axis").a ("chart:dimension", "y").a ("chart:name", "secondary-y").a ("chart:style-name", "ax3");
                    if (ch.sec_axis.title != "") x.start ("chart:title").a ("chart:style-name", "ch3").start ("text:p").text (ch.sec_axis.title).end ().end ();
                    x.end ();
                }
            }
            for (int i = 0; i < nser; i++) {
                string col = col_letter (bubble ? 1 + i * 2 : i + 1);
                x.start ("chart:series").a ("chart:style-name", "cs%d".printf (i + 1));
                if (bubble) {
                    string zc = col_letter (2 + i * 2);
                    x.a ("chart:values-cell-range-address", "local-table.$%s$2:.$%s$%d".printf (zc, zc, ncat + 1));
                } else {
                    x.a ("chart:values-cell-range-address", "local-table.$%s$2:.$%s$%d".printf (col, col, ncat + 1));
                }
                x.a ("chart:label-cell-address", "local-table.$%s$1".printf (col));
                x.a ("chart:class", series_class (ch, ch.series[i]));
                if (ch.has_secondary () && ch.series[i].secondary) x.a ("chart:attached-axis", "secondary-y");
                if (bubble) {
                    x.start ("chart:domain").a ("table:cell-range-address", "local-table.$%s$2:.$%s$%d".printf (col, col, ncat + 1)).end ();
                    x.start ("chart:domain").a ("table:cell-range-address", "local-table.$A$2:.$A$%d".printf (ncat + 1)).end ();
                } else if (ch.chart == ChartKind.SCATTER) {
                    x.start ("chart:domain").a ("table:cell-range-address", "local-table.$A$2:.$A$%d".printf (ncat + 1)).end ();
                }
                if (ch.series[i].trend != TrendKind.NONE) {
                    x.start ("chart:regression-curve").a ("chart:style-name", "cr%d".printf (i + 1));
                    if (ch.series[i].trend_equation || ch.series[i].trend_r2) x.start ("chart:equation").a ("chart:display-equation", ch.series[i].trend_equation ? "true" : "false").a ("chart:display-r-square", ch.series[i].trend_r2 ? "true" : "false").end ();
                    x.end ();
                }
                if (ch.chart.is_radial ()) {
                    for (int k = 0; k < ncat; k++) x.start ("chart:data-point").a ("chart:style-name", "cp%d".printf (k + 1)).end ();
                } else {
                    x.start ("chart:data-point").a ("chart:repeated", ncat.to_string ()).end ();
                }
                x.end ();
            }
            x.end ();
            x.end ();
            x.start ("table:table").a ("table:name", "local-table");
            x.start ("table:table-header-columns").empty ("table:table-column").end ();
            x.start ("table:table-columns").start ("table:table-column").a ("table:number-columns-repeated", int.max (bubble ? nser * 2 : nser, 1).to_string ()).end ().end ();
            x.start ("table:table-header-rows").start ("table:table-row");
            x.start ("table:table-cell").start ("text:p").end ().end ();
            foreach (var s in ch.series) {
                x.start ("table:table-cell").a ("office:value-type", "string").start ("text:p").text (s.name).end ().end ();
                if (bubble) x.start ("table:table-cell").a ("office:value-type", "string").start ("text:p").text (_("Size")).end ().end ();
            }
            x.end ().end ();
            x.start ("table:table-rows");
            for (int k = 0; k < ncat; k++) {
                x.start ("table:table-row");
                x.start ("table:table-cell").a ("office:value-type", "string").start ("text:p").text (k < ch.categories.size ? ch.categories[k] : "").end ().end ();
                foreach (var s in ch.series) {
                    if (k < s.values.size && s.values[k] != null) {
                        double v = s.values[k];
                        x.start ("table:table-cell").a ("office:value-type", "float").a ("office:value", Odf.dbl (v)).start ("text:p").text (Odf.dbl (v)).end ().end ();
                    } else {
                        x.start ("table:table-cell").start ("text:p").end ().end ();
                    }
                    if (!bubble) continue;
                    if (k < s.sizes.size && s.sizes[k] != null) {
                        double z = s.sizes[k];
                        x.start ("table:table-cell").a ("office:value-type", "float").a ("office:value", Odf.dbl (z)).start ("text:p").text (Odf.dbl (z)).end ().end ();
                    } else {
                        x.start ("table:table-cell").start ("text:p").end ().end ();
                    }
                }
                x.end ();
            }
            x.end ();
            x.end ();
            x.end ().end ();
            x.raw ("</office:document-content>");
            return x.finish ();
        }

        private void write_chart (XmlOut x, ChartElement ch, Ctx c) {
            string name = "Object %d".printf (chart_names.size + 1);
            chart_names.add (name);
            chart_docs.add (chart_document (ch, c.theme));
            x.start ("draw:frame");
            if (ch.placeholder != PlaceholderKind.NONE) x.a ("presentation:class", "chart");
            common_attrs (x, ch, c);
            geometry (x, ch);
            private_attrs (x, ch, c);
            x.start ("draw:object").a ("xlink:href", "./" + name).a ("xlink:type", "simple").a ("xlink:show", "embed").a ("xlink:actuate", "onLoad").end ();
            description (x, ch);
            x.end ();
        }

        private Ctx make_ctx (Slide? s, Layout? l, Master m, bool on_master, string mp) {
            var c = new Ctx ();
            c.slide = s;
            c.layout = l;
            c.master = m;
            c.theme = m.theme;
            c.on_master = on_master;
            c.styles = on_master ? master_styles : content_styles;
            c.mp = mp;
            c.layer = on_master ? "backgroundobjects" : "layout";
            c.rctx = new RenderContext (pres, s, l, m);
            return c;
        }

        private string page_fill_props (Fill? f, Theme t) {
            var at = new OdpAttrs ();
            if (f == null) return "";
            if (f.kind == FillKind.NONE) at.a ("draw:fill", "solid").a ("draw:fill-color", "#ffffff");
            else fill_attrs (at, f, t);
            at.a ("draw:background-size", "full");
            return at.str ();
        }

        private string level_text_props (LevelStyle ls, Theme t) {
            var at = new OdpAttrs ();
            if (ls.size > 0) at.a ("fo:font-size", Odf.pt (ls.size));
            string font = t.resolve_font (ls.font);
            at.a ("fo:font-family", font).a ("style:font-name", font);
            if (ls.color != "") {
                var c = t.resolve (ls.color);
                at.a ("fo:color", Odf.hex (c));
            }
            if (ls.bold >= 0) at.a ("fo:font-weight", ls.bold == 1 ? "bold" : "normal");
            if (ls.italic >= 0) at.a ("fo:font-style", ls.italic == 1 ? "italic" : "normal");
            return at.str ();
        }

        private string level_para_props (LevelStyle ls) {
            var at = new OdpAttrs ();
            switch (ls.align) {
                case TextAlign.CENTER: at.a ("fo:text-align", "center"); break;
                case TextAlign.RIGHT: at.a ("fo:text-align", "end"); break;
                case TextAlign.JUSTIFY: at.a ("fo:text-align", "justify"); break;
                case TextAlign.LEFT: at.a ("fo:text-align", "start"); break;
                default: break;
            }
            if (ls.space_before >= 0) at.a ("fo:margin-top", Odf.cm (ls.space_before));
            if (ls.space_after >= 0) at.a ("fo:margin-bottom", Odf.cm (ls.space_after));
            if (ls.line_spacing > 0) at.a ("fo:line-height", Odf.pct (ls.line_spacing));
            if (ls.margin >= 0) at.a ("fo:margin-left", Odf.cm (ls.margin));
            if (ls.indent != 0) at.a ("fo:text-indent", Odf.cm (ls.indent));
            return at.str ();
        }

        private Element? layout_ph (Layout? l, Master m, PlaceholderKind k) {
            if (l != null) {
                foreach (var e in l.elements) if (e.placeholder.matches (k) && !(k == PlaceholderKind.BODY && e.placeholder == PlaceholderKind.SUBTITLE)) return e;
            }
            return m.find_placeholder (k);
        }

        private void presentation_styles (StringBuilder sb, string mp, Master m, Layout? l) {
            var t = m.theme;
            var title_e = layout_ph (l, m, PlaceholderKind.TITLE);
            var body_e = layout_ph (l, m, PlaceholderKind.BODY);
            var sub_e = l != null ? l.find_placeholder (PlaceholderKind.SUBTITLE, -1) : null;
            var tls = title_e != null ? pres.level_style (null, l, m, title_e, 0) : m.title_style.level (0).clone ();
            sb.append ("<style:style style:name=\"%s-title\" style:family=\"presentation\"><style:graphic-properties draw:stroke=\"none\" draw:fill=\"none\" draw:auto-grow-height=\"false\" draw:textarea-vertical-align=\"middle\"/><style:paragraph-properties%s/><style:text-properties%s/></style:style>".printf (
                mp, level_para_props (tls), level_text_props (tls, t)));
            for (int lv = 0; lv < 9; lv++) {
                var ls = body_e != null ? pres.level_style (null, l, m, body_e, lv) : m.body_style.level (lv).clone ();
                string parent = lv == 0 ? "" : " style:parent-style-name=\"%s-outline%d\"".printf (mp, lv);
                string list = "";
                if (lv == 0) {
                    var lb = new StringBuilder ();
                    for (int k = 0; k < 9; k++) {
                        var lk = body_e != null ? pres.level_style (null, l, m, body_e, k) : m.body_style.level (k);
                        lb.append (list_level_xml (k, lk.bullet == BulletKind.NUMBER ? BulletKind.NUMBER : BulletKind.CHAR, lk.bullet_char, NumberStyle.ARABIC_PERIOD, 1, lk.margin >= 0 ? lk.margin : 0, lk.indent, ""));
                    }
                    list = "<text:list-style style:name=\"%s-outline-list\">%s</text:list-style>".printf (mp, lb.str);
                }
                sb.append ("<style:style style:name=\"%s-outline%d\" style:family=\"presentation\"%s><style:graphic-properties draw:stroke=\"none\" draw:fill=\"none\" draw:auto-grow-height=\"false\">%s</style:graphic-properties><style:paragraph-properties%s/><style:text-properties%s/></style:style>".printf (
                    mp, lv + 1, parent, list, level_para_props (ls), level_text_props (ls, t)));
            }
            var sls = sub_e != null ? pres.level_style (null, l, m, sub_e, 0) : m.body_style.level (0).clone ();
            sb.append ("<style:style style:name=\"%s-subtitle\" style:family=\"presentation\"><style:graphic-properties draw:stroke=\"none\" draw:fill=\"none\" draw:textarea-vertical-align=\"middle\"/><style:paragraph-properties%s/><style:text-properties%s/></style:style>".printf (
                mp, level_para_props (sls), level_text_props (sls, t)));
            var ols = m.other_style.level (0);
            sb.append ("<style:style style:name=\"%s-notes\" style:family=\"presentation\"><style:paragraph-properties fo:margin-left=\"0cm\"/><style:text-properties fo:font-size=\"20pt\"/></style:style>".printf (mp));
            sb.append ("<style:style style:name=\"%s-backgroundobjects\" style:family=\"presentation\"><style:graphic-properties draw:shadow=\"hidden\"/></style:style>".printf (mp));
            sb.append ("<style:style style:name=\"%s-background\" style:family=\"presentation\"><style:graphic-properties draw:stroke=\"none\" draw:fill=\"none\"/></style:style>".printf (mp));
            sb.append ("<style:style style:name=\"%s-other\" style:family=\"presentation\"><style:text-properties%s/></style:style>".printf (mp, level_text_props (ols, t)));
        }

        private string page_layout_xml (Layout l, string name) {
            var sb = new StringBuilder ();
            sb.append ("<style:presentation-page-layout style:name=\"%s\" style:display-name=\"%s\">".printf (name, XmlOut.esc (l.name)));
            foreach (var e in l.elements) {
                if (e.placeholder == PlaceholderKind.NONE || e.placeholder.is_meta ()) continue;
                string obj;
                switch (e.placeholder) {
                    case PlaceholderKind.TITLE: case PlaceholderKind.CENTER_TITLE: obj = "title"; break;
                    case PlaceholderKind.SUBTITLE: obj = "subtitle"; break;
                    case PlaceholderKind.PICTURE: obj = "graphic"; break;
                    default: obj = "outline"; break;
                }
                double x, y, w, h;
                pres.effective_geometry (null, l, pres.master_of_layout (l) ?? pres.master, e, out x, out y, out w, out h);
                sb.append ("<presentation:placeholder presentation:object=\"%s\" svg:x=\"%s\" svg:y=\"%s\" svg:width=\"%s\" svg:height=\"%s\"/>".printf (obj, Odf.cm (x), Odf.cm (y), Odf.cm (w), Odf.cm (h)));
            }
            sb.append ("</style:presentation-page-layout>");
            return sb.str;
        }

        private string master_pages_xml (StringBuilder presentation_sb, StringBuilder layouts_sb) {
            var x = new XmlOut (false);
            int mi = 0;
            foreach (var m in pres.masters) {
                mi++;
                string mname = "Mst%d".printf (mi);
                master_pages[m] = mname;
                presentation_styles (presentation_sb, mname, m, null);
                string dp = master_styles.add ("drawing-page", "dp", "<style:drawing-page-properties%s/>".printf (page_fill_props (m.background, m.theme)));
                x.start ("style:master-page").a ("style:name", mname).a ("style:display-name", m.name != "" ? m.name : mname).a ("style:page-layout-name", "PM1").a ("draw:style-name", dp);
                if (include_private) {
                    x.a ("sgs:role", "master").a ("sgs:id", m.id).a ("sgs:name", m.name);
                    x.a ("sgs:theme", Odf.theme_code (m.theme));
                    x.a ("sgs:bg", Odf.fill_code (m.background));
                    x.a ("sgs:title-style", Odf.style_code (m.title_style));
                    x.a ("sgs:body-style", Odf.style_code (m.body_style));
                    x.a ("sgs:other-style", Odf.style_code (m.other_style));
                }
                var c = make_ctx (null, null, m, true, mname);
                foreach (var e in m.elements) write_element (x, e, c);
                x.end ();
                int li = 0;
                foreach (var l in m.layouts) {
                    li++;
                    string lname = "M%dL%d".printf (mi, li);
                    layout_pages[l] = lname;
                    string plname = "AL%d_%d".printf (mi, li);
                    page_layout_names[lname] = plname;
                    layouts_sb.append (page_layout_xml (l, plname));
                    presentation_styles (presentation_sb, lname, m, l);
                    string ldp = master_styles.add ("drawing-page", "dp", "<style:drawing-page-properties%s/>".printf (page_fill_props (l.background ?? m.background, m.theme)));
                    x.start ("style:master-page").a ("style:name", lname).a ("style:display-name", l.name != "" ? l.name : lname).a ("style:page-layout-name", "PM1").a ("draw:style-name", ldp);
                    if (include_private) {
                        x.a ("sgs:role", "layout").a ("sgs:master", m.id).a ("sgs:layout-id", l.id).a ("sgs:name", l.name);
                        x.a ("sgs:layout-kind", ((int) l.kind).to_string ()).a ("sgs:show-master", l.show_master_shapes ? "1" : "0");
                        x.a ("sgs:bg", l.background != null ? Odf.fill_code (l.background) : "inherit");
                    }
                    var lc = make_ctx (null, l, m, true, lname);
                    if (l.show_master_shapes) {
                        var mc = make_ctx (null, null, m, true, lname);
                        mc.origin = "master";
                        foreach (var e in m.elements) if (e.placeholder == PlaceholderKind.NONE) write_element (x, e, mc);
                    }
                    foreach (var e in l.elements) write_element (x, e, lc);
                    x.end ();
                }
            }
            return x.finish ();
        }

        private string page_name (Slide s) {
            var m = pres.master_for (s);
            var l = pres.layout_for (s);
            if (l != null && layout_pages.has_key (l)) return layout_pages[l];
            return master_pages.has_key (m) ? master_pages[m] : "Mst1";
        }

        private string transition_props (Slide s) {
            var t = s.transition;
            var at = new OdpAttrs ();
            if (t.advance_after >= 0) {
                at.a ("presentation:transition-type", t.on_click ? "semi-automatic" : "automatic");
                at.a ("presentation:duration", Odf.duration (t.advance_after));
            } else {
                at.a ("presentation:transition-type", "manual");
            }
            string sub = Odf.subtype_of (t.direction);
            switch (t.kind) {
                case TransitionKind.FADE:
                    at.a ("smil:type", "fade").a ("smil:subtype", "crossfade");
                    break;
                case TransitionKind.FADE_BLACK:
                    at.a ("smil:type", "fade").a ("smil:subtype", "fadeOverColor").a ("smil:fadeColor", "#000000");
                    break;
                case TransitionKind.PUSH:
                    at.a ("smil:type", "pushWipe").a ("smil:subtype", sub);
                    break;
                case TransitionKind.WIPE:
                    bool horizontal = t.direction == Direction.FROM_LEFT || t.direction == Direction.FROM_RIGHT;
                    at.a ("smil:type", "barWipe").a ("smil:subtype", horizontal ? "leftToRight" : "topToBottom");
                    if (t.direction == Direction.FROM_RIGHT || t.direction == Direction.FROM_BOTTOM) at.a ("smil:direction", "reverse");
                    break;
                case TransitionKind.COVER:
                    at.a ("smil:type", "slideWipe").a ("smil:subtype", sub);
                    break;
                case TransitionKind.UNCOVER:
                    at.a ("smil:type", "slideWipe").a ("smil:subtype", sub).a ("smil:direction", "reverse");
                    break;
                case TransitionKind.SPLIT:
                    at.a ("smil:type", "barnDoorWipe").a ("smil:subtype", "vertical");
                    break;
                case TransitionKind.ZOOM:
                    at.a ("smil:type", "irisWipe").a ("smil:subtype", "rectangle");
                    break;
                case TransitionKind.DISSOLVE:
                    at.a ("smil:type", "dissolve");
                    break;
                case TransitionKind.CIRCLE:
                    if (t.variant == 1) at.a ("smil:type", "irisWipe").a ("smil:subtype", "diamond");
                    else if (t.variant == 2) at.a ("smil:type", "fourBoxWipe").a ("smil:subtype", "cornersIn");
                    else at.a ("smil:type", "ellipseWipe").a ("smil:subtype", "circle");
                    break;
                case TransitionKind.RANDOM_BARS:
                    at.a ("smil:type", "randomBarWipe").a ("smil:subtype", t.variant == 1 ? "horizontal" : "vertical");
                    break;
                case TransitionKind.CHECKERBOARD:
                    at.a ("smil:type", "checkerBoardWipe").a ("smil:subtype", t.variant == 0 ? "down" : "across");
                    break;
                case TransitionKind.BLINDS:
                    at.a ("smil:type", "blindsWipe").a ("smil:subtype", t.variant == 0 ? "vertical" : "horizontal");
                    break;
                case TransitionKind.CLOCK:
                    if (t.variant == 2) at.a ("smil:type", "fanWipe").a ("smil:subtype", "centerTop");
                    else at.a ("smil:type", "clockWipe").a ("smil:subtype", "clockwiseTwelve");
                    if (t.variant == 1) at.a ("smil:direction", "reverse");
                    break;
                case TransitionKind.STRIPS:
                    at.a ("smil:type", "waterfallWipe").a ("smil:subtype", "horizontalLeft");
                    break;
                case TransitionKind.COMB:
                    at.a ("smil:type", "pushWipe").a ("smil:subtype", t.variant == 0 ? "combVertical" : "combHorizontal");
                    break;
                case TransitionKind.NEWSFLASH:
                    at.a ("smil:type", "zoom").a ("smil:subtype", "rotateIn");
                    break;
                case TransitionKind.RANDOM:
                    at.a ("smil:type", "random");
                    break;
                case TransitionKind.VORTEX:
                case TransitionKind.RIPPLE:
                case TransitionKind.GLITTER:
                case TransitionKind.HONEYCOMB:
                    string misc = t.kind == TransitionKind.VORTEX ? "vortex" : (t.kind == TransitionKind.RIPPLE ? "ripple" : (t.kind == TransitionKind.GLITTER ? "glitter" : "honeycomb"));
                    at.a ("smil:type", "miscShapeWipe").a ("smil:subtype", misc);
                    break;
                case TransitionKind.CUBE:
                case TransitionKind.BOX:
                    at.a ("smil:type", "miscShapeWipe").a ("smil:subtype", "cornersIn");
                    break;
                case TransitionKind.FLIP:
                case TransitionKind.ROTATE:
                case TransitionKind.ORBIT:
                case TransitionKind.GALLERY:
                case TransitionKind.SWITCH:
                    at.a ("smil:type", "miscShapeWipe").a ("smil:subtype", "vertical");
                    break;
                case TransitionKind.NONE:
                case TransitionKind.CUT:
                    break;
                default:
                    at.a ("smil:type", "fade").a ("smil:subtype", "crossfade");
                    break;
            }
            if (t.kind != TransitionKind.NONE) {
                at.a ("presentation:transition-speed", t.duration < 0.6 ? "fast" : (t.duration < 1.1 ? "medium" : "slow"));
                at.a ("smil:dur", Odf.fixed (t.duration, 3) + "s");
            }
            return at.str ();
        }

        private void write_behaviours (XmlOut x, Animation a, string target) {
            string dur = Odf.fixed (double.max (a.duration, 0.001), 3) + "s";
            bool exit = a.anim_class == AnimClass.EXIT;
            if (a.anim_class == AnimClass.PATH) {
                var sb = new StringBuilder ();
                foreach (var c in a.path) {
                    if (c.op == 'Z') {
                        sb.append ("z ");
                        continue;
                    }
                    sb.append_c (c.op == 'Q' ? 'Q' : c.op);
                    foreach (double v in c.pts) sb.append (" " + Odf.fixed (v, 5));
                    sb.append (" ");
                }
                x.start ("anim:animateMotion").a ("smil:dur", dur).a ("smil:fill", "hold").a ("smil:targetElement", target).a ("svg:path", sb.str.strip ()).a ("presentation:additive", "sum").end ();
                return;
            }
            if (a.anim_class == AnimClass.MEDIA) {
                string cmd = a.effect == AnimEffect.MEDIA_PAUSE ? "toggle-pause" : (a.effect == AnimEffect.MEDIA_STOP ? "stop" : "play");
                x.start ("anim:command").a ("anim:command", cmd).a ("smil:targetElement", target).end ();
                return;
            }
            if (a.anim_class == AnimClass.EMPHASIS) {
                switch (a.effect) {
                    case AnimEffect.FILL_COLOR:
                    case AnimEffect.OBJECT_COLOR:
                    case AnimEffect.FONT_COLOR:
                    case AnimEffect.LINE_COLOR:
                    case AnimEffect.COLOR_PULSE:
                        string attr = a.effect == AnimEffect.FONT_COLOR ? "color" : (a.effect == AnimEffect.LINE_COLOR ? "stroke-color" : "fill-color");
                        string hex = a.color.has_prefix ("#") ? a.color : "#c0504d";
                        x.start ("anim:animateColor").a ("smil:dur", a.effect == AnimEffect.COLOR_PULSE ? Odf.fixed (a.duration / 2, 3) + "s" : dur).a ("smil:fill", "hold").a ("smil:targetElement", target).a ("smil:attributeName", attr).a ("smil:to", hex);
                        if (a.effect == AnimEffect.COLOR_PULSE) x.a ("smil:autoReverse", "true");
                        x.end ();
                        break;
                    case AnimEffect.TRANSPARENCY:
                        x.start ("anim:set").a ("smil:dur", dur).a ("smil:fill", "hold").a ("smil:targetElement", target).a ("smil:attributeName", "opacity").a ("smil:to", Odf.fixed (1 - a.amount, 3)).end ();
                        break;
                    case AnimEffect.TEETER:
                        x.start ("anim:animateTransform").a ("smil:dur", Odf.fixed (a.duration / 4, 3) + "s").a ("smil:fill", "hold").a ("smil:targetElement", target).a ("smil:attributeName", "transform").a ("smil:by", "5").a ("smil:autoReverse", "true").a ("smil:repeatCount", "2").a ("svg:type", "rotate").end ();
                        break;
                    case AnimEffect.SPIN:
                        x.start ("anim:animateTransform").a ("smil:dur", dur).a ("smil:fill", "hold").a ("smil:targetElement", target).a ("smil:attributeName", "transform").a ("smil:by", Odf.fixed (a.amount != 0 ? a.amount : 360, 1)).a ("svg:type", "rotate").end ();
                        break;
                    case AnimEffect.GROW:
                        x.start ("anim:animateTransform").a ("smil:dur", dur).a ("smil:fill", "hold").a ("smil:targetElement", target).a ("smil:attributeName", "transform").a ("smil:to", "1.5,1.5").a ("svg:type", "scale").end ();
                        break;
                    default:
                        x.start ("anim:animateTransform").a ("smil:dur", Odf.fixed (a.duration / 2, 3) + "s").a ("smil:fill", "hold").a ("smil:targetElement", target).a ("smil:attributeName", "transform").a ("smil:to", "1.1,1.1").a ("smil:autoReverse", "true").a ("svg:type", "scale").end ();
                        break;
                }
                return;
            }
            if (!exit) x.start ("anim:set").a ("smil:begin", "0s").a ("smil:dur", "0.001s").a ("smil:fill", "hold").a ("smil:targetElement", target).a ("smil:attributeName", "visibility").a ("smil:to", "visible").end ();
            string mode = exit ? "out" : "in";
            switch (a.effect) {
                case AnimEffect.FADE:
                    x.start ("anim:transitionFilter").a ("smil:dur", dur).a ("smil:targetElement", target).a ("smil:type", "fade").a ("smil:subtype", "crossfade").a ("smil:mode", mode).end ();
                    break;
                case AnimEffect.FLY:
                case AnimEffect.FLOAT:
                    string attr = a.direction == Direction.FROM_LEFT || a.direction == Direction.FROM_RIGHT ? "x" : "y";
                    string off;
                    if (a.effect == AnimEffect.FLY) {
                        switch (a.direction) {
                            case Direction.FROM_LEFT: off = "0-width/2"; break;
                            case Direction.FROM_RIGHT: off = "1+width/2"; break;
                            case Direction.FROM_TOP: off = "0-height/2"; break;
                            default: off = "1+height/2"; break;
                        }
                    } else {
                        switch (a.direction) {
                            case Direction.FROM_LEFT: off = "x-.1"; break;
                            case Direction.FROM_RIGHT: off = "x+.1"; break;
                            case Direction.FROM_TOP: off = "y-.1"; break;
                            default: off = "y+.1"; break;
                        }
                    }
                    string values = exit ? "%s;%s".printf (attr, off) : "%s;%s".printf (off, attr);
                    x.start ("anim:animate").a ("smil:dur", dur).a ("smil:fill", "hold").a ("smil:targetElement", target).a ("smil:attributeName", attr).a ("smil:values", values).a ("smil:keyTimes", "0;1").a ("presentation:additive", "base").end ();
                    if (a.effect == AnimEffect.FLOAT) x.start ("anim:transitionFilter").a ("smil:dur", dur).a ("smil:targetElement", target).a ("smil:type", "fade").a ("smil:subtype", "crossfade").a ("smil:mode", mode).end ();
                    break;
                case AnimEffect.ZOOM:
                    string w = exit ? "width;0" : "0;width";
                    string h = exit ? "height;0" : "0;height";
                    x.start ("anim:animate").a ("smil:dur", dur).a ("smil:fill", "hold").a ("smil:targetElement", target).a ("smil:attributeName", "width").a ("smil:values", w).a ("smil:keyTimes", "0;1").end ();
                    x.start ("anim:animate").a ("smil:dur", dur).a ("smil:fill", "hold").a ("smil:targetElement", target).a ("smil:attributeName", "height").a ("smil:values", h).a ("smil:keyTimes", "0;1").end ();
                    x.start ("anim:transitionFilter").a ("smil:dur", dur).a ("smil:targetElement", target).a ("smil:type", "fade").a ("smil:subtype", "crossfade").a ("smil:mode", mode).end ();
                    break;
                case AnimEffect.WIPE:
                    bool horizontal = a.direction == Direction.FROM_LEFT || a.direction == Direction.FROM_RIGHT;
                    x.start ("anim:transitionFilter").a ("smil:dur", dur).a ("smil:targetElement", target).a ("smil:type", "barWipe").a ("smil:subtype", horizontal ? "leftToRight" : "topToBottom");
                    if (a.direction == Direction.FROM_RIGHT || a.direction == Direction.FROM_BOTTOM) x.a ("smil:direction", "reverse");
                    x.a ("smil:mode", mode).end ();
                    break;
                case AnimEffect.APPEAR:
                    break;
                default:
                    string ftype = "fade", fsub = "crossfade";
                    switch (a.effect) {
                        case AnimEffect.SPLIT: ftype = "barnDoorWipe"; fsub = a.subtype == 26 || a.subtype == 42 ? "horizontal" : "vertical"; break;
                        case AnimEffect.BLINDS: ftype = "blindsWipe"; fsub = a.subtype == 5 ? "vertical" : "horizontal"; break;
                        case AnimEffect.CHECKERBOARD: ftype = "checkerBoardWipe"; fsub = a.subtype == 5 ? "down" : "across"; break;
                        case AnimEffect.RANDOM_BARS: ftype = "randomBarWipe"; fsub = a.subtype == 5 ? "vertical" : "horizontal"; break;
                        case AnimEffect.BOX: ftype = "irisWipe"; fsub = "rectangle"; break;
                        case AnimEffect.CIRCLE: ftype = "ellipseWipe"; fsub = "circle"; break;
                        case AnimEffect.DIAMOND: ftype = "irisWipe"; fsub = "diamond"; break;
                        case AnimEffect.PLUS: ftype = "fourBoxWipe"; fsub = "cornersIn"; break;
                        case AnimEffect.WEDGE: ftype = "fanWipe"; fsub = "centerTop"; break;
                        case AnimEffect.WHEEL: ftype = "pinWheelWipe"; fsub = a.subtype >= 8 ? "eightBlade" : (a.subtype >= 4 ? "fourBlade" : (a.subtype >= 3 ? "threeBlade" : (a.subtype >= 2 ? "twoBladeVertical" : "oneBlade"))); break;
                        case AnimEffect.DISSOLVE: ftype = "dissolve"; fsub = "dissolve"; break;
                        case AnimEffect.STRIPS: ftype = "waterfallWipe"; fsub = "horizontalLeft"; break;
                        default: break;
                    }
                    x.start ("anim:transitionFilter").a ("smil:dur", dur).a ("smil:targetElement", target).a ("smil:type", ftype).a ("smil:subtype", fsub);
                    if ((a.subtype == 32 || a.subtype == 37 || a.subtype == 42) && ftype != "fade") x.a ("smil:direction", "reverse");
                    x.a ("smil:mode", mode).end ();
                    break;
            }
            if (exit) x.start ("anim:set").a ("smil:begin", dur).a ("smil:dur", "0.001s").a ("smil:fill", "hold").a ("smil:targetElement", target).a ("smil:attributeName", "visibility").a ("smil:to", "hidden").end ();
        }

        private void write_timing (XmlOut x, Slide s) {
            var anims = new Gee.ArrayList<Animation> ();
            foreach (var a in s.animations) if (s.find (a.target) != null) anims.add (a);
            if (anims.size == 0) return;
            x.start ("anim:par").a ("presentation:node-type", "timing-root");
            x.start ("anim:seq").a ("presentation:node-type", "main-sequence");
            int i = 0;
            int group = 0;
            while (i < anims.size) {
                x.start ("anim:par").a ("smil:begin", i == 0 && anims[0].trigger != AnimTrigger.ON_CLICK ? "next" : "indefinite");
                double prev_start = 0, prev_end = 0;
                bool first_in_click = true;
                bool time_open = false;
                double time_begin = 0;
                while (i < anims.size && (first_in_click || anims[i].trigger != AnimTrigger.ON_CLICK)) {
                    var a = anims[i];
                    double start;
                    if (first_in_click) start = a.delay;
                    else if (a.trigger == AnimTrigger.WITH_PREVIOUS) start = prev_start + a.delay;
                    else start = prev_end + a.delay;
                    double dur = a.effect == AnimEffect.APPEAR ? 0.01 : double.max (a.duration, 0.01);
                    bool new_time = first_in_click || a.trigger == AnimTrigger.AFTER_PREVIOUS;
                    if (new_time) {
                        if (time_open) x.end ();
                        time_begin = first_in_click ? 0 : prev_end;
                        x.start ("anim:par").a ("smil:begin", Odf.fixed (time_begin, 3) + "s");
                        time_open = true;
                    }
                    x.start ("anim:par").a ("smil:begin", Odf.fixed (start - time_begin, 3) + "s").a ("smil:fill", "hold");
                    string node_trigger = first_in_click && a.trigger == AnimTrigger.ON_CLICK ? "on-click" : Odf.node_type (a.trigger);
                    x.a ("presentation:node-type", node_trigger);
                    string pclass;
                    switch (a.anim_class) {
                        case AnimClass.EXIT: pclass = "exit"; break;
                        case AnimClass.EMPHASIS: pclass = "emphasis"; break;
                        case AnimClass.PATH: pclass = "motion-path"; break;
                        case AnimClass.MEDIA: pclass = "media-call"; break;
                        default: pclass = "entrance"; break;
                    }
                    x.a ("presentation:preset-class", pclass);
                    x.a ("presentation:preset-id", Odf.preset_id (a.anim_class, a.effect));
                    if (a.effect.has_direction ()) x.a ("presentation:preset-sub-type", Odf.anim_subtype (a.direction));
                    x.a ("presentation:group-id", group.to_string ());
                    if (include_private) x.a ("sgs:anim", Odf.anim_code (a));
                    write_behaviours (x, a, "id%d".printf (a.target));
                    x.end ();
                    prev_start = start;
                    prev_end = start + dur;
                    first_in_click = false;
                    group++;
                    i++;
                }
                if (time_open) x.end ();
                x.end ();
            }
            x.end ();
            x.end ();
        }

        private string content_xml () {
            var body = new XmlOut (false);
            body.start ("office:body").start ("office:presentation");
            if (include_private) {
                body.a ("sgs:pres", "%s|%s|%s|%s|%s|%s".printf (Odf.dbl (pres.width), Odf.dbl (pres.height), pres.loop ? "1" : "0", pres.use_timings ? "1" : "0", Odf.enc (pres.footer_text), Odf.enc (pres.date_text)));
            }
            if (pres.footer_text != "") body.start ("presentation:footer-decl").a ("presentation:name", "ftr1").text (pres.footer_text).end ();
            if (pres.date_text != "") body.start ("presentation:date-time-decl").a ("presentation:name", "dtd1").a ("presentation:source", "fixed").text (pres.date_text).end ();
            for (int k = 0; k < pres.slides.size; k++) page_names[pres.slides[k].uid] = pres.slides[k].name != "" ? pres.slides[k].name : "page%d".printf (k + 1);
            int n = 0;
            foreach (var s in pres.slides) {
                n++;
                var m = pres.master_for (s);
                var l = pres.layout_for (s);
                string mp = page_name (s);
                var dpa = new OdpAttrs ();
                dpa.a ("presentation:background-visible", "true");
                dpa.a ("presentation:background-objects-visible", s.show_master_shapes ? "true" : "false");
                dpa.a ("presentation:display-footer", "true").a ("presentation:display-page-number", "true").a ("presentation:display-date-time", "true");
                if (s.hidden) dpa.a ("presentation:visibility", "hidden");
                string dp = content_styles.add ("drawing-page", "dp", "<style:drawing-page-properties%s%s%s/>".printf (dpa.str (), page_fill_props (s.background, m.theme), transition_props (s)));
                body.start ("draw:page").a ("draw:name", s.name != "" ? s.name : "page%d".printf (n)).a ("draw:style-name", dp).a ("draw:master-page-name", mp);
                if (page_layout_names.has_key (mp)) body.a ("presentation:presentation-page-layout-name", page_layout_names[mp]);
                if (pres.footer_text != "") body.a ("presentation:use-footer-name", "ftr1");
                if (pres.date_text != "") body.a ("presentation:use-date-time-name", "dtd1");
                if (include_private) {
                    body.a ("sgs:slide", "%s|%s|%s|%s".printf (Odf.enc (s.layout_id), s.hidden ? "1" : "0", s.show_master_shapes ? "1" : "0", Odf.enc (s.name)));
                    body.a ("sgs:bg", s.background != null ? Odf.fill_code (s.background) : "inherit");
                    body.a ("sgs:transition", Odf.transition_code (s.transition));
                    if (s.section != null) body.a ("sgs:section", "%s|%s|%s".printf (Odf.enc (s.section.name), Odf.enc (s.section.id), s.section.collapsed ? "1" : "0"));
                    body.a ("sgs:uid", s.uid.to_string ());
                }
                var c = make_ctx (s, l, m, false, mp);
                foreach (var e in s.elements) write_element (body, e, c);
                foreach (var cm in s.comments) {
                    write_annotation (body, cm, "");
                    foreach (var r in cm.replies) write_annotation (body, r, cm.id);
                }
                write_timing (body, s);
                body.start ("presentation:notes").a ("draw:style-name", dp);
                body.start ("draw:page-thumbnail").a ("draw:layer", "layout").a ("svg:width", "14.848cm").a ("svg:height", "8.35cm").a ("svg:x", "3.075cm").a ("svg:y", "2.257cm").a ("draw:page-number", n.to_string ()).a ("presentation:class", "page").end ();
                body.start ("draw:frame").a ("presentation:style-name", mp + "-notes").a ("draw:layer", "layout").a ("svg:width", "16.799cm").a ("svg:height", "13.365cm").a ("svg:x", "2.1cm").a ("svg:y", "11.576cm").a ("presentation:class", "notes");
                if (s.notes == "") body.a ("presentation:placeholder", "true");
                body.start ("draw:text-box");
                if (s.notes != "") {
                    foreach (string line in s.notes.split ("\n")) {
                        body.start ("text:p");
                        write_run_text (body, line);
                        body.end ();
                    }
                }
                body.end ().end ().end ();
                body.end ();
            }
            body.start ("presentation:settings");
            if (pres.loop) body.a ("presentation:endless", "true");
            if (!pres.use_timings) body.a ("presentation:force-manual", "true");
            if (pres.show_custom != "") body.a ("presentation:show", pres.show_custom);
            else if (pres.show_from > 1 && pres.slides.size > 0) body.a ("presentation:start-page", page_names[pres.slides[(pres.show_from - 1).clamp (0, pres.slides.size - 1)].uid] ?? "");
            if (pres.show_kind == 1) body.a ("presentation:full-screen", "false");
            if (!pres.show_animation) body.a ("presentation:animations", "disabled");
            foreach (var cs in pres.custom_shows) {
                var names = new Gee.ArrayList<string> ();
                foreach (int uid in cs.slides) if (page_names.has_key (uid)) names.add (page_names[uid]);
                body.start ("presentation:show").a ("presentation:name", cs.name).a ("presentation:pages", string.joinv (",", names.to_array ())).end ();
            }
            body.end ();
            body.end ().end ();
            string body_xml = body.finish ();
            var sb = new StringBuilder ("<?xml version=\"1.0\" encoding=\"UTF-8\"?>\n");
            sb.append ("<office:document-content" + Odf.ns_decls () + ">");
            sb.append (font_decls ());
            sb.append ("<office:automatic-styles>");
            sb.append (content_styles.output.str);
            sb.append ("</office:automatic-styles>");
            sb.append (body_xml);
            sb.append ("</office:document-content>");
            return sb.str;
        }

        private Gee.TreeSet<string> fonts = new Gee.TreeSet<string> ();

        private string font_decls () {
            if (fonts.size == 0) {
                foreach (var m in pres.masters) {
                    fonts.add (m.theme.major_font);
                    fonts.add (m.theme.minor_font);
                }
                fonts.add ("Inter");
            }
            var sb = new StringBuilder ("<office:font-face-decls>");
            foreach (string f in fonts) sb.append ("<style:font-face style:name=\"%s\" svg:font-family=\"%s\"/>".printf (XmlOut.esc (f), XmlOut.esc (f)));
            sb.append ("</office:font-face-decls>");
            return sb.str;
        }

        private string styles_xml (string master_xml, string presentation_styles_xml, string layouts_xml) {
            var sb = new StringBuilder ("<?xml version=\"1.0\" encoding=\"UTF-8\"?>\n");
            sb.append ("<office:document-styles" + Odf.ns_decls () + ">");
            sb.append (font_decls ());
            sb.append ("<office:styles>");
            sb.append (common.str);
            sb.append ("<style:default-style style:family=\"graphic\"><style:graphic-properties draw:fill=\"none\" draw:stroke=\"none\" draw:shadow=\"hidden\"/><style:paragraph-properties fo:text-align=\"start\"/><style:text-properties fo:font-size=\"18pt\" style:font-name=\"Inter\" fo:font-family=\"Inter\"/></style:default-style>");
            sb.append ("<style:style style:name=\"standard\" style:family=\"graphic\"><style:graphic-properties draw:stroke=\"none\" draw:fill=\"none\" fo:padding-left=\"0.25cm\" fo:padding-right=\"0.25cm\" fo:padding-top=\"0.125cm\" fo:padding-bottom=\"0.125cm\"/></style:style>");
            sb.append (presentation_styles_xml);
            sb.append (layouts_xml);
            sb.append ("</office:styles>");
            sb.append ("<office:automatic-styles>");
            sb.append ("<style:page-layout style:name=\"PM1\"><style:page-layout-properties fo:margin-top=\"0cm\" fo:margin-bottom=\"0cm\" fo:margin-left=\"0cm\" fo:margin-right=\"0cm\" fo:page-width=\"%s\" fo:page-height=\"%s\" style:print-orientation=\"%s\"/></style:page-layout>".printf (
                Odf.cm (pres.width), Odf.cm (pres.height), pres.width >= pres.height ? "landscape" : "portrait"));
            sb.append (master_styles.output.str);
            sb.append ("</office:automatic-styles>");
            sb.append ("<office:master-styles>");
            sb.append (master_xml);
            sb.append ("</office:master-styles>");
            sb.append ("</office:document-styles>");
            return sb.str;
        }

        private string meta_xml () {
            var p = pres.properties;
            var x = new XmlOut ();
            x.raw ("<office:document-meta" + Odf.ns_decls () + ">");
            x.start ("office:meta");
            x.element ("meta:generator", "Singularity Slides");
            if (p.title != "") x.element ("dc:title", p.title);
            if (p.subject != "") x.element ("dc:subject", p.subject);
            if (p.keywords != "") foreach (string k in p.keywords.split (",")) if (k.strip () != "") x.element ("meta:keyword", k.strip ());
            if (p.author != "") {
                x.element ("meta:initial-creator", p.author);
                x.element ("dc:creator", p.author);
            }
            if (p.created != "") x.element ("meta:creation-date", p.created);
            if (p.modified != "") x.element ("dc:date", p.modified);
            x.start ("meta:document-statistic").a ("meta:object-count", pres.slides.size.to_string ()).end ();
            x.end ();
            x.raw ("</office:document-meta>");
            return x.finish ();
        }

        private string settings_xml () {
            return "<?xml version=\"1.0\" encoding=\"UTF-8\"?>\n<office:document-settings xmlns:office=\"%s\" xmlns:config=\"urn:oasis:names:tc:opendocument:xmlns:config:1.0\" office:version=\"1.3\"><office:settings><config:config-item-set config:name=\"ooo:configuration-settings\"><config:config-item config:name=\"IsPrintDrawing\" config:type=\"boolean\">true</config:config-item></config:config-item-set></office:settings></office:document-settings>".printf (Odf.NS_OFFICE);
        }

        private string chart_styles_xml () {
            return "<?xml version=\"1.0\" encoding=\"UTF-8\"?>\n<office:document-styles" + Odf.ns_decls () + "><office:styles/></office:document-styles>";
        }

        private string chart_meta_xml () {
            return "<?xml version=\"1.0\" encoding=\"UTF-8\"?>\n<office:document-meta" + Odf.ns_decls () + "><office:meta><meta:generator>Singularity Slides</meta:generator></office:meta></office:document-meta>";
        }

        private string manifest_xml (Gee.List<string> parts, Gee.List<string> types) {
            var x = new XmlOut ();
            x.raw ("<manifest:manifest xmlns:manifest=\"%s\" manifest:version=\"1.3\">".printf (Odf.NS_MANIFEST));
            x.start ("manifest:file-entry").a ("manifest:full-path", "/").a ("manifest:version", "1.3").a ("manifest:media-type", Odf.MIME).end ();
            for (int i = 0; i < parts.size; i++) x.start ("manifest:file-entry").a ("manifest:full-path", parts[i]).a ("manifest:media-type", types[i]).end ();
            x.raw ("</manifest:manifest>");
            return x.finish ();
        }

        public uint8[] write () throws Error {
            var presentation_sb = new StringBuilder ();
            var layouts_sb = new StringBuilder ();
            string master_xml = master_pages_xml (presentation_sb, layouts_sb);
            string content = content_xml ();
            string styles = styles_xml (master_xml, presentation_sb.str, layouts_sb.str);
            var parts = new Gee.ArrayList<string> ();
            var types = new Gee.ArrayList<string> ();
            var zip = new ZipWriter ();
            zip.add ("mimetype", Odf.MIME.data, false);
            zip.add_text ("content.xml", content);
            parts.add ("content.xml");
            types.add ("text/xml");
            zip.add_text ("styles.xml", styles);
            parts.add ("styles.xml");
            types.add ("text/xml");
            zip.add_text ("meta.xml", meta_xml ());
            parts.add ("meta.xml");
            types.add ("text/xml");
            zip.add_text ("settings.xml", settings_xml ());
            parts.add ("settings.xml");
            types.add ("text/xml");
            for (int i = 0; i < image_paths.size; i++) {
                zip.add (image_paths[i], image_data[i].get_data (), false);
                parts.add (image_paths[i]);
                types.add (image_mimes[i]);
            }
            for (int i = 0; i < extra_paths.size; i++) {
                zip.add (extra_paths[i], extra_data[i].get_data (), false);
                parts.add (extra_paths[i]);
                types.add (extra_mimes[i]);
            }
            for (int i = 0; i < formula_names.size; i++) {
                string dir = formula_names[i];
                zip.add_text (dir + "/content.xml", formula_docs[i]);
                parts.add (dir + "/");
                types.add ("application/vnd.oasis.opendocument.formula");
                parts.add (dir + "/content.xml");
                types.add ("text/xml");
            }
            for (int i = 0; i < chart_names.size; i++) {
                string dir = chart_names[i];
                zip.add_text (dir + "/content.xml", chart_docs[i]);
                zip.add_text (dir + "/styles.xml", chart_styles_xml ());
                zip.add_text (dir + "/meta.xml", chart_meta_xml ());
                parts.add (dir + "/");
                types.add (Odf.CHART_MIME);
                parts.add (dir + "/content.xml");
                types.add ("text/xml");
                parts.add (dir + "/styles.xml");
                types.add ("text/xml");
                parts.add (dir + "/meta.xml");
                types.add ("text/xml");
            }
            zip.add_text ("META-INF/manifest.xml", manifest_xml (parts, types));
            return zip.finish ();
        }
    }
}
