namespace Singularity.Apps.Slides {

    public enum Direction {
        FROM_LEFT,
        FROM_RIGHT,
        FROM_TOP,
        FROM_BOTTOM;

        public string label () {
            switch (this) {
                case FROM_LEFT: return _("From Left");
                case FROM_RIGHT: return _("From Right");
                case FROM_TOP: return _("From Top");
                default: return _("From Bottom");
            }
        }

        public string to_ooxml () {
            switch (this) {
                case FROM_LEFT: return "r";
                case FROM_RIGHT: return "l";
                case FROM_TOP: return "d";
                default: return "u";
            }
        }

        public static Direction from_ooxml (string? s, Direction fallback) {
            switch (s) {
                case "r": return FROM_LEFT;
                case "l": return FROM_RIGHT;
                case "d": return FROM_TOP;
                case "u": return FROM_BOTTOM;
                default: return fallback;
            }
        }

        public int to_subtype () {
            switch (this) {
                case FROM_LEFT: return 8;
                case FROM_RIGHT: return 2;
                case FROM_TOP: return 1;
                default: return 4;
            }
        }

        public static Direction from_subtype (int s, Direction fallback) {
            if ((s & 8) != 0) return FROM_LEFT;
            if ((s & 2) != 0) return FROM_RIGHT;
            if ((s & 1) != 0) return FROM_TOP;
            if ((s & 4) != 0) return FROM_BOTTOM;
            return fallback;
        }

        public void vector (out double dx, out double dy) {
            dx = 0;
            dy = 0;
            switch (this) {
                case FROM_LEFT: dx = -1; break;
                case FROM_RIGHT: dx = 1; break;
                case FROM_TOP: dy = -1; break;
                default: dy = 1; break;
            }
        }
    }

    public enum TransitionKind {
        NONE,
        FADE,
        FADE_BLACK,
        PUSH,
        WIPE,
        COVER,
        UNCOVER,
        SPLIT,
        ZOOM,
        DISSOLVE,
        CIRCLE,
        MORPH,
        REVEAL,
        CUT,
        RANDOM_BARS,
        FLASH,
        FALL_OVER,
        DRAPE,
        CURTAINS,
        WIND,
        PRESTIGE,
        FRACTURE,
        CRUSH,
        PEEL_OFF,
        PAGE_CURL,
        AIRPLANE,
        ORIGAMI,
        CHECKERBOARD,
        BLINDS,
        CLOCK,
        RIPPLE,
        HONEYCOMB,
        GLITTER,
        VORTEX,
        SHRED,
        SWITCH,
        FLIP,
        GALLERY,
        CUBE,
        DOORS,
        BOX,
        COMB,
        RANDOM,
        PAN,
        FERRIS_WHEEL,
        CONVEYOR,
        ROTATE,
        WINDOW,
        ORBIT,
        FLY_THROUGH,
        STRIPS,
        NEWSFLASH;

