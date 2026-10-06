namespace Singularity.Apps.Slides {

    public enum ShowFormat {
        MP4,
        WEBM,
        GIF;

        public string extension () {
            switch (this) {
                case WEBM: return "webm";
                case GIF: return "gif";
                default: return "mp4";
            }
        }
    }

    public class ShowExport : Object {
        public Presentation pres;
        public ShowFormat format = ShowFormat.MP4;
        public int width = 1280;
        public int fps = 30;
        public double seconds_per_slide = 5;
        public double seconds_per_click = 1;
        public bool use_timings = true;
        public bool include_audio = true;
        public bool include_hidden = false;
        public string audio_note = "";
        private Renderer renderer = new Renderer ();
        private int height;
        private double scale;
        private VideoEncoder? video = null;
        private GifEncoder? gif = null;
        private FileOutputStream? gif_stream = null;
        private int frames = 0;
        private Gee.ArrayList<string> temp_files = new Gee.ArrayList<string> ();

        public signal void progress (double fraction);

        public ShowExport (Presentation pres) {
            this.pres = pres;
        }

        private Gee.ArrayList<Slide> slides () {
            var list = new Gee.ArrayList<Slide> ();
            foreach (var s in pres.slides) if (include_hidden || !s.hidden) list.add (s);
            return list;
        }

        private double slide_hold (Slide s) {
            if (use_timings && s.transition.advance_after >= 0) return s.transition.advance_after;
            return seconds_per_slide;
        }

        public double slide_length (Slide s) {
            var p = new Player (pres, s);
            double anim = 0;
            for (int k = 0; k < p.step_count; k++) {
                bool auto = false;
                foreach (var ta in p.timed) if (ta.step == k && ta.anim.trigger != AnimTrigger.ON_CLICK) auto = true;
                anim += p.step_length (k) + (auto ? 0 : seconds_per_click);
            }
            double tr = s.transition.kind != TransitionKind.NONE ? s.transition.duration : 0;
            return tr + double.max (anim, 0) + slide_hold (s);
        }

        public double total_length () {
            double t = 0;
            foreach (var s in slides ()) t += slide_length (s);
            return t;
        }

        private Cairo.ImageSurface render_states (Slide s, Gee.HashMap<int, ElementState>? states) {
            var surf = new Cairo.ImageSurface (Cairo.Format.ARGB32, width, height);
            var cr = new Cairo.Context (surf);
            cr.set_source_rgb (0, 0, 0);
            cr.paint ();
            cr.scale (scale, scale);
            renderer.states = states;
            renderer.draw_slide (cr, pres, s);
            renderer.states = null;
            return surf;
        }

        private void emit (Cairo.ImageSurface frame, int count) throws Error {
            if (count <= 0) return;
            if (video != null) {
                for (int i = 0; i < count; i++) video.push_frame (frame);
            } else if (gif != null) {
                gif.add_frame (frame, int.max (1, (int) Math.round (count * 100.0 / fps)));
            }
            frames += count;
        }

        private async void pause () {
            Idle.add (pause.callback);
            yield;
        }

        private void collect_audio (Gee.ArrayList<Slide> list) {
            if (video == null || !include_audio) return;
            double t = 0;
            foreach (var s in list) {
                double start = t + (s.transition.kind != TransitionKind.NONE ? s.transition.duration : 0);
                foreach (var e in s.elements) {
                    var m = e as MediaElement;
                    if (m == null || m.is_video || m.data == null) continue;
                    if (m.start != MediaStart.AUTOMATIC) continue;
                    string path = Path.build_filename (Environment.get_tmp_dir (), "slides-audio-%s.%s".printf (Uuid.string_random (), m.extension ()));
                    try {
                        FileUtils.set_data (path, m.data.get_data ());
                        temp_files.add (path);
                        video.add_audio_file (path, start);
                    } catch (Error err) {
                        warning ("audio: %s", err.message);
                    }
                }
                t += slide_length (s);
            }
        }

        public async void run (string path, Cancellable? cancel = null) throws Error {
            var list = slides ();
            if (list.size == 0) throw new FileError.INVAL (_("There are no slides to export."));
            width = (width / 2) * 2;
            height = ((int) Math.round (width * pres.height / pres.width) / 2) * 2;
            scale = width / pres.width;
            frames = 0;
            if (format == ShowFormat.GIF) {
                var file = File.new_for_path (path);
                gif_stream = file.replace (null, false, FileCreateFlags.REPLACE_DESTINATION);
                gif = new GifEncoder (gif_stream, width, height, 0);
            } else {
                var container = format == ShowFormat.WEBM ? VideoEncoder.Container.WEBM : VideoEncoder.Container.MP4;
                if (!VideoEncoder.available (container)) throw new IOError.NOT_SUPPORTED (_("No video encoder for this format is installed."));
                video = new VideoEncoder (path, width, height, fps, container);
                collect_audio (list);
            }
            double total = total_length ();
            double done = 0;
            Cairo.ImageSurface? prev = null;
            Slide? prev_slide = null;
            int gfps = format == ShowFormat.GIF ? int.min (fps, 15) : fps;
            if (format == ShowFormat.GIF) fps = gfps;
            try {
                foreach (var s in list) {
                    var player = new Player (pres, s);
                    var start_states = player.initial_states ();
                    if (s.transition.kind != TransitionKind.NONE && prev != null) {
                        var to = render_states (s, start_states);
                        int n = int.max (1, (int) Math.round (s.transition.duration * fps));
                        for (int i = 0; i < n; i++) {
                            var frame = new Cairo.ImageSurface (Cairo.Format.ARGB32, width, height);
                            var cr = new Cairo.Context (frame);
                            double t = (i + 0.5) / n;
                            if (s.transition.kind == TransitionKind.MORPH && prev_slide != null) {
                                cr.set_source_rgb (0, 0, 0);
                                cr.paint ();
                                cr.scale (scale, scale);
                                Morph.draw (cr, pres, prev_slide, s, t);
                            } else {
                                Transitions.draw_full (cr, s.transition, t, prev, to, width, height);
                            }
                            emit (frame, 1);
                            if (cancel != null && cancel.is_cancelled ()) throw new IOError.CANCELLED (_("Export cancelled"));
                            yield pause ();
                        }
                        done += s.transition.duration;
                        progress (done / total);
                    }
                    int step = -1;
                    if (player.auto_first) step = 0;
                    var cur = render_states (s, step < 0 ? start_states : player.states_at (step, 0));
                    for (int k = 0; k < player.step_count; k++) {
                        bool auto = false;
                        foreach (var ta in player.timed) if (ta.step == k && ta.anim.trigger != AnimTrigger.ON_CLICK) auto = true;
                        if (!auto) {
                            emit (cur, (int) Math.round (seconds_per_click * fps));
                            done += seconds_per_click;
                        }
                        double len = player.step_length (k);
                        int n = (int) Math.round (len * fps);
                        for (int i = 0; i < n; i++) {
                            cur = render_states (s, player.states_at (k, (i + 1.0) / fps));
                            emit (cur, 1);
                            if (cancel != null && cancel.is_cancelled ()) throw new IOError.CANCELLED (_("Export cancelled"));
                            if (i % 2 == 0) yield pause ();
                        }
                        cur = render_states (s, player.states_at (k, len + 1));
                        done += len;
                        progress (done / total);
                    }
                    int hold_frames = (int) Math.round (slide_hold (s) * fps);
                    emit (cur, hold_frames);
                    done += slide_hold (s);
                    progress (done / total);
                    prev = cur;
                    prev_slide = s;
                    yield pause ();
                }
                if (video != null) {
                    video.finish ();
                    if (video.audio_dropped && video.audio_drop_reason != null) audio_note = video.audio_drop_reason;
                }
                if (gif != null) {
                    gif.finish ();
                    gif_stream.close ();
                }
            } finally {
                foreach (string f in temp_files) FileUtils.remove (f);
                temp_files.clear ();
            }
            progress (1);
        }
    }
}
