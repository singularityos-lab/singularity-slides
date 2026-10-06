namespace Singularity.Apps.Slides {

    public class ElementState {
        public bool visible = true;
        public double opacity = 1;
        public double dx = 0;
        public double dy = 0;
        public double path_dx = 0;
        public double path_dy = 0;
        public double scale = 1;
        public double sx = 1;
        public double sy = 1;
        public double spin = 0;
        public double wipe = 1;
        public Direction wipe_dir = Direction.FROM_BOTTOM;
        public ClipKind clip = ClipKind.NONE;
        public int clip_sub = 0;
        public double clip_p = 1;
        public string fill_color = "";
        public string line_color = "";
        public string text_color = "";
        public double color_mix = 1;
        public double hue_shift = 0;
        public double lightness = 0;
        public double desaturate = 0;
        public bool bold = false;
        public bool underline = false;
        public Gee.HashMap<int, ElementState>? paras = null;

        public bool is_identity () {
            return visible && opacity >= 1 && dx == 0 && dy == 0 && path_dx == 0 && path_dy == 0 && scale == 1 && sx == 1 && sy == 1 && spin == 0 && wipe >= 1 && clip == ClipKind.NONE;
        }

        public bool recolors () {
            return fill_color != "" || line_color != "" || text_color != "" || hue_shift != 0 || lightness != 0 || desaturate > 0 || bold || underline;
        }
    }

    public class RenderContext {
        public Presentation pres;
        public Slide? slide;
        public Layout? layout;
        public Master master;
        public Theme theme;
        public bool dark;
        public int number;

        public RenderContext (Presentation pres, Slide? slide, Layout? layout, Master master) {
            this.pres = pres;
            this.slide = slide;
            this.layout = layout;
            this.master = master;
            theme = master.theme;
            number = slide != null ? pres.slides.index_of (slide) + 1 : 1;
            Fill bg = slide != null ? pres.background_for (slide) : (layout != null && layout.background != null ? layout.background : master.background);
            string c = bg.first_color ();
            dark = c != "" && theme.resolve (c).luminance () < 0.5;
            if (bg.kind == FillKind.IMAGE) dark = true;
        }
    }

    public class ParaLayout {
        public Pango.Layout layout;
        public double x;
        public double y;
        public double width;
        public double height;
        public string bullet = "";
        public double bullet_x;
        public Pango.FontDescription? bullet_font;
        public Rgba bullet_color;
        public int index;
        public Gee.ArrayList<int> run_starts = new Gee.ArrayList<int> ();
        public Gee.ArrayList<int> run_ends = new Gee.ArrayList<int> ();
        public Gee.ArrayList<TextRun> runs = new Gee.ArrayList<TextRun> ();
    }

    public class TextLayout {
        public Gee.ArrayList<ParaLayout> paras = new Gee.ArrayList<ParaLayout> ();
        public double height;
        public double scale = 1;
    }

    public class Renderer {
        public bool edit_mode = false;
        public int hidden_text_id = -1;
        public Gee.HashMap<int, ElementState>? states = null;
        public Gee.HashSet<int>? hidden = null;
        public string date_format = "%x";

        public static Pango.Context? measure_context = null;

        public void draw_slide (Cairo.Context cr, Presentation p, Slide s) {
            var ctx = new RenderContext (p, s, p.layout_for (s), p.master_for (s));
            cr.save ();
            cr.rectangle (0, 0, p.width, p.height);
            cr.clip ();
            draw_fill_rect (cr, ctx, p.background_for (s), 0, 0, p.width, p.height);
            bool master_shapes = s.show_master_shapes && (ctx.layout == null || ctx.layout.show_master_shapes);
            if (master_shapes) {
                foreach (var e in ctx.master.elements) if (e.placeholder == PlaceholderKind.NONE) draw_element (cr, ctx, e, true);
            }
            if (ctx.layout != null) {
                foreach (var e in ctx.layout.elements) if (e.placeholder == PlaceholderKind.NONE) draw_element (cr, ctx, e, true);
            }
            foreach (var e in s.elements) draw_element (cr, ctx, e, false);
            cr.restore ();
        }

        public void draw_master_view (Cairo.Context cr, Presentation p, Master m, Layout? l) {
            var ctx = new RenderContext (p, null, l, m);
            cr.save ();
            cr.rectangle (0, 0, p.width, p.height);
            cr.clip ();
            Fill bg = l != null && l.background != null ? l.background : m.background;
            draw_fill_rect (cr, ctx, bg, 0, 0, p.width, p.height);
            if (l == null || l.show_master_shapes) {
                foreach (var e in m.elements) {
                    if (l != null && e.placeholder != PlaceholderKind.NONE) continue;
                    draw_element (cr, ctx, e, l != null);
                }
            }
            if (l != null) foreach (var e in l.elements) draw_element (cr, ctx, e, false);
            cr.restore ();
        }

        public static void set_source (Cairo.Context cr, Rgba c, double alpha = 1) {
            cr.set_source_rgba (c.r, c.g, c.b, c.a * alpha);
        }

        public void apply_fill (Cairo.Context cr, RenderContext ctx, Fill f, double x, double y, double w, double h, bool preserve) {
            switch (f.kind) {
                case FillKind.SOLID:
                    set_source (cr, ctx.theme.resolve (f.color));
                    break;
                case FillKind.GRADIENT:
                    Cairo.Pattern pat;
                    if (f.radial) {
                        double r = Math.sqrt (w * w + h * h) / 2;
                        pat = new Cairo.Pattern.radial (x + w / 2, y + h / 2, 0, x + w / 2, y + h / 2, double.min (r, double.max (w, h) / 2));
                    } else {
                        double a = f.angle * Math.PI / 180;
                        double cx = x + w / 2, cy = y + h / 2;
                        double len = (Math.fabs (w * Math.cos (a)) + Math.fabs (h * Math.sin (a))) / 2;
                        pat = new Cairo.Pattern.linear (cx - Math.cos (a) * len, cy - Math.sin (a) * len, cx + Math.cos (a) * len, cy + Math.sin (a) * len);
                    }
                    foreach (var st in f.stops) {
                        var c = ctx.theme.resolve (st.color);
                        pat.add_color_stop_rgba (st.pos, c.r, c.g, c.b, c.a);
                    }
                    cr.set_source (pat);
                    break;
                case FillKind.IMAGE:
                    var surf = f.image != null ? ImageCache.surface (f.image) : null;
                    if (surf == null) {
                        cr.set_source_rgba (0.5, 0.5, 0.5, 1);
                        break;
                    }
                    int iw = surf.get_width (), ih = surf.get_height ();
                    var pat = new Cairo.Pattern.for_surface (surf);
                    var m = Cairo.Matrix.identity ();
                    if (f.tile) {
                        pat.set_extend (Cairo.Extend.REPEAT);
                        m.translate (-x, -y);
                    } else {
                        double sc = double.max (w / iw, h / ih);
                        m = Cairo.Matrix (1 / sc, 0, 0, 1 / sc, 0, 0);
                        m.translate (-(x + (w - iw * sc) / 2), -(y + (h - ih * sc) / 2));
                        pat.set_extend (Cairo.Extend.PAD);
                    }
                    pat.set_matrix (m);
                    pat.set_filter (Cairo.Filter.GOOD);
                    cr.set_source (pat);
                    break;
                default:
                    return;
            }
            if (preserve) cr.fill_preserve ();
            else cr.fill ();
        }

        private void draw_fill_rect (Cairo.Context cr, RenderContext ctx, Fill f, double x, double y, double w, double h) {
            if (f.kind == FillKind.NONE) {
                cr.set_source_rgb (1, 1, 1);
                cr.rectangle (x, y, w, h);
                cr.fill ();
                return;
            }
            cr.rectangle (x, y, w, h);
            apply_fill (cr, ctx, f, x, y, w, h, false);
        }

        private void stroke_line (Cairo.Context cr, RenderContext ctx, Line l) {
            set_source (cr, ctx.theme.resolve (l.color));
            cr.set_line_width (l.width);
            double[] dashes = l.dash.pattern (l.width);
            cr.set_dash (dashes, 0);
            cr.set_line_join (Cairo.LineJoin.MITER);
            cr.set_line_cap (l.dash == DashKind.DOT ? Cairo.LineCap.ROUND : Cairo.LineCap.BUTT);
            cr.stroke_preserve ();
            cr.set_dash (null, 0);
        }

        public void draw_element (Cairo.Context cr, RenderContext ctx, Element e, bool inherited) {
            if (hidden != null && hidden.contains (e.id) && !inherited) return;
            ElementState? st = states != null && !inherited ? states[e.id] : null;
            if (st != null && !st.visible) return;
            double x, y, w, h;
            ctx.pres.effective_geometry (ctx.slide, ctx.layout, ctx.master, e, out x, out y, out w, out h);
            Element el = e;
            if (st != null && st.recolors ()) el = recolored (ctx, e, st);
            cr.save ();
            bool grouped = false;
            if (st != null && !st.is_identity ()) {
                cr.translate (st.dx + st.path_dx, st.dy + st.path_dy);
                if (st.scale != 1 || st.spin != 0 || st.sx != 1 || st.sy != 1) {
                    cr.translate (x + w / 2, y + h / 2);
                    if (st.spin != 0) cr.rotate (st.spin * Math.PI / 180);
                    cr.scale (st.scale * st.sx, st.scale * st.sy);
                    cr.translate (-(x + w / 2), -(y + h / 2));
                }
                if (st.wipe < 1) {
                    double wx = x - w, wy = y - h, ww = w * 3, wh = h * 3;
                    double f = st.wipe.clamp (0, 1);
                    switch (st.wipe_dir) {
                        case Direction.FROM_LEFT: wx = x - w; ww = w + w * f; break;
                        case Direction.FROM_RIGHT: wx = x + w - w * f; ww = w * 2; break;
                        case Direction.FROM_TOP: wy = y - h; wh = h + h * f; break;
                        default: wy = y + h - h * f; wh = h * 2; break;
                    }
                    cr.rectangle (wx, wy, ww, wh);
                    cr.clip ();
                }
                if (st.clip != ClipKind.NONE) Clips.apply (cr, st.clip, st.clip_sub, st.clip_p, x, y, w, h);
                if (st.opacity < 1) {
                    cr.push_group ();
                    grouped = true;
                }
            }
            bool filtered = st != null && (st.desaturate > 0 || st.lightness != 0);
            if (filtered) cr.push_group ();
            if (e.rotation != 0) {
                cr.translate (x + w / 2, y + h / 2);
                cr.rotate (e.rotation * Math.PI / 180);
                cr.translate (-(x + w / 2), -(y + h / 2));
            }
            var saved_paras = para_states;
            para_states = st != null ? st.paras : null;
            draw_kind (cr, ctx, el, x, y, w, h, inherited);
            para_states = saved_paras;
            if (filtered) {
                var pat = cr.pop_group ();
                cr.set_source (pat);
                cr.paint ();
                if (st.desaturate > 0) {
                    cr.set_operator (Cairo.Operator.HSL_SATURATION);
                    cr.set_source_rgba (0.5, 0.5, 0.5, st.desaturate.clamp (0, 1));
                    cr.mask (pat);
                }
                if (st.lightness != 0) {
                    cr.set_operator (Cairo.Operator.ATOP);
                    if (st.lightness > 0) cr.set_source_rgba (1, 1, 1, st.lightness.clamp (0, 1));
                    else cr.set_source_rgba (0, 0, 0, (-st.lightness).clamp (0, 1));
                    cr.mask (pat);
                }
                cr.set_operator (Cairo.Operator.OVER);
            }
            if (grouped) {
                cr.pop_group_to_source ();
                cr.paint_with_alpha (st.opacity.clamp (0, 1));
            }
            cr.restore ();
        }

        private Gee.HashMap<int, ElementState>? para_states = null;
        private int zoom_depth = 0;

        private static string mix_color (RenderContext ctx, string from, string to, double t) {
            if (from == "" || t >= 1) return to;
            var a = ctx.theme.resolve (from), b = ctx.theme.resolve (to);
            return a.mix (b, t.clamp (0, 1)).to_hex ();
        }

        private static string shift_color (RenderContext ctx, string c, double hue) {
            if (c == "" || hue == 0) return c;
            var rgb = ctx.theme.resolve (c);
            double h, s, l;
            rgb.to_hsl (out h, out s, out l);
            h = (h + hue / 360.0) % 1.0;
            if (h < 0) h += 1;
            return Rgba.from_hsl (h, s, l, rgb.a).to_hex ();
        }

        private Element recolored (RenderContext ctx, Element src, ElementState st) {
            var e = src.clone ();
            var sh = e as ShapeElement;
            if (sh != null) {
                if (st.fill_color != "") sh.fill = new Fill.solid (mix_color (ctx, sh.fill.first_color (), st.fill_color, st.color_mix));
                if (st.hue_shift != 0 && sh.fill.first_color () != "") sh.fill = new Fill.solid (shift_color (ctx, sh.fill.first_color (), st.hue_shift));
                if (st.line_color != "") {
                    sh.line.color = mix_color (ctx, sh.line.color, st.line_color, st.color_mix);
                    if (sh.line.width <= 0) sh.line.width = 1;
                }
            }
            var body = e.text_body ();
            if (body != null && (st.text_color != "" || st.bold || st.underline)) {
                body.apply_to_runs ((r) => {
                    if (st.text_color != "") r.color = mix_color (ctx, r.color != "" ? r.color : "tx1", st.text_color, st.color_mix);
                    if (st.bold) r.bold = 1;
                    if (st.underline) r.underline = 1;
                });
            }
            return e;
        }

        private void draw_kind (Cairo.Context cr, RenderContext ctx, Element e, double x, double y, double w, double h, bool inherited) {
            switch (e.kind) {
                case ElementKind.SHAPE:
                    draw_shape (cr, ctx, (ShapeElement) e, x, y, w, h, inherited);
                    break;
                case ElementKind.IMAGE:
                    draw_image (cr, ctx, (ImageElement) e, x, y, w, h);
                    break;
                case ElementKind.TABLE:
                    draw_table (cr, ctx, (TableElement) e, x, y);
                    break;
                case ElementKind.CHART:
                    ChartPainter.draw (cr, ctx, (ChartElement) e, x, y, w, h);
                    break;
                case ElementKind.GROUP:
                    var g = (GroupElement) e;
                    if (e.rotation != 0) {
                        cr.translate (x + w / 2, y + h / 2);
                        cr.rotate (-e.rotation * Math.PI / 180);
                        cr.translate (-(x + w / 2), -(y + h / 2));
                    }
                    foreach (var c in g.children) draw_element (cr, ctx, c, inherited);
                    break;
                case ElementKind.FOREIGN:
                    var f = (ForeignElement) e;
                    if (f.preview != null) {
                        if (f.rotation != 0) {
                            cr.translate (x + w / 2, y + h / 2);
                            cr.rotate (-e.rotation * Math.PI / 180);
                            cr.translate (-(x + w / 2), -(y + h / 2));
                        }
                        draw_element (cr, ctx, f.preview, true);
                    } else {
                        placeholder_box (cr, x, y, w, h, f.display_name ());
                    }
                    break;
                case ElementKind.MEDIA:
                    draw_media (cr, ctx, (MediaElement) e, x, y, w, h);
                    break;
                case ElementKind.INK:
                    draw_ink (cr, ctx, (InkElement) e);
                    break;
                case ElementKind.ZOOM:
                    draw_zoom (cr, ctx, (ZoomElement) e, x, y, w, h);
                    break;
                case ElementKind.DIAGRAM:
                    var d = (DiagramElement) e;
                    if (d.drawing != null && d.pristine ()) {
                        if (d.rotation != 0) {
                            cr.translate (x + w / 2, y + h / 2);
                            cr.rotate (-e.rotation * Math.PI / 180);
                            cr.translate (-(x + w / 2), -(y + h / 2));
                        }
                        draw_element (cr, ctx, d.drawing, true);
                    } else {
                        foreach (var c in d.build ()) draw_element (cr, ctx, c, true);
                    }
                    break;
                case ElementKind.EQUATION:
                    draw_equation (cr, ctx, (EquationElement) e, x, y, w, h);
                    break;
                case ElementKind.MODEL3D:
                    draw_model (cr, (Model3DElement) e, x, y, w, h);
                    break;
            }
        }

        private void draw_model (Cairo.Context cr, Model3DElement m, double x, double y, double w, double h) {
            double dw = w, dh = h;
            cr.user_to_device_distance (ref dw, ref dh);
            int pw = (int) Math.ceil (Math.fabs (dw)).clamp (8, 2400), ph = (int) Math.ceil (Math.fabs (dh)).clamp (8, 2400);
            var surf = MeshPainter.surface (m, pw, ph);
            if (surf == null && m.preview != null) surf = ImageCache.surface (m.preview);
            if (surf == null) {
                placeholder_box (cr, x, y, w, h, m.display_name ());
                return;
            }
            cr.save ();
            cr.translate (x, y);
            cr.scale (w / surf.get_width (), h / surf.get_height ());
            cr.set_source_surface (surf, 0, 0);
            cr.paint ();
            cr.restore ();
        }

        private void placeholder_box (Cairo.Context cr, double x, double y, double w, double h, string label) {
            cr.save ();
            cr.rectangle (x, y, w, h);
            cr.set_source_rgba (0.5, 0.5, 0.5, 0.12);
            cr.fill_preserve ();
            cr.set_source_rgba (0.5, 0.5, 0.5, 0.6);
            cr.set_line_width (1);
            cr.stroke ();
            var l = new Pango.Layout (context ());
            var fd = new Pango.FontDescription ();
            fd.set_family ("Inter");
            fd.set_size ((int) (double.min (14, h / 4) * Pango.SCALE));
            l.set_font_description (fd);
            l.set_width ((int) (w * Pango.SCALE));
            l.set_alignment (Pango.Alignment.CENTER);
            l.set_text (label, -1);
            int lw, lh;
            l.get_size (out lw, out lh);
            cr.move_to (x, y + (h - lh / (double) Pango.SCALE) / 2);
            Pango.cairo_show_layout (cr, l);
            cr.restore ();
        }

        public Gee.HashMap<int, Cairo.ImageSurface>? media_frames = null;

        private void draw_media (Cairo.Context cr, RenderContext ctx, MediaElement m, double x, double y, double w, double h) {
            Cairo.ImageSurface? surf = media_frames != null && media_frames.has_key (m.id) ? media_frames[m.id] : null;
            if (surf == null && m.poster != null) surf = ImageCache.surface (m.poster);
            cr.save ();
            flip_transform (cr, m, x, y, w, h);
            if (surf != null) {
                cr.rectangle (x, y, w, h);
                cr.clip ();
                cr.translate (x, y);
                cr.scale (w / surf.get_width (), h / surf.get_height ());
                cr.set_source_surface (surf, 0, 0);
                cr.get_source ().set_filter (Cairo.Filter.GOOD);
                cr.paint ();
            } else {
                MediaArt.draw (cr, m, x, y, w, h);
            }
            cr.restore ();
            if (m.line.visible ()) {
                cr.save ();
                cr.rectangle (x, y, w, h);
                stroke_line (cr, ctx, m.line);
                cr.new_path ();
                cr.restore ();
            }
        }

        public static void stroke_ink (Cairo.Context cr, RenderContext? ctx, InkStroke s) {
            if (s.pts.size < 2) return;
            Rgba c;
            if (ctx != null) c = ctx.theme.resolve (s.color);
            else if (!Rgba.parse_hex (s.color, out c)) c = Rgba (0, 0, 0, 1);
            cr.save ();
            cr.set_line_cap (s.highlighter ? Cairo.LineCap.SQUARE : Cairo.LineCap.ROUND);
            cr.set_line_join (Cairo.LineJoin.ROUND);
            cr.set_line_width (s.width);
            cr.move_to (s.pts[0], s.pts[1]);
            int n = s.pts.size / 2;
            if (n == 1) cr.line_to (s.pts[0] + 0.01, s.pts[1]);
            for (int i = 1; i < n; i++) {
                double x1 = s.pts[(i - 1) * 2], y1 = s.pts[(i - 1) * 2 + 1];
                double x2 = s.pts[i * 2], y2 = s.pts[i * 2 + 1];
                if (i < n - 1) cr.curve_to (x1 + (x2 - x1) * 0.5, y1 + (y2 - y1) * 0.5, x2, y2, x2, y2);
                else cr.line_to (x2, y2);
            }
            set_source (cr, c, s.highlighter ? 0.4 : s.opacity);
            if (s.highlighter) cr.set_operator (Cairo.Operator.MULTIPLY);
            cr.stroke ();
            cr.restore ();
        }

        private void draw_ink (Cairo.Context cr, RenderContext ctx, InkElement ink) {
            foreach (var s in ink.strokes) stroke_ink (cr, ctx, s);
        }

        private void draw_zoom (Cairo.Context cr, RenderContext ctx, ZoomElement z, double x, double y, double w, double h) {
            Cairo.ImageSurface? surf = null;
            if (z.image != null) surf = ImageCache.surface (z.image);
            var target = z.target (ctx.pres);
            cr.save ();
            cr.rectangle (x, y, w, h);
            cr.clip ();
            if (surf != null) {
                cr.translate (x, y);
                cr.scale (w / surf.get_width (), h / surf.get_height ());
                cr.set_source_surface (surf, 0, 0);
                cr.paint ();
            } else if (target != null && zoom_depth < 2 && target != ctx.slide) {
                zoom_depth++;
                cr.translate (x, y);
                cr.scale (w / ctx.pres.width, h / ctx.pres.height);
                var saved_states = states;
                var saved_hidden = hidden;
                bool saved_edit = edit_mode;
                states = null;
                hidden = null;
                edit_mode = false;
                draw_slide (cr, ctx.pres, target);
                states = saved_states;
                hidden = saved_hidden;
                edit_mode = saved_edit;
                zoom_depth--;
            } else {
                cr.rectangle (x, y, w, h);
                cr.set_source_rgba (0.5, 0.5, 0.5, 0.2);
                cr.fill ();
            }
            cr.restore ();
            cr.save ();
            cr.rectangle (x, y, w, h);
            cr.set_source_rgba (0.75, 0.75, 0.75, 1);
            cr.set_line_width (0.5);
            cr.stroke ();
            cr.restore ();
        }

        private void draw_equation (Cairo.Context cr, RenderContext ctx, EquationElement q, double x, double y, double w, double h) {
            var surf = q.image != null ? ImageCache.surface (q.image) : null;
            if (surf == null) {
                placeholder_box (cr, x, y, w, h, q.latex != "" ? q.latex : _("Equation"));
                return;
            }
            cr.save ();
            cr.translate (x, y);
            cr.scale (w / surf.get_width (), h / surf.get_height ());
            if (q.color != "") {
                set_source (cr, ctx.theme.resolve (q.color));
                cr.mask_surface (surf, 0, 0);
            } else {
                cr.set_source_surface (surf, 0, 0);
                cr.get_source ().set_filter (Cairo.Filter.GOOD);
                cr.paint ();
            }
            cr.restore ();
        }

        private void flip_transform (Cairo.Context cr, Element e, double x, double y, double w, double h) {
            if (!e.flip_h && !e.flip_v) return;
            cr.translate (x + w / 2, y + h / 2);
            cr.scale (e.flip_h ? -1 : 1, e.flip_v ? -1 : 1);
            cr.translate (-(x + w / 2), -(y + h / 2));
        }

        private void draw_shape (Cairo.Context cr, RenderContext ctx, ShapeElement s, double x, double y, double w, double h, bool inherited) {
            var fx = s.effects;
            bool three_d = fx.rot_x != 0 || fx.rot_y != 0;
            if (three_d) {
                cr.save ();
                cr.translate (x + w / 2, y + h / 2);
                double ky = Math.cos (fx.rot_x * Math.PI / 180), kx = Math.cos (fx.rot_y * Math.PI / 180);
                cr.transform (Cairo.Matrix (double.max (Math.fabs (kx), 0.05), Math.sin (fx.rot_y * Math.PI / 180) * 0.15, Math.sin (fx.rot_x * Math.PI / 180) * 0.15, double.max (Math.fabs (ky), 0.05), 0, 0));
                cr.translate (-(x + w / 2), -(y + h / 2));
            }
            if (fx.reflection && !inherited) draw_reflection (cr, ctx, s, x, y, w, h);
            draw_shape_body (cr, ctx, s, x, y, w, h, inherited);
            if (three_d) cr.restore ();
        }

        private void draw_reflection (Cairo.Context cr, RenderContext ctx, ShapeElement s, double x, double y, double w, double h) {
            var fx = s.effects;
            cr.save ();
            cr.push_group ();
            cr.translate (0, 2 * (y + h) + fx.reflection_distance);
            cr.scale (1, -1);
            draw_shape_body (cr, ctx, s, x, y, w, h, false);
            var pat = cr.pop_group ();
            double top = y + h + fx.reflection_distance;
            double len = double.max (h * fx.reflection_size, 1);
            var mask = new Cairo.Pattern.linear (0, top, 0, top + len);
            mask.add_color_stop_rgba (0, 0, 0, 0, fx.reflection_alpha);
            mask.add_color_stop_rgba (1, 0, 0, 0, 0);
            cr.set_source (pat);
            cr.mask (mask);
            cr.restore ();
        }

        private void preset_passes (Cairo.Context cr, RenderContext ctx, ShapeElement s, double x, double y, double w, double h, bool has_fill, bool has_line) {
            string name = s.preset_name ();
            var adj = Geometry.adjust_of (s);
            var sink = new CairoSink (cr);
            if (has_fill) {
                cr.new_path ();
                PresetGeometry.build_each (name, x, y, w, h, adj, sink, (info) => {
                    if (info.fill && info.fill_mode != "none") {
                        cr.set_fill_rule (Cairo.FillRule.EVEN_ODD);
                        apply_fill (cr, ctx, s.fill, x, y, w, h, true);
                        double shade = 0;
                        switch (info.fill_mode) {
                            case "darken": shade = -0.4; break;
                            case "darkenLess": shade = -0.2; break;
                            case "lighten": shade = 0.4; break;
                            case "lightenLess": shade = 0.2; break;
                            default: break;
                        }
                        if (shade < 0) {
                            cr.set_source_rgba (0, 0, 0, -shade);
                            cr.fill_preserve ();
                        } else if (shade > 0) {
                            cr.set_source_rgba (1, 1, 1, shade);
                            cr.fill_preserve ();
                        }
                        cr.set_fill_rule (Cairo.FillRule.WINDING);
                    }
                    cr.new_path ();
                });
            }
            if (has_line) {
                cr.new_path ();
                PresetGeometry.build_each (name, x, y, w, h, adj, sink, (info) => {
                    if (info.stroke) stroke_line (cr, ctx, s.line);
                    cr.new_path ();
                });
            }
        }

        private void draw_shape_body (Cairo.Context cr, RenderContext ctx, ShapeElement s, double x, double y, double w, double h, bool inherited) {
            bool closed = Geometry.is_closed (s);
            bool has_fill = closed && s.fill.kind != FillKind.NONE;
            bool has_line = s.line.visible ();
            var fx = s.effects;
            string pkey = s.shape == ShapeKind.PRESET || s.adjust_values.size > 0 ? s.preset_name () + adjust_key (s) : "";
            if (fx.glow_color != "" && fx.glow_radius > 0 && (has_fill || has_line)) {
                var gc = ctx.theme.resolve (fx.glow_color);
                string key = "g%d:%d:%s:%g".printf (s.id, (int) s.shape, pkey, fx.glow_radius);
                Effects.shadow (cr, key, x, y, w, h, gc, fx.glow_radius, 0, 0, (c) => {
                    flip_shape_path (c, s, x, y, w, h);
                }, true, fx.glow_radius * 2);
            }
            if (s.shadow.enabled && (has_fill || has_line)) {
                var sc = ctx.theme.resolve (s.shadow.color);
                sc.a *= s.shadow.opacity;
                string key = "s%d:%d:%g:%s:%s:%s".printf (s.id, (int) s.shape, s.corner, s.flip_h.to_string (), s.flip_v.to_string (), pkey);
                Effects.shadow (cr, key, x, y, w, h, sc, s.shadow.blur, s.shadow.dx (), s.shadow.dy (), (c) => {
                    flip_shape_path (c, s, x, y, w, h);
                }, !has_fill, s.line.width);
            }
            if (has_fill || has_line) {
                bool soft = fx.soft_edge > 0 && has_fill;
                if (soft) cr.push_group ();
                cr.save ();
                cr.new_path ();
                if (s.shape != ShapeKind.LINE) flip_transform (cr, s, x, y, w, h);
                if (Geometry.uses_preset (s) && PresetGeometry.names ().length > 0 && s.shape != ShapeKind.RECT && s.shape != ShapeKind.ELLIPSE) {
                    preset_passes (cr, ctx, s, x, y, w, h, has_fill, has_line);
                } else {
                    Geometry.path (cr, s, x, y, w, h);
                    if (s.shape == ShapeKind.DONUT) cr.set_fill_rule (Cairo.FillRule.EVEN_ODD);
                    if (has_fill) apply_fill (cr, ctx, s.fill, x, y, w, h, true);
                    if (has_line) stroke_line (cr, ctx, s.line);
                }
                cr.new_path ();
                if (fx.bevel != "" && has_fill) {
                    cr.save ();
                    Geometry.path (cr, s, x, y, w, h);
                    cr.clip_preserve ();
                    var g = new Cairo.Pattern.linear (x, y, x + w, y + h);
                    g.add_color_stop_rgba (0, 1, 1, 1, 0.55);
                    g.add_color_stop_rgba (0.5, 1, 1, 1, 0);
                    g.add_color_stop_rgba (0.5, 0, 0, 0, 0);
                    g.add_color_stop_rgba (1, 0, 0, 0, 0.35);
                    cr.set_source (g);
                    cr.set_line_width (double.max (fx.bevel_width, 1) * 2);
                    cr.stroke ();
                    cr.restore ();
                }
                if (has_line && (s.line.head != ArrowKind.NONE || s.line.tail != ArrowKind.NONE) && s.shape == ShapeKind.LINE) {
                    double x1 = s.flip_h ? x + w : x, y1 = s.flip_v ? y + h : y;
                    double x2 = s.flip_h ? x : x + w, y2 = s.flip_v ? y : y + h;
                    set_source (cr, ctx.theme.resolve (s.line.color));
                    Geometry.arrow_head (cr, s.line.tail, x2, y2, x1, y1, s.line.width);
                    Geometry.arrow_head (cr, s.line.head, x1, y1, x2, y2, s.line.width);
                }
                cr.restore ();
                if (soft) {
                    var pat = cr.pop_group ();
                    double sx, sy;
                    Effects.device_scale (cr, out sx, out sy);
                    double sc = double.min (double.max (sx, sy), 4);
                    if (sc <= 0) sc = 1;
                    double pad = fx.soft_edge * 2 + 2;
                    var mask = Effects.soft_mask (x, y, w, h, fx.soft_edge, sc, (c) => {
                        flip_shape_path (c, s, x, y, w, h);
                    });
                    cr.save ();
                    cr.set_source (pat);
                    if (mask != null) {
                        cr.translate (x - pad, y - pad);
                        cr.scale (1 / sc, 1 / sc);
                        cr.mask_surface (mask, 0, 0);
                    } else {
                        cr.paint ();
                    }
                    cr.restore ();
                }
            }
            bool empty = s.text == null || s.text.is_empty ();
            if (s.placeholder != PlaceholderKind.NONE && edit_mode && !inherited) {
                if (empty && s.id != hidden_text_id) {
                    if (s.placeholder == PlaceholderKind.PICTURE) draw_picture_prompt (cr, ctx, x, y, w, h);
                    draw_prompt_frame (cr, x, y, w, h);
                    draw_prompt (cr, ctx, s, x, y, w, h);
                    return;
                }
            }
            if (s.text != null && !empty && s.id != hidden_text_id) {
                double tx, ty, tw, th;
                Geometry.text_rect (s, x, y, w, h, out tx, out ty, out tw, out th);
                if (fx.has_text_effects ()) TextEffects.draw (this, cr, ctx, s, tx, ty, tw, th, default_text_color (ctx, s));
                else draw_text (cr, ctx, s, s.text, tx, ty, tw, th, default_text_color (ctx, s));
            }
        }

        private static string adjust_key (ShapeElement s) {
            var sb = new StringBuilder ();
            foreach (var e in s.adjust_values.entries) sb.append ("%s=%g,".printf (e.key, e.value));
            return sb.str;
        }

        private void flip_shape_path (Cairo.Context c, ShapeElement s, double x, double y, double w, double h) {
            c.save ();
            if (s.shape != ShapeKind.LINE) flip_transform (c, s, x, y, w, h);
            Geometry.path (c, s, x, y, w, h);
            c.restore ();
        }

        public static void draw_prompt_frame (Cairo.Context cr, double x, double y, double w, double h) {
            cr.save ();
            cr.rectangle (x, y, w, h);
            cr.set_source_rgba (0.5, 0.5, 0.5, 0.6);
            double[] dash = { 4, 3 };
            double sx, sy;
            Effects.device_scale (cr, out sx, out sy);
            cr.set_line_width (1 / double.max (sx, 0.01));
            for (int i = 0; i < dash.length; i++) dash[i] /= double.max (sx, 0.01);
            cr.set_dash (dash, 0);
            cr.stroke ();
            cr.restore ();
        }

        private void draw_picture_prompt (Cairo.Context cr, RenderContext ctx, double x, double y, double w, double h) {
            cr.save ();
            cr.rectangle (x, y, w, h);
            cr.set_source_rgba (0.5, 0.5, 0.5, 0.08);
            cr.fill ();
            double s = double.min (w, h) * 0.18;
            double cx = x + w / 2, cy = y + h / 2 - s * 0.6;
            cr.set_source_rgba (0.5, 0.5, 0.5, 0.55);
            cr.set_line_width (double.max (s * 0.06, 1));
            Geometry.round_rect (cr, cx - s, cy - s * 0.7, s * 2, s * 1.4, s * 0.15);
            cr.stroke ();
            cr.move_to (cx - s * 0.8, cy + s * 0.5);
            cr.line_to (cx - s * 0.25, cy - s * 0.1);
            cr.line_to (cx + s * 0.15, cy + s * 0.3);
            cr.line_to (cx + s * 0.45, cy);
            cr.line_to (cx + s * 0.8, cy + s * 0.5);
            cr.stroke ();
            cr.arc (cx + s * 0.45, cy - s * 0.35, s * 0.14, 0, 2 * Math.PI);
            cr.fill ();
            cr.restore ();
        }

        private void draw_prompt (Cairo.Context cr, RenderContext ctx, ShapeElement s, double x, double y, double w, double h) {
            var body = new TextBody ();
            var src = s.text ?? new TextBody ();
            body.inset_left = src.inset_left;
            body.inset_right = src.inset_right;
            body.inset_top = src.inset_top;
            body.inset_bottom = src.inset_bottom;
            body.anchor = src.anchor;
            body.anchor_set = src.anchor_set;
            var p = new Paragraph (s.placeholder.prompt ());
            if (src.paragraphs.size > 0) {
                p.copy_format (src.paragraphs[0]);
                p.runs[0].copy_format (src.paragraphs[0].end_format);
            }
            body.paragraphs.add (p);
            cr.save ();
            cr.push_group ();
            double tx, ty, tw, th;
            Geometry.text_rect (s, x, y, w, h, out tx, out ty, out tw, out th);
            draw_text (cr, ctx, s, body, tx, ty, tw, th, default_text_color (ctx, s));
            cr.pop_group_to_source ();
            cr.paint_with_alpha (0.45);
            cr.restore ();
        }

        public string default_text_color (RenderContext ctx, Element e) {
            var s = e as ShapeElement;
            if (s == null || s.text_box || s.placeholder != PlaceholderKind.NONE) return "";
            string fc = s.fill.first_color ();
            if (fc == "" || s.fill.kind == FillKind.IMAGE) return "";
            var c = ctx.theme.resolve (fc);
            if (c.a < 0.4) return "";
            return contrast_for (ctx, c);
        }

        public static string contrast_for (RenderContext ctx, Rgba c) {
            var lt = ctx.theme.resolve ("lt1");
            var dk = ctx.theme.resolve ("dk1");
            double lc = Math.fabs (lt.luminance () - c.luminance ());
            double dc = Math.fabs (dk.luminance () - c.luminance ());
            return lc >= dc ? "lt1" : "dk1";
        }

        private static Pango.Context new_context () {
            var fm = Pango.CairoFontMap.get_default () as Pango.CairoFontMap;
            var pc = new Pango.Context ();
            pc.set_font_map (fm);
            Pango.cairo_context_set_resolution (pc, 72);
            var fo = new Cairo.FontOptions ();
            fo.set_hint_metrics (Cairo.HintMetrics.OFF);
            fo.set_hint_style (Cairo.HintStyle.NONE);
            fo.set_antialias (Cairo.Antialias.GRAY);
            Pango.cairo_context_set_font_options (pc, fo);
            pc.set_round_glyph_positions (false);
            return pc;
        }

        public static Pango.Context context () {
            if (measure_context == null) measure_context = new_context ();
            return measure_context;
        }

        private static void add_attr (Pango.AttrList list, owned Pango.Attribute a, int start, int end) {
            a.start_index = start;
            a.end_index = end;
            list.insert ((owned) a);
        }

        public static Pango.FontDescription font_for (RunStyle rs, double scale) {
            var fd = new Pango.FontDescription ();
            fd.set_family (rs.font);
            fd.set_size ((int) Math.round (rs.size * scale * (rs.baseline != 0 ? 0.66 : 1) * Pango.SCALE));
            fd.set_weight (rs.bold ? Pango.Weight.BOLD : Pango.Weight.NORMAL);
            fd.set_style (rs.italic ? Pango.Style.ITALIC : Pango.Style.NORMAL);
            return fd;
        }

        public string field_text (RenderContext ctx, TextRun r) {
            if (r.field == "slidenum") return ctx.number.to_string ();
            if (r.field.has_prefix ("datetime")) return new DateTime.now_local ().format (date_format);
            return r.text;
        }

        public TextLayout layout_text (RenderContext ctx, Element e, TextBody body, double width, string default_color, double scale) {
            var tl = new TextLayout ();
            tl.scale = scale;
            var pc = context ();
            double inner = width - body.inset_left - body.inset_right;
            double y = 0;
            int[] counters = new int[9];
            int prev_level = -1;
            for (int pi = 0; pi < body.paragraphs.size; pi++) {
                var p = body.paragraphs[pi];
                var ls = ctx.pres.level_style (ctx.slide, ctx.layout, ctx.master, e, p.level);
                if (default_color != "") ls.color = default_color;
                var ps = ctx.pres.para_style (ls, p, ctx.theme);
                var layout = new Pango.Layout (pc);
                var attrs = new Pango.AttrList ();
                var sb = new StringBuilder ();
                RunStyle? first = null;
                var starts = new Gee.ArrayList<int> ();
                var ends = new Gee.ArrayList<int> ();
                var refs = new Gee.ArrayList<TextRun> ();
                foreach (var r in p.runs) {
                    string text = r.field != "" ? field_text (ctx, r) : r.text;
                    if (text == "") continue;
                    var rs = ctx.pres.run_style (ls, r, ctx.theme);
                    if (first == null) first = rs;
                    int start = (int) sb.len;
                    string shown = rs.caps ? text.up () : text.replace ("\t", "    ").replace ("\v", "\n");
                    sb.append (shown);
                    int end = (int) sb.len;
                    starts.add (start);
                    ends.add (end);
                    refs.add (r);
                    add_attr (attrs, new Pango.AttrFontDesc (font_for (rs, scale)), start, end);
                    add_attr (attrs, Pango.attr_foreground_new ((uint16) (rs.color.r * 65535), (uint16) (rs.color.g * 65535), (uint16) (rs.color.b * 65535)), start, end);
                    if (rs.color.a < 1) add_attr (attrs, Pango.attr_foreground_alpha_new ((uint16) (rs.color.a * 65535)), start, end);
                    if (rs.underline) add_attr (attrs, Pango.attr_underline_new (Pango.Underline.SINGLE), start, end);
                    if (rs.strike) add_attr (attrs, Pango.attr_strikethrough_new (true), start, end);
                    if (rs.baseline != 0) add_attr (attrs, Pango.attr_rise_new ((int) (rs.size * scale * (rs.baseline > 0 ? 0.33 : -0.12) * Pango.SCALE)), start, end);
                    if (rs.highlight != "") {
                        var hc = ctx.theme.resolve (rs.highlight);
                        add_attr (attrs, Pango.attr_background_new ((uint16) (hc.r * 65535), (uint16) (hc.g * 65535), (uint16) (hc.b * 65535)), start, end);
                    }
                }
                var end_rs = ctx.pres.run_style (ls, p.end_format, ctx.theme);
                if (first == null) first = end_rs;
                layout.set_font_description (font_for (first, scale));
                layout.set_text (sb.str, -1);
                layout.set_attributes (attrs);
                double margin = ps.margin;
                double indent = ps.indent;
                double lx = margin;
                string bullet = "";
                if (ps.bullet == BulletKind.CHAR && sb.len > 0) bullet = ps.bullet_char;
                if (ps.bullet == BulletKind.NUMBER && sb.len > 0) {
                    int lv = p.level.clamp (0, 8);
                    if (prev_level < 0 || prev_level < lv) counters[lv] = 0;
                    for (int k = lv + 1; k < 9; k++) counters[k] = 0;
                    counters[lv]++;
                    bullet = p.number_style.label (p.number_start - 1 + counters[lv]);
                } else if (sb.len > 0) {
                    counters[p.level.clamp (0, 8)] = 0;
                }
                prev_level = p.level;
                double text_w = inner - margin;
                if (bullet == "") {
                    if (indent < 0) {
                        lx = margin + indent;
                        text_w = inner - lx;
                        layout.set_indent ((int) (indent * Pango.SCALE));
                    } else if (indent > 0) {
                        layout.set_indent ((int) (indent * Pango.SCALE));
                    }
                }
                if (body.wrap && text_w > 1) {
                    layout.set_width ((int) (text_w * Pango.SCALE));
                    layout.set_wrap (Pango.WrapMode.WORD_CHAR);
                } else {
                    layout.set_width (-1);
                }
                switch (ps.align) {
                    case TextAlign.CENTER: layout.set_alignment (Pango.Alignment.CENTER); break;
                    case TextAlign.RIGHT: layout.set_alignment (Pango.Alignment.RIGHT); break;
                    case TextAlign.JUSTIFY:
                        layout.set_alignment (Pango.Alignment.LEFT);
                        layout.set_justify (true);
                        break;
                    default: layout.set_alignment (Pango.Alignment.LEFT); break;
                }
                double lsp = ps.line_spacing * (1 - body.line_reduction);
                if (lsp > 0 && Math.fabs (lsp - 1) > 0.001) layout.set_line_spacing ((float) (lsp * 1.0));
                if (!body.wrap || text_w <= 1) {
                    int lw, lh;
                    layout.get_size (out lw, out lh);
                    if (ps.align == TextAlign.CENTER) lx = (inner - lw / (double) Pango.SCALE) / 2;
                    else if (ps.align == TextAlign.RIGHT) lx = inner - lw / (double) Pango.SCALE;
                }
                int pw, ph;
                layout.get_size (out pw, out ph);
                double before = pi > 0 ? ps.space_before * scale : 0;
                y += before;
                var pl = new ParaLayout ();
                pl.layout = layout;
                pl.x = lx;
                pl.y = y;
                pl.width = text_w;
                pl.height = ph / (double) Pango.SCALE;
                pl.index = pi;
                pl.run_starts = starts;
                pl.run_ends = ends;
                pl.runs = refs;
                if (bullet != "") {
                    pl.bullet = bullet;
                    var brs = first;
                    pl.bullet_font = font_for (brs, scale);
                    pl.bullet_color = ps.bullet_color != "" ? ctx.theme.resolve (ps.bullet_color) : brs.color;
                    pl.bullet_x = margin + indent;
                    var bl = new Pango.Layout (pc);
                    bl.set_font_description (pl.bullet_font);
                    bl.set_text (bullet + " ", -1);
                    int bw, bh;
                    bl.get_size (out bw, out bh);
                    double bullet_end = pl.bullet_x + bw / (double) Pango.SCALE;
                    if (bullet_end > margin) {
                        layout.set_indent ((int) ((bullet_end - margin) * Pango.SCALE));
                        layout.get_size (out pw, out ph);
                        pl.height = ph / (double) Pango.SCALE;
                    }
                }
                tl.paras.add (pl);
                y += pl.height + ps.space_after * scale;
            }
            tl.height = y;
            return tl;
        }

        public TextLayout fit_text (RenderContext ctx, Element e, TextBody body, double w, double h, string default_color) {
            var tl = layout_text (ctx, e, body, w, default_color, body.autofit == AutoFit.SHRINK ? 1 : 1);
            if (body.autofit != AutoFit.SHRINK) return tl;
            double avail = h - body.inset_top - body.inset_bottom;
            if (tl.height <= avail || avail <= 0) {
                body.font_scale = 1;
                body.line_reduction = 0;
                return tl;
            }
            double lo = 0.25, hi = 1;
            TextLayout best = layout_text (ctx, e, body, w, default_color, lo);
            for (int i = 0; i < 7; i++) {
                double mid = (lo + hi) / 2;
                var t = layout_text (ctx, e, body, w, default_color, mid);
                if (t.height <= avail) {
                    lo = mid;
                    best = t;
                } else {
                    hi = mid;
                }
            }
            body.font_scale = Math.floor (lo * 40) / 40;
            return best;
        }

        public double text_height (RenderContext ctx, Element e, TextBody body, double w) {
            var tl = layout_text (ctx, e, body, w, default_text_color (ctx, e), 1);
            return tl.height + body.inset_top + body.inset_bottom;
        }

        public TextRun? run_at (RenderContext ctx, Element e, double px, double py) {
            var s = e as ShapeElement;
            if (s == null || s.text == null || s.text.is_empty ()) return null;
            double x, y, w, h;
            ctx.pres.effective_geometry (ctx.slide, ctx.layout, ctx.master, e, out x, out y, out w, out h);
            if (e.rotation != 0) {
                double a = -e.rotation * Math.PI / 180;
                double cx = x + w / 2, cy = y + h / 2;
                double dx = px - cx, dy = py - cy;
                px = cx + dx * Math.cos (a) - dy * Math.sin (a);
                py = cy + dx * Math.sin (a) + dy * Math.cos (a);
            }
            double tx, ty, tw, th;
            Geometry.text_rect (s, x, y, w, h, out tx, out ty, out tw, out th);
            var body = s.text;
            var tl = fit_text (ctx, e, body, tw, th, default_text_color (ctx, s));
            var anchor = ctx.pres.effective_anchor (ctx.slide, ctx.layout, ctx.master, e, body);
            double avail = th - body.inset_top - body.inset_bottom;
            double oy = ty + body.inset_top;
            if (anchor == TextAnchor.MIDDLE) oy += (avail - tl.height) / 2;
            else if (anchor == TextAnchor.BOTTOM) oy += avail - tl.height;
            double ox = tx + body.inset_left;
            foreach (var pl in tl.paras) {
                double lx = px - (ox + pl.x), ly = py - (oy + pl.y);
                if (ly < 0 || ly > pl.height) continue;
                int idx, trailing;
                if (!pl.layout.xy_to_index ((int) (lx * Pango.SCALE), (int) (ly * Pango.SCALE), out idx, out trailing)) return null;
                for (int i = 0; i < pl.runs.size; i++) if (idx >= pl.run_starts[i] && idx < pl.run_ends[i]) return pl.runs[i];
            }
            return null;
        }

        public void draw_text (Cairo.Context cr, RenderContext ctx, Element e, TextBody body, double x, double y, double w, double h, string default_color) {
            var tl = fit_text (ctx, e, body, w, h, default_color);
            var anchor = ctx.pres.effective_anchor (ctx.slide, ctx.layout, ctx.master, e, body);
            double avail = h - body.inset_top - body.inset_bottom;
            double oy = y + body.inset_top;
            if (anchor == TextAnchor.MIDDLE) oy += (avail - tl.height) / 2;
            else if (anchor == TextAnchor.BOTTOM) oy += avail - tl.height;
            double ox = x + body.inset_left;
            cr.save ();
            foreach (var pl in tl.paras) {
                ElementState? ps = para_states != null && para_states.has_key (pl.index) ? para_states[pl.index] : null;
                if (ps != null && !ps.visible) continue;
                bool pgroup = false;
                if (ps != null) {
                    cr.save ();
                    cr.translate (ps.dx + ps.path_dx, ps.dy + ps.path_dy);
                    double pcx = ox + pl.x + pl.width / 2, pcy = oy + pl.y + pl.height / 2;
                    if (ps.scale != 1 || ps.sx != 1 || ps.sy != 1 || ps.spin != 0) {
                        cr.translate (pcx, pcy);
                        cr.rotate (ps.spin * Math.PI / 180);
                        cr.scale (ps.scale * ps.sx, ps.scale * ps.sy);
                        cr.translate (-pcx, -pcy);
                    }
                    if (ps.clip != ClipKind.NONE) Clips.apply (cr, ps.clip, ps.clip_sub, ps.clip_p, ox + pl.x, oy + pl.y, double.max (pl.width, 1), double.max (pl.height, 1));
                    if (ps.opacity < 1) {
                        cr.push_group ();
                        pgroup = true;
                    }
                }
                cr.move_to (ox + pl.x, oy + pl.y);
                Pango.cairo_show_layout (cr, pl.layout);
                if (pl.bullet != "") {
                    var bl = new Pango.Layout (context ());
                    bl.set_font_description (pl.bullet_font);
                    bl.set_text (pl.bullet, -1);
                    var iter = pl.layout.get_iter ();
                    int baseline = iter.get_baseline ();
                    set_source (cr, pl.bullet_color);
                    cr.move_to (ox + pl.bullet_x, oy + pl.y + baseline / (double) Pango.SCALE - bl.get_baseline () / (double) Pango.SCALE);
                    Pango.cairo_show_layout (cr, bl);
                }
                if (ps != null) {
                    if (pgroup) {
                        cr.pop_group_to_source ();
                        cr.paint_with_alpha (ps.opacity.clamp (0, 1));
                    }
                    cr.restore ();
                }
            }
            cr.restore ();
        }

        private void draw_image (Cairo.Context cr, RenderContext ctx, ImageElement img, double x, double y, double w, double h) {
            var surf = ImageCache.filtered (img);
            if (img.shadow.enabled) {
                var sc = ctx.theme.resolve (img.shadow.color);
                sc.a *= img.shadow.opacity;
                string key = "i%d:%g".printf (img.id, img.corner);
                Effects.shadow (cr, key, x, y, w, h, sc, img.shadow.blur, img.shadow.dx (), img.shadow.dy (), (c) => {
                    Geometry.round_rect (c, x, y, w, h, img.corner * double.min (w, h));
                }, false, 0);
            }
            cr.save ();
            flip_transform (cr, img, x, y, w, h);
            Geometry.round_rect (cr, x, y, w, h, img.corner * double.min (w, h));
            if (surf == null) {
                cr.set_source_rgba (0.6, 0.6, 0.6, 0.4);
                cr.fill ();
                cr.restore ();
                return;
            }
            cr.clip ();
            int iw = surf.get_width (), ih = surf.get_height ();
            double sx0 = img.crop_left * iw, sy0 = img.crop_top * ih;
            double sw = iw * (1 - img.crop_left - img.crop_right), sh = ih * (1 - img.crop_top - img.crop_bottom);
            if (sw <= 0 || sh <= 0) {
                cr.restore ();
                return;
            }
            cr.translate (x, y);
            cr.scale (w / sw, h / sh);
            cr.translate (-sx0, -sy0);
            cr.set_source_surface (surf, 0, 0);
            var pat = cr.get_source ();
            pat.set_filter (Cairo.Filter.GOOD);
            pat.set_extend (Cairo.Extend.PAD);
            if (img.opacity < 1) cr.paint_with_alpha (img.opacity);
            else cr.paint ();
            cr.restore ();
            if (img.line.visible ()) {
                cr.save ();
                Geometry.round_rect (cr, x, y, w, h, img.corner * double.min (w, h));
                stroke_line (cr, ctx, img.line);
                cr.new_path ();
                cr.restore ();
            }
        }

        public string table_cell_fill (TableElement t, int r, int c) {
            var cell = t.cells[r][c];
            if (cell.fill != "") return cell.fill;
            string sc = t.style_color;
            if (t.first_row && r == 0) return sc;
            if (t.last_row && r == t.rows - 1) return sc;
            if (t.first_col && c == 0) return ColorSpec.tint (sc, 0.75, 0);
            if (t.banded_rows) {
                int k = t.first_row ? r - 1 : r;
                return k % 2 == 0 ? ColorSpec.tint (sc, 0.2, 0.8) : ColorSpec.tint (sc, 0.4, 0.6);
            }
            if (t.banded_cols) {
                int k = t.first_col ? c - 1 : c;
                return k % 2 == 0 ? ColorSpec.tint (sc, 0.2, 0.8) : ColorSpec.tint (sc, 0.4, 0.6);
            }
            return ColorSpec.tint (sc, 0.2, 0.8);
        }

        public bool table_cell_bold (TableElement t, int r, int c) {
            return (t.first_row && r == 0) || (t.first_col && c == 0) || (t.last_row && r == t.rows - 1);
        }

        public int hidden_cell_row = -1;
        public int hidden_cell_col = -1;

        private void draw_table (Cairo.Context cr, RenderContext ctx, TableElement t, double x, double y) {
            double ox = t.x, oy = t.y;
            t.x = x;
            t.y = y;
            for (int r = 0; r < t.rows; r++) {
                for (int c = 0; c < t.cols; c++) {
                    var cell = t.cells[r][c];
                    if (cell.covered) continue;
                    double cx = t.col_x (c), cy = t.row_y (r);
                    double cw = 0, ch = 0;
                    for (int k = c; k < c + cell.col_span && k < t.cols; k++) cw += t.col_widths[k];
                    for (int k = r; k < r + cell.row_span && k < t.rows; k++) ch += t.row_heights[k];
                    string fill = table_cell_fill (t, r, c);
                    var fc = ctx.theme.resolve (fill);
                    cr.rectangle (cx, cy, cw, ch);
                    set_source (cr, fc);
                    cr.fill ();
                    if (t.id == hidden_text_id && r == hidden_cell_row && c == hidden_cell_col) continue;
                    if (!cell.text.is_empty ()) {
                        string col = fc.a > 0.3 ? contrast_for (ctx, fc) : "";
                        bool bold = table_cell_bold (t, r, c);
                        var body = cell.text;
                        if (bold) {
                            body = cell.text.clone ();
                            body.apply_to_runs ((run) => {
                                if (run.bold < 0) run.bold = 1;
                            });
                        }
                        body.anchor = cell.anchor;
                        body.anchor_set = true;
                        draw_text (cr, ctx, t, body, cx, cy, cw, ch, col);
                    }
                }
            }
            if (t.border.visible ()) {
                set_source (cr, ctx.theme.resolve (t.border.color));
                cr.set_line_width (t.border.width);
                for (int r = 0; r < t.rows; r++) {
                    for (int c = 0; c < t.cols; c++) {
                        var cell = t.cells[r][c];
                        if (cell.covered) continue;
                        double cw = 0, ch = 0;
                        for (int k = c; k < c + cell.col_span && k < t.cols; k++) cw += t.col_widths[k];
                        for (int k = r; k < r + cell.row_span && k < t.rows; k++) ch += t.row_heights[k];
                        cr.rectangle (t.col_x (c), t.row_y (r), cw, ch);
                    }
                }
                cr.stroke ();
            }
            t.x = ox;
            t.y = oy;
        }

        public double table_row_needed (RenderContext ctx, TableElement t, int r) {
            double need = 0;
            for (int c = 0; c < t.cols; c++) {
                var cell = t.cells[r][c];
                if (cell.covered || cell.row_span > 1) continue;
                double cw = 0;
                for (int k = c; k < c + cell.col_span && k < t.cols; k++) cw += t.col_widths[k];
                need = double.max (need, text_height (ctx, t, cell.text, cw));
            }
            return need;
        }

        public void fit_table_rows (RenderContext ctx, TableElement t) {
            for (int r = 0; r < t.rows; r++) {
                double need = table_row_needed (ctx, t, r);
                if (need > t.row_heights[r]) t.row_heights[r] = Math.ceil (need);
            }
            t.sync_size ();
        }

        public Cairo.ImageSurface thumbnail (Presentation p, Slide s, int width) {
            int height = (int) Math.round (width * p.height / p.width);
            var surf = new Cairo.ImageSurface (Cairo.Format.ARGB32, int.max (width, 1), int.max (height, 1));
            var cr = new Cairo.Context (surf);
            double sc = width / p.width;
            cr.scale (sc, sc);
            draw_slide (cr, p, s);
            surf.flush ();
            return surf;
        }
    }
}
