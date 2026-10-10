using Gtk;
using Singularity.Widgets;

namespace Singularity.Apps.Slides {

    public class DeckDialogs {
        public delegate void TextApply (string value);
        public delegate void SlidesApply (Gee.ArrayList<Slide> slides);

        private static string slide_label (Presentation p, int i) {
            string t = p.slides[i].title ().strip ();
            return t != "" ? _("%d. %s").printf (i + 1, t) : _("%d. Untitled Slide").printf (i + 1);
        }

        public static void ask_text (SlidesWindow win, string title, string field, string current, owned TextApply apply) {
            var dlg = Dialogs.make (win, title, 420, 280);
            var box = Dialogs.body (dlg);
            var g = new PreferencesGroup ();
            var entry = new EntryRow (field);
            entry.text = current;
            g.add_row (entry);
            box.append (g);
            Dialogs.footer (dlg, title == _("Add Section") ? _("Add") : (title == _("Save as Template") ? _("Save") : _("Rename")), () => {
                string v = entry.text.strip ();
                if (v != "") apply (v);
            });
            entry.entry_activated.connect (() => {
                string v = entry.text.strip ();
                if (v != "") apply (v);
                dlg.close ();
            });
            dlg.open_dialog ();
        }

        private static Gee.ArrayList<CheckButton> slide_checks (Presentation p, PreferencesGroup g, Gee.List<int> selected) {
            var checks = new Gee.ArrayList<CheckButton> ();
            for (int i = 0; i < p.slides.size; i++) {
                var row = new ActionRow (slide_label (p, i), p.slides[i].hidden ? _("Hidden") : null);
                var cb = new CheckButton ();
                cb.valign = Align.CENTER;
                cb.active = selected.contains (p.slides[i].uid);
                row.add_prefix (cb);
                row.activated.connect (() => cb.active = !cb.active);
                g.add_row (row);
                checks.add (cb);
            }
            return checks;
        }

        public static void choose_zoom (SlidesWindow win, ZoomKind kind) {
            var p = win.doc.pres;
            string title = kind == ZoomKind.SUMMARY ? _("Summary Zoom") : (kind == ZoomKind.SECTION ? _("Section Zoom") : _("Slide Zoom"));
            var dlg = Dialogs.make (win, title, 460, 620);
            var box = Dialogs.body (dlg);
            if (kind == ZoomKind.SECTION) {
                var g = new PreferencesGroup (_("Sections"), _("Each section gets a zoom that jumps to it and returns here"));
                var checks = new Gee.ArrayList<CheckButton> ();
                var starts = new Gee.ArrayList<Slide> ();
                for (int i = 0; i < p.slides.size; i++) {
                    if (p.slides[i].section == null) continue;
                    var row = new ActionRow (p.slides[i].section.name, _("Starts at slide %d").printf (i + 1));
                    var cb = new CheckButton ();
                    cb.valign = Align.CENTER;
                    row.add_prefix (cb);
                    row.activated.connect (() => cb.active = !cb.active);
                    g.add_row (row);
                    checks.add (cb);
                    starts.add (p.slides[i]);
                }
                if (checks.size == 0) {
                    var sp = new StatusPage ();
                    sp.icon_name = "x-office-presentation";
                    sp.title = _("No Sections");
                    sp.description = _("Add sections to the slides list first");
                    g.add_row (sp);
                }
                box.append (g);
                Dialogs.footer (dlg, _("Insert"), () => {
                    var list = new Gee.ArrayList<Slide> ();
                    for (int i = 0; i < checks.size; i++) if (checks[i].active) list.add (starts[i]);
                    win.insert_zoom (ZoomKind.SECTION, list);
                });
                dlg.open_dialog ();
                return;
            }
            var g = new PreferencesGroup (_("Slides"), kind == ZoomKind.SUMMARY ? _("A new summary slide links to each chosen slide; each starts a section") : _("Each chosen slide gets a zoom on the current slide"));
            var checks = slide_checks (p, g, new Gee.ArrayList<int> ());
            box.append (g);
            Dialogs.footer (dlg, _("Insert"), () => {
                var list = new Gee.ArrayList<Slide> ();
                for (int i = 0; i < checks.size; i++) if (checks[i].active) list.add (p.slides[i]);
                if (list.size == 0) return;
                if (kind == ZoomKind.SUMMARY) {
                    win.doc.checkpoint (_("Add Sections"));
                    if (p.slides[0].section == null && p.slides[0] != list[0]) p.slides[0].section = new SectionMark (_("Default Section"));
                    foreach (var s in list) {
                        if (s.section == null) {
                            string t = s.title ().strip ();
                            s.section = new SectionMark (t != "" ? t : _("Section %d").printf (p.slides.index_of (s) + 1));
                        }
                    }
                    win.doc.touch ();
                }
                win.insert_zoom (kind, list);
            });
            dlg.open_dialog ();
        }

