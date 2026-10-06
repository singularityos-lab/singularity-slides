using Singularity.Apps.Slides;

int checks = 0;

void check (bool ok, string what) {
    checks++;
    if (!ok) error ("check failed: %s", what);
}

bool near (double a, double b, double tol) {
    return Math.fabs (a - b) <= tol;
}

Presentation read_bytes (uint8[] data) throws Error {
    return new OdpReader (new ZipReader (data)).read ();
}

uint8[] write_pres (Presentation p, bool with_private = true) throws Error {
    var w = new OdpWriter (p);
    w.include_private = with_private;
    return w.write ();
}

Theme theme_of (Presentation p, Slide s) {
    return p.master_for (s).theme;
}

void check_color (Theme ta, string a, Theme tb, string b, string what) {
    var ca = ta.resolve (a);
    var cb = tb.resolve (b);
    double tol = 1.01 / 255;
    check (near (ca.r, cb.r, tol) && near (ca.g, cb.g, tol) && near (ca.b, cb.b, tol) && near (ca.a, cb.a, 0.011),
        "%s color %s (%s) vs %s (%s)".printf (what, a, ca.to_hex (), b, cb.to_hex ()));
}

void check_fill (Theme ta, Fill a, Theme tb, Fill b, string what) {
    check (a.kind == b.kind, what + " fill kind %d vs %d".printf ((int) a.kind, (int) b.kind));
    if (a.kind == FillKind.SOLID) check_color (ta, a.color, tb, b.color, what + " fill");
    if (a.kind == FillKind.GRADIENT) {
        check_color (ta, a.stops[0].color, tb, b.stops[0].color, what + " gradient start");
        check_color (ta, a.stops[a.stops.size - 1].color, tb, b.stops[b.stops.size - 1].color, what + " gradient end");
        check (a.radial == b.radial, what + " radial");
        if (!a.radial) check (near (a.angle, b.angle, 0.05), what + " gradient angle %g vs %g".printf (a.angle, b.angle));
    }
    if (a.kind == FillKind.IMAGE) {
        check (b.image != null && a.image.compare (b.image) == 0, what + " image bytes");
        check (a.tile == b.tile, what + " tile");
    }
}

void check_line (Theme ta, Line a, Theme tb, Line b, string what) {
    check (a.visible () == b.visible (), what + " line visible");
    if (!a.visible ()) return;
    check_color (ta, a.color, tb, b.color, what + " line");
    check (near (a.width, b.width, 0.05), what + " line width");
    check (a.dash == b.dash, what + " dash");
    check (a.head == b.head && a.tail == b.tail, what + " arrows");
}

void check_body (TextBody a, TextBody b, bool exact, string what) {
    check (a.plain_text () == b.plain_text (), what + " text '%s' vs '%s'".printf (a.plain_text (), b.plain_text ()));
    if (!exact) return;
    check (a.paragraphs.size == b.paragraphs.size, what + " paragraph count");
    for (int i = 0; i < a.paragraphs.size; i++) {
        var pa = a.paragraphs[i];
        var pb = b.paragraphs[i];
        check (pa.align == pb.align && pa.level == pb.level && pa.bullet == pb.bullet && pa.bullet_char == pb.bullet_char, what + " paragraph format %d".printf (i));
        check (pa.number_style == pb.number_style && pa.number_start == pb.number_start, what + " numbering");
        check (near (pa.space_before, pb.space_before, 1e-9) && near (pa.space_after, pb.space_after, 1e-9) && near (pa.line_spacing, pb.line_spacing, 1e-9), what + " spacing");
        check (pa.end_format.same_format (pb.end_format) || (pa.end_format.field == pb.end_format.field), what + " end format");
        var ra = new Gee.ArrayList<TextRun> ();
        var rb = new Gee.ArrayList<TextRun> ();
        foreach (var r in pa.runs) if (r.text != "" || r.field != "") ra.add (r);
        foreach (var r in pb.runs) if (r.text != "" || r.field != "") rb.add (r);
        check (ra.size == rb.size, what + " run count %d vs %d in '%s'".printf (ra.size, rb.size, pa.text ()));
        for (int k = 0; k < ra.size; k++) {
            check (ra[k].text == rb[k].text || ra[k].field == "slidenum", what + " run text");
            check (ra[k].field == rb[k].field, what + " run field");
            var x = ra[k].clone ();
            var y = rb[k].clone ();
            x.field = "";
            y.field = "";
            check (x.same_format (y), what + " run format '%s'".printf (ra[k].text));
        }
    }
    check (near (a.inset_left, b.inset_left, 0.05) && near (a.inset_top, b.inset_top, 0.05) && near (a.inset_right, b.inset_right, 0.05) && near (a.inset_bottom, b.inset_bottom, 0.05), what + " insets");
    check (a.anchor == b.anchor && a.anchor_set == b.anchor_set && a.wrap == b.wrap && a.autofit == b.autofit, what + " body props");
}

