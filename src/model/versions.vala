namespace Singularity.Apps.Slides {

    public class VersionStore {
        public const int KEEP = 40;
        public static string? root_override = null;

        public static string folder_for (string path) {
            string id = Checksum.compute_for_string (ChecksumType.SHA256, path).substring (0, 20);
            string root = root_override ?? Path.build_filename (Environment.get_user_data_dir (), "singularity-slides", "versions");
            return Path.build_filename (root, id);
        }

        public static void keep_previous (string path) {
            if (!FileUtils.test (path, FileTest.IS_REGULAR)) return;
            string dir = folder_for (path);
            DirUtils.create_with_parents (dir, 0700);
            int dot = path.last_index_of (".");
            string ext = dot > path.last_index_of ("/") ? path.substring (dot) : "";
            var now = new DateTime.now_local ();
            string stamp = now.format ("%Y%m%d-%H%M%S");
            string target = Path.build_filename (dir, stamp + ext);
            int n = 1;
            while (FileUtils.test (target, FileTest.EXISTS)) target = Path.build_filename (dir, "%s-%d%s".printf (stamp, n++, ext));
            try {
                File.new_for_path (path).copy (File.new_for_path (target), FileCopyFlags.OVERWRITE);
                FileUtils.set_contents (Path.build_filename (dir, "source.txt"), path);
            } catch (Error e) {
                warning ("versions: %s", e.message);
                return;
            }
            var all = list (path);
            for (int i = KEEP; i < all.size; i++) FileUtils.unlink (all[i]);
        }

        public static Gee.ArrayList<string> list (string path) {
            var result = new Gee.ArrayList<string> ();
            string dir = folder_for (path);
            try {
                var d = Dir.open (dir);
                string? name;
                while ((name = d.read_name ()) != null) {
                    if (name == "source.txt") continue;
                    result.add (Path.build_filename (dir, name));
                }
            } catch (FileError e) {
            }
            result.sort ((a, b) => strcmp (b, a));
            return result;
        }

        public static DateTime? time_of (string file) {
            string b = Path.get_basename (file);
            if (b.length < 15) return null;
            return new DateTime.local (int.parse (b.substring (0, 4)), int.parse (b.substring (4, 2)), int.parse (b.substring (6, 2)),
                int.parse (b.substring (9, 2)), int.parse (b.substring (11, 2)), int.parse (b.substring (13, 2)));
        }
    }
}
