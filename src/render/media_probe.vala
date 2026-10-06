namespace Singularity.Apps.Slides {

    public class MediaProbe {
        private static void ensure_gst () {
            if (!Gst.is_initialized ()) {
                unowned string[]? args = null;
                Gst.init (ref args);
            }
        }

        public static string temp_file (MediaElement m) throws Error {
            string dir = Path.build_filename (Environment.get_user_cache_dir (), "singularity-slides", "media");
            DirUtils.create_with_parents (dir, 0700);
            string path = Path.build_filename (dir, "%s.%s".printf (Checksum.compute_for_bytes (ChecksumType.SHA1, m.data), m.extension ()));
            if (!FileUtils.test (path, FileTest.EXISTS)) FileUtils.set_data (path, m.data.get_data ());
            return path;
        }

        public static bool probe (string path, double at, int max_width, out double duration, out Bytes? poster) {
            ensure_gst ();
            duration = 0;
            poster = null;
            string uri;
            try {
                uri = Filename.to_uri (path);
            } catch (Error e) {
                return false;
            }
            var pipeline = Gst.ElementFactory.make ("playbin", null);
            if (pipeline == null) return false;
            Gst.App.Sink? sink = null;
            try {
                var vbin = Gst.parse_bin_from_description ("videoconvert ! videoscale ! appsink name=sink sync=false max-buffers=1 drop=true caps=video/x-raw,format=BGRA,pixel-aspect-ratio=1/1", true);
                sink = ((Gst.Bin) vbin).get_by_name ("sink") as Gst.App.Sink;
                pipeline.set ("video-sink", vbin);
            } catch (Error e) {
                sink = null;
            }
            var fake = Gst.ElementFactory.make ("fakesink", null);
            if (fake != null) pipeline.set ("audio-sink", fake);
            pipeline.set ("uri", uri);
            pipeline.set_state (Gst.State.PAUSED);
            Gst.State state, pending;
            var ret = pipeline.get_state (out state, out pending, 5 * Gst.SECOND);
            if (ret == Gst.StateChangeReturn.FAILURE) {
                pipeline.set_state (Gst.State.NULL);
                return false;
            }
            int64 dur = 0;
            if (pipeline.query_duration (Gst.Format.TIME, out dur) && dur > 0) duration = dur / (double) Gst.SECOND;
            if (sink != null) {
                double t = duration > 0 ? double.min (at, duration / 3) : 0;
                if (t > 0) {
                    pipeline.seek_simple (Gst.Format.TIME, Gst.SeekFlags.FLUSH | Gst.SeekFlags.KEY_UNIT, (int64) (t * Gst.SECOND));
                    pipeline.get_state (out state, out pending, 5 * Gst.SECOND);
                }
                var sample = sink.try_pull_preroll (2 * Gst.SECOND);
                if (sample != null) poster = sample_png (sample, max_width);
            }
            pipeline.set_state (Gst.State.NULL);
            return true;
        }

        private static Bytes? sample_png (Gst.Sample sample, int max_width) {
            var caps = sample.get_caps ();
            if (caps == null) return null;
            unowned Gst.Structure st = caps.get_structure (0);
            int w = 0, h = 0;
            st.get_int ("width", out w);
            st.get_int ("height", out h);
            if (w <= 0 || h <= 0) return null;
            var buffer = sample.get_buffer ();
            Gst.MapInfo map;
            if (!buffer.map (out map, Gst.MapFlags.READ)) return null;
            int stride = (int) (map.size / h);
            var surf = new Cairo.ImageSurface (Cairo.Format.ARGB32, w, h);
            surf.flush ();
            unowned uint8[] dst = surf.get_data ();
            int dstride = surf.get_stride ();
            for (int y = 0; y < h; y++) {
                Memory.copy (&dst[y * dstride], &map.data[y * stride], int.min (stride, dstride));
                for (int x = 0; x < w; x++) dst[y * dstride + x * 4 + 3] = 255;
            }
            surf.mark_dirty ();
            buffer.unmap (map);
            Cairo.ImageSurface outp = surf;
            if (w > max_width) {
                int nh = (int) Math.round ((double) h * max_width / w);
                outp = new Cairo.ImageSurface (Cairo.Format.ARGB32, max_width, int.max (nh, 1));
                var cr = new Cairo.Context (outp);
                cr.scale ((double) max_width / w, (double) max_width / w);
                cr.set_source_surface (surf, 0, 0);
                cr.paint ();
            }
            var bytes = new ByteArray ();
            outp.write_to_png_stream ((d) => {
                bytes.append (d);
                return Cairo.Status.SUCCESS;
            });
            return ByteArray.free_to_bytes ((owned) bytes);
        }

        public static async void fill (MediaElement m) {
            if (m.data == null && m.link == "") return;
            string path;
            try {
                path = m.data != null ? temp_file (m) : m.link;
            } catch (Error e) {
                return;
            }
            double duration = 0;
            Bytes? poster = null;
            bool video = m.is_video;
            new Thread<bool> ("slides-media-probe", () => {
                probe (path, 1.0, 1280, out duration, out poster);
                Idle.add (fill.callback);
                return true;
            });
            yield;
            if (duration > 0) m.length = duration;
            if (video && poster != null && m.poster == null) {
                m.poster = poster;
                m.poster_mime = "image/png";
                int pw, ph;
                if (ImageCache.size_of (poster, out pw, out ph) && pw > 0) m.h = m.w * ph / pw;
            }
        }
    }
}