void check_element (Presentation pa, Theme ta, Element a, Presentation pb, Theme tb, Element b, bool exact, string what) {
    check (a.kind == b.kind, what + " kind %d vs %d".printf ((int) a.kind, (int) b.kind));
    check (near (a.x, b.x, 0.05) && near (a.y, b.y, 0.05) && near (a.w, b.w, 0.05) && near (a.h, b.h, 0.05),
        what + " geometry %g,%g %gx%g vs %g,%g %gx%g".printf (a.x, a.y, a.w, a.h, b.x, b.y, b.w, b.h));
    check (near (a.rotation, b.rotation, 0.01), what + " rotation %g vs %g".printf (a.rotation, b.rotation));
    check (a.flip_h == b.flip_h && a.flip_v == b.flip_v, what + " flips");
    check (a.name == b.name, what + " name");
    if (exact) {
        check (a.id == b.id, what + " id");
        check (a.placeholder == b.placeholder && a.placeholder_idx == b.placeholder_idx && a.inherit_geometry == b.inherit_geometry, what + " placeholder");
        check (a.description == b.description, what + " description");
        check (a.shadow.enabled == b.shadow.enabled, what + " shadow");
        if (a.shadow.enabled) {
            check_color (ta, a.shadow.color, tb, b.shadow.color, what + " shadow");
            check (near (a.shadow.blur, b.shadow.blur, 1e-9) && near (a.shadow.distance, b.shadow.distance, 1e-9) && near (a.shadow.angle, b.shadow.angle, 1e-9) && near (a.shadow.opacity, b.shadow.opacity, 1e-9), what + " shadow params");
        }
    }
    if (a.kind != ElementKind.TABLE && a.kind != ElementKind.GROUP && a.kind != ElementKind.CHART) check_line (ta, a.line, tb, b.line, what);
    switch (a.kind) {
        case ElementKind.SHAPE:
            var sa = (ShapeElement) a;
            var sb = (ShapeElement) b;
            if (exact || (sa.placeholder == PlaceholderKind.NONE && !sa.text_box)) check (sa.shape == sb.shape, what + " shape %d vs %d".printf ((int) sa.shape, (int) sb.shape));
            if (sa.shape != ShapeKind.LINE && (exact || sa.placeholder == PlaceholderKind.NONE)) check_fill (ta, sa.fill, tb, sb.fill, what);
            if (sa.text != null && !sa.text.is_empty ()) {
                check (sb.text != null, what + " has text");
                check_body (sa.text, sb.text, exact, what);
            }
            if (exact) {
                check (sa.text_box == sb.text_box && near (sa.corner, sb.corner, 1e-9), what + " shape props");
                check ((sa.list_style == null) == (sb.list_style == null), what + " list style presence");
                if (sa.list_style != null) check (Odf.style_code (sa.list_style) == Odf.style_code (sb.list_style), what + " list style");
                check (sa.path.size == sb.path.size, what + " path");
            }
            break;
        case ElementKind.IMAGE:
            var ia = (ImageElement) a;
            var ib = (ImageElement) b;
            check (ia.data.compare (ib.data) == 0, what + " image data");
            check (near (ia.crop_left, ib.crop_left, 0.002) && near (ia.crop_top, ib.crop_top, 0.002) && near (ia.crop_right, ib.crop_right, 0.002) && near (ia.crop_bottom, ib.crop_bottom, 0.002), what + " crop");
            check (near (ia.brightness, ib.brightness, 0.001) && near (ia.contrast, ib.contrast, 0.001) && near (ia.opacity, ib.opacity, 0.001), what + " image adjustments");
            check ((ia.saturation == 0) == (ib.saturation == 0), what + " greyscale");
            if (exact) check (ia.sepia == ib.sepia && ia.blur == ib.blur && ia.corner == ib.corner && ia.saturation == ib.saturation, what + " private image filters");
            break;
        case ElementKind.TABLE:
            var xa = (TableElement) a;
            var xb = (TableElement) b;
            check (xa.rows == xb.rows && xa.cols == xb.cols, what + " table size");
            for (int c = 0; c < xa.cols; c++) check (near (xa.col_widths[c], xb.col_widths[c], 0.05), what + " column width");
            for (int r = 0; r < xa.rows; r++) {
                check (near (xa.row_heights[r], xb.row_heights[r], 0.05), what + " row height");
                for (int c = 0; c < xa.cols; c++) {
                    var ca = xa.cells[r][c];
                    var cb = xb.cells[r][c];
                    check (ca.covered == cb.covered && ca.row_span == cb.row_span && ca.col_span == cb.col_span, what + " cell span %d,%d".printf (r, c));
                    if (ca.covered) continue;
                    check (ca.text.plain_text () == cb.text.plain_text (), what + " cell text");
                    check (ca.anchor == cb.anchor, what + " cell anchor");
                    var rr = new Renderer ();
                    check_color (ta, rr.table_cell_fill (xa, r, c), tb, rr.table_cell_fill (xb, r, c), what + " cell fill");
                }
            }
            check (xa.first_row == xb.first_row && xa.banded_rows == xb.banded_rows && xa.first_col == xb.first_col && xa.last_row == xb.last_row && xa.banded_cols == xb.banded_cols, what + " table flags");
            if (exact) check (xa.style_color == xb.style_color, what + " table style color");
            break;
        case ElementKind.CHART:
            var ca = (ChartElement) a;
            var cb = (ChartElement) b;
            check (ca.chart == cb.chart && ca.grouping == cb.grouping, what + " chart kind");
            check (ca.title == cb.title && ca.legend == cb.legend && ca.data_labels == cb.data_labels && ca.smooth == cb.smooth, what + " chart options");
            check (ca.categories.size == cb.categories.size, what + " categories");
            for (int i = 0; i < ca.categories.size; i++) check (ca.categories[i] == cb.categories[i], what + " category");
            check (ca.series.size == cb.series.size, what + " series count");
            for (int i = 0; i < ca.series.size; i++) {
                check (ca.series[i].name == cb.series[i].name, what + " series name");
                for (int k = 0; k < ca.series[i].values.size; k++) check (near (ca.series[i].value_at (k), cb.series[i].value_at (k), 1e-9), what + " value");
                if (!ca.chart.is_radial ()) check_color (ta, ChartPainter.series_color (ca, i), tb, ChartPainter.series_color (cb, i), what + " series color");
            }
            if (exact) check (ca.gridlines == cb.gridlines && ca.text_color == cb.text_color, what + " chart private");
            break;
        case ElementKind.GROUP:
            var ga = (GroupElement) a;
            var gb = (GroupElement) b;
            check (ga.children.size == gb.children.size, what + " group size");
            for (int i = 0; i < ga.children.size; i++) check_element (pa, ta, ga.children[i], pb, tb, gb.children[i], exact, what + "/child%d".printf (i));
            break;
    }
}

