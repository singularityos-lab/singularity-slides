namespace Singularity.Apps.Slides {

    public class VideoEncoder {
        public enum Container {
            MP4,
            WEBM
        }

        private const int AUDIO_RATE = 48000;
        private const int AUDIO_CHUNK = 4800;

        public bool audio_dropped = false;
        public string? audio_drop_reason = null;
        public int width { get; private set; }
        public int height { get; private set; }
        public int fps { get; private set; }

        private Container container;
        private Gst.Pipeline pipeline;
        private Gst.App.Src video_src;
        private Gst.App.Src? audio_src = null;
        private Gst.Element muxer;
        private uint64 frame_index = 0;
        private bool started = false;
        private bool finished = false;
        private string[] audio_paths = {};
        private double[] audio_offsets = {};
        private uint8[] audio_pcm = {};
        private int64 audio_pos = 0;
        private int64 audio_frames = 0;
        private bool audio_eos = false;

        public static bool available (Container c) {
            ensure_init ();
            if (!has ("appsrc") || !has ("videoconvert") || !has ("queue") || !has ("capsfilter") || !has ("filesink")) return false;
            if (!has (c == Container.MP4 ? "mp4mux" : "webmmux")) return false;
            return pick_video_encoder (c) != null;
        }

        public VideoEncoder (string path, int width, int height, int fps, Container c) throws Error {
            ensure_init ();
            if (!available (c)) throw new IOError.NOT_SUPPORTED (_("No suitable video encoder is installed."));
            this.width = int.max (2, width - width % 2);
            this.height = int.max (2, height - height % 2);
            this.fps = int.max (1, fps);
            container = c;
            pipeline = new Gst.Pipeline (null);
            video_src = (Gst.App.Src) make ("appsrc");
            video_src.caps = Gst.Caps.from_string ("video/x-raw,format=%s,width=%d,height=%d,framerate=%d/1,pixel-aspect-ratio=1/1".printf (ByteOrder.HOST == ByteOrder.LITTLE_ENDIAN ? "BGRx" : "xRGB", this.width, this.height, this.fps));
            video_src.format = Gst.Format.TIME;
            video_src.is_live = false;
            video_src.block = true;
            video_src.stream_type = Gst.App.StreamType.STREAM;
            video_src.max_bytes = (uint64) this.width * this.height * 4 * 4;
            var convert = make ("videoconvert");
            var filter = make ("capsfilter");
            filter.set ("caps", Gst.Caps.from_string ("video/x-raw,format=I420"));
            var queue = make ("queue");
            var encoder = make (pick_video_encoder (c));
            configure_video_encoder (encoder);
            muxer = make (c == Container.MP4 ? "mp4mux" : "webmmux");
            var sink = make ("filesink");
            sink.set ("location", path);
            pipeline.add_many (video_src, convert, filter, queue, encoder, muxer, sink);
            Gst.Element last = encoder;
            if (c == Container.MP4 && has ("h264parse")) {
                var parse = make ("h264parse");
                pipeline.add (parse);
                if (!encoder.link (parse)) throw new IOError.FAILED (_("Could not set up the video encoder."));
                last = parse;
            }
            if (!video_src.link_many (convert, filter, queue, encoder) || !last.link (muxer) || !muxer.link (sink)) throw new IOError.FAILED (_("Could not set up the video encoder."));
        }

        ~VideoEncoder () {
            if (pipeline != null) pipeline.set_state (Gst.State.NULL);
        }

        public void add_audio_file (string path, double at_seconds) {
            if (started) {
                note_audio_problem (_("\"%s\" was added after the video started and was left out.").printf (Path.get_basename (path)));
                return;
            }
            audio_paths += path;
            audio_offsets += double.max (0, at_seconds);
        }

        public void push_frame (Cairo.ImageSurface frame) throws Error {
            if (finished) throw new IOError.CLOSED (_("The video has already been finished."));
            if (!started) start ();
            check_bus ();
            var surf = new Cairo.ImageSurface (Cairo.Format.RGB24, width, height);
            var cr = new Cairo.Context (surf);
            cr.set_source_rgb (1, 1, 1);
            cr.paint ();
            if (frame.get_width () != width || frame.get_height () != height) {
                cr.scale ((double) width / int.max (1, frame.get_width ()), (double) height / int.max (1, frame.get_height ()));
                cr.set_source_surface (frame, 0, 0);
                cr.get_source ().set_filter (Cairo.Filter.GOOD);
            } else {
                cr.set_source_surface (frame, 0, 0);
            }
            cr.paint ();
            surf.flush ();
            int row = width * 4, stride = surf.get_stride ();
            var data = new uint8[row * height];
            uint8* src = (uint8*) surf.get_data ();
            for (int y = 0; y < height; y++) Memory.copy (&data[y * row], src + y * stride, row);
            var buf = new Gst.Buffer.wrapped ((owned) data);
            uint64 pts = Gst.Util.uint64_scale (frame_index, Gst.SECOND, fps);
            uint64 next = Gst.Util.uint64_scale (frame_index + 1, Gst.SECOND, fps);
            buf.pts = pts;
            buf.dts = pts;
            buf.duration = next - pts;
            buf.offset = frame_index;
            frame_index++;
            var ret = video_src.push_buffer ((owned) buf);
            pump_audio (next, false);
            if (ret != Gst.FlowReturn.OK) {
                check_bus ();
                throw new IOError.FAILED (_("The video encoder stopped unexpectedly."));
            }
        }

        public void finish () throws Error {
            if (finished) return;
            finished = true;
            if (frame_index == 0) {
                pipeline.set_state (Gst.State.NULL);
                throw new IOError.INVALID_DATA (_("There are no frames to export."));
            }
            pump_audio (Gst.Util.uint64_scale (frame_index, Gst.SECOND, fps), true);
            video_src.end_of_stream ();
            var msg = pipeline.get_bus ().timed_pop_filtered (300 * Gst.SECOND, Gst.MessageType.EOS | Gst.MessageType.ERROR);
            pipeline.set_state (Gst.State.NULL);
            if (msg == null) throw new IOError.TIMED_OUT (_("The video encoder did not finish in time."));
            if (msg.type == Gst.MessageType.ERROR) {
                Error err;
                string debug;
                msg.parse_error (out err, out debug);
                throw new IOError.FAILED (_("Could not write the video: %s").printf (err.message));
            }
        }

        private void start () throws Error {
            if (audio_paths.length > 0) setup_audio ();
            if (pipeline.set_state (Gst.State.PLAYING) == Gst.StateChangeReturn.FAILURE) {
                check_bus ();
                throw new IOError.FAILED (_("Could not start the video encoder."));
            }
            started = true;
        }

        private void setup_audio () {
            string? enc_name = null;
            string[] names = container == Container.MP4 ? new string[] { "fdkaacenc", "avenc_aac", "voaacenc" } : new string[] { "opusenc" };
            foreach (var n in names) {
                if (can_make (n)) {
                    enc_name = n;
                    break;
                }
            }
            if (enc_name == null || !has ("audioconvert") || !has ("audioresample") || !has ("uridecodebin") || !has ("appsink")) {
                audio_dropped = true;
                note_audio_problem (container == Container.MP4 ? _("No AAC audio encoder is installed, so the video has no sound.") : _("No Opus audio encoder is installed, so the video has no sound."));
                return;
            }
            ByteArray[] tracks = {};
            var starts = new int64[audio_paths.length];
            int64 total = 0;
            for (int i = 0; i < audio_paths.length; i++) {
                ByteArray pcm;
                try {
                    pcm = decode_file (audio_paths[i]);
                } catch (Error e) {
                    note_audio_problem (_("Could not read \"%s\": %s").printf (Path.get_basename (audio_paths[i]), e.message));
                    pcm = new ByteArray ();
                }
                starts[i] = (int64) Math.llround (audio_offsets[i] * AUDIO_RATE);
                int64 frames = pcm.len / 4;
                if (frames > 0) total = int64.max (total, starts[i] + frames);
                tracks += pcm;
            }
            if (total == 0) {
                audio_dropped = true;
                note_audio_problem (_("None of the audio files could be used, so the video has no sound."));
                return;
            }
            var mix = new int[(int) (total * 2)];
            for (int i = 0; i < audio_paths.length; i++) {
                var pcm = tracks[i];
                int16* s = (int16*) pcm.data;
                int64 samples = (pcm.len / 4) * 2;
                int64 base_index = starts[i] * 2;
                for (int64 k = 0; k < samples; k++) mix[base_index + k] += s[k];
            }
            audio_pcm = new uint8[(int) (total * 4)];
            int16* out_samples = (int16*) audio_pcm;
            for (int64 k = 0; k < total * 2; k++) out_samples[k] = (int16) mix[k].clamp (-32768, 32767);
            audio_frames = total;
            try {
                attach_audio (enc_name);
            } catch (Error e) {
                audio_dropped = true;
                note_audio_problem (_("The audio could not be added to this video format."));
                audio_src = null;
            }
        }

        private void attach_audio (string enc_name) throws Error {
            var src = (Gst.App.Src) make ("appsrc");
            src.caps = Gst.Caps.from_string ("audio/x-raw,format=%s,layout=interleaved,rate=%d,channels=2,channel-mask=(bitmask)0x3".printf (ByteOrder.HOST == ByteOrder.LITTLE_ENDIAN ? "S16LE" : "S16BE", AUDIO_RATE));
            src.format = Gst.Format.TIME;
            src.is_live = false;
            src.block = false;
            src.stream_type = Gst.App.StreamType.STREAM;
            src.max_bytes = AUDIO_CHUNK * 4 * 2;
            var convert = make ("audioconvert");
            var resample = make ("audioresample");
            var queue = make ("queue");
            var encoder = make (enc_name);
            Gst.Element? parse = container == Container.MP4 && has ("aacparse") ? make ("aacparse") : null;
            pipeline.add_many (src, convert, resample, queue, encoder);
            if (parse != null) pipeline.add (parse);
            bool ok = src.link_many (convert, resample, queue, encoder);
            if (ok && parse != null) ok = encoder.link (parse) && parse.link (muxer);
            else if (ok) ok = encoder.link (muxer);
            if (!ok) {
                pipeline.remove (src);
                pipeline.remove (convert);
                pipeline.remove (resample);
                pipeline.remove (queue);
                pipeline.remove (encoder);
                if (parse != null) pipeline.remove (parse);
                throw new IOError.NOT_SUPPORTED (_("The audio could not be added to this video format."));
            }
            audio_src = src;
        }

        private void pump_audio (uint64 until, bool last) {
            if (audio_src == null || audio_eos) return;
            int64 stop = int64.min (audio_frames, (int64) Gst.Util.uint64_scale (until, AUDIO_RATE, Gst.SECOND));
            while (audio_pos < stop) {
                int64 n = int64.min (AUDIO_CHUNK, stop - audio_pos);
                var data = audio_pcm[(int) (audio_pos * 4) : (int) ((audio_pos + n) * 4)];
                var buf = new Gst.Buffer.wrapped ((owned) data);
                uint64 pts = Gst.Util.uint64_scale ((uint64) audio_pos, Gst.SECOND, AUDIO_RATE);
                uint64 next = Gst.Util.uint64_scale ((uint64) (audio_pos + n), Gst.SECOND, AUDIO_RATE);
                buf.pts = pts;
                buf.dts = pts;
                buf.duration = next - pts;
                audio_pos += n;
                if (audio_src.push_buffer ((owned) buf) != Gst.FlowReturn.OK) {
                    audio_eos = true;
                    return;
                }
            }
            if (last || audio_pos >= audio_frames) {
                audio_eos = true;
                audio_src.end_of_stream ();
            }
        }

        private ByteArray decode_file (string path) throws Error {
            var p = new Gst.Pipeline (null);
            var dec = make ("uridecodebin");
            dec.set ("uri", File.new_for_path (path).get_uri ());
            var convert = make ("audioconvert");
            var resample = make ("audioresample");
            var filter = make ("capsfilter");
            filter.set ("caps", Gst.Caps.from_string ("audio/x-raw,format=%s,layout=interleaved,rate=%d,channels=2".printf (ByteOrder.HOST == ByteOrder.LITTLE_ENDIAN ? "S16LE" : "S16BE", AUDIO_RATE)));
            var sink = (Gst.App.Sink) make ("appsink");
            sink.sync = false;
            p.add_many (dec, convert, resample, filter, sink);
            if (!convert.link_many (resample, filter, sink)) throw new IOError.FAILED (_("Could not set up the audio decoder."));
            bool linked = false, no_more = false;
            dec.pad_added.connect ((pad) => {
                var caps = pad.get_current_caps () ?? pad.query_caps (null);
                string name = caps != null && caps.get_size () > 0 ? caps.get_structure (0).get_name () : "";
                if (!linked && name.has_prefix ("audio/")) {
                    linked = pad.link (convert.get_static_pad ("sink")) == Gst.PadLinkReturn.OK;
                    return;
                }
                var fake = Gst.ElementFactory.make ("fakesink", null);
                if (fake == null) return;
                fake.set ("sync", false);
                p.add (fake);
                fake.sync_state_with_parent ();
                pad.link (fake.get_static_pad ("sink"));
            });
            dec.no_more_pads.connect (() => {
                no_more = true;
            });
            var bytes = new ByteArray ();
            var bus = p.get_bus ();
            if (p.set_state (Gst.State.PLAYING) == Gst.StateChangeReturn.FAILURE) {
                p.set_state (Gst.State.NULL);
                throw new IOError.FAILED (_("The file could not be opened."));
            }
            var idle = new Timer ();
            while (true) {
                var sample = sink.try_pull_sample (100 * Gst.MSECOND);
                if (sample != null) {
                    var buf = sample.get_buffer ();
                    if (buf != null) {
                        Gst.MapInfo info;
                        if (buf.map (out info, Gst.MapFlags.READ)) {
                            bytes.append (info.data);
                            buf.unmap (info);
                        }
                    }
                    idle.start ();
                    continue;
                }
                if (sink.is_eos ()) break;
                var msg = bus.pop_filtered (Gst.MessageType.ERROR | Gst.MessageType.EOS);
                if (msg != null && msg.type == Gst.MessageType.EOS) break;
                if (msg != null && msg.type == Gst.MessageType.ERROR) {
                    Error err;
                    string debug;
                    msg.parse_error (out err, out debug);
                    p.set_state (Gst.State.NULL);
                    throw new IOError.FAILED (err.message);
                }
                if (no_more && !linked) {
                    p.set_state (Gst.State.NULL);
                    throw new IOError.INVALID_DATA (_("The file has no sound."));
                }
                if (idle.elapsed () > 30) {
                    p.set_state (Gst.State.NULL);
                    throw new IOError.TIMED_OUT (_("Reading the file took too long."));
                }
            }
            p.set_state (Gst.State.NULL);
            return bytes;
        }

        private void note_audio_problem (string text) {
            audio_drop_reason = audio_drop_reason == null ? text : audio_drop_reason + "\n" + text;
        }

        private void check_bus () throws Error {
            var msg = pipeline.get_bus ().pop_filtered (Gst.MessageType.ERROR);
            if (msg == null) return;
            Error err;
            string debug;
            msg.parse_error (out err, out debug);
            throw new IOError.FAILED (_("Could not write the video: %s").printf (err.message));
        }

        private void configure_video_encoder (Gst.Element enc) {
            uint bitrate = (uint) ((int64) width * height * fps / 4).clamp (500000, 50000000);
            string name = enc.get_factory ().get_name ();
            if (name == "x264enc") {
                set_arg (enc, "speed-preset", "faster");
                set_arg (enc, "pass", "qual");
                set_arg (enc, "quantizer", "20");
                set_arg (enc, "key-int-max", (fps * 2).to_string ());
            } else if (name == "openh264enc") {
                set_arg (enc, "bitrate", bitrate.to_string ());
                set_arg (enc, "max-bitrate", (bitrate * 2).to_string ());
                set_arg (enc, "gop-size", (fps * 2).to_string ());
                set_arg (enc, "complexity", "high");
                set_arg (enc, "rate-control", "bitrate");
                set_arg (enc, "qp-max", "30");
                set_arg (enc, "enable-frame-skip", "false");
            } else if (name == "vp9enc" || name == "vp8enc") {
                set_arg (enc, "deadline", "1");
                set_arg (enc, "cpu-used", name == "vp9enc" ? "6" : "4");
                set_arg (enc, "target-bitrate", bitrate.to_string ());
                set_arg (enc, "threads", int.max (1, (int) get_num_processors ()).to_string ());
                set_arg (enc, "row-mt", "true");
                set_arg (enc, "keyframe-max-dist", (fps * 2).to_string ());
            } else {
                set_arg (enc, "bitrate", (bitrate / 1000).to_string ());
            }
        }

        private static void set_arg (Gst.Element enc, string prop, string value) {
            if (enc.get_class ().find_property (prop) != null) Gst.Util.set_object_arg (enc, prop, value);
        }

        private static void ensure_init () {
            if (Gst.is_initialized ()) return;
            unowned string[]? args = null;
            Gst.init (ref args);
        }

        private static bool has (string name) {
            return Gst.ElementFactory.find (name) != null;
        }

        private static bool can_make (string name) {
            return Gst.ElementFactory.make (name, null) != null;
        }

        private static string? pick_video_encoder (Container c) {
            string[] names = c == Container.MP4 ? new string[] { "x264enc", "openh264enc", "avenc_h264" } : new string[] { "vp9enc", "vp8enc" };
            foreach (var n in names) if (can_make (n)) return n;
            if (c != Container.MP4) return null;
            var all = Gst.ElementFactory.list_get_elements (Gst.ElementFactoryType.VIDEO_ENCODER, Gst.Rank.MARGINAL);
            var h264 = Gst.ElementFactory.list_filter (all, Gst.Caps.from_string ("video/x-h264"), Gst.PadDirection.SRC, false);
            foreach (var f in h264) if (can_make (f.get_name ())) return f.get_name ();
            return null;
        }

        private static Gst.Element make (string name) throws Error {
            var e = Gst.ElementFactory.make (name, null);
            if (e == null) throw new IOError.NOT_SUPPORTED (_("The \"%s\" media component is missing.").printf (name));
            return e;
        }
    }
}
