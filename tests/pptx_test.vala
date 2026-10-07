using Singularity.Apps.Slides;

int checks = 0;

void check (bool ok, string what) {
    checks++;
    if (!ok) error ("check failed: %s", what);
}

bool near (double a, double b, double eps = 0.01) {
    return Math.fabs (a - b) <= eps;
}

void add_dir (ZipWriter zip, string root, string rel) throws Error {
    var dir = Dir.open (Path.build_filename (root, rel));
    string? name;
    var names = new Gee.ArrayList<string> ();
    while ((name = dir.read_name ()) != null) names.add (name);
    names.sort ();
    foreach (string n in names) {
        string r = rel == "" ? n : rel + "/" + n;
        string full = Path.build_filename (root, r);
        if (FileUtils.test (full, FileTest.IS_DIR)) {
            add_dir (zip, root, r);
        } else {
            uint8[] data;
            FileUtils.get_data (full, out data);
            zip.add (r, data);
        }
    }
}

uint8[] png_bytes (int w, int h, double r, double g, double b) {
    var surf = new Cairo.ImageSurface (Cairo.Format.ARGB32, w, h);
    var cr = new Cairo.Context (surf);
    cr.set_source_rgb (r, g, b);
    cr.paint ();
    cr.set_source_rgb (1 - r, 1 - g, 1 - b);
    cr.rectangle (0, 0, w / 2, h / 2);
    cr.fill ();
    var bytes = new ByteArray ();
    surf.write_to_png_stream ((data) => {
        bytes.append (data);
        return Cairo.Status.SUCCESS;
    });
    return bytes.steal ();
}

Presentation read_fixture (string name, bool with_media) throws Error {
    var zip = new ZipWriter ();
    add_dir (zip, Path.build_filename ("fixtures", name), "");
    if (with_media) zip.add ("ppt/media/image1.png", png_bytes (40, 20, 0.1, 0.4, 0.8));
    return new PptxReader (new ZipReader (zip.finish ())).read ();
}

Presentation roundtrip (Presentation p, out uint8[] data) throws Error {
    data = new PptxWriter (p).write ();
    check_package (data);
    return Document.load_bytes (data, "deck.pptx");
}

bool same_color (string a, string b, Theme ta, Theme tb) {
    if (a == "" || b == "") return a == b;
    var ca = ta.resolve (a), cb = tb.resolve (b);
    return ca.to_hex () == cb.to_hex () && near (ca.a, cb.a, 0.011);
}

void compare_fill (Fill a, Fill b, Theme ta, Theme tb, string where) {
    check (a.kind == b.kind, where + ": fill kind");
    switch (a.kind) {
        case FillKind.SOLID:
            check (same_color (a.color, b.color, ta, tb), where + ": fill color %s vs %s".printf (a.color, b.color));
            break;
        case FillKind.GRADIENT:
            check (a.stops.size == b.stops.size, where + ": gradient stops");
            for (int i = 0; i < a.stops.size; i++) {
                check (near (a.stops[i].pos, b.stops[i].pos, 1e-4), where + ": stop pos");
                check (same_color (a.stops[i].color, b.stops[i].color, ta, tb), where + ": stop color");
            }
            check (a.radial == b.radial, where + ": radial");
            if (!a.radial) check (near (a.angle, b.angle, 1e-3), where + ": angle %g vs %g".printf (a.angle, b.angle));
            break;
        case FillKind.IMAGE:
            check (a.image.compare (b.image) == 0, where + ": image bytes");
            check (a.tile == b.tile, where + ": tile");
            break;
        default:
            break;
    }
}

void compare_line (Line a, Line b, Theme ta, Theme tb, string where) {
    check (same_color (a.color, b.color, ta, tb), where + ": line color %s vs %s".printf (a.color, b.color));
    check (near (a.width, b.width), where + ": line width %g vs %g".printf (a.width, b.width));
    if (a.color == "") return;
    check (a.dash == b.dash, where + ": dash");
    check (a.head == b.head && a.tail == b.tail, where + ": arrows");
}

void compare_run (TextRun a, TextRun b, Theme ta, Theme tb, string where) {
    check (a.text == b.text, where + ": run text '%s' vs '%s'".printf (a.text, b.text));
    check (a.bold == b.bold && a.italic == b.italic, where + ": bold/italic");
    check (a.underline == b.underline && a.strike == b.strike, where + ": underline/strike");
    check (near (a.size, b.size), where + ": size %g vs %g".printf (a.size, b.size));
    check (a.font == b.font, where + ": font %s vs %s".printf (a.font, b.font));
    check (same_color (a.color, b.color, ta, tb), where + ": run color %s vs %s".printf (a.color, b.color));
    check (same_color (a.highlight, b.highlight, ta, tb), where + ": highlight");
    check (a.baseline == b.baseline, where + ": baseline");
    check (a.link == b.link, where + ": link");
    check (a.field == b.field, where + ": field");
}

void compare_level (LevelStyle a, LevelStyle b, Theme ta, Theme tb, string where) {
    check (near (a.size, b.size), where + ": level size");
    check (a.font == b.font, where + ": level font");
    check (same_color (a.color, b.color, ta, tb), where + ": level color %s vs %s".printf (a.color, b.color));
    check (a.bold == b.bold && a.italic == b.italic, where + ": level bold/italic");
    check (a.align == b.align, where + ": level align");
    check (a.bullet == b.bullet, where + ": level bullet");
    if (a.bullet == BulletKind.CHAR) check (a.bullet_char == b.bullet_char, where + ": level bullet char");
    check (near (a.margin, b.margin), where + ": level margin %g vs %g".printf (a.margin, b.margin));
    if (a.margin >= 0) check (near (a.indent, b.indent), where + ": level indent");
    check (near (a.space_before, b.space_before), where + ": level space before");
    check (near (a.space_after, b.space_after), where + ": level space after");
    check (near (a.line_spacing, b.line_spacing, 1e-4), where + ": level line spacing");
    check (a.caps == b.caps, where + ": caps");
}

void compare_style (TextStyle? a, TextStyle? b, Theme ta, Theme tb, string where) {
    check ((a == null) == (b == null), where + ": list style presence");
    if (a == null) return;
    for (int i = 0; i < 9; i++) compare_level (a.levels[i], b.levels[i], ta, tb, where + " lvl%d".printf (i + 1));
}

