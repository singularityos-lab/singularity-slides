using Singularity.Apps.Slides;

int checks = 0;

void check (bool ok, string what) {
    checks++;
    if (!ok) error ("check failed: %s", what);
}

bool near (double a, double b, double eps = 0.01) {
    return Math.fabs (a - b) <= eps;
}

uint8[] load_file (string name) throws Error {
    uint8[] data;
    FileUtils.get_data (Path.build_filename ("fixtures", "poi", name), out data);
    return data;
}

Presentation read_bytes (uint8[] data, string name) throws Error {
    return Document.load_bytes (data, name);
}

Presentation pptx_roundtrip (Presentation p, out ZipReader zip) throws Error {
    var data = new PptxWriter (p).write ();
    zip = new ZipReader (data);
    return Document.load_bytes (data, "deck.pptx");
}

Presentation odp_roundtrip (Presentation p) throws Error {
    var data = new OdpWriter (p).write ();
    return Document.load_bytes (data, "deck.odp");
}

Gee.ArrayList<Element> all_elements (Slide s) {
    var list = new Gee.ArrayList<Element> ();
    foreach (var e in s.elements) collect (e, list);
    return list;
}

void collect (Element e, Gee.List<Element> list) {
    list.add (e);
    var g = e as GroupElement;
    if (g != null) foreach (var c in g.children) collect (c, list);
}

T? first_of<T> (Slide s) {
    foreach (var e in all_elements (s)) if (e is T) return (T) e;
    return null;
}

bool zip_has_prefix (ZipReader z, string prefix) {
    foreach (string n in z.names ()) if (n.has_prefix (prefix)) return true;
    return false;
}

string zip_text (ZipReader z, string name) throws Error {
    return z.read_text (name) ?? "";
}

string slide_xml (ZipReader z, int n) throws Error {
    return zip_text (z, "ppt/slides/slide%d.xml".printf (n));
}

void test_poi_smartart () throws Error {
    var p = read_bytes (load_file ("smartart-simple.pptx"), "a.pptx");
    DiagramElement? d = first_of<DiagramElement> (p.slides[0]);
    check (d != null, "smartart read as diagram");
    var texts = new Gee.ArrayList<string> ();
    foreach (var n in d.flat ()) texts.add (n.plain ());
    check (texts.contains ("abc") && texts.contains ("def") && texts.contains ("ghi"), "smartart node texts %s".printf (string.joinv (",", texts.to_array ())));
    check (d.layout.category () == DiagramCategory.RELATIONSHIP, "smartart layout is venn %s".printf (d.layout.label ()));
    check (d.drawing != null && d.pristine (), "smartart keeps the PowerPoint drawing");
    ZipReader z;
    var p2 = pptx_roundtrip (p, out z);
    check (zip_has_prefix (z, "ppt/diagrams/data"), "diagram data part kept");
    check (zip_has_prefix (z, "ppt/diagrams/layout"), "diagram layout part kept");
    check (zip_has_prefix (z, "ppt/diagrams/drawing"), "diagram drawing part kept");
    check (slide_xml (z, 1).contains ("dgm:relIds"), "graphic frame still a SmartArt");
    DiagramElement? d2 = first_of<DiagramElement> (p2.slides[0]);
    check (d2 != null && d2.flat ().size == d.flat ().size, "smartart survives round trip");
    var p3 = read_bytes (load_file ("SmartArt.pptx"), "b.pptx");
    DiagramElement? d3 = first_of<DiagramElement> (p3.slides[0]);
    check (d3 != null && d3.layout == DiagramLayout.BLOCK_LIST && d3.nodes.size >= 3, "default block list smartart");
    d2.nodes[0].set_plain ("Changed");
    d2.layout = DiagramLayout.BASIC_PROCESS;
    ZipReader z2;
    var p4 = pptx_roundtrip (p2, out z2);
    DiagramElement? d4 = first_of<DiagramElement> (p4.slides[0]);
    check (d4 != null && d4.nodes[0].plain () == "Changed" && d4.layout == DiagramLayout.BASIC_PROCESS, "edited diagram reopens as an editable diagram");
    check (slide_xml (z2, 1).contains ("<p:grpSp>"), "edited diagram written as shapes for other apps");
    var od = odp_roundtrip (p4);
    DiagramElement? d5 = first_of<DiagramElement> (od.slides[0]);
    check (d5 != null && d5.nodes[0].plain () == "Changed" && d5.layout == DiagramLayout.BASIC_PROCESS, "diagram through ODP");
}

void test_poi_media () throws Error {
    var p = read_bytes (load_file ("EmbeddedVideo.pptx"), "v.pptx");
    MediaElement? m = first_of<MediaElement> (p.slides[0]);
    check (m != null && m.is_video && m.data != null && m.data.get_size () > 1000, "video read");
    check (m.poster != null, "video poster read");
    check (near (m.volume, 0.8), "video volume from timing %g".printf (m.volume));
    check (m.start == MediaStart.IN_SEQUENCE, "video starts in click sequence");
    ZipReader z;
    var p2 = pptx_roundtrip (p, out z);
    MediaElement? m2 = first_of<MediaElement> (p2.slides[0]);
    check (m2 != null && m2.data.compare (m.data) == 0, "video bytes survive");
    string xml = slide_xml (z, 1);
    check (xml.contains ("a:videoFile") && xml.contains ("p14:media") && xml.contains ("<p:video>"), "video markup written");
    var a = read_bytes (load_file ("EmbeddedAudio.pptx"), "a.pptx");
    MediaElement? am = first_of<MediaElement> (a.slides[0]);
    check (am != null && !am.is_video && am.mime == "audio/mpeg", "audio read");
    am.trim_start = 0.5;
    am.trim_end = 0.25;
    am.fade_in = 1;
    am.loop = true;
    am.start = MediaStart.AUTOMATIC;
    am.bookmarks.add (new MediaBookmark ("Chorus", 1.5));
    ZipReader za;
    var a2 = pptx_roundtrip (a, out za);
    MediaElement? am2 = first_of<MediaElement> (a2.slides[0]);
    check (am2 != null && near (am2.trim_start, 0.5) && near (am2.trim_end, 0.25) && near (am2.fade_in, 1) && am2.loop, "audio trim, fade and loop");
    check (am2.start == MediaStart.AUTOMATIC && am2.bookmarks.size == 1 && am2.bookmarks[0].name == "Chorus", "audio start and bookmarks");
    var o = odp_roundtrip (a2);
    MediaElement? om = first_of<MediaElement> (o.slides[0]);
    check (om != null && om.data.compare (am.data) == 0 && near (om.trim_start, 0.5) && om.loop, "audio through ODP");
}

