using Gtk;
using Singularity.Widgets;

namespace Singularity.Apps.Slides {

    public class FindPopover : Popover {
        private SlidesWindow win;
        private Entry find_entry;
        private Entry replace_entry;
        private CheckButton match_case;
        private CheckButton whole;
        private Label status;
        private TextSpot? last = null;

        public FindPopover (SlidesWindow win, bool replace) {
            this.win = win;
            has_arrow = false;
            var box = new Box (Orientation.VERTICAL, 8);
            box.margin_top = box.margin_bottom = box.margin_start = box.margin_end = 10;
            box.width_request = 320;
            find_entry = new Entry ();
            find_entry.placeholder_text = _("Find");
            find_entry.primary_icon_name = "edit-find-symbolic";
            find_entry.activate.connect (() => find (true));
            find_entry.changed.connect (() => {
                last = null;
                update_count ();
            });
            replace_entry = new Entry ();
            replace_entry.placeholder_text = _("Replace with");
            replace_entry.activate.connect (() => replace_one ());
            box.append (find_entry);
            box.append (replace_entry);
            var opts = new Box (Orientation.HORIZONTAL, 10);
            match_case = new CheckButton.with_label (_("Match case"));
            whole = new CheckButton.with_label (_("Whole words"));
            match_case.toggled.connect (update_count);
            whole.toggled.connect (update_count);
            opts.append (match_case);
            opts.append (whole);
            box.append (opts);
            var buttons = new Box (Orientation.HORIZONTAL, 6);
            var prev = new Button.from_icon_name ("go-up-symbolic");
            prev.tooltip_text = _("Previous");
            prev.clicked.connect (() => find (false));
            var next = new Button.from_icon_name ("go-down-symbolic");
            next.tooltip_text = _("Next");
            next.clicked.connect (() => find (true));
            var rep = new Button.with_label (_("Replace"));
            rep.clicked.connect (() => replace_one ());
            var rep_all = new Button.with_label (_("Replace All"));
            rep_all.add_css_class ("suggested-action");
            rep_all.clicked.connect (() => replace_all ());
            buttons.append (prev);
            buttons.append (next);
            var spacer = new Box (Orientation.HORIZONTAL, 0);
            spacer.hexpand = true;
            buttons.append (spacer);
            buttons.append (rep);
            buttons.append (rep_all);
            box.append (buttons);
            status = new Label ("");
            status.add_css_class ("dim-label");
            status.add_css_class ("caption");
            status.halign = Align.START;
            box.append (status);
            child = box;
            map.connect (() => {
                if (replace) replace_entry.grab_focus ();
                else find_entry.grab_focus ();
            });
        }

        private bool is_word_char (unichar c) {
            return c.isalnum () || c == '_';
        }

        private Gee.ArrayList<TextSpot> matches () {
            var list = new Gee.ArrayList<TextSpot> ();
            string needle = find_entry.text;
            if (needle == "" || win.doc == null) return list;
            bool mc = match_case.active;
            string n = mc ? needle : needle.down ();
            TextWalker.walk (win.doc.pres, (spot, text) => {
                string hay = mc ? text : text.down ();
                if (hay.length != text.length) hay = text;
                int pos = 0;
                while (true) {
                    int i = hay.index_of (n, pos);
                    if (i < 0) break;
                    pos = i + n.length;
                    if (whole.active) {
                        if (i > 0) {
                            unichar before = text.substring (0, i).reverse ().get_char (0);
                            if (is_word_char (before)) continue;
                        }
                        if (pos < text.length && is_word_char (text.get_char (pos))) continue;
                    }
                    var m = new TextSpot (spot.slide, spot.element);
                    m.row = spot.row;
                    m.col = spot.col;
                    m.notes = spot.notes;
                    m.body = spot.body;
                    m.start = text.substring (0, i).char_count ();
                    m.length = needle.char_count ();
                    list.add (m);
                }
            });
            return list;
        }

        private void update_count () {
            var list = matches ();
            if (find_entry.text == "") status.label = "";
            else if (list.size == 0) status.label = _("No matches");
            else status.label = ngettext ("%d match", "%d matches", list.size).printf (list.size);
        }