        public static void custom_shows (SlidesWindow win) {
            var p = win.doc.pres;
            var dlg = Dialogs.make (win, _("Custom Shows"), 460, 560);
            var box = Dialogs.body (dlg);
            var g = new PreferencesGroup (_("Custom Shows"), _("Present a chosen set of slides in any order"));
            var add = new Button.from_icon_name ("list-add-symbolic");
            add.tooltip_text = _("New Custom Show");
            g.add_header_suffix (add);
            box.append (g);
            Dialogs.Apply refresh = null;
            refresh = () => {
                g.clear ();
                if (p.custom_shows.size == 0) {
                    var sp = new WelcomePage ();
                    sp.is_section = true;
                    sp.embedded = true;
                    sp.title = _("No Custom Shows");
                    sp.subtitle = _("Group slides for a shorter or different audience");
                    sp.add_action ("x-office-presentation", _("New Custom Show"), _("Pick slides and their order"), () => edit_show (win, null, () => refresh ()));
                    g.add_row (sp);
                    return;
                }
                foreach (var cs in p.custom_shows) {
                    var row = new ActionRow (cs.name, ngettext ("%d slide", "%d slides", cs.slides.size).printf (cs.slides.size));
                    var play = new Button.from_icon_name ("media-playback-start-symbolic");
                    play.add_css_class ("flat");
                    play.valign = Align.CENTER;
                    play.tooltip_text = _("Show");
                    var show = cs;
                    play.clicked.connect (() => {
                        dlg.close ();
                        win.start_custom_show (show.name);
                    });
                    var ed = new Button.from_icon_name ("document-edit-symbolic");
                    ed.add_css_class ("flat");
                    ed.valign = Align.CENTER;
                    ed.tooltip_text = _("Edit");
                    ed.clicked.connect (() => edit_show (win, show, () => refresh ()));
                    var copy = new Button.from_icon_name ("edit-copy-symbolic");
                    copy.add_css_class ("flat");
                    copy.valign = Align.CENTER;
                    copy.tooltip_text = _("Copy");
                    copy.clicked.connect (() => {
                        win.doc.checkpoint (_("Copy Custom Show"));
                        var c = show.clone ();
                        c.name = _("Copy of %s").printf (show.name);
                        p.custom_shows.add (c);
                        win.doc.touch ();
                        refresh ();
                    });
                    var del = new Button.from_icon_name ("user-trash-symbolic");
                    del.add_css_class ("flat");
                    del.valign = Align.CENTER;
                    del.tooltip_text = _("Remove");
                    del.clicked.connect (() => {
                        win.doc.checkpoint (_("Remove Custom Show"));
                        p.custom_shows.remove (show);
                        if (p.show_custom == show.name) p.show_custom = "";
                        win.doc.touch ();
                        refresh ();
                    });
                    row.add_suffix (play);
                    row.add_suffix (ed);
                    row.add_suffix (copy);
                    row.add_suffix (del);
                    g.add_row (row);
                }
            };
            add.clicked.connect (() => edit_show (win, null, () => refresh ()));
            refresh ();
            dlg.open_dialog ();
        }

        private static void edit_show (SlidesWindow win, CustomShow? show, owned Dialogs.Apply done) {
            var p = win.doc.pres;
            var dlg = Dialogs.make (win, show == null ? _("New Custom Show") : _("Edit Custom Show"), 460, 640);
            var box = Dialogs.body (dlg);
            var ng = new PreferencesGroup ();
            var name = new EntryRow (_("Name"));
            name.text = show != null ? show.name : _("Custom Show %d").printf (p.custom_shows.size + 1);
            ng.add_row (name);
            box.append (ng);
            var order = new Gee.ArrayList<int> ();
            if (show != null) order.add_all (show.slides);
            var og = new PreferencesGroup (_("Slides in the Show"), _("Played in this order"));
            box.append (og);
            var ag = new PreferencesGroup (_("Add Slides"));
            box.append (ag);
            Dialogs.Apply refresh = null;
            refresh = () => {
                og.clear ();
                ag.clear ();
                for (int k = 0; k < order.size; k++) {
                    int idx = p.index_of_uid (order[k]);
                    if (idx < 0) continue;
                    var row = new ActionRow (slide_label (p, idx));
                    int kk = k;
                    var up = new Button.from_icon_name ("go-up-symbolic");
                    up.add_css_class ("flat");
                    up.valign = Align.CENTER;
                    up.tooltip_text = _("Move Up");
                    up.sensitive = k > 0;
                    up.clicked.connect (() => {
                        int v = order.remove_at (kk);
                        order.insert (kk - 1, v);
                        refresh ();
                    });
                    var down = new Button.from_icon_name ("go-down-symbolic");
                    down.add_css_class ("flat");
                    down.valign = Align.CENTER;
                    down.tooltip_text = _("Move Down");
                    down.sensitive = k < order.size - 1;
                    down.clicked.connect (() => {
                        int v = order.remove_at (kk);
                        order.insert (kk + 1, v);
                        refresh ();
                    });
                    var rm = new Button.from_icon_name ("list-remove-symbolic");
                    rm.add_css_class ("flat");
                    rm.valign = Align.CENTER;
                    rm.tooltip_text = _("Remove from Show");
                    rm.clicked.connect (() => {
                        order.remove_at (kk);
                        refresh ();
                    });
                    row.add_suffix (up);
                    row.add_suffix (down);
                    row.add_suffix (rm);
                    og.add_row (row);
                }
                for (int i = 0; i < p.slides.size; i++) {
                    var row = new ActionRow (slide_label (p, i));
                    var addb = new Button.from_icon_name ("list-add-symbolic");
                    addb.add_css_class ("flat");
                    addb.valign = Align.CENTER;
                    addb.tooltip_text = _("Add to Show");
                    int uid = p.slides[i].uid;
                    addb.clicked.connect (() => {
                        order.add (uid);
                        refresh ();
                    });
                    row.add_suffix (addb);
                    ag.add_row (row);
                }
            };
            refresh ();
            Dialogs.footer (dlg, _("Save"), () => {
                string n = name.text.strip ();
                if (n == "") n = _("Custom Show");
                win.doc.checkpoint (_("Custom Show"));
                var target = show;
                if (target == null) {
                    target = new CustomShow ();
                    p.custom_shows.add (target);
                }
                if (p.show_custom == target.name) p.show_custom = n;
                target.name = n;
                target.slides.clear ();
                target.slides.add_all (order);
                win.doc.touch ();
                done ();
            });
            dlg.open_dialog ();
        }

