namespace Singularity.Apps.Slides {

    public class TransitionCodec {
        private const string[] PRST = { "fallOver", "drape", "curtains", "wind", "prestige", "fracture", "crush", "peelOff", "airplane", "origami" };
        private const TransitionKind[] PRST_KINDS = {
            TransitionKind.FALL_OVER, TransitionKind.DRAPE, TransitionKind.CURTAINS, TransitionKind.WIND, TransitionKind.PRESTIGE,
            TransitionKind.FRACTURE, TransitionKind.CRUSH, TransitionKind.PEEL_OFF, TransitionKind.AIRPLANE, TransitionKind.ORIGAMI
        };

        public static int dir8_from (string? d, int fallback) {
            if (d == null || d == "") return fallback;
            int s = 0;
            if (d.contains ("l")) s |= 2;
            if (d.contains ("r")) s |= 8;
            if (d.contains ("u")) s |= 4;
            if (d.contains ("d")) s |= 1;
            return s != 0 ? s : fallback;
        }

        public static string dir8_to (int s) {
            string v = "";
            if ((s & 8) != 0) v += "r";
            else if ((s & 2) != 0) v += "l";
            string u = "";
            if ((s & 1) != 0) u = "d";
            else if ((s & 4) != 0) u = "u";
            if (v != "" && u != "") return v + u;
            return v != "" ? v : (u != "" ? u : "l");
        }

        private static bool b (Xml.Node* n, string a) {
            return XmlIn.bool_attr (n, a, false);
        }

        private static int lr (Xml.Node* n) {
            return XmlIn.attr (n, "dir") == "r" ? 1 : 0;
        }

        public static bool known (Xml.Node* k) {
            var t = new Transition ();
            return read (k, t);
        }