        public string label () {
            switch (this) {
                case FADE: return _("Fade");
                case FADE_BLACK: return _("Fade Through Black");
                case PUSH: return _("Push");
                case WIPE: return _("Wipe");
                case COVER: return _("Cover");
                case UNCOVER: return _("Uncover");
                case SPLIT: return _("Split");
                case ZOOM: return _("Zoom");
                case DISSOLVE: return _("Dissolve");
                case CIRCLE: return _("Shape");
                case MORPH: return _("Morph");
                case REVEAL: return _("Reveal");
                case CUT: return _("Cut");
                case RANDOM_BARS: return _("Random Bars");
                case FLASH: return _("Flash");
                case FALL_OVER: return _("Fall Over");
                case DRAPE: return _("Drape");
                case CURTAINS: return _("Curtains");
                case WIND: return _("Wind");
                case PRESTIGE: return _("Prestige");
                case FRACTURE: return _("Fracture");
                case CRUSH: return _("Crush");
                case PEEL_OFF: return _("Peel Off");
                case PAGE_CURL: return _("Page Curl");
                case AIRPLANE: return _("Airplane");
                case ORIGAMI: return _("Origami");
                case CHECKERBOARD: return _("Checkerboard");
                case BLINDS: return _("Blinds");
                case CLOCK: return _("Clock");
                case RIPPLE: return _("Ripple");
                case HONEYCOMB: return _("Honeycomb");
                case GLITTER: return _("Glitter");
                case VORTEX: return _("Vortex");
                case SHRED: return _("Shred");
                case SWITCH: return _("Switch");
                case FLIP: return _("Flip");
                case GALLERY: return _("Gallery");
                case CUBE: return _("Cube");
                case DOORS: return _("Doors");
                case BOX: return _("Box");
                case COMB: return _("Comb");
                case RANDOM: return _("Random");
                case PAN: return _("Pan");
                case FERRIS_WHEEL: return _("Ferris Wheel");
                case CONVEYOR: return _("Conveyor");
                case ROTATE: return _("Rotate");
                case WINDOW: return _("Window");
                case ORBIT: return _("Orbit");
                case FLY_THROUGH: return _("Fly Through");
                case STRIPS: return _("Strips");
                case NEWSFLASH: return _("Newsflash");
                default: return _("None");
            }
        }

        public bool has_direction () {
            var o = TransitionCatalog.options (this);
            return o == TransitionOptions.DIR4 || o == TransitionOptions.DIR8;
        }

        public const TransitionKind[] ALL = {
            NONE, MORPH, FADE, PUSH, WIPE, SPLIT, REVEAL, CUT, RANDOM_BARS, CIRCLE, UNCOVER, COVER, FLASH,
            FALL_OVER, DRAPE, CURTAINS, WIND, PRESTIGE, FRACTURE, CRUSH, PEEL_OFF, PAGE_CURL, AIRPLANE, ORIGAMI,
            DISSOLVE, CHECKERBOARD, BLINDS, CLOCK, RIPPLE, HONEYCOMB, GLITTER, VORTEX, SHRED, SWITCH, FLIP,
            GALLERY, CUBE, DOORS, BOX, COMB, ZOOM, RANDOM, PAN, FERRIS_WHEEL, CONVEYOR, ROTATE, WINDOW, ORBIT,
            FLY_THROUGH, STRIPS, NEWSFLASH, FADE_BLACK
        };
    }

    public class Transition {
        public TransitionKind kind = TransitionKind.NONE;
        public int subtype = 2;
        public int variant = 0;
        public double duration = 0.7;
        public bool on_click = true;
        public double advance_after = -1;
        public string sound = "";
        public Bytes? sound_data = null;
        public bool sound_loop = false;

        public Direction direction {
            get { return Direction.from_subtype (subtype, Direction.FROM_RIGHT); }
            set { subtype = value.to_subtype (); }
        }

        public Transition clone () {
            var t = new Transition ();
            t.kind = kind;
            t.subtype = subtype;
            t.variant = variant;
            t.duration = duration;
            t.on_click = on_click;
            t.advance_after = advance_after;
            t.sound = sound;
            t.sound_data = sound_data;
            t.sound_loop = sound_loop;
            return t;
        }
    }

    public enum AnimClass {
        ENTRANCE,
        EMPHASIS,
        EXIT,
        PATH,
        MEDIA;

        public string label () {
            switch (this) {
                case EMPHASIS: return _("Emphasis");
                case EXIT: return _("Exit");
                case PATH: return _("Motion Path");
                case MEDIA: return _("Media");
                default: return _("Entrance");
            }
        }

        public string to_ooxml () {
            switch (this) {
                case EMPHASIS: return "emph";
                case EXIT: return "exit";
                case PATH: return "path";
                case MEDIA: return "mediacall";
                default: return "entr";
            }
        }
    }

    public enum AnimTrigger {
        ON_CLICK,
        WITH_PREVIOUS,
        AFTER_PREVIOUS;