        public static void setup_show (SlidesWindow win) {
            var p = win.doc.pres;
            var dlg = Dialogs.make (win, _("Set Up Slide Show"), 480, 700);
            var box = Dialogs.body (dlg);
            var tg = new PreferencesGroup (_("Show Type"));
            string[] kinds = { _("Presented by a Speaker (Full Screen)"), _("Browsed by an Individual (Window)"), _("Browsed at a Kiosk (Full Screen)") };
            var kind = new SelectionRow (_("Type"), kinds, kinds[p.show_kind.clamp (0, 2)]);
            tg.add_row (kind);
            box.append (tg);
            var sg = new PreferencesGroup (_("Slides"));
            string[] ranges = { _("All"), _("From and To"), _("Custom Show") };
            int cur = p.show_custom != "" ? 2 : (p.show_from > 0 ? 1 : 0);
            var range = new SelectionRow (_("Show Slides"), ranges, ranges[cur]);
            sg.add_row (range);
            var from = new SpinRow (_("From"), null, 1, double.max (p.slides.size, 1), 1, p.show_from > 0 ? p.show_from : 1);
            var to = new SpinRow (_("To"), null, 1, double.max (p.slides.size, 1), 1, p.show_to > 0 ? p.show_to : p.slides.size);
            sg.add_row (from);
            sg.add_row (to);
            string[] shows = {};
            foreach (var cs in p.custom_shows) shows += cs.name;
            SelectionRow? custom = null;
            if (shows.length > 0) {
                custom = new SelectionRow (_("Custom Show"), shows, p.show_custom != "" ? p.show_custom : shows[0]);
                sg.add_row (custom);
            }
            Dialogs.Apply sync = () => {
                from.visible = to.visible = range.current_value == ranges[1];
                if (custom != null) custom.visible = range.current_value == ranges[2];
            };
            range.selected.connect (() => sync ());
            sync ();
            box.append (sg);
            var og = new PreferencesGroup (_("Show Options"));
            var loop = new SwitchRow (_("Loop Continuously Until Esc"), null, p.loop);
            var narr = new SwitchRow (_("Play Narrations"), null, p.show_narration);
            var anim = new SwitchRow (_("Play Animations"), null, p.show_animation);
            var timings = new SwitchRow (_("Use Timings"), _("Advance slides automatically when timings are saved"), p.use_timings);
            string[] pens = { _("Red"), _("Yellow"), _("Blue"), _("Green"), _("Black"), _("White") };
            string[] pen_hex = { "#ff0000", "#ffcc00", "#0070c0", "#00b050", "#000000", "#ffffff" };
            int pc = 0;
            for (int i = 0; i < pen_hex.length; i++) if (pen_hex[i] == p.pen_color.down ()) pc = i;
            var pen = new SelectionRow (_("Pen Color"), pens, pens[pc]);
            og.add_row (loop);
            og.add_row (narr);
            og.add_row (anim);
            og.add_row (timings);
            og.add_row (pen);
            box.append (og);
            Dialogs.footer (dlg, _("Apply"), () => {
                win.doc.checkpoint (_("Set Up Slide Show"));
                for (int i = 0; i < kinds.length; i++) if (kind.current_value == kinds[i]) p.show_kind = i;
                if (range.current_value == ranges[1]) {
                    p.show_from = (int) from.spin_btn.value;
                    p.show_to = int.max ((int) to.spin_btn.value, p.show_from);
                    p.show_custom = "";
                } else if (range.current_value == ranges[2] && custom != null) {
                    p.show_custom = custom.current_value;
                    p.show_from = p.show_to = 0;
                } else {
                    p.show_from = p.show_to = 0;
                    p.show_custom = "";
                }
                p.loop = loop.active || p.show_kind == 2;
                p.show_narration = narr.active;
                p.show_animation = anim.active;
                p.use_timings = timings.active || p.show_kind == 2;
                for (int i = 0; i < pens.length; i++) if (pen.current_value == pens[i]) p.pen_color = pen_hex[i];
                win.doc.touch ();
            });
            dlg.open_dialog ();
        }

