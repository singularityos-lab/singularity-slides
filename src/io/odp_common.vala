namespace Singularity.Apps.Slides {

    public class Odf {
        public const string MIME = "application/vnd.oasis.opendocument.presentation";
        public const string CHART_MIME = "application/vnd.oasis.opendocument.chart";
        public const string NS_OFFICE = "urn:oasis:names:tc:opendocument:xmlns:office:1.0";
        public const string NS_STYLE = "urn:oasis:names:tc:opendocument:xmlns:style:1.0";
        public const string NS_TEXT = "urn:oasis:names:tc:opendocument:xmlns:text:1.0";
        public const string NS_TABLE = "urn:oasis:names:tc:opendocument:xmlns:table:1.0";
        public const string NS_DRAW = "urn:oasis:names:tc:opendocument:xmlns:drawing:1.0";
        public const string NS_FO = "urn:oasis:names:tc:opendocument:xmlns:xsl-fo-compatible:1.0";
        public const string NS_XLINK = "http://www.w3.org/1999/xlink";
        public const string NS_DC = "http://purl.org/dc/elements/1.1/";
        public const string NS_META = "urn:oasis:names:tc:opendocument:xmlns:meta:1.0";
        public const string NS_NUMBER = "urn:oasis:names:tc:opendocument:xmlns:datastyle:1.0";
        public const string NS_PRESENTATION = "urn:oasis:names:tc:opendocument:xmlns:presentation:1.0";
        public const string NS_SVG = "urn:oasis:names:tc:opendocument:xmlns:svg-compatible:1.0";
        public const string NS_CHART = "urn:oasis:names:tc:opendocument:xmlns:chart:1.0";
        public const string NS_SMIL = "urn:oasis:names:tc:opendocument:xmlns:smil-compatible:1.0";
        public const string NS_ANIM = "urn:oasis:names:tc:opendocument:xmlns:animation:1.0";
        public const string NS_XML = "http://www.w3.org/XML/1998/namespace";
        public const string NS_MANIFEST = "urn:oasis:names:tc:opendocument:xmlns:manifest:1.0";
        public const string NS_LOEXT = "urn:org:documentfoundation:names:experimental:office:xmlns:loext:1.0";
        public const string NS_SGS = "urn:singularity:slides:1.0";

        public const double PT_PER_CM = 72.0 / 2.54;

        public static string ns_decls () {
            return " xmlns:script=\"urn:oasis:names:tc:opendocument:xmlns:script:1.0\" xmlns:officeooo=\"http://openoffice.org/2009/office\" xmlns:office=\"%s\" xmlns:style=\"%s\" xmlns:text=\"%s\" xmlns:table=\"%s\" xmlns:draw=\"%s\" xmlns:fo=\"%s\" xmlns:xlink=\"%s\" xmlns:dc=\"%s\" xmlns:meta=\"%s\" xmlns:number=\"%s\" xmlns:presentation=\"%s\" xmlns:svg=\"%s\" xmlns:chart=\"%s\" xmlns:smil=\"%s\" xmlns:anim=\"%s\" xmlns:loext=\"%s\" xmlns:sgs=\"%s\" office:version=\"1.3\"".printf (
                NS_OFFICE, NS_STYLE, NS_TEXT, NS_TABLE, NS_DRAW, NS_FO, NS_XLINK, NS_DC, NS_META, NS_NUMBER, NS_PRESENTATION, NS_SVG, NS_CHART, NS_SMIL, NS_ANIM, NS_LOEXT, NS_SGS);
        }

        public static string fixed (double v, int decimals) {
            string s = ("%." + decimals.to_string () + "f").printf (v).replace (",", ".");
            if (s.contains (".")) {
                while (s.has_suffix ("0")) s = s.substring (0, s.length - 1);
                if (s.has_suffix (".")) s = s.substring (0, s.length - 1);
            }
            if (s == "-0") s = "0";
            return s;
        }

        public static string cm (double pt) {
            return fixed (pt / PT_PER_CM, 4) + "cm";
        }

        public static string pt (double v) {
            return fixed (v, 3) + "pt";
        }

        public static string pct (double v) {
            return fixed (v * 100, 2) + "%";
        }

        public static string dbl (double v) {
            return v.to_string ();
        }

        public static double length (string? s, double fallback = 0) {
            if (s == null) return fallback;
            string t = s.strip ();
            int i = 0;
            while (i < t.length && (t[i].isdigit () || t[i] == '.' || t[i] == '-' || t[i] == '+' || t[i] == 'e' || t[i] == 'E')) {
                if ((t[i] == 'e' || t[i] == 'E') && (i + 1 >= t.length || !(t[i + 1].isdigit () || t[i + 1] == '-' || t[i + 1] == '+'))) break;
                i++;
            }
            double v;
            if (!double.try_parse (t.substring (0, i), out v)) return fallback;
            string unit = t.substring (i).strip ().down ();
            switch (unit) {
                case "cm": return v * PT_PER_CM;
                case "mm": return v * PT_PER_CM / 10;
                case "in": case "inch": return v * 72;
                case "pt": case "": return v;
                case "pc": return v * 12;
                case "px": return v * 0.75;
                default: return fallback;
            }
        }

        public static double percent (string? s, double fallback) {
            if (s == null) return fallback;
            string t = s.strip ().replace ("%", "");
            double v;
            if (!double.try_parse (t, out v)) return fallback;
            return v / 100;
        }

        public static double seconds (string? s, double fallback) {
            if (s == null) return fallback;
            string t = s.strip ();
            double v = 0;
            if (t.has_prefix ("PT") || t.has_prefix ("pt")) {
                string body = t.substring (2).up ();
                double total = 0;
                var num = new StringBuilder ();
                for (int i = 0; i < body.length; i++) {
                    char c = body[i];
                    if (c.isdigit () || c == '.') {
                        num.append_c (c);
                        continue;
                    }
                    double n = double.parse (num.str);
                    num.truncate ();
                    if (c == 'H') total += n * 3600;
                    else if (c == 'M') total += n * 60;
                    else if (c == 'S') total += n;
                }
                return total;
            }
            if (t.has_suffix ("ms") && double.try_parse (t.substring (0, t.length - 2), out v)) return v / 1000;
            if (t.has_suffix ("s") && double.try_parse (t.substring (0, t.length - 1), out v)) return v;
            if (t.has_suffix ("min") && double.try_parse (t.substring (0, t.length - 3), out v)) return v * 60;
            if (t.has_suffix ("h") && double.try_parse (t.substring (0, t.length - 1), out v)) return v * 3600;
            if (t.contains (":")) {
                string[] parts = t.split (":");
                double total = 0;
                foreach (string part in parts) total = total * 60 + double.parse (part);
                return total;
            }
            if (double.try_parse (t, out v)) return v;
            return fallback;
        }

        public static string duration (double secs) {
            int h = (int) (secs / 3600);
            int m = (int) ((secs - h * 3600) / 60);
            double s = secs - h * 3600 - m * 60;
            return "PT%02dH%02dM%sS".printf (h, m, fixed (s, 3));
        }

        public static string hex (Rgba c) {
            return c.to_hex ();
        }

        public static string enc (string s) {
            return Uri.escape_string (s, "", true);
        }

        public static string dec (string s) {
            return Uri.unescape_string (s) ?? s;
        }

        public static int to_int (string s, int fallback = 0) {
            int64 v;
            if (int64.try_parse (s.strip (), out v)) return (int) v;
            return fallback;
        }

        public static double to_double (string s, double fallback = 0) {
            double v;
            if (double.try_parse (s.strip (), out v)) return v;
            return fallback;
        }

        public static string[] fields (string s, int count) {
            string[] parts = s.split ("|");
            string[] result = new string[count];
            for (int i = 0; i < count; i++) result[i] = i < parts.length ? parts[i] : "";
            return result;
        }

        private static string axis_code (ChartAxis a) {
            return "%s,%s,%s,%s,%s,%s,%s,%s".printf (enc (a.title), a.min.is_nan () ? "" : dbl (a.min), a.max.is_nan () ? "" : dbl (a.max), dbl (a.major), enc (a.format), dbl (a.log_base), a.reverse ? "1" : "0", a.visible ? "1" : "0");
        }

        private static void axis_decode (string code, ChartAxis a) {
            string[] p = code.split (",");
            if (p.length < 8) return;
            a.title = dec (p[0]);
            a.min = p[1] == "" ? double.NAN : to_double (p[1]);
            a.max = p[2] == "" ? double.NAN : to_double (p[2]);
            a.major = to_double (p[3]);
            a.format = dec (p[4]);
            a.log_base = to_double (p[5]);
            a.reverse = p[6] == "1";
            a.visible = p[7] == "1";
        }

        public static string chart_extra (ChartElement ch) {
            var sb = new StringBuilder ();
            sb.append ("%s~%s~%s|".printf (axis_code (ch.cat_axis), axis_code (ch.val_axis), axis_code (ch.sec_axis)));
            for (int i = 0; i < ch.series.size; i++) {
                var s = ch.series[i];
                if (i > 0) sb.append (";");
                var sizes = new StringBuilder ();
                foreach (var z in s.sizes) {
                    if (sizes.len > 0) sizes.append (" ");
                    sizes.append (z == null ? "n" : dbl (z));
                }
                sb.append ("%d,%s,%d,%d,%d,%s,%s,%s".printf ((int) s.kind, s.secondary ? "1" : "0", (int) s.trend, s.trend_order, s.trend_period, s.trend_equation ? "1" : "0", s.trend_r2 ? "1" : "0", enc (sizes.str)));
            }
            return sb.str;
        }

        public static void apply_chart_extra (ChartElement ch, string code) {
            string[] top = fields (code, 2);
            string[] axes = top[0].split ("~");
            if (axes.length == 3) {
                axis_decode (axes[0], ch.cat_axis);
                axis_decode (axes[1], ch.val_axis);
                axis_decode (axes[2], ch.sec_axis);
            }
            string[] ser = top[1].split (";");
            for (int i = 0; i < ch.series.size && i < ser.length; i++) {
                string[] p = ser[i].split (",");
                if (p.length < 8) continue;
                var s = ch.series[i];
                s.kind = (SeriesKind) to_int (p[0]).clamp (0, 3);
                s.secondary = p[1] == "1";
                s.trend = (TrendKind) to_int (p[2]).clamp (0, 6);
                s.trend_order = to_int (p[3], 2);
                s.trend_period = to_int (p[4], 2);
                s.trend_equation = p[5] == "1";
                s.trend_r2 = p[6] == "1";
                s.sizes.clear ();
                string sz = dec (p[7]);
                if (sz != "") foreach (string v in sz.split (" ")) s.sizes.add (v == "n" ? null : (double?) to_double (v));
            }
        }

        public static string fill_code (Fill f) {
            switch (f.kind) {
                case FillKind.SOLID:
                    return "solid|" + enc (f.color);
                case FillKind.GRADIENT:
                    var sb = new StringBuilder ();
                    foreach (var st in f.stops) {
                        if (sb.len > 0) sb.append (",");
                        sb.append (dbl (st.pos) + ":" + enc (st.color));
                    }
                    return "gradient|%s|%s|%s".printf (dbl (f.angle), f.radial ? "1" : "0", sb.str);
                case FillKind.IMAGE:
                    return "image|%s|%s".printf (f.tile ? "1" : "0", enc (f.image_mime));
                default:
                    return "none";
            }
        }

        public static Fill parse_fill (string code, Bytes? image, string mime) {
            string[] p = code.split ("|");
            var f = new Fill ();
            switch (p[0]) {
                case "solid":
                    f.kind = FillKind.SOLID;
                    f.color = p.length > 1 ? dec (p[1]) : "";
                    break;
                case "gradient":
                    f.kind = FillKind.GRADIENT;
                    f.angle = p.length > 1 ? to_double (p[1], 90) : 90;
                    f.radial = p.length > 2 && p[2] == "1";
                    if (p.length > 3 && p[3] != "") {
                        foreach (string stop in p[3].split (",")) {
                            int colon = stop.index_of (":");
                            if (colon < 0) continue;
                            f.stops.add (new GradientStop (to_double (stop.substring (0, colon)), dec (stop.substring (colon + 1))));
                        }
                    }
                    if (f.stops.size > 0) f.color = f.stops[0].color;
                    break;
                case "image":
                    f.kind = image != null ? FillKind.IMAGE : FillKind.NONE;
                    f.tile = p.length > 1 && p[1] == "1";
                    f.image = image;
                    f.image_mime = p.length > 2 && dec (p[2]) != "" ? dec (p[2]) : mime;
                    break;
                default:
                    f.kind = FillKind.NONE;
                    break;
            }
            return f;
        }

        public static string line_code (Line l) {
            return "%s|%s|%d|%d|%d".printf (enc (l.color), dbl (l.width), (int) l.dash, (int) l.head, (int) l.tail);
        }

        public static Line parse_line (string code) {
            string[] p = fields (code, 5);
            var l = new Line ();
            l.color = dec (p[0]);
            l.width = to_double (p[1], 1);
            l.dash = (DashKind) to_int (p[2]).clamp (0, 4);
            l.head = (ArrowKind) to_int (p[3]).clamp (0, 4);
            l.tail = (ArrowKind) to_int (p[4]).clamp (0, 4);
            return l;
        }

        public static string shadow_code (Shadow s) {
            return "%s|%s|%s|%s|%s|%s".printf (s.enabled ? "1" : "0", enc (s.color), dbl (s.opacity), dbl (s.blur), dbl (s.distance), dbl (s.angle));
        }

        public static Shadow parse_shadow (string code) {
            string[] p = fields (code, 6);
            var s = new Shadow ();
            s.enabled = p[0] == "1";
            s.color = dec (p[1]);
            s.opacity = to_double (p[2], 0.35);
            s.blur = to_double (p[3], 8);
            s.distance = to_double (p[4], 4);
            s.angle = to_double (p[5], 90);
            return s;
        }

        public static string body_code (TextBody b) {
            return "%s|%s|%s|%s|%d|%s|%s|%d|%s|%s|%d|%s".printf (dbl (b.inset_left), dbl (b.inset_top), dbl (b.inset_right), dbl (b.inset_bottom),
                (int) b.anchor, b.anchor_set ? "1" : "0", b.wrap ? "1" : "0", (int) b.autofit, dbl (b.font_scale), dbl (b.line_reduction), b.columns, b.vertical ? "1" : "0");
        }

        public static void apply_body_code (TextBody b, string code) {
            string[] p = fields (code, 12);
            b.inset_left = to_double (p[0], b.inset_left);
            b.inset_top = to_double (p[1], b.inset_top);
            b.inset_right = to_double (p[2], b.inset_right);
            b.inset_bottom = to_double (p[3], b.inset_bottom);
            b.anchor = (TextAnchor) to_int (p[4]).clamp (0, 2);
            b.anchor_set = p[5] == "1";
            b.wrap = p[6] != "0";
            b.autofit = (AutoFit) to_int (p[7]).clamp (0, 2);
            b.font_scale = to_double (p[8], 1);
            b.line_reduction = to_double (p[9], 0);
            b.columns = int.max (1, to_int (p[10], 1));
            b.vertical = p[11] == "1";
        }

        public static string run_code (TextRun r) {
            return "%d|%d|%d|%d|%s|%s|%s|%s|%d|%s|%s".printf (r.bold, r.italic, r.underline, r.strike, dbl (r.size), enc (r.font), enc (r.color), enc (r.highlight), r.baseline, enc (r.link), enc (r.field));
        }

        public static void apply_run_code (TextRun r, string code) {
            string[] p = fields (code, 11);
            r.bold = to_int (p[0], -1);
            r.italic = to_int (p[1], -1);
            r.underline = to_int (p[2], -1);
            r.strike = to_int (p[3], -1);
            r.size = to_double (p[4], 0);
            r.font = dec (p[5]);
            r.color = dec (p[6]);
            r.highlight = dec (p[7]);
            r.baseline = to_int (p[8], 0);
            r.link = dec (p[9]);
            r.field = dec (p[10]);
        }

        public static string para_code (Paragraph p) {
            return "%d|%d|%d|%s|%s|%d|%d|%s|%s|%s".printf ((int) p.align, p.level, (int) p.bullet, enc (p.bullet_char), enc (p.bullet_color),
                (int) p.number_style, p.number_start, dbl (p.space_before), dbl (p.space_after), dbl (p.line_spacing));
        }

        public static void apply_para_code (Paragraph p, string code) {
            string[] f = fields (code, 10);
            p.align = (TextAlign) to_int (f[0]).clamp (0, 4);
            p.level = to_int (f[1]).clamp (0, 8);
            p.bullet = (BulletKind) to_int (f[2]).clamp (0, 3);
            p.bullet_char = dec (f[3]);
            p.bullet_color = dec (f[4]);
            p.number_style = (NumberStyle) to_int (f[5]).clamp (0, 5);
            p.number_start = to_int (f[6], 1);
            p.space_before = to_double (f[7], -1);
            p.space_after = to_double (f[8], -1);
            p.line_spacing = to_double (f[9], 0);
        }

        public static string level_code (LevelStyle l) {
            return "%s;%s;%s;%d;%d;%d;%d;%s;%s;%s;%s;%s;%s;%s".printf (dbl (l.size), enc (l.font), enc (l.color), l.bold, l.italic, (int) l.align, (int) l.bullet,
                enc (l.bullet_char), dbl (l.margin), dbl (l.indent), dbl (l.space_before), dbl (l.space_after), dbl (l.line_spacing), l.caps ? "1" : "0");
        }

        public static LevelStyle parse_level (string code) {
            string[] p = code.split (";");
            var l = new LevelStyle ();
            if (p.length < 14) return l;
            l.size = to_double (p[0]);
            l.font = dec (p[1]);
            l.color = dec (p[2]);
            l.bold = to_int (p[3], -1);
            l.italic = to_int (p[4], -1);
            l.align = (TextAlign) to_int (p[5]).clamp (0, 4);
            l.bullet = (BulletKind) to_int (p[6]).clamp (0, 3);
            l.bullet_char = dec (p[7]);
            l.margin = to_double (p[8], -1);
            l.indent = to_double (p[9], 0);
            l.space_before = to_double (p[10], -1);
            l.space_after = to_double (p[11], -1);
            l.line_spacing = to_double (p[12], 0);
            l.caps = p[13] == "1";
            return l;
        }

        public static string style_code (TextStyle t) {
            var sb = new StringBuilder ();
            for (int i = 0; i < 9; i++) {
                if (i > 0) sb.append ("/");
                sb.append (level_code (t.levels[i]));
            }
            return sb.str;
        }

        public static TextStyle parse_style (string code) {
            var t = new TextStyle ();
            string[] levels = code.split ("/");
            for (int i = 0; i < 9 && i < levels.length; i++) t.levels[i] = parse_level (levels[i]);
            return t;
        }

        public static string theme_code (Theme t) {
            var sb = new StringBuilder ();
            foreach (string k in Theme.SCHEME_KEYS) {
                if (sb.len > 0) sb.append (",");
                sb.append (k + "=" + enc (t.colors[k] ?? "#000000"));
            }
            return "%s|%s|%s|%s|%s".printf (enc (t.id), enc (t.name), enc (t.major_font), enc (t.minor_font), sb.str);
        }

        public static Theme parse_theme (string code) {
            string[] p = fields (code, 5);
            var t = new Theme ();
            t.id = dec (p[0]);
            t.name = dec (p[1]);
            t.major_font = dec (p[2]);
            t.minor_font = dec (p[3]);
            foreach (string kv in p[4].split (",")) {
                int eq = kv.index_of ("=");
                if (eq > 0) t.colors[kv.substring (0, eq)] = dec (kv.substring (eq + 1));
            }
            return t;
        }

        public static string geom_code (Element e) {
            return "%s|%s|%s|%s|%s|%s|%s".printf (dbl (e.x), dbl (e.y), dbl (e.w), dbl (e.h), dbl (e.rotation), e.flip_h ? "1" : "0", e.flip_v ? "1" : "0");
        }

        public static void apply_geom_code (Element e, string code) {
            string[] p = fields (code, 7);
            e.x = to_double (p[0], e.x);
            e.y = to_double (p[1], e.y);
            e.w = to_double (p[2], e.w);
            e.h = to_double (p[3], e.h);
            e.rotation = to_double (p[4], e.rotation);
            e.flip_h = p[5] == "1";
            e.flip_v = p[6] == "1";
        }

        public static string path_code (Gee.List<PathCommand> path) {
            var sb = new StringBuilder ();
            foreach (var c in path) {
                if (sb.len > 0) sb.append (";");
                sb.append_c (c.op);
                foreach (double v in c.pts) sb.append ("," + dbl (v));
            }
            return sb.str;
        }

        public static void parse_path_code (string code, Gee.List<PathCommand> path) {
            path.clear ();
            if (code == "") return;
            foreach (string cmd in code.split (";")) {
                if (cmd == "") continue;
                string[] parts = cmd.split (",");
                double[] pts = new double[parts.length - 1];
                for (int i = 1; i < parts.length; i++) pts[i - 1] = to_double (parts[i]);
                path.add (new PathCommand (parts[0][0], pts));
            }
        }

        public static string fx_code (ShapeEffects f) {
            return string.joinv ("|", {
                enc (f.glow_color), dbl (f.glow_radius), dbl (f.soft_edge), f.reflection ? "1" : "0", dbl (f.reflection_size), dbl (f.reflection_distance), dbl (f.reflection_alpha),
                enc (f.bevel), dbl (f.bevel_width), dbl (f.bevel_height), dbl (f.rot_x), dbl (f.rot_y), dbl (f.perspective), enc (f.text_outline), dbl (f.text_outline_width),
                enc (f.text_glow), dbl (f.text_glow_radius), f.text_shadow ? "1" : "0", f.text_reflection ? "1" : "0", enc (f.text_warp), enc (f.text_fill)
            });
        }

        public static void apply_fx_code (ShapeEffects f, string code) {
            string[] p = fields (code, 21);
            f.glow_color = dec (p[0]);
            f.glow_radius = to_double (p[1], 0);
            f.soft_edge = to_double (p[2], 0);
            f.reflection = p[3] == "1";
            f.reflection_size = to_double (p[4], 0.5);
            f.reflection_distance = to_double (p[5], 0);
            f.reflection_alpha = to_double (p[6], 0.5);
            f.bevel = dec (p[7]);
            f.bevel_width = to_double (p[8], 6);
            f.bevel_height = to_double (p[9], 6);
            f.rot_x = to_double (p[10], 0);
            f.rot_y = to_double (p[11], 0);
            f.perspective = to_double (p[12], 0);
            f.text_outline = dec (p[13]);
            f.text_outline_width = to_double (p[14], 0.75);
            f.text_glow = dec (p[15]);
            f.text_glow_radius = to_double (p[16], 0);
            f.text_shadow = p[17] == "1";
            f.text_reflection = p[18] == "1";
            f.text_warp = dec (p[19]);
            f.text_fill = dec (p[20]);
        }

        public static string diagram_code (DiagramElement d) {
            var sb = new StringBuilder ();
            sb.append ("%d|%d|%d|".printf ((int) d.layout, (int) d.colors, (int) d.style));
            var parts = new Gee.ArrayList<string> ();
            foreach (var n in d.nodes) diagram_nodes (n, 0, parts);
            sb.append (string.joinv (";", parts.to_array ()));
            return sb.str;
        }

        private static void diagram_nodes (DiagramNode n, int depth, Gee.List<string> parts) {
            parts.add ("%d,%s,%s".printf (depth, enc (n.color), enc (n.plain ())));
            foreach (var c in n.children) diagram_nodes (c, depth + 1, parts);
        }

        public static void apply_diagram_code (DiagramElement d, string code) {
            string[] p = code.split ("|", 4);
            if (p.length < 4) return;
            d.layout = (DiagramLayout) to_int (p[0]).clamp (0, (int) DiagramLayout.PICTURE_CAPTION);
            d.colors = (DiagramColors) to_int (p[1]).clamp (0, 4);
            d.style = (DiagramStyle) to_int (p[2]).clamp (0, 3);
            d.nodes.clear ();
            var stack = new Gee.ArrayList<DiagramNode> ();
            foreach (string item in p[3].split (";")) {
                if (item == "") continue;
                string[] f = item.split (",", 3);
                if (f.length < 3) continue;
                int depth = to_int (f[0]).clamp (0, 20);
                var n = new DiagramNode (dec (f[2]));
                n.color = dec (f[1]);
                while (stack.size > depth) stack.remove_at (stack.size - 1);
                if (stack.size == 0) d.nodes.add (n);
                else stack[stack.size - 1].children.add (n);
                stack.add (n);
            }
        }

        public static string ink_code (InkElement ink) {
            var parts = new Gee.ArrayList<string> ();
            foreach (var s in ink.strokes) {
                var sb = new StringBuilder ();
                sb.append ("%s,%s,%s,%s".printf (enc (s.color), dbl (s.width), dbl (s.opacity), s.highlighter ? "1" : "0"));
                for (int i = 0; i < s.pts.size; i++) sb.append ("," + fixed (s.pts[i], 2));
                parts.add (sb.str);
            }
            return string.joinv (";", parts.to_array ());
        }

        public static void apply_ink_code (InkElement ink, string code) {
            ink.strokes.clear ();
            foreach (string item in code.split (";")) {
                string[] f = item.split (",");
                if (f.length < 6) continue;
                var s = new InkStroke ();
                s.color = dec (f[0]);
                s.width = to_double (f[1], 2);
                s.opacity = to_double (f[2], 1);
                s.highlighter = f[3] == "1";
                for (int i = 4; i < f.length; i++) s.pts.add (to_double (f[i], 0));
                ink.strokes.add (s);
            }
        }

        public static string media_code (MediaElement m) {
            var bm = new Gee.ArrayList<string> ();
            foreach (var b in m.bookmarks) bm.add ("%s:%s".printf (enc (b.name), dbl (b.time)));
            return "%s|%s|%s|%s|%s|%s|%s|%d|%s|%s|%s|%s|%s|%s|%s".printf (m.is_video ? "1" : "0", dbl (m.length), dbl (m.trim_start), dbl (m.trim_end), dbl (m.fade_in), dbl (m.fade_out),
                dbl (m.volume), (int) m.start, m.loop ? "1" : "0", m.rewind ? "1" : "0", m.hide_when_stopped ? "1" : "0", m.full_screen ? "1" : "0", m.muted ? "1" : "0", enc (m.link), enc (string.joinv (";", bm.to_array ())));
        }

        public static void apply_media_code (MediaElement m, string code) {
            string[] p = fields (code, 15);
            m.is_video = p[0] != "0";
            m.length = to_double (p[1], 0);
            m.trim_start = to_double (p[2], 0);
            m.trim_end = to_double (p[3], 0);
            m.fade_in = to_double (p[4], 0);
            m.fade_out = to_double (p[5], 0);
            m.volume = to_double (p[6], 1);
            m.start = (MediaStart) to_int (p[7]).clamp (0, 2);
            m.loop = p[8] == "1";
            m.rewind = p[9] == "1";
            m.hide_when_stopped = p[10] == "1";
            m.full_screen = p[11] == "1";
            m.muted = p[12] == "1";
            m.link = dec (p[13]);
            m.bookmarks.clear ();
            foreach (string b in dec (p[14]).split (";")) {
                string[] f = b.split (":");
                if (f.length == 2) m.bookmarks.add (new MediaBookmark (dec (f[0]), to_double (f[1], 0)));
            }
        }

        public static string action_code (ClickAction a) {
            return "%d|%d|%s|%s|%s|%s|%s".printf ((int) a.kind, a.slide_uid, enc (a.target), a.show_and_return ? "1" : "0", enc (a.sound), a.highlight ? "1" : "0", enc (a.tooltip));
        }

        public static ClickAction parse_action_code (string code) {
            string[] p = fields (code, 7);
            var a = new ClickAction ((ActionKind) to_int (p[0]).clamp (0, (int) ActionKind.PLAY_MEDIA));
            a.slide_uid = to_int (p[1]);
            a.target = dec (p[2]);
            a.show_and_return = p[3] == "1";
            a.sound = dec (p[4]);
            a.highlight = p[5] == "1";
            a.tooltip = dec (p[6]);
            return a;
        }

        public static string transition_code (Transition t) {
            return "%d|%d|%s|%s|%s|%d|%d".printf ((int) t.kind, (int) t.direction, dbl (t.duration), t.on_click ? "1" : "0", dbl (t.advance_after), t.subtype, t.variant);
        }

        public static void apply_transition_code (Transition t, string code) {
            string[] p = fields (code, 7);
            t.kind = (TransitionKind) to_int (p[0]).clamp (0, (int) TransitionKind.NEWSFLASH);
            t.direction = (Direction) to_int (p[1]).clamp (0, 3);
            t.duration = to_double (p[2], 0.7);
            t.on_click = p[3] != "0";
            t.advance_after = to_double (p[4], -1);
            if (p[5] != "") t.subtype = to_int (p[5]);
            if (p[6] != "") t.variant = to_int (p[6]);
        }

        public static string anim_code (Animation a) {
            return "%d|%d|%d|%d|%s|%s|%d|%d|%s|%s|%s|%d|%s|%s|%s|%s|%s|%d|%d|%d|%d|%s".printf ((int) a.anim_class, (int) a.effect, (int) a.direction, (int) a.trigger, dbl (a.duration), dbl (a.delay), a.target,
                a.subtype, dbl (a.amount), a.color, path_code (a.path), a.trigger_shape, dbl (a.repeat), a.rewind ? "1" : "0", a.auto_reverse ? "1" : "0",
                dbl (a.accel), dbl (a.decel), (int) a.after, a.paragraph, (int) a.text_unit, (int) a.path_preset, a.dim_color);
        }

        public static Animation parse_anim_code (string code) {
            string[] p = fields (code, 22);
            var a = new Animation (to_int (p[6]));
            a.anim_class = (AnimClass) to_int (p[0]).clamp (0, 4);
            a.effect = (AnimEffect) to_int (p[1]).clamp (0, (int) AnimEffect.MEDIA_STOP);
            a.direction = (Direction) to_int (p[2]).clamp (0, 3);
            a.trigger = (AnimTrigger) to_int (p[3]).clamp (0, 2);
            a.duration = to_double (p[4], 0.5);
            a.delay = to_double (p[5], 0);
            if (p[7] != "") a.subtype = to_int (p[7]);
            a.amount = to_double (p[8], 0);
            a.color = p[9];
            parse_path_code (p[10], a.path);
            a.trigger_shape = p[11] != "" ? to_int (p[11]) : -1;
            a.repeat = to_double (p[12], 1);
            a.rewind = p[13] == "1";
            a.auto_reverse = p[14] == "1";
            a.accel = to_double (p[15], 0);
            a.decel = to_double (p[16], 0);
            a.after = (AfterEffect) to_int (p[17]).clamp (0, 3);
            a.paragraph = p[18] != "" ? to_int (p[18]) : -1;
            a.text_unit = (TextUnit) to_int (p[19]).clamp (0, 2);
            a.path_preset = (MotionPreset) to_int (p[20]).clamp (0, (int) MotionPreset.FIGURE8);
            a.dim_color = p[21];
            return a;
        }

        public const string[] SHAPE_TYPES = { "rectangle", "round-rectangle", "ellipse", "isosceles-triangle", "right-triangle", "diamond",
            "parallelogram", "trapezoid", "pentagon", "hexagon", "octagon", "star4", "star5", "star6", "right-arrow", "left-arrow",
            "up-arrow", "down-arrow", "left-right-arrow", "chevron", "pentagon-right", "cross", "heart", "cloud", "ring",
            "round-rectangular-callout", "line", "non-primitive" };

        public static string shape_type (ShapeKind k) {
            return (int) k < SHAPE_TYPES.length ? SHAPE_TYPES[(int) k] : "non-primitive";
        }

        public const string[] LO_TYPES = {
            "parallelogram", "parallelogram", "trapezoid", "trapezoid", "cross", "plus", "ring", "donut", "block-arc", "blockArc",
            "can", "can", "cube", "cube", "paper", "foldedCorner", "smiley", "smileyFace", "sun", "sun", "moon", "moon",
            "lightning", "lightningBolt", "forbidden", "noSmoking", "bracket-pair", "bracketPair", "brace-pair", "bracePair",
            "left-bracket", "leftBracket", "right-bracket", "rightBracket", "left-brace", "leftBrace", "right-brace", "rightBrace",
            "quad-bevel", "bevel", "frame", "frame", "star8", "star8", "star12", "star12", "star24", "star24", "bang", "irregularSeal1",
            "flowchart-process", "flowChartProcess", "flowchart-alternate-process", "flowChartAlternateProcess",
            "flowchart-decision", "flowChartDecision", "flowchart-data", "flowChartInputOutput", "flowchart-predefined-process", "flowChartPredefinedProcess",
            "flowchart-internal-storage", "flowChartInternalStorage", "flowchart-document", "flowChartDocument", "flowchart-multidocument", "flowChartMultidocument",
            "flowchart-terminator", "flowChartTerminator", "flowchart-preparation", "flowChartPreparation", "flowchart-manual-input", "flowChartManualInput",
            "flowchart-manual-operation", "flowChartManualOperation", "flowchart-connector", "flowChartConnector", "flowchart-off-page-connector", "flowChartOffpageConnector",
            "flowchart-card", "flowChartPunchedCard", "flowchart-punched-tape", "flowChartPunchedTape", "flowchart-summing-junction", "flowChartSummingJunction",
            "flowchart-or", "flowChartOr", "flowchart-collate", "flowChartCollate", "flowchart-sort", "flowChartSort", "flowchart-extract", "flowChartExtract",
            "flowchart-merge", "flowChartMerge", "flowchart-stored-data", "flowChartOnlineStorage", "flowchart-delay", "flowChartDelay",
            "flowchart-sequential-access", "flowChartMagneticTape", "flowchart-magnetic-disk", "flowChartMagneticDisk", "flowchart-direct-access-storage", "flowChartMagneticDrum",
            "flowchart-display", "flowChartDisplay", "up-down-arrow", "upDownArrow", "4-way-arrow", "quadArrow", "striped-right-arrow", "stripedRightArrow",
            "notched-right-arrow", "notchedRightArrow", "circular-arrow", "circularArrow", "right-arrow-callout", "rightArrowCallout", "left-arrow-callout", "leftArrowCallout",
            "up-arrow-callout", "upArrowCallout", "down-arrow-callout", "downArrowCallout", "left-right-arrow-callout", "leftRightArrowCallout",
            "up-down-arrow-callout", "upDownArrowCallout", "4-way-arrow-callout", "quadArrowCallout", "rectangular-callout", "wedgeRectCallout",
            "round-callout", "wedgeEllipseCallout", "cloud-callout", "cloudCallout", "line-callout-1", "borderCallout1", "line-callout-2", "borderCallout2",
            "line-callout-3", "borderCallout3", "horizontal-scroll", "horizontalScroll", "vertical-scroll", "verticalScroll", "wave", "wave", "double-wave", "doubleWave"
        };

        public static string? preset_of_lo (string t) {
            if (t.has_prefix ("ooxml-")) {
                string n = t.substring (6);
                return PresetGeometry.has (n) ? n : null;
            }
            for (int i = 0; i + 1 < LO_TYPES.length; i += 2) if (LO_TYPES[i] == t) return LO_TYPES[i + 1];
            return null;
        }

        public static string lo_of_preset (string preset) {
            for (int i = 0; i + 1 < LO_TYPES.length; i += 2) if (LO_TYPES[i + 1] == preset) return LO_TYPES[i];
            return "ooxml-" + preset;
        }

        public static ShapeKind shape_from_type (string? t, out bool known) {
            known = true;
            if (t == null) {
                known = false;
                return ShapeKind.RECT;
            }
            for (int i = 0; i < SHAPE_TYPES.length; i++) if (SHAPE_TYPES[i] == t) return (ShapeKind) i;
            switch (t) {
                case "circle": case "ooxml-ellipse": case "flowchart-connector": return ShapeKind.ELLIPSE;
                case "ooxml-rect": case "flowchart-process": case "frame": return ShapeKind.RECT;
                case "ooxml-roundRect": case "flowchart-alternate-process": case "flowchart-terminator": return ShapeKind.ROUND_RECT;
                case "ooxml-triangle": return ShapeKind.TRIANGLE;
                case "ooxml-rtTriangle": return ShapeKind.RIGHT_TRIANGLE;
                case "flowchart-decision": case "ooxml-diamond": return ShapeKind.DIAMOND;
                case "ooxml-star5": return ShapeKind.STAR5;
                case "ooxml-star6": case "star8": case "star12": case "star24": case "mso-spt18": return ShapeKind.STAR6;
                case "ooxml-rightArrow": case "notched-right-arrow": case "striped-right-arrow": return ShapeKind.ARROW_RIGHT;
                case "ooxml-leftArrow": return ShapeKind.ARROW_LEFT;
                case "ooxml-upArrow": case "up-down-arrow": return ShapeKind.ARROW_UP;
                case "ooxml-downArrow": return ShapeKind.ARROW_DOWN;
                case "ooxml-chevron": return ShapeKind.CHEVRON;
                case "ooxml-homePlate": return ShapeKind.HOME_PLATE;
                case "ooxml-plus": case "ooxml-mathPlus": return ShapeKind.PLUS;
                case "ooxml-heart": return ShapeKind.HEART;
                case "ooxml-cloud": return ShapeKind.CLOUD;
                case "ooxml-donut": return ShapeKind.DONUT;
                case "rectangular-callout": case "round-callout": case "ooxml-wedgeRoundRectCallout": case "cloud-callout": return ShapeKind.CALLOUT;
                default:
                    known = false;
                    return ShapeKind.RECT;
            }
        }

        public static string class_of (PlaceholderKind k) {
            switch (k) {
                case PlaceholderKind.TITLE: case PlaceholderKind.CENTER_TITLE: return "title";
                case PlaceholderKind.SUBTITLE: return "subtitle";
                case PlaceholderKind.PICTURE: return "graphic";
                case PlaceholderKind.DATE: return "date-time";
                case PlaceholderKind.FOOTER: return "footer";
                case PlaceholderKind.SLIDE_NUMBER: return "page-number";
                case PlaceholderKind.CHART: return "chart";
                case PlaceholderKind.TABLE: return "table";
                case PlaceholderKind.DIAGRAM: return "orgchart";
                case PlaceholderKind.MEDIA: case PlaceholderKind.CLIP_ART: return "object";
                default: return "outline";
            }
        }

        public static PlaceholderKind placeholder_of (string? cls, bool on_master) {
            switch (cls) {
                case "title": return PlaceholderKind.TITLE;
                case "subtitle": return PlaceholderKind.SUBTITLE;
                case "outline": return on_master ? PlaceholderKind.BODY : PlaceholderKind.OBJECT;
                case "text": return PlaceholderKind.BODY;
                case "graphic": return PlaceholderKind.PICTURE;
                case "chart": return PlaceholderKind.CHART;
                case "table": return PlaceholderKind.TABLE;
                case "orgchart": return PlaceholderKind.DIAGRAM;
                case "object": return PlaceholderKind.OBJECT;
                case "date-time": return PlaceholderKind.DATE;
                case "footer": return PlaceholderKind.FOOTER;
                case "page-number": return PlaceholderKind.SLIDE_NUMBER;
                default: return PlaceholderKind.NONE;
            }
        }

        public static string subtype_of (Direction d) {
            switch (d) {
                case Direction.FROM_LEFT: return "fromLeft";
                case Direction.FROM_RIGHT: return "fromRight";
                case Direction.FROM_TOP: return "fromTop";
                default: return "fromBottom";
            }
        }

        public static Direction direction_of_subtype (string? s, Direction fallback) {
            switch (s) {
                case "fromLeft": return Direction.FROM_LEFT;
                case "fromRight": return Direction.FROM_RIGHT;
                case "fromTop": return Direction.FROM_TOP;
                case "fromBottom": return Direction.FROM_BOTTOM;
                default: return fallback;
            }
        }

        public static string anim_subtype (Direction d) {
            switch (d) {
                case Direction.FROM_LEFT: return "from-left";
                case Direction.FROM_RIGHT: return "from-right";
                case Direction.FROM_TOP: return "from-top";
                default: return "from-bottom";
            }
        }

        public static Direction anim_direction (string? s, Direction fallback) {
            switch (s) {
                case "from-left": return Direction.FROM_LEFT;
                case "from-right": return Direction.FROM_RIGHT;
                case "from-top": return Direction.FROM_TOP;
                case "from-bottom": return Direction.FROM_BOTTOM;
                default: return fallback;
            }
        }

        public static string preset_id (AnimClass cls, AnimEffect e) {
            return EffectCatalog.odp_name (e, cls);
        }

        public static AnimEffect effect_of_preset (string? id, AnimClass cls) {
            return EffectCatalog.from_odp (id, cls);
        }

        public static string node_type (AnimTrigger t) {
            switch (t) {
                case AnimTrigger.WITH_PREVIOUS: return "with-previous";
                case AnimTrigger.AFTER_PREVIOUS: return "after-previous";
                default: return "on-click";
            }
        }

        public static string ext_for_mime (string mime) {
            switch (mime) {
                case "image/jpeg": return "jpg";
                case "image/gif": return "gif";
                case "image/svg+xml": return "svg";
                case "image/bmp": return "bmp";
                case "image/tiff": return "tif";
                case "image/webp": return "webp";
                default: return "png";
            }
        }

        public static string sniff_mime (Bytes data, string name) {
            unowned uint8[] d = data.get_data ();
            if (d.length >= 8 && d[0] == 0x89 && d[1] == 'P' && d[2] == 'N' && d[3] == 'G') return "image/png";
            if (d.length >= 3 && d[0] == 0xff && d[1] == 0xd8) return "image/jpeg";
            if (d.length >= 4 && d[0] == 'G' && d[1] == 'I' && d[2] == 'F') return "image/gif";
            if (d.length >= 2 && d[0] == 'B' && d[1] == 'M') return "image/bmp";
            return ImageElement.mime_for (name);
        }
    }
}