void compare_body (TextBody? a, TextBody? b, Theme ta, Theme tb, string where) {
    check ((a == null) == (b == null), where + ": body presence");
    if (a == null) return;
    check (near (a.inset_left, b.inset_left) && near (a.inset_top, b.inset_top) && near (a.inset_right, b.inset_right) && near (a.inset_bottom, b.inset_bottom), where + ": insets");
    check (a.anchor_set == b.anchor_set, where + ": anchor set");
    if (a.anchor_set) check (a.anchor == b.anchor, where + ": anchor");
    check (a.wrap == b.wrap && a.autofit == b.autofit, where + ": wrap/autofit");
    if (a.autofit == AutoFit.SHRINK) check (near (a.font_scale, b.font_scale, 1e-4) && near (a.line_reduction, b.line_reduction, 1e-4), where + ": font scale");
    check (a.columns == b.columns && a.vertical == b.vertical, where + ": columns/vertical");
    check (a.paragraphs.size == b.paragraphs.size, where + ": paragraphs %d vs %d".printf (a.paragraphs.size, b.paragraphs.size));
    for (int i = 0; i < a.paragraphs.size; i++) {
        var pa = a.paragraphs[i];
        var pb = b.paragraphs[i];
        string w = where + " p%d".printf (i);
        check (pa.align == pb.align && pa.level == pb.level, w + ": align/level");
        check (pa.bullet == pb.bullet, w + ": bullet");
        if (pa.bullet == BulletKind.CHAR) check (pa.bullet_char == pb.bullet_char || (pa.bullet_char == "" && pb.bullet_char == "•"), w + ": bullet char");
        if (pa.bullet == BulletKind.NUMBER) check (pa.number_style == pb.number_style && pa.number_start == pb.number_start, w + ": numbering");
        check (same_color (pa.bullet_color, pb.bullet_color, ta, tb), w + ": bullet color");
        check (near (pa.space_before, pb.space_before) && near (pa.space_after, pb.space_after), w + ": spacing");
        check (near (pa.line_spacing, pb.line_spacing, 1e-4), w + ": line spacing");
        check (pa.runs.size == pb.runs.size, w + ": runs %d vs %d".printf (pa.runs.size, pb.runs.size));
        for (int j = 0; j < pa.runs.size; j++) compare_run (pa.runs[j], pb.runs[j], ta, tb, w + " r%d".printf (j));
        var ea = pa.end_format;
        var eb = pb.end_format;
        check (ea.bold == eb.bold && ea.italic == eb.italic && near (ea.size, eb.size) && ea.font == eb.font && same_color (ea.color, eb.color, ta, tb), w + ": end format");
    }
}

void compare_element (Element a, Element b, Theme ta, Theme tb, bool ids, string where) {
    string w = where + " [" + a.display_name () + "]";
    check (a.kind == b.kind, w + ": kind");
    if (ids) check (a.id == b.id, w + ": id %d vs %d".printf (a.id, b.id));
    check (a.name == b.name, w + ": name '%s' vs '%s'".printf (a.name, b.name));
    check (a.description == b.description, w + ": description");
    check (a.placeholder == b.placeholder, w + ": placeholder %d vs %d".printf ((int) a.placeholder, (int) b.placeholder));
    check (a.placeholder_idx == b.placeholder_idx, w + ": placeholder idx");
    check (a.inherit_geometry == b.inherit_geometry, w + ": inherit geometry");
    check (near (a.x, b.x) && near (a.y, b.y) && near (a.w, b.w) && near (a.h, b.h), w + ": geometry %g,%g,%g,%g vs %g,%g,%g,%g".printf (a.x, a.y, a.w, a.h, b.x, b.y, b.w, b.h));
    check (near (a.rotation, b.rotation, 1e-3) && a.flip_h == b.flip_h && a.flip_v == b.flip_v, w + ": rotation/flip");
    check (a.locked == b.locked, w + ": locked");
    if (a.kind != ElementKind.TABLE && a.kind != ElementKind.CHART && a.kind != ElementKind.GROUP) {
        compare_line (a.line, b.line, ta, tb, w);
        check (a.shadow.enabled == b.shadow.enabled, w + ": shadow");
        if (a.shadow.enabled) {
            check (near (a.shadow.blur, b.shadow.blur) && near (a.shadow.distance, b.shadow.distance) && near (a.shadow.angle, b.shadow.angle, 1e-3), w + ": shadow geometry");
            var sa = ta.resolve (a.shadow.color);
            var sb = tb.resolve (b.shadow.color);
            check (sa.to_hex () == sb.to_hex () && near (sa.a * a.shadow.opacity, sb.a * b.shadow.opacity, 0.001), w + ": shadow color");
        }
    }
    switch (a.kind) {
        case ElementKind.SHAPE:
            var sa = (ShapeElement) a;
            var sb = (ShapeElement) b;
            check (sa.shape == sb.shape, w + ": shape %s vs %s".printf (sa.shape.to_ooxml (), sb.shape.to_ooxml ()));
            if (sa.shape == ShapeKind.ROUND_RECT) check (near (sa.corner, sb.corner, 1e-4), w + ": corner");
            check (sa.text_box == sb.text_box, w + ": text box");
            compare_fill (sa.fill, sb.fill, ta, tb, w);
            compare_body (sa.text, sb.text, ta, tb, w);
            compare_style (sa.list_style, sb.list_style, ta, tb, w);
            check (sa.path.size == sb.path.size, w + ": path size");
            for (int i = 0; i < sa.path.size; i++) {
                check (sa.path[i].op == sb.path[i].op && sa.path[i].pts.length == sb.path[i].pts.length, w + ": path op");
                for (int k = 0; k < sa.path[i].pts.length; k++) check (near (sa.path[i].pts[k], sb.path[i].pts[k], 1e-4), w + ": path point");
            }
            break;
        case ElementKind.IMAGE:
            var ia = (ImageElement) a;
            var ib = (ImageElement) b;
            check (ia.data.compare (ib.data) == 0 && ia.mime == ib.mime, w + ": image data");
            check (near (ia.crop_left, ib.crop_left, 1e-5) && near (ia.crop_top, ib.crop_top, 1e-5) && near (ia.crop_right, ib.crop_right, 1e-5) && near (ia.crop_bottom, ib.crop_bottom, 1e-5), w + ": crop");
            check (near (ia.brightness, ib.brightness, 1e-5) && near (ia.contrast, ib.contrast, 1e-5) && near (ia.saturation, ib.saturation, 1e-5), w + ": filters");
            check (ia.sepia == ib.sepia && near (ia.blur, ib.blur, 1e-5) && near (ia.opacity, ib.opacity, 1e-5) && near (ia.corner, ib.corner, 1e-5), w + ": effects");
            break;
        case ElementKind.TABLE:
            var ta2 = (TableElement) a;
            var tb2 = (TableElement) b;
            check (ta2.rows == tb2.rows && ta2.cols == tb2.cols, w + ": table size");
            for (int c = 0; c < ta2.cols; c++) check (near (ta2.col_widths[c], tb2.col_widths[c]), w + ": col width");
            for (int r = 0; r < ta2.rows; r++) check (near (ta2.row_heights[r], tb2.row_heights[r]), w + ": row height");
            check (ta2.first_row == tb2.first_row && ta2.first_col == tb2.first_col && ta2.last_row == tb2.last_row && ta2.banded_rows == tb2.banded_rows && ta2.banded_cols == tb2.banded_cols, w + ": table flags");
            check (ta2.style_color == tb2.style_color, w + ": table style");
            compare_line (ta2.border, tb2.border, ta, tb, w + " border");
            for (int r = 0; r < ta2.rows; r++) {
                for (int c = 0; c < ta2.cols; c++) {
                    var ca = ta2.cells[r][c];
                    var cb = tb2.cells[r][c];
                    string cw = w + " cell %d,%d".printf (r, c);
                    check (ca.covered == cb.covered, cw + ": covered");
                    if (!ca.covered) check (ca.row_span == cb.row_span && ca.col_span == cb.col_span, cw + ": spans");
                    check (same_color (ca.fill, cb.fill, ta, tb), cw + ": fill");
                    check (ca.anchor == cb.anchor, cw + ": anchor");
                    compare_body (ca.text, cb.text, ta, tb, cw);
                }
            }
            break;
        case ElementKind.CHART:
            var ca = (ChartElement) a;
            var cb = (ChartElement) b;
            check (ca.chart == cb.chart, w + ": chart kind %s vs %s".printf (ca.chart.label (), cb.chart.label ()));
            if (!ca.chart.is_radial ()) check (ca.grouping == cb.grouping, w + ": grouping");
            check (ca.title == cb.title && ca.legend == cb.legend, w + ": title/legend");
            check (ca.link == cb.link, w + ": linked chart source");
            check (ca.data_labels == cb.data_labels, w + ": labels");
            if (!ca.chart.is_radial ()) check (ca.gridlines == cb.gridlines, w + ": gridlines");
            if (ca.chart == ChartKind.LINE || ca.chart == ChartKind.SCATTER) check (ca.smooth == cb.smooth, w + ": smooth");
            check (ca.categories.size == cb.categories.size, w + ": categories");
            for (int i = 0; i < ca.categories.size; i++) check (ca.categories[i] == cb.categories[i], w + ": category %s vs %s".printf (ca.categories[i], cb.categories[i]));
            check (ca.series.size == cb.series.size, w + ": series count");
            for (int i = 0; i < ca.series.size; i++) {
                check (ca.series[i].name == cb.series[i].name, w + ": series name");
                check (same_color (ca.series[i].color, cb.series[i].color, ta, tb), w + ": series color");
                int n = int.max (ca.series[i].values.size, cb.series[i].values.size);
                for (int k = 0; k < n; k++) {
                    double? va = k < ca.series[i].values.size ? ca.series[i].values[k] : null;
                    double? vb = k < cb.series[i].values.size ? cb.series[i].values[k] : null;
                    check ((va == null) == (vb == null), w + ": value presence");
                    if (va != null) check (near (va, vb, 1e-9), w + ": value");
                }
            }
            check (same_color (ca.text_color, cb.text_color, ta, tb), w + ": text color");
            break;
        case ElementKind.GROUP:
            var ga = (GroupElement) a;
            var gb = (GroupElement) b;
            check (ga.children.size == gb.children.size, w + ": children");
            for (int i = 0; i < ga.children.size; i++) compare_element (ga.children[i], gb.children[i], ta, tb, ids, w);
            break;
    }
}

