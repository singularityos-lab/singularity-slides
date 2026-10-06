namespace Singularity.Apps.Slides {

    public class TimedAnimation {
        public Animation anim;
        public int step;
        public double start;
        public double end;
        public double cycle;

        public TimedAnimation (Animation anim, int step, double start, double end) {
            this.anim = anim;
            this.step = step;
            this.start = start;
            this.end = end;
            cycle = end - start;
        }
    }

    public class Player {
        public Presentation pres;
        public Slide slide;
        public Gee.ArrayList<TimedAnimation> timed = new Gee.ArrayList<TimedAnimation> ();
        public Gee.ArrayList<double?> step_lengths = new Gee.ArrayList<double?> ();
        public bool auto_first = false;
        public Gee.HashMap<string, Gee.ArrayList<TimedAnimation>> triggers = new Gee.HashMap<string, Gee.ArrayList<TimedAnimation>> ();
        public Gee.HashMap<string, double?> trigger_elapsed = new Gee.HashMap<string, double?> ();

        public Player (Presentation pres, Slide slide) {
            this.pres = pres;
            this.slide = slide;
            build ();
        }

        public static string trigger_key (Animation a) {
            return a.trigger_bookmark != "" ? "b%d:%s".printf (a.trigger_shape, a.trigger_bookmark) : "s%d".printf (a.trigger_shape);
        }

        private static double total_length (Animation a) {
            if (a.anim_class == AnimClass.MEDIA) return 0.01;
            double d = a.effect == AnimEffect.APPEAR ? 0.01 : double.max (a.duration, 0.01);
            if (a.auto_reverse) d *= 2;
            if (a.repeat > 1) d *= a.repeat;
            return d;
        }

        public static Gee.ArrayList<Animation> with_implied_media (Slide slide) {
            var list = new Gee.ArrayList<Animation> ();
            var explicit_media = new Gee.HashSet<int> ();
            foreach (var a in slide.animations) if (a.anim_class == AnimClass.MEDIA && a.effect == AnimEffect.MEDIA_PLAY) explicit_media.add (a.target);
            var all = new Gee.ArrayList<Element> ();
            foreach (var e in slide.elements) flatten (e, all);
            var tail = new Gee.ArrayList<Animation> ();
            foreach (var e in all) {
                var m = e as MediaElement;
                if (m == null || explicit_media.contains (m.id) || m.start == MediaStart.ON_CLICK) continue;
                var a = new Animation (m.id);
                a.anim_class = AnimClass.MEDIA;
                a.effect = AnimEffect.MEDIA_PLAY;
                a.trigger = m.start == MediaStart.AUTOMATIC ? AnimTrigger.WITH_PREVIOUS : AnimTrigger.ON_CLICK;
                if (m.start == MediaStart.AUTOMATIC) list.add (a);
                else tail.add (a);
            }
            list.add_all (slide.animations);
            list.add_all (tail);
            return list;
        }

        private static void flatten (Element e, Gee.List<Element> list) {
            list.add (e);
            var g = e as GroupElement;
            if (g != null) foreach (var c in g.children) flatten (c, list);
        }

        private void build () {
            int step = -1;
            double prev_start = 0, prev_end = 0, step_end = 0;
            var groups = new Gee.HashMap<string, double?> ();
            var group_prev = new Gee.HashMap<string, double?> ();
            var effective = with_implied_media (slide);
            for (int i = 0; i < effective.size; i++) {
                var a = effective[i];
                if (slide.find (a.target) == null) continue;
                if (a.trigger_shape >= 0 || a.trigger_bookmark != "") {
                    string key = trigger_key (a);
                    if (!triggers.has_key (key)) {
                        triggers[key] = new Gee.ArrayList<TimedAnimation> ();
                        groups[key] = 0;
                        group_prev[key] = 0;
                    }
                    var list = triggers[key];
                    double ps = group_prev[key], pe = groups[key];
                    double st = list.size == 0 || a.trigger == AnimTrigger.ON_CLICK && list.size == 0 ? a.delay : (a.trigger == AnimTrigger.WITH_PREVIOUS ? ps + a.delay : pe + a.delay);
                    var ta = new TimedAnimation (a, 0, st, st + total_length (a));
                    ta.cycle = a.effect == AnimEffect.APPEAR ? 0.01 : double.max (a.duration, 0.01);
                    list.add (ta);
                    group_prev[key] = st;
                    groups[key] = st + total_length (a);
                    continue;
                }
                bool new_step = a.trigger == AnimTrigger.ON_CLICK || step < 0;
                if (new_step) {
                    if (step >= 0) step_lengths.add (step_end);
                    step++;
                    if (step == 0 && a.trigger != AnimTrigger.ON_CLICK) auto_first = true;
                    prev_start = 0;
                    prev_end = 0;
                    step_end = 0;
                }
                double start;
                if (new_step && a.trigger == AnimTrigger.ON_CLICK) start = a.delay;
                else if (a.trigger == AnimTrigger.WITH_PREVIOUS) start = prev_start + a.delay;
                else start = prev_end + a.delay;
                double len = total_length (a);
                if (a.anim_class == AnimClass.MEDIA && a.effect == AnimEffect.MEDIA_PLAY) {
                    var m = slide.find (a.target) as MediaElement;
                    if (m != null && !m.loop) len = double.max (m.play_length (), 0.01);
                }
                double end = start + len;
                var ta = new TimedAnimation (a, step, start, end);
                ta.cycle = a.effect == AnimEffect.APPEAR ? 0.01 : double.max (a.duration, 0.01);
                timed.add (ta);
                prev_start = start;
                prev_end = end;
                double visual_end = a.repeat < 0 ? start + ta.cycle : end;
                if (a.anim_class != AnimClass.MEDIA) step_end = double.max (step_end, visual_end);
            }
            if (step >= 0) step_lengths.add (step_end);
        }

        public int step_count {
            get { return step_lengths.size; }
        }

        public double step_length (int step) {
            if (step < 0 || step >= step_lengths.size) return 0;
            return step_lengths[step];
        }

        public double trigger_length (string key) {
            if (!triggers.has_key (key)) return 0;
            double m = 0;
            foreach (var ta in triggers[key]) m = double.max (m, ta.end);
            return m;
        }

        public Gee.ArrayList<string> trigger_keys_for (int shape) {
            var list = new Gee.ArrayList<string> ();
            foreach (var k in triggers.keys) if (k == "s%d".printf (shape)) list.add (k);
            return list;
        }

        public static double ease (double t) {
            t = t.clamp (0, 1);
            return t < 0.5 ? 4 * t * t * t : 1 - Math.pow (-2 * t + 2, 3) / 2;
        }

        private static double ease_out (double t) {
            t = t.clamp (0, 1);
            return 1 - Math.pow (1 - t, 3);
        }

        public static double accel_decel (double p, double a, double d) {
            if (a <= 0 && d <= 0) return p;
            if (a + d > 1) {
                double s = a + d;
                a /= s;
                d /= s;
            }
            double r = 1 / (1 - a / 2 - d / 2);
            if (p < a) return r * p * p / (2 * a);
            if (p <= 1 - d) return r * (p - a / 2);
            double t = 1 - p;
            return 1 - r * t * t / (2 * d);
        }

        private static double progress (TimedAnimation ta, double t) {
            var a = ta.anim;
            double local = t - ta.start;
            if (local <= 0) return 0;
            double cyc = ta.cycle;
            double span = a.auto_reverse ? cyc * 2 : cyc;
            bool infinite = a.repeat < 0;
            double total = infinite ? double.MAX : span * double.max (a.repeat, 1);
            if (local >= total) return a.auto_reverse ? 0 : 1;
            double in_cycle = local % span;
            double p = in_cycle / cyc;
            if (a.auto_reverse && p > 1) p = 2 - p;
            return accel_decel (p.clamp (0, 1), a.accel, a.decel);
        }

        private ElementState state_for (Gee.HashMap<int, ElementState> map, Animation a) {
            if (!map.has_key (a.target)) map[a.target] = new ElementState ();
            var st = map[a.target];
            if (a.paragraph < 0) return st;
            if (st.paras == null) st.paras = new Gee.HashMap<int, ElementState> ();
            if (!st.paras.has_key (a.paragraph)) st.paras[a.paragraph] = new ElementState ();
            return st.paras[a.paragraph];
        }

        public Gee.HashMap<int, ElementState> states_at (int step, double t) {
            var map = new Gee.HashMap<int, ElementState> ();
            var first_seen = new Gee.HashSet<string> ();
            var all = new Gee.ArrayList<TimedAnimation> ();
            all.add_all (timed);
            foreach (var list in triggers.values) all.add_all (list);
            foreach (var ta in all) {
                var a = ta.anim;
                if (a.anim_class == AnimClass.MEDIA) continue;
                string key = "%d:%d".printf (a.target, a.paragraph);
                if (first_seen.contains (key)) continue;
                first_seen.add (key);
                var st = state_for (map, a);
                st.visible = a.anim_class != AnimClass.ENTRANCE;
            }
            foreach (var ta in timed) {
                if (ta.anim.anim_class == AnimClass.MEDIA) continue;
                double p;
                if (ta.step < step) {
                    p = ta.anim.rewind ? -1 : (ta.anim.auto_reverse ? 0 : 1);
                    if (ta.anim.repeat < 0 && !ta.anim.rewind) p = ta.anim.auto_reverse ? 0 : 1;
                } else if (ta.step > step) {
                    continue;
                } else {
                    if (t < ta.start) continue;
                    p = progress (ta, t);
                    if (ta.anim.rewind && t >= ta.end && ta.anim.repeat >= 0) p = -1;
                }
                var st = state_for (map, ta.anim);
                if (p < 0) {
                    if (ta.anim.anim_class == AnimClass.EXIT) st.visible = true;
                    continue;
                }
                apply (st, ta.anim, p.clamp (0, 1));
                bool done = ta.step < step || (ta.step == step && t >= ta.end);
                if (done) after_effect (st, ta, step);
            }
            foreach (var entry in triggers.entries) {
                if (!trigger_elapsed.has_key (entry.key)) continue;
                double et = trigger_elapsed[entry.key];
                foreach (var ta in entry.value) {
                    if (et < ta.start) continue;
                    var st = state_for (map, ta.anim);
                    apply (st, ta.anim, progress (ta, et).clamp (0, 1));
                }
            }
            return map;
        }

        private void after_effect (ElementState st, TimedAnimation ta, int step) {
            var a = ta.anim;
            switch (a.after) {
                case AfterEffect.HIDE:
                    st.visible = false;
                    break;
                case AfterEffect.HIDE_ON_CLICK:
                    if (ta.step < step) st.visible = false;
                    break;
                case AfterEffect.DIM:
                    if (a.dim_color != "") st.text_color = a.dim_color;
                    break;
                default:
                    break;
            }
        }

        private Element? target_of (Animation a) {
            return slide.find (a.target);
        }

        private void apply (ElementState st, Animation a, double p) {
            var e = target_of (a);
            if (e == null) return;
            switch (a.anim_class) {
                case AnimClass.EMPHASIS:
                    st.visible = true;
                    emphasis (st, a, e, p);
                    return;
                case AnimClass.PATH:
                    st.visible = true;
                    double px, py, ang;
                    PathSampler.at (a.path, ease (p), out px, out py, out ang);
                    st.path_dx += px * pres.width;
                    st.path_dy += py * pres.height;
                    if (a.path_rotate) st.spin += ang;
                    return;
                default:
                    break;
            }
            bool exit = a.anim_class == AnimClass.EXIT;
            double e_in = exit ? 1 - ease (p) : ease_out (p);
            double lin = exit ? 1 - p : p;
            if (exit && p >= 1) {
                st.visible = false;
                return;
            }
            st.visible = true;
            st.opacity = 1;
            st.dx = 0;
            st.dy = 0;
            st.scale = 1;
            st.sx = 1;
            st.sy = 1;
            st.wipe = 1;
            st.clip = ClipKind.NONE;
            double dx, dy;
            EffectCatalog.vector (a.subtype, out dx, out dy);
            switch (a.effect) {
                case AnimEffect.APPEAR:
                    st.visible = exit ? p < 1 : p > 0;
                    break;
                case AnimEffect.FLASH_ONCE:
                    st.visible = p > 0 && p < 1;
                    if (exit) st.visible = p < 1;
                    break;
                case AnimEffect.FADE:
                    st.opacity = e_in;
                    break;
                case AnimEffect.FLY:
                case AnimEffect.CRAWL:
                    st.dx = dx * fly_distance (e, dx, 0) * (1 - e_in);
                    st.dy = dy * fly_distance (e, 0, dy) * (1 - e_in);
                    break;
                case AnimEffect.CREDITS:
                    st.dy = (exit ? -1 : 1) * fly_distance (e, 0, exit ? -1 : 1) * (1 - lin);
                    break;
                case AnimEffect.PEEK:
                    st.dx = dx * e.w * (1 - e_in);
                    st.dy = dy * e.h * (1 - e_in);
                    st.clip = ClipKind.WIPE;
                    st.clip_sub = a.subtype;
                    st.clip_p = e_in;
                    break;
                case AnimEffect.ZOOM:
                    st.scale = double.max (e_in, 0.001);
                    st.opacity = e_in;
                    break;
                case AnimEffect.BASIC_ZOOM:
                    st.scale = a.subtype == 32 ? 1 + 3 * (1 - e_in) : double.max (e_in, 0.001);
                    break;
                case AnimEffect.EXPAND:
                    st.sx = 0.7 + 0.3 * e_in;
                    st.opacity = e_in;
                    break;
                case AnimEffect.EASE_IN:
                    st.scale = 1 + 0.5 * (1 - e_in);
                    st.opacity = e_in;
                    break;
                case AnimEffect.COMPRESS:
                    st.sy = 1 + 2 * (1 - e_in);
                    st.opacity = e_in;
                    break;
                case AnimEffect.STRETCH:
                    st.sx = double.max (e_in, 0.001);
                    break;
                case AnimEffect.SWIVEL:
                case AnimEffect.FADE_SWIVEL:
                    st.sx = double.max (Math.fabs (Math.cos ((1 - e_in) * Math.PI * 2.5)), 0.001);
                    if (a.effect == AnimEffect.FADE_SWIVEL) st.opacity = e_in;
                    break;
                case AnimEffect.FLIP:
                    st.sx = double.max (Math.fabs (Math.cos ((1 - e_in) * Math.PI / 2)), 0.001);
                    break;
                case AnimEffect.UNFOLD:
                case AnimEffect.FOLD:
                    st.sx = double.max (e_in, 0.001);
                    st.opacity = e_in;
                    break;
                case AnimEffect.GLIDE:
                    st.dx = -0.15 * pres.width * (1 - e_in);
                    st.sx = 0.05 + 0.95 * e_in;
                    st.opacity = e_in;
                    break;
                case AnimEffect.ZIP:
                    st.sy = double.max (e_in, 0.001);
                    st.opacity = e_in;
                    break;
                case AnimEffect.FLOAT:
                case AnimEffect.RISE_UP:
                case AnimEffect.ARC_UP:
                    double d = pres.height * 0.08;
                    if (a.effect != AnimEffect.FLOAT) {
                        dx = 0;
                        dy = 1;
                    }
                    st.dx = dx * d * (1 - e_in);
                    st.dy = dy * d * (1 - e_in);
                    if (a.effect == AnimEffect.ARC_UP) st.dx = -pres.width * 0.05 * Math.sin (Math.PI * (1 - e_in));
                    st.opacity = e_in;
                    break;
                case AnimEffect.BOUNCE:
                    double bp = e_in;
                    double h = pres.height * 0.25;
                    st.dy = -h * Math.fabs (Math.cos (bp * Math.PI * 1.5)) * (1 - bp);
                    st.dx = -pres.width * 0.1 * (1 - bp);
                    st.opacity = double.min (1, bp * 3);
                    break;
                case AnimEffect.GROW_TURN:
                    st.scale = double.max (e_in, 0.001);
                    st.spin = -90 * (1 - e_in);
                    st.opacity = e_in;
                    break;
                case AnimEffect.SPINNER:
                case AnimEffect.CENTER_REVOLVE:
                case AnimEffect.SPIRAL:
                    st.scale = double.max (e_in, 0.001);
                    st.spin = -360 * (1 - e_in);
                    st.opacity = e_in;
                    if (a.effect == AnimEffect.SPIRAL) {
                        st.dx = pres.width * 0.3 * (1 - e_in) * Math.cos ((1 - e_in) * 6);
                        st.dy = pres.height * 0.3 * (1 - e_in) * Math.sin ((1 - e_in) * 6);
                    }
                    break;
                case AnimEffect.PINWHEEL:
                    st.scale = double.max (e_in, 0.001);
                    st.spin = 720 * (1 - e_in);
                    st.opacity = e_in;
                    break;
                case AnimEffect.BOOMERANG:
                case AnimEffect.SLING:
                case AnimEffect.WHIP:
                case AnimEffect.LIGHT_SPEED:
                case AnimEffect.SWISH:
                    st.dx = pres.width * 0.4 * (1 - e_in);
                    st.sx = a.effect == AnimEffect.LIGHT_SPEED ? 1 + (1 - e_in) : double.max (0.3 + 0.7 * e_in, 0.001);
                    if (a.effect == AnimEffect.BOOMERANG) st.spin = 45 * (1 - e_in);
                    st.opacity = e_in;
                    break;
                case AnimEffect.THIN_LINE:
                    st.sy = double.max (e_in < 0.5 ? 0.03 : (e_in - 0.5) * 2, 0.03);
                    st.sx = double.min (e_in * 2, 1);
                    break;
                case AnimEffect.DISSOLVE:
                case AnimEffect.WIPE:
                case AnimEffect.SPLIT:
                case AnimEffect.BLINDS:
                case AnimEffect.CHECKERBOARD:
                case AnimEffect.RANDOM_BARS:
                case AnimEffect.STRIPS:
                case AnimEffect.BOX:
                case AnimEffect.CIRCLE:
                case AnimEffect.DIAMOND:
                case AnimEffect.PLUS:
                case AnimEffect.WEDGE:
                case AnimEffect.WHEEL:
                    st.clip = Clips.for_effect (a.effect);
                    st.clip_sub = a.subtype;
                    st.clip_p = exit ? 1 - p : p;
                    if (a.effect == AnimEffect.WIPE) st.clip_p = e_in;
                    break;
                default:
                    st.opacity = e_in;
                    break;
            }
        }

        private double fly_distance (Element e, double dx, double dy) {
            if (dx < 0) return e.x + e.w;
            if (dx > 0) return pres.width - e.x;
            if (dy < 0) return e.y + e.h;
            return pres.height - e.y;
        }

        private void emphasis (ElementState st, Animation a, Element e, double p) {
            string c = a.color != "" ? a.color : "accent2";
            switch (a.effect) {
                case AnimEffect.SPIN:
                    st.spin += ease (p) * (a.amount != 0 ? a.amount : 360);
                    if (p >= 1 && ((int) Math.round (a.amount != 0 ? a.amount : 360)) % 360 == 0) st.spin -= (a.amount != 0 ? a.amount : 360);
                    break;
                case AnimEffect.GROW:
                    double target = a.amount > 0 ? a.amount : 1.5;
                    st.scale *= 1 + (target - 1) * ease (p);
                    break;
                case AnimEffect.TEETER:
                    st.spin += 6 * Math.sin (p * Math.PI * 4) * (1 - p * 0.3);
                    break;
                case AnimEffect.TRANSPARENCY:
                    st.opacity *= 1 - (a.amount > 0 ? a.amount : 0.5) * ease (p);
                    break;
                case AnimEffect.FILL_COLOR:
                case AnimEffect.OBJECT_COLOR:
                    st.fill_color = c;
                    st.color_mix = ease (p);
                    break;
                case AnimEffect.LINE_COLOR:
                    st.line_color = c;
                    st.color_mix = ease (p);
                    break;
                case AnimEffect.FONT_COLOR:
                    st.text_color = c;
                    st.color_mix = ease (p);
                    break;
                case AnimEffect.COLOR_PULSE:
                    st.fill_color = c;
                    st.color_mix = Math.sin (Math.PI * p);
                    break;
                case AnimEffect.GROW_COLOR:
                    st.scale *= 1 + 0.1 * ease (p);
                    st.text_color = c;
                    st.color_mix = ease (p);
                    break;
                case AnimEffect.COMPLEMENTARY:
                    st.hue_shift = 180 * ease (p);
                    break;
                case AnimEffect.CONTRASTING:
                    st.hue_shift = 90 * ease (p);
                    break;
                case AnimEffect.DARKEN:
                    st.lightness = -0.25 * ease (p);
                    break;
                case AnimEffect.LIGHTEN:
                    st.lightness = 0.25 * ease (p);
                    break;
                case AnimEffect.DESATURATE:
                    st.desaturate = ease (p);
                    break;
                case AnimEffect.BOLD_FLASH:
                    st.bold = p > 0 && p < 1;
                    break;
                case AnimEffect.BOLD_REVEAL:
                    st.bold = p > 0;
                    break;
                case AnimEffect.UNDERLINE:
                    st.underline = p > 0;
                    break;
                case AnimEffect.WAVE:
                    st.dy = -pres.height * 0.03 * Math.sin (Math.PI * p);
                    break;
                case AnimEffect.BLINK:
                    st.visible = p <= 0 || p >= 1 || p > 0.5;
                    break;
                case AnimEffect.FLICKER:
                case AnimEffect.SHIMMER:
                    st.opacity *= 1 - 0.7 * Math.fabs (Math.sin (Math.PI * p * 3));
                    break;
                default:
                    st.scale *= 1 + 0.08 * Math.sin (Math.PI * p);
                    break;
            }
        }

        public Gee.HashMap<int, ElementState> final_states () {
            return states_at (step_count, 0);
        }

        public Gee.HashMap<int, ElementState> initial_states () {
            return states_at (-1, 0);
        }

        public Gee.ArrayList<TimedAnimation> media_events (int step) {
            var list = new Gee.ArrayList<TimedAnimation> ();
            foreach (var ta in timed) if (ta.step == step && ta.anim.anim_class == AnimClass.MEDIA) list.add (ta);
            return list;
        }
    }

    public class PathSampler {
        public static Gee.ArrayList<double?> flatten (Gee.List<PathCommand> path) {
            var pts = new Gee.ArrayList<double?> ();
            double cx = 0, cy = 0, sx = 0, sy = 0;
            foreach (var c in path) {
                switch (c.op) {
                    case 'M':
                        cx = c.pts[0];
                        cy = c.pts[1];
                        sx = cx;
                        sy = cy;
                        pts.add (cx);
                        pts.add (cy);
                        break;
                    case 'L':
                        cx = c.pts[0];
                        cy = c.pts[1];
                        pts.add (cx);
                        pts.add (cy);
                        break;
                    case 'C':
                    case 'Q':
                        double x1, y1, x2, y2, x3, y3;
                        if (c.op == 'C') {
                            x1 = c.pts[0]; y1 = c.pts[1]; x2 = c.pts[2]; y2 = c.pts[3]; x3 = c.pts[4]; y3 = c.pts[5];
                        } else {
                            x1 = cx + 2.0 / 3 * (c.pts[0] - cx); y1 = cy + 2.0 / 3 * (c.pts[1] - cy);
                            x3 = c.pts[2]; y3 = c.pts[3];
                            x2 = x3 + 2.0 / 3 * (c.pts[0] - x3); y2 = y3 + 2.0 / 3 * (c.pts[1] - y3);
                        }
                        for (int i = 1; i <= 16; i++) {
                            double t = i / 16.0, u = 1 - t;
                            pts.add (u * u * u * cx + 3 * u * u * t * x1 + 3 * u * t * t * x2 + t * t * t * x3);
                            pts.add (u * u * u * cy + 3 * u * u * t * y1 + 3 * u * t * t * y2 + t * t * t * y3);
                        }
                        cx = x3;
                        cy = y3;
                        break;
                    case 'Z':
                        cx = sx;
                        cy = sy;
                        pts.add (cx);
                        pts.add (cy);
                        break;
                    default:
                        break;
                }
            }
            if (pts.size == 0) {
                pts.add (0);
                pts.add (0);
            }
            return pts;
        }

        public static void at (Gee.List<PathCommand> path, double t, out double x, out double y, out double angle) {
            var pts = flatten (path);
            angle = 0;
            double total = 0;
            for (int i = 2; i + 1 < pts.size; i += 2) total += Math.hypot (pts[i] - pts[i - 2], pts[i + 1] - pts[i - 1]);
            x = pts[0];
            y = pts[1];
            if (total <= 0) return;
            double want = total * t.clamp (0, 1);
            double acc = 0;
            for (int i = 2; i + 1 < pts.size; i += 2) {
                double seg = Math.hypot (pts[i] - pts[i - 2], pts[i + 1] - pts[i - 1]);
                if (acc + seg >= want && seg > 0) {
                    double f = (want - acc) / seg;
                    x = pts[i - 2] + (pts[i] - pts[i - 2]) * f;
                    y = pts[i - 1] + (pts[i + 1] - pts[i - 1]) * f;
                    angle = Math.atan2 (pts[i + 1] - pts[i - 1], pts[i] - pts[i - 2]) * 180 / Math.PI;
                    return;
                }
                acc += seg;
            }
            x = pts[pts.size - 2];
            y = pts[pts.size - 1];
        }
    }

    public enum ClipKind {
        NONE,
        WIPE,
        SPLIT,
        BLINDS,
        CHECKERBOARD,
        RANDOM_BARS,
        STRIPS,
        BOX,
        CIRCLE,
        DIAMOND,
        PLUS,
        WEDGE,
        WHEEL,
        DISSOLVE,
        CLOCK,
        COMB
    }

    public class Clips {
        public static ClipKind for_effect (AnimEffect e) {
            switch (e) {
                case AnimEffect.WIPE: return ClipKind.WIPE;
                case AnimEffect.SPLIT: return ClipKind.SPLIT;
                case AnimEffect.BLINDS: return ClipKind.BLINDS;
                case AnimEffect.CHECKERBOARD: return ClipKind.CHECKERBOARD;
                case AnimEffect.RANDOM_BARS: return ClipKind.RANDOM_BARS;
                case AnimEffect.STRIPS: return ClipKind.STRIPS;
                case AnimEffect.BOX: return ClipKind.BOX;
                case AnimEffect.CIRCLE: return ClipKind.CIRCLE;
                case AnimEffect.DIAMOND: return ClipKind.DIAMOND;
                case AnimEffect.PLUS: return ClipKind.PLUS;
                case AnimEffect.WEDGE: return ClipKind.WEDGE;
                case AnimEffect.WHEEL: return ClipKind.WHEEL;
                case AnimEffect.DISSOLVE: return ClipKind.DISSOLVE;
                default: return ClipKind.NONE;
            }
        }

        private static uint hash (int x, int y) {
            uint h = (uint) x * 374761393U + (uint) y * 668265263U;
            h = (h ^ (h >> 13)) * 1274126177;
            return h ^ (h >> 16);
        }

        public static void path (Cairo.Context cr, ClipKind kind, int sub, double p, double x, double y, double w, double h) {
            p = p.clamp (0, 1);
            cr.new_path ();
            double cx = x + w / 2, cy = y + h / 2;
            double diag = Math.sqrt (w * w + h * h) / 2;
            switch (kind) {
                case ClipKind.WIPE:
                    if ((sub & 8) != 0) cr.rectangle (x, y, w * p, h);
                    else if ((sub & 2) != 0) cr.rectangle (x + w * (1 - p), y, w * p, h);
                    else if ((sub & 1) != 0) cr.rectangle (x, y, w, h * p);
                    else cr.rectangle (x, y + h * (1 - p), w, h * p);
                    break;
                case ClipKind.SPLIT:
                    bool horz = sub == 26 || sub == 42;
                    bool outward = sub == 37 || sub == 42;
                    if (outward) {
                        if (horz) cr.rectangle (x, cy - h / 2 * p, w, h * p);
                        else cr.rectangle (cx - w / 2 * p, y, w * p, h);
                    } else {
                        if (horz) {
                            cr.rectangle (x, y, w, h / 2 * p);
                            cr.rectangle (x, y + h - h / 2 * p, w, h / 2 * p);
                        } else {
                            cr.rectangle (x, y, w / 2 * p, h);
                            cr.rectangle (x + w - w / 2 * p, y, w / 2 * p, h);
                        }
                    }
                    break;
                case ClipKind.BLINDS:
                case ClipKind.COMB:
                    int n = 6;
                    for (int i = 0; i < n; i++) {
                        if (sub == 5) cr.rectangle (x + w * i / n, y, w / n * p, h);
                        else cr.rectangle (x, y + h * i / n, w, h / n * p);
                    }
                    break;
                case ClipKind.CHECKERBOARD:
                    int cols = 8, rows = 6;
                    double bw = w / cols, bh = h / rows;
                    for (int r = 0; r < rows; r++) {
                        for (int c = 0; c < cols; c++) {
                            double off = (r + c) % 2 == 0 ? 0 : 0.5;
                            double q = (p * 1.5 - off * 0.5).clamp (0, 1);
                            if (sub == 5) cr.rectangle (x + c * bw, y + r * bh, bw, bh * q);
                            else cr.rectangle (x + c * bw, y + r * bh, bw * q, bh);
                        }
                    }
                    break;
                case ClipKind.RANDOM_BARS:
                    int bars = 40;
                    for (int i = 0; i < bars; i++) {
                        if ((hash (i, 7) % 1000) / 1000.0 >= p) continue;
                        if (sub == 5) cr.rectangle (x + w * i / bars, y, w / bars + 0.5, h);
                        else cr.rectangle (x, y + h * i / bars, w, h / bars + 0.5);
                    }
                    break;
                case ClipKind.DISSOLVE:
                    int dc = 24, dr = int.max (1, (int) Math.ceil (24 * h / double.max (w, 1)));
                    double dw = w / dc, dh = h / dr;
                    for (int r = 0; r < dr; r++) {
                        for (int c = 0; c < dc; c++) {
                            if ((hash (c, r) % 1000) / 1000.0 < p) cr.rectangle (x + c * dw, y + r * dh, dw + 0.5, dh + 0.5);
                        }
                    }
                    break;
                case ClipKind.STRIPS:
                    double diagonal = (w + h) * p;
                    bool from_left = sub == 12 || sub == 9;
                    bool from_top = sub == 12 || sub == 6;
                    double ox = from_left ? x : x + w, oy = from_top ? y : y + h;
                    double sxs = from_left ? 1 : -1, sys = from_top ? 1 : -1;
                    cr.move_to (ox, oy);
                    cr.line_to (ox + sxs * diagonal, oy);
                    cr.line_to (ox, oy + sys * diagonal);
                    cr.close_path ();
                    break;
                case ClipKind.BOX:
                    if (sub == 32) {
                        cr.rectangle (x, y, w, h);
                        cr.rectangle (cx + w / 2 * (1 - p), cy - h / 2 * (1 - p), -w * (1 - p), h * (1 - p));
                    } else {
                        cr.rectangle (cx - w / 2 * p, cy - h / 2 * p, w * p, h * p);
                    }
                    break;
                case ClipKind.CIRCLE:
                    if (sub == 32) {
                        cr.set_fill_rule (Cairo.FillRule.EVEN_ODD);
                        cr.rectangle (x, y, w, h);
                        cr.arc (cx, cy, diag * (1 - p), 0, 2 * Math.PI);
                    } else {
                        cr.arc (cx, cy, diag * p, 0, 2 * Math.PI);
                    }
                    break;
                case ClipKind.DIAMOND:
                    double r = (w + h) / 2 * (sub == 32 ? 1 - p : p);
                    if (sub == 32) {
                        cr.set_fill_rule (Cairo.FillRule.EVEN_ODD);
                        cr.rectangle (x, y, w, h);
                    }
                    cr.move_to (cx, cy - r);
                    cr.line_to (cx + r, cy);
                    cr.line_to (cx, cy + r);
                    cr.line_to (cx - r, cy);
                    cr.close_path ();
                    break;
                case ClipKind.PLUS:
                    double q = sub == 32 ? 1 - p : p;
                    if (sub == 32) {
                        cr.set_fill_rule (Cairo.FillRule.EVEN_ODD);
                        cr.rectangle (x, y, w, h);
                    }
                    cr.rectangle (cx - w / 2 * q, y, w * q, h);
                    cr.rectangle (x, cy - h / 2 * q, w, h * q);
                    break;
                case ClipKind.WEDGE:
                    cr.move_to (cx, cy);
                    cr.arc (cx, cy, diag, -Math.PI / 2 - Math.PI * p, -Math.PI / 2 + Math.PI * p);
                    cr.close_path ();
                    break;
                case ClipKind.WHEEL:
                case ClipKind.CLOCK:
                    int spokes = int.max (sub, 1);
                    bool reverse = kind == ClipKind.CLOCK && sub < 0;
                    if (kind == ClipKind.CLOCK) spokes = 1;
                    for (int i = 0; i < spokes; i++) {
                        double a0 = -Math.PI / 2 + 2 * Math.PI * i / spokes;
                        double a1 = a0 + 2 * Math.PI / spokes * p * (reverse ? -1 : 1);
                        cr.move_to (cx, cy);
                        if (reverse) cr.arc_negative (cx, cy, diag, a0, a1);
                        else cr.arc (cx, cy, diag, a0, a1);
                        cr.close_path ();
                    }
                    break;
                default:
                    cr.rectangle (x, y, w, h);
                    break;
            }
        }

        public static void apply (Cairo.Context cr, ClipKind kind, int sub, double p, double x, double y, double w, double h) {
            if (kind == ClipKind.NONE) return;
            path (cr, kind, sub, p, x, y, w, h);
            cr.clip ();
            cr.set_fill_rule (Cairo.FillRule.WINDING);
        }
    }

    public class Transitions {

        private static void paint (Cairo.Context cr, Cairo.Surface s, double x, double y, double alpha = 1) {
            cr.set_source_surface (s, x, y);
            if (alpha >= 1) cr.paint ();
            else cr.paint_with_alpha (alpha);
        }

        private static void paint_scaled (Cairo.Context cr, Cairo.Surface s, double w, double h, double cx, double cy, double sx, double sy, double rot, double alpha, double tx = 0, double ty = 0) {
            cr.save ();
            cr.translate (cx + tx, cy + ty);
            if (rot != 0) cr.rotate (rot);
            cr.scale (double.max (sx, 0.0001), double.max (sy, 0.0001));
            cr.translate (-cx, -cy);
            paint (cr, s, 0, 0, alpha);
            cr.restore ();
        }

        private static void reveal (Cairo.Context cr, Cairo.Surface to, ClipKind kind, int sub, double p, double w, double h) {
            cr.save ();
            Clips.apply (cr, kind, sub, p, 0, 0, w, h);
            paint (cr, to, 0, 0);
            cr.restore ();
        }

        private static uint hash (int x, int y) {
            uint h = (uint) x * 374761393U + (uint) y * 668265263U;
            h = (h ^ (h >> 13)) * 1274126177;
            return h ^ (h >> 16);
        }

        public static void draw (Cairo.Context cr, TransitionKind kind, Direction dir, double progress, Cairo.Surface? from, Cairo.Surface to, double w, double h) {
            var t = new Transition ();
            t.kind = kind;
            t.direction = dir;
            draw_full (cr, t, progress, from, to, w, h);
        }

        public static void draw_full (Cairo.Context cr, Transition tr, double progress, Cairo.Surface? from, Cairo.Surface to, double w, double h) {
            var kind = tr.kind;
            double p = Player.ease (progress);
            double dx, dy;
            EffectCatalog.vector (tr.subtype, out dx, out dy);
            if (tr.subtype == 0) {
                dx = 1;
                dy = 0;
            }
            double side = tr.variant == 1 ? -1 : 1;
            double cx = w / 2, cy = h / 2;
            cr.save ();
            cr.set_source_rgb (0, 0, 0);
            cr.paint ();
            if (from == null || kind == TransitionKind.NONE || progress >= 1) {
                paint (cr, to, 0, 0);
                cr.restore ();
                return;
            }
            switch (kind) {
                case TransitionKind.FADE:
                case TransitionKind.MORPH:
                    paint (cr, from, 0, 0);
                    paint (cr, to, 0, 0, progress);
                    break;
                case TransitionKind.FADE_BLACK:
                    if (progress < 0.5) paint (cr, from, 0, 0, 1 - progress * 2);
                    else paint (cr, to, 0, 0, (progress - 0.5) * 2);
                    break;
                case TransitionKind.CUT:
                    if (tr.variant == 1) {
                        if (progress < 0.5) paint (cr, from, 0, 0);
                    } else {
                        paint (cr, to, 0, 0);
                    }
                    break;
                case TransitionKind.FLASH:
                    if (progress < 0.5) paint (cr, from, 0, 0);
                    else paint (cr, to, 0, 0);
                    cr.set_source_rgba (1, 1, 1, 1 - Math.fabs (progress - 0.5) * 2);
                    cr.paint ();
                    break;
                case TransitionKind.PUSH:
                case TransitionKind.PAN:
                    paint (cr, from, -dx * w * p, -dy * h * p);
                    paint (cr, to, dx * w * (1 - p), dy * h * (1 - p));
                    break;
                case TransitionKind.WIPE:
                    paint (cr, from, 0, 0);
                    reveal (cr, to, ClipKind.WIPE, dx > 0 ? 2 : (dx < 0 ? 8 : (dy > 0 ? 4 : 1)), p, w, h);
                    break;
                case TransitionKind.COVER:
                    paint (cr, from, 0, 0);
                    paint (cr, to, dx * w * (1 - p), dy * h * (1 - p));
                    break;
                case TransitionKind.UNCOVER:
                    paint (cr, to, 0, 0);
                    paint (cr, from, -dx * w * p, -dy * h * p);
                    break;
                case TransitionKind.REVEAL:
                    if (progress < 0.5) {
                        paint (cr, from, -dx * w * 0.2 * progress * 2, 0, 1 - progress * 2);
                    } else {
                        double q = (progress - 0.5) * 2;
                        paint (cr, to, dx * w * 0.2 * (1 - q), 0, q);
                    }
                    break;
                case TransitionKind.SPLIT:
                    paint (cr, from, 0, 0);
                    int split_sub = tr.variant == 0 ? 37 : (tr.variant == 1 ? 21 : (tr.variant == 2 ? 42 : 26));
                    reveal (cr, to, ClipKind.SPLIT, split_sub, p, w, h);
                    break;
                case TransitionKind.ZOOM:
                case TransitionKind.NEWSFLASH:
                case TransitionKind.FLY_THROUGH:
                    bool out_dir = tr.variant == 1;
                    if (out_dir) {
                        paint_scaled (cr, from, w, h, cx, cy, 1 + p, 1 + p, kind == TransitionKind.NEWSFLASH ? p * 4 * Math.PI : 0, 1 - p);
                        paint_scaled (cr, to, w, h, cx, cy, 0.6 + 0.4 * p, 0.6 + 0.4 * p, 0, p);
                    } else {
                        paint_scaled (cr, from, w, h, cx, cy, 1 - 0.4 * p, 1 - 0.4 * p, 0, 1 - p);
                        paint_scaled (cr, to, w, h, cx, cy, 0.3 + 0.7 * p, 0.3 + 0.7 * p, kind == TransitionKind.NEWSFLASH ? (1 - p) * 4 * Math.PI : 0, p);
                    }
                    break;
                case TransitionKind.DISSOLVE:
                case TransitionKind.GLITTER:
                    paint (cr, from, 0, 0);
                    if (kind == TransitionKind.GLITTER) {
                        cr.save ();
                        int gc = 30, gr = (int) Math.ceil (30 * h / w);
                        double gw = w / gc, gh = h / gr;
                        for (int yy = 0; yy < gr; yy++) {
                            for (int xx = 0; xx < gc; xx++) {
                                double th = ((dx >= 0 ? xx : gc - xx) / (double) gc) * 0.6 + (hash (xx, yy) % 1000) / 1000.0 * 0.4;
                                if (th < progress) {
                                    double hx = xx * gw + gw / 2 + ((yy % 2) * gw / 2), hy = yy * gh + gh / 2;
                                    cr.arc (hx, hy, gw * 0.62, 0, 2 * Math.PI);
                                    cr.new_sub_path ();
                                }
                            }
                        }
                        cr.clip ();
                        paint (cr, to, 0, 0);
                        cr.restore ();
                    } else {
                        reveal (cr, to, ClipKind.DISSOLVE, 0, progress, w, h);
                    }
                    break;
                case TransitionKind.CIRCLE:
                    paint (cr, from, 0, 0);
                    ClipKind sk = tr.variant == 1 ? ClipKind.DIAMOND : (tr.variant == 2 ? ClipKind.PLUS : (tr.variant >= 3 ? ClipKind.BOX : ClipKind.CIRCLE));
                    if (tr.variant == 4) {
                        cr.save ();
                        paint (cr, to, 0, 0);
                        cr.restore ();
                        cr.save ();
                        Clips.apply (cr, ClipKind.BOX, 16, 1 - p, 0, 0, w, h);
                        paint (cr, from, 0, 0);
                        cr.restore ();
                    } else {
                        reveal (cr, to, sk, 16, p, w, h);
                    }
                    break;
                case TransitionKind.RANDOM_BARS:
                    paint (cr, from, 0, 0);
                    reveal (cr, to, ClipKind.RANDOM_BARS, tr.variant == 1 ? 10 : 5, progress, w, h);
                    break;
                case TransitionKind.CHECKERBOARD:
                    paint (cr, from, 0, 0);
                    reveal (cr, to, ClipKind.CHECKERBOARD, tr.variant == 0 ? 5 : 10, p, w, h);
                    break;
                case TransitionKind.BLINDS:
                    paint (cr, from, 0, 0);
                    reveal (cr, to, ClipKind.BLINDS, tr.variant == 0 ? 5 : 10, p, w, h);
                    break;
                case TransitionKind.COMB:
                    paint (cr, from, 0, 0);
                    int teeth = 10;
                    for (int i = 0; i < teeth; i++) {
                        cr.save ();
                        double dir2 = i % 2 == 0 ? 1 : -1;
                        if (tr.variant == 0) {
                            cr.rectangle (w * i / teeth, 0, w / teeth + 0.5, h);
                            cr.clip ();
                            paint (cr, to, 0, dir2 * h * (1 - p));
                        } else {
                            cr.rectangle (0, h * i / teeth, w, h / teeth + 0.5);
                            cr.clip ();
                            paint (cr, to, dir2 * w * (1 - p), 0);
                        }
                        cr.restore ();
                    }
                    break;
                case TransitionKind.STRIPS:
                    paint (cr, from, 0, 0);
                    int[] ss = { 12, 9, 6, 3 };
                    reveal (cr, to, ClipKind.STRIPS, ss[tr.variant.clamp (0, 3)], p, w, h);
                    break;
                case TransitionKind.CLOCK:
                    paint (cr, from, 0, 0);
                    if (tr.variant == 2) reveal (cr, to, ClipKind.WEDGE, 0, p, w, h);
                    else reveal (cr, to, ClipKind.CLOCK, tr.variant == 1 ? -1 : 1, p, w, h);
                    break;
                case TransitionKind.RANDOM:
                    TransitionKind[] pool = { TransitionKind.FADE, TransitionKind.PUSH, TransitionKind.WIPE, TransitionKind.SPLIT, TransitionKind.CIRCLE, TransitionKind.BLINDS, TransitionKind.CHECKERBOARD };
                    var rt = tr.clone ();
                    rt.kind = pool[(uint) (w + h * 7) % pool.length];
                    cr.restore ();
                    draw_full (cr, rt, progress, from, to, w, h);
                    return;
                case TransitionKind.FALL_OVER:
                    paint (cr, to, 0, 0);
                    cr.save ();
                    double fall = p * Math.PI / 2;
                    cr.translate (tr.variant == 1 ? w : 0, h);
                    cr.scale (1, double.max (Math.cos (fall), 0.001));
                    cr.translate (-(tr.variant == 1 ? w : 0), -h);
                    paint (cr, from, 0, 0, 1 - p * 0.3);
                    cr.restore ();
                    break;
                case TransitionKind.DRAPE:
                case TransitionKind.CURTAINS:
                    paint (cr, to, 0, 0);
                    if (kind == TransitionKind.CURTAINS) {
                        for (int side2 = 0; side2 < 2; side2++) {
                            cr.save ();
                            cr.rectangle (side2 == 0 ? 0 : cx, 0, cx, h);
                            cr.clip ();
                            double sxk = 1 - p;
                            cr.translate (side2 == 0 ? 0 : w, 0);
                            cr.scale (double.max (sxk, 0.001), 1);
                            cr.translate (side2 == 0 ? 0 : -w, 0);
                            paint (cr, from, 0, 0);
                            cr.restore ();
                        }
                    } else {
                        cr.save ();
                        cr.translate (tr.variant == 1 ? 0 : w, 0);
                        cr.scale (double.max (1 - p, 0.001), 1);
                        cr.translate (tr.variant == 1 ? 0 : -w, 0);
                        paint (cr, from, 0, 0);
                        cr.restore ();
                    }
                    break;
                case TransitionKind.WIND:
                case TransitionKind.SHRED:
                case TransitionKind.FRACTURE:
                case TransitionKind.CRUSH:
                case TransitionKind.ORIGAMI:
                case TransitionKind.AIRPLANE:
                case TransitionKind.PRESTIGE:
                    paint (cr, to, 0, 0);
                    int pc = kind == TransitionKind.SHRED ? 24 : 12;
                    int pr = kind == TransitionKind.SHRED ? 1 : 8;
                    double pw = w / pc, ph = h / pr;
                    for (int r = 0; r < pr; r++) {
                        for (int c = 0; c < pc; c++) {
                            double delay = kind == TransitionKind.WIND ? (side > 0 ? (pc - c) : c) / (double) pc * 0.5 : (hash (c, r) % 1000) / 1000.0 * 0.5;
                            double q = ((progress - delay) / 0.5).clamp (0, 1);
                            if (q >= 1) continue;
                            cr.save ();
                            double px2 = c * pw, py2 = r * ph;
                            double mx = kind == TransitionKind.WIND || kind == TransitionKind.AIRPLANE ? -side * w * q : 0;
                            double my = kind == TransitionKind.SHRED ? h * q * ((c % 2 == 0) ? 1 : -1) : (kind == TransitionKind.WIND ? -h * 0.2 * q : h * q * q);
                            cr.translate (px2 + pw / 2 + mx, py2 + ph / 2 + my);
                            cr.rotate ((kind == TransitionKind.SHRED ? 0 : 1.5) * q * ((hash (r, c) % 2 == 0) ? 1 : -1));
                            double sc = kind == TransitionKind.CRUSH ? 1 - q * 0.7 : 1;
                            cr.scale (sc, sc);
                            cr.translate (-(px2 + pw / 2), -(py2 + ph / 2));
                            cr.rectangle (px2, py2, pw + 0.5, ph + 0.5);
                            cr.clip ();
                            paint (cr, from, 0, 0, 1 - q * 0.5);
                            cr.restore ();
                        }
                    }
                    break;
                case TransitionKind.PEEL_OFF:
                case TransitionKind.PAGE_CURL:
                    paint (cr, to, 0, 0);
                    cr.save ();
                    bool from_right = tr.variant % 2 == 0;
                    double edge = from_right ? w * (1 - p) : w * p;
                    if (from_right) cr.rectangle (0, 0, edge, h);
                    else cr.rectangle (edge, 0, w - edge, h);
                    cr.clip ();
                    paint (cr, from, 0, 0);
                    cr.restore ();
                    cr.save ();
                    double fold = double.min (w * p, w * 0.25) * 0.6;
                    var grad = new Cairo.Pattern.linear (edge, 0, edge + (from_right ? fold : -fold), 0);
                    grad.add_color_stop_rgba (0, 0.95, 0.95, 0.95, 1);
                    grad.add_color_stop_rgba (1, 0.6, 0.6, 0.6, 0.9);
                    if (from_right) cr.rectangle (edge, 0, fold, h);
                    else cr.rectangle (edge - fold, 0, fold, h);
                    cr.set_source (grad);
                    cr.fill ();
                    cr.restore ();
                    break;
                case TransitionKind.RIPPLE:
                    paint (cr, from, 0, 0);
                    cr.save ();
                    double rr = Math.sqrt (w * w + h * h) * p;
                    cr.arc (cx, cy, rr, 0, 2 * Math.PI);
                    cr.clip ();
                    paint (cr, to, 0, 0);
                    cr.restore ();
                    cr.set_line_width (6);
                    for (int i = 0; i < 3; i++) {
                        double ringr = rr - i * 18;
                        if (ringr <= 0) continue;
                        cr.arc (cx, cy, ringr, 0, 2 * Math.PI);
                        cr.set_source_rgba (1, 1, 1, 0.25 * (1 - p));
                        cr.stroke ();
                    }
                    break;
                case TransitionKind.HONEYCOMB:
                case TransitionKind.VORTEX:
                    paint (cr, to, 0, 0);
                    double hs = w / 14;
                    int hcols = (int) Math.ceil (w / (hs * 1.5)) + 1, hrows = (int) Math.ceil (h / (hs * 1.732)) + 2;
                    for (int r = 0; r < hrows; r++) {
                        for (int c = 0; c < hcols; c++) {
                            double hx = c * hs * 1.5, hy = r * hs * 1.732 + (c % 2) * hs * 0.866;
                            double dist = Math.hypot (hx - cx, hy - cy) / Math.hypot (cx, cy);
                            double delay = kind == TransitionKind.VORTEX ? dist * 0.5 : (hash (c, r) % 1000) / 1000.0 * 0.5;
                            double q = ((progress - delay) / 0.5).clamp (0, 1);
                            if (q >= 1) continue;
                            cr.save ();
                            if (kind == TransitionKind.VORTEX) {
                                cr.translate (cx, cy);
                                cr.rotate (q * 2 * side);
                                cr.translate (-cx, -cy);
                            }
                            double sc = 1 - q;
                            cr.translate (hx, hy);
                            cr.scale (sc, sc);
                            cr.translate (-hx, -hy);
                            for (int k = 0; k < 6; k++) {
                                double a2 = Math.PI / 3 * k;
                                if (k == 0) cr.move_to (hx + hs * Math.cos (a2), hy + hs * Math.sin (a2));
                                else cr.line_to (hx + hs * Math.cos (a2), hy + hs * Math.sin (a2));
                            }
                            cr.close_path ();
                            cr.clip ();
                            paint (cr, from, 0, 0);
                            cr.restore ();
                        }
                    }
                    break;
                case TransitionKind.SWITCH:
                case TransitionKind.FLIP:
                case TransitionKind.GALLERY:
                case TransitionKind.CUBE:
                case TransitionKind.BOX:
                case TransitionKind.ROTATE:
                case TransitionKind.ORBIT:
                case TransitionKind.FERRIS_WHEEL:
                case TransitionKind.CONVEYOR:
                    three_d (cr, kind, side, p, from, to, w, h);
                    break;
                case TransitionKind.DOORS:
                    paint_scaled (cr, to, w, h, cx, cy, 0.7 + 0.3 * p, 0.7 + 0.3 * p, 0, 1);
                    for (int side2 = 0; side2 < 2; side2++) {
                        cr.save ();
                        double open = double.max (Math.cos (p * Math.PI / 2), 0.001);
                        if (tr.variant == 1) {
                            cr.translate (0, side2 == 0 ? 0 : h);
                            cr.scale (1, open);
                            cr.translate (0, side2 == 0 ? 0 : -h);
                            cr.rectangle (0, side2 == 0 ? 0 : cy, w, cy);
                        } else {
                            cr.translate (side2 == 0 ? 0 : w, 0);
                            cr.scale (open, 1);
                            cr.translate (side2 == 0 ? 0 : -w, 0);
                            cr.rectangle (side2 == 0 ? 0 : cx, 0, cx, h);
                        }
                        cr.clip ();
                        paint (cr, from, 0, 0);
                        cr.restore ();
                    }
                    break;
                case TransitionKind.WINDOW:
                    paint (cr, from, 0, 0);
                    paint_scaled (cr, to, w, h, cx, cy, 0.5 + 0.5 * p, 0.5 + 0.5 * p, 0, p);
                    for (int side2 = 0; side2 < 2; side2++) {
                        cr.save ();
                        double open = double.max (1 - p, 0.001);
                        cr.translate (side2 == 0 ? 0 : w, 0);
                        cr.scale (open, 1);
                        cr.translate (side2 == 0 ? 0 : -w, 0);
                        cr.rectangle (side2 == 0 ? 0 : cx, 0, cx, h);
                        cr.clip ();
                        paint (cr, from, 0, 0);
                        cr.restore ();
                    }
                    break;
                default:
                    paint (cr, from, 0, 0);
                    paint (cr, to, 0, 0, progress);
                    break;
            }
            cr.restore ();
        }

        private static void face (Cairo.Context cr, Cairo.Surface s, double w, double h, double x0, double width, double shade) {
            if (width <= 0.5) return;
            cr.save ();
            cr.translate (x0, 0);
            cr.scale (width / w, 1);
            paint (cr, s, 0, 0);
            if (shade > 0) {
                cr.rectangle (0, 0, w, h);
                cr.set_source_rgba (0, 0, 0, shade);
                cr.fill ();
            }
            cr.restore ();
        }

        private static void three_d (Cairo.Context cr, TransitionKind kind, double side, double p, Cairo.Surface from, Cairo.Surface to, double w, double h) {
            double cx = w / 2, cy = h / 2;
            switch (kind) {
                case TransitionKind.CUBE:
                case TransitionKind.BOX:
                case TransitionKind.ROTATE:
                    double a = p * Math.PI / 2;
                    double fw = w * Math.cos (a), tw = w * Math.sin (a);
                    double depth = kind == TransitionKind.BOX ? 0.85 : 0.9;
                    double sc = kind == TransitionKind.ROTATE ? 1 : depth + (1 - depth) * Math.fabs (Math.cos (2 * a));
                    cr.save ();
                    cr.translate (cx, cy);
                    cr.scale (sc, sc);
                    cr.translate (-cx, -cy);
                    if (side > 0) {
                        face (cr, from, w, h, 0, fw, p * 0.5);
                        face (cr, to, w, h, fw, tw, (1 - p) * 0.5);
                    } else {
                        face (cr, to, w, h, 0, tw, (1 - p) * 0.5);
                        face (cr, from, w, h, tw, fw, p * 0.5);
                    }
                    cr.restore ();
                    break;
                case TransitionKind.FLIP:
                case TransitionKind.SWITCH:
                case TransitionKind.ORBIT:
                    bool first_half = p < 0.5;
                    double q = first_half ? p * 2 : (p - 0.5) * 2;
                    double sxk = first_half ? 1 - q : q;
                    double lift = kind == TransitionKind.ORBIT ? 0.2 * Math.sin (p * Math.PI) : 0;
                    double s2 = 1 - lift;
                    paint_scaled (cr, first_half ? from : to, w, h, cx, cy, sxk * s2, s2, 0, 1, (kind == TransitionKind.SWITCH ? side * w * 0.3 * Math.sin (p * Math.PI) : 0), 0);
                    break;
                case TransitionKind.GALLERY:
                case TransitionKind.CONVEYOR:
                    double s3 = 1 - 0.25 * Math.sin (p * Math.PI);
                    paint_scaled (cr, from, w, h, cx, cy, s3, s3, 0, 1, -side * w * p * 1.05, 0);
                    paint_scaled (cr, to, w, h, cx, cy, s3, s3, 0, 1, side * w * (1 - p) * 1.05, 0);
                    break;
                case TransitionKind.FERRIS_WHEEL:
                    double ang = p * Math.PI / 2 * side;
                    cr.save ();
                    cr.translate (cx, h * 2);
                    cr.rotate (-ang);
                    cr.translate (-cx, -h * 2);
                    paint (cr, from, 0, 0);
                    cr.restore ();
                    cr.save ();
                    cr.translate (cx, h * 2);
                    cr.rotate (Math.PI / 2 * side - ang);
                    cr.translate (-cx, -h * 2);
                    paint (cr, to, 0, 0);
                    cr.restore ();
                    break;
                default:
                    paint (cr, to, 0, 0);
                    break;
            }
        }
    }
}
