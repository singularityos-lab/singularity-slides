namespace Singularity.Apps.Slides {

    public class CameraRecorder : Object {
        private Gst.Pipeline? pipeline = null;
        private string path = "";
        public string error_message = "";

        public static bool available () {
            unowned string[]? gst_args = null;
            Gst.init (ref gst_args);
            if (CaptureSources.get ("CAMERA") != null) return true;
            bool src = Gst.ElementFactory.find ("v4l2src") != null || Gst.ElementFactory.find ("pipewiresrc") != null;
            bool enc = Gst.ElementFactory.find ("vp8enc") != null && Gst.ElementFactory.find ("webmmux") != null;
            if (!src || !enc) return false;
            foreach (string dev in new string[] { "/dev/video0", "/dev/video1", "/dev/video2" }) if (FileUtils.test (dev, FileTest.EXISTS)) return true;
            return false;
        }

        public bool recording {
            get { return pipeline != null; }
        }

        public bool start (bool with_audio) {
            unowned string[]? gst_args = null;
            Gst.init (ref gst_args);
            path = Path.build_filename (Environment.get_tmp_dir (), "slides-camera-%s.webm".printf (Uuid.string_random ()));
            string desc = (CaptureSources.get ("CAMERA") ?? "v4l2src") + " ! videoconvert ! videoscale ! video/x-raw,width=640,height=360 ! videorate ! video/x-raw,framerate=24/1 ! queue ! vp8enc deadline=1 cpu-used=8 ! queue ! webmmux name=mux ! filesink name=sink";
            if (with_audio && Gst.ElementFactory.find ("opusenc") != null && (CaptureSources.get ("AUDIO") != null || Gst.ElementFactory.find ("autoaudiosrc") != null)) desc += " " + (CaptureSources.get ("AUDIO") ?? "autoaudiosrc") + " ! queue ! audioconvert ! audioresample ! opusenc ! queue ! mux.";
            try {
                pipeline = (Gst.Pipeline) Gst.parse_launch (desc);
            } catch (Error e) {
                error_message = e.message;
                pipeline = null;
                return false;
            }
            pipeline.get_by_name ("sink").set ("location", path);
            if (pipeline.set_state (Gst.State.PLAYING) == Gst.StateChangeReturn.FAILURE) {
                error_message = _("The camera could not be opened");
                pipeline.set_state (Gst.State.NULL);
                pipeline = null;
                return false;
            }
            return true;
        }

        public Bytes? stop () {
            if (pipeline == null) return null;
            pipeline.send_event (new Gst.Event.eos ());
            var msg = pipeline.get_bus ().timed_pop_filtered (4 * Gst.SECOND, Gst.MessageType.EOS | Gst.MessageType.ERROR);
            if (msg != null && msg.type == Gst.MessageType.ERROR) {
                Error err;
                string dbg;
                msg.parse_error (out err, out dbg);
                error_message = err.message;
            }
            pipeline.set_state (Gst.State.NULL);
            pipeline = null;
            Bytes? result = null;
            try {
                uint8[] data;
                FileUtils.get_data (path, out data);
                if (data.length > 1024) result = new Bytes (data);
            } catch (Error e) {
                error_message = e.message;
            }
            FileUtils.unlink (path);
            return result;
        }
    }
}