void check_slide (Presentation pa, Slide a, Presentation pb, Slide b, bool exact, string what) {
    var ta = theme_of (pa, a);
    var tb = theme_of (pb, b);
    check (a.elements.size == b.elements.size, what + " element count %d vs %d".printf (a.elements.size, b.elements.size));
    for (int i = 0; i < a.elements.size; i++) check_element (pa, ta, a.elements[i], pb, tb, b.elements[i], exact, what + "/e%d".printf (i));
    check (a.title () == b.title (), what + " title");
    check (a.notes == b.notes, what + " notes");
    check (a.hidden == b.hidden, what + " hidden");
    check (a.show_master_shapes == b.show_master_shapes, what + " master shapes");
    var t1 = a.transition;
    var t2 = b.transition;
    check (t1.kind == t2.kind, what + " transition kind %d vs %d".printf ((int) t1.kind, (int) t2.kind));
    if (t1.kind != TransitionKind.NONE) check (near (t1.duration, t2.duration, 0.001), what + " transition duration");
    if (t1.kind.has_direction ()) check (t1.direction == t2.direction, what + " transition direction");
    check (near (t1.advance_after, t2.advance_after, 0.001), what + " advance");
    if (t1.advance_after >= 0) check (t1.on_click == t2.on_click, what + " on click");
    check (a.animations.size == b.animations.size, what + " animation count %d vs %d".printf (a.animations.size, b.animations.size));
    for (int i = 0; i < a.animations.size; i++) {
        var x = a.animations[i];
        var y = b.animations[i];
        check (x.anim_class == y.anim_class && x.effect == y.effect, what + " anim effect %d".printf (i));
        check (x.trigger == y.trigger, what + " anim trigger %d: %d vs %d".printf (i, (int) x.trigger, (int) y.trigger));
        check (x.effect == AnimEffect.APPEAR || near (x.duration, y.duration, 0.001), what + " anim duration %g vs %g".printf (x.duration, y.duration));
        check (near (x.delay, y.delay, 0.001), what + " anim delay %g vs %g".printf (x.delay, y.delay));
        if (x.effect.has_direction ()) check (x.direction == y.direction, what + " anim direction");
        var ex = a.find (x.target);
        var ey = b.find (y.target);
        check (ey != null, what + " anim target resolves");
        check (a.elements.index_of (ex) == b.elements.index_of (ey), what + " anim target identity");
    }
    if (a.background == null) {
        if (exact) check (b.background == null, what + " background inherited");
    } else {
        check (b.background != null, what + " background present");
        check_fill (ta, a.background, tb, b.background, what + " background");
    }
    check_fill (ta, pa.background_for (a), tb, pb.background_for (b), what + " effective background");
}

void compare (Presentation a, Presentation b, bool exact, string what) {
    check (a.slides.size == b.slides.size, what + " slide count");
    check (near (a.width, b.width, 0.05) && near (a.height, b.height, 0.05), what + " slide size");
    for (int i = 0; i < a.slides.size; i++) check_slide (a, a.slides[i], b, b.slides[i], exact, what + " slide %d".printf (i + 1));
    if (!exact) return;
    check (a.masters.size == b.masters.size, what + " master count");
    for (int m = 0; m < a.masters.size; m++) {
        var ma = a.masters[m];
        var mb = b.masters[m];
        check (ma.id == mb.id && ma.name == mb.name, what + " master id");
        check (Odf.theme_code (ma.theme) == Odf.theme_code (mb.theme), what + " theme");
        check (Odf.fill_code (ma.background) == Odf.fill_code (mb.background), what + " master background");
        check (Odf.style_code (ma.title_style) == Odf.style_code (mb.title_style), what + " title style");
        check (Odf.style_code (ma.body_style) == Odf.style_code (mb.body_style), what + " body style");
        check (Odf.style_code (ma.other_style) == Odf.style_code (mb.other_style), what + " other style");
        check (ma.elements.size == mb.elements.size, what + " master elements");
        for (int i = 0; i < ma.elements.size; i++) check_element (a, ma.theme, ma.elements[i], b, mb.theme, mb.elements[i], true, what + " master e%d".printf (i));
        check (ma.layouts.size == mb.layouts.size, what + " layout count");
        for (int l = 0; l < ma.layouts.size; l++) {
            var la = ma.layouts[l];
            var lb = mb.layouts[l];
            check (la.id == lb.id && la.name == lb.name && la.kind == lb.kind && la.show_master_shapes == lb.show_master_shapes, what + " layout " + la.name);
            check ((la.background == null) == (lb.background == null), what + " layout background");
            check (la.elements.size == lb.elements.size, what + " layout elements " + la.name);
            for (int i = 0; i < la.elements.size; i++) check_element (a, ma.theme, la.elements[i], b, mb.theme, lb.elements[i], true, what + " layout %s e%d".printf (la.name, i));
        }
    }
    for (int i = 0; i < a.slides.size; i++) check (a.slides[i].layout_id == b.slides[i].layout_id, what + " layout id");
    check (a.loop == b.loop && a.use_timings == b.use_timings && a.footer_text == b.footer_text && a.date_text == b.date_text, what + " show settings");
    check (a.properties.title == b.properties.title && a.properties.author == b.properties.author && a.properties.created == b.properties.created, what + " properties");
}

Bytes make_png (int w, int h, double r, double g, double b) {
    var surf = new Cairo.ImageSurface (Cairo.Format.ARGB32, w, h);
    var cr = new Cairo.Context (surf);
    cr.set_source_rgb (r, g, b);
    cr.paint ();
    cr.set_source_rgb (1 - r, 1 - g, 1 - b);
    cr.rectangle (0, 0, w / 2, h / 2);
    cr.fill ();
    var buf = new ByteArray ();
    surf.write_to_png_stream ((data) => {
        buf.append (data);
        return Cairo.Status.SUCCESS;
    });
    return ByteArray.free_to_bytes (buf);
}