void test_poi_comments () throws Error {
    var p = read_bytes (load_file ("45545_Comment.pptx"), "c.pptx");
    int n = p.comment_count ();
    check (n >= 2, "comments read %d".printf (n));
    Comment? first = null;
    foreach (var s in p.slides) if (s.comments.size > 0 && first == null) first = s.comments[0];
    check (first.author == "XPVMWARE01" && first.text == "testdoc", "comment author and text");
    check (near (first.x, 3472 / 8.0), "comment position");
    first.replies.add (new Comment ());
    first.replies[0].author = "Reviewer";
    first.replies[0].text = "Agreed @XPVMWARE01";
    first.resolved = true;
    ZipReader z;
    var p2 = pptx_roundtrip (p, out z);
    check (p2.comment_count () == n, "comments survive %d".printf (p2.comment_count ()));
    Comment? f2 = null;
    foreach (var s in p2.slides) if (s.comments.size > 0 && f2 == null) f2 = s.comments[0];
    check (f2.replies.size == 1 && f2.replies[0].text == "Agreed @XPVMWARE01" && f2.resolved, "reply and resolved state survive");
    check (f2.replies[0].mentions ("XPVMWARE01"), "mention detected");
    check (z.has ("ppt/commentAuthors.xml"), "authors part written");
    var o = odp_roundtrip (p2);
    Comment? f3 = null;
    foreach (var s in o.slides) if (s.comments.size > 0 && f3 == null) f3 = s.comments[0];
    check (f3 != null && f3.text == "testdoc" && f3.replies.size == 1, "comments through ODP");
}

Presentation feature_deck () {
    var p = Factory.new_presentation (ThemePreset.all ()[0]);
    while (p.slides.size < 4) Factory.add_slide (p, p.master.layouts[1], p.slides.size);
    p.slides[0].section = new SectionMark ("Intro");
    p.slides[2].section = new SectionMark ("Details");
    var cs = new CustomShow ();
    cs.name = "Short";
    cs.slides.add (p.slides[0].uid);
    cs.slides.add (p.slides[3].uid);
    p.custom_shows.add (cs);
    var s = p.slides[1];
    var star = new ShapeElement (ShapeKind.PRESET);
    star.preset = "star7";
    star.adjust_values["adj"] = 30000;
    star.set_geometry (100, 100, 120, 120);
    star.fill = new Fill.solid ("accent2");
    star.name = "!!Star";
    star.effects.glow_color = "accent1";
    star.effects.glow_radius = 8;
    star.effects.reflection = true;
    star.effects.bevel = "circle";
    star.click = new ClickAction (ActionKind.SLIDE);
    star.click.slide_uid = p.slides[3].uid;
    p.assign_ids (star);
    s.elements.add (star);
    var btn = new ShapeElement (ShapeKind.PRESET);
    btn.preset = "actionButtonForwardNext";
    btn.set_geometry (800, 450, 60, 40);
    btn.fill = new Fill.solid ("accent1");
    btn.click = new ClickAction (ActionKind.NEXT_SLIDE);
    p.assign_ids (btn);
    s.elements.add (btn);
    var link = Factory.text_box (p, 300, 300, 300, "Go to details");
    link.text.paragraphs[0].runs[0].link = LinkTarget.for_slide (p.slides[2].uid);
    link.effects.text_outline = "accent1";
    link.effects.text_warp = "textArchUp";
    link.effects.text_glow = "accent3";
    link.effects.text_glow_radius = 5;
    p.assign_ids (link);
    s.elements.add (link);
    var ink = new InkElement ();
    var st = new InkStroke ();
    st.color = "#ff0000";
    st.width = 3;
    for (int i = 0; i < 10; i++) {
        st.pts.add (400 + i * 10);
        st.pts.add (100 + (i % 2) * 20);
    }
    ink.strokes.add (st);
    ink.fit ();
    p.assign_ids (ink);
    s.elements.add (ink);
    var zoom = new ZoomElement ();
    zoom.target_uid = p.slides[2].uid;
    zoom.return_to_zoom = true;
    zoom.set_geometry (600, 100, 192, 108);
    p.assign_ids (zoom);
    s.elements.add (zoom);
    var eq = new EquationElement ();
    eq.mathml = "<math xmlns=\"http://www.w3.org/1998/Math/MathML\" display=\"block\"><mrow><msup><mi>e</mi><mrow><mi>i</mi><mi>π</mi></mrow></msup><mo>+</mo><mn>1</mn><mo>=</mo><mn>0</mn></mrow></math>";
    eq.latex = "e^{i\\pi}+1=0";
    eq.set_geometry (100, 300, 150, 40);
    p.assign_ids (eq);
    s.elements.add (eq);
    var path = new Animation (star.id);
    path.anim_class = AnimClass.PATH;
    path.effect = AnimEffect.MOTION_PATH;
    path.path_preset = MotionPreset.ARC_DOWN;
    path.path = MotionPreset.ARC_DOWN.build (p.width / p.height);
    path.duration = 2;
    s.animations.add (path);
    var trig = new Animation (btn.id);
    trig.anim_class = AnimClass.EMPHASIS;
    trig.set_effect (AnimEffect.FILL_COLOR);
    trig.color = "#00ff00";
    trig.trigger_shape = star.id;
    s.animations.add (trig);
    var rep = new Animation (link.id);
    rep.anim_class = AnimClass.EMPHASIS;
    rep.set_effect (AnimEffect.SPIN);
    rep.amount = 180;
    rep.repeat = 3;
    rep.auto_reverse = true;
    rep.trigger = AnimTrigger.AFTER_PREVIOUS;
    s.animations.add (rep);
    var wheel = new Animation (btn.id);
    wheel.set_effect (AnimEffect.WHEEL);
    wheel.subtype = 4;
    wheel.after = AfterEffect.HIDE;
    s.animations.add (wheel);
    p.slides[2].transition.kind = TransitionKind.MORPH;
    p.slides[2].transition.variant = 1;
    p.slides[2].transition.duration = 2;
    p.slides[3].transition.kind = TransitionKind.CURTAINS;
    p.slides[3].transition.duration = 1.5;
    p.slides[1].transition.kind = TransitionKind.VORTEX;
    p.slides[1].transition.variant = 1;
    var c = new Comment ();
    c.author = "Ada";
    c.initials = "A";
    c.text = "Check this";
    c.x = 50;
    c.y = 60;
    p.slides[1].comments.add (c);
    return p;
}

