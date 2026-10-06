using Singularity.Apps.Slides;

void test_colors () {
    var t = new Theme ();
    t.colors["accent1"] = "#336699";
    var c = t.resolve ("accent1");
    assert (c.to_hex () == "#336699");
    assert (t.resolve ("#ff0000").to_hex () == "#ff0000");
    assert (t.resolve ("tx1").to_hex () == t.resolve ("dk1").to_hex ());
    var half = t.resolve ("#ff0000@0.5");
    assert (Math.fabs (half.a - 0.5) < 0.001);
    var tint = t.resolve ("accent1~0.2+0.8");
    assert (tint.luminance () > c.luminance ());
    var spec = ColorSpec.parse ("accent2~0.75+0.25@0.4");
    assert (spec.base_name == "accent2");
    assert (Math.fabs (spec.lum_mod - 0.75) < 1e-9 && Math.fabs (spec.lum_off - 0.25) < 1e-9 && Math.fabs (spec.alpha - 0.4) < 1e-9);
    assert (ColorSpec.parse (spec.to_string ()).to_string () == spec.to_string ());
    assert (ColorSpec.with_alpha ("#112233", 0.5) == "#112233@0.5");
    Rgba parsed;
    assert (Rgba.parse_hex ("#abc", out parsed) && parsed.to_hex () == "#aabbcc");
    assert (!Rgba.parse_hex ("#zzz", out parsed));
    double h, s, l;
    c.to_hsl (out h, out s, out l);
    assert (Rgba.from_hsl (h, s, l).to_hex () == "#336699");
    assert (t.resolve_font ("+mj-lt") == t.major_font);
}

void test_text () {
    var body = new TextBody.with_text ("Hello world\nSecond line");
    assert (body.paragraphs.size == 2);
    assert (body.plain_text () == "Hello world\nSecond line");
    int n = body.replace_all ("line", "row", true);
    assert (n == 1 && body.plain_text () == "Hello world\nSecond row");
    n = body.replace_all ("HELLO", "Bye", false);
    assert (n == 1 && body.paragraphs[0].text () == "Bye world");
    var p = new Paragraph ();
    var r1 = new TextRun ("a");
    r1.bold = 1;
    var r2 = new TextRun ("b");
    r2.bold = 1;
    var r3 = new TextRun ("c");
    p.runs.add (r1);
    p.runs.add (r2);
    p.runs.add (r3);
    p.normalize ();
    assert (p.runs.size == 2 && p.runs[0].text == "ab" && p.runs[1].text == "c");
    var copy = body.clone ();
    copy.paragraphs[0].runs[0].text = "changed";
    assert (body.paragraphs[0].runs[0].text == "Bye world");
    assert (NumberStyle.ROMAN_UPPER.label (4) == "IV.");
    assert (NumberStyle.ALPHA_LOWER.label (2) == "b.");
    assert (NumberStyle.from_ooxml (NumberStyle.ARABIC_PAREN.to_ooxml ()) == NumberStyle.ARABIC_PAREN);
}

