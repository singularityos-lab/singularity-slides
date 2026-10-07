namespace Singularity.Apps.Slides {

    public class PptxReader {
        private class Rel {
            public string type;
            public string target;
            public bool external;
        }

        private class Xform {
            public double sx = 1;
            public double sy = 1;
            public double tx = 0;
            public double ty = 0;

            public double x (double v) {
                return v * sx + tx;
            }

            public double y (double v) {
                return v * sy + ty;
            }
        }

        private ZipReader zip;
        private Presentation pres;
        private Gee.HashMap<string, Layout> layout_by_part = new Gee.HashMap<string, Layout> ();
        private Gee.HashMap<Master, Gee.HashMap<string, string>> master_maps = new Gee.HashMap<Master, Gee.HashMap<string, string>> ();
        private Gee.HashMap<Master, Gee.ArrayList<double?>> master_widths = new Gee.HashMap<Master, Gee.ArrayList<double?>> ();
        private Gee.HashSet<string> layout_ids = new Gee.HashSet<string> ();
        private string part = "";
        private Gee.HashMap<string, Rel> rels = new Gee.HashMap<string, Rel> ();
        private Gee.HashMap<string, string> clr_map = new Gee.HashMap<string, string> ();
        private Gee.ArrayList<double?> line_widths = new Gee.ArrayList<double?> ();
        private string ph_color = "accent1";
        private int layout_counter = 0;
        private Gee.HashMap<string, string> ct_defaults = new Gee.HashMap<string, string> ();
        private Gee.HashMap<string, string> ct_overrides = new Gee.HashMap<string, string> ();
        private Gee.HashMap<string, ForeignPart> foreign_cache = new Gee.HashMap<string, ForeignPart> ();
        private Gee.HashMap<string, int> uid_by_part = new Gee.HashMap<string, int> ();
        private Gee.HashMap<string, string> part_by_sldid = new Gee.HashMap<string, string> ();
        private Gee.ArrayList<ClickAction> pending_actions = new Gee.ArrayList<ClickAction> ();
        private Gee.ArrayList<TextRun> pending_links = new Gee.ArrayList<TextRun> ();
        private Gee.HashMap<string, string> author_names = new Gee.HashMap<string, string> ();
        private Gee.HashMap<string, string> author_initials = new Gee.HashMap<string, string> ();
        private Gee.HashMap<string, string> custom_show_names = new Gee.HashMap<string, string> ();
        private Slide? current_slide = null;
        private Gee.HashMap<int, MediaElement> media_by_id = new Gee.HashMap<int, MediaElement> ();
        private int foreign_count = 0;
        private Gee.HashMap<ZoomElement, string> pending_zoom = new Gee.HashMap<ZoomElement, string> ();

        public PptxReader (ZipReader zip) {
            this.zip = zip;
        }

        private Xml.Doc* load (string path) throws Error {
            string? text = zip.read_text (path);
            if (text == null) return null;
            Xml.Doc* doc = Xml.Parser.read_memory (text, text.length, null, null, Xml.ParserOption.NONET | Xml.ParserOption.HUGE | Xml.ParserOption.NOERROR | Xml.ParserOption.NOWARNING);
            if (doc == null || doc->get_root_element () == null) {
                if (doc != null) delete doc;
                throw new FormatError.INVALID (_("The presentation contains a damaged part: %s").printf (path));
            }
            return doc;
        }

        private Gee.HashMap<string, Rel> load_rels (string path) throws Error {
            var map = new Gee.HashMap<string, Rel> ();
            Xml.Doc* doc = null;
            try {
                doc = load (OoxmlRels.rels_path (path));
            } catch (Error e) {
                return map;
            }
            if (doc == null) return map;
            foreach (Xml.Node* n in XmlIn.elements (doc->get_root_element (), "Relationship")) {
                var r = new Rel ();
                r.type = XmlIn.attr (n, "Type") ?? "";
                string target = XmlIn.attr (n, "Target") ?? "";
                r.external = XmlIn.attr (n, "TargetMode") == "External";
                r.target = r.external ? target : OoxmlRels.resolve (path, target);
                string? id = XmlIn.attr (n, "Id");
                if (id != null) map[id] = r;
            }
            delete doc;
            return map;
        }

        private void enter (string path) throws Error {
            part = path;
            rels = load_rels (path);
        }

        private string? rel_target (string? id) {
            if (id == null || !rels.has_key (id)) return null;
            return rels[id].target;
        }

        private static string? rid (Xml.Node* n, string name) {
            return XmlIn.attr_ns (n, name, "/relationships");
        }

        private static int64 lattr (Xml.Node* n, string name, int64 fallback) {
            string? v = XmlIn.attr (n, name);
            if (v == null) return fallback;
            int64 r = 0;
            if (int64.try_parse (v.strip (), out r)) return r;
            double d = 0;
            if (double.try_parse (v.strip (), out d)) return (int64) d;
            return fallback;
        }

        private static bool battr (Xml.Node* n, string name, bool fallback) {
            string? v = XmlIn.attr (n, name);
            if (v == null) return fallback;
            return v == "1" || v == "true" || v == "on";
        }

        public Presentation read () throws Error {
            pres = new Presentation ();
            load_content_types ();
            var root_rels = load_rels ("");
            string pres_path = "ppt/presentation.xml";
            foreach (var r in root_rels.values) if (r.type.has_suffix ("/officeDocument")) pres_path = r.target;
            enter (pres_path);
            var pres_rels = rels;
            Xml.Doc* doc = load (pres_path);
            if (doc == null) throw new FormatError.INVALID (_("The file is not a PowerPoint presentation."));
            Xml.Node* root = doc->get_root_element ();
            Xml.Node* sz = XmlIn.child (root, "sldSz");
            if (sz != null) {
                pres.width = Ooxml.pt (lattr (sz, "cx", 12192000));
                pres.height = Ooxml.pt (lattr (sz, "cy", 6858000));
            }
            var master_paths = new Gee.ArrayList<string> ();
            foreach (Xml.Node* m in XmlIn.elements (XmlIn.child (root, "sldMasterIdLst"), "sldMasterId")) {
                string? t = pres_rels.has_key (rid (m, "id") ?? "") ? pres_rels[rid (m, "id")].target : null;
                if (t != null) master_paths.add (t);
            }
            if (master_paths.size == 0) foreach (var r in pres_rels.values) if (r.type.has_suffix ("/slideMaster")) master_paths.add (r.target);
            var slide_paths = new Gee.ArrayList<string> ();
            var slide_numbers = new Gee.ArrayList<int64?> ();
            foreach (Xml.Node* s in XmlIn.elements (XmlIn.child (root, "sldIdLst"), "sldId")) {
                string? id = rid (s, "id");
                if (id != null && pres_rels.has_key (id)) {
                    slide_paths.add (pres_rels[id].target);
                    slide_numbers.add ((int64) XmlIn.double_attr (s, "id", 0));
                    part_by_sldid[XmlIn.attr (s, "id") ?? ""] = pres_rels[id].target;
                }
            }
            string? sections_xml = null;
            string? shows_xml = null;
            Xml.Node* shows_node = XmlIn.child (root, "custShowLst");
            if (shows_node != null) shows_xml = XmlIn.serialize (shows_node);
            foreach (Xml.Node* e in XmlIn.elements (XmlIn.child (root, "extLst"), "ext")) {
                if (XmlIn.attr (e, "uri") == Ooxml.EXT_SECTIONS) {
                    Xml.Node* sl = XmlIn.child (e, "sectionLst");
                    if (sl != null) sections_xml = XmlIn.serialize (sl);
                }
            }
            foreach (Xml.Node* c in XmlIn.elements (root)) {
                switch (c->name) {
                    case "sldMasterIdLst": case "notesMasterIdLst": case "handoutMasterIdLst": case "sldIdLst": case "sldSz":
                    case "notesSz": case "defaultTextStyle": case "extLst": case "custShowLst": case "embeddedFontLst":
                        break;
                    default:
                        pres.extras.add (make_extra (c));
                        break;
                }
            }
            foreach (Xml.Node* e in XmlIn.elements (XmlIn.child (root, "extLst"), "ext")) {
                string uri = XmlIn.attr (e, "uri") ?? "";
                if (uri == Ooxml.EXT_SECTIONS || uri == Ooxml.EXT_URI) continue;
                pres.extras.add (make_extra (e));
            }
            read_fonts (XmlIn.child (root, "embeddedFontLst"));
            TextStyle? default_style = null;
            Xml.Node* dts = XmlIn.child (root, "defaultTextStyle");
            if (dts != null) default_style = parse_lst (dts);
            Xml.Node* ext = find_ext (root);
            if (ext != null) {
                Xml.Node* hf = XmlIn.child (ext, "headerFooter");
                if (hf != null) {
                    pres.footer_text = XmlIn.attr (hf, "footer") ?? "";
                    pres.date_text = XmlIn.attr (hf, "date") ?? "";
                }
            }
            delete doc;
            foreach (string mp in master_paths) read_master (mp);
            if (pres.masters.size == 0) pres.masters.add (Factory.build_master (ThemePreset.all ()[0], pres.width, pres.height));
            if (default_style != null) {
                foreach (var m in pres.masters) if (m.other_style.is_empty ()) m.other_style = default_style.clone ();
            }
            foreach (var r in pres_rels.values) {
                if (r.type.has_suffix ("/presProps")) read_pres_props (r.target);
                else if (r.type == Ooxml.REL_COMMENT_AUTHORS) read_authors (r.target, false);
                else if (r.type == Ooxml.REL_MODERN_AUTHORS) read_authors (r.target, true);
            }
            foreach (var e in pres_rels.entries) {
                var r = e.value;
                if (r.external || structural (r.type) || r.type == Ooxml.REL_MODERN_AUTHORS || r.type == Ooxml.REL_FONT) continue;
                bool used = false;
                foreach (var x in pres.extras) foreach (var fr in x.rels) if (fr.id == e.key) used = true;
                if (used) continue;
                var fr = new ForeignRel (e.key, r.type, r.target, false);
                fr.part = load_part (r.target);
                if (fr.part != null) pres.extra_parts.add (fr);
            }
            foreach (var r in root_rels.values) {
                if (r.type.has_suffix ("/core-properties")) read_core (r.target);
            }
            foreach (string sp in slide_paths) read_slide (sp);
            var taken = new Gee.HashSet<int> ();
            if (pres.slides.size == slide_numbers.size) {
                for (int i = 0; i < pres.slides.size; i++) {
                    int64 n = slide_numbers[i] - 255;
                    if (n < 1 || n > int.MAX / 2 || taken.contains ((int) n)) continue;
                    taken.add ((int) n);
                    pres.slides[i].uid = (int) n;
                    Slide.reserve_uid ((int) n);
                    uid_by_part[slide_paths[i]] = (int) n;
                }
            }
            if (sections_xml != null) {
                Xml.Doc* sd = XmlIn.parse (sections_xml);
                read_sections (sd->get_root_element ());
                delete sd;
            }
            if (shows_xml != null) {
                enter (pres_path);
                Xml.Doc* cd = XmlIn.parse (shows_xml);
                read_custom_shows (cd->get_root_element ());
                delete cd;
            }
            resolve_links ();
            Factory.refresh_inherited (pres);
            fix_ids ();
            if (foreign_count > 0) pres.warnings.add (ngettext ("%d object is kept as it is but cannot be edited here.", "%d objects are kept as they are but cannot be edited here.", foreign_count).printf (foreign_count));
            return pres;
        }

        private void load_content_types () {
            string? text = null;
            try {
                text = zip.read_text ("[Content_Types].xml");
            } catch (Error e) {
                return;
            }
            if (text == null) return;
            Xml.Doc* doc = Xml.Parser.read_memory (text, text.length, null, null, Xml.ParserOption.NONET | Xml.ParserOption.NOERROR | Xml.ParserOption.NOWARNING);
            if (doc == null) return;
            foreach (Xml.Node* n in XmlIn.elements (doc->get_root_element ())) {
                if (n->name == "Default") ct_defaults[(XmlIn.attr (n, "Extension") ?? "").down ()] = XmlIn.attr (n, "ContentType") ?? "";
                else if (n->name == "Override") ct_overrides[(XmlIn.attr (n, "PartName") ?? "").substring (1)] = XmlIn.attr (n, "ContentType") ?? "";
            }
            delete doc;
        }

        private string content_type (string path) {
            if (ct_overrides.has_key (path)) return ct_overrides[path];
            int dot = path.last_index_of (".");
            string ext = dot >= 0 ? path.substring (dot + 1).down () : "";
            if (ct_defaults.has_key (ext)) return ct_defaults[ext];
            return "application/octet-stream";
        }

        private static bool structural (string type) {
            foreach (string t in new string[] { "/slide", "/slideLayout", "/slideMaster", "/notesSlide", "/notesMaster", "/handoutMaster", "/theme", "/presProps", "/viewProps", "/tableStyles", "/officeDocument", "/commentAuthors" }) {
                if (type.has_suffix (t)) return true;
            }
            return false;
        }

        private ForeignPart? load_part (string path) {
            if (foreign_cache.has_key (path)) return foreign_cache[path];
            uint8[]? data = null;
            try {
                data = zip.read (path);
            } catch (Error e) {
                return null;
            }
            if (data == null) return null;
            var fp = new ForeignPart (path, new Bytes (data), content_type (path));
            foreign_cache[path] = fp;
            Gee.HashMap<string, Rel> r;
            try {
                r = load_rels (path);
            } catch (Error e) {
                r = new Gee.HashMap<string, Rel> ();
            }
            foreach (var e in r.entries) {
                var fr = new ForeignRel (e.key, e.value.type, e.value.target, e.value.external);
                if (!e.value.external && !structural (e.value.type)) fr.part = load_part (e.value.target);
                else if (!e.value.external) continue;
                fp.rels.add (fr);
            }
            return fp;
        }

        private static void collect_rids (Xml.Node* n, Gee.Set<string> ids) {
            for (Xml.Attr* a = n->properties; a != null; a = a->next) {
                if (a->ns != null && a->ns->href != null && a->ns->href == Ooxml.NS_R && a->children != null) ids.add (a->children->content);
            }
            for (Xml.Node* c = n->children; c != null; c = c->next) {
                if (c->type == Xml.ElementType.ELEMENT_NODE) collect_rids (c, ids);
            }
        }

        private static Xml.Node* find_desc (Xml.Node* n, string name) {
            for (Xml.Node* c = n->children; c != null; c = c->next) {
                if (c->type != Xml.ElementType.ELEMENT_NODE) continue;
                if (c->name == name) return c;
                var r = find_desc (c, name);
                if (r != null) return r;
            }
            return null;
        }

        private ForeignElement make_foreign (Xml.Node* n, string label, Xform xf) {
            var f = new ForeignElement ();
            f.xml = XmlIn.serialize (n);
            f.label = label;
            var ids = new Gee.HashSet<string> ();
            collect_rids (n, ids);
            foreach (string id in ids) {
                if (!rels.has_key (id)) continue;
                var r = rels[id];
                var fr = new ForeignRel (id, r.type, r.target, r.external);
                if (!r.external) {
                    if (structural (r.type)) {
                        if (r.type.has_suffix ("/slide")) fr.target = r.target;
                        else continue;
                    } else {
                        fr.part = load_part (r.target);
                        if (fr.part == null) continue;
                    }
                }
                f.rels.add (fr);
            }
            Xml.Node* nv = find_desc (n, "cNvPr");
            if (nv != null) {
                f.id = XmlIn.int_attr (nv, "id", 0);
                f.name = XmlIn.attr (nv, "name") ?? "";
                f.description = XmlIn.attr (nv, "descr") ?? "";
            }
            Xml.Node* x = find_desc (n, "xfrm");
            if (x != null) parse_xfrm (x, f, xf);
            f.orig_x = f.x;
            f.orig_y = f.y;
            f.orig_w = f.w;
            f.orig_h = f.h;
            f.orig_rot = f.rotation;
            foreign_count++;
            return f;
        }

        private ForeignElement make_extra (Xml.Node* n) {
            var f = make_foreign (n, n->name, new Xform ());
            foreign_count--;
            return f;
        }

        private Xml.Node* find_ext (Xml.Node* parent) {
            Xml.Node* lst = XmlIn.child (parent, "extLst");
            foreach (Xml.Node* e in XmlIn.elements (lst, "ext")) {
                if (XmlIn.attr (e, "uri") == Ooxml.EXT_URI) return e;
            }
            return null;
        }

        private void read_fonts (Xml.Node* lst) {
            if (lst == null) return;
            foreach (Xml.Node* f in XmlIn.elements (lst, "embeddedFont")) {
                string family = XmlIn.attr (XmlIn.child (f, "font"), "typeface") ?? "";
                Bytes? reg = null, bold = null, ital = null, bi = null;
                foreach (Xml.Node* c in XmlIn.elements (f)) {
                    string? t = rel_target (rid (c, "id"));
                    if (t == null) continue;
                    Bytes? data = null;
                    try {
                        uint8[]? raw = zip.read (t);
                        if (raw != null) data = new Bytes (raw);
                    } catch (Error e) {
                        data = null;
                    }
                    switch (c->name) {
                        case "regular": reg = data; break;
                        case "bold": bold = data; break;
                        case "italic": ital = data; break;
                        case "boldItalic": bi = data; break;
                        default: break;
                    }
                }
                if (family == "" || (reg == null && bold == null)) continue;
                var ef = new EmbeddedFont (family, reg ?? bold);
                ef.bold = bold;
                ef.italic = ital;
                ef.bold_italic = bi;
                pres.fonts.add (ef);
                pres.embed_fonts = true;
            }
        }

        private void read_authors (string path, bool modern) {
            Xml.Doc* doc = null;
            try {
                doc = load (path);
            } catch (Error e) {
                return;
            }
            if (doc == null) return;
            foreach (Xml.Node* a in XmlIn.elements (doc->get_root_element ())) {
                string id = XmlIn.attr (a, "id") ?? "";
                author_names[(modern ? "m" : "l") + id] = XmlIn.attr (a, "name") ?? "";
                author_initials[(modern ? "m" : "l") + id] = XmlIn.attr (a, "initials") ?? "";
            }
            delete doc;
        }

        private static string rich_text (Xml.Node* body) {
            var lines = new Gee.ArrayList<string> ();
            foreach (Xml.Node* p in XmlIn.elements (body, "p")) {
                var sb = new StringBuilder ();
                foreach (Xml.Node* r in XmlIn.elements (p)) {
                    if (r->name == "r" || r->name == "fld") sb.append (XmlIn.text (XmlIn.child (r, "t")));
                    else if (r->name == "br") sb.append ("\n");
                }
                lines.add (sb.str);
            }
            return string.joinv ("\n", lines.to_array ()).strip ();
        }

        private void read_comments (string path, Slide s, bool modern) {
            Xml.Doc* doc = null;
            try {
                doc = load (path);
            } catch (Error e) {
                return;
            }
            if (doc == null) return;
            if (!modern) {
                var by_key = new Gee.HashMap<string, Comment> ();
                var pending = new Gee.ArrayList<Comment> ();
                var parents = new Gee.ArrayList<string> ();
                foreach (Xml.Node* cm in XmlIn.elements (doc->get_root_element (), "cm")) {
                    var c = new Comment ();
                    string aid = XmlIn.attr (cm, "authorId") ?? "0";
                    c.author = author_names["l" + aid] ?? "";
                    c.initials = author_initials["l" + aid] ?? Comment.initials_of (c.author);
                    c.date = XmlIn.attr (cm, "dt") ?? "";
                    Xml.Node* pos = XmlIn.child (cm, "pos");
                    c.x = XmlIn.double_attr (pos, "x", 0) / 8;
                    c.y = XmlIn.double_attr (pos, "y", 0) / 8;
                    c.text = XmlIn.text (XmlIn.child (cm, "text"));
                    by_key[aid + ":" + (XmlIn.attr (cm, "idx") ?? "")] = c;
                    string parent = "";
                    foreach (Xml.Node* e in XmlIn.elements (XmlIn.child (cm, "extLst"), "ext")) {
                        Xml.Node* sgc = XmlIn.child (e, "comment");
                        if (sgc != null && XmlIn.attr (e, "uri") == Ooxml.EXT_URI) {
                            c.resolved = battr (sgc, "resolved", false);
                            string? guid = XmlIn.attr (sgc, "guid");
                            if (guid != null && guid != "") c.id = guid;
                        }
                        Xml.Node* ti = XmlIn.child (e, "threadingInfo");
                        Xml.Node* pc = XmlIn.child (ti, "parentCm");
                        if (pc != null) parent = (XmlIn.attr (pc, "authorId") ?? "") + ":" + (XmlIn.attr (pc, "idx") ?? "");
                    }
                    pending.add (c);
                    parents.add (parent);
                }
                for (int i = 0; i < pending.size; i++) {
                    if (parents[i] != "" && by_key.has_key (parents[i])) by_key[parents[i]].replies.add (pending[i]);
                    else s.comments.add (pending[i]);
                }
            } else {
                foreach (Xml.Node* cm in XmlIn.elements (doc->get_root_element (), "cm")) {
                    var c = modern_comment (cm);
                    Xml.Node* pos = XmlIn.child (cm, "pos");
                    if (pos != null) {
                        c.x = Ooxml.pt (lattr (pos, "x", 0));
                        c.y = Ooxml.pt (lattr (pos, "y", 0));
                    }
                    c.resolved = XmlIn.attr (cm, "status") == "resolved";
                    foreach (Xml.Node* r in XmlIn.elements (XmlIn.child (cm, "replyLst"), "reply")) c.replies.add (modern_comment (r));
                    s.comments.add (c);
                }
            }
            delete doc;
        }

        private Comment modern_comment (Xml.Node* cm) {
            var c = new Comment ();
            c.id = (XmlIn.attr (cm, "id") ?? c.id).replace ("{", "").replace ("}", "");
            string aid = XmlIn.attr (cm, "authorId") ?? "";
            c.author = author_names["m" + aid] ?? "";
            c.initials = author_initials["m" + aid] ?? Comment.initials_of (c.author);
            c.date = XmlIn.attr (cm, "created") ?? "";
            c.text = rich_text (XmlIn.child (cm, "txBody"));
            return c;
        }

        private void read_sections (Xml.Node* lst) {
            foreach (Xml.Node* sec in XmlIn.elements (lst, "section")) {
                var ids = XmlIn.elements (XmlIn.child (sec, "sldIdLst"), "sldId");
                Slide? first = null;
                foreach (Xml.Node* sid in ids) {
                    string? part = part_by_sldid[XmlIn.attr (sid, "id") ?? ""];
                    if (part == null || !uid_by_part.has_key (part)) continue;
                    first = pres.slide_by_uid (uid_by_part[part]);
                    break;
                }
                if (first == null) continue;
                var m = new SectionMark (XmlIn.attr (sec, "name") ?? "");
                string? gid = XmlIn.attr (sec, "id");
                if (gid != null && gid != "") m.id = gid;
                first.section = m;
            }
            if (pres.slides.size > 0 && pres.has_sections () && pres.slides[0].section == null) pres.slides[0].section = new SectionMark (_("Default Section"));
        }

        private void read_custom_shows (Xml.Node* lst) {
            foreach (Xml.Node* cs in XmlIn.elements (lst, "custShow")) {
                var show = new CustomShow ();
                show.name = XmlIn.attr (cs, "name") ?? "";
                custom_show_names[XmlIn.attr (cs, "id") ?? ""] = show.name;
                foreach (Xml.Node* sl in XmlIn.elements (XmlIn.child (cs, "sldLst"), "sld")) {
                    string? t = rel_target (rid (sl, "id"));
                    if (t != null && uid_by_part.has_key (t)) show.slides.add (uid_by_part[t]);
                }
                pres.custom_shows.add (show);
            }
        }

        private void resolve_links () {
            if (pres.show_custom != "") pres.show_custom = custom_show_names[pres.show_custom] ?? "";
            foreach (var a in pending_actions) {
                if (a.kind == ActionKind.SLIDE) {
                    a.slide_uid = uid_by_part.has_key (a.target) ? uid_by_part[a.target] : 0;
                    a.target = "";
                } else if (a.kind == ActionKind.CUSTOM_SHOW) {
                    a.target = custom_show_names[a.target] ?? a.target;
                }
            }
            foreach (var e in pending_zoom.entries) e.key.target_uid = uid_by_part.has_key (e.value) ? uid_by_part[e.value] : 0;
            foreach (var r in pending_links) {
                string part = r.link.substring (6);
                r.link = uid_by_part.has_key (part) ? LinkTarget.for_slide (uid_by_part[part]) : "";
            }
            foreach (var s in pres.slides) {
                var all = new Gee.ArrayList<Element> ();
                foreach (var e in s.elements) flatten (e, all);
                foreach (var e in all) {
                    var f = e as ForeignElement;
                    if (f == null) {
                        var dg = e as DiagramElement;
                        if (dg != null) f = dg.original;
                    }
                    if (f == null) continue;
                    foreach (var fr in f.rels) {
                        if (fr.part == null && !fr.external && uid_by_part.has_key (fr.target)) fr.target = "uid:%d".printf (uid_by_part[fr.target]);
                    }
                }
            }
        }

        private ClickAction? read_action (Xml.Node* h) {
            if (h == null) return null;
            string? id = rid (h, "id");
            string? target = id != null && id != "" ? rel_target (id) : null;
            var a = ClickAction.from_ppaction (XmlIn.attr (h, "action"), target);
            if (a == null) return null;
            a.highlight = XmlIn.bool_attr (h, "highlightClick", false);
            a.tooltip = XmlIn.attr (h, "tooltip") ?? "";
            Xml.Node* snd = XmlIn.child (h, "snd");
            if (snd != null) a.sound = XmlIn.attr (snd, "name") ?? "";
            if (a.kind == ActionKind.SLIDE || a.kind == ActionKind.CUSTOM_SHOW) pending_actions.add (a);
            return a;
        }

        private void read_pres_props (string path) throws Error {
            Xml.Doc* doc = load (path);
            if (doc == null) return;
            Xml.Node* show = XmlIn.child (doc->get_root_element (), "showPr");
            if (show != null) {
                pres.loop = battr (show, "loop", false);
                pres.use_timings = battr (show, "useTimings", true);
                if (XmlIn.attr (show, "showNarration") != null) pres.show_narration = battr (show, "showNarration", true);
                pres.show_animation = battr (show, "showAnimation", true);
                if (XmlIn.child (show, "kiosk") != null) pres.show_kind = 2;
                else if (XmlIn.child (show, "browse") != null) pres.show_kind = 1;
                Xml.Node* range = XmlIn.child (show, "sldRg");
                if (range != null) {
                    pres.show_from = XmlIn.int_attr (range, "st", 0);
                    pres.show_to = XmlIn.int_attr (range, "end", 0);
                }
                Xml.Node* cs = XmlIn.child (show, "custShow");
                if (cs != null) pres.show_custom = XmlIn.attr (cs, "id") ?? "";
                string pen = color_child (XmlIn.child (show, "penClr"));
                if (pen != "" && pen.has_prefix ("#")) pres.pen_color = pen;
            }
            delete doc;
        }

        private void read_core (string path) throws Error {
            Xml.Doc* doc = load (path);
            if (doc == null) return;
            foreach (Xml.Node* n in XmlIn.elements (doc->get_root_element ())) {
                string v = XmlIn.text (n).strip ();
                switch (n->name) {
                    case "title": pres.properties.title = v; break;
                    case "creator": pres.properties.author = v; break;
                    case "subject": pres.properties.subject = v; break;
                    case "keywords": pres.properties.keywords = v; break;
                    case "created": pres.properties.created = v; break;
                    case "modified": pres.properties.modified = v; break;
                    default: break;
                }
            }
            delete doc;
        }

        public Theme? read_theme_part () throws Error {
            string? path = null;
            foreach (string n in zip.names ()) {
                if (n.has_suffix (".xml") && n.contains ("theme/theme") && !n.contains ("_rels")) {
                    if (path == null || n < path) path = n;
                }
            }
            if (path == null) return null;
            clr_map = parse_clr_map (null);
            return read_theme (path, new Gee.ArrayList<double?> ());
        }

        private Theme read_theme (string path, Gee.ArrayList<double?> widths) throws Error {
            var t = new Theme ();
            Xml.Doc* doc = load (path);
            if (doc == null) return t;
            Xml.Node* root = doc->get_root_element ();
            t.name = XmlIn.attr (root, "name") ?? "Office";
            t.id = t.name.down ().replace (" ", "-");
            Xml.Node* elements = XmlIn.child (root, "themeElements");
            var saved = clr_map;
            clr_map = new Gee.HashMap<string, string> ();
            foreach (Xml.Node* c in XmlIn.elements (XmlIn.child (elements, "clrScheme"))) {
                string spec = color_child (c);
                if (spec != "" && spec.has_prefix ("#")) t.colors[c->name] = ColorSpec.parse (spec).base_name;
            }
            clr_map = saved;
            Xml.Node* fonts = XmlIn.child (elements, "fontScheme");
            string? major = XmlIn.attr (XmlIn.find (fonts, "majorFont/latin"), "typeface");
            string? minor = XmlIn.attr (XmlIn.find (fonts, "minorFont/latin"), "typeface");
            if (major != null && major != "") t.major_font = major;
            if (minor != null && minor != "") t.minor_font = minor;
            foreach (Xml.Node* ln in XmlIn.elements (XmlIn.find (elements, "fmtScheme/lnStyleLst"), "ln")) widths.add (Ooxml.pt (lattr (ln, "w", 9525)));
            Xml.Node* ext = find_ext (root);
            if (ext != null) {
                string? id = XmlIn.attr (XmlIn.child (ext, "theme"), "id");
                if (id != null && id != "") t.id = id;
            }
            delete doc;
            return t;
        }

        private Gee.HashMap<string, string> parse_clr_map (Xml.Node* n) {
            var map = new Gee.HashMap<string, string> ();
            map["bg1"] = "lt1";
            map["tx1"] = "dk1";
            map["bg2"] = "lt2";
            map["tx2"] = "dk2";
            if (n == null) return map;
            foreach (string k in new string[] { "bg1", "tx1", "bg2", "tx2" }) {
                string? v = XmlIn.attr (n, k);
                if (v != null && v != "") map[k] = v;
            }
            return map;
        }

        private void read_master (string path) throws Error {
            enter (path);
            Xml.Doc* doc = load (path);
            if (doc == null) return;
            var m = new Master ();
            m.id = "master%d".printf (pres.masters.size + 1);
            var widths = new Gee.ArrayList<double?> ();
            string? theme_path = null;
            foreach (var r in rels.values) if (r.type.has_suffix ("/theme")) theme_path = r.target;
            if (theme_path != null) m.theme = read_theme (theme_path, widths);
            enter (path);
            Xml.Node* root = doc->get_root_element ();
            clr_map = parse_clr_map (XmlIn.child (root, "clrMap"));
            master_maps[m] = clr_map;
            master_widths[m] = widths;
            line_widths = widths;
            Xml.Node* csld = XmlIn.child (root, "cSld");
            m.name = XmlIn.attr (csld, "name") ?? m.theme.name;
            var bg = parse_background (XmlIn.child (csld, "bg"));
            if (bg != null) m.background = bg;
            parse_tree (XmlIn.child (csld, "spTree"), m.elements, new Xform ());
            Xml.Node* tx = XmlIn.child (root, "txStyles");
            if (tx != null) {
                Xml.Node* ts = XmlIn.child (tx, "titleStyle");
                if (ts != null) m.title_style = parse_lst (ts);
                Xml.Node* bs = XmlIn.child (tx, "bodyStyle");
                if (bs != null) m.body_style = parse_lst (bs);
                Xml.Node* os = XmlIn.child (tx, "otherStyle");
                if (os != null) m.other_style = parse_lst (os);
            }
            var layout_paths = new Gee.ArrayList<string> ();
            foreach (Xml.Node* l in XmlIn.elements (XmlIn.child (root, "sldLayoutIdLst"), "sldLayoutId")) {
                string? t = rel_target (rid (l, "id"));
                if (t != null) layout_paths.add (t);
            }
            if (layout_paths.size == 0) foreach (var r in rels.values) if (r.type.has_suffix ("/slideLayout")) layout_paths.add (r.target);
            delete doc;
            pres.masters.add (m);
            foreach (string lp in layout_paths) read_layout (lp, m);
        }

        private void read_layout (string path, Master m) throws Error {
            enter (path);
            Xml.Doc* doc = load (path);
            if (doc == null) return;
            Xml.Node* root = doc->get_root_element ();
            clr_map = master_maps[m];
            line_widths = master_widths[m];
            Xml.Node* ovr = XmlIn.find (root, "clrMapOvr/overrideClrMapping");
            if (ovr != null) clr_map = parse_clr_map (ovr);
            var l = new Layout ();
            layout_counter++;
            l.kind = LayoutKind.from_ooxml (XmlIn.attr (root, "type"));
            l.show_master_shapes = battr (root, "showMasterSp", true);
            string id = "layout%d".printf (layout_counter);
            Xml.Node* ext = find_ext (root);
            if (ext != null) {
                Xml.Node* sg = XmlIn.child (ext, "layout");
                if (sg != null) {
                    int k = XmlIn.int_attr (sg, "kind", -1);
                    if (k >= 0 && k <= (int) LayoutKind.CUSTOM) l.kind = (LayoutKind) k;
                    string? sid = XmlIn.attr (sg, "id");
                    if (sid != null && sid != "" && !layout_ids.contains (sid)) id = sid;
                }
            }
            if (layout_ids.contains (id)) id = "layout-%d".printf (layout_counter);
            layout_ids.add (id);
            l.id = id;
            Xml.Node* csld = XmlIn.child (root, "cSld");
            l.name = XmlIn.attr (csld, "name") ?? "";
            l.background = parse_background (XmlIn.child (csld, "bg"));
            parse_tree (XmlIn.child (csld, "spTree"), l.elements, new Xform ());
            delete doc;
            m.layouts.add (l);
            layout_by_part[path] = l;
        }

        private void read_slide (string path) throws Error {
            enter (path);
            Xml.Doc* doc = load (path);
            if (doc == null) return;
            Xml.Node* root = doc->get_root_element ();
            var s = new Slide ();
            current_slide = s;
            media_by_id.clear ();
            uid_by_part[path] = s.uid;
            Layout? layout = null;
            foreach (var r in rels.values) {
                if (r.type.has_suffix ("/slideLayout") && layout_by_part.has_key (r.target)) layout = layout_by_part[r.target];
            }
            Master m = layout != null ? (pres.master_of_layout (layout) ?? pres.masters[0]) : pres.masters[0];
            s.layout_id = layout != null ? layout.id : "";
            clr_map = master_maps.has_key (m) ? master_maps[m] : parse_clr_map (null);
            line_widths = master_widths.has_key (m) ? master_widths[m] : new Gee.ArrayList<double?> ();
            Xml.Node* ovr = XmlIn.find (root, "clrMapOvr/overrideClrMapping");
            if (ovr != null) clr_map = parse_clr_map (ovr);
            s.hidden = !battr (root, "show", true);
            s.show_master_shapes = battr (root, "showMasterSp", true);
            Xml.Node* csld = XmlIn.child (root, "cSld");
            s.name = XmlIn.attr (csld, "name") ?? "";
            s.background = parse_background (XmlIn.child (csld, "bg"));
            parse_tree (XmlIn.child (csld, "spTree"), s.elements, new Xform ());
            foreach (Xml.Node* c in XmlIn.elements (root)) {
                if (c->name == "transition") parse_transition (c, s.transition);
                else if (c->name == "AlternateContent") {
                    Xml.Node* tr = pick_transition (c);
                    if (tr != null) parse_transition (tr, s.transition);
                } else if (c->name == "timing") {
                    parse_timing (c, s);
                } else if (c->name != "cSld" && c->name != "clrMapOvr") {
                    s.extras.add (make_extra (c));
                }
            }
            foreach (Xml.Node* c in XmlIn.elements (csld)) {
                if (c->name == "custDataLst" || c->name == "controls") s.extras.add (make_extra (c));
            }
            string? notes = null;
            var comment_parts = new Gee.ArrayList<string> ();
            var modern_parts = new Gee.ArrayList<string> ();
            foreach (var r in rels.values) {
                if (r.type.has_suffix ("/notesSlide")) notes = r.target;
                else if (r.type == Ooxml.REL_COMMENTS) comment_parts.add (r.target);
                else if (r.type == Ooxml.REL_MODERN_COMMENTS) modern_parts.add (r.target);
            }
            delete doc;
            if (notes != null) s.notes = read_notes (notes);
            foreach (string cp in comment_parts) read_comments (cp, s, false);
            foreach (string cp in modern_parts) read_comments (cp, s, true);
            pres.slides.add (s);
        }

        private string read_notes (string path) throws Error {
            Xml.Doc* doc = load (path);
            if (doc == null) return "";
            string result = "";
            Xml.Node* tree = XmlIn.find (doc->get_root_element (), "cSld/spTree");
            foreach (Xml.Node* sp in XmlIn.elements (tree, "sp")) {
                Xml.Node* ph = XmlIn.find (sp, "nvSpPr/nvPr/ph");
                if (ph == null || XmlIn.attr (ph, "type") != "body") continue;
                Xml.Node* tx = XmlIn.child (sp, "txBody");
                var lines = new Gee.ArrayList<string> ();
                foreach (Xml.Node* p in XmlIn.elements (tx, "p")) {
                    var sb = new StringBuilder ();
                    foreach (Xml.Node* r in XmlIn.elements (p)) {
                        if (r->name == "r" || r->name == "fld") sb.append (XmlIn.text (XmlIn.child (r, "t")));
                        else if (r->name == "br") sb.append ("\n");
                    }
                    lines.add (sb.str);
                }
                while (lines.size > 0 && lines[lines.size - 1] == "") lines.remove_at (lines.size - 1);
                result = string.joinv ("\n", lines.to_array ());
                break;
            }
            delete doc;
            return result;
        }

        private Xml.Node* pick_transition (Xml.Node* ac) {
            foreach (Xml.Node* ch in XmlIn.elements (ac, "Choice")) {
                Xml.Node* tr = XmlIn.child (ch, "transition");
                if (tr == null) continue;
                bool ok = true;
                foreach (Xml.Node* k in XmlIn.elements (tr)) {
                    if (k->name == "sndAc" || k->name == "extLst") continue;
                    if (!TransitionCodec.known (k)) ok = false;
                }
                if (ok) return tr;
            }
            return XmlIn.find (ac, "Fallback/transition");
        }

        private void parse_transition (Xml.Node* n, Transition t) {
            string spd = XmlIn.attr (n, "spd") ?? "fast";
            t.duration = spd == "slow" ? 1.0 : (spd == "med" ? 0.75 : 0.5);
            string? dur = XmlIn.attr_ns (n, "dur", "/powerpoint/2010/main");
            if (dur != null) {
                double d = 0;
                if (double.try_parse (dur, out d)) t.duration = d / 1000.0;
            }
            t.on_click = battr (n, "advClick", true);
            string? adv = XmlIn.attr (n, "advTm");
            if (adv != null) {
                double d = 0;
                if (double.try_parse (adv, out d)) t.advance_after = d / 1000.0;
            }
            t.kind = TransitionKind.NONE;
            foreach (Xml.Node* k in XmlIn.elements (n)) {
                if (k->name == "sndAc") {
                    Xml.Node* st = XmlIn.child (k, "stSnd");
                    Xml.Node* snd = XmlIn.child (st, "snd");
                    if (snd != null) {
                        t.sound = XmlIn.attr (snd, "name") ?? "sound";
                        t.sound_loop = battr (st, "loop", false);
                        string mime;
                        t.sound_data = media (rid (snd, "embed"), out mime);
                    }
                    continue;
                }
                if (k->name == "extLst") continue;
                if (TransitionCodec.read (k, t)) break;
                t.kind = TransitionKind.FADE;
            }
        }

        private static int cond_delay (Xml.Node* ctn) {
            Xml.Node* c = XmlIn.find (ctn, "stCondLst/cond");
            string? d = XmlIn.attr (c, "delay");
            if (d == null || d == "indefinite") return 0;
            int64 v = 0;
            if (int64.try_parse (d, out v)) return (int) v;
            return 0;
        }

        private static void behaviour_duration (Xml.Node* n, ref double best, ref int spid) {
            for (Xml.Node* c = n->children; c != null; c = c->next) {
                if (c->type != Xml.ElementType.ELEMENT_NODE) continue;
                if (c->name == "spTgt" && spid < 0) spid = XmlIn.int_attr (c, "spid", -1);
                if (c->name == "cTn" && XmlIn.attr (c, "presetClass") == null) {
                    string? d = XmlIn.attr (c, "dur");
                    double v = 0;
                    if (d != null && d != "1" && d != "indefinite" && double.try_parse (d, out v)) {
                        if (battr (c, "autoRev", false)) v *= 2;
                        string? rc = XmlIn.attr (c, "repeatCount");
                        double rep = 0;
                        if (rc != null && rc != "indefinite" && double.try_parse (rc, out rep) && rep > 1000) v *= rep / 1000;
                        best = double.max (best, v + cond_delay (c));
                    }
                }
                behaviour_duration (c, ref best, ref spid);
            }
        }

        private void collect_effects (Xml.Node* n, Gee.List<Xml.Node*> list) {
            for (Xml.Node* c = n->children; c != null; c = c->next) {
                if (c->type != Xml.ElementType.ELEMENT_NODE) continue;
                if (c->name == "cTn" && XmlIn.attr (c, "presetClass") != null) {
                    list.add (c);
                    continue;
                }
                if (c->name == "seq") continue;
                collect_effects (c, list);
            }
        }

        public static Gee.ArrayList<PathCommand> parse_motion_path (string path) {
            var list = new Gee.ArrayList<PathCommand> ();
            var tokens = new Gee.ArrayList<string> ();
            var sb = new StringBuilder ();
            for (int i = 0; i < path.length; i++) {
                char ch = path[i];
                if (ch.isalpha () && ch != 'e' && ch != 'E') {
                    if (sb.len > 0) tokens.add (sb.str);
                    sb.truncate ();
                    tokens.add (ch.to_string ());
                } else if (ch == 'E' || (ch == 'e' && (i == 0 || !path[i - 1].isdigit ()))) {
                    if (sb.len > 0) tokens.add (sb.str);
                    sb.truncate ();
                    tokens.add ("E");
                } else if (ch == ' ' || ch == ',') {
                    if (sb.len > 0) tokens.add (sb.str);
                    sb.truncate ();
                } else {
                    sb.append_c (ch);
                }
            }
            if (sb.len > 0) tokens.add (sb.str);
            char op = 'M';
            double cx = 0, cy = 0;
            int i = 0;
            while (i < tokens.size) {
                string t = tokens[i];
                if (t.length == 1 && t[0].isalpha ()) {
                    op = t[0];
                    i++;
                    if (op == 'Z' || op == 'z') {
                        list.add (new PathCommand ('Z', {}));
                        continue;
                    }
                    if (op == 'E') break;
                    continue;
                }
                int need = (op == 'C' || op == 'c') ? 6 : ((op == 'Q' || op == 'q') ? 4 : 2);
                if (i + need > tokens.size) break;
                var pts = new double[need];
                for (int k = 0; k < need; k++) pts[k] = double.parse (tokens[i + k]);
                i += need;
                bool rel = op.islower ();
                if (rel) for (int k = 0; k < need; k += 2) {
                    pts[k] += cx;
                    pts[k + 1] += cy;
                }
                char up = op.toupper ();
                list.add (new PathCommand (up == 'Q' ? 'Q' : (up == 'C' ? 'C' : (up == 'M' && list.size > 0 ? 'L' : up)), pts));
                cx = pts[need - 2];
                cy = pts[need - 1];
                if (up == 'M') op = rel ? 'l' : 'L';
            }
            return list;
        }

        private Xml.Node* desc (Xml.Node* n, string name) {
            return find_desc (n, name);
        }

        private void parse_timing (Xml.Node* timing, Slide s) {
            Xml.Node* root_ctn = XmlIn.find (timing, "tnLst/par/cTn");
            foreach (Xml.Node* c in XmlIn.elements (XmlIn.child (root_ctn, "childTnLst"))) {
                if (c->name == "seq") {
                    Xml.Node* ctn = XmlIn.child (c, "cTn");
                    string nt = XmlIn.attr (ctn, "nodeType") ?? "";
                    if (nt == "interactiveSeq") {
                        int trig = -1;
                        string bm = "";
                        foreach (Xml.Node* cond in XmlIn.elements (XmlIn.child (ctn, "stCondLst"), "cond")) {
                            string evt = XmlIn.attr (cond, "evt") ?? "";
                            Xml.Node* sp = desc (cond, "spTgt");
                            if (sp != null) trig = XmlIn.int_attr (sp, "spid", -1);
                            if (evt == "onMediaBookmark") bm = XmlIn.attr (cond, "name") ?? "bookmark";
                        }
                        walk_effects (ctn, s, trig, bm);
                    } else {
                        walk_effects (ctn, s, -1, "");
                    }
                } else if (c->name == "video" || c->name == "audio") {
                    Xml.Node* mn = XmlIn.child (c, "cMediaNode");
                    Xml.Node* sp = desc (mn, "spTgt");
                    int spid = XmlIn.int_attr (sp, "spid", -1);
                    if (!media_by_id.has_key (spid)) continue;
                    var m = media_by_id[spid];
                    m.volume = XmlIn.double_attr (mn, "vol", 100000) / 100000;
                    m.muted = battr (mn, "mute", false);
                    m.hide_when_stopped = !battr (mn, "showWhenStopped", true);
                    m.across_slides = XmlIn.int_attr (mn, "numSld", 1) > 1;
                    Xml.Node* ctn = XmlIn.child (mn, "cTn");
                    m.loop = XmlIn.attr (ctn, "repeatCount") == "indefinite";
                    m.full_screen = battr (c, "fullScrn", false);
                }
            }
        }

        private void walk_effects (Xml.Node* root, Slide s, int trig, string bookmark) {
            var effects = new Gee.ArrayList<Xml.Node*> ();
            collect_effects (XmlIn.child (root, "childTnLst"), effects);
            bool first = true;
            foreach (Xml.Node* ctn in effects) {
                string cls = XmlIn.attr (ctn, "presetClass") ?? "";
                AnimClass ac;
                switch (cls) {
                    case "entr": ac = AnimClass.ENTRANCE; break;
                    case "exit": ac = AnimClass.EXIT; break;
                    case "emph": ac = AnimClass.EMPHASIS; break;
                    case "path": ac = AnimClass.PATH; break;
                    case "mediacall": ac = AnimClass.MEDIA; break;
                    default: continue;
                }
                double dur = 0;
                int spid = -1;
                behaviour_duration (ctn, ref dur, ref spid);
                if (spid < 0) continue;
                string node = XmlIn.attr (ctn, "nodeType") ?? "";
                var trigger = node == "clickEffect" ? AnimTrigger.ON_CLICK : (node == "afterEffect" ? AnimTrigger.AFTER_PREVIOUS : AnimTrigger.WITH_PREVIOUS);
                if (trig >= 0 && first) trigger = AnimTrigger.ON_CLICK;
                if (ac == AnimClass.MEDIA) {
                    if (media_by_id.has_key (spid)) {
                        var m = media_by_id[spid];
                        Xml.Node* cmd = desc (ctn, "cmd");
                        string cmds = XmlIn.attr (cmd, "cmd") ?? "";
                        if (cmds.has_prefix ("playFrom")) {
                            if (trig >= 0) m.start = MediaStart.ON_CLICK;
                            else m.start = trigger == AnimTrigger.ON_CLICK ? MediaStart.IN_SEQUENCE : MediaStart.AUTOMATIC;
                            if (dur > 0 && m.length <= 0) m.length = dur / 1000.0;
                            continue;
                        }
                        if (trig >= 0 && trig == spid) continue;
                    }
                }
                var a = new Animation (spid);
                a.anim_class = ac;
                int preset = XmlIn.int_attr (ctn, "presetID", 10);
                int subtype = XmlIn.int_attr (ctn, "presetSubtype", 0);
                a.effect = EffectCatalog.from_preset (cls, preset);
                if (ac == AnimClass.EMPHASIS && !a.effect.is_emphasis () && a.effect != AnimEffect.SPIN && a.effect != AnimEffect.GROW) a.effect = AnimEffect.PULSE;
                if ((ac == AnimClass.ENTRANCE || ac == AnimClass.EXIT) && !EffectCatalog.entrance_ok (a.effect)) a.effect = AnimEffect.FADE;
                a.subtype = subtype;
                if (a.effect == AnimEffect.FLOAT) a.subtype = preset == 47 ? 1 : (subtype == 0 ? 4 : subtype);
                else if (a.effect.has_direction () && subtype == 0) a.subtype = EffectCatalog.default_subtype (a.effect);
                a.trigger = trigger;
                a.trigger_shape = trig;
                a.trigger_bookmark = bookmark;
                a.delay = cond_delay (ctn) / 1000.0;
                if (dur > 0) a.duration = dur / 1000.0;
                string? rc = XmlIn.attr (ctn, "repeatCount");
                if (rc == "indefinite") a.repeat = -1;
                else if (rc != null) a.repeat = double.parse (rc) / 1000;
                a.auto_reverse = battr (ctn, "autoRev", false);
                if (a.auto_reverse && a.duration > 0) a.duration /= 2;
                if (a.repeat > 1 && a.duration > 0) a.duration /= a.repeat;
                a.accel = XmlIn.double_attr (ctn, "accel", 0) / 100000;
                a.decel = XmlIn.double_attr (ctn, "decel", 0) / 100000;
                a.rewind = XmlIn.attr (ctn, "fill") == "remove";
                Xml.Node* tgt = desc (ctn, "spTgt");
                Xml.Node* prg = desc (tgt, "pRg");
                if (prg != null) {
                    a.paragraph = XmlIn.int_attr (prg, "st", 0);
                    a.text_build = TextBuild.BY_PARAGRAPH;
                }
                Xml.Node* motion = desc (ctn, "animMotion");
                if (motion != null) {
                    a.path = parse_motion_path (XmlIn.attr (motion, "path") ?? "");
                    a.path_rotate = XmlIn.attr (motion, "rAng") != null && XmlIn.attr (motion, "rAng") != "0";
                    if (ac == AnimClass.PATH) {
                        a.effect = AnimEffect.MOTION_PATH;
                        a.path_preset = MotionPreset.from_preset (preset);
                    }
                }
                Xml.Node* rot = desc (ctn, "animRot");
                if (rot != null) a.amount = XmlIn.double_attr (rot, "by", 21600000) / 60000;
                if (a.effect == AnimEffect.GROW) {
                    Xml.Node* by = desc (desc (ctn, "animScale"), "by");
                    if (by != null) a.amount = XmlIn.double_attr (by, "x", 150000) / 100000;
                }
                if (a.effect == AnimEffect.TRANSPARENCY) {
                    Xml.Node* sv = desc (ctn, "to");
                    Xml.Node* v = sv != null ? (XmlIn.child (sv, "strVal") ?? XmlIn.child (sv, "fltVal")) : null;
                    if (v != null) a.amount = 1 - double.parse (XmlIn.attr (v, "val") ?? "0.5");
                }
                Xml.Node* clr = desc (ctn, "animClr");
                if (clr != null) {
                    string c = color_child (XmlIn.child (clr, "to"));
                    if (c != "") a.color = c;
                }
                if (ac != AnimClass.EXIT) {
                    foreach (Xml.Node* set in XmlIn.elements (XmlIn.child (ctn, "childTnLst"), "set")) {
                        Xml.Node* v = desc (set, "strVal");
                        Xml.Node* sctn = desc (set, "cTn");
                        if (XmlIn.attr (v, "val") == "hidden" && cond_delay (sctn) > 0) a.after = AfterEffect.HIDE;
                    }
                }
                a.set_effect (a.effect);
                if (a.effect.has_direction () || EffectCatalog.options (a.effect) != EffectOptions.NONE) {
                    if (subtype != 0 && a.effect != AnimEffect.FLOAT) a.subtype = subtype;
                }
                a.raw = XmlIn.serialize (ctn->parent);
                a.raw_sig = a.signature ();
                s.animations.add (a);
                first = false;
            }
        }

        private void fix_ids () {
            int mx = pres.max_id ();
            var used = new Gee.HashSet<int> ();
            foreach (var s in pres.slides) {
                var remap = new Gee.HashMap<int, int> ();
                var all = new Gee.ArrayList<Element> ();
                foreach (var e in s.elements) flatten (e, all);
                foreach (var e in all) {
                    if (e.id <= 0 || used.contains (e.id)) {
                        int nid = ++mx;
                        if (!remap.has_key (e.id)) remap[e.id] = nid;
                        e.id = nid;
                    }
                    used.add (e.id);
                }
                foreach (var a in s.animations) {
                    if (remap.has_key (a.target)) {
                        a.target = remap[a.target];
                        a.raw = "";
                    }
                    if (a.trigger_shape >= 0 && remap.has_key (a.trigger_shape)) {
                        a.trigger_shape = remap[a.trigger_shape];
                        a.raw = "";
                    }
                }
                for (int i = s.animations.size - 1; i >= 0; i--) if (s.find (s.animations[i].target) == null) s.animations.remove_at (i);
            }
        }

        private static void flatten (Element e, Gee.List<Element> all) {
            all.add (e);
            var g = e as GroupElement;
            if (g != null) foreach (var c in g.children) flatten (c, all);
        }

        private static string prst_color (string v) {
            switch (v) {
                case "white": return "#ffffff";
                case "red": return "#ff0000";
                case "green": return "#008000";
                case "blue": return "#0000ff";
                case "yellow": return "#ffff00";
                case "gray": case "grey": return "#808080";
                case "orange": return "#ffa500";
                default: return "#000000";
            }
        }

        private string color_of (Xml.Node* c) {
            var spec = new ColorSpec ();
            switch (c->name) {
                case "srgbClr":
                    spec.base_name = "#" + (XmlIn.attr (c, "val") ?? "000000").down ();
                    break;
                case "schemeClr":
                    string v = XmlIn.attr (c, "val") ?? "tx1";
                    if (clr_map.has_key (v)) v = clr_map[v];
                    else if (v == "phClr") v = ph_color;
                    spec.base_name = v;
                    break;
                case "sysClr":
                    string? last = XmlIn.attr (c, "lastClr");
                    if (last != null) spec.base_name = "#" + last.down ();
                    else spec.base_name = XmlIn.attr (c, "val") == "window" ? "#ffffff" : "#000000";
                    break;
                case "prstClr":
                    spec.base_name = prst_color (XmlIn.attr (c, "val") ?? "black");
                    break;
                case "scrgbClr":
                    double r = XmlIn.double_attr (c, "r", 0) / 100000, g = XmlIn.double_attr (c, "g", 0) / 100000, b = XmlIn.double_attr (c, "b", 0) / 100000;
                    spec.base_name = Rgba (Math.pow (r, 1 / 2.2), Math.pow (g, 1 / 2.2), Math.pow (b, 1 / 2.2)).to_hex ();
                    break;
                case "hslClr":
                    spec.base_name = Rgba.from_hsl (XmlIn.double_attr (c, "hue", 0) / 21600000, XmlIn.double_attr (c, "sat", 0) / 100000, XmlIn.double_attr (c, "lum", 0) / 100000).to_hex ();
                    break;
                default:
                    return "";
            }
            foreach (Xml.Node* m in XmlIn.elements (c)) {
                double v = XmlIn.double_attr (m, "val", 100000) / 100000;
                switch (m->name) {
                    case "lumMod": spec.lum_mod *= v; break;
                    case "lumOff": spec.lum_off += v; break;
                    case "alpha": spec.alpha = v; break;
                    case "shade": spec.lum_mod *= v; break;
                    case "tint":
                        spec.lum_mod *= v;
                        spec.lum_off += 1 - v;
                        break;
                    default: break;
                }
            }
            return spec.to_string ();
        }

        private string color_child (Xml.Node* parent) {
            foreach (Xml.Node* c in XmlIn.elements (parent)) {
                string s = color_of (c);
                if (s != "") return s;
            }
            return "";
        }

        private Bytes? media (string? id, out string mime) {
            mime = "image/png";
            string? target = rel_target (id);
            if (target == null || (rels.has_key (id) && rels[id].external)) return null;
            try {
                uint8[]? data = zip.read (target);
                if (data == null) return null;
                int dot = target.last_index_of (".");
                mime = Ooxml.mime_for_ext (dot >= 0 ? target.substring (dot + 1) : "png");
                return new Bytes (data);
            } catch (Error e) {
                return null;
            }
        }

        private Fill? parse_fill (Xml.Node* parent) {
            foreach (Xml.Node* c in XmlIn.elements (parent)) {
                switch (c->name) {
                    case "noFill":
                        return new Fill.none ();
                    case "solidFill":
                        return new Fill.solid (color_child (c));
                    case "gradFill":
                        var f = new Fill ();
                        f.kind = FillKind.GRADIENT;
                        foreach (Xml.Node* gs in XmlIn.elements (XmlIn.child (c, "gsLst"), "gs")) f.stops.add (new GradientStop (XmlIn.double_attr (gs, "pos", 0) / 100000, color_child (gs)));
                        f.stops.sort ((a, b) => a.pos < b.pos ? -1 : (a.pos > b.pos ? 1 : 0));
                        Xml.Node* lin = XmlIn.child (c, "lin");
                        if (lin != null) f.angle = XmlIn.double_attr (lin, "ang", 0) / 60000;
                        else if (XmlIn.child (c, "path") != null) f.radial = true;
                        else f.angle = 90;
                        if (f.stops.size > 0) f.color = f.stops[0].color;
                        if (f.stops.size == 1) return new Fill.solid (f.stops[0].color);
                        return f;
                    case "blipFill":
                        string mime;
                        var data = media (rid (XmlIn.child (c, "blip"), "embed"), out mime);
                        if (data == null) return new Fill.none ();
                        var pf = new Fill.picture (data, mime);
                        pf.tile = XmlIn.child (c, "tile") != null;
                        return pf;
                    case "pattFill":
                        return new Fill.solid (color_child (XmlIn.child (c, "fgClr")));
                    case "grpFill":
                        return new Fill.none ();
                    default:
                        break;
                }
            }
            return null;
        }

        private Fill? parse_background (Xml.Node* bg) {
            if (bg == null) return null;
            Xml.Node* pr = XmlIn.child (bg, "bgPr");
            if (pr != null) return parse_fill (pr) ?? new Fill.solid ("lt1");
            Xml.Node* rf = XmlIn.child (bg, "bgRef");
            if (rf != null) {
                string c = color_child (rf);
                return new Fill.solid (c != "" ? c : "lt1");
            }
            return null;
        }

        private Line parse_line (Xml.Node* ln, out bool has_fill) {
            var l = new Line ();
            has_fill = false;
            l.width = Ooxml.pt (lattr (ln, "w", 9525));
            foreach (Xml.Node* c in XmlIn.elements (ln)) {
                switch (c->name) {
                    case "noFill":
                        has_fill = true;
                        l.color = "";
                        break;
                    case "solidFill":
                        has_fill = true;
                        l.color = color_child (c);
                        break;
                    case "gradFill":
                        has_fill = true;
                        l.color = color_child (XmlIn.find (c, "gsLst/gs"));
                        break;
                    case "prstDash":
                        l.dash = DashKind.from_ooxml (XmlIn.attr (c, "val") ?? "solid");
                        break;
                    case "headEnd":
                        l.head = ArrowKind.from_ooxml (XmlIn.attr (c, "type") ?? "none");
                        break;
                    case "tailEnd":
                        l.tail = ArrowKind.from_ooxml (XmlIn.attr (c, "type") ?? "none");
                        break;
                    default:
                        break;
                }
            }
            return l;
        }

        private void parse_shape_effects (Xml.Node* sppr, ShapeEffects fx) {
            Xml.Node* el = XmlIn.child (sppr, "effectLst");
            Xml.Node* glow = XmlIn.child (el, "glow");
            if (glow != null) {
                fx.glow_radius = Ooxml.pt (lattr (glow, "rad", 0));
                fx.glow_color = color_child (glow);
            }
            Xml.Node* refl = XmlIn.child (el, "reflection");
            if (refl != null) {
                fx.reflection = true;
                fx.reflection_alpha = XmlIn.double_attr (refl, "stA", 50000) / 100000;
                fx.reflection_size = XmlIn.double_attr (refl, "endPos", 50000) / 100000;
                fx.reflection_distance = Ooxml.pt (lattr (refl, "dist", 0));
            }
            Xml.Node* soft = XmlIn.child (el, "softEdge");
            if (soft != null) fx.soft_edge = Ooxml.pt (lattr (soft, "rad", 0));
            Xml.Node* rot = XmlIn.find (sppr, "scene3d/camera/rot");
            if (rot != null) {
                double lat = XmlIn.double_attr (rot, "lat", 0) / 60000, lon = XmlIn.double_attr (rot, "lon", 0) / 60000;
                fx.rot_x = lat > 180 ? lat - 360 : lat;
                fx.rot_y = lon > 180 ? lon - 360 : lon;
            }
            Xml.Node* bevel = XmlIn.find (sppr, "sp3d/bevelT");
            if (bevel != null) {
                fx.bevel = XmlIn.attr (bevel, "prst") ?? "circle";
                fx.bevel_width = Ooxml.pt (lattr (bevel, "w", 76200));
                fx.bevel_height = Ooxml.pt (lattr (bevel, "h", 76200));
            }
        }

        private void parse_text_effects (Xml.Node* tx, ShapeEffects fx) {
            Xml.Node* warp = XmlIn.find (tx, "bodyPr/prstTxWarp");
            if (warp != null) {
                string w = XmlIn.attr (warp, "prst") ?? "";
                if (w != "textNoShape" && w != "textPlain") fx.text_warp = w;
            }
            Xml.Node* rpr = null;
            foreach (Xml.Node* p in XmlIn.elements (tx, "p")) {
                foreach (Xml.Node* r in XmlIn.elements (p, "r")) {
                    rpr = XmlIn.child (r, "rPr");
                    break;
                }
                if (rpr != null) break;
            }
            if (rpr == null) return;
            Xml.Node* ln = XmlIn.child (rpr, "ln");
            if (ln != null && XmlIn.child (ln, "noFill") == null) {
                string c = color_child (XmlIn.child (ln, "solidFill"));
                if (c != "") {
                    fx.text_outline = c;
                    fx.text_outline_width = Ooxml.pt (lattr (ln, "w", 9525));
                }
            }
            Xml.Node* gf = XmlIn.child (rpr, "gradFill");
            if (gf != null) {
                var stops = XmlIn.elements (XmlIn.child (gf, "gsLst"), "gs");
                if (stops.size >= 2) fx.text_fill = color_child (stops[0]) + ">" + color_child (stops[stops.size - 1]);
            }
            Xml.Node* el = XmlIn.child (rpr, "effectLst");
            if (el != null) {
                Xml.Node* g = XmlIn.child (el, "glow");
                if (g != null) {
                    fx.text_glow = ColorSpec.with_alpha (color_child (g), 1);
                    fx.text_glow_radius = Ooxml.pt (lattr (g, "rad", 0));
                }
                fx.text_shadow = XmlIn.child (el, "outerShdw") != null;
                fx.text_reflection = XmlIn.child (el, "reflection") != null;
            }
        }

        private void parse_effects (Xml.Node* sppr, Element e) {
            var shp = e as ShapeElement;
            if (shp != null) parse_shape_effects (sppr, shp.effects);
            Xml.Node* sh = XmlIn.find (sppr, "effectLst/outerShdw");
            if (sh == null) return;
            e.shadow.enabled = true;
            e.shadow.blur = Ooxml.pt (lattr (sh, "blurRad", 0));
            e.shadow.distance = Ooxml.pt (lattr (sh, "dist", 0));
            e.shadow.angle = XmlIn.double_attr (sh, "dir", 0) / 60000;
            var spec = ColorSpec.parse (color_child (sh));
            e.shadow.opacity = spec.alpha;
            spec.alpha = 1;
            e.shadow.color = spec.to_string () != "" ? spec.to_string () : "#000000";
        }

        private bool parse_xfrm (Xml.Node* x, Element e, Xform xf) {
            if (x == null) return false;
            Xml.Node* off = XmlIn.child (x, "off");
            Xml.Node* ext = XmlIn.child (x, "ext");
            if (off == null && ext == null) return false;
            double ox = Ooxml.pt (lattr (off, "x", 0)), oy = Ooxml.pt (lattr (off, "y", 0));
            double w = Ooxml.pt (lattr (ext, "cx", 0)), h = Ooxml.pt (lattr (ext, "cy", 0));
            e.set_geometry (xf.x (ox), xf.y (oy), w * xf.sx, h * xf.sy);
            e.rotation = XmlIn.double_attr (x, "rot", 0) / 60000;
            e.flip_h = battr (x, "flipH", false);
            e.flip_v = battr (x, "flipV", false);
            return true;
        }

        private void parse_nv (Xml.Node* nv, Element e) {
            Xml.Node* c = XmlIn.child (nv, "cNvPr");
            e.id = XmlIn.int_attr (c, "id", 0);
            e.name = XmlIn.attr (c, "name") ?? "";
            e.description = XmlIn.attr (c, "descr") ?? "";
            var linked = e as ChartElement;
            string link_title = XmlIn.attr (c, "title") ?? "";
            if (linked != null && link_title.has_prefix (ChartElement.LINK_PREFIX)) linked.link = Uri.unescape_string (link_title.substring (ChartElement.LINK_PREFIX.length)) ?? "";
            e.click = read_action (XmlIn.child (c, "hlinkClick"));
            e.hover = read_action (XmlIn.child (c, "hlinkHover"));
            Xml.Node* ph = XmlIn.find (nv, "nvPr/ph");
            if (ph != null) {
                e.placeholder = PlaceholderKind.from_ooxml (XmlIn.attr (ph, "type"));
                e.placeholder_idx = XmlIn.int_attr (ph, "idx", -1);
            }
            foreach (Xml.Node* k in XmlIn.elements (nv)) {
                foreach (Xml.Node* lk in XmlIn.elements (k)) {
                    if (lk->name.has_suffix ("Locks") && battr (lk, "noMove", false)) e.locked = true;
                }
            }
        }

        private bool hidden (Xml.Node* nv) {
            return battr (XmlIn.child (nv, "cNvPr"), "hidden", false);
        }

        private void parse_tree (Xml.Node* tree, Gee.List<Element> list, Xform xf) {
            if (tree == null) return;
            foreach (Xml.Node* c in XmlIn.elements (tree)) {
                Element? e = null;
                switch (c->name) {
                    case "sp":
                    case "cxnSp":
                        e = parse_shape (c, xf);
                        break;
                    case "pic":
                        e = parse_picture (c, xf);
                        break;
                    case "graphicFrame":
                        e = parse_frame (c, xf);
                        break;
                    case "grpSp":
                        e = parse_group (c, xf);
                        break;
                    case "AlternateContent":
                        e = parse_alternate (c, xf);
                        break;
                    case "contentPart":
                        e = parse_content_part (c, xf, null);
                        break;
                    case "nvGrpSpPr": case "grpSpPr": case "extLst":
                        break;
                    default:
                        e = make_foreign (c, c->name, xf);
                        break;
                }
                if (e != null) list.add (e);
            }
        }

        private Element? parse_alternate (Xml.Node* ac, Xform xf) {
            Xml.Node* fallback = XmlIn.child (ac, "Fallback");
            foreach (Xml.Node* ch in XmlIn.elements (ac, "Choice")) {
                string req = XmlIn.attr (ch, "Requires") ?? "";
                Xml.Node* inner = null;
                foreach (Xml.Node* k in XmlIn.elements (ch)) {
                    inner = k;
                    break;
                }
                if (inner == null) continue;
                if (req == "pslz" || req == "psez" || req == "psuz") {
                    var z = parse_zoom (inner, fallback, xf);
                    if (z != null) return z;
                }
                if (inner->name == "contentPart") {
                    var ink = parse_content_part (inner, xf, fallback);
                    if (ink != null) return ink;
                }
                if (inner->name == "graphicFrame" && (XmlIn.attr (XmlIn.find (inner, "graphic/graphicData"), "uri") ?? "") == Ooxml.URI_CHARTEX) {
                    var cx = parse_chartex (ac, inner, xf);
                    if (cx != null) return cx;
                }
                if (req == "am3d" || find_desc (inner, "model3d") != null) {
                    var model = parse_model3d (ac, inner, fallback, xf);
                    if (model != null) return model;
                }
                if (inner->name == "sp" && (find_desc (inner, "oMathPara") != null || find_desc (inner, "oMath") != null)) {
                    var eq = parse_equation (ac, inner, fallback, xf);
                    if (eq != null) return eq;
                }
            }
            if (fallback != null) {
                var fl = new Gee.ArrayList<Element> ();
                foreach (Xml.Node* k in XmlIn.elements (fallback)) parse_tree_one (k, fl, xf);
                if (fl.size == 1 && fl[0].kind != ElementKind.FOREIGN && find_desc (ac, "oleObj") == null) {
                    var el = fl[0];
                    el.alternate = make_foreign (ac, el.display_name (), xf);
                    foreign_count--;
                    el.alternate_sig = el.light_signature ();
                    return el;
                }
            }
            var f = make_foreign (ac, _("Embedded Object"), xf);
            Xml.Node* ole = find_desc (ac, "oleObj");
            if (ole != null) f.label = XmlIn.attr (ole, "name") ?? XmlIn.attr (ole, "progId") ?? _("Embedded Object");
            if (fallback != null) {
                var list = new Gee.ArrayList<Element> ();
                foreach (Xml.Node* k in XmlIn.elements (fallback)) parse_tree_one (k, list, xf);
                if (list.size == 1) f.preview = list[0];
                else if (list.size > 1) {
                    var g = new GroupElement ();
                    g.children.add_all (list);
                    g.fit ();
                    f.preview = g;
                }
                if (f.preview != null && f.w <= 0) {
                    f.set_geometry (f.preview.x, f.preview.y, f.preview.w, f.preview.h);
                    f.orig_x = f.x;
                    f.orig_y = f.y;
                    f.orig_w = f.w;
                    f.orig_h = f.h;
                }
            }
            return f;
        }

        private void parse_tree_one (Xml.Node* c, Gee.List<Element> list, Xform xf) {
            Element? e = null;
            switch (c->name) {
                case "sp": case "cxnSp": e = parse_shape (c, xf); break;
                case "pic": e = parse_picture (c, xf); break;
                case "graphicFrame": e = parse_frame (c, xf); break;
                case "grpSp": e = parse_group (c, xf); break;
                case "AlternateContent": e = parse_alternate (c, xf); break;
                default: break;
            }
            if (e != null) list.add (e);
        }

        private Element? parse_zoom (Xml.Node* frame, Xml.Node* fallback, Xform xf) {
            var z = new ZoomElement ();
            parse_nv (XmlIn.child (frame, "nvGraphicFramePr"), z);
            if (!parse_xfrm (XmlIn.child (frame, "xfrm"), z, xf)) return null;
            Xml.Node* obj = find_desc (frame, "sldZmObj");
            Xml.Node* sec = find_desc (frame, "sectionZmObj");
            if (obj == null) obj = find_desc (frame, "summaryZmObj");
            if (obj == null && sec == null) return null;
            if (obj != null) {
                z.zoom = ZoomKind.SLIDE;
                string? part = part_by_sldid[XmlIn.attr (obj, "sldId") ?? ""];
                if (part != null) pending_zoom[z] = part;
            } else {
                z.zoom = ZoomKind.SECTION;
                z.section_id = XmlIn.attr (sec, "sectionId") ?? "";
            }
            Xml.Node* zp = find_desc (frame, "zmPr");
            if (zp != null) {
                z.return_to_zoom = battr (zp, "returnToParent", false);
                z.transition_duration = XmlIn.double_attr (zp, "transitionDur", 1000) / 1000;
                z.use_background = battr (zp, "useBgFill", false);
                Xml.Node* blip = find_desc (zp, "blip");
                if (blip != null) {
                    string mime;
                    var img = media (rid (blip, "embed"), out mime);
                    if (img != null) {
                        z.image = img;
                        z.image_mime = mime;
                    }
                }
            }
            return z;
        }

        private Element? parse_equation (Xml.Node* ac, Xml.Node* sp, Xml.Node* fallback, Xform xf) {
            Xml.Node* ext = null;
            foreach (Xml.Node* e in XmlIn.elements (XmlIn.find (sp, "nvSpPr/cNvPr/extLst"), "ext")) {
                if (XmlIn.attr (e, "uri") == Ooxml.EXT_EQUATION) ext = XmlIn.child (e, "equation");
            }
            var f = make_foreign (ac, _("Equation"), xf);
            Xml.Node* fpic = fallback != null ? XmlIn.child (fallback, "pic") : null;
            if (fpic == null && fallback != null) fpic = find_desc (fallback, "pic");
            var q = new EquationElement ();
            q.set_geometry (f.x, f.y, f.w, f.h);
            q.id = f.id;
            q.name = f.name;
            q.rotation = f.rotation;
            if (ext != null) {
                q.latex = XmlIn.text (XmlIn.child (ext, "latex"));
                q.mathml = XmlIn.text (XmlIn.child (ext, "mathml"));
            }
            q.omml = XmlIn.serialize (find_desc (sp, "oMathPara") ?? find_desc (sp, "oMath"));
            if (fpic != null) {
                var img = parse_picture (fpic, xf) as ImageElement;
                if (img != null) {
                    q.image = img.data;
                    q.image_mime = img.mime;
                    if (q.w <= 0) q.set_geometry (img.x, img.y, img.w, img.h);
                }
            }
            if (q.mathml == "" && q.omml != "") q.mathml = EquationCodec.mathml_from_omml (q.omml);
            foreign_count--;
            q.original = f;
            q.original_sig = EquationCodec.signature (q);
            return q;
        }

        private Element? parse_model3d (Xml.Node* ac, Xml.Node* frame, Xml.Node* fallback, Xform xf) {
            Xml.Node* md = find_desc (frame, "model3d");
            if (md == null) return null;
            string? target = rel_target (rid (md, "embed"));
            var f = make_foreign (ac, _("3D Model"), xf);
            var m = new Model3DElement ();
            m.set_geometry (f.x, f.y, f.w, f.h);
            m.id = f.id;
            m.name = f.name;
            m.rotation = f.rotation;
            Xml.Node* cnv = find_desc (frame, "cNvPr");
            if (cnv != null) m.description = XmlIn.attr (cnv, "descr") ?? "";
            if (target != null) {
                try {
                    uint8[]? d = zip.read (target);
                    if (d != null) {
                        m.data = new Bytes (d);
                        m.format = MeshLoader.format_of (m.data, target);
                    }
                } catch (Error e) {
                    warning ("3d model: %s", e.message);
                }
            }
            Xml.Node* rot = find_desc (md, "rot");
            if (rot != null) {
                m.rot_x = XmlIn.double_attr (rot, "ax", 0) / 60000;
                m.rot_y = XmlIn.double_attr (rot, "ay", 0) / 60000;
                m.rot_z = XmlIn.double_attr (rot, "az", 0) / 60000;
            }
            Xml.Node* pos = find_desc (md, "pos");
            double z = pos != null ? XmlIn.double_attr (pos, "z", 68000000) : 68000000;
            if (z > 0) m.zoom = (68000000 / z).clamp (0.1, 10);
            Xml.Node* fpic = fallback != null ? find_desc (fallback, "pic") : null;
            if (fpic != null) {
                var img = parse_picture (fpic, xf) as ImageElement;
                if (img != null) {
                    m.preview = img.data;
                    if (m.w <= 0) m.set_geometry (img.x, img.y, img.w, img.h);
                }
            }
            foreign_count--;
            m.original = f;
            m.original_sig = m.signature ();
            return m;
        }

        private Element? parse_content_part (Xml.Node* cp, Xform xf, Xml.Node* fallback) {
            string? target = rel_target (rid (cp, "id"));
            if (target == null) return null;
            string? text = null;
            try {
                text = zip.read_text (target);
            } catch (Error e) {
                text = null;
            }
            var ink = new InkElement ();
            Xml.Node* nv = XmlIn.child (cp, "nvContentPartPr");
            Xml.Node* c = XmlIn.child (nv, "cNvPr");
            ink.id = XmlIn.int_attr (c, "id", 0);
            ink.name = XmlIn.attr (c, "name") ?? "";
            Xml.Node* x = XmlIn.child (cp, "xfrm");
            if (!parse_xfrm (x, ink, xf) && fallback != null) {
                Xml.Node* fx = find_desc (fallback, "xfrm");
                parse_xfrm (fx, ink, xf);
            }
            if (text == null || !InkCodec.parse (text, ink)) return null;
            return ink;
        }

        private void geometry (Xml.Node* sppr, ShapeElement s) {
            Xml.Node* prst = XmlIn.child (sppr, "prstGeom");
            if (prst != null) {
                string name = XmlIn.attr (prst, "prst") ?? "rect";
                if (ShapeKind.is_native (name)) {
                    s.shape = ShapeKind.from_ooxml (name);
                } else if (PresetGeometry.has (name)) {
                    s.shape = ShapeKind.PRESET;
                    s.preset = name;
                } else {
                    s.shape = ShapeKind.from_ooxml (name);
                }
                foreach (Xml.Node* g in XmlIn.elements (XmlIn.child (prst, "avLst"), "gd")) {
                    string f = XmlIn.attr (g, "fmla") ?? "";
                    string? gn = XmlIn.attr (g, "name");
                    if (gn != null && f.has_prefix ("val ")) s.adjust_values[gn] = double.parse (f.substring (4));
                }
                if (s.shape == ShapeKind.ROUND_RECT) {
                    s.corner = 0.16667;
                    Xml.Node* gd = XmlIn.find (prst, "avLst/gd");
                    if (gd != null) {
                        string f = XmlIn.attr (gd, "fmla") ?? "";
                        if (f.has_prefix ("val ")) s.corner = double.parse (f.substring (4)) / 100000;
                    }
                }
                return;
            }
            Xml.Node* cust = XmlIn.child (sppr, "custGeom");
            if (cust == null) return;
            s.shape = ShapeKind.CUSTOM;
            Xml.Node* xext = XmlIn.find (sppr, "xfrm/ext");
            foreach (Xml.Node* p in XmlIn.elements (XmlIn.child (cust, "pathLst"), "path")) {
                double pw = XmlIn.double_attr (p, "w", 0), ph = XmlIn.double_attr (p, "h", 0);
                if (pw <= 0) pw = XmlIn.double_attr (xext, "cx", 1);
                if (ph <= 0) ph = XmlIn.double_attr (xext, "cy", 1);
                if (pw <= 0) pw = 1;
                if (ph <= 0) ph = 1;
                double cx = 0, cy = 0;
                foreach (Xml.Node* cmd in XmlIn.elements (p)) {
                    var pts = new double[0];
                    foreach (Xml.Node* pt in XmlIn.elements (cmd, "pt")) {
                        pts += XmlIn.double_attr (pt, "x", 0) / pw;
                        pts += XmlIn.double_attr (pt, "y", 0) / ph;
                    }
                    switch (cmd->name) {
                        case "moveTo":
                            if (pts.length >= 2) s.path.add (new PathCommand ('M', pts[0:2]));
                            break;
                        case "lnTo":
                            if (pts.length >= 2) s.path.add (new PathCommand ('L', pts[0:2]));
                            break;
                        case "cubicBezTo":
                            if (pts.length >= 6) s.path.add (new PathCommand ('C', pts[0:6]));
                            break;
                        case "quadBezTo":
                            if (pts.length >= 4) s.path.add (new PathCommand ('Q', pts[0:4]));
                            break;
                        case "arcTo":
                            double wr = XmlIn.double_attr (cmd, "wR", 0) / pw, hr = XmlIn.double_attr (cmd, "hR", 0) / ph;
                            double st = XmlIn.double_attr (cmd, "stAng", 0) / 60000 * Math.PI / 180;
                            double sw = XmlIn.double_attr (cmd, "swAng", 0) / 60000 * Math.PI / 180;
                            double ocx = cx - wr * Math.cos (st), ocy = cy - hr * Math.sin (st);
                            int steps = int.max (2, (int) (Math.fabs (sw) / (Math.PI / 8)));
                            for (int i = 1; i <= steps; i++) {
                                double a = st + sw * i / steps;
                                s.path.add (new PathCommand ('L', { ocx + wr * Math.cos (a), ocy + hr * Math.sin (a) }));
                            }
                            pts = { ocx + wr * Math.cos (st + sw), ocy + hr * Math.sin (st + sw) };
                            break;
                        case "close":
                            s.path.add (new PathCommand ('Z', {}));
                            break;
                        default:
                            break;
                    }
                    if (pts.length >= 2) {
                        cx = pts[pts.length - 2];
                        cy = pts[pts.length - 1];
                    }
                }
            }
        }

        private void apply_style (Xml.Node* style, ShapeElement s, bool has_fill, bool line_fill, bool has_ln_w) {
            if (style == null) return;
            Xml.Node* fr = XmlIn.child (style, "fillRef");
            if (!has_fill && fr != null && XmlIn.int_attr (fr, "idx", 0) > 0) {
                string c = color_child (fr);
                if (c != "") s.fill = new Fill.solid (c);
            }
            Xml.Node* lr = XmlIn.child (style, "lnRef");
            if (!line_fill && lr != null) {
                int idx = XmlIn.int_attr (lr, "idx", 0);
                string c = color_child (lr);
                if (idx > 0 && c != "") {
                    s.line.color = c;
                    if (!has_ln_w) s.line.width = idx - 1 < line_widths.size ? line_widths[idx - 1] : 0.75;
                }
            }
            Xml.Node* fo = XmlIn.child (style, "fontRef");
            if (fo != null && s.text != null) {
                string c = color_child (fo);
                string font = XmlIn.attr (fo, "idx") == "major" ? "+mj-lt" : "";
                if (c != "" || font != "") {
                    s.text.apply_to_runs ((r) => {
                        if (c != "" && r.color == "") r.color = c;
                        if (font != "" && r.font == "") r.font = font;
                    });
                }
            }
        }

        private Element? parse_shape (Xml.Node* n, Xform xf) {
            Xml.Node* nv = XmlIn.child (n, n->name == "cxnSp" ? "nvCxnSpPr" : "nvSpPr");
            if (hidden (nv)) return null;
            var s = new ShapeElement (ShapeKind.RECT);
            parse_nv (nv, s);
            Xml.Node* cnv = XmlIn.child (nv, "cNvSpPr");
            s.text_box = battr (cnv, "txBox", false);
            Xml.Node* sppr = XmlIn.child (n, "spPr");
            if (!parse_xfrm (XmlIn.child (sppr, "xfrm"), s, xf)) {
                if (s.placeholder != PlaceholderKind.NONE) s.inherit_geometry = true;
            }
            geometry (sppr, s);
            if (n->name == "cxnSp" && s.shape != ShapeKind.CUSTOM) s.shape = ShapeKind.LINE;
            var f = parse_fill (sppr);
            if (f != null) s.fill = f;
            bool line_fill = false, has_w = false;
            Xml.Node* ln = XmlIn.child (sppr, "ln");
            if (ln != null) {
                s.line = parse_line (ln, out line_fill);
                has_w = XmlIn.attr (ln, "w") != null;
                if (!line_fill) s.line.color = "";
            } else {
                s.line.color = "";
            }
            parse_effects (sppr, s);
            Xml.Node* tx = XmlIn.child (n, "txBody");
            if (tx != null) {
                TextStyle? ls;
                s.text = parse_body (tx, out ls);
                s.list_style = ls;
                parse_text_effects (tx, s.effects);
            }
            apply_style (XmlIn.child (n, "style"), s, f != null, line_fill, has_w);
            if (!Geometry.is_closed (s)) s.fill = new Fill.none ();
            return s;
        }

        private Element? parse_media (Xml.Node* n, Xml.Node* nv, Xform xf) {
            Xml.Node* nvpr = XmlIn.child (nv, "nvPr");
            Xml.Node* vf = XmlIn.child (nvpr, "videoFile");
            Xml.Node* af = XmlIn.child (nvpr, "audioFile");
            if (vf == null && af == null) return null;
            var m = new MediaElement ();
            m.is_video = vf != null;
            Xml.Node* p14 = null;
            foreach (Xml.Node* e in XmlIn.elements (XmlIn.child (nvpr, "extLst"), "ext")) {
                Xml.Node* mm = XmlIn.child (e, "media");
                if (mm != null) p14 = mm;
            }
            string? embed = p14 != null ? rid (p14, "embed") : null;
            string? link = rid (vf ?? af, "link");
            string? target = embed != null ? rel_target (embed) : null;
            if (target == null && link != null && rels.has_key (link)) {
                if (rels[link].external) m.link = rels[link].target;
                else target = rels[link].target;
            }
            if (target != null) {
                try {
                    uint8[]? raw = zip.read (target);
                    if (raw != null) m.data = new Bytes (raw);
                } catch (Error e) {
                    m.data = null;
                }
                m.mime = MediaElement.mime_for (target);
                if (m.mime == "application/octet-stream") m.mime = content_type (target);
            } else if (m.link != "") {
                m.mime = MediaElement.mime_for (m.link);
            }
            if (m.data == null && m.link == "") return null;
            if (p14 != null) {
                Xml.Node* tr = XmlIn.child (p14, "trim");
                if (tr != null) {
                    m.trim_start = XmlIn.double_attr (tr, "st", 0) / 1000;
                    m.trim_end = XmlIn.double_attr (tr, "end", 0) / 1000;
                }
                Xml.Node* fd = XmlIn.child (p14, "fade");
                if (fd != null) {
                    m.fade_in = XmlIn.double_attr (fd, "in", 0) / 1000;
                    m.fade_out = XmlIn.double_attr (fd, "out", 0) / 1000;
                }
                foreach (Xml.Node* b in XmlIn.elements (XmlIn.child (p14, "bmkLst"), "bmk")) {
                    m.bookmarks.add (new MediaBookmark (XmlIn.attr (b, "name") ?? "", XmlIn.double_attr (b, "time", 0) / 1000));
                }
            }
            Xml.Node* blip = XmlIn.find (n, "blipFill/blip");
            if (blip != null) {
                string pm;
                m.poster = media (rid (blip, "embed"), out pm);
                m.poster_mime = pm;
            }
            parse_nv (nv, m);
            m.click = null;
            Xml.Node* sppr = XmlIn.child (n, "spPr");
            parse_xfrm (XmlIn.child (sppr, "xfrm"), m, xf);
            Xml.Node* ln = XmlIn.child (sppr, "ln");
            if (ln != null) {
                bool has;
                m.line = parse_line (ln, out has);
                if (!has) m.line.color = "";
            } else {
                m.line.color = "";
            }
            parse_effects (sppr, m);
            m.start = MediaStart.ON_CLICK;
            if (m.id > 0) media_by_id[m.id] = m;
            return m;
        }

        private Element? parse_diagram (Xml.Node* frame, Xml.Node* data, Xform xf) {
            Xml.Node* ids = XmlIn.child (data, "relIds");
            string? dm = rel_target (rid (ids, "dm"));
            string? lo = rel_target (rid (ids, "lo"));
            if (dm == null) return null;
            var d = new DiagramElement ();
            d.original = make_foreign (frame, _("SmartArt"), xf);
            foreign_count--;
            foreach (var e in rels.entries) {
                if (e.value.type != Ooxml.REL_DIAGRAM_DRAWING) continue;
                bool has = false;
                foreach (var fr in d.original.rels) if (fr.id == e.key) has = true;
                if (has) continue;
                var dr = new ForeignRel (e.key, e.value.type, e.value.target, false);
                dr.part = load_part (e.value.target);
                if (dr.part != null) d.original.rels.add (dr);
            }
            d.set_geometry (d.original.x, d.original.y, d.original.w, d.original.h);
            string? layout_uid = null;
            string? cat = null;
            if (lo != null) {
                try {
                    Xml.Doc* ld = load (lo);
                    if (ld != null) {
                        layout_uid = XmlIn.attr (ld->get_root_element (), "uniqueId");
                        cat = XmlIn.attr (XmlIn.find (ld->get_root_element (), "catLst/cat"), "type");
                        delete ld;
                    }
                } catch (Error e) {
                    layout_uid = null;
                }
            }
            string? drawing_path = null;
            string saved = part;
            var saved_rels = rels;
            try {
                Xml.Doc* doc = load (dm);
                if (doc != null) {
                    Xml.Node* root = doc->get_root_element ();
                    var pts = new Gee.HashMap<string, Xml.Node*> ();
                    var order = new Gee.ArrayList<string> ();
                    string doc_id = "";
                    foreach (Xml.Node* pt in XmlIn.elements (XmlIn.child (root, "ptLst"), "pt")) {
                        string id = XmlIn.attr (pt, "modelId") ?? "";
                        string type = XmlIn.attr (pt, "type") ?? "node";
                        if (type == "doc") {
                            doc_id = id;
                            Xml.Node* ps = XmlIn.child (pt, "prSet");
                            if (layout_uid == null) layout_uid = XmlIn.attr (ps, "loTypeId");
                            if (cat == null) cat = XmlIn.attr (ps, "loCatId");
                            string cs = XmlIn.attr (ps, "csTypeId") ?? "";
                            if (cs.contains ("colorful")) d.colors = DiagramColors.COLORFUL;
                            else if (cs.contains ("accent1_4") || cs.contains ("accent1_5")) d.colors = DiagramColors.GRADIENT;
                            else if (cs.contains ("accent0") || cs.contains ("dark")) d.colors = DiagramColors.DARK;
                            else if (cs.contains ("accent1_1")) d.colors = DiagramColors.OUTLINE;
                            string qs = XmlIn.attr (ps, "qsTypeId") ?? "";
                            if (qs.contains ("simple3") || qs.contains ("simple4")) d.style = DiagramStyle.SUBTLE;
                            else if (qs.contains ("simple5") || qs.contains ("3d")) d.style = DiagramStyle.INTENSE;
                        }
                        if (type == "node" || type == "doc" || type == "asst") {
                            pts[id] = pt;
                            order.add (id);
                        }
                    }
                    var children = new Gee.HashMap<string, Gee.ArrayList<string>> ();
                    var ords = new Gee.HashMap<string, int> ();
                    foreach (Xml.Node* cx in XmlIn.elements (XmlIn.child (root, "cxnLst"), "cxn")) {
                        string type = XmlIn.attr (cx, "type") ?? "parOf";
                        if (type != "parOf") continue;
                        string src = XmlIn.attr (cx, "srcId") ?? "";
                        string dst = XmlIn.attr (cx, "destId") ?? "";
                        if (!pts.has_key (dst)) continue;
                        if (!children.has_key (src)) children[src] = new Gee.ArrayList<string> ();
                        children[src].add (dst);
                        ords[dst] = XmlIn.int_attr (cx, "srcOrd", 0);
                    }
                    foreach (var list in children.values) list.sort ((a, b) => ords[a] - ords[b]);
                    enter (dm);
                    if (children.has_key (doc_id)) foreach (string cid in children[doc_id]) d.nodes.add (diagram_node (cid, pts, children, 0));
                    foreach (var r in rels.values) if (r.type == Ooxml.REL_DIAGRAM_DRAWING) drawing_path = r.target;
                    Xml.Node* dext = find_desc (root, "dataModelExt");
                    if (dext != null && drawing_path == null) {
                        string? rid2 = XmlIn.attr (dext, "relId");
                        if (rid2 != null) {
                            part = saved;
                            rels = saved_rels;
                            drawing_path = rel_target (rid2);
                        }
                    }
                    delete doc;
                }
            } catch (Error e) {
                part = saved;
                rels = saved_rels;
                return null;
            }
            part = saved;
            rels = saved_rels;
            if (drawing_path == null) foreach (var r in rels.values) if (r.type == Ooxml.REL_DIAGRAM_DRAWING) drawing_path = r.target;
            d.layout = DiagramLayout.from_ooxml (layout_uid, cat);
            d.layout_id = layout_uid ?? "";
            if (drawing_path != null) {
                try {
                    Xml.Doc* dd = load (drawing_path);
                    if (dd != null) {
                        enter (drawing_path);
                        var g = new GroupElement ();
                        var inner = new Xform ();
                        inner.sx = xf.sx;
                        inner.sy = xf.sy;
                        inner.tx = d.x;
                        inner.ty = d.y;
                        parse_tree (XmlIn.child (dd->get_root_element (), "spTree"), g.children, inner);
                        g.set_geometry (d.x, d.y, d.w, d.h);
                        if (g.children.size > 0) d.drawing = g;
                        delete dd;
                    }
                } catch (Error e) {
                    d.drawing = null;
                }
                part = saved;
                rels = saved_rels;
            }
            d.mark_pristine ();
            return d;
        }

        private DiagramNode diagram_node (string id, Gee.HashMap<string, Xml.Node*> pts, Gee.HashMap<string, Gee.ArrayList<string>> children, int depth) {
            var node = new DiagramNode ();
            Xml.Node* pt = pts[id];
            Xml.Node* t = XmlIn.child (pt, "t");
            if (t != null) {
                TextStyle? ls;
                node.text = parse_body (t, out ls);
            }
            Xml.Node* sf = XmlIn.find (pt, "spPr/solidFill");
            if (sf != null) node.color = color_child (sf);
            Xml.Node* bf = XmlIn.find (pt, "spPr/blipFill/blip");
            if (bf != null) {
                string mime;
                node.image = media (rid (bf, "embed"), out mime);
                node.image_mime = mime;
            }
            if (depth < 12 && children.has_key (id)) foreach (string c in children[id]) node.children.add (diagram_node (c, pts, children, depth + 1));
            return node;
        }

        private Element? parse_picture (Xml.Node* n, Xform xf) {
            Xml.Node* nv = XmlIn.child (n, "nvPicPr");
            if (hidden (nv)) return null;
            var media_el = parse_media (n, nv, xf);
            if (media_el != null) return media_el;
            Xml.Node* eq_ext = null;
            foreach (Xml.Node* e in XmlIn.elements (XmlIn.find (nv, "cNvPr/extLst"), "ext")) {
                if (XmlIn.attr (e, "uri") == Ooxml.EXT_EQUATION) eq_ext = XmlIn.child (e, "equation");
            }
            if (eq_ext != null) {
                var q = new EquationElement ();
                parse_nv (nv, q);
                parse_xfrm (XmlIn.find (n, "spPr/xfrm"), q, xf);
                q.latex = XmlIn.text (XmlIn.child (eq_ext, "latex"));
                q.mathml = XmlIn.text (XmlIn.child (eq_ext, "mathml"));
                q.color = XmlIn.text (XmlIn.child (eq_ext, "color"));
                string emime;
                q.image = media (rid (XmlIn.find (n, "blipFill/blip"), "embed"), out emime);
                q.image_mime = emime;
                if (q.description == q.latex) q.description = "";
                return q;
            }
            Xml.Node* bf = XmlIn.child (n, "blipFill");
            Xml.Node* blip = XmlIn.child (bf, "blip");
            string mime;
            var data = media (rid (blip, "embed"), out mime);
            if (data == null) return null;
            var img = new ImageElement (data, mime);
            parse_nv (nv, img);
            Xml.Node* src = XmlIn.child (bf, "srcRect");
            if (src != null) {
                img.crop_left = XmlIn.double_attr (src, "l", 0) / 100000;
                img.crop_top = XmlIn.double_attr (src, "t", 0) / 100000;
                img.crop_right = XmlIn.double_attr (src, "r", 0) / 100000;
                img.crop_bottom = XmlIn.double_attr (src, "b", 0) / 100000;
            }
            foreach (Xml.Node* c in XmlIn.elements (blip)) {
                switch (c->name) {
                    case "alphaModFix":
                        img.opacity = XmlIn.double_attr (c, "amt", 100000) / 100000;
                        break;
                    case "grayscl":
                        img.saturation = 0;
                        break;
                    case "lum":
                        img.brightness = XmlIn.double_attr (c, "bright", 0) / 100000;
                        img.contrast = XmlIn.double_attr (c, "contrast", 0) / 100000;
                        break;
                    default:
                        break;
                }
            }
            Xml.Node* ext = find_ext (blip);
            if (ext != null) {
                Xml.Node* fl = XmlIn.child (ext, "filters");
                if (fl != null) {
                    img.brightness = XmlIn.double_attr (fl, "brightness", img.brightness);
                    img.contrast = XmlIn.double_attr (fl, "contrast", img.contrast);
                    img.saturation = XmlIn.double_attr (fl, "saturation", img.saturation);
                    img.sepia = battr (fl, "sepia", false);
                    img.blur = XmlIn.double_attr (fl, "blur", 0);
                }
            }
            Xml.Node* sppr = XmlIn.child (n, "spPr");
            if (!parse_xfrm (XmlIn.child (sppr, "xfrm"), img, xf) && img.placeholder != PlaceholderKind.NONE) img.inherit_geometry = true;
            Xml.Node* prst = XmlIn.child (sppr, "prstGeom");
            if (prst != null && XmlIn.attr (prst, "prst") == "roundRect") {
                img.corner = 0.16667;
                Xml.Node* gd = XmlIn.find (prst, "avLst/gd");
                string f = XmlIn.attr (gd, "fmla") ?? "";
                if (f.has_prefix ("val ")) img.corner = double.parse (f.substring (4)) / 100000;
            }
            Xml.Node* ln = XmlIn.child (sppr, "ln");
            if (ln != null) {
                bool has;
                img.line = parse_line (ln, out has);
                if (!has) img.line.color = "";
            } else {
                img.line.color = "";
            }
            parse_effects (sppr, img);
            return img;
        }

        private Element? parse_frame (Xml.Node* n, Xform xf) {
            Xml.Node* nv = XmlIn.child (n, "nvGraphicFramePr");
            if (hidden (nv)) return null;
            Xml.Node* data = XmlIn.find (n, "graphic/graphicData");
            string uri = XmlIn.attr (data, "uri") ?? "";
            Element? e = null;
            if (uri == Ooxml.URI_TABLE) {
                Xml.Node* tbl = XmlIn.child (data, "tbl");
                if (tbl != null) e = parse_table (tbl);
            } else if (uri == Ooxml.URI_CHART) {
                string? target = rel_target (rid (XmlIn.child (data, "chart"), "id"));
                if (target != null) e = read_chart (target);
                if (e != null) {
                    var ch = (ChartElement) e;
                    ch.original = make_foreign (n, _("Chart"), xf);
                    foreign_count--;
                }
            } else if (uri == Ooxml.URI_DIAGRAM) {
                e = parse_diagram (n, data, xf);
            }
            if (e == null) {
                var f = make_foreign (n, uri == Ooxml.URI_OLE ? _("Embedded Object") : _("Object"), xf);
                Xml.Node* ole = find_desc (n, "oleObj");
                if (ole != null) {
                    f.label = XmlIn.attr (ole, "name") ?? XmlIn.attr (ole, "progId") ?? _("Embedded Object");
                    Xml.Node* pic = find_desc (ole, "pic");
                    if (pic != null) {
                        var prev = parse_picture (pic, xf);
                        if (prev != null) {
                            prev.set_geometry (f.x, f.y, f.w, f.h);
                            f.preview = prev;
                        }
                    }
                }
                return f;
            }
            parse_nv (nv, e);
            if (!parse_xfrm (XmlIn.child (n, "xfrm"), e, xf) && e.placeholder != PlaceholderKind.NONE) e.inherit_geometry = true;
            var chart_el = e as ChartElement;
            if (chart_el != null) chart_el.mark_pristine ();
            var t = e as TableElement;
            if (t != null) {
                double ox = t.x, oy = t.y;
                for (int i = 0; i < t.col_widths.size; i++) t.col_widths[i] = t.col_widths[i] * xf.sx;
                for (int i = 0; i < t.row_heights.size; i++) t.row_heights[i] = t.row_heights[i] * xf.sy;
                t.sync_size ();
                t.x = ox;
                t.y = oy;
            }
            return e;
        }

        private DiagramNode sg_node (Xml.Node* n) {
            var node = new DiagramNode ();
            TextStyle? ls;
            node.text = parse_body (n, out ls);
            node.color = XmlIn.attr (n, "color") ?? "";
            string? emb = rid (n, "embed");
            if (emb != null) {
                string mime;
                node.image = media (emb, out mime);
                node.image_mime = mime;
            }
            foreach (Xml.Node* c in XmlIn.elements (n, "node")) node.children.add (sg_node (c));
            return node;
        }

        private Element? parse_group (Xml.Node* n, Xform xf) {
            Xml.Node* nv = XmlIn.child (n, "nvGrpSpPr");
            if (hidden (nv)) return null;
            foreach (Xml.Node* e in XmlIn.elements (XmlIn.find (nv, "nvPr/extLst"), "ext")) {
                Xml.Node* dg = XmlIn.child (e, "diagram");
                if (XmlIn.attr (e, "uri") != Ooxml.EXT_URI || dg == null) continue;
                var d = new DiagramElement ();
                parse_nv (nv, d);
                parse_xfrm (XmlIn.find (n, "grpSpPr/xfrm"), d, xf);
                d.layout = DiagramLayout.from_ooxml (XmlIn.attr (dg, "layout"), null);
                d.colors = (DiagramColors) XmlIn.int_attr (dg, "colors", 0).clamp (0, 4);
                d.style = (DiagramStyle) XmlIn.int_attr (dg, "style", 0).clamp (0, 3);
                foreach (Xml.Node* c in XmlIn.elements (dg, "node")) d.nodes.add (sg_node (c));
                return d;
            }
            var g = new GroupElement ();
            parse_nv (nv, g);
            Xml.Node* x = XmlIn.find (n, "grpSpPr/xfrm");
            var inner = new Xform ();
            inner.sx = xf.sx;
            inner.sy = xf.sy;
            inner.tx = xf.tx;
            inner.ty = xf.ty;
            if (x != null) {
                parse_xfrm (x, g, xf);
                double ox = Ooxml.pt (lattr (XmlIn.child (x, "off"), "x", 0)), oy = Ooxml.pt (lattr (XmlIn.child (x, "off"), "y", 0));
                double ew = Ooxml.pt (lattr (XmlIn.child (x, "ext"), "cx", 0)), eh = Ooxml.pt (lattr (XmlIn.child (x, "ext"), "cy", 0));
                Xml.Node* cho = XmlIn.child (x, "chOff");
                Xml.Node* che = XmlIn.child (x, "chExt");
                double cx = cho != null ? Ooxml.pt (lattr (cho, "x", 0)) : ox, cy = cho != null ? Ooxml.pt (lattr (cho, "y", 0)) : oy;
                double cw = che != null ? Ooxml.pt (lattr (che, "cx", 0)) : ew, chh = che != null ? Ooxml.pt (lattr (che, "cy", 0)) : eh;
                double kx = cw > 0 ? ew / cw : 1, ky = chh > 0 ? eh / chh : 1;
                inner.sx = kx * xf.sx;
                inner.sy = ky * xf.sy;
                inner.tx = (ox - cx * kx) * xf.sx + xf.tx;
                inner.ty = (oy - cy * ky) * xf.sy + xf.ty;
            }
            parse_tree (n, g.children, inner);
            if (x == null) g.fit ();
            return g;
        }

        private TableElement parse_table (Xml.Node* tbl) {
            var t = new TableElement (0, 0, 0, 0);
            Xml.Node* pr = XmlIn.child (tbl, "tblPr");
            t.first_row = battr (pr, "firstRow", false);
            t.first_col = battr (pr, "firstCol", false);
            t.last_row = battr (pr, "lastRow", false);
            t.banded_rows = battr (pr, "bandRow", false);
            t.banded_cols = battr (pr, "bandCol", false);
            string sid = XmlIn.text (XmlIn.child (pr, "tableStyleId")).strip ();
            t.style_color = Ooxml.color_for_table_style (sid) ?? "accent1";
            bool border_known = false;
            Xml.Node* ext = find_ext (pr);
            if (ext != null) {
                Xml.Node* st = XmlIn.child (ext, "table");
                if (st != null) {
                    t.style_color = XmlIn.attr (st, "style") ?? t.style_color;
                    t.border.color = XmlIn.attr (st, "border") ?? "";
                    t.border.width = XmlIn.double_attr (st, "borderWidth", 1);
                    t.border.dash = DashKind.from_ooxml (XmlIn.attr (st, "borderDash") ?? "solid");
                    border_known = true;
                }
            }
            foreach (Xml.Node* gc in XmlIn.elements (XmlIn.child (tbl, "tblGrid"), "gridCol")) t.col_widths.add (Ooxml.pt (lattr (gc, "w", 0)));
            int cols = t.col_widths.size;
            foreach (Xml.Node* tr in XmlIn.elements (tbl, "tr")) {
                t.row_heights.add (Ooxml.pt (lattr (tr, "h", 0)));
                var row = new Gee.ArrayList<TableCell> ();
                foreach (Xml.Node* tc in XmlIn.elements (tr, "tc")) {
                    var cell = new TableCell ();
                    cell.col_span = int.max (1, XmlIn.int_attr (tc, "gridSpan", 1));
                    cell.row_span = int.max (1, XmlIn.int_attr (tc, "rowSpan", 1));
                    cell.covered = battr (tc, "hMerge", false) || battr (tc, "vMerge", false);
                    if (cell.covered) {
                        cell.col_span = 1;
                        cell.row_span = 1;
                    }
                    Xml.Node* body = XmlIn.child (tc, "txBody");
                    if (body != null) {
                        TextStyle? ls;
                        cell.text = parse_body (body, out ls);
                    }
                    Xml.Node* tcpr = XmlIn.child (tc, "tcPr");
                    cell.text.inset_left = Ooxml.pt (lattr (tcpr, "marL", 91440));
                    cell.text.inset_right = Ooxml.pt (lattr (tcpr, "marR", 91440));
                    cell.text.inset_top = Ooxml.pt (lattr (tcpr, "marT", 45720));
                    cell.text.inset_bottom = Ooxml.pt (lattr (tcpr, "marB", 45720));
                    string anchor = XmlIn.attr (tcpr, "anchor") ?? "t";
                    cell.anchor = anchor == "ctr" ? TextAnchor.MIDDLE : (anchor == "b" ? TextAnchor.BOTTOM : TextAnchor.TOP);
                    Xml.Node* sf = XmlIn.child (tcpr, "solidFill");
                    if (sf != null) cell.fill = color_child (sf);
                    if (!border_known) {
                        Xml.Node* lnl = XmlIn.child (tcpr, "lnL");
                        if (lnl != null) {
                            bool has;
                            var l = parse_line (lnl, out has);
                            if (has) {
                                t.border = l;
                                border_known = true;
                            }
                        }
                    }
                    if (cell.text.paragraphs.size == 0) cell.text.paragraphs.add (new Paragraph ());
                    row.add (cell);
                }
                while (row.size < cols) row.add (new TableCell ());
                while (row.size > cols && cols > 0) row.remove_at (row.size - 1);
                t.cells.add (row);
            }
            for (int r = 0; r < t.rows; r++) {
                for (int c = 0; c < t.cols; c++) {
                    var cl = t.cells[r][c];
                    if (cl.covered) continue;
                    cl.col_span = int.min (cl.col_span, t.cols - c);
                    cl.row_span = int.min (cl.row_span, t.rows - r);
                }
            }
            t.sync_size ();
            return t;
        }

        private static Gee.ArrayList<string> cache_strings (Xml.Node* n) {
            var list = new Gee.ArrayList<string> ();
            if (n == null) return list;
            Xml.Node* cache = null;
            foreach (Xml.Node* c in XmlIn.elements (n)) {
                switch (c->name) {
                    case "strRef": cache = XmlIn.child (c, "strCache"); break;
                    case "numRef": cache = XmlIn.child (c, "numCache"); break;
                    case "strLit": case "numLit": cache = c; break;
                    case "multiLvlStrRef": cache = XmlIn.find (c, "multiLvlStrCache/lvl"); break;
                    case "v": list.add (XmlIn.text (c)); return list;
                    default: break;
                }
                if (cache != null) break;
            }
            if (cache == null) return list;
            int count = XmlIn.int_attr (XmlIn.child (cache, "ptCount"), "val", 0);
            foreach (Xml.Node* pt in XmlIn.elements (cache, "pt")) count = int.max (count, XmlIn.int_attr (pt, "idx", 0) + 1);
            for (int i = 0; i < count; i++) list.add ("");
            foreach (Xml.Node* pt in XmlIn.elements (cache, "pt")) {
                int idx = XmlIn.int_attr (pt, "idx", 0);
                if (idx >= 0 && idx < count) list[idx] = XmlIn.text (XmlIn.child (pt, "v"));
            }
            return list;
        }

        private ChartElement? read_chart (string path) {
            Xml.Doc* doc = null;
            try {
                doc = load (path);
            } catch (Error e) {
                return null;
            }
            if (doc == null) return null;
            Xml.Node* space = doc->get_root_element ();
            Xml.Node* chart = XmlIn.child (space, "chart");
            Xml.Node* plot = XmlIn.child (chart, "plotArea");
            if (XmlIn.child (plot, "stockChart") != null) {
                delete doc;
                return read_engine_chart (path);
            }
            ChartElement? ch = null;
            var sec_ids = new Gee.HashSet<string> ();
            var ser_order = new Gee.HashMap<ChartSeries, int> ();
            var val_axes = new Gee.ArrayList<Xml.Node*> ();
            foreach (Xml.Node* ax in XmlIn.elements (plot, "valAx")) val_axes.add (ax);
            foreach (Xml.Node* ax in val_axes) {
                if (XmlIn.attr (XmlIn.child (ax, "axPos"), "val") == "r" && val_axes.size > 1) sec_ids.add (XmlIn.attr (XmlIn.child (ax, "axId"), "val") ?? "");
            }
            foreach (Xml.Node* c in XmlIn.elements (plot)) {
                ChartKind kind;
                SeriesKind skind = SeriesKind.AUTO;
                switch (c->name) {
                    case "barChart": case "bar3DChart":
                        kind = XmlIn.attr (XmlIn.child (c, "barDir"), "val") == "bar" ? ChartKind.BAR : ChartKind.COLUMN;
                        skind = SeriesKind.COLUMN;
                        break;
                    case "lineChart": case "line3DChart": case "stockChart":
                        kind = ChartKind.LINE;
                        skind = SeriesKind.LINE;
                        break;
                    case "radarChart":
                        kind = ChartKind.RADAR;
                        break;
                    case "pieChart": case "pie3DChart": case "ofPieChart":
                        kind = ChartKind.PIE;
                        break;
                    case "doughnutChart":
                        kind = ChartKind.DOUGHNUT;
                        break;
                    case "areaChart": case "area3DChart":
                        kind = ChartKind.AREA;
                        skind = SeriesKind.AREA;
                        break;
                    case "scatterChart":
                        kind = ChartKind.SCATTER;
                        break;
                    case "bubbleChart":
                        kind = ChartKind.BUBBLE;
                        break;
                    default:
                        continue;
                }
                bool first = ch == null;
                if (first) {
                    ch = new ChartElement (kind);
                    string grouping = XmlIn.attr (XmlIn.child (c, "grouping"), "val") ?? "";
                    ch.grouping = grouping == "stacked" ? ChartGrouping.STACKED : (grouping == "percentStacked" ? ChartGrouping.PERCENT : ChartGrouping.CLUSTERED);
                    if (kind == ChartKind.RADAR && XmlIn.attr (XmlIn.child (c, "radarStyle"), "val") == "filled") ch.grouping = ChartGrouping.STACKED;
                    string style = XmlIn.attr (XmlIn.child (c, "scatterStyle"), "val") ?? "";
                    if (style.has_prefix ("smooth")) ch.smooth = true;
                }
                bool secondary = false;
                foreach (Xml.Node* id in XmlIn.elements (c, "axId")) if (sec_ids.contains (XmlIn.attr (id, "val") ?? "")) secondary = true;
                Xml.Node* dl = XmlIn.child (c, "dLbls");
                if (dl != null && (battr (XmlIn.child (dl, "showVal"), "val", false) || battr (XmlIn.child (dl, "showPercent"), "val", false))) ch.data_labels = true;
                foreach (Xml.Node* ser in XmlIn.elements (c, "ser")) {
                    var names = cache_strings (XmlIn.child (ser, "tx"));
                    var s = new ChartSeries (names.size > 0 ? names[0] : _("Series %d").printf (ch.series.size + 1));
                    if (!first && skind != SeriesKind.AUTO) s.kind = skind;
                    ser_order[s] = XmlIn.int_attr (XmlIn.child (ser, "order"), "val", ch.series.size);
                    s.secondary = secondary;
                    Xml.Node* sppr = XmlIn.child (ser, "spPr");
                    Xml.Node* sf = XmlIn.child (sppr, "solidFill");
                    if (sf == null && (skind == SeriesKind.LINE || kind == ChartKind.SCATTER || kind == ChartKind.RADAR)) sf = XmlIn.find (sppr, "ln/solidFill");
                    if (sf != null) s.color = color_child (sf);
                    Xml.Node* cat = XmlIn.child (ser, "cat") ?? XmlIn.child (ser, "xVal");
                    if (ch.categories.size == 0 && cat != null) ch.categories.add_all (cache_strings (cat));
                    Xml.Node* val = XmlIn.child (ser, "val") ?? XmlIn.child (ser, "yVal");
                    read_numbers (val, s.values);
                    Xml.Node* bsz = XmlIn.child (ser, "bubbleSize");
                    if (bsz != null) read_numbers (bsz, s.sizes);
                    Xml.Node* tl = XmlIn.child (ser, "trendline");
                    if (tl != null) {
                        s.trend = TrendKind.from_ooxml (XmlIn.attr (XmlIn.child (tl, "trendlineType"), "val"));
                        if (s.trend == TrendKind.NONE) s.trend = TrendKind.LINEAR;
                        s.trend_order = XmlIn.int_attr (XmlIn.child (tl, "order"), "val", 2);
                        s.trend_period = XmlIn.int_attr (XmlIn.child (tl, "period"), "val", 2);
                        s.trend_equation = battr (XmlIn.child (tl, "dispEq"), "val", false);
                        s.trend_r2 = battr (XmlIn.child (tl, "dispRSqr"), "val", false);
                    }
                    if (battr (XmlIn.child (ser, "smooth"), "val", false)) ch.smooth = true;
                    Xml.Node* sdl = XmlIn.child (ser, "dLbls");
                    if (sdl != null && (battr (XmlIn.child (sdl, "showVal"), "val", false) || battr (XmlIn.child (sdl, "showPercent"), "val", false))) ch.data_labels = true;
                    ch.series.add (s);
                }
                if (kind.is_radial ()) break;
            }
            if (ch == null) {
                delete doc;
                return null;
            }
            if (ch.series.size > 1) {
                ch.series.sort ((a, b) => ser_order[a] - ser_order[b]);
                var main_kind = ch.series_kind (new ChartSeries (""));
                foreach (var se in ch.series) if (se.kind == main_kind) se.kind = SeriesKind.AUTO;
            }
            foreach (Xml.Node* ax in XmlIn.elements (plot)) {
                if (ax->name != "valAx" && ax->name != "catAx" && ax->name != "dateAx") continue;
                string id = XmlIn.attr (XmlIn.child (ax, "axId"), "val") ?? "";
                ChartAxis target;
                bool xy = ch.chart == ChartKind.SCATTER || ch.chart == ChartKind.BUBBLE;
                string pos = XmlIn.attr (XmlIn.child (ax, "axPos"), "val") ?? "";
                if (ax->name == "valAx" && sec_ids.contains (id)) target = ch.sec_axis;
                else if (ax->name == "valAx" && !(xy && (pos == "b" || pos == "t"))) target = ch.val_axis;
                else if (battr (XmlIn.child (ax, "delete"), "val", false) && target_is_secondary_cat (ax, sec_ids)) continue;
                else target = ch.cat_axis;
                read_axis (ax, target);
            }
            ch.gridlines = false;
            foreach (Xml.Node* ax in XmlIn.elements (plot, "valAx")) if (XmlIn.child (ax, "majorGridlines") != null) ch.gridlines = true;
            Xml.Node* title = XmlIn.child (chart, "title");
            if (title != null && !battr (XmlIn.child (chart, "autoTitleDeleted"), "val", false)) {
                var sb = new StringBuilder ();
                foreach (Xml.Node* p in XmlIn.elements (XmlIn.find (title, "tx/rich"), "p")) {
                    if (sb.len > 0) sb.append (" ");
                    foreach (Xml.Node* r in XmlIn.elements (p)) if (r->name == "r" || r->name == "fld") sb.append (XmlIn.text (XmlIn.child (r, "t")));
                }
                ch.title = sb.str;
            }
            Xml.Node* legend = XmlIn.child (chart, "legend");
            if (legend == null) {
                ch.legend = LegendPosition.NONE;
            } else {
                switch (XmlIn.attr (XmlIn.child (legend, "legendPos"), "val") ?? "r") {
                    case "b": ch.legend = LegendPosition.BOTTOM; break;
                    case "t": ch.legend = LegendPosition.TOP; break;
                    case "l": ch.legend = LegendPosition.LEFT; break;
                    default: ch.legend = LegendPosition.RIGHT; break;
                }
            }
            Xml.Node* defr = XmlIn.find (space, "txPr/p/pPr/defRPr");
            Xml.Node* tsf = XmlIn.child (defr, "solidFill");
            if (tsf != null) ch.text_color = color_child (tsf);
            delete doc;
            return ch;
        }

        private ChartElement? read_engine_chart (string path) {
            string? xml = null;
            try {
                xml = zip.read_text (path);
            } catch (Error e) {
                return null;
            }
            if (xml == null) return null;
            var spec = Singularity.Charts.DrawingML.read_chart (xml);
            if (spec == null) return null;
            return ChartBridge.from_spec (spec);
        }

        private Element? parse_chartex (Xml.Node* ac, Xml.Node* frame, Xform xf) {
            Xml.Node* data = XmlIn.find (frame, "graphic/graphicData");
            Xml.Node* cref = XmlIn.child (data, "chart");
            string? target = rel_target (rid (cref, "id"));
            if (target == null) return null;
            var ch = read_engine_chart (target);
            if (ch == null) return null;
            Xml.Node* nv = XmlIn.child (frame, "nvGraphicFramePr");
            parse_nv (nv, ch);
            parse_xfrm (XmlIn.child (frame, "xfrm"), ch, xf);
            ch.original = make_foreign (ac, _("Chart"), xf);
            foreign_count--;
            ch.mark_pristine ();
            return ch;
        }

        private static bool target_is_secondary_cat (Xml.Node* ax, Gee.Set<string> sec_ids) {
            return sec_ids.contains (XmlIn.attr (XmlIn.child (ax, "crossAx"), "val") ?? "");
        }

        private void read_numbers (Xml.Node* val, Gee.List<double?> into) {
            Xml.Node* vcache = null;
            foreach (Xml.Node* vc in XmlIn.elements (val)) {
                if (vc->name == "numRef") vcache = XmlIn.child (vc, "numCache");
                else if (vc->name == "numLit") vcache = vc;
            }
            if (vcache == null) return;
            int count = XmlIn.int_attr (XmlIn.child (vcache, "ptCount"), "val", 0);
            foreach (Xml.Node* pt in XmlIn.elements (vcache, "pt")) count = int.max (count, XmlIn.int_attr (pt, "idx", 0) + 1);
            for (int i = 0; i < count; i++) into.add (null);
            foreach (Xml.Node* pt in XmlIn.elements (vcache, "pt")) {
                int idx = XmlIn.int_attr (pt, "idx", 0);
                double v = 0;
                if (idx >= 0 && idx < count && double.try_parse (XmlIn.text (XmlIn.child (pt, "v")).strip (), out v)) into[idx] = v;
            }
        }

        private void read_axis (Xml.Node* ax, ChartAxis a) {
            Xml.Node* sc = XmlIn.child (ax, "scaling");
            double v = 0;
            string? mx = XmlIn.attr (XmlIn.child (sc, "max"), "val");
            string? mn = XmlIn.attr (XmlIn.child (sc, "min"), "val");
            if (mx != null && double.try_parse (mx, out v)) a.max = v;
            if (mn != null && double.try_parse (mn, out v)) a.min = v;
            string? lb = XmlIn.attr (XmlIn.child (sc, "logBase"), "val");
            if (lb != null && double.try_parse (lb, out v)) a.log_base = v;
            a.reverse = XmlIn.attr (XmlIn.child (sc, "orientation"), "val") == "maxMin";
            a.visible = !battr (XmlIn.child (ax, "delete"), "val", false);
            string? mu = XmlIn.attr (XmlIn.child (ax, "majorUnit"), "val");
            if (mu != null && double.try_parse (mu, out v)) a.major = v;
            Xml.Node* nf = XmlIn.child (ax, "numFmt");
            if (nf != null && !battr (nf, "sourceLinked", false)) {
                string f = XmlIn.attr (nf, "formatCode") ?? "";
                if (f != "General") a.format = f;
            }
            Xml.Node* t = XmlIn.child (ax, "title");
            if (t != null) {
                var sb = new StringBuilder ();
                foreach (Xml.Node* p in XmlIn.elements (XmlIn.find (t, "tx/rich"), "p")) {
                    if (sb.len > 0) sb.append (" ");
                    foreach (Xml.Node* r in XmlIn.elements (p)) if (r->name == "r" || r->name == "fld") sb.append (XmlIn.text (XmlIn.child (r, "t")));
                }
                a.title = sb.str;
            }
        }

        private LevelStyle parse_level (Xml.Node* n) {
            var l = new LevelStyle ();
            if (XmlIn.attr (n, "marL") != null) {
                l.margin = Ooxml.pt (lattr (n, "marL", 0));
                l.indent = Ooxml.pt (lattr (n, "indent", 0));
            } else if (XmlIn.attr (n, "indent") != null) {
                l.margin = 0;
                l.indent = Ooxml.pt (lattr (n, "indent", 0));
            }
            l.align = align_of (XmlIn.attr (n, "algn"));
            foreach (Xml.Node* c in XmlIn.elements (n)) {
                switch (c->name) {
                    case "lnSpc":
                        Xml.Node* pct = XmlIn.child (c, "spcPct");
                        if (pct != null) l.line_spacing = XmlIn.double_attr (pct, "val", 100000) / 100000;
                        break;
                    case "spcBef":
                        Xml.Node* pts = XmlIn.child (c, "spcPts");
                        if (pts != null) l.space_before = XmlIn.double_attr (pts, "val", 0) / 100;
                        break;
                    case "spcAft":
                        Xml.Node* pa = XmlIn.child (c, "spcPts");
                        if (pa != null) l.space_after = XmlIn.double_attr (pa, "val", 0) / 100;
                        break;
                    case "buNone":
                        l.bullet = BulletKind.NONE;
                        break;
                    case "buChar":
                        l.bullet = BulletKind.CHAR;
                        l.bullet_char = XmlIn.attr (c, "char") ?? "•";
                        break;
                    case "buAutoNum":
                        l.bullet = BulletKind.NUMBER;
                        break;
                    case "defRPr":
                        if (XmlIn.attr (c, "sz") != null) l.size = XmlIn.double_attr (c, "sz", 1800) / 100;
                        if (XmlIn.attr (c, "b") != null) l.bold = battr (c, "b", false) ? 1 : 0;
                        if (XmlIn.attr (c, "i") != null) l.italic = battr (c, "i", false) ? 1 : 0;
                        l.caps = XmlIn.attr (c, "cap") == "all";
                        Xml.Node* sf = XmlIn.child (c, "solidFill");
                        if (sf != null) l.color = color_child (sf);
                        string? tf = XmlIn.attr (XmlIn.child (c, "latin"), "typeface");
                        if (tf != null && tf != "") l.font = font_of (tf);
                        break;
                    default:
                        break;
                }
            }
            return l;
        }

        private TextStyle parse_lst (Xml.Node* n) {
            var ts = new TextStyle ();
            for (int i = 0; i < 9; i++) {
                Xml.Node* lv = XmlIn.child (n, "lvl%dpPr".printf (i + 1));
                if (lv != null) ts.levels[i] = parse_level (lv);
            }
            return ts;
        }

        private static TextAlign align_of (string? a) {
            switch (a) {
                case "l": return TextAlign.LEFT;
                case "ctr": return TextAlign.CENTER;
                case "r": return TextAlign.RIGHT;
                case "just": case "dist": case "justLow": case "thaiDist": return TextAlign.JUSTIFY;
                default: return TextAlign.INHERIT;
            }
        }

        private static string font_of (string tf) {
            if (tf.has_prefix ("+mj")) return "+mj-lt";
            if (tf.has_prefix ("+mn")) return "+mn-lt";
            return tf;
        }

        private void parse_rpr (Xml.Node* n, TextRun r) {
            if (n == null) return;
            if (XmlIn.attr (n, "b") != null) r.bold = battr (n, "b", false) ? 1 : 0;
            if (XmlIn.attr (n, "i") != null) r.italic = battr (n, "i", false) ? 1 : 0;
            string? u = XmlIn.attr (n, "u");
            if (u != null) r.underline = u == "none" ? 0 : 1;
            string? st = XmlIn.attr (n, "strike");
            if (st != null) r.strike = st == "noStrike" ? 0 : 1;
            if (XmlIn.attr (n, "sz") != null) r.size = XmlIn.double_attr (n, "sz", 1800) / 100;
            double bl = XmlIn.double_attr (n, "baseline", 0);
            r.baseline = bl > 0 ? 1 : (bl < 0 ? -1 : 0);
            foreach (Xml.Node* c in XmlIn.elements (n)) {
                switch (c->name) {
                    case "solidFill":
                        r.color = color_child (c);
                        break;
                    case "gradFill":
                        r.color = color_child (XmlIn.find (c, "gsLst/gs"));
                        break;
                    case "highlight":
                        r.highlight = color_child (c);
                        break;
                    case "latin":
                        string? tf = XmlIn.attr (c, "typeface");
                        if (tf != null && tf != "") r.font = font_of (tf);
                        break;
                    case "hlinkClick":
                        string act = XmlIn.attr (c, "action") ?? "";
                        string? t = rel_target (rid (c, "id"));
                        if (act.has_prefix ("ppaction://hlinksldjump") && t != null) {
                            r.link = "#part:" + t;
                            pending_links.add (r);
                        } else if (act.has_prefix ("ppaction://hlinkshowjump")) {
                            var ca = ClickAction.from_ppaction (act, null);
                            if (ca != null) r.link = LinkTarget.from_action (ca);
                        } else if (t != null) {
                            r.link = t;
                        }
                        break;
                    default:
                        break;
                }
            }
        }

        private TextBody parse_body (Xml.Node* tx, out TextStyle? list_style) {
            var b = new TextBody ();
            list_style = null;
            Xml.Node* pr = XmlIn.child (tx, "bodyPr");
            if (pr != null) {
                b.inset_left = Ooxml.pt (lattr (pr, "lIns", 91440));
                b.inset_top = Ooxml.pt (lattr (pr, "tIns", 45720));
                b.inset_right = Ooxml.pt (lattr (pr, "rIns", 91440));
                b.inset_bottom = Ooxml.pt (lattr (pr, "bIns", 45720));
                string? anchor = XmlIn.attr (pr, "anchor");
                if (anchor != null) {
                    b.anchor_set = true;
                    b.anchor = anchor == "ctr" ? TextAnchor.MIDDLE : (anchor == "b" ? TextAnchor.BOTTOM : TextAnchor.TOP);
                }
                b.wrap = XmlIn.attr (pr, "wrap") != "none";
                b.columns = int.max (1, XmlIn.int_attr (pr, "numCol", 1));
                string vert = XmlIn.attr (pr, "vert") ?? "horz";
                b.vertical = vert != "horz";
                if (XmlIn.child (pr, "normAutofit") != null) {
                    Xml.Node* na = XmlIn.child (pr, "normAutofit");
                    b.autofit = AutoFit.SHRINK;
                    b.font_scale = XmlIn.double_attr (na, "fontScale", 100000) / 100000;
                    b.line_reduction = XmlIn.double_attr (na, "lnSpcReduction", 0) / 100000;
                } else if (XmlIn.child (pr, "spAutoFit") != null) {
                    b.autofit = AutoFit.RESIZE;
                }
            }
            Xml.Node* lst = XmlIn.child (tx, "lstStyle");
            if (lst != null) {
                var ts = parse_lst (lst);
                if (!ts.is_empty ()) list_style = ts;
            }
            foreach (Xml.Node* pn in XmlIn.elements (tx, "p")) {
                var p = new Paragraph ();
                foreach (Xml.Node* c in XmlIn.elements (pn)) {
                    switch (c->name) {
                        case "pPr":
                            parse_ppr (c, p);
                            break;
                        case "r":
                            var r = new TextRun (XmlIn.text (XmlIn.child (c, "t")));
                            parse_rpr (XmlIn.child (c, "rPr"), r);
                            p.runs.add (r);
                            break;
                        case "fld":
                            var fr = new TextRun (XmlIn.text (XmlIn.child (c, "t")));
                            parse_rpr (XmlIn.child (c, "rPr"), fr);
                            string type = XmlIn.attr (c, "type") ?? "";
                            fr.field = type == "slidenum" ? "slidenum" : (type.has_prefix ("datetime") ? type : "");
                            p.runs.add (fr);
                            break;
                        case "br":
                            var br = new TextRun ("\v");
                            parse_rpr (XmlIn.child (c, "rPr"), br);
                            if (p.runs.size > 0 && p.runs[p.runs.size - 1].field == "" && p.runs[p.runs.size - 1].same_format (br)) p.runs[p.runs.size - 1].text += "\v";
                            else p.runs.add (br);
                            break;
                        case "endParaRPr":
                            parse_rpr (c, p.end_format);
                            break;
                        default:
                            break;
                    }
                }
                for (int i = p.runs.size - 1; i > 0; i--) {
                    var prev = p.runs[i - 1];
                    var cur = p.runs[i];
                    if (prev.field == "" && cur.field == "" && prev.text.has_suffix ("\v") && prev.same_format (cur)) {
                        prev.text += cur.text;
                        p.runs.remove_at (i);
                    }
                }
                b.paragraphs.add (p);
            }
            if (b.paragraphs.size == 0) b.paragraphs.add (new Paragraph ());
            return b;
        }

        private void parse_ppr (Xml.Node* n, Paragraph p) {
            p.level = XmlIn.int_attr (n, "lvl", 0).clamp (0, 8);
            p.align = align_of (XmlIn.attr (n, "algn"));
            foreach (Xml.Node* c in XmlIn.elements (n)) {
                switch (c->name) {
                    case "lnSpc":
                        Xml.Node* pct = XmlIn.child (c, "spcPct");
                        if (pct != null) p.line_spacing = XmlIn.double_attr (pct, "val", 100000) / 100000;
                        break;
                    case "spcBef":
                        Xml.Node* pts = XmlIn.child (c, "spcPts");
                        if (pts != null) p.space_before = XmlIn.double_attr (pts, "val", 0) / 100;
                        break;
                    case "spcAft":
                        Xml.Node* pa = XmlIn.child (c, "spcPts");
                        if (pa != null) p.space_after = XmlIn.double_attr (pa, "val", 0) / 100;
                        break;
                    case "buClr":
                        p.bullet_color = color_child (c);
                        break;
                    case "buNone":
                        p.bullet = BulletKind.NONE;
                        break;
                    case "buChar":
                        p.bullet = BulletKind.CHAR;
                        p.bullet_char = XmlIn.attr (c, "char") ?? "•";
                        break;
                    case "buAutoNum":
                        p.bullet = BulletKind.NUMBER;
                        p.number_style = NumberStyle.from_ooxml (XmlIn.attr (c, "type") ?? "arabicPeriod");
                        p.number_start = XmlIn.int_attr (c, "startAt", 1);
                        break;
                    default:
                        break;
                }
            }
        }
    }
}
