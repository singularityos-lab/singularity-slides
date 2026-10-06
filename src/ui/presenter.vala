using Gtk;
using Singularity.Widgets;

namespace Singularity.Apps.Slides {

    public enum BlankMode {
        NONE,
        BLACK,
        WHITE
    }

    public enum PointerTool {
        ARROW,
        LASER,
        PEN,
        HIGHLIGHTER,
        ERASER
    }

    public class MediaHost : Object {
        private class Entry {
            public MediaElement media;
            public MediaPlayback player;
            public bool started = false;
            public string path = "";
        }

        private Gee.HashMap<int, Entry> entries = new Gee.HashMap<int, Entry> ();
        private string dir;
        public signal void changed ();

        public MediaHost () {
            dir = Path.build_filename (Environment.get_user_cache_dir (), "singularity-slides", "media");
            DirUtils.create_with_parents (dir, 0700);
        }

        private string file_for (MediaElement m) {
            if (m.data == null) return m.link;
            string name = "%s.%s".printf (Checksum.compute_for_bytes (ChecksumType.SHA1, m.data), m.extension ());
            string path = Path.build_filename (dir, name);
            if (!FileUtils.test (path, FileTest.EXISTS)) {
                try {
                    FileUtils.set_data (path, m.data.get_data ());
                } catch (Error e) {
                    warning ("media: %s", e.message);
                }
            }
            return path;
        }

        public void load (Slide s) {
            clear ();
            var all = new Gee.ArrayList<Element> ();
            foreach (var e in s.elements) flatten (e, all);
            foreach (var e in all) {
                var m = e as MediaElement;
                if (m == null) continue;
                var en = new Entry ();
                en.media = m;
                en.player = new MediaPlayback ();
                if (!en.player.available) continue;
                en.path = file_for (m);
                string uri = en.path.contains ("://") ? en.path : File.new_for_path (en.path).get_uri ();
                en.player.volume = m.volume;
                en.player.muted = m.muted;
                en.player.loop = m.loop;
                en.player.video.invalidate_contents.connect (() => changed ());
                en.player.finished.connect (() => {
                    en.started = false;
                    if (m.rewind) en.player.seek ((int64) (m.trim_start * Gst.SECOND));
                    changed ();
                });
                en.player.open (uri, false);
                entries[m.id] = en;
            }
        }

        private static void flatten (Element e, Gee.List<Element> list) {
            list.add (e);
            var g = e as GroupElement;
            if (g != null) foreach (var c in g.children) flatten (c, list);
        }

        public void clear () {
            foreach (var en in entries.values) en.player.stop ();
            entries.clear ();
            stop_sounds ();
        }

        public void play (int id) {
            if (!entries.has_key (id)) return;
            var en = entries[id];
            if (!en.started) en.player.seek ((int64) (en.media.trim_start * Gst.SECOND));
            en.started = true;
            en.player.play ();
            changed ();
        }

        public void toggle (int id) {
            if (!entries.has_key (id)) return;
            var en = entries[id];
            if (!en.started) {
                play (id);
                return;
            }
            en.player.toggle ();
            changed ();
        }

        public void stop (int id) {
            if (!entries.has_key (id)) return;
            var en = entries[id];
            en.player.pause ();
            en.player.seek ((int64) (en.media.trim_start * Gst.SECOND));
            en.started = false;
            changed ();
        }

        private Gee.ArrayList<MediaPlayback> sounds = new Gee.ArrayList<MediaPlayback> ();

        public void sound (Bytes data, bool loop = false) {
            var sp = new MediaPlayback ();
            if (!sp.available) return;
            string ext = MediaElement.sniff_extension (data);
            string path = Path.build_filename (dir, "%s.%s".printf (Checksum.compute_for_bytes (ChecksumType.SHA1, data), ext));
            if (!FileUtils.test (path, FileTest.EXISTS)) {
                try {
                    FileUtils.set_data (path, data.get_data ());
                } catch (Error e) {
                    warning ("sound: %s", e.message);
                    return;
                }
            }
            sp.loop = loop;
            sp.finished.connect (() => sounds.remove (sp));
            sp.open (File.new_for_path (path).get_uri (), true);
            sounds.add (sp);
        }

        public void stop_sounds () {
            foreach (var sp in sounds) sp.stop ();
            sounds.clear ();
        }

        public bool has (int id) {
            return entries.has_key (id);
        }

        public bool playing (int id) {
            return entries.has_key (id) && entries[id].player.playing;
        }

        public bool started (int id) {
            return entries.has_key (id) && entries[id].started;
        }

        public Gdk.Paintable? frame (int id) {
            if (!entries.has_key (id)) return null;
            var en = entries[id];
            if (!en.started || !en.player.video.has_frame) return null;
            return en.player.video;
        }

        public void tick () {
            foreach (var en in entries.values) {
                if (!en.player.playing) continue;
                var m = en.media;
                double pos = en.player.position / (double) Gst.SECOND;
                double dur = en.player.duration > 0 ? en.player.duration / (double) Gst.SECOND : m.length;
                if (dur > 0 && m.length <= 0) m.length = dur;
                double end = dur - m.trim_end;
                if (m.trim_end > 0 && pos >= end) {
                    if (m.loop) en.player.seek ((int64) (m.trim_start * Gst.SECOND));
                    else {
                        en.player.pause ();
                        en.started = !m.rewind;
                        if (m.rewind) en.player.seek ((int64) (m.trim_start * Gst.SECOND));
                    }
                    changed ();
                    continue;
                }
                double vol = m.volume;
                if (m.fade_in > 0 && pos - m.trim_start < m.fade_in) vol *= ((pos - m.trim_start) / m.fade_in).clamp (0, 1);
                if (m.fade_out > 0 && end - pos < m.fade_out) vol *= ((end - pos) / m.fade_out).clamp (0, 1);
                en.player.volume = vol;
            }
        }
    }

    public class SlideShow : Object {
        public Presentation pres;
        public Gee.ArrayList<int> order = new Gee.ArrayList<int> ();
        public int position = 0;
        public int step = -1;
        public double step_time = 0;
        public Player? player = null;
        public bool in_transition = false;
        public double transition_time = 0;
        public int transition_from = -1;
        public int transition_serial = 0;
        public Transition? override_transition = null;
        public bool ended = false;
        public BlankMode blank = BlankMode.NONE;
        public PointerTool tool = PointerTool.ARROW;
        public double laser_x = -1;
        public double laser_y = -1;
        public Gee.HashMap<int, Gee.ArrayList<InkStroke>> ink = new Gee.HashMap<int, Gee.ArrayList<InkStroke>> ();
        public Rgba laser_color = Rgba (1, 0.23, 0.19, 1);
        public Rgba pen_color = Rgba (1, 0.8, 0, 1);
        public bool rehearse = false;
        public Gee.HashMap<int, double?> rehearsed = new Gee.HashMap<int, double?> ();
        public Timer total = new Timer ();
        public Timer on_slide = new Timer ();
        public bool paused = false;
        public bool autoplay = false;
        public MediaHost media = new MediaHost ();
        public Gee.ArrayList<int> history = new Gee.ArrayList<int> ();
        public Gee.ArrayList<int> return_stack = new Gee.ArrayList<int> ();
        public int return_after = -1;
        public string caption = "";
        public bool show_captions = false;
        public string caption_command = "";
        private Subprocess? caption_proc = null;
        private Cancellable? caption_cancel = null;