        public static void grid_settings (SlidesWindow win) {
            var p = win.doc.pres;
            var dlg = Dialogs.make (win, _("Grid and Guides"), 440, 520);
            var box = Dialogs.body (dlg);
            var g = new PreferencesGroup (_("Grid"));
            var snap = new SwitchRow (_("Snap Objects to Grid"), null, p.snap_to_grid);
            var spacing = new SpinRow (_("Spacing (points)"), null, 2, 144, 1, p.grid_spacing);
            var show = new SwitchRow (_("Display Grid on Screen"), null, p.show_grid);
            g.add_row (snap);
            g.add_row (spacing);
            g.add_row (show);
            box.append (g);
            var gg = new PreferencesGroup (_("Guides"));
            var guides = new SwitchRow (_("Display Drawing Guides"), null, p.show_guides);
            var smart = new SwitchRow (_("Display Smart Guides When Shapes Are Aligned"), null, win.canvas.snap);
            var ruler = new SwitchRow (_("Display Ruler"), null, p.show_ruler);
            gg.add_row (guides);
            gg.add_row (smart);
            gg.add_row (ruler);
            box.append (gg);
            Dialogs.footer (dlg, _("Apply"), () => {
                p.snap_to_grid = snap.active;
                p.grid_spacing = spacing.spin_btn.value;
                p.show_grid = show.active;
                p.show_guides = guides.active;
                if (p.show_guides && p.guides_x.size == 0 && p.guides_y.size == 0) {
                    p.guides_x.add (p.width / 2);
                    p.guides_y.add (p.height / 2);
                }
                p.show_ruler = ruler.active;
                win.canvas.snap = smart.active;
                win.sync_view_toggles ();
                win.canvas.queue_draw ();
            });
            dlg.open_dialog ();
        }

        public static void slide_size (SlidesWindow win) {
            var p = win.doc.pres;
            var dlg = Dialogs.make (win, _("Custom Slide Size"), 440, 460);
            var box = Dialogs.body (dlg);
            var g = new PreferencesGroup (_("Size"), _("Content is scaled to fit the new size"));
            string[] presets = { _("Custom"), _("Widescreen (13.33 × 7.5 in)"), _("Standard (10 × 7.5 in)"), _("A4 Paper (10.83 × 7.5 in)"), _("Letter Paper (10 × 7.5 in)"), _("Banner (8 × 1 in)"), _("35mm Slides (11.25 × 7.5 in)") };
            double[] pw = { 0, 960, 720, 780, 720, 576, 810 };
            double[] ph = { 0, 540, 540, 540, 540, 72, 540 };
            var preset = new SelectionRow (_("Slide Size"), presets, presets[0]);
            var width = new SpinRow (_("Width (inches)"), null, 1, 56, 0.01, p.width / 72);
            width.spin_btn.digits = 2;
            var height = new SpinRow (_("Height (inches)"), null, 1, 56, 0.01, p.height / 72);
            height.spin_btn.digits = 2;
            string[] orients = { _("Landscape"), _("Portrait") };
            var orient = new SelectionRow (_("Orientation"), orients, p.width >= p.height ? orients[0] : orients[1]);
            preset.selected.connect ((item) => {
                for (int i = 1; i < presets.length; i++) {
                    if (presets[i] == item) {
                        width.spin_btn.value = pw[i] / 72;
                        height.spin_btn.value = ph[i] / 72;
                    }
                }
            });
            orient.selected.connect ((item) => {
                double a = width.spin_btn.value, b = height.spin_btn.value;
                bool portrait = item == orients[1];
                if (portrait == (a > b)) {
                    width.spin_btn.value = b;
                    height.spin_btn.value = a;
                }
            });
            g.add_row (preset);
            g.add_row (width);
            g.add_row (height);
            g.add_row (orient);
            box.append (g);
            Dialogs.footer (dlg, _("Apply"), () => win.resize_slides (width.spin_btn.value * 72, height.spin_btn.value * 72));
            dlg.open_dialog ();
        }

        public static void variants (SlidesWindow win) {
            var p = win.doc.pres;
            var base_theme = p.master.theme;
            var dlg = Dialogs.make (win, _("Theme Variants"), 460, 560);
            var box = Dialogs.body (dlg);
            var g = new PreferencesGroup (_("Variants"), _("Alternative colors for the current theme"));
            string[] names = { _("Original"), _("Dark"), _("Warm"), _("Cool"), _("Grayscale"), _("Vivid") };
            for (int v = 0; v < names.length; v++) {
                var t = ThemeVariants.make (base_theme, v);
                var row = new ActionRow (names[v]);
                var sw = new DrawingArea ();
                sw.content_width = 120;
                sw.content_height = 20;
                sw.valign = Align.CENTER;
                sw.set_draw_func ((d, cr, w, h) => {
                    string[] keys = { "lt1", "dk1", "accent1", "accent2", "accent3", "accent4", "accent5", "accent6" };
                    double cw = w / (double) keys.length;
                    for (int k = 0; k < keys.length; k++) {
                        Rgba c;
                        if (!Rgba.parse_hex (t.scheme_hex (keys[k]), out c)) continue;
                        cr.set_source_rgb (c.r, c.g, c.b);
                        cr.rectangle (k * cw, 0, cw, h);
                        cr.fill ();
                    }
                    cr.set_source_rgba (0.5, 0.5, 0.5, 0.6);
                    cr.set_line_width (1);
                    cr.rectangle (0.5, 0.5, w - 1, h - 1);
                    cr.stroke ();
                });
                row.add_suffix (sw);
                row.activated.connect (() => {
                    win.apply_theme_colors (t);
                    dlg.close ();
                });
                g.add_row (row);
            }
            box.append (g);
            dlg.open_dialog ();
        }