void test_factory () {
    foreach (var preset in ThemePreset.all ()) {
        var p = Factory.new_presentation (preset);
        assert (p.masters.size == 1);
        assert (p.master.layouts.size >= 10);
        assert (p.slides.size == 1);
        var title = p.slides[0].placeholder (PlaceholderKind.CENTER_TITLE);
        assert (title != null);
        assert (p.layout_for (p.slides[0]).kind == LayoutKind.TITLE);
    }
    var p = Factory.new_presentation (ThemePreset.find ("clean"));
    var s = Factory.add_slide (p, p.master.layout_of_kind (LayoutKind.TWO_CONTENT), 1);
    assert (p.slides.size == 2 && p.slides[1] == s);
    int objects = 0;
    foreach (var e in s.elements) if (e.placeholder == PlaceholderKind.OBJECT) objects++;
    assert (objects == 2);
    var ids = new Gee.HashSet<int> ();
    foreach (var sl in p.slides) foreach (var e in sl.elements) {
        assert (!ids.contains (e.id));
        ids.add (e.id);
    }
    ((ShapeElement) s.placeholder (PlaceholderKind.TITLE)).text.set_plain ("Kept");
    ((ShapeElement) s.elements[1]).text.set_plain ("Left");
    ((ShapeElement) s.elements[2]).text.set_plain ("Right");
    Factory.apply_layout (p, s, p.master.layout_of_kind (LayoutKind.TITLE_CONTENT));
    assert (s.title () == "Kept");
    bool found_right = false;
    foreach (var e in s.elements) if (e.text_body () != null && e.text_body ().plain_text () == "Right") found_right = true;
    assert (found_right);
    var body = p.layout_for (s).find_placeholder (PlaceholderKind.OBJECT, 1);
    assert (body != null);
    var ls = p.level_style (s, p.layout_for (s), p.master, s.elements[1], 0);
    assert (ls.size > 0 && ls.bullet == BulletKind.CHAR);
    var title_ls = p.level_style (p.slides[0], p.layout_for (p.slides[0]), p.master, p.slides[0].elements[0], 0);
    assert (title_ls.align == TextAlign.CENTER);
    assert (title_ls.size >= 50);
}

void test_inheritance () {
    var p = Factory.new_presentation (ThemePreset.find ("clean"));
    var s = Factory.add_slide (p, p.master.layout_of_kind (LayoutKind.TITLE_CONTENT), 1);
    var title = s.placeholder (PlaceholderKind.TITLE);
    var master_title = p.master.find_placeholder (PlaceholderKind.TITLE);
    assert (title.inherit_geometry);
    master_title.y = 12;
    Factory.refresh_inherited (p);
    assert (title.y == 12);
    title.inherit_geometry = false;
    title.y = 99;
    master_title.y = 40;
    Factory.refresh_inherited (p);
    assert (title.y == 99);
    var bg = p.background_for (s);
    assert (bg.kind == FillKind.SOLID);
    s.background = new Fill.solid ("#123456");
    assert (p.background_for (s).color == "#123456");
    Factory.apply_theme (p, ThemePreset.find ("midnight"));
    assert (p.theme.id == "midnight");
    assert (p.master.title_style.levels[0].color == "lt1");
}

void test_undo () {
    var d = new Document (Factory.new_presentation (ThemePreset.find ("clean")));
    int changes = 0;
    d.changed.connect (() => changes++);
    assert (!d.can_undo);
    d.edit ("Add Slide", () => Factory.add_slide (d.pres, d.pres.master.layouts[1], 1));
    assert (d.pres.slides.size == 2 && d.can_undo && d.modified);
    assert (d.undo_label == "Add Slide");
    d.edit ("Add Slide", () => Factory.add_slide (d.pres, d.pres.master.layouts[1], 2));
    assert (d.pres.slides.size == 3);
    d.undo ();
    assert (d.pres.slides.size == 2);
    d.undo ();
    assert (d.pres.slides.size == 1 && !d.can_undo && d.can_redo);
    d.redo ();
    assert (d.pres.slides.size == 2);
    d.edit ("Move", () => d.pres.slides[0].elements[0].x += 5, "move");
    d.edit ("Move", () => d.pres.slides[0].elements[0].x += 5, "move");
    double moved = d.pres.slides[0].elements[0].x;
    d.undo ();
    assert (d.pres.slides[0].elements[0].x == moved - 10);
    assert (changes >= 5);
}

void test_table () {
    var t = new TableElement (3, 3, 300, 30);
    assert (t.rows == 3 && t.cols == 3 && t.w == 300 && t.h == 90);
    t.insert_row (1);
    assert (t.rows == 4 && t.h == 120);
    t.insert_col (3);
    assert (t.cols == 4);
    t.cells[0][0].text.set_plain ("A");
    t.cells[0][1].text.set_plain ("B");
    t.merge (0, 0, 1, 1);
    assert (t.cells[0][0].col_span == 2 && t.cells[0][0].row_span == 2 && t.cells[1][1].covered);
    assert (t.cells[0][0].text.plain_text () == "A\nB");
    int r, c;
    t.x = 0;
    t.y = 0;
    assert (t.cell_at (80, 40, out r, out c) && r == 0 && c == 0);
    t.split (0, 0);
    assert (!t.cells[1][1].covered);
    t.delete_row (0);
    t.delete_col (0);
    assert (t.rows == 3 && t.cols == 3);
    var copy = (TableElement) t.clone ();
    copy.cells[0][0].text.set_plain ("X");
    assert (t.cells[0][0].text.plain_text () != "X");
    t.scale_into (0, 0, t.w * 2, t.h);
    assert (Math.fabs (t.col_widths[0] - 200) < 0.01);
}

