namespace Singularity.Apps.Slides {

    public class OdpReader {
        private ZipReader zip;
        private Presentation pres;
        private bool private_data = false;
        private Gee.HashMap<string, Xml.Node*> common = new Gee.HashMap<string, Xml.Node*> ();
        private Gee.HashMap<string, Xml.Node*> auto_content = new Gee.HashMap<string, Xml.Node*> ();
        private Gee.HashMap<string, Xml.Node*> auto_styles = new Gee.HashMap<string, Xml.Node*> ();
        private Gee.HashMap<string, Xml.Node*> defaults = new Gee.HashMap<string, Xml.Node*> ();
        private Gee.HashMap<string, Xml.Node*> named = new Gee.HashMap<string, Xml.Node*> ();
        private Gee.HashMap<string, Bytes> images = new Gee.HashMap<string, Bytes> ();
        private Gee.HashMap<string, Element> id_map = new Gee.HashMap<string, Element> ();
        private Gee.HashMap<string, Layout> page_layouts = new Gee.HashMap<string, Layout> ();
        private Gee.ArrayList<Xml.Doc*> docs = new Gee.ArrayList<Xml.Doc*> ();

        private const int CONTENT = 0;
        private const int STYLES = 1;

        private class Ref {
            public int scope;
            public string family;
            public string name;

            public Ref (int scope, string family, string name) {
                this.scope = scope;
                this.family = family;
                this.name = name;
            }
        }

        private class Ctx {
            public int scope;
            public bool on_master;
            public bool layout_page;
        }

        public OdpReader (ZipReader zip) {
            this.zip = zip;
        }

        ~OdpReader () {
            foreach (var d in docs) delete d;
        }

        private Xml.Doc* load (string name, bool required) throws Error {
            string? text = zip.read_text (name);
            if (text == null) {
                if (required) throw new FormatError.INVALID (_("The presentation is missing \"%s\".").printf (name));
                return null;
            }
            Xml.Doc* doc = Xml.Parser.read_memory (text, text.length, null, null, Xml.ParserOption.NONET | Xml.ParserOption.HUGE | Xml.ParserOption.NOERROR | Xml.ParserOption.NOWARNING);
            if (doc == null || doc->get_root_element () == null) {
                if (doc != null) delete doc;
                throw new FormatError.INVALID (_("The presentation contains malformed XML."));
            }
            docs.add (doc);
            return doc;
        }

        private static string uri_of (string prefix) {
            switch (prefix) {
                case "office": return Odf.NS_OFFICE;
                case "style": return Odf.NS_STYLE;
                case "text": return Odf.NS_TEXT;
                case "table": return Odf.NS_TABLE;
                case "draw": return Odf.NS_DRAW;
                case "fo": return Odf.NS_FO;
                case "xlink": return Odf.NS_XLINK;
                case "dc": return Odf.NS_DC;
                case "meta": return Odf.NS_META;
                case "presentation": return Odf.NS_PRESENTATION;
                case "svg": return Odf.NS_SVG;
                case "chart": return Odf.NS_CHART;
                case "smil": return Odf.NS_SMIL;
                case "anim": return Odf.NS_ANIM;
                case "xml": return Odf.NS_XML;
                case "loext": return Odf.NS_LOEXT;
                case "sgs": return Odf.NS_SGS;
                case "manifest": return Odf.NS_MANIFEST;
                case "officeooo": return "http://openoffice.org/2009/office";
                case "script": return "urn:oasis:names:tc:opendocument:xmlns:script:1.0";
                default: return "";
            }
        }

        public static string? a (Xml.Node* n, string qname) {
            if (n == null) return null;
            int colon = qname.index_of (":");
            string local = colon >= 0 ? qname.substring (colon + 1) : qname;
            string uri = colon >= 0 ? uri_of (qname.substring (0, colon)) : "";
            for (Xml.Attr* at = n->properties; at != null; at = at->next) {
                if (at->name != local) continue;
                string href = at->ns != null && at->ns->href != null ? at->ns->href : "";
                if (href == uri) return at->children != null ? at->children->content : "";
            }
            return null;
        }

        private static bool is (Xml.Node* n, string qname) {
            if (n == null || n->type != Xml.ElementType.ELEMENT_NODE) return false;
            int colon = qname.index_of (":");
            string local = qname.substring (colon + 1);
            if (n->name != local) return false;
            string uri = uri_of (qname.substring (0, colon));
            return XmlIn.ns_of (n) == uri;
        }

        private static Xml.Node* kid (Xml.Node* n, string qname) {
            if (n == null) return null;
            for (Xml.Node* c = n->children; c != null; c = c->next) if (is (c, qname)) return c;
            return null;
        }

        private static Gee.ArrayList<Xml.Node*> kids (Xml.Node* n, string? qname = null) {
            var list = new Gee.ArrayList<Xml.Node*> ();
            if (n == null) return list;
            for (Xml.Node* c = n->children; c != null; c = c->next) {
                if (c->type != Xml.ElementType.ELEMENT_NODE) continue;
                if (qname == null || is (c, qname)) list.add (c);
            }
            return list;
        }

        private void index_styles (Xml.Node* container, Gee.HashMap<string, Xml.Node*> target) {
            foreach (var n in kids (container)) {
                string? name = a (n, "style:name") ?? a (n, "draw:name");
                if (is (n, "style:style")) {
                    string fam = a (n, "style:family") ?? "";
                    if (name != null) target[fam + "/" + name] = n;
                } else if (is (n, "style:default-style")) {
                    defaults[a (n, "style:family") ?? ""] = n;
                } else if (is (n, "text:list-style")) {
                    if (name != null) target["list/" + name] = n;
                } else if (is (n, "style:presentation-page-layout")) {
                    continue;
                } else if (name != null) {
                    named[n->name + "/" + name] = n;
                    if (a (n, "draw:display-name") != null) named[n->name + "/" + a (n, "draw:display-name")] = n;
                }
            }
        }

        private Xml.Node* lookup (int scope, string family, string name) {
            string key = family + "/" + name;
            if (scope == CONTENT && auto_content.has_key (key)) return auto_content[key];
            if (scope == STYLES && auto_styles.has_key (key)) return auto_styles[key];
            if (common.has_key (key)) return common[key];
            if (scope == CONTENT && auto_styles.has_key (key)) return auto_styles[key];
            return null;
        }

        private string? prop_in (int scope, string family, string name, string pelem, string attr) {
            Xml.Node* node = lookup (scope, family, name);
            int guard = 0;
            while (node != null && guard++ < 32) {
                Xml.Node* p = kid (node, pelem);
                if (p != null) {
                    string? v = a (p, attr);
                    if (v != null) return v;
                }
                string? parent = a (node, "style:parent-style-name");
                if (parent == null) break;
                node = lookup (scope, family, parent);
            }
            return null;
        }

        private string? prop (Gee.List<Ref> refs, string pelem, string attr, bool use_defaults = true) {
            foreach (var r in refs) {
                string? v = prop_in (r.scope, r.family, r.name, pelem, attr);
                if (v != null) return v;
            }
            if (use_defaults) {
                foreach (var r in refs) {
                    var d = defaults[r.family];
                    if (d == null) continue;
                    string? v = a (kid (d, pelem), attr);
                    if (v != null) return v;
                }
            }
            return null;
        }

        private Gee.ArrayList<Ref> refs_of (Xml.Node* n, Ctx c) {
            var list = new Gee.ArrayList<Ref> ();
            string? ps = a (n, "presentation:style-name");
            if (ps != null) list.add (new Ref (c.scope, "presentation", ps));
            string? ds = a (n, "draw:style-name");
            if (ds != null) list.add (new Ref (c.scope, "graphic", ds));
            if (list.size == 0) list.add (new Ref (c.scope, "graphic", "standard"));
            return list;
        }

        private Bytes? image_bytes (string? href) {
            if (href == null || href == "") return null;
            string path = href.has_prefix ("./") ? href.substring (2) : href;
            if (images.has_key (path)) return images[path];
            try {
                var data = zip.read (path);
                if (data == null) return null;
                var b = new Bytes (data);
                images[path] = b;
                return b;
            } catch (Error e) {
                return null;
            }
        }

        private static string color_with_alpha (string hex, double alpha) {
            if (alpha < 0.999) return ColorSpec.with_alpha (hex.down (), alpha.clamp (0, 1));
            return hex.down ();
        }

        private Fill read_fill (Gee.List<Ref> refs, string pelem = "style:graphic-properties", bool use_defaults = true) {
            var f = new Fill ();
            string? kind = prop (refs, pelem, "draw:fill", use_defaults);
            if (kind == null) return f;
            double opacity = Odf.percent (prop (refs, pelem, "draw:opacity", use_defaults), 1);
            switch (kind) {
                case "solid":
                case "hatch":
                    f.kind = FillKind.SOLID;
                    f.color = color_with_alpha (prop (refs, pelem, "draw:fill-color", use_defaults) ?? "#99ccff", opacity);
                    break;
                case "gradient":
                    string? gname = prop (refs, pelem, "draw:fill-gradient-name", use_defaults);
                    Xml.Node* g = gname != null ? named["gradient/" + gname] : null;
                    if (g == null) {
                        f.kind = FillKind.SOLID;
                        f.color = prop (refs, pelem, "draw:fill-color", use_defaults) ?? "#ffffff";
                        break;
                    }
                    f.kind = FillKind.GRADIENT;
                    string style = a (g, "draw:style") ?? "linear";
                    f.radial = style == "radial" || style == "ellipsoid" || style == "square" || style == "rectangular";
                    string c1 = (a (g, "draw:start-color") ?? "#000000").down ();
                    string c2 = (a (g, "draw:end-color") ?? "#ffffff").down ();
                    if (style == "axial") {
                        f.stops.add (new GradientStop (0, c2));
                        f.stops.add (new GradientStop (0.5, c1));
                        f.stops.add (new GradientStop (1, c2));
                    } else {
                        f.stops.add (new GradientStop (0, c1));
                        f.stops.add (new GradientStop (1, c2));
                    }
                    string? oname = prop (refs, pelem, "draw:opacity-name", use_defaults);
                    Xml.Node* op = oname != null ? named["opacity/" + oname] : null;
                    if (op != null) {
                        double o1 = Odf.percent (a (op, "draw:start"), 1), o2 = Odf.percent (a (op, "draw:end"), 1);
                        f.stops[0].color = color_with_alpha (f.stops[0].color, o1);
                        f.stops[f.stops.size - 1].color = color_with_alpha (f.stops[f.stops.size - 1].color, o2);
                    }
                    f.color = f.stops[0].color;
                    double ang = 0;
                    string? av = a (g, "draw:angle");
                    if (av != null) {
                        string t = av.strip ();
                        if (t.has_suffix ("deg")) ang = Odf.to_double (t.substring (0, t.length - 3));
                        else if (t.has_suffix ("rad")) ang = Odf.to_double (t.substring (0, t.length - 3)) * 180 / Math.PI;
                        else if (t.has_suffix ("grad")) ang = Odf.to_double (t.substring (0, t.length - 4)) * 0.9;
                        else ang = Odf.to_double (t) / 10;
                    }
                    f.angle = ((90 - ang) % 360 + 360) % 360;
                    break;
                case "bitmap":
                    string? iname = prop (refs, pelem, "draw:fill-image-name", use_defaults);
                    Xml.Node* img = iname != null ? named["fill-image/" + iname] : null;
                    var bytes = img != null ? image_bytes (a (img, "xlink:href")) : null;
                    if (bytes == null) break;
                    f.kind = FillKind.IMAGE;
                    f.image = bytes;
                    f.image_mime = Odf.sniff_mime (bytes, a (img, "xlink:href") ?? "");
                    f.tile = (prop (refs, pelem, "style:repeat", use_defaults) ?? "stretch") == "repeat";
                    break;
                default:
                    break;
            }
            return f;
        }

        private ArrowKind marker_kind (string? name) {
            if (name == null || name == "") return ArrowKind.NONE;
            Xml.Node* m = named["marker/" + name];
            string label = (m != null ? (a (m, "draw:display-name") ?? name) : name).down ();
            if (label.contains ("line") && label.contains ("arrow")) return ArrowKind.ARROW;
            if (label.contains ("circle") || label.contains ("oval")) return ArrowKind.OVAL;
            if (label.contains ("diamond") || label.contains ("square")) return ArrowKind.DIAMOND;
            return ArrowKind.TRIANGLE;
        }

        private Line read_line (Gee.List<Ref> refs) {
            var l = new Line ();
            string stroke = prop (refs, "style:graphic-properties", "draw:stroke") ?? "none";
            if (stroke == "none") {
                l.color = "";
                l.width = 0;
                return l;
            }
            double opacity = Odf.percent (prop (refs, "style:graphic-properties", "svg:stroke-opacity"), 1);
            l.color = color_with_alpha (prop (refs, "style:graphic-properties", "svg:stroke-color") ?? "#000000", opacity);
            l.width = Odf.length (prop (refs, "style:graphic-properties", "svg:stroke-width"), 0);
            if (l.width <= 0) l.width = 0.75;
            if (stroke == "dash") {
                string? dn = prop (refs, "style:graphic-properties", "draw:stroke-dash");
                Xml.Node* d = dn != null ? named["stroke-dash/" + dn] : null;
                if (d == null) {
                    l.dash = DashKind.DASH;
                } else {
                    double len1 = Odf.percent (a (d, "draw:dots1-length"), -1);
                    if (len1 < 0) len1 = Odf.length (a (d, "draw:dots1-length"), 1) / double.max (l.width, 0.1);
                    if (a (d, "draw:dots2") != null && Odf.to_int (a (d, "draw:dots2") ?? "0") > 0) l.dash = DashKind.DASH_DOT;
                    else if (len1 <= 1.5) l.dash = DashKind.DOT;
                    else if (len1 >= 7) l.dash = DashKind.LONG_DASH;
                    else l.dash = DashKind.DASH;
                }
            }
            l.head = marker_kind (prop (refs, "style:graphic-properties", "draw:marker-start"));
            l.tail = marker_kind (prop (refs, "style:graphic-properties", "draw:marker-end"));
            return l;
        }