Presentation synthetic () {
    var p = Factory.new_presentation (ThemePreset.find ("coral"));
    p.loop = true;
    p.use_timings = false;
    p.footer_text = "Footer & <text>";
    p.date_text = "28 September 2026";
    p.properties.title = "Synthetic";
    p.properties.author = "Test Author";
    p.properties.created = "2026-09-01T10:00:00Z";
    p.properties.modified = "2026-09-02T10:00:00Z";
    p.master.layouts[1].background = new Fill.gradient ("accent2", "accent3@0.5", 30);
    var png = make_png (40, 20, 0.2, 0.4, 0.8);
    var s = p.slides[0];
    ((ShapeElement) s.elements[0]).text.set_plain ("Synthetic Title");
    s.background = new Fill.picture (png, "image/png");
    s.transition.kind = TransitionKind.FADE_BLACK;
    s.transition.duration = 1.25;
    s.transition.advance_after = 3.5;
    s.transition.on_click = false;
    s.notes = "First line\nSecond line with  two spaces";

    var s2 = Factory.add_slide (p, p.master.layout_of_kind (LayoutKind.TITLE_ONLY), 1);
    ((ShapeElement) s2.elements[0]).text.set_plain ("Shapes");
    s2.background = new Fill.gradient ("#ff0000", "#0000ff@0.4", 45, true);
    int k = 0;
    for (int i = 0; i < (int) ShapeKind.CUSTOM; i++) {
        if ((ShapeKind) i == ShapeKind.LINE) continue;
        var sh = Factory.shape (p, (ShapeKind) i, 20 + (k % 9) * 100, 130 + (k / 9) * 110, 80, 60);
        sh.fill = new Fill.solid (k % 3 == 0 ? "accent%d".printf (k % 6 + 1) : (k % 3 == 1 ? "#12ab34@0.5" : "accent1~0.4+0.6"));
        sh.line.color = "dk1";
        sh.line.width = 1.5 + k % 3;
        sh.line.dash = (DashKind) (k % 5);
        sh.rotation = k % 4 == 1 ? 30 : (k % 4 == 2 ? 290.5 : 0);
        sh.flip_h = k % 5 == 3;
        sh.flip_v = k % 7 == 4;
        sh.corner = 0.25;
        sh.shadow.enabled = k % 2 == 0;
        sh.shadow.color = "#223344";
        sh.shadow.blur = 6;
        sh.shadow.distance = 5;
        sh.shadow.angle = 45;
        sh.shadow.opacity = 0.5;
        sh.text.set_plain ("S%d".printf (k));
        sh.name = "Shape %d".printf (k);
        sh.description = "Alt text %d".printf (k);
        s2.elements.add (sh);
        k++;
    }
    var custom = new ShapeElement (ShapeKind.CUSTOM);
    custom.path.add (new PathCommand ('M', { 0, 0 }));
    custom.path.add (new PathCommand ('L', { 1, 0.25 }));
    custom.path.add (new PathCommand ('C', { 1, 1, 0.5, 1, 0.25, 0.75 }));
    custom.path.add (new PathCommand ('Q', { 0, 0.5, 0, 0 }));
    custom.path.add (new PathCommand ('Z', {}));
    custom.fill = new Fill.solid ("accent4");
    custom.set_geometry (700, 400, 120, 90);
    p.assign_ids (custom);
    s2.elements.add (custom);
    var line = Factory.shape (p, ShapeKind.LINE, 30, 480, 300, 40);
    line.flip_v = true;
    line.line.head = ArrowKind.OVAL;
    line.line.tail = ArrowKind.TRIANGLE;
    line.line.width = 3;
    line.line.color = "accent2";
    s2.elements.add (line);
    var line2 = Factory.shape (p, ShapeKind.LINE, 400, 480, 200, 0);
    line2.line.tail = ArrowKind.ARROW;
    line2.line.head = ArrowKind.DIAMOND;
    line2.line.dash = DashKind.DASH_DOT;
    s2.elements.add (line2);
    s2.transition.kind = TransitionKind.UNCOVER;
    s2.transition.direction = Direction.FROM_TOP;
    s2.transition.duration = 0.9;

    var s3 = Factory.add_slide (p, p.master.layout_of_kind (LayoutKind.TITLE_CONTENT), 2);
    ((ShapeElement) s3.elements[0]).text.set_plain ("Rich Text");
    var body = (ShapeElement) s3.elements[1];
    body.text.paragraphs.clear ();
    var p1 = new Paragraph ();
    var r1 = new TextRun ("Bold ");
    r1.bold = 1;
    r1.color = "accent2";
    var r2 = new TextRun ("italic");
    r2.italic = 1;
    r2.size = 31;
    r2.font = "Georgia";
    var r3 = new TextRun (" underlined strike");
    r3.underline = 1;
    r3.strike = 1;
    r3.highlight = "#ffff00";
    var r4 = new TextRun ("x2");
    r4.baseline = 1;
    var r5 = new TextRun ("link");
    r5.link = "https://example.org/a?b=1&c=2";
    p1.runs.add (r1);
    p1.runs.add (r2);
    p1.runs.add (r3);
    p1.runs.add (r4);
    p1.runs.add (r5);
    p1.align = TextAlign.JUSTIFY;
    p1.space_before = 12;
    p1.space_after = 6;
    p1.line_spacing = 1.2;
    body.text.paragraphs.add (p1);
    var p2 = new Paragraph ("Numbered level one");
    p2.bullet = BulletKind.NUMBER;
    p2.number_style = NumberStyle.ROMAN_UPPER;
    p2.number_start = 3;
    body.text.paragraphs.add (p2);
    var p3 = new Paragraph ("  leading spaces\tand tab\nand break");
    p3.level = 2;
    p3.bullet = BulletKind.CHAR;
    p3.bullet_char = "»";
    p3.bullet_color = "accent3";
    body.text.paragraphs.add (p3);
    var p4 = new Paragraph ("No bullet");
    p4.bullet = BulletKind.NONE;
    p4.align = TextAlign.RIGHT;
    p4.end_format.size = 40;
    body.text.paragraphs.add (p4);
    var p5 = new Paragraph ();
    p5.runs.add (Factory.field_run ("slidenum", "‹#›"));
    p5.runs.add (new TextRun (" of deck "));
    p5.runs.add (Factory.field_run ("datetime", "today"));
    body.text.paragraphs.add (p5);
    body.text.autofit = AutoFit.SHRINK;
    body.text.anchor = TextAnchor.MIDDLE;
    body.text.anchor_set = true;
    body.list_style = new TextStyle ();
    body.list_style.levels[0].size = 26;
    body.list_style.levels[0].color = "accent5";
    var tb = Factory.text_box (p, 600, 100, 300, "A text box that grows", 20);
    tb.text.inset_left = 10;
    tb.text.wrap = false;
    tb.rotation = 15;
    s3.elements.add (tb);
    s3.hidden = true;
    s3.transition.kind = TransitionKind.WIPE;
    s3.transition.direction = Direction.FROM_BOTTOM;
    s3.transition.advance_after = 2;
    s3.transition.on_click = true;

    var s4 = Factory.add_slide (p, p.master.layout_of_kind (LayoutKind.BLANK), 3);
    var img = new ImageElement (png, "image/png");
    img.set_geometry (50, 50, 300, 150);
    img.crop_left = 0.1;
    img.crop_top = 0.05;
    img.crop_right = 0.2;
    img.crop_bottom = 0.15;
    img.brightness = 0.2;
    img.contrast = -0.3;
    img.saturation = 0;
    img.opacity = 0.8;
    img.sepia = true;
    img.blur = 2;
    img.corner = 0.1;
    img.flip_h = true;
    img.line.color = "#000000";
    img.line.width = 2;
    img.shadow.enabled = true;
    p.assign_ids (img);
    s4.elements.add (img);
    var t = new TableElement (4, 3, 360, 36);
    t.set_geometry (420, 60, 360, 144);
    t.cells[0][0].text.set_plain ("Merged header");
    t.merge (0, 0, 0, 1);
    t.cells[1][0].text.set_plain ("Tall");
    t.merge (1, 0, 2, 0);
    t.cells[1][1].text.set_plain ("x");
    t.cells[3][2].text.set_plain ("Custom fill");
    t.cells[3][2].fill = "#abcdef";
    t.cells[3][2].anchor = TextAnchor.BOTTOM;
    t.first_col = true;
    t.style_color = "accent3";
    t.row_heights[3] = 50;
    t.sync_size ();
    p.assign_ids (t);
    s4.elements.add (t);
    var a = Factory.shape (p, ShapeKind.RECT, 100, 300, 50, 50);
    var b = Factory.shape (p, ShapeKind.ELLIPSE, 200, 320, 60, 60);
    var g = new GroupElement ();
    g.children.add (a);
    g.children.add (b);
    g.fit ();
    g.name = "Group";
    p.assign_ids (g);
    s4.elements.add (g);
    s4.transition.kind = TransitionKind.CIRCLE;
    s4.transition.duration = 2;

    var s5 = Factory.add_slide (p, p.master.layout_of_kind (LayoutKind.BLANK), 4);
    ChartKind[] kinds = { ChartKind.COLUMN, ChartKind.BAR, ChartKind.LINE, ChartKind.PIE, ChartKind.DOUGHNUT, ChartKind.AREA, ChartKind.SCATTER };
    for (int i = 0; i < kinds.length; i++) {
        var ch = new ChartElement (kinds[i]);
        ch.set_geometry (20 + (i % 4) * 230, 20 + (i / 4) * 260, 220, 240);
        ch.sample_data ();
        if (kinds[i] == ChartKind.SCATTER) {
            ch.categories.clear ();
            foreach (string c in new string[] { "1", "2.5", "4", "7" }) ch.categories.add (c);
        }
        ch.title = "Chart %d".printf (i);
        ch.grouping = (ChartGrouping) (i % 3);
        if (kinds[i].is_radial () || kinds[i] == ChartKind.SCATTER) ch.grouping = ChartGrouping.CLUSTERED;
        ch.legend = (LegendPosition) (i % 5);
        ch.data_labels = i % 2 == 0;
        ch.smooth = kinds[i] == ChartKind.LINE;
        if (ch.series.size > 1) ch.series[1].color = "#336699";
        ch.series[0].values[1] = 1234.5678;
        p.assign_ids (ch);
        s5.elements.add (ch);
    }
    s5.transition.kind = TransitionKind.PUSH;
    s5.transition.direction = Direction.FROM_LEFT;

    var s6 = Factory.add_slide (p, p.master.layout_of_kind (LayoutKind.BLANK), 5);
    AnimEffect[] entrance = { AnimEffect.APPEAR, AnimEffect.FADE, AnimEffect.FLY, AnimEffect.ZOOM, AnimEffect.WIPE, AnimEffect.FLOAT };
    int n = 0;
    foreach (var cls in new AnimClass[] { AnimClass.ENTRANCE, AnimClass.EXIT }) {
        foreach (var eff in entrance) {
            var sh = Factory.shape (p, ShapeKind.RECT, 20 + (n % 8) * 110, 20 + (n / 8) * 110, 90, 90);
            s6.elements.add (sh);
            var an = new Animation (sh.id);
            an.anim_class = cls;
            an.effect = eff;
            an.direction = (Direction) (n % 4);
            an.trigger = (AnimTrigger) (n % 3);
            an.duration = 0.25 + n * 0.1;
            an.delay = n % 2 == 0 ? 0 : 0.3;
            s6.animations.add (an);
            n++;
        }
    }
    foreach (var eff in AnimEffect.EMPHASIS) {
        var sh = Factory.shape (p, ShapeKind.ELLIPSE, 20 + (n % 8) * 110, 20 + (n / 8) * 110, 90, 90);
        s6.elements.add (sh);
        var an = new Animation (sh.id);
        an.anim_class = AnimClass.EMPHASIS;
        an.effect = eff;
        an.trigger = n % 2 == 0 ? AnimTrigger.AFTER_PREVIOUS : AnimTrigger.WITH_PREVIOUS;
        an.duration = 1;
        an.delay = 0.5;
        s6.animations.add (an);
        n++;
    }
    s6.transition.kind = TransitionKind.SPLIT;
    s6.show_master_shapes = false;
    var s7 = Factory.add_slide (p, p.master.layout_of_kind (LayoutKind.TITLE), 6);
    ((ShapeElement) s7.elements[0]).text.set_plain ("Kinds");
    s7.transition.kind = TransitionKind.ZOOM;
    var s8 = Factory.add_slide (p, p.master.layout_of_kind (LayoutKind.TITLE), 7);
    s8.transition.kind = TransitionKind.DISSOLVE;
    s8.name = "Named slide";
    var s9 = Factory.add_slide (p, p.master.layout_of_kind (LayoutKind.TITLE), 8);
    s9.transition.kind = TransitionKind.COVER;
    s9.transition.direction = Direction.FROM_RIGHT;
    return p;
}