        private void find (bool forward) {
            var list = matches ();
            update_count ();
            if (list.size == 0) return;
            int idx = -1;
            if (last != null) {
                for (int i = 0; i < list.size; i++) {
                    var m = list[i];
                    if (m.slide == last.slide && m.element == last.element && m.row == last.row && m.col == last.col && m.notes == last.notes && m.start == last.start) idx = i;
                }
            }
            if (idx < 0) {
                idx = forward ? 0 : list.size - 1;
                for (int i = 0; i < list.size; i++) {
                    if (list[i].slide >= win.doc.current_slide) {
                        idx = forward ? i : int.max (i - 1, 0);
                        break;
                    }
                }
            } else {
                idx = forward ? (idx + 1) % list.size : (idx - 1 + list.size) % list.size;
            }
            last = list[idx];
            win.reveal_spot (last);
            status.label = _("Match %d of %d").printf (idx + 1, list.size);
        }

        private void replace_one () {
            if (last == null) {
                find (true);
                return;
            }
            if (win.replace_spot (last, replace_entry.text)) {
                last = null;
                find (true);
            }
        }

        private void replace_all () {
            string needle = find_entry.text;
            if (needle == "" || win.doc == null) return;
            var list = matches ();
            if (list.size == 0) return;
            win.canvas.commit_edit ();
            string rep = replace_entry.text;
            win.doc.checkpoint (_("Replace All"));
            for (int i = list.size - 1; i >= 0; i--) SpotEdit.replace (win.doc.pres, list[i], rep);
            win.doc.touch ();
            win.content_edited ();
            win.refresh_thumbnails ();
            status.label = ngettext ("Replaced %d match", "Replaced %d matches", list.size).printf (list.size);
            last = null;
        }
    }

    public class ChartDataEditor : Object {
        public Gee.ArrayList<string> cats = new Gee.ArrayList<string> ();
        public Gee.ArrayList<ChartSeries> series = new Gee.ArrayList<ChartSeries> ();
        public ScrolledWindow scroller;
        private Grid grid;
        private Entry[,] cells = new Entry[0, 0];

        public ChartDataEditor (ChartElement ch) {
            grid = new Grid ();
            grid.row_spacing = 4;
            grid.column_spacing = 4;
            grid.add_css_class ("slides-data-grid");
            grid.margin_top = 8;
            grid.margin_bottom = 8;
            grid.margin_start = 8;
            grid.margin_end = 8;
            scroller = new ScrolledWindow ();
            scroller.vscrollbar_policy = PolicyType.NEVER;
            scroller.child = grid;
            cats.add_all (ch.categories);
            foreach (var s in ch.series) series.add (s.clone ());
            int ncat = cats.size;
            foreach (var s in series) ncat = int.max (ncat, s.values.size);
            while (cats.size < ncat) cats.add (_("Category %d").printf (cats.size + 1));
            rebuild ();
        }

        public void read () {
            if (cells.length[0] == 0) return;
            for (int r = 0; r < cats.size && r + 1 < cells.length[0]; r++) cats[r] = cells[r + 1, 0].text;
            for (int c = 0; c < series.size && c + 1 < cells.length[1]; c++) {
                series[c].name = cells[0, c + 1].text;
                series[c].values.clear ();
                for (int r = 0; r < cats.size && r + 1 < cells.length[0]; r++) {
                    double v = 0;
                    string t = cells[r + 1, c + 1].text.strip ().replace (",", ".");
                    if (!double.try_parse (t, out v)) v = 0;
                    series[c].values.add (v);
                }
            }
        }

        public void rebuild () {
            Widget? child;
            while ((child = grid.get_first_child ()) != null) grid.remove (child);
            cells = new Entry[cats.size + 1, series.size + 1];
            var corner = new Label (_("Category"));
            corner.add_css_class ("dim-label");
            grid.attach (corner, 0, 0);
            cells[0, 0] = new Entry ();
            for (int c = 0; c < series.size; c++) {
                var e = new Entry ();
                e.text = series[c].name;
                e.add_css_class ("heading");
                e.width_chars = 10;
                cells[0, c + 1] = e;
                grid.attach (e, c + 1, 0);
            }
            for (int r = 0; r < cats.size; r++) {
                var ce = new Entry ();
                ce.text = cats[r];
                ce.width_chars = 12;
                cells[r + 1, 0] = ce;
                grid.attach (ce, 0, r + 1);
                for (int c = 0; c < series.size; c++) {
                    var e = new Entry ();
                    e.text = Num.fmt (series[c].value_at (r));
                    e.width_chars = 8;
                    e.xalign = 1;
                    e.input_purpose = InputPurpose.NUMBER;
                    cells[r + 1, c + 1] = e;
                    grid.attach (e, c + 1, r + 1);
                }
            }
        }

        public void add_category () {
            read ();
            cats.add (_("Category %d").printf (cats.size + 1));
            foreach (var s in series) s.values.add (0);
            rebuild ();
        }

