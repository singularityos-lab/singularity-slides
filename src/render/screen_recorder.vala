namespace Singularity.Apps.Slides {

    public class ScreenRecorder : Object {
        private const string PORTAL = "org.freedesktop.portal.Desktop";
        private const string PATH = "/org/freedesktop/portal/desktop";
        private const string IFACE = "org.freedesktop.portal.ScreenCast";

        private DBusConnection? bus = null;
        private string session = "";
        private Gst.Pipeline? pipeline = null;
        private string file = "";
        private int64 started = 0;
        public string error_message = "";
        public bool with_audio = true;

        public bool recording {
            get { return pipeline != null; }
        }

        public double elapsed {
            get { return started > 0 ? (get_monotonic_time () - started) / 1000000.0 : 0; }
        }

        private string token () {
            return "slides%u".printf (Random.next_int ());
        }

        private async Variant request (string method, Variant args, string handle_token) throws Error {
            string sender = bus.unique_name.substring (1).replace (".", "_");
            string req_path = "/org/freedesktop/portal/desktop/request/%s/%s".printf (sender, handle_token);
            Variant? result = null;
            uint32 code = 2;
            var loop_done = false;
            uint sub = bus.signal_subscribe (PORTAL, "org.freedesktop.portal.Request", "Response", req_path, null, DBusSignalFlags.NONE, (c, s, p, i, sig, parameters) => {
                parameters.get ("(u@a{sv})", out code, out result);
                loop_done = true;
                request.callback ();
            });
            try {
                yield bus.call (PORTAL, PATH, IFACE, method, args, null, DBusCallFlags.NONE, -1, null);
                if (!loop_done) yield;
            } finally {
                bus.signal_unsubscribe (sub);
            }
            if (code != 0) throw new IOError.CANCELLED (code == 1 ? _("Screen recording was cancelled") : _("Screen recording is not allowed"));
            return result;
        }

        public async bool start () {
            unowned string[]? gst_args = null;
            Gst.init (ref gst_args);
            try {
                bus = yield Bus.get (BusType.SESSION);
                string t1 = token (), t2 = token ();
                var b1 = new VariantBuilder (new VariantType ("a{sv}"));
                b1.add ("{sv}", "handle_token", new Variant.string (t1));
                b1.add ("{sv}", "session_handle_token", new Variant.string (t2));
                var r1 = yield request ("CreateSession", new Variant ("(a{sv})", b1), t1);
                var sh = r1.lookup_value ("session_handle", null);
                session = sh != null ? sh.get_string () : "";
                if (session == "") throw new IOError.FAILED (_("The screen sharing service did not start a session"));
                string t3 = token ();
                var b2 = new VariantBuilder (new VariantType ("a{sv}"));
                b2.add ("{sv}", "handle_token", new Variant.string (t3));
                b2.add ("{sv}", "types", new Variant.uint32 (3));
                b2.add ("{sv}", "multiple", new Variant.boolean (false));
                b2.add ("{sv}", "cursor_mode", new Variant.uint32 (2));
                yield request ("SelectSources", new Variant ("(oa{sv})", session, b2), t3);
                string t4 = token ();
                var b3 = new VariantBuilder (new VariantType ("a{sv}"));
                b3.add ("{sv}", "handle_token", new Variant.string (t4));
                var r3 = yield request ("Start", new Variant ("(osa{sv})", session, "", b3), t4);
                var streams = r3.lookup_value ("streams", null);
                if (streams == null || streams.n_children () == 0) throw new IOError.FAILED (_("No screen was chosen"));
                uint32 node;
                Variant props;
                streams.get_child_value (0).get ("(u@a{sv})", out node, out props);
                UnixFDList fds;
                var fdv = bus.call_with_unix_fd_list_sync (PORTAL, PATH, IFACE, "OpenPipeWireRemote",
                    new Variant ("(oa{sv})", session, new VariantBuilder (new VariantType ("a{sv}"))), new VariantType ("(h)"), DBusCallFlags.NONE, -1, null, out fds, null);
                int32 idx;
                fdv.get ("(h)", out idx);
                int fd = fds.get (idx);
                file = Path.build_filename (Environment.get_tmp_dir (), "slides-screen-%s.webm".printf (Uuid.string_random ()));
                bool mp4 = Gst.ElementFactory.find ("x264enc") != null && Gst.ElementFactory.find ("mp4mux") != null && (!with_audio || Gst.ElementFactory.find ("avenc_aac") != null);
                if (mp4) file = file.replace (".webm", ".mp4");
                string venc = mp4 ? "x264enc tune=zerolatency speed-preset=veryfast ! h264parse" : "vp8enc deadline=1 cpu-used=8";
                string mux = mp4 ? "mp4mux name=mux" : "webmmux name=mux";
                string aenc = mp4 ? "avenc_aac ! aacparse" : "opusenc";
                bool audio = with_audio && Gst.ElementFactory.find (mp4 ? "avenc_aac" : "opusenc") != null && (CaptureSources.get ("AUDIO") != null || Gst.ElementFactory.find ("autoaudiosrc") != null);
                string screen_src = CaptureSources.get ("SCREEN") ?? "pipewiresrc fd=%d path=%u do-timestamp=true keepalive-time=1000".printf (fd, node);
                string desc = "%s ! videoconvert ! videorate ! video/x-raw,framerate=30/1 ! queue ! %s ! queue ! %s ! filesink location=\"%s\"".printf (screen_src, venc, mux, file);
                if (audio) desc += " " + (CaptureSources.get ("AUDIO") ?? "autoaudiosrc") + " ! queue ! audioconvert ! audioresample ! %s ! queue ! mux.".printf (aenc);
                pipeline = (Gst.Pipeline) Gst.parse_launch (desc);
                if (pipeline.set_state (Gst.State.PLAYING) == Gst.StateChangeReturn.FAILURE) throw new IOError.FAILED (_("The recording could not start"));
                started = get_monotonic_time ();
                return true;
            } catch (Error e) {
                error_message = e.message;
                close_session ();
                pipeline = null;
                return false;
            }
        }

        private void close_session () {
            if (bus == null || session == "") return;
            try {
                bus.call_sync (PORTAL, session, "org.freedesktop.portal.Session", "Close", null, null, DBusCallFlags.NONE, 2000, null);
            } catch (Error e) {
            }
            session = "";
        }

        public Bytes? stop (out string mime) {
            mime = file.has_suffix (".mp4") ? "video/mp4" : "video/webm";
            if (pipeline == null) return null;
            pipeline.send_event (new Gst.Event.eos ());
            var msg = pipeline.get_bus ().timed_pop_filtered (5 * Gst.SECOND, Gst.MessageType.EOS | Gst.MessageType.ERROR);
            if (msg != null && msg.type == Gst.MessageType.ERROR) {
                Error err;
                string dbg;
                msg.parse_error (out err, out dbg);
                error_message = err.message;
            }
            pipeline.set_state (Gst.State.NULL);
            pipeline = null;
            started = 0;
            close_session ();
            Bytes? result = null;
            try {
                uint8[] data;
                FileUtils.get_data (file, out data);
                if (data.length > 1024) result = new Bytes (data);
            } catch (Error e) {
                error_message = e.message;
            }
            FileUtils.unlink (file);
            return result;
        }
    }
}
