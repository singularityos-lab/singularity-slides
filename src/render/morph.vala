namespace Singularity.Apps.Slides {

    public class MorphPair {
        public Element? from;
        public Element? to;

        public MorphPair (Element? from, Element? to) {
            this.from = from;
            this.to = to;
        }
    }

    public class Morph {
        private static string key_text (Element e) {
            var b = e.text_body ();
            return b != null ? b.plain_text ().strip () : "";
        }

        private static int score (Element a, Element b) {
            if (a.name != "" && a.name == b.name && a.name.has_prefix ("!!")) return 1000;
            if (a.kind != b.kind) return -1;
            int s = 0;
            if (a.name != "" && a.name == b.name) s += 200;
            string ta = key_text (a), tb = key_text (b);
            if (ta != "" && ta == tb) s += 150;
            if (a.placeholder != PlaceholderKind.NONE && a.placeholder.matches (b.placeholder)) s += 120;
            var sa = a as ShapeElement;
            var sb = b as ShapeElement;
            if (sa != null && sb != null && sa.preset_name () == sb.preset_name ()) s += 40;
            var ia = a as ImageElement;
            var ib = b as ImageElement;
            if (ia != null && ib != null && ia.data.compare (ib.data) == 0) s += 300;
            double d = Math.hypot (a.cx () - b.cx (), a.cy () - b.cy ());
            s += (int) double.max (0, 30 - d / 20);
            return s >= 60 ? s : -1;
        }

        public static Gee.ArrayList<MorphPair> match (Slide from, Slide to) {
            var pairs = new Gee.ArrayList<MorphPair> ();
            var used = new Gee.HashSet<Element> ();
            var matched_from = new Gee.HashSet<Element> ();
            var candidates = new Gee.ArrayList<MorphPair> ();
            var scores = new Gee.HashMap<MorphPair, int> ();
            foreach (var a in from.elements) {
                foreach (var b in to.elements) {
                    int sc = score (a, b);
                    if (sc < 0) continue;
                    var p = new MorphPair (a, b);
                    candidates.add (p);
                    scores[p] = sc;
                }
            }
            candidates.sort ((x, y) => scores[y] - scores[x]);
            foreach (var c in candidates) {
                if (matched_from.contains (c.from) || used.contains (c.to)) continue;
                matched_from.add (c.from);
                used.add (c.to);
                pairs.add (c);
            }
            foreach (var a in from.elements) if (!matched_from.contains (a)) pairs.add (new MorphPair (a, null));
            foreach (var b in to.elements) if (!used.contains (b)) pairs.add (new MorphPair (null, b));
            return pairs;
        }

        private static double lerp (double a, double b, double t) {
            return a + (b - a) * t;
        }

        private static Element blend (RenderContext ctx, Element a, Element b, double t) {
            var e = b.clone ();
            double x = lerp (a.x, b.x, t), y = lerp (a.y, b.y, t), w = lerp (a.w, b.w, t), h = lerp (a.h, b.h, t);
            e.scale_into (x, y, double.max (w, 0.1), double.max (h, 0.1));
            double ra = a.rotation, rb = b.rotation;
            if (rb - ra > 180) ra += 360;
            else if (ra - rb > 180) rb += 360;
            e.rotation = lerp (ra, rb, t);
            var sa = a as ShapeElement;
            var se = e as ShapeElement;
            if (sa != null && se != null) {
                string ca = sa.fill.first_color (), cb = se.fill.first_color ();
                if (ca != "" && cb != "" && sa.fill.kind == FillKind.SOLID && se.fill.kind == FillKind.SOLID) {
                    se.fill = new Fill.solid (ctx.theme.resolve (ca).mix (ctx.theme.resolve (cb), t).to_hex ());
                }
                if (sa.line.color != "" && se.line.color != "") {
                    se.line.color = ctx.theme.resolve (sa.line.color).mix (ctx.theme.resolve (se.line.color), t).to_hex ();
                    se.line.width = lerp (sa.line.width, se.line.width, t);
                }
            }
            return e;
        }

        public static void draw (Cairo.Context cr, Presentation p, Slide from, Slide to, double progress) {
            double t = Player.ease (progress);
            var r = new Renderer ();
            var hide_from = new Gee.HashSet<int> ();
            foreach (var e in from.elements) hide_from.add (e.id);
            var hide_to = new Gee.HashSet<int> ();
            foreach (var e in to.elements) hide_to.add (e.id);
            r.hidden = hide_from;
            r.draw_slide (cr, p, from);
            cr.push_group ();
            r.hidden = hide_to;
            r.draw_slide (cr, p, to);
            cr.pop_group_to_source ();
            cr.paint_with_alpha (t);
            r.hidden = null;
            var ctx_from = new RenderContext (p, from, p.layout_for (from), p.master_for (from));
            var ctx_to = new RenderContext (p, to, p.layout_for (to), p.master_for (to));
            cr.save ();
            cr.rectangle (0, 0, p.width, p.height);
            cr.clip ();
            foreach (var pair in match (from, to)) {
                if (pair.from != null && pair.to == null) {
                    cr.push_group ();
                    r.draw_element (cr, ctx_from, pair.from, false);
                    cr.pop_group_to_source ();
                    cr.paint_with_alpha (1 - t);
                } else if (pair.from == null && pair.to != null) {
                    cr.push_group ();
                    r.draw_element (cr, ctx_to, pair.to, false);
                    cr.pop_group_to_source ();
                    cr.paint_with_alpha (t);
                } else {
                    bool same_text = key_text (pair.from) == key_text (pair.to);
                    if (same_text) {
                        r.draw_element (cr, ctx_to, blend (ctx_to, pair.from, pair.to, t), false);
                    } else {
                        var fa = blend (ctx_from, pair.to, pair.from, 1 - t);
                        var fb = blend (ctx_to, pair.from, pair.to, t);
                        cr.push_group ();
                        r.draw_element (cr, ctx_from, fa, false);
                        cr.pop_group_to_source ();
                        cr.paint_with_alpha (1 - t);
                        cr.push_group ();
                        r.draw_element (cr, ctx_to, fb, false);
                        cr.pop_group_to_source ();
                        cr.paint_with_alpha (t);
                    }
                }
            }
            cr.restore ();
        }
    }
}