        public void remove_category () {
            read ();
            if (cats.size <= 1) return;
            cats.remove_at (cats.size - 1);
            foreach (var s in series) if (s.values.size > cats.size) s.values.remove_at (s.values.size - 1);
            rebuild ();
        }

        public void add_series () {
            read ();
            var s = new ChartSeries (_("Series %d").printf (series.size + 1));
            for (int i = 0; i < cats.size; i++) s.values.add (0);
            series.add (s);
            rebuild ();
        }

        public void remove_series () {
            read ();
            if (series.size <= 1) return;
            series.remove_at (series.size - 1);
            rebuild ();
        }

        public void load_text (string text) {
            var lines = new Gee.ArrayList<string> ();
            foreach (string l in text.split ("\n")) if (l.strip () != "") lines.add (l.replace ("\r", ""));
            if (lines.size < 2) return;
            string sep = lines[0].contains ("\t") ? "\t" : (lines[0].contains (";") ? ";" : ",");
            string[] head = lines[0].split (sep);
            cats.clear ();
            series.clear ();
            for (int c = 1; c < head.length; c++) series.add (new ChartSeries (head[c].strip ()));
            for (int r = 1; r < lines.size; r++) {
                string[] f = lines[r].split (sep);
                cats.add (f.length > 0 ? f[0].strip () : "");
                for (int c = 1; c < head.length; c++) {
                    double v = 0;
                    if (c < f.length) double.try_parse (f[c].strip ().replace (",", "."), out v);
                    series[c - 1].values.add (v);
                }
            }
            rebuild ();
        }
    }

    public class Dialogs {
        public delegate void Apply ();

        public static AppDialog make (SlidesWindow win, string title, int width, int height) {
            var dlg = new AppDialog ((Gtk.Application) win.application, true);
            dlg.set_title (title);
            dlg.transient_for = win;
            dlg.set_default_size (width, height);
            return dlg;
        }

        public static Box body (AppDialog dlg) {
            var scroll = new ScrolledWindow ();
            scroll.hscrollbar_policy = PolicyType.NEVER;
            scroll.vexpand = true;
            var box = new Box (Orientation.VERTICAL, 14);
            box.margin_start = box.margin_end = 18;
            box.margin_top = 6;
            box.margin_bottom = 12;
            scroll.child = box;
            dlg.content_box.append (scroll);
            return box;
        }

        public static Button footer (AppDialog dlg, string label, owned Apply apply, bool close_after = true) {
            var bar = new Box (Orientation.HORIZONTAL, 8);
            bar.margin_start = bar.margin_end = 18;
            bar.margin_bottom = 16;
            bar.margin_top = 4;
            var spacer = new Box (Orientation.HORIZONTAL, 0);
            spacer.hexpand = true;
            bar.append (spacer);
            var cancel = dlg.add_cancel_button ();
            var ok = new Button.with_label (label);
            ok.add_css_class ("suggested-action");
            ok.clicked.connect (() => {
                apply ();
                if (close_after) dlg.close ();
            });
            bar.append (cancel);
            bar.append (ok);
            dlg.content_box.append (bar);
            return ok;
        }

        public static Gtk.Widget template_card (Template t, int width, owned Apply activate) {
            var b = new Button ();
            b.add_css_class ("flat");
            b.add_css_class ("slides-template-card");
            b.halign = Align.CENTER;
            b.valign = Align.START;
            b.tooltip_text = t.description;
            var box = new Box (Orientation.VERTICAL, 6);
            var pic = new Picture ();
            pic.add_css_class ("slides-template-thumb");
            pic.can_shrink = true;
            pic.content_fit = ContentFit.FILL;
            pic.set_size_request (width, (int) (width * 9 / 16.0));
            pic.overflow = Overflow.HIDDEN;
            var p = Templates.build (t.id);
            var r = new Renderer ();
            pic.paintable = ThumbCache.texture_of (r.thumbnail (p, p.slides[0], width));
            pic.halign = Align.START;
            box.append (pic);
            var name = new Label (t.name);
            name.add_css_class ("caption");
            name.add_css_class ("heading");
            name.xalign = 0;
            box.append (name);
            b.child = box;
            b.clicked.connect (() => activate ());
            return b;
        }