        public void toggle_captions () {
            show_captions = !show_captions;
            if (show_captions) start_captions ();
            else stop_captions ();
            changed ();
        }

        private void start_captions () {
            if (caption_proc != null) return;
            if (caption_command.strip () == "") {
                if (SpeechService.present () && AudioRecorder.available ()) {
                    caption = _("Listening");
                    caption_cancel = new Cancellable ();
                    caption_chunk ();
                    return;
                }
                caption = _("Live captions need speech recognition: turn on dictation in Settings");
                return;
            }
            try {
                string[] argv;
                GLib.Shell.parse_argv (caption_command, out argv);
                caption_proc = new Subprocess.newv (argv, SubprocessFlags.STDOUT_PIPE | SubprocessFlags.STDERR_SILENCE);
                caption_cancel = new Cancellable ();
                caption = _("Listening");
                read_captions.begin (new DataInputStream (caption_proc.get_stdout_pipe ()));
            } catch (Error e) {
                caption = _("Live captions could not start: %s").printf (e.message);
                caption_proc = null;
            }
        }

        private async void read_captions (DataInputStream input) {
            try {
                string? line;
                while ((line = yield input.read_line_utf8_async (Priority.DEFAULT, caption_cancel)) != null) {
                    string t = line.strip ();
                    if (t == "") continue;
                    caption = t.length > 200 ? t.substring (t.length - 200) : t;
                    changed ();
                }
            } catch (Error e) {
            }
        }

        private AudioRecorder? caption_rec = null;
        private uint caption_timer = 0;

        private void caption_chunk () {
            if (caption_cancel == null || caption_cancel.is_cancelled ()) return;
            caption_rec = new AudioRecorder ();
            caption_rec.speech_wav = true;
            if (!caption_rec.start ()) {
                caption = _("Live captions could not start: %s").printf (caption_rec.error_message);
                caption_rec = null;
                changed ();
                return;
            }
            caption_timer = Timeout.add (3500, () => {
                caption_timer = 0;
                if (caption_rec == null) return Source.REMOVE;
                var clip = caption_rec.stop ();
                caption_rec = null;
                var cancel = caption_cancel;
                caption_chunk ();
                if (clip != null && cancel != null) {
                    SpeechService.transcribe.begin (clip, cancel, (o, r) => {
                        try {
                            string t = SpeechService.transcribe.end (r);
                            if (t != "" && show_captions) {
                                caption = t.length > 200 ? t.substring (t.length - 200) : t;
                                changed ();
                            }
                        } catch (Error e) {
                        }
                    });
                }
                return Source.REMOVE;
            });
        }

        private void stop_captions () {
            if (caption_timer != 0) {
                Source.remove (caption_timer);
                caption_timer = 0;
            }
            if (caption_rec != null) {
                caption_rec.cancel ();
                caption_rec = null;
            }
            if (caption_cancel != null) caption_cancel.cancel ();
            if (caption_proc != null) caption_proc.force_exit ();
            caption_proc = null;
            caption_cancel = null;
            caption = "";
        }
        public bool preview_mode = false;
        private double idle_time = 0;
        private uint tick_id = 0;
        private int64 last_tick = 0;
        private string jump = "";
        private double prev_step_time = 0;

        public signal void changed ();
        public signal void slide_changed ();
        public signal void finished ();
        public signal void open_link (string uri);
        public signal void run_program (string path);

        public SlideShow (Presentation pres, int start, bool include_hidden_start, string custom_show = "") {
            this.pres = pres;
            build_order (start, include_hidden_start, custom_show);
            position = int.max (0, order.index_of (start));
            media.changed.connect (() => changed ());
            enter_slide (-1);
            tick_id = Timeout.add (16, tick);
        }

        public SlideShow.preview (Presentation pres, int index, bool transition, int from_animation) {
            this.pres = pres;
            preview_mode = true;
            order.add (index);
            position = 0;
            autoplay = true;
            player = new Player (pres, current);
            media.changed.connect (() => changed ());
            on_slide.start ();
            if (transition && current.transition.kind != TransitionKind.NONE) {
                in_transition = true;
                transition_time = 0;
                transition_from = index > 0 ? index - 1 : index;
                transition_serial++;
                step = -1;
            } else {
                step = -1;
                if (from_animation > 0) {
                    int k = 0;
                    foreach (var ta in player.timed) {
                        if (k++ == from_animation) {
                            step = ta.step - 1;
                            break;
                        }
                    }
                }
                step_time = 0;
            }
            tick_id = Timeout.add (16, tick);
        }

        private void build_order (int start, bool include_hidden_start, string custom_show) {
            order.clear ();
            string cs_name = custom_show != "" ? custom_show : pres.show_custom;
            var cs = cs_name != "" ? pres.find_custom_show (cs_name) : null;
            if (cs != null) {
                foreach (int uid in cs.slides) {
                    int i = pres.index_of_uid (uid);
                    if (i >= 0) order.add (i);
                }
            } else {
                int from = 0, to = pres.slides.size - 1;
                if (pres.show_from > 0 && pres.show_to >= pres.show_from && custom_show == "") {
                    from = (pres.show_from - 1).clamp (0, pres.slides.size - 1);
                    to = (pres.show_to - 1).clamp (from, pres.slides.size - 1);
                }
                for (int i = from; i <= to; i++) {
                    if (!pres.slides[i].hidden || (include_hidden_start && i == start)) order.add (i);
                }
            }
            if (order.size == 0) for (int i = 0; i < pres.slides.size; i++) order.add (i);
        }

        public void stop () {
            stop_captions ();
            if (tick_id != 0) {
                Source.remove (tick_id);
                tick_id = 0;
            }
            media.clear ();
        }

        public int slide_index {
            get { return order.size > 0 ? order[position.clamp (0, order.size - 1)] : 0; }
        }

        public Slide current {
            owned get { return pres.slides[slide_index]; }
        }

        public Slide? next_slide {
            owned get { return position + 1 < order.size ? pres.slides[order[position + 1]] : (pres.loop && order.size > 0 ? pres.slides[order[0]] : null); }
        }

        public Transition active_transition {
            owned get { return override_transition ?? current.transition; }
        }

