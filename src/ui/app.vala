using Gtk;

namespace Singularity.Apps.Slides {

    public class SlidesApp : Singularity.Application {
        public GLib.Settings? settings = null;

        public SlidesApp () {
            Object (application_id: "dev.sinty.slides", flags: ApplicationFlags.HANDLES_OPEN);
            add_main_option ("new", 0, OptionFlags.NONE, OptionArg.NONE, _("Start a new presentation"), null);
        }

        protected override int handle_local_options (VariantDict options) {
            if (!options.contains ("new")) return -1;
            try {
                register (null);
            } catch (Error e) {
                warning ("slides: %s", e.message);
                return 1;
            }
            activate_action ("new", null);
            return get_is_remote () ? 0 : -1;
        }

        public string get_string (string key, string fallback) {
            if (settings == null) return fallback;
            return settings.get_string (key);
        }

        public bool get_bool (string key, bool fallback) {
            if (settings == null) return fallback;
            return settings.get_boolean (key);
        }

        public int get_int (string key, int fallback) {
            if (settings == null) return fallback;
            return settings.get_int (key);
        }

        protected override void startup () {
            base.startup ();
            var source = SettingsSchemaSource.get_default ();
            if (source != null && source.lookup ("dev.sinty.slides", true) != null) settings = new GLib.Settings ("dev.sinty.slides");
            about_description = _("Create and present slideshows");
            IconTheme.get_for_display (Gdk.Display.get_default ()).add_resource_path ("/dev/sinty/slides/icons");
            add_app_css (CSS);
            Singularity.Text.SpellIntegration.install (this);

            var new_action = new SimpleAction ("new", null);
            new_action.activate.connect (() => {
                var w = get_active_window () as SlidesWindow;
                if (w != null && w.doc == null) w.new_presentation ();
                else {
                    var nw = new SlidesWindow (this);
                    nw.present ();
                    nw.new_presentation ();
                }
            });
            add_action (new_action);
            var template_action = new SimpleAction ("new-from-template", null);
            template_action.activate.connect (() => {
                var w = get_active_window () as SlidesWindow;
                if (w == null) {
                    w = new SlidesWindow (this);
                    w.present ();
                }
                Dialogs.templates (w);
            });
            add_action (template_action);
            var open_action = new SimpleAction ("open", null);
            open_action.activate.connect (() => {
                var w = get_active_window () as SlidesWindow;
                if (w == null) {
                    w = new SlidesWindow (this);
                    w.present ();
                }
                choose_file (w);
            });
            add_action (open_action);
            var open_online = new SimpleAction ("open-online", null);
            open_online.activate.connect (() => {
                var w = get_active_window () as SlidesWindow;
                if (w == null) {
                    w = new SlidesWindow (this);
                    w.present ();
                }
                CloudActions.open.begin (w, (f) => open_file (f, w));
            });
            add_action (open_online);
            var quit = new SimpleAction ("quit", null);
            quit.activate.connect (() => {
                foreach (var w in get_windows ()) w.close ();
            });
            add_action (quit);
            var settings_action = new SimpleAction ("settings", null);
            settings_action.activate.connect (() => {
                try {
                    Singularity.Shell.ShellService shell = Bus.get_proxy_sync (BusType.SESSION, "dev.sinty.desktop", "/dev/sinty/Shell");
                    shell.open_app_settings ("dev.sinty.slides");
                } catch (Error e) {
                    warning ("Failed to open settings: %s", e.message);
                }
            });
            add_action (settings_action);
            build_menu ();
            string[,] accels = {
                { "app.quit", "<Control>q" }, { "app.new", "<Control>n" }, { "app.open", "<Control>o" },
                { "app.new-from-template", "<Control><Shift>n" }, { "app.settings", "<Control>comma" },
                { "win.save", "<Control>s" }, { "win.save-as", "<Control><Shift>s" }, { "win.print", "<Control>p" },
                { "win.export-pdf", "<Control><Shift>e" }, { "win.close-doc", "<Control>w" }, { "win.close", "<Control><Shift>w" },
                { "win.undo", "<Control>z" }, { "win.cut", "<Control>x" }, { "win.copy", "<Control>c" }, { "win.paste", "<Control>v" },
                { "win.paste-style", "<Control><Shift>v" }, { "win.duplicate", "<Control>d" }, { "win.select-all", "<Control>a" },
                { "win.find", "<Control>f" }, { "win.replace", "<Control>h" }, { "win.spelling", "F7" },
                { "win.new-slide", "<Control>m" }, { "win.duplicate-slide", "<Control><Shift>d" }, { "win.hide-slide", "<Control><Shift>h" },
                { "win.insert-text", "<Control><Shift>t" }, { "win.insert-image", "<Control><Shift>i" }, { "win.insert-equation", "<Alt>equal" }, { "win.insert-link", "<Control>k" },
                { "win.bold", "<Control>b" }, { "win.italic", "<Control>i" }, { "win.underline", "<Control>u" },
                { "win.strike", "<Control><Shift>x" }, { "win.align-left", "<Control>l" }, { "win.align-center", "<Control>e" },
                { "win.align-right", "<Control>r" }, { "win.align-justify", "<Control>j" },
                { "win.font-bigger", "<Control><Shift>greater" }, { "win.font-smaller", "<Control><Shift>less" },
                { "win.indent-more", "<Alt><Shift>Right" }, { "win.indent-less", "<Alt><Shift>Left" },
                { "win.group", "<Control>g" }, { "win.ungroup", "<Control><Shift>g" },
                { "win.bring-front", "<Control><Shift>bracketright" }, { "win.bring-forward", "<Control>bracketright" },
                { "win.send-backward", "<Control>bracketleft" }, { "win.send-back", "<Control><Shift>bracketleft" },
                { "win.play-start", "F5" }, { "win.play-current", "<Shift>F5" }, { "win.presenter", "<Alt>F5" },
                { "win.rehearse", "<Control><Alt>r" }, { "win.sidebar", "F9" }, { "win.notes", "<Control><Alt>n" },
                { "win.inspector", "<Control><Alt>i" }, { "win.animations", "<Control><Alt>a" },
                { "win.view-normal", "<Control><Alt>1" }, { "win.view-sorter", "<Control><Alt>2" }, { "win.view-master", "<Control><Alt>3" },
                { "win.zoom-fit", "<Control>0" }, { "win.zoom-actual", "<Control><Alt>0" }
            };
            for (int i = 0; i < accels.length[0]; i++) set_accels_for_action (accels[i, 0], { accels[i, 1] });
            set_accels_for_action ("win.redo", { "<Control><Shift>z", "<Control>y" });
            set_accels_for_action ("win.zoom-in", { "<Control>plus", "<Control>equal" });
            set_accels_for_action ("win.zoom-out", { "<Control>minus" });
        }