        public static void templates (SlidesWindow win) {
            var dlg = make (win, _("New from Template"), 760, 700);
            var box = body (dlg);
            var g = new PreferencesGroup (_("Templates"), _("Every template can be restyled later with any theme"));
            var flow = new FlowBox ();
            flow.selection_mode = SelectionMode.NONE;
            flow.max_children_per_line = 3;
            flow.min_children_per_line = 2;
            flow.column_spacing = 12;
            flow.row_spacing = 12;
            flow.margin_top = 8;
            flow.margin_bottom = 8;
            flow.margin_start = 8;
            flow.margin_end = 8;
            string aspect = win.app.get_string ("default-aspect", "16:9");
            var size = new SelectionRow (_("Slide Size"), { _("Widescreen (16:9)"), _("Standard (4:3)"), "16:10" }, aspect == "4:3" ? _("Standard (4:3)") : (aspect == "16:10" ? "16:10" : _("Widescreen (16:9)")));
            foreach (var t in Templates.all ()) {
                var tt = t;
                flow.append (template_card (t, 200, () => {
                    string a = size.current_value == _("Standard (4:3)") ? "4:3" : (size.current_value == "16:10" ? "16:10" : "16:9");
                    win.new_from_template (tt.id, a);
                    dlg.close ();
                }));
            }
            g.add_row (flow);
            box.append (g);
            var personal = PersonalTemplates.list ();
            if (personal.size > 0) {
                var pg = new PreferencesGroup (_("Personal"), _("Templates you saved from your own presentations"));
                var pflow = new FlowBox ();
                pflow.selection_mode = SelectionMode.NONE;
                pflow.max_children_per_line = 3;
                pflow.min_children_per_line = 2;
                pflow.column_spacing = 12;
                pflow.row_spacing = 12;
                pflow.margin_top = pflow.margin_bottom = pflow.margin_start = pflow.margin_end = 8;
                foreach (string path in personal) {
                    Presentation? pres = null;
                    try {
                        uint8[] data;
                        FileUtils.get_data (path, out data);
                        pres = Document.load_bytes (data, path);
                    } catch (Error e) {
                        continue;
                    }
                    if (pres.slides.size == 0) continue;
                    var b = new Button ();
                    b.add_css_class ("flat");
                    b.add_css_class ("slides-template-card");
                    var v = new Box (Orientation.VERTICAL, 6);
                    var pic = new Picture ();
                    pic.can_shrink = true;
                    pic.set_size_request (200, (int) (200 * pres.height / pres.width));
                    pic.add_css_class ("slides-template-thumb");
                    pic.paintable = ThumbCache.texture_of (new Renderer ().thumbnail (pres, pres.slides[0], 400));
                    v.append (pic);
                    string nm = Path.get_basename (path);
                    int dot = nm.last_index_of (".");
                    v.append (new Label (dot > 0 ? nm.substring (0, dot) : nm));
                    b.child = v;
                    string file = path;
                    b.clicked.connect (() => {
                        try {
                            var d = Document.open (file);
                            d.path = null;
                            win.load_or_open_new (d);
                            dlg.close ();
                        } catch (Error e) {
                            win.show_error (_("Could Not Open"), e.message);
                        }
                    });
                    pflow.append (b);
                }
                pg.add_row (pflow);
                box.append (pg);
            }
            var sg = new PreferencesGroup (_("Format"));
            sg.add_row (size);
            box.append (sg);
            var bar = new Box (Orientation.HORIZONTAL, 8);
            bar.margin_start = bar.margin_end = 18;
            bar.margin_bottom = 16;
            var spacer = new Box (Orientation.HORIZONTAL, 0);
            spacer.hexpand = true;
            bar.append (spacer);
            bar.append (dlg.add_cancel_button ());
            dlg.content_box.append (bar);
            dlg.open_dialog ();
        }

        public static void insert_table (SlidesWindow win) {
            var dlg = make (win, _("Insert Table"), 400, 400);
            var box = body (dlg);
            var g = new PreferencesGroup (_("Size"), _("You can add rows and columns later"));
            var rows = new SpinRow (_("Rows"), null, 1, 100, 1, 4);
            var cols = new SpinRow (_("Columns"), null, 1, 30, 1, 3);
            g.add_row (rows);
            g.add_row (cols);
            box.append (g);
            footer (dlg, _("Insert"), () => win.insert_table ((int) rows.value, (int) cols.value));
            dlg.open_dialog ();
        }