        private Shadow read_shadow (Gee.List<Ref> refs) {
            var s = new Shadow ();
            s.enabled = (prop (refs, "style:graphic-properties", "draw:shadow") ?? "hidden") == "visible";
            double dx = Odf.length (prop (refs, "style:graphic-properties", "draw:shadow-offset-x"), 3);
            double dy = Odf.length (prop (refs, "style:graphic-properties", "draw:shadow-offset-y"), 3);
            s.distance = Math.sqrt (dx * dx + dy * dy);
            s.angle = Math.atan2 (dy, dx) * 180 / Math.PI;
            if (s.angle < 0) s.angle += 360;
            s.color = (prop (refs, "style:graphic-properties", "draw:shadow-color") ?? "#000000").down ();
            s.opacity = Odf.percent (prop (refs, "style:graphic-properties", "draw:shadow-opacity"), 0.35);
            s.blur = Odf.length (prop (refs, "style:graphic-properties", "loext:shadow-blur"), 0);
            return s;
        }

        private void read_body_props (Gee.List<Ref> refs, TextBody b) {
            string gp = "style:graphic-properties";
            b.inset_left = Odf.length (prop (refs, gp, "fo:padding-left") ?? prop (refs, gp, "fo:padding"), b.inset_left);
            b.inset_right = Odf.length (prop (refs, gp, "fo:padding-right") ?? prop (refs, gp, "fo:padding"), b.inset_right);
            b.inset_top = Odf.length (prop (refs, gp, "fo:padding-top") ?? prop (refs, gp, "fo:padding"), b.inset_top);
            b.inset_bottom = Odf.length (prop (refs, gp, "fo:padding-bottom") ?? prop (refs, gp, "fo:padding"), b.inset_bottom);
            string? va = prop (refs, gp, "draw:textarea-vertical-align", false);
            if (va != null) {
                b.anchor = va == "middle" ? TextAnchor.MIDDLE : (va == "bottom" ? TextAnchor.BOTTOM : TextAnchor.TOP);
                b.anchor_set = true;
            }
            b.wrap = (prop (refs, gp, "fo:wrap-option") ?? "wrap") != "no-wrap";
            string fit = prop (refs, gp, "draw:fit-to-size") ?? "false";
            if (fit == "shrink-to-fit" || (prop (refs, gp, "style:shrink-to-fit") ?? "false") == "true") b.autofit = AutoFit.SHRINK;
            else if ((prop (refs, gp, "draw:auto-grow-height") ?? "false") == "true") b.autofit = AutoFit.RESIZE;
            else b.autofit = AutoFit.NONE;
        }

        private void geometry (Xml.Node* n, Element e) {
            e.w = Odf.length (a (n, "svg:width"), 0);
            e.h = Odf.length (a (n, "svg:height"), 0);
            string? tr = a (n, "draw:transform");
            if (tr == null) {
                e.x = Odf.length (a (n, "svg:x"), 0);
                e.y = Odf.length (a (n, "svg:y"), 0);
                return;
            }
            double rot = 0, tx = 0, ty = 0;
            double sx = 1, sy = 1;
            string t = tr;
            int pos = 0;
            while (pos < t.length) {
                int open = t.index_of ("(", pos);
                if (open < 0) break;
                int close = t.index_of (")", open);
                if (close < 0) break;
                string name = t.substring (pos, open - pos).strip ();
                string[] args = t.substring (open + 1, close - open - 1).replace (",", " ").split (" ");
                var vals = new Gee.ArrayList<string> ();
                foreach (string s in args) if (s.strip () != "") vals.add (s.strip ());
                if (name == "rotate" && vals.size > 0) rot = Odf.to_double (vals[0]);
                else if (name == "translate" && vals.size > 0) {
                    tx = Odf.length (vals[0], 0);
                    ty = vals.size > 1 ? Odf.length (vals[1], 0) : 0;
                } else if (name == "scale" && vals.size > 0) {
                    sx = Odf.to_double (vals[0], 1);
                    sy = vals.size > 1 ? Odf.to_double (vals[1], 1) : sx;
                }
                pos = close + 1;
            }
            e.w *= Math.fabs (sx);
            e.h *= Math.fabs (sy);
            double hw = e.w / 2, hh = e.h / 2;
            double cx = hw * Math.cos (rot) + hh * Math.sin (rot) + tx;
            double cy = -hw * Math.sin (rot) + hh * Math.cos (rot) + ty;
            e.x = cx - hw;
            e.y = cy - hh;
            double deg = -rot * 180 / Math.PI;
            deg = ((deg % 360) + 360) % 360;
            if (Math.fabs (deg - 360) < 1e-7 || Math.fabs (deg) < 1e-7) deg = 0;
            e.rotation = deg;
        }

        private void base_attrs (Xml.Node* n, Element e, Ctx c) {
            string? name = a (n, "draw:name");
            if (name != null) e.name = name;
            Xml.Node* desc = kid (n, "svg:desc") ?? kid (n, "svg:title");
            if (desc != null) e.description = XmlIn.text (desc);
            string? did = a (n, "draw:id");
            string? xid = a (n, "xml:id");
            if (did != null) id_map[did] = e;
            if (xid != null) id_map[xid] = e;
            string? cls = a (n, "presentation:class");
            if (cls != null) {
                e.placeholder = Odf.placeholder_of (cls, c.on_master);
                if (e.placeholder != PlaceholderKind.NONE && !c.on_master) e.inherit_geometry = false;
            }
        }

        private void apply_private (Xml.Node* n, Element e) {
            read_events (n, e);
            if (!private_data) return;
            string? v = a (n, "sgs:id");
            if (v != null) e.id = Odf.to_int (v);
            v = a (n, "sgs:geom");
            if (v != null) Odf.apply_geom_code (e, v);
            v = a (n, "sgs:line");
            if (v != null) e.line = Odf.parse_line (v);
            v = a (n, "sgs:shadow");
            if (v != null) e.shadow = Odf.parse_shadow (v);
            v = a (n, "sgs:ph");
            if (v != null) {
                string[] p = Odf.fields (v, 3);
                e.placeholder = (PlaceholderKind) Odf.to_int (p[0]).clamp (0, 9);
                e.placeholder_idx = Odf.to_int (p[1], -1);
                e.inherit_geometry = p[2] == "1";
            } else {
                e.placeholder = PlaceholderKind.NONE;
                e.placeholder_idx = -1;
                e.inherit_geometry = false;
            }
            e.locked = a (n, "sgs:locked") == "1";
            v = a (n, "sgs:click");
            if (v != null) e.click = Odf.parse_action_code (v);
            v = a (n, "sgs:hover");
            if (v != null) e.hover = Odf.parse_action_code (v);
        }

        private Xml.Node* settings_node = null;
        private Gee.ArrayList<ClickAction> pending_page = new Gee.ArrayList<ClickAction> ();

        private void read_events (Xml.Node* n, Element e) {
            Xml.Node* ev = kid (n, "office:event-listeners");
            if (ev == null) return;
            foreach (var l in kids (ev)) {
                string evn = a (l, "script:event-name") ?? "";
                if (evn != "dom:click") continue;
                string act = a (l, "presentation:action") ?? "none";
                string href = a (l, "xlink:href") ?? "";
                var ca = new ClickAction ();
                switch (act) {
                    case "next-page": ca.kind = ActionKind.NEXT_SLIDE; break;
                    case "previous-page": ca.kind = ActionKind.PREVIOUS_SLIDE; break;
                    case "first-page": ca.kind = ActionKind.FIRST_SLIDE; break;
                    case "last-page": ca.kind = ActionKind.LAST_SLIDE; break;
                    case "stop": ca.kind = ActionKind.END_SHOW; break;
                    case "execute": ca.kind = ActionKind.PROGRAM; ca.target = href; break;
                    case "show":
                        if (href.has_prefix ("#")) {
                            ca.kind = ActionKind.SLIDE;
                            ca.target = href.substring (1);
                            pending_page.add (ca);
                        } else {
                            ca.kind = ActionKind.URL;
                            ca.target = href;
                        }
                        break;
                    default: continue;
                }
                if (e.click == null) e.click = ca;
            }
        }

        private Gee.ArrayList<Element> read_elements (Xml.Node* container, Ctx c) {
            var list = new Gee.ArrayList<Element> ();
            foreach (var n in kids (container)) {
                if (private_data && c.layout_page && a (n, "sgs:origin") == "master") continue;
                var e = read_element (n, c);
                if (e != null) list.add (e);
            }
            return list;
        }

        private Element? read_element (Xml.Node* n, Ctx c) {
            if (is (n, "draw:custom-shape")) return read_custom (n, c);
            if (is (n, "draw:rect") || is (n, "draw:ellipse") || is (n, "draw:circle")) return read_basic (n, c);
            if (is (n, "draw:polygon") || is (n, "draw:polyline") || is (n, "draw:path")) return read_poly (n, c);
            if (is (n, "draw:line") || is (n, "draw:connector")) return read_line_shape (n, c);
            if (is (n, "draw:frame")) return read_frame (n, c);
            if (is (n, "draw:g") && private_data && a (n, "sgs:ink") != null) {
                var ink = new InkElement ();
                base_attrs (n, ink, c);
                Odf.apply_ink_code (ink, a (n, "sgs:ink"));
                ink.fit ();
                apply_private (n, ink);
                return ink;
            }
            if (is (n, "draw:g") && private_data && a (n, "sgs:diagram") != null) {
                var d = new DiagramElement ();
                base_attrs (n, d, c);
                Odf.apply_diagram_code (d, a (n, "sgs:diagram"));
                var tmp = new GroupElement ();
                foreach (var child in read_elements (n, c)) tmp.children.add (child);
                tmp.fit ();
                d.set_geometry (tmp.x, tmp.y, tmp.w, tmp.h);
                apply_private (n, d);
                return d;
            }
            if (is (n, "draw:g")) {
                var g = new GroupElement ();
                base_attrs (n, g, c);
                foreach (var child in read_elements (n, c)) g.children.add (child);
                if (g.children.size == 0) return null;
                g.fit ();
                apply_private (n, g);
                return g;
            }
            return null;
        }

        private void shape_style (Xml.Node* n, ShapeElement s, Ctx c) {
            var refs = refs_of (n, c);
            s.fill = read_fill (refs);
            s.line = read_line (refs);
            s.shadow = read_shadow (refs);
        }

        private void shape_private (Xml.Node* n, ShapeElement s) {
            if (!private_data) return;
            string? v = a (n, "sgs:shape");
            if (v != null) {
                string[] p = Odf.fields (v, 5);
                s.shape = (ShapeKind) Odf.to_int (p[0]).clamp (0, ShapeKind.PRESET);
                string? pv = a (n, "sgs:preset");
                if (pv != null) {
                    string[] pp = pv.split ("|");
                    s.preset = pp[0];
                    s.adjust_values.clear ();
                    for (int i = 1; i + 1 < pp.length; i += 2) s.adjust_values[pp[i]] = Odf.to_double (pp[i + 1], 0);
                }
                s.corner = Odf.to_double (p[1], s.corner);
                s.adjust = Odf.to_double (p[2], -1);
                s.text_box = p[3] == "1";
                Odf.parse_path_code (Odf.dec (p[4]), s.path);
            }
            v = a (n, "sgs:fill");
            if (v != null) s.fill = Odf.parse_fill (v, s.fill.image, s.fill.image_mime);
            v = a (n, "sgs:body");
            if (v == "none") s.text = null;
            else if (v != null) {
                if (s.text == null) {
                    s.text = new TextBody ();
                    s.text.paragraphs.add (new Paragraph ());
                }
                Odf.apply_body_code (s.text, v);
            }
            v = a (n, "sgs:liststyle");
            s.list_style = v != null ? Odf.parse_style (v) : null;
            v = a (n, "sgs:fx");
            if (v != null) Odf.apply_fx_code (s.effects, v);
        }

        private TextBody? body_from (Xml.Node* container, Xml.Node* style_node, Ctx c, Element e) {
            bool outline = e.placeholder == PlaceholderKind.BODY || e.placeholder == PlaceholderKind.OBJECT;
            var body = new TextBody ();
            read_paragraphs (container, body, c, outline, 0, null, false);
            read_body_props (refs_of (style_node, c), body);
            if (body.paragraphs.size == 0) body.paragraphs.add (new Paragraph ());
            return body;
        }