        public static bool read (Xml.Node* k, Transition t) {
            string name = k->name;
            string? dir = XmlIn.attr (k, "dir");
            t.variant = 0;
            switch (name) {
                case "fade":
                    t.kind = b (k, "thruBlk") ? TransitionKind.FADE_BLACK : TransitionKind.FADE;
                    return true;
                case "push":
                    t.kind = TransitionKind.PUSH;
                    t.subtype = dir8_from (dir ?? "u", 4);
                    return true;
                case "wipe":
                    t.kind = TransitionKind.WIPE;
                    t.subtype = dir8_from (dir ?? "l", 2);
                    return true;
                case "cover":
                    t.kind = TransitionKind.COVER;
                    t.subtype = dir8_from (dir ?? "l", 2);
                    return true;
                case "pull":
                    t.kind = TransitionKind.UNCOVER;
                    t.subtype = dir8_from (dir ?? "l", 2);
                    return true;
                case "split":
                    t.kind = TransitionKind.SPLIT;
                    bool horz = XmlIn.attr (k, "orient") == "horz";
                    bool into = dir == "in";
                    t.variant = (horz ? 2 : 0) + (into ? 1 : 0);
                    return true;
                case "reveal":
                    t.kind = TransitionKind.REVEAL;
                    t.variant = b (k, "thruBlk") ? 1 : 0;
                    t.subtype = dir == "r" ? 8 : 2;
                    return true;
                case "cut":
                    t.kind = TransitionKind.CUT;
                    t.variant = b (k, "thruBlk") ? 1 : 0;
                    return true;
                case "randomBar":
                    t.kind = TransitionKind.RANDOM_BARS;
                    t.variant = dir == "horz" ? 1 : 0;
                    return true;
                case "circle":
                    t.kind = TransitionKind.CIRCLE;
                    return true;
                case "diamond":
                    t.kind = TransitionKind.CIRCLE;
                    t.variant = 1;
                    return true;
                case "plus":
                    t.kind = TransitionKind.CIRCLE;
                    t.variant = 2;
                    return true;
                case "zoom":
                    t.kind = TransitionKind.ZOOM;
                    t.variant = dir == "out" ? 1 : 0;
                    return true;
                case "warp":
                    t.kind = TransitionKind.ZOOM;
                    t.variant = dir == "out" ? 1 : 0;
                    return true;
                case "flash":
                    t.kind = TransitionKind.FLASH;
                    return true;
                case "dissolve":
                    t.kind = TransitionKind.DISSOLVE;
                    return true;
                case "checker":
                    t.kind = TransitionKind.CHECKERBOARD;
                    t.variant = dir == "vert" ? 0 : 1;
                    return true;
                case "blinds":
                    t.kind = TransitionKind.BLINDS;
                    t.variant = dir == "vert" ? 0 : 1;
                    return true;
                case "comb":
                    t.kind = TransitionKind.COMB;
                    t.variant = dir == "vert" ? 0 : 1;
                    return true;
                case "wheel":
                    t.kind = TransitionKind.CLOCK;
                    return true;
                case "wheelReverse":
                    t.kind = TransitionKind.CLOCK;
                    t.variant = 1;
                    return true;
                case "wedge":
                    t.kind = TransitionKind.CLOCK;
                    t.variant = 2;
                    return true;
                case "random":
                    t.kind = TransitionKind.RANDOM;
                    return true;
                case "strips":
                    t.kind = TransitionKind.STRIPS;
                    switch (dir ?? "lu") {
                        case "ld": t.variant = 0; break;
                        case "lu": t.variant = 1; break;
                        case "rd": t.variant = 2; break;
                        default: t.variant = 3; break;
                    }
                    return true;
                case "newsflash":
                    t.kind = TransitionKind.NEWSFLASH;
                    return true;
                case "ripple":
                    t.kind = TransitionKind.RIPPLE;
                    return true;
                case "honeycomb":
                    t.kind = TransitionKind.HONEYCOMB;
                    return true;
                case "glitter":
                    t.kind = TransitionKind.GLITTER;
                    t.subtype = dir == "r" ? 8 : 2;
                    return true;
                case "vortex":
                    t.kind = TransitionKind.VORTEX;
                    t.variant = lr (k);
                    return true;
                case "shred":
                    t.kind = TransitionKind.SHRED;
                    t.variant = dir == "out" ? 1 : 0;
                    return true;
                case "switch":
                    t.kind = TransitionKind.SWITCH;
                    t.variant = lr (k);
                    return true;
                case "flip":
                    t.kind = TransitionKind.FLIP;
                    t.variant = lr (k);
                    return true;
                case "gallery":
                    t.kind = TransitionKind.GALLERY;
                    t.variant = lr (k);
                    return true;
                case "prism":
                    bool content = b (k, "isContent"), inverted = b (k, "isInverted");
                    if (content) t.kind = inverted ? TransitionKind.ORBIT : TransitionKind.ROTATE;
                    else t.kind = inverted ? TransitionKind.BOX : TransitionKind.CUBE;
                    t.variant = lr (k);
                    return true;
                case "doors":
                    t.kind = TransitionKind.DOORS;
                    t.variant = dir == "horz" ? 1 : 0;
                    return true;
                case "window":
                    t.kind = TransitionKind.WINDOW;
                    t.subtype = dir == "horz" ? 1 : 2;
                    return true;
                case "ferris":
                    t.kind = TransitionKind.FERRIS_WHEEL;
                    t.variant = lr (k);
                    return true;
                case "conveyor":
                    t.kind = TransitionKind.CONVEYOR;
                    t.variant = lr (k);
                    return true;
                case "pan":
                    t.kind = TransitionKind.PAN;
                    t.subtype = dir8_from (dir ?? "u", 4);
                    return true;
                case "flythrough":
                    t.kind = TransitionKind.FLY_THROUGH;
                    t.variant = dir == "out" ? 1 : 0;
                    return true;
                case "morph":
                    t.kind = TransitionKind.MORPH;
                    string opt = XmlIn.attr (k, "option") ?? "byObject";
                    t.variant = opt == "byWord" ? 1 : (opt == "byChar" ? 2 : 0);
                    return true;
                case "prstTrans":
                    string prst = XmlIn.attr (k, "prst") ?? "";
                    t.variant = b (k, "invX") ? 1 : 0;
                    if (prst == "pageCurlDouble" || prst == "pageCurlSingle") {
                        t.kind = TransitionKind.PAGE_CURL;
                        t.variant = (prst == "pageCurlSingle" ? 2 : 0) + (b (k, "invX") ? 1 : 0);
                        return true;
                    }
                    for (int i = 0; i < PRST.length; i++) {
                        if (PRST[i] == prst) {
                            t.kind = PRST_KINDS[i];
                            return true;
                        }
                    }
                    return false;
                default:
                    return false;
            }
        }

