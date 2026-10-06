namespace Singularity.Apps.Slides {

    public class InkCodec {
        private const double PT_PER_UNIT = 28.346456692913385 / 1000.0;

        private class Brush {
            public string color = "#000000";
            public double width = 1.5;
            public double opacity = 1;
            public bool highlighter = false;
        }

        private static Gee.ArrayList<double?> decode (string data) {
            var pts = new Gee.ArrayList<double?> ();
            double lx = 0, ly = 0, vx = 0, vy = 0;
            foreach (string point in data.split (",")) {
                var vals = new double[2];
                var modes = new char[2];
                int count = 0;
                int i = 0;
                string p = point.strip ();
                while (i < p.length && count < 2) {
                    while (i < p.length && p[i] == ' ') i++;
                    if (i >= p.length) break;
                    char mode = '!';
                    if (p[i] == '!' || p[i] == '\'' || p[i] == '"') {
                        mode = p[i];
                        i++;
                    }
                    int start = i;
                    if (i < p.length && (p[i] == '-' || p[i] == '+')) i++;
                    while (i < p.length && (p[i].isdigit () || p[i] == '.')) i++;
                    if (i == start) {
                        i++;
                        continue;
                    }
                    vals[count] = double.parse (p.substring (start, i - start));
                    modes[count] = mode;
                    count++;
                }
                if (count < 2) continue;
                double x, y;
                if (modes[0] == '\'') {
                    vx = vals[0];
                    x = lx + vx;
                } else if (modes[0] == '"') {
                    vx += vals[0];
                    x = lx + vx;
                } else {
                    x = vals[0];
                    vx = pts.size >= 2 ? x - lx : 0;
                }
                if (modes[1] == '\'') {
                    vy = vals[1];
                    y = ly + vy;
                } else if (modes[1] == '"') {
                    vy += vals[1];
                    y = ly + vy;
                } else {
                    y = vals[1];
                    vy = pts.size >= 2 ? y - ly : 0;
                }
                pts.add (x);
                pts.add (y);
                lx = x;
                ly = y;
            }
            return pts;
        }

        public static bool parse (string text, InkElement ink) {
            Xml.Doc* doc = Xml.Parser.read_memory (text, text.length, null, null, Xml.ParserOption.NONET | Xml.ParserOption.NOERROR | Xml.ParserOption.NOWARNING);
            if (doc == null) return false;
            Xml.Node* root = doc->get_root_element ();
            if (root == null) {
                delete doc;
                return false;
            }
            var brushes = new Gee.HashMap<string, Brush> ();
            double res = 1000;
            walk_defs (root, brushes, ref res);
            var raw = new Gee.ArrayList<InkStroke> ();
            walk_traces (root, brushes, raw, res);
            delete doc;
            if (raw.size == 0) return false;
            double x1 = double.MAX, y1 = double.MAX, x2 = -double.MAX, y2 = -double.MAX;
            foreach (var s in raw) {
                for (int i = 0; i + 1 < s.pts.size; i += 2) {
                    x1 = double.min (x1, s.pts[i]);
                    y1 = double.min (y1, s.pts[i + 1]);
                    x2 = double.max (x2, s.pts[i]);
                    y2 = double.max (y2, s.pts[i + 1]);
                }
            }
            double bw = double.max (x2 - x1, 0.001), bh = double.max (y2 - y1, 0.001);
            bool placed = ink.w > 0 && ink.h > 0;
            double sx = 1, sy = 1, ox = x1, oy = y1, tx = x1, ty = y1;
            if (placed) {
                double pad = 0;
                foreach (var s in raw) pad = double.max (pad, s.width / 2);
                double iw = double.max (ink.w - pad * 2, 0.5), ih = double.max (ink.h - pad * 2, 0.5);
                sx = bw > 0.01 ? iw / bw : 1;
                sy = bh > 0.01 ? ih / bh : 1;
                if (bw <= 0.01) sx = sy;
                if (bh <= 0.01) sy = sx;
                tx = ink.x + pad;
                ty = ink.y + pad;
            }
            foreach (var s in raw) {
                for (int i = 0; i + 1 < s.pts.size; i += 2) {
                    s.pts[i] = tx + (s.pts[i] - ox) * sx;
                    s.pts[i + 1] = ty + (s.pts[i + 1] - oy) * sy;
                }
                ink.strokes.add (s);
            }
            if (!placed) ink.fit ();
            return true;
        }

        private static void walk_defs (Xml.Node* n, Gee.HashMap<string, Brush> brushes, ref double res) {
            for (Xml.Node* c = n->children; c != null; c = c->next) {
                if (c->type != Xml.ElementType.ELEMENT_NODE) continue;
                if (c->name == "brush") {
                    var b = new Brush ();
                    foreach (Xml.Node* p in XmlIn.elements (c, "brushProperty")) {
                        string name = XmlIn.attr (p, "name") ?? "";
                        string val = XmlIn.attr (p, "value") ?? "";
                        string units = XmlIn.attr (p, "units") ?? "cm";
                        switch (name) {
                            case "width":
                                double w = double.parse (val);
                                b.width = units == "cm" ? w * 28.3465 : (units == "mm" ? w * 2.83465 : w);
                                break;
                            case "color":
                                b.color = val.down ();
                                break;
                            case "transparency":
                                b.opacity = 1 - double.parse (val) / 255.0;
                                break;
                            case "rasterOp":
                                b.highlighter = val == "maskPen";
                                break;
                            default:
                                break;
                        }
                    }
                    string id = XmlIn.attr_any (c, "id") ?? "";
                    brushes["#" + id] = b;
                } else if (c->name == "channelProperty" && XmlIn.attr (c, "channel") == "X" && XmlIn.attr (c, "name") == "resolution") {
                    double r = double.parse (XmlIn.attr (c, "value") ?? "1000");
                    string units = XmlIn.attr (c, "units") ?? "1/cm";
                    if (r > 0) res = units == "1/in" ? r / 2.54 : (units == "1/mm" ? r * 10 : r);
                }
                walk_defs (c, brushes, ref res);
            }
        }

        private static void walk_traces (Xml.Node* n, Gee.HashMap<string, Brush> brushes, Gee.ArrayList<InkStroke> list, double res) {
            for (Xml.Node* c = n->children; c != null; c = c->next) {
                if (c->type != Xml.ElementType.ELEMENT_NODE) continue;
                if (c->name == "trace") {
                    var pts = decode (XmlIn.text (c));
                    if (pts.size < 2) continue;
                    var s = new InkStroke ();
                    double k = 28.346456692913385 / res;
                    foreach (var v in pts) s.pts.add (v * k);
                    string bref = XmlIn.attr (c, "brushRef") ?? "";
                    if (brushes.has_key (bref)) {
                        var b = brushes[bref];
                        s.color = b.color;
                        s.width = b.width;
                        s.opacity = b.opacity;
                        s.highlighter = b.highlighter;
                    }
                    if (s.pts.size == 2) {
                        s.pts.add (s.pts[0] + 0.01);
                        s.pts.add (s.pts[1]);
                    }
                    list.add (s);
                } else {
                    walk_traces (c, brushes, list, res);
                }
            }
        }

        public static string write (InkElement ink) {
            var x = new XmlOut ();
            x.start ("inkml:ink").a ("xmlns:inkml", Ooxml.NS_INKML);
            x.start ("inkml:definitions");
            x.start ("inkml:context").a ("xml:id", "ctx0");
            x.start ("inkml:inkSource").a ("xml:id", "inkSrc0");
            x.start ("inkml:traceFormat");
            x.start ("inkml:channel").a ("name", "X").a ("type", "integer").a ("units", "cm").end ();
            x.start ("inkml:channel").a ("name", "Y").a ("type", "integer").a ("units", "cm").end ();
            x.end ();
            x.start ("inkml:channelProperties");
            x.start ("inkml:channelProperty").a ("channel", "X").a ("name", "resolution").a ("value", "1000").a ("units", "1/cm").end ();
            x.start ("inkml:channelProperty").a ("channel", "Y").a ("name", "resolution").a ("value", "1000").a ("units", "1/cm").end ();
            x.end ();
            x.end ();
            x.end ();
            for (int i = 0; i < ink.strokes.size; i++) {
                var s = ink.strokes[i];
                x.start ("inkml:brush").a ("xml:id", "br%d".printf (i));
                string wcm = XmlOut.num (s.width / 28.3465);
                x.start ("inkml:brushProperty").a ("name", "width").a ("value", wcm).a ("units", "cm").end ();
                x.start ("inkml:brushProperty").a ("name", "height").a ("value", wcm).a ("units", "cm").end ();
                x.start ("inkml:brushProperty").a ("name", "color").a ("value", s.color.up ()).end ();
                if (s.opacity < 1) x.start ("inkml:brushProperty").a ("name", "transparency").a ("value", ((int) Math.round ((1 - s.opacity) * 255)).to_string ()).end ();
                if (s.highlighter) {
                    x.start ("inkml:brushProperty").a ("name", "tip").a ("value", "rectangle").end ();
                    x.start ("inkml:brushProperty").a ("name", "rasterOp").a ("value", "maskPen").end ();
                }
                x.end ();
            }
            x.end ();
            for (int i = 0; i < ink.strokes.size; i++) {
                var s = ink.strokes[i];
                var sb = new StringBuilder ();
                for (int k = 0; k + 1 < s.pts.size; k += 2) {
                    if (k > 0) sb.append (", ");
                    sb.append ("%d %d".printf ((int) Math.round ((s.pts[k] - ink.x) / PT_PER_UNIT), (int) Math.round ((s.pts[k + 1] - ink.y) / PT_PER_UNIT)));
                }
                x.start ("inkml:trace").a ("contextRef", "#ctx0").a ("brushRef", "#br%d".printf (i)).text (sb.str).end ();
            }
            x.end ();
            return x.finish ();
        }
    }
}
