namespace Singularity.Apps.Slides {

    public errordomain FormatError {
        INVALID,
        UNSUPPORTED
    }

    public enum FileKind {
        PPTX,
        ODP;

        public static FileKind from_path (string path) {
            string p = path.down ();
            if (p.has_suffix (".odp") || p.has_suffix (".otp")) return ODP;
            return PPTX;
        }
    }

    public class UndoStep {
        public string label;
        public Presentation state;
        public int slide;
        public string key;
        public int64 time;

        public UndoStep (string label, Presentation state, int slide, string key) {
            this.label = label;
            this.state = state;
            this.slide = slide;
            this.key = key;
            time = get_monotonic_time ();
        }
    }

    public class Document : Object {
        public Presentation pres { get; private set; }
        public string? path = null;
        public string password = "";
        public bool modified { get; set; default = false; }
        public int current_slide = 0;
        private Gee.ArrayList<UndoStep> undo_stack = new Gee.ArrayList<UndoStep> ();
        private Gee.ArrayList<UndoStep> redo_stack = new Gee.ArrayList<UndoStep> ();
        private const int MAX_UNDO = 200;

        public signal void changed ();
        public signal void replaced (int slide);

        public Document (Presentation? p = null) {
            pres = p ?? Factory.new_presentation (ThemePreset.all ()[0]);
        }

        public bool can_undo {
            get { return undo_stack.size > 0; }
        }

        public bool can_redo {
            get { return redo_stack.size > 0; }
        }

        public string undo_label {
            owned get { return undo_stack.size > 0 ? undo_stack[undo_stack.size - 1].label : ""; }
        }

        public string redo_label {
            owned get { return redo_stack.size > 0 ? redo_stack[redo_stack.size - 1].label : ""; }
        }

        public void checkpoint (string label, string key = "") {
            if (key != "" && undo_stack.size > 0) {
                var last = undo_stack[undo_stack.size - 1];
                if (last.key == key && get_monotonic_time () - last.time < 1500000) {
                    last.time = get_monotonic_time ();
                    redo_stack.clear ();
                    return;
                }
            }
            undo_stack.add (new UndoStep (label, pres.clone (), current_slide, key));
            if (undo_stack.size > MAX_UNDO) undo_stack.remove_at (0);
            redo_stack.clear ();
        }

        public void drop_checkpoint () {
            if (undo_stack.size > 0) undo_stack.remove_at (undo_stack.size - 1);
        }

        public void touch () {
            modified = true;
            changed ();
        }

        public void edit (string label, EditFunc f, string key = "") {
            checkpoint (label, key);
            f ();
            touch ();
        }

        public delegate void EditFunc ();

        public void undo () {
            if (undo_stack.size == 0) return;
            var step = undo_stack.remove_at (undo_stack.size - 1);
            redo_stack.add (new UndoStep (step.label, pres, current_slide, ""));
            pres = step.state;
            current_slide = step.slide.clamp (0, int.max (pres.slides.size - 1, 0));
            modified = true;
            replaced (current_slide);
            changed ();
        }

        public void redo () {
            if (redo_stack.size == 0) return;
            var step = redo_stack.remove_at (redo_stack.size - 1);
            undo_stack.add (new UndoStep (step.label, pres, current_slide, ""));
            pres = step.state;
            current_slide = step.slide.clamp (0, int.max (pres.slides.size - 1, 0));
            modified = true;
            replaced (current_slide);
            changed ();
        }

        public void replace_presentation (Presentation p) {
            pres = p;
            undo_stack.clear ();
            redo_stack.clear ();
            current_slide = 0;
            replaced (0);
            changed ();
        }

        public static Presentation load_bytes (uint8[] data, string name) throws Error {
            var zip = new ZipReader (data);
            if (zip.has ("ppt/presentation.xml")) return new PptxReader (zip).read ();
            if (zip.has ("content.xml")) return new OdpReader (zip).read ();
            if (FileKind.from_path (name) == FileKind.ODP) throw new FormatError.INVALID (_("The file is not an OpenDocument presentation."));
            throw new FormatError.INVALID (_("The file is not a PowerPoint or OpenDocument presentation."));
        }

        public static bool needs_password (string path) {
            try {
                uint8[] data;
                FileUtils.get_data (path, out data);
                return OfficeCrypto.is_encrypted (data) || OdfCrypto.is_encrypted (data);
            } catch (Error e) {
                return false;
            }
        }

        public static uint8[] decrypt (uint8[] data, string password) throws Error {
            if (OfficeCrypto.is_encrypted (data)) {
                if (password == "") throw new CryptoError.PASSWORD_REQUIRED (_("This presentation is protected with a password."));
                return OfficeCrypto.decrypt (data, password);
            }
            if (OdfCrypto.is_encrypted (data)) {
                if (password == "") throw new CryptoError.PASSWORD_REQUIRED (_("This presentation is protected with a password."));
                return OdfCrypto.decrypt (data, password);
            }
            return data;
        }

        public static uint8[] encrypt (uint8[] data, string ext, string password) throws Error {
            if (password == "") return data;
            if (ext == "odp" || ext == "otp") return OdfCrypto.encrypt (data, password);
            return OfficeCrypto.encrypt (data, password);
        }

        public static Document open (string path, string password = "") throws Error {
            uint8[] raw;
            FileUtils.get_data (path, out raw);
            var data = decrypt (raw, password);
            var d = new Document (load_bytes (data, path));
            d.password = password;
            string low = path.down ();
            d.path = low.has_suffix (".potx") || low.has_suffix (".otp") ? null : path;
            return d;
        }

        public static uint8[] serialize (Presentation p, FileKind kind) throws Error {
            if (kind == FileKind.ODP) return new OdpWriter (p).write ();
            return new PptxWriter (p).write ();
        }

        public static uint8[] serialize_as (Presentation p, string ext) throws Error {
            switch (ext) {
                case "ppsx":
                case "potx":
                    var w = new PptxWriter (p);
                    w.main_content_type = ext == "ppsx" ? Ooxml.CT_SLIDESHOW : Ooxml.CT_TEMPLATE;
                    return w.write ();
                case "odp":
                case "otp":
                    return new OdpWriter (p).write ();
                default:
                    return new PptxWriter (p).write ();
            }
        }

        public void save_to (string target) throws Error {
            var now = new DateTime.now_utc ();
            if (pres.properties.created == "") pres.properties.created = now.format ("%Y-%m-%dT%H:%M:%SZ");
            pres.properties.modified = now.format ("%Y-%m-%dT%H:%M:%SZ");
            if (pres.properties.author == "") pres.properties.author = Environment.get_real_name () != "Unknown" ? Environment.get_real_name () : Environment.get_user_name ();
            int dot = target.last_index_of (".");
            string ext = dot >= 0 ? target.substring (dot + 1).down () : "pptx";
            var bytes = encrypt (serialize_as (pres, ext), ext, password);
            string tmp = target + ".part";
            FileUtils.set_data (tmp, bytes);
            VersionStore.keep_previous (target);
            if (FileUtils.rename (tmp, target) != 0) {
                FileUtils.remove (tmp);
                throw new FileError.FAILED (_("Could not write \"%s\".").printf (target));
            }
            path = target;
            modified = false;
            changed ();
        }

        public Slide? slide {
            owned get { return current_slide >= 0 && current_slide < pres.slides.size ? pres.slides[current_slide] : null; }
        }
    }
}
