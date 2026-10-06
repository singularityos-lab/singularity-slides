namespace Singularity.Apps.Slides {

    public class PersonalTemplates {
        public static string? override_dir = null;

        public static string folder () {
            if (override_dir != null) return override_dir;
            return Path.build_filename (Environment.get_user_data_dir (), "singularity-slides", "templates");
        }

        public static Gee.ArrayList<string> list () {
            var result = new Gee.ArrayList<string> ();
            var dirs = new Gee.ArrayList<string> ();
            dirs.add (folder ());
            if (override_dir == null) {
                string? t = Environment.get_user_special_dir (UserDirectory.TEMPLATES);
                if (t != null && t != Environment.get_home_dir ()) dirs.add (t);
            }
            foreach (string dir in dirs) {
                try {
                    var d = Dir.open (dir);
                    string? n;
                    while ((n = d.read_name ()) != null) {
                        string low = n.down ();
                        if (low.has_suffix (".potx") || low.has_suffix (".otp")) result.add (Path.build_filename (dir, n));
                    }
                } catch (FileError e) {
                }
            }
            result.sort ((a, b) => strcmp (Path.get_basename (a).down (), Path.get_basename (b).down ()));
            return result;
        }

        public static string save (Presentation p, string name) throws Error {
            string dir = folder ();
            DirUtils.create_with_parents (dir, 0700);
            string safe = name.strip ().replace ("/", "-");
            if (safe == "") safe = _("Template");
            string path = Path.build_filename (dir, safe + ".potx");
            FileUtils.set_data (path, Document.serialize_as (p, "potx"));
            return path;
        }
    }
}