        public string label () {
            switch (this) {
                case WITH_PREVIOUS: return _("With Previous");
                case AFTER_PREVIOUS: return _("After Previous");
                default: return _("On Click");
            }
        }
    }

    public class Animation {
        public int target = 0;
        public AnimClass anim_class = AnimClass.ENTRANCE;
        public AnimEffect effect = AnimEffect.FADE;
        public int subtype = 4;
        public AnimTrigger trigger = AnimTrigger.ON_CLICK;
        public double duration = 0.5;
        public double delay = 0;
        public double amount = 0;
        public string color = "";
        public Gee.ArrayList<PathCommand> path = new Gee.ArrayList<PathCommand> ();
        public MotionPreset path_preset = MotionPreset.CUSTOM;
        public bool path_rotate = false;
        public int trigger_shape = -1;
        public string trigger_bookmark = "";
        public double repeat = 1;
        public bool rewind = false;
        public bool auto_reverse = false;
        public double accel = 0;
        public double decel = 0;
        public AfterEffect after = AfterEffect.NONE;
        public string dim_color = "";
        public TextBuild text_build = TextBuild.AS_ONE;
        public int build_level = 1;
        public TextUnit text_unit = TextUnit.ALL;
        public double unit_delay = 0.1;
        public int paragraph = -1;
        public string sound = "";
        public Bytes? sound_data = null;
        public string raw = "";
        public string raw_sig = "";

        public Direction direction {
            get { return Direction.from_subtype (subtype, Direction.FROM_BOTTOM); }
            set { subtype = value.to_subtype (); }
        }

        public Animation (int target) {
            this.target = target;
        }

        public Animation clone () {
            var a = new Animation (target);
            a.anim_class = anim_class;
            a.effect = effect;
            a.subtype = subtype;
            a.trigger = trigger;
            a.duration = duration;
            a.delay = delay;
            a.amount = amount;
            a.color = color;
            foreach (var c in path) a.path.add (new PathCommand (c.op, c.pts));
            a.path_preset = path_preset;
            a.path_rotate = path_rotate;
            a.trigger_shape = trigger_shape;
            a.trigger_bookmark = trigger_bookmark;
            a.repeat = repeat;
            a.rewind = rewind;
            a.auto_reverse = auto_reverse;
            a.accel = accel;
            a.decel = decel;
            a.after = after;
            a.dim_color = dim_color;
            a.text_build = text_build;
            a.build_level = build_level;
            a.text_unit = text_unit;
            a.unit_delay = unit_delay;
            a.paragraph = paragraph;
            a.sound = sound;
            a.sound_data = sound_data;
            a.raw = raw;
            a.raw_sig = raw_sig;
            return a;
        }

        public string signature () {
            var sb = new StringBuilder ();
            sb.append ("%d|%d|%d|%d|%g|%g|%g|%s|%d|%g|%s|%s|%d|%d|%g|%g|%s|%d".printf ((int) anim_class, (int) effect, subtype, (int) trigger, duration, delay, amount, color,
                trigger_shape, repeat, rewind.to_string (), auto_reverse.to_string (), (int) after, (int) text_build, accel, decel, sound, paragraph));
            foreach (var c in path) {
                sb.append_c (c.op);
                foreach (double v in c.pts) sb.append ("%.5f,".printf (v));
            }
            return sb.str;
        }

        public void set_effect (AnimEffect e) {
            effect = e;
            var o = EffectCatalog.options (e);
            var vals = EffectCatalog.option_values (o);
            bool ok = false;
            foreach (int v in vals) if (v == subtype) ok = true;
            if (!ok) subtype = EffectCatalog.default_subtype (e);
            if (o == EffectOptions.SPIN && amount == 0) amount = 360;
            if (o == EffectOptions.SCALE && amount == 0) amount = 1.5;
            if (o == EffectOptions.ALPHA && amount == 0) amount = 0.5;
            if (o == EffectOptions.COLOR && color == "") color = "accent2";
        }