        private void enter_slide (int from, Transition? forced = null) {
            player = new Player (pres, current);
            step = -1;
            step_time = 0;
            prev_step_time = 0;
            on_slide.start ();
            override_transition = forced;
            if (!preview_mode) media.load (current);
            var tr = active_transition;
            if (!preview_mode && tr.sound_data != null) media.sound (tr.sound_data, tr.sound_loop);
            if (from >= 0 && tr.kind != TransitionKind.NONE && pres.show_animation) {
                in_transition = true;
                transition_time = 0;
                transition_from = from;
                transition_serial++;
            } else {
                in_transition = false;
                start_auto ();
            }
            if (history.size == 0 || history[history.size - 1] != slide_index) history.add (slide_index);
            slide_changed ();
            changed ();
        }

        private void start_auto () {
            if (player.auto_first && step < 0) {
                step = 0;
                step_time = 0;
                prev_step_time = -1;
            }
        }

        public bool animating () {
            if (in_transition) return true;
            if (player == null || step < 0 || step >= player.step_count) return false;
            return step_time < player.step_length (step);
        }

        private void fire_media (double from_t, double to_t) {
            if (player == null || step < 0) return;
            foreach (var ta in player.timed) {
                if (ta.step != step || ta.anim.sound_data == null) continue;
                bool due = from_t < 0 ? ta.start <= to_t : ta.start > from_t && ta.start <= to_t;
                if (due) media.sound (ta.anim.sound_data);
            }
            foreach (var ta in player.media_events (step)) {
                if (ta.start < from_t || ta.start > to_t) {
                    if (!(from_t < 0 && ta.start <= to_t && ta.start >= 0)) continue;
                }
                if (ta.start >= 0 && from_t >= 0 && ta.start <= from_t) continue;
                switch (ta.anim.effect) {
                    case AnimEffect.MEDIA_PAUSE: media.toggle (ta.anim.target); break;
                    case AnimEffect.MEDIA_STOP: media.stop (ta.anim.target); break;
                    default: media.play (ta.anim.target); break;
                }
            }
        }

        private bool tick () {
            int64 now = get_monotonic_time ();
            double dt = last_tick > 0 ? (now - last_tick) / 1000000.0 : 0;
            last_tick = now;
            bool redraw = false;
            media.tick ();
            if (in_transition) {
                transition_time += dt;
                double dur = double.max (active_transition.duration, 0.05);
                if (transition_time >= dur) {
                    in_transition = false;
                    override_transition = null;
                    start_auto ();
                }
                redraw = true;
            } else if (animating ()) {
                double before = prev_step_time;
                step_time += dt;
                fire_media (before, step_time);
                prev_step_time = step_time;
                redraw = true;
            } else if (player != null && step >= 0 && step + 1 < player.step_count && !ended) {
                var next_a = first_of_step (step + 1);
                if (next_a != null && next_a.trigger != AnimTrigger.ON_CLICK) {
                    advance_step ();
                    redraw = true;
                }
            }
            if (player != null && step >= 0 && prev_step_time < 0) {
                fire_media (-1, step_time);
                prev_step_time = step_time;
            }
            if (player != null && player.trigger_elapsed.size > 0) {
                foreach (var k in player.trigger_elapsed.keys) {
                    double el = player.trigger_elapsed[k];
                    if (el <= player.trigger_length (k) + 0.1) {
                        player.trigger_elapsed[k] = el + dt;
                        redraw = true;
                    }
                }
            }
            if (!ended && !paused && !rehearse && pres.use_timings && !animating () && !preview_mode) {
                double adv = current.transition.advance_after;
                if (adv >= 0 && on_slide.elapsed () >= adv) next ();
            }
            if (autoplay && !in_transition && !animating ()) {
                if (player != null && step + 1 < player.step_count) {
                    advance_step ();
                    idle_time = 0;
                    redraw = true;
                } else {
                    idle_time += dt;
                    if (idle_time > 0.6) {
                        autoplay = false;
                        finished ();
                    }
                }
            }
            if (tool == PointerTool.LASER) redraw = true;
            if (redraw) changed ();
            return Source.CONTINUE;
        }

        private void advance_step () {
            step++;
            step_time = 0;
            prev_step_time = -1;
        }

        private Animation? first_of_step (int s) {
            if (player == null) return null;
            foreach (var ta in player.timed) if (ta.step == s) return ta.anim;
            return null;
        }

        public void next () {
            if (blank != BlankMode.NONE) {
                blank = BlankMode.NONE;
                changed ();
                return;
            }
            if (ended) {
                finished ();
                return;
            }
            if (in_transition) {
                in_transition = false;
                transition_time = 0;
                override_transition = null;
                start_auto ();
                changed ();
                return;
            }
            if (animating ()) {
                double before = step_time;
                step_time = player.step_length (step);
                fire_media (before, step_time);
                prev_step_time = step_time;
                changed ();
                return;
            }
            if (player != null && step + 1 < player.step_count) {
                advance_step ();
                changed ();
                return;
            }
            record_rehearsal ();
            if (return_after >= 0 && slide_index == return_after && return_stack.size > 0) {
                int back = return_stack.remove_at (return_stack.size - 1);
                return_after = -1;
                int from = slide_index;
                position = back;
                enter_slide (from, zoom_transition ());
                return;
            }
            if (position + 1 < order.size) {
                int from = slide_index;
                position++;
                enter_slide (from);
            } else if (pres.loop && !rehearse) {
                int from = slide_index;
                position = 0;
                enter_slide (from);
            } else {
                ended = true;
                changed ();
            }
        }

        private Transition zoom_transition () {
            var t = new Transition ();
            t.kind = TransitionKind.ZOOM;
            t.duration = 0.8;
            return t;
        }

        public void previous () {
            if (ended) {
                ended = false;
                changed ();
                return;
            }
            if (player != null && step >= 0 && !(step == 0 && player.auto_first)) {
                step--;
                step_time = step >= 0 ? player.step_length (step) : 0;
                prev_step_time = step_time;
                changed ();
                return;
            }
            if (position > 0) {
                position--;
                player = new Player (pres, current);
                step = player.step_count - 1;
                step_time = step >= 0 ? player.step_length (step) : 0;
                prev_step_time = step_time;
                in_transition = false;
                on_slide.start ();
                if (!preview_mode) media.load (current);
                slide_changed ();
                changed ();
            }
        }

        public void go_to (int pos) {
            if (pos < 0 || pos >= order.size) return;
            record_rehearsal ();
            ended = false;
            int from = slide_index;
            position = pos;
            enter_slide (from == slide_index ? -1 : from);
        }

        public void go_to_slide_index (int index, Transition? forced = null) {
            int pos = order.index_of (index);
            if (pos < 0) {
                order.insert (position + 1, index);
                pos = position + 1;
            }
            record_rehearsal ();
            ended = false;
            int from = slide_index;
            position = pos;
            enter_slide (from, forced);
        }