void test_templates () throws Error {
    foreach (var t in Templates.all ()) {
        var p = Templates.build (t.id);
        p.properties.author = "A";
        p.properties.created = "2026-01-01T00:00:00Z";
        var back = read_bytes (write_pres (p));
        compare (p, back, true, "template " + t.id);
        var std = read_bytes (write_pres (p, false));
        compare (p, std, false, "standard template " + t.id);
        var again = read_bytes (write_pres (back));
        compare (back, again, true, "second pass " + t.id);
        string? dir = Environment.get_variable ("SLIDES_ODP_SAMPLES");
        if (dir != null) FileUtils.set_data (Path.build_filename (dir, t.id + ".odp"), write_pres (p));
    }
}

void test_synthetic () throws Error {
    var p = synthetic ();
    var data = write_pres (p);
    var back = read_bytes (data);
    compare (p, back, true, "synthetic");
    var std = read_bytes (write_pres (p, false));
    compare (p, std, false, "standard synthetic");
    var body = (ShapeElement) std.slides[2].elements[1];
    check (body.text.paragraphs[1].bullet == BulletKind.NUMBER && body.text.paragraphs[1].number_style == NumberStyle.ROMAN_UPPER && body.text.paragraphs[1].number_start == 3, "standard numbering");
    check (body.text.paragraphs[2].bullet == BulletKind.CHAR && body.text.paragraphs[2].bullet_char == "»" && body.text.paragraphs[2].level == 2, "standard bullet level");
    check (body.text.paragraphs[0].runs[0].bold == 1 && body.text.paragraphs[0].runs[1].italic == 1 && near (body.text.paragraphs[0].runs[1].size, 31, 0.01), "standard run format");
    check (body.text.paragraphs[0].runs[1].font == "Georgia", "standard font");
    check (body.text.paragraphs[0].align == TextAlign.JUSTIFY && near (body.text.paragraphs[0].line_spacing, 1.2, 0.001), "standard paragraph");
    check (body.text.autofit == AutoFit.SHRINK && body.text.anchor == TextAnchor.MIDDLE, "standard body props");
    bool link = false, field = false;
    foreach (var par in body.text.paragraphs) foreach (var r in par.runs) {
        if (r.link == "https://example.org/a?b=1&c=2") link = true;
        if (r.field == "slidenum") field = true;
    }
    check (link && field, "standard link and field");
    check (std.loop && !std.use_timings && std.footer_text == p.footer_text, "standard settings");
    check (std.properties.title == "Synthetic" && std.properties.author == "Test Author", "standard metadata");
}