        private ShapeElement read_custom (Xml.Node* n, Ctx c) {
            var s = new ShapeElement ();
            base_attrs (n, s, c);
            geometry (n, s);
            shape_style (n, s, c);
            Xml.Node* geo = kid (n, "draw:enhanced-geometry");
            bool known;
            string gtype = a (geo, "draw:type") ?? "";
            string? preset = Odf.preset_of_lo (gtype);
            s.shape = Odf.shape_from_type (a (geo, "draw:type"), out known);
            if (preset != null && !ShapeKind.is_native (preset)) {
                s.shape = ShapeKind.PRESET;
                s.preset = preset;
                known = true;
            } else if (preset != null) {
                s.shape = ShapeKind.from_ooxml (preset);
                known = true;
            }
            if (!known && geo != null) {
                string? path = a (geo, "draw:enhanced-path");
                if (path != null && parse_enhanced (path, a (geo, "svg:viewBox"), s.path)) s.shape = ShapeKind.CUSTOM;
            }
            if (s.shape == ShapeKind.ROUND_RECT) {
                string? mods = a (geo, "draw:modifiers");
                if (mods != null) {
                    string first = mods.strip ().split (" ")[0];
                    double v = Odf.to_double (first, 3600);
                    s.corner = (v / 21600).clamp (0, 0.5);
                }
            }
            s.flip_h = a (geo, "draw:mirror-horizontal") == "true";
            s.flip_v = a (geo, "draw:mirror-vertical") == "true";
            s.text = body_from (n, n, c, s);
            apply_private (n, s);
            shape_private (n, s);
            return s;
        }

        private ShapeElement read_basic (Xml.Node* n, Ctx c) {
            var s = new ShapeElement (is (n, "draw:rect") ? ShapeKind.RECT : ShapeKind.ELLIPSE);
            base_attrs (n, s, c);
            if (is (n, "draw:circle") && a (n, "svg:r") != null) {
                double r = Odf.length (a (n, "svg:r"), 0);
                s.set_geometry (Odf.length (a (n, "svg:cx"), 0) - r, Odf.length (a (n, "svg:cy"), 0) - r, 2 * r, 2 * r);
            } else {
                geometry (n, s);
            }
            if (s.shape == ShapeKind.RECT && a (n, "draw:corner-radius") != null) {
                double r = Odf.length (a (n, "draw:corner-radius"), 0);
                if (r > 0) {
                    s.shape = ShapeKind.ROUND_RECT;
                    s.corner = (r / double.max (double.min (s.w, s.h), 1)).clamp (0, 0.5);
                }
            }
            shape_style (n, s, c);
            s.text = body_from (n, n, c, s);
            apply_private (n, s);
            shape_private (n, s);
            return s;
        }

        private static double[] view_box (string? vb) {
            double[] r = { 0, 0, 21600, 21600 };
            if (vb == null) return r;
            var vals = new Gee.ArrayList<double?> ();
            foreach (string p in vb.replace (",", " ").split (" ")) if (p.strip () != "") vals.add (Odf.to_double (p));
            if (vals.size == 4) {
                r[0] = vals[0];
                r[1] = vals[1];
                r[2] = vals[2] != 0 ? vals[2] : 1;
                r[3] = vals[3] != 0 ? vals[3] : 1;
            }
            return r;
        }

        private static Gee.ArrayList<string> path_tokens (string d) {
            var list = new Gee.ArrayList<string> ();
            var cur = new StringBuilder ();
            for (int i = 0; i < d.length; i++) {
                char ch = d[i];
                if (ch.isalpha () && ch != 'e' && ch != 'E') {
                    if (cur.len > 0) list.add (cur.str);
                    cur.truncate ();
                    list.add (ch.to_string ());
                } else if (ch == ' ' || ch == ',' || ch == '\n' || ch == '\t') {
                    if (cur.len > 0) list.add (cur.str);
                    cur.truncate ();
                } else if (ch == '-' && cur.len > 0 && !(cur.str.has_suffix ("e") || cur.str.has_suffix ("E"))) {
                    list.add (cur.str);
                    cur.truncate ();
                    cur.append_c (ch);
                } else if (ch == '?' || ch == '$') {
                    list.add ("?");
                    return list;
                } else {
                    cur.append_c (ch);
                }
            }
            if (cur.len > 0) list.add (cur.str);
            return list;
        }

        private static bool parse_enhanced (string d, string? vb, Gee.List<PathCommand> out_path) {
            var box = view_box (vb);
            var tokens = path_tokens (d);
            if (tokens.contains ("?")) return false;
            out_path.clear ();
            string cmd = "";
            int i = 0;
            while (i < tokens.size) {
                string t = tokens[i];
                if (t.length == 1 && t[0].isalpha ()) {
                    cmd = t;
                    i++;
                    if (cmd == "Z") out_path.add (new PathCommand ('Z', {}));
                    continue;
                }
                int need = cmd == "C" ? 6 : (cmd == "Q" ? 4 : (cmd == "M" || cmd == "L" ? 2 : 0));
                if (need == 0 || i + need > tokens.size) {
                    i++;
                    continue;
                }
                double[] pts = new double[need];
                for (int k = 0; k < need; k++) pts[k] = (Odf.to_double (tokens[i + k]) - box[k % 2]) / box[2 + k % 2];
                i += need;
                out_path.add (new PathCommand (cmd[0], pts));
                if (cmd == "M") cmd = "L";
            }
            return out_path.size > 0;
        }

        private static bool parse_svg_path (string d, double[] box, Gee.List<PathCommand> out_path) {
            var tokens = path_tokens (d);
            out_path.clear ();
            double cx = 0, cy = 0, sx = 0, sy = 0, lcx = 0, lcy = 0;
            string cmd = "";
            int i = 0;
            while (i < tokens.size) {
                string t = tokens[i];
                if (t.length == 1 && t[0].isalpha ()) {
                    cmd = t;
                    i++;
                    if (cmd == "Z" || cmd == "z") {
                        out_path.add (new PathCommand ('Z', {}));
                        cx = sx;
                        cy = sy;
                    }
                    continue;
                }
                bool rel = cmd.down () == cmd;
                string up = cmd.up ();
                double ox = rel ? cx : 0, oy = rel ? cy : 0;
                if (up == "M" || up == "L" || up == "T") {
                    if (i + 2 > tokens.size) break;
                    double x = Odf.to_double (tokens[i]) + ox, y = Odf.to_double (tokens[i + 1]) + oy;
                    i += 2;
                    out_path.add (new PathCommand (up == "M" ? 'M' : 'L', { (x - box[0]) / box[2], (y - box[1]) / box[3] }));
                    if (up == "M") {
                        sx = x;
                        sy = y;
                        cmd = rel ? "l" : "L";
                    }
                    cx = x;
                    cy = y;
                } else if (up == "H" || up == "V") {
                    if (i + 1 > tokens.size) break;
                    double v = Odf.to_double (tokens[i]);
                    i++;
                    if (up == "H") cx = v + (rel ? cx : 0);
                    else cy = v + (rel ? cy : 0);
                    out_path.add (new PathCommand ('L', { (cx - box[0]) / box[2], (cy - box[1]) / box[3] }));
                } else if (up == "C" || up == "S") {
                    int need = up == "C" ? 6 : 4;
                    if (i + need > tokens.size) break;
                    double[] p = new double[6];
                    if (up == "C") {
                        for (int k = 0; k < 6; k++) p[k] = Odf.to_double (tokens[i + k]) + (k % 2 == 0 ? ox : oy);
                    } else {
                        p[0] = 2 * cx - lcx;
                        p[1] = 2 * cy - lcy;
                        for (int k = 0; k < 4; k++) p[2 + k] = Odf.to_double (tokens[i + k]) + (k % 2 == 0 ? ox : oy);
                    }
                    i += need;
                    double[] n = new double[6];
                    for (int k = 0; k < 6; k++) n[k] = (p[k] - box[k % 2]) / box[2 + k % 2];
                    out_path.add (new PathCommand ('C', n));
                    lcx = p[2];
                    lcy = p[3];
                    cx = p[4];
                    cy = p[5];
                } else if (up == "Q") {
                    if (i + 4 > tokens.size) break;
                    double[] p = new double[4];
                    for (int k = 0; k < 4; k++) p[k] = Odf.to_double (tokens[i + k]) + (k % 2 == 0 ? ox : oy);
                    i += 4;
                    double[] n = new double[4];
                    for (int k = 0; k < 4; k++) n[k] = (p[k] - box[k % 2]) / box[2 + k % 2];
                    out_path.add (new PathCommand ('Q', n));
                    cx = p[2];
                    cy = p[3];
                } else if (up == "A") {
                    if (i + 7 > tokens.size) break;
                    double x = Odf.to_double (tokens[i + 5]) + ox, y = Odf.to_double (tokens[i + 6]) + oy;
                    i += 7;
                    out_path.add (new PathCommand ('L', { (x - box[0]) / box[2], (y - box[1]) / box[3] }));
                    cx = x;
                    cy = y;
                } else {
                    i++;
                }
            }
            return out_path.size > 0;
        }

        private ShapeElement read_poly (Xml.Node* n, Ctx c) {
            var s = new ShapeElement (ShapeKind.CUSTOM);
            base_attrs (n, s, c);
            geometry (n, s);
            shape_style (n, s, c);
            var box = view_box (a (n, "svg:viewBox"));
            if (is (n, "draw:path")) {
                parse_svg_path (a (n, "svg:d") ?? "", box, s.path);
            } else {
                string pts = a (n, "draw:points") ?? "";
                bool first = true;
                foreach (string pair in pts.split (" ")) {
                    string[] xy = pair.split (",");
                    if (xy.length != 2) continue;
                    s.path.add (new PathCommand (first ? 'M' : 'L', { (Odf.to_double (xy[0]) - box[0]) / box[2], (Odf.to_double (xy[1]) - box[1]) / box[3] }));
                    first = false;
                }
                if (is (n, "draw:polygon") && s.path.size > 0) s.path.add (new PathCommand ('Z', {}));
            }
            if (!is (n, "draw:polygon") && !Geometry.is_closed (s)) s.fill = new Fill ();
            s.text = body_from (n, n, c, s);
            apply_private (n, s);
            shape_private (n, s);
            return s;
        }

        private ShapeElement read_line_shape (Xml.Node* n, Ctx c) {
            var s = new ShapeElement (ShapeKind.LINE);
            base_attrs (n, s, c);
            double x1 = Odf.length (a (n, "svg:x1"), 0), y1 = Odf.length (a (n, "svg:y1"), 0);
            double x2 = Odf.length (a (n, "svg:x2"), 0), y2 = Odf.length (a (n, "svg:y2"), 0);
            s.set_geometry (double.min (x1, x2), double.min (y1, y2), Math.fabs (x2 - x1), Math.fabs (y2 - y1));
            s.flip_h = x2 < x1;
            s.flip_v = y2 < y1;
            var refs = refs_of (n, c);
            s.line = read_line (refs);
            if (!s.line.visible ()) {
                s.line.color = "#000000";
                s.line.width = 0.75;
            }
            s.shadow = read_shadow (refs);
            s.fill = new Fill ();
            bool has_text = kid (n, "text:p") != null || kid (n, "text:list") != null;
            s.text = has_text ? body_from (n, n, c, s) : null;
            apply_private (n, s);
            shape_private (n, s);
            return s;
        }

        private Element? read_frame (Xml.Node* n, Ctx c) {
            string? cls = a (n, "presentation:class");
            if (cls == "notes" || cls == "page" || cls == "handout") return null;
            Xml.Node* tb = kid (n, "draw:text-box");
            Xml.Node* img = kid (n, "draw:image");
            Xml.Node* obj = kid (n, "draw:object");
            Xml.Node* table = kid (n, "table:table");
            Xml.Node* plugin = kid (n, "draw:plugin");
            if (table != null) return read_table (n, table, c);
            if (plugin != null) {
                var m = read_media (n, plugin, img, c);
                if (m != null) return m;
            }
            if (private_data && a (n, "sgs:zoom") != null && img != null) return read_zoom (n, img, c);
            if (private_data && a (n, "sgs:model3d") != null) return read_model (n, img, c);
            if (obj != null) {
                var ch = read_chart_object (n, obj, c);
                if (ch != null) return ch;
                var eq = read_formula_object (n, obj, img, c);
                if (eq != null) return eq;
                if (img == null) return null;
            }
            if (img != null) return read_image (n, img, c);
            var s = new ShapeElement (ShapeKind.RECT);
            base_attrs (n, s, c);
            geometry (n, s);
            shape_style (n, s, c);
            if (s.placeholder == PlaceholderKind.NONE) s.text_box = true;
            if (tb != null) s.text = body_from (tb, n, c, s);
            else {
                s.text = new TextBody ();
                s.text.paragraphs.add (new Paragraph ());
                read_body_props (refs_of (n, c), s.text);
            }
            if (s.placeholder != PlaceholderKind.NONE && s.placeholder != PlaceholderKind.PICTURE) {
                s.fill = read_fill (refs_of (n, c), "style:graphic-properties", false);
            }
            if (s.placeholder != PlaceholderKind.NONE && !c.on_master && !private_data) {
                string? prompt = a (n, "presentation:placeholder");
                if (prompt == "true") {
                    s.text.paragraphs.clear ();
                    s.text.paragraphs.add (new Paragraph ());
                }
            }
            apply_private (n, s);
            shape_private (n, s);
            return s;
        }