        public void run_action (ClickAction a) {
            switch (a.kind) {
                case ActionKind.NEXT_SLIDE:
                    if (position + 1 < order.size) go_to (position + 1);
                    break;
                case ActionKind.PREVIOUS_SLIDE:
                    if (position > 0) go_to (position - 1);
                    break;
                case ActionKind.FIRST_SLIDE:
                    go_to (0);
                    break;
                case ActionKind.LAST_SLIDE:
                    go_to (order.size - 1);
                    break;
                case ActionKind.LAST_VIEWED:
                    if (history.size >= 2) go_to_slide_index (history[history.size - 2]);
                    break;
                case ActionKind.END_SHOW:
                    finished ();
                    break;
                case ActionKind.SLIDE:
                    int i = pres.index_of_uid (a.slide_uid);
                    if (i >= 0) go_to_slide_index (i);
                    break;
                case ActionKind.URL:
                case ActionKind.FILE:
                    if (a.target != "") open_link (a.target);
                    break;
                case ActionKind.PROGRAM:
                    if (a.target != "") run_program (a.target);
                    break;
                case ActionKind.CUSTOM_SHOW:
                    var cs = pres.find_custom_show (a.target);
                    if (cs == null || cs.slides.size == 0) break;
                    int back = position;
                    var sub = new Gee.ArrayList<int> ();
                    foreach (int uid in cs.slides) {
                        int idx = pres.index_of_uid (uid);
                        if (idx >= 0) sub.add (idx);
                    }
                    if (sub.size == 0) break;
                    for (int k = 0; k < sub.size; k++) order.insert (position + 1 + k, sub[k]);
                    if (a.show_and_return) {
                        return_stack.add (back);
                        return_after = sub[sub.size - 1];
                    }
                    go_to (position + 1);
                    break;
                default:
                    break;
            }
        }

        public void open_zoom (ZoomElement z) {
            var target = z.target (pres);
            if (target == null) return;
            int idx = pres.slides.index_of (target);
            int back = position;
            if (z.return_to_zoom) {
                return_stack.add (back);
                if (z.zoom == ZoomKind.SLIDE) {
                    return_after = idx;
                } else {
                    int end = pres.section_end (idx) - 1;
                    return_after = end;
                    int k = position + 1;
                    for (int i = idx; i <= end; i++) {
                        if (pres.slides[i].hidden) continue;
                        if (order.index_of (i) > position) continue;
                        order.insert (k++, i);
                    }
                }
            }
            go_to_slide_index (idx, z.zoom_transition ? zoom_transition () : null);
        }

        public bool trigger (int shape) {
            if (player == null) return false;
            var keys = player.trigger_keys_for (shape);
            if (keys.size == 0) return false;
            foreach (var k in keys) {
                player.trigger_elapsed[k] = 0;
                foreach (var ta in player.triggers[k]) {
                    if (ta.anim.anim_class != AnimClass.MEDIA) continue;
                    switch (ta.anim.effect) {
                        case AnimEffect.MEDIA_PAUSE: media.toggle (ta.anim.target); break;
                        case AnimEffect.MEDIA_STOP: media.stop (ta.anim.target); break;
                        default: media.play (ta.anim.target); break;
                    }
                }
            }
            changed ();
            return true;
        }

        private void record_rehearsal () {
            if (!rehearse) return;
            double prev = rehearsed.has_key (slide_index) ? rehearsed[slide_index] : 0;
            rehearsed[slide_index] = prev + on_slide.elapsed ();
            on_slide.start ();
        }

        public void finish_rehearsal () {
            record_rehearsal ();
        }

        public Gee.HashMap<int, ElementState> states () {
            if (player == null || !pres.show_animation) return new Gee.HashMap<int, ElementState> ();
            if (step < 0) return player.initial_states ();
            return player.states_at (step, step_time);
        }

        public void toggle_blank (BlankMode m) {
            blank = blank == m ? BlankMode.NONE : m;
            changed ();
        }

        public void set_tool (PointerTool t) {
            tool = tool == t ? PointerTool.ARROW : t;
            if (tool != PointerTool.LASER) laser_x = -1;
            changed ();
        }

        public Gee.ArrayList<InkStroke> strokes () {
            if (!ink.has_key (slide_index)) ink[slide_index] = new Gee.ArrayList<InkStroke> ();
            return ink[slide_index];
        }

        public bool has_ink () {
            foreach (var list in ink.values) if (list.size > 0) return true;
            return false;
        }

        public void erase () {
            ink.unset (slide_index);
            changed ();
        }

        public void erase_at (double x, double y, double radius) {
            var list = strokes ();
            for (int i = list.size - 1; i >= 0; i--) {
                var s = list[i];
                for (int k = 0; k + 1 < s.pts.size; k += 2) {
                    if (Math.hypot (s.pts[k] - x, s.pts[k + 1] - y) <= radius + s.width / 2) {
                        list.remove_at (i);
                        changed ();
                        break;
                    }
                }
            }
        }

        public bool handle_key (uint keyval, Gdk.ModifierType state) {
            bool ctrl = (state & Gdk.ModifierType.CONTROL_MASK) != 0;
            if (ctrl) {
                switch (keyval) {
                    case Gdk.Key.l: set_tool (PointerTool.LASER); return true;
                    case Gdk.Key.p: set_tool (PointerTool.PEN); return true;
                    case Gdk.Key.i: set_tool (PointerTool.HIGHLIGHTER); return true;
                    case Gdk.Key.e: set_tool (PointerTool.ERASER); return true;
                    case Gdk.Key.a: tool = PointerTool.ARROW; changed (); return true;
                    default: return false;
                }
            }
            if (keyval >= Gdk.Key.@0 && keyval <= Gdk.Key.@9) {
                jump += ((char) ('0' + (keyval - Gdk.Key.@0))).to_string ();
                return true;
            }
            switch (keyval) {
                case Gdk.Key.Right:
                case Gdk.Key.Down:
                case Gdk.Key.space:
                case Gdk.Key.Page_Down:
                case Gdk.Key.n:
                    next ();
                    return true;
                case Gdk.Key.Return:
                case Gdk.Key.KP_Enter:
                    if (jump != "") {
                        int n = int.parse (jump);
                        jump = "";
                        if (n >= 1 && n <= pres.slides.size) go_to_slide_index (n - 1);
                        return true;
                    }
                    next ();
                    return true;
                case Gdk.Key.Left:
                case Gdk.Key.Up:
                case Gdk.Key.Page_Up:
                case Gdk.Key.BackSpace:
                case Gdk.Key.p:
                    previous ();
                    return true;
                case Gdk.Key.Home:
                    go_to (0);
                    return true;
                case Gdk.Key.End:
                    go_to (order.size - 1);
                    return true;
                case Gdk.Key.h:
                    for (int i = slide_index + 1; i < pres.slides.size; i++) {
                        if (pres.slides[i].hidden) {
                            go_to_slide_index (i);
                            return true;
                        }
                    }
                    next ();
                    return true;
                case Gdk.Key.b:
                case Gdk.Key.period:
                    toggle_blank (BlankMode.BLACK);
                    return true;
                case Gdk.Key.w:
                case Gdk.Key.comma:
                    toggle_blank (BlankMode.WHITE);
                    return true;
                case Gdk.Key.e:
                    erase ();
                    return true;
                case Gdk.Key.j:
                    toggle_captions ();
                    return true;
                case Gdk.Key.Escape:
                    if (tool != PointerTool.ARROW) {
                        tool = PointerTool.ARROW;
                        changed ();
                        return true;
                    }
                    finished ();
                    return true;
                default:
                    return false;
            }
        }
    }