string entry_name (uint8[] d, int offset, out int method, out int next) {
    method = d[offset + 8] | (d[offset + 9] << 8);
    int csize = (int) (d[offset + 18] | (d[offset + 19] << 8) | (d[offset + 20] << 16) | (d[offset + 21] << 24));
    int nlen = d[offset + 26] | (d[offset + 27] << 8);
    int elen = d[offset + 28] | (d[offset + 29] << 8);
    var sb = new StringBuilder ();
    for (int i = 0; i < nlen; i++) sb.append_c ((char) d[offset + 30 + i]);
    next = offset + 30 + nlen + elen + csize;
    return sb.str;
}

void collect_hrefs (Xml.Node* n, Gee.List<string> out_list) {
    for (Xml.Attr* a = n->properties; a != null; a = a->next) {
        if (a->name == "href" && a->children != null) out_list.add (a->children->content);
    }
    for (Xml.Node* c = n->children; c != null; c = c->next) if (c->type == Xml.ElementType.ELEMENT_NODE) collect_hrefs (c, out_list);
}

void test_structure () throws Error {
    var p = synthetic ();
    var data = write_pres (p);
    int method, next;
    check (entry_name (data, 0, out method, out next) == "mimetype" && method == 0, "mimetype first and stored");
    var zip = new ZipReader (data);
    check (zip.read_text ("mimetype") == Odf.MIME, "mimetype content");
    string mtext = zip.read_text ("META-INF/manifest.xml");
    Xml.Doc* manifest = Xml.Parser.read_memory (mtext, mtext.length);
    check (manifest != null, "manifest parses");
    var listed = new Gee.HashSet<string> ();
    for (Xml.Node* n = manifest->get_root_element ()->children; n != null; n = n->next) {
        if (n->type != Xml.ElementType.ELEMENT_NODE) continue;
        listed.add (OdpReader.a (n, "manifest:full-path"));
        check (OdpReader.a (n, "manifest:media-type") != null, "manifest media type");
    }
    delete manifest;
    foreach (string name in zip.names ()) {
        if (name == "mimetype" || name == "META-INF/manifest.xml") continue;
        check (listed.contains (name), "manifest lists " + name);
        if (name.has_suffix (".xml")) {
            string text = zip.read_text (name);
            Xml.Doc* doc = Xml.Parser.read_memory (text, text.length, null, null, Xml.ParserOption.NONET);
            check (doc != null && doc->get_root_element () != null, name + " parses");
            var hrefs = new Gee.ArrayList<string> ();
            collect_hrefs (doc->get_root_element (), hrefs);
            foreach (string h in hrefs) {
                if (h.has_prefix ("http")) continue;
                string path = h.has_prefix ("./") ? h.substring (2) : h;
                check (zip.has (path) || zip.has (path + "/content.xml"), "href target " + h);
            }
            delete doc;
        }
    }
    foreach (string entry in listed) {
        if (entry == "/" || entry.has_suffix ("/")) continue;
        check (zip.has (entry), "listed part exists " + entry);
    }
    check (zip.has ("Pictures/image1.png") && zip.has ("Object 1/content.xml") && zip.has ("Object 7/content.xml"), "media and chart objects");
}