        public static string requires (Transition t) {
            switch (t.kind) {
                case TransitionKind.NONE:
                case TransitionKind.FADE:
                case TransitionKind.FADE_BLACK:
                case TransitionKind.PUSH:
                case TransitionKind.WIPE:
                case TransitionKind.COVER:
                case TransitionKind.UNCOVER:
                case TransitionKind.SPLIT:
                case TransitionKind.ZOOM:
                case TransitionKind.DISSOLVE:
                case TransitionKind.CIRCLE:
                case TransitionKind.CUT:
                case TransitionKind.RANDOM_BARS:
                case TransitionKind.CHECKERBOARD:
                case TransitionKind.BLINDS:
                case TransitionKind.COMB:
                case TransitionKind.RANDOM:
                case TransitionKind.STRIPS:
                case TransitionKind.NEWSFLASH:
                    return "";
                case TransitionKind.MORPH:
                    return "p159";
                case TransitionKind.FALL_OVER:
                case TransitionKind.DRAPE:
                case TransitionKind.CURTAINS:
                case TransitionKind.WIND:
                case TransitionKind.PRESTIGE:
                case TransitionKind.FRACTURE:
                case TransitionKind.CRUSH:
                case TransitionKind.PEEL_OFF:
                case TransitionKind.PAGE_CURL:
                case TransitionKind.AIRPLANE:
                case TransitionKind.ORIGAMI:
                    return "p15";
                case TransitionKind.CLOCK:
                    return t.variant == 1 ? "p14" : "";
                default:
                    return "p14";
            }
        }