        public static void embed_fonts (SlidesWindow win) {
            var p = win.doc.pres;
            var used = FontEmbed.used_fonts (p);
            var dlg = Dialogs.make (win, _("Embed Fonts"), 460, 520);
            var box = Dialogs.body (dlg);
            var g = new PreferencesGroup (_("Fonts"), _("Embedded fonts travel with the file so it looks the same on other computers"));
            var on = new SwitchRow (_("Embed Fonts in the File"), null, p.embed_fonts);
            g.add_row (on);
            box.append (g);
            var lg = new PreferencesGroup (_("Used in This Presentation"));
            foreach (string f in used) {
                bool embedded = false;
                foreach (var ef in p.fonts) if (ef.family == f) embedded = true;
                string? file = FontEmbed.find (f, false, false);
                lg.add_row (new ActionRow (f, embedded ? _("Embedded") : (file != null ? _("Available to embed") : _("Not installed"))));
            }
            box.append (lg);
            Dialogs.footer (dlg, _("Apply"), () => {
                win.doc.checkpoint (_("Embed Fonts"));
                p.embed_fonts = on.active;
                if (on.active) FontEmbed.collect (p, used);
                win.doc.touch ();
            });
            dlg.open_dialog ();
        }

        public static void accessibility (SlidesWindow win) {
            var issues = AccessibilityCheck.run (win.doc.pres);
            var dlg = Dialogs.make (win, _("Accessibility"), 480, 620);
            var box = Dialogs.body (dlg);
            if (issues.size == 0) {
                var sp = new StatusPage ();
                sp.icon_name = "object-select-symbolic";
                sp.title = _("No Accessibility Issues Found");
                sp.description = _("People with disabilities should not have difficulty reading this presentation");
                box.append (sp);
                dlg.open_dialog ();
                return;
            }
            string[] titles = { _("Errors"), _("Warnings"), _("Tips") };
            for (int sev = 0; sev < 3; sev++) {
                PreferencesGroup? g = null;
                foreach (var it in issues) {
                    if (it.severity != sev) continue;
                    if (g == null) {
                        g = new PreferencesGroup (titles[sev]);
                        box.append (g);
                    }
                    var row = new ActionRow (it.title, _("Slide %d: %s").printf (it.slide + 1, it.detail));
                    var go = new Button.from_icon_name ("go-next-symbolic");
                    go.add_css_class ("flat");
                    go.valign = Align.CENTER;
                    go.tooltip_text = _("Go to Object");
                    var issue = it;
                    go.clicked.connect (() => win.reveal_object (issue.slide, issue.element));
                    row.add_suffix (go);
                    if (issue.kind == AccessibilityCheck.Kind.ALT_TEXT) {
                        var fix = new Button.from_icon_name ("document-edit-symbolic");
                        fix.add_css_class ("flat");
                        fix.valign = Align.CENTER;
                        fix.tooltip_text = _("Add a Description");
                        fix.clicked.connect (() => {
                            ask_description (win, issue, () => row.visible = false);
                        });
                        row.add_suffix (fix);
                    }
                    g.add_row (row);
                }
            }
            dlg.open_dialog ();
        }

        private static void ask_description (SlidesWindow win, AccessibilityCheck.Issue issue, owned Dialogs.Apply done) {
            var dlg = Dialogs.make (win, _("Alt Text"), 420, 300);
            var box = Dialogs.body (dlg);
            var g = new PreferencesGroup (null, _("Describe the object for people who cannot see it"));
            var entry = new EntryRow (_("Description"));
            g.add_row (entry);
            box.append (g);
            Dialogs.footer (dlg, _("Save"), () => {
                string t = entry.text.strip ();
                if (t == "" || issue.element == null) return;
                win.doc.checkpoint (_("Alt Text"));
                issue.element.description = t;
                win.doc.touch ();
                done ();
            });
            dlg.open_dialog ();
        }

        public static void record_audio (SlidesWindow win) {
            if (!AudioRecorder.available ()) {
                win.show_error (_("Could Not Record"), _("Recording needs the GStreamer audio source and Opus or WAV encoder plugins."));
                return;
            }
            var rec = new AudioRecorder ();
            var dlg = Dialogs.make (win, _("Record Audio"), 400, 320);
            var box = Dialogs.body (dlg);
            var g = new PreferencesGroup (null, _("Record a sound clip from the microphone and insert it on the slide"));
            var name = new EntryRow (_("Name"));
            name.text = _("Recorded Sound");
            g.add_row (name);
            var status = new ActionRow (_("Ready"), "0:00");
            var btn = new Button.from_icon_name ("media-record-symbolic");
            btn.valign = Align.CENTER;
            btn.add_css_class ("circular");
            btn.tooltip_text = _("Record");
            status.add_suffix (btn);
            g.add_row (status);
            box.append (g);
            Bytes? clip = null;
            uint timer = 0;
            btn.clicked.connect (() => {
                if (!rec.recording) {
                    clip = null;
                    if (!rec.start ()) {
                        status.title = _("Could Not Record");
                        status.subtitle = rec.error_message;
                        return;
                    }
                    btn.icon_name = "media-playback-stop-symbolic";
                    btn.tooltip_text = _("Stop");
                    status.title = _("Recording");
                    timer = Timeout.add (250, () => {
                        int sec = (int) rec.elapsed;
                        status.subtitle = "%d:%02d".printf (sec / 60, sec % 60);
                        if (rec.recording) return Source.CONTINUE;
                        timer = 0;
                        return Source.REMOVE;
                    });
                } else {
                    clip = rec.stop ();
                    btn.icon_name = "media-record-symbolic";
                    btn.tooltip_text = _("Record Again");
                    status.title = clip != null ? _("Recorded") : _("Nothing Was Recorded");
                    if (clip == null && rec.error_message != "") status.subtitle = rec.error_message;
                }
            });
            dlg.close_request.connect (() => {
                if (rec.recording) rec.cancel ();
                if (timer != 0) Source.remove (timer);
                return false;
            });
            Dialogs.footer (dlg, _("Insert"), () => {
                if (rec.recording) clip = rec.stop ();
                if (clip == null) return;
                string n = name.text.strip ();
                if (n == "") n = _("Recorded Sound");
                win.insert_media_bytes (clip, n + (rec.mime == "audio/ogg" ? ".ogg" : ".wav"), false);
            });
            dlg.open_dialog ();
        }