void add_dir (ZipWriter zip, string root, string rel) throws Error {
    var dir = Dir.open (Path.build_filename (root, rel));
    string? name;
    var names = new Gee.ArrayList<string> ();
    while ((name = dir.read_name ()) != null) names.add (name);
    names.sort ();
    foreach (string n in names) {
        string r = rel == "" ? n : rel + "/" + n;
        if (r == "mimetype") continue;
        string full = Path.build_filename (root, r);
        if (FileUtils.test (full, FileTest.IS_DIR)) {
            add_dir (zip, root, r);
            continue;
        }
        uint8[] data;
        FileUtils.get_data (full, out data);
        zip.add (r, data);
    }
}

uint8[] zip_fixture (string name) throws Error {
    string root = Path.build_filename ("fixtures", name);
    var zip = new ZipWriter ();
    uint8[] mt;
    FileUtils.get_data (Path.build_filename (root, "mimetype"), out mt);
    zip.add ("mimetype", mt, false);
    add_dir (zip, root, "");
    return zip.finish ();
}

void test_impress_fixture () throws Error {
    var p = read_bytes (zip_fixture ("odp-impress"));
    check (near (p.width, 28 * Odf.PT_PER_CM, 0.01) && near (p.height, 15.75 * Odf.PT_PER_CM, 0.01), "fixture page size");
    check (p.masters.size == 2, "fixture masters %d".printf (p.masters.size));
    check (p.masters[0].name == "Blue Lines" && p.masters[1].name == "Plain", "fixture master names");
    var m0 = p.masters[0];
    check (m0.find_placeholder (PlaceholderKind.TITLE) != null && m0.find_placeholder (PlaceholderKind.BODY) != null, "fixture master placeholders");
    check (near (m0.title_style.levels[0].size, 40, 0.01) && m0.title_style.levels[0].color == "#1f3864", "fixture master title style");
    check (near (m0.body_style.levels[0].size, 28, 0.01) && near (m0.body_style.levels[1].size, 24, 0.01), "fixture outline levels");
    check (m0.body_style.levels[1].bullet == BulletKind.CHAR && m0.body_style.levels[1].bullet_char == "-", "fixture outline bullets");
    check (m0.background.kind == FillKind.GRADIENT, "fixture master gradient background");
    bool deco = false;
    foreach (var e in m0.elements) if (e.placeholder == PlaceholderKind.NONE && e.kind == ElementKind.SHAPE) deco = true;
    check (deco, "fixture master decoration");
    check (p.slides.size == 3, "fixture slide count");
    var s1 = p.slides[0];
    check (s1.title () == "Quarterly Results", "fixture title");
    check (p.layout_for (s1) == p.masters[0].layouts[0], "fixture slide 1 master");
    check (p.layout_for (p.slides[2]) == p.masters[1].layouts[0], "fixture slide 3 master");
    var sub = s1.placeholder (PlaceholderKind.SUBTITLE);
    check (sub != null && sub.text_body ().plain_text () == "Prepared for the board", "fixture subtitle");
    check (s1.transition.kind == TransitionKind.PUSH && s1.transition.direction == Direction.FROM_LEFT && near (s1.transition.duration, 1.5, 0.001), "fixture transition");
    var s2 = p.slides[1];
    var outline = s2.placeholder (PlaceholderKind.OBJECT) as ShapeElement;
    check (outline != null && outline.text.paragraphs.size == 3, "fixture outline paragraphs");
    check (outline.text.paragraphs[1].level == 1 && outline.text.paragraphs[1].text () == "Sub point with   spaces", "fixture nested list '%s'".printf (outline.text.paragraphs[1].text ()));
    check (outline.text.paragraphs[0].runs.size >= 2 && outline.text.paragraphs[0].runs[1].bold == 1 && outline.text.paragraphs[0].runs[1].color == "#c00000", "fixture span parent style");
    ShapeElement? star = null;
    foreach (var e in s2.elements) {
        var sh = e as ShapeElement;
        if (sh != null && sh.shape == ShapeKind.STAR5) star = sh;
    }
    check (star != null && star.fill.kind == FillKind.SOLID && star.fill.color == "#ffc000", "fixture custom shape fill from parent style");
    check (near (star.rotation, 30, 0.01), "fixture rotation %g".printf (star.rotation));
    check (star.line.visible () && near (star.line.width, 0.1 * Odf.PT_PER_CM, 0.01), "fixture stroke");
    check (star.shadow.enabled, "fixture shadow");
    GroupElement? group = null;
    foreach (var e in s2.elements) if (e is GroupElement) group = (GroupElement) e;
    check (group != null && group.children.size == 2 && group.children[1].kind == ElementKind.SHAPE && ((ShapeElement) group.children[1]).shape == ShapeKind.ELLIPSE, "fixture group");
    check (s2.notes == "Mention the new office.\nThank the team.", "fixture notes");
    check (s2.animations.size == 2, "fixture animation count %d".printf (s2.animations.size));
    check (s2.animations[0].effect == AnimEffect.FLY && s2.animations[0].direction == Direction.FROM_LEFT && s2.animations[0].trigger == AnimTrigger.ON_CLICK && near (s2.animations[0].duration, 0.5, 0.001), "fixture fly-in");
    check (s2.animations[1].effect == AnimEffect.FADE && s2.animations[1].trigger == AnimTrigger.AFTER_PREVIOUS && near (s2.animations[1].duration, 1, 0.001) && near (s2.animations[1].delay, 0.25, 0.001), "fixture fade after previous");
    check (s2.find (s2.animations[0].target) == star, "fixture animation target");
    var s3 = p.slides[2];
    TableElement? table = null;
    ChartElement? chart = null;
    foreach (var e in s3.elements) {
        if (e is TableElement) table = (TableElement) e;
        if (e is ChartElement) chart = (ChartElement) e;
    }
    check (table != null && table.rows == 3 && table.cols == 3, "fixture table size");
    check (table.cells[0][0].col_span == 2 && table.cells[0][1].covered, "fixture covered cell");
    check (table.cells[1][2].text.plain_text () == "42" && table.cells[0][0].fill == "#4472c4", "fixture table cells");
    check (near (table.col_widths[0], 4 * Odf.PT_PER_CM, 0.01), "fixture column width");
    check (chart != null && chart.chart == ChartKind.BAR && chart.grouping == ChartGrouping.STACKED, "fixture chart kind");
    check (chart.categories.size == 3 && chart.categories[2] == "Mar", "fixture chart categories");
    check (chart.series.size == 2 && chart.series[1].name == "Costs" && near (chart.series[1].value_at (2), 7.5, 1e-9), "fixture chart series");
    check (chart.title == "Revenue" && chart.legend == LegendPosition.RIGHT, "fixture chart title and legend");
    check (s3.hidden, "fixture hidden slide");
    check (s3.transition.kind == TransitionKind.FADE, "fixture fade transition");
    check (p.properties.title == "Board Meeting" && p.properties.author == "Jane Doe", "fixture meta");
    var ex = new Exporter (p);
    foreach (var s in p.slides) ex.render (s, 320);
    var rewritten = read_bytes (write_pres (p));
    compare (p, rewritten, true, "fixture rewrite");
}