        public static void chart_data (SlidesWindow win, ChartElement ch) {
            var dlg = make (win, _("Chart Data"), 720, 660);
            var box = body (dlg);
            var g = new PreferencesGroup (_("Data"), ch.chart.is_radial () ? _("The first series gives the slice sizes; each row is a slice") : _("Each row is a category, each column is a series"));
            box.append (g);
            var editor = new ChartDataEditor (ch);
            g.add_row (editor.scroller);
            var edits = new PreferencesGroup (_("Rows and Series"));
            var row_tools = new ActionRow (_("Categories"));
            var add_row = new Button.from_icon_name ("list-add-symbolic");
            add_row.tooltip_text = _("Add Category");
            add_row.valign = Align.CENTER;
            add_row.clicked.connect (() => editor.add_category ());
            var del_row = new Button.from_icon_name ("list-remove-symbolic");
            del_row.tooltip_text = _("Remove Last Category");
            del_row.valign = Align.CENTER;
            del_row.clicked.connect (() => editor.remove_category ());
            row_tools.add_suffix (add_row);
            row_tools.add_suffix (del_row);
            edits.add_row (row_tools);
            var col_tools = new ActionRow (_("Series"));
            var add_col = new Button.from_icon_name ("list-add-symbolic");
            add_col.tooltip_text = _("Add Series");
            add_col.valign = Align.CENTER;
            add_col.clicked.connect (() => editor.add_series ());
            var del_col = new Button.from_icon_name ("list-remove-symbolic");
            del_col.tooltip_text = _("Remove Last Series");
            del_col.valign = Align.CENTER;
            del_col.clicked.connect (() => editor.remove_series ());
            col_tools.add_suffix (add_col);
            col_tools.add_suffix (del_col);
            edits.add_row (col_tools);
            var paste = new ActionRow (_("Paste from Spreadsheet"), _("Tab-separated text with a header row"));
            var paste_btn = new Button.from_icon_name ("edit-paste-symbolic");
            paste_btn.valign = Align.CENTER;
            paste_btn.tooltip_text = _("Paste from Spreadsheet");
            paste_btn.clicked.connect (() => {
                var cb = dlg.get_clipboard ();
                cb.read_text_async.begin (null, (o, res) => {
                    try {
                        string? text = cb.read_text_async.end (res);
                        if (text != null) editor.load_text (text);
                    } catch (Error e) {
                    }
                });
            });
            paste.add_suffix (paste_btn);
            edits.add_row (paste);
            box.append (edits);
            footer (dlg, _("Apply"), () => {
                editor.read ();
                win.doc.checkpoint (_("Chart Data"));
                ch.categories.clear ();
                ch.categories.add_all (editor.cats);
                ch.series.clear ();
                ch.series.add_all (editor.series);
                win.doc.touch ();
                win.content_edited ();
                win.canvas.queue_draw ();
            });
            dlg.open_dialog ();
        }

        public static void export_pdf (SlidesWindow win) {
            var dlg = make (win, _("Export as PDF"), 440, 480);
            var box = body (dlg);
            var g = new PreferencesGroup (_("Layout"), _("What each page of the PDF contains"));
            string[] layouts = {};
            foreach (var w in PrintWhat.ALL) layouts += w.label ();
            var layout = new SelectionRow (_("Pages"), layouts, layouts[0]);
            g.add_row (layout);
            var hidden = new SwitchRow (_("Include Hidden Slides"), null, false);
            g.add_row (hidden);
            var comments = new SwitchRow (_("Include Comments"), _("A page with the comments after each commented slide"), false);
            g.add_row (comments);
            box.append (g);
            footer (dlg, _("Export"), () => {
                int k = 0;
                for (int i = 0; i < layouts.length; i++) if (layouts[i] == layout.current_value) k = i;
                win.export_pdf.begin (PrintWhat.ALL[k], hidden.active, comments.active);
            });
            dlg.open_dialog ();
        }

        public static void export_video (SlidesWindow win) {
            var dlg = make (win, _("Export as Video"), 460, 560);
            var box = body (dlg);
            var g = new PreferencesGroup (_("Video"), _("The slideshow with its transitions, animations and narration"));
            string[] formats = {};
            ShowFormat[] kinds = {};
            if (VideoEncoder.available (VideoEncoder.Container.MP4)) {
                formats += _("MP4 Video");
                kinds += ShowFormat.MP4;
            }
            if (VideoEncoder.available (VideoEncoder.Container.WEBM)) {
                formats += _("WebM Video");
                kinds += ShowFormat.WEBM;
            }
            formats += _("Animated GIF");
            kinds += ShowFormat.GIF;
            var fmt = new SelectionRow (_("Format"), formats, formats[0]);
            g.add_row (fmt);
            string[] sizes = { _("Full HD (1920 wide)"), _("HD (1280 wide)"), _("Standard (854 wide)"), _("Small (640 wide)") };
            int[] widths = { 1920, 1280, 854, 640 };
            var size = new SelectionRow (_("Quality"), sizes, sizes[1]);
            g.add_row (size);
            var per = new SpinRow (_("Seconds on Each Slide"), _("Used when a slide has no recorded timing"), 1, 120, 1, 5);
            g.add_row (per);
            var timings = new SwitchRow (_("Use Recorded Timings and Narration"), null, true);
            g.add_row (timings);
            box.append (g);
            footer (dlg, _("Export"), () => {
                int fi = 0, si = 1;
                for (int i = 0; i < formats.length; i++) if (formats[i] == fmt.current_value) fi = i;
                for (int i = 0; i < sizes.length; i++) if (sizes[i] == size.current_value) si = i;
                win.export_video.begin (kinds[fi], widths[si], per.value, timings.active);
            });
            dlg.open_dialog ();
        }

