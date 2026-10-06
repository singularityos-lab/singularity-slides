namespace Singularity.Apps.Slides {

    public class CaptureSources {
        public static string? get (string kind) {
            string? v = Environment.get_variable ("SINGULARITY_SLIDES_%s_SOURCE".printf (kind));
            return v != null && v.strip () != "" ? v.strip () : null;
        }
    }

    public class AudioRecorder : Object {
        private Gst.Pipeline? pipeline = null;
        private string path = "";
        private int64 started = 0;
        public string mime = "audio/ogg";
        public string error_message = "";
        public bool speech_wav = false;

        public static bool available () {
            unowned string[]? gst_args = null;
            Gst.init (ref gst_args);
            bool src = CaptureSources.get ("AUDIO") != null || Gst.ElementFactory.find ("pulsesrc") != null || Gst.ElementFactory.find ("pipewiresrc") != null || Gst.ElementFactory.find ("autoaudiosrc") != null;
            bool enc = (Gst.ElementFactory.find ("opusenc") != null && Gst.ElementFactory.find ("oggmux") != null) || Gst.ElementFactory.find ("wavenc") != null;
            return src && enc;
        }

        public double elapsed {
            get { return started > 0 ? (get_monotonic_time () - started) / 1000000.0 : 0; }
        }

        public bool recording {
            get { return pipeline != null; }
        }

        public bool start () {
            unowned string[]? gst_args = null;
            Gst.init (ref gst_args);
            string src = CaptureSources.get ("AUDIO") ?? (Gst.ElementFactory.find ("autoaudiosrc") != null ? "autoaudiosrc" : (Gst.ElementFactory.find ("pulsesrc") != null ? "pulsesrc" : "pipewiresrc"));
            bool opus = !speech_wav && Gst.ElementFactory.find ("opusenc") != null && Gst.ElementFactory.find ("oggmux") != null;
            mime = opus ? "audio/ogg" : "audio/wav";
            path = Path.build_filename (Environment.get_tmp_dir (), "slides-rec-%s.%s".printf (Uuid.string_random (), opus ? "ogg" : "wav"));
            string desc = "%s ! queue ! audioconvert ! audioresample ! %s ! filesink name=sink".printf (src, opus ? "opusenc bitrate=64000 ! oggmux" : (speech_wav ? "audio/x-raw,format=S16LE,rate=16000,channels=1 ! wavenc" : "audio/x-raw,rate=44100,channels=1 ! wavenc"));
            try {
                pipeline = (Gst.Pipeline) Gst.parse_launch (desc);
            } catch (Error e) {
                error_message = e.message;
                pipeline = null;
                return false;
            }
            var sink = pipeline.get_by_name ("sink");
            sink.set ("location", path);
            if (pipeline.set_state (Gst.State.PLAYING) == Gst.StateChangeReturn.FAILURE) {
                error_message = _("The microphone could not be opened");
                pipeline.set_state (Gst.State.NULL);
                pipeline = null;
                return false;
            }
            started = get_monotonic_time ();
            return true;
        }

        public Bytes? stop () {
            if (pipeline == null) return null;
            pipeline.send_event (new Gst.Event.eos ());
            var bus = pipeline.get_bus ();
            var msg = bus.timed_pop_filtered (3 * Gst.SECOND, Gst.MessageType.EOS | Gst.MessageType.ERROR);
            if (msg != null && msg.type == Gst.MessageType.ERROR) {
                Error err;
                string dbg;
                msg.parse_error (out err, out dbg);
                error_message = err.message;
            }
            pipeline.set_state (Gst.State.NULL);
            pipeline = null;
            started = 0;
            Bytes? result = null;
            try {
                uint8[] data;
                FileUtils.get_data (path, out data);
                if (data.length > 64) result = new Bytes (data);
            } catch (Error e) {
                error_message = e.message;
            }
            FileUtils.unlink (path);
            return result;
        }

        public void cancel () {
            if (pipeline == null) return;
            pipeline.set_state (Gst.State.NULL);
            pipeline = null;
            started = 0;
            FileUtils.unlink (path);
        }
    }
}