        public static void ask_password (SlidesWindow win, string name, string? problem, owned TextApply apply) {
            var dlg = Dialogs.make (win, _("Password Required"), 420, 320);
            var box = Dialogs.body (dlg);
            var g = new PreferencesGroup (null, problem ?? _("\"%s\" is protected with a password").printf (name));
            var pw = new PasswordRow (_("Password"));
            g.add_row (pw);
            box.append (g);
            Dialogs.footer (dlg, _("Open"), () => {
                if (pw.text != "") apply (pw.text);
            });
            pw.entry_activated.connect (() => {
                if (pw.text == "") return;
                string v = pw.text;
                dlg.close ();
                apply (v);
            });
            dlg.open_dialog ();
        }

        public static void protect (SlidesWindow win) {
            var dlg = Dialogs.make (win, _("Encrypt with Password"), 440, 420);
            var box = Dialogs.body (dlg);
            var g = new PreferencesGroup (_("Password"), win.doc.password != "" ? _("The presentation is encrypted. Leave both fields empty to remove the password.") : _("Anyone who opens the presentation will need this password. It cannot be recovered if you forget it."));
            var pw = new PasswordRow (_("Password"));
            var again = new PasswordRow (_("Confirm Password"));
            g.add_row (pw);
            g.add_row (again);
            box.append (g);
            var status = new Label ("");
            status.add_css_class ("error");
            status.visible = false;
            box.append (status);
            var ok = Dialogs.footer (dlg, _("Apply"), () => {}, false);
            ok.clicked.connect (() => {
                if (pw.text != again.text) {
                    status.label = _("The passwords do not match.");
                    status.visible = true;
                    return;
                }
                win.doc.password = pw.text;
                win.doc.modified = true;
                win.content_edited ();
                win.add_toast (new Toast (pw.text != "" ? _("The presentation will be encrypted when saved") : _("The password will be removed when saved")));
                dlg.close ();
            });
            dlg.open_dialog ();
        }

        public static void versions (SlidesWindow win) {
            var dlg = Dialogs.make (win, _("Version History"), 520, 620);
            var box = Dialogs.body (dlg);
            string? path = win.doc.path;
            var items = path != null ? VersionStore.list (path) : new Gee.ArrayList<string> ();
            if (items.size == 0) {
                var empty = new StatusPage ();
                empty.icon_name = "document-open-recent-symbolic";
                empty.title = _("No Earlier Versions");
                empty.description = path == null ? _("Save the presentation to start keeping versions") : _("Each time the presentation is saved, the previous version is kept here");
                box.append (empty);
                dlg.open_dialog ();
                return;
            }
            var g = new PreferencesGroup (Path.get_basename (path), _("Open a version to look at it, or restore it"));
            foreach (string item in items) {
                var t = VersionStore.time_of (item);
                string file = item;
                string label = t != null ? t.format ("%x %X") : Path.get_basename (item);
                string sub = "";
                Presentation? pres = null;
                try {
                    uint8[] data;
                    FileUtils.get_data (file, out data);
                    pres = Document.load_bytes (Document.decrypt (data, win.doc.password), file);
                    sub = ngettext ("%d slide", "%d slides", pres.slides.size).printf (pres.slides.size);
                } catch (Error e) {
                    sub = _("Protected with a different password");
                }
                var row = new ActionRow (label, sub);
                if (pres != null && pres.slides.size > 0) {
                    var thumb = new Picture ();
                    thumb.can_shrink = true;
                    thumb.set_size_request (96, 54);
                    var surf = new Renderer ().thumbnail (pres, pres.slides[0], 192);
                    thumb.paintable = ThumbCache.texture_of (surf);
                    row.add_prefix (thumb);
                }
                var open = new Button.with_label (_("Open"));
                open.valign = Align.CENTER;
                open.sensitive = pres != null;
                open.clicked.connect (() => {
                    try {
                        var d = Document.open (file, win.doc.password);
                        d.path = null;
                        var nw = new SlidesWindow (win.app);
                        nw.present ();
                        nw.load_document (d);
                        dlg.close ();
                    } catch (Error e) {
                        win.show_error (_("Could Not Open"), e.message);
                    }
                });
                var restore = new Button.with_label (_("Restore"));
                restore.valign = Align.CENTER;
                restore.sensitive = pres != null;
                restore.clicked.connect (() => {
                    try {
                        VersionStore.keep_previous (path);
                        File.new_for_path (file).copy (File.new_for_path (path), FileCopyFlags.OVERWRITE);
                        var d = Document.open (path, win.doc.password);
                        win.load_document (d);
                        win.add_toast (new Toast (_("Version restored")));
                        dlg.close ();
                    } catch (Error e) {
                        win.show_error (_("Could Not Restore"), e.message);
                    }
                });
                row.add_suffix (open);
                row.add_suffix (restore);
                g.add_row (row);
            }
            box.append (g);
            dlg.open_dialog ();
        }