    public class ShowStage : Widget {
        public SlideShow slideshow;
        public bool interactive = true;
        public bool mirror = false;
        private Renderer renderer = new Renderer ();
        private Cairo.ImageSurface? from_surf = null;
        private Cairo.ImageSurface? to_surf = null;
        private int cached_serial = -1;
        private int cached_w = 0;
        private int cached_h = 0;
        private InkStroke? drawing = null;
        private double ox;
        private double oy;
        private double sc = 1;
        private Element? hover_el = null;
        private TextRun? hover_run = null;

        public signal void clicked_next ();

        public ShowStage (SlideShow slideshow) {
            this.slideshow = slideshow;
            hexpand = true;
            vexpand = true;
            focusable = true;
            slideshow.changed.connect (queue_draw);
            var click = new GestureClick ();
            click.button = 0;
            click.released.connect ((n, x, y) => {
                if (!interactive) return;
                if (slideshow.tool == PointerTool.PEN || slideshow.tool == PointerTool.HIGHLIGHTER || slideshow.tool == PointerTool.ERASER) return;
                if (click.get_current_button () == Gdk.BUTTON_SECONDARY) {
                    slideshow.previous ();
                    return;
                }
                double sx, sy;
                to_slide (x, y, out sx, out sy);
                if (handle_click (sx, sy)) return;
                slideshow.next ();
            });
            add_controller (click);
            var drag = new GestureDrag ();
            drag.drag_begin.connect ((x, y) => {
                double sx, sy;
                to_slide (x, y, out sx, out sy);
                if (slideshow.tool == PointerTool.ERASER) {
                    slideshow.erase_at (sx, sy, 8);
                    return;
                }
                if (slideshow.tool != PointerTool.PEN && slideshow.tool != PointerTool.HIGHLIGHTER) return;
                drawing = new InkStroke ();
                bool hl = slideshow.tool == PointerTool.HIGHLIGHTER;
                var pc = slideshow.pen_color;
                drawing.color = hl ? "#ffeb33" : pc.to_hex ();
                drawing.highlighter = hl;
                drawing.width = hl ? 18 : 4;
                drawing.pts.add (sx);
                drawing.pts.add (sy);
                slideshow.strokes ().add (drawing);
            });
            drag.drag_update.connect ((dx, dy) => {
                double bx, by;
                drag.get_start_point (out bx, out by);
                double sx, sy;
                to_slide (bx + dx, by + dy, out sx, out sy);
                if (slideshow.tool == PointerTool.ERASER) {
                    slideshow.erase_at (sx, sy, 8);
                    return;
                }
                if (drawing == null) return;
                drawing.pts.add (sx);
                drawing.pts.add (sy);
                slideshow.changed ();
            });
            drag.drag_end.connect (() => drawing = null);
            add_controller (drag);
            var motion = new EventControllerMotion ();
            motion.motion.connect ((x, y) => {
                double sx, sy;
                to_slide (x, y, out sx, out sy);
                if (slideshow.tool == PointerTool.LASER) {
                    slideshow.laser_x = sx;
                    slideshow.laser_y = sy;
                }
                update_hover (sx, sy);
                update_cursor ();
            });
            motion.leave.connect (() => {
                if (slideshow.tool == PointerTool.LASER) {
                    slideshow.laser_x = -1;
                    slideshow.changed ();
                }
            });
            add_controller (motion);
        }

        private RenderContext context () {
            var s = slideshow.current;
            return new RenderContext (slideshow.pres, s, slideshow.pres.layout_for (s), slideshow.pres.master_for (s));
        }

        private Element? hit (double x, double y, out TextRun? run) {
            run = null;
            var s = slideshow.current;
            var states = slideshow.states ();
            for (int i = s.elements.size - 1; i >= 0; i--) {
                var e = s.elements[i];
                if (states.has_key (e.id) && !states[e.id].visible) continue;
                if (!e.contains (x, y, 2)) continue;
                run = renderer.run_at (context (), e, x, y);
                return e;
            }
            return null;
        }

        private bool clickable (Element e, TextRun? run) {
            if (run != null && run.link != "") return true;
            if (e.click != null && e.click.kind != ActionKind.NONE) return true;
            if (e is ZoomElement) return true;
            if (e is MediaElement && slideshow.media.has (e.id)) return true;
            if (slideshow.player != null && slideshow.player.trigger_keys_for (e.id).size > 0) return true;
            return false;
        }

        private void update_hover (double x, double y) {
            if (!interactive) return;
            TextRun? run;
            var e = hit (x, y, out run);
            hover_run = run;
            if (e != hover_el) {
                hover_el = e;
                if (e != null && e.hover != null) slideshow.run_action (e.hover);
            }
        }

        private bool handle_click (double x, double y) {
            TextRun? run;
            var e = hit (x, y, out run);
            if (e == null) return false;
            if (run != null && run.link != "") {
                var a = LinkTarget.to_action (run.link);
                if (a != null) {
                    slideshow.run_action (a);
                    return true;
                }
            }
            if (slideshow.trigger (e.id)) return true;
            var z = e as ZoomElement;
            if (z != null) {
                slideshow.open_zoom (z);
                return true;
            }
            if (e.click != null && e.click.kind != ActionKind.NONE) {
                if (e.click.kind == ActionKind.PLAY_MEDIA) slideshow.media.toggle (e.id);
                else slideshow.run_action (e.click);
                return true;
            }
            if (e is MediaElement && slideshow.media.has (e.id)) {
                slideshow.media.toggle (e.id);
                return true;
            }
            return false;
        }

        private void update_cursor () {
            switch (slideshow.tool) {
                case PointerTool.LASER:
                    set_cursor_from_name ("none");
                    break;
                case PointerTool.PEN:
                case PointerTool.HIGHLIGHTER:
                    set_cursor_from_name ("crosshair");
                    break;
                case PointerTool.ERASER:
                    set_cursor_from_name ("cell");
                    break;
                default:
                    bool link = hover_el != null && interactive && clickable (hover_el, hover_run);
                    set_cursor_from_name (link ? "pointer" : "default");
                    break;
            }
        }

