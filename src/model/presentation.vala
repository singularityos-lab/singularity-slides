namespace Singularity.Apps.Slides {

    public class RunStyle {
        public string font = "Inter";
        public double size = 18;
        public bool bold = false;
        public bool italic = false;
        public bool underline = false;
        public bool strike = false;
        public Rgba color = Rgba (0, 0, 0, 1);
        public string highlight = "";
        public int baseline = 0;
        public bool caps = false;
    }

    public class ParaStyle {
        public TextAlign align = TextAlign.LEFT;
        public BulletKind bullet = BulletKind.NONE;
        public string bullet_char = "•";
        public string bullet_color = "";
        public double margin = 0;
        public double indent = 0;
        public double space_before = 0;
        public double space_after = 0;
        public double line_spacing = 1;
    }

    public class DocProperties {
        public string title = "";
        public string author = "";
        public string subject = "";
        public string keywords = "";
        public string created = "";
        public string modified = "";

        public DocProperties clone () {
            var p = new DocProperties ();
            p.title = title;
            p.author = author;
            p.subject = subject;
            p.keywords = keywords;
            p.created = created;
            p.modified = modified;
            return p;
        }
    }

    public class Presentation {
        public double width = 960;
        public double height = 540;
        public Gee.ArrayList<Master> masters = new Gee.ArrayList<Master> ();
        public Gee.ArrayList<Slide> slides = new Gee.ArrayList<Slide> ();
        public DocProperties properties = new DocProperties ();
        public bool loop = false;
        public bool use_timings = true;
        public string footer_text = "";
        public string date_text = "";
        public Gee.ArrayList<CustomShow> custom_shows = new Gee.ArrayList<CustomShow> ();
        public Gee.ArrayList<ForeignRel> extra_parts = new Gee.ArrayList<ForeignRel> ();
        public Gee.ArrayList<ForeignElement> extras = new Gee.ArrayList<ForeignElement> ();
        public Gee.ArrayList<EmbeddedFont> fonts = new Gee.ArrayList<EmbeddedFont> ();
        public bool embed_fonts = false;
        public Gee.ArrayList<string> warnings = new Gee.ArrayList<string> ();
        public int show_kind = 0;
        public int show_from = 0;
        public int show_to = 0;
        public string show_custom = "";
        public bool show_narration = true;
        public bool show_animation = true;
        public string pen_color = "#ff0000";
        public Gee.ArrayList<double?> guides_x = new Gee.ArrayList<double?> ();
        public Gee.ArrayList<double?> guides_y = new Gee.ArrayList<double?> ();
        public double grid_spacing = 12;
        public bool snap_to_grid = false;
        public bool show_grid = false;
        public bool show_guides = false;
        public bool show_ruler = false;

        public Presentation clone () {
            var p = new Presentation ();
            p.width = width;
            p.height = height;
            foreach (var m in masters) p.masters.add (m.clone ());
            foreach (var s in slides) p.slides.add (s.clone ());
            p.properties = properties.clone ();
            p.loop = loop;
            p.use_timings = use_timings;
            p.footer_text = footer_text;
            p.date_text = date_text;
            foreach (var c in custom_shows) p.custom_shows.add (c.clone ());
            p.extra_parts.add_all (extra_parts);
            p.extras.add_all (extras);
            p.fonts.add_all (fonts);
            p.embed_fonts = embed_fonts;
            p.warnings.add_all (warnings);
            p.show_kind = show_kind;
            p.show_from = show_from;
            p.show_to = show_to;
            p.show_custom = show_custom;
            p.show_narration = show_narration;
            p.show_animation = show_animation;
            p.pen_color = pen_color;
            p.guides_x.add_all (guides_x);
            p.guides_y.add_all (guides_y);
            p.grid_spacing = grid_spacing;
            p.snap_to_grid = snap_to_grid;
            p.show_grid = show_grid;
            p.show_guides = show_guides;
            p.show_ruler = show_ruler;
            return p;
        }

        public Master master {
            owned get { return masters[0]; }
        }

        public Theme theme {
            owned get { return masters[0].theme; }
        }

        public Master master_for (Slide s) {
            foreach (var m in masters) if (m.find_layout (s.layout_id) != null) return m;
            return masters[0];
        }

        public Layout? layout_for (Slide s) {
            foreach (var m in masters) {
                var l = m.find_layout (s.layout_id);
                if (l != null) return l;
            }
            return null;
        }

        public Master? master_of_layout (Layout l) {
            foreach (var m in masters) if (m.layouts.contains (l)) return m;
            return null;
        }

        public Layout? find_layout (string id) {
            foreach (var m in masters) {
                var l = m.find_layout (id);
                if (l != null) return l;
            }
            return null;
        }

        public Gee.ArrayList<Layout> all_layouts () {
            var list = new Gee.ArrayList<Layout> ();
            foreach (var m in masters) list.add_all (m.layouts);
            return list;
        }

        public int max_id () {
            int mx = 0;
            foreach (var s in slides) foreach (var e in s.elements) mx = int.max (mx, max_in (e));
            foreach (var s in slides) Slide.reserve_uid (s.uid);
            foreach (var m in masters) {
                foreach (var e in m.elements) mx = int.max (mx, max_in (e));
                foreach (var l in m.layouts) foreach (var e in l.elements) mx = int.max (mx, max_in (e));
            }
            return mx;
        }

        private static int max_in (Element e) {
            int mx = e.id;
            var g = e as GroupElement;
            if (g != null) foreach (var c in g.children) mx = int.max (mx, max_in (c));
            return mx;
        }

        private int id_counter = 0;

        public int new_id () {
            if (id_counter == 0) id_counter = max_id ();
            id_counter = int.max (id_counter, max_id ()) + 1;
            return id_counter;
        }

        public void assign_ids (Element e) {
            e.id = new_id ();
            var g = e as GroupElement;
            if (g != null) foreach (var c in g.children) assign_ids (c);
        }

        public Fill background_for (Slide s) {
            if (s.background != null) return s.background;
            var l = layout_for (s);
            if (l != null && l.background != null) return l.background;
            return master_for (s).background;
        }

        public Element? inherited_placeholder (Slide? s, Layout? layout, Master m, Element e) {
            if (e.placeholder == PlaceholderKind.NONE) return null;
            if (s != null && layout != null) {
                var lp = layout.find_placeholder (e.placeholder, e.placeholder_idx);
                if (lp != null) return lp;
            }
            if (s == null && layout != null) return m.find_placeholder (e.placeholder);
            return m.find_placeholder (e.placeholder);
        }

        public void placeholder_chain (Slide? s, Layout? layout, Master m, Element e, Gee.List<Element> chain) {
            if (e.placeholder == PlaceholderKind.NONE) return;
            if (s != null && layout != null) {
                var lp = layout.find_placeholder (e.placeholder, e.placeholder_idx);
                if (lp != null && lp != e) chain.add (lp);
            }
            if (s != null || layout != null) {
                var mp = m.find_placeholder (e.placeholder);
                if (mp != null && mp != e) chain.add (mp);
            }
        }

        public void effective_geometry (Slide? s, Layout? layout, Master m, Element e, out double x, out double y, out double w, out double h) {
            x = e.x;
            y = e.y;
            w = e.w;
            h = e.h;
            if (!e.inherit_geometry) return;
            var chain = new Gee.ArrayList<Element> ();
            placeholder_chain (s, layout, m, e, chain);
            foreach (var p in chain) {
                if (!p.inherit_geometry) {
                    x = p.x;
                    y = p.y;
                    w = p.w;
                    h = p.h;
                    return;
                }
            }
        }

        public TextStyle base_style (Master m, Element e) {
            if (e.placeholder.is_title ()) return m.title_style;
            if (e.placeholder == PlaceholderKind.NONE || e.placeholder.is_meta ()) return m.other_style;
            return m.body_style;
        }

        public LevelStyle level_style (Slide? s, Layout? layout, Master m, Element e, int level) {
            var result = new LevelStyle ();
            result.overlay (base_style (m, e).level (level));
            var chain = new Gee.ArrayList<Element> ();
            placeholder_chain (s, layout, m, e, chain);
            for (int i = chain.size - 1; i >= 0; i--) {
                var sh = chain[i] as ShapeElement;
                if (sh != null && sh.list_style != null) result.overlay (sh.list_style.level (level));
            }
            var own = e as ShapeElement;
            if (own != null && own.list_style != null) result.overlay (own.list_style.level (level));
            return result;
        }

        public TextBody? inherited_body (Slide? s, Layout? layout, Master m, Element e) {
            var chain = new Gee.ArrayList<Element> ();
            placeholder_chain (s, layout, m, e, chain);
            foreach (var p in chain) {
                var body = p.text_body ();
                if (body != null && body.anchor_set) return body;
            }
            return null;
        }

        public TextAnchor effective_anchor (Slide? s, Layout? layout, Master m, Element e, TextBody body) {
            if (body.anchor_set || e.placeholder == PlaceholderKind.NONE) return body.anchor;
            var ib = inherited_body (s, layout, m, e);
            if (ib != null) return ib.anchor;
            return e.placeholder.is_title () ? TextAnchor.MIDDLE : TextAnchor.TOP;
        }

        public ParaStyle para_style (LevelStyle ls, Paragraph p, Theme theme) {
            var ps = new ParaStyle ();
            ps.align = p.align != TextAlign.INHERIT ? p.align : (ls.align != TextAlign.INHERIT ? ls.align : TextAlign.LEFT);
            BulletKind bk = p.bullet != BulletKind.INHERIT ? p.bullet : ls.bullet;
            ps.bullet = bk == BulletKind.INHERIT ? BulletKind.NONE : bk;
            ps.bullet_char = p.bullet == BulletKind.CHAR && p.bullet_char != "" ? p.bullet_char : (ls.bullet_char != "" ? ls.bullet_char : "•");
            ps.bullet_color = p.bullet_color;
            ps.margin = ls.margin >= 0 ? ls.margin : 0;
            ps.indent = ls.indent;
            if (ps.bullet == BulletKind.NONE && p.bullet == BulletKind.NONE && ps.indent < 0 && ls.bullet != BulletKind.NONE) {
                ps.margin = 0;
                ps.indent = 0;
            }
            ps.space_before = p.space_before >= 0 ? p.space_before : (ls.space_before >= 0 ? ls.space_before : 0);
            ps.space_after = p.space_after >= 0 ? p.space_after : (ls.space_after >= 0 ? ls.space_after : 0);
            ps.line_spacing = p.line_spacing > 0 ? p.line_spacing : (ls.line_spacing > 0 ? ls.line_spacing : 1);
            return ps;
        }

        public RunStyle run_style (LevelStyle ls, TextRun r, Theme theme) {
            var rs = new RunStyle ();
            rs.font = theme.resolve_font (r.font != "" ? r.font : ls.font);
            rs.size = r.size > 0 ? r.size : (ls.size > 0 ? ls.size : 18);
            rs.bold = r.bold >= 0 ? r.bold == 1 : ls.bold == 1;
            rs.italic = r.italic >= 0 ? r.italic == 1 : ls.italic == 1;
            rs.underline = r.underline == 1 || (r.underline < 0 && r.link != "");
            rs.strike = r.strike == 1;
            string c = r.color != "" ? r.color : (r.link != "" ? "hlink" : (ls.color != "" ? ls.color : "tx1"));
            rs.color = theme.resolve (c);
            rs.highlight = r.highlight;
            rs.baseline = r.baseline;
            rs.caps = ls.caps;
            return rs;
        }

        public Slide? slide_by_uid (int uid) {
            foreach (var s in slides) if (s.uid == uid) return s;
            return null;
        }

        public int index_of_uid (int uid) {
            for (int i = 0; i < slides.size; i++) if (slides[i].uid == uid) return i;
            return -1;
        }

        public string section_name_of (int index) {
            for (int i = index; i >= 0 && i < slides.size; i--) if (slides[i].section != null) return slides[i].section.name;
            return "";
        }

        public int section_start (int index) {
            for (int i = index; i >= 0 && i < slides.size; i--) if (slides[i].section != null) return i;
            return -1;
        }

        public int section_end (int start) {
            int i = start + 1;
            while (i < slides.size && slides[i].section == null) i++;
            return i;
        }

        public Gee.ArrayList<Slide> section_slides (string id) {
            var list = new Gee.ArrayList<Slide> ();
            for (int i = 0; i < slides.size; i++) {
                if (slides[i].section != null && slides[i].section.id == id) {
                    int end = section_end (i);
                    for (int k = i; k < end; k++) list.add (slides[k]);
                    break;
                }
            }
            return list;
        }

        public bool has_sections () {
            foreach (var s in slides) if (s.section != null) return true;
            return false;
        }

        public CustomShow? find_custom_show (string name) {
            foreach (var c in custom_shows) if (c.name == name) return c;
            return null;
        }

        public int comment_count () {
            int n = 0;
            foreach (var s in slides) n += s.comments.size;
            return n;
        }

        public int slide_number (Slide s) {
            return slides.index_of (s) + 1;
        }

        public string aspect_label () {
            double r = width / height;
            if ((r - 16.0 / 9).abs () < 0.02) return "16:9";
            if ((r - 4.0 / 3).abs () < 0.02) return "4:3";
            if ((r - 16.0 / 10).abs () < 0.02) return "16:10";
            return "%g:%g".printf (Math.round (width), Math.round (height));
        }
    }
}

namespace Singularity.Apps.Slides {

    public class EmbeddedFont {
        public string family;
        public Bytes regular;
        public Bytes? bold = null;
        public Bytes? italic = null;
        public Bytes? bold_italic = null;

        public EmbeddedFont (string family, Bytes regular) {
            this.family = family;
            this.regular = regular;
        }
    }
}