        public static void remove_background (SlidesWindow win, ImageElement img) {
            var src = ImageCache.surface (img.data);
            if (src == null) return;
            int maxw = 520;
            double k = double.min (1, (double) maxw / src.get_width ());
            var small = new Cairo.ImageSurface (Cairo.Format.ARGB32, int.max (1, (int) (src.get_width () * k)), int.max (1, (int) (src.get_height () * k)));
            var scr = new Cairo.Context (small);
            scr.scale (k, k);
            scr.set_source_surface (src, 0, 0);
            scr.paint ();
            var dlg = make (win, _("Remove Background"), 600, 640);
            var box = body (dlg);
            var g = new PreferencesGroup (_("Preview"), _("The checkered area becomes transparent"));
            var pic = new Picture ();
            pic.can_shrink = true;
            pic.set_size_request (-1, 320);
            g.add_row (pic);
            var tol = new SpinRow (_("Tolerance"), _("Higher removes more colors similar to the edges"), 1, 60, 1, 14);
            g.add_row (tol);
            box.append (g);
            Cairo.ImageSurface? result = null;
            Dialogs.Apply refresh = () => {
                result = BackgroundRemover.run (small, tol.value / 100);
                if (result == null) return;
                var view = new Cairo.ImageSurface (Cairo.Format.ARGB32, result.get_width (), result.get_height ());
                var vcr = new Cairo.Context (view);
                for (int y = 0; y < result.get_height (); y += 10) {
                    for (int x = 0; x < result.get_width (); x += 10) {
                        vcr.rectangle (x, y, 10, 10);
                        double c = ((x / 10 + y / 10) % 2 == 0) ? 0.85 : 0.65;
                        vcr.set_source_rgb (c, c, c);
                        vcr.fill ();
                    }
                }
                vcr.set_source_surface (result, 0, 0);
                vcr.paint ();
                pic.paintable = ThumbCache.texture_of (view);
            };
            refresh ();
            tol.spin_btn.value_changed.connect (() => refresh ());
            footer (dlg, _("Remove Background"), () => {
                var full = BackgroundRemover.run (src, tol.value / 100);
                if (full == null) return;
                var data = BackgroundRemover.png (full);
                win.doc.checkpoint (_("Remove Background"));
                img.data = data;
                img.mime = "image/png";
                win.doc.touch ();
                win.content_edited ();
            });
            dlg.open_dialog ();
        }

        public static void export_images (SlidesWindow win) {
            var dlg = make (win, _("Export Slides as Images"), 440, 460);
            var box = body (dlg);
            var g = new PreferencesGroup (_("Images"), _("One file per slide in the folder you choose"));
            var fmt = new SelectionRow (_("Format"), { "PNG", "JPEG" }, "PNG");
            g.add_row (fmt);
            var width = new SpinRow (_("Width in Pixels"), null, 320, 7680, 160, win.app.get_int ("export-width", 1920));
            g.add_row (width);
            var hidden = new SwitchRow (_("Include Hidden Slides"), null, false);
            g.add_row (hidden);
            box.append (g);
            footer (dlg, _("Export"), () => win.export_images.begin (fmt.current_value == "JPEG" ? "jpg" : "png", (int) width.value, hidden.active));
            dlg.open_dialog ();
        }