void compare_elements (Gee.List<Element> a, Gee.List<Element> b, Theme ta, Theme tb, bool ids, string where) {
    check (a.size == b.size, where + ": element count %d vs %d".printf (a.size, b.size));
    for (int i = 0; i < a.size; i++) compare_element (a[i], b[i], ta, tb, ids, where + " #%d".printf (i));
}

void compare_pres (Presentation a, Presentation b, string where) {
    check (near (a.width, b.width) && near (a.height, b.height), where + ": size");
    check (a.loop == b.loop && a.use_timings == b.use_timings, where + ": show settings");
    check (a.footer_text == b.footer_text && a.date_text == b.date_text, where + ": header footer");
    check (a.properties.title == b.properties.title && a.properties.author == b.properties.author, where + ": properties");
    check (a.properties.subject == b.properties.subject && a.properties.keywords == b.properties.keywords, where + ": subject/keywords");
    if (a.properties.created != "") check (a.properties.created == b.properties.created && a.properties.modified == b.properties.modified, where + ": dates");
    check (a.masters.size == b.masters.size, where + ": masters");
    for (int m = 0; m < a.masters.size; m++) {
        var ma = a.masters[m];
        var mb = b.masters[m];
        string w = where + " master%d".printf (m);
        check (ma.name == mb.name, w + ": name");
        check (ma.theme.name == mb.theme.name && ma.theme.id == mb.theme.id, w + ": theme name/id");
        foreach (string k in Theme.SCHEME_KEYS) check (ma.theme.scheme_hex (k).down () == mb.theme.scheme_hex (k).down (), w + ": theme color " + k);
        check (ma.theme.major_font == mb.theme.major_font && ma.theme.minor_font == mb.theme.minor_font, w + ": theme fonts");
        compare_fill (ma.background, mb.background, ma.theme, mb.theme, w + " background");
        compare_style (ma.title_style, mb.title_style, ma.theme, mb.theme, w + " title style");
        compare_style (ma.body_style, mb.body_style, ma.theme, mb.theme, w + " body style");
        compare_style (ma.other_style, mb.other_style, ma.theme, mb.theme, w + " other style");
        compare_elements (ma.elements, mb.elements, ma.theme, mb.theme, false, w);
        check (ma.layouts.size == mb.layouts.size, w + ": layouts");
        for (int l = 0; l < ma.layouts.size; l++) {
            var la = ma.layouts[l];
            var lb = mb.layouts[l];
            string lw = w + " layout " + la.name;
            check (la.name == lb.name && la.kind == lb.kind && la.id == lb.id, lw + ": identity");
            check (la.show_master_shapes == lb.show_master_shapes, lw + ": master shapes");
            check ((la.background == null) == (lb.background == null), lw + ": background presence");
            if (la.background != null) compare_fill (la.background, lb.background, ma.theme, mb.theme, lw);
            compare_elements (la.elements, lb.elements, ma.theme, mb.theme, false, lw);
        }
    }
    check (a.slides.size == b.slides.size, where + ": slides");
    for (int i = 0; i < a.slides.size; i++) {
        var sa = a.slides[i];
        var sb = b.slides[i];
        string w = where + " slide%d".printf (i + 1);
        var ta = a.master_for (sa).theme;
        var tb = b.master_for (sb).theme;
        check (sa.layout_id == sb.layout_id, w + ": layout");
        check (sa.title () == sb.title (), w + ": title");
        check (sa.hidden == sb.hidden && sa.show_master_shapes == sb.show_master_shapes && sa.name == sb.name, w + ": flags");
        check (sa.notes == sb.notes, w + ": notes '%s' vs '%s'".printf (sa.notes, sb.notes));
        check ((sa.background == null) == (sb.background == null), w + ": background presence");
        if (sa.background != null) compare_fill (sa.background, sb.background, ta, tb, w + " background");
        var tra = sa.transition;
        var trb = sb.transition;
        check (tra.kind == trb.kind, w + ": transition %s vs %s".printf (tra.kind.label (), trb.kind.label ()));
        if (tra.kind != TransitionKind.NONE || !tra.on_click || tra.advance_after >= 0) check (near (tra.duration, trb.duration, 0.001), w + ": transition duration");
        if (tra.kind.has_direction ()) check (tra.direction == trb.direction, w + ": transition direction");
        check (tra.on_click == trb.on_click && near (tra.advance_after, trb.advance_after, 0.001), w + ": advance");
        compare_elements (sa.elements, sb.elements, ta, tb, true, w);
        check (sa.animations.size == sb.animations.size, w + ": animations %d vs %d".printf (sa.animations.size, sb.animations.size));
        for (int k = 0; k < sa.animations.size; k++) {
            var aa = sa.animations[k];
            var ab = sb.animations[k];
            string aw = w + " anim%d".printf (k);
            check (aa.target == ab.target && sb.find (ab.target) != null, aw + ": target");
            check (aa.anim_class == ab.anim_class && aa.effect == ab.effect, aw + ": effect %s vs %s".printf (aa.label (), ab.label ()));
            check (aa.trigger == ab.trigger, aw + ": trigger");
            if (aa.effect != AnimEffect.APPEAR) check (near (aa.duration, ab.duration, 0.001), aw + ": duration %g vs %g".printf (aa.duration, ab.duration));
            check (near (aa.delay, ab.delay, 0.001), aw + ": delay");
            if (aa.effect.has_direction ()) check (aa.direction == ab.direction, aw + ": direction");
        }
    }
}