        private static GLib.Menu section (string[,] items) {
            var m = new GLib.Menu ();
            for (int i = 0; i < items.length[0]; i++) m.append (items[i, 0], items[i, 1]);
            return m;
        }

        private static GLib.Menu submenu_section (string label, GLib.Menu sub) {
            var m = new GLib.Menu ();
            m.append_submenu (label, sub);
            return m;
        }

        private void build_menu () {
            var menu = new GLib.Menu ();

            var file = new GLib.Menu ();
            file.append_section (null, section ({ { _("New"), "app.new" }, { _("New from Template…"), "app.new-from-template" }, { _("Open…"), "app.open" }, { _("Open from Online Account…"), "app.open-online" } }));
            file.append_section (null, section ({ { _("Save"), "win.save" }, { _("Save As…"), "win.save-as" }, { _("Save as Template…"), "win.save-template" }, { _("Save to Online Account…"), "win.save-online" } }));
            var export = section ({ { _("PDF…"), "win.export-pdf" }, { _("Video or Animated GIF…"), "win.export-video" }, { _("Current Slide as Image…"), "win.export-image" }, { _("All Slides as Images…"), "win.export-images" }, { _("Current Slide as SVG…"), "win.export-svg" } });
            export.append_section (null, section ({ { _("PowerPoint…"), "win.export-pptx" }, { _("PowerPoint Show…"), "win.export-ppsx" }, { _("PowerPoint Template…"), "win.export-potx" }, { _("OpenDocument…"), "win.export-odp" }, { _("OpenDocument Template…"), "win.export-otp" }, { _("Outline as Rich Text…"), "win.export-rtf" } }));
            var export_section = submenu_section (_("Export"), export);
            export_section.append (_("Print…"), "win.print");
            export_section.append (_("Share…"), "win.share");
            file.append_section (null, export_section);
            file.append_section (null, section ({ { _("Properties…"), "win.properties" }, { _("Encrypt with Password…"), "win.protect" }, { _("Version History…"), "win.version-history" } }));
            file.append_section (null, section ({ { _("Close Presentation"), "win.close-doc" } }));
            file.append_section (null, section ({ { _("Close Window"), "win.close" }, { _("Quit"), "app.quit" } }));
            menu.append_submenu (_("File"), file);

            var edit = new GLib.Menu ();
            edit.append_section (null, section ({ { _("Undo"), "win.undo" }, { _("Redo"), "win.redo" } }));
            edit.append_section (null, section ({ { _("Cut"), "win.cut" }, { _("Copy"), "win.copy" }, { _("Paste"), "win.paste" }, { _("Paste and Match Style"), "win.paste-style" }, { _("Duplicate"), "win.duplicate" }, { _("Delete"), "win.delete" } }));
            edit.append_section (null, section ({ { _("Select All"), "win.select-all" }, { _("Find"), "win.find" }, { _("Find and Replace"), "win.replace" }, { _("Check Spelling…"), "win.spelling" } }));
            edit.append_section (null, section ({ { _("Settings"), "app.settings" } }));
            menu.append_submenu (_("Edit"), edit);

            var view = new GLib.Menu ();
            view.append_section (null, section ({ { _("Normal"), "win.view-normal" }, { _("Outline"), "win.outline" }, { _("Slide Sorter"), "win.view-sorter" }, { _("Master Slides"), "win.view-master" } }));
            view.append_section (null, section ({ { _("Slides Sidebar"), "win.sidebar" }, { _("Speaker Notes"), "win.notes" }, { _("Format Panel"), "win.inspector" }, { _("Animation Pane"), "win.animations" }, { _("Comments"), "win.comments" } }));
            var show = section ({ { _("Ruler"), "win.show-ruler" }, { _("Gridlines"), "win.show-grid" }, { _("Guides"), "win.show-guides" }, { _("Smart Guides"), "win.guides" }, { _("Snap to Grid"), "win.snap-grid" } });
            show.append_section (null, section ({ { _("Add Vertical Guide"), "win.add-guide-v" }, { _("Add Horizontal Guide"), "win.add-guide-h" }, { _("Grid and Guides…"), "win.grid-settings" } }));
            view.append_section (null, submenu_section (_("Show"), show));
            view.append_section (null, section ({ { _("Zoom In"), "win.zoom-in" }, { _("Zoom Out"), "win.zoom-out" }, { _("Fit Slide"), "win.zoom-fit" }, { _("Actual Size"), "win.zoom-actual" } }));
            menu.append_submenu (_("View"), view);

            var insert = new GLib.Menu ();
            insert.append_section (null, section ({ { _("New Slide"), "win.new-slide" }, { _("Duplicate Slide"), "win.duplicate-slide" } }));
            var shapes = new GLib.Menu ();
            ShapeKind[] kinds = { ShapeKind.RECT, ShapeKind.ROUND_RECT, ShapeKind.ELLIPSE, ShapeKind.TRIANGLE, ShapeKind.DIAMOND, ShapeKind.PENTAGON, ShapeKind.HEXAGON, ShapeKind.STAR5, ShapeKind.ARROW_RIGHT, ShapeKind.CHEVRON, ShapeKind.CALLOUT, ShapeKind.HEART, ShapeKind.CLOUD, ShapeKind.PLUS, ShapeKind.LINE };
            foreach (var k in kinds) {
                var item = new GLib.MenuItem (k.label (), null);
                item.set_action_and_target_value ("win.insert-shape", new Variant.string (k.to_ooxml ()));
                shapes.append_item (item);
            }
            var charts = new GLib.Menu ();
            ChartKind[] ck = { ChartKind.COLUMN, ChartKind.BAR, ChartKind.LINE, ChartKind.AREA, ChartKind.PIE, ChartKind.DOUGHNUT, ChartKind.SCATTER, ChartKind.BUBBLE, ChartKind.RADAR, ChartKind.STOCK, ChartKind.HISTOGRAM, ChartKind.PARETO, ChartKind.BOX_WHISKER, ChartKind.WATERFALL, ChartKind.FUNNEL, ChartKind.TREEMAP, ChartKind.SUNBURST };
            foreach (var k in ck) {
                var item = new GLib.MenuItem (k.label (), null);
                item.set_action_and_target_value ("win.insert-chart", new Variant.int32 ((int) k));
                charts.append_item (item);
            }
            var objects = section ({ { _("Text Box"), "win.insert-text" }, { _("Image…"), "win.insert-image" }, { _("Icons…"), "win.insert-icons" }, { _("Stock Images…"), "win.insert-stock" }, { _("3D Model…"), "win.insert-model" }, { _("SmartArt…"), "win.insert-smartart" }, { _("Equation…"), "win.insert-equation" }, { _("Table…"), "win.insert-table" } });
            shapes.append_section (null, section ({ { _("All Shapes…"), "win.insert-shapes" } }));
            objects.append_submenu (_("Shape"), shapes);
            objects.append_submenu (_("Chart"), charts);
            insert.append_section (null, objects);
            var media = section ({ { _("Video…"), "win.insert-video" }, { _("Audio…"), "win.insert-audio" }, { _("Record Audio…"), "win.record-audio" }, { _("Screen Recording…"), "win.record-screen" } });
            var zoom = section ({ { _("Summary Zoom…"), "win.insert-zoom-summary" }, { _("Section Zoom…"), "win.insert-zoom-section" }, { _("Slide Zoom…"), "win.insert-zoom-slide" } });
            var mz = new GLib.Menu ();
            mz.append_submenu (_("Media"), media);
            mz.append_submenu (_("Zoom"), zoom);
            insert.append_section (null, mz);
            insert.append_section (null, section ({ { _("Hyperlink or Action…"), "win.insert-link" }, { _("Comment"), "win.new-comment" }, { _("Slide Number"), "win.insert-slide-number" }, { _("Date and Time"), "win.insert-date" }, { _("Header and Footer…"), "win.header-footer" } }));
            var phs = new GLib.Menu ();
            string[,] ph_items = { { _("Content"), "object" }, { _("Text"), "text" }, { _("Picture"), "picture" }, { _("Chart"), "chart" }, { _("Table"), "table" }, { _("SmartArt"), "smartart" }, { _("Media"), "media" } };
            for (int i = 0; i < ph_items.length[0]; i++) {
                var item = new GLib.MenuItem (ph_items[i, 0], null);
                item.set_action_and_target_value ("win.insert-placeholder", new Variant.string (ph_items[i, 1]));
                phs.append_item (item);
            }
            var master = section ({ { _("Insert Slide Master"), "win.new-master" }, { _("Insert Layout"), "win.new-layout" }, { _("Duplicate Layout"), "win.duplicate-layout" }, { _("Delete Layout"), "win.delete-layout" } });
            master.append_submenu (_("Placeholder"), phs);
            insert.append_section (null, submenu_section (_("Slide Master"), master));
            menu.append_submenu (_("Insert"), insert);

            var draw = new GLib.Menu ();
            draw.append_section (null, section ({ { _("Select"), "win.draw-select" }, { _("Pen"), "win.draw-pen" }, { _("Highlighter"), "win.draw-highlighter" }, { _("Eraser"), "win.draw-eraser" } }));
            draw.append_section (null, section ({ { _("Freeform"), "win.draw-freeform" }, { _("Scribble"), "win.draw-scribble" }, { _("Convert to Freeform"), "win.convert-freeform" }, { _("Ink to Shape"), "win.ink-to-shape" } }));
            menu.append_submenu (_("Draw"), draw);

            var format = new GLib.Menu ();
            var text = section ({ { _("Bold"), "win.bold" }, { _("Italic"), "win.italic" }, { _("Underline"), "win.underline" }, { _("Strikethrough"), "win.strike" }, { _("Superscript"), "win.superscript" }, { _("Subscript"), "win.subscript" }, { _("Bigger"), "win.font-bigger" }, { _("Smaller"), "win.font-smaller" } });
            var align = section ({ { _("Left"), "win.align-left" }, { _("Center"), "win.align-center" }, { _("Right"), "win.align-right" }, { _("Justify"), "win.align-justify" } });
            var lists = section ({ { _("Bullets"), "win.bullets" }, { _("Numbering"), "win.numbering" }, { _("No Bullets"), "win.no-bullets" }, { _("Increase Indent"), "win.indent-more" }, { _("Decrease Indent"), "win.indent-less" } });
            var subs = new GLib.Menu ();
            subs.append_submenu (_("Text"), text);
            subs.append_submenu (_("Alignment"), align);
            subs.append_submenu (_("Lists"), lists);
            format.append_section (null, subs);
            var themes = new GLib.Menu ();
            foreach (var preset in ThemePreset.all ()) {
                var item = new GLib.MenuItem (preset.name, null);
                item.set_action_and_target_value ("win.theme", new Variant.string (preset.id));
                themes.append_item (item);
            }
            var sizes = new GLib.Menu ();
            foreach (string s in new string[] { "16:9", "4:3", "16:10" }) {
                var item = new GLib.MenuItem (s == "16:9" ? _("Widescreen (16:9)") : (s == "4:3" ? _("Standard (4:3)") : "16:10"), null);
                item.set_action_and_target_value ("win.slide-size", new Variant.string (s));
                sizes.append_item (item);
            }
            var design = new GLib.Menu ();
            design.append_submenu (_("Theme"), themes);
            themes.append_section (null, section ({ { _("Variants…"), "win.theme-variants" }, { _("Browse for Themes…"), "win.import-theme" } }));
            sizes.append_section (null, section ({ { _("Custom Slide Size…"), "win.slide-size-custom" } }));
            design.append_submenu (_("Slide Size"), sizes);
            design.append (_("Design Ideas…"), "win.designer");
            design.append (_("Format Painter"), "win.format-painter");
            design.append (_("Embed Fonts…"), "win.embed-fonts");
            design.append (_("Clear Formatting"), "win.clear-format");
            format.append_section (null, design);
            menu.append_submenu (_("Format"), format);

            var arrange = new GLib.Menu ();
            arrange.append_section (null, section ({ { _("Bring to Front"), "win.bring-front" }, { _("Bring Forward"), "win.bring-forward" }, { _("Send Backward"), "win.send-backward" }, { _("Send to Back"), "win.send-back" } }));
            var aligns = section ({ { _("Left"), "win.arrange-left" }, { _("Center"), "win.arrange-center" }, { _("Right"), "win.arrange-right" }, { _("Top"), "win.arrange-top" }, { _("Middle"), "win.arrange-middle" }, { _("Bottom"), "win.arrange-bottom" } });
            var distribute = section ({ { _("Horizontally"), "win.distribute-h" }, { _("Vertically"), "win.distribute-v" } });
            var al = new GLib.Menu ();
            al.append_submenu (_("Align Objects"), aligns);
            al.append_submenu (_("Distribute Objects"), distribute);
            arrange.append_section (null, al);
            arrange.append_section (null, section ({ { _("Group"), "win.group" }, { _("Ungroup"), "win.ungroup" } }));
            var merge = section ({ { _("Union"), "win.merge-union" }, { _("Combine"), "win.merge-combine" }, { _("Fragment"), "win.merge-fragment" }, { _("Intersect"), "win.merge-intersect" }, { _("Subtract"), "win.merge-subtract" } });
            arrange.append_section (null, submenu_section (_("Merge Shapes"), merge));
            arrange.append_section (null, section ({ { _("Flip Horizontally"), "win.flip-h" }, { _("Flip Vertically"), "win.flip-v" }, { _("Rotate Left"), "win.rotate-left" }, { _("Rotate Right"), "win.rotate-right" }, { _("Lock"), "win.lock" } }));
            menu.append_submenu (_("Arrange"), arrange);

            var slide = new GLib.Menu ();
            slide.append_section (null, section ({ { _("New Slide"), "win.new-slide" }, { _("Duplicate Slide"), "win.duplicate-slide" }, { _("Delete Slide"), "win.delete-slide" }, { _("Hide Slide"), "win.hide-slide" } }));
            slide.append_section (null, section ({ { _("Move Up"), "win.slide-up" }, { _("Move Down"), "win.slide-down" } }));
            var sect = section ({ { _("Add Section"), "win.add-section" }, { _("Rename Section"), "win.rename-section" }, { _("Move Section Up"), "win.section-up" }, { _("Move Section Down"), "win.section-down" }, { _("Remove Section"), "win.remove-section" }, { _("Remove Section and Slides"), "win.remove-section-slides" } });
            slide.append_section (null, submenu_section (_("Section"), sect));
            slide.append_section (null, section ({ { _("Reset Layout"), "win.reset-layout" }, { _("Background…"), "win.background" }, { _("Apply Transition to All Slides"), "win.transition-all" } }));
            menu.append_submenu (_("Slide"), slide);

            var play = new GLib.Menu ();
            play.append_section (null, section ({ { _("Play from Start"), "win.play-start" }, { _("Play from Current Slide"), "win.play-current" }, { _("Presenter View"), "win.presenter" } }));
            play.append_section (null, section ({ { _("Custom Shows…"), "win.custom-shows" }, { _("Set Up Slide Show…"), "win.setup-show" } }));
            var record = section ({ { _("From Current Slide"), "win.record-show" }, { _("From Beginning"), "win.record-show-start" }, { _("With Camera"), "win.record-show-camera" }, { _("Clear Narration on Current Slide"), "win.clear-narration" }, { _("Clear Narration on All Slides"), "win.clear-narration-all" } });
            play.append_section (null, submenu_section (_("Record Slide Show"), record));
            play.append_section (null, section ({ { _("Rehearse Timings"), "win.rehearse" }, { _("Rehearse with Coach"), "win.rehearse-coach" }, { _("Use Slide Timings"), "win.use-timings" }, { _("Loop Until Stopped"), "win.loop" } }));
            menu.append_submenu (_("Play"), play);

            var review = new GLib.Menu ();
            review.append_section (null, section ({ { _("Check Spelling…"), "win.spelling" }, { _("Thesaurus…"), "win.thesaurus" }, { _("Translate…"), "win.translate" }, { _("Check Accessibility…"), "win.check-accessibility" } }));
            review.append_section (null, section ({ { _("New Comment"), "win.new-comment" }, { _("Show Comments"), "win.comments" } }));
            review.append_section (null, section ({ { _("Edit Together…"), "win.live" }, { _("Version History…"), "win.version-history" } }));
            menu.append_submenu (_("Review"), review);

            set_menubar (menu);
        }