        private ImageElement? read_image (Xml.Node* frame, Xml.Node* img, Ctx c) {
            Bytes? data = null;
            string href = a (img, "xlink:href") ?? "";
            if (href != "") data = image_bytes (href);
            if (data == null) {
                Xml.Node* bin = kid (img, "office:binary-data");
                if (bin != null) data = new Bytes (Base64.decode (XmlIn.text (bin).strip ()));
            }
            if (data == null) return null;
            string mime = a (img, "draw:mime-type") ?? a (img, "loext:mime-type") ?? Odf.sniff_mime (data, href);
            var e = new ImageElement (data, mime);
            base_attrs (frame, e, c);
            geometry (frame, e);
            var refs = refs_of (frame, c);
            e.line = read_line (refs);
            e.shadow = read_shadow (refs);
            string gp = "style:graphic-properties";
            e.brightness = Odf.percent (prop (refs, gp, "draw:luminance"), 0);
            e.contrast = Odf.percent (prop (refs, gp, "draw:contrast"), 0);
            if ((prop (refs, gp, "draw:color-mode") ?? "") == "greyscale") e.saturation = 0;
            e.opacity = Odf.percent (prop (refs, gp, "draw:image-opacity"), 1);
            string mirror = prop (refs, gp, "style:mirror") ?? "none";
            e.flip_h = mirror.contains ("horizontal");
            e.flip_v = mirror.contains ("vertical");
            string? clip = prop (refs, gp, "fo:clip");
            int pw = 0, ph = 0;
            if (clip != null && clip.has_prefix ("rect") && ImageCache.size_of (data, out pw, out ph)) {
                string inner = clip.substring (clip.index_of ("(") + 1).replace (")", "").replace (",", " ");
                var vals = new Gee.ArrayList<double?> ();
                foreach (string p in inner.split (" ")) if (p.strip () != "") vals.add (Odf.length (p.strip (), 0));
                if (vals.size == 4) {
                    double nw = pw * 0.75, nh = ph * 0.75;
                    e.crop_top = vals[0] / nh;
                    e.crop_right = vals[1] / nw;
                    e.crop_bottom = vals[2] / nh;
                    e.crop_left = vals[3] / nw;
                }
            }
            if (e.placeholder != PlaceholderKind.NONE) e.placeholder = PlaceholderKind.PICTURE;
            apply_private (frame, e);
            if (private_data) {
                string? v = a (frame, "sgs:image");
                if (v != null) {
                    string[] p = Odf.fields (v, 13);
                    e.crop_left = Odf.to_double (p[0]);
                    e.crop_top = Odf.to_double (p[1]);
                    e.crop_right = Odf.to_double (p[2]);
                    e.crop_bottom = Odf.to_double (p[3]);
                    e.brightness = Odf.to_double (p[4]);
                    e.contrast = Odf.to_double (p[5]);
                    e.saturation = Odf.to_double (p[6], 1);
                    e.sepia = p[7] == "1";
                    e.opacity = Odf.to_double (p[8], 1);
                    e.blur = Odf.to_double (p[9]);
                    e.corner = Odf.to_double (p[10]);
                    e.pixel_width = Odf.to_int (p[11]);
                    e.pixel_height = Odf.to_int (p[12]);
                }
            }
            return e;
        }

        private TableElement read_table (Xml.Node* frame, Xml.Node* tn, Ctx c) {
            var t = new TableElement (0, 0, 0, 0);
            base_attrs (frame, t, c);
            geometry (frame, t);
            double fx = t.x, fy = t.y, fw = t.w, fh = t.h;
            var col_widths = new Gee.ArrayList<double?> ();
            var rows = new Gee.ArrayList<Xml.Node*> ();
            collect_table (tn, col_widths, rows, c);
            int ncols = col_widths.size;
            foreach (var r in rows) {
                int n = 0;
                foreach (var cell in kids (r)) {
                    if (!is (cell, "table:table-cell") && !is (cell, "table:covered-table-cell")) continue;
                    n += int.max (1, Odf.to_int (a (cell, "table:number-columns-repeated") ?? "1", 1));
                }
                ncols = int.max (ncols, n);
            }
            if (ncols == 0 || rows.size == 0) {
                t.col_widths.add (fw > 0 ? fw : 100);
                t.row_heights.add (fh > 0 ? fh : 30);
                var row = new Gee.ArrayList<TableCell> ();
                row.add (new TableCell ());
                t.cells.add (row);
                t.sync_size ();
                t.x = fx;
                t.y = fy;
                apply_private (frame, t);
                return t;
            }
            for (int i = 0; i < ncols; i++) {
                double w = i < col_widths.size && col_widths[i] > 0 ? col_widths[i] : 0;
                t.col_widths.add (w);
            }
            double known = 0;
            int unknown = 0;
            foreach (var w in t.col_widths) {
                if (w > 0) known += w;
                else unknown++;
            }
            for (int i = 0; i < ncols; i++) if (t.col_widths[i] <= 0) t.col_widths[i] = unknown > 0 ? double.max ((fw - known) / unknown, 20) : 100;
            foreach (var r in rows) {
                string? rs = a (r, "table:style-name");
                double h = 0;
                if (rs != null) {
                    var refs = new Gee.ArrayList<Ref> ();
                    refs.add (new Ref (c.scope, "table-row", rs));
                    h = Odf.length (prop (refs, "style:table-row-properties", "style:row-height") ?? prop (refs, "style:table-row-properties", "style:min-row-height"), 0);
                }
                t.row_heights.add (h > 0 ? h : (fh > 0 ? fh / rows.size : 30));
                var row = new Gee.ArrayList<TableCell> ();
                foreach (var cn in kids (r)) {
                    bool covered = is (cn, "table:covered-table-cell");
                    if (!covered && !is (cn, "table:table-cell")) continue;
                    int rep = int.max (1, Odf.to_int (a (cn, "table:number-columns-repeated") ?? "1", 1));
                    for (int k = 0; k < rep && row.size < ncols; k++) {
                        var cell = new TableCell ();
                        cell.covered = covered;
                        if (!covered) read_cell (cn, cell, c, t);
                        row.add (cell);
                    }
                }
                while (row.size < ncols) row.add (new TableCell ());
                t.cells.add (row);
            }
            string? fr = a (tn, "table:use-first-row-styles");
            t.first_row = fr == "true";
            t.first_col = a (tn, "table:use-first-column-styles") == "true";
            t.last_row = a (tn, "table:use-last-row-styles") == "true";
            t.banded_rows = a (tn, "table:use-banding-rows-styles") == "true";
            t.banded_cols = a (tn, "table:use-banding-columns-styles") == "true";
            t.sync_size ();
            t.x = fx;
            t.y = fy;
            apply_private (frame, t);
            if (private_data) {
                string? v = a (frame, "sgs:table");
                if (v != null) {
                    string[] p = Odf.fields (v, 6);
                    t.first_row = p[0] == "1";
                    t.first_col = p[1] == "1";
                    t.last_row = p[2] == "1";
                    t.banded_rows = p[3] == "1";
                    t.banded_cols = p[4] == "1";
                    t.style_color = Odf.dec (p[5]);
                }
                v = a (frame, "sgs:border");
                if (v != null) t.border = Odf.parse_line (v);
            }
            return t;
        }

        private void collect_table (Xml.Node* n, Gee.List<double?> widths, Gee.List<Xml.Node*> rows, Ctx c) {
            foreach (var k in kids (n)) {
                if (is (k, "table:table-column")) {
                    int rep = int.max (1, Odf.to_int (a (k, "table:number-columns-repeated") ?? "1", 1));
                    double w = 0;
                    string? cs = a (k, "table:style-name");
                    if (cs != null) {
                        var refs = new Gee.ArrayList<Ref> ();
                        refs.add (new Ref (c.scope, "table-column", cs));
                        w = Odf.length (prop (refs, "style:table-column-properties", "style:column-width"), 0);
                    }
                    for (int i = 0; i < rep && widths.size < 256; i++) widths.add (w);
                } else if (is (k, "table:table-row")) {
                    int rep = int.max (1, Odf.to_int (a (k, "table:number-rows-repeated") ?? "1", 1));
                    for (int i = 0; i < rep && rows.size < 1024; i++) rows.add (k);
                } else if (is (k, "table:table-columns") || is (k, "table:table-header-columns") || is (k, "table:table-column-group")
                        || is (k, "table:table-rows") || is (k, "table:table-header-rows") || is (k, "table:table-row-group")) {
                    collect_table (k, widths, rows, c);
                }
            }
        }

        private void read_cell (Xml.Node* cn, TableCell cell, Ctx c, TableElement t) {
            cell.col_span = int.max (1, Odf.to_int (a (cn, "table:number-columns-spanned") ?? "1", 1));
            cell.row_span = int.max (1, Odf.to_int (a (cn, "table:number-rows-spanned") ?? "1", 1));
            string? cs = a (cn, "table:style-name");
            var refs = new Gee.ArrayList<Ref> ();
            if (cs != null) refs.add (new Ref (c.scope, "table-cell", cs));
            string? fill = prop (refs, "style:graphic-properties", "draw:fill-color", false);
            string? kind = prop (refs, "style:graphic-properties", "draw:fill", false);
            if (fill != null && kind != "none") cell.fill = fill.down ();
            else {
                string? bg = prop (refs, "style:table-cell-properties", "fo:background-color", false);
                if (bg != null && bg != "transparent") cell.fill = bg.down ();
            }
            string va = prop (refs, "style:graphic-properties", "draw:textarea-vertical-align", false) ?? prop (refs, "style:table-cell-properties", "style:vertical-align", false) ?? "top";
            cell.anchor = va == "middle" ? TextAnchor.MIDDLE : (va == "bottom" ? TextAnchor.BOTTOM : TextAnchor.TOP);
            cell.text = new TextBody ();
            string gp = "style:graphic-properties";
            cell.text.inset_left = Odf.length (prop (refs, gp, "fo:padding-left", false), 7.2);
            cell.text.inset_right = Odf.length (prop (refs, gp, "fo:padding-right", false), 7.2);
            cell.text.inset_top = Odf.length (prop (refs, gp, "fo:padding-top", false), 3.6);
            cell.text.inset_bottom = Odf.length (prop (refs, gp, "fo:padding-bottom", false), 3.6);
            read_paragraphs (cn, cell.text, c, false, 0, null, false);
            if (cell.text.paragraphs.size == 0) cell.text.paragraphs.add (new Paragraph ());
            if (private_data) {
                string? v = a (cn, "sgs:fill");
                if (v != null) cell.fill = Odf.dec (v);
                v = a (cn, "sgs:anchor");
                if (v != null) cell.anchor = (TextAnchor) Odf.to_int (v).clamp (0, 2);
                v = a (cn, "sgs:body");
                if (v != null) Odf.apply_body_code (cell.text, v);
            }
        }

        private static void cell_ref (string r, out int col, out int row) {
            col = 0;
            row = 0;
            string s = r;
            int dot = s.last_index_of (".");
            if (dot >= 0) s = s.substring (dot + 1);
            s = s.replace ("$", "");
            int i = 0;
            int c = 0;
            while (i < s.length && s[i].isalpha ()) {
                c = c * 26 + (s[i].toupper () - 'A' + 1);
                i++;
            }
            col = c - 1;
            row = Odf.to_int (s.substring (i), 1) - 1;
        }

        private static void range_ref (string r, out int c1, out int r1, out int c2, out int r2) {
            string[] parts = r.split (":");
            cell_ref (parts[0], out c1, out r1);
            if (parts.length > 1) cell_ref (parts[1], out c2, out r2);
            else {
                c2 = c1;
                r2 = r1;
            }
        }

        private MediaElement? read_media (Xml.Node* frame, Xml.Node* plugin, Xml.Node* img, Ctx c) {
            string href = a (plugin, "xlink:href") ?? "";
            var m = new MediaElement ();
            base_attrs (frame, m, c);
            geometry (frame, m);
            string path = href.has_prefix ("./") ? href.substring (2) : href;
            bool internal_part = !path.contains ("://") && !path.has_prefix ("/");
            if (internal_part) {
                try {
                    var data = zip.read (path);
                    if (data != null) m.data = new Bytes (data);
                } catch (Error e) {
                    m.data = null;
                }
            }
            if (m.data == null) m.link = href;
            m.mime = MediaElement.mime_for (path);
            m.is_video = m.mime.has_prefix ("video/");
            foreach (var p in kids (plugin, "draw:param")) {
                string name = a (p, "draw:name") ?? "";
                string val = a (p, "draw:value") ?? "";
                if (name == "Loop") m.loop = val == "true";
                else if (name == "Mute") m.muted = val == "true";
                else if (name == "VolumeDB") m.volume = Math.pow (10, Odf.to_double (val, 0) / 20).clamp (0, 1);
            }
            if (img != null) {
                var pd = image_bytes (a (img, "xlink:href"));
                if (pd != null) {
                    m.poster = pd;
                    m.poster_mime = Odf.sniff_mime (pd, a (img, "xlink:href") ?? "");
                }
            }
            m.start = MediaStart.ON_CLICK;
            if (private_data && a (frame, "sgs:media") != null) Odf.apply_media_code (m, a (frame, "sgs:media"));
            apply_private (frame, m);
            if (m.data == null && m.link == "") return null;
            return m;
        }