void check_package (uint8[] data) throws Error {
    var zip = new ZipReader (data);
    string? ct = zip.read_text ("[Content_Types].xml");
    check (ct != null, "content types present");
    Xml.Doc* doc = XmlIn.parse (ct);
    var defaults = new Gee.HashSet<string> ();
    var overrides = new Gee.HashSet<string> ();
    foreach (Xml.Node* n in XmlIn.elements (doc->get_root_element ())) {
        if (n->name == "Default") defaults.add (XmlIn.attr (n, "Extension").down ());
        if (n->name == "Override") {
            string part = XmlIn.attr (n, "PartName").substring (1);
            check (zip.has (part), "override part exists: " + part);
            overrides.add (part);
        }
    }
    delete doc;
    foreach (string name in zip.names ()) {
        if (name == "[Content_Types].xml") continue;
        int dot = name.last_index_of (".");
        string ext = dot >= 0 ? name.substring (dot + 1).down () : "";
        check (overrides.contains (name) || defaults.contains (ext), "content type for " + name);
        if (ext == "xml" || ext == "rels") {
            Xml.Doc* d = XmlIn.parse (zip.read_text (name));
            if (name.has_prefix ("ppt/slides/slide") || name.has_prefix ("ppt/slideLayouts/") || name.has_prefix ("ppt/slideMasters/")) {
                var ids = new Gee.HashSet<string> ();
                check_ids (d->get_root_element (), ids, name);
            }
            delete d;
        }
        if (ext == "rels") {
            string source = name.replace ("_rels/", "");
            source = source.substring (0, source.length - 5);
            if (source.has_prefix ("/")) source = source.substring (1);
            Xml.Doc* r = XmlIn.parse (zip.read_text (name));
            foreach (Xml.Node* rel in XmlIn.elements (r->get_root_element (), "Relationship")) {
                if (XmlIn.attr (rel, "TargetMode") == "External") continue;
                string target = OoxmlRels.resolve (source == ".rels" || name == "_rels/.rels" ? "" : source, XmlIn.attr (rel, "Target"));
                check (zip.has (target), "relationship target exists: %s from %s".printf (target, name));
            }
            delete r;
        }
    }
    Xml.Doc* pd = XmlIn.parse (zip.read_text ("ppt/presentation.xml"));
    var slide_ids = new Gee.HashSet<string> ();
    foreach (Xml.Node* s in XmlIn.elements (XmlIn.child (pd->get_root_element (), "sldIdLst"), "sldId")) {
        string id = XmlIn.attr (s, "id");
        check (!slide_ids.contains (id) && int.parse (id) >= 256, "slide id unique " + id);
        slide_ids.add (id);
    }
    delete pd;
}

void check_ids (Xml.Node* n, Gee.HashSet<string> ids, string part) {
    for (Xml.Node* c = n->children; c != null; c = c->next) {
        if (c->type != Xml.ElementType.ELEMENT_NODE) continue;
        if (c->name == "Fallback") continue;
        if (c->name == "cNvPr") {
            string id = XmlIn.attr (c, "id");
            check (!ids.contains (id) && int.parse (id) > 0, "shape id unique %s in %s".printf (id, part));
            ids.add (id);
        }
        check_ids (c, ids, part);
    }
}

void test_templates () throws Error {
    foreach (var t in Templates.all ()) {
        var p = Templates.build (t.id);
        p.properties.author = "Test Author";
        p.properties.created = "2026-01-02T03:04:05Z";
        p.properties.modified = "2026-01-03T03:04:05Z";
        uint8[] data;
        var q = roundtrip (p, out data);
        compare_pres (p, q, "template " + t.id);
        uint8[] data2;
        var r = roundtrip (q, out data2);
        compare_pres (p, r, "template twice " + t.id);
    }
}

