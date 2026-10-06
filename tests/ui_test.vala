using Singularity.Apps.Slides;

void pump () {
    var ctx = MainContext.default ();
    for (int i = 0; i < 200 && ctx.pending (); i++) ctx.iteration (false);
}

void churn () {
    string[] junk = {};
    for (int i = 0; i < 3000; i++) junk += string.nfill (i % 40 + 1, (char) ('a' + i % 26));
    junk = {};
}

Singularity.Widgets.SelectionRow? find_row (Gtk.Widget root, string title) {
    var row = root as Singularity.Widgets.SelectionRow;
    if (row != null && row.title == title && row.get_mapped ()) return row;
    for (var c = root.get_first_child (); c != null; c = c.get_next_sibling ()) {
        var r = find_row (c, title);
        if (r != null) return r;
    }
    return null;
}

ChartElement? find_chart (Document doc, out int index) {
    index = -1;
    for (int i = 0; i < doc.pres.slides.size; i++) {
        foreach (var e in doc.pres.slides[i].elements) {
            if (e is ChartElement) {
                index = i;
                return (ChartElement) e;
            }
        }
    }
    return null;
}

ChartElement select_chart (SlidesWindow win) {
    int index;
    var ch = find_chart (win.doc, out index);
    assert (ch != null);
    win.go_to_slide (index);
    pump ();
    win.canvas.select (ch);
    pump ();
    return ch;
}

void choose (SlidesWindow win, string title, string label) {
    var row = find_row (win, title);
    assert (row != null);
    churn ();
    row.selected (label);
    pump ();
    churn ();
}

void cycle_kinds (SlidesWindow win) {
    ChartKind[] kinds = { ChartKind.COLUMN, ChartKind.BAR, ChartKind.LINE, ChartKind.AREA, ChartKind.PIE, ChartKind.DOUGHNUT, ChartKind.SCATTER };
    var ch = select_chart (win);
    for (int round = 0; round < 2; round++) {
        foreach (var k in kinds) {
            choose (win, _("Type"), k.label ());
            assert (ch.chart == k);
            if (round == 1) {
                win.canvas.selection_changed ();
                pump ();
            }
            if (round == 1 && !k.is_radial () && k != ChartKind.SCATTER) {
                choose (win, _("Grouping"), _("Stacked"));
                assert (ch.grouping == ChartGrouping.STACKED);
                choose (win, _("Grouping"), _("Clustered"));
            }
            win.canvas.selection_changed ();
            pump ();
        }
    }
    choose (win, _("Legend"), _("Top"));
    assert (ch.legend == LegendPosition.TOP);
    win.run ("undo");
    pump ();
    ch = select_chart (win);
    choose (win, _("Type"), ChartKind.PIE.label ());
    assert (ch.chart == ChartKind.PIE);
    win.run ("undo");
    pump ();
    win.run ("redo");
    pump ();
    ch = select_chart (win);
    assert (ch.chart == ChartKind.PIE);
    foreach (var k in kinds) {
        choose (win, _("Type"), k.label ());
        assert (ch.chart == k);
    }
}

int main (string[] args) {
    Intl.setlocale (LocaleCategory.ALL, "C.UTF-8");
    string? display = Environment.get_variable ("SLIDES_UI_TEST_DISPLAY");
    if (display == null || display == "") {
        print ("ui test skipped: set SLIDES_UI_TEST_DISPLAY to a private X display\n");
        return 77;
    }
    Environment.set_variable ("DISPLAY", display, true);
    Environment.unset_variable ("WAYLAND_DISPLAY");
    Environment.set_variable ("GDK_BACKEND", "x11", true);
    if (!Gtk.init_check ()) {
        print ("ui test skipped: no display\n");
        return 77;
    }
    var app = new SlidesApp ();
    app.flags = ApplicationFlags.HANDLES_OPEN | ApplicationFlags.NON_UNIQUE;
    try {
        app.register (null);
    } catch (Error e) {
        print ("ui test skipped: %s\n", e.message);
        return 77;
    }
    var win = new SlidesWindow (app);
    win.present ();
    foreach (string id in new string[] { "review", "status", "pitch" }) {
        win.load_document (new Document (Templates.build (id)));
        pump ();
        cycle_kinds (win);
        try {
            var bytes = Document.serialize (win.doc.pres, FileKind.PPTX);
            win.load_document (new Document (Document.load_bytes (bytes, "round.pptx")));
            pump ();
            cycle_kinds (win);
            bytes = Document.serialize (win.doc.pres, FileKind.ODP);
            win.load_document (new Document (Document.load_bytes (bytes, "round.odp")));
            pump ();
            cycle_kinds (win);
        } catch (Error e) {
            error ("%s", e.message);
        }
    }
    win.destroy ();
    print ("ui tests passed\n");
    return 0;
}