        private void fit (int w, int h) {
            var p = slideshow.pres;
            sc = double.min (w / p.width, h / p.height);
            ox = (w - p.width * sc) / 2;
            oy = (h - p.height * sc) / 2;
        }

        public void to_slide (double x, double y, out double sx, out double sy) {
            fit (get_width (), get_height ());
            sx = (x - ox) / sc;
            sy = (y - oy) / sc;
        }

        private Gee.HashSet<int> hidden_media () {
            var set = new Gee.HashSet<int> ();
            foreach (var e in slideshow.current.elements) {
                var m = e as MediaElement;
                if (m == null) continue;
                bool shown = slideshow.media.started (m.id);
                if (m.hide_when_stopped && !shown) set.add (m.id);
                if (shown && slideshow.media.frame (m.id) != null) set.add (m.id);
            }
            return set;
        }

        private Cairo.ImageSurface render (Slide s, Gee.HashMap<int, ElementState>? states, int w, int h) {
            var surf = new Cairo.ImageSurface (Cairo.Format.ARGB32, w, h);
            var cr = new Cairo.Context (surf);
            cr.scale (w / slideshow.pres.width, h / slideshow.pres.height);
            renderer.states = states;
            renderer.draw_slide (cr, slideshow.pres, s);
            renderer.states = null;
            return surf;
        }

        protected override void snapshot (Snapshot snap) {
            int w = get_width (), h = get_height ();
            var rect = Graphene.Rect ();
            rect.init (0, 0, w, h);
            var cr = snap.append_cairo (rect);
            cr.set_source_rgb (0, 0, 0);
            cr.paint ();
            if (slideshow.pres.slides.size == 0) return;
            fit (w, h);
            if (slideshow.ended) {
                var layout = create_pango_layout (_("End of slideshow. Click or press a key to exit."));
                int lw, lh;
                layout.get_pixel_size (out lw, out lh);
                cr.set_source_rgba (1, 1, 1, 0.7);
                cr.move_to ((w - lw) / 2, (h - lh) / 2);
                Pango.cairo_show_layout (cr, layout);
                return;
            }
            if (slideshow.blank != BlankMode.NONE) {
                if (slideshow.blank == BlankMode.WHITE) {
                    cr.set_source_rgb (1, 1, 1);
                    cr.paint ();
                }
                return;
            }
            int sw = (int) Math.round (slideshow.pres.width * sc), sh = (int) Math.round (slideshow.pres.height * sc);
            var tr = slideshow.active_transition;
            bool transitioning = slideshow.in_transition && slideshow.transition_from >= 0;
            if (transitioning && tr.kind == TransitionKind.MORPH) {
                cr.save ();
                cr.translate (ox, oy);
                cr.scale (sc, sc);
                var from_slide = slideshow.pres.slides[slideshow.transition_from];
                Morph.draw (cr, slideshow.pres, from_slide, slideshow.current, slideshow.transition_time / double.max (tr.duration, 0.05));
                cr.restore ();
            } else if (transitioning) {
                if (cached_serial != slideshow.transition_serial || cached_w != sw || cached_h != sh) {
                    var from_slide = slideshow.pres.slides[slideshow.transition_from];
                    var fp = new Player (slideshow.pres, from_slide);
                    from_surf = render (from_slide, fp.final_states (), sw, sh);
                    to_surf = render (slideshow.current, slideshow.player.initial_states (), sw, sh);
                    cached_serial = slideshow.transition_serial;
                    cached_w = sw;
                    cached_h = sh;
                }
                cr.save ();
                cr.translate (ox, oy);
                cr.rectangle (0, 0, sw, sh);
                cr.clip ();
                Transitions.draw_full (cr, tr, slideshow.transition_time / double.max (tr.duration, 0.05), from_surf, to_surf, sw, sh);
                cr.restore ();
            } else {
                cr.save ();
                cr.translate (ox, oy);
                cr.scale (sc, sc);
                renderer.states = slideshow.states ();
                renderer.hidden = hidden_media ();
                renderer.draw_slide (cr, slideshow.pres, slideshow.current);
                renderer.states = null;
                renderer.hidden = null;
                cr.restore ();
            }
            if (!transitioning) {
                foreach (var e in slideshow.current.elements) {
                    var m = e as MediaElement;
                    if (m == null || !m.is_video) continue;
                    var frame = slideshow.media.frame (m.id);
                    if (frame == null) continue;
                    snap.save ();
                    double fx = ox + m.x * sc, fy = oy + m.y * sc, fw = m.w * sc, fh = m.h * sc;
                    if (m.full_screen && slideshow.media.playing (m.id)) {
                        fx = 0;
                        fy = 0;
                        fw = w;
                        fh = h;
                        var black = Graphene.Rect ();
                        black.init (0, 0, w, h);
                        snap.append_color ({ 0, 0, 0, 1 }, black);
                    }
                    var p = Graphene.Point ();
                    p.init ((float) fx, (float) fy);
                    snap.translate (p);
                    frame.snapshot (snap, fw, fh);
                    snap.restore ();
                }
            }
            var cr2 = snap.append_cairo (rect);
            cr2.save ();
            cr2.translate (ox, oy);
            cr2.scale (sc, sc);
            foreach (var st in slideshow.strokes ()) Renderer.stroke_ink (cr2, null, st);
            if (slideshow.tool == PointerTool.LASER && slideshow.laser_x >= 0) {
                var c = slideshow.laser_color;
                double r = slideshow.pres.height * 0.012;
                var pat = new Cairo.Pattern.radial (slideshow.laser_x, slideshow.laser_y, 0, slideshow.laser_x, slideshow.laser_y, r * 3);
                pat.add_color_stop_rgba (0, c.r, c.g, c.b, 0.55);
                pat.add_color_stop_rgba (1, c.r, c.g, c.b, 0);
                cr2.set_source (pat);
                cr2.arc (slideshow.laser_x, slideshow.laser_y, r * 3, 0, 2 * Math.PI);
                cr2.fill ();
                cr2.set_source_rgba (c.r, c.g, c.b, 1);
                cr2.arc (slideshow.laser_x, slideshow.laser_y, r, 0, 2 * Math.PI);
                cr2.fill ();
                cr2.set_source_rgba (1, 1, 1, 0.8);
                cr2.arc (slideshow.laser_x, slideshow.laser_y, r * 0.35, 0, 2 * Math.PI);
                cr2.fill ();
            }
            cr2.restore ();
            if (slideshow.show_captions && slideshow.caption != "") draw_caption (cr2, w, h);
        }