Presentation synthetic () {
    var p = Factory.new_presentation (ThemePreset.find ("clean"));
    p.loop = true;
    p.use_timings = false;
    p.footer_text = "Footer text";
    p.date_text = "Today";
    p.properties.title = "Synthetic";
    p.properties.author = "Tester";
    p.properties.subject = "Everything";
    p.properties.keywords = "a, b";
    p.properties.created = "2026-01-02T03:04:05Z";
    p.properties.modified = "2026-01-03T03:04:05Z";
    var m2 = Factory.build_master (ThemePreset.find ("midnight"), p.width, p.height);
    m2.id = "master2";
    foreach (var l in m2.layouts) l.id = "m2-" + l.id;
    m2.layouts[1].show_master_shapes = false;
    m2.layouts[1].background = new Fill.solid ("#223344");
    p.masters.add (m2);
    var png = new Bytes (png_bytes (64, 32, 0.9, 0.2, 0.1));
    var png2 = new Bytes (png_bytes (16, 16, 0.2, 0.7, 0.3));

    var s = Factory.add_slide (p, p.master.layout_of_kind (LayoutKind.BLANK), 1);
    for (int k = 0; k <= (int) ShapeKind.LINE; k++) {
        var sh = Factory.shape (p, (ShapeKind) k, 10 + (k % 9) * 100, 10 + (k / 9) * 120, 80 + k, 60 + k * 0.5);
        if (k % 3 == 0) sh.fill = new Fill.solid ("#ff8800@0.5");
        else if (k % 3 == 1) sh.fill = new Fill.gradient ("accent2", "accent3~0.5+0.1", 45 + k, k % 2 == 0);
        if ((ShapeKind) k != ShapeKind.LINE) {
            sh.line.color = k % 2 == 0 ? "dk2" : "#123456";
            sh.line.width = 0.5 + k * 0.25;
            sh.line.dash = (DashKind) (k % 5);
        } else {
            sh.line.head = ArrowKind.OVAL;
            sh.line.tail = ArrowKind.TRIANGLE;
            sh.flip_h = true;
        }
        sh.rotation = k * 7.5;
        sh.flip_v = k % 4 == 1;
        sh.corner = 0.05 + k * 0.01;
        sh.shadow.enabled = k % 2 == 1;
        sh.shadow.blur = 3 + k;
        sh.shadow.distance = 2;
        sh.shadow.angle = 30 + k;
        sh.shadow.color = "#330000";
        sh.shadow.opacity = 0.5;
        sh.locked = k == 5;
        sh.name = "Shape %d".printf (k);
        sh.description = k == 3 ? "Accessible description" : "";
        s.elements.add (sh);
    }
    var custom = new ShapeElement (ShapeKind.CUSTOM);
    custom.set_geometry (500, 400, 120, 90);
    custom.path.add (new PathCommand ('M', { 0, 1 }));
    custom.path.add (new PathCommand ('L', { 0.5, 0 }));
    custom.path.add (new PathCommand ('C', { 0.7, 0, 1, 0.3, 1, 1 }));
    custom.path.add (new PathCommand ('Q', { 0.5, 0.8, 0, 1 }));
    custom.path.add (new PathCommand ('Z', {}));
    custom.fill = new Fill.solid ("accent5");
    p.assign_ids (custom);
    s.elements.add (custom);
    var inner = new GroupElement ();
    inner.children.add (Factory.shape (p, ShapeKind.ELLIPSE, 700, 400, 30, 30));
    inner.children.add (Factory.shape (p, ShapeKind.RECT, 740, 410, 20, 40));
    inner.fit ();
    inner.name = "Inner";
    p.assign_ids (inner);
    var outer = new GroupElement ();
    outer.children.add (inner);
    outer.children.add (Factory.shape (p, ShapeKind.STAR5, 800, 380, 50, 50));
    outer.fit ();
    outer.name = "Outer";
    p.assign_ids (outer);
    s.elements.add (outer);
    s.background = new Fill.picture (png, "image/png");
    s.name = "Shapes";

    s = Factory.add_slide (p, p.master.layout_of_kind (LayoutKind.TITLE_CONTENT), 2);
    ((ShapeElement) s.placeholder (PlaceholderKind.TITLE)).text.set_plain ("Rich Text");
    var body = ((ShapeElement) s.elements[1]).text;
    body.paragraphs.clear ();
    NumberStyle[] styles = { NumberStyle.ARABIC_PERIOD, NumberStyle.ARABIC_PAREN, NumberStyle.ALPHA_LOWER, NumberStyle.ALPHA_UPPER, NumberStyle.ROMAN_LOWER, NumberStyle.ROMAN_UPPER };
    for (int i = 0; i < 6; i++) {
        var par = new Paragraph ("Numbered %d".printf (i));
        par.bullet = BulletKind.NUMBER;
        par.number_style = styles[i];
        par.number_start = i + 1;
        par.level = i % 3;
        body.paragraphs.add (par);
    }
    var none = new Paragraph ("No bullet");
    none.bullet = BulletKind.NONE;
    none.align = TextAlign.RIGHT;
    body.paragraphs.add (none);
    var chr = new Paragraph ("Char bullet");
    chr.bullet = BulletKind.CHAR;
    chr.bullet_char = "▪";
    chr.bullet_color = "accent2";
    chr.align = TextAlign.JUSTIFY;
    chr.space_before = 6;
    chr.space_after = 3.5;
    chr.line_spacing = 1.25;
    body.paragraphs.add (chr);
    var inherit = new Paragraph ("Inherited");
    inherit.align = TextAlign.CENTER;
    inherit.end_format.size = 17;
    inherit.end_format.bold = 1;
    inherit.end_format.color = "#00ff00";
    body.paragraphs.add (inherit);
    body.autofit = AutoFit.SHRINK;
    body.font_scale = 0.85;
    body.line_reduction = 0.1;
    var tb = Factory.text_box (p, 40, 380, 400, "");
    tb.text.paragraphs.clear ();
    var rp = new Paragraph ();
    var r1 = new TextRun ("Bold ");
    r1.bold = 1;
    r1.italic = 0;
    r1.size = 21.5;
    r1.font = "Georgia";
    rp.runs.add (r1);
    var r2 = new TextRun ("italic underline strike");
    r2.italic = 1;
    r2.underline = 1;
    r2.strike = 1;
    r2.color = "accent4~0.75+0.1@0.8";
    r2.highlight = "#ffff00";
    rp.runs.add (r2);
    var r3 = new TextRun ("super");
    r3.baseline = 1;
    r3.bold = 0;
    r3.underline = 0;
    r3.strike = 0;
    rp.runs.add (r3);
    var r4 = new TextRun ("sub");
    r4.baseline = -1;
    r4.font = "+mj-lt";
    rp.runs.add (r4);
    var r5 = new TextRun ("link");
    r5.link = "https://example.org/a?b=c&d=e";
    rp.runs.add (r5);
    var r6 = new TextRun ("line one\vline two\v");
    r6.color = "tx2";
    rp.runs.add (r6);
    rp.runs.add (Factory.field_run ("slidenum", "7"));
    rp.runs.add (Factory.field_run ("datetime1", "1/1/2026"));
    tb.text.paragraphs.add (rp);
    tb.text.anchor = TextAnchor.BOTTOM;
    tb.text.wrap = false;
    tb.text.columns = 2;
    tb.text.inset_left = 1.5;
    tb.text.inset_top = 2;
    tb.text.inset_right = 3;
    tb.text.inset_bottom = 4;
    tb.list_style = new TextStyle ();
    tb.list_style.levels[0].size = 13;
    tb.list_style.levels[0].color = "accent6";
    tb.list_style.levels[0].caps = true;
    tb.list_style.levels[2].bullet = BulletKind.CHAR;
    tb.list_style.levels[2].bullet_char = "+";
    tb.list_style.levels[2].margin = 30;
    tb.list_style.levels[2].indent = -10;
    s.elements.add (tb);
    var vert = Factory.text_box (p, 600, 100, 80, "Vertical");
    vert.text.vertical = true;
    vert.text.autofit = AutoFit.NONE;
    s.elements.add (vert);
    s.notes = "First note line\nSecond note line";
    s.hidden = true;
    s.show_master_shapes = false;

    s = Factory.add_slide (p, p.master.layout_of_kind (LayoutKind.PICTURE_CAPTION), 3);
    var img = new ImageElement (png, "image/png");
    img.set_geometry (100, 100, 300, 150);
    img.crop_left = 0.1;
    img.crop_top = 0.05;
    img.crop_right = 0.2;
    img.crop_bottom = 0.15;
    img.brightness = 0.2;
    img.contrast = -0.3;
    img.saturation = 0.5;
    img.sepia = true;
    img.blur = 2.5;
    img.opacity = 0.7;
    img.corner = 0.12;
    img.line.color = "accent1";
    img.line.width = 3;
    img.shadow.enabled = true;
    img.locked = true;
    img.description = "Red picture";
    img.name = "Picture";
    p.assign_ids (img);
    s.elements.add (img);
    var gray = new ImageElement (png2, "image/png");
    gray.set_geometry (450, 100, 100, 100);
    gray.saturation = 0;
    gray.rotation = 12;
    gray.flip_h = true;
    p.assign_ids (gray);
    s.elements.add (gray);
    var same = new ImageElement (png, "image/png");
    same.set_geometry (600, 100, 64, 32);
    p.assign_ids (same);
    s.elements.add (same);
    var ph_img = new ImageElement (png2, "image/png");
    foreach (var e in s.elements) {
        if (e.placeholder == PlaceholderKind.PICTURE) {
            ph_img.set_geometry (e.x, e.y, e.w, e.h);
            ph_img.placeholder = PlaceholderKind.PICTURE;
            ph_img.placeholder_idx = e.placeholder_idx;
            ph_img.inherit_geometry = true;
        }
    }
    p.assign_ids (ph_img);
    s.elements.add (ph_img);
    var radial = Factory.shape (p, ShapeKind.ELLIPSE, 700, 300, 120, 120);
    radial.fill = new Fill.gradient ("#ffffff", "accent1", 0, true);
    radial.fill.stops.insert (1, new GradientStop (0.4, "#ff00ff@0.3"));
    s.elements.add (radial);
    s.background = new Fill.gradient ("lt2", "#445566", 135);

    s = Factory.add_slide (p, p.master.layout_of_kind (LayoutKind.TITLE_ONLY), 4);
    var t = new TableElement (4, 4, 600, 36);
    t.set_geometry (60, 120, 600, 144);
    for (int r = 0; r < 4; r++) for (int c = 0; c < 4; c++) t.cells[r][c].text.set_plain ("R%dC%d".printf (r, c));
    t.merge (1, 1, 2, 2);
    t.merge (3, 0, 3, 1);
    t.cells[0][3].fill = "#ffcc00";
    t.cells[1][0].anchor = TextAnchor.MIDDLE;
    t.cells[2][3].anchor = TextAnchor.BOTTOM;
    t.cells[0][0].text.paragraphs[0].runs[0].bold = 1;
    t.first_col = true;
    t.last_row = true;
    t.banded_rows = false;
    t.banded_cols = true;
    t.style_color = "accent3";
    t.border.color = "#000000";
    t.border.width = 2;
    t.border.dash = DashKind.DASH;
    t.col_widths[0] = 180;
    t.col_widths[1] = 140;
    t.col_widths[2] = 140;
    t.col_widths[3] = 140;
    t.row_heights[2] = 50;
    t.sync_size ();
    t.name = "Table";
    p.assign_ids (t);
    s.elements.add (t);

    ChartKind[] kinds = { ChartKind.COLUMN, ChartKind.BAR, ChartKind.LINE, ChartKind.PIE, ChartKind.DOUGHNUT, ChartKind.AREA, ChartKind.SCATTER };
    s = Factory.add_slide (p, p.masters[1].layouts[1], 5);
    for (int i = 0; i < kinds.length; i++) {
        var ch = new ChartElement (kinds[i]);
        ch.set_geometry (20 + (i % 4) * 230, 40 + (i / 4) * 250, 220, 230);
        ch.sample_data ();
        ch.title = i % 2 == 0 ? "Chart %d".printf (i) : "";
        ch.legend = (LegendPosition) (i % 5);
        ch.data_labels = i % 2 == 1;
        ch.gridlines = i != 2;
        ch.smooth = kinds[i] == ChartKind.LINE;
        if (!kinds[i].is_radial ()) ch.grouping = (ChartGrouping) (i % 3);
        if (kinds[i] == ChartKind.SCATTER) {
            ch.categories.clear ();
            foreach (string c in new string[] { "1", "2.5", "4", "10" }) ch.categories.add (c);
            ch.grouping = ChartGrouping.CLUSTERED;
            ch.smooth = true;
        }
        ch.series[0].color = "accent6";
        if (ch.series.size > 1) ch.series[1].values[2] = null;
        ch.text_color = i == 0 ? "#333333" : "";
        ch.link = i == 0 ? "/home/user/Documents/Quarterly Sales.xlsx\tCombo\t#0" : "";
        ch.name = "Chart %d".printf (i);
        p.assign_ids (ch);
        s.elements.add (ch);
    }

    s = Factory.add_slide (p, p.master.layout_of_kind (LayoutKind.BLANK), 6);
    var shapes = new Gee.ArrayList<Element> ();
    for (int i = 0; i < 12; i++) {
        var sh = Factory.shape (p, ShapeKind.RECT, 20 + i * 70, 200, 60, 60);
        s.elements.add (sh);
        shapes.add (sh);
    }
    AnimEffect[] entr = AnimEffect.ENTRANCE;
    Direction[] dirs = { Direction.FROM_LEFT, Direction.FROM_RIGHT, Direction.FROM_TOP, Direction.FROM_BOTTOM };
    int n = 0;
    var auto = new Animation (shapes[11].id);
    auto.effect = AnimEffect.FADE;
    auto.trigger = AnimTrigger.AFTER_PREVIOUS;
    auto.duration = 0.4;
    s.animations.add (auto);
    foreach (var eff in entr) {
        var a = new Animation (shapes[n % 11].id);
        a.effect = eff;
        a.direction = dirs[n % 4];
        a.trigger = (AnimTrigger) (n % 3);
        a.duration = 0.25 + n * 0.1;
        a.delay = n * 0.05;
        s.animations.add (a);
        n++;
    }
    foreach (var eff in entr) {
        var a = new Animation (shapes[n % 11].id);
        a.anim_class = AnimClass.EXIT;
        a.effect = eff;
        a.direction = dirs[(n + 1) % 4];
        a.trigger = (AnimTrigger) (n % 3);
        a.duration = 0.3 + n * 0.02;
        s.animations.add (a);
        n++;
    }
    foreach (var eff in AnimEffect.EMPHASIS) {
        var a = new Animation (shapes[n % 11].id);
        a.anim_class = AnimClass.EMPHASIS;
        a.effect = eff;
        a.trigger = AnimTrigger.ON_CLICK;
        a.duration = 0.8;
        s.animations.add (a);
        n++;
    }
    var fl = new Animation (shapes[0].id);
    fl.effect = AnimEffect.FLOAT;
    fl.direction = Direction.FROM_TOP;
    s.animations.add (fl);

    for (int i = 0; i < TransitionKind.ALL.length; i++) {
        var ts = Factory.add_slide (p, i % 2 == 0 ? p.master.layout_of_kind (LayoutKind.SECTION) : p.masters[1].layouts[2], p.slides.size);
        ((ShapeElement) ts.placeholder (PlaceholderKind.TITLE)).text.set_plain ("Transition %d".printf (i));
        ts.transition.kind = TransitionKind.ALL[i];
        ts.transition.direction = dirs[i % 4];
        ts.transition.duration = 0.3 + i * 0.137;
        ts.transition.on_click = i % 3 != 0;
        ts.transition.advance_after = i % 2 == 0 ? 2.5 + i : -1;
    }
    return p;
}

