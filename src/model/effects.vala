namespace Singularity.Apps.Slides {

    public enum EffectOptions {
        NONE,
        DIR4,
        DIR8,
        IN_OUT,
        SPLIT,
        ORIENT,
        SPOKES,
        STRIPS,
        SHAPE,
        SPIN,
        SCALE,
        ALPHA,
        COLOR,
        PATH
    }

    public enum AnimEffect {
        APPEAR,
        FADE,
        FLY,
        ZOOM,
        WIPE,
        FLOAT,
        SPIN,
        PULSE,
        GROW,
        BLINDS,
        BOX,
        CHECKERBOARD,
        CIRCLE,
        CRAWL,
        DIAMOND,
        DISSOLVE,
        FLASH_ONCE,
        PEEK,
        PLUS,
        RANDOM_BARS,
        SPIRAL,
        SPLIT,
        STRETCH,
        STRIPS,
        SWIVEL,
        WEDGE,
        WHEEL,
        BASIC_ZOOM,
        BOOMERANG,
        BOUNCE,
        CREDITS,
        EASE_IN,
        GROW_TURN,
        LIGHT_SPEED,
        PINWHEEL,
        RISE_UP,
        SWISH,
        THIN_LINE,
        UNFOLD,
        WHIP,
        CENTER_REVOLVE,
        FADE_SWIVEL,
        SLING,
        SPINNER,
        COMPRESS,
        ZIP,
        ARC_UP,
        GLIDE,
        EXPAND,
        FLIP,
        FOLD,
        COLOR_PULSE,
        TEETER,
        TRANSPARENCY,
        FILL_COLOR,
        LINE_COLOR,
        FONT_COLOR,
        OBJECT_COLOR,
        COMPLEMENTARY,
        CONTRASTING,
        DARKEN,
        LIGHTEN,
        DESATURATE,
        BOLD_FLASH,
        BOLD_REVEAL,
        UNDERLINE,
        WAVE,
        BLINK,
        FLICKER,
        GROW_COLOR,
        SHIMMER,
        MOTION_PATH,
        MEDIA_PLAY,
        MEDIA_PAUSE,
        MEDIA_STOP;

        public string label (AnimClass cls) {
            return EffectCatalog.label (this, cls);
        }

        public int preset_id () {
            return EffectCatalog.preset_id (this, AnimClass.ENTRANCE);
        }

        public static AnimEffect from_preset (string cls, int id) {
            return EffectCatalog.from_preset (cls, id);
        }

        public bool has_direction () {
            var o = EffectCatalog.options (this);
            return o == EffectOptions.DIR4 || o == EffectOptions.DIR8;
        }

        public bool is_emphasis () {
            return EffectCatalog.emphasis_only (this);
        }

        public bool is_media () {
            return this == MEDIA_PLAY || this == MEDIA_PAUSE || this == MEDIA_STOP;
        }

        public const AnimEffect[] ENTRANCE = {
            APPEAR, FADE, FLY, FLOAT, SPLIT, WIPE, CIRCLE, WHEEL, RANDOM_BARS, GROW_TURN, ZOOM, SWIVEL, BOUNCE,
            BLINDS, BOX, CHECKERBOARD, CRAWL, DIAMOND, DISSOLVE, FLASH_ONCE, PEEK, PLUS, STRIPS, WEDGE, BASIC_ZOOM,
            EXPAND, FADE_SWIVEL, COMPRESS, CENTER_REVOLVE, RISE_UP, STRETCH, SPINNER, UNFOLD, BOOMERANG,
            CREDITS, EASE_IN, FLIP, FOLD, GLIDE, LIGHT_SPEED, PINWHEEL, SLING, SPIRAL, SWISH, THIN_LINE, WHIP, ZIP, ARC_UP
        };

        public const AnimEffect[] EMPHASIS = {
            PULSE, COLOR_PULSE, TEETER, SPIN, GROW, DESATURATE, DARKEN, LIGHTEN, TRANSPARENCY, OBJECT_COLOR,
            COMPLEMENTARY, LINE_COLOR, FILL_COLOR, FONT_COLOR, UNDERLINE, BOLD_FLASH, BOLD_REVEAL, WAVE,
            CONTRASTING, BLINK, FLICKER, GROW_COLOR, SHIMMER
        };
    }

    public enum AfterEffect {
        NONE,
        HIDE,
        HIDE_ON_CLICK,
        DIM;

        public string label () {
            switch (this) {
                case HIDE: return _("Hide After Animation");
                case HIDE_ON_CLICK: return _("Hide on Next Click");
                case DIM: return _("Dim to Color");
                default: return _("Don't Dim");
            }
        }
    }

    public enum TextBuild {
        AS_ONE,
        ALL_AT_ONCE,
        BY_PARAGRAPH;

        public string label () {
            switch (this) {
                case ALL_AT_ONCE: return _("All at Once");
                case BY_PARAGRAPH: return _("By Paragraph");
                default: return _("As One Object");
            }
        }
    }

    public enum TextUnit {
        ALL,
        WORD,
        LETTER;

        public string label () {
            switch (this) {
                case WORD: return _("By Word");
                case LETTER: return _("By Letter");
                default: return _("All at Once");
            }
        }
    }

    public enum MotionPreset {
        CUSTOM,
        LINE_DOWN,
        LINE_UP,
        LINE_LEFT,
        LINE_RIGHT,
        DIAGONAL_DOWN_RIGHT,
        DIAGONAL_UP_RIGHT,
        ARC_DOWN,
        ARC_UP,
        ARC_LEFT,
        ARC_RIGHT,
        TURN_DOWN,
        TURN_UP,
        TURN_DOWN_RIGHT,
        TURN_UP_RIGHT,
        CIRCLE,
        SQUARE,
        TRIANGLE,
        DIAMOND,
        HEXAGON,
        OCTAGON,
        PENTAGON,
        STAR5,
        HEART,
        TEARDROP,
        LOOP,
        S_CURVE,
        SINE_WAVE,
        ZIGZAG,
        SPIRAL,
        BOUNCE,
        STAIRS,
        FIGURE8;

        public string label () {
            switch (this) {
                case LINE_DOWN: return _("Down");
                case LINE_UP: return _("Up");
                case LINE_LEFT: return _("Left");
                case LINE_RIGHT: return _("Right");
                case DIAGONAL_DOWN_RIGHT: return _("Diagonal Down Right");
                case DIAGONAL_UP_RIGHT: return _("Diagonal Up Right");
                case ARC_DOWN: return _("Arc Down");
                case ARC_UP: return _("Arc Up");
                case ARC_LEFT: return _("Arc Left");
                case ARC_RIGHT: return _("Arc Right");
                case TURN_DOWN: return _("Turn Down");
                case TURN_UP: return _("Turn Up");
                case TURN_DOWN_RIGHT: return _("Turn Down Right");
                case TURN_UP_RIGHT: return _("Turn Up Right");
                case CIRCLE: return _("Circle");
                case SQUARE: return _("Square");
                case TRIANGLE: return _("Triangle");
                case DIAMOND: return _("Diamond");
                case HEXAGON: return _("Hexagon");
                case OCTAGON: return _("Octagon");
                case PENTAGON: return _("Pentagon");
                case STAR5: return _("5-Point Star");
                case HEART: return _("Heart");
                case TEARDROP: return _("Teardrop");
                case LOOP: return _("Loop de Loop");
                case S_CURVE: return _("S Curve");
                case SINE_WAVE: return _("Sine Wave");
                case ZIGZAG: return _("Zigzag");
                case SPIRAL: return _("Spiral");
                case BOUNCE: return _("Bounce");
                case STAIRS: return _("Stairs Down");
                case FIGURE8: return _("Figure 8");
                default: return _("Custom Path");
            }
        }

        public int preset_id () {
            switch (this) {
                case LINE_DOWN: return 42;
                case LINE_UP: return 64;
                case LINE_LEFT: return 35;
                case LINE_RIGHT: return 63;
                case DIAGONAL_DOWN_RIGHT: return 17;
                case DIAGONAL_UP_RIGHT: return 18;
                case ARC_DOWN: return 37;
                case ARC_UP: return 47;
                case ARC_LEFT: return 51;
                case ARC_RIGHT: return 58;
                case TURN_DOWN: return 44;
                case TURN_UP: return 50;
                case TURN_DOWN_RIGHT: return 45;
                case TURN_UP_RIGHT: return 57;
                case CIRCLE: return 1;
                case SQUARE: return 2;
                case TRIANGLE: return 3;
                case DIAMOND: return 4;
                case HEXAGON: return 5;
                case OCTAGON: return 6;
                case PENTAGON: return 7;
                case STAR5: return 16;
                case HEART: return 9;
                case TEARDROP: return 10;
                case LOOP: return 26;
                case S_CURVE: return 28;
                case SINE_WAVE: return 30;
                case ZIGZAG: return 33;
                case SPIRAL: return 29;
                case BOUNCE: return 41;
                case STAIRS: return 61;
                case FIGURE8: return 25;
                default: return 0;
            }
        }

        public static MotionPreset from_preset (int id) {
            foreach (var m in ALL) if (m.preset_id () == id && m != CUSTOM) return m;
            return CUSTOM;
        }

        public const MotionPreset[] ALL = {
            LINE_DOWN, LINE_UP, LINE_LEFT, LINE_RIGHT, DIAGONAL_DOWN_RIGHT, DIAGONAL_UP_RIGHT, ARC_DOWN, ARC_UP, ARC_LEFT, ARC_RIGHT,
            TURN_DOWN, TURN_UP, TURN_DOWN_RIGHT, TURN_UP_RIGHT, CIRCLE, SQUARE, TRIANGLE, DIAMOND, HEXAGON, OCTAGON, PENTAGON,
            STAR5, HEART, TEARDROP, LOOP, S_CURVE, SINE_WAVE, ZIGZAG, SPIRAL, BOUNCE, STAIRS, FIGURE8, CUSTOM
        };

        private static void polygon (Gee.List<PathCommand> p, double sx, double sy, int n, double r, double rot) {
            double cx = 0, cy = -r;
            double a0 = -Math.PI / 2 + rot;
            double fx = cx + r * Math.cos (a0), fy = cy + r * Math.sin (a0) + r;
            for (int i = 1; i <= n; i++) {
                double a = a0 + 2 * Math.PI * i / n;
                p.add (new PathCommand ('L', { (cx + r * Math.cos (a) - fx) * sx, (cy + r * Math.sin (a) + r - fy) * sy }));
            }
        }

        public Gee.ArrayList<PathCommand> build (double aspect) {
            var p = new Gee.ArrayList<PathCommand> ();
            double sx = 1, sy = aspect;
            p.add (new PathCommand ('M', { 0, 0 }));
            switch (this) {
                case LINE_DOWN: p.add (new PathCommand ('L', { 0, 0.25 })); break;
                case LINE_UP: p.add (new PathCommand ('L', { 0, -0.25 })); break;
                case LINE_LEFT: p.add (new PathCommand ('L', { -0.25, 0 })); break;
                case LINE_RIGHT: p.add (new PathCommand ('L', { 0.25, 0 })); break;
                case DIAGONAL_DOWN_RIGHT: p.add (new PathCommand ('L', { 0.2, 0.2 * sy })); break;
                case DIAGONAL_UP_RIGHT: p.add (new PathCommand ('L', { 0.2, -0.2 * sy })); break;
                case ARC_DOWN: p.add (new PathCommand ('C', { 0.04, 0.14 * sy, 0.2, 0.14 * sy, 0.24, 0 })); break;
                case ARC_UP: p.add (new PathCommand ('C', { 0.04, -0.14 * sy, 0.2, -0.14 * sy, 0.24, 0 })); break;
                case ARC_LEFT: p.add (new PathCommand ('C', { -0.14, 0.04 * sy, -0.14, 0.2 * sy, 0, 0.24 * sy })); break;
                case ARC_RIGHT: p.add (new PathCommand ('C', { 0.14, 0.04 * sy, 0.14, 0.2 * sy, 0, 0.24 * sy })); break;
                case TURN_DOWN: p.add (new PathCommand ('C', { 0.12, 0, 0.18, 0.04 * sy, 0.18, 0.2 * sy })); break;
                case TURN_UP: p.add (new PathCommand ('C', { 0.12, 0, 0.18, -0.04 * sy, 0.18, -0.2 * sy })); break;
                case TURN_DOWN_RIGHT: p.add (new PathCommand ('C', { 0, 0.12 * sy, 0.04, 0.18 * sy, 0.2, 0.18 * sy })); break;
                case TURN_UP_RIGHT: p.add (new PathCommand ('C', { 0, -0.12 * sy, 0.04, -0.18 * sy, 0.2, -0.18 * sy })); break;
                case CIRCLE:
                    double k = 0.5523;
                    double r = 0.1;
                    p.add (new PathCommand ('C', { r * k, 0, r, (r - r * k) * sy, r, r * sy }));
                    p.add (new PathCommand ('C', { r, (r + r * k) * sy, r * k, 2 * r * sy, 0, 2 * r * sy }));
                    p.add (new PathCommand ('C', { -r * k, 2 * r * sy, -r, (r + r * k) * sy, -r, r * sy }));
                    p.add (new PathCommand ('C', { -r, (r - r * k) * sy, -r * k, 0, 0, 0 }));
                    break;
                case SQUARE:
                    p.add (new PathCommand ('L', { 0.1, 0 }));
                    p.add (new PathCommand ('L', { 0.1, 0.2 * sy }));
                    p.add (new PathCommand ('L', { -0.1, 0.2 * sy }));
                    p.add (new PathCommand ('L', { -0.1, 0 }));
                    p.add (new PathCommand ('L', { 0, 0 }));
                    break;
                case TRIANGLE: polygon (p, sx, sy, 3, 0.11, 0); break;
                case DIAMOND: polygon (p, sx, sy, 4, 0.11, 0); break;
                case HEXAGON: polygon (p, sx, sy, 6, 0.11, 0); break;
                case OCTAGON: polygon (p, sx, sy, 8, 0.11, 0); break;
                case PENTAGON: polygon (p, sx, sy, 5, 0.11, 0); break;
                case STAR5:
                    for (int i = 1; i <= 10; i++) {
                        double a = -Math.PI / 2 + i * Math.PI / 5;
                        double rr = i % 2 == 0 ? 0.11 : 0.045;
                        p.add (new PathCommand ('L', { rr * Math.cos (a), (rr * Math.sin (a) + 0.11) * sy }));
                    }
                    break;
                case HEART:
                    p.add (new PathCommand ('C', { 0.02, -0.06 * sy, 0.12, -0.04 * sy, 0.1, 0.04 * sy }));
                    p.add (new PathCommand ('C', { 0.08, 0.1 * sy, 0.02, 0.14 * sy, 0, 0.18 * sy }));
                    p.add (new PathCommand ('C', { -0.02, 0.14 * sy, -0.08, 0.1 * sy, -0.1, 0.04 * sy }));
                    p.add (new PathCommand ('C', { -0.12, -0.04 * sy, -0.02, -0.06 * sy, 0, 0 }));
                    break;
                case TEARDROP:
                    p.add (new PathCommand ('C', { 0.08, 0.06 * sy, 0.1, 0.2 * sy, 0, 0.2 * sy }));
                    p.add (new PathCommand ('C', { -0.1, 0.2 * sy, -0.08, 0.06 * sy, 0, 0 }));
                    break;
                case LOOP:
                    p.add (new PathCommand ('C', { 0.1, 0, 0.14, -0.1 * sy, 0.08, -0.12 * sy }));
                    p.add (new PathCommand ('C', { 0.02, -0.14 * sy, 0.02, 0, 0.12, 0 }));
                    p.add (new PathCommand ('L', { 0.24, 0 }));
                    break;
                case S_CURVE:
                    p.add (new PathCommand ('C', { 0.08, 0, 0.08, 0.1 * sy, 0, 0.1 * sy }));
                    p.add (new PathCommand ('C', { -0.08, 0.1 * sy, -0.08, 0.2 * sy, 0, 0.2 * sy }));
                    break;
                case SINE_WAVE:
                    for (int i = 0; i < 4; i++) {
                        double x0 = i * 0.06;
                        double dir = i % 2 == 0 ? -1 : 1;
                        p.add (new PathCommand ('C', { x0 + 0.02, dir * 0.06 * sy, x0 + 0.04, dir * 0.06 * sy, x0 + 0.06, 0 }));
                    }
                    break;
                case ZIGZAG:
                    for (int i = 1; i <= 6; i++) p.add (new PathCommand ('L', { i * 0.04, (i % 2 == 1 ? -0.04 : 0) * sy }));
                    break;
                case SPIRAL:
                    for (int i = 1; i <= 48; i++) {
                        double a = i * Math.PI / 8;
                        double rr = 0.004 * i;
                        p.add (new PathCommand ('L', { rr * Math.sin (a), (rr * -Math.cos (a) + 0.004 * i * 0.2) * sy }));
                    }
                    break;
                case BOUNCE:
                    for (int i = 0; i < 3; i++) {
                        double x0 = i * 0.08, hgt = 0.16 / (i + 1);
                        p.add (new PathCommand ('C', { x0 + 0.02, -hgt * sy, x0 + 0.06, -hgt * sy, x0 + 0.08, 0 }));
                    }
                    break;
                case STAIRS:
                    for (int i = 1; i <= 4; i++) {
                        p.add (new PathCommand ('L', { i * 0.05, (i - 1) * 0.05 * sy }));
                        p.add (new PathCommand ('L', { i * 0.05, i * 0.05 * sy }));
                    }
                    break;
                case FIGURE8:
                    p.add (new PathCommand ('C', { 0.08, 0, 0.08, 0.1 * sy, 0, 0.1 * sy }));
                    p.add (new PathCommand ('C', { -0.08, 0.1 * sy, -0.08, 0.2 * sy, 0, 0.2 * sy }));
                    p.add (new PathCommand ('C', { 0.08, 0.2 * sy, 0.08, 0.1 * sy, 0, 0.1 * sy }));
                    p.add (new PathCommand ('C', { -0.08, 0.1 * sy, -0.08, 0, 0, 0 }));
                    break;
                default:
                    p.add (new PathCommand ('L', { 0.2, 0 }));
                    break;
            }
            return p;
        }
    }

    public class EffectCatalog {
        private class Info {
            public AnimEffect effect;
            public int entr;
            public int emph;
            public EffectOptions options;
            public int default_sub;
            public string odp;

            public Info (AnimEffect effect, int entr, int emph, EffectOptions options, int default_sub, string odp) {
                this.effect = effect;
                this.entr = entr;
                this.emph = emph;
                this.options = options;
                this.default_sub = default_sub;
                this.odp = odp;
            }
        }

        private static Gee.HashMap<int, Info>? table = null;

        private static void add (AnimEffect e, int entr, int emph, EffectOptions o, int sub, string odp) {
            table[(int) e] = new Info (e, entr, emph, o, sub, odp);
        }

        private static Gee.HashMap<int, Info> all () {
            if (table != null) return table;
            table = new Gee.HashMap<int, Info> ();
            add (AnimEffect.APPEAR, 1, -1, EffectOptions.NONE, 0, "appear");
            add (AnimEffect.FLY, 2, -1, EffectOptions.DIR8, 4, "fly-in");
            add (AnimEffect.BLINDS, 3, -1, EffectOptions.ORIENT, 10, "venetian-blinds");
            add (AnimEffect.BOX, 4, -1, EffectOptions.IN_OUT, 16, "box");
            add (AnimEffect.CHECKERBOARD, 5, -1, EffectOptions.ORIENT, 10, "checkerboard");
            add (AnimEffect.CIRCLE, 6, -1, EffectOptions.IN_OUT, 16, "circle");
            add (AnimEffect.CRAWL, 7, -1, EffectOptions.DIR4, 4, "fly-in-slow");
            add (AnimEffect.DIAMOND, 8, -1, EffectOptions.IN_OUT, 16, "diamond");
            add (AnimEffect.DISSOLVE, 9, -1, EffectOptions.NONE, 0, "dissolve-in");
            add (AnimEffect.FADE, 10, -1, EffectOptions.NONE, 0, "fade-in");
            add (AnimEffect.FLASH_ONCE, 11, -1, EffectOptions.NONE, 0, "flash-once");
            add (AnimEffect.PEEK, 12, -1, EffectOptions.DIR4, 4, "peek-in");
            add (AnimEffect.PLUS, 13, -1, EffectOptions.IN_OUT, 16, "plus");
            add (AnimEffect.RANDOM_BARS, 14, -1, EffectOptions.ORIENT, 10, "random-bars");
            add (AnimEffect.SPIRAL, 15, -1, EffectOptions.NONE, 0, "spiral-in");
            add (AnimEffect.SPLIT, 16, -1, EffectOptions.SPLIT, 21, "split");
            add (AnimEffect.STRETCH, 17, -1, EffectOptions.NONE, 10, "stretchy");
            add (AnimEffect.STRIPS, 18, -1, EffectOptions.STRIPS, 12, "diagonal-squares");
            add (AnimEffect.SWIVEL, 19, -1, EffectOptions.ORIENT, 10, "swivel");
            add (AnimEffect.WEDGE, 20, -1, EffectOptions.NONE, 0, "wedge");
            add (AnimEffect.WHEEL, 21, -1, EffectOptions.SPOKES, 1, "wheel");
            add (AnimEffect.WIPE, 22, -1, EffectOptions.DIR4, 4, "wipe");
            add (AnimEffect.BASIC_ZOOM, 23, -1, EffectOptions.IN_OUT, 16, "zoom");
            add (AnimEffect.BOOMERANG, 25, -1, EffectOptions.NONE, 0, "boomerang");
            add (AnimEffect.BOUNCE, 26, -1, EffectOptions.NONE, 0, "bounce");
            add (AnimEffect.CREDITS, 28, -1, EffectOptions.NONE, 0, "movie-credits");
            add (AnimEffect.EASE_IN, 29, -1, EffectOptions.NONE, 0, "ease-in");
            add (AnimEffect.GROW_TURN, 31, -1, EffectOptions.NONE, 0, "turn-and-grow");
            add (AnimEffect.LIGHT_SPEED, 34, -1, EffectOptions.NONE, 0, "breaks");
            add (AnimEffect.PINWHEEL, 35, -1, EffectOptions.NONE, 0, "pinwheel");
            add (AnimEffect.RISE_UP, 37, -1, EffectOptions.NONE, 0, "rise-up");
            add (AnimEffect.SWISH, 38, -1, EffectOptions.NONE, 0, "falling-in");
            add (AnimEffect.THIN_LINE, 39, -1, EffectOptions.NONE, 0, "thread");
            add (AnimEffect.UNFOLD, 40, -1, EffectOptions.NONE, 0, "unfold");
            add (AnimEffect.WHIP, 41, -1, EffectOptions.NONE, 0, "whip");
            add (AnimEffect.FLOAT, 42, -1, EffectOptions.DIR4, 4, "ascend");
            add (AnimEffect.CENTER_REVOLVE, 43, -1, EffectOptions.NONE, 0, "center-revolve");
            add (AnimEffect.FADE_SWIVEL, 45, -1, EffectOptions.NONE, 0, "fade-in-and-swivel");
            add (AnimEffect.SLING, 48, -1, EffectOptions.NONE, 0, "sling");
            add (AnimEffect.SPINNER, 49, -1, EffectOptions.NONE, 0, "spin-in");
            add (AnimEffect.COMPRESS, 50, -1, EffectOptions.NONE, 0, "compress");
            add (AnimEffect.ZIP, 51, -1, EffectOptions.NONE, 0, "magnify");
            add (AnimEffect.ARC_UP, 52, -1, EffectOptions.NONE, 0, "curve-up");
            add (AnimEffect.ZOOM, 53, -1, EffectOptions.NONE, 16, "fade-in-and-zoom");
            add (AnimEffect.GLIDE, 54, -1, EffectOptions.NONE, 0, "glide");
            add (AnimEffect.EXPAND, 55, -1, EffectOptions.NONE, 0, "expand");
            add (AnimEffect.FLIP, 56, -1, EffectOptions.NONE, 0, "flip");
            add (AnimEffect.FOLD, 58, -1, EffectOptions.NONE, 0, "fold");
            add (AnimEffect.FILL_COLOR, -1, 1, EffectOptions.COLOR, 0, "fill-color");
            add (AnimEffect.FONT_COLOR, -1, 3, EffectOptions.COLOR, 0, "font-color");
            add (AnimEffect.GROW, -1, 6, EffectOptions.SCALE, 0, "grow-and-shrink");
            add (AnimEffect.LINE_COLOR, -1, 7, EffectOptions.COLOR, 0, "line-color");
            add (AnimEffect.SPIN, -1, 8, EffectOptions.SPIN, 0, "spin");
            add (AnimEffect.TRANSPARENCY, -1, 9, EffectOptions.ALPHA, 0, "transparency");
            add (AnimEffect.BOLD_FLASH, -1, 10, EffectOptions.NONE, 0, "bold-flash");
            add (AnimEffect.BOLD_REVEAL, -1, 15, EffectOptions.NONE, 0, "bold-reveal");
            add (AnimEffect.UNDERLINE, -1, 18, EffectOptions.NONE, 0, "reveal-underline");
            add (AnimEffect.OBJECT_COLOR, -1, 19, EffectOptions.COLOR, 0, "color-blend");
            add (AnimEffect.COMPLEMENTARY, -1, 21, EffectOptions.NONE, 0, "complementary-color");
            add (AnimEffect.CONTRASTING, -1, 23, EffectOptions.NONE, 0, "contrasting-color");
            add (AnimEffect.DARKEN, -1, 24, EffectOptions.NONE, 0, "darken");
            add (AnimEffect.DESATURATE, -1, 25, EffectOptions.NONE, 0, "desaturate");
            add (AnimEffect.PULSE, -1, 26, EffectOptions.NONE, 0, "flash-bulb");
            add (AnimEffect.COLOR_PULSE, -1, 27, EffectOptions.COLOR, 0, "flicker");
            add (AnimEffect.GROW_COLOR, -1, 28, EffectOptions.COLOR, 0, "grow-with-color");
            add (AnimEffect.LIGHTEN, -1, 30, EffectOptions.NONE, 0, "lighten");
            add (AnimEffect.TEETER, -1, 32, EffectOptions.NONE, 0, "teeter");
            add (AnimEffect.WAVE, -1, 34, EffectOptions.NONE, 0, "wave");
            add (AnimEffect.BLINK, -1, 35, EffectOptions.NONE, 0, "blink");
            add (AnimEffect.SHIMMER, -1, 36, EffectOptions.NONE, 0, "shimmer");
            add (AnimEffect.FLICKER, -1, 29, EffectOptions.NONE, 0, "style-emphasis");
            add (AnimEffect.MOTION_PATH, -1, -1, EffectOptions.PATH, 0, "motionpath");
            add (AnimEffect.MEDIA_PLAY, -1, -1, EffectOptions.NONE, 0, "media-start");
            add (AnimEffect.MEDIA_PAUSE, -1, -1, EffectOptions.NONE, 0, "media-toggle-pause");
            add (AnimEffect.MEDIA_STOP, -1, -1, EffectOptions.NONE, 0, "media-stop");
            return table;
        }

        private static Info? info (AnimEffect e) {
            return all ()[(int) e];
        }

        public static EffectOptions options (AnimEffect e) {
            var i = info (e);
            return i != null ? i.options : EffectOptions.NONE;
        }

        public static int default_subtype (AnimEffect e) {
            var i = info (e);
            return i != null ? i.default_sub : 0;
        }

        public static bool emphasis_only (AnimEffect e) {
            var i = info (e);
            return i != null && i.emph >= 0 && i.entr < 0;
        }

        public static bool entrance_ok (AnimEffect e) {
            var i = info (e);
            return i != null && i.entr >= 0;
        }

        public static int preset_id (AnimEffect e, AnimClass cls) {
            var i = info (e);
            if (i == null) return 10;
            if (cls == AnimClass.EMPHASIS) return i.emph >= 0 ? i.emph : 26;
            if (cls == AnimClass.PATH) return 0;
            if (cls == AnimClass.MEDIA) {
                switch (e) {
                    case AnimEffect.MEDIA_PAUSE: return 2;
                    case AnimEffect.MEDIA_STOP: return 3;
                    default: return 1;
                }
            }
            return i.entr >= 0 ? i.entr : 10;
        }

        public static AnimEffect from_preset (string cls, int id) {
            if (cls == "path") return AnimEffect.MOTION_PATH;
            if (cls == "mediacall") {
                switch (id) {
                    case 2: return AnimEffect.MEDIA_PAUSE;
                    case 3: return AnimEffect.MEDIA_STOP;
                    default: return AnimEffect.MEDIA_PLAY;
                }
            }
            bool emph = cls == "emph";
            foreach (var i in all ().values) {
                if (emph && i.emph == id) return i.effect;
                if (!emph && i.entr == id) return i.effect;
            }
            switch (id) {
                case 24: case 27: case 30: return emph ? AnimEffect.PULSE : AnimEffect.FADE;
                case 47: return AnimEffect.FLOAT;
                default: return emph ? AnimEffect.PULSE : AnimEffect.FADE;
            }
        }

        public static string odp_name (AnimEffect e, AnimClass cls) {
            var i = info (e);
            string n = i != null ? i.odp : "fade-in";
            switch (cls) {
                case AnimClass.EMPHASIS: return "ooo-emphasis-" + n;
                case AnimClass.PATH: return "ooo-motionpath-" + n;
                case AnimClass.MEDIA: return "ooo-media-" + n;
                case AnimClass.EXIT:
                    if (e == AnimEffect.APPEAR) return "ooo-exit-disappear";
                    if (e == AnimEffect.FADE) return "ooo-exit-fade-out";
                    if (e == AnimEffect.FLY) return "ooo-exit-fly-out";
                    if (e == AnimEffect.FLOAT) return "ooo-exit-descend";
                    if (e == AnimEffect.DISSOLVE) return "ooo-exit-dissolve";
                    if (e == AnimEffect.CRAWL) return "ooo-exit-crawl-out";
                    if (e == AnimEffect.PEEK) return "ooo-exit-peek-out";
                    return "ooo-exit-" + n.replace ("-in-", "-out-").replace ("fade-in", "fade-out");
                default:
                    return "ooo-entrance-" + n;
            }
        }

        public static AnimEffect from_odp (string? name, AnimClass cls) {
            if (name == null) return cls == AnimClass.EMPHASIS ? AnimEffect.PULSE : AnimEffect.FADE;
            if (name.has_prefix ("ooo-motionpath")) return AnimEffect.MOTION_PATH;
            string n = name;
            foreach (string pre in new string[] { "ooo-entrance-", "ooo-exit-", "ooo-emphasis-" }) {
                if (n.has_prefix (pre)) n = n.substring (pre.length);
            }
            if (n == "disappear") return AnimEffect.APPEAR;
            if (n == "fade-out") return AnimEffect.FADE;
            if (n == "fly-out") return AnimEffect.FLY;
            if (n == "descend") return AnimEffect.FLOAT;
            if (n == "crawl-out") return AnimEffect.CRAWL;
            if (n == "peek-out") return AnimEffect.PEEK;
            if (n == "dissolve") return AnimEffect.DISSOLVE;
            string alt = n.replace ("-out-", "-in-");
            foreach (var i in all ().values) {
                if (i.odp == n || i.odp == alt) {
                    if (cls == AnimClass.EMPHASIS && i.emph < 0) continue;
                    if (cls != AnimClass.EMPHASIS && i.entr < 0) continue;
                    return i.effect;
                }
            }
            if (cls == AnimClass.EMPHASIS) return n.contains ("spin") ? AnimEffect.SPIN : AnimEffect.PULSE;
            if (n.contains ("fly") || n.contains ("crawl")) return AnimEffect.FLY;
            if (n.contains ("zoom") || n.contains ("stretch")) return AnimEffect.ZOOM;
            if (n.contains ("wipe")) return AnimEffect.WIPE;
            if (n.contains ("ascend") || n.contains ("float") || n.contains ("rise")) return AnimEffect.FLOAT;
            return AnimEffect.FADE;
        }

        public static string label (AnimEffect e, AnimClass cls) {
            bool exit = cls == AnimClass.EXIT;
            switch (e) {
                case AnimEffect.APPEAR: return exit ? _("Disappear") : _("Appear");
                case AnimEffect.FADE: return exit ? _("Fade Out") : _("Fade");
                case AnimEffect.FLY: return exit ? _("Fly Out") : _("Fly In");
                case AnimEffect.ZOOM: return _("Zoom");
                case AnimEffect.WIPE: return _("Wipe");
                case AnimEffect.FLOAT: return exit ? _("Float Out") : _("Float In");
                case AnimEffect.SPIN: return _("Spin");
                case AnimEffect.PULSE: return _("Pulse");
                case AnimEffect.GROW: return _("Grow and Shrink");
                case AnimEffect.BLINDS: return _("Blinds");
                case AnimEffect.BOX: return _("Box");
                case AnimEffect.CHECKERBOARD: return _("Checkerboard");
                case AnimEffect.CIRCLE: return _("Shape");
                case AnimEffect.CRAWL: return exit ? _("Crawl Out") : _("Crawl In");
                case AnimEffect.DIAMOND: return _("Diamond");
                case AnimEffect.DISSOLVE: return exit ? _("Dissolve Out") : _("Dissolve In");
                case AnimEffect.FLASH_ONCE: return _("Flash Once");
                case AnimEffect.PEEK: return exit ? _("Peek Out") : _("Peek In");
                case AnimEffect.PLUS: return _("Plus");
                case AnimEffect.RANDOM_BARS: return _("Random Bars");
                case AnimEffect.SPIRAL: return exit ? _("Spiral Out") : _("Spiral In");
                case AnimEffect.SPLIT: return _("Split");
                case AnimEffect.STRETCH: return exit ? _("Collapse") : _("Stretch");
                case AnimEffect.STRIPS: return _("Strips");
                case AnimEffect.SWIVEL: return _("Swivel");
                case AnimEffect.WEDGE: return _("Wedge");
                case AnimEffect.WHEEL: return _("Wheel");
                case AnimEffect.BASIC_ZOOM: return _("Basic Zoom");
                case AnimEffect.BOOMERANG: return _("Boomerang");
                case AnimEffect.BOUNCE: return _("Bounce");
                case AnimEffect.CREDITS: return _("Credits");
                case AnimEffect.EASE_IN: return exit ? _("Ease Out") : _("Ease In");
                case AnimEffect.GROW_TURN: return exit ? _("Shrink and Turn") : _("Grow and Turn");
                case AnimEffect.LIGHT_SPEED: return _("Light Speed");
                case AnimEffect.PINWHEEL: return _("Pinwheel");
                case AnimEffect.RISE_UP: return exit ? _("Sink Down") : _("Rise Up");
                case AnimEffect.SWISH: return _("Swish");
                case AnimEffect.THIN_LINE: return _("Thin Line");
                case AnimEffect.UNFOLD: return exit ? _("Fold Up") : _("Unfold");
                case AnimEffect.WHIP: return _("Whip");
                case AnimEffect.CENTER_REVOLVE: return _("Center Revolve");
                case AnimEffect.FADE_SWIVEL: return _("Faded Swivel");
                case AnimEffect.SLING: return _("Sling");
                case AnimEffect.SPINNER: return _("Spinner");
                case AnimEffect.COMPRESS: return exit ? _("Stretchy") : _("Compress");
                case AnimEffect.ZIP: return _("Zip");
                case AnimEffect.ARC_UP: return exit ? _("Arc Down") : _("Arc Up");
                case AnimEffect.GLIDE: return _("Glide");
                case AnimEffect.EXPAND: return exit ? _("Contract") : _("Expand");
                case AnimEffect.FLIP: return _("Flip");
                case AnimEffect.FOLD: return _("Fold");
                case AnimEffect.COLOR_PULSE: return _("Color Pulse");
                case AnimEffect.TEETER: return _("Teeter");
                case AnimEffect.TRANSPARENCY: return _("Transparency");
                case AnimEffect.FILL_COLOR: return _("Fill Color");
                case AnimEffect.LINE_COLOR: return _("Line Color");
                case AnimEffect.FONT_COLOR: return _("Font Color");
                case AnimEffect.OBJECT_COLOR: return _("Object Color");
                case AnimEffect.COMPLEMENTARY: return _("Complementary Color");
                case AnimEffect.CONTRASTING: return _("Contrasting Color");
                case AnimEffect.DARKEN: return _("Darken");
                case AnimEffect.LIGHTEN: return _("Lighten");
                case AnimEffect.DESATURATE: return _("Desaturate");
                case AnimEffect.BOLD_FLASH: return _("Bold Flash");
                case AnimEffect.BOLD_REVEAL: return _("Bold Reveal");
                case AnimEffect.UNDERLINE: return _("Underline");
                case AnimEffect.WAVE: return _("Wave");
                case AnimEffect.BLINK: return _("Blink");
                case AnimEffect.FLICKER: return _("Flicker");
                case AnimEffect.GROW_COLOR: return _("Grow with Color");
                case AnimEffect.SHIMMER: return _("Shimmer");
                case AnimEffect.MOTION_PATH: return _("Motion Path");
                case AnimEffect.MEDIA_PLAY: return _("Play");
                case AnimEffect.MEDIA_PAUSE: return _("Pause");
                default: return _("Stop");
            }
        }

        public static string[] option_labels (EffectOptions o) {
            switch (o) {
                case EffectOptions.DIR4:
                    return { _("From Bottom"), _("From Left"), _("From Right"), _("From Top") };
                case EffectOptions.DIR8:
                    return { _("From Bottom"), _("From Bottom Left"), _("From Left"), _("From Top Left"), _("From Top"), _("From Top Right"), _("From Right"), _("From Bottom Right") };
                case EffectOptions.IN_OUT:
                    return { _("In"), _("Out") };
                case EffectOptions.SPLIT:
                    return { _("Vertical In"), _("Vertical Out"), _("Horizontal In"), _("Horizontal Out") };
                case EffectOptions.ORIENT:
                    return { _("Horizontal"), _("Vertical") };
                case EffectOptions.SPOKES:
                    return { _("1 Spoke"), _("2 Spokes"), _("3 Spokes"), _("4 Spokes"), _("8 Spokes") };
                case EffectOptions.STRIPS:
                    return { _("Left Down"), _("Left Up"), _("Right Down"), _("Right Up") };
                default:
                    return {};
            }
        }

        public static int[] option_values (EffectOptions o) {
            switch (o) {
                case EffectOptions.DIR4: return { 4, 8, 2, 1 };
                case EffectOptions.DIR8: return { 4, 12, 8, 9, 1, 3, 2, 6 };
                case EffectOptions.IN_OUT: return { 16, 32 };
                case EffectOptions.SPLIT: return { 21, 37, 26, 42 };
                case EffectOptions.ORIENT: return { 10, 5 };
                case EffectOptions.SPOKES: return { 1, 2, 3, 4, 8 };
                case EffectOptions.STRIPS: return { 12, 9, 6, 3 };
                default: return {};
            }
        }

        public static void vector (int subtype, out double dx, out double dy) {
            dx = 0;
            dy = 0;
            if ((subtype & 1) != 0) dy = -1;
            if ((subtype & 4) != 0) dy = 1;
            if ((subtype & 8) != 0) dx = -1;
            if ((subtype & 2) != 0) dx = 1;
            if (dx == 0 && dy == 0) dy = 1;
        }
    }

    public enum TransitionGroup {
        SUBTLE,
        EXCITING,
        DYNAMIC
    }

    public enum TransitionOptions {
        NONE,
        DIR4,
        DIR8,
        LR,
        IN_OUT,
        SPLIT,
        ORIENT,
        SHAPE,
        SPOKES,
        MORPH,
        FADE,
        STRIPS,
        CURL
    }

    public class TransitionCatalog {
        public static TransitionGroup group (TransitionKind k) {
            switch (k) {
                case TransitionKind.MORPH:
                case TransitionKind.FADE:
                case TransitionKind.FADE_BLACK:
                case TransitionKind.PUSH:
                case TransitionKind.WIPE:
                case TransitionKind.SPLIT:
                case TransitionKind.REVEAL:
                case TransitionKind.CUT:
                case TransitionKind.RANDOM_BARS:
                case TransitionKind.CIRCLE:
                case TransitionKind.UNCOVER:
                case TransitionKind.COVER:
                case TransitionKind.FLASH:
                case TransitionKind.NONE:
                    return TransitionGroup.SUBTLE;
                case TransitionKind.PAN:
                case TransitionKind.FERRIS_WHEEL:
                case TransitionKind.CONVEYOR:
                case TransitionKind.ROTATE:
                case TransitionKind.WINDOW:
                case TransitionKind.ORBIT:
                case TransitionKind.FLY_THROUGH:
                    return TransitionGroup.DYNAMIC;
                default:
                    return TransitionGroup.EXCITING;
            }
        }

        public static TransitionOptions options (TransitionKind k) {
            switch (k) {
                case TransitionKind.PUSH:
                case TransitionKind.WIPE:
                case TransitionKind.PAN:
                case TransitionKind.WINDOW:
                    return TransitionOptions.DIR4;
                case TransitionKind.COVER:
                case TransitionKind.UNCOVER:
                    return TransitionOptions.DIR8;
                case TransitionKind.REVEAL:
                case TransitionKind.FALL_OVER:
                case TransitionKind.DRAPE:
                case TransitionKind.WIND:
                case TransitionKind.AIRPLANE:
                case TransitionKind.ORIGAMI:
                case TransitionKind.VORTEX:
                case TransitionKind.SWITCH:
                case TransitionKind.FLIP:
                case TransitionKind.GALLERY:
                case TransitionKind.CUBE:
                case TransitionKind.DOORS:
                case TransitionKind.BOX:
                case TransitionKind.FERRIS_WHEEL:
                case TransitionKind.CONVEYOR:
                case TransitionKind.ROTATE:
                case TransitionKind.ORBIT:
                case TransitionKind.RIPPLE:
                case TransitionKind.SHRED:
                case TransitionKind.PEEL_OFF:
                    return TransitionOptions.LR;
                case TransitionKind.ZOOM:
                case TransitionKind.FLY_THROUGH:
                    return TransitionOptions.IN_OUT;
                case TransitionKind.SPLIT:
                    return TransitionOptions.SPLIT;
                case TransitionKind.RANDOM_BARS:
                case TransitionKind.BLINDS:
                case TransitionKind.CHECKERBOARD:
                case TransitionKind.COMB:
                    return TransitionOptions.ORIENT;
                case TransitionKind.CIRCLE:
                    return TransitionOptions.SHAPE;
                case TransitionKind.CLOCK:
                    return TransitionOptions.SPOKES;
                case TransitionKind.MORPH:
                    return TransitionOptions.MORPH;
                case TransitionKind.FADE:
                case TransitionKind.CUT:
                    return TransitionOptions.FADE;
                case TransitionKind.STRIPS:
                    return TransitionOptions.STRIPS;
                case TransitionKind.PAGE_CURL:
                    return TransitionOptions.CURL;
                default:
                    return TransitionOptions.NONE;
            }
        }

        public static string[] variant_labels (TransitionOptions o) {
            switch (o) {
                case TransitionOptions.LR: return { _("From Right"), _("From Left") };
                case TransitionOptions.IN_OUT: return { _("In"), _("Out") };
                case TransitionOptions.SPLIT: return { _("Vertical Out"), _("Vertical In"), _("Horizontal Out"), _("Horizontal In") };
                case TransitionOptions.ORIENT: return { _("Vertical"), _("Horizontal") };
                case TransitionOptions.SHAPE: return { _("Circle"), _("Diamond"), _("Plus"), _("In"), _("Out") };
                case TransitionOptions.SPOKES: return { _("Clockwise"), _("Counterclockwise"), _("Wedge") };
                case TransitionOptions.MORPH: return { _("Objects"), _("Words"), _("Characters") };
                case TransitionOptions.FADE: return { _("Smoothly"), _("Through Black") };
                case TransitionOptions.STRIPS: return { _("Left Down"), _("Left Up"), _("Right Down"), _("Right Up") };
                case TransitionOptions.CURL: return { _("Double Left"), _("Double Right"), _("Single Left"), _("Single Right") };
                default: return {};
            }
        }
    }
}