        public static void properties (SlidesWindow win) {
            var p = win.doc.pres.properties;
            var dlg = make (win, _("Properties"), 460, 600);
            var box = body (dlg);
            var g = new PreferencesGroup (_("Document"), _("Stored in the file and shown by other apps"));
            var title = new EntryRow (_("Title"));
            title.text = p.title;
            var author = new EntryRow (_("Author"));
            author.text = p.author;
            var subject = new EntryRow (_("Subject"));
            subject.text = p.subject;
            var keywords = new EntryRow (_("Keywords"));
            keywords.text = p.keywords;
            g.add_row (title);
            g.add_row (author);
            g.add_row (subject);
            g.add_row (keywords);
            box.append (g);
            var s = new PreferencesGroup (_("Statistics"));
            int words = 0;
            TextWalker.walk (win.doc.pres, (spot, text) => {
                foreach (string w in text.split_set (" \n\t\v")) if (w.strip () != "") words++;
            });
            s.add_row (new ActionRow (_("Slides"), win.doc.pres.slides.size.to_string ()));
            s.add_row (new ActionRow (_("Words"), words.to_string ()));
            s.add_row (new ActionRow (_("Slide Size"), "%s, %s × %s pt".printf (win.doc.pres.aspect_label (), Num.fmt (Math.round (win.doc.pres.width)), Num.fmt (Math.round (win.doc.pres.height)))));
            box.append (s);
            footer (dlg, _("Save"), () => {
                win.doc.checkpoint (_("Properties"));
                p.title = title.text;
                p.author = author.text;
                p.subject = subject.text;
                p.keywords = keywords.text;
                win.doc.touch ();
            });
            dlg.open_dialog ();
        }

        public static void hyperlink (SlidesWindow win, string current, owned SpotApply apply) {
            var dlg = make (win, _("Insert Hyperlink"), 440, 340);
            var box = body (dlg);
            var g = new PreferencesGroup (_("Link"), _("A web address or an email address"));
            var url = new EntryRow (_("Address"));
            url.text = current;
            g.add_row (url);
            box.append (g);
            footer (dlg, _("Apply"), () => {
                string u = url.text.strip ();
                if (u != "" && !u.contains (":")) u = u.contains ("@") ? "mailto:" + u : "https://" + u;
                apply (u);
            });
            dlg.open_dialog ();
        }

        public delegate void SpotApply (string value);

        public static void spelling (SlidesWindow win) {
            var checker = Singularity.Text.SpellChecker.get_default ();
            if (!checker.available) {
                win.show_error (_("Spelling Unavailable"), _("No dictionary is installed for the current language."));
                return;
            }
            var dlg = make (win, _("Check Spelling"), 480, 620);
            var box = body (dlg);
            var g = new PreferencesGroup (_("Not in Dictionary"));
            var word = new Label ("");
            word.add_css_class ("title-2");
            word.xalign = 0;
            word.margin_top = 8;
            word.margin_bottom = 4;
            word.margin_start = 12;
            var context = new Label ("");
            context.add_css_class ("dim-label");
            context.wrap = true;
            context.xalign = 0;
            context.margin_bottom = 8;
            context.margin_start = 12;
            context.margin_end = 12;
            var wbox = new Box (Orientation.VERTICAL, 0);
            wbox.append (word);
            wbox.append (context);
            g.add_row (wbox);
            box.append (g);
            var sg = new PreferencesGroup (_("Suggestions"));
            var list = new ListBox ();
            list.add_css_class ("navigation-sidebar");
            sg.add_row (list);
            var change_to = new EntryRow (_("Change To"));
            sg.add_row (change_to);
            box.append (sg);
            var ignored = new Gee.HashSet<string> ();
            TextSpot? current = null;
            string current_word = "";
            int skip = 0;
            Apply? advance = null;
            advance = () => {
                current = null;
                int seen = 0;
                TextWalker.walk (win.doc.pres, (spot, text) => {
                    if (current != null) return;
                    int i = 0;
                    unichar c;
                    int start = -1;
                    int ci = 0, cstart = 0;
                    while (true) {
                        int prev = i;
                        bool more = text.get_next_char (ref i, out c);
                        bool letter = more && (c.isalpha () || c == '\'');
                        if (letter && start < 0) {
                            start = prev;
                            cstart = ci;
                        }
                        if (!letter && start >= 0) {
                            string w = text.substring (start, prev - start).strip ();
                            while (w.has_suffix ("'")) w = w.substring (0, w.length - 1);
                            if (w.char_count () > 1 && !ignored.contains (w) && !checker.check (w)) {
                                if (seen++ >= skip) {
                                    current = new TextSpot (spot.slide, spot.element);
                                    current.row = spot.row;
                                    current.col = spot.col;
                                    current.notes = spot.notes;
                                    current.body = spot.body;
                                    current.start = cstart;
                                    current.length = w.char_count ();
                                    current_word = w;
                                    context.label = text.length > 160 ? text.substring (0, text.index_of_nth_char (int.min (text.char_count (), 150))) + "…" : text;
                                    return;
                                }
                            }
                            start = -1;
                        }
                        if (!more) break;
                        ci++;
                    }
                });
                Widget? child;
                while ((child = list.get_first_child ()) != null) list.remove (child);
                if (current == null) {
                    word.label = _("Spelling Check Complete");
                    context.label = _("No other misspelled words were found.");
                    change_to.text = "";
                    return;
                }
                word.label = current_word;
                string[] sugg = checker.suggest (current_word, 6);
                change_to.text = sugg.length > 0 ? sugg[0] : current_word;
                foreach (string s in sugg) {
                    var l = new Label (s);
                    l.xalign = 0;
                    l.margin_top = l.margin_bottom = 4;
                    l.margin_start = 8;
                    list.append (l);
                }
                win.reveal_spot (current);
            };
            list.row_activated.connect ((row) => change_to.text = ((Label) row.child).label);
            list.row_selected.connect ((row) => {
                if (row != null) change_to.text = ((Label) row.child).label;
            });
            var bar = new Box (Orientation.HORIZONTAL, 6);
            bar.margin_start = bar.margin_end = 18;
            bar.margin_bottom = 16;
            var ignore = new Button.with_label (_("Ignore"));
            ignore.clicked.connect (() => {
                skip++;
                advance ();
            });
            var ignore_all = new Button.with_label (_("Ignore All"));
            ignore_all.clicked.connect (() => {
                ignored.add (current_word);
                advance ();
            });
            var add = new Button.with_label (_("Add"));
            add.tooltip_text = _("Add to Dictionary");
            add.clicked.connect (() => {
                if (current_word != "") checker.add_to_dictionary (current_word);
                advance ();
            });
            var change = new Button.with_label (_("Change"));
            change.add_css_class ("suggested-action");
            change.clicked.connect (() => {
                if (current == null) return;
                win.canvas.commit_edit ();
                win.doc.checkpoint (_("Spelling"));
                SpotEdit.replace (win.doc.pres, current, change_to.text);
                win.doc.touch ();
                win.content_edited ();
                advance ();
            });
            var spacer = new Box (Orientation.HORIZONTAL, 0);
            spacer.hexpand = true;
            var close = new Button.with_label (_("Close"));
            dlg.set_cancel_button (close);
            close.clicked.connect (() => dlg.close ());
            bar.append (close);
            bar.append (spacer);
            bar.append (ignore);
            bar.append (ignore_all);
            bar.append (add);
            bar.append (change);
            dlg.content_box.append (bar);
            advance ();
            dlg.open_dialog ();
        }

