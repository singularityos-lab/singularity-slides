using Singularity.Apps.Slides;

string tmp_path (string name) {
    return Path.build_filename (Environment.get_tmp_dir (), "slides-render-%d-%s".printf (Random.int_range (0, 1000000), name));
}

int distinct_colors (Cairo.ImageSurface surf) {
    surf.flush ();
    unowned uint8[] data = surf.get_data ();
    var seen = new Gee.HashSet<uint> ();
    int stride = surf.get_stride ();
    for (int y = 0; y < surf.get_height (); y += 3) {
        for (int x = 0; x < surf.get_width (); x += 3) {
            int i = y * stride + x * 4;
            seen.add ((uint) data[i] | ((uint) data[i + 1] << 8) | ((uint) data[i + 2] << 16));
            if (seen.size > 64) return seen.size;
        }
    }
    return seen.size;
}

Rgba pixel (Cairo.ImageSurface surf, int x, int y) {
    surf.flush ();
    unowned uint8[] d = surf.get_data ();
    int i = y * surf.get_stride () + x * 4;
    return Rgba (d[i + 2] / 255.0, d[i + 1] / 255.0, d[i] / 255.0, d[i + 3] / 255.0);
}

void test_templates_render () {
    foreach (var t in Templates.all ()) {
        var p = Templates.build (t.id);
        var ex = new Exporter (p);
        foreach (var s in p.slides) {
            var surf = ex.render (s, 480);
            assert (surf.get_width () == 480 && surf.get_height () == 270);
            if (t.id != "blank") assert (distinct_colors (surf) > 3);
        }
    }
}

void test_shapes_render () {
    var p = Factory.new_presentation (ThemePreset.find ("clean"));
    var s = p.slides[0];
    s.elements.clear ();
    s.background = new Fill.solid ("#ffffff");
    for (int k = 0; k < ShapeKind.CUSTOM; k++) {
        var sh = Factory.shape (p, (ShapeKind) k, 10 + (k % 9) * 100, 10 + (k / 9) * 160, 80, 80);
        sh.fill = new Fill.solid ("#ff0000");
        sh.line.color = "#000000";
        sh.line.width = 2;
        sh.shadow.enabled = k % 2 == 0;
        s.elements.add (sh);
    }
    var ex = new Exporter (p);
    var surf = ex.render (s, 960);
    var c = pixel (surf, 50, 50);
    assert (c.r > 0.9 && c.g < 0.1 && c.b < 0.1);
    var bg = pixel (surf, 5, 530);
    assert (bg.r > 0.9 && bg.g > 0.9);
    var custom = new ShapeElement (ShapeKind.CUSTOM);
    custom.path.add (new PathCommand ('M', { 0, 0 }));
    custom.path.add (new PathCommand ('L', { 1, 0 }));
    custom.path.add (new PathCommand ('L', { 0.5, 1 }));
    custom.path.add (new PathCommand ('Z', {}));
    custom.fill = new Fill.solid ("#0000ff");
    custom.set_geometry (400, 400, 100, 100);
    s.elements.clear ();
    s.elements.add (custom);
    surf = ex.render (s, 960);
    var blue = pixel (surf, 450, 420);
    assert (blue.b > 0.9 && blue.r < 0.1);
    var white = pixel (surf, 405, 495);
    assert (white.b > 0.9 && white.r > 0.9);
}

void test_text_and_autofit () {
    var p = Factory.new_presentation (ThemePreset.find ("clean"));
    var s = p.slides[0];
    var title = (ShapeElement) s.placeholder (PlaceholderKind.CENTER_TITLE);
    title.text.set_plain ("A very long title that keeps going and going so that it needs to shrink to fit the box that holds it");
    title.text.autofit = AutoFit.SHRINK;
    var ex = new Exporter (p);
    ex.render (s, 960);
    assert (title.text.font_scale < 1);
    var r = new Renderer ();
    var ctx = new RenderContext (p, s, p.layout_for (s), p.master);
    var tb = Factory.text_box (p, 10, 10, 200, "one\ntwo\nthree\nfour");
    double h4 = r.text_height (ctx, tb, tb.text, 200);
    tb.text.set_plain ("one");
    double h1 = r.text_height (ctx, tb, tb.text, 200);
    assert (h4 > h1 * 3);
    var body = new TextBody ();
    for (int i = 0; i < 3; i++) {
        var par = new Paragraph ("item %d".printf (i));
        par.bullet = BulletKind.NUMBER;
        body.paragraphs.add (par);
    }
    var layout = r.layout_text (ctx, tb, body, 300, "", 1);
    assert (layout.paras[0].bullet == "1." && layout.paras[2].bullet == "3.");
}

void test_image_filters () throws Error {
    var src = new Cairo.ImageSurface (Cairo.Format.ARGB32, 20, 20);
    var cr = new Cairo.Context (src);
    cr.set_source_rgb (1, 0, 0);
    cr.paint ();
    var gray = ImageCache.apply_filters (src, 0, 0, 0, false, 0);
    var g = pixel (gray, 5, 5);
    assert (Math.fabs (g.r - g.g) < 0.02 && Math.fabs (g.g - g.b) < 0.02);
    var bright = ImageCache.apply_filters (src, 0.5, 0, 1, false, 0);
    var b = pixel (bright, 5, 5);
    assert (b.g > 0.4);
    var png = tmp_path ("img.png");
    src.write_to_png (png);
    uint8[] data;
    FileUtils.get_data (png, out data);
    FileUtils.remove (png);
    var bytes = new Bytes (data);
    int w, h;
    assert (ImageCache.size_of (bytes, out w, out h) && w == 20 && h == 20);
    var p = Factory.new_presentation (ThemePreset.find ("clean"));
    var img = new ImageElement (bytes, "image/png");
    img.set_geometry (0, 0, 960, 540);
    img.crop_left = 0.5;
    img.saturation = 0;
    p.slides[0].elements.add (img);
    var out_surf = new Exporter (p).render (p.slides[0], 96);
    var px = pixel (out_surf, 40, 20);
    assert (Math.fabs (px.r - px.g) < 0.05);
}