        private Model3DElement read_model (Xml.Node* frame, Xml.Node* img, Ctx c) {
            var m = new Model3DElement ();
            base_attrs (frame, m, c);
            geometry (frame, m);
            string[] p = Odf.fields (a (frame, "sgs:model3d"), 6);
            string href = Odf.dec (p[0]);
            m.format = p[1] == "obj" ? "obj" : "glb";
            m.rot_x = Odf.to_double (p[2]);
            m.rot_y = Odf.to_double (p[3]);
            m.rot_z = Odf.to_double (p[4]);
            m.zoom = Odf.to_double (p[5], 1);
            if (href != "") {
                try {
                    uint8[]? d = zip.read (href);
                    if (d != null) m.data = new Bytes (d);
                } catch (Error e) {
                    warning ("3d model: %s", e.message);
                }
            }
            if (img != null) m.preview = image_bytes (a (img, "xlink:href"));
            apply_private (frame, m);
            return m;
        }

        private ZoomElement read_zoom (Xml.Node* frame, Xml.Node* img, Ctx c) {
            var z = new ZoomElement ();
            base_attrs (frame, z, c);
            geometry (frame, z);
            string[] p = Odf.fields (a (frame, "sgs:zoom"), 7);
            z.zoom = (ZoomKind) Odf.to_int (p[0]).clamp (0, 2);
            z.target_uid = Odf.to_int (p[1]);
            z.section_id = Odf.dec (p[2]);
            z.return_to_zoom = p[3] == "1";
            z.zoom_transition = p[4] != "0";
            z.transition_duration = Odf.to_double (p[5], 1);
            if (p[6] == "1") {
                z.image = image_bytes (a (img, "xlink:href"));
                if (z.image != null) z.image_mime = Odf.sniff_mime (z.image, a (img, "xlink:href") ?? "");
            }
            apply_private (frame, z);
            return z;
        }

        private EquationElement? read_formula_object (Xml.Node* frame, Xml.Node* obj, Xml.Node* img, Ctx c) {
            string href = a (obj, "xlink:href") ?? "";
            if (href.has_prefix ("./")) href = href.substring (2);
            if (href.has_suffix ("/")) href = href.substring (0, href.length - 1);
            string? text = null;
            try {
                text = zip.read_text (href + "/content.xml");
            } catch (Error e) {
                text = null;
            }
            if (text == null || !text.contains ("math")) return null;
            int st = text.index_of ("<math");
            if (st < 0) {
                int alt = text.index_of (":math");
                if (alt < 0) return null;
                st = text.last_index_of ("<", alt);
            }
            var q = new EquationElement ();
            base_attrs (frame, q, c);
            geometry (frame, q);
            q.mathml = text.substring (st);
            var eq = new Singularity.Equations.Equation.from_mathml (q.mathml);
            q.mathml = eq.mathml;
            if (img != null) {
                q.image = image_bytes (a (img, "xlink:href"));
                if (q.image != null) q.image_mime = Odf.sniff_mime (q.image, a (img, "xlink:href") ?? "");
            }
            if (private_data && a (frame, "sgs:equation") != null) {
                string[] p = Odf.fields (a (frame, "sgs:equation"), 2);
                q.latex = Odf.dec (p[0]);
                q.color = Odf.dec (p[1]);
            }
            apply_private (frame, q);
            return q;
        }

        private ChartElement? read_chart_object (Xml.Node* frame, Xml.Node* obj, Ctx c) {
            string href = a (obj, "xlink:href") ?? "";
            if (href.has_prefix ("./")) href = href.substring (2);
            if (href.has_suffix ("/")) href = href.substring (0, href.length - 1);
            Xml.Doc* doc;
            try {
                doc = load (href + "/content.xml", false);
            } catch (Error e) {
                return null;
            }
            if (doc == null) return null;
            Xml.Node* root = doc->get_root_element ();
            var auto = new Gee.HashMap<string, Xml.Node*> ();
            foreach (var st in kids (kid (root, "office:automatic-styles"), "style:style")) {
                string? nm = a (st, "style:name");
                if (nm != null) auto[nm] = st;
            }
            Xml.Node* chart = kid (kid (kid (root, "office:body"), "office:chart"), "chart:chart");
            if (chart == null) return null;
            string cls = a (chart, "chart:class") ?? "chart:bar";
            if (cls.contains (":")) cls = cls.substring (cls.index_of (":") + 1);
            Xml.Node* plot = kid (chart, "chart:plot-area");
            string? ps = plot != null ? a (plot, "chart:style-name") : null;
            Xml.Node* pprops = ps != null && auto.has_key (ps) ? kid (auto[ps], "style:chart-properties") : null;
            ChartKind kind;
            switch (cls) {
                case "line": kind = ChartKind.LINE; break;
                case "circle": kind = ChartKind.PIE; break;
                case "ring": kind = ChartKind.DOUGHNUT; break;
                case "area": kind = ChartKind.AREA; break;
                case "scatter": kind = ChartKind.SCATTER; break;
                case "radar": case "filled-radar": kind = ChartKind.RADAR; break;
                case "bubble": kind = ChartKind.BUBBLE; break;
                default: kind = a (pprops, "chart:vertical") == "true" ? ChartKind.BAR : ChartKind.COLUMN; break;
            }
            var ch = new ChartElement (kind);
            base_attrs (frame, ch, c);
            geometry (frame, ch);
            if (cls == "filled-radar") ch.grouping = ChartGrouping.STACKED;
            if (a (pprops, "chart:percentage") == "true") ch.grouping = ChartGrouping.PERCENT;
            else if (a (pprops, "chart:stacked") == "true") ch.grouping = ChartGrouping.STACKED;
            ch.smooth = (a (pprops, "chart:interpolation") ?? "none") != "none";
            string dl = a (pprops, "chart:data-label-number") ?? "none";
            ch.data_labels = dl != "none" || a (pprops, "chart:data-label-text") == "true";
            Xml.Node* title = kid (chart, "chart:title");
            ch.title = title != null ? XmlIn.text (kid (title, "text:p")).strip () : "";
            Xml.Node* legend = kid (chart, "chart:legend");
            if (legend == null) ch.legend = LegendPosition.NONE;
            else {
                string lp = a (legend, "chart:legend-position") ?? "end";
                if (lp.has_prefix ("bottom")) ch.legend = LegendPosition.BOTTOM;
                else if (lp.has_prefix ("top")) ch.legend = LegendPosition.TOP;
                else if (lp.has_prefix ("start")) ch.legend = LegendPosition.LEFT;
                else ch.legend = LegendPosition.RIGHT;
            }
            ch.gridlines = false;
            Xml.Node* cats_node = null;
            foreach (var ax in kids (plot, "chart:axis")) {
                string dim = a (ax, "chart:dimension") ?? "";
                string an = a (ax, "chart:name") ?? "";
                if (dim == "x") cats_node = kid (ax, "chart:categories");
                if (dim == "y" && an != "secondary-y" && kid (ax, "chart:grid") != null) ch.gridlines = true;
                ChartAxis? target = dim == "x" && an != "secondary-x" ? ch.cat_axis : (dim == "y" ? (an == "secondary-y" ? ch.sec_axis : ch.val_axis) : null);
                if (target == null) continue;
                Xml.Node* at = kid (ax, "chart:title");
                if (at != null) target.title = XmlIn.text (kid (at, "text:p")).strip ();
                string? asn = a (ax, "chart:style-name");
                Xml.Node* ap = asn != null && auto.has_key (asn) ? kid (auto[asn], "style:chart-properties") : null;
                if (ap != null) {
                    string? mn = a (ap, "chart:minimum");
                    string? mx = a (ap, "chart:maximum");
                    string? iv = a (ap, "chart:interval-major");
                    if (mn != null) target.min = Odf.to_double (mn);
                    if (mx != null) target.max = Odf.to_double (mx);
                    if (iv != null) target.major = Odf.to_double (iv);
                    if (a (ap, "chart:logarithmic") == "true") target.log_base = 10;
                    target.reverse = a (ap, "chart:reverse-direction") == "true";
                    target.visible = a (ap, "chart:display-label") != "false";
                }
            }
            var grid = new Gee.ArrayList<Gee.ArrayList<string>> ();
            var nums = new Gee.ArrayList<Gee.ArrayList<double?>> ();
            Xml.Node* table = null;
            foreach (var k in kids (kid (kid (root, "office:body"), "office:chart"), "table:table")) table = k;
            if (table == null) table = kid (chart, "table:table");
            if (table != null) {
                var widths = new Gee.ArrayList<double?> ();
                var rows = new Gee.ArrayList<Xml.Node*> ();
                collect_table (table, widths, rows, c);
                foreach (var r in rows) {
                    var srow = new Gee.ArrayList<string> ();
                    var nrow = new Gee.ArrayList<double?> ();
                    foreach (var cell in kids (r)) {
                        if (!is (cell, "table:table-cell") && !is (cell, "table:covered-table-cell")) continue;
                        int rep = int.max (1, Odf.to_int (a (cell, "table:number-columns-repeated") ?? "1", 1));
                        string? val = a (cell, "office:value");
                        string text = XmlIn.text (kid (cell, "text:p"));
                        for (int k = 0; k < rep && srow.size < 256; k++) {
                            srow.add (text);
                            double d = 0;
                            if (val != null && double.try_parse (val, out d)) nrow.add (d);
                            else if (double.try_parse (text.strip (), out d)) nrow.add (d);
                            else nrow.add (null);
                        }
                    }
                    grid.add (srow);
                    nums.add (nrow);
                }
            }
            int ncat_rows = 0;
            if (cats_node != null && a (cats_node, "table:cell-range-address") != null) {
                int c1, r1, c2, r2;
                range_ref (a (cats_node, "table:cell-range-address"), out c1, out r1, out c2, out r2);
                for (int r = r1; r <= r2 && r < grid.size; r++) ch.categories.add (c1 < grid[r].size ? grid[r][c1] : "");
                ncat_rows = r2 - r1 + 1;
            } else if (grid.size > 1) {
                for (int r = 1; r < grid.size; r++) ch.categories.add (grid[r].size > 0 ? grid[r][0] : "");
                ncat_rows = grid.size - 1;
            }
            int idx = 0;
            foreach (var sn in kids (plot, "chart:series")) {
                var s = new ChartSeries (_("Series %d").printf (idx + 1));
                string? lab = a (sn, "chart:label-cell-address");
                if (lab != null) {
                    int lc, lr;
                    cell_ref (lab, out lc, out lr);
                    if (lr < grid.size && lc < grid[lr].size) s.name = grid[lr][lc];
                }
                string? vr = a (sn, "chart:values-cell-range-address");
                if (kind == ChartKind.BUBBLE) {
                    if (vr != null) read_range (vr, nums, s.sizes);
                    var domains = kids (sn, "chart:domain");
                    if (domains.size > 0) {
                        string? yr = a (domains[0], "table:cell-range-address");
                        if (yr != null) read_range (yr, nums, s.values);
                    }
                    vr = null;
                } else if (vr != null) {
                    int c1, r1, c2, r2;
                    range_ref (vr, out c1, out r1, out c2, out r2);
                    if (c1 == c2) {
                        for (int r = r1; r <= r2 && r < nums.size; r++) s.values.add (c1 < nums[r].size ? nums[r][c1] : null);
                    } else {
                        for (int cc = c1; cc <= c2 && r1 < nums.size; cc++) s.values.add (cc < nums[r1].size ? nums[r1][cc] : null);
                    }
                } else if (grid.size > 1) {
                    for (int r = 1; r < nums.size; r++) s.values.add (idx + 1 < nums[r].size ? nums[r][idx + 1] : null);
                }
                string scls = a (sn, "chart:class") ?? "";
                if (scls.contains (":")) scls = scls.substring (scls.index_of (":") + 1);
                if (kind != ChartKind.RADAR && kind != ChartKind.BUBBLE && kind != ChartKind.SCATTER && !kind.is_radial () && scls != "" && scls != cls) {
                    if (scls == "line") s.kind = SeriesKind.LINE;
                    else if (scls == "area") s.kind = SeriesKind.AREA;
                    else if (scls == "bar") s.kind = SeriesKind.COLUMN;
                }
                s.secondary = a (sn, "chart:attached-axis") == "secondary-y";
                Xml.Node* rc = kid (sn, "chart:regression-curve");
                if (rc != null) {
                    string? rsn = a (rc, "chart:style-name");
                    Xml.Node* rp = rsn != null && auto.has_key (rsn) ? kid (auto[rsn], "style:chart-properties") : null;
                    s.trend = TrendKind.from_odf (a (rp, "chart:regression-type") ?? "linear");
                    if (s.trend == TrendKind.NONE) s.trend = TrendKind.LINEAR;
                    s.trend_order = Odf.to_int (a (rp, "chart:regression-max-degree") ?? a (rp, "loext:regression-max-degree") ?? "2", 2);
                    s.trend_period = Odf.to_int (a (rp, "chart:regression-period") ?? a (rp, "loext:regression-period") ?? "2", 2);
                    Xml.Node* eq = kid (rc, "chart:equation");
                    if (eq != null) {
                        s.trend_equation = a (eq, "chart:display-equation") == "true";
                        s.trend_r2 = a (eq, "chart:display-r-square") == "true";
                    }
                }
                string? ss = a (sn, "chart:style-name");
                if (ss != null && auto.has_key (ss) && !kind.is_radial ()) {
                    Xml.Node* gp = kid (auto[ss], "style:graphic-properties");
                    string? col = kind == ChartKind.LINE ? (a (gp, "svg:stroke-color") ?? a (gp, "draw:fill-color")) : a (gp, "draw:fill-color");
                    if (col != null) s.color = col.down ();
                }
                ch.series.add (s);
                idx++;
            }
            if (ncat_rows > 0) while (ch.categories.size < ncat_rows) ch.categories.add ("");
            apply_private (frame, ch);
            if (private_data) {
                string? v = a (chart, "sgs:chart");
                if (v != null) {
                    string[] p = Odf.fields (v, 9);
                    ch.chart = (ChartKind) Odf.to_int (p[0]).clamp (0, (int) ChartKind.SUNBURST);
                    ch.grouping = (ChartGrouping) Odf.to_int (p[1]).clamp (0, 2);
                    ch.title = Odf.dec (p[2]);
                    ch.legend = (LegendPosition) Odf.to_int (p[3]).clamp (0, 4);
                    ch.data_labels = p[4] == "1";
                    ch.gridlines = p[5] == "1";
                    ch.smooth = p[6] == "1";
                    ch.text_color = Odf.dec (p[7]);
                    string[] cols = p[8].split (",");
                    for (int i = 0; i < ch.series.size; i++) ch.series[i].color = i < cols.length ? Odf.dec (cols[i]) : "";
                }
                string? vx = a (chart, "sgs:chartx");
                if (vx != null) Odf.apply_chart_extra (ch, vx);
            }
            return ch;
        }