void check_features (Presentation p, string how, bool pptx) {
    check (p.slides.size == 4, how + ": slides");
    check (p.slides[0].section != null && p.slides[0].section.name == "Intro" && p.slides[2].section != null && p.slides[2].section.name == "Details" && p.slides[1].section == null, how + ": sections");
    var cs = p.find_custom_show ("Short");
    check (cs != null && cs.slides.size == 2 && cs.slides[1] == p.slides[3].uid, how + ": custom show");
    var s = p.slides[1];
    ShapeElement? star = null, btn = null, link = null;
    foreach (var e in s.elements) {
        var sh = e as ShapeElement;
        if (sh == null) continue;
        if (sh.preset_name () == "star7") star = sh;
        else if (sh.preset_name () == "actionButtonForwardNext") btn = sh;
        else if (sh.text_box) link = sh;
    }
    check (star != null && near (star.adjust_values["adj"], 30000), how + ": preset and adjust");
    check (star.click != null && star.click.kind == ActionKind.SLIDE && star.click.slide_uid == p.slides[3].uid, how + ": slide jump action");
    check (star.effects.glow_color != "" && near (star.effects.glow_radius, 8) && star.effects.reflection && star.effects.bevel == "circle", how + ": shape effects");
    check (btn != null && btn.click != null && btn.click.kind == ActionKind.NEXT_SLIDE, how + ": action button");
    check (link != null && link.text.paragraphs[0].runs[0].link == LinkTarget.for_slide (p.slides[2].uid), how + ": internal hyperlink %s".printf (link != null ? link.text.paragraphs[0].runs[0].link : "none"));
    check (link.effects.text_outline != "" && link.effects.text_warp == "textArchUp" && link.effects.text_glow != "", how + ": text effects");
    InkElement? ink = first_of<InkElement> (s);
    check (ink != null && ink.strokes.size == 1 && ink.strokes[0].pts.size == 20, how + ": ink");
    check (near (ink.strokes[0].pts[0], 400, 1.5) && near (ink.strokes[0].pts[3], 120, 1.5), how + ": ink points %g %g".printf (ink.strokes[0].pts[0], ink.strokes[0].pts[3]));
    ZoomElement? zoom = first_of<ZoomElement> (s);
    check (zoom != null && zoom.target_uid == p.slides[2].uid && zoom.return_to_zoom, how + ": zoom");
    EquationElement? eq = first_of<EquationElement> (s);
    check (eq != null && eq.mathml.contains ("msup"), how + ": equation");
    if (pptx) check (eq.latex == "e^{i\\pi}+1=0", how + ": equation latex");
    Animation? path = null, trig = null, rep = null, wheel = null;
    foreach (var a in s.animations) {
        if (a.anim_class == AnimClass.PATH) path = a;
        else if (a.trigger_shape >= 0) trig = a;
        else if (a.effect == AnimEffect.SPIN) rep = a;
        else if (a.effect == AnimEffect.WHEEL) wheel = a;
    }
    check (path != null && path.path.size >= 2 && near (path.duration, 2), how + ": motion path");
    double px, py, ang;
    PathSampler.at (path.path, 1, out px, out py, out ang);
    check (near (px, 0.24, 0.005) && near (py, 0, 0.005), how + ": motion path end %g %g".printf (px, py));
    check (trig != null && trig.trigger_shape == star.id && trig.effect == AnimEffect.FILL_COLOR, how + ": trigger");
    check (rep != null && near (rep.amount, 180) && near (rep.repeat, 3) && rep.auto_reverse, how + ": repeat and rewind options");
    check (wheel != null && wheel.subtype == 4 && wheel.after == AfterEffect.HIDE, how + ": wheel spokes and hide after");
    check (p.slides[2].transition.kind == TransitionKind.MORPH && p.slides[2].transition.variant == 1 && near (p.slides[2].transition.duration, 2), how + ": morph");
    check (p.slides[3].transition.kind == TransitionKind.CURTAINS, how + ": curtains");
    check (p.slides[1].transition.kind == TransitionKind.VORTEX && p.slides[1].transition.variant == 1, how + ": vortex");
    check (s.comments.size == 1 && s.comments[0].author == "Ada" && s.comments[0].text == "Check this", how + ": comment");
}

void test_features () throws Error {
    var p = feature_deck ();
    check_features (p, "model", true);
    ZipReader z;
    var p2 = pptx_roundtrip (p, out z);
    check_features (p2, "pptx", true);
    check (zip_text (z, "ppt/presentation.xml").contains ("p14:sectionLst") && zip_text (z, "ppt/presentation.xml").contains ("p:custShowLst"), "sections and custom shows in presentation.xml");
    string s2 = slide_xml (z, 2);
    check (s2.contains ("pslz:sldZm") && s2.contains ("p:contentPart") && s2.contains ("a14:m") && s2.contains ("interactiveSeq") && s2.contains ("animMotion"), "slide 2 markup");
    check (slide_xml (z, 3).contains ("p159:morph"), "morph markup");
    check (zip_has_prefix (z, "ppt/ink/"), "ink part");
    var p3 = odp_roundtrip (p2);
    check_features (p3, "odp", false);
    var again = pptx_roundtrip (p3, out z);
    check_features (again, "odp then pptx", false);
}

void test_foreign () throws Error {
    var zw = new ZipWriter ();
    var base_p = Factory.new_presentation (ThemePreset.all ()[0]);
    var data = new PptxWriter (base_p).write ();
    var zr = new ZipReader (data);
    foreach (string n in zr.names ()) {
        if (n == "ppt/slides/slide1.xml" || n == "[Content_Types].xml" || n == "ppt/slides/_rels/slide1.xml.rels" || n == "ppt/_rels/presentation.xml.rels") continue;
        zw.add (n, zr.read (n));
    }
    string slide = zr.read_text ("ppt/slides/slide1.xml");
    string ole = "<p:graphicFrame><p:nvGraphicFramePr><p:cNvPr id=\"77\" name=\"Worksheet\"/><p:cNvGraphicFramePr/><p:nvPr/></p:nvGraphicFramePr><p:xfrm><a:off x=\"1270000\" y=\"1270000\"/><a:ext cx=\"2540000\" cy=\"1270000\"/></p:xfrm><a:graphic><a:graphicData uri=\"http://schemas.openxmlformats.org/presentationml/2006/ole\"><p:oleObj name=\"Worksheet\" r:id=\"rIdOle\" progId=\"Excel.Sheet.12\"><p:embed/></p:oleObj></a:graphicData></a:graphic></p:graphicFrame>";
    slide = slide.replace ("</p:spTree>", ole + "</p:spTree>");
    zw.add_text ("ppt/slides/slide1.xml", slide);
    string rels = zr.read_text ("ppt/slides/_rels/slide1.xml.rels");
    rels = rels.replace ("</Relationships>", "<Relationship Id=\"rIdOle\" Type=\"http://schemas.openxmlformats.org/officeDocument/2006/relationships/package\" Target=\"../embeddings/Sheet1.xlsx\"/></Relationships>");
    zw.add_text ("ppt/slides/_rels/slide1.xml.rels", rels);
    zw.add ("ppt/embeddings/Sheet1.xlsx", "PK-fake-workbook".data);
    string prels = zr.read_text ("ppt/_rels/presentation.xml.rels");
    prels = prels.replace ("</Relationships>", "<Relationship Id=\"rIdX\" Type=\"http://schemas.openxmlformats.org/officeDocument/2006/relationships/customXml\" Target=\"../customXml/item1.xml\"/></Relationships>");
    zw.add_text ("ppt/_rels/presentation.xml.rels", prels);
    zw.add_text ("customXml/item1.xml", "<data>keep me</data>");
    string ct = zr.read_text ("[Content_Types].xml").replace ("</Types>", "<Default Extension=\"xlsx\" ContentType=\"application/vnd.openxmlformats-officedocument.spreadsheetml.sheet\"/></Types>");
    zw.add_text ("[Content_Types].xml", ct);
    var p = Document.load_bytes (zw.finish (), "ole.pptx");
    ForeignElement? f = first_of<ForeignElement> (p.slides[0]);
    check (f != null && f.label == "Worksheet" && near (f.x, 100) && near (f.w, 200), "ole object kept as a foreign element");
    check (p.warnings.size == 1, "user is told about kept objects");
    check (p.extra_parts.size == 1, "unknown package part kept");
    f.move_by (50, 0);
    ZipReader z;
    var p2 = pptx_roundtrip (p, out z);
    check (z.has ("ppt/embeddings/Sheet1.xlsx") && z.read_text ("ppt/embeddings/Sheet1.xlsx") == "PK-fake-workbook", "embedded package bytes kept");
    string xml = slide_xml (z, 1);
    check (xml.contains ("p:oleObj") && xml.contains ("x=\"1905000\""), "ole markup kept and moved");
    check (z.has ("customXml/item1.xml"), "custom xml part kept");
    ForeignElement? f2 = first_of<ForeignElement> (p2.slides[0]);
    check (f2 != null && near (f2.x, 150), "foreign element geometry after round trip");
    var rels2 = z.read_text ("ppt/slides/_rels/slide1.xml.rels");
    check (rels2.contains ("embeddings/Sheet1.xlsx"), "relationship rewritten");
}

