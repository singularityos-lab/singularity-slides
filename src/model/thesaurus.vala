namespace Singularity.Apps.Slides {

    public class ThesaurusMeaning {
        public string part = "";
        public Gee.ArrayList<string> words = new Gee.ArrayList<string> ();
    }

    public class Thesaurus {
        public static Gee.ArrayList<string> dirs () {
            var list = new Gee.ArrayList<string> ();
            string? extra = Environment.get_variable ("SINGULARITY_THESAURUS_DIRS");
            if (extra != null) foreach (string d in extra.split (":")) if (d != "") list.add (d);
            list.add (Path.build_filename (Environment.get_user_data_dir (), "mythes"));
            foreach (string base_dir in Environment.get_system_data_dirs ()) {
                list.add (Path.build_filename (base_dir, "mythes"));
                list.add (Path.build_filename (base_dir, "myspell", "dicts"));
                list.add (Path.build_filename (base_dir, "hunspell"));
            }
            return list;
        }

        public static string? file_for (string lang) {
            string key = lang.replace ("-", "_");
            string[] parts = key.split ("_");
            var names = new Gee.ArrayList<string> ();
            names.add ("th_%s_v2.dat".printf (key));
            names.add ("th_%s.dat".printf (key));
            if (parts.length > 1) {
                names.add ("th_%s_%s_v2.dat".printf (parts[0], parts[1].up ()));
                names.add ("th_%s_%s.dat".printf (parts[0], parts[1].up ()));
            }
            names.add ("th_%s_v2.dat".printf (parts[0]));
            names.add ("th_%s.dat".printf (parts[0]));
            foreach (string d in dirs ()) {
                foreach (string n in names) {
                    string p = Path.build_filename (d, n);
                    if (FileUtils.test (p, FileTest.IS_REGULAR)) return p;
                }
                try {
                    var dir = Dir.open (d);
                    string? f;
                    while ((f = dir.read_name ()) != null) {
                        if (f.has_prefix ("th_" + parts[0]) && f.has_suffix (".dat")) return Path.build_filename (d, f);
                    }
                } catch (FileError e) {
                }
            }
            return null;
        }

        public static string current_language () {
            foreach (string l in Intl.get_language_names ()) {
                if (l == "C" || l == "POSIX" || l.contains (".")) continue;
                return l;
            }
            return "en_US";
        }

        public static Gee.ArrayList<ThesaurusMeaning> lookup_in (string path, string word) {
            var result = new Gee.ArrayList<ThesaurusMeaning> ();
            string data;
            try {
                FileUtils.get_contents (path, out data);
            } catch (Error e) {
                return result;
            }
            if (!data.validate ()) {
                try {
                    data = convert (data, data.length, "UTF-8", "ISO-8859-1");
                } catch (Error e) {
                    return result;
                }
            }
            string needle = word.down ().strip ();
            string[] lines = data.split ("\n");
            for (int i = 1; i < lines.length; i++) {
                string l = lines[i];
                int bar = l.index_of_char ('|');
                if (bar < 0 || l.has_prefix ("(") || l.has_prefix ("-")) continue;
                if (l.substring (0, bar).down () != needle) continue;
                int n = int.parse (l.substring (bar + 1));
                for (int k = 1; k <= n && i + k < lines.length; k++) {
                    string[] parts = lines[i + k].strip ().split ("|");
                    if (parts.length < 2) continue;
                    var m = new ThesaurusMeaning ();
                    m.part = parts[0].replace ("(", "").replace (")", "").strip ();
                    for (int j = 1; j < parts.length; j++) {
                        string w = parts[j].strip ();
                        if (w != "" && w.down () != needle) m.words.add (w);
                    }
                    if (m.words.size > 0) result.add (m);
                }
                break;
            }
            return result;
        }

        public static Gee.ArrayList<ThesaurusMeaning> lookup (string word, string? lang = null) {
            string? path = file_for (lang ?? current_language ());
            if (path == null) return new Gee.ArrayList<ThesaurusMeaning> ();
            return lookup_in (path, word);
        }
    }
}