        private void read_range (string range, Gee.List<Gee.ArrayList<double?>> nums, Gee.List<double?> into) {
            int c1, r1, c2, r2;
            range_ref (range, out c1, out r1, out c2, out r2);
            for (int r = r1; r <= r2 && r < nums.size; r++) into.add (c1 < nums[r].size ? nums[r][c1] : null);
        }

        private void read_paragraphs (Xml.Node* container, TextBody body, Ctx c, bool outline, int depth, Xml.Node* list_style, bool in_list) {
            foreach (var n in kids (container)) {
                if (is (n, "text:p") || is (n, "text:h")) {
                    var p = read_paragraph (n, c);
                    if (!private_data || a (n, "sgs:para") == null) {
                        p.level = depth.clamp (0, 8);
                        if (in_list) apply_list_level (p, list_style, depth);
                        else p.bullet = outline ? BulletKind.NONE : BulletKind.INHERIT;
                    }
                    body.paragraphs.add (p);
                } else if (is (n, "text:list")) {
                    Xml.Node* ls = list_style;
                    string? sn = a (n, "text:style-name");
                    if (sn != null) ls = lookup (c.scope, "list", sn);
                    foreach (var item in kids (n)) {
                        if (is (item, "text:list-item")) read_paragraphs (item, body, c, outline, in_list ? depth + 1 : depth, ls, true);
                        else if (is (item, "text:list-header")) {
                            int before = body.paragraphs.size;
                            read_paragraphs (item, body, c, outline, in_list ? depth + 1 : depth, ls, false);
                            for (int i = before; i < body.paragraphs.size; i++) {
                                if (!private_data) body.paragraphs[i].bullet = BulletKind.NONE;
                            }
                        }
                    }
                } else if (is (n, "text:list-item")) {
                    read_paragraphs (n, body, c, outline, depth, list_style, true);
                }
            }
        }

        private void apply_list_level (Paragraph p, Xml.Node* list_style, int depth) {
            p.bullet = BulletKind.INHERIT;
            if (list_style == null) return;
            foreach (var lv in kids (list_style)) {
                if (Odf.to_int (a (lv, "text:level") ?? "1", 1) != depth + 1) continue;
                if (is (lv, "text:list-level-style-bullet")) {
                    p.bullet = BulletKind.CHAR;
                    p.bullet_char = a (lv, "text:bullet-char") ?? "•";
                    Xml.Node* tp = kid (lv, "style:text-properties");
                    string? col = a (tp, "fo:color");
                    if (col != null) p.bullet_color = col.down ();
                } else if (is (lv, "text:list-level-style-number")) {
                    p.bullet = BulletKind.NUMBER;
                    string fmt = a (lv, "style:num-format") ?? "1";
                    string suffix = a (lv, "style:num-suffix") ?? ".";
                    switch (fmt) {
                        case "a": p.number_style = NumberStyle.ALPHA_LOWER; break;
                        case "A": p.number_style = NumberStyle.ALPHA_UPPER; break;
                        case "i": p.number_style = NumberStyle.ROMAN_LOWER; break;
                        case "I": p.number_style = NumberStyle.ROMAN_UPPER; break;
                        default: p.number_style = suffix == ")" ? NumberStyle.ARABIC_PAREN : NumberStyle.ARABIC_PERIOD; break;
                    }
                    p.number_start = Odf.to_int (a (lv, "text:start-value") ?? "1", 1);
                } else if (is (lv, "text:list-level-style-image")) {
                    p.bullet = BulletKind.CHAR;
                    p.bullet_char = "•";
                }
                return;
            }
        }

        private Paragraph read_paragraph (Xml.Node* n, Ctx c) {
            var p = new Paragraph ();
            string? ps = a (n, "text:style-name");
            if (ps != null) {
                var refs = new Gee.ArrayList<Ref> ();
                refs.add (new Ref (c.scope, "paragraph", ps));
                string pp = "style:paragraph-properties";
                string? al = prop (refs, pp, "fo:text-align", false);
                if (al != null) {
                    switch (al) {
                        case "center": p.align = TextAlign.CENTER; break;
                        case "end": case "right": p.align = TextAlign.RIGHT; break;
                        case "justify": p.align = TextAlign.JUSTIFY; break;
                        default: p.align = TextAlign.LEFT; break;
                    }
                }
                string? mt = prop (refs, pp, "fo:margin-top", false);
                if (mt != null) p.space_before = Odf.length (mt, 0);
                string? mb = prop (refs, pp, "fo:margin-bottom", false);
                if (mb != null) p.space_after = Odf.length (mb, 0);
                string? lh = prop (refs, pp, "fo:line-height", false);
                if (lh != null && lh.has_suffix ("%")) p.line_spacing = Odf.percent (lh, 0);
            }
            var fmt = new TextRun ();
            read_inline (n, p, fmt, c, "");
            if (private_data) {
                string? v = a (n, "sgs:para");
                if (v != null) Odf.apply_para_code (p, v);
                v = a (n, "sgs:end");
                if (v != null) Odf.apply_run_code (p.end_format, v);
            }
            if (!private_data) p.normalize ();
            return p;
        }

        private void append_text (Paragraph p, TextRun fmt, string text) {
            if (text == "") return;
            if (p.runs.size > 0) {
                var last = p.runs[p.runs.size - 1];
                if (last.field == "" && fmt.field == "" && last.same_format (fmt)) {
                    last.text += text;
                    return;
                }
            }
            var r = new TextRun (text);
            r.copy_format (fmt);
            p.runs.add (r);
        }

        private void span_format (Xml.Node* n, TextRun fmt, Ctx c) {
            string? ts = a (n, "text:style-name");
            if (ts == null) return;
            var refs = new Gee.ArrayList<Ref> ();
            refs.add (new Ref (c.scope, "text", ts));
            string tp = "style:text-properties";
            string? v = prop (refs, tp, "fo:font-size", false);
            if (v != null && !v.has_suffix ("%")) fmt.size = Odf.length (v, 0);
            v = prop (refs, tp, "style:font-name", false) ?? prop (refs, tp, "fo:font-family", false);
            if (v != null) fmt.font = v.replace ("'", "");
            v = prop (refs, tp, "fo:font-weight", false);
            if (v != null) fmt.bold = v == "bold" || Odf.to_int (v, 400) >= 600 ? 1 : 0;
            v = prop (refs, tp, "fo:font-style", false);
            if (v != null) fmt.italic = v == "italic" || v == "oblique" ? 1 : 0;
            v = prop (refs, tp, "fo:color", false);
            if (v != null) fmt.color = v.down ();
            v = prop (refs, tp, "style:text-underline-style", false);
            if (v != null) fmt.underline = v != "none" ? 1 : 0;
            v = prop (refs, tp, "style:text-line-through-style", false);
            if (v != null) fmt.strike = v != "none" ? 1 : 0;
            v = prop (refs, tp, "style:text-position", false);
            if (v != null) {
                if (v.has_prefix ("super") || (Odf.to_double (v.split (" ")[0].replace ("%", ""), 0) > 0 && !v.has_prefix ("sub"))) fmt.baseline = 1;
                else if (v.has_prefix ("sub") || v.has_prefix ("-")) fmt.baseline = -1;
            }
            v = prop (refs, tp, "fo:background-color", false);
            if (v != null && v != "transparent") fmt.highlight = v.down ();
        }

        private void read_inline (Xml.Node* n, Paragraph p, TextRun fmt, Ctx c, string link) {
            for (Xml.Node* ch = n->children; ch != null; ch = ch->next) {
                if (ch->type == Xml.ElementType.TEXT_NODE || ch->type == Xml.ElementType.CDATA_SECTION_NODE) {
                    string t = ch->content ?? "";
                    var sb = new StringBuilder ();
                    bool space = false;
                    unichar u;
                    int i = 0;
                    while (t.get_next_char (ref i, out u)) {
                        if (u == ' ' || u == '\n' || u == '\t' || u == '\r') {
                            if (!space) sb.append_c (' ');
                            space = true;
                        } else {
                            sb.append_unichar (u);
                            space = false;
                        }
                    }
                    append_text (p, fmt, sb.str);
                    continue;
                }
                if (ch->type != Xml.ElementType.ELEMENT_NODE) continue;
                if (is (ch, "text:span")) {
                    var f = new TextRun ();
                    f.copy_format (fmt);
                    span_format (ch, f, c);
                    if (link != "") f.link = link;
                    string? code = private_data ? a (ch, "sgs:run") : null;
                    if (code != null) Odf.apply_run_code (f, code);
                    if (code != null && f.field != "") {
                        var r = new TextRun (XmlIn.text (ch));
                        r.copy_format (f);
                        if (r.field == "slidenum" && r.text == "<number>") r.text = "";
                        p.runs.add (r);
                        continue;
                    }
                    if (code != null) {
                        var sub = new Paragraph ();
                        read_inline (ch, sub, f, c, link);
                        var merged = new TextRun ("");
                        merged.copy_format (f);
                        foreach (var r in sub.runs) merged.text += r.text;
                        p.runs.add (merged);
                        continue;
                    }
                    read_inline (ch, p, f, c, link);
                } else if (is (ch, "text:a")) {
                    string href = a (ch, "xlink:href") ?? "";
                    var f = new TextRun ();
                    f.copy_format (fmt);
                    f.link = href;
                    read_inline (ch, p, f, c, href);
                } else if (is (ch, "text:s")) {
                    int count = int.max (1, Odf.to_int (a (ch, "text:c") ?? "1", 1));
                    append_text (p, fmt, string.nfill (count, ' '));
                } else if (is (ch, "text:tab")) {
                    append_text (p, fmt, "\t");
                } else if (is (ch, "text:line-break")) {
                    append_text (p, fmt, "\n");
                } else if (is (ch, "text:page-number")) {
                    var r = new TextRun (XmlIn.text (ch));
                    r.copy_format (fmt);
                    r.field = "slidenum";
                    if (r.text == "<number>") r.text = "";
                    p.runs.add (r);
                } else if (is (ch, "text:date") || is (ch, "text:time") || is (ch, "presentation:date-time")) {
                    var r = new TextRun (XmlIn.text (ch));
                    r.copy_format (fmt);
                    r.field = "datetime";
                    p.runs.add (r);
                } else if (is (ch, "presentation:footer")) {
                    append_text (p, fmt, pres.footer_text);
                } else if (is (ch, "text:note") || is (ch, "office:annotation")) {
                    continue;
                } else {
                    read_inline (ch, p, fmt, c, link);
                }
            }
        }

        private Fill? page_fill (int scope, string? style) {
            if (style == null) return null;
            var refs = new Gee.ArrayList<Ref> ();
            refs.add (new Ref (scope, "drawing-page", style));
            if (prop (refs, "style:drawing-page-properties", "draw:fill", false) == null) return null;
            var f = read_fill (refs, "style:drawing-page-properties", false);
            return f;
        }

        private LevelStyle level_from (int scope, string family, string name) {
            var l = new LevelStyle ();
            var refs = new Gee.ArrayList<Ref> ();
            refs.add (new Ref (scope, family, name));
            string tp = "style:text-properties", pp = "style:paragraph-properties";
            string? v = prop (refs, tp, "fo:font-size", false);
            if (v != null && !v.has_suffix ("%")) l.size = Odf.length (v, 0);
            v = prop (refs, tp, "style:font-name", false) ?? prop (refs, tp, "fo:font-family", false);
            if (v != null) l.font = v.replace ("'", "");
            v = prop (refs, tp, "fo:color", false);
            if (v != null) l.color = v.down ();
            v = prop (refs, tp, "fo:font-weight", false);
            if (v != null) l.bold = v == "bold" ? 1 : 0;
            v = prop (refs, tp, "fo:font-style", false);
            if (v != null) l.italic = v == "italic" ? 1 : 0;
            v = prop (refs, pp, "fo:text-align", false);
            if (v != null) l.align = v == "center" ? TextAlign.CENTER : (v == "end" || v == "right" ? TextAlign.RIGHT : (v == "justify" ? TextAlign.JUSTIFY : TextAlign.LEFT));
            v = prop (refs, pp, "fo:margin-top", false);
            if (v != null) l.space_before = Odf.length (v, 0);
            v = prop (refs, pp, "fo:margin-bottom", false);
            if (v != null) l.space_after = Odf.length (v, 0);
            v = prop (refs, pp, "fo:line-height", false);
            if (v != null && v.has_suffix ("%")) l.line_spacing = Odf.percent (v, 0);
            v = prop (refs, pp, "fo:margin-left", false);
            if (v != null) {
                l.margin = Odf.length (v, 0);
                l.indent = Odf.length (prop (refs, pp, "fo:text-indent", false), 0);
            }
            return l;
        }