void test_synthetic () throws Error {
    var p = synthetic ();
    uint8[] data;
    var q = roundtrip (p, out data);
    compare_pres (p, q, "synthetic");
    uint8[] data2;
    var r = roundtrip (q, out data2);
    compare_pres (p, r, "synthetic twice");
    var zip = new ZipReader (data);
    int media = 0;
    foreach (string name in zip.names ()) if (name.has_prefix ("ppt/media/")) media++;
    check (media == 2, "images are stored once each, found %d".printf (media));
    check (zip.has ("ppt/charts/chart7.xml"), "seven chart parts");
    check (zip.has ("ppt/notesSlides/notesSlide3.xml"), "notes slide part for slide 3");
    check (zip.has ("ppt/slideMasters/slideMaster2.xml"), "second master part");
    string timing = zip.read_text ("ppt/slides/slide7.xml");
    check (timing.contains ("nodeType=\"mainSeq\"") && timing.contains ("p:bldLst") && timing.contains ("ppt_x") && timing.contains ("p:animScale") && timing.contains ("p:animRot") && timing.contains ("filter=\"wipe("), "timing tree has real behaviours");
    string trans = zip.read_text ("ppt/slides/slide8.xml");
    check (trans.contains ("mc:AlternateContent") && trans.contains ("p14:dur="), "transition with exact duration");
    string pic = zip.read_text ("ppt/slides/slide4.xml");
    check (pic.contains ("a:srcRect") && pic.contains ("a:alphaModFix") && pic.contains ("a:grayscl") && pic.contains ("sg:filters"), "picture effects written");
}