        private void draw_caption (Cairo.Context cr, int w, int h) {
            var layout = create_pango_layout (slideshow.caption);
            var fd = Pango.FontDescription.from_string ("Inter 22");
            fd.set_absolute_size (double.max (h * 0.035, 12) * Pango.SCALE);
            layout.set_font_description (fd);
            layout.set_width ((int) (w * 0.8 * Pango.SCALE));
            layout.set_alignment (Pango.Alignment.CENTER);
            layout.set_wrap (Pango.WrapMode.WORD);
            int lw, lh;
            layout.get_pixel_size (out lw, out lh);
            double bx = (w - w * 0.8) / 2, by = h - lh - h * 0.06;
            cr.save ();
            cr.rectangle (bx - 12, by - 8, w * 0.8 + 24, lh + 16);
            cr.set_source_rgba (0, 0, 0, 0.72);
            cr.fill ();
            cr.set_source_rgb (1, 1, 1);
            cr.move_to (bx, by);
            Pango.cairo_show_layout (cr, layout);
            cr.restore ();
        }
    }

    public class ShowWindow : Gtk.Window {
        public SlideShow slideshow;
        public ShowStage stage;
        private uint hide_cursor_id = 0;

        public ShowWindow (Gtk.Application app, SlideShow slideshow) {
            Object (application: app);
            this.slideshow = slideshow;
            title = _("Slideshow");
            add_css_class ("slides-show");
            decorated = false;
            stage = new ShowStage (slideshow);
            child = stage;
            set_default_size (960, 540);
            var keys = new EventControllerKey ();
            keys.key_pressed.connect ((keyval, code, state) => slideshow.handle_key (keyval, state));
            ((Widget) this).add_controller (keys);
            var motion = new EventControllerMotion ();
            motion.motion.connect (() => {
                if (slideshow.tool != PointerTool.ARROW) return;
                if (hide_cursor_id != 0) Source.remove (hide_cursor_id);
                hide_cursor_id = Timeout.add (2000, () => {
                    hide_cursor_id = 0;
                    if (slideshow.tool == PointerTool.ARROW) stage.set_cursor_from_name ("none");
                    return Source.REMOVE;
                });
            });
            ((Widget) this).add_controller (motion);
            close_request.connect (() => {
                if (hide_cursor_id != 0) Source.remove (hide_cursor_id);
                return false;
            });
        }
    }

    public class PresenterWindow : Singularity.Widgets.Window {
        public SlideShow slideshow;
        private ShowStage stage;
        private Picture next_pic;
        private Label next_label;
        private TextView notes;
        private Label timer_label;
        private Label clock_label;
        private Label counter;
        private Label slide_timer;
        private uint clock_id = 0;
        private double notes_size = 20;
        private Renderer renderer = new Renderer ();
        private Button pen_bubble;
        private Button laser_bubble;
        private Button eraser_bubble;
        private Stack main_stack;
        private FlowBox grid;

        public PresenterWindow (Gtk.Application app, SlideShow slideshow) {
            base (app);
            this.slideshow = slideshow;
            set_title (slideshow.rehearse ? _("Rehearse Timings") : _("Presenter View"));
            set_default_size (1280, 760);
            var root = new Box (Orientation.HORIZONTAL, 16);
            apply_bubble_inset (root, 56, 16);
            root.margin_bottom = 16;
            root.margin_start = 16;
            root.margin_end = 16;
            var left = new Box (Orientation.VERTICAL, 10);
            left.hexpand = true;
            var cur_title = new Label (_("Current Slide"));
            cur_title.add_css_class ("heading");
            cur_title.xalign = 0;
            left.append (cur_title);
            stage = new ShowStage (slideshow);
            stage.add_css_class ("slides-presenter-slide");
            stage.overflow = Overflow.HIDDEN;
            grid = new FlowBox ();
            grid.selection_mode = SelectionMode.NONE;
            grid.max_children_per_line = 6;
            grid.min_children_per_line = 3;
            grid.row_spacing = 12;
            grid.column_spacing = 12;
            var grid_scroll = new ScrolledWindow ();
            grid_scroll.child = grid;
            grid_scroll.vexpand = true;
            main_stack = new Stack ();
            main_stack.vexpand = true;
            main_stack.add_named (stage, "stage");
            main_stack.add_named (grid_scroll, "grid");
            left.append (main_stack);
            var info = new Box (Orientation.HORIZONTAL, 18);
            timer_label = new Label ("00:00:00");
            timer_label.add_css_class ("slides-timer");
            timer_label.tooltip_text = _("Elapsed time");
            info.append (timer_label);
            slide_timer = new Label ("");
            slide_timer.add_css_class ("title-3");
            slide_timer.add_css_class ("dim-label");
            slide_timer.tooltip_text = _("Time on this slide");
            info.append (slide_timer);
            var spacer = new Box (Orientation.HORIZONTAL, 0);
            spacer.hexpand = true;
            info.append (spacer);
            counter = new Label ("");
            counter.add_css_class ("title-3");
            info.append (counter);
            clock_label = new Label ("");
            clock_label.add_css_class ("title-3");
            clock_label.add_css_class ("dim-label");
            clock_label.tooltip_text = _("Current time");
            info.append (clock_label);
            left.append (info);
            root.append (left);
            var right = new Box (Orientation.VERTICAL, 10);
            right.set_size_request (380, -1);
            right.hexpand = false;
            var next_title = new Label (_("Next"));
            next_title.add_css_class ("heading");
            next_title.xalign = 0;
            right.append (next_title);
            next_pic = new Picture ();
            next_pic.add_css_class ("slides-thumb");
            next_pic.can_shrink = true;
            next_pic.content_fit = ContentFit.CONTAIN;
            next_pic.set_size_request (380, (int) (380 * slideshow.pres.height / slideshow.pres.width));
            next_pic.hexpand = false;
            next_pic.halign = Align.START;
            right.append (next_pic);
            next_label = new Label ("");
            next_label.add_css_class ("dim-label");
            next_label.xalign = 0;
            next_label.ellipsize = Pango.EllipsizeMode.END;
            right.append (next_label);
            var notes_head = new Box (Orientation.HORIZONTAL, 6);
            var notes_title = new Label (_("Notes"));
            notes_title.add_css_class ("heading");
            notes_title.xalign = 0;
            notes_title.hexpand = true;
            notes_head.append (notes_title);
            var smaller = new Button.from_icon_name ("zoom-out-symbolic");
            smaller.add_css_class ("flat");
            smaller.tooltip_text = _("Smaller Notes");
            smaller.clicked.connect (() => set_notes_size (notes_size - 2));
            notes_head.append (smaller);
            var bigger = new Button.from_icon_name ("zoom-in-symbolic");
            bigger.add_css_class ("flat");
            bigger.tooltip_text = _("Larger Notes");
            bigger.clicked.connect (() => set_notes_size (notes_size + 2));
            notes_head.append (bigger);
            right.append (notes_head);
            notes = new TextView ();
            notes.editable = false;
            notes.cursor_visible = false;
            notes.wrap_mode = WrapMode.WORD_CHAR;
            notes.add_css_class ("slides-presenter-notes");
            notes.left_margin = 8;
            notes.right_margin = 8;
            var ns = new ScrolledWindow ();
            ns.vexpand = true;
            ns.child = notes;
            ns.add_css_class ("slides-notes");
            right.append (ns);
            root.append (right);
            set_content (root);

            add_bubble_icon ("go-previous-symbolic", _("Previous (Left)"), () => slideshow.previous ());
            add_bubble_icon ("go-next-symbolic", _("Next (Right)"), () => slideshow.next ());
            add_bubble_icon ("view-grid-symbolic", _("See All Slides"), () => toggle_grid ());
            laser_bubble = add_bubble_icon ("slides-laser-symbolic", _("Laser Pointer (Ctrl+L)"), () => slideshow.set_tool (PointerTool.LASER));
            pen_bubble = add_bubble_icon ("slides-pen-symbolic", _("Pen (Ctrl+P)"), () => slideshow.set_tool (PointerTool.PEN));
            add_bubble_icon ("slides-highlighter-symbolic", _("Highlighter (Ctrl+I)"), () => slideshow.set_tool (PointerTool.HIGHLIGHTER));
            eraser_bubble = add_bubble_icon ("edit-clear-symbolic", _("Eraser (Ctrl+E)"), () => slideshow.set_tool (PointerTool.ERASER));
            add_bubble_icon ("edit-clear-all-symbolic", _("Erase All Drawings (E)"), () => slideshow.erase ());
            add_bubble_icon ("slides-black-screen-symbolic", _("Black Screen (B)"), () => slideshow.toggle_blank (BlankMode.BLACK));
            add_bubble_icon ("media-view-subtitles-symbolic", _("Subtitles (J)"), () => {
                slideshow.toggle_captions ();
            });
            add_bubble_icon ("media-playback-pause-symbolic", _("Pause Timer"), () => {
                slideshow.paused = !slideshow.paused;
                if (slideshow.paused) slideshow.total.stop ();
                else slideshow.total.continue ();
            });
            add_bubble_icon ("view-refresh-symbolic", _("Reset Timer"), () => {
                slideshow.total.start ();
                slideshow.on_slide.start ();
            });
            add_bubble_text (_("End Show"), () => slideshow.finished ());

            var keys = new EventControllerKey ();
            keys.key_pressed.connect ((keyval, code, state) => {
                if (keyval == Gdk.Key.g && (state & Gdk.ModifierType.CONTROL_MASK) == 0) {
                    toggle_grid ();
                    return true;
                }
                return slideshow.handle_key (keyval, state);
            });
            ((Widget) this).add_controller (keys);
            slideshow.slide_changed.connect (update_slide);
            slideshow.changed.connect (update_tools);
            update_slide ();
            clock_id = Timeout.add (250, () => {
                update_clock ();
                return Source.CONTINUE;
            });
            close_request.connect (() => {
                if (clock_id != 0) Source.remove (clock_id);
                clock_id = 0;
                slideshow.finished ();
                return false;
            });
        }

