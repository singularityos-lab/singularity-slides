namespace Singularity.Apps.Slides {

    public enum DiagramCategory {
        LIST,
        PROCESS,
        CYCLE,
        HIERARCHY,
        RELATIONSHIP,
        MATRIX,
        PYRAMID,
        PICTURE;

        public string label () {
            switch (this) {
                case PROCESS: return _("Process");
                case CYCLE: return _("Cycle");
                case HIERARCHY: return _("Hierarchy");
                case RELATIONSHIP: return _("Relationship");
                case MATRIX: return _("Matrix");
                case PYRAMID: return _("Pyramid");
                case PICTURE: return _("Picture");
                default: return _("List");
            }
        }

        public const DiagramCategory[] ALL = { LIST, PROCESS, CYCLE, HIERARCHY, RELATIONSHIP, MATRIX, PYRAMID, PICTURE };
    }

    public enum DiagramLayout {
        BLOCK_LIST,
        VERTICAL_BULLET_LIST,
        HORIZONTAL_BULLET_LIST,
        VERTICAL_BOX_LIST,
        BASIC_PROCESS,
        ACCENT_PROCESS,
        CHEVRON_PROCESS,
        CONTINUOUS_ARROW,
        VERTICAL_PROCESS,
        BENDING_PROCESS,
        STEP_UP,
        TIMELINE,
        FUNNEL,
        BASIC_CYCLE,
        TEXT_CYCLE,
        CONTINUOUS_CYCLE,
        SEGMENTED_CYCLE,
        RADIAL_CYCLE,
        GEAR,
        ORG_CHART,
        HIERARCHY,
        HORIZONTAL_HIERARCHY,
        BASIC_VENN,
        LINEAR_VENN,
        STACKED_VENN,
        BASIC_RADIAL,
        TARGET,
        BASIC_MATRIX,
        TITLED_MATRIX,
        BASIC_PYRAMID,
        INVERTED_PYRAMID,
        PYRAMID_LIST,
        PICTURE_CAPTION;

        public string label () {
            switch (this) {
                case VERTICAL_BULLET_LIST: return _("Vertical Bullet List");
                case HORIZONTAL_BULLET_LIST: return _("Horizontal Bullet List");
                case VERTICAL_BOX_LIST: return _("Vertical Box List");
                case BASIC_PROCESS: return _("Basic Process");
                case ACCENT_PROCESS: return _("Accent Process");
                case CHEVRON_PROCESS: return _("Basic Chevron Process");
                case CONTINUOUS_ARROW: return _("Continuous Arrow Process");
                case VERTICAL_PROCESS: return _("Vertical Process");
                case BENDING_PROCESS: return _("Basic Bending Process");
                case STEP_UP: return _("Step Up Process");
                case TIMELINE: return _("Basic Timeline");
                case FUNNEL: return _("Funnel");
                case BASIC_CYCLE: return _("Basic Cycle");
                case TEXT_CYCLE: return _("Text Cycle");
                case CONTINUOUS_CYCLE: return _("Continuous Cycle");
                case SEGMENTED_CYCLE: return _("Segmented Cycle");
                case RADIAL_CYCLE: return _("Radial Cycle");
                case GEAR: return _("Gear");
                case ORG_CHART: return _("Organization Chart");
                case HIERARCHY: return _("Hierarchy");
                case HORIZONTAL_HIERARCHY: return _("Horizontal Hierarchy");
                case BASIC_VENN: return _("Basic Venn");
                case LINEAR_VENN: return _("Linear Venn");
                case STACKED_VENN: return _("Stacked Venn");
                case BASIC_RADIAL: return _("Basic Radial");
                case TARGET: return _("Basic Target");
                case BASIC_MATRIX: return _("Basic Matrix");
                case TITLED_MATRIX: return _("Titled Matrix");
                case BASIC_PYRAMID: return _("Basic Pyramid");
                case INVERTED_PYRAMID: return _("Inverted Pyramid");
                case PYRAMID_LIST: return _("Pyramid List");
                case PICTURE_CAPTION: return _("Picture Caption List");
                default: return _("Basic Block List");
            }
        }

        public DiagramCategory category () {
            switch (this) {
                case BASIC_PROCESS: case ACCENT_PROCESS: case CHEVRON_PROCESS: case CONTINUOUS_ARROW: case VERTICAL_PROCESS:
                case BENDING_PROCESS: case STEP_UP: case TIMELINE: case FUNNEL:
                    return DiagramCategory.PROCESS;
                case BASIC_CYCLE: case TEXT_CYCLE: case CONTINUOUS_CYCLE: case SEGMENTED_CYCLE: case RADIAL_CYCLE: case GEAR:
                    return DiagramCategory.CYCLE;
                case ORG_CHART: case HIERARCHY: case HORIZONTAL_HIERARCHY:
                    return DiagramCategory.HIERARCHY;
                case BASIC_VENN: case LINEAR_VENN: case STACKED_VENN: case BASIC_RADIAL: case TARGET:
                    return DiagramCategory.RELATIONSHIP;
                case BASIC_MATRIX: case TITLED_MATRIX:
                    return DiagramCategory.MATRIX;
                case BASIC_PYRAMID: case INVERTED_PYRAMID: case PYRAMID_LIST:
                    return DiagramCategory.PYRAMID;
                case PICTURE_CAPTION:
                    return DiagramCategory.PICTURE;
                default:
                    return DiagramCategory.LIST;
            }
        }

        public string ooxml_id () {
            string n;
            switch (this) {
                case VERTICAL_BULLET_LIST: n = "vList2"; break;
                case HORIZONTAL_BULLET_LIST: n = "hList1"; break;
                case VERTICAL_BOX_LIST: n = "vList5"; break;
                case BASIC_PROCESS: n = "process1"; break;
                case ACCENT_PROCESS: n = "process3"; break;
                case CHEVRON_PROCESS: n = "chevron1"; break;
                case CONTINUOUS_ARROW: n = "hProcess9"; break;
                case VERTICAL_PROCESS: n = "process2"; break;
                case BENDING_PROCESS: n = "process5"; break;
                case STEP_UP: n = "StepUpProcess"; break;
                case TIMELINE: n = "hProcess11"; break;
                case FUNNEL: n = "funnel1"; break;
                case BASIC_CYCLE: n = "cycle2"; break;
                case TEXT_CYCLE: n = "cycle1"; break;
                case CONTINUOUS_CYCLE: n = "cycle3"; break;
                case SEGMENTED_CYCLE: n = "cycle8"; break;
                case RADIAL_CYCLE: n = "radial6"; break;
                case GEAR: n = "gear1"; break;
                case ORG_CHART: n = "orgChart1"; break;
                case HIERARCHY: n = "hierarchy1"; break;
                case HORIZONTAL_HIERARCHY: n = "hierarchy2"; break;
                case BASIC_VENN: n = "venn1"; break;
                case LINEAR_VENN: n = "venn3"; break;
                case STACKED_VENN: n = "venn2"; break;
                case BASIC_RADIAL: n = "radial1"; break;
                case TARGET: n = "target1"; break;
                case BASIC_MATRIX: n = "matrix3"; break;
                case TITLED_MATRIX: n = "matrix1"; break;
                case BASIC_PYRAMID: n = "pyramid1"; break;
                case INVERTED_PYRAMID: n = "pyramid3"; break;
                case PYRAMID_LIST: n = "pyramid2"; break;
                case PICTURE_CAPTION: n = "pList1"; break;
                default: n = "default"; break;
            }
            return "urn:microsoft.com/office/officeart/2005/8/layout/" + n;
        }

        public static DiagramLayout from_ooxml (string? id, string? category) {
            string s = id ?? "";
            foreach (var l in ALL) if (l.ooxml_id () == s) return l;
            string n = s.down ();
            int slash = n.last_index_of ("/");
            if (slash >= 0) n = n.substring (slash + 1);
            if (n.has_prefix ("orgchart")) return ORG_CHART;
            if (n.has_prefix ("hierarchy")) return n.has_suffix ("2") || n.has_suffix ("4") ? HORIZONTAL_HIERARCHY : HIERARCHY;
            if (n.has_prefix ("venn")) return BASIC_VENN;
            if (n.has_prefix ("pyramid")) return BASIC_PYRAMID;
            if (n.has_prefix ("matrix")) return BASIC_MATRIX;
            if (n.has_prefix ("radial")) return BASIC_RADIAL;
            if (n.has_prefix ("target")) return TARGET;
            if (n.has_prefix ("gear")) return GEAR;
            if (n.has_prefix ("funnel")) return FUNNEL;
            if (n.contains ("chevron")) return CHEVRON_PROCESS;
            if (n.has_prefix ("cycle")) return BASIC_CYCLE;
            if (n.contains ("process") || n.has_prefix ("arrow")) return BASIC_PROCESS;
            if (n.has_prefix ("vlist")) return VERTICAL_BULLET_LIST;
            if (n.has_prefix ("hlist")) return HORIZONTAL_BULLET_LIST;
            if (n.has_prefix ("plist") || n.contains ("picture")) return PICTURE_CAPTION;
            switch (category ?? "") {
                case "process": return BASIC_PROCESS;
                case "cycle": return BASIC_CYCLE;
                case "hierarchy": return ORG_CHART;
                case "relationship": return BASIC_VENN;
                case "matrix": return BASIC_MATRIX;
                case "pyramid": return BASIC_PYRAMID;
                case "picture": return PICTURE_CAPTION;
                default: return BLOCK_LIST;
            }
        }

        public string category_id () {
            switch (category ()) {
                case DiagramCategory.PROCESS: return "process";
                case DiagramCategory.CYCLE: return "cycle";
                case DiagramCategory.HIERARCHY: return "hierarchy";
                case DiagramCategory.RELATIONSHIP: return "relationship";
                case DiagramCategory.MATRIX: return "matrix";
                case DiagramCategory.PYRAMID: return "pyramid";
                case DiagramCategory.PICTURE: return "picture";
                default: return "list";
            }
        }

        public const DiagramLayout[] ALL = {
            BLOCK_LIST, VERTICAL_BULLET_LIST, HORIZONTAL_BULLET_LIST, VERTICAL_BOX_LIST, BASIC_PROCESS, ACCENT_PROCESS,
            CHEVRON_PROCESS, CONTINUOUS_ARROW, VERTICAL_PROCESS, BENDING_PROCESS, STEP_UP, TIMELINE, FUNNEL, BASIC_CYCLE,
            TEXT_CYCLE, CONTINUOUS_CYCLE, SEGMENTED_CYCLE, RADIAL_CYCLE, GEAR, ORG_CHART, HIERARCHY, HORIZONTAL_HIERARCHY,
            BASIC_VENN, LINEAR_VENN, STACKED_VENN, BASIC_RADIAL, TARGET, BASIC_MATRIX, TITLED_MATRIX, BASIC_PYRAMID,
            INVERTED_PYRAMID, PYRAMID_LIST, PICTURE_CAPTION
        };
    }

    public enum DiagramColors {
        PRIMARY,
        COLORFUL,
        GRADIENT,
        OUTLINE,
        DARK;

        public string label () {
            switch (this) {
                case COLORFUL: return _("Colorful");
                case GRADIENT: return _("Gradient Range");
                case OUTLINE: return _("Transparent Outline");
                case DARK: return _("Dark");
                default: return _("Primary Theme Color");
            }
        }

        public const DiagramColors[] ALL = { PRIMARY, COLORFUL, GRADIENT, OUTLINE, DARK };
    }

    public enum DiagramStyle {
        FLAT,
        SUBTLE,
        INTENSE,
        OUTLINED;

        public string label () {
            switch (this) {
                case SUBTLE: return _("Subtle Effect");
                case INTENSE: return _("Intense Effect");
                case OUTLINED: return _("Outlined");
                default: return _("Simple Fill");
            }
        }

        public const DiagramStyle[] ALL = { FLAT, SUBTLE, INTENSE, OUTLINED };
    }

    public class DiagramNode {
        public TextBody text = new TextBody ();
        public Gee.ArrayList<DiagramNode> children = new Gee.ArrayList<DiagramNode> ();
        public string color = "";
        public Bytes? image = null;
        public string image_mime = "image/png";

        public DiagramNode (string plain = "") {
            text.set_plain (plain);
        }

        public DiagramNode clone () {
            var n = new DiagramNode ();
            n.text = text.clone ();
            foreach (var c in children) n.children.add (c.clone ());
            n.color = color;
            n.image = image;
            n.image_mime = image_mime;
            return n;
        }

        public string plain () {
            return text.plain_text ().replace ("\n", " ").strip ();
        }

        public void set_plain (string s) {
            text.set_plain (s);
        }

        public int count () {
            int n = 1;
            foreach (var c in children) n += c.count ();
            return n;
        }

        public int depth () {
            int d = 0;
            foreach (var c in children) d = int.max (d, c.depth ());
            return d + 1;
        }

        public int leaves () {
            if (children.size == 0) return 1;
            int n = 0;
            foreach (var c in children) n += c.leaves ();
            return n;
        }
    }

    public class DiagramElement : Element {
        public DiagramLayout layout = DiagramLayout.BLOCK_LIST;
        public DiagramColors colors = DiagramColors.PRIMARY;
        public DiagramStyle style = DiagramStyle.FLAT;
        public Gee.ArrayList<DiagramNode> nodes = new Gee.ArrayList<DiagramNode> ();
        public ForeignElement? original = null;
        public string original_sig = "";
        public Element? drawing = null;
        public string layout_id = "";

        public override ElementKind kind {
            get { return ElementKind.DIAGRAM; }
        }

        public override Element clone () {
            var d = new DiagramElement ();
            copy_base (d);
            d.layout = layout;
            d.colors = colors;
            d.style = style;
            foreach (var n in nodes) d.nodes.add (n.clone ());
            d.original = original != null ? (ForeignElement) original.clone () : null;
            d.original_sig = original_sig;
            d.drawing = drawing != null ? drawing.clone () : null;
            d.layout_id = layout_id;
            return d;
        }

        public string signature () {
            var sb = new StringBuilder ();
            sb.append ("%d|%d|%d|%.2f|%.2f|%.2f|%.2f|%.2f".printf ((int) layout, (int) colors, (int) style, x, y, w, h, rotation));
            foreach (var n in nodes) sig_node (sb, n);
            return sb.str;
        }

        private static void sig_node (StringBuilder sb, DiagramNode n) {
            sb.append ("[");
            sb.append (n.plain ());
            foreach (var p in n.text.paragraphs) foreach (var r in p.runs) sb.append ("%d%d%g%s%s".printf (r.bold, r.italic, r.size, r.color, r.font));
            sb.append (n.color);
            if (n.image != null) sb.append ("%u".printf (n.image.hash ()));
            foreach (var c in n.children) sig_node (sb, c);
            sb.append ("]");
        }

        public bool pristine () {
            return original != null && original_sig != "" && original_sig == signature ();
        }

        public void mark_pristine () {
            original_sig = signature ();
        }

        public override void move_by (double dx, double dy) {
            bool was = pristine ();
            base.move_by (dx, dy);
            if (drawing != null) drawing.move_by (dx, dy);
            if (was) mark_pristine ();
        }

        public override void scale_into (double nx, double ny, double nw, double nh) {
            if (drawing != null) {
                double sx = w > 0 ? nw / w : 1, sy = h > 0 ? nh / h : 1;
                drawing.scale_into (nx + (drawing.x - x) * sx, ny + (drawing.y - y) * sy, drawing.w * sx, drawing.h * sy);
            }
            set_geometry (nx, ny, nw, nh);
            drawing = null;
        }

        public Gee.ArrayList<Element> build () {
            return new DiagramEngine (this).run ();
        }

        public void sample (int count = 3) {
            nodes.clear ();
            for (int i = 0; i < count; i++) nodes.add (new DiagramNode (_("Text")));
            if (layout.category () == DiagramCategory.HIERARCHY) {
                var root = new DiagramNode (_("Text"));
                for (int i = 0; i < 3; i++) root.children.add (new DiagramNode (_("Text")));
                nodes.clear ();
                nodes.add (root);
            }
        }

        public Gee.ArrayList<DiagramNode> flat () {
            var list = new Gee.ArrayList<DiagramNode> ();
            foreach (var n in nodes) collect (n, list);
            return list;
        }

        private static void collect (DiagramNode n, Gee.List<DiagramNode> list) {
            list.add (n);
            foreach (var c in n.children) collect (c, list);
        }

        public DiagramNode? parent_of (DiagramNode target) {
            foreach (var n in nodes) {
                var p = find_parent (n, target);
                if (p != null) return p;
            }
            return null;
        }

        private static DiagramNode? find_parent (DiagramNode n, DiagramNode target) {
            foreach (var c in n.children) {
                if (c == target) return n;
                var p = find_parent (c, target);
                if (p != null) return p;
            }
            return null;
        }

        public Gee.ArrayList<DiagramNode> siblings_of (DiagramNode n) {
            var p = parent_of (n);
            return p != null ? p.children : nodes;
        }

        public void add_after (DiagramNode n, DiagramNode added) {
            var list = siblings_of (n);
            list.insert (list.index_of (n) + 1, added);
        }

        public void add_before (DiagramNode n, DiagramNode added) {
            var list = siblings_of (n);
            list.insert (list.index_of (n), added);
        }

        public bool demote (DiagramNode n) {
            var list = siblings_of (n);
            int i = list.index_of (n);
            if (i <= 0) return false;
            list.remove_at (i);
            list[i - 1].children.add (n);
            return true;
        }

        public bool promote (DiagramNode n) {
            var p = parent_of (n);
            if (p == null) return false;
            var outer = siblings_of (p);
            int pi = outer.index_of (p);
            int ci = p.children.index_of (n);
            var tail = new Gee.ArrayList<DiagramNode> ();
            for (int k = ci + 1; k < p.children.size; k++) tail.add (p.children[k]);
            while (p.children.size > ci) p.children.remove_at (p.children.size - 1);
            n.children.add_all (tail);
            outer.insert (pi + 1, n);
            return true;
        }

        public bool move (DiagramNode n, int delta) {
            var list = siblings_of (n);
            int i = list.index_of (n);
            int j = i + delta;
            if (i < 0 || j < 0 || j >= list.size) return false;
            list.remove_at (i);
            list.insert (j, n);
            return true;
        }

        public void remove (DiagramNode n) {
            var list = siblings_of (n);
            int i = list.index_of (n);
            if (i < 0) return;
            list.remove_at (i);
            for (int k = n.children.size - 1; k >= 0; k--) list.insert (i, n.children[k]);
        }

        public override string display_name () {
            return name != "" ? name : _("SmartArt: %s").printf (layout.label ());
        }
    }

    public class DiagramEngine {
        private DiagramElement d;
        private Gee.ArrayList<Element> result = new Gee.ArrayList<Element> ();
        private double X;
        private double Y;
        private double W;
        private double H;
        private int total = 0;

        public DiagramEngine (DiagramElement d) {
            this.d = d;
            X = d.x;
            Y = d.y;
            W = double.max (d.w, 10);
            H = double.max (d.h, 10);
        }

        private string fill_for (int index, int count, int level) {
            switch (d.colors) {
                case DiagramColors.COLORFUL:
                    return level > 0 ? ColorSpec.tint ("accent%d".printf (index % 6 + 1), 0.2, 0.8) : "accent%d".printf (index % 6 + 1);
                case DiagramColors.GRADIENT:
                    double t = count > 1 ? (double) index / (count - 1) : 0;
                    return level > 0 ? ColorSpec.tint ("accent1", 0.2, 0.8) : ColorSpec.tint ("accent1", 1 - t * 0.5, t * 0.5);
                case DiagramColors.OUTLINE:
                    return "lt1";
                case DiagramColors.DARK:
                    return level > 0 ? ColorSpec.tint ("dk2", 0.2, 0.8) : "dk2";
                default:
                    return level > 0 ? ColorSpec.tint ("accent1", 0.2, 0.8) : "accent1";
            }
        }

        private string text_for (int level) {
            if (d.colors == DiagramColors.OUTLINE || level > 0) return "dk1";
            return "lt1";
        }

        private void style (ShapeElement s, int index, int count, int level) {
            string c = fill_for (index, count, level);
            string ov = index < d.nodes.size && level == 0 ? d.nodes[index].color : "";
            if (ov != "") c = ov;
            if (d.style == DiagramStyle.INTENSE) {
                s.fill = new Fill.gradient (ColorSpec.tint (c, 0.8, 0.2), ColorSpec.tint (c, 0.85, 0), 90);
            } else {
                s.fill = new Fill.solid (c);
            }
            if (d.colors == DiagramColors.OUTLINE || d.style == DiagramStyle.OUTLINED) {
                s.line.color = d.colors == DiagramColors.OUTLINE ? "accent1" : ColorSpec.tint (c, 0.75, 0);
                s.line.width = 1.5;
            } else {
                s.line.color = "lt1";
                s.line.width = 1;
            }
            if (d.style == DiagramStyle.SUBTLE || d.style == DiagramStyle.INTENSE) {
                s.shadow.enabled = true;
                s.shadow.blur = 6;
                s.shadow.distance = 2;
                s.shadow.opacity = 0.3;
            }
        }

        private TextBody body_of (DiagramNode? n, int level, bool with_children, TextAlign align = TextAlign.CENTER) {
            var b = n != null ? n.text.clone () : new TextBody ();
            if (b.paragraphs.size == 0) b.paragraphs.add (new Paragraph ());
            foreach (var p in b.paragraphs) {
                p.align = align;
                p.bullet = BulletKind.NONE;
                foreach (var r in p.runs) if (r.color == "") r.color = text_for (level);
            }
            if (with_children && n != null) {
                foreach (var c in n.children) append_bullets (b, c, 0, text_for (level));
            }
            b.anchor = TextAnchor.MIDDLE;
            b.anchor_set = true;
            b.autofit = AutoFit.SHRINK;
            double ins = double.min (W, H) * 0.015 + 2;
            b.inset_left = ins;
            b.inset_right = ins;
            b.inset_top = ins * 0.5;
            b.inset_bottom = ins * 0.5;
            foreach (var p in b.paragraphs) foreach (var r in p.runs) if (r.size <= 0) r.size = level > 0 ? 16 : 24;
            return b;
        }

        private void append_bullets (TextBody b, DiagramNode n, int depth, string color) {
            var src = n.text.paragraphs.size > 0 ? n.text.paragraphs[0] : new Paragraph ();
            var p = src.clone ();
            p.align = TextAlign.LEFT;
            p.bullet = BulletKind.CHAR;
            p.bullet_char = "•";
            p.level = depth;
            foreach (var r in p.runs) {
                if (r.color == "") r.color = color;
                if (r.size <= 0) r.size = 16;
            }
            b.paragraphs.add (p);
            foreach (var c in n.children) append_bullets (b, c, depth + 1, color);
        }

        private TextBody bullets_of (DiagramNode n, string color) {
            var b = new TextBody ();
            foreach (var c in n.children) append_bullets (b, c, 0, color);
            if (b.paragraphs.size == 0) b.paragraphs.add (new Paragraph ());
            b.anchor = TextAnchor.TOP;
            b.anchor_set = true;
            b.autofit = AutoFit.SHRINK;
            return b;
        }

        private ShapeElement box (double x, double y, double w, double h, string preset, int index, int count, int level, TextBody? text) {
            var s = new ShapeElement (ShapeKind.PRESET);
            s.preset = preset;
            if (ShapeKind.is_native (preset)) s.shape = ShapeKind.from_ooxml (preset);
            if (s.shape == ShapeKind.ROUND_RECT) s.corner = 0.1;
            s.set_geometry (X + x, Y + y, double.max (w, 1), double.max (h, 1));
            style (s, index, count, level);
            s.text = text;
            s.id = ++total;
            result.add (s);
            return s;
        }

        private ShapeElement label (double x, double y, double w, double h, DiagramNode n, TextAlign align, string color = "dk1") {
            var s = new ShapeElement (ShapeKind.RECT);
            s.text_box = true;
            s.set_geometry (X + x, Y + y, double.max (w, 1), double.max (h, 1));
            s.fill = new Fill.none ();
            s.line.color = "";
            var b = body_of (n, 1, false, align);
            foreach (var p in b.paragraphs) foreach (var r in p.runs) r.color = color;
            s.text = b;
            s.id = ++total;
            result.add (s);
            return s;
        }

        private void line (double x1, double y1, double x2, double y2, string color = "accent1", bool arrow = false) {
            var s = new ShapeElement (ShapeKind.LINE);
            double lx = double.min (x1, x2), ly = double.min (y1, y2);
            s.set_geometry (X + lx, Y + ly, Math.fabs (x2 - x1), Math.fabs (y2 - y1));
            s.flip_h = x2 < x1;
            s.flip_v = y2 < y1;
            s.fill = new Fill.none ();
            s.line.color = d.colors == DiagramColors.OUTLINE ? "accent1" : ColorSpec.tint (color, 0.75, 0);
            s.line.width = 1.5;
            if (arrow) s.line.tail = ArrowKind.TRIANGLE;
            s.id = ++total;
            result.add (s);
        }

        private void arrow (double cx, double cy, double size, double angle_deg, int index, int count) {
            var s = box (cx - size / 2, cy - size * 0.35, size, size * 0.7, "rightArrow", index, count, 1, null);
            s.fill = new Fill.solid (ColorSpec.tint (fill_for (index, count, 0), 0.6, 0.4));
            s.line.color = "";
            s.shadow.enabled = false;
            s.rotation = angle_deg;
        }

        public Gee.ArrayList<Element> run () {
            var n = d.nodes;
            if (n.size == 0) return result;
            switch (d.layout) {
                case DiagramLayout.VERTICAL_BULLET_LIST: vertical_bullets (); break;
                case DiagramLayout.HORIZONTAL_BULLET_LIST: horizontal_bullets (); break;
                case DiagramLayout.VERTICAL_BOX_LIST: vertical_box (); break;
                case DiagramLayout.BASIC_PROCESS: process (false); break;
                case DiagramLayout.ACCENT_PROCESS: process (true); break;
                case DiagramLayout.CHEVRON_PROCESS: chevrons (); break;
                case DiagramLayout.CONTINUOUS_ARROW: continuous_arrow (); break;
                case DiagramLayout.VERTICAL_PROCESS: vertical_process (); break;
                case DiagramLayout.BENDING_PROCESS: bending (); break;
                case DiagramLayout.STEP_UP: step_up (); break;
                case DiagramLayout.TIMELINE: timeline (); break;
                case DiagramLayout.FUNNEL: funnel (); break;
                case DiagramLayout.BASIC_CYCLE: cycle (true, false); break;
                case DiagramLayout.TEXT_CYCLE: cycle (false, false); break;
                case DiagramLayout.CONTINUOUS_CYCLE: cycle (true, true); break;
                case DiagramLayout.SEGMENTED_CYCLE: segmented (); break;
                case DiagramLayout.RADIAL_CYCLE: radial (true); break;
                case DiagramLayout.BASIC_RADIAL: radial (false); break;
                case DiagramLayout.GEAR: gears (); break;
                case DiagramLayout.ORG_CHART: tree (true, true); break;
                case DiagramLayout.HIERARCHY: tree (true, false); break;
                case DiagramLayout.HORIZONTAL_HIERARCHY: tree (false, false); break;
                case DiagramLayout.BASIC_VENN: venn (); break;
                case DiagramLayout.LINEAR_VENN: linear_venn (); break;
                case DiagramLayout.STACKED_VENN: stacked_venn (); break;
                case DiagramLayout.TARGET: target (); break;
                case DiagramLayout.BASIC_MATRIX: matrix (false); break;
                case DiagramLayout.TITLED_MATRIX: matrix (true); break;
                case DiagramLayout.BASIC_PYRAMID: pyramid (false, false); break;
                case DiagramLayout.INVERTED_PYRAMID: pyramid (true, false); break;
                case DiagramLayout.PYRAMID_LIST: pyramid (false, true); break;
                case DiagramLayout.PICTURE_CAPTION: pictures (); break;
                default: block_list (); break;
            }
            return result;
        }

        private void grid (int count, double aspect, out int cols, out int rows, out double cw, out double ch, double gap) {
            int best = 1;
            double best_size = 0;
            for (int c = 1; c <= count; c++) {
                int r = (count + c - 1) / c;
                double w = (W - gap * (c - 1)) / c;
                double h = (H - gap * (r - 1)) / r;
                double size = double.min (w, h * aspect);
                if (size > best_size) {
                    best_size = size;
                    best = c;
                }
            }
            cols = best;
            rows = (count + best - 1) / best;
            cw = best_size;
            ch = best_size / aspect;
        }

        private void block_list () {
            int n = d.nodes.size;
            double gap = double.min (W, H) * 0.04;
            int cols, rows;
            double cw, ch;
            grid (n, 1.6, out cols, out rows, out cw, out ch, gap);
            double oy = (H - rows * ch - (rows - 1) * gap) / 2;
            for (int i = 0; i < n; i++) {
                int r = i / cols, c = i % cols;
                int in_row = r == rows - 1 ? n - r * cols : cols;
                double ox = (W - in_row * cw - (in_row - 1) * gap) / 2;
                box (ox + c * (cw + gap), oy + r * (ch + gap), cw, ch, "rect", i, n, 0, body_of (d.nodes[i], 0, true));
            }
        }

        private void vertical_bullets () {
            int n = d.nodes.size;
            double gap = H * 0.02;
            double units = 0;
            foreach (var node in d.nodes) units += 1 + node.children.size * 0.7;
            double unit = (H - gap * (n - 1)) / double.max (units, 1);
            double y = 0;
            for (int i = 0; i < n; i++) {
                var node = d.nodes[i];
                double hh = unit;
                box (0, y, W, hh, "roundRect", i, n, 0, body_of (node, 0, false, TextAlign.LEFT));
                y += hh;
                if (node.children.size > 0) {
                    double bh = unit * node.children.size * 0.7;
                    var s = box (0, y, W, bh, "rect", i, n, 1, bullets_of (node, "dk1"));
                    s.fill = new Fill.none ();
                    s.line.color = "";
                    s.shadow.enabled = false;
                    y += bh;
                }
                y += gap;
            }
        }

        private void horizontal_bullets () {
            int n = d.nodes.size;
            double gap = W * 0.02;
            double cw = (W - gap * (n - 1)) / n;
            for (int i = 0; i < n; i++) {
                double x = i * (cw + gap);
                box (x, 0, cw, H * 0.25, "rect", i, n, 0, body_of (d.nodes[i], 0, false));
                var s = box (x, H * 0.25, cw, H * 0.75, "rect", i, n, 1, bullets_of (d.nodes[i], "dk1"));
                s.shadow.enabled = false;
            }
        }

        private void vertical_box () {
            int n = d.nodes.size;
            double gap = H * 0.03;
            double rh = (H - gap * (n - 1)) / n;
            for (int i = 0; i < n; i++) {
                double y = i * (rh + gap);
                var back = box (W * 0.1, y, W * 0.9, rh, "rect", i, n, 1, bullets_of (d.nodes[i], "dk1"));
                back.text.inset_left = W * 0.3;
                back.shadow.enabled = false;
                box (0, y + rh * 0.15, W * 0.35, rh * 0.7, "roundRect", i, n, 0, body_of (d.nodes[i], 0, false));
            }
        }

        private void process (bool accent) {
            int n = d.nodes.size;
            double aw = W * 0.06;
            double bw = (W - aw * 1.6 * (n - 1)) / n;
            double bh = double.min (H * (accent ? 0.35 : 0.6), bw * 0.9);
            double y = accent ? H * 0.1 : (H - bh) / 2;
            for (int i = 0; i < n; i++) {
                double x = i * (bw + aw * 1.6);
                box (x, y, bw, bh, "roundRect", i, n, 0, body_of (d.nodes[i], 0, !accent));
                if (accent && d.nodes[i].children.size > 0) {
                    var s = box (x + bw * 0.1, y + bh * 0.8, bw * 0.8, H - y - bh * 0.8 - H * 0.05, "rect", i, n, 1, bullets_of (d.nodes[i], "dk1"));
                    s.shadow.enabled = false;
                    result.remove (s);
                    result.insert (result.size - 1, s);
                }
                if (i < n - 1) arrow (x + bw + aw * 0.8, y + bh / 2, aw, 0, i, n);
            }
        }

        private void chevrons () {
            int n = d.nodes.size;
            double overlap = 0.12;
            double cw = W / (n - overlap * (n - 1));
            double ch = double.min (H, cw * 0.4);
            double y = (H - ch) / 2;
            for (int i = 0; i < n; i++) box (i * cw * (1 - overlap), y, cw, ch, i == 0 ? "homePlate" : "chevron", i, n, 0, body_of (d.nodes[i], 0, true));
        }

        private void continuous_arrow () {
            int n = d.nodes.size;
            var back = box (0, 0, W, H, "rightArrow", 0, n, 1, null);
            back.shadow.enabled = false;
            back.line.color = "";
            double cw = W * 0.85 / n;
            double s = double.min (cw * 0.85, H * 0.45);
            for (int i = 0; i < n; i++) box (i * cw + (cw - s) / 2, (H - s) / 2, s, s, "roundRect", i, n, 0, body_of (d.nodes[i], 0, true));
        }

        private void vertical_process () {
            int n = d.nodes.size;
            double ah = H * 0.08;
            double bh = (H - ah * 1.5 * (n - 1)) / n;
            double bw = double.min (W, bh * 3.5);
            double x = (W - bw) / 2;
            for (int i = 0; i < n; i++) {
                double y = i * (bh + ah * 1.5);
                box (x, y, bw, bh, "roundRect", i, n, 0, body_of (d.nodes[i], 0, true));
                if (i < n - 1) arrow (W / 2, y + bh + ah * 0.75, ah, 90, i, n);
            }
        }

        private void bending () {
            int n = d.nodes.size;
            int cols = int.max (1, (int) Math.ceil (Math.sqrt (n * W / H / 1.4)));
            int rows = (n + cols - 1) / cols;
            double aw = W * 0.05;
            double cw = (W - aw * 1.6 * (cols - 1)) / cols;
            double ch = double.min ((H - H * 0.08 * (rows - 1)) / rows, cw * 0.6);
            double gapy = rows > 1 ? (H - ch * rows) / (rows - 1) : 0;
            for (int i = 0; i < n; i++) {
                int r = i / cols, c = i % cols;
                double x = c * (cw + aw * 1.6), y = r * (ch + gapy);
                box (x, y, cw, ch, "rect", i, n, 0, body_of (d.nodes[i], 0, true));
                if (i < n - 1) {
                    if (c < cols - 1) arrow (x + cw + aw * 0.8, y + ch / 2, aw, 0, i, n);
                    else line (x + cw / 2, y + ch, cols > 1 ? cw / 2 : x + cw / 2, y + ch + gapy, "accent1", true);
                }
            }
        }

        private void step_up () {
            int n = d.nodes.size;
            double sw = W / n;
            double sh = H / (n + 1);
            for (int i = 0; i < n; i++) {
                double x = i * sw;
                double y = H - (i + 1) * sh - sh;
                var s = box (x, y + sh, sw, H - y - sh, "rect", i, n, 1, null);
                s.shadow.enabled = false;
                s.line.color = "";
                box (x, y, sw, sh, "rect", i, n, 0, body_of (d.nodes[i], 0, true));
            }
        }

        private void timeline () {
            int n = d.nodes.size;
            line (0, H / 2, W, H / 2, "accent1", true);
            double cw = W / n;
            double r = double.min (cw, H) * 0.12;
            for (int i = 0; i < n; i++) {
                double cx = cw * (i + 0.5);
                box (cx - r / 2, H / 2 - r / 2, r, r, "ellipse", i, n, 0, null);
                bool above = i % 2 == 0;
                label (cx - cw / 2, above ? H * 0.05 : H / 2 + r, cw, H / 2 - r - H * 0.05, d.nodes[i], TextAlign.CENTER);
            }
        }

        private void funnel () {
            int n = d.nodes.size;
            int top = int.max (n - 1, 1);
            double fw = double.min (W * 0.6, H * 0.9);
            double fx = (W - fw) / 2;
            var f = box (fx, H * 0.25, fw, H * 0.5, "funnel", 0, n, 1, null);
            f.fill = new Fill.solid (ColorSpec.tint ("accent1", 0.4, 0.6));
            double r = double.min (fw / (top + 1), H * 0.25);
            for (int i = 0; i < top && i < n; i++) {
                double cx = fx + fw * (i + 1) / (top + 1);
                box (cx - r / 2, H * 0.28 + r * 0.2 * (i % 2), r, r, "ellipse", i, n, 0, body_of (d.nodes[i], 0, false));
            }
            if (n > 1) {
                double lw = fw * 0.8;
                box ((W - lw) / 2, H * 0.8, lw, H * 0.2, "roundRect", n - 1, n, 0, body_of (d.nodes[n - 1], 0, true));
            }
        }

        private void cycle (bool shapes, bool ring) {
            int n = d.nodes.size;
            double cx = W / 2, cy = H / 2;
            double R0 = double.min (W, H) * 0.36;
            double s = double.min (2 * Math.PI * R0 / n * 0.55, double.min (W, H) * 0.3);
            double R = double.min (W, H) / 2 - s / 2 - 2;
            if (ring) {
                double rr = R * 1.02;
                var arc = box (cx - rr, cy - rr, rr * 2, rr * 2, "blockArc", 0, n, 1, null);
                arc.adjust_values["adj1"] = 10800000;
                arc.adjust_values["adj2"] = 10799999;
                arc.adjust_values["adj3"] = 8000;
                arc.fill = new Fill.solid (ColorSpec.tint ("accent1", 0.4, 0.6));
                arc.line.color = "";
            }
            for (int i = 0; i < n; i++) {
                double a = -Math.PI / 2 + 2 * Math.PI * i / n;
                double px = cx + R * Math.cos (a), py = cy + R * Math.sin (a);
                if (shapes) box (px - s / 2, py - s / 2, s, s, ring ? "roundRect" : "ellipse", i, n, 0, body_of (d.nodes[i], 0, true));
                else label (px - s, py - s / 2, s * 2, s, d.nodes[i], TextAlign.CENTER);
                if (!ring && n > 1) {
                    double am = a + Math.PI / n;
                    arrow (cx + R * Math.cos (am), cy + R * Math.sin (am), s * 0.3, am * 180 / Math.PI + 90, i, n);
                }
            }
        }

        private void segmented () {
            int n = d.nodes.size;
            double s = double.min (W, H) * 0.95;
            double ox = (W - s) / 2, oy = (H - s) / 2;
            for (int i = 0; i < n; i++) {
                double a1 = -90 + 360.0 * i / n, a2 = a1 + 360.0 / n;
                var p = box (ox, oy, s, s, "pie", i, n, 0, null);
                p.adjust_values["adj1"] = ((a1 % 360) + 360) % 360 * 60000;
                p.adjust_values["adj2"] = ((a2 % 360) + 360) % 360 * 60000;
                double am = (a1 + a2) / 2 * Math.PI / 180;
                double tx = W / 2 + s * 0.3 * Math.cos (am), ty = H / 2 + s * 0.3 * Math.sin (am);
                label (tx - s * 0.18, ty - s * 0.1, s * 0.36, s * 0.2, d.nodes[i], TextAlign.CENTER, text_for (0));
            }
        }

        private void radial (bool cycle_ring) {
            var center = d.nodes[0];
            var spokes = center.children.size > 0 ? center.children : new Gee.ArrayList<DiagramNode> ();
            if (spokes.size == 0) for (int i = 1; i < d.nodes.size; i++) spokes.add (d.nodes[i]);
            int n = spokes.size;
            double cx = W / 2, cy = H / 2;
            double S = double.min (W, H);
            double R = S * 0.36;
            double cs = S * 0.3;
            double s = n > 0 ? double.min (2 * Math.PI * R / n * 0.6, S * 0.24) : 0;
            for (int i = 0; i < n; i++) {
                double a = -Math.PI / 2 + 2 * Math.PI * i / n;
                if (!cycle_ring) line (cx + cs / 2 * Math.cos (a), cy + cs / 2 * Math.sin (a), cx + (R - s / 2) * Math.cos (a), cy + (R - s / 2) * Math.sin (a));
            }
            if (cycle_ring && n > 0) {
                var ring = box (cx - R, cy - R, R * 2, R * 2, "donut", 0, n, 1, null);
                ring.adjust_values["adj"] = 4000;
                ring.line.color = "";
            }
            box (cx - cs / 2, cy - cs / 2, cs, cs, "ellipse", 0, n + 1, 0, body_of (center, 0, false));
            for (int i = 0; i < n; i++) {
                double a = -Math.PI / 2 + 2 * Math.PI * i / n;
                box (cx + R * Math.cos (a) - s / 2, cy + R * Math.sin (a) - s / 2, s, s, "ellipse", i + 1, n + 1, 0, body_of (spokes[i], 0, true));
            }
        }

        private void gears () {
            int n = int.min (d.nodes.size, 3);
            double S = double.min (W, H);
            double[,] pos = { { 0.3, 0.55, 0.52 }, { 0.62, 0.3, 0.38 }, { 0.72, 0.72, 0.3 } };
            double ox = (W - S * 1.0) / 2;
            for (int i = 0; i < n; i++) {
                double sz = S * pos[i, 2];
                box (ox + S * pos[i, 0] - sz / 2, S * pos[i, 1] - sz / 2, sz, sz, i == 0 ? "gear9" : "gear6", i, n, 0, body_of (d.nodes[i], 0, true));
            }
            for (int i = 3; i < d.nodes.size; i++) label (0, H - H * 0.1 * (d.nodes.size - i), W, H * 0.1, d.nodes[i], TextAlign.LEFT);
        }

        private class Placed {
            public DiagramNode node;
            public double cx;
            public int depth;
            public Gee.ArrayList<Placed> kids = new Gee.ArrayList<Placed> ();
        }

        private double cursor = 0;

        private Placed place (DiagramNode n, int depth) {
            var p = new Placed ();
            p.node = n;
            p.depth = depth;
            if (n.children.size == 0) {
                p.cx = cursor + 0.5;
                cursor += 1;
                return p;
            }
            foreach (var c in n.children) p.kids.add (place (c, depth + 1));
            p.cx = (p.kids[0].cx + p.kids[p.kids.size - 1].cx) / 2;
            return p;
        }

        private void tree (bool vertical, bool org) {
            cursor = 0;
            var roots = new Gee.ArrayList<Placed> ();
            int depth = 0;
            foreach (var r in d.nodes) {
                roots.add (place (r, 0));
                depth = int.max (depth, r.depth ());
            }
            double leaves = double.max (cursor, 1);
            double along = vertical ? W : H;
            double across = vertical ? H : W;
            double slot = along / leaves;
            double level = across / depth;
            double bw = slot * 0.85;
            double bh = level * 0.6;
            if (vertical) bh = double.min (bh, bw * 0.7);
            else bw = double.min (bw, bh * 0.7);
            int idx = 0;
            foreach (var r in roots) draw_tree (r, vertical, slot, level, bw, bh, ref idx);
        }

        private void draw_tree (Placed p, bool vertical, double slot, double level, double bw, double bh, ref int idx) {
            double a = p.cx * slot;
            double b = p.depth * level + level * 0.2;
            foreach (var k in p.kids) {
                double ka = k.cx * slot, kb = k.depth * level + level * 0.2;
                double mid = b + (vertical ? bh : bw) + (kb - b - (vertical ? bh : bw)) / 2;
                if (vertical) {
                    line (a, b + bh, a, mid, "accent1");
                    line (a < ka ? a : ka, mid, a < ka ? ka : a, mid, "accent1");
                    line (ka, mid, ka, kb, "accent1");
                } else {
                    line (b + bw, a, mid, a, "accent1");
                    line (mid, a < ka ? a : ka, mid, a < ka ? ka : a, "accent1");
                    line (mid, ka, kb, ka, "accent1");
                }
            }
            int my = idx++;
            if (vertical) box (a - bw / 2, b, bw, bh, "rect", my, 6, 0, body_of (p.node, 0, false));
            else box (b, a - bh / 2, bw, bh, "roundRect", my, 6, 0, body_of (p.node, 0, false));
            foreach (var k in p.kids) draw_tree (k, vertical, slot, level, bw, bh, ref idx);
        }

        private void venn () {
            int n = d.nodes.size;
            double S = double.min (W, H);
            double r = n == 1 ? S * 0.45 : S / (2 * 1.75);
            double R = n == 1 ? 0 : r * 0.75;
            for (int i = 0; i < n; i++) {
                double a = -Math.PI / 2 + 2 * Math.PI * i / n;
                double cx = W / 2 + R * Math.cos (a), cy = H / 2 + R * Math.sin (a);
                var c = box (cx - r, cy - r, r * 2, r * 2, "ellipse", i, n, 0, null);
                c.fill = new Fill.solid (ColorSpec.with_alpha (fill_for (i, n, 0), 0.5));
                c.shadow.enabled = false;
                double tx = W / 2 + (R + r * 0.45) * Math.cos (a), ty = H / 2 + (R + r * 0.45) * Math.sin (a);
                label (tx - r * 0.6, ty - r * 0.3, r * 1.2, r * 0.6, d.nodes[i], TextAlign.CENTER);
            }
        }

        private void linear_venn () {
            int n = d.nodes.size;
            double r = double.min (H / 2, W / (2 + (n - 1) * 1.5) );
            double step = r * 1.5;
            double ox = (W - (2 * r + step * (n - 1))) / 2;
            for (int i = 0; i < n; i++) {
                var c = box (ox + i * step, H / 2 - r, r * 2, r * 2, "ellipse", i, n, 0, body_of (d.nodes[i], 0, true));
                c.fill = new Fill.solid (ColorSpec.with_alpha (fill_for (i, n, 0), 0.55));
                foreach (var p in c.text.paragraphs) foreach (var rr in p.runs) rr.color = "dk1";
            }
        }

        private void stacked_venn () {
            int n = d.nodes.size;
            double S = double.min (W, H);
            double ox = (W - S) / 2;
            for (int i = 0; i < n; i++) {
                double s = S * (1 - (double) i / (n + 0.5));
                var c = box (ox + (S - s) / 2, H - s, s, s, "ellipse", i, n, 0, null);
                c.fill = new Fill.solid (ColorSpec.with_alpha (fill_for (i, n, 0), 0.6));
                double next = S * (1 - (double) (i + 1) / (n + 0.5));
                label (ox, H - s, S, (s - next) * 0.9 + S * 0.02, d.nodes[i], TextAlign.CENTER, text_for (0));
            }
        }

        private void target () {
            int n = d.nodes.size;
            double S = H;
            for (int i = 0; i < n; i++) {
                double s = S * (1 - (double) i / n);
                var c = box ((S - s) / 2, (H - s) / 2, s, s, "ellipse", i, n, 0, null);
                c.shadow.enabled = false;
                double ly = H * (i + 0.5) / n;
                line (S / 2, (H - s) / 2 + S / n * 0.25, S * 1.1, ly, "dk1");
                label (S * 1.12, ly - H / n * 0.45, W - S * 1.12, H / n * 0.9, d.nodes[i], TextAlign.LEFT);
            }
        }

        private void matrix (bool titled) {
            var items = new Gee.ArrayList<DiagramNode> ();
            DiagramNode? title = null;
            if (titled && d.nodes[0].children.size > 0) {
                title = d.nodes[0];
                items.add_all (d.nodes[0].children);
                for (int i = 1; i < d.nodes.size; i++) items.add (d.nodes[i]);
            } else {
                items.add_all (d.nodes);
            }
            double S = double.min (W, H);
            double ox = (W - S) / 2;
            double g = S * 0.02;
            double q = (S - g) / 2;
            for (int i = 0; i < 4 && i < items.size; i++) {
                int r = i / 2, c = i % 2;
                box (ox + c * (q + g), r * (q + g), q, q, titled ? "roundRect" : "rect", i, 4, 0, body_of (items[i], 0, true));
            }
            if (title != null) {
                double t = S * 0.34;
                var s = box (ox + (S - t) / 2, (S - t * 0.6) / 2, t, t * 0.6, "roundRect", 0, 4, 1, body_of (title, 1, false));
                s.fill = new Fill.solid ("lt1");
            }
        }

        private void pyramid (bool inverted, bool list) {
            int n = d.nodes.size;
            double pw = list ? W * 0.55 : W;
            double gap = H * 0.01;
            double bh = (H - gap * (n - 1)) / n;
            for (int i = 0; i < n; i++) {
                int k = inverted ? n - 1 - i : i;
                double top_w = pw * k / n, bot_w = pw * (k + 1) / n;
                if (inverted) {
                    top_w = pw * (k + 1) / n;
                    bot_w = pw * k / n;
                }
                double bw = double.max (top_w, bot_w);
                var s = new ShapeElement (ShapeKind.CUSTOM);
                double y = i * (bh + gap);
                s.set_geometry (X + (pw - bw) / 2, Y + y, bw, bh);
                double l1 = (bw - top_w) / 2 / bw, l2 = (bw - bot_w) / 2 / bw;
                s.path.add (new PathCommand ('M', { l1, 0 }));
                s.path.add (new PathCommand ('L', { 1 - l1, 0 }));
                s.path.add (new PathCommand ('L', { 1 - l2, 1 }));
                s.path.add (new PathCommand ('L', { l2, 1 }));
                s.path.add (new PathCommand ('Z', {}));
                style (s, i, n, 0);
                if (!list) s.text = body_of (d.nodes[i], 0, true);
                s.id = ++total;
                result.add (s);
                if (list) {
                    var t = box (pw * 0.45, y + bh * 0.1, W - pw * 0.45, bh * 0.8, "roundRect", i, n, 1, body_of (d.nodes[i], 1, true));
                    t.fill = new Fill.solid ("lt1");
                    t.line.color = "accent1";
                }
            }
        }

        private void pictures () {
            int n = d.nodes.size;
            double gap = double.min (W, H) * 0.04;
            int cols, rows;
            double cw, ch;
            grid (n, 0.9, out cols, out rows, out cw, out ch, gap);
            double oy = (H - rows * ch - (rows - 1) * gap) / 2;
            for (int i = 0; i < n; i++) {
                int r = i / cols, c = i % cols;
                int in_row = r == rows - 1 ? n - r * cols : cols;
                double ox = (W - in_row * cw - (in_row - 1) * gap) / 2;
                double x = ox + c * (cw + gap), y = oy + r * (ch + gap);
                var pic = box (x, y, cw, ch * 0.72, "rect", i, n, 1, null);
                if (d.nodes[i].image != null) pic.fill = new Fill.picture (d.nodes[i].image, d.nodes[i].image_mime);
                box (x, y + ch * 0.72, cw, ch * 0.28, "rect", i, n, 0, body_of (d.nodes[i], 0, false));
            }
        }
    }
}