void test_group () {
    var p = Factory.new_presentation (ThemePreset.find ("clean"));
    var a = Factory.shape (p, ShapeKind.RECT, 10, 10, 50, 50);
    var b = Factory.shape (p, ShapeKind.ELLIPSE, 100, 40, 20, 80);
    var g = new GroupElement ();
    g.children.add (a);
    g.children.add (b);
    g.fit ();
    assert (g.x == 10 && g.y == 10 && g.w == 110 && g.h == 110);
    g.move_by (5, 5);
    assert (a.x == 15 && b.y == 45);
    g.scale_into (15, 15, 220, 110);
    assert (Math.fabs (b.x - 195) < 0.01 && Math.fabs (b.w - 40) < 0.01);
    var s = p.slides[0];
    p.assign_ids (g);
    s.elements.add (g);
    assert (s.find (b.id) == b);
    var r = Factory.shape (p, ShapeKind.RECT, 0, 0, 100, 50);
    r.rotation = 90;
    double bx, by, bw, bh;
    r.bounds (out bx, out by, out bw, out bh);
    assert (Math.fabs (bw - 50) < 0.01 && Math.fabs (bh - 100) < 0.01);
    assert (r.contains (50, -20) && !r.contains (5, 5));
}

void test_player () {
    var p = Factory.new_presentation (ThemePreset.find ("clean"));
    var s = p.slides[0];
    var a = Factory.shape (p, ShapeKind.RECT, 10, 10, 50, 50);
    var b = Factory.shape (p, ShapeKind.RECT, 100, 10, 50, 50);
    var c = Factory.shape (p, ShapeKind.RECT, 200, 10, 50, 50);
    s.elements.add (a);
    s.elements.add (b);
    s.elements.add (c);
    var an1 = new Animation (a.id);
    an1.effect = AnimEffect.FADE;
    an1.duration = 1;
    var an2 = new Animation (b.id);
    an2.effect = AnimEffect.FLY;
    an2.trigger = AnimTrigger.AFTER_PREVIOUS;
    an2.duration = 0.5;
    var an3 = new Animation (c.id);
    an3.effect = AnimEffect.ZOOM;
    an3.anim_class = AnimClass.EXIT;
    an3.trigger = AnimTrigger.ON_CLICK;
    s.animations.add (an1);
    s.animations.add (an2);
    s.animations.add (an3);
    var pl = new Player (p, s);
    assert (pl.step_count == 2 && !pl.auto_first);
    assert (Math.fabs (pl.step_length (0) - 1.5) < 1e-9);
    var init = pl.initial_states ();
    assert (!init[a.id].visible && !init[b.id].visible && init[c.id].visible);
    var mid = pl.states_at (0, 0.5);
    assert (mid[a.id].visible && mid[a.id].opacity > 0 && mid[a.id].opacity < 1);
    assert (!mid[b.id].visible);
    var fly = pl.states_at (0, 1.25);
    assert (fly[b.id].visible && fly[b.id].dy > 0);
    var done = pl.states_at (0, 2);
    assert (done[b.id].dy == 0 && done[a.id].opacity == 1);
    var fin = pl.final_states ();
    assert (!fin[c.id].visible && fin[a.id].visible);
    s.animations[0].trigger = AnimTrigger.WITH_PREVIOUS;
    var pl2 = new Player (p, s);
    assert (pl2.auto_first);
}