void test_diagram_engine () {
    foreach (var l in DiagramLayout.ALL) {
        var d = new DiagramElement ();
        d.layout = l;
        d.set_geometry (0, 0, 600, 400);
        d.sample (4);
        if (l.category () == DiagramCategory.HIERARCHY) {
            d.nodes[0].children[0].children.add (new DiagramNode ("Leaf"));
        } else {
            d.nodes[0].children.add (new DiagramNode ("Detail"));
        }
        var shapes = d.build ();
        check (shapes.size >= 3, "diagram %s builds shapes (%d)".printf (l.label (), shapes.size));
        foreach (var e in shapes) {
            check (e.x >= -1 && e.y >= -1 && e.x + e.w <= 601 && e.y + e.h <= 401 || e.rotation != 0, "diagram %s stays inside its frame".printf (l.label ()));
        }
    }
    var d = new DiagramElement ();
    d.sample (3);
    var n1 = d.nodes[1];
    check (d.demote (n1) && d.nodes.size == 2 && d.nodes[0].children.size == 1, "demote");
    check (d.promote (n1) && d.nodes.size == 3, "promote");
    check (d.move (d.nodes[2], -1), "move");
    d.remove (d.nodes[0]);
    check (d.nodes.size == 2, "remove");
}

void test_outline () {
    var p = Factory.new_presentation (ThemePreset.all ()[0]);
    string text = "First\n\tPoint A\n\t\tSub point\nSecond\n\tPoint B\n";
    var q = DeckOutline.from_text (text, p);
    check (q.slides.size == 2 && q.slides[0].title () == "First", "outline import slides");
    check (DeckOutline.to_text (q).contains ("\t\tSub point"), "outline export keeps levels");
    check (DeckOutline.to_rtf (q).has_prefix ("{\\rtf1") && DeckOutline.to_rtf (q).contains ("Point B"), "rtf outline");
}

void test_player () {
    var p = feature_deck ();
    var s = p.slides[1];
    var pl = new Player (p, s);
    check (pl.triggers.size == 1, "trigger group built");
    var st0 = pl.states_at (0, 0);
    Element? star = null;
    foreach (var e in s.elements) if (e.name == "!!Star") star = e;
    var mid = pl.states_at (0, 1);
    check (mid.has_key (star.id) && mid[star.id].path_dx > 0, "motion path moves the star");
    var end = pl.states_at (0, 10);
    check (near (end[star.id].path_dx, 0.24 * p.width, 1), "motion path end offset");
    var key = pl.trigger_keys_for (star.id)[0];
    pl.trigger_elapsed[key] = 0.25;
    var t = pl.states_at (0, 0);
    int btn = s.animations[1].target;
    check (t.has_key (btn) && t[btn].fill_color == "#00ff00" && t[btn].color_mix > 0, "trigger drives fill color");
    check (st0 != null, "initial states");
    var surf = new Cairo.ImageSurface (Cairo.Format.ARGB32, 320, 180);
    var cr = new Cairo.Context (surf);
    cr.scale (320 / p.width, 180 / p.height);
    Morph.draw (cr, p, p.slides[1], p.slides[2], 0.5);
    check (surf.status () == Cairo.Status.SUCCESS, "morph renders");
}

void test_deck_tools () throws Error {
    var p = Factory.new_presentation (ThemePreset.all ()[0]);
    var q = DeckOutline.from_text ("One\n\tA\nTwo\n\tB\n", p);
    var keep = q.slides[0];
    DeckOutline.apply (q, "One edited\n\tA\n\tA2\nTwo\n\tB\nThree\n\tC\n");
    check (q.slides.size == 3 && q.slides[0] == keep && q.slides[0].title () == "One edited", "outline edit updates slides in place");
    check (DeckOutline.to_text (q).contains ("\tA2\n") && q.slides[2].title () == "Three", "outline edit adds bullets and slides");
    var untitled = Factory.add_slide (q, q.master.layouts[1], 3);
    var ut = untitled.placeholder (PlaceholderKind.TITLE);
    if (ut != null) ut.text_body ().set_plain ("");
    DeckOutline.apply (q, DeckOutline.to_text (q));
    check (q.slides.size == 4 && q.slides[3] == untitled, "outline round trip keeps untitled slides");
    DeckOutline.apply (q, "One edited\n\tA\n");
    check (q.slides.size == 1, "outline edit removes slides");
    var issues = AccessibilityCheck.run (q);
    var img = new ImageElement (new Bytes ({ 1, 2, 3 }), "image/png");
    img.set_geometry (10, 10, 100, 100);
    q.assign_ids (img);
    q.slides[0].elements.add (img);
    var s2 = Factory.add_slide (q, q.master.layouts[0], 1);
    var t = s2.placeholder (PlaceholderKind.TITLE);
    if (t != null) t.text_body ().set_plain ("");
    var issues2 = AccessibilityCheck.run (q);
    bool alt = false, title = false;
    foreach (var it in issues2) {
        if (it.kind == AccessibilityCheck.Kind.ALT_TEXT && it.element == img) alt = true;
        if (it.kind == AccessibilityCheck.Kind.NO_TITLE && it.slide == 1) title = true;
    }
    check (alt && title && issues2.size > issues.size, "accessibility finds missing alt text and titles");
    check (AccessibilityCheck.contrast (Rgba (0, 0, 0, 1), Rgba (1, 1, 1, 1)) > 20, "contrast ratio");
    img.description = "Logo";
    bool still = false;
    foreach (var it in AccessibilityCheck.run (q)) if (it.kind == AccessibilityCheck.Kind.ALT_TEXT) still = true;
    check (!still, "alt text clears the issue");
    var layout = q.master.layouts[0];
    var ph = new ShapeElement (ShapeKind.RECT);
    ph.placeholder = PlaceholderKind.CHART;
    ph.placeholder_idx = 42;
    ph.text = new TextBody ();
    ph.set_geometry (50, 50, 200, 100);
    q.assign_ids (ph);
    layout.elements.add (ph);
    ZipReader z;
    var r = pptx_roundtrip (q, out z);
    bool found = false;
    foreach (var e in r.master.layouts[0].elements) if (e.placeholder == PlaceholderKind.CHART && e.placeholder_idx == 42) found = true;
    check (found, "chart placeholder survives PPTX");
    var o = odp_roundtrip (q);
    bool ofound = false;
    foreach (var l in o.all_layouts ()) foreach (var e in l.elements) if (e.placeholder == PlaceholderKind.CHART) ofound = true;
    foreach (var e in o.master.elements) if (e.placeholder == PlaceholderKind.CHART) ofound = true;
    check (ofound || o.all_layouts ().size > 0, "chart placeholder through ODP");
    var dark = ThemeVariants.make (q.master.theme, 1);
    check (dark.scheme_hex ("dk1") == q.master.theme.scheme_hex ("lt1"), "dark variant swaps colors");
    var cs = new CustomShow ();
    cs.name = "Short";
    cs.slides.add (q.slides[0].uid);
    q.custom_shows.add (cs);
    q.show_kind = 2;
    q.show_custom = "Short";
    var r2 = pptx_roundtrip (q, out z);
    check (r2.find_custom_show ("Short") != null && r2.show_kind == 2 && r2.show_custom == "Short", "custom show and kiosk setup survive PPTX");
    var m = new MediaElement ();
    m.data = new Bytes ({ 'O', 'g', 'g', 'S', 0, 0 });
    m.mime = "audio/ogg";
    m.is_video = false;
    m.start = MediaStart.AUTOMATIC;
    m.set_geometry (0, 0, 40, 40);
    q.assign_ids (m);
    q.slides[0].elements.add (m);
    var anims = Player.with_implied_media (q.slides[0]);
    check (anims.size >= 1 && anims[0].target == m.id && anims[0].effect == AnimEffect.MEDIA_PLAY, "automatic media plays in the show");
    check (MediaElement.sniff_extension (m.data) == "ogg", "sound type sniffed");
}

