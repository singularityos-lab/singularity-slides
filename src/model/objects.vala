namespace Singularity.Apps.Slides {

    public class ForeignPart {
        public string path;
        public Bytes data;
        public string content_type;
        public Gee.ArrayList<ForeignRel> rels = new Gee.ArrayList<ForeignRel> ();

        public ForeignPart (string path, Bytes data, string content_type) {
            this.path = path;
            this.data = data;
            this.content_type = content_type;
        }

        public string text () {
            return bytes_text (data);
        }

        public static string bytes_text (Bytes data) {
            size_t n = data.get_size ();
            var buf = new uint8[n + 1];
            if (n > 0) Memory.copy (buf, data.get_data (), n);
            buf[n] = 0;
            return ((string) buf).dup ();
        }
    }

    public class ForeignRel {
        public string id;
        public string type;
        public string target;
        public bool external;
        public ForeignPart? part = null;

        public ForeignRel (string id, string type, string target, bool external) {
            this.id = id;
            this.type = type;
            this.target = target;
            this.external = external;
        }
    }

    public class ForeignElement : Element {
        public string xml = "";
        public string label = "";
        public Gee.ArrayList<ForeignRel> rels = new Gee.ArrayList<ForeignRel> ();
        public Element? preview = null;
        public double orig_x = 0;
        public double orig_y = 0;
        public double orig_w = 0;
        public double orig_h = 0;
        public double orig_rot = 0;

        public override ElementKind kind {
            get { return ElementKind.FOREIGN; }
        }

        public override Element clone () {
            var f = new ForeignElement ();
            copy_base (f);
            f.xml = xml;
            f.label = label;
            f.rels.add_all (rels);
            f.preview = preview != null ? preview.clone () : null;
            f.orig_x = orig_x;
            f.orig_y = orig_y;
            f.orig_w = orig_w;
            f.orig_h = orig_h;
            f.orig_rot = orig_rot;
            return f;
        }

        public bool moved () {
            return Math.fabs (x - orig_x) > 0.01 || Math.fabs (y - orig_y) > 0.01 || Math.fabs (w - orig_w) > 0.01 || Math.fabs (h - orig_h) > 0.01 || Math.fabs (rotation - orig_rot) > 0.01;
        }

        public override void move_by (double dx, double dy) {
            base.move_by (dx, dy);
            if (preview != null) preview.move_by (dx, dy);
        }

        public override void scale_into (double nx, double ny, double nw, double nh) {
            if (preview != null) {
                double sx = w > 0 ? nw / w : 1, sy = h > 0 ? nh / h : 1;
                preview.scale_into (nx + (preview.x - x) * sx, ny + (preview.y - y) * sy, preview.w * sx, preview.h * sy);
            }
            set_geometry (nx, ny, nw, nh);
        }

        public override string display_name () {
            return name != "" ? name : (label != "" ? label : _("Embedded Object"));
        }
    }

    public enum MediaStart {
        IN_SEQUENCE,
        AUTOMATIC,
        ON_CLICK;

        public string label () {
            switch (this) {
                case AUTOMATIC: return _("Automatically");
                case ON_CLICK: return _("When Clicked On");
                default: return _("In Click Sequence");
            }
        }
    }

    public class MediaBookmark {
        public string name;
        public double time;

        public MediaBookmark (string name, double time) {
            this.name = name;
            this.time = time;
        }
    }

    public class MediaElement : Element {
        public Bytes? data = null;
        public string mime = "video/mp4";
        public string link = "";
        public bool is_video = true;
        public Bytes? poster = null;
        public string poster_mime = "image/png";
        public double length = 0;
        public double trim_start = 0;
        public double trim_end = 0;
        public double fade_in = 0;
        public double fade_out = 0;
        public double volume = 1;
        public bool muted = false;
        public MediaStart start = MediaStart.IN_SEQUENCE;
        public bool loop = false;
        public bool rewind = false;
        public bool hide_when_stopped = false;
        public bool full_screen = false;
        public bool across_slides = false;
        public Gee.ArrayList<MediaBookmark> bookmarks = new Gee.ArrayList<MediaBookmark> ();

        public override ElementKind kind {
            get { return ElementKind.MEDIA; }
        }

        public override Element clone () {
            var m = new MediaElement ();
            copy_base (m);
            m.data = data;
            m.mime = mime;
            m.link = link;
            m.is_video = is_video;
            m.poster = poster;
            m.poster_mime = poster_mime;
            m.length = length;
            m.trim_start = trim_start;
            m.trim_end = trim_end;
            m.fade_in = fade_in;
            m.fade_out = fade_out;
            m.volume = volume;
            m.muted = muted;
            m.start = start;
            m.loop = loop;
            m.rewind = rewind;
            m.hide_when_stopped = hide_when_stopped;
            m.full_screen = full_screen;
            m.across_slides = across_slides;
            foreach (var b in bookmarks) m.bookmarks.add (new MediaBookmark (b.name, b.time));
            return m;
        }

        public double play_length () {
            return double.max (length - trim_start - trim_end, 0);
        }

        public string extension () {
            switch (mime) {
                case "video/mp4": return "mp4";
                case "video/webm": return "webm";
                case "video/ogg": return "ogv";
                case "video/quicktime": return "mov";
                case "video/x-msvideo": return "avi";
                case "video/x-matroska": return "mkv";
                case "video/x-ms-wmv": return "wmv";
                case "audio/mpeg": return "mp3";
                case "audio/mp4": return "m4a";
                case "audio/ogg": return "ogg";
                case "audio/wav": case "audio/x-wav": return "wav";
                case "audio/flac": return "flac";
                case "audio/webm": return "weba";
                case "audio/x-ms-wma": return "wma";
                default: return is_video ? "mp4" : "mp3";
            }
        }

        public static string mime_for (string name) {
            string n = name.down ();
            int dot = n.last_index_of (".");
            string ext = dot >= 0 ? n.substring (dot + 1) : n;
            switch (ext) {
                case "mp4": case "m4v": return "video/mp4";
                case "webm": return "video/webm";
                case "ogv": return "video/ogg";
                case "mov": return "video/quicktime";
                case "avi": return "video/x-msvideo";
                case "mkv": return "video/x-matroska";
                case "wmv": return "video/x-ms-wmv";
                case "mp3": return "audio/mpeg";
                case "m4a": case "aac": return "audio/mp4";
                case "ogg": case "oga": case "opus": return "audio/ogg";
                case "wav": return "audio/wav";
                case "flac": return "audio/flac";
                case "weba": return "audio/webm";
                case "wma": return "audio/x-ms-wma";
                default: return "application/octet-stream";
            }
        }

        public static string sniff_extension (Bytes data) {
            unowned uint8[] d = data.get_data ();
            if (d.length >= 12 && d[0] == 'R' && d[1] == 'I' && d[2] == 'F' && d[3] == 'F') return "wav";
            if (d.length >= 4 && d[0] == 'O' && d[1] == 'g' && d[2] == 'g' && d[3] == 'S') return "ogg";
            if (d.length >= 4 && d[0] == 'f' && d[1] == 'L' && d[2] == 'a' && d[3] == 'C') return "flac";
            if (d.length >= 8 && d[4] == 'f' && d[5] == 't' && d[6] == 'y' && d[7] == 'p') return "m4a";
            if (d.length >= 4 && d[0] == 0x1a && d[1] == 0x45 && d[2] == 0xdf && d[3] == 0xa3) return "webm";
            return "mp3";
        }

        public static bool is_media_name (string name) {
            return mime_for (name) != "application/octet-stream";
        }

        public override string display_name () {
            return name != "" ? name : (is_video ? _("Video") : _("Audio"));
        }
    }

    public class InkStroke {
        public Gee.ArrayList<double?> pts = new Gee.ArrayList<double?> ();
        public string color = "#000000";
        public double width = 2;
        public double opacity = 1;
        public bool highlighter = false;

        public InkStroke clone () {
            var s = new InkStroke ();
            s.pts.add_all (pts);
            s.color = color;
            s.width = width;
            s.opacity = opacity;
            s.highlighter = highlighter;
            return s;
        }
    }

    public class InkElement : Element {
        public Gee.ArrayList<InkStroke> strokes = new Gee.ArrayList<InkStroke> ();

        public override ElementKind kind {
            get { return ElementKind.INK; }
        }

        public override Element clone () {
            var i = new InkElement ();
            copy_base (i);
            foreach (var s in strokes) i.strokes.add (s.clone ());
            return i;
        }

        public void fit () {
            double x1 = double.MAX, y1 = double.MAX, x2 = -double.MAX, y2 = -double.MAX;
            foreach (var s in strokes) {
                for (int i = 0; i + 1 < s.pts.size; i += 2) {
                    x1 = double.min (x1, s.pts[i] - s.width / 2);
                    y1 = double.min (y1, s.pts[i + 1] - s.width / 2);
                    x2 = double.max (x2, s.pts[i] + s.width / 2);
                    y2 = double.max (y2, s.pts[i + 1] + s.width / 2);
                }
            }
            if (x1 > x2) return;
            set_geometry (x1, y1, double.max (x2 - x1, 1), double.max (y2 - y1, 1));
        }

        public override void move_by (double dx, double dy) {
            base.move_by (dx, dy);
            foreach (var s in strokes) {
                for (int i = 0; i + 1 < s.pts.size; i += 2) {
                    s.pts[i] = s.pts[i] + dx;
                    s.pts[i + 1] = s.pts[i + 1] + dy;
                }
            }
        }

        public override void scale_into (double nx, double ny, double nw, double nh) {
            double sx = w > 0 ? nw / w : 1, sy = h > 0 ? nh / h : 1;
            foreach (var s in strokes) {
                for (int i = 0; i + 1 < s.pts.size; i += 2) {
                    s.pts[i] = nx + (s.pts[i] - x) * sx;
                    s.pts[i + 1] = ny + (s.pts[i + 1] - y) * sy;
                }
            }
            set_geometry (nx, ny, nw, nh);
        }

        public override string display_name () {
            return name != "" ? name : _("Ink");
        }
    }

    public enum ZoomKind {
        SLIDE,
        SECTION,
        SUMMARY
    }

    public class ZoomElement : Element {
        public ZoomKind zoom = ZoomKind.SLIDE;
        public int target_uid = 0;
        public string section_id = "";
        public bool return_to_zoom = false;
        public bool zoom_transition = true;
        public double transition_duration = 1;
        public Bytes? image = null;
        public string image_mime = "image/png";
        public bool use_background = false;

        public override ElementKind kind {
            get { return ElementKind.ZOOM; }
        }

        public override Element clone () {
            var z = new ZoomElement ();
            copy_base (z);
            z.zoom = zoom;
            z.target_uid = target_uid;
            z.section_id = section_id;
            z.return_to_zoom = return_to_zoom;
            z.zoom_transition = zoom_transition;
            z.transition_duration = transition_duration;
            z.image = image;
            z.image_mime = image_mime;
            z.use_background = use_background;
            return z;
        }

        public Slide? target (Presentation p) {
            if (zoom == ZoomKind.SLIDE) {
                foreach (var s in p.slides) if (s.uid == target_uid) return s;
                return null;
            }
            foreach (var s in p.slides) if (s.section != null && s.section.id == section_id) return s;
            return null;
        }

        public override string display_name () {
            if (name != "") return name;
            return zoom == ZoomKind.SLIDE ? _("Slide Zoom") : _("Section Zoom");
        }
    }

    public class EquationElement : Element {
        public string latex = "";
        public string mathml = "";
        public string omml = "";
        public ForeignElement? original = null;
        public string original_sig = "";
        public Bytes? image = null;
        public string image_mime = "image/svg+xml";
        public string color = "";

        public override ElementKind kind {
            get { return ElementKind.EQUATION; }
        }

        public override Element clone () {
            var q = new EquationElement ();
            copy_base (q);
            q.latex = latex;
            q.mathml = mathml;
            q.image = image;
            q.image_mime = image_mime;
            q.color = color;
            q.omml = omml;
            q.original = original != null ? (ForeignElement) original.clone () : null;
            q.original_sig = original_sig;
            return q;
        }

        public override string display_name () {
            return name != "" ? name : _("Equation");
        }
    }

    public class Model3DElement : Element {
        public Bytes? data = null;
        public string format = "glb";
        public double rot_x = 0;
        public double rot_y = 0;
        public double rot_z = 0;
        public double zoom = 1;
        public Bytes? preview = null;
        public ForeignElement? original = null;
        public string original_sig = "";

        public override ElementKind kind {
            get { return ElementKind.MODEL3D; }
        }

        public string signature () {
            return "%g|%g|%g|%g|%s|%u".printf (rot_x, rot_y, rot_z, zoom, format, data != null ? data.hash () : 0);
        }

        public bool pristine () {
            return original != null && original_sig != "" && original_sig == signature ();
        }

        public override Element clone () {
            var m = new Model3DElement ();
            copy_base (m);
            m.data = data;
            m.format = format;
            m.rot_x = rot_x;
            m.rot_y = rot_y;
            m.rot_z = rot_z;
            m.zoom = zoom;
            m.preview = preview;
            m.original = original != null ? (ForeignElement) original.clone () : null;
            m.original_sig = original_sig;
            return m;
        }

        public override string display_name () {
            return name != "" ? name : _("3D Model");
        }
    }
}
