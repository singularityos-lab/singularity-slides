namespace Singularity.Apps.Slides {

    public class FontEmbed {
        public static Gee.ArrayList<string> used_fonts (Presentation p) {
            var set = new Gee.TreeSet<string> ();
            foreach (var m in p.masters) {
                set.add (m.theme.major_font);
                set.add (m.theme.minor_font);
            }
            foreach (var s in p.slides) {
                var theme = p.master_for (s).theme;
                foreach (var e in s.elements) collect_element (e, theme, set);
            }
            var list = new Gee.ArrayList<string> ();
            foreach (string f in set) if (f.strip () != "" && !f.has_prefix ("+")) list.add (f);
            return list;
        }

        private static void collect_element (Element e, Theme theme, Gee.Set<string> set) {
            var body = e.text_body ();
            if (body != null) {
                foreach (var para in body.paragraphs) foreach (var r in para.runs) if (r.font != "") set.add (theme.resolve_font (r.font));
            }
            var g = e as GroupElement;
            if (g != null) foreach (var c in g.children) collect_element (c, theme, set);
        }

        public static string? find (string family, bool bold, bool italic) {
            string pattern = "%s:style=%s".printf (family, bold && italic ? "Bold Italic" : (bold ? "Bold" : (italic ? "Italic" : "Regular")));
            string stdout_text;
            int status;
            try {
                Process.spawn_sync (null, { "fc-match", "-f", "%{family}\n%{file}", pattern }, null, SpawnFlags.SEARCH_PATH | SpawnFlags.STDERR_TO_DEV_NULL, null, out stdout_text, null, out status);
            } catch (SpawnError e) {
                return null;
            }
            if (status != 0 || stdout_text == null) return null;
            var parts = stdout_text.split ("\n");
            if (parts.length < 2) return null;
            bool same = false;
            foreach (string fam in parts[0].split (",")) if (fam.strip ().down () == family.down ()) same = true;
            if (!same) return null;
            string path = parts[1].strip ();
            string low = path.down ();
            if (!low.has_suffix (".ttf") && !low.has_suffix (".otf")) return null;
            return FileUtils.test (path, FileTest.EXISTS) ? path : null;
        }

        private static Bytes? load (string? path) {
            if (path == null) return null;
            try {
                uint8[] data;
                FileUtils.get_data (path, out data);
                return new Bytes (data);
            } catch (Error e) {
                return null;
            }
        }

        public static int collect (Presentation p, Gee.List<string> families) {
            int n = 0;
            foreach (string f in families) {
                bool have = false;
                foreach (var ef in p.fonts) if (ef.family == f) have = true;
                if (have) continue;
                string? reg = find (f, false, false);
                var data = load (reg);
                if (data == null) continue;
                var ef = new EmbeddedFont (f, data);
                string? b = find (f, true, false);
                string? it = find (f, false, true);
                string? bi = find (f, true, true);
                if (b != reg) ef.bold = load (b);
                if (it != reg) ef.italic = load (it);
                if (bi != reg && bi != b && bi != it) ef.bold_italic = load (bi);
                p.fonts.add (ef);
                n++;
            }
            return n;
        }
    }
}