void test_pdf_png_export () throws Error {
    var p = Templates.build ("status");
    var ex = new Exporter (p);
    string pdf = tmp_path ("deck.pdf");
    ex.export_pdf (pdf);
    uint8[] data;
    FileUtils.get_data (pdf, out data);
    string head = ((string) data).substring (0, 5);
    assert (head == "%PDF-");
    int pages = 0;
    string text = (string) data;
    int pos = 0;
    while ((pos = text.index_of ("/Type /Page\n", pos)) >= 0 || (pos = text.index_of ("/Type /Page ", pos)) >= 0) {
        pages++;
        pos++;
    }
    FileUtils.remove (pdf);
    foreach (var layout in new PdfLayout[] { PdfLayout.NOTES, PdfLayout.HANDOUT_3, PdfLayout.HANDOUT_6 }) {
        string f = tmp_path ("handout.pdf");
        ex.export_pdf (f, layout);
        assert (FileUtils.test (f, FileTest.EXISTS));
        FileUtils.remove (f);
    }
    string png = tmp_path ("slide.png");
    ex.export_image (p.slides[0], png, 640);
    var loaded = new Cairo.ImageSurface.from_png (png);
    assert (loaded.get_width () == 640 && loaded.get_height () == 360);
    FileUtils.remove (png);
    string jpg = tmp_path ("slide.jpg");
    ex.export_image (p.slides[1], jpg, 320);
    assert (FileUtils.test (jpg, FileTest.EXISTS));
    FileUtils.remove (jpg);
    string svg = tmp_path ("slide.svg");
    ex.export_svg (p.slides[0], svg);
    string svg_text;
    FileUtils.get_contents (svg, out svg_text);
    assert (svg_text.contains ("<svg"));
    FileUtils.remove (svg);
}

void test_transitions () {
    var a = new Cairo.ImageSurface (Cairo.Format.ARGB32, 100, 50);
    var ca = new Cairo.Context (a);
    ca.set_source_rgb (1, 0, 0);
    ca.paint ();
    var b = new Cairo.ImageSurface (Cairo.Format.ARGB32, 100, 50);
    var cb = new Cairo.Context (b);
    cb.set_source_rgb (0, 0, 1);
    cb.paint ();
    foreach (var k in TransitionKind.ALL) {
        var out_s = new Cairo.ImageSurface (Cairo.Format.ARGB32, 100, 50);
        var cr = new Cairo.Context (out_s);
        Transitions.draw (cr, k, Direction.FROM_RIGHT, 1, a, b, 100, 50);
        var end = pixel (out_s, 50, 25);
        assert (end.b > 0.9 && end.r < 0.1);
        cr = new Cairo.Context (out_s);
        Transitions.draw (cr, k, Direction.FROM_RIGHT, 0, a, b, 100, 50);
        var start = pixel (out_s, 10, 25);
        if (k != TransitionKind.NONE && k != TransitionKind.CUT && !(start.r > 0.9 || k == TransitionKind.FADE_BLACK)) error ("transition %s shows the next slide at start", k.label ());
    }
    var mid = new Cairo.ImageSurface (Cairo.Format.ARGB32, 100, 50);
    var cm = new Cairo.Context (mid);
    Transitions.draw (cm, TransitionKind.PUSH, Direction.FROM_RIGHT, 0.5, a, b, 100, 50);
    assert (pixel (mid, 10, 25).r > 0.9 && pixel (mid, 90, 25).b > 0.9);
}

void test_chart_kind_changes () {
    var p = Factory.new_presentation (ThemePreset.find ("clean"));
    var s = p.slides[0];
    s.elements.clear ();
    var ex = new Exporter (p);
    for (int from = 0; from <= ChartKind.SCATTER; from++) {
        for (int to = 0; to <= ChartKind.SCATTER; to++) {
            for (int g = 0; g <= ChartGrouping.PERCENT; g++) {
                for (int lg = 0; lg <= LegendPosition.LEFT; lg++) {
                    var ch = new ChartElement ((ChartKind) from);
                    ch.sample_data ();
                    ch.x = 60; ch.y = 60; ch.w = 600; ch.h = 400;
                    ch.grouping = (ChartGrouping) g;
                    ch.legend = (LegendPosition) lg;
                    ch.data_labels = true;
                    s.elements.clear ();
                    s.elements.add (ch);
                    ex.render (s, 480);
                    ch.chart = (ChartKind) to;
                    ex.render (s, 480);
                    ch.smooth = true;
                    ex.render (s, 480);
                }
            }
        }
    }
}

void main () {
    Intl.setlocale (LocaleCategory.ALL, "C.UTF-8");
    test_templates_render ();
    test_shapes_render ();
    test_text_and_autofit ();
    try {
        test_image_filters ();
        test_pdf_png_export ();
    } catch (Error e) {
        error ("%s", e.message);
    }
    test_transitions ();
    test_chart_kind_changes ();
    print ("render tests passed\n");
}