        public static void coach_report (SlidesWindow win, CoachReport r) {
            var dlg = Dialogs.make (win, _("Rehearsal Report"), 520, 680);
            var box = Dialogs.body (dlg);
            var g = new PreferencesGroup (_("Summary"));
            int mins = (int) (r.seconds / 60), secs = (int) r.seconds % 60;
            g.add_row (new ActionRow (_("Time Spent"), "%d:%02d".printf (mins, secs)));
            g.add_row (new ActionRow (_("Pace"), r.words > 0 ? _("%.0f words per minute").printf (r.wpm) : r.pace_label ()));
            g.add_row (new ActionRow (_("Advice"), r.pace_label ()));
            int filler_total = 0;
            foreach (var v in r.fillers.values) filler_total += v;
            var fr = new ActionRow (_("Filler Words"), filler_total == 0 ? _("None, well done") : ngettext ("%d filler word", "%d filler words", filler_total).printf (filler_total));
            g.add_row (fr);
            g.add_row (new ActionRow (_("Reading from the Slides"), r.read_ratio > 0.35 ? _("You read %.0f%% of what you said from the slides; try to talk around them").printf (r.read_ratio * 100) : _("%.0f%% of your words repeat the slide text").printf (r.read_ratio * 100)));
            box.append (g);
            if (r.fillers.size > 0) {
                var fg = new PreferencesGroup (_("Filler Words"));
                foreach (var e in r.fillers.entries) fg.add_row (new ActionRow ("\u201c%s\u201d".printf (e.key), ngettext ("%d time", "%d times", e.value).printf (e.value)));
                box.append (fg);
            }
            if (r.repeated.size > 0) {
                var rg = new PreferencesGroup (_("Repetitive Language"), _("Phrases you used three or more times"));
                foreach (string rep in r.repeated) rg.add_row (new ActionRow (rep));
                box.append (rg);
            }
            var sg = new PreferencesGroup (_("Slides"));
            foreach (var cs in r.slides) {
                var row = new ExpanderRow (slide_label (win.doc.pres, cs.index.clamp (0, win.doc.pres.slides.size - 1)), "%ds, %s".printf ((int) cs.seconds, cs.words > 0 ? _("%.0f words per minute").printf (cs.wpm) : _("no speech")));
                var t = new Label (cs.transcript != "" ? cs.transcript : _("Nothing was recognised on this slide"));
                t.wrap = true;
                t.xalign = 0;
                t.selectable = true;
                t.margin_start = t.margin_end = t.margin_top = t.margin_bottom = 12;
                row.add_row (t);
                sg.add_row (row);
            }
            box.append (sg);
            dlg.open_dialog ();
        }

        public static void designer (SlidesWindow win) {
            var slide = win.doc.slide;
            if (slide == null) return;
            var ideas = DesignIdeas.suggest (win.doc.pres, slide);
            var dlg = Dialogs.make (win, _("Design Ideas"), 560, 660);
            var box = Dialogs.body (dlg);
            var g = new PreferencesGroup (null, _("Arrangements for the content of this slide"));
            box.append (g);
            var flow = new FlowBox ();
            flow.selection_mode = SelectionMode.NONE;
            flow.max_children_per_line = 2;
            flow.min_children_per_line = 2;
            flow.column_spacing = 12;
            flow.row_spacing = 12;
            flow.homogeneous = true;
            foreach (var idea in ideas) {
                var b = new Button ();
                b.add_css_class ("flat");
                var v = new Box (Orientation.VERTICAL, 6);
                var pic = new Picture ();
                pic.can_shrink = true;
                pic.set_size_request (240, 135);
                pic.paintable = ThumbCache.texture_of (new Renderer ().thumbnail (win.doc.pres, idea.slide, 480));
                pic.add_css_class ("slides-thumb");
                v.append (pic);
                var l = new Label (idea.name);
                v.append (l);
                b.child = v;
                var chosen = idea;
                b.clicked.connect (() => {
                    win.apply_design (chosen.slide);
                    dlg.close ();
                });
                flow.append (b);
            }
            box.append (flow);
            dlg.open_dialog ();
        }

        public static void record_screen (SlidesWindow win) {
            var rec = new ScreenRecorder ();
            var dlg = Dialogs.make (win, _("Screen Recording"), 420, 340);
            var box = Dialogs.body (dlg);
            var g = new PreferencesGroup (null, _("Choose a screen or window to record, then insert the recording on the slide"));
            var audio = new SwitchRow (_("Record Audio"), null, true);
            g.add_row (audio);
            var status = new ActionRow (_("Ready"), "0:00");
            var btn = new Button.from_icon_name ("media-record-symbolic");
            btn.valign = Align.CENTER;
            btn.add_css_class ("circular");
            btn.tooltip_text = _("Record");
            status.add_suffix (btn);
            g.add_row (status);
            box.append (g);
            Bytes? clip = null;
            string mime = "video/webm";
            uint timer = 0;
            btn.clicked.connect (() => {
                if (!rec.recording) {
                    rec.with_audio = audio.active;
                    btn.sensitive = false;
                    status.title = _("Choose What to Record");
                    rec.start.begin ((o, r) => {
                        btn.sensitive = true;
                        if (!rec.start.end (r)) {
                            status.title = _("Could Not Record");
                            status.subtitle = rec.error_message;
                            return;
                        }
                        btn.icon_name = "media-playback-stop-symbolic";
                        btn.tooltip_text = _("Stop");
                        status.title = _("Recording");
                        timer = Timeout.add (250, () => {
                            int sec = (int) rec.elapsed;
                            status.subtitle = "%d:%02d".printf (sec / 60, sec % 60);
                            if (rec.recording) return Source.CONTINUE;
                            timer = 0;
                            return Source.REMOVE;
                        });
                    });
                } else {
                    clip = rec.stop (out mime);
                    btn.icon_name = "media-record-symbolic";
                    btn.tooltip_text = _("Record Again");
                    status.title = clip != null ? _("Recorded") : _("Nothing Was Recorded");
                    if (clip == null && rec.error_message != "") status.subtitle = rec.error_message;
                }
            });
            dlg.close_request.connect (() => {
                if (rec.recording) {
                    string m;
                    rec.stop (out m);
                }
                if (timer != 0) Source.remove (timer);
                return false;
            });
            Dialogs.footer (dlg, _("Insert"), () => {
                if (rec.recording) clip = rec.stop (out mime);
                if (clip == null) return;
                win.insert_media_bytes (clip, _("Screen Recording") + (mime == "video/mp4" ? ".mp4" : ".webm"), true);
            });
            dlg.open_dialog ();
        }

