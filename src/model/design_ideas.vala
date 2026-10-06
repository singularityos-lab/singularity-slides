namespace Singularity.Apps.Slides {

    public class DesignIdea {
        public string name;
        public Slide slide;

        public DesignIdea (string name, Slide slide) {
            this.name = name;
            this.slide = slide;
        }
    }

    public class DesignIdeas {
        public const string BAND = "Design Accent";

        private static void cover (ImageElement img, double x, double y, double w, double h) {
            img.set_geometry (x, y, w, h);
            img.inherit_geometry = false;
            img.rotation = 0;
            img.crop_left = img.crop_right = img.crop_top = img.crop_bottom = 0;
            if (img.pixel_width <= 0 || img.pixel_height <= 0 || w <= 0 || h <= 0) return;
            double ia = img.pixel_width / (double) img.pixel_height;
            double ta = w / h;
            if (ia > ta) {
                double keep = ta / ia;
                img.crop_left = img.crop_right = (1 - keep) / 2;
            } else {
                double keep = ia / ta;
                img.crop_top = img.crop_bottom = (1 - keep) / 2;
            }
        }

        private static void place (Element e, double x, double y, double w, double h) {
            e.set_geometry (x, y, w, h);
            e.inherit_geometry = false;
        }

        private static ShapeElement band (Presentation p, double x, double y, double w, double h, string color, double alpha = 1) {
            var s = new ShapeElement (ShapeKind.RECT);
            s.fill = new Fill.solid (alpha < 1 ? ColorSpec.with_alpha (color, alpha) : color);
            s.line = new Line ();
            s.name = BAND;
            s.set_geometry (x, y, w, h);
            p.assign_ids (s);
            return s;
        }

        private static void clear_bands (Slide s) {
            for (int i = s.elements.size - 1; i >= 0; i--) if (s.elements[i].name == BAND) s.elements.remove_at (i);
        }

        private static void set_text_color (Element? e, string color) {
            if (e == null || e.text_body () == null) return;
            foreach (var para in e.text_body ().paragraphs) foreach (var r in para.runs) r.color = color;
        }

        public static Gee.ArrayList<DesignIdea> suggest (Presentation p, Slide src) {
            var ideas = new Gee.ArrayList<DesignIdea> ();
            double W = p.width, H = p.height, m = W * 0.05;
            var probe = src.clone ();
            clear_bands (probe);
            Element? title = probe.placeholder (PlaceholderKind.TITLE) ?? probe.placeholder (PlaceholderKind.CENTER_TITLE);
            Element? body = DeckOutline.body_of (probe);
            var pics = new Gee.ArrayList<Element> ();
            var other = new Gee.ArrayList<Element> ();
            foreach (var e in probe.elements) {
                if (e == title || e == body) continue;
                if (e is ImageElement) pics.add (e);
                else if (e is ChartElement || e is TableElement || e is DiagramElement || e is MediaElement) other.add (e);
            }
            bool has_body = body != null && body.text_body () != null && !body.text_body ().is_empty ();
            Element? visual = pics.size > 0 ? pics[0] : (other.size > 0 ? other[0] : null);
            if (visual != null) {
                for (int v = 0; v < 2; v++) {
                    var s = src.clone ();
                    clear_bands (s);
                    var t = s.placeholder (PlaceholderKind.TITLE) ?? s.placeholder (PlaceholderKind.CENTER_TITLE);
                    var b = DeckOutline.body_of (s);
                    var vis = s.find (visual.id);
                    bool right = v == 0;
                    double vx = right ? W * 0.5 : 0;
                    if (vis is ImageElement) cover ((ImageElement) vis, vx, 0, W * 0.5, H);
                    else place (vis, vx + m, H * 0.18, W * 0.5 - 2 * m, H * 0.64);
                    double tx = right ? m : W * 0.5 + m;
                    if (t != null) place (t, tx, H * 0.1, W * 0.5 - 2 * m, H * 0.22);
                    if (b != null) place (b, tx, H * 0.36, W * 0.5 - 2 * m, H * 0.54);
                    ideas.add (new DesignIdea (right ? _("Picture on the Right") : _("Picture on the Left"), s));
                }
                if (vis_is_image (visual)) {
                    var s = src.clone ();
                    clear_bands (s);
                    var vis = (ImageElement) s.find (visual.id);
                    cover (vis, 0, 0, W, H);
                    s.elements.remove (vis);
                    s.elements.insert (0, vis);
                    var shade = band (p, 0, H * 0.58, W, H * 0.42, "dk1", 0.62);
                    s.elements.insert (1, shade);
                    var t = s.placeholder (PlaceholderKind.TITLE) ?? s.placeholder (PlaceholderKind.CENTER_TITLE);
                    var b = DeckOutline.body_of (s);
                    if (t != null) {
                        place (t, m, H * 0.62, W - 2 * m, H * 0.16);
                        set_text_color (t, "lt1");
                    }
                    if (b != null) {
                        place (b, m, H * 0.78, W - 2 * m, H * 0.18);
                        set_text_color (b, "lt1");
                    }
                    ideas.add (new DesignIdea (_("Full-Bleed Picture"), s));
                }
                if (pics.size >= 2) {
                    var s = src.clone ();
                    clear_bands (s);
                    var t = s.placeholder (PlaceholderKind.TITLE) ?? s.placeholder (PlaceholderKind.CENTER_TITLE);
                    var b = DeckOutline.body_of (s);
                    if (t != null) place (t, m, H * 0.06, W - 2 * m, H * 0.16);
                    int n = pics.size;
                    double gap = W * 0.02;
                    double cw = (W - 2 * m - (n - 1) * gap) / n;
                    double top = has_body ? H * 0.46 : H * 0.28;
                    for (int i = 0; i < n; i++) {
                        var img = s.find (pics[i].id) as ImageElement;
                        if (img != null) cover (img, m + i * (cw + gap), top, cw, H * 0.94 - top);
                    }
                    if (b != null) place (b, m, H * 0.24, W - 2 * m, H * 0.2);
                    ideas.add (new DesignIdea (_("Picture Gallery"), s));
                }
            }
            {
                var s = src.clone ();
                clear_bands (s);
                var t = s.placeholder (PlaceholderKind.TITLE) ?? s.placeholder (PlaceholderKind.CENTER_TITLE);
                var b = DeckOutline.body_of (s);
                s.elements.insert (0, band (p, 0, 0, W, H * 0.26, "accent1"));
                if (t != null) {
                    place (t, m, H * 0.04, W - 2 * m, H * 0.18);
                    set_text_color (t, "lt1");
                }
                if (visual != null && b != null && has_body) {
                    place (b, m, H * 0.32, W * 0.46 - m, H * 0.6);
                    var vis = s.find (visual.id);
                    if (vis is ImageElement) cover ((ImageElement) vis, W * 0.52, H * 0.32, W * 0.48 - m, H * 0.6);
                    else if (vis != null) place (vis, W * 0.52, H * 0.32, W * 0.48 - m, H * 0.6);
                } else if (visual != null) {
                    var vis = s.find (visual.id);
                    if (vis is ImageElement) cover ((ImageElement) vis, m, H * 0.3, W - 2 * m, H * 0.64);
                    else if (vis != null) place (vis, m, H * 0.3, W - 2 * m, H * 0.64);
                } else if (b != null) {
                    place (b, m, H * 0.32, W - 2 * m, H * 0.6);
                }
                ideas.add (new DesignIdea (_("Accent Title Band"), s));
            }
            {
                var s = src.clone ();
                clear_bands (s);
                var t = s.placeholder (PlaceholderKind.TITLE) ?? s.placeholder (PlaceholderKind.CENTER_TITLE);
                var b = DeckOutline.body_of (s);
                s.elements.insert (0, band (p, 0, 0, W * 0.36, H, "accent1"));
                if (t != null) {
                    place (t, m * 0.8, H * 0.1, W * 0.36 - 1.6 * m, H * 0.8);
                    set_text_color (t, "lt1");
                    if (t.text_body () != null) t.text_body ().anchor = TextAnchor.MIDDLE;
                }
                if (b != null) place (b, W * 0.36 + m, H * 0.12, W * 0.64 - 2 * m, H * 0.76);
                if (visual != null && b != null && has_body) {
                    place (b, W * 0.36 + m, H * 0.08, W * 0.64 - 2 * m, H * 0.4);
                    var vis = s.find (visual.id);
                    if (vis is ImageElement) cover ((ImageElement) vis, W * 0.36 + m, H * 0.5, W * 0.64 - 2 * m, H * 0.42);
                    else if (vis != null) place (vis, W * 0.36 + m, H * 0.5, W * 0.64 - 2 * m, H * 0.42);
                } else if (visual != null) {
                    var vis = s.find (visual.id);
                    if (vis is ImageElement) cover ((ImageElement) vis, W * 0.36 + m, H * 0.1, W * 0.64 - 2 * m, H * 0.8);
                    else if (vis != null) place (vis, W * 0.36 + m, H * 0.1, W * 0.64 - 2 * m, H * 0.8);
                }
                ideas.add (new DesignIdea (_("Side Panel"), s));
            }
            {
                var s = src.clone ();
                clear_bands (s);
                var t = s.placeholder (PlaceholderKind.TITLE) ?? s.placeholder (PlaceholderKind.CENTER_TITLE);
                var b = DeckOutline.body_of (s);
                s.elements.insert (0, band (p, m, H * 0.3, W * 0.012, H * 0.4, "accent2"));
                if (t != null) place (t, m * 1.8, H * 0.24, W - 3.6 * m, H * 0.3);
                if (b != null) place (b, m * 1.8, H * 0.56, W - 3.6 * m, H * 0.36);
                if (visual != null) {
                    var vis = s.find (visual.id);
                    if (t != null) place (t, m * 1.8, H * 0.24, W * 0.5 - 2.4 * m, H * 0.3);
                    if (b != null) place (b, m * 1.8, H * 0.56, W * 0.5 - 2.4 * m, H * 0.36);
                    if (vis is ImageElement) cover ((ImageElement) vis, W * 0.55, H * 0.12, W * 0.45 - m, H * 0.76);
                    else if (vis != null) place (vis, W * 0.55, H * 0.12, W * 0.45 - m, H * 0.76);
                }
                ideas.add (new DesignIdea (_("Quiet Accent"), s));
            }
            return ideas;
        }

        private static bool vis_is_image (Element e) {
            return e is ImageElement;
        }
    }
}