void test_fixture_realistic () throws Error {
    var p = read_fixture ("pptx-realistic", true);
    check (p.slides.size == 3, "fixture slides");
    check (p.masters.size == 1 && p.master.layouts.size == 2, "fixture master and layouts");
    check (p.master.layouts[0].name == "Title Slide" && p.master.layouts[0].kind == LayoutKind.TITLE, "layout 1");
    check (p.master.layouts[1].name == "Title and Content" && p.master.layouts[1].kind == LayoutKind.TITLE_CONTENT, "layout 2");
    check (near (p.width, 960) && near (p.height, 540), "fixture size");
    check (p.properties.title == "Quarterly Results" && p.properties.author == "Ada Lovelace", "core properties");
    var th = p.theme;
    check (th.name == "Office Theme" && th.scheme_hex ("accent1").down () == "#4472c4" && th.scheme_hex ("dk1") == "#000000" && th.scheme_hex ("lt1").down () == "#ffffff", "theme colors");
    check (th.major_font == "Calibri Light" && th.minor_font == "Calibri", "theme fonts");
    check (p.master.background.kind == FillKind.SOLID && p.master.background.color == "lt1", "master background from bgRef");
    check (near (p.master.title_style.levels[0].size, 44) && p.master.title_style.levels[0].font == "+mj-lt", "title style");
    check (p.master.body_style.levels[0].bullet == BulletKind.CHAR && p.master.body_style.levels[0].bullet_char == "•" && near (p.master.body_style.levels[0].margin, 18) && near (p.master.body_style.levels[0].indent, -18), "body style");
    check (near (p.master.body_style.levels[1].size, 24) && near (p.master.body_style.levels[0].line_spacing, 0.9, 1e-6), "body style level 2");

    var s1 = p.slides[0];
    var title = s1.placeholder (PlaceholderKind.CENTER_TITLE);
    check (title != null && title.inherit_geometry, "slide 1 title inherits geometry");
    check (near (title.x, 120) && near (title.y, 1122363 / 12700.0) && near (title.w, 720), "slide 1 title geometry from layout");
    check (s1.title () == "Quarterly Results", "slide 1 title text");
    var ls = p.level_style (s1, p.layout_for (s1), p.master, title, 0);
    check (near (ls.size, 60) && ls.align == TextAlign.CENTER, "title inherits layout list style");
    var sub = (ShapeElement) s1.placeholder (PlaceholderKind.SUBTITLE);
    check (sub.placeholder_idx == 1 && sub.text.paragraphs[0].runs.size == 3, "subtitle runs");
    check (sub.text.paragraphs[0].runs[1].text == " ", "whitespace run preserved");
    check (sub.text.paragraphs[0].runs[0].bold == 1 && sub.text.paragraphs[0].runs[2].italic == 1 && sub.text.paragraphs[0].runs[2].color == "#c00000", "subtitle formatting");
    check (sub.text.autofit == AutoFit.SHRINK && near (sub.text.font_scale, 0.925, 1e-6) && near (sub.text.line_reduction, 0.1, 1e-6), "normAutofit");
    var pic = s1.elements[2] as ImageElement;
    check (pic != null && pic.description == "A small logo" && near (pic.opacity, 0.8) && near (pic.crop_left, 0.1) && near (pic.crop_bottom, 0.05), "picture");
    int iw, ih;
    check (ImageCache.size_of (pic.data, out iw, out ih) && iw == 40 && ih == 20, "picture data decodes");

    var s2 = p.slides[1];
    check (s2.elements.size == 5, "slide 2 elements %d".printf (s2.elements.size));
    var content = (ShapeElement) s2.elements[1];
    check (content.placeholder == PlaceholderKind.OBJECT && content.placeholder_idx == 1 && content.inherit_geometry, "content placeholder");
    check (near (content.y, 1825625 / 12700.0), "content geometry from master");
    check (content.text.paragraphs.size == 3 && content.text.paragraphs[1].level == 1 && content.text.paragraphs[2].bullet == BulletKind.NONE, "content paragraphs");
    check (content.text.paragraphs[2].runs[0].link == "https://example.org/report", "hyperlink");
    var styled = (ShapeElement) s2.elements[2];
    check (styled.shape == ShapeKind.ROUND_RECT && near (styled.corner, 0.25) && near (styled.rotation, 30), "styled shape geometry");
    check (styled.fill.kind == FillKind.SOLID && styled.fill.color == "accent1", "fillRef applied");
    check (styled.line.color == "accent1~0.5" && near (styled.line.width, 1), "lnRef applied: %s %g".printf (styled.line.color, styled.line.width));
    check (styled.text.paragraphs[0].runs[0].color == "lt1", "fontRef color applied");
    check (styled.text.anchor_set && styled.text.anchor == TextAnchor.MIDDLE, "shape anchor");
    var grp = s2.elements[3] as GroupElement;
    check (grp != null && grp.children.size == 2, "group");
    check (near (grp.x, 500) && near (grp.w, 200) && near (grp.h, 100), "group geometry");
    var oval = grp.children[0];
    var rect = (ShapeElement) grp.children[1];
    check (near (oval.x, 500) && near (oval.y, 360) && near (oval.w, 100) && near (oval.h, 100), "group child scaled from child space");
    check (near (rect.x, 600) && rect.fill.kind == FillKind.GRADIENT && rect.fill.stops[1].color == "accent2~0.5", "second child");
    check (rect.shadow.enabled && near (rect.shadow.opacity, 0.4) && rect.shadow.color == "#000000" && near (rect.shadow.angle, 45), "shadow from prstClr");
    var arrow = (ShapeElement) s2.elements[4];
    check (arrow.shape == ShapeKind.LINE && arrow.flip_v && arrow.line.tail == ArrowKind.TRIANGLE && arrow.line.dash == DashKind.DASH && near (arrow.line.width, 2.25) && arrow.line.color == "dk1", "connector");
    check (s2.transition.kind == TransitionKind.VORTEX && s2.transition.variant == 1 && near (s2.transition.duration, 2.0), "p14 vortex transition read");
    check (s2.animations.size == 2, "fixture animations");
    var fly = s2.animations[0];
    check (fly.effect == AnimEffect.FLY && fly.anim_class == AnimClass.ENTRANCE && fly.direction == Direction.FROM_BOTTOM && fly.trigger == AnimTrigger.ON_CLICK && near (fly.duration, 0.5) && fly.target == styled.id, "fly in");
    var fade = s2.animations[1];
    check (fade.effect == AnimEffect.FADE && fade.trigger == AnimTrigger.AFTER_PREVIOUS && near (fade.duration, 0.75) && near (fade.delay, 0.25) && fade.target == grp.id, "fade after previous");

    var s3 = p.slides[2];
    check (s3.notes == "Mention the new office\nThank the sales team", "notes text");
    var table = s3.elements[1] as TableElement;
    check (table != null && table.rows == 3 && table.cols == 3 && table.style_color == "accent2", "table with built-in style");
    check (table.first_row && table.banded_rows && !table.first_col, "table flags");
    check (table.cells[2][0].col_span == 2 && table.cells[2][1].covered && table.cells[2][2].anchor == TextAnchor.MIDDLE, "table merge and anchor");
    check (table.cells[1][1].text.plain_text () == "4.2M" && near (table.col_widths[0], 160), "table cells");
    var chart = s3.elements[2] as ChartElement;
    check (chart != null && chart.chart == ChartKind.COLUMN && chart.grouping == ChartGrouping.CLUSTERED, "chart kind");
    check (chart.title == "Revenue by Quarter" && chart.legend == LegendPosition.BOTTOM && chart.gridlines, "chart title legend grid");
    check (chart.categories.size == 3 && chart.categories[2] == "Q3", "chart categories");
    check (chart.series.size == 2 && chart.series[0].name == "2023" && chart.series[0].color == "accent1" && near (chart.series[0].value_at (0), 4.3), "chart series");
    check (chart.series[1].values.size == 3 && chart.series[1].values[1] == null && near (chart.series[1].value_at (2), 4), "chart gaps");
    var ids = new Gee.HashSet<int> ();
    foreach (var s in p.slides) foreach (var e in s.elements) {
        check (!ids.contains (e.id), "unique ids after load");
        ids.add (e.id);
    }
    uint8[] data;
    var again = roundtrip (p, out data);
    compare_pres (p, again, "fixture realistic round trip");
}