void test_charts () throws Error {
    double[] xs = { 1, 2, 3, 4, 5 };
    double[] ys = { 3, 5, 7, 9, 11 };
    var lin = TrendFit.fit (xs, ys, TrendKind.LINEAR, 2, 2);
    check (lin.ok && near (lin.coef[1], 2) && near (lin.coef[0], 1) && near (lin.r2, 1), "linear trend fit");
    double[] ey = { 2.7183, 7.389, 20.086, 54.598, 148.41 };
    var ex = TrendFit.fit (xs, ey, TrendKind.EXPONENTIAL, 2, 2);
    check (ex.ok && near (ex.coef[1], 1, 0.01) && near (ex.coef[0], 1, 0.02), "exponential trend fit");
    double[] py = { 1, 4, 9, 16, 25 };
    var po = TrendFit.fit (xs, py, TrendKind.POLYNOMIAL, 2, 2);
    check (po.ok && near (po.coef[2], 1) && near (po.r2, 1) && po.equation ().contains ("x^2"), "polynomial trend fit");
    var ma = TrendFit.moving_average (ys, 2);
    check (ma[0].is_nan () && near (ma[1], 4), "moving average");
    var p = Factory.new_presentation (ThemePreset.all ()[0]);
    var s = p.slides[0];
    var ch = new ChartElement (ChartKind.COLUMN);
    ch.sample_data ();
    ch.series[1].kind = SeriesKind.LINE;
    ch.series[1].secondary = true;
    ch.series[0].trend = TrendKind.POLYNOMIAL;
    ch.series[0].trend_order = 3;
    ch.series[0].trend_equation = true;
    ch.series[0].trend_r2 = true;
    ch.val_axis.title = "Revenue";
    ch.val_axis.min = 0;
    ch.val_axis.max = 10;
    ch.val_axis.major = 2;
    ch.val_axis.format = "#,##0";
    ch.cat_axis.title = "Quarter";
    ch.sec_axis.title = "Margin";
    ch.set_geometry (50, 50, 500, 300);
    p.assign_ids (ch);
    s.elements.add (ch);
    var radar = new ChartElement (ChartKind.RADAR);
    radar.sample_data ();
    radar.set_geometry (50, 50, 300, 300);
    p.assign_ids (radar);
    s.elements.add (radar);
    var bub = new ChartElement (ChartKind.BUBBLE);
    bub.sample_data ();
    bub.categories.clear ();
    foreach (string c in new string[] { "1", "2", "3", "4" }) bub.categories.add (c);
    bub.set_geometry (50, 50, 300, 300);
    p.assign_ids (bub);
    s.elements.add (bub);
    ZipReader z;
    var r = pptx_roundtrip (p, out z);
    check (zip_has_prefix (z, "ppt/embeddings/Microsoft_Excel_Worksheet"), "chart embeds its workbook");
    var wb = new ZipReader (z.read ("ppt/embeddings/Microsoft_Excel_Worksheet1.xlsx"));
    string sheet = wb.read_text ("xl/worksheets/sheet1.xml") ?? "";
    check (sheet.contains ("Series 1") && sheet.contains ("<v>4.3</v>"), "workbook holds the chart data");
    string cx = zip_text (z, "ppt/charts/chart1.xml");
    check (cx.contains ("c:lineChart") && cx.contains ("c:barChart") && cx.contains ("c:trendline") && cx.contains ("c:externalData") && cx.contains ("<c:axPos val=\"r\"/>"), "combo chart markup");
    var rc = r.slides[0].elements[r.slides[0].elements.size - 3] as ChartElement;
    check (rc != null && rc.series[1].kind == SeriesKind.LINE && rc.series[1].secondary && !rc.series[0].secondary, "combo and secondary axis survive PPTX");
    check (rc.series[0].trend == TrendKind.POLYNOMIAL && rc.series[0].trend_order == 3 && rc.series[0].trend_equation && rc.series[0].trend_r2, "trendline survives PPTX");
    check (rc.val_axis.title == "Revenue" && near (rc.val_axis.max, 10) && near (rc.val_axis.major, 2) && rc.val_axis.format == "#,##0" && rc.cat_axis.title == "Quarter" && rc.sec_axis.title == "Margin", "axis options survive PPTX %s %g".printf (rc.val_axis.title, rc.val_axis.max));
    var rr = r.slides[0].elements[r.slides[0].elements.size - 2] as ChartElement;
    var rb = r.slides[0].elements[r.slides[0].elements.size - 1] as ChartElement;
    check (rr != null && rr.chart == ChartKind.RADAR && rr.series.size == 3, "radar survives PPTX");
    check (rb != null && rb.chart == ChartKind.BUBBLE && rb.series[0].sizes.size == 4 && near (rb.series[0].sizes[0], bub.series[0].sizes[0]), "bubble sizes survive PPTX");
    check (rc.pristine () || rc.original == null, "read chart is pristine or native");
    var o = odp_roundtrip (p);
    var oc = o.slides[0].elements[o.slides[0].elements.size - 3] as ChartElement;
    check (oc != null && oc.series[1].kind == SeriesKind.LINE && oc.series[1].secondary && oc.series[0].trend == TrendKind.POLYNOMIAL && oc.val_axis.title == "Revenue", "combo chart through ODP");
    var ob = o.slides[0].elements[o.slides[0].elements.size - 1] as ChartElement;
    check (ob != null && ob.chart == ChartKind.BUBBLE && ob.series[0].sizes.size == 4, "bubble through ODP");
    var surf = new Cairo.ImageSurface (Cairo.Format.ARGB32, 480, 270);
    var cr = new Cairo.Context (surf);
    cr.scale (480 / p.width, 270 / p.height);
    new Renderer ().draw_slide (cr, p, s);
    check (surf.status () == Cairo.Status.SUCCESS, "combo, radar and bubble charts render");
}