        public static void keep_ink (SlidesWindow win, SlideShow show) {
            if (!show.has_ink ()) return;
            var dlg = new ConfirmDialog (win.app, _("Keep Your Ink Annotations?"), "x-office-presentation",
                _("The pen and highlighter drawings can be added to the slides as ink you can move, recolour or delete."),
                _("Keep"), ConfirmDialog.ActionStyle.SUGGESTED);
            dlg.transient_for = win;
            dlg.response.connect ((r) => {
                if (r != ConfirmDialog.Response.PRIMARY) return;
                win.doc.checkpoint (_("Keep Ink Annotations"));
                foreach (var e in show.ink.entries) {
                    if (e.key >= win.doc.pres.slides.size || e.value.size == 0) continue;
                    var ink = new InkElement ();
                    foreach (var st in e.value) ink.strokes.add (st.clone ());
                    ink.fit ();
                    ink.name = _("Ink Annotation");
                    win.doc.pres.assign_ids (ink);
                    win.doc.pres.slides[e.key].elements.add (ink);
                }
                win.doc.touch ();
                win.content_edited ();
            });
            dlg.present ();
        }

        public static void keep_timings (SlidesWindow win, SlideShow show) {
            if (show.rehearsed.size == 0) return;
            double total = 0;
            foreach (var v in show.rehearsed.values) total += v;
            int t = (int) total;
            var dlg = new ConfirmDialog (win.app, _("Keep the New Slide Timings?"), "x-office-presentation",
                _("The slideshow took %d:%02d. Use these timings to advance the slides automatically?").printf (t / 60, t % 60),
                _("Keep Timings"), ConfirmDialog.ActionStyle.SUGGESTED);
            dlg.transient_for = win;
            dlg.response.connect ((r) => {
                if (r != ConfirmDialog.Response.PRIMARY) return;
                win.doc.checkpoint (_("Rehearse Timings"));
                foreach (var e in show.rehearsed.entries) {
                    if (e.key < win.doc.pres.slides.size) win.doc.pres.slides[e.key].transition.advance_after = Math.round (e.value * 10) / 10;
                }
                win.doc.pres.use_timings = true;
                win.doc.touch ();
                win.content_edited ();
            });
            dlg.present ();
        }
    }
}