        private void read_master_styles (Master m, string mp) {
            if (lookup (STYLES, "presentation", mp + "-title") != null) {
                var t = level_from (STYLES, "presentation", mp + "-title");
                t.bullet = BulletKind.NONE;
                m.title_style.levels[0] = t;
                if (t.font != "") m.theme.major_font = t.font;
            }
            Xml.Node* list = null;
            Xml.Node* o1 = lookup (STYLES, "presentation", mp + "-outline1");
            if (o1 != null) list = kid (kid (o1, "style:graphic-properties"), "text:list-style");
            for (int i = 0; i < 9; i++) {
                string name = "%s-outline%d".printf (mp, i + 1);
                if (lookup (STYLES, "presentation", name) == null) continue;
                var l = level_from (STYLES, "presentation", name);
                l.bullet = BulletKind.CHAR;
                l.bullet_char = "•";
                if (list != null) {
                    var p = new Paragraph ();
                    apply_list_level (p, list, i);
                    if (p.bullet != BulletKind.INHERIT) {
                        l.bullet = p.bullet;
                        l.bullet_char = p.bullet_char;
                    }
                }
                m.body_style.levels[i] = l;
                if (i == 0 && l.font != "") m.theme.minor_font = l.font;
            }
        }

        private void read_masters (Xml.Node* master_styles) {
            var pages = kids (master_styles, "style:master-page");
            var masters_by_id = new Gee.HashMap<string, Master> ();
            foreach (var mp in pages) {
                if (private_data && a (mp, "sgs:role") == "master") {
                    var m = new Master ();
                    m.id = a (mp, "sgs:id") ?? "master%d".printf (pres.masters.size + 1);
                    m.name = a (mp, "sgs:name") ?? (a (mp, "style:display-name") ?? "");
                    m.theme = Odf.parse_theme (a (mp, "sgs:theme") ?? "");
                    string? bg = a (mp, "sgs:bg");
                    var std_bg = page_fill (STYLES, a (mp, "draw:style-name"));
                    m.background = bg != null ? Odf.parse_fill (bg, std_bg != null ? std_bg.image : null, std_bg != null ? std_bg.image_mime : "") : (std_bg ?? new Fill.solid ("#ffffff"));
                    m.title_style = Odf.parse_style (a (mp, "sgs:title-style") ?? "");
                    m.body_style = Odf.parse_style (a (mp, "sgs:body-style") ?? "");
                    m.other_style = Odf.parse_style (a (mp, "sgs:other-style") ?? "");
                    var c = new Ctx ();
                    c.scope = STYLES;
                    c.on_master = true;
                    m.elements.add_all (read_elements (mp, c));
                    pres.masters.add (m);
                    masters_by_id[m.id] = m;
                }
            }
            foreach (var mp in pages) {
                string name = a (mp, "style:name") ?? "";
                if (private_data && a (mp, "sgs:role") == "master") continue;
                if (private_data && a (mp, "sgs:role") == "layout") {
                    var m = masters_by_id[a (mp, "sgs:master") ?? ""];
                    if (m == null) continue;
                    var l = new Layout ();
                    l.id = a (mp, "sgs:layout-id") ?? "layout%d".printf (m.layouts.size + 1);
                    l.name = a (mp, "sgs:name") ?? (a (mp, "style:display-name") ?? name);
                    l.kind = (LayoutKind) Odf.to_int (a (mp, "sgs:layout-kind") ?? "11").clamp (0, 11);
                    l.show_master_shapes = a (mp, "sgs:show-master") != "0";
                    string bg = a (mp, "sgs:bg") ?? "inherit";
                    if (bg != "inherit") {
                        var std_bg = page_fill (STYLES, a (mp, "draw:style-name"));
                        l.background = Odf.parse_fill (bg, std_bg != null ? std_bg.image : null, std_bg != null ? std_bg.image_mime : "");
                    }
                    var c = new Ctx ();
                    c.scope = STYLES;
                    c.on_master = true;
                    c.layout_page = true;
                    l.elements.add_all (read_elements (mp, c));
                    m.layouts.add (l);
                    page_layouts[name] = l;
                    continue;
                }
                var m = new Master ();
                m.id = "master%d".printf (pres.masters.size + 1);
                m.name = a (mp, "style:display-name") ?? name;
                m.theme = new Theme ();
                m.theme.id = "odp";
                m.theme.name = m.name;
                m.background = page_fill (STYLES, a (mp, "draw:style-name")) ?? new Fill.solid ("#ffffff");
                var c = new Ctx ();
                c.scope = STYLES;
                c.on_master = true;
                m.elements.add_all (read_elements (mp, c));
                read_master_styles (m, name);
                for (int i = 0; i < 9; i++) {
                    var o = m.other_style.levels[i];
                    o.size = 18;
                    o.color = m.body_style.levels[0].color;
                    o.margin = 0;
                    o.indent = 0;
                }
                var l = new Layout ();
                l.id = "layout%d".printf (page_layouts.size + 1);
                l.name = m.name;
                l.kind = LayoutKind.TITLE_CONTENT;
                foreach (var e in m.elements) {
                    if (e.placeholder == PlaceholderKind.NONE) continue;
                    var clone = e.clone ();
                    clone.inherit_geometry = true;
                    if (clone.placeholder == PlaceholderKind.BODY) clone.placeholder = PlaceholderKind.OBJECT;
                    var sh = clone as ShapeElement;
                    if (sh != null && !clone.placeholder.is_meta ()) {
                        sh.text = new TextBody ();
                        sh.text.paragraphs.add (new Paragraph ());
                        if (e.text_body () != null) {
                            sh.text.anchor = e.text_body ().anchor;
                            sh.text.anchor_set = e.text_body ().anchor_set;
                        }
                    }
                    l.elements.add (clone);
                }
                m.layouts.add (l);
                page_layouts[name] = l;
                pres.masters.add (m);
            }
            foreach (var m in pres.masters) {
                foreach (var l in m.layouts) {
                    foreach (var e in l.elements) if (e.placeholder_idx < 0 && !e.placeholder.is_title ()) e.placeholder_idx = -1;
                }
            }
        }

        private void read_transition (Xml.Node* page, Slide s) {
            var refs = new Gee.ArrayList<Ref> ();
            string? st = a (page, "draw:style-name");
            if (st == null) return;
            refs.add (new Ref (CONTENT, "drawing-page", st));
            string dp = "style:drawing-page-properties";
            var t = s.transition;
            string? type = prop (refs, dp, "smil:type", false);
            string? sub = prop (refs, dp, "smil:subtype", false);
            bool reverse = prop (refs, dp, "smil:direction", false) == "reverse";
            if (type != null) {
                t.direction = Odf.direction_of_subtype (sub, Direction.FROM_RIGHT);
                switch (type) {
                    case "fade":
                        t.kind = sub == "fadeOverColor" || sub == "fadeFromColor" || sub == "fadeToColor" ? TransitionKind.FADE_BLACK : TransitionKind.FADE;
                        break;
                    case "pushWipe":
                        t.kind = TransitionKind.PUSH;
                        break;
                    case "barWipe":
                        t.kind = TransitionKind.WIPE;
                        bool vertical = sub == "topToBottom";
                        t.direction = vertical ? (reverse ? Direction.FROM_BOTTOM : Direction.FROM_TOP) : (reverse ? Direction.FROM_RIGHT : Direction.FROM_LEFT);
                        break;
                    case "slideWipe":
                        t.kind = reverse ? TransitionKind.UNCOVER : TransitionKind.COVER;
                        break;
                    case "barnDoorWipe":
                        t.kind = TransitionKind.SPLIT;
                        break;
                    case "irisWipe":
                    case "zoom":
                        t.kind = TransitionKind.ZOOM;
                        break;
                    case "dissolve":
                    case "randomBarWipe":
                        t.kind = TransitionKind.DISSOLVE;
                        break;
                    case "ellipseWipe":
                        t.kind = TransitionKind.CIRCLE;
                        break;
                    default:
                        t.kind = TransitionKind.FADE;
                        break;
                }
            } else {
                string? style = prop (refs, dp, "presentation:transition-style", false);
                if (style != null && style != "none") {
                    if (style.has_prefix ("fade")) t.kind = TransitionKind.FADE;
                    else if (style.has_prefix ("move") || style.has_prefix ("roll")) t.kind = TransitionKind.COVER;
                    else if (style.has_prefix ("uncover")) t.kind = TransitionKind.UNCOVER;
                    else if (style.contains ("stripes") || style.contains ("wipe")) t.kind = TransitionKind.WIPE;
                    else if (style.contains ("dissolve")) t.kind = TransitionKind.DISSOLVE;
                    else if (style.contains ("close") || style.contains ("open")) t.kind = TransitionKind.SPLIT;
                    else t.kind = TransitionKind.FADE;
                    if (style.has_suffix ("from-left")) t.direction = Direction.FROM_LEFT;
                    else if (style.has_suffix ("from-top")) t.direction = Direction.FROM_TOP;
                    else if (style.has_suffix ("from-bottom")) t.direction = Direction.FROM_BOTTOM;
                }
            }
            string? dur = prop (refs, dp, "smil:dur", false);
            if (dur != null) t.duration = Odf.seconds (dur, 0.7);
            else {
                string speed = prop (refs, dp, "presentation:transition-speed", false) ?? "medium";
                t.duration = speed == "fast" ? 0.5 : (speed == "slow" ? 1.0 : 0.7);
            }
            string tt = prop (refs, dp, "presentation:transition-type", false) ?? "manual";
            if (tt == "automatic" || tt == "semi-automatic") {
                t.advance_after = Odf.seconds (prop (refs, dp, "presentation:duration", false), 0);
                t.on_click = tt == "semi-automatic";
            }
            s.hidden = prop (refs, dp, "presentation:visibility", false) == "hidden";
            s.show_master_shapes = prop (refs, dp, "presentation:background-objects-visible", false) != "false";
            s.background = page_fill (CONTENT, st);
        }

        private class EffectInfo {
            public Xml.Node* node;
            public int click;
            public double time_begin;
        }

        private void collect_effects (Xml.Node* n, int click, double time_begin, Gee.List<EffectInfo> out_list, ref int click_counter, int depth) {
            foreach (var k in kids (n)) {
                if (!is (k, "anim:par") && !is (k, "anim:seq")) continue;
                if (a (k, "presentation:preset-class") != null || a (k, "sgs:anim") != null) {
                    var info = new EffectInfo ();
                    info.node = k;
                    info.click = click;
                    info.time_begin = time_begin;
                    out_list.add (info);
                    continue;
                }
                string nt = a (k, "presentation:node-type") ?? "";
                if (nt == "main-sequence" || nt == "timing-root") {
                    collect_effects (k, click, time_begin, out_list, ref click_counter, 0);
                    continue;
                }
                if (nt == "interactive-sequence") continue;
                if (depth == 0) {
                    click_counter++;
                    collect_effects (k, click_counter, 0, out_list, ref click_counter, 1);
                } else {
                    double tb = Odf.seconds (a (k, "smil:begin"), 0);
                    collect_effects (k, click, tb, out_list, ref click_counter, depth + 1);
                }
            }
        }

        private static double behaviour_length (Xml.Node* n) {
            double mx = 0;
            for (Xml.Node* c = n->children; c != null; c = c->next) {
                if (c->type != Xml.ElementType.ELEMENT_NODE) continue;
                if (a (c, "smil:attributeName") == "visibility") continue;
                double b = Odf.seconds (a (c, "smil:begin"), 0);
                double d = Odf.seconds (a (c, "smil:dur"), 0);
                if (a (c, "smil:autoReverse") == "true") d *= 2;
                string? rc = a (c, "smil:repeatCount");
                if (rc != null && rc != "indefinite") d *= double.max (Odf.to_double (rc, 1), 1);
                mx = double.max (mx, b + d);
                mx = double.max (mx, behaviour_length (c));
            }
            return mx;
        }

        private static Xml.Node* find_named (Xml.Node* n, string local) {
            for (Xml.Node* c = n->children; c != null; c = c->next) {
                if (c->type != Xml.ElementType.ELEMENT_NODE) continue;
                if (c->name == local) return c;
                var r = find_named (c, local);
                if (r != null) return r;
            }
            return null;
        }

        private static string? target_of (Xml.Node* n) {
            string? t = a (n, "smil:targetElement");
            if (t != null) return t;
            for (Xml.Node* c = n->children; c != null; c = c->next) {
                if (c->type != Xml.ElementType.ELEMENT_NODE) continue;
                t = target_of (c);
                if (t != null) return t;
            }
            return null;
        }