void test_protection () throws Error {
    var p = Factory.new_presentation (ThemePreset.all ()[0]);
    var t = p.slides[0].placeholder (PlaceholderKind.TITLE);
    t.text_body ().set_plain ("Secret plan");
    var pptx = Document.serialize_as (p, "pptx");
    var enc = Document.encrypt (pptx, "pptx", "hunter2");
    check (OfficeCrypto.is_encrypted (enc), "pptx encrypted as an Office package");
    bool refused = false;
    try {
        Document.decrypt (enc, "wrong");
    } catch (Error e) {
        refused = true;
    }
    check (refused, "wrong password refused for pptx");
    var back = Document.load_bytes (Document.decrypt (enc, "hunter2"), "a.pptx");
    check (back.slides[0].title () == "Secret plan", "pptx decrypts with the password");
    var odp = Document.serialize_as (p, "odp");
    var oenc = Document.encrypt (odp, "odp", "hunter2");
    check (OdfCrypto.is_encrypted (oenc) && !((string) oenc).contains ("Secret plan"), "odp encrypted as OpenDocument");
    var z = new ZipReader (oenc);
    string man = z.read_text ("META-INF/manifest.xml") ?? "";
    check (man.contains ("aes256-cbc") && man.contains ("PBKDF2") && man.contains ("sha256-1k"), "odp manifest carries encryption data");
    refused = false;
    try {
        Document.decrypt (oenc, "nope");
    } catch (Error e) {
        refused = true;
    }
    check (refused, "wrong password refused for odp");
    var oback = Document.load_bytes (Document.decrypt (oenc, "hunter2"), "a.odp");
    check (oback.slides[0].title () == "Secret plan", "odp decrypts with the password");
    var dk = OdfCrypto.pbkdf2_sha1 ("password".data, "salt".data, 2, 20);
    var sb = new StringBuilder ();
    foreach (uint8 b in dk) sb.append ("%02x".printf (b));
    check (sb.str == "ea6c014dc72d6f8ccd1ed92ace1d41f0d8de8957", "pbkdf2 matches RFC 6070");
    string root = DirUtils.make_tmp ("slides-versions-XXXXXX");
    VersionStore.root_override = root;
    string file = Path.build_filename (root, "deck.pptx");
    var d = new Document (p);
    d.save_to (file);
    check (VersionStore.list (file).size == 0, "first save keeps no version");
    t.text_body ().set_plain ("Second");
    d.save_to (file);
    var vs = VersionStore.list (file);
    check (vs.size == 1, "second save keeps the previous version");
    uint8[] vd;
    FileUtils.get_data (vs[0], out vd);
    check (Document.load_bytes (vd, vs[0]).slides[0].title () == "Secret plan", "version holds the earlier content");
    d.password = "pw";
    d.save_to (file);
    check (Document.needs_password (file) && Document.open (file, "pw").pres.slides[0].title () == "Second", "saved file encrypted and reopens");
    foreach (string f in VersionStore.list (file)) FileUtils.unlink (f);
    FileUtils.unlink (Path.build_filename (VersionStore.folder_for (file), "source.txt"));
    DirUtils.remove (VersionStore.folder_for (file));
    FileUtils.unlink (file);
    DirUtils.remove (Path.get_dirname (VersionStore.folder_for (file)));
    DirUtils.remove (root);
    VersionStore.root_override = null;
}

void test_thesaurus () {
    var m = Thesaurus.lookup_in (Path.build_filename ("fixtures", "thes", "th_en_US_v2.dat"), "Happy");
    check (m.size == 2 && m[0].part == "adj" && m[0].words.contains ("cheerful") && m[1].words.contains ("lucky"), "thesaurus lookup");
    check (Thesaurus.lookup_in (Path.build_filename ("fixtures", "thes", "th_en_US_v2.dat"), "absent").size == 0, "thesaurus miss");
}

void test_coach () {
    var p = Factory.new_presentation (ThemePreset.all ()[0]);
    var t = p.slides[0].placeholder (PlaceholderKind.TITLE);
    t.text_body ().set_plain ("Our quarterly revenue grew by twenty percent");
    var order = new Gee.ArrayList<int> ();
    order.add (0);
    var secs = new Gee.ArrayList<double?> ();
    secs.add (30.0);
    var texts = new Gee.ArrayList<string> ();
    texts.add ("Um so our quarterly revenue grew by twenty percent, um, you know, and basically that is great, and that is great, and that is great");
    var r = SpeechCoach.analyse (p, order, secs, texts);
    check (r.words == 25 && near (r.wpm, 50), "coach pace %d %g".printf (r.words, r.wpm));
    check (r.fillers["um"] == 2 && r.fillers["you know"] == 1 && r.fillers["basically"] == 1, "coach filler words");
    check (r.read_ratio > 0.2, "coach detects reading the slide %g".printf (r.read_ratio));
    check (r.repeated.size > 0 && r.repeated[0].has_prefix ("and that is") || r.repeated.contains ("that is great (3)"), "coach repeated phrases");
}

void test_design_ideas () {
    var p = Factory.new_presentation (ThemePreset.all ()[0]);
    var s = Factory.add_slide (p, p.master.layout_of_kind (LayoutKind.TITLE_CONTENT) ?? p.master.layouts[1], 1);
    s.placeholder (PlaceholderKind.TITLE).text_body ().set_plain ("Our Team");
    DeckOutline.body_of (s).text_body ().set_plain ("Twelve people across three offices");
    var img = new ImageElement (new Bytes ({ 1, 2, 3 }), "image/png");
    img.pixel_width = 1600;
    img.pixel_height = 900;
    img.set_geometry (400, 100, 200, 150);
    p.assign_ids (img);
    s.elements.add (img);
    var ideas = DesignIdeas.suggest (p, s);
    check (ideas.size >= 5, "design ideas offered %d".printf (ideas.size));
    var right = ideas[0].slide;
    var ri = right.find (img.id);
    check (ri != null && near (ri.x, p.width / 2) && near (ri.h, p.height), "picture placed on the right half");
    var ii = (ImageElement) ri;
    check (ii.crop_left > 0 && near (ii.crop_left, ii.crop_right) && near (ii.crop_top, 0), "picture cropped to cover");
    check (s.find (img.id).x == 400, "suggestions do not touch the slide");
}

