namespace Singularity.Apps.Slides {

    public class Ooxml {
        public const string NS_A = "http://schemas.openxmlformats.org/drawingml/2006/main";
        public const string NS_R = "http://schemas.openxmlformats.org/officeDocument/2006/relationships";
        public const string NS_P = "http://schemas.openxmlformats.org/presentationml/2006/main";
        public const string NS_C = "http://schemas.openxmlformats.org/drawingml/2006/chart";
        public const string NS_MC = "http://schemas.openxmlformats.org/markup-compatibility/2006";
        public const string NS_P14 = "http://schemas.microsoft.com/office/powerpoint/2010/main";
        public const string NS_PKG_RELS = "http://schemas.openxmlformats.org/package/2006/relationships";
        public const string NS_CT = "http://schemas.openxmlformats.org/package/2006/content-types";
        public const string NS_SG = "urn:singularity:slides:pptx";
        public const string EXT_URI = "{9B0C3E5A-6F2D-4A1B-8C7E-3D5F1A2B4C6E}";
        public const string URI_TABLE = "http://schemas.openxmlformats.org/drawingml/2006/table";
        public const string URI_CHART = "http://schemas.openxmlformats.org/drawingml/2006/chart";
        public const string URI_DIAGRAM = "http://schemas.openxmlformats.org/drawingml/2006/diagram";
        public const string URI_OLE = "http://schemas.openxmlformats.org/presentationml/2006/ole";
        public const string URI_SLIDE_ZOOM = "http://schemas.microsoft.com/office/powerpoint/2016/slidezoom";
        public const string URI_SECTION_ZOOM = "http://schemas.microsoft.com/office/powerpoint/2016/sectionzoom";
        public const string URI_SUMMARY_ZOOM = "http://schemas.microsoft.com/office/powerpoint/2016/summaryzoom";
        public const string NS_P15 = "http://schemas.microsoft.com/office/powerpoint/2012/main";
        public const string NS_P159 = "http://schemas.microsoft.com/office/powerpoint/2015/09/main";
        public const string NS_P166 = "http://schemas.microsoft.com/office/powerpoint/2016/6/main";
        public const string NS_P188 = "http://schemas.microsoft.com/office/powerpoint/2018/8/main";
        public const string NS_A14 = "http://schemas.microsoft.com/office/drawing/2010/main";
        public const string NS_DGM = "http://schemas.openxmlformats.org/drawingml/2006/diagram";
        public const string NS_DSP = "http://schemas.microsoft.com/office/drawing/2008/diagram";
        public const string NS_INKML = "http://www.w3.org/2003/InkML";
        public const string NS_PSLZ = "http://schemas.microsoft.com/office/powerpoint/2016/slidezoom";
        public const string NS_PSEZ = "http://schemas.microsoft.com/office/powerpoint/2016/sectionzoom";
        public const string NS_M = "http://schemas.openxmlformats.org/officeDocument/2006/math";
        public const string EXT_SECTIONS = "{521415D9-36F7-43E2-AB2F-B90AF26B5E84}";
        public const string EXT_MEDIA = "{DAA4B4D4-6D71-4841-9C94-3DE7FCFB9230}";
        public const string EXT_THREADING = "{C676402C-5697-4E1C-873F-D02D1690AC5C}";
        public const string EXT_EQUATION = "{4A2B7C1E-3F5D-4E6A-9B8C-7D6E5F4A3B2C}";