        private static void live_people (SlidesWindow win, Box box, Singularity.Widgets.AppDialog dlg, bool inviting) {
            if (!Singularity.Collab.Client.installed ()) return;
            var client = Singularity.Collab.Client.get_default ();
            var g = new PreferencesGroup (inviting ? _("Invite More People") : _("People Nearby"),
                _("They are asked to accept, then they edit with you in real time"));
            box.prepend (g);
            client.refresh_people.begin ((o, res) => {
                client.refresh_people.end (res);
                int shown = 0;
                foreach (var p in client.people) {
                    if (!p.can_join) continue;
                    var person = p;
                    var row = new ActionRow (p.name, p.provider_name, p.icon_name);
                    row.activatable = true;
                    row.activated.connect (() => {
                        dlg.close ();
                        win.start_live_collab (person);
                    });
                    g.add_row (row);
                    shown++;
                }
                if (shown == 0) {
                    var none = new ActionRow (_("Nobody Is Reachable"), _("Pair a computer in Settings, Connected Devices"), "network-offline-symbolic");
                    none.activatable = false;
                    g.add_row (none);
                }
            });
        }

        public static void live (SlidesWindow win) {
            var dlg = Dialogs.make (win, _("Edit Together"), 500, 560);
            var box = Dialogs.body (dlg);
            if (win.live != null && win.live.collab) {
                var cg = new PreferencesGroup (win.live.hosting ? _("Sharing This Presentation") : _("Joined a Presentation"), _("Shared with people nearby"));
                box.append (cg);
                var cp = new PreferencesGroup (_("People"));
                cp.add_row (new ActionRow (CommentsPanel.me (), _("You")));
                foreach (var p in win.live.peers.values) {
                    int i = p.slide >= 0 ? win.doc.pres.index_of_uid (p.slide) : -1;
                    cp.add_row (new ActionRow (p.name, i >= 0 ? _("On slide %d").printf (i + 1) : null));
                }
                box.append (cp);
                if (win.live.hosting) live_people (win, box, dlg, true);
                Dialogs.footer (dlg, win.live.hosting ? _("Stop Sharing") : _("Leave"), () => win.stop_live ());
                dlg.open_dialog ();
                return;
            }
            if (win.live != null) {
                var g = new PreferencesGroup (win.live.hosting ? _("Sharing This Presentation") : _("Joined a Presentation"), _("Everyone with the link can edit at the same time"));
                var link = new ActionRow (_("Link"), win.live.link);
                var copy = new Button.from_icon_name ("edit-copy-symbolic");
                copy.valign = Align.CENTER;
                copy.tooltip_text = _("Copy Link");
                copy.clicked.connect (() => {
                    win.get_clipboard ().set_text (win.live.link);
                    win.add_toast (new Toast (_("Link copied")));
                });
                link.add_suffix (copy);
                g.add_row (link);
                box.append (g);
                var pg = new PreferencesGroup (_("People"));
                pg.add_row (new ActionRow (CommentsPanel.me (), _("You")));
                foreach (var p in win.live.peers.values) {
                    int i = p.slide >= 0 ? win.doc.pres.index_of_uid (p.slide) : -1;
                    pg.add_row (new ActionRow (p.name, i >= 0 ? _("On slide %d").printf (i + 1) : null));
                }
                box.append (pg);
                Dialogs.footer (dlg, win.live.hosting ? _("Stop Sharing") : _("Leave"), () => win.stop_live ());
                dlg.open_dialog ();
                return;
            }
            live_people (win, box, dlg, false);
            var hg = new PreferencesGroup (_("Share"), _("Let people on this network edit this presentation with you in real time"));
            var start = new ActionRow (_("Start a Live Session"), _("You get a link to send to others"));
            var sb = new Button.with_label (_("Start"));
            sb.valign = Align.CENTER;
            sb.add_css_class ("suggested-action");
            sb.clicked.connect (() => {
                dlg.close ();
                win.start_live (true, "");
                live (win);
            });
            start.add_suffix (sb);
            hg.add_row (start);
            box.append (hg);
            var jg = new PreferencesGroup (_("Join"), _("Paste a link someone sent you"));
            var entry = new EntryRow (_("Live Link"));
            jg.add_row (entry);
            box.append (jg);
            Dialogs.footer (dlg, _("Join"), () => {
                string l = entry.text.strip ();
                if (l != "") win.start_live (false, l);
            });
            dlg.open_dialog ();
        }
    }
}