Bytes make_glb () {
    float[] pos = { 0, 0, 0, 1, 0, 0, 1, 1, 0, 0, 1, 0, 0, 0, 1, 1, 0, 1, 1, 1, 1, 0, 1, 1 };
    uint16[] idx = { 0, 1, 2, 0, 2, 3, 4, 6, 5, 4, 7, 6, 0, 4, 5, 0, 5, 1, 1, 5, 6, 1, 6, 2, 2, 6, 7, 2, 7, 3, 3, 7, 4, 3, 4, 0 };
    var bin = new ByteArray ();
    foreach (float f in pos) {
        uint8[] b = new uint8[4];
        Memory.copy (b, &f, 4);
        bin.append (b);
    }
    foreach (uint16 i in idx) bin.append ({ (uint8) (i & 0xff), (uint8) (i >> 8) });
    while (bin.len % 4 != 0) bin.append ({ 0 });
    string json = "{\"asset\":{\"version\":\"2.0\"},\"scene\":0,\"scenes\":[{\"nodes\":[0]}],\"nodes\":[{\"mesh\":0,\"translation\":[1,0,0]}],\"meshes\":[{\"primitives\":[{\"attributes\":{\"POSITION\":0},\"indices\":1,\"material\":0}]}],\"materials\":[{\"pbrMetallicRoughness\":{\"baseColorFactor\":[0.8,0.2,0.2,1]}}],\"buffers\":[{\"byteLength\":%u}],\"bufferViews\":[{\"buffer\":0,\"byteOffset\":0,\"byteLength\":96},{\"buffer\":0,\"byteOffset\":96,\"byteLength\":72}],\"accessors\":[{\"bufferView\":0,\"componentType\":5126,\"count\":8,\"type\":\"VEC3\"},{\"bufferView\":1,\"componentType\":5123,\"count\":36,\"type\":\"SCALAR\"}]}".printf (bin.len);
    var js = new ByteArray ();
    js.append (json.data);
    while (js.len % 4 != 0) js.append ({ 0x20 });
    var out_b = new ByteArray ();
    uint32 total = 12 + 8 + js.len + 8 + bin.len;
    uint32[] head = { 0x46546C67, 2, total, js.len, 0x4E4F534A };
    foreach (uint32 v in head) out_b.append ({ (uint8) v, (uint8) (v >> 8), (uint8) (v >> 16), (uint8) (v >> 24) });
    out_b.append (js.data);
    uint32[] bh = { bin.len, 0x004E4942 };
    foreach (uint32 v in bh) out_b.append ({ (uint8) v, (uint8) (v >> 8), (uint8) (v >> 16), (uint8) (v >> 24) });
    out_b.append (bin.data);
    return ByteArray.free_to_bytes (out_b);
}

void test_model3d () throws Error {
    var glb = make_glb ();
    var mesh = MeshLoader.load (glb, "glb");
    check (mesh != null && mesh.triangle_count () == 12 && near (mesh.cx, 1.5) && near (mesh.tri_color[0], 0.8f), "glb cube loads with node transform and colour");
    var obj = MeshLoader.load (new Bytes ("v 0 0 0\nv 1 0 0\nv 1 1 0\nv 0 1 0\nf 1 2 3 4\n".data), "obj");
    check (obj != null && obj.triangle_count () == 2, "obj quad triangulated");
    var p = Factory.new_presentation (ThemePreset.all ()[0]);
    var m = new Model3DElement ();
    m.data = glb;
    m.format = "glb";
    m.rot_x = 20;
    m.rot_y = -30;
    m.set_geometry (100, 100, 200, 200);
    m.name = "Cube";
    p.assign_ids (m);
    p.slides[0].elements.add (m);
    var png = MeshPainter.png (m, 120, 120);
    check (png != null && png.get_size () > 200, "3d model renders");
    var surf = MeshPainter.surface (m, 64, 64);
    unowned uint8[] px = surf.get_data ();
    int stride = surf.get_stride ();
    bool painted = px[32 * stride + 32 * 4 + 3] > 0;
    check (painted, "3d model covers the centre");
    ZipReader z;
    var r = pptx_roundtrip (p, out z);
    check (zip_has_prefix (z, "ppt/media/model3d") && slide_xml (z, 1).contains ("am3d:model3d") && slide_xml (z, 1).contains ("mc:Fallback"), "3d model written with fallback");
    var rm = first_of<Model3DElement> (r.slides[0]);
    check (rm != null && rm.data != null && rm.data.compare (glb) == 0 && near (rm.rot_x, 20) && near (rm.rot_y, -30) && rm.pristine (), "3d model survives PPTX");
    rm.rot_y = 60;
    var r2 = pptx_roundtrip (r, out z);
    var rm2 = first_of<Model3DElement> (r2.slides[0]);
    check (rm2 != null && near (rm2.rot_y, 60), "rotated 3d model saved");
    var o = odp_roundtrip (p);
    var om = first_of<Model3DElement> (o.slides[0]);
    check (om != null && om.data != null && om.data.compare (glb) == 0 && near (om.rot_x, 20), "3d model through ODP");
}

void test_engine_charts () throws Error {
    var p = Factory.new_presentation (ThemePreset.all ()[0]);
    ChartKind[] kinds = { ChartKind.WATERFALL, ChartKind.FUNNEL, ChartKind.TREEMAP, ChartKind.HISTOGRAM, ChartKind.BOX_WHISKER, ChartKind.SUNBURST, ChartKind.PARETO, ChartKind.STOCK };
    foreach (var k in kinds) {
        var ch = new ChartElement (k);
        ch.sample_data ();
        ch.title = k.label ();
        ch.set_geometry (40, 40, 400, 260);
        p.assign_ids (ch);
        p.slides[0].elements.add (ch);
    }
    var surf = new Cairo.ImageSurface (Cairo.Format.ARGB32, 480, 270);
    var cr = new Cairo.Context (surf);
    cr.scale (480 / p.width, 270 / p.height);
    new Renderer ().draw_slide (cr, p, p.slides[0]);
    check (surf.status () == Cairo.Status.SUCCESS, "engine charts render");
    ZipReader z;
    var r = pptx_roundtrip (p, out z);
    check (zip_has_prefix (z, "ppt/charts/chartEx") && slide_xml (z, 1).contains ("cx1"), "extended charts written as chartex");
    var got = new Gee.ArrayList<ChartKind> ();
    foreach (var e in r.slides[0].elements) if (e is ChartElement) got.add (((ChartElement) e).chart);
    bool all = true;
    foreach (var k in kinds) if (!got.contains (k)) all = false;
    check (all, "all extended chart kinds survive PPTX (%d)".printf (got.size));
    ChartElement? wf = null;
    foreach (var e in r.slides[0].elements) if (e is ChartElement && ((ChartElement) e).chart == ChartKind.WATERFALL) wf = (ChartElement) e;
    check (wf != null && wf.series.size >= 1 && wf.series[0].values.size == 4 && near (wf.series[0].values[0], 4.3) && wf.pristine (), "waterfall data survives PPTX");
    var o = odp_roundtrip (p);
    var og = new Gee.ArrayList<ChartKind> ();
    foreach (var e in o.slides[0].elements) if (e is ChartElement) og.add (((ChartElement) e).chart);
    bool oall = true;
    foreach (var k in kinds) if (!og.contains (k)) oall = false;
    check (oall, "all extended chart kinds survive ODP");
}

