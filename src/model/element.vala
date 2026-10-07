namespace Singularity.Apps.Slides {

    public enum FillKind {
        NONE,
        SOLID,
        GRADIENT,
        IMAGE
    }

    public class GradientStop {
        public double pos;
        public string color;

        public GradientStop (double pos, string color) {
            this.pos = pos;
            this.color = color;
        }
    }

    public class Fill {
        public FillKind kind = FillKind.NONE;
        public string color = "";
        public Gee.ArrayList<GradientStop> stops = new Gee.ArrayList<GradientStop> ();
        public double angle = 90;
        public bool radial = false;
        public Bytes? image = null;
        public string image_mime = "";
        public bool tile = false;

        public Fill.none () {
            kind = FillKind.NONE;
        }

        public Fill.solid (string color) {
            kind = FillKind.SOLID;
            this.color = color;
        }

        public Fill.gradient (string c1, string c2, double angle, bool radial = false) {
            kind = FillKind.GRADIENT;
            stops.add (new GradientStop (0, c1));
            stops.add (new GradientStop (1, c2));
            this.angle = angle;
            this.radial = radial;
            color = c1;
        }

        public Fill.picture (Bytes data, string mime) {
            kind = FillKind.IMAGE;
            image = data;
            image_mime = mime;
        }

        public Fill clone () {
            var f = new Fill ();
            f.kind = kind;
            f.color = color;
            foreach (var s in stops) f.stops.add (new GradientStop (s.pos, s.color));
            f.angle = angle;
            f.radial = radial;
            f.image = image;
            f.image_mime = image_mime;
            f.tile = tile;
            return f;
        }

        public string first_color () {
            if (kind == FillKind.SOLID) return color;
            if (kind == FillKind.GRADIENT && stops.size > 0) return stops[0].color;
            return "";
        }
    }

    public enum DashKind {
        SOLID,
        DASH,
        DOT,
        DASH_DOT,
        LONG_DASH;

        public string to_ooxml () {
            switch (this) {
                case DASH: return "dash";
                case DOT: return "sysDot";
                case DASH_DOT: return "dashDot";
                case LONG_DASH: return "lgDash";
                default: return "solid";
            }
        }

        public static DashKind from_ooxml (string s) {
            switch (s) {
                case "dash": case "sysDash": return DASH;
                case "dot": case "sysDot": return DOT;
                case "dashDot": case "sysDashDot": case "lgDashDot": return DASH_DOT;
                case "lgDash": return LONG_DASH;
                default: return SOLID;
            }
        }

        public double[] pattern (double width) {
            double w = double.max (width, 1);
            switch (this) {
                case DASH: return { 4 * w, 3 * w };
                case DOT: return { w, w };
                case DASH_DOT: return { 4 * w, 2 * w, w, 2 * w };
                case LONG_DASH: return { 8 * w, 3 * w };
                default: return {};
            }
        }
    }

    public enum ArrowKind {
        NONE,
        TRIANGLE,
        ARROW,
        OVAL,
        DIAMOND;

        public string to_ooxml () {
            switch (this) {
                case TRIANGLE: return "triangle";
                case ARROW: return "arrow";
                case OVAL: return "oval";
                case DIAMOND: return "diamond";
                default: return "none";
            }
        }

        public static ArrowKind from_ooxml (string s) {
            switch (s) {
                case "triangle": return TRIANGLE;
                case "arrow": case "stealth": return ARROW;
                case "oval": return OVAL;
                case "diamond": return DIAMOND;
                default: return NONE;
            }
        }
    }

    public class Line {
        public string color = "";
        public double width = 1;
        public DashKind dash = DashKind.SOLID;
        public ArrowKind head = ArrowKind.NONE;
        public ArrowKind tail = ArrowKind.NONE;

        public Line clone () {
            var l = new Line ();
            l.color = color;
            l.width = width;
            l.dash = dash;
            l.head = head;
            l.tail = tail;
            return l;
        }

        public bool visible () {
            return color != "" && width > 0;
        }
    }

    public class Shadow {
        public bool enabled = false;
        public string color = "#000000";
        public double opacity = 0.35;
        public double blur = 8;
        public double distance = 4;
        public double angle = 90;

        public Shadow clone () {
            var s = new Shadow ();
            s.enabled = enabled;
            s.color = color;
            s.opacity = opacity;
            s.blur = blur;
            s.distance = distance;
            s.angle = angle;
            return s;
        }

        public double dx () {
            return distance * Math.cos (angle * Math.PI / 180);
        }

        public double dy () {
            return distance * Math.sin (angle * Math.PI / 180);
        }
    }

    public enum PlaceholderKind {
        NONE,
        TITLE,
        CENTER_TITLE,
        SUBTITLE,
        BODY,
        OBJECT,
        PICTURE,
        DATE,
        FOOTER,
        SLIDE_NUMBER,
        CHART,
        TABLE,
        MEDIA,
        DIAGRAM,
        CLIP_ART;

        public string to_ooxml () {
            switch (this) {
                case TITLE: return "title";
                case CENTER_TITLE: return "ctrTitle";
                case SUBTITLE: return "subTitle";
                case BODY: return "body";
                case PICTURE: return "pic";
                case DATE: return "dt";
                case FOOTER: return "ftr";
                case SLIDE_NUMBER: return "sldNum";
                case CHART: return "chart";
                case TABLE: return "tbl";
                case MEDIA: return "media";
                case DIAGRAM: return "dgm";
                case CLIP_ART: return "clipArt";
                default: return "obj";
            }
        }

        public static PlaceholderKind from_ooxml (string? s) {
            switch (s) {
                case "title": return TITLE;
                case "ctrTitle": return CENTER_TITLE;
                case "subTitle": return SUBTITLE;
                case "body": return BODY;
                case "pic": return PICTURE;
                case "dt": return DATE;
                case "ftr": return FOOTER;
                case "sldNum": return SLIDE_NUMBER;
                case "chart": return CHART;
                case "tbl": return TABLE;
                case "media": return MEDIA;
                case "dgm": return DIAGRAM;
                case "clipArt": return CLIP_ART;
                case null: return OBJECT;
                default: return OBJECT;
            }
        }

        public bool is_title () {
            return this == TITLE || this == CENTER_TITLE;
        }

        public bool is_meta () {
            return this == DATE || this == FOOTER || this == SLIDE_NUMBER;
        }

        public bool matches (PlaceholderKind o) {
            if (this == o) return true;
            if (is_title () && o.is_title ()) return true;
            bool a = this == BODY || this == OBJECT || this == SUBTITLE;
            bool b = o == BODY || o == OBJECT || o == SUBTITLE;
            return a && b;
        }

        public string label () {
            switch (this) {
                case TITLE: case CENTER_TITLE: return _("Title");
                case SUBTITLE: return _("Subtitle");
                case PICTURE: return _("Picture Placeholder");
                case DATE: return _("Date Placeholder");
                case FOOTER: return _("Footer Placeholder");
                case SLIDE_NUMBER: return _("Slide Number Placeholder");
                case CHART: return _("Chart Placeholder");
                case TABLE: return _("Table Placeholder");
                case MEDIA: return _("Media Placeholder");
                case DIAGRAM: return _("SmartArt Placeholder");
                case CLIP_ART: return _("Online Image Placeholder");
                case BODY: return _("Text Placeholder");
                default: return _("Content Placeholder");
            }
        }

        public string prompt () {
            switch (this) {
                case TITLE: case CENTER_TITLE: return _("Click to add title");
                case SUBTITLE: return _("Click to add subtitle");
                case PICTURE: return _("Click to add a picture");
                case DATE: return _("Date");
                case FOOTER: return _("Footer");
                case SLIDE_NUMBER: return "#";
                case CHART: return _("Click to add a chart");
                case TABLE: return _("Click to add a table");
                case MEDIA: return _("Click to add media");
                case DIAGRAM: return _("Click to add a SmartArt graphic");
                case CLIP_ART: return _("Click to add an online picture");
                default: return _("Click to add text");
            }
        }
    }

    public enum ElementKind {
        SHAPE,
        IMAGE,
        TABLE,
        CHART,
        GROUP,
        FOREIGN,
        MEDIA,
        INK,
        ZOOM,
        DIAGRAM,
        EQUATION,
        MODEL3D
    }

    public abstract class Element {
        public int id = 0;
        public string name = "";
        public string description = "";
        public double x = 0;
        public double y = 0;
        public double w = 100;
        public double h = 100;
        public double rotation = 0;
        public bool flip_h = false;
        public bool flip_v = false;
        public bool locked = false;
        public Line line = new Line ();
        public Shadow shadow = new Shadow ();
        public PlaceholderKind placeholder = PlaceholderKind.NONE;
        public int placeholder_idx = -1;
        public bool inherit_geometry = false;
        public ClickAction? click = null;
        public ClickAction? hover = null;
        public ForeignElement? alternate = null;
        public string alternate_sig = "";

        public abstract ElementKind kind { get; }

        public string light_signature () {
            var t = text_body ();
            var sh = this as ShapeElement;
            return "%d|%.2f|%.2f|%.2f|%.2f|%.2f|%s|%s|%s|%s".printf ((int) kind, x, y, w, h, rotation, name, t != null ? t.plain_text () : "",
                sh != null ? sh.fill.first_color () + sh.preset_name () : "", line.color);
        }

        public abstract Element clone ();

        protected void copy_base (Element e) {
            e.id = id;
            e.name = name;
            e.description = description;
            e.x = x;
            e.y = y;
            e.w = w;
            e.h = h;
            e.rotation = rotation;
            e.flip_h = flip_h;
            e.flip_v = flip_v;
            e.locked = locked;
            e.line = line.clone ();
            e.shadow = shadow.clone ();
            e.placeholder = placeholder;
            e.placeholder_idx = placeholder_idx;
            e.inherit_geometry = inherit_geometry;
            e.click = click != null ? click.clone () : null;
            e.hover = hover != null ? hover.clone () : null;
            e.alternate = alternate;
            e.alternate_sig = alternate_sig;
        }

        public double cx () {
            return x + w / 2;
        }

        public double cy () {
            return y + h / 2;
        }

        public void set_geometry (double x, double y, double w, double h) {
            this.x = x;
            this.y = y;
            this.w = w;
            this.h = h;
        }

        public virtual void move_by (double dx, double dy) {
            x += dx;
            y += dy;
        }

        public virtual void scale_into (double nx, double ny, double nw, double nh) {
            set_geometry (nx, ny, nw, nh);
        }

        public void bounds (out double bx, out double by, out double bw, out double bh) {
            if (rotation == 0) {
                bx = x;
                by = y;
                bw = w;
                bh = h;
                return;
            }
            double a = rotation * Math.PI / 180;
            double c = Math.fabs (Math.cos (a)), s = Math.fabs (Math.sin (a));
            bw = w * c + h * s;
            bh = w * s + h * c;
            bx = cx () - bw / 2;
            by = cy () - bh / 2;
        }

        public bool contains (double px, double py, double tolerance = 0) {
            double lx = px, ly = py;
            if (rotation != 0) {
                double a = -rotation * Math.PI / 180;
                double dx = px - cx (), dy = py - cy ();
                lx = cx () + dx * Math.cos (a) - dy * Math.sin (a);
                ly = cy () + dx * Math.sin (a) + dy * Math.cos (a);
            }
            return lx >= x - tolerance && lx <= x + w + tolerance && ly >= y - tolerance && ly <= y + h + tolerance;
        }

        public virtual TextBody? text_body () {
            return null;
        }

        public virtual string display_name () {
            return name != "" ? name : _("Object");
        }
    }

    public enum ShapeKind {
        RECT,
        ROUND_RECT,
        ELLIPSE,
        TRIANGLE,
        RIGHT_TRIANGLE,
        DIAMOND,
        PARALLELOGRAM,
        TRAPEZOID,
        PENTAGON,
        HEXAGON,
        OCTAGON,
        STAR4,
        STAR5,
        STAR6,
        ARROW_RIGHT,
        ARROW_LEFT,
        ARROW_UP,
        ARROW_DOWN,
        ARROW_LEFT_RIGHT,
        CHEVRON,
        HOME_PLATE,
        PLUS,
        HEART,
        CLOUD,
        DONUT,
        CALLOUT,
        LINE,
        CUSTOM,
        PRESET;

        public const string[] NAMES = { "rect", "roundRect", "ellipse", "triangle", "rtTriangle", "diamond", "parallelogram", "trapezoid",
            "pentagon", "hexagon", "octagon", "star4", "star5", "star6", "rightArrow", "leftArrow", "upArrow", "downArrow",
            "leftRightArrow", "chevron", "homePlate", "plus", "heart", "cloud", "donut", "wedgeRoundRectCallout", "line", "custom", "rect" };

        public string to_ooxml () {
            return NAMES[(int) this];
        }

        public static ShapeKind from_ooxml (string s) {
            for (int i = 0; i < NAMES.length; i++) if (NAMES[i] == s) return (ShapeKind) i;
            switch (s) {
                case "mathPlus": return PLUS;
                case "flowChartProcess": return RECT;
                case "flowChartAlternateProcess": case "snip1Rect": case "round1Rect": case "round2SameRect": return ROUND_RECT;
                case "flowChartConnector": return ELLIPSE;
                case "flowChartDecision": return DIAMOND;
                case "straightConnector1": case "bentConnector2": case "bentConnector3": case "curvedConnector3": return LINE;
                case "wedgeRectCallout": case "wedgeEllipseCallout": case "cloudCallout": return CALLOUT;
                case "star7": case "star8": case "star10": case "star12": case "star16": case "star24": return STAR6;
                case "notchedRightArrow": case "stripedRightArrow": return ARROW_RIGHT;
                case "upDownArrow": return ARROW_UP;
                case "flowChartTerminator": return ROUND_RECT;
                default: return RECT;
            }
        }

        public static bool is_native (string s) {
            for (int i = 0; i < NAMES.length - 2; i++) if (NAMES[i] == s) return true;
            return false;
        }

        public string label () {
            switch (this) {
                case RECT: return _("Rectangle");
                case ROUND_RECT: return _("Rounded Rectangle");
                case ELLIPSE: return _("Oval");
                case TRIANGLE: return _("Triangle");
                case RIGHT_TRIANGLE: return _("Right Triangle");
                case DIAMOND: return _("Diamond");
                case PARALLELOGRAM: return _("Parallelogram");
                case TRAPEZOID: return _("Trapezoid");
                case PENTAGON: return _("Pentagon");
                case HEXAGON: return _("Hexagon");
                case OCTAGON: return _("Octagon");
                case STAR4: return _("4-Point Star");
                case STAR5: return _("5-Point Star");
                case STAR6: return _("6-Point Star");
                case ARROW_RIGHT: return _("Right Arrow");
                case ARROW_LEFT: return _("Left Arrow");
                case ARROW_UP: return _("Up Arrow");
                case ARROW_DOWN: return _("Down Arrow");
                case ARROW_LEFT_RIGHT: return _("Left-Right Arrow");
                case CHEVRON: return _("Chevron");
                case HOME_PLATE: return _("Pentagon Arrow");
                case PLUS: return _("Plus");
                case HEART: return _("Heart");
                case CLOUD: return _("Cloud");
                case DONUT: return _("Donut");
                case CALLOUT: return _("Speech Callout");
                case LINE: return _("Line");
                default: return _("Freeform");
            }
        }
    }

    public class PathCommand {
        public char op;
        public double[] pts;

        public PathCommand (char op, double[] pts) {
            this.op = op;
            this.pts = pts;
        }
    }

    public class ShapeElement : Element {
        public ShapeKind shape = ShapeKind.RECT;
        public Fill fill = new Fill ();
        public double corner = 0.16;
        public double adjust = -1;
        public TextBody? text = null;
        public TextStyle? list_style = null;
        public bool text_box = false;
        public Gee.ArrayList<PathCommand> path = new Gee.ArrayList<PathCommand> ();
        public string preset = "";
        public Gee.HashMap<string, double?> adjust_values = new Gee.HashMap<string, double?> ();
        public ShapeEffects effects = new ShapeEffects ();

        public override ElementKind kind {
            get { return ElementKind.SHAPE; }
        }

        public string preset_name () {
            if (shape == ShapeKind.PRESET) return preset != "" ? preset : "rect";
            return shape.to_ooxml ();
        }

        public ShapeElement (ShapeKind shape = ShapeKind.RECT) {
            this.shape = shape;
        }

        public override Element clone () {
            var s = new ShapeElement (shape);
            copy_base (s);
            s.fill = fill.clone ();
            s.corner = corner;
            s.adjust = adjust;
            s.text = text != null ? text.clone () : null;
            s.list_style = list_style != null ? list_style.clone () : null;
            s.text_box = text_box;
            foreach (var c in path) s.path.add (new PathCommand (c.op, c.pts));
            s.preset = preset;
            foreach (var e in adjust_values.entries) s.adjust_values[e.key] = e.value;
            s.effects = effects.clone ();
            return s;
        }

        public override TextBody? text_body () {
            return text;
        }

        public TextBody ensure_text () {
            if (text == null) {
                text = new TextBody ();
                text.anchor = TextAnchor.MIDDLE;
                var p = new Paragraph ();
                p.align = TextAlign.CENTER;
                text.paragraphs.add (p);
            }
            return text;
        }

        public override string display_name () {
            if (name != "") return name;
            if (text != null && !text.is_empty ()) {
                string t = text.plain_text ().replace ("\n", " ").replace ("\v", " ").strip ();
                if (t.char_count () > 28) t = t.substring (0, t.index_of_nth_char (27)) + "…";
                return "%s \"%s\"".printf (text_box || placeholder != PlaceholderKind.NONE ? _("Text") : shape.label (), t);
            }
            if (placeholder != PlaceholderKind.NONE) return placeholder.is_title () ? _("Title") : _("Text");
            if (text_box) return _("Text Box");
            if (shape == ShapeKind.PRESET) return PresetLabels.label (preset);
            return shape.label ();
        }
    }

    public class ImageElement : Element {
        public Bytes data;
        public string mime = "image/png";
        public double crop_left = 0;
        public double crop_top = 0;
        public double crop_right = 0;
        public double crop_bottom = 0;
        public double brightness = 0;
        public double contrast = 0;
        public double saturation = 1;
        public bool sepia = false;
        public double opacity = 1;
        public double blur = 0;
        public double corner = 0;
        public int pixel_width = 0;
        public int pixel_height = 0;

        public override ElementKind kind {
            get { return ElementKind.IMAGE; }
        }

        public ImageElement (Bytes data, string mime) {
            this.data = data;
            this.mime = mime;
        }

        public override Element clone () {
            var i = new ImageElement (data, mime);
            copy_base (i);
            i.crop_left = crop_left;
            i.crop_top = crop_top;
            i.crop_right = crop_right;
            i.crop_bottom = crop_bottom;
            i.brightness = brightness;
            i.contrast = contrast;
            i.saturation = saturation;
            i.sepia = sepia;
            i.opacity = opacity;
            i.blur = blur;
            i.corner = corner;
            i.pixel_width = pixel_width;
            i.pixel_height = pixel_height;
            return i;
        }

        public bool has_filters () {
            return brightness != 0 || contrast != 0 || saturation != 1 || sepia || blur > 0;
        }

        public string extension () {
            switch (mime) {
                case "image/jpeg": return "jpeg";
                case "image/gif": return "gif";
                case "image/svg+xml": return "svg";
                case "image/bmp": return "bmp";
                case "image/tiff": return "tiff";
                case "image/webp": return "webp";
                default: return "png";
            }
        }

        public static string mime_for (string name) {
            string n = name.down ();
            if (n.has_suffix (".jpg") || n.has_suffix (".jpeg")) return "image/jpeg";
            if (n.has_suffix (".gif")) return "image/gif";
            if (n.has_suffix (".svg")) return "image/svg+xml";
            if (n.has_suffix (".bmp")) return "image/bmp";
            if (n.has_suffix (".tif") || n.has_suffix (".tiff")) return "image/tiff";
            if (n.has_suffix (".webp")) return "image/webp";
            return "image/png";
        }

        public override string display_name () {
            return name != "" ? name : _("Picture");
        }
    }

    public class TableCell {
        public TextBody text = new TextBody ();
        public string fill = "";
        public int row_span = 1;
        public int col_span = 1;
        public bool covered = false;
        public TextAnchor anchor = TextAnchor.TOP;

        public TableCell () {
            text.inset_left = 7.2;
            text.inset_right = 7.2;
            text.inset_top = 3.6;
            text.inset_bottom = 3.6;
            text.paragraphs.add (new Paragraph ());
        }

        public TableCell clone () {
            var c = new TableCell ();
            c.text = text.clone ();
            c.fill = fill;
            c.row_span = row_span;
            c.col_span = col_span;
            c.covered = covered;
            c.anchor = anchor;
            return c;
        }
    }

    public class TableElement : Element {
        public Gee.ArrayList<double?> col_widths = new Gee.ArrayList<double?> ();
        public Gee.ArrayList<double?> row_heights = new Gee.ArrayList<double?> ();
        public Gee.ArrayList<Gee.ArrayList<TableCell>> cells = new Gee.ArrayList<Gee.ArrayList<TableCell>> ();
        public bool first_row = true;
        public bool first_col = false;
        public bool last_row = false;
        public bool banded_rows = true;
        public bool banded_cols = false;
        public string style_color = "accent1";
        public Line border = new Line ();

        public override ElementKind kind {
            get { return ElementKind.TABLE; }
        }

        public TableElement (int rows, int cols, double width, double row_height) {
            border.color = "#ffffff";
            border.width = 1;
            for (int c = 0; c < cols; c++) col_widths.add (width / cols);
            for (int r = 0; r < rows; r++) {
                row_heights.add (row_height);
                var row = new Gee.ArrayList<TableCell> ();
                for (int c = 0; c < cols; c++) row.add (new TableCell ());
                cells.add (row);
            }
            w = width;
            h = row_height * rows;
        }

        public int rows {
            get { return row_heights.size; }
        }

        public int cols {
            get { return col_widths.size; }
        }

        public TableCell cell (int r, int c) {
            return cells[r][c];
        }

        public override Element clone () {
            var t = new TableElement (0, 0, 0, 0);
            copy_base (t);
            foreach (var cw in col_widths) t.col_widths.add (cw);
            foreach (var rh in row_heights) t.row_heights.add (rh);
            foreach (var row in cells) {
                var nr = new Gee.ArrayList<TableCell> ();
                foreach (var c in row) nr.add (c.clone ());
                t.cells.add (nr);
            }
            t.first_row = first_row;
            t.first_col = first_col;
            t.last_row = last_row;
            t.banded_rows = banded_rows;
            t.banded_cols = banded_cols;
            t.style_color = style_color;
            t.border = border.clone ();
            return t;
        }

        public void sync_size () {
            double tw = 0, th = 0;
            foreach (var cw in col_widths) tw += cw;
            foreach (var rh in row_heights) th += rh;
            w = tw;
            h = th;
        }

        public override void scale_into (double nx, double ny, double nw, double nh) {
            double sx = w > 0 ? nw / w : 1, sy = h > 0 ? nh / h : 1;
            for (int i = 0; i < col_widths.size; i++) col_widths[i] = col_widths[i] * sx;
            for (int i = 0; i < row_heights.size; i++) row_heights[i] = row_heights[i] * sy;
            set_geometry (nx, ny, nw, nh);
        }

        public double col_x (int c) {
            double acc = x;
            for (int i = 0; i < c && i < col_widths.size; i++) acc += col_widths[i];
            return acc;
        }

        public double row_y (int r) {
            double acc = y;
            for (int i = 0; i < r && i < row_heights.size; i++) acc += row_heights[i];
            return acc;
        }

        public bool cell_at (double px, double py, out int row, out int col) {
            row = -1;
            col = -1;
            double acc = x;
            for (int c = 0; c < cols; c++) {
                if (px >= acc && px < acc + col_widths[c]) col = c;
                acc += col_widths[c];
            }
            acc = y;
            for (int r = 0; r < rows; r++) {
                if (py >= acc && py < acc + row_heights[r]) row = r;
                acc += row_heights[r];
            }
            if (row < 0 || col < 0) return false;
            for (int r = 0; r <= row; r++) {
                for (int c = 0; c <= col; c++) {
                    var cl = cells[r][c];
                    if (!cl.covered && r + cl.row_span > row && c + cl.col_span > col) {
                        row = r;
                        col = c;
                    }
                }
            }
            return true;
        }

        public void insert_row (int at, bool copy_style = true) {
            at = at.clamp (0, rows);
            int src = at > 0 ? at - 1 : 0;
            double hgt = rows > 0 ? row_heights[src] : 30;
            var row = new Gee.ArrayList<TableCell> ();
            for (int c = 0; c < cols; c++) {
                var cl = new TableCell ();
                if (copy_style && rows > 0) {
                    cl.fill = cells[src][c].fill;
                    cl.anchor = cells[src][c].anchor;
                    if (cells[src][c].text.paragraphs.size > 0) cl.text.paragraphs[0].copy_format (cells[src][c].text.paragraphs[0]);
                }
                row.add (cl);
            }
            cells.insert (at, row);
            row_heights.insert (at, hgt);
            sync_size ();
        }

        public void insert_col (int at) {
            at = at.clamp (0, cols);
            int src = at > 0 ? at - 1 : 0;
            double wid = cols > 0 ? col_widths[src] : 100;
            foreach (var row in cells) {
                var cl = new TableCell ();
                if (row.size > 0) {
                    cl.fill = row[src.clamp (0, row.size - 1)].fill;
                    cl.anchor = row[src.clamp (0, row.size - 1)].anchor;
                }
                row.insert (at, cl);
            }
            col_widths.insert (at, wid);
            sync_size ();
        }

        public void delete_row (int at) {
            if (rows <= 1 || at < 0 || at >= rows) return;
            unmerge_all ();
            cells.remove_at (at);
            row_heights.remove_at (at);
            sync_size ();
        }

        public void delete_col (int at) {
            if (cols <= 1 || at < 0 || at >= cols) return;
            unmerge_all ();
            foreach (var row in cells) row.remove_at (at);
            col_widths.remove_at (at);
            sync_size ();
        }

        public void unmerge_all () {
            foreach (var row in cells) {
                foreach (var c in row) {
                    c.row_span = 1;
                    c.col_span = 1;
                    c.covered = false;
                }
            }
        }

        public void merge (int r1, int c1, int r2, int c2) {
            for (int r = r1; r <= r2; r++) {
                for (int c = c1; c <= c2; c++) {
                    var cl = cells[r][c];
                    if (r == r1 && c == c1) continue;
                    if (!cl.text.is_empty ()) {
                        foreach (var p in cl.text.paragraphs) if (p.text () != "") cells[r1][c1].text.paragraphs.add (p.clone ());
                        cl.text.set_plain ("");
                    }
                    cl.covered = true;
                    cl.row_span = 1;
                    cl.col_span = 1;
                }
            }
            cells[r1][c1].row_span = r2 - r1 + 1;
            cells[r1][c1].col_span = c2 - c1 + 1;
            cells[r1][c1].covered = false;
        }

        public void split (int r, int c) {
            var cl = cells[r][c];
            for (int i = r; i < r + cl.row_span && i < rows; i++) {
                for (int j = c; j < c + cl.col_span && j < cols; j++) cells[i][j].covered = false;
            }
            cl.row_span = 1;
            cl.col_span = 1;
        }

        public override string display_name () {
            return name != "" ? name : _("Table");
        }
    }

    public enum ChartKind {
        COLUMN,
        BAR,
        LINE,
        PIE,
        DOUGHNUT,
        AREA,
        SCATTER,
        RADAR,
        BUBBLE,
        STOCK,
        HISTOGRAM,
        PARETO,
        BOX_WHISKER,
        WATERFALL,
        FUNNEL,
        TREEMAP,
        SUNBURST;

        public bool uses_engine () {
            return (int) this >= (int) STOCK;
        }

        public bool is_chartex () {
            return (int) this > (int) STOCK;
        }

        public string label () {
            switch (this) {
                case RADAR: return _("Radar");
                case BUBBLE: return _("Bubble");
                case STOCK: return _("Stock");
                case HISTOGRAM: return _("Histogram");
                case PARETO: return _("Pareto");
                case BOX_WHISKER: return _("Box and Whisker");
                case WATERFALL: return _("Waterfall");
                case FUNNEL: return _("Funnel");
                case TREEMAP: return _("Treemap");
                case SUNBURST: return _("Sunburst");
                case BAR: return _("Bar");
                case LINE: return _("Line");
                case PIE: return _("Pie");
                case DOUGHNUT: return _("Doughnut");
                case AREA: return _("Area");
                case SCATTER: return _("Scatter");
                default: return _("Column");
            }
        }

        public bool is_radial () {
            return this == PIE || this == DOUGHNUT;
        }
    }

    public enum ChartGrouping {
        CLUSTERED,
        STACKED,
        PERCENT
    }

    public enum LegendPosition {
        NONE,
        BOTTOM,
        RIGHT,
        TOP,
        LEFT
    }

    public class ChartSeries {
        public string name;
        public Gee.ArrayList<double?> values = new Gee.ArrayList<double?> ();
        public Gee.ArrayList<double?> sizes = new Gee.ArrayList<double?> ();
        public string color = "";
        public SeriesKind kind = SeriesKind.AUTO;
        public bool secondary = false;
        public TrendKind trend = TrendKind.NONE;
        public int trend_order = 2;
        public int trend_period = 2;
        public bool trend_equation = false;
        public bool trend_r2 = false;

        public ChartSeries (string name) {
            this.name = name;
        }

        public ChartSeries clone () {
            var s = new ChartSeries (name);
            foreach (var v in values) s.values.add (v);
            foreach (var v in sizes) s.sizes.add (v);
            s.color = color;
            s.kind = kind;
            s.secondary = secondary;
            s.trend = trend;
            s.trend_order = trend_order;
            s.trend_period = trend_period;
            s.trend_equation = trend_equation;
            s.trend_r2 = trend_r2;
            return s;
        }

        public double value_at (int i) {
            if (i < 0 || i >= values.size || values[i] == null) return 0;
            return values[i];
        }
    }

    public class ChartElement : Element {
        public ChartKind chart = ChartKind.COLUMN;
        public ChartGrouping grouping = ChartGrouping.CLUSTERED;
        public string title = "";
        public LegendPosition legend = LegendPosition.BOTTOM;
        public bool data_labels = false;
        public bool gridlines = true;
        public bool smooth = false;
        public Gee.ArrayList<string> categories = new Gee.ArrayList<string> ();
        public Gee.ArrayList<ChartSeries> series = new Gee.ArrayList<ChartSeries> ();
        public string text_color = "";
        public ChartAxis cat_axis = new ChartAxis ();
        public ChartAxis val_axis = new ChartAxis ();
        public ChartAxis sec_axis = new ChartAxis ();
        public ForeignElement? original = null;
        public string original_sig = "";
        public const string LINK_PREFIX = "sinty-chart-link:";
        public string link = "";

        public override ElementKind kind {
            get { return ElementKind.CHART; }
        }

        public SeriesKind series_kind (ChartSeries s) {
            if (s.kind != SeriesKind.AUTO && !chart.is_radial () && chart != ChartKind.SCATTER && chart != ChartKind.BUBBLE && chart != ChartKind.RADAR) return s.kind;
            switch (chart) {
                case ChartKind.LINE: return SeriesKind.LINE;
                case ChartKind.AREA: return SeriesKind.AREA;
                default: return SeriesKind.COLUMN;
            }
        }

        public bool has_secondary () {
            if (chart.is_radial () || chart == ChartKind.RADAR) return false;
            foreach (var s in series) if (s.secondary) return true;
            return false;
        }

        public virtual string signature () {
            var sb = new StringBuilder ();
            sb.append ("%d|%d|%s|%d|%s|%s|%s|%s".printf ((int) chart, (int) grouping, title, (int) legend, data_labels.to_string (), gridlines.to_string (), smooth.to_string (), text_color));
            foreach (string c in categories) sb.append (c + ";");
            foreach (var se in series) {
                sb.append (se.name + ":" + se.color + ":%d:%s:%d:%d:%d:%s:%s:".printf ((int) se.kind, se.secondary.to_string (), (int) se.trend, se.trend_order, se.trend_period, se.trend_equation.to_string (), se.trend_r2.to_string ()));
                foreach (var v in se.values) sb.append (v == null ? "n," : "%g,".printf (v));
                foreach (var v in se.sizes) sb.append (v == null ? "n;" : "%g;".printf (v));
            }
            sb.append (cat_axis.signature () + val_axis.signature () + sec_axis.signature ());
            return sb.str;
        }

        public bool pristine () {
            return original != null && original_sig != "" && original_sig == signature ();
        }

        public void mark_pristine () {
            original_sig = signature ();
        }

        public ChartElement (ChartKind chart) {
            this.chart = chart;
        }

        public override Element clone () {
            var c = new ChartElement (chart);
            copy_base (c);
            c.grouping = grouping;
            c.title = title;
            c.link = link;
            c.legend = legend;
            c.data_labels = data_labels;
            c.gridlines = gridlines;
            c.smooth = smooth;
            c.categories.add_all (categories);
            foreach (var s in series) c.series.add (s.clone ());
            c.text_color = text_color;
            c.cat_axis = cat_axis.clone ();
            c.val_axis = val_axis.clone ();
            c.sec_axis = sec_axis.clone ();
            c.original = original != null ? (ForeignElement) original.clone () : null;
            c.original_sig = original_sig;
            return c;
        }

        public void sample_data () {
            categories.clear ();
            series.clear ();
            string[] cats = { _("Q1"), _("Q2"), _("Q3"), _("Q4") };
            foreach (string s in cats) categories.add (s);
            double[,] vals = { { 4.3, 2.5, 3.5, 4.5 }, { 2.4, 4.4, 1.8, 2.8 }, { 2, 2, 3, 5 } };
            string[] names = { _("Series 1"), _("Series 2"), _("Series 3") };
            int n = chart.is_radial () ? 1 : 3;
            for (int i = 0; i < n; i++) {
                var s = new ChartSeries (names[i]);
                for (int j = 0; j < 4; j++) s.values.add (vals[i, j]);
                if (chart == ChartKind.BUBBLE) for (int j = 0; j < 4; j++) s.sizes.add (vals[(i + 1) % 3, j] * 3);
                series.add (s);
            }
        }

        public override string display_name () {
            return name != "" ? name : _("Chart");
        }
    }

    public class GroupElement : Element {
        public Gee.ArrayList<Element> children = new Gee.ArrayList<Element> ();

        public override ElementKind kind {
            get { return ElementKind.GROUP; }
        }

        public override Element clone () {
            var g = new GroupElement ();
            copy_base (g);
            foreach (var c in children) g.children.add (c.clone ());
            return g;
        }

        public void fit () {
            if (children.size == 0) return;
            double x1 = double.MAX, y1 = double.MAX, x2 = -double.MAX, y2 = -double.MAX;
            foreach (var c in children) {
                double bx, by, bw, bh;
                c.bounds (out bx, out by, out bw, out bh);
                x1 = double.min (x1, bx);
                y1 = double.min (y1, by);
                x2 = double.max (x2, bx + bw);
                y2 = double.max (y2, by + bh);
            }
            set_geometry (x1, y1, x2 - x1, y2 - y1);
        }

        public override void move_by (double dx, double dy) {
            base.move_by (dx, dy);
            foreach (var c in children) c.move_by (dx, dy);
        }

        public override void scale_into (double nx, double ny, double nw, double nh) {
            double sx = w > 0 ? nw / w : 1, sy = h > 0 ? nh / h : 1;
            foreach (var c in children) {
                c.scale_into (nx + (c.x - x) * sx, ny + (c.y - y) * sy, c.w * sx, c.h * sy);
            }
            set_geometry (nx, ny, nw, nh);
        }

        public override string display_name () {
            return name != "" ? name : _("Group");
        }
    }
}