        public override void activate () {
            var w = get_active_window ();
            if (w == null) w = new SlidesWindow (this);
            w.present ();
        }

        public override void open (File[] files, string hint) {
            foreach (var f in files) open_file (f, null);
        }

        public void open_file (File file, SlidesWindow? target) {
            string? path = file.get_path ();
            if (path == null) return;
            foreach (var w in get_windows ()) {
                var sw = w as SlidesWindow;
                if (sw != null && sw.doc != null && sw.doc.path == path) {
                    sw.present ();
                    return;
                }
            }
            SlidesWindow? win = target != null && target.is_empty () ? target : null;
            if (win == null) {
                foreach (var w in get_windows ()) {
                    var sw = w as SlidesWindow;
                    if (sw != null && sw.is_empty ()) win = sw;
                }
            }
            if (win == null) win = new SlidesWindow (this);
            win.present ();
            open_with_password (win, file, "", null);
        }

        private void open_with_password (SlidesWindow win, File file, string password, string? problem) {
            string path = file.get_path ();
            if (password == "" && Document.needs_password (path)) {
                DeckDialogs.ask_password (win, file.get_basename (), problem, (pw) => open_with_password (win, file, pw, null));
                return;
            }
            try {
                var d = Document.open (path, password);
                win.load_document (d);
                if (Singularity.Runtime.file_history_enabled ()) RecentManager.get_default ().add_item (file.get_uri ());
            } catch (Error e) {
                if (e is CryptoError.WRONG_PASSWORD || e is CryptoError.PASSWORD_REQUIRED) {
                    DeckDialogs.ask_password (win, file.get_basename (), _("The password is not correct."), (pw) => open_with_password (win, file, pw, null));
                    return;
                }
                win.show_error (_("Could Not Open"), _("\"%s\" could not be opened: %s").printf (file.get_basename (), e.message));
            }
        }