        public const string REL = "http://schemas.openxmlformats.org/officeDocument/2006/relationships/";
        public const string REL_OFFICE_DOCUMENT = REL + "officeDocument";
        public const string REL_CORE = "http://schemas.openxmlformats.org/package/2006/relationships/metadata/core-properties";
        public const string REL_APP = REL + "extended-properties";
        public const string REL_MASTER = REL + "slideMaster";
        public const string REL_LAYOUT = REL + "slideLayout";
        public const string REL_SLIDE = REL + "slide";
        public const string REL_THEME = REL + "theme";
        public const string REL_NOTES_MASTER = REL + "notesMaster";
        public const string REL_NOTES_SLIDE = REL + "notesSlide";
        public const string REL_PRES_PROPS = REL + "presProps";
        public const string REL_VIEW_PROPS = REL + "viewProps";
        public const string REL_TABLE_STYLES = REL + "tableStyles";
        public const string REL_IMAGE = REL + "image";
        public const string REL_CHART = REL + "chart";
        public const string REL_HYPERLINK = REL + "hyperlink";
        public const string REL_VIDEO = REL + "video";
        public const string REL_AUDIO = REL + "audio";
        public const string REL_MEDIA = "http://schemas.microsoft.com/office/2007/relationships/media";
        public const string REL_COMMENTS = REL + "comments";
        public const string REL_COMMENT_AUTHORS = REL + "commentAuthors";
        public const string REL_MODERN_COMMENTS = "http://schemas.microsoft.com/office/2018/10/relationships/comments";
        public const string REL_MODERN_AUTHORS = "http://schemas.microsoft.com/office/2018/10/relationships/authors";
        public const string REL_DIAGRAM_DATA = REL + "diagramData";
        public const string REL_DIAGRAM_LAYOUT = REL + "diagramLayout";
        public const string REL_DIAGRAM_STYLE = REL + "diagramQuickStyle";
        public const string REL_DIAGRAM_COLORS = REL + "diagramColors";
        public const string REL_DIAGRAM_DRAWING = "http://schemas.microsoft.com/office/2007/relationships/diagramDrawing";
        public const string REL_INK = "http://schemas.microsoft.com/office/2011/relationships/inkAction";
        public const string REL_CUSTOM_XML = REL + "customXml";
        public const string REL_PACKAGE = REL + "package";
        public const string REL_FONT = REL + "font";
        public const string REL_TAGS = REL + "tags";
        public const string REL_THUMBNAIL = "http://schemas.openxmlformats.org/package/2006/relationships/metadata/thumbnail";

        public const string CT_BASE = "application/vnd.openxmlformats-officedocument.presentationml.";
        public const string CT_PRESENTATION = CT_BASE + "presentation.main+xml";
        public const string CT_SLIDE = CT_BASE + "slide+xml";
        public const string CT_SLIDESHOW = CT_BASE + "slideshow.main+xml";
        public const string CT_TEMPLATE = CT_BASE + "template.main+xml";
        public const string CT_LAYOUT = CT_BASE + "slideLayout+xml";
        public const string CT_MASTER = CT_BASE + "slideMaster+xml";
        public const string CT_NOTES_MASTER = CT_BASE + "notesMaster+xml";
        public const string CT_NOTES_SLIDE = CT_BASE + "notesSlide+xml";
        public const string CT_PRES_PROPS = CT_BASE + "presProps+xml";
        public const string CT_VIEW_PROPS = CT_BASE + "viewProps+xml";
        public const string CT_TABLE_STYLES = CT_BASE + "tableStyles+xml";
        public const string CT_THEME = "application/vnd.openxmlformats-officedocument.theme+xml";
        public const string URI_CHARTEX = "http://schemas.microsoft.com/office/drawing/2014/chartex";
        public const string NS_CX1 = "http://schemas.microsoft.com/office/drawing/2015/9/8/chartex";
        public const string CT_GLB = "model/gltf-binary";
        public const string NS_AM3D = "http://schemas.microsoft.com/office/drawing/2017/model3d";
        public const string URI_MODEL3D = "http://schemas.microsoft.com/office/drawing/2017/model3d";
        public const string REL_MODEL3D = "http://schemas.microsoft.com/office/2017/06/relationships/model3d";
        public const string CT_CHART = "application/vnd.openxmlformats-officedocument.drawingml.chart+xml";
        public const string CT_CORE = "application/vnd.openxmlformats-package.core-properties+xml";
        public const string CT_APP = "application/vnd.openxmlformats-officedocument.extended-properties+xml";
        public const string CT_RELS = "application/vnd.openxmlformats-package.relationships+xml";
        public const string CT_COMMENTS = CT_BASE + "comments+xml";
        public const string CT_COMMENT_AUTHORS = CT_BASE + "commentAuthors+xml";
        public const string CT_INK = "application/inkml+xml";
        public const string CT_XLSX = "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet";

        public const string[] TABLE_STYLES = {
            "{5C22544A-7EE6-4342-B048-85BDC9FD1C3A}",
            "{21E4AEA4-8DFA-4A89-87EB-49C32662AFE8}",
            "{F5AB1C69-6EDB-4FF4-983F-18BD219EF322}",
            "{00A15C55-8517-42AA-B614-E9B94910E393}",
            "{7DF18680-E054-41AD-8BC1-D1AEF772440D}",
            "{93296810-A885-4BE3-A3E7-6D5BEEA58F35}"
        };