        private void read_timing (Xml.Node* page, Slide s) {
            Xml.Node* root = null;
            foreach (var k in kids (page, "anim:par")) root = k;
            if (root == null) return;
            var effects = new Gee.ArrayList<EffectInfo> ();
            int counter = 0;
            collect_effects (root, 0, 0, effects, ref counter, 0);
            double prev_start = 0, prev_end = 0;
            int prev_click = -1;
            foreach (var info in effects) {
                var n = info.node;
                Animation? anim = null;
                if (private_data && a (n, "sgs:anim") != null) {
                    anim = Odf.parse_anim_code (a (n, "sgs:anim"));
                    if (s.find (anim.target) == null) anim = null;
                }
                if (anim == null) {
                    string? target = target_of (n);
                    if (target == null || !id_map.has_key (target)) continue;
                    var e = id_map[target];
                    if (s.find (e.id) != e) continue;
                    anim = new Animation (e.id);
                    string cls = a (n, "presentation:preset-class") ?? "entrance";
                    anim.anim_class = cls == "exit" ? AnimClass.EXIT : (cls == "emphasis" ? AnimClass.EMPHASIS : (cls == "motion-path" ? AnimClass.PATH : (cls == "media-call" ? AnimClass.MEDIA : AnimClass.ENTRANCE)));
                    anim.effect = Odf.effect_of_preset (a (n, "presentation:preset-id"), anim.anim_class);
                    if ((anim.anim_class == AnimClass.ENTRANCE || anim.anim_class == AnimClass.EXIT) && !EffectCatalog.entrance_ok (anim.effect)) anim.effect = AnimEffect.FADE;
                    if (anim.anim_class == AnimClass.EMPHASIS && !anim.effect.is_emphasis () && anim.effect != AnimEffect.SPIN && anim.effect != AnimEffect.GROW) anim.effect = AnimEffect.PULSE;
                    if (anim.anim_class == AnimClass.PATH) {
                        anim.effect = AnimEffect.MOTION_PATH;
                        Xml.Node* mo = find_named (n, "animateMotion");
                        if (mo != null) anim.path = PptxReader.parse_motion_path ((a (mo, "svg:path") ?? "").replace ("z", "Z"));
                    }
                    if (anim.anim_class == AnimClass.MEDIA) {
                        Xml.Node* cm = find_named (n, "command");
                        string cmd = cm != null ? (a (cm, "anim:command") ?? "play") : "play";
                        anim.effect = cmd == "toggle-pause" ? AnimEffect.MEDIA_PAUSE : (cmd == "stop" ? AnimEffect.MEDIA_STOP : AnimEffect.MEDIA_PLAY);
                    }
                    anim.direction = Odf.anim_direction (a (n, "presentation:preset-sub-type"), Direction.FROM_BOTTOM);
                    string nt = a (n, "presentation:node-type") ?? "on-click";
                    anim.trigger = nt == "with-previous" ? AnimTrigger.WITH_PREVIOUS : (nt == "after-previous" ? AnimTrigger.AFTER_PREVIOUS : AnimTrigger.ON_CLICK);
                    if (info.click != prev_click && anim.trigger != AnimTrigger.ON_CLICK && s.animations.size > 0) anim.trigger = AnimTrigger.ON_CLICK;
                    double len = behaviour_length (n);
                    anim.duration = len > 0.002 ? len : (anim.effect == AnimEffect.APPEAR ? 0.5 : 0.5);
                    double start = info.time_begin + Odf.seconds (a (n, "smil:begin"), 0);
                    bool first = info.click != prev_click;
                    if (first) anim.delay = start;
                    else if (anim.trigger == AnimTrigger.WITH_PREVIOUS) anim.delay = start - prev_start;
                    else anim.delay = start - prev_end;
                    if (anim.delay < 1e-6) anim.delay = 0;
                    anim.delay = Math.round (anim.delay * 1000) / 1000;
                    double dur = anim.effect == AnimEffect.APPEAR ? 0.01 : double.max (anim.duration, 0.01);
                    prev_start = start;
                    prev_end = start + dur;
                }
                prev_click = info.click;
                s.animations.add (anim);
            }
        }

        private void read_meta () {
            Xml.Doc* doc;
            try {
                doc = load ("meta.xml", false);
            } catch (Error e) {
                return;
            }
            if (doc == null) return;
            Xml.Node* meta = kid (doc->get_root_element (), "office:meta");
            var p = pres.properties;
            var keywords = new StringBuilder ();
            foreach (var n in kids (meta)) {
                string v = XmlIn.text (n);
                if (is (n, "dc:title")) p.title = v;
                else if (is (n, "dc:subject")) p.subject = v;
                else if (is (n, "meta:initial-creator")) p.author = v;
                else if (is (n, "dc:creator") && p.author == "") p.author = v;
                else if (is (n, "meta:creation-date")) p.created = v;
                else if (is (n, "dc:date")) p.modified = v;
                else if (is (n, "meta:keyword")) {
                    if (keywords.len > 0) keywords.append (", ");
                    keywords.append (v);
                }
            }
            p.keywords = keywords.str;
        }

        public Presentation read () throws Error {
            pres = new Presentation ();
            Xml.Doc* content = load ("content.xml", true);
            Xml.Doc* styles = load ("styles.xml", false);
            Xml.Node* croot = content->get_root_element ();
            Xml.Node* sroot = styles != null ? styles->get_root_element () : null;
            if (sroot != null) {
                index_styles (kid (sroot, "office:styles"), common);
                index_styles (kid (sroot, "office:automatic-styles"), auto_styles);
            }
            index_styles (kid (croot, "office:styles"), common);
            index_styles (kid (croot, "office:automatic-styles"), auto_content);
            Xml.Node* body = kid (kid (croot, "office:body"), "office:presentation");
            if (body == null) throw new FormatError.INVALID (_("The file is not an OpenDocument presentation."));
            Xml.Node* ms = sroot != null ? kid (sroot, "office:master-styles") : null;
            foreach (var mp in kids (ms, "style:master-page")) if (a (mp, "sgs:role") != null) private_data = true;
            if (a (body, "sgs:pres") != null) private_data = true;
            if (ms != null) {
                foreach (var mp in kids (ms, "style:master-page")) {
                    string? pl = a (mp, "style:page-layout-name");
                    if (pl == null) continue;
                    Xml.Node* layout = lookup (STYLES, "page-layout", pl);
                    if (layout == null) {
                        foreach (var n in kids (kid (sroot, "office:automatic-styles"), "style:page-layout")) if (a (n, "style:name") == pl) layout = n;
                    }
                    Xml.Node* props = kid (layout, "style:page-layout-properties");
                    if (props != null) {
                        pres.width = Odf.length (a (props, "fo:page-width"), 960);
                        pres.height = Odf.length (a (props, "fo:page-height"), 540);
                    }
                    break;
                }
                read_masters (ms);
            }
            if (pres.masters.size == 0) {
                var fallback = Factory.build_master (ThemePreset.all ()[0], pres.width, pres.height);
                pres.masters.add (fallback);
            }
            foreach (var n in kids (body)) {
                if (is (n, "presentation:footer-decl")) pres.footer_text = XmlIn.text (n);
                else if (is (n, "presentation:date-time-decl")) pres.date_text = XmlIn.text (n);
                else if (is (n, "presentation:settings")) {
                    pres.loop = a (n, "presentation:endless") == "true";
                    pres.use_timings = a (n, "presentation:force-manual") != "true";
                    pres.show_custom = a (n, "presentation:show") ?? "";
                    if (a (n, "presentation:full-screen") == "false") pres.show_kind = 1;
                    pres.show_animation = a (n, "presentation:animations") != "disabled";
                    settings_node = n;
                }
            }
            if (private_data && a (body, "sgs:pres") != null) {
                string[] p = Odf.fields (a (body, "sgs:pres"), 6);
                pres.width = Odf.to_double (p[0], pres.width);
                pres.height = Odf.to_double (p[1], pres.height);
                pres.loop = p[2] == "1";
                pres.use_timings = p[3] != "0";
                pres.footer_text = Odf.dec (p[4]);
                pres.date_text = Odf.dec (p[5]);
            }
            var pages = kids (body, "draw:page");
            var page_by_name = new Gee.HashMap<string, Slide> ();
            var slides_pages = new Gee.ArrayList<Xml.Node*> ();
            foreach (var page in pages) {
                var s = new Slide ();
                string mpn = a (page, "draw:master-page-name") ?? "";
                var l = page_layouts[mpn];
                if (l != null) s.layout_id = l.id;
                else if (pres.masters[0].layouts.size > 0) s.layout_id = pres.masters[0].layouts[0].id;
                string pname = a (page, "draw:name") ?? "";
                if (!pname.has_prefix ("page") && !pname.has_prefix ("Slide")) s.name = pname;
                read_transition (page, s);
                page_by_name[a (page, "draw:name") ?? ""] = s;
                if (private_data && a (page, "sgs:uid") != null) {
                    s.uid = Odf.to_int (a (page, "sgs:uid"), s.uid);
                    Slide.reserve_uid (s.uid);
                }
                if (private_data && a (page, "sgs:section") != null) {
                    string[] sp = Odf.fields (a (page, "sgs:section"), 3);
                    s.section = new SectionMark (Odf.dec (sp[0]));
                    if (sp[1] != "") s.section.id = Odf.dec (sp[1]);
                    s.section.collapsed = sp[2] == "1";
                }
                var by_id = new Gee.HashMap<string, Comment> ();
                foreach (var an in kids (page, "officeooo:annotation")) {
                    var cm = new Comment ();
                    cm.x = Odf.length (a (an, "svg:x"), 0);
                    cm.y = Odf.length (a (an, "svg:y"), 0);
                    cm.author = XmlIn.text (kid (an, "dc:creator"));
                    cm.date = XmlIn.text (kid (an, "dc:date"));
                    cm.initials = XmlIn.text (kid (an, "meta:creator-initials"));
                    if (cm.initials == "") cm.initials = Comment.initials_of (cm.author);
                    var lines = new Gee.ArrayList<string> ();
                    foreach (var tp in kids (an, "text:p")) lines.add (XmlIn.text (tp));
                    cm.text = string.joinv ("\n", lines.to_array ());
                    string parent = "";
                    if (private_data && a (an, "sgs:comment") != null) {
                        string[] cp = Odf.fields (a (an, "sgs:comment"), 3);
                        cm.id = Odf.dec (cp[0]);
                        parent = Odf.dec (cp[1]);
                        cm.resolved = cp[2] == "1";
                    }
                    if (parent != "" && by_id.has_key (parent)) by_id[parent].replies.add (cm);
                    else {
                        s.comments.add (cm);
                        by_id[cm.id] = cm;
                    }
                }
                var c = new Ctx ();
                c.scope = CONTENT;
                s.elements.add_all (read_elements (page, c));
                Xml.Node* notes = kid (page, "presentation:notes");
                if (notes != null) {
                    foreach (var f in kids (notes, "draw:frame")) {
                        if (a (f, "presentation:class") != "notes") continue;
                        var nb = new TextBody ();
                        read_paragraphs (kid (f, "draw:text-box"), nb, c, false, 0, null, false);
                        s.notes = nb.plain_text ();
                    }
                }
                if (private_data) {
                    string? v = a (page, "sgs:slide");
                    if (v != null) {
                        string[] p = Odf.fields (v, 4);
                        s.layout_id = Odf.dec (p[0]);
                        s.hidden = p[1] == "1";
                        s.show_master_shapes = p[2] != "0";
                        s.name = Odf.dec (p[3]);
                    }
                    v = a (page, "sgs:bg");
                    if (v != null) {
                        if (v == "inherit") s.background = null;
                        else s.background = Odf.parse_fill (v, s.background != null ? s.background.image : null, s.background != null ? s.background.image_mime : "");
                    }
                    v = a (page, "sgs:transition");
                    if (v != null) Odf.apply_transition_code (s.transition, v);
                }
                pres.slides.add (s);
                slides_pages.add (page);
            }
            if (!private_data) {
                foreach (var m in pres.masters) {
                    foreach (var e in m.elements) pres.assign_ids (e);
                    foreach (var l in m.layouts) foreach (var e in l.elements) pres.assign_ids (e);
                }
                foreach (var s in pres.slides) foreach (var e in s.elements) pres.assign_ids (e);
            }
            for (int i = 0; i < pres.slides.size; i++) read_timing (slides_pages[i], pres.slides[i]);
            foreach (var ca in pending_page) {
                if (page_by_name.has_key (ca.target)) ca.slide_uid = page_by_name[ca.target].uid;
                ca.target = "";
            }
            if (settings_node != null) {
                foreach (var sh in kids (settings_node, "presentation:show")) {
                    var cs = new CustomShow ();
                    cs.name = a (sh, "presentation:name") ?? "";
                    foreach (string pn in (a (sh, "presentation:pages") ?? "").split (",")) {
                        if (page_by_name.has_key (pn.strip ())) cs.slides.add (page_by_name[pn.strip ()].uid);
                    }
                    pres.custom_shows.add (cs);
                }
                string? sp = a (settings_node, "presentation:start-page");
                if (sp != null && page_by_name.has_key (sp)) pres.show_from = pres.slides.index_of (page_by_name[sp]) + 1;
            }
            read_meta ();
            return pres;
        }
    }
}