        public void choose_file (SlidesWindow parent) {
            var dialog = new FileDialog ();
            dialog.title = _("Open Presentation");
            var filter = new FileFilter ();
            filter.name = _("Presentations");
            foreach (string s in new string[] { "pptx", "potx", "ppsx", "odp", "otp" }) filter.add_suffix (s);
            var filters = new GLib.ListStore (typeof (FileFilter));
            filters.append (filter);
            dialog.filters = filters;
            dialog.open.begin (parent, null, (obj, res) => {
                try {
                    var file = dialog.open.end (res);
                    if (file != null) open_file (file, parent);
                } catch (Error e) {
                }
            });
        }

        private const string CSS = """
.slides-stage {
    background-color: alpha(@window_fg_color, 0.04);
    border-radius: 12px;
    margin: 0 12px 0 12px;
}

.slides-text-editor,
.slides-text-editor text {
    background: transparent;
    color: black;
}

.slides-notes {
    margin: 8px 12px 12px 12px;
    border-radius: 12px;
    border: 1px solid alpha(@window_fg_color, 0.1);
}

.slides-notes textview,
.slides-notes textview text {
    background: transparent;
}

.slides-thumb-row {
    padding: 6px 8px;
    border-radius: 10px;
}

.slides-thumb {
    border-radius: 6px;
    box-shadow: 0 1px 3px alpha(black, 0.25);
}

.slides-thumb-row:selected .slides-thumb,
.slides-sorter-cell:selected .slides-thumb {
    box-shadow: 0 0 0 3px @accent_color;
}

.slides-thumb-number {
    font-feature-settings: "tnum";
    min-width: 18px;
}

.slides-thumb-hidden .slides-thumb {
    opacity: 0.45;
}

.slides-sorter {
    padding: 16px;
}

.slides-sorter-cell {
    border-radius: 12px;
    padding: 8px;
}

.slides-inspector {
    padding: 0 12px 12px 4px;
}

.slides-inspector-scroll {
    min-width: 300px;
}

.slides-template-card {
    border-radius: 12px;
    padding: 6px;
}

.slides-template-thumb {
    border-radius: 8px;
    box-shadow: 0 1px 4px alpha(black, 0.3);
}

.slides-recent-row {
    border-radius: 10px;
    padding: 8px 10px;
}

.slides-swatch {
    min-width: 22px;
    min-height: 22px;
    padding: 0;
    border-radius: 99px;
    box-shadow: inset 0 0 0 1px alpha(@window_fg_color, 0.2);
}

.slides-theme-card {
    border-radius: 10px;
    padding: 4px;
}

.slides-theme-card:checked {
    box-shadow: 0 0 0 2px @accent_color;
}

.slides-anim-row {
    border-radius: 10px;
    padding: 6px 8px;
}

.slides-anim-bar {
    min-height: 8px;
    border-radius: 4px;
    background-color: @accent_color;
}

.slides-anim-index {
    font-feature-settings: "tnum";
    min-width: 22px;
    min-height: 22px;
    border-radius: 99px;
    background-color: alpha(@accent_color, 0.18);
    color: @accent_color;
    font-weight: 700;
    font-size: 12px;
}

.slides-presenter-slide {
    border-radius: 8px;
}

.slides-timer {
    font-feature-settings: "tnum";
    font-size: 34px;
    font-weight: 700;
}

.slides-presenter-notes,
.slides-presenter-notes text {
    background: transparent;
    font-size: 20px;
}

.slides-show {
    background-color: black;
}

.slides-data-grid entry {
    min-width: 72px;
}

.slides-zoom {
    border-radius: 99px;
    font-feature-settings: "tnum";
    font-size: 12px;
    min-height: 26px;
    padding: 0 10px;
}
""";
    }
}