        public static int64 emu (double pt) {
            return (int64) Math.round (pt * 12700);
        }

        public static double pt (int64 emu) {
            return emu / 12700.0;
        }

        public static string pct (double v) {
            return ((int64) Math.round (v * 100000)).to_string ();
        }

        public static string mime_for_ext (string ext) {
            switch (ext.down ()) {
                case "jpg": case "jpeg": return "image/jpeg";
                case "gif": return "image/gif";
                case "svg": return "image/svg+xml";
                case "bmp": return "image/bmp";
                case "tif": case "tiff": return "image/tiff";
                case "webp": return "image/webp";
                case "emf": return "image/x-emf";
                case "wmf": return "image/x-wmf";
                default: return "image/png";
            }
        }

        public static string ext_for_mime (string mime) {
            switch (mime) {
                case "image/jpeg": return "jpeg";
                case "image/gif": return "gif";
                case "image/svg+xml": return "svg";
                case "image/bmp": return "bmp";
                case "image/tiff": return "tiff";
                case "image/webp": return "webp";
                default: return "png";
            }
        }

        public static string table_style_for (string color) {
            string c = ColorSpec.parse (color).base_name;
            if (c.has_prefix ("accent") && c.length == 7) {
                int n = int.parse (c.substring (6));
                if (n >= 1 && n <= 6) return TABLE_STYLES[n - 1];
            }
            return TABLE_STYLES[0];
        }

        public static string? color_for_table_style (string id) {
            for (int i = 0; i < TABLE_STYLES.length; i++) if (TABLE_STYLES[i].up () == id.up ()) return "accent%d".printf (i + 1);
            return null;
        }

        public static int subtype_for (Direction d) {
            switch (d) {
                case Direction.FROM_TOP: return 1;
                case Direction.FROM_RIGHT: return 2;
                case Direction.FROM_LEFT: return 8;
                default: return 4;
            }
        }

        public static Direction direction_for (int subtype, Direction fallback) {
            switch (subtype) {
                case 1: return Direction.FROM_TOP;
                case 2: return Direction.FROM_RIGHT;
                case 4: return Direction.FROM_BOTTOM;
                case 8: return Direction.FROM_LEFT;
                default: return fallback;
            }
        }
    }

    public class OoxmlRels {
        private class Rel {
            public string id;
            public string type;
            public string target;
            public bool external;
        }

        private Gee.ArrayList<Rel> rels = new Gee.ArrayList<Rel> ();

        public string add (string type, string target, bool external = false) {
            foreach (var r in rels) if (r.type == type && r.target == target && r.external == external) return r.id;
            var r = new Rel ();
            r.id = "rId%d".printf (rels.size + 1);
            r.type = type;
            r.target = target;
            r.external = external;
            rels.add (r);
            return r.id;
        }

        public bool is_empty () {
            return rels.size == 0;
        }

        public string to_xml () {
            var x = new XmlOut ();
            x.start ("Relationships").a ("xmlns", Ooxml.NS_PKG_RELS);
            foreach (var r in rels) {
                x.start ("Relationship").a ("Id", r.id).a ("Type", r.type).a ("Target", r.target);
                if (r.external) x.a ("TargetMode", "External");
                x.end ();
            }
            x.end ();
            return x.finish ();
        }

        public static string rels_path (string part) {
            int slash = part.last_index_of ("/");
            string dir = slash >= 0 ? part.substring (0, slash + 1) : "";
            string name = slash >= 0 ? part.substring (slash + 1) : part;
            return dir + "_rels/" + name + ".rels";
        }

        public static string resolve (string part, string target) {
            if (target.has_prefix ("/")) return target.substring (1);
            int slash = part.last_index_of ("/");
            string dir = slash >= 0 ? part.substring (0, slash) : "";
            var parts = new Gee.ArrayList<string> ();
            if (dir != "") foreach (string s in dir.split ("/")) parts.add (s);
            foreach (string s in target.split ("/")) {
                if (s == "" || s == ".") continue;
                if (s == "..") {
                    if (parts.size > 0) parts.remove_at (parts.size - 1);
                    continue;
                }
                parts.add (s);
            }
            return string.joinv ("/", parts.to_array ());
        }
    }
}
