namespace Singularity.Apps.Slides {

    public class ShapeEffects {
        public string glow_color = "";
        public double glow_radius = 0;
        public double soft_edge = 0;
        public bool reflection = false;
        public double reflection_size = 0.5;
        public double reflection_distance = 0;
        public double reflection_alpha = 0.5;
        public string bevel = "";
        public double bevel_width = 6;
        public double bevel_height = 6;
        public double rot_x = 0;
        public double rot_y = 0;
        public double perspective = 0;
        public string text_outline = "";
        public double text_outline_width = 0.75;
        public string text_glow = "";
        public double text_glow_radius = 0;
        public bool text_shadow = false;
        public bool text_reflection = false;
        public string text_warp = "";
        public string text_fill = "";

        public ShapeEffects clone () {
            var e = new ShapeEffects ();
            e.glow_color = glow_color;
            e.glow_radius = glow_radius;
            e.soft_edge = soft_edge;
            e.reflection = reflection;
            e.reflection_size = reflection_size;
            e.reflection_distance = reflection_distance;
            e.reflection_alpha = reflection_alpha;
            e.bevel = bevel;
            e.bevel_width = bevel_width;
            e.bevel_height = bevel_height;
            e.rot_x = rot_x;
            e.rot_y = rot_y;
            e.perspective = perspective;
            e.text_outline = text_outline;
            e.text_outline_width = text_outline_width;
            e.text_glow = text_glow;
            e.text_glow_radius = text_glow_radius;
            e.text_shadow = text_shadow;
            e.text_reflection = text_reflection;
            e.text_warp = text_warp;
            e.text_fill = text_fill;
            return e;
        }

        public bool has_shape_effects () {
            return (glow_color != "" && glow_radius > 0) || soft_edge > 0 || reflection || bevel != "" || rot_x != 0 || rot_y != 0;
        }

        public bool has_text_effects () {
            return text_outline != "" || (text_glow != "" && text_glow_radius > 0) || text_shadow || text_reflection || text_warp != "" || text_fill != "";
        }

        public const string[] WARPS = {
            "textArchUp", "textArchDown", "textCircle", "textButton", "textWave1", "textWave2", "textDoubleWave1",
            "textInflate", "textDeflate", "textSlantUp", "textSlantDown", "textTriangle", "textTriangleInverted",
            "textChevron", "textChevronInverted", "textFadeRight", "textFadeLeft", "textFadeUp", "textFadeDown",
            "textCurveUp", "textCurveDown", "textCanUp", "textCanDown", "textStop", "textPlain"
        };

        public const string[] BEVELS = { "circle", "relaxedInset", "cross", "coolSlant", "angle", "softRound", "convex", "slope", "divot", "riblet", "hardEdge", "artDeco" };
    }

    public class PresetLabels {
        public static string label (string name) {
            switch (name) {
                case "rect": return _("Rectangle");
                case "roundRect": return _("Rounded Rectangle");
                case "snip1Rect": return _("Snip Single Corner Rectangle");
                case "snip2SameRect": return _("Snip Same Side Corner Rectangle");
                case "snip2DiagRect": return _("Snip Diagonal Corner Rectangle");
                case "snipRoundRect": return _("Snip and Round Single Corner Rectangle");
                case "round1Rect": return _("Round Single Corner Rectangle");
                case "round2SameRect": return _("Round Same Side Corner Rectangle");
                case "round2DiagRect": return _("Round Diagonal Corner Rectangle");
                case "ellipse": return _("Oval");
                case "triangle": return _("Isosceles Triangle");
                case "rtTriangle": return _("Right Triangle");
                case "homePlate": return _("Pentagon Arrow");
                case "wedgeRoundRectCallout": return _("Speech Bubble: Rectangle with Corners Rounded");
                case "wedgeRectCallout": return _("Speech Bubble: Rectangle");
                case "wedgeEllipseCallout": return _("Speech Bubble: Oval");
                case "cloudCallout": return _("Thought Bubble: Cloud");
                case "irregularSeal1": return _("Explosion 1");
                case "irregularSeal2": return _("Explosion 2");
                case "flowChartConnector": return _("Flowchart: Connector");
                case "flowChartOffpageConnector": return _("Flowchart: Off-page Connector");
                case "mathPlus": return _("Plus Sign");
                case "mathMinus": return _("Minus Sign");
                case "mathMultiply": return _("Multiplication Sign");
                case "mathDivide": return _("Division Sign");
                case "mathEqual": return _("Equal");
                case "mathNotEqual": return _("Not Equal");
                case "noSmoking": return _("\"Not Allowed\" Symbol");
                case "smileyFace": return _("Smiley Face");
                case "lightningBolt": return _("Lightning Bolt");
                case "straightConnector1": return _("Straight Arrow Connector");
                case "bentConnector3": return _("Elbow Connector");
                case "curvedConnector3": return _("Curved Connector");
                default: break;
            }
            string n = name;
            string prefix = "";
            if (n.has_prefix ("flowChart")) {
                prefix = _("Flowchart: ");
                n = n.substring (9);
            } else if (n.has_prefix ("actionButton")) {
                prefix = _("Action Button: ");
                n = n.substring (12);
            } else if (n.has_prefix ("star") && n.length <= 6) {
                return _("Star: %s Points").printf (n.substring (4));
            }
            var sb = new StringBuilder ();
            for (int i = 0; i < n.length; i++) {
                char c = n[i];
                if (i == 0) {
                    sb.append_c (c.toupper ());
                    continue;
                }
                if (c.isupper () || (c.isdigit () && !n[i - 1].isdigit ())) sb.append_c (' ');
                sb.append_c (c);
            }
            return prefix + sb.str;
        }
    }
}