void test_templates () {
    foreach (var t in Templates.all ()) {
        var p = Templates.build (t.id);
        assert (p.slides.size >= 1);
        assert (p.theme.id == t.theme);
        var clone = p.clone ();
        assert (clone.slides.size == p.slides.size);
        assert (clone.slides[0].elements.size == p.slides[0].elements.size);
        foreach (var s in p.slides) foreach (var a in s.animations) assert (s.find (a.target) != null);
    }
}

void test_edits () {
    var p = Templates.build ("lecture");
    int texts = 0, notes = 0;
    TextWalker.walk (p, (spot, text) => {
        if (spot.notes) notes++;
        else texts++;
    });
    assert (notes == p.slides.size && texts > 10);
    var body = new TextBody ();
    var par = new Paragraph ();
    var a = new TextRun ("Hello wo");
    a.bold = 1;
    par.runs.add (a);
    par.runs.add (new TextRun ("rld again"));
    body.paragraphs.add (par);
    body.paragraphs.add (new Paragraph ("second world"));
    var s = new Slide ();
    var sh = new ShapeElement (ShapeKind.RECT);
    sh.text = body;
    sh.id = 7;
    s.elements.add (sh);
    s.notes = "a world of notes";
    var deck = new Presentation ();
    deck.slides.add (s);
    var found = new Gee.ArrayList<TextSpot> ();
    TextWalker.walk (deck, (spot, text) => {
        int i = text.index_of ("world");
        while (i >= 0) {
            var m = new TextSpot (spot.slide, spot.element);
            m.notes = spot.notes;
            m.body = spot.body;
            m.start = text.substring (0, i).char_count ();
            m.length = 5;
            found.add (m);
            i = text.index_of ("world", i + 1);
        }
    });
    assert (found.size == 3);
    for (int i = found.size - 1; i >= 0; i--) assert (SpotEdit.replace (deck, found[i], "planet"));
    assert (body.plain_text () == "Hello planet again\nsecond planet");
    assert (body.paragraphs[0].runs[0].bold == 1);
    assert (s.notes == "a planet of notes");
    var q = Factory.new_presentation (ThemePreset.find ("clean"));
    Factory.add_slide (q, q.master.layout_of_kind (LayoutKind.TITLE_CONTENT), 1);
    HeaderFooter.set_meta (q, PlaceholderKind.SLIDE_NUMBER, true, "");
    HeaderFooter.set_meta (q, PlaceholderKind.FOOTER, true, "Confidential");
    foreach (var sl in q.slides) {
        var num = sl.placeholder (PlaceholderKind.SLIDE_NUMBER);
        assert (num != null && num.text_body ().paragraphs[0].runs[0].field == "slidenum");
        assert (sl.placeholder (PlaceholderKind.FOOTER).text_body ().plain_text () == "Confidential");
    }
    HeaderFooter.set_meta (q, PlaceholderKind.SLIDE_NUMBER, false, "");
    foreach (var sl in q.slides) assert (sl.placeholder (PlaceholderKind.SLIDE_NUMBER) == null);
    var r = new Renderer ();
    var ctx = new RenderContext (q, q.slides[1], q.layout_for (q.slides[1]), q.master);
    var foot = q.slides[1].placeholder (PlaceholderKind.FOOTER);
    assert (r.field_text (ctx, Factory.field_run ("slidenum", "x")) == "2");
    assert (foot.w > 0);
    var tb = Factory.text_box (q, 480, 270, 100, "Box", 20);
    q.slides[0].elements.add (tb);
    SlideSize.resize (q, 720, 540);
    assert (q.width == 720 && q.height == 540);
    assert (tb.x + tb.w <= 720 && tb.x >= 0);
    assert (Math.fabs (tb.text.paragraphs[0].runs[0].size - 15) < 0.01);
}

void main () {
    Intl.setlocale (LocaleCategory.ALL, "C.UTF-8");
    test_colors ();
    test_text ();
    test_factory ();
    test_inheritance ();
    test_undo ();
    test_table ();
    test_group ();
    test_player ();
    test_templates ();
    test_edits ();
    print ("model tests passed\n");
}
