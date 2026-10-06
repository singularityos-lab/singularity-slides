namespace Singularity.Apps.Slides {

    public class PptxWriter {
        private class Part {
            public string name;
            public Bytes data;
            public string? content_type;

            public Part (string name, Bytes data, string? content_type) {
                this.name = name;
                this.data = data;
                this.content_type = content_type;
            }
        }

        private Presentation pres;
        public string main_content_type = Ooxml.CT_PRESENTATION;
        private Gee.ArrayList<Part> parts = new Gee.ArrayList<Part> ();
        private Gee.HashSet<string> media_exts = new Gee.HashSet<string> ();
        private Gee.HashMap<string, string> media = new Gee.HashMap<string, string> ();
        private Gee.HashMap<Layout, string> layout_parts = new Gee.HashMap<Layout, string> ();
        private OoxmlRels rels;
        private Gee.HashMap<Element, int> ids = new Gee.HashMap<Element, int> ();
        private int root_id = 1;
        private int media_count = 0;
        private int chart_count = 0;
        private int field_count = 0;
        private int ctn = 0;
        private string current_part = "";
        private Gee.HashSet<string> used_names = new Gee.HashSet<string> ();
        private Gee.HashMap<ForeignPart, string> foreign_written = new Gee.HashMap<ForeignPart, string> ();
        private Gee.HashMap<int, string> slide_part_by_uid = new Gee.HashMap<int, string> ();
        private Gee.HashMap<int, int64?> sld_id_by_uid = new Gee.HashMap<int, int64?> ();
        private Gee.HashMap<string, int> author_ids = new Gee.HashMap<string, int> ();
        private Gee.ArrayList<string> author_order = new Gee.ArrayList<string> ();
        private Gee.HashMap<string, int> author_last = new Gee.HashMap<string, int> ();
        private Gee.HashMap<string, int> custom_show_ids = new Gee.HashMap<string, int> ();
        private int comment_count = 0;
        private int ink_count = 0;
        private int media_file_count = 0;
        private Gee.HashMap<Bytes, string> media_files = new Gee.HashMap<Bytes, string> ();
        private Slide? writing_slide = null;

        private Gee.HashMap<int, int64?>? numbers = null;

        private int64 slide_number (int index) {
            if (numbers == null) {
                numbers = new Gee.HashMap<int, int64?> ();
                var used = new Gee.HashSet<int64?> ();
                for (int i = 0; i < pres.slides.size; i++) {
                    int64 n = 255 + (int64) pres.slides[i].uid;
                    if (pres.slides[i].uid < 1 || n >= 2147483648 || used.contains (n)) n = -1;
                    if (n > 0) used.add (n);
                    numbers[i] = n;
                }
                int64 next = 256;
                for (int i = 0; i < pres.slides.size; i++) {
                    if (numbers[i] > 0) continue;
                    while (used.contains (next)) next++;
                    numbers[i] = next;
                    used.add (next);
                }
            }
            return numbers[index];
        }

        public PptxWriter (Presentation pres) {
            this.pres = pres;
        }

        private void add_part (string name, string content, string? type) {
            parts.add (new Part (name, new Bytes (content.data), type));
            used_names.add (name);
        }

        private void add_bytes_part (string name, Bytes data, string? type) {
            parts.add (new Part (name, data, type));
            used_names.add (name);
        }

        public static string relative (string from_part, string to_part) {
            var a = from_part.split ("/");
            var b = to_part.split ("/");
            int common = 0;
            while (common < a.length - 1 && common < b.length - 1 && a[common] == b[common]) common++;
            var sb = new StringBuilder ();
            for (int i = common; i < a.length - 1; i++) sb.append ("../");
            for (int i = common; i < b.length; i++) {
                if (i > common) sb.append ("/");
                sb.append (b[i]);
            }
            return sb.str;
        }

        private string unique_name (string wanted) {
            if (!used_names.contains (wanted)) return wanted;
            int dot = wanted.last_index_of (".");
            string stem = dot > 0 ? wanted.substring (0, dot) : wanted;
            string ext = dot > 0 ? wanted.substring (dot) : "";
            int n = 2;
            while (used_names.contains ("%s_%d%s".printf (stem, n, ext))) n++;
            return "%s_%d%s".printf (stem, n, ext);
        }

        private string write_foreign_part (ForeignPart fp) {
            if (foreign_written.has_key (fp)) return foreign_written[fp];
            string name = unique_name (fp.path);
            foreign_written[fp] = name;
            used_names.add (name);
            var r = new OoxmlRels ();
            var map = new Gee.HashMap<string, string> ();
            foreach (var fr in fp.rels) {
                string? id = emit_rel (r, name, fr);
                if (id != null) map[fr.id] = id;
            }
            Bytes data = fp.data;
            bool xml = fp.content_type.has_suffix ("xml") || fp.path.has_suffix (".xml");
            if (xml && map.size > 0) {
                string? remapped = remap_xml (fp.text (), map, -1, null, null);
                if (remapped != null) data = new Bytes (("<?xml version=\"1.0\" encoding=\"UTF-8\" standalone=\"yes\"?>\n" + remapped).data);
            }
            parts.add (new Part (name, data, fp.content_type != "" ? fp.content_type : "application/octet-stream"));
            add_rels (name, r);
            return name;
        }

        private string? emit_rel (OoxmlRels r, string from_part, ForeignRel fr) {
            if (fr.external) return r.add (fr.type, fr.target, true);
            if (fr.part != null) {
                string path = write_foreign_part (fr.part);
                return r.add (fr.type, relative (from_part, path));
            }
            if (fr.target.has_prefix ("uid:")) {
                int uid = int.parse (fr.target.substring (4));
                if (slide_part_by_uid.has_key (uid)) return r.add (fr.type, relative (from_part, slide_part_by_uid[uid]));
            }
            return null;
        }

        private static void remap_node (Xml.Node* n, Gee.Map<string, string> map) {
            for (Xml.Attr* a = n->properties; a != null; a = a->next) {
                if (a->ns != null && a->ns->href == Ooxml.NS_R && a->children != null) {
                    string v = a->children->content;
                    if (map.has_key (v)) n->set_ns_prop (a->ns, a->name, map[v]);
                    else if (v != "") n->set_ns_prop (a->ns, a->name, "");
                }
            }
            for (Xml.Node* c = n->children; c != null; c = c->next) {
                if (c->type == Xml.ElementType.ELEMENT_NODE) remap_node (c, map);
            }
        }

        private static void set_xfrm (Xml.Node* x, Element e) {
            Xml.Node* off = XmlIn.child (x, "off");
            Xml.Node* ext = XmlIn.child (x, "ext");
            if (off != null) {
                off->set_prop ("x", Ooxml.emu (e.x).to_string ());
                off->set_prop ("y", Ooxml.emu (e.y).to_string ());
            }
            if (ext != null) {
                ext->set_prop ("cx", Ooxml.emu (double.max (e.w, 0)).to_string ());
                ext->set_prop ("cy", Ooxml.emu (double.max (e.h, 0)).to_string ());
            }
            double r = e.rotation % 360;
            if (r < 0) r += 360;
            if (r != 0) x->set_prop ("rot", ((int64) Math.round (r * 60000)).to_string ());
            else if (XmlIn.attr (x, "rot") != null) x->unset_prop ("rot");
        }

        private string? remap_xml (string xml, Gee.Map<string, string> map, int id, Element? geometry, string? name) {
            Xml.Doc* doc = Xml.Parser.read_memory (xml, xml.length, null, null, Xml.ParserOption.NONET | Xml.ParserOption.HUGE | Xml.ParserOption.NOERROR | Xml.ParserOption.NOWARNING);
            if (doc == null) return null;
            Xml.Node* root = doc->get_root_element ();
            if (root == null) {
                delete doc;
                return null;
            }
            remap_node (root, map);
            if (id >= 0) {
                var list = new Gee.ArrayList<Xml.Node*> ();
                all_named (root, "cNvPr", list);
                foreach (Xml.Node* c in list) c->set_prop ("id", id.to_string ());
                if (name != null) foreach (Xml.Node* c in list) c->set_prop ("name", name);
            }
            if (geometry != null) {
                var list = new Gee.ArrayList<Xml.Node*> ();
                all_named (root, "xfrm", list);
                foreach (Xml.Node* x in list) {
                    if (x->parent != null && (x->parent->name == "grpSpPr")) continue;
                    set_xfrm (x, geometry);
                }
            }
            string mem;
            doc->dump_memory (out mem);
            delete doc;
            if (mem.has_prefix ("<?xml")) {
                int end = mem.index_of ("?>");
                if (end >= 0) mem = mem.substring (end + 2);
            }
            return mem.strip ();
        }

        private static void all_named (Xml.Node* n, string name, Gee.List<Xml.Node*> list) {
            if (n->name == name) {
                list.add (n);
                return;
            }
            for (Xml.Node* c = n->children; c != null; c = c->next) {
                if (c->type == Xml.ElementType.ELEMENT_NODE) all_named (c, name, list);
            }
        }

        private void foreign (XmlOut x, ForeignElement f, Element? owner = null) {
            var map = new Gee.HashMap<string, string> ();
            foreach (var fr in f.rels) {
                if (fr.type == Ooxml.REL_DIAGRAM_DATA && fr.part != null) continue;
                string? id = emit_rel (rels, current_part, fr);
                if (id != null) map[fr.id] = id;
            }
            foreach (var fr in f.rels) {
                if (fr.type != Ooxml.REL_DIAGRAM_DATA || fr.part == null) continue;
                var data_part = fr.part;
                string txt = data_part.text ();
                bool patched = false;
                foreach (var e in map.entries) {
                    string from = "relId=\"%s\"".printf (e.key);
                    if (txt.contains (from)) {
                        txt = txt.replace (from, "relId=\"%s\"".printf (e.value));
                        patched = true;
                    }
                }
                if (patched) {
                    var copy = new ForeignPart (data_part.path, new Bytes (txt.data), data_part.content_type);
                    copy.rels.add_all (data_part.rels);
                    data_part = copy;
                }
                var tmp = new ForeignRel (fr.id, fr.type, fr.target, false);
                tmp.part = data_part;
                string? id = emit_rel (rels, current_part, tmp);
                if (id != null) map[fr.id] = id;
            }
            var e = owner ?? f;
            bool moved = Math.fabs (e.x - f.orig_x) > 0.01 || Math.fabs (e.y - f.orig_y) > 0.01 || Math.fabs (e.w - f.orig_w) > 0.01 || Math.fabs (e.h - f.orig_h) > 0.01 || Math.fabs (e.rotation - f.orig_rot) > 0.01;
            string? xml = remap_xml (f.xml, map, id_of (e), moved ? e : null, e.name != "" ? e.name : null);
            if (xml != null) x.raw (xml);
        }

        private void add_rels (string part, OoxmlRels r) {
            if (!r.is_empty ()) add_part (OoxmlRels.rels_path (part), r.to_xml (), null);
        }

        public uint8[] write () throws Error {
            var pres_rels = new OoxmlRels ();
            var master_ids = new Gee.ArrayList<string> ();
            var slide_rids = new Gee.ArrayList<string> ();
            int64 next_id = 2147483648;
            int layout_no = 0;
            int theme_no = 0;
            for (int si = 0; si < pres.slides.size; si++) {
                slide_part_by_uid[pres.slides[si].uid] = "ppt/slides/slide%d.xml".printf (si + 1);
                sld_id_by_uid[pres.slides[si].uid] = slide_number (si);
                used_names.add ("ppt/slides/slide%d.xml".printf (si + 1));
            }
            for (int i = 0; i < pres.custom_shows.size; i++) custom_show_ids[pres.custom_shows[i].name] = i;
            foreach (var m in pres.masters) {
                foreach (var l in m.layouts) {
                    layout_no++;
                    layout_parts[l] = "ppt/slideLayouts/slideLayout%d.xml".printf (layout_no);
                }
            }
            for (int mi = 0; mi < pres.masters.size; mi++) {
                var m = pres.masters[mi];
                theme_no++;
                string theme_part = "ppt/theme/theme%d.xml".printf (theme_no);
                add_part (theme_part, theme_xml (m.theme), Ooxml.CT_THEME);
                string master_part = "ppt/slideMasters/slideMaster%d.xml".printf (mi + 1);
                int64 master_id = next_id++;
                var layout_ids = new Gee.ArrayList<int64?> ();
                for (int li = 0; li < m.layouts.size; li++) layout_ids.add (next_id++);
                var mrels = new OoxmlRels ();
                var layout_rids = new Gee.ArrayList<string> ();
                foreach (var l in m.layouts) layout_rids.add (mrels.add (Ooxml.REL_LAYOUT, "../slideLayouts/" + Path.get_basename (layout_parts[l])));
                mrels.add (Ooxml.REL_THEME, "../theme/" + Path.get_basename (theme_part));
                rels = mrels;
                current_part = master_part;
                add_part (master_part, master_xml (m, layout_ids, layout_rids), Ooxml.CT_MASTER);
                add_rels (master_part, mrels);
                foreach (var l in m.layouts) {
                    var lrels = new OoxmlRels ();
                    lrels.add (Ooxml.REL_MASTER, "../slideMasters/" + Path.get_basename (master_part));
                    rels = lrels;
                    current_part = layout_parts[l];
                    add_part (layout_parts[l], layout_xml (l), Ooxml.CT_LAYOUT);
                    add_rels (layout_parts[l], lrels);
                }
                master_ids.add ("%s|%s".printf (master_id.to_string (), pres_rels.add (Ooxml.REL_MASTER, "slideMasters/" + Path.get_basename (master_part))));
            }
            theme_no++;
            string notes_theme = "ppt/theme/theme%d.xml".printf (theme_no);
            add_part (notes_theme, theme_xml (pres.theme), Ooxml.CT_THEME);
            string notes_master = "ppt/notesMasters/notesMaster1.xml";
            var nmrels = new OoxmlRels ();
            nmrels.add (Ooxml.REL_THEME, "../theme/" + Path.get_basename (notes_theme));
            add_part (notes_master, notes_master_xml (), Ooxml.CT_NOTES_MASTER);
            add_rels (notes_master, nmrels);
            string notes_rid = pres_rels.add (Ooxml.REL_NOTES_MASTER, "notesMasters/notesMaster1.xml");
            for (int si = 0; si < pres.slides.size; si++) {
                var s = pres.slides[si];
                string part = "ppt/slides/slide%d.xml".printf (si + 1);
                var srels = new OoxmlRels ();
                var layout = pres.layout_for (s);
                if (layout == null) layout = pres.master.layouts.size > 0 ? pres.master.layouts[0] : null;
                if (layout != null) srels.add (Ooxml.REL_LAYOUT, "../slideLayouts/" + Path.get_basename (layout_parts[layout]));
                rels = srels;
                current_part = part;
                writing_slide = s;
                add_part (part, slide_xml (s), Ooxml.CT_SLIDE);
                writing_slide = null;
                if (s.comments.size > 0) {
                    comment_count++;
                    string cp = "ppt/comments/comment%d.xml".printf (comment_count);
                    add_part (cp, comments_xml (s), Ooxml.CT_COMMENTS);
                    srels.add (Ooxml.REL_COMMENTS, "../comments/" + Path.get_basename (cp));
                }
                if (s.notes != "") {
                    string np = "ppt/notesSlides/notesSlide%d.xml".printf (si + 1);
                    srels.add (Ooxml.REL_NOTES_SLIDE, "../notesSlides/" + Path.get_basename (np));
                    var nrels = new OoxmlRels ();
                    nrels.add (Ooxml.REL_NOTES_MASTER, "../notesMasters/notesMaster1.xml");
                    nrels.add (Ooxml.REL_SLIDE, "../slides/" + Path.get_basename (part));
                    add_part (np, notes_xml (s), Ooxml.CT_NOTES_SLIDE);
                    add_rels (np, nrels);
                }
                add_rels (part, srels);
                slide_rids.add (pres_rels.add (Ooxml.REL_SLIDE, "slides/" + Path.get_basename (part)));
            }
            if (author_order.size > 0) {
                add_part ("ppt/commentAuthors.xml", authors_xml (), Ooxml.CT_COMMENT_AUTHORS);
                pres_rels.add (Ooxml.REL_COMMENT_AUTHORS, "commentAuthors.xml");
            }
            rels = pres_rels;
            current_part = "ppt/presentation.xml";
            foreach (var fr in pres.extra_parts) emit_rel (pres_rels, "ppt/presentation.xml", fr);
            pres_rels.add (Ooxml.REL_PRES_PROPS, "presProps.xml");
            pres_rels.add (Ooxml.REL_VIEW_PROPS, "viewProps.xml");
            pres_rels.add (Ooxml.REL_THEME, "theme/theme1.xml");
            pres_rels.add (Ooxml.REL_TABLE_STYLES, "tableStyles.xml");
            rels = pres_rels;
            current_part = "ppt/presentation.xml";
            add_part ("ppt/presentation.xml", presentation_xml (master_ids, slide_rids, notes_rid), main_content_type);
            add_rels ("ppt/presentation.xml", pres_rels);
            add_part ("ppt/presProps.xml", pres_props_xml (), Ooxml.CT_PRES_PROPS);
            add_part ("ppt/viewProps.xml", view_props_xml (), Ooxml.CT_VIEW_PROPS);
            add_part ("ppt/tableStyles.xml", "<?xml version=\"1.0\" encoding=\"UTF-8\" standalone=\"yes\"?>\n<a:tblStyleLst xmlns:a=\"%s\" def=\"%s\"/>".printf (Ooxml.NS_A, Ooxml.TABLE_STYLES[0]), Ooxml.CT_TABLE_STYLES);
            add_part ("docProps/core.xml", core_xml (), Ooxml.CT_CORE);
            add_part ("docProps/app.xml", app_xml (), Ooxml.CT_APP);
            var root = new OoxmlRels ();
            root.add (Ooxml.REL_OFFICE_DOCUMENT, "ppt/presentation.xml");
            root.add (Ooxml.REL_CORE, "docProps/core.xml");
            root.add (Ooxml.REL_APP, "docProps/app.xml");
            add_part ("_rels/.rels", root.to_xml (), null);

            var zip = new ZipWriter ();
            zip.add_text ("[Content_Types].xml", content_types_xml ());
            foreach (var p in parts) {
                bool compress = !p.name.has_prefix ("ppt/media/") || p.name.has_suffix (".svg") || p.name.has_suffix (".bmp");
                zip.add (p.name, p.data.get_data (), compress);
            }
            return zip.finish ();
        }

        private string content_types_xml () {
            var x = new XmlOut ();
            x.start ("Types").a ("xmlns", Ooxml.NS_CT);
            x.start ("Default").a ("Extension", "rels").a ("ContentType", Ooxml.CT_RELS).end ();
            x.start ("Default").a ("Extension", "xml").a ("ContentType", "application/xml").end ();
            foreach (string e in media_exts) x.start ("Default").a ("Extension", e).a ("ContentType", Ooxml.mime_for_ext (e)).end ();
            foreach (var p in parts) {
                if (p.content_type == null) continue;
                x.start ("Override").a ("PartName", "/" + p.name).a ("ContentType", p.content_type).end ();
            }
            x.end ();
            return x.finish ();
        }

        private static string iso_now () {
            return new DateTime.now_utc ().format ("%Y-%m-%dT%H:%M:%SZ");
        }

        private string core_xml () {
            var pr = pres.properties;
            var x = new XmlOut ();
            x.start ("cp:coreProperties")
                .a ("xmlns:cp", "http://schemas.openxmlformats.org/package/2006/metadata/core-properties")
                .a ("xmlns:dc", "http://purl.org/dc/elements/1.1/")
                .a ("xmlns:dcterms", "http://purl.org/dc/terms/")
                .a ("xmlns:dcmitype", "http://purl.org/dc/dcmitype/")
                .a ("xmlns:xsi", "http://www.w3.org/2001/XMLSchema-instance");
            if (pr.title != "") x.element ("dc:title", pr.title);
            if (pr.subject != "") x.element ("dc:subject", pr.subject);
            if (pr.author != "") x.element ("dc:creator", pr.author);
            if (pr.keywords != "") x.element ("cp:keywords", pr.keywords);
            if (pr.author != "") x.element ("cp:lastModifiedBy", pr.author);
            x.start ("dcterms:created").a ("xsi:type", "dcterms:W3CDTF").text (pr.created != "" ? pr.created : iso_now ()).end ();
            x.start ("dcterms:modified").a ("xsi:type", "dcterms:W3CDTF").text (pr.modified != "" ? pr.modified : iso_now ()).end ();
            x.end ();
            return x.finish ();
        }

        private string app_xml () {
            var x = new XmlOut ();
            x.start ("Properties")
                .a ("xmlns", "http://schemas.openxmlformats.org/officeDocument/2006/extended-properties")
                .a ("xmlns:vt", "http://schemas.openxmlformats.org/officeDocument/2006/docPropsVTypes");
            x.element ("Application", "Singularity Slides");
            x.element ("PresentationFormat", pres.aspect_label ());
            x.element ("Slides", pres.slides.size.to_string ());
            int notes = 0, hidden = 0;
            foreach (var s in pres.slides) {
                if (s.notes != "") notes++;
                if (s.hidden) hidden++;
            }
            x.element ("Notes", notes.to_string ());
            x.element ("HiddenSlides", hidden.to_string ());
            x.element ("AppVersion", "16.0000");
            x.end ();
            return x.finish ();
        }

        private string presentation_xml (Gee.List<string> master_ids, Gee.List<string> slide_rids, string notes_rid) {
            var x = new XmlOut ();
            x.start ("p:presentation").a ("xmlns:a", Ooxml.NS_A).a ("xmlns:r", Ooxml.NS_R).a ("xmlns:p", Ooxml.NS_P).a ("saveSubsetFonts", "1");
            x.start ("p:sldMasterIdLst");
            foreach (string mid in master_ids) {
                string[] parts2 = mid.split ("|");
                x.start ("p:sldMasterId").a ("id", parts2[0]).a ("r:id", parts2[1]).end ();
            }
            x.end ();
            x.start ("p:notesMasterIdLst").start ("p:notesMasterId").a ("r:id", notes_rid).end ().end ();
            if (slide_rids.size > 0) {
                x.start ("p:sldIdLst");
                for (int i = 0; i < slide_rids.size; i++) x.start ("p:sldId").ai ("id", slide_number (i)).a ("r:id", slide_rids[i]).end ();
                x.end ();
            }
            x.start ("p:sldSz").ai ("cx", Ooxml.emu (pres.width)).ai ("cy", Ooxml.emu (pres.height));
            string label = pres.aspect_label ();
            if (label == "4:3") x.a ("type", "screen4x3");
            else if (label == "16:10") x.a ("type", "screen16x10");
            x.end ();
            x.start ("p:notesSz").ai ("cx", 6858000).ai ("cy", 9144000).end ();
            extras_named (x, pres.extras, { "smartTags" });
            embedded_fonts (x);
            if (pres.custom_shows.size > 0) {
                x.start ("p:custShowLst");
                for (int i = 0; i < pres.custom_shows.size; i++) {
                    var cs = pres.custom_shows[i];
                    x.start ("p:custShow").a ("name", cs.name).ai ("id", i).start ("p:sldLst");
                    foreach (int uid in cs.slides) {
                        if (!slide_part_by_uid.has_key (uid)) continue;
                        x.start ("p:sld").a ("r:id", rels.add (Ooxml.REL_SLIDE, relative ("ppt/presentation.xml", slide_part_by_uid[uid]))).end ();
                    }
                    x.end ().end ();
                }
                x.end ();
            }
            extras_named (x, pres.extras, { "photoAlbum", "custDataLst", "kinsoku" });
            lst_style (x, pres.master.other_style, "p:defaultTextStyle", true);
            extras_named (x, pres.extras, { "modifyVerifier" });
            bool sections = pres.has_sections ();
            var exts = new Gee.ArrayList<ForeignElement> ();
            foreach (var e in pres.extras) if (e.label == "ext") exts.add (e);
            if (pres.footer_text != "" || pres.date_text != "" || sections || exts.size > 0) {
                x.start ("p:extLst");
                if (sections) {
                    x.start ("p:ext").a ("uri", Ooxml.EXT_SECTIONS);
                    x.start ("p14:sectionLst").a ("xmlns:p14", Ooxml.NS_P14);
                    for (int i = 0; i < pres.slides.size; i++) {
                        var sm = pres.slides[i].section;
                        if (sm == null && i > 0) continue;
                        x.start ("p14:section").a ("name", sm != null ? sm.name : _("Default Section")).a ("id", sm != null ? sm.id : "{" + Uuid.string_random ().up () + "}");
                        x.start ("p14:sldIdLst");
                        int end = pres.section_end (i);
                        for (int k = i; k < end; k++) x.start ("p14:sldId").ai ("id", slide_number (k)).end ();
                        x.end ().end ();
                    }
                    x.end ().end ();
                }
                foreach (var e in exts) extra (x, e);
                if (pres.footer_text != "" || pres.date_text != "") {
                    x.start ("p:ext").a ("uri", Ooxml.EXT_URI);
                    x.start ("sg:headerFooter").a ("xmlns:sg", Ooxml.NS_SG).a ("footer", pres.footer_text).a ("date", pres.date_text).end ();
                    x.end ();
                }
                x.end ();
            }
            x.end ();
            return x.finish ();
        }

        private void extras_named (XmlOut x, Gee.List<ForeignElement> list, string[] names) {
            foreach (var e in list) {
                foreach (string n in names) if (e.label == n) extra (x, e);
            }
        }

        private void extra (XmlOut x, ForeignElement f) {
            var map = new Gee.HashMap<string, string> ();
            foreach (var fr in f.rels) {
                string? id = emit_rel (rels, current_part, fr);
                if (id != null) map[fr.id] = id;
            }
            string? xml = remap_xml (f.xml, map, -1, null, null);
            if (xml != null) x.raw (xml);
        }

        private void embedded_fonts (XmlOut x) {
            if (!pres.embed_fonts || pres.fonts.size == 0) return;
            x.start ("p:embeddedFontLst");
            int n = 0;
            foreach (var f in pres.fonts) {
                x.start ("p:embeddedFont");
                x.start ("p:font").a ("typeface", f.family).end ();
                Bytes?[] faces = { f.regular, f.bold, f.italic, f.bold_italic };
                string[] tags = { "p:regular", "p:bold", "p:italic", "p:boldItalic" };
                for (int i = 0; i < 4; i++) {
                    if (faces[i] == null) continue;
                    n++;
                    string name = "ppt/fonts/font%d.fntdata".printf (n);
                    add_bytes_part (name, faces[i], "application/x-fontdata");
                    x.start (tags[i]).a ("r:id", rels.add (Ooxml.REL_FONT, "fonts/font%d.fntdata".printf (n))).end ();
                }
                x.end ();
            }
            x.end ();
        }

        private string pres_props_xml () {
            var x = new XmlOut ();
            x.start ("p:presentationPr").a ("xmlns:a", Ooxml.NS_A).a ("xmlns:r", Ooxml.NS_R).a ("xmlns:p", Ooxml.NS_P);
            x.start ("p:showPr").a ("loop", pres.loop ? "1" : "0").a ("useTimings", pres.use_timings ? "1" : "0");
            if (!pres.show_narration) x.a ("showNarration", "0");
            if (!pres.show_animation) x.a ("showAnimation", "0");
            if (pres.show_kind == 2) x.empty ("p:kiosk");
            else if (pres.show_kind == 1) x.start ("p:browse").a ("showScrollbar", "1").end ();
            else x.empty ("p:present");
            if (pres.show_custom != "" && custom_show_ids.has_key (pres.show_custom)) x.start ("p:custShow").ai ("id", custom_show_ids[pres.show_custom]).end ();
            else if (pres.show_from > 0 && pres.show_to >= pres.show_from) x.start ("p:sldRg").ai ("st", pres.show_from).ai ("end", pres.show_to).end ();
            else x.empty ("p:sldAll");
            if (pres.pen_color != "") {
                x.start ("p:penClr");
                x.start ("a:srgbClr").a ("val", hex6 (pres.pen_color)).end ();
                x.end ();
            }
            x.end ();
            x.end ();
            return x.finish ();
        }

        private string view_props_xml () {
            var x = new XmlOut ();
            x.start ("p:viewPr").a ("xmlns:a", Ooxml.NS_A).a ("xmlns:r", Ooxml.NS_R).a ("xmlns:p", Ooxml.NS_P);
            x.start ("p:normalViewPr").start ("p:restoredLeft").a ("sz", "15620").end ().start ("p:restoredTop").a ("sz", "94660").end ().end ();
            x.start ("p:gridSpacing").ai ("cx", 76200).ai ("cy", 76200).end ();
            x.end ();
            return x.finish ();
        }

        private static string hex6 (string spec) {
            string h = spec.has_prefix ("#") ? spec.substring (1) : spec;
            if (h.length == 3) h = "%c%c%c%c%c%c".printf (h[0], h[0], h[1], h[1], h[2], h[2]);
            if (h.length > 6) h = h.substring (0, 6);
            return h.up ();
        }

        private string theme_xml (Theme t) {
            var x = new XmlOut ();
            x.start ("a:theme").a ("xmlns:a", Ooxml.NS_A).a ("name", t.name);
            x.start ("a:themeElements");
            x.start ("a:clrScheme").a ("name", t.name);
            foreach (string k in Theme.SCHEME_KEYS) {
                x.start ("a:" + k);
                x.start ("a:srgbClr").a ("val", hex6 (t.scheme_hex (k))).end ();
                x.end ();
            }
            x.end ();
            x.start ("a:fontScheme").a ("name", t.name);
            foreach (string kind in new string[] { "majorFont", "minorFont" }) {
                x.start ("a:" + kind);
                x.start ("a:latin").a ("typeface", kind == "majorFont" ? t.major_font : t.minor_font).end ();
                x.start ("a:ea").a ("typeface", "").end ();
                x.start ("a:cs").a ("typeface", "").end ();
                x.end ();
            }
            x.end ();
            x.start ("a:fmtScheme").a ("name", t.name);
            x.start ("a:fillStyleLst");
            for (int i = 0; i < 3; i++) x.start ("a:solidFill").start ("a:schemeClr").a ("val", "phClr").end ().end ();
            x.end ();
            x.start ("a:lnStyleLst");
            int[] widths = { 6350, 12700, 19050 };
            foreach (int w in widths) {
                x.start ("a:ln").ai ("w", w).a ("cap", "flat").a ("cmpd", "sng").a ("algn", "ctr");
                x.start ("a:solidFill").start ("a:schemeClr").a ("val", "phClr").end ().end ();
                x.start ("a:prstDash").a ("val", "solid").end ();
                x.start ("a:miter").a ("lim", "800000").end ();
                x.end ();
            }
            x.end ();
            x.start ("a:effectStyleLst");
            for (int i = 0; i < 3; i++) x.start ("a:effectStyle").empty ("a:effectLst").end ();
            x.end ();
            x.start ("a:bgFillStyleLst");
            for (int i = 0; i < 3; i++) x.start ("a:solidFill").start ("a:schemeClr").a ("val", "phClr").end ().end ();
            x.end ();
            x.end ();
            x.end ();
            x.empty ("a:objectDefaults");
            x.empty ("a:extraClrSchemeLst");
            x.start ("a:extLst").start ("a:ext").a ("uri", Ooxml.EXT_URI);
            x.start ("sg:theme").a ("xmlns:sg", Ooxml.NS_SG).a ("id", t.id).end ();
            x.end ().end ();
            x.end ();
            return x.finish ();
        }

        private void color (XmlOut x, string spec) {
            var c = ColorSpec.parse (spec);
            string b = c.base_name;
            double alpha = c.alpha;
            if (b.has_prefix ("#")) {
                string h = b.substring (1);
                if (h.length == 8) {
                    uint64 av;
                    if (uint64.try_parse ("0x" + h.substring (6), out av)) alpha *= av / 255.0;
                }
                x.start ("a:srgbClr").a ("val", hex6 (b));
            } else if (b == "none" || b == "transparent" || b == "") {
                x.start ("a:srgbClr").a ("val", "000000");
                alpha = 0;
            } else {
                string v = b;
                switch (b) {
                    case "dk1": v = "tx1"; break;
                    case "lt1": v = "bg1"; break;
                    case "dk2": v = "tx2"; break;
                    case "lt2": v = "bg2"; break;
                    default: break;
                }
                x.start ("a:schemeClr").a ("val", v);
            }
            if (c.lum_mod != 1) x.start ("a:lumMod").a ("val", Ooxml.pct (c.lum_mod)).end ();
            if (c.lum_off != 0) x.start ("a:lumOff").a ("val", Ooxml.pct (c.lum_off)).end ();
            if (alpha < 1) x.start ("a:alpha").a ("val", Ooxml.pct (alpha)).end ();
            x.end ();
        }

        private void solid (XmlOut x, string spec) {
            x.start ("a:solidFill");
            color (x, spec);
            x.end ();
        }

        private string media_part (Bytes data, string mime) {
            string key = "%p".printf (data);
            if (media.has_key (key)) return media[key];
            media_count++;
            string ext = Ooxml.ext_for_mime (mime);
            string name = "ppt/media/image%d.%s".printf (media_count, ext);
            media_exts.add (ext);
            parts.add (new Part (name, data, null));
            media[key] = name;
            return name;
        }

        private string image_rel (Bytes data, string mime) {
            string part = media_part (data, mime);
            return rels.add (Ooxml.REL_IMAGE, "../media/" + Path.get_basename (part));
        }

        private void fill (XmlOut x, Fill f, bool none_explicit) {
            switch (f.kind) {
                case FillKind.SOLID:
                    solid (x, f.color);
                    break;
                case FillKind.GRADIENT:
                    x.start ("a:gradFill").a ("rotWithShape", "1");
                    x.start ("a:gsLst");
                    foreach (var st in f.stops) {
                        x.start ("a:gs").a ("pos", Ooxml.pct (st.pos));
                        color (x, st.color);
                        x.end ();
                    }
                    x.end ();
                    if (f.radial) {
                        x.start ("a:path").a ("path", "circle");
                        x.start ("a:fillToRect").a ("l", "50000").a ("t", "50000").a ("r", "50000").a ("b", "50000").end ();
                        x.end ();
                    } else {
                        double ang = f.angle % 360;
                        if (ang < 0) ang += 360;
                        x.start ("a:lin").ai ("ang", (int64) Math.round (ang * 60000)).a ("scaled", "0").end ();
                    }
                    x.end ();
                    break;
                case FillKind.IMAGE:
                    if (f.image == null) {
                        x.empty ("a:noFill");
                        break;
                    }
                    x.start ("a:blipFill").a ("dpi", "0").a ("rotWithShape", "1");
                    x.start ("a:blip").a ("r:embed", image_rel (f.image, f.image_mime != "" ? f.image_mime : "image/png")).end ();
                    x.empty ("a:srcRect");
                    if (f.tile) x.start ("a:tile").a ("tx", "0").a ("ty", "0").a ("sx", "100000").a ("sy", "100000").a ("flip", "none").a ("algn", "tl").end ();
                    else x.start ("a:stretch").empty ("a:fillRect").end ();
                    x.end ();
                    break;
                default:
                    if (none_explicit) x.empty ("a:noFill");
                    break;
            }
        }

        private void line (XmlOut x, Line l, bool explicit_none) {
            if (l.color == "") {
                if (explicit_none) x.start ("a:ln").ai ("w", Ooxml.emu (l.width)).empty ("a:noFill").end ();
                return;
            }
            x.start ("a:ln").ai ("w", Ooxml.emu (l.width));
            solid (x, l.color);
            x.start ("a:prstDash").a ("val", l.dash.to_ooxml ()).end ();
            if (l.head != ArrowKind.NONE) x.start ("a:headEnd").a ("type", l.head.to_ooxml ()).end ();
            if (l.tail != ArrowKind.NONE) x.start ("a:tailEnd").a ("type", l.tail.to_ooxml ()).end ();
            x.end ();
        }

        private void effects (XmlOut x, Shadow s, ShapeEffects? fx = null) {
            bool glow = fx != null && fx.glow_color != "" && fx.glow_radius > 0;
            bool refl = fx != null && fx.reflection;
            bool soft = fx != null && fx.soft_edge > 0;
            if (!s.enabled && !glow && !refl && !soft) {
                effects_3d (x, fx);
                return;
            }
            x.start ("a:effectLst");
            if (glow) {
                x.start ("a:glow").ai ("rad", Ooxml.emu (fx.glow_radius));
                color (x, fx.glow_color);
                x.end ();
            }
            if (s.enabled) {
                double ang = s.angle % 360;
                if (ang < 0) ang += 360;
                x.start ("a:outerShdw").ai ("blurRad", Ooxml.emu (s.blur)).ai ("dist", Ooxml.emu (s.distance))
                    .ai ("dir", (int64) Math.round (ang * 60000)).a ("algn", "ctr").a ("rotWithShape", "0");
                color (x, ColorSpec.with_alpha (s.color, ColorSpec.parse (s.color).alpha * s.opacity));
                x.end ();
            }
            if (refl) {
                x.start ("a:reflection").a ("blurRad", "6350").a ("stA", Ooxml.pct (fx.reflection_alpha)).a ("endA", "300").a ("endPos", Ooxml.pct (fx.reflection_size))
                    .ai ("dist", Ooxml.emu (fx.reflection_distance)).a ("dir", "5400000").a ("sy", "-100000").a ("algn", "bl").a ("rotWithShape", "0").end ();
            }
            if (soft) x.start ("a:softEdge").ai ("rad", Ooxml.emu (fx.soft_edge)).end ();
            x.end ();
            effects_3d (x, fx);
        }

        private void effects_3d (XmlOut x, ShapeEffects? fx) {
            if (fx == null) return;
            if (fx.rot_x != 0 || fx.rot_y != 0) {
                x.start ("a:scene3d");
                x.start ("a:camera").a ("prst", "orthographicFront");
                double lat = fx.rot_x % 360, lon = fx.rot_y % 360;
                if (lat < 0) lat += 360;
                if (lon < 0) lon += 360;
                x.start ("a:rot").ai ("lat", (int64) Math.round (lat * 60000)).ai ("lon", (int64) Math.round (lon * 60000)).a ("rev", "0").end ();
                x.end ();
                x.start ("a:lightRig").a ("rig", "threePt").a ("dir", "t").end ();
                x.end ();
            }
            if (fx.bevel != "") {
                x.start ("a:sp3d");
                x.start ("a:bevelT").ai ("w", Ooxml.emu (fx.bevel_width)).ai ("h", Ooxml.emu (fx.bevel_height)).a ("prst", fx.bevel).end ();
                x.end ();
            }
        }

        private ShapeEffects? text_fx = null;

        private void xfrm (XmlOut x, Element e, string tag) {
            x.start (tag);
            if (e.rotation != 0) {
                double r = e.rotation % 360;
                if (r < 0) r += 360;
                x.ai ("rot", (int64) Math.round (r * 60000));
            }
            if (e.flip_h) x.a ("flipH", "1");
            if (e.flip_v) x.a ("flipV", "1");
            x.start ("a:off").ai ("x", Ooxml.emu (e.x)).ai ("y", Ooxml.emu (e.y)).end ();
            x.start ("a:ext").ai ("cx", Ooxml.emu (double.max (e.w, 0))).ai ("cy", Ooxml.emu (double.max (e.h, 0))).end ();
            x.end ();
        }

        private void preset (XmlOut x, string name, double corner) {
            x.start ("a:prstGeom").a ("prst", name);
            if (corner >= 0) {
                x.start ("a:avLst").start ("a:gd").a ("name", "adj").a ("fmla", "val " + Ooxml.pct (corner)).end ().end ();
            } else {
                x.empty ("a:avLst");
            }
            x.end ();
        }

        private void geometry (XmlOut x, ShapeElement s) {
            if (s.shape == ShapeKind.CUSTOM) {
                int64 w = 100000, h = 100000;
                x.start ("a:custGeom");
                x.empty ("a:avLst");
                x.empty ("a:gdLst");
                x.empty ("a:ahLst");
                x.empty ("a:cxnLst");
                x.start ("a:rect").a ("l", "l").a ("t", "t").a ("r", "r").a ("b", "b").end ();
                x.start ("a:pathLst").start ("a:path").ai ("w", w).ai ("h", h);
                if (!Geometry.is_closed (s)) x.a ("fill", "none");
                foreach (var c in s.path) {
                    switch (c.op) {
                        case 'M':
                        case 'L':
                            x.start (c.op == 'M' ? "a:moveTo" : "a:lnTo");
                            x.start ("a:pt").ai ("x", (int64) Math.round (c.pts[0] * w)).ai ("y", (int64) Math.round (c.pts[1] * h)).end ();
                            x.end ();
                            break;
                        case 'C':
                        case 'Q':
                            x.start (c.op == 'C' ? "a:cubicBezTo" : "a:quadBezTo");
                            for (int i = 0; i + 1 < c.pts.length; i += 2) x.start ("a:pt").ai ("x", (int64) Math.round (c.pts[i] * w)).ai ("y", (int64) Math.round (c.pts[i + 1] * h)).end ();
                            x.end ();
                            break;
                        case 'Z':
                            x.empty ("a:close");
                            break;
                    }
                }
                x.end ().end ();
                x.end ();
                return;
            }
            if (s.shape == ShapeKind.ROUND_RECT || s.adjust_values.size == 0) {
                preset (x, s.preset_name (), s.shape == ShapeKind.ROUND_RECT ? s.corner : -1);
                return;
            }
            x.start ("a:prstGeom").a ("prst", s.preset_name ());
            x.start ("a:avLst");
            var keys = new Gee.ArrayList<string> ();
            keys.add_all (s.adjust_values.keys);
            keys.sort ();
            foreach (string k in keys) x.start ("a:gd").a ("name", k).a ("fmla", "val " + ((int64) Math.round (s.adjust_values[k])).to_string ()).end ();
            x.end ();
            x.end ();
        }

        private void collect (Element e, Gee.HashSet<int> used, Gee.ArrayList<Element> pending) {
            if (e.id > 0 && !used.contains (e.id)) {
                used.add (e.id);
                ids[e] = e.id;
            } else {
                pending.add (e);
            }
            var g = e as GroupElement;
            if (g != null) foreach (var c in g.children) collect (c, used, pending);
        }

        private void prepare_ids (Gee.List<Element> elements, int reserve = 0) {
            ids.clear ();
            var used = new Gee.HashSet<int> ();
            var pending = new Gee.ArrayList<Element> ();
            foreach (var e in elements) collect (e, used, pending);
            int mx = reserve;
            foreach (int i in used) mx = int.max (mx, i);
            root_id = used.contains (1) ? ++mx : 1;
            if (root_id == 1) mx = int.max (mx, 1);
            foreach (var e in pending) ids[e] = ++mx;
            max_used = mx;
        }

        private int max_used = 0;

        private int fresh_id (Element e) {
            ids[e] = ++max_used;
            return max_used;
        }

        private int id_of (Element e) {
            return ids.has_key (e) ? ids[e] : e.id;
        }

        private void sp_tree (XmlOut x, Gee.List<Element> elements) {
            x.start ("p:spTree");
            x.start ("p:nvGrpSpPr");
            x.start ("p:cNvPr").ai ("id", root_id).a ("name", "").end ();
            x.empty ("p:cNvGrpSpPr");
            x.empty ("p:nvPr");
            x.end ();
            x.start ("p:grpSpPr").start ("a:xfrm");
            x.start ("a:off").a ("x", "0").a ("y", "0").end ();
            x.start ("a:ext").a ("cx", "0").a ("cy", "0").end ();
            x.start ("a:chOff").a ("x", "0").a ("y", "0").end ();
            x.start ("a:chExt").a ("cx", "0").a ("cy", "0").end ();
            x.end ().end ();
            foreach (var e in elements) element (x, e);
            x.end ();
        }

        private void c_nv_pr (XmlOut x, Element e, string tag = "p:cNvPr") {
            x.start (tag).ai ("id", id_of (e)).a ("name", e.name);
            if (e.description != "") x.a ("descr", e.description);
            if (e.click != null) action (x, "a:hlinkClick", e.click);
            if (e.hover != null) action (x, "a:hlinkHover", e.hover);
            x.end ();
        }

        private void action (XmlOut x, string tag, ClickAction a) {
            string rid = "";
            switch (a.kind) {
                case ActionKind.URL:
                case ActionKind.FILE:
                case ActionKind.PROGRAM:
                    if (a.target == "") return;
                    rid = rels.add (Ooxml.REL_HYPERLINK, a.target, true);
                    break;
                case ActionKind.SLIDE:
                    if (!slide_part_by_uid.has_key (a.slide_uid)) return;
                    rid = rels.add (Ooxml.REL_SLIDE, relative (current_part, slide_part_by_uid[a.slide_uid]));
                    break;
                case ActionKind.NONE:
                    return;
                default:
                    break;
            }
            x.start (tag).a ("r:id", rid);
            string? act = a.ppaction ();
            if (a.kind == ActionKind.CUSTOM_SHOW) act = "ppaction://customshow?id=%d%s".printf (custom_show_ids.has_key (a.target) ? custom_show_ids[a.target] : 0, a.show_and_return ? "&return=true" : "");
            if (act != null) x.a ("action", act);
            if (a.tooltip != "") x.a ("tooltip", a.tooltip);
            if (a.highlight && a.kind != ActionKind.URL) x.a ("highlightClick", "1");
            x.end ();
        }

        private void nv_pr (XmlOut x, Element e) {
            if (e.placeholder == PlaceholderKind.NONE) {
                x.empty ("p:nvPr");
                return;
            }
            x.start ("p:nvPr").start ("p:ph");
            if (e.placeholder != PlaceholderKind.OBJECT) x.a ("type", e.placeholder.to_ooxml ());
            if (e.placeholder_idx >= 0) x.ai ("idx", e.placeholder_idx);
            x.end ().end ();
        }

        private void element (XmlOut x, Element e) {
            if (e.alternate != null && e.alternate_sig != "" && e.alternate_sig == e.light_signature ()) {
                foreign (x, e.alternate, e);
                return;
            }
            switch (e.kind) {
                case ElementKind.SHAPE:
                    shape (x, (ShapeElement) e);
                    break;
                case ElementKind.IMAGE:
                    picture (x, (ImageElement) e);
                    break;
                case ElementKind.TABLE:
                    table (x, (TableElement) e);
                    break;
                case ElementKind.CHART:
                    chart (x, (ChartElement) e);
                    break;
                case ElementKind.GROUP:
                    group (x, (GroupElement) e);
                    break;
                case ElementKind.FOREIGN:
                    foreign (x, (ForeignElement) e);
                    break;
                case ElementKind.MEDIA:
                    media_el (x, (MediaElement) e);
                    break;
                case ElementKind.INK:
                    ink_el (x, (InkElement) e);
                    break;
                case ElementKind.ZOOM:
                    zoom_el (x, (ZoomElement) e);
                    break;
                case ElementKind.DIAGRAM:
                    diagram_el (x, (DiagramElement) e);
                    break;
                case ElementKind.EQUATION:
                    equation_el (x, (EquationElement) e);
                    break;
                case ElementKind.MODEL3D:
                    model_el (x, (Model3DElement) e);
                    break;
            }
        }

        private int model_count = 0;

        private void model_el (XmlOut x, Model3DElement m) {
            if (m.pristine ()) {
                foreign (x, m.original, m);
                return;
            }
            var png = MeshPainter.png (m, int.max ((int) (m.w * 2), 16), int.max ((int) (m.h * 2), 16)) ?? m.preview;
            string? img_rid = png != null ? image_rel (png, "image/png") : null;
            string? model_rid = null;
            if (m.data != null && m.format == "glb") {
                model_count++;
                string name = unique_name ("ppt/media/model3d%d.glb".printf (model_count));
                add_bytes_part (name, m.data, Ooxml.CT_GLB);
                model_rid = rels.add (Ooxml.REL_MODEL3D, "../media/" + Path.get_basename (name));
            }
            if (model_rid != null) {
                x.start ("mc:AlternateContent").a ("xmlns:mc", Ooxml.NS_MC);
                x.start ("mc:Choice").a ("xmlns:am3d", Ooxml.NS_AM3D).a ("Requires", "am3d");
                x.start ("p:graphicFrame");
                x.start ("p:nvGraphicFramePr");
                model_nv (x, m);
                x.start ("p:cNvGraphicFramePr").start ("a:graphicFrameLocks").a ("noGrp", "1").end ().end ();
                x.empty ("p:nvPr");
                x.end ();
                xfrm (x, m, "p:xfrm");
                x.start ("a:graphic").start ("a:graphicData").a ("uri", Ooxml.URI_MODEL3D);
                x.start ("am3d:model3d").a ("r:embed", model_rid);
                x.start ("am3d:spPr");
                xfrm (x, m, "a:xfrm");
                preset (x, "rect", -1);
                x.end ();
                x.start ("am3d:camera");
                x.start ("am3d:pos").a ("x", "0").a ("y", "0").a ("z", "%lld".printf ((int64) Math.round (68000000 / double.max (m.zoom, 0.1)))).end ();
                x.start ("am3d:up").a ("dx", "0").a ("dy", "36000000").a ("dz", "0").end ();
                x.start ("am3d:lookAt").a ("x", "0").a ("y", "0").a ("z", "0").end ();
                x.start ("am3d:perspective").a ("fov", "2700000").end ();
                x.end ();
                x.start ("am3d:trans");
                x.start ("am3d:meterPerModelUnit").a ("n", "1000000").a ("d", "1000000").end ();
                x.start ("am3d:preTrans").a ("dx", "0").a ("dy", "0").a ("dz", "0").end ();
                x.start ("am3d:scale");
                x.start ("am3d:sx").a ("n", "1000000").a ("d", "1000000").end ();
                x.start ("am3d:sy").a ("n", "1000000").a ("d", "1000000").end ();
                x.start ("am3d:sz").a ("n", "1000000").a ("d", "1000000").end ();
                x.end ();
                x.start ("am3d:rot").ai ("ax", (int64) Math.round (m.rot_x * 60000)).ai ("ay", (int64) Math.round (m.rot_y * 60000)).ai ("az", (int64) Math.round (m.rot_z * 60000)).end ();
                x.start ("am3d:postTrans").a ("dx", "0").a ("dy", "0").a ("dz", "0").end ();
                x.end ();
                if (img_rid != null) x.start ("am3d:raster").a ("rName", "Office3DRenderer").a ("rVer", "16.0.8326").start ("am3d:blip").a ("r:embed", img_rid).end ().end ();
                x.start ("am3d:objViewport").a ("viewportSz", "%lld".printf (Ooxml.emu (double.max (m.w, m.h)))).end ();
                x.start ("am3d:ambientLight").start ("am3d:clr").start ("a:scrgbClr").a ("r", "50000").a ("g", "50000").a ("b", "50000").end ().end ().start ("am3d:illuminance").a ("n", "500000").a ("d", "1000000").end ().end ();
                x.end ();
                x.end ().end ();
                x.end ();
                x.end ();
                x.start ("mc:Fallback");
            }
            if (img_rid != null) {
                x.start ("p:pic");
                x.start ("p:nvPicPr");
                model_nv (x, m);
                x.start ("p:cNvPicPr").start ("a:picLocks").a ("noChangeAspect", "1").end ().end ();
                x.empty ("p:nvPr");
                x.end ();
                pic_frame (x, m, img_rid);
                x.end ();
            }
            if (model_rid != null) {
                x.end ();
                x.end ();
            }
        }

        private void model_nv (XmlOut x, Model3DElement m) {
            x.start ("p:cNvPr").ai ("id", id_of (m)).a ("name", m.name != "" ? m.name : "3D Model");
            if (m.description != "") x.a ("descr", m.description);
            x.end ();
        }

        private Bytes render_png (Element e, double w, double h, double scale = 2) {
            int pw = int.max (1, (int) Math.ceil (w * scale)), ph = int.max (1, (int) Math.ceil (h * scale));
            var surf = new Cairo.ImageSurface (Cairo.Format.ARGB32, pw, ph);
            var cr = new Cairo.Context (surf);
            cr.scale (scale, scale);
            cr.translate (-e.x, -e.y);
            var slide = writing_slide ?? (pres.slides.size > 0 ? pres.slides[0] : new Slide ());
            var ctx = new RenderContext (pres, slide, pres.layout_for (slide), pres.master_for (slide));
            var r = new Renderer ();
            var saved = e.rotation;
            e.rotation = 0;
            r.draw_element (cr, ctx, e, false);
            e.rotation = saved;
            return png_of (surf);
        }

        private static Bytes png_of (Cairo.ImageSurface surf) {
            var bytes = new ByteArray ();
            surf.write_to_png_stream ((data) => {
                bytes.append (data);
                return Cairo.Status.SUCCESS;
            });
            return ByteArray.free_to_bytes ((owned) bytes);
        }

        private void pic_frame (XmlOut x, Element e, string blip_rid) {
            x.start ("p:blipFill");
            x.start ("a:blip").a ("r:embed", blip_rid).end ();
            x.start ("a:stretch").empty ("a:fillRect").end ();
            x.end ();
            x.start ("p:spPr");
            xfrm (x, e, "a:xfrm");
            preset (x, "rect", -1);
            x.end ();
        }

        private string media_file (MediaElement m) {
            if (media_files.has_key (m.data)) return media_files[m.data];
            media_file_count++;
            string name = unique_name ("ppt/media/media%d.%s".printf (media_file_count, m.extension ()));
            add_bytes_part (name, m.data, m.mime);
            media_files[m.data] = name;
            return name;
        }

        private void media_el (XmlOut x, MediaElement m) {
            if (m.data == null && m.link == "") return;
            string link_rid, media_rid = "";
            string rtype = m.is_video ? Ooxml.REL_VIDEO : Ooxml.REL_AUDIO;
            if (m.data != null) {
                string rel = relative (current_part, media_file (m));
                media_rid = rels.add (Ooxml.REL_MEDIA, rel);
                link_rid = rels.add (rtype, rel);
            } else {
                link_rid = rels.add (rtype, m.link, true);
            }
            Bytes poster = m.poster ?? MediaArt.poster_png (m);
            string poster_rid = image_rel (poster, m.poster != null ? m.poster_mime : "image/png");
            x.start ("p:pic");
            x.start ("p:nvPicPr");
            x.start ("p:cNvPr").ai ("id", id_of (m)).a ("name", m.name != "" ? m.name : (m.is_video ? "Video" : "Audio"));
            if (m.description != "") x.a ("descr", m.description);
            x.start ("a:hlinkClick").a ("r:id", "").a ("action", "ppaction://media").end ();
            x.end ();
            x.start ("p:cNvPicPr").start ("a:picLocks").a ("noChangeAspect", "1").end ().end ();
            x.start ("p:nvPr");
            x.start (m.is_video ? "a:videoFile" : "a:audioFile").a ("r:link", link_rid).end ();
            if (media_rid != "") {
                x.start ("p:extLst").start ("p:ext").a ("uri", Ooxml.EXT_MEDIA);
                x.start ("p14:media").a ("xmlns:p14", Ooxml.NS_P14).a ("r:embed", media_rid);
                if (m.trim_start > 0 || m.trim_end > 0) {
                    x.start ("p14:trim");
                    if (m.trim_start > 0) x.ai ("st", (int64) Math.round (m.trim_start * 1000));
                    if (m.trim_end > 0) x.ai ("end", (int64) Math.round (m.trim_end * 1000));
                    x.end ();
                }
                if (m.fade_in > 0 || m.fade_out > 0) {
                    x.start ("p14:fade");
                    if (m.fade_in > 0) x.ai ("in", (int64) Math.round (m.fade_in * 1000));
                    if (m.fade_out > 0) x.ai ("out", (int64) Math.round (m.fade_out * 1000));
                    x.end ();
                }
                if (m.bookmarks.size > 0) {
                    x.start ("p14:bmkLst");
                    foreach (var b in m.bookmarks) x.start ("p14:bmk").a ("name", b.name).ai ("time", (int64) Math.round (b.time * 1000)).end ();
                    x.end ();
                }
                x.end ();
                x.end ().end ();
            }
            x.end ();
            x.end ();
            x.start ("p:blipFill");
            x.start ("a:blip").a ("r:embed", poster_rid).end ();
            x.start ("a:stretch").empty ("a:fillRect").end ();
            x.end ();
            x.start ("p:spPr");
            xfrm (x, m, "a:xfrm");
            preset (x, "rect", -1);
            line (x, m.line, false);
            effects (x, m.shadow);
            x.end ();
            x.end ();
        }

        private void ink_el (XmlOut x, InkElement ink) {
            ink_count++;
            string part = unique_name ("ppt/ink/ink%d.xml".printf (ink_count));
            add_part (part, InkCodec.write (ink), Ooxml.CT_INK);
            string rid = rels.add (Ooxml.REL + "customXml", relative (current_part, part));
            x.start ("mc:AlternateContent").a ("xmlns:mc", Ooxml.NS_MC);
            x.start ("mc:Choice").a ("xmlns:p14", Ooxml.NS_P14).a ("Requires", "p14");
            x.start ("p:contentPart").a ("p14:bwMode", "auto").a ("r:id", rid);
            x.start ("p14:nvContentPartPr");
            x.start ("p14:cNvPr").ai ("id", id_of (ink)).a ("name", ink.name != "" ? ink.name : "Ink %d".printf (ink_count)).end ();
            x.empty ("p14:cNvContentPartPr");
            x.empty ("p14:nvPr");
            x.end ();
            xfrm (x, ink, "p14:xfrm");
            x.end ();
            x.end ();
            x.start ("mc:Fallback");
            x.start ("p:pic");
            x.start ("p:nvPicPr");
            x.start ("p:cNvPr").ai ("id", id_of (ink)).a ("name", ink.name != "" ? ink.name : "Ink %d".printf (ink_count)).end ();
            x.empty ("p:cNvPicPr");
            x.empty ("p:nvPr");
            x.end ();
            pic_frame (x, ink, image_rel (render_png (ink, ink.w, ink.h), "image/png"));
            x.end ();
            x.end ();
            x.end ();
        }

        private void diagram_el (XmlOut x, DiagramElement d) {
            if (d.pristine ()) {
                foreign (x, d.original, d);
                return;
            }
            var shapes = d.build ();
            foreach (var e in shapes) fresh_id (e);
            x.start ("p:grpSp");
            x.start ("p:nvGrpSpPr");
            c_nv_pr (x, d);
            x.empty ("p:cNvGrpSpPr");
            x.start ("p:nvPr").start ("p:extLst").start ("p:ext").a ("uri", Ooxml.EXT_URI);
            x.start ("sg:diagram").a ("xmlns:sg", Ooxml.NS_SG).a ("layout", d.layout.ooxml_id ()).ai ("colors", (int) d.colors).ai ("style", (int) d.style);
            foreach (var n in d.nodes) diagram_node (x, n);
            x.end ();
            x.end ().end ().end ();
            x.end ();
            x.start ("p:grpSpPr");
            x.start ("a:xfrm");
            x.start ("a:off").ai ("x", Ooxml.emu (d.x)).ai ("y", Ooxml.emu (d.y)).end ();
            x.start ("a:ext").ai ("cx", Ooxml.emu (double.max (d.w, 0))).ai ("cy", Ooxml.emu (double.max (d.h, 0))).end ();
            x.start ("a:chOff").ai ("x", Ooxml.emu (d.x)).ai ("y", Ooxml.emu (d.y)).end ();
            x.start ("a:chExt").ai ("cx", Ooxml.emu (double.max (d.w, 0))).ai ("cy", Ooxml.emu (double.max (d.h, 0))).end ();
            x.end ();
            x.end ();
            foreach (var e in shapes) element (x, e);
            x.end ();
        }

        private void diagram_node (XmlOut x, DiagramNode n) {
            x.start ("sg:node");
            if (n.color != "") x.a ("color", n.color);
            if (n.image != null) x.a ("r:embed", image_rel (n.image, n.image_mime));
            foreach (var p in n.text.paragraphs) paragraph (x, p);
            foreach (var c in n.children) diagram_node (x, c);
            x.end ();
        }

        private void zoom_el (XmlOut x, ZoomElement z) {
            var target = z.target (pres);
            Bytes img = z.image;
            if (img == null && target != null) {
                var surf = new Renderer ().thumbnail (pres, target, (int) Math.ceil (double.max (z.w, 64) * 2));
                img = png_of (surf);
            }
            if (img == null) img = render_png (z, z.w, z.h);
            string img_rid = image_rel (img, z.image != null ? z.image_mime : "image/png");
            string name = z.name != "" ? z.name : (z.zoom == ZoomKind.SLIDE ? "Slide Zoom" : "Section Zoom");
            string slide_rid = "";
            if (target != null && slide_part_by_uid.has_key (target.uid)) slide_rid = rels.add (Ooxml.REL_SLIDE, relative (current_part, slide_part_by_uid[target.uid]));
            bool slide = z.zoom == ZoomKind.SLIDE;
            string ns = slide ? Ooxml.NS_PSLZ : Ooxml.NS_PSEZ;
            string pfx = slide ? "pslz" : "psez";
            x.start ("mc:AlternateContent").a ("xmlns:mc", Ooxml.NS_MC);
            x.start ("mc:Choice").a ("xmlns:" + pfx, ns).a ("Requires", pfx);
            x.start ("p:graphicFrame");
            x.start ("p:nvGraphicFramePr");
            x.start ("p:cNvPr").ai ("id", id_of (z)).a ("name", name).end ();
            x.start ("p:cNvGraphicFramePr").start ("a:graphicFrameLocks").a ("noChangeAspect", "1").end ().end ();
            x.empty ("p:nvPr");
            x.end ();
            xfrm (x, z, "p:xfrm");
            x.start ("a:graphic").start ("a:graphicData").a ("uri", slide ? Ooxml.URI_SLIDE_ZOOM : Ooxml.URI_SECTION_ZOOM);
            x.start (pfx + (slide ? ":sldZm" : ":sectionZm"));
            x.start (pfx + (slide ? ":sldZmObj" : ":sectionZmObj"));
            if (slide) x.a ("sldId", (target != null && sld_id_by_uid.has_key (target.uid) ? sld_id_by_uid[target.uid] : 256).to_string ()).a ("cId", "0");
            else x.a ("sectionId", z.section_id);
            x.start (pfx + ":zmPr").a ("id", "{" + Uuid.string_random ().up () + "}").a ("returnToParent", z.return_to_zoom ? "1" : "0")
                .ai ("transitionDur", (int64) Math.round (z.transition_duration * 1000));
            if (z.use_background) x.a ("useBgFill", "1");
            x.start ("p166:blipFill").a ("xmlns:p166", Ooxml.NS_P166);
            x.start ("a:blip").a ("r:embed", img_rid).end ();
            x.start ("a:stretch").empty ("a:fillRect").end ();
            x.end ();
            x.start ("p166:spPr").a ("xmlns:p166", Ooxml.NS_P166);
            x.start ("a:xfrm").start ("a:off").a ("x", "0").a ("y", "0").end ().start ("a:ext").ai ("cx", Ooxml.emu (z.w)).ai ("cy", Ooxml.emu (z.h)).end ().end ();
            preset (x, "rect", -1);
            x.start ("a:ln").ai ("w", 3175).start ("a:solidFill").start ("a:prstClr").a ("val", "ltGray").end ().end ().end ();
            x.end ();
            x.end ();
            x.end ();
            x.end ();
            x.end ().end ();
            x.end ();
            x.end ();
            x.start ("mc:Fallback");
            x.start ("p:pic");
            x.start ("p:nvPicPr");
            x.start ("p:cNvPr").ai ("id", id_of (z)).a ("name", name);
            if (slide_rid != "") x.start ("a:hlinkClick").a ("r:id", slide_rid).a ("action", "ppaction://hlinksldjump").end ();
            x.end ();
            x.start ("p:cNvPicPr").start ("a:picLocks").a ("noGrp", "1").a ("noRot", "1").a ("noChangeAspect", "1").end ().end ();
            x.empty ("p:nvPr");
            x.end ();
            pic_frame (x, z, img_rid);
            x.end ();
            x.end ();
            x.end ();
        }

        private void equation_el (XmlOut x, EquationElement q) {
            if (q.original != null && q.original_sig != "" && q.original_sig == EquationCodec.signature (q)) {
                foreign (x, q.original, q);
                return;
            }
            Bytes img = q.image != null ? EquationCodec.png_for (q) : render_png (q, q.w, q.h);
            string img_rid = image_rel (img, "image/png");
            string omml = EquationCodec.omml_for (q);
            if (omml != "") {
                x.start ("mc:AlternateContent").a ("xmlns:mc", Ooxml.NS_MC);
                x.start ("mc:Choice").a ("xmlns:a14", Ooxml.NS_A14).a ("Requires", "a14");
                x.start ("p:sp");
                x.start ("p:nvSpPr");
                equation_nv (x, q);
                x.start ("p:cNvSpPr").a ("txBox", "1").end ();
                x.empty ("p:nvPr");
                x.end ();
                x.start ("p:spPr");
                xfrm (x, q, "a:xfrm");
                preset (x, "rect", -1);
                x.empty ("a:noFill");
                x.end ();
                x.start ("p:txBody");
                x.start ("a:bodyPr").a ("wrap", "none").a ("lIns", "0").a ("tIns", "0").a ("rIns", "0").a ("bIns", "0").empty ("a:spAutoFit").end ();
                x.empty ("a:lstStyle");
                x.start ("a:p");
                x.start ("a14:m");
                x.raw (omml);
                x.end ();
                x.start ("a:endParaRPr").a ("lang", "en-US").end ();
                x.end ();
                x.end ();
                x.end ();
                x.end ();
                x.start ("mc:Fallback");
            }
            x.start ("p:pic");
            x.start ("p:nvPicPr");
            equation_nv (x, q);
            x.start ("p:cNvPicPr").start ("a:picLocks").a ("noChangeAspect", "1").end ().end ();
            x.empty ("p:nvPr");
            x.end ();
            pic_frame (x, q, img_rid);
            x.end ();
            if (omml != "") {
                x.end ();
                x.end ();
            }
        }

        private void equation_nv (XmlOut x, EquationElement q) {
            x.start ("p:cNvPr").ai ("id", id_of (q)).a ("name", q.name != "" ? q.name : "Equation");
            x.a ("descr", q.description != "" ? q.description : q.latex);
            x.start ("a:extLst").start ("a:ext").a ("uri", Ooxml.EXT_EQUATION);
            x.start ("sg:equation").a ("xmlns:sg", Ooxml.NS_SG);
            x.element ("sg:latex", q.latex);
            x.element ("sg:mathml", q.mathml);
            if (q.color != "") x.element ("sg:color", q.color);
            x.end ();
            x.end ().end ();
            x.end ();
        }

        private static bool is_connector (ShapeElement s) {
            return s.shape == ShapeKind.LINE && (s.text == null || s.text.is_empty ()) && s.placeholder == PlaceholderKind.NONE;
        }

        private void shape (XmlOut x, ShapeElement s) {
            bool connector = is_connector (s);
            bool ph = s.placeholder != PlaceholderKind.NONE;
            x.start (connector ? "p:cxnSp" : "p:sp");
            x.start (connector ? "p:nvCxnSpPr" : "p:nvSpPr");
            c_nv_pr (x, s);
            if (connector) {
                x.start ("p:cNvCxnSpPr");
                if (s.locked) x.start ("a:cxnSpLocks").a ("noMove", "1").a ("noResize", "1").end ();
                x.end ();
            } else {
                x.start ("p:cNvSpPr");
                if (s.text_box) x.a ("txBox", "1");
                if (ph || s.locked) {
                    x.start ("a:spLocks");
                    if (ph) x.a ("noGrp", "1");
                    if (s.locked) x.a ("noMove", "1").a ("noResize", "1").a ("noRot", "1");
                    x.end ();
                }
                x.end ();
            }
            nv_pr (x, s);
            x.end ();
            x.start ("p:spPr");
            if (!s.inherit_geometry) xfrm (x, s, "a:xfrm");
            bool styled = !ph || s.shape != ShapeKind.RECT || s.fill.kind != FillKind.NONE || s.line.color != "" || s.shadow.enabled;
            if (!ph || styled) geometry (x, s);
            fill (x, s.fill, !ph);
            line (x, s.line, !ph);
            effects (x, s.shadow, s.effects);
            x.end ();
            text_fx = s.effects.has_text_effects () ? s.effects : null;
            if (!connector) text_body (x, s.text ?? new TextBody (), s.list_style, "p:txBody", ph || s.text != null);
            text_fx = null;
            x.end ();
        }

        private void picture (XmlOut x, ImageElement img) {
            x.start ("p:pic");
            x.start ("p:nvPicPr");
            c_nv_pr (x, img);
            x.start ("p:cNvPicPr").start ("a:picLocks").a ("noChangeAspect", "1");
            if (img.placeholder != PlaceholderKind.NONE) x.a ("noGrp", "1");
            if (img.locked) x.a ("noMove", "1").a ("noResize", "1").a ("noRot", "1");
            x.end ().end ();
            nv_pr (x, img);
            x.end ();
            x.start ("p:blipFill");
            x.start ("a:blip").a ("r:embed", image_rel (img.data, img.mime));
            if (img.opacity < 1) x.start ("a:alphaModFix").a ("amt", Ooxml.pct (img.opacity)).end ();
            if (img.saturation <= 0) x.empty ("a:grayscl");
            if (img.brightness != 0 || img.contrast != 0) {
                x.start ("a:lum");
                if (img.brightness != 0) x.a ("bright", Ooxml.pct (img.brightness));
                if (img.contrast != 0) x.a ("contrast", Ooxml.pct (img.contrast));
                x.end ();
            }
            if (img.has_filters ()) {
                x.start ("a:extLst").start ("a:ext").a ("uri", Ooxml.EXT_URI);
                x.start ("sg:filters").a ("xmlns:sg", Ooxml.NS_SG)
                    .ad ("brightness", img.brightness).ad ("contrast", img.contrast).ad ("saturation", img.saturation)
                    .a ("sepia", img.sepia ? "1" : "0").ad ("blur", img.blur).end ();
                x.end ().end ();
            }
            x.end ();
            if (img.crop_left != 0 || img.crop_top != 0 || img.crop_right != 0 || img.crop_bottom != 0) {
                x.start ("a:srcRect");
                if (img.crop_left != 0) x.a ("l", Ooxml.pct (img.crop_left));
                if (img.crop_top != 0) x.a ("t", Ooxml.pct (img.crop_top));
                if (img.crop_right != 0) x.a ("r", Ooxml.pct (img.crop_right));
                if (img.crop_bottom != 0) x.a ("b", Ooxml.pct (img.crop_bottom));
                x.end ();
            }
            x.start ("a:stretch").empty ("a:fillRect").end ();
            x.end ();
            x.start ("p:spPr");
            if (!img.inherit_geometry) xfrm (x, img, "a:xfrm");
            if (img.corner > 0) preset (x, "roundRect", img.corner);
            else preset (x, "rect", -1);
            line (x, img.line, false);
            effects (x, img.shadow);
            x.end ();
            x.end ();
        }

        private void frame_start (XmlOut x, Element e, string name_uri) {
            x.start ("p:graphicFrame");
            x.start ("p:nvGraphicFramePr");
            c_nv_pr (x, e);
            x.start ("p:cNvGraphicFramePr").start ("a:graphicFrameLocks").a ("noGrp", "1");
            if (e.locked) x.a ("noMove", "1").a ("noResize", "1");
            x.end ().end ();
            nv_pr (x, e);
            x.end ();
            xfrm (x, e, "p:xfrm");
            x.start ("a:graphic").start ("a:graphicData").a ("uri", name_uri);
        }

        private void table (XmlOut x, TableElement t) {
            frame_start (x, t, Ooxml.URI_TABLE);
            x.start ("a:tbl");
            x.start ("a:tblPr");
            if (t.first_row) x.a ("firstRow", "1");
            if (t.first_col) x.a ("firstCol", "1");
            if (t.last_row) x.a ("lastRow", "1");
            if (t.banded_rows) x.a ("bandRow", "1");
            if (t.banded_cols) x.a ("bandCol", "1");
            x.element ("a:tableStyleId", Ooxml.table_style_for (t.style_color));
            x.start ("a:extLst").start ("a:ext").a ("uri", Ooxml.EXT_URI);
            x.start ("sg:table").a ("xmlns:sg", Ooxml.NS_SG).a ("style", t.style_color)
                .a ("border", t.border.color).ad ("borderWidth", t.border.width).a ("borderDash", t.border.dash.to_ooxml ()).end ();
            x.end ().end ();
            x.end ();
            x.start ("a:tblGrid");
            foreach (var w in t.col_widths) x.start ("a:gridCol").ai ("w", Ooxml.emu (w)).end ();
            x.end ();
            for (int r = 0; r < t.rows; r++) {
                x.start ("a:tr").ai ("h", Ooxml.emu (t.row_heights[r]));
                for (int c = 0; c < t.cols; c++) {
                    var cell = t.cells[r][c];
                    x.start ("a:tc");
                    if (cell.covered) {
                        int orow = r, ocol = c;
                        find_origin (t, r, c, out orow, out ocol);
                        if (ocol != c) x.a ("hMerge", "1");
                        if (orow != r) x.a ("vMerge", "1");
                    } else {
                        if (cell.col_span > 1) x.ai ("gridSpan", cell.col_span);
                        if (cell.row_span > 1) x.ai ("rowSpan", cell.row_span);
                    }
                    text_body (x, cell.text, null, "a:txBody", true);
                    x.start ("a:tcPr").ai ("marL", Ooxml.emu (cell.text.inset_left)).ai ("marR", Ooxml.emu (cell.text.inset_right))
                        .ai ("marT", Ooxml.emu (cell.text.inset_top)).ai ("marB", Ooxml.emu (cell.text.inset_bottom));
                    if (cell.anchor == TextAnchor.MIDDLE) x.a ("anchor", "ctr");
                    else if (cell.anchor == TextAnchor.BOTTOM) x.a ("anchor", "b");
                    foreach (string side in new string[] { "lnL", "lnR", "lnT", "lnB" }) {
                        if (t.border.visible ()) {
                            x.start ("a:" + side).ai ("w", Ooxml.emu (t.border.width));
                            solid (x, t.border.color);
                            x.start ("a:prstDash").a ("val", t.border.dash.to_ooxml ()).end ();
                            x.end ();
                        } else {
                            x.start ("a:" + side).a ("w", "0").empty ("a:noFill").end ();
                        }
                    }
                    if (cell.fill != "") solid (x, cell.fill);
                    x.end ();
                    x.end ();
                }
                x.end ();
            }
            x.end ();
            x.end ().end ();
            x.end ();
        }

        private static void find_origin (TableElement t, int r, int c, out int orow, out int ocol) {
            orow = r;
            ocol = c;
            for (int rr = 0; rr <= r; rr++) {
                for (int cc = 0; cc <= c; cc++) {
                    var cl = t.cells[rr][cc];
                    if (!cl.covered && (rr != r || cc != c) && rr + cl.row_span > r && cc + cl.col_span > c) {
                        orow = rr;
                        ocol = cc;
                    }
                }
            }
        }

        private void chart (XmlOut x, ChartElement ch) {
            if (ch.pristine ()) {
                foreign (x, ch.original, ch);
                return;
            }
            if (ch.chart.is_chartex ()) {
                chartex (x, ch);
                return;
            }
            chart_count++;
            string part = "ppt/charts/chart%d.xml".printf (chart_count);
            var crels = new OoxmlRels ();
            string? wb_rid = null;
            try {
                string wb = "ppt/embeddings/Microsoft_Excel_Worksheet%d.xlsx".printf (chart_count);
                add_bytes_part (wb, new Bytes (ChartWorkbook.build (ch)), Ooxml.CT_XLSX);
                wb_rid = crels.add (Ooxml.REL_PACKAGE, "../embeddings/" + Path.get_basename (wb));
            } catch (Error e) {
                warning ("chart workbook: %s", e.message);
            }
            string cxml = ch.chart == ChartKind.STOCK ? Singularity.Charts.DrawingML.write_chart (ChartBridge.to_spec (ch, pres.theme)) : chart_xml (ch, wb_rid);
            add_part (part, cxml, Ooxml.CT_CHART);
            add_rels (part, crels);
            string rid = rels.add (Ooxml.REL_CHART, "../charts/" + Path.get_basename (part));
            frame_start (x, ch, Ooxml.URI_CHART);
            x.start ("c:chart").a ("xmlns:c", Ooxml.NS_C).a ("xmlns:r", Ooxml.NS_R).a ("r:id", rid).end ();
            x.end ().end ();
            x.end ();
        }

        private int chartex_count = 0;

        private void chartex (XmlOut x, ChartElement ch) {
            chartex_count++;
            string part = "ppt/charts/chartEx%d.xml".printf (chartex_count);
            add_part (part, Singularity.Charts.DrawingML.write_chart_ex (ChartBridge.to_spec (ch, pres.theme)), Singularity.Charts.DrawingML.CHARTEX_CONTENT_TYPE);
            string rid = rels.add (Singularity.Charts.DrawingML.CHARTEX_REL_TYPE, "../charts/" + Path.get_basename (part));
            string img_rid = image_rel (render_png (ch, ch.w, ch.h), "image/png");
            x.start ("mc:AlternateContent").a ("xmlns:mc", Ooxml.NS_MC);
            x.start ("mc:Choice").a ("xmlns:cx1", Ooxml.NS_CX1).a ("Requires", "cx1");
            frame_start (x, ch, Ooxml.URI_CHARTEX);
            x.start ("cx:chart").a ("xmlns:cx", Ooxml.URI_CHARTEX).a ("xmlns:r", Ooxml.NS_R).a ("r:id", rid).end ();
            x.end ().end ();
            x.end ();
            x.end ();
            x.start ("mc:Fallback");
            x.start ("p:pic");
            x.start ("p:nvPicPr");
            x.start ("p:cNvPr").ai ("id", id_of (ch)).a ("name", ch.name != "" ? ch.name : "Chart");
            if (ch.description != "") x.a ("descr", ch.description);
            x.end ();
            x.start ("p:cNvPicPr").start ("a:picLocks").a ("noChangeAspect", "1").end ().end ();
            x.empty ("p:nvPr");
            x.end ();
            pic_frame (x, ch, img_rid);
            x.end ();
            x.end ();
            x.end ();
        }

        private static string col_name (int i) {
            return ChartWorkbook.col_name (i);
        }

        private void str_ref (XmlOut x, string tag, string formula, Gee.List<string> values) {
            x.start (tag).start ("c:strRef");
            x.element ("c:f", formula);
            x.start ("c:strCache");
            x.start ("c:ptCount").ai ("val", values.size).end ();
            for (int i = 0; i < values.size; i++) x.start ("c:pt").ai ("idx", i).element ("c:v", values[i]).end ();
            x.end ();
            x.end ().end ();
        }

        private void num_ref (XmlOut x, string tag, string formula, Gee.List<double?> values, int count) {
            x.start (tag).start ("c:numRef");
            x.element ("c:f", formula);
            x.start ("c:numCache");
            x.element ("c:formatCode", "General");
            x.start ("c:ptCount").ai ("val", count).end ();
            for (int i = 0; i < values.size && i < count; i++) {
                if (values[i] == null) continue;
                x.start ("c:pt").ai ("idx", i).element ("c:v", ChartWorkbook.full (values[i])).end ();
            }
            x.end ();
            x.end ().end ();
        }

        private void dlbls (XmlOut x, ChartElement ch) {
            x.start ("c:dLbls");
            x.start ("c:showLegendKey").a ("val", "0").end ();
            x.start ("c:showVal").a ("val", ch.data_labels && !ch.chart.is_radial () ? "1" : "0").end ();
            x.start ("c:showCatName").a ("val", "0").end ();
            x.start ("c:showSerName").a ("val", "0").end ();
            x.start ("c:showPercent").a ("val", ch.data_labels && ch.chart.is_radial () ? "1" : "0").end ();
            x.start ("c:showBubbleSize").a ("val", "0").end ();
            x.end ();
        }

        private void rich_title (XmlOut x, string text, bool rotated = false) {
            x.start ("c:title").start ("c:tx").start ("c:rich");
            if (rotated) x.start ("a:bodyPr").a ("rot", "-5400000").a ("vert", "horz").end ();
            else x.empty ("a:bodyPr");
            x.empty ("a:lstStyle");
            x.start ("a:p").start ("a:r").empty ("a:rPr").element ("a:t", text).end ().end ();
            x.end ().end ();
            x.start ("c:overlay").a ("val", "0").end ();
            x.end ();
        }

        private void axis (XmlOut x, string tag, string id, string cross, string pos, bool grid, ChartAxis ax, bool delete_axis = false, bool crosses_max = false) {
            x.start (tag);
            x.start ("c:axId").a ("val", id).end ();
            x.start ("c:scaling");
            if (ax.log_base > 1 && tag == "c:valAx") x.start ("c:logBase").ad ("val", ax.log_base).end ();
            x.start ("c:orientation").a ("val", ax.reverse ? "maxMin" : "minMax").end ();
            if (tag == "c:valAx") {
                if (!ax.max.is_nan ()) x.start ("c:max").a ("val", ChartWorkbook.full (ax.max)).end ();
                if (!ax.min.is_nan ()) x.start ("c:min").a ("val", ChartWorkbook.full (ax.min)).end ();
            }
            x.end ();
            x.start ("c:delete").a ("val", delete_axis || !ax.visible ? "1" : "0").end ();
            x.start ("c:axPos").a ("val", pos).end ();
            if (grid) x.empty ("c:majorGridlines");
            if (ax.title != "") rich_title (x, ax.title, pos == "l" || pos == "r");
            if (ax.format != "") x.start ("c:numFmt").a ("formatCode", ax.format).a ("sourceLinked", "0").end ();
            else x.start ("c:numFmt").a ("formatCode", "General").a ("sourceLinked", "1").end ();
            x.start ("c:majorTickMark").a ("val", "out").end ();
            x.start ("c:minorTickMark").a ("val", "none").end ();
            x.start ("c:tickLblPos").a ("val", "nextTo").end ();
            x.start ("c:crossAx").a ("val", cross).end ();
            x.start ("c:crosses").a ("val", crosses_max ? "max" : "autoZero").end ();
            if (tag == "c:catAx") {
                x.start ("c:auto").a ("val", "1").end ();
                x.start ("c:lblAlgn").a ("val", "ctr").end ();
                x.start ("c:lblOffset").a ("val", "100").end ();
            } else {
                x.start ("c:crossBetween").a ("val", "between").end ();
                if (ax.major > 0) x.start ("c:majorUnit").a ("val", ChartWorkbook.full (ax.major)).end ();
            }
            x.end ();
        }

        private void trendline (XmlOut x, ChartSeries s) {
            if (s.trend == TrendKind.NONE) return;
            x.start ("c:trendline");
            x.start ("c:trendlineType").a ("val", s.trend.to_ooxml ()).end ();
            if (s.trend == TrendKind.POLYNOMIAL) x.start ("c:order").ai ("val", s.trend_order.clamp (2, 6)).end ();
            if (s.trend == TrendKind.MOVING_AVERAGE) x.start ("c:period").ai ("val", int.max (s.trend_period, 2)).end ();
            x.start ("c:dispRSqr").a ("val", s.trend_r2 ? "1" : "0").end ();
            x.start ("c:dispEq").a ("val", s.trend_equation ? "1" : "0").end ();
            x.end ();
        }

        private void series_xml (XmlOut x, ChartElement ch, int i, SeriesKind kind, int ncat, string cat_f) {
            var s = ch.series[i];
            bool bubble = ch.chart == ChartKind.BUBBLE;
            bool xy = ch.chart == ChartKind.SCATTER || bubble;
            string colname = col_name (bubble ? 1 + i * 2 : i + 1);
            x.start ("c:ser");
            x.start ("c:idx").ai ("val", i).end ();
            x.start ("c:order").ai ("val", i).end ();
            var name = new Gee.ArrayList<string> ();
            name.add (s.name);
            str_ref (x, "c:tx", "Sheet1!$%s$1".printf (colname), name);
            bool lineish = (kind == SeriesKind.LINE && !bubble) || ch.chart == ChartKind.RADAR;
            if (s.color != "") {
                x.start ("c:spPr");
                if (lineish || (ch.chart == ChartKind.SCATTER)) {
                    x.start ("a:ln").ai ("w", 28575);
                    solid (x, s.color);
                    x.end ();
                } else {
                    solid (x, s.color);
                }
                x.end ();
            }
            if (kind == SeriesKind.COLUMN && !xy && ch.chart != ChartKind.RADAR && !ch.chart.is_radial ()) x.start ("c:invertIfNegative").a ("val", "0").end ();
            if (bubble) x.start ("c:invertIfNegative").a ("val", "0").end ();
            if (ch.chart != ChartKind.RADAR && !ch.chart.is_radial ()) trendline (x, s);
            string val_f = "Sheet1!$%s$2:$%s$%d".printf (colname, colname, ncat + 1);
            if (xy) {
                bool numeric = ch.categories.size > 0;
                var xs = new Gee.ArrayList<double?> ();
                foreach (string c in ch.categories) {
                    double v = 0;
                    if (!double.try_parse (c, out v)) {
                        numeric = false;
                        break;
                    }
                    xs.add (v);
                }
                if (numeric) num_ref (x, "c:xVal", cat_f, xs, ch.categories.size);
                else str_ref (x, "c:xVal", cat_f, ch.categories);
                num_ref (x, "c:yVal", val_f, s.values, ncat);
                if (bubble) {
                    string sc = col_name (2 + i * 2);
                    num_ref (x, "c:bubbleSize", "Sheet1!$%s$2:$%s$%d".printf (sc, sc, ncat + 1), s.sizes, ncat);
                    x.start ("c:bubble3D").a ("val", "0").end ();
                } else {
                    x.start ("c:smooth").a ("val", ch.smooth ? "1" : "0").end ();
                }
            } else {
                str_ref (x, "c:cat", cat_f, ch.categories);
                num_ref (x, "c:val", val_f, s.values, ncat);
                if (kind == SeriesKind.LINE && ch.chart != ChartKind.RADAR && !ch.chart.is_radial ()) x.start ("c:smooth").a ("val", ch.smooth ? "1" : "0").end ();
            }
            x.end ();
        }

        private string chart_xml (ChartElement ch, string? wb_rid) {
            var x = new XmlOut ();
            x.start ("c:chartSpace").a ("xmlns:c", Ooxml.NS_C).a ("xmlns:a", Ooxml.NS_A).a ("xmlns:r", Ooxml.NS_R);
            x.start ("c:roundedCorners").a ("val", "0").end ();
            x.start ("c:chart");
            if (ch.title != "") rich_title (x, ch.title);
            x.start ("c:autoTitleDeleted").a ("val", ch.title == "" ? "1" : "0").end ();
            x.start ("c:plotArea");
            x.empty ("c:layout");
            int ncat = ch.categories.size;
            foreach (var s in ch.series) ncat = int.max (ncat, s.values.size);
            string cat_f = "Sheet1!$A$2:$A$%d".printf (ncat + 1);
            bool radial = ch.chart.is_radial ();
            bool secondary = ch.has_secondary ();
            var groups = new Gee.ArrayList<string> ();
            var members = new Gee.HashMap<string, Gee.ArrayList<int>> ();
            for (int i = 0; i < ch.series.size; i++) {
                var k = ch.series_kind (ch.series[i]);
                bool sec = secondary && ch.series[i].secondary;
                string key = "%d|%s".printf ((int) k, sec ? "s" : "p");
                if (!members.has_key (key)) {
                    members[key] = new Gee.ArrayList<int> ();
                    groups.add (key);
                }
                members[key].add (i);
            }
            if (groups.size == 0) {
                groups.add ("%d|p".printf ((int) ch.series_kind (new ChartSeries (""))));
                members[groups[0]] = new Gee.ArrayList<int> ();
            }
            bool used_sec = false;
            foreach (string key in groups) {
                var kind = (SeriesKind) int.parse (key.split ("|")[0]);
                bool sec = key.has_suffix ("|s");
                if (sec) used_sec = true;
                string tag;
                switch (ch.chart) {
                    case ChartKind.PIE: tag = "c:pieChart"; break;
                    case ChartKind.DOUGHNUT: tag = "c:doughnutChart"; break;
                    case ChartKind.SCATTER: tag = "c:scatterChart"; break;
                    case ChartKind.BUBBLE: tag = "c:bubbleChart"; break;
                    case ChartKind.RADAR: tag = "c:radarChart"; break;
                    default:
                        tag = kind == SeriesKind.LINE ? "c:lineChart" : (kind == SeriesKind.AREA ? "c:areaChart" : "c:barChart");
                        break;
                }
                bool is_bar = tag == "c:barChart";
                string grouping = ch.grouping == ChartGrouping.STACKED ? "stacked" : (ch.grouping == ChartGrouping.PERCENT ? "percentStacked" : (is_bar ? "clustered" : "standard"));
                x.start (tag);
                if (is_bar) x.start ("c:barDir").a ("val", ch.chart == ChartKind.BAR ? "bar" : "col").end ();
                if (tag == "c:scatterChart") x.start ("c:scatterStyle").a ("val", ch.smooth ? "smoothMarker" : "lineMarker").end ();
                else if (tag == "c:radarChart") x.start ("c:radarStyle").a ("val", ch.grouping == ChartGrouping.STACKED ? "filled" : "marker").end ();
                else if (!radial && tag != "c:bubbleChart") x.start ("c:grouping").a ("val", grouping).end ();
                x.start ("c:varyColors").a ("val", radial ? "1" : "0").end ();
                foreach (int i in members[key]) series_xml (x, ch, i, kind, ncat, cat_f);
                dlbls (x, ch);
                switch (tag) {
                    case "c:barChart":
                        x.start ("c:gapWidth").a ("val", "150").end ();
                        if (ch.grouping != ChartGrouping.CLUSTERED) x.start ("c:overlap").a ("val", "100").end ();
                        break;
                    case "c:lineChart":
                        x.start ("c:marker").a ("val", "1").end ();
                        break;
                    case "c:pieChart":
                        x.start ("c:firstSliceAng").a ("val", "0").end ();
                        break;
                    case "c:doughnutChart":
                        x.start ("c:firstSliceAng").a ("val", "0").end ();
                        x.start ("c:holeSize").a ("val", "55").end ();
                        break;
                    case "c:bubbleChart":
                        x.start ("c:bubbleScale").a ("val", "100").end ();
                        x.start ("c:showNegBubbles").a ("val", "0").end ();
                        break;
                    default:
                        break;
                }
                if (!radial) {
                    x.start ("c:axId").a ("val", sec ? "500000003" : "500000001").end ();
                    x.start ("c:axId").a ("val", sec ? "500000004" : "500000002").end ();
                }
                x.end ();
            }
            if (!radial) {
                bool bar = ch.chart == ChartKind.BAR;
                bool xy = ch.chart == ChartKind.SCATTER || ch.chart == ChartKind.BUBBLE;
                if (xy) axis (x, "c:valAx", "500000001", "500000002", "b", false, ch.cat_axis);
                else axis (x, "c:catAx", "500000001", "500000002", bar ? "l" : "b", false, ch.cat_axis);
                axis (x, "c:valAx", "500000002", "500000001", bar ? "b" : "l", ch.gridlines, ch.val_axis);
                if (used_sec) {
                    if (xy) axis (x, "c:valAx", "500000003", "500000004", "b", false, ch.cat_axis, true);
                    else axis (x, "c:catAx", "500000003", "500000004", "b", false, ch.cat_axis, true);
                    axis (x, "c:valAx", "500000004", "500000003", "r", false, ch.sec_axis, false, true);
                }
            }
            x.end ();
            if (ch.legend != LegendPosition.NONE) {
                string pos;
                switch (ch.legend) {
                    case LegendPosition.RIGHT: pos = "r"; break;
                    case LegendPosition.TOP: pos = "t"; break;
                    case LegendPosition.LEFT: pos = "l"; break;
                    default: pos = "b"; break;
                }
                x.start ("c:legend").start ("c:legendPos").a ("val", pos).end ().start ("c:overlay").a ("val", "0").end ().end ();
            }
            x.start ("c:plotVisOnly").a ("val", "1").end ();
            x.start ("c:dispBlanksAs").a ("val", "gap").end ();
            x.end ();
            if (ch.text_color != "") {
                x.start ("c:txPr");
                x.empty ("a:bodyPr");
                x.empty ("a:lstStyle");
                x.start ("a:p").start ("a:pPr").start ("a:defRPr");
                solid (x, ch.text_color);
                x.end ().end ().start ("a:endParaRPr").a ("lang", "en-US").end ().end ();
                x.end ();
            }
            if (wb_rid != null) x.start ("c:externalData").a ("r:id", wb_rid).start ("c:autoUpdate").a ("val", "0").end ().end ();
            x.end ();
            return x.finish ();
        }

        private void group (XmlOut x, GroupElement g) {
            x.start ("p:grpSp");
            x.start ("p:nvGrpSpPr");
            c_nv_pr (x, g);
            x.start ("p:cNvGrpSpPr");
            if (g.locked) x.start ("a:grpSpLocks").a ("noMove", "1").a ("noResize", "1").end ();
            x.end ();
            nv_pr (x, g);
            x.end ();
            x.start ("p:grpSpPr");
            x.start ("a:xfrm");
            if (g.rotation != 0) {
                double r = g.rotation % 360;
                if (r < 0) r += 360;
                x.ai ("rot", (int64) Math.round (r * 60000));
            }
            if (g.flip_h) x.a ("flipH", "1");
            if (g.flip_v) x.a ("flipV", "1");
            x.start ("a:off").ai ("x", Ooxml.emu (g.x)).ai ("y", Ooxml.emu (g.y)).end ();
            x.start ("a:ext").ai ("cx", Ooxml.emu (double.max (g.w, 0))).ai ("cy", Ooxml.emu (double.max (g.h, 0))).end ();
            x.start ("a:chOff").ai ("x", Ooxml.emu (g.x)).ai ("y", Ooxml.emu (g.y)).end ();
            x.start ("a:chExt").ai ("cx", Ooxml.emu (double.max (g.w, 0))).ai ("cy", Ooxml.emu (double.max (g.h, 0))).end ();
            x.end ();
            x.end ();
            foreach (var c in g.children) element (x, c);
            x.end ();
        }

        private void level_ppr (XmlOut x, LevelStyle l, string tag) {
            x.start (tag);
            if (l.margin >= 0) {
                x.ai ("marL", Ooxml.emu (l.margin));
                x.ai ("indent", Ooxml.emu (l.indent));
            }
            string? algn = align_value (l.align);
            if (algn != null) x.a ("algn", algn);
            if (l.line_spacing > 0) x.start ("a:lnSpc").start ("a:spcPct").a ("val", Ooxml.pct (l.line_spacing)).end ().end ();
            if (l.space_before >= 0) x.start ("a:spcBef").start ("a:spcPts").ai ("val", (int64) Math.round (l.space_before * 100)).end ().end ();
            if (l.space_after >= 0) x.start ("a:spcAft").start ("a:spcPts").ai ("val", (int64) Math.round (l.space_after * 100)).end ().end ();
            switch (l.bullet) {
                case BulletKind.NONE:
                    x.empty ("a:buNone");
                    break;
                case BulletKind.CHAR:
                    x.start ("a:buFont").a ("typeface", "Arial").end ();
                    x.start ("a:buChar").a ("char", l.bullet_char != "" ? l.bullet_char : "•").end ();
                    break;
                case BulletKind.NUMBER:
                    x.start ("a:buAutoNum").a ("type", "arabicPeriod").end ();
                    break;
                default:
                    break;
            }
            x.start ("a:defRPr");
            if (l.size > 0) x.ai ("sz", (int64) Math.round (l.size * 100));
            if (l.bold >= 0) x.a ("b", l.bold == 1 ? "1" : "0");
            if (l.italic >= 0) x.a ("i", l.italic == 1 ? "1" : "0");
            if (l.caps) x.a ("cap", "all");
            if (l.color != "") solid (x, l.color);
            if (l.font != "") x.start ("a:latin").a ("typeface", l.font).end ();
            x.end ();
            x.end ();
        }

        private void lst_style (XmlOut x, TextStyle? ts, string tag, bool always = false) {
            if (ts == null || ts.is_empty ()) {
                if (always) x.empty (tag);
                return;
            }
            x.start (tag);
            for (int i = 0; i < 9; i++) {
                if (ts.levels[i].is_empty () && !ts.levels[i].caps) continue;
                level_ppr (x, ts.levels[i], "a:lvl%dpPr".printf (i + 1));
            }
            x.end ();
        }

        private static string? align_value (TextAlign a) {
            switch (a) {
                case TextAlign.LEFT: return "l";
                case TextAlign.CENTER: return "ctr";
                case TextAlign.RIGHT: return "r";
                case TextAlign.JUSTIFY: return "just";
                default: return null;
            }
        }

        private void text_body (XmlOut x, TextBody b, TextStyle? ls, string tag, bool write) {
            if (!write) return;
            x.start (tag);
            x.start ("a:bodyPr").ai ("lIns", Ooxml.emu (b.inset_left)).ai ("tIns", Ooxml.emu (b.inset_top))
                .ai ("rIns", Ooxml.emu (b.inset_right)).ai ("bIns", Ooxml.emu (b.inset_bottom))
                .a ("wrap", b.wrap ? "square" : "none").a ("rtlCol", "0");
            if (b.columns > 1) x.ai ("numCol", b.columns);
            if (b.vertical) x.a ("vert", "vert");
            if (b.anchor_set) x.a ("anchor", b.anchor == TextAnchor.MIDDLE ? "ctr" : (b.anchor == TextAnchor.BOTTOM ? "b" : "t"));
            if (text_fx != null && text_fx.text_warp != "") x.start ("a:prstTxWarp").a ("prst", text_fx.text_warp).empty ("a:avLst").end ();
            switch (b.autofit) {
                case AutoFit.SHRINK:
                    x.start ("a:normAutofit");
                    if (b.font_scale < 1) x.a ("fontScale", Ooxml.pct (b.font_scale));
                    if (b.line_reduction > 0) x.a ("lnSpcReduction", Ooxml.pct (b.line_reduction));
                    x.end ();
                    break;
                case AutoFit.RESIZE:
                    x.empty ("a:spAutoFit");
                    break;
                default:
                    x.empty ("a:noAutofit");
                    break;
            }
            x.end ();
            lst_style (x, ls, "a:lstStyle", true);
            if (b.paragraphs.size == 0) x.empty ("a:p");
            foreach (var p in b.paragraphs) paragraph (x, p);
            x.end ();
        }

        private void paragraph (XmlOut x, Paragraph p) {
            x.start ("a:p");
            bool ppr = p.align != TextAlign.INHERIT || p.level > 0 || p.bullet != BulletKind.INHERIT || p.line_spacing > 0
                || p.space_before >= 0 || p.space_after >= 0 || p.bullet_color != "";
            if (ppr) {
                x.start ("a:pPr");
                if (p.level > 0) x.ai ("lvl", p.level);
                string? algn = align_value (p.align);
                if (algn != null) x.a ("algn", algn);
                if (p.line_spacing > 0) x.start ("a:lnSpc").start ("a:spcPct").a ("val", Ooxml.pct (p.line_spacing)).end ().end ();
                if (p.space_before >= 0) x.start ("a:spcBef").start ("a:spcPts").ai ("val", (int64) Math.round (p.space_before * 100)).end ().end ();
                if (p.space_after >= 0) x.start ("a:spcAft").start ("a:spcPts").ai ("val", (int64) Math.round (p.space_after * 100)).end ().end ();
                if (p.bullet_color != "") {
                    x.start ("a:buClr");
                    color (x, p.bullet_color);
                    x.end ();
                }
                switch (p.bullet) {
                    case BulletKind.NONE:
                        x.empty ("a:buNone");
                        break;
                    case BulletKind.CHAR:
                        x.start ("a:buChar").a ("char", p.bullet_char != "" ? p.bullet_char : "•").end ();
                        break;
                    case BulletKind.NUMBER:
                        x.start ("a:buAutoNum").a ("type", p.number_style.to_ooxml ());
                        if (p.number_start != 1) x.ai ("startAt", p.number_start);
                        x.end ();
                        break;
                    default:
                        break;
                }
                x.end ();
            }
            foreach (var r in p.runs) run (x, r);
            if (rpr_attrs (p.end_format)) rpr (x, p.end_format, "a:endParaRPr");
            x.end ();
        }

        private static bool rpr_attrs (TextRun r) {
            return r.bold >= 0 || r.italic >= 0 || r.underline >= 0 || r.strike >= 0 || r.size > 0 || r.font != ""
                || r.color != "" || r.highlight != "" || r.baseline != 0;
        }

        private void rpr (XmlOut x, TextRun r, string tag) {
            x.start (tag).a ("lang", "en-US");
            if (r.size > 0) x.ai ("sz", (int64) Math.round (r.size * 100));
            if (r.bold >= 0) x.a ("b", r.bold == 1 ? "1" : "0");
            if (r.italic >= 0) x.a ("i", r.italic == 1 ? "1" : "0");
            if (r.underline >= 0) x.a ("u", r.underline == 1 ? "sng" : "none");
            if (r.strike >= 0) x.a ("strike", r.strike == 1 ? "sngStrike" : "noStrike");
            if (r.baseline > 0) x.a ("baseline", "30000");
            else if (r.baseline < 0) x.a ("baseline", "-25000");
            x.a ("dirty", "0");
            if (text_fx != null && text_fx.text_outline != "") {
                x.start ("a:ln").ai ("w", Ooxml.emu (text_fx.text_outline_width));
                solid (x, text_fx.text_outline);
                x.end ();
            }
            if (text_fx != null && text_fx.text_fill.contains (">")) {
                string[] gp = text_fx.text_fill.split (">");
                x.start ("a:gradFill").start ("a:gsLst");
                x.start ("a:gs").a ("pos", "0");
                color (x, gp[0]);
                x.end ();
                x.start ("a:gs").a ("pos", "100000");
                color (x, gp[1]);
                x.end ();
                x.end ();
                x.start ("a:lin").a ("ang", "5400000").a ("scaled", "0").end ();
                x.end ();
            } else if (text_fx != null && text_fx.text_fill != "") {
                solid (x, text_fx.text_fill);
            } else if (r.color != "") {
                solid (x, r.color);
            }
            if (text_fx != null && ((text_fx.text_glow != "" && text_fx.text_glow_radius > 0) || text_fx.text_shadow || text_fx.text_reflection)) {
                x.start ("a:effectLst");
                if (text_fx.text_glow != "" && text_fx.text_glow_radius > 0) {
                    x.start ("a:glow").ai ("rad", Ooxml.emu (text_fx.text_glow_radius));
                    color (x, ColorSpec.with_alpha (text_fx.text_glow, 0.6));
                    x.end ();
                }
                if (text_fx.text_shadow) x.start ("a:outerShdw").a ("blurRad", "38100").a ("dist", "38100").a ("dir", "2700000").a ("algn", "tl").start ("a:srgbClr").a ("val", "000000").start ("a:alpha").a ("val", "43137").end ().end ().end ();
                if (text_fx.text_reflection) x.start ("a:reflection").a ("blurRad", "6350").a ("stA", "55000").a ("endA", "300").a ("endPos", "45500").a ("dir", "5400000").a ("sy", "-100000").a ("algn", "bl").a ("rotWithShape", "0").end ();
                x.end ();
            }
            if (r.highlight != "") {
                x.start ("a:highlight");
                color (x, r.highlight);
                x.end ();
            }
            if (r.font != "") x.start ("a:latin").a ("typeface", r.font).end ();
            if (r.link != "" && tag == "a:rPr") {
                var la = LinkTarget.to_action (r.link);
                if (la != null) {
                    la.highlight = false;
                    action (x, "a:hlinkClick", la);
                }
            }
            x.end ();
        }

        private void run (XmlOut x, TextRun r) {
            if (r.field != "") {
                field_count++;
                string type = r.field;
                x.start ("a:fld").a ("id", "{5B1C7E2A-3D4F-4A6B-9C8D-%012X}".printf (field_count)).a ("type", type);
                rpr (x, r, "a:rPr");
                x.element ("a:t", r.text);
                x.end ();
                return;
            }
            string text = r.text.replace ("\n", "\v");
            string[] segs = text.split ("\v");
            for (int i = 0; i < segs.length; i++) {
                if (i > 0) {
                    x.start ("a:br");
                    rpr (x, r, "a:rPr");
                    x.end ();
                }
                if (segs[i] == "" && segs.length > 1) continue;
                x.start ("a:r");
                rpr (x, r, "a:rPr");
                x.element ("a:t", segs[i]);
                x.end ();
            }
        }

        private void open_part (XmlOut x, string tag) {
            x.start (tag).a ("xmlns:a", Ooxml.NS_A).a ("xmlns:r", Ooxml.NS_R).a ("xmlns:p", Ooxml.NS_P);
        }

        private void background (XmlOut x, Fill? bg) {
            if (bg == null) return;
            x.start ("p:bg").start ("p:bgPr");
            fill (x, bg, true);
            x.empty ("a:effectLst");
            x.end ().end ();
        }

        private string master_xml (Master m, Gee.List<int64?> layout_ids, Gee.List<string> layout_rids) {
            prepare_ids (m.elements);
            var x = new XmlOut ();
            open_part (x, "p:sldMaster");
            x.start ("p:cSld");
            if (m.name != "") x.a ("name", m.name);
            background (x, m.background);
            sp_tree (x, m.elements);
            x.end ();
            x.start ("p:clrMap").a ("bg1", "lt1").a ("tx1", "dk1").a ("bg2", "lt2").a ("tx2", "dk2")
                .a ("accent1", "accent1").a ("accent2", "accent2").a ("accent3", "accent3").a ("accent4", "accent4")
                .a ("accent5", "accent5").a ("accent6", "accent6").a ("hlink", "hlink").a ("folHlink", "folHlink").end ();
            x.start ("p:sldLayoutIdLst");
            for (int i = 0; i < layout_ids.size; i++) x.start ("p:sldLayoutId").ai ("id", layout_ids[i]).a ("r:id", layout_rids[i]).end ();
            x.end ();
            x.start ("p:txStyles");
            lst_style (x, m.title_style, "p:titleStyle", true);
            lst_style (x, m.body_style, "p:bodyStyle", true);
            lst_style (x, m.other_style, "p:otherStyle", true);
            x.end ();
            x.end ();
            return x.finish ();
        }

        private string layout_xml (Layout l) {
            prepare_ids (l.elements);
            var x = new XmlOut ();
            open_part (x, "p:sldLayout");
            x.a ("type", l.kind.to_ooxml ()).a ("preserve", "1");
            if (!l.show_master_shapes) x.a ("showMasterSp", "0");
            x.start ("p:cSld").a ("name", l.name);
            background (x, l.background);
            sp_tree (x, l.elements);
            x.end ();
            x.start ("p:clrMapOvr").empty ("a:masterClrMapping").end ();
            x.start ("p:extLst").start ("p:ext").a ("uri", Ooxml.EXT_URI);
            x.start ("sg:layout").a ("xmlns:sg", Ooxml.NS_SG).a ("kind", ((int) l.kind).to_string ()).a ("id", l.id).end ();
            x.end ().end ();
            x.end ();
            return x.finish ();
        }

        private string slide_xml (Slide s) {
            prepare_ids (s.elements);
            var x = new XmlOut ();
            open_part (x, "p:sld");
            if (s.hidden) x.a ("show", "0");
            if (!s.show_master_shapes) x.a ("showMasterSp", "0");
            x.start ("p:cSld");
            if (s.name != "") x.a ("name", s.name);
            background (x, s.background);
            sp_tree (x, s.elements);
            extras_named (x, s.extras, { "custDataLst", "controls" });
            x.end ();
            x.start ("p:clrMapOvr").empty ("a:masterClrMapping").end ();
            transition (x, s.transition);
            timing (x, s);
            extras_named (x, s.extras, { "extLst" });
            x.end ();
            return x.finish ();
        }

        private void transition_element (XmlOut x, Transition t, bool rich) {
            x.start ("p:transition");
            double d = t.duration;
            x.a ("spd", d < 0.6 ? "fast" : (d < 0.9 ? "med" : "slow"));
            if (rich) x.ai ("p14:dur", (int64) Math.round (d * 1000));
            if (!t.on_click) x.a ("advClick", "0");
            if (t.advance_after >= 0) x.ai ("advTm", (int64) Math.round (t.advance_after * 1000));
            if (t.kind != TransitionKind.NONE) TransitionCodec.write (x, t, rich);
            if (t.sound_data != null) {
                x.start ("p:sndAc").start ("p:stSnd");
                if (t.sound_loop) x.a ("loop", "1");
                x.start ("p:snd").a ("r:embed", rels.add (Ooxml.REL_AUDIO, relative (current_part, sound_part (t.sound_data)))).a ("name", t.sound != "" ? t.sound : "sound.wav").end ();
                x.end ().end ();
            }
            x.end ();
        }

        private Gee.HashMap<Bytes, string> sounds = new Gee.HashMap<Bytes, string> ();

        private string sound_part (Bytes data) {
            if (sounds.has_key (data)) return sounds[data];
            string name = unique_name ("ppt/media/audio%d.wav".printf (sounds.size + 1));
            add_bytes_part (name, data, "audio/wav");
            sounds[data] = name;
            return name;
        }

        private void transition (XmlOut x, Transition t) {
            if (t.kind == TransitionKind.NONE && t.on_click && t.advance_after < 0 && t.sound_data == null) return;
            string req = TransitionCodec.requires (t);
            string ns = req == "p159" ? Ooxml.NS_P159 : (req == "p15" ? Ooxml.NS_P15 : Ooxml.NS_P14);
            x.start ("mc:AlternateContent").a ("xmlns:mc", Ooxml.NS_MC);
            x.start ("mc:Choice").a ("xmlns:p14", Ooxml.NS_P14);
            if (req == "p15" || req == "p159") x.a ("xmlns:" + req, ns);
            x.a ("Requires", req == "" ? "p14" : req);
            transition_element (x, t, true);
            x.end ();
            x.start ("mc:Fallback");
            transition_element (x, t, false);
            x.end ();
            x.end ();
        }

        private void cond (XmlOut x, string delay) {
            x.start ("p:stCondLst").start ("p:cond").a ("delay", delay).end ().end ();
        }

        private int tgt_para = -1;

        private void tgt (XmlOut x, int spid) {
            x.start ("p:tgtEl").start ("p:spTgt").ai ("spid", spid);
            if (tgt_para >= 0) x.start ("p:txEl").start ("p:pRg").ai ("st", tgt_para).ai ("end", tgt_para).end ().end ();
            x.end ().end ();
        }

        private void set_prop (XmlOut x, int spid, string attr, string val, int delay_ms, int dur = 1) {
            x.start ("p:set").start ("p:cBhvr");
            x.start ("p:cTn").ai ("id", ++ctn).ai ("dur", dur).a ("fill", "hold");
            cond (x, delay_ms.to_string ());
            x.end ();
            tgt (x, spid);
            x.start ("p:attrNameLst").element ("p:attrName", attr).end ();
            x.end ();
            x.start ("p:to").start ("p:strVal").a ("val", val).end ().end ();
            x.end ();
        }

        private void set_visibility (XmlOut x, int spid, bool visible, int delay_ms) {
            set_prop (x, spid, "style.visibility", visible ? "visible" : "hidden", delay_ms);
        }

        private void anim_effect (XmlOut x, int spid, bool entrance, string filter, int dur) {
            x.start ("p:animEffect").a ("transition", entrance ? "in" : "out").a ("filter", filter);
            x.start ("p:cBhvr");
            x.start ("p:cTn").ai ("id", ++ctn).ai ("dur", dur).end ();
            tgt (x, spid);
            x.end ();
            x.end ();
        }

        private void anim_prop (XmlOut x, int spid, string attr, string from, string to, int dur, string vtype = "num", bool auto_rev = false) {
            x.start ("p:anim").a ("calcmode", "lin").a ("valueType", vtype);
            x.start ("p:cBhvr").a ("additive", "base");
            x.start ("p:cTn").ai ("id", ++ctn).ai ("dur", dur).a ("fill", "hold");
            if (auto_rev) x.a ("autoRev", "1");
            x.end ();
            tgt (x, spid);
            x.start ("p:attrNameLst").element ("p:attrName", attr).end ();
            x.end ();
            x.start ("p:tavLst");
            x.start ("p:tav").a ("tm", "0").start ("p:val").start ("p:strVal").a ("val", from).end ().end ().end ();
            x.start ("p:tav").a ("tm", "100000").start ("p:val").start ("p:strVal").a ("val", to).end ().end ().end ();
            x.end ();
            x.end ();
        }

        private void anim_scale (XmlOut x, int spid, int dur, int from_pct, int to_pct, bool by, bool auto_rev) {
            x.start ("p:animScale");
            x.start ("p:cBhvr");
            x.start ("p:cTn").ai ("id", ++ctn).ai ("dur", dur).a ("fill", "hold");
            if (auto_rev) x.a ("autoRev", "1");
            x.end ();
            tgt (x, spid);
            x.end ();
            if (by) {
                x.start ("p:by").ai ("x", to_pct).ai ("y", to_pct).end ();
            } else {
                x.start ("p:from").ai ("x", from_pct).ai ("y", from_pct).end ();
                x.start ("p:to").ai ("x", to_pct).ai ("y", to_pct).end ();
            }
            x.end ();
        }

        private void anim_rot (XmlOut x, int spid, int dur, double degrees, bool auto_rev = false, int delay = 0) {
            x.start ("p:animRot").ai ("by", (int64) Math.round (degrees * 60000));
            x.start ("p:cBhvr");
            x.start ("p:cTn").ai ("id", ++ctn).ai ("dur", dur).a ("fill", "hold");
            if (auto_rev) x.a ("autoRev", "1");
            if (delay > 0) {
                cond (x, delay.to_string ());
                x.end ();
            } else {
                x.end ();
            }
            tgt (x, spid);
            x.start ("p:attrNameLst").element ("p:attrName", "r").end ();
            x.end ();
            x.end ();
        }

        private void anim_color (XmlOut x, int spid, int dur, string attr, string? color, int h, int sat, int l, bool auto_rev = false) {
            x.start ("p:animClr").a ("clrSpc", color != null ? "rgb" : "hsl").a ("dir", "cw");
            x.start ("p:cBhvr");
            x.start ("p:cTn").ai ("id", ++ctn).ai ("dur", dur).a ("fill", "hold");
            if (auto_rev) x.a ("autoRev", "1");
            x.end ();
            tgt (x, spid);
            x.start ("p:attrNameLst").element ("p:attrName", attr).end ();
            x.end ();
            if (color != null) {
                x.start ("p:to");
                color_el (x, color);
                x.end ();
            } else {
                x.start ("p:by").start ("p:hsl").ai ("h", h).ai ("s", sat).ai ("l", l).end ().end ();
            }
            x.end ();
        }

        private void color_el (XmlOut x, string spec) {
            color (x, spec);
        }

        private static string filter_for (Animation a) {
            int s = a.subtype;
            switch (a.effect) {
                case AnimEffect.WIPE:
                case AnimEffect.PEEK:
                    if ((s & 8) != 0) return "wipe(right)";
                    if ((s & 2) != 0) return "wipe(left)";
                    if ((s & 1) != 0) return "wipe(down)";
                    return "wipe(up)";
                case AnimEffect.SPLIT:
                    switch (s) {
                        case 37: return "barn(outVertical)";
                        case 26: return "barn(inHorizontal)";
                        case 42: return "barn(outHorizontal)";
                        default: return "barn(inVertical)";
                    }
                case AnimEffect.BLINDS: return s == 5 ? "blinds(vertical)" : "blinds(horizontal)";
                case AnimEffect.CHECKERBOARD: return s == 5 ? "checkerboard(down)" : "checkerboard(across)";
                case AnimEffect.RANDOM_BARS: return s == 5 ? "randombar(vertical)" : "randombar(horizontal)";
                case AnimEffect.STRIPS:
                    switch (s) {
                        case 9: return "strips(upLeft)";
                        case 6: return "strips(downRight)";
                        case 3: return "strips(upRight)";
                        default: return "strips(downLeft)";
                    }
                case AnimEffect.BOX: return s == 32 ? "box(out)" : "box(in)";
                case AnimEffect.CIRCLE: return s == 32 ? "circle(out)" : "circle(in)";
                case AnimEffect.DIAMOND: return s == 32 ? "diamond(out)" : "diamond(in)";
                case AnimEffect.PLUS: return s == 32 ? "plus(out)" : "plus(in)";
                case AnimEffect.WEDGE: return "wedge";
                case AnimEffect.WHEEL: return "wheel(%d)".printf (int.max (s, 1));
                case AnimEffect.DISSOLVE: return "dissolve";
                case AnimEffect.SWISH: return "slide(fromLeft)";
                default: return "fade";
            }
        }

        private static string motion_path (Gee.List<PathCommand> path) {
            var sb = new StringBuilder ();
            foreach (var c in path) {
                switch (c.op) {
                    case 'M': sb.append ("M %s %s ".printf (XmlOut.num (c.pts[0]), XmlOut.num (c.pts[1]))); break;
                    case 'L': sb.append ("L %s %s ".printf (XmlOut.num (c.pts[0]), XmlOut.num (c.pts[1]))); break;
                    case 'C':
                        sb.append ("C");
                        foreach (double v in c.pts) sb.append (" " + XmlOut.num (v));
                        sb.append (" ");
                        break;
                    case 'Q':
                        sb.append ("C %s %s %s %s %s %s ".printf (XmlOut.num (c.pts[0]), XmlOut.num (c.pts[1]), XmlOut.num (c.pts[0]), XmlOut.num (c.pts[1]), XmlOut.num (c.pts[2]), XmlOut.num (c.pts[3])));
                        break;
                    case 'Z': sb.append ("Z "); break;
                    default: break;
                }
            }
            sb.append ("E");
            return sb.str;
        }

        private void effect_behaviours (XmlOut x, Animation a, int spid, MediaElement? media) {
            int dur = (int) Math.round (a.duration * 1000);
            if (dur < 1) dur = 1;
            switch (a.anim_class) {
                case AnimClass.MEDIA:
                    string cmd;
                    if (a.effect == AnimEffect.MEDIA_PAUSE) cmd = "togglePause";
                    else if (a.effect == AnimEffect.MEDIA_STOP) cmd = "stop";
                    else cmd = "playFrom(" + XmlOut.num (media != null ? media.trim_start : 0) + ")";
                    int mdur = media != null && media.play_length () > 0 ? (int) Math.round (media.play_length () * 1000) : 1;
                    x.start ("p:cmd").a ("type", "call").a ("cmd", cmd);
                    x.start ("p:cBhvr");
                    x.start ("p:cTn").ai ("id", ++ctn).ai ("dur", a.effect == AnimEffect.MEDIA_PLAY ? mdur : 1).a ("fill", "hold").end ();
                    tgt (x, spid);
                    x.end ();
                    x.end ();
                    return;
                case AnimClass.PATH:
                    x.start ("p:animMotion").a ("origin", "layout").a ("path", motion_path (a.path)).a ("pathEditMode", "relative").a ("rAng", "0").a ("ptsTypes", "");
                    x.start ("p:cBhvr");
                    x.start ("p:cTn").ai ("id", ++ctn).ai ("dur", dur).a ("fill", "hold").end ();
                    tgt (x, spid);
                    x.start ("p:attrNameLst").element ("p:attrName", "ppt_x").element ("p:attrName", "ppt_y").end ();
                    x.end ();
                    if (a.path_rotate) x.a ("rAng", "0");
                    x.end ();
                    return;
                case AnimClass.EMPHASIS:
                    emphasis (x, a, spid, dur);
                    return;
                default:
                    break;
            }
            bool entrance = a.anim_class == AnimClass.ENTRANCE;
            if (entrance) set_visibility (x, spid, true, 0);
            double dx, dy;
            EffectCatalog.vector (a.subtype, out dx, out dy);
            string sx = entrance ? "from" : "to";
            switch (a.effect) {
                case AnimEffect.APPEAR:
                    break;
                case AnimEffect.FLASH_ONCE:
                    set_prop (x, spid, "style.visibility", "visible", 0, dur);
                    if (entrance) set_visibility (x, spid, false, dur);
                    break;
                case AnimEffect.FLY:
                case AnimEffect.CRAWL:
                case AnimEffect.CREDITS:
                    if (a.effect == AnimEffect.CREDITS) {
                        dx = 0;
                        dy = entrance ? 1 : -1;
                    }
                    string ox = dx < 0 ? "0-#ppt_w/2" : (dx > 0 ? "1+#ppt_w/2" : "#ppt_x");
                    string oy = dy < 0 ? "0-#ppt_h/2" : (dy > 0 ? "1+#ppt_h/2" : "#ppt_y");
                    anim_prop (x, spid, "ppt_x", entrance ? ox : "#ppt_x", entrance ? "#ppt_x" : ox, dur);
                    anim_prop (x, spid, "ppt_y", entrance ? oy : "#ppt_y", entrance ? "#ppt_y" : oy, dur);
                    break;
                case AnimEffect.PEEK:
                    anim_effect (x, spid, entrance, filter_for (a), dur);
                    string px = dx < 0 ? "#ppt_x-#ppt_w" : (dx > 0 ? "#ppt_x+#ppt_w" : "#ppt_x");
                    string py = dy < 0 ? "#ppt_y-#ppt_h" : (dy > 0 ? "#ppt_y+#ppt_h" : "#ppt_y");
                    anim_prop (x, spid, "ppt_x", entrance ? px : "#ppt_x", entrance ? "#ppt_x" : px, dur);
                    anim_prop (x, spid, "ppt_y", entrance ? py : "#ppt_y", entrance ? "#ppt_y" : py, dur);
                    break;
                case AnimEffect.FLOAT:
                case AnimEffect.RISE_UP:
                case AnimEffect.ARC_UP:
                    anim_effect (x, spid, entrance, "fade", dur);
                    string off = dy < 0 ? "#ppt_y-.1" : "#ppt_y+.1";
                    string offx = dx < 0 ? "#ppt_x-.1" : "#ppt_x+.1";
                    if (dx != 0 && a.effect == AnimEffect.FLOAT) anim_prop (x, spid, "ppt_x", entrance ? offx : "#ppt_x", entrance ? "#ppt_x" : offx, dur);
                    else anim_prop (x, spid, "ppt_y", entrance ? off : "#ppt_y", entrance ? "#ppt_y" : off, dur);
                    break;
                case AnimEffect.ZOOM:
                case AnimEffect.EXPAND:
                case AnimEffect.EASE_IN:
                case AnimEffect.BASIC_ZOOM:
                case AnimEffect.COMPRESS:
                case AnimEffect.STRETCH:
                case AnimEffect.FLIP:
                case AnimEffect.SWIVEL:
                case AnimEffect.FADE_SWIVEL:
                case AnimEffect.UNFOLD:
                case AnimEffect.FOLD:
                case AnimEffect.GLIDE:
                case AnimEffect.ZIP:
                    if (a.effect != AnimEffect.STRETCH && a.effect != AnimEffect.SWIVEL && a.effect != AnimEffect.FLIP) anim_effect (x, spid, entrance, "fade", dur);
                    string wfrom = "0", hfrom = "0";
                    switch (a.effect) {
                        case AnimEffect.EXPAND: wfrom = "#ppt_w*0.70"; hfrom = "#ppt_h"; break;
                        case AnimEffect.EASE_IN: wfrom = "#ppt_w*1.5"; hfrom = "#ppt_h*1.5"; break;
                        case AnimEffect.BASIC_ZOOM: if (a.subtype == 32) { wfrom = "#ppt_w*4"; hfrom = "#ppt_h*4"; } break;
                        case AnimEffect.COMPRESS: wfrom = "#ppt_w"; hfrom = "#ppt_h*3"; break;
                        case AnimEffect.STRETCH: case AnimEffect.SWIVEL: case AnimEffect.FLIP: case AnimEffect.FADE_SWIVEL: case AnimEffect.UNFOLD: hfrom = "#ppt_h"; break;
                        case AnimEffect.FOLD: case AnimEffect.ZIP: wfrom = "#ppt_w"; break;
                        case AnimEffect.GLIDE: wfrom = "#ppt_w*0.05"; hfrom = "#ppt_h"; break;
                        default: break;
                    }
                    anim_prop (x, spid, "ppt_w", entrance ? wfrom : "#ppt_w", entrance ? "#ppt_w" : wfrom, dur);
                    anim_prop (x, spid, "ppt_h", entrance ? hfrom : "#ppt_h", entrance ? "#ppt_h" : hfrom, dur);
                    break;
                case AnimEffect.GROW_TURN:
                case AnimEffect.SPINNER:
                case AnimEffect.PINWHEEL:
                case AnimEffect.CENTER_REVOLVE:
                case AnimEffect.BOOMERANG:
                case AnimEffect.SPIRAL:
                case AnimEffect.SLING:
                case AnimEffect.WHIP:
                case AnimEffect.LIGHT_SPEED:
                case AnimEffect.THIN_LINE:
                case AnimEffect.BOUNCE:
                    anim_effect (x, spid, entrance, "fade", dur);
                    double turn = a.effect == AnimEffect.PINWHEEL ? 720 : (a.effect == AnimEffect.GROW_TURN ? 90 : (a.effect == AnimEffect.SPINNER || a.effect == AnimEffect.CENTER_REVOLVE || a.effect == AnimEffect.SPIRAL ? 360 : 0));
                    if (a.effect == AnimEffect.BOUNCE || a.effect == AnimEffect.LIGHT_SPEED || a.effect == AnimEffect.WHIP || a.effect == AnimEffect.BOOMERANG) {
                        string o = a.effect == AnimEffect.BOUNCE ? "#ppt_y-0.25" : "1+#ppt_w/2";
                        anim_prop (x, spid, a.effect == AnimEffect.BOUNCE ? "ppt_y" : "ppt_x", entrance ? o : (a.effect == AnimEffect.BOUNCE ? "#ppt_y" : "#ppt_x"), entrance ? (a.effect == AnimEffect.BOUNCE ? "#ppt_y" : "#ppt_x") : o, dur);
                    } else {
                        anim_prop (x, spid, "ppt_w", entrance ? "0" : "#ppt_w", entrance ? "#ppt_w" : "0", dur);
                        anim_prop (x, spid, "ppt_h", entrance ? (a.effect == AnimEffect.THIN_LINE ? "#ppt_h*0.03" : "0") : "#ppt_h", entrance ? "#ppt_h" : "0", dur);
                    }
                    if (turn != 0) anim_rot (x, spid, dur, entrance ? -turn : turn);
                    break;
                case AnimEffect.FADE:
                    anim_effect (x, spid, entrance, "fade", dur);
                    break;
                default:
                    anim_effect (x, spid, entrance, filter_for (a), dur);
                    break;
            }
            if (!entrance) set_visibility (x, spid, false, int.max (dur - 1, 0));
            if (sx == "") return;
        }

        private void emphasis (XmlOut x, Animation a, int spid, int dur) {
            string c = a.color != "" ? a.color : "accent2";
            switch (a.effect) {
                case AnimEffect.SPIN:
                    anim_rot (x, spid, dur, a.amount != 0 ? a.amount : 360);
                    break;
                case AnimEffect.GROW:
                    int pct = (int) Math.round ((a.amount > 0 ? a.amount : 1.5) * 100000);
                    anim_scale (x, spid, dur, 100000, pct, true, false);
                    break;
                case AnimEffect.TEETER:
                    int q = int.max (dur / 4, 1);
                    anim_rot (x, spid, q, 4);
                    anim_rot (x, spid, q, -8, false, q);
                    anim_rot (x, spid, q, 8, false, q * 2);
                    anim_rot (x, spid, dur - q * 3 > 0 ? dur - q * 3 : 1, -4, false, q * 3);
                    break;
                case AnimEffect.TRANSPARENCY:
                    set_prop (x, spid, "style.opacity", XmlOut.num (1 - (a.amount > 0 ? a.amount : 0.5)), 0, dur);
                    break;
                case AnimEffect.FILL_COLOR:
                case AnimEffect.OBJECT_COLOR:
                    anim_color (x, spid, dur, "fillcolor", c, 0, 0, 0);
                    set_prop (x, spid, "fill.type", "solid", 0);
                    set_prop (x, spid, "fill.on", "true", 0);
                    break;
                case AnimEffect.COLOR_PULSE:
                    anim_color (x, spid, int.max (dur / 2, 1), "fillcolor", c, 0, 0, 0, true);
                    break;
                case AnimEffect.GROW_COLOR:
                    anim_scale (x, spid, dur, 100000, 110000, true, false);
                    anim_color (x, spid, dur, "style.color", c, 0, 0, 0);
                    break;
                case AnimEffect.LINE_COLOR:
                    anim_color (x, spid, dur, "stroke.color", c, 0, 0, 0);
                    set_prop (x, spid, "stroke.on", "true", 0);
                    break;
                case AnimEffect.FONT_COLOR:
                    anim_color (x, spid, dur, "style.color", c, 0, 0, 0);
                    break;
                case AnimEffect.COMPLEMENTARY:
                    anim_color (x, spid, dur, "fillcolor", null, 10800000, 0, 0);
                    break;
                case AnimEffect.CONTRASTING:
                    anim_color (x, spid, dur, "fillcolor", null, 5400000, 0, 0);
                    break;
                case AnimEffect.DARKEN:
                    anim_color (x, spid, dur, "fillcolor", null, 0, 0, -25000);
                    break;
                case AnimEffect.LIGHTEN:
                    anim_color (x, spid, dur, "fillcolor", null, 0, 0, 25000);
                    break;
                case AnimEffect.DESATURATE:
                    anim_color (x, spid, dur, "fillcolor", null, 0, -100000, 0);
                    break;
                case AnimEffect.BOLD_FLASH:
                case AnimEffect.BOLD_REVEAL:
                    set_prop (x, spid, "style.fontWeight", "bold", 0, dur);
                    break;
                case AnimEffect.UNDERLINE:
                    set_prop (x, spid, "style.textDecorationUnderline", "true", 0, dur);
                    break;
                case AnimEffect.WAVE:
                    anim_prop (x, spid, "ppt_y", "#ppt_y", "#ppt_y-0.03", int.max (dur / 2, 1), "num", true);
                    break;
                case AnimEffect.BLINK:
                    set_prop (x, spid, "style.visibility", "hidden", 0, int.max (dur / 2, 1));
                    set_prop (x, spid, "style.visibility", "visible", int.max (dur / 2, 1), int.max (dur - dur / 2, 1));
                    break;
                case AnimEffect.FLICKER:
                case AnimEffect.SHIMMER:
                    anim_prop (x, spid, "style.opacity", "1", "0.3", int.max (dur / 2, 1), "num", true);
                    break;
                default:
                    anim_scale (x, spid, dur / 2 > 0 ? dur / 2 : 1, 100000, 105000, true, true);
                    break;
            }
        }

        private string? raw_effect (Animation a, int spid) {
            if (a.raw == "" || a.raw_sig != a.signature () || spid != a.target) return null;
            Xml.Doc* doc = Xml.Parser.read_memory (a.raw, a.raw.length, null, null, Xml.ParserOption.NONET | Xml.ParserOption.HUGE | Xml.ParserOption.NOERROR | Xml.ParserOption.NOWARNING);
            if (doc == null) return null;
            Xml.Node* root = doc->get_root_element ();
            if (root == null) {
                delete doc;
                return null;
            }
            var list = new Gee.ArrayList<Xml.Node*> ();
            all_named_deep (root, "cTn", list);
            foreach (Xml.Node* c in list) c->set_prop ("id", (++ctn).to_string ());
            string mem;
            doc->dump_memory (out mem);
            delete doc;
            if (mem.has_prefix ("<?xml")) {
                int end = mem.index_of ("?>");
                if (end >= 0) mem = mem.substring (end + 2);
            }
            return mem.strip ();
        }

        private static void all_named_deep (Xml.Node* n, string name, Gee.List<Xml.Node*> list) {
            if (n->name == name) list.add (n);
            for (Xml.Node* c = n->children; c != null; c = c->next) {
                if (c->type == Xml.ElementType.ELEMENT_NODE) all_named_deep (c, name, list);
            }
        }

        private void effect_par (XmlOut x, Animation a, int spid, string node, MediaElement? media) {
            string? raw = raw_effect (a, spid);
            if (raw != null) {
                x.raw (raw);
                return;
            }
            int subtype = a.subtype;
            int preset_id = EffectCatalog.preset_id (a.effect, a.anim_class);
            if (a.effect == AnimEffect.FLOAT) {
                preset_id = (a.subtype & 1) != 0 ? 47 : 42;
                subtype = (a.subtype & 10) != 0 ? a.subtype : 0;
            }
            if (a.anim_class == AnimClass.PATH) {
                preset_id = a.path_preset.preset_id ();
                subtype = 0;
            }
            if (a.anim_class == AnimClass.MEDIA) subtype = 0;
            if (EffectCatalog.options (a.effect) == EffectOptions.NONE || EffectCatalog.options (a.effect) == EffectOptions.COLOR) subtype = 0;
            tgt_para = a.paragraph;
            x.start ("p:par");
            x.start ("p:cTn").ai ("id", ++ctn).ai ("presetID", preset_id).a ("presetClass", a.anim_class.to_ooxml ())
                .ai ("presetSubtype", subtype);
            if (a.repeat < 0) x.a ("repeatCount", "indefinite");
            else if (a.repeat > 1) x.ai ("repeatCount", (int64) Math.round (a.repeat * 1000));
            if (a.accel > 0) x.a ("accel", Ooxml.pct (a.accel));
            if (a.decel > 0) x.a ("decel", Ooxml.pct (a.decel));
            if (a.auto_reverse) x.a ("autoRev", "1");
            x.a ("fill", a.rewind ? "remove" : "hold").a ("grpId", "0").a ("nodeType", node);
            cond (x, ((int64) Math.round (a.delay * 1000)).to_string ());
            if (a.text_unit != TextUnit.ALL) {
                x.start ("p:iterate").a ("type", a.text_unit == TextUnit.WORD ? "wd" : "lt");
                x.start ("p:tmPct").a ("val", Ooxml.pct (a.unit_delay)).end ();
                x.end ();
            }
            x.start ("p:childTnLst");
            effect_behaviours (x, a, spid, media);
            if (a.after == AfterEffect.HIDE && a.anim_class != AnimClass.EXIT) set_visibility (x, spid, false, (int) Math.round (a.duration * 1000));
            if (a.after == AfterEffect.DIM && a.dim_color != "") {
                x.start ("p:set").start ("p:cBhvr");
                x.start ("p:cTn").ai ("id", ++ctn).a ("dur", "1").a ("fill", "hold");
                cond (x, ((int64) Math.round (a.duration * 1000)).to_string ());
                x.end ();
                tgt (x, spid);
                x.start ("p:attrNameLst").element ("p:attrName", "style.color").end ();
                x.end ();
                x.start ("p:to");
                color (x, a.dim_color);
                x.end ();
                x.end ();
            }
            x.end ();
            if (a.sound_data != null) {
                x.start ("p:subTnLst").start ("p:audio").start ("p:cMediaNode").a ("showWhenStopped", "0");
                x.start ("p:cTn").ai ("id", ++ctn).a ("display", "0").a ("masterRel", "sameClick");
                cond (x, "0");
                x.end ();
                x.start ("p:tgtEl").start ("p:sndTgt").a ("r:embed", rels.add (Ooxml.REL_AUDIO, relative (current_part, sound_part (a.sound_data)))).a ("name", a.sound != "" ? a.sound : "sound.wav").end ().end ();
                x.end ().end ().end ();
            }
            x.end ();
            x.end ();
            tgt_para = -1;
        }

        private void sequence_body (XmlOut x, Gee.List<Animation> anims, Gee.List<Element> targets, Slide s, int seq_id, bool interactive) {
            int i = 0;
            while (i < anims.size) {
                int group_end = i + 1;
                while (group_end < anims.size && anims[group_end].trigger != AnimTrigger.ON_CLICK) group_end++;
                bool auto_group = anims[i].trigger != AnimTrigger.ON_CLICK;
                x.start ("p:par");
                x.start ("p:cTn").ai ("id", ++ctn).a ("fill", "hold");
                x.start ("p:stCondLst");
                x.start ("p:cond").a ("delay", interactive ? "0" : "indefinite").end ();
                if (auto_group && !interactive) x.start ("p:cond").a ("evt", "onBegin").a ("delay", "0").start ("p:tn").ai ("val", seq_id).end ().end ();
                x.end ();
                x.start ("p:childTnLst");
                double prev_start = 0, prev_end = 0;
                int k = i;
                while (k < group_end) {
                    double sub_start = k == i ? 0 : prev_end;
                    if (k > i && anims[k].trigger == AnimTrigger.WITH_PREVIOUS) sub_start = prev_start;
                    int sub_end = k + 1;
                    while (sub_end < group_end && anims[sub_end].trigger == AnimTrigger.WITH_PREVIOUS) sub_end++;
                    x.start ("p:par");
                    x.start ("p:cTn").ai ("id", ++ctn).a ("fill", "hold");
                    cond (x, ((int64) Math.round (sub_start * 1000)).to_string ());
                    x.start ("p:childTnLst");
                    double base_start = sub_start;
                    for (int j = k; j < sub_end; j++) {
                        var a = anims[j];
                        int spid = id_of (targets[j]);
                        string node = a.trigger == AnimTrigger.ON_CLICK ? "clickEffect" : (a.trigger == AnimTrigger.WITH_PREVIOUS ? "withEffect" : "afterEffect");
                        effect_par (x, a, spid, node, targets[j] as MediaElement);
                        double st = base_start + a.delay;
                        double dur = a.effect == AnimEffect.APPEAR ? 0.01 : double.max (a.duration, 0.01);
                        if (a.anim_class == AnimClass.MEDIA) {
                            var me = targets[j] as MediaElement;
                            dur = me != null && a.effect == AnimEffect.MEDIA_PLAY ? double.max (me.play_length (), 0.01) : 0.01;
                        }
                        prev_start = st;
                        prev_end = st + dur;
                    }
                    x.end ();
                    x.end ();
                    x.end ();
                    k = sub_end;
                }
                x.end ();
                x.end ();
                x.end ();
                i = group_end;
            }
        }

        private void timing (XmlOut x, Slide s) {
            var anims = new Gee.ArrayList<Animation> ();
            var targets = new Gee.ArrayList<Element> ();
            var medias = new Gee.ArrayList<MediaElement> ();
            var all = new Gee.ArrayList<Element> ();
            foreach (var e in s.elements) flatten_el (e, all);
            foreach (var e in all) {
                var m = e as MediaElement;
                if (m != null) medias.add (m);
            }
            var explicit_media = new Gee.HashSet<int> ();
            var tail_anims = new Gee.ArrayList<Animation> ();
            var tail_targets = new Gee.ArrayList<Element> ();
            foreach (var a in s.animations) if (a.anim_class == AnimClass.MEDIA && a.effect == AnimEffect.MEDIA_PLAY) explicit_media.add (a.target);
            foreach (var m in medias) {
                if (explicit_media.contains (m.id) || m.start == MediaStart.ON_CLICK) continue;
                var a = new Animation (m.id);
                a.anim_class = AnimClass.MEDIA;
                a.effect = AnimEffect.MEDIA_PLAY;
                a.trigger = m.start == MediaStart.AUTOMATIC ? AnimTrigger.WITH_PREVIOUS : AnimTrigger.ON_CLICK;
                if (m.start == MediaStart.AUTOMATIC) {
                    anims.add (a);
                    targets.add (m);
                } else {
                    tail_anims.add (a);
                    tail_targets.add (m);
                }
            }
            var triggered = new Gee.TreeMap<string, Gee.ArrayList<int>> ();
            for (int i = 0; i < s.animations.size; i++) {
                var a = s.animations[i];
                var e = s.find (a.target);
                if (e == null) continue;
                if (a.trigger_shape >= 0 || a.trigger_bookmark != "") {
                    if (a.trigger_shape >= 0 && s.find (a.trigger_shape) == null) continue;
                    string key = a.trigger_bookmark != "" ? "b%d:%s".printf (a.trigger_shape, a.trigger_bookmark) : "s%d".printf (a.trigger_shape);
                    if (!triggered.has_key (key)) triggered[key] = new Gee.ArrayList<int> ();
                    triggered[key].add (i);
                    continue;
                }
                anims.add (a);
                targets.add (e);
            }
            anims.add_all (tail_anims);
            targets.add_all (tail_targets);
            if (anims.size == 0 && triggered.size == 0 && medias.size == 0) return;
            ctn = 0;
            x.start ("p:timing").start ("p:tnLst").start ("p:par");
            x.start ("p:cTn").ai ("id", ++ctn).a ("dur", "indefinite").a ("restart", "never").a ("nodeType", "tmRoot");
            x.start ("p:childTnLst");
            if (anims.size > 0) {
                x.start ("p:seq").a ("concurrent", "1").a ("nextAc", "seek");
                int main_id = ++ctn;
                x.start ("p:cTn").ai ("id", main_id).a ("dur", "indefinite").a ("nodeType", "mainSeq");
                x.start ("p:childTnLst");
                sequence_body (x, anims, targets, s, main_id, false);
                x.end ();
                x.end ();
                x.start ("p:prevCondLst").start ("p:cond").a ("evt", "onPrev").a ("delay", "0").start ("p:tgtEl").empty ("p:sldTgt").end ().end ().end ();
                x.start ("p:nextCondLst").start ("p:cond").a ("evt", "onNext").a ("delay", "0").start ("p:tgtEl").empty ("p:sldTgt").end ().end ().end ();
                x.end ();
            }
            foreach (var m in medias) {
                x.start (m.is_video ? "p:video" : "p:audio");
                if (m.is_video && m.full_screen) x.a ("fullScrn", "1");
                x.start ("p:cMediaNode").ai ("vol", (int64) Math.round (m.volume * 100000));
                if (m.muted) x.a ("mute", "1");
                if (m.across_slides) x.a ("numSld", "999");
                if (m.hide_when_stopped) x.a ("showWhenStopped", "0");
                x.start ("p:cTn").ai ("id", ++ctn).a ("fill", "hold").a ("display", "0");
                if (m.loop) x.a ("repeatCount", "indefinite");
                cond (x, "indefinite");
                if (!m.is_video) x.start ("p:endCondLst").start ("p:cond").a ("evt", "onStopAudio").a ("delay", "0").start ("p:tgtEl").empty ("p:sldTgt").end ().end ().end ();
                x.end ();
                tgt (x, id_of (m));
                x.end ();
                x.end ();
            }
            foreach (var m in medias) {
                bool has_trigger = false;
                foreach (var k in triggered.keys) if (k == "s%d".printf (m.id)) has_trigger = true;
                if (has_trigger) continue;
                interactive_seq (x, s, m.id, "", m.start == MediaStart.ON_CLICK ? AnimEffect.MEDIA_PLAY : AnimEffect.MEDIA_PAUSE, null);
            }
            foreach (var entry in triggered.entries) {
                var list = new Gee.ArrayList<Animation> ();
                foreach (int idx in entry.value) list.add (s.animations[idx]);
                var first = list[0];
                interactive_seq (x, s, first.trigger_shape, first.trigger_bookmark, null, list);
            }
            x.end ();
            x.end ();
            x.end ();
            x.end ();
            build_list (x, anims, targets, s);
            x.end ();
        }

        private void interactive_seq (XmlOut x, Slide s, int shape, string bookmark, AnimEffect? media_effect, Gee.List<Animation>? list) {
            var anims = new Gee.ArrayList<Animation> ();
            var targets = new Gee.ArrayList<Element> ();
            if (list != null) {
                foreach (var a in list) {
                    var e = s.find (a.target);
                    if (e == null) continue;
                    anims.add (a);
                    targets.add (e);
                }
            } else {
                var e = s.find (shape);
                if (e == null) return;
                var a = new Animation (shape);
                a.anim_class = AnimClass.MEDIA;
                a.effect = media_effect;
                anims.add (a);
                targets.add (e);
            }
            if (anims.size == 0) return;
            var shape_el = s.find (shape);
            int spid = shape_el != null ? id_of (shape_el) : shape;
            x.start ("p:seq").a ("concurrent", "1").a ("nextAc", "seek");
            int seq_id = ++ctn;
            x.start ("p:cTn").ai ("id", seq_id).a ("restart", "whenNotActive").a ("fill", "hold").a ("evtFilter", "cancelBubble").a ("nodeType", "interactiveSeq");
            x.start ("p:stCondLst");
            if (bookmark != "") {
                x.start ("p:cond").a ("evt", "onMediaBookmark").a ("delay", "0");
                x.start ("p:tgtEl").start ("p:spTgt").ai ("spid", spid).end ().end ();
                x.end ();
            } else {
                x.start ("p:cond").a ("evt", "onClick").a ("delay", "0");
                x.start ("p:tgtEl").start ("p:spTgt").ai ("spid", spid).end ().end ();
                x.end ();
            }
            x.end ();
            x.start ("p:endSync").a ("evt", "end").a ("delay", "0").start ("p:rtn").a ("val", "all").end ().end ();
            x.start ("p:childTnLst");
            anims[0].trigger = AnimTrigger.ON_CLICK;
            sequence_body (x, anims, targets, s, seq_id, true);
            x.end ();
            x.end ();
            x.start ("p:nextCondLst").start ("p:cond").a ("evt", "onClick").a ("delay", "0");
            x.start ("p:tgtEl").start ("p:spTgt").ai ("spid", spid).end ().end ();
            x.end ().end ();
            x.end ();
        }

        private static void flatten_el (Element e, Gee.List<Element> all) {
            all.add (e);
            var g = e as GroupElement;
            if (g != null) foreach (var c in g.children) flatten_el (c, all);
        }

        private void build_list (XmlOut x, Gee.List<Animation> anims, Gee.List<Element> targets, Slide s) {
            var entries = new Gee.ArrayList<string> ();
            var done = new Gee.HashSet<int> ();
            var all_anims = new Gee.ArrayList<Animation> ();
            all_anims.add_all (s.animations);
            foreach (var a in all_anims) {
                var e = s.find (a.target);
                if (e == null || a.anim_class == AnimClass.MEDIA) continue;
                int spid = id_of (e);
                if (done.contains (spid)) continue;
                done.add (spid);
                if (e.kind == ElementKind.TABLE || e.kind == ElementKind.CHART || e.kind == ElementKind.DIAGRAM) {
                    entries.add ("<p:bldGraphic spid=\"%d\" grpId=\"0\"><p:bldAsOne/></p:bldGraphic>".printf (spid));
                } else if (e.kind == ElementKind.SHAPE && ((ShapeElement) e).text != null && !is_connector ((ShapeElement) e)) {
                    bool by_para = false;
                    foreach (var b in all_anims) if (b.target == a.target && b.paragraph >= 0) by_para = true;
                    entries.add ("<p:bldP spid=\"%d\" grpId=\"0\"%s animBg=\"1\"/>".printf (spid, by_para ? " build=\"p\"" : ""));
                }
            }
            if (entries.size == 0) return;
            x.start ("p:bldLst");
            foreach (string en in entries) x.raw (en);
            x.end ();
        }

        private int author_id (Comment c) {
            string key = c.author + "\n" + c.initials;
            if (!author_ids.has_key (key)) {
                author_ids[key] = author_order.size;
                author_order.add (key);
                author_last[key] = 0;
            }
            return author_ids[key];
        }

        private void comment_el (XmlOut x, Comment c, Comment? parent, int parent_author, int parent_idx, out int my_author, out int my_idx) {
            string key = c.author + "\n" + c.initials;
            my_author = author_id (c);
            my_idx = author_last[key] + 1;
            author_last[key] = my_idx;
            x.start ("p:cm").ai ("authorId", my_author).a ("dt", c.date != "" ? c.date : Comment.now ()).ai ("idx", my_idx);
            x.start ("p:pos").ai ("x", (int64) Math.round (c.x * 8)).ai ("y", (int64) Math.round (c.y * 8)).end ();
            x.element ("p:text", c.text);
            x.start ("p:extLst").start ("p:ext").a ("uri", Ooxml.EXT_THREADING);
            x.start ("p15:threadingInfo").a ("xmlns:p15", Ooxml.NS_P15).a ("timeZoneBias", "0");
            if (parent != null) x.start ("p15:parentCm").ai ("authorId", parent_author).ai ("idx", parent_idx).end ();
            x.end ();
            x.end ();
            if (c.resolved) x.start ("p:ext").a ("uri", Ooxml.EXT_URI).start ("sg:comment").a ("xmlns:sg", Ooxml.NS_SG).a ("resolved", "1").a ("guid", c.id).end ().end ();
            else x.start ("p:ext").a ("uri", Ooxml.EXT_URI).start ("sg:comment").a ("xmlns:sg", Ooxml.NS_SG).a ("guid", c.id).end ().end ();
            x.end ();
            x.end ();
        }

        private string comments_xml (Slide s) {
            var x = new XmlOut ();
            open_part (x, "p:cmLst");
            foreach (var c in s.comments) {
                int a, i;
                comment_el (x, c, null, 0, 0, out a, out i);
                foreach (var r in c.replies) {
                    int ra, ri;
                    comment_el (x, r, c, a, i, out ra, out ri);
                }
            }
            x.end ();
            return x.finish ();
        }

        private string authors_xml () {
            var x = new XmlOut ();
            open_part (x, "p:cmAuthorLst");
            for (int i = 0; i < author_order.size; i++) {
                string[] parts2 = author_order[i].split ("\n", 2);
                x.start ("p:cmAuthor").ai ("id", i).a ("name", parts2[0]).a ("initials", parts2.length > 1 ? parts2[1] : "").ai ("lastIdx", author_last[author_order[i]]).ai ("clrIdx", i % 8).end ();
            }
            x.end ();
            return x.finish ();
        }

        private string notes_xml (Slide s) {
            var x = new XmlOut ();
            open_part (x, "p:notes");
            x.start ("p:cSld").start ("p:spTree");
            x.start ("p:nvGrpSpPr").start ("p:cNvPr").a ("id", "1").a ("name", "").end ().empty ("p:cNvGrpSpPr").empty ("p:nvPr").end ();
            x.start ("p:grpSpPr").start ("a:xfrm");
            x.start ("a:off").a ("x", "0").a ("y", "0").end ().start ("a:ext").a ("cx", "0").a ("cy", "0").end ();
            x.start ("a:chOff").a ("x", "0").a ("y", "0").end ().start ("a:chExt").a ("cx", "0").a ("cy", "0").end ();
            x.end ().end ();
            x.start ("p:sp").start ("p:nvSpPr");
            x.start ("p:cNvPr").a ("id", "2").a ("name", "Slide Image Placeholder 1").end ();
            x.start ("p:cNvSpPr").start ("a:spLocks").a ("noGrp", "1").a ("noRot", "1").a ("noChangeAspect", "1").end ().end ();
            x.start ("p:nvPr").start ("p:ph").a ("type", "sldImg").end ().end ();
            x.end ().empty ("p:spPr").end ();
            x.start ("p:sp").start ("p:nvSpPr");
            x.start ("p:cNvPr").a ("id", "3").a ("name", "Notes Placeholder 2").end ();
            x.start ("p:cNvSpPr").start ("a:spLocks").a ("noGrp", "1").end ().end ();
            x.start ("p:nvPr").start ("p:ph").a ("type", "body").a ("idx", "1").end ().end ();
            x.end ().empty ("p:spPr");
            x.start ("p:txBody").empty ("a:bodyPr").empty ("a:lstStyle");
            foreach (string line in s.notes.split ("\n")) {
                x.start ("a:p");
                if (line != "") x.start ("a:r").start ("a:rPr").a ("lang", "en-US").a ("dirty", "0").end ().element ("a:t", line).end ();
                x.end ();
            }
            x.end ();
            x.end ();
            x.end ().end ();
            x.start ("p:clrMapOvr").empty ("a:masterClrMapping").end ();
            x.end ();
            return x.finish ();
        }

        private void notes_shape (XmlOut x, int id, string name, string type, int idx, double ox, double oy, double w, double h) {
            x.start ("p:sp").start ("p:nvSpPr");
            x.start ("p:cNvPr").ai ("id", id).a ("name", name).end ();
            x.start ("p:cNvSpPr").start ("a:spLocks").a ("noGrp", "1").end ().end ();
            x.start ("p:nvPr").start ("p:ph").a ("type", type);
            if (idx >= 0) x.ai ("idx", idx);
            x.end ().end ();
            x.end ();
            x.start ("p:spPr").start ("a:xfrm");
            x.start ("a:off").ai ("x", Ooxml.emu (ox)).ai ("y", Ooxml.emu (oy)).end ();
            x.start ("a:ext").ai ("cx", Ooxml.emu (w)).ai ("cy", Ooxml.emu (h)).end ();
            x.end ();
            x.start ("a:prstGeom").a ("prst", "rect").empty ("a:avLst").end ();
            x.end ();
            if (type != "sldImg") x.start ("p:txBody").empty ("a:bodyPr").empty ("a:lstStyle").start ("a:p").start ("a:endParaRPr").a ("lang", "en-US").end ().end ().end ();
            x.end ();
        }

        private string notes_master_xml () {
            var x = new XmlOut ();
            open_part (x, "p:notesMaster");
            x.start ("p:cSld");
            x.start ("p:bg").start ("p:bgRef").a ("idx", "1001").start ("a:schemeClr").a ("val", "bg1").end ().end ().end ();
            x.start ("p:spTree");
            x.start ("p:nvGrpSpPr").start ("p:cNvPr").a ("id", "1").a ("name", "").end ().empty ("p:cNvGrpSpPr").empty ("p:nvPr").end ();
            x.start ("p:grpSpPr").start ("a:xfrm");
            x.start ("a:off").a ("x", "0").a ("y", "0").end ().start ("a:ext").a ("cx", "0").a ("cy", "0").end ();
            x.start ("a:chOff").a ("x", "0").a ("y", "0").end ().start ("a:chExt").a ("cx", "0").a ("cy", "0").end ();
            x.end ().end ();
            double nw = 540, nh = 720;
            double iw = nw - 108, ih = iw * pres.height / pres.width;
            notes_shape (x, 2, "Slide Image Placeholder 1", "sldImg", 2, 54, 54, iw, ih);
            notes_shape (x, 3, "Notes Placeholder 2", "body", 3, 54, 54 + ih + 24, iw, nh - ih - 150);
            x.end ();
            x.end ();
            x.start ("p:clrMap").a ("bg1", "lt1").a ("tx1", "dk1").a ("bg2", "lt2").a ("tx2", "dk2")
                .a ("accent1", "accent1").a ("accent2", "accent2").a ("accent3", "accent3").a ("accent4", "accent4")
                .a ("accent5", "accent5").a ("accent6", "accent6").a ("hlink", "hlink").a ("folHlink", "folHlink").end ();
            x.start ("p:notesStyle");
            x.start ("a:lvl1pPr").a ("marL", "0").a ("algn", "l");
            x.start ("a:defRPr").a ("sz", "1200");
            x.start ("a:solidFill").start ("a:schemeClr").a ("val", "tx1").end ().end ();
            x.start ("a:latin").a ("typeface", "+mn-lt").end ();
            x.end ();
            x.end ();
            x.end ();
            x.end ();
            return x.finish ();
        }
    }
}