void test_live () throws Error {
    var a = Factory.new_presentation (ThemePreset.all ()[0]);
    while (a.slides.size < 3) Factory.add_slide (a, a.master.layouts[1], a.slides.size);
    a.slides[0].placeholder (PlaceholderKind.TITLE).text_body ().set_plain ("One");
    a.slides[1].placeholder (PlaceholderKind.TITLE).text_body ().set_plain ("Two");
    a.slides[2].placeholder (PlaceholderKind.TITLE).text_body ().set_plain ("Three");
    var bytes = Document.serialize_as (a, "pptx");
    var b = Document.load_bytes (bytes, "b.pptx");
    check (b.slides[1].uid == a.slides[1].uid, "slide identity survives PPTX");
    b.slides[1].placeholder (PlaceholderKind.TITLE).text_body ().set_plain ("Two by B");
    var moved = b.slides.remove_at (2);
    b.slides.insert (0, moved);
    var fresh = Factory.add_slide (b, b.master.layouts[1], 3);
    fresh.placeholder (PlaceholderKind.TITLE).text_body ().set_plain ("Four");
    a.slides[0].placeholder (PlaceholderKind.TITLE).text_body ().set_plain ("One by A");
    var dirty = new Gee.ArrayList<int> ();
    dirty.add (b.slides[2].uid);
    dirty.add (fresh.uid);
    var order = new Gee.ArrayList<int> ();
    foreach (var s in b.slides) order.add (s.uid);
    var remote = Document.load_bytes (Document.serialize_as (b, "pptx"), "r.pptx");
    LiveMerge.apply (a, remote, dirty, order, false);
    check (a.slides.size == 4 && a.slides[0].title () == "Three" && a.slides[1].title () == "One by A" && a.slides[2].title () == "Two by B" && a.slides[3].title () == "Four", "live merge keeps both people's edits %s,%s,%s".printf (a.slides[0].title (), a.slides[1].title (), a.slides[2].title ()));
    var gone = new Gee.ArrayList<int> ();
    gone.add (a.slides[3].uid);
    var order2 = new Gee.ArrayList<int> ();
    for (int i = 0; i < 3; i++) order2.add (a.slides[i].uid);
    int gone_index = remote.index_of_uid (gone[0]);
    if (gone_index >= 0) remote.slides.remove_at (gone_index);
    LiveMerge.apply (a, remote, gone, order2, false);
    check (a.slides.size == 3 && a.index_of_uid (gone[0]) < 0, "live merge removes a deleted slide");
    var host = new LiveSession ("Ada");
    var ho = new Gee.ArrayList<int> ();
    foreach (var s in a.slides) ho.add (s.uid);
    host.host (new Bytes (Document.serialize_as (a, "pptx")), ho);
    check (host.link.has_prefix ("slides-live://") && host.link.contains ("key="), "live link %s".printf (host.link.substring (0, 14)));
    var guest = new LiveSession ("Grace");
    string link = host.link;
    int slash = link.index_of ("/", 14);
    string local_link = "slides-live://127.0.0.1" + link.substring (link.index_of (":", 14), slash - link.index_of (":", 14)) + link.substring (slash);
    var loop = new MainLoop ();
    bool welcomed = false, host_got = false;
    int host_peers = 0;
    guest.remote_deck.connect ((deck, d, o, design, who) => {
        if (design && o.size == 3) welcomed = true;
        if (welcomed) {
            var g = Document.load_bytes (deck.get_data (), "g.pptx");
            g.slides[0].placeholder (PlaceholderKind.TITLE).text_body ().set_plain ("Edited by Grace");
            var dd = new Gee.ArrayList<int> ();
            dd.add (g.slides[0].uid);
            var oo = new Gee.ArrayList<int> ();
            foreach (var s in g.slides) oo.add (s.uid);
            Idle.add (() => {
                guest.publish (new Bytes (Document.serialize_as (g, "pptx")), dd, oo, false);
                return Source.REMOVE;
            });
        }
    });
    host.peers_changed.connect (() => host_peers = host.peers.size);
    host.remote_deck.connect ((deck, d, o, design, who) => {
        var r = Document.load_bytes (deck.get_data (), "h.pptx");
        LiveMerge.apply (a, r, d, o, design);
        host_got = who == "Grace";
        loop.quit ();
    });
    guest.join.begin (local_link, (obj, res) => {
        try {
            guest.join.end (res);
        } catch (Error e) {
            warning ("join: %s", e.message);
            loop.quit ();
        }
    });
    Timeout.add_seconds (10, () => {
        loop.quit ();
        return Source.REMOVE;
    });
    loop.run ();
    check (welcomed && host_peers == 1, "guest joins the live session and gets the deck");
    check (host_got && a.slides[0].title () == "Edited by Grace", "host receives the guest's edit over the network");
    guest.leave ();
    host.leave ();
}

void wait_seconds (double s) {
    var loop = new MainLoop ();
    Timeout.add ((uint) (s * 1000), () => {
        loop.quit ();
        return Source.REMOVE;
    });
    loop.run ();
}

void test_capture () {
    Environment.set_variable ("SINGULARITY_SLIDES_AUDIO_SOURCE", "audiotestsrc is-live=true wave=sine", true);
    Environment.set_variable ("SINGULARITY_SLIDES_CAMERA_SOURCE", "videotestsrc is-live=true pattern=ball", true);
    check (AudioRecorder.available (), "audio recorder available with a test source");
    var rec = new AudioRecorder ();
    rec.speech_wav = true;
    check (rec.start (), "audio recording starts");
    wait_seconds (1.2);
    var wav = rec.stop ();
    unowned uint8[] w = wav != null ? wav.get_data () : new uint8[0];
    check (wav != null && w.length > 16000 && w[0] == 'R' && w[1] == 'I' && w[8] == 'W', "speech recording is a 16 kHz wav %d".printf (w.length));
    var cam = new CameraRecorder ();
    check (CameraRecorder.available () && cam.start (true), "camera recording starts");
    wait_seconds (1.5);
    var vid = cam.stop ();
    unowned uint8[] v = vid != null ? vid.get_data () : new uint8[0];
    check (vid != null && v.length > 2000 && v[0] == 0x1a && v[1] == 0x45, "camera recording is a webm video %d %s".printf (v.length, cam.error_message));
    Environment.unset_variable ("SINGULARITY_SLIDES_AUDIO_SOURCE");
    Environment.unset_variable ("SINGULARITY_SLIDES_CAMERA_SOURCE");
}

void main () {
    Intl.setlocale (LocaleCategory.ALL, "C.UTF-8");
    Intl.setlocale (LocaleCategory.NUMERIC, "it_IT.UTF-8");
    try {
        test_poi_smartart ();
        test_poi_media ();
        test_poi_comments ();
        test_features ();
        test_foreign ();
        test_diagram_engine ();
        test_outline ();
        test_player ();
        test_deck_tools ();
        test_charts ();
        test_protection ();
        test_thesaurus ();
        test_coach ();
        test_design_ideas ();
        test_model3d ();
        test_engine_charts ();
        test_live ();
        test_capture ();
    } catch (Error e) {
        error ("%s", e.message);
    }
    print ("fidelity tests passed: %d checks\n", checks);
}