        public static void write (XmlOut x, Transition t, bool rich) {
            string req = requires (t);
            if (!rich && req != "") {
                x.empty ("p:fade");
                return;
            }
            string lr = t.variant == 1 ? "r" : "l";
            switch (t.kind) {
                case TransitionKind.FADE: x.empty ("p:fade"); break;
                case TransitionKind.FADE_BLACK: x.start ("p:fade").a ("thruBlk", "1").end (); break;
                case TransitionKind.PUSH: x.start ("p:push").a ("dir", dir4 (t.subtype)).end (); break;
                case TransitionKind.WIPE: x.start ("p:wipe").a ("dir", dir4 (t.subtype)).end (); break;
                case TransitionKind.COVER: x.start ("p:cover").a ("dir", dir8_to (t.subtype)).end (); break;
                case TransitionKind.UNCOVER: x.start ("p:pull").a ("dir", dir8_to (t.subtype)).end (); break;
                case TransitionKind.SPLIT:
                    x.start ("p:split").a ("orient", t.variant >= 2 ? "horz" : "vert").a ("dir", t.variant % 2 == 1 ? "in" : "out").end ();
                    break;
                case TransitionKind.ZOOM: x.start ("p:zoom").a ("dir", t.variant == 1 ? "out" : "in").end (); break;
                case TransitionKind.DISSOLVE: x.empty ("p:dissolve"); break;
                case TransitionKind.CIRCLE:
                    if (t.variant == 1) x.empty ("p:diamond");
                    else if (t.variant == 2) x.empty ("p:plus");
                    else if (t.variant == 3) x.start ("p:zoom").a ("dir", "in").end ();
                    else if (t.variant == 4) x.start ("p:zoom").a ("dir", "out").end ();
                    else x.empty ("p:circle");
                    break;
                case TransitionKind.CUT:
                    x.start ("p:cut");
                    if (t.variant == 1) x.a ("thruBlk", "1");
                    x.end ();
                    break;
                case TransitionKind.RANDOM_BARS: x.start ("p:randomBar").a ("dir", t.variant == 1 ? "horz" : "vert").end (); break;
                case TransitionKind.CHECKERBOARD: x.start ("p:checker").a ("dir", t.variant == 0 ? "vert" : "horz").end (); break;
                case TransitionKind.BLINDS: x.start ("p:blinds").a ("dir", t.variant == 0 ? "vert" : "horz").end (); break;
                case TransitionKind.COMB: x.start ("p:comb").a ("dir", t.variant == 0 ? "vert" : "horz").end (); break;
                case TransitionKind.RANDOM: x.empty ("p:random"); break;
                case TransitionKind.NEWSFLASH: x.empty ("p:newsflash"); break;
                case TransitionKind.STRIPS:
                    string[] sd = { "ld", "lu", "rd", "ru" };
                    x.start ("p:strips").a ("dir", sd[t.variant.clamp (0, 3)]).end ();
                    break;
                case TransitionKind.CLOCK:
                    if (t.variant == 1) x.start ("p14:wheelReverse").a ("spokes", "1").end ();
                    else if (t.variant == 2) x.empty ("p:wedge");
                    else x.start ("p:wheel").a ("spokes", "1").end ();
                    break;
                case TransitionKind.MORPH:
                    string[] opts = { "byObject", "byWord", "byChar" };
                    x.start ("p159:morph").a ("option", opts[t.variant.clamp (0, 2)]).end ();
                    break;
                case TransitionKind.REVEAL:
                    x.start ("p14:reveal");
                    if (t.variant == 1) x.a ("thruBlk", "1");
                    x.a ("dir", (t.subtype & 8) != 0 ? "r" : "l").end ();
                    break;
                case TransitionKind.FLASH: x.empty ("p14:flash"); break;
                case TransitionKind.RIPPLE: x.empty ("p14:ripple"); break;
                case TransitionKind.HONEYCOMB: x.empty ("p14:honeycomb"); break;
                case TransitionKind.GLITTER: x.start ("p14:glitter").a ("pattern", "hexagon").a ("dir", (t.subtype & 8) != 0 ? "r" : "l").end (); break;
                case TransitionKind.VORTEX: x.start ("p14:vortex").a ("dir", lr).end (); break;
                case TransitionKind.SHRED: x.start ("p14:shred").a ("pattern", "strip").a ("dir", t.variant == 1 ? "out" : "in").end (); break;
                case TransitionKind.SWITCH: x.start ("p14:switch").a ("dir", lr).end (); break;
                case TransitionKind.FLIP: x.start ("p14:flip").a ("dir", lr).end (); break;
                case TransitionKind.GALLERY: x.start ("p14:gallery").a ("dir", lr).end (); break;
                case TransitionKind.CUBE: x.start ("p14:prism").a ("dir", lr).end (); break;
                case TransitionKind.BOX: x.start ("p14:prism").a ("dir", lr).a ("isInverted", "1").end (); break;
                case TransitionKind.ROTATE: x.start ("p14:prism").a ("dir", lr).a ("isContent", "1").end (); break;
                case TransitionKind.ORBIT: x.start ("p14:prism").a ("dir", lr).a ("isContent", "1").a ("isInverted", "1").end (); break;
                case TransitionKind.DOORS: x.start ("p14:doors").a ("dir", t.variant == 1 ? "horz" : "vert").end (); break;
                case TransitionKind.WINDOW: x.start ("p14:window").a ("dir", (t.subtype & 5) != 0 ? "horz" : "vert").end (); break;
                case TransitionKind.FERRIS_WHEEL: x.start ("p14:ferris").a ("dir", lr).end (); break;
                case TransitionKind.CONVEYOR: x.start ("p14:conveyor").a ("dir", lr).end (); break;
                case TransitionKind.PAN: x.start ("p14:pan").a ("dir", dir4 (t.subtype)).end (); break;
                case TransitionKind.FLY_THROUGH: x.start ("p14:flythrough").a ("dir", t.variant == 1 ? "out" : "in").end (); break;
                case TransitionKind.PAGE_CURL:
                    x.start ("p15:prstTrans").a ("prst", t.variant >= 2 ? "pageCurlSingle" : "pageCurlDouble");
                    if (t.variant % 2 == 1) x.a ("invX", "1");
                    x.end ();
                    break;
                default:
                    for (int i = 0; i < PRST_KINDS.length; i++) {
                        if (PRST_KINDS[i] == t.kind) {
                            x.start ("p15:prstTrans").a ("prst", PRST[i]);
                            if (t.variant == 1) x.a ("invX", "1");
                            x.end ();
                            return;
                        }
                    }
                    break;
            }
        }

        private static string dir4 (int subtype) {
            if ((subtype & 8) != 0) return "r";
            if ((subtype & 2) != 0) return "l";
            if ((subtype & 1) != 0) return "d";
            return "u";
        }
    }
}
