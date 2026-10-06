namespace Singularity.Apps.Slides {

    public struct Rgba {
        public double r;
        public double g;
        public double b;
        public double a;

        public Rgba (double r, double g, double b, double a = 1) {
            this.r = r;
            this.g = g;
            this.b = b;
            this.a = a;
        }

        public string to_hex () {
            return "#%02x%02x%02x".printf ((uint) Math.round (r.clamp (0, 1) * 255), (uint) Math.round (g.clamp (0, 1) * 255), (uint) Math.round (b.clamp (0, 1) * 255));
        }

        public double luminance () {
            return 0.2126 * r + 0.7152 * g + 0.0722 * b;
        }

        public Rgba mix (Rgba o, double t) {
            return Rgba (r + (o.r - r) * t, g + (o.g - g) * t, b + (o.b - b) * t, a + (o.a - a) * t);
        }

        public static bool parse_hex (string s, out Rgba result) {
            result = Rgba (0, 0, 0, 1);
            string h = s.has_prefix ("#") ? s.substring (1) : s;
            if (h.length == 3) h = "%c%c%c%c%c%c".printf (h[0], h[0], h[1], h[1], h[2], h[2]);
            if (h.length != 6 && h.length != 8) return false;
            for (int i = 0; i < h.length; i++) if (!h[i].isxdigit ()) return false;
            uint64 v;
            if (!uint64.try_parse ("0x" + h, out v)) return false;
            if (h.length == 8) {
                result = Rgba (((v >> 24) & 0xff) / 255.0, ((v >> 16) & 0xff) / 255.0, ((v >> 8) & 0xff) / 255.0, (v & 0xff) / 255.0);
            } else {
                result = Rgba (((v >> 16) & 0xff) / 255.0, ((v >> 8) & 0xff) / 255.0, (v & 0xff) / 255.0, 1);
            }
            return true;
        }

        public void to_hsl (out double h, out double s, out double l) {
            double mx = double.max (r, double.max (g, b));
            double mn = double.min (r, double.min (g, b));
            l = (mx + mn) / 2;
            if (mx == mn) {
                h = 0;
                s = 0;
                return;
            }
            double d = mx - mn;
            s = l > 0.5 ? d / (2 - mx - mn) : d / (mx + mn);
            if (mx == r) h = (g - b) / d + (g < b ? 6 : 0);
            else if (mx == g) h = (b - r) / d + 2;
            else h = (r - g) / d + 4;
            h /= 6;
        }

        private static double hue (double p, double q, double t) {
            if (t < 0) t += 1;
            if (t > 1) t -= 1;
            if (t < 1.0 / 6) return p + (q - p) * 6 * t;
            if (t < 0.5) return q;
            if (t < 2.0 / 3) return p + (q - p) * (2.0 / 3 - t) * 6;
            return p;
        }

        public static Rgba from_hsl (double h, double s, double l, double a = 1) {
            if (s == 0) return Rgba (l, l, l, a);
            double q = l < 0.5 ? l * (1 + s) : l + s - l * s;
            double p = 2 * l - q;
            return Rgba (hue (p, q, h + 1.0 / 3), hue (p, q, h), hue (p, q, h - 1.0 / 3), a);
        }
    }

    public class Num {
        public static string fmt (double v) {
            return "%g".printf (v).replace (",", ".");
        }
    }

    public class ColorSpec {
        public string base_name = "";
        public double lum_mod = 1;
        public double lum_off = 0;
        public double alpha = 1;

        public static ColorSpec parse (string spec) {
            var c = new ColorSpec ();
            string s = spec;
            int at = s.index_of ("@");
            if (at >= 0) {
                c.alpha = double.parse (s.substring (at + 1)).clamp (0, 1);
                s = s.substring (0, at);
            }
            int tilde = s.index_of ("~");
            if (tilde >= 0) {
                string mods = s.substring (tilde + 1);
                s = s.substring (0, tilde);
                int plus = mods.index_of ("+", 1);
                if (plus > 0) {
                    c.lum_mod = double.parse (mods.substring (0, plus));
                    c.lum_off = double.parse (mods.substring (plus + 1));
                } else {
                    c.lum_mod = double.parse (mods);
                }
            }
            c.base_name = s;
            return c;
        }

        public string to_string () {
            var sb = new StringBuilder (base_name);
            if (lum_mod != 1 || lum_off != 0) {
                sb.append ("~" + fmt (lum_mod));
                if (lum_off != 0) sb.append ("+" + fmt (lum_off));
            }
            if (alpha < 1) sb.append ("@" + fmt (alpha));
            return sb.str;
        }

        private static string fmt (double v) {
            return Num.fmt (Math.round (v * 100000) / 100000);
        }

        public static string with_alpha (string spec, double alpha) {
            var c = parse (spec);
            c.alpha = alpha;
            return c.to_string ();
        }

        public static string tint (string spec, double lum_mod, double lum_off) {
            var c = parse (spec);
            c.lum_mod = lum_mod;
            c.lum_off = lum_off;
            return c.to_string ();
        }

        public bool is_scheme () {
            return !base_name.has_prefix ("#") && base_name != "";
        }
    }

    public class Theme {
        public const string[] SCHEME_KEYS = { "dk1", "lt1", "dk2", "lt2", "accent1", "accent2", "accent3", "accent4", "accent5", "accent6", "hlink", "folHlink" };

        public string name = "Office";
        public string id = "office";
        public Gee.HashMap<string, string> colors = new Gee.HashMap<string, string> ();
        public string major_font = "Inter";
        public string minor_font = "Inter";

        public Theme () {
            string[] defaults = { "#000000", "#ffffff", "#1f2937", "#e7e6e6", "#2a78d6", "#eb6834", "#1baf7a", "#eda100", "#4a3aa7", "#e34948", "#2a78d6", "#8e44ad" };
            for (int i = 0; i < SCHEME_KEYS.length; i++) colors[SCHEME_KEYS[i]] = defaults[i];
        }

        public Theme clone () {
            var t = new Theme ();
            t.name = name;
            t.id = id;
            foreach (var e in colors.entries) t.colors[e.key] = e.value;
            t.major_font = major_font;
            t.minor_font = minor_font;
            return t;
        }

        public static string canonical_key (string key) {
            switch (key) {
                case "tx1": return "dk1";
                case "bg1": return "lt1";
                case "tx2": return "dk2";
                case "bg2": return "lt2";
                default: return key;
            }
        }

        public string scheme_hex (string key) {
            string? v = colors[canonical_key (key)];
            return v ?? "#000000";
        }

        public Rgba resolve (string spec) {
            return resolve_or (spec, Rgba (0, 0, 0, 1));
        }

        public Rgba resolve_or (string spec, Rgba fallback) {
            if (spec == "") return fallback;
            var c = ColorSpec.parse (spec);
            Rgba baseline;
            string b = c.base_name;
            if (b.has_prefix ("#")) {
                if (!Rgba.parse_hex (b, out baseline)) baseline = fallback;
            } else if (b == "none" || b == "transparent") {
                return Rgba (0, 0, 0, 0);
            } else {
                if (!Rgba.parse_hex (scheme_hex (b), out baseline)) baseline = fallback;
            }
            if (c.lum_mod != 1 || c.lum_off != 0) {
                double h, s, l;
                baseline.to_hsl (out h, out s, out l);
                l = (l * c.lum_mod + c.lum_off).clamp (0, 1);
                baseline = Rgba.from_hsl (h, s, l, baseline.a);
            }
            baseline.a *= c.alpha;
            return baseline;
        }

        public string resolve_font (string font) {
            if (font == "+mj-lt" || font == "+mj") return major_font;
            if (font == "+mn-lt" || font == "+mn" || font == "") return minor_font;
            return font;
        }
    }

    public class ThemePreset {
        public string id;
        public string name;
        public string[] colors;
        public string major;
        public string minor;
        public string background;
        public string background2;
        public int decoration;

        public ThemePreset (string id, string name, string major, string minor, string background, string background2, int decoration, string[] colors) {
            this.id = id;
            this.name = name;
            this.major = major;
            this.minor = minor;
            this.background = background;
            this.background2 = background2;
            this.decoration = decoration;
            this.colors = colors;
        }

        public Theme build () {
            var t = new Theme ();
            t.id = id;
            t.name = name;
            for (int i = 0; i < Theme.SCHEME_KEYS.length && i < colors.length; i++) t.colors[Theme.SCHEME_KEYS[i]] = colors[i];
            t.major_font = major;
            t.minor_font = minor;
            return t;
        }

        private static Gee.ArrayList<ThemePreset>? list = null;

        public static Gee.ArrayList<ThemePreset> all () {
            if (list != null) return list;
            list = new Gee.ArrayList<ThemePreset> ();
            list.add (new ThemePreset ("clean", _("Clean"), "Inter", "Inter", "lt1", "", 0,
                { "#1d1d1f", "#ffffff", "#2b3a55", "#eef1f5", "#2a78d6", "#eb6834", "#1baf7a", "#eda100", "#8f5bd6", "#e34948", "#2a78d6", "#8f5bd6" }));
            list.add (new ThemePreset ("midnight", _("Midnight"), "Inter", "Inter", "dk2", "dk1", 1,
                { "#0b1020", "#f4f6fb", "#161d33", "#c9d1e8", "#5aa2ff", "#ff8a5c", "#3ddc97", "#ffd166", "#b28dff", "#ff6b81", "#7fb8ff", "#c7a6ff" }));
            list.add (new ThemePreset ("coral", _("Coral"), "Georgia", "Inter", "lt1", "", 2,
                { "#2d2320", "#fffaf6", "#5c3a2e", "#fbe9df", "#e8674a", "#f2a65a", "#3f8f7f", "#7b6ba8", "#d94f70", "#5a8fc2", "#c4513a", "#7b6ba8" }));
            list.add (new ThemePreset ("forest", _("Forest"), "Inter", "Inter", "lt2", "", 3,
                { "#16241c", "#ffffff", "#1e3a2b", "#eef4ef", "#2f8f5b", "#86b049", "#d9a441", "#4a7ab0", "#c2593d", "#6b5b95", "#2f8f5b", "#6b5b95" }));
            list.add (new ThemePreset ("slate", _("Slate"), "Inter", "Inter", "dk1", "dk2", 4,
                { "#1b1f24", "#e9edf2", "#2b313a", "#9aa5b4", "#38bdf8", "#f472b6", "#a3e635", "#fbbf24", "#818cf8", "#fb7185", "#38bdf8", "#818cf8" }));
            list.add (new ThemePreset ("paper", _("Paper"), "Georgia", "Georgia", "lt1", "", 5,
                { "#2b2b2b", "#fbf8f1", "#3d3a33", "#efe8d8", "#8a5a44", "#4f6d7a", "#a3b18a", "#d4a373", "#6d597a", "#b56576", "#4f6d7a", "#6d597a" }));
            list.add (new ThemePreset ("vivid", _("Vivid"), "Inter", "Inter", "accent1", "accent5", 6,
                { "#111111", "#ffffff", "#3a1c71", "#f5f0ff", "#6a3de8", "#ff5f6d", "#00c9a7", "#ffc75f", "#3a86ff", "#ff9671", "#3a86ff", "#6a3de8" }));
            list.add (new ThemePreset ("mono", _("Monochrome"), "Inter", "Inter", "lt1", "", 7,
                { "#111111", "#ffffff", "#333333", "#f2f2f2", "#111111", "#555555", "#888888", "#aaaaaa", "#cccccc", "#2a78d6", "#2a78d6", "#555555" }));
            return list;
        }

        public static ThemePreset? find (string id) {
            foreach (var p in all ()) if (p.id == id) return p;
            return null;
        }
    }

    public class ThemeVariants {
        public static Theme make (Theme src, int v) {
            var t = src.clone ();
            if (v == 0) return t;
            if (v == 1) {
                string dk1 = t.scheme_hex ("dk1"), lt1 = t.scheme_hex ("lt1"), dk2 = t.scheme_hex ("dk2"), lt2 = t.scheme_hex ("lt2");
                t.colors["dk1"] = lt1;
                t.colors["lt1"] = dk1;
                t.colors["dk2"] = lt2;
                t.colors["lt2"] = dk2;
                t.name = src.name + " Dark";
                return t;
            }
            for (int k = 1; k <= 6; k++) {
                string key = "accent%d".printf (k);
                Rgba c;
                if (!Rgba.parse_hex (t.scheme_hex (key), out c)) continue;
                double h, s, l;
                c.to_hsl (out h, out s, out l);
                switch (v) {
                    case 2: h = Math.fmod (h * 0.5 + 0.02 * k, 1.0); break;
                    case 3: h = 0.5 + Math.fmod (h * 0.3 + 0.03 * k, 0.25); break;
                    case 4: s = 0; break;
                    default: s = double.min (1, s * 1.4 + 0.1); break;
                }
                t.colors[key] = Rgba.from_hsl (h, s, l).to_hex ();
            }
            t.name = src.name + " Variant";
            return t;
        }
    }
}