        public string label () {
            if (effect == AnimEffect.MOTION_PATH && path_preset != MotionPreset.CUSTOM) return path_preset.label ();
            return effect.label (anim_class);
        }
    }
    public enum LayoutKind {
        TITLE,
        TITLE_CONTENT,
        SECTION,
        TWO_CONTENT,
        COMPARISON,
        TITLE_ONLY,
        BLANK,
        CONTENT_CAPTION,
        PICTURE_CAPTION,
        QUOTE,
        BIG_NUMBER,
        CUSTOM;

        public string to_ooxml () {
            switch (this) {
                case TITLE: return "title";
                case TITLE_CONTENT: return "obj";
                case SECTION: return "secHead";
                case TWO_CONTENT: return "twoObj";
                case COMPARISON: return "twoTxTwoObj";
                case TITLE_ONLY: return "titleOnly";
                case BLANK: return "blank";
                case CONTENT_CAPTION: return "objTx";
                case PICTURE_CAPTION: return "picTx";
                default: return "cust";
            }
        }

        public static LayoutKind from_ooxml (string? s) {
            switch (s) {
                case "title": return TITLE;
                case "obj": case "tx": return TITLE_CONTENT;
                case "secHead": return SECTION;
                case "twoObj": case "twoColTx": return TWO_CONTENT;
                case "twoTxTwoObj": return COMPARISON;
                case "titleOnly": return TITLE_ONLY;
                case "blank": return BLANK;
                case "objTx": return CONTENT_CAPTION;
                case "picTx": return PICTURE_CAPTION;
                default: return CUSTOM;
            }
        }
    }

    public class Layout {
        public string id = "";
        public string name = "";
        public LayoutKind kind = LayoutKind.CUSTOM;
        public Gee.ArrayList<Element> elements = new Gee.ArrayList<Element> ();
        public Fill? background = null;
        public bool show_master_shapes = true;

        public Layout clone () {
            var l = new Layout ();
            l.id = id;
            l.name = name;
            l.kind = kind;
            foreach (var e in elements) l.elements.add (e.clone ());
            l.background = background != null ? background.clone () : null;
            l.show_master_shapes = show_master_shapes;
            return l;
        }

        public Element? find_placeholder (PlaceholderKind k, int idx) {
            if (k == PlaceholderKind.NONE) return null;
            if (idx >= 0) {
                foreach (var e in elements) if (e.placeholder != PlaceholderKind.NONE && e.placeholder_idx == idx && e.placeholder.matches (k)) return e;
            }
            foreach (var e in elements) if (e.placeholder == k && (idx < 0 || e.placeholder_idx < 0 || e.placeholder_idx == idx)) return e;
            if (!k.is_meta () && idx >= 0) {
                foreach (var e in elements) if (e.placeholder_idx == idx && !e.placeholder.is_meta ()) return e;
            }
            foreach (var e in elements) if (e.placeholder.matches (k) && (k.is_title () || idx < 0)) return e;
            return null;
        }
    }

    public class Master {
        public string id = "";
        public string name = "";
        public Theme theme = new Theme ();
        public Gee.ArrayList<Element> elements = new Gee.ArrayList<Element> ();
        public Fill background = new Fill.solid ("lt1");
        public TextStyle title_style = new TextStyle ();
        public TextStyle body_style = new TextStyle ();
        public TextStyle other_style = new TextStyle ();
        public Gee.ArrayList<Layout> layouts = new Gee.ArrayList<Layout> ();

        public Master clone () {
            var m = new Master ();
            m.id = id;
            m.name = name;
            m.theme = theme.clone ();
            foreach (var e in elements) m.elements.add (e.clone ());
            m.background = background.clone ();
            m.title_style = title_style.clone ();
            m.body_style = body_style.clone ();
            m.other_style = other_style.clone ();
            foreach (var l in layouts) m.layouts.add (l.clone ());
            return m;
        }