        private void toggle_grid () {
            if (main_stack.visible_child_name == "grid") {
                main_stack.visible_child_name = "stage";
                return;
            }
            Widget? child;
            while ((child = grid.get_first_child ()) != null) grid.remove (child);
            var pres = slideshow.pres;
            for (int i = 0; i < pres.slides.size; i++) {
                var s = pres.slides[i];
                var surf = renderer.thumbnail (pres, s, 220);
                var pic = new Picture.for_paintable (ThumbCache.texture_of (surf));
                pic.can_shrink = true;
                pic.set_size_request (200, (int) (200 * pres.height / pres.width));
                var btn = new Button ();
                btn.add_css_class ("flat");
                var box = new Box (Orientation.VERTICAL, 4);
                box.append (pic);
                string title = s.title ();
                string sec = s.section != null ? s.section.name + ": " : "";
                var lbl = new Label ("%d  %s%s".printf (i + 1, sec, title));
                lbl.ellipsize = Pango.EllipsizeMode.END;
                lbl.max_width_chars = 24;
                if (s.hidden) lbl.add_css_class ("dim-label");
                box.append (lbl);
                btn.child = box;
                int idx = i;
                btn.clicked.connect (() => {
                    slideshow.go_to_slide_index (idx);
                    main_stack.visible_child_name = "stage";
                });
                grid.append (btn);
            }
            main_stack.visible_child_name = "grid";
        }

        private void set_notes_size (double s) {
            notes_size = s.clamp (10, 48);
            apply_notes_size ();
        }

        private void apply_notes_size () {
            var tag = notes.buffer.tag_table.lookup ("size");
            if (tag == null) {
                tag = new TextTag ("size");
                notes.buffer.tag_table.add (tag);
            }
            tag.size_points = notes_size * 0.75;
            TextIter a, b;
            notes.buffer.get_bounds (out a, out b);
            notes.buffer.apply_tag (tag, a, b);
        }

        private void update_tools () {
            if (slideshow.tool == PointerTool.LASER) laser_bubble.add_css_class ("suggested-action");
            else laser_bubble.remove_css_class ("suggested-action");
            if (slideshow.tool == PointerTool.PEN) pen_bubble.add_css_class ("suggested-action");
            else pen_bubble.remove_css_class ("suggested-action");
            if (slideshow.tool == PointerTool.ERASER) eraser_bubble.add_css_class ("suggested-action");
            else eraser_bubble.remove_css_class ("suggested-action");
            counter.label = _("Slide %d of %d").printf (slideshow.position + 1, slideshow.order.size);
        }

        private static string fmt_time (double secs) {
            int s = (int) secs;
            return "%02d:%02d:%02d".printf (s / 3600, (s / 60) % 60, s % 60);
        }

        private void update_clock () {
            timer_label.label = fmt_time (slideshow.total.elapsed ());
            slide_timer.label = fmt_time (slideshow.on_slide.elapsed ());
            clock_label.label = new DateTime.now_local ().format ("%H:%M");
        }

        private void update_slide () {
            var next = slideshow.next_slide;
            if (next != null) {
                var fp = new Player (slideshow.pres, next);
                int tw = 380 * int.max (1, get_scale_factor ());
                var surf = new Cairo.ImageSurface (Cairo.Format.ARGB32, tw, (int) (tw * slideshow.pres.height / slideshow.pres.width));
                var cr = new Cairo.Context (surf);
                cr.scale (tw / slideshow.pres.width, tw / slideshow.pres.width);
                renderer.states = fp.final_states ();
                renderer.draw_slide (cr, slideshow.pres, next);
                renderer.states = null;
                next_pic.paintable = ThumbCache.texture_of (surf);
                string title = next.title ();
                next_label.label = title != "" ? title : _("Slide %d").printf (slideshow.pres.slides.index_of (next) + 1);
            } else {
                next_pic.paintable = null;
                next_label.label = _("End of slideshow");
            }
            notes.buffer.text = slideshow.current.notes != "" ? slideshow.current.notes : _("No notes for this slide.");
            apply_notes_size ();
            update_tools ();
        }
    }
}
