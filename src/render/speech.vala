namespace Singularity.Apps.Slides {

    public class SpeechService {
        public const string BUS_NAME = "dev.sinty.Dictation";

        public static bool present () {
            try {
                var connection = Bus.get_sync (BusType.SESSION);
                var reply = connection.call_sync ("org.freedesktop.DBus", "/org/freedesktop/DBus", "org.freedesktop.DBus", "NameHasOwner",
                    new Variant ("(s)", BUS_NAME), new VariantType ("(b)"), DBusCallFlags.NONE, 2000, null);
                bool owned;
                reply.get ("(b)", out owned);
                if (owned) return true;
                var act = connection.call_sync ("org.freedesktop.DBus", "/org/freedesktop/DBus", "org.freedesktop.DBus", "ListActivatableNames",
                    null, new VariantType ("(as)"), DBusCallFlags.NONE, 2000, null);
                var names = act.get_child_value (0);
                for (size_t i = 0; i < names.n_children (); i++) if (names.get_child_value (i).get_string () == BUS_NAME) return true;
            } catch (Error e) {
            }
            return false;
        }

        public static string language () {
            string l = Thesaurus.current_language ();
            int u = l.index_of ("_");
            return u > 0 ? l.substring (0, u) : l;
        }

        public static async string transcribe (Bytes wav, Cancellable? cancellable = null) throws Error {
            string path;
            int fd = FileUtils.open_tmp ("slides-speech-XXXXXX.wav", out path);
            FileUtils.close (fd);
            try {
                FileUtils.set_data (path, wav.get_data ());
                var connection = yield Bus.get (BusType.SESSION, cancellable);
                var reply = yield connection.call (BUS_NAME, "/dev/sinty/Dictation", "dev.sinty.Dictation", "TranscribeFile",
                    new Variant ("(ss)", path, language ()), new VariantType ("(s)"), DBusCallFlags.NONE, 10 * 60 * 1000, cancellable);
                string text;
                reply.get ("(s)", out text);
                return text.strip ();
            } catch (Error e) {
                DBusError.strip_remote_error (e);
                throw e;
            } finally {
                FileUtils.unlink (path);
            }
        }
    }
}