        public Element? find_placeholder (PlaceholderKind k) {
            foreach (var e in elements) if (e.placeholder == k) return e;
            foreach (var e in elements) if (e.placeholder.matches (k)) return e;
            if (k == PlaceholderKind.OBJECT || k == PlaceholderKind.PICTURE || k == PlaceholderKind.SUBTITLE) {
                foreach (var e in elements) if (e.placeholder == PlaceholderKind.BODY) return e;
            }
            return null;
        }

        public Layout? find_layout (string id) {
            foreach (var l in layouts) if (l.id == id) return l;
            return null;
        }

        public Layout? layout_of_kind (LayoutKind k) {
            foreach (var l in layouts) if (l.kind == k) return l;
            return null;
        }
    }

    public class Slide {
        public Gee.ArrayList<Element> elements = new Gee.ArrayList<Element> ();
        public string layout_id = "";
        public Fill? background = null;
        public Transition transition = new Transition ();
        public Gee.ArrayList<Animation> animations = new Gee.ArrayList<Animation> ();
        public string notes = "";
        public bool hidden = false;
        public bool show_master_shapes = true;
        public string name = "";
        public int uid = 0;
        public SectionMark? section = null;
        public Gee.ArrayList<Comment> comments = new Gee.ArrayList<Comment> ();
        public Gee.ArrayList<ForeignElement> extras = new Gee.ArrayList<ForeignElement> ();

        private static int uid_counter = 0;

        public Slide () {
            uid = ++uid_counter;
        }

        public static void reserve_uid (int u) {
            if (u > uid_counter) uid_counter = u;
        }

        public Slide duplicate () {
            var s = clone ();
            s.uid = ++uid_counter;
            s.section = null;
            s.comments.clear ();
            return s;
        }

        public Slide clone () {
            var s = new Slide ();
            s.uid = uid;
            s.section = section != null ? section.clone () : null;
            foreach (var c in comments) s.comments.add (c.clone ());
            s.extras.add_all (extras);
            foreach (var e in elements) s.elements.add (e.clone ());
            s.layout_id = layout_id;
            s.background = background != null ? background.clone () : null;
            s.transition = transition.clone ();
            foreach (var a in animations) s.animations.add (a.clone ());
            s.notes = notes;
            s.hidden = hidden;
            s.show_master_shapes = show_master_shapes;
            s.name = name;
            return s;
        }

        public Element? find (int id) {
            foreach (var e in elements) {
                if (e.id == id) return e;
                var g = e as GroupElement;
                if (g != null) {
                    var inner = find_in (g, id);
                    if (inner != null) return inner;
                }
            }
            return null;
        }

        private static Element? find_in (GroupElement g, int id) {
            foreach (var c in g.children) {
                if (c.id == id) return c;
                var gg = c as GroupElement;
                if (gg != null) {
                    var inner = find_in (gg, id);
                    if (inner != null) return inner;
                }
            }
            return null;
        }

        public Element? placeholder (PlaceholderKind k) {
            foreach (var e in elements) if (e.placeholder == k) return e;
            foreach (var e in elements) if (e.placeholder.matches (k)) return e;
            return null;
        }

        public string title () {
            var t = placeholder (PlaceholderKind.TITLE);
            if (t != null && t.text_body () != null) {
                string s = t.text_body ().plain_text ().replace ("\n", " ").strip ();
                if (s != "") return s;
            }
            return "";
        }

        public Gee.ArrayList<Animation> animations_for (int id) {
            var list = new Gee.ArrayList<Animation> ();
            foreach (var a in animations) if (a.target == id) list.add (a);
            return list;
        }

        public void remove_animations_for (int id) {
            for (int i = animations.size - 1; i >= 0; i--) if (animations[i].target == id) animations.remove_at (i);
        }

        public int click_count () {
            int n = 0;
            for (int i = 0; i < animations.size; i++) {
                if (animations[i].trigger == AnimTrigger.ON_CLICK) n++;
            }
            return n;
        }
    }
}