void test_errors () {
    bool failed = false;
    try {
        var zip = new ZipWriter ();
        zip.add ("mimetype", Odf.MIME.data, false);
        read_bytes (zip.finish ());
    } catch (Error e) {
        failed = true;
    }
    check (failed, "missing content fails");
    failed = false;
    try {
        var zip = new ZipWriter ();
        zip.add ("mimetype", Odf.MIME.data, false);
        zip.add_text ("content.xml", "<not closed");
        read_bytes (zip.finish ());
    } catch (Error e) {
        failed = true;
    }
    check (failed, "malformed content fails");
    try {
        var zip = new ZipWriter ();
        zip.add ("mimetype", Odf.MIME.data, false);
        zip.add_text ("content.xml", "<?xml version=\"1.0\"?><office:document-content xmlns:office=\"%s\" xmlns:draw=\"%s\"><office:body><office:presentation><draw:page/></office:presentation></office:body></office:document-content>".printf (Odf.NS_OFFICE, Odf.NS_DRAW));
        var p = read_bytes (zip.finish ());
        check (p.slides.size == 1 && p.masters.size == 1, "minimal document without styles");
    } catch (Error e) {
        check (false, "minimal document: " + e.message);
    }
}

void test_units () {
    check (near (Odf.length ("2.54cm"), 72, 1e-9) && near (Odf.length ("10mm"), 72 / 2.54, 1e-9) && near (Odf.length ("1in"), 72, 1e-9), "lengths");
    check (near (Odf.length ("12pt"), 12, 1e-9) && near (Odf.length ("16px"), 12, 1e-9) && near (Odf.length ("1pc"), 12, 1e-9), "more lengths");
    check (near (Odf.seconds ("PT00H00M05.5S", 0), 5.5, 1e-9) && near (Odf.seconds ("0.25s", 0), 0.25, 1e-9) && near (Odf.seconds ("750ms", 0), 0.75, 1e-9), "durations");
    check (Odf.cm (72) == "2.54cm", "cm output");
    Intl.setlocale (LocaleCategory.NUMERIC, "it_IT.UTF-8");
    check (Odf.cm (36) == "1.27cm" && Odf.fixed (0.5, 2) == "0.5", "locale independent output");
    Intl.setlocale (LocaleCategory.NUMERIC, "C.UTF-8");
}

void main () {
    Intl.setlocale (LocaleCategory.ALL, "C.UTF-8");
    int passed = 0;
    int total = 6;
    try {
        test_units ();
        passed++;
        test_templates ();
        passed++;
        test_synthetic ();
        passed++;
        test_structure ();
        passed++;
        test_impress_fixture ();
        passed++;
        test_errors ();
        passed++;
    } catch (Error e) {
        error ("%s", e.message);
    }
    print ("odp tests passed %d/%d (%d checks)\n", passed, total, checks);
}