void test_fixture_minimal () throws Error {
    var p = read_fixture ("pptx-minimal", false);
    check (p.slides.size == 1 && near (p.width, 720) && near (p.height, 540), "minimal deck");
    check (p.theme.name == "Night" && p.theme.major_font == "Georgia", "minimal theme");
    var bg = p.master.background;
    check (bg.kind == FillKind.GRADIENT && bg.radial && bg.stops[0].color == "dk2" && bg.stops[1].color == "dk1", "radial background with dark clrMap");
    var layout = p.master.layouts[0];
    check (!layout.show_master_shapes && layout.name == "Only Title" && layout.kind == LayoutKind.CUSTOM, "layout without type");
    var s = p.slides[0];
    check (s.hidden && s.name == "Intro", "hidden named slide");
    check (s.elements.size == 3, "hidden element skipped and fallback taken: %d".printf (s.elements.size));
    var title = (ShapeElement) s.elements[0];
    check (title.inherit_geometry && near (title.x, 36) && near (title.w, 648), "title from master geometry");
    var p0 = title.text.paragraphs[0];
    check (p0.runs.size == 1 && p0.runs[0].text == "First line\vSecond line" && p0.runs[0].color == "lt1", "soft break and mapped tx1");
    check (title.text.paragraphs[1].runs[0].field == "datetime1", "datetime field");
    var free = (ShapeElement) s.elements[1];
    check (free.shape == ShapeKind.CUSTOM && free.path.size == 4 && free.path[2].op == 'C' && near (free.path[2].pts[2], 1) && near (free.path[1].pts[0], 0.5), "custom geometry normalized");
    check (free.fill.kind == FillKind.SOLID && free.fill.color == "accent2", "pattern fill as solid");
    var fb = (ShapeElement) s.elements[2];
    check (fb.name == "Fallback Shape" && fb.preset_name () == "flowChartDecision" && fb.text_box && !fb.text.wrap && fb.text.autofit == AutoFit.RESIZE, "alternate content fallback");
    check (fb.text.anchor == TextAnchor.BOTTOM && near (fb.text.inset_left, 0), "fallback body props");
    var fp = fb.text.paragraphs[0];
    check (fp.bullet == BulletKind.NUMBER && fp.number_style == NumberStyle.ROMAN_UPPER && fp.number_start == 3 && fp.align == TextAlign.RIGHT, "numbered paragraph");
    var fr = fp.runs[0];
    check (near (fr.size, 14.5) && fr.underline == 1 && fr.strike == 1 && fr.baseline == 1 && fr.highlight == "#ffff00" && fr.font == "+mj-lt", "run attributes");
    check (s.transition.kind == TransitionKind.PUSH && s.transition.direction == Direction.FROM_BOTTOM && !s.transition.on_click && near (s.transition.advance_after, 4) && near (s.transition.duration, 0.5), "plain transition");
    uint8[] data;
    var again = roundtrip (p, out data);
    compare_pres (p, again, "fixture minimal round trip");
}

void test_errors () {
    try {
        new PptxReader (new ZipReader (new ZipWriter ().finish ())).read ();
        check (false, "empty package must fail");
    } catch (Error e) {
        check (true, "empty package fails");
    }
    var zip = new ZipWriter ();
    try {
        zip.add_text ("ppt/presentation.xml", "<p:presentation xmlns:p=\"x\"><broken");
        new PptxReader (new ZipReader (zip.finish ())).read ();
        check (false, "malformed xml must fail");
    } catch (Error e) {
        check (true, "malformed xml fails");
    }
}

void main () {
    Intl.setlocale (LocaleCategory.ALL, "C.UTF-8");
    Intl.setlocale (LocaleCategory.NUMERIC, "it_IT.UTF-8");
    try {
        test_templates ();
        test_synthetic ();
        test_fixture_realistic ();
        test_fixture_minimal ();
        test_errors ();
    } catch (Error e) {
        error ("%s", e.message);
    }
    print ("pptx tests passed: %d/%d checks\n", checks, checks);
}
