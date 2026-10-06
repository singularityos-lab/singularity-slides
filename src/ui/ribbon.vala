using Gtk;
using Singularity.Widgets;

namespace Singularity.Apps.Slides {

    public class SlidesRibbon : ContextRibbon {
        private const string[] FONTS = { "Noto Sans", "Noto Serif", "Cantarell", "DejaVu Sans", "DejaVu Serif", "Liberation Sans", "Liberation Serif", "Carlito", "Caladea", "Source Code Pro" };
        private static double[] SIZES = { 8, 9, 10, 11, 12, 14, 16, 18, 20, 24, 28, 32, 36, 40, 44, 48, 54, 60, 72, 88, 96 };
        private static double[] DURATIONS = { 0.25, 0.5, 0.75, 1, 1.5, 2, 3, 5 };
        private static int[] ZOOMS = { 50, 75, 100, 150, 200 };

        private weak SlidesWindow win;
        private bool syncing = false;
        private RibbonButton undo;
        private RibbonButton redo;
        private RibbonSelector font_selector;
        private RibbonSelector size_selector;
        private RibbonSelector duration_selector;
        private RibbonSelector zoom_selector;
        private RibbonToggle bold;
        private RibbonToggle italic;
        private RibbonToggle underline;
        private RibbonToggle strike;
        private RibbonMenu transition_options;
        private Gee.HashMap<string, RibbonToggle> panels = new Gee.HashMap<string, RibbonToggle> ();
        private Gee.HashMap<ViewMode, RibbonToggle> modes = new Gee.HashMap<ViewMode, RibbonToggle> ();
        private RibbonToggle notes_toggle;
        private RibbonToggle sidebar_toggle;
        private TextEditor? watched_editor = null;

        public SlidesRibbon (SlidesWindow win) {
            Object (orientation: Orientation.VERTICAL, spacing: 0);
            this.win = win;
            add_css_class ("slides-ribbon");
            build_home (add_context ("home", _("Home"), "go-home-symbolic"));
            build_insert (add_context ("insert", _("Insert"), "list-add-symbolic"));
            build_design (add_context ("design", _("Design"), "preferences-desktop-appearance-symbolic"));
            build_transitions (add_context ("transitions", _("Transitions"), "slides-transition-symbolic"));
            build_animations (add_context ("animations", _("Animations"), "slides-animate-symbolic"));
            build_show (add_context ("show", _("Slide Show"), "x-office-presentation-symbolic"));
            build_review (add_context ("review", _("Review"), "tools-check-spelling-symbolic"));
            build_view (add_context ("view", _("View"), "view-reveal-symbolic"));
        }

        private delegate void Act ();

        private RibbonButton call (RibbonContext c, string icon, string label, string? tip, owned Act cb) {
            var b = c.add_button (icon, label, tip);
            b.activated.connect (() => cb ());
            return b;
        }

        private RibbonMenu menu (RibbonContext c, string icon, string label, string? tip, owned RibbonMenuBuilder build) {
            var m = c.add_menu (icon, label, tip);
            m.set_builder ((owned) build);
            return m;
        }

        private RibbonToggle panel_toggle (RibbonContext c, string icon, string label, string panel, string action) {
            var t = c.add_toggle (icon, label);
            t.shortcut = accel ("win." + action);
            t.toggled.connect ((on) => {
                if (syncing) return;
                win.toggle_panel (panel);
            });
            panels[panel + "/" + c.id] = t;
            return t;
        }

        private static string? accel (string action) {
            var app = GLib.Application.get_default () as Gtk.Application;
            if (app == null) return null;
            string[] accels = app.get_accels_for_action (action);
            if (accels.length == 0) return null;
            uint key;
            Gdk.ModifierType mods;
            if (!Gtk.accelerator_parse (accels[0], out key, out mods)) return null;
            return Gtk.accelerator_get_label (key, mods);
        }

        private void build_home (RibbonContext c) {
            undo = c.add_button ("edit-undo-symbolic", _("Undo"), null, "win.undo");
            redo = c.add_button ("edit-redo-symbolic", _("Redo"), null, "win.redo");
            c.add_separator ();
            menu (c, "edit-paste-symbolic", _("Paste"), null, (m) => {
                m.add_item (_("Paste"), "edit-paste-symbolic", () => win.run ("paste"));
                m.add_item (_("Paste and Match Style"), null, () => win.run ("paste-style"));
            });
            c.add_button ("edit-cut-symbolic", _("Cut"), null, "win.cut");
            c.add_button ("edit-copy-symbolic", _("Copy"), null, "win.copy");
            c.add_button ("slides-format-painter-symbolic", _("Format Painter"), null, "win.format-painter");
            c.add_separator ();
            var new_slide = c.add_button ("slides-new-slide-symbolic", _("New Slide"), null, "win.new-slide");
            new_slide.label_in_compact = true;
            menu (c, "slides-layout-symbolic", _("Layout"), _("Slide Layout"), (m) => win.fill_layout_menu (m, false));
            c.add_button ("view-refresh-symbolic", _("Reset"), _("Reset Slide Layout"), "win.reset-layout");
            menu (c, "view-list-symbolic", _("Section"), null, (m) => {
                m.add_item (_("Add Section"), null, () => win.run ("add-section"));
                m.add_item (_("Rename Section"), null, () => win.run ("rename-section"));
                m.add_item (_("Move Section Up"), null, () => win.run ("section-up"));
                m.add_item (_("Move Section Down"), null, () => win.run ("section-down"));
                m.add_separator ();
                m.add_item (_("Remove Section"), null, () => win.run ("remove-section"));
                m.add_item (_("Remove Section and Slides"), null, () => win.run ("remove-section-slides"), "destructive");
            });
            c.add_separator ();
            font_selector = c.add_selector (_("Font"), 10);
            fill_fonts (null, null);
            font_selector.text = _("Font");
            font_selector.changed.connect ((id) => {
                if (syncing || id == "") return;
                win.format_runs (_("Font"), (r) => r.font = id);
                sync_text ();
            });
            size_selector = c.add_selector (_("Font Size"), 3);
            foreach (double s in SIZES) size_selector.add_option (size_id (s), size_id (s));
            size_selector.add_separator ();
            size_selector.add_option ("bigger", _("Increase Font Size"));
            size_selector.add_option ("smaller", _("Decrease Font Size"));
            size_selector.text = "18";
            size_selector.changed.connect ((id) => {
                if (syncing) return;
                if (id == "bigger") win.run ("font-bigger");
                else if (id == "smaller") win.run ("font-smaller");
                else {
                    double v = double.parse (id);
                    win.format_runs (_("Font Size"), (r) => r.size = v);
                }
                sync_text ();
            });
            bold = style_toggle (c, "format-text-bold-symbolic", _("Bold"), "bold");
            italic = style_toggle (c, "format-text-italic-symbolic", _("Italic"), "italic");
            underline = style_toggle (c, "format-text-underline-symbolic", _("Underline"), "underline");
            strike = style_toggle (c, "format-text-strikethrough-symbolic", _("Strikethrough"), "strike");
            menu (c, "font-x-generic-symbolic", _("Text Effects"), null, (m) => {
                m.add_item (_("Superscript"), null, () => win.run ("superscript"));
                m.add_item (_("Subscript"), null, () => win.run ("subscript"));
                m.add_separator ();
                m.add_item (_("Increase Font Size"), null, () => win.run ("font-bigger"));
                m.add_item (_("Decrease Font Size"), null, () => win.run ("font-smaller"));
            });
            c.add_button ("edit-clear-all-symbolic", _("Clear Formatting"), null, "win.clear-format");
            c.add_separator ();
            c.add_button ("view-list-bullet-symbolic", _("Bullets"), null, "win.bullets");
            c.add_button ("view-list-ordered-symbolic", _("Numbering"), null, "win.numbering");
            c.add_button ("format-indent-less-symbolic", _("Decrease Indent"), null, "win.indent-less");
            c.add_button ("format-indent-more-symbolic", _("Increase Indent"), null, "win.indent-more");
            c.add_separator ();
            c.add_button ("format-justify-left-symbolic", _("Align Left"), null, "win.align-left");
            c.add_button ("format-justify-center-symbolic", _("Center"), null, "win.align-center");
            c.add_button ("format-justify-right-symbolic", _("Align Right"), null, "win.align-right");
            c.add_button ("format-justify-fill-symbolic", _("Justify"), null, "win.align-justify");
            c.add_separator ();
            menu (c, "slides-bring-front-symbolic", _("Arrange"), null, (m) => fill_arrange (m));
            c.add_button ("edit-find-replace-symbolic", _("Replace"), null, "win.replace");
        }

        private RibbonToggle style_toggle (RibbonContext c, string icon, string label, string action) {
            var t = c.add_toggle (icon, label);
            t.shortcut = accel ("win." + action);
            t.toggled.connect (() => {
                if (syncing) return;
                win.run (action);
                sync_text ();
            });
            return t;
        }

        private void fill_arrange (ContextMenu m) {
            var order = m.add_submenu (_("Order"), "slides-bring-front-symbolic");
            order.add_item (_("Bring to Front"), "slides-bring-front-symbolic", () => win.run ("bring-front"));
            order.add_item (_("Bring Forward"), "slides-bring-forward-symbolic", () => win.run ("bring-forward"));
            order.add_item (_("Send Backward"), "slides-send-backward-symbolic", () => win.run ("send-backward"));
            order.add_item (_("Send to Back"), "slides-send-back-symbolic", () => win.run ("send-back"));
            var align = m.add_submenu (_("Align Objects"), "slides-align-left-symbolic");
            align.add_item (_("Left"), "slides-align-left-symbolic", () => win.run ("arrange-left"));
            align.add_item (_("Center"), "slides-align-center-symbolic", () => win.run ("arrange-center"));
            align.add_item (_("Right"), "slides-align-right-symbolic", () => win.run ("arrange-right"));
            align.add_item (_("Top"), "slides-align-top-symbolic", () => win.run ("arrange-top"));
            align.add_item (_("Middle"), "slides-align-middle-symbolic", () => win.run ("arrange-middle"));
            align.add_item (_("Bottom"), "slides-align-bottom-symbolic", () => win.run ("arrange-bottom"));
            var dist = m.add_submenu (_("Distribute Objects"), "slides-distribute-h-symbolic");
            dist.add_item (_("Horizontally"), "slides-distribute-h-symbolic", () => win.run ("distribute-h"));
            dist.add_item (_("Vertically"), "slides-distribute-v-symbolic", () => win.run ("distribute-v"));
            m.add_separator ();
            m.add_item (_("Group"), "slides-group-symbolic", () => win.run ("group"));
            m.add_item (_("Ungroup"), "slides-ungroup-symbolic", () => win.run ("ungroup"));
            var merge = m.add_submenu (_("Merge Shapes"), "slides-merge-union-symbolic");
            merge.add_item (_("Union"), "slides-merge-union-symbolic", () => win.run ("merge-union"));
            merge.add_item (_("Combine"), "slides-merge-combine-symbolic", () => win.run ("merge-combine"));
            merge.add_item (_("Fragment"), "slides-merge-fragment-symbolic", () => win.run ("merge-fragment"));
            merge.add_item (_("Intersect"), "slides-merge-intersect-symbolic", () => win.run ("merge-intersect"));
            merge.add_item (_("Subtract"), "slides-merge-subtract-symbolic", () => win.run ("merge-subtract"));
            m.add_separator ();
            m.add_item (_("Rotate Right 90°"), "object-rotate-right-symbolic", () => win.run ("rotate-right"));
            m.add_item (_("Rotate Left 90°"), "object-rotate-left-symbolic", () => win.run ("rotate-left"));
            m.add_item (_("Flip Horizontally"), "object-flip-horizontal-symbolic", () => win.run ("flip-h"));
            m.add_item (_("Flip Vertically"), "object-flip-vertical-symbolic", () => win.run ("flip-v"));
            m.add_item (_("Lock"), "system-lock-screen-symbolic", () => win.run ("lock"));
        }

        private void build_insert (RibbonContext c) {
            var new_slide = c.add_button ("slides-new-slide-symbolic", _("New Slide"), null, "win.new-slide");
            new_slide.label_in_compact = true;
            menu (c, "slides-layout-symbolic", _("New Slide with Layout"), null, (m) => win.fill_layout_menu (m, true));
            c.add_button ("edit-copy-symbolic", _("Duplicate Slide"), null, "win.duplicate-slide");
            c.add_separator ();
            c.add_button ("slides-table-symbolic", _("Table"), null, "win.insert-table");
            menu (c, "insert-image-symbolic", _("Pictures"), null, (m) => {
                m.add_item (_("Image…"), "insert-image-symbolic", () => win.run ("insert-image"));
                m.add_item (_("Stock Images…"), "image-x-generic-symbolic", () => win.run ("insert-stock"));
            });
            menu (c, "slides-shape-symbolic", _("Shapes"), null, (m) => {
                ShapeKind[] kinds = { ShapeKind.RECT, ShapeKind.ROUND_RECT, ShapeKind.ELLIPSE, ShapeKind.TRIANGLE, ShapeKind.DIAMOND, ShapeKind.PENTAGON, ShapeKind.HEXAGON, ShapeKind.STAR5, ShapeKind.ARROW_RIGHT, ShapeKind.CHEVRON, ShapeKind.CALLOUT, ShapeKind.HEART, ShapeKind.CLOUD, ShapeKind.PLUS, ShapeKind.DONUT };
                foreach (var k in kinds) {
                    var kk = k;
                    m.add_item (k.label (), null, () => win.insert_shape (kk));
                }
                m.add_item (_("Line"), "slides-line-symbolic", () => win.insert_shape (ShapeKind.LINE));
                m.add_separator ();
                m.add_item (_("All Shapes…"), "slides-shape-symbolic", () => win.run ("insert-shapes"));
            });
            c.add_button ("face-smile-symbolic", _("Icons"), _("Insert Icons"), "win.insert-icons");
            c.add_button ("insert-object-symbolic", _("3D Model"), _("Insert a 3D Model"), "win.insert-model");
            c.add_button ("slides-group-symbolic", _("SmartArt"), _("Insert SmartArt"), "win.insert-smartart");
            menu (c, "slides-chart-symbolic", _("Chart"), null, (m) => {
                ChartKind[] ck = { ChartKind.COLUMN, ChartKind.BAR, ChartKind.LINE, ChartKind.AREA, ChartKind.PIE, ChartKind.DOUGHNUT, ChartKind.SCATTER, ChartKind.BUBBLE, ChartKind.RADAR, ChartKind.STOCK, ChartKind.HISTOGRAM, ChartKind.PARETO, ChartKind.BOX_WHISKER, ChartKind.WATERFALL, ChartKind.FUNNEL, ChartKind.TREEMAP, ChartKind.SUNBURST };
                foreach (var k in ck) {
                    var kk = k;
                    m.add_item (k.label (), null, () => win.insert_chart (kk));
                }
            });
            c.add_separator ();
            c.add_button ("insert-text-symbolic", _("Text Box"), null, "win.insert-text");
            c.add_button ("slides-equation-symbolic", _("Equation"), null, "win.insert-equation");
            c.add_button ("insert-link-symbolic", _("Link"), _("Hyperlink or Action"), "win.insert-link");
            c.add_button ("slides-comment-symbolic", _("Comment"), _("New Comment"), "win.new-comment");
            menu (c, "text-x-generic-symbolic", _("Header and Footer"), null, (m) => {
                m.add_item (_("Header and Footer…"), null, () => win.run ("header-footer"));
                m.add_item (_("Slide Number"), "view-list-ordered-symbolic", () => win.run ("insert-slide-number"));
                m.add_item (_("Date and Time"), "x-office-calendar-symbolic", () => win.run ("insert-date"));
            });
            menu (c, "slides-pen-symbolic", _("Draw"), _("Ink and Freeform"), (m) => {
                m.add_item (_("Select"), "edit-select-all-symbolic", () => win.run ("draw-select"));
                m.add_item (_("Pen"), "slides-pen-symbolic", () => win.run ("draw-pen"));
                m.add_item (_("Highlighter"), "slides-highlighter-symbolic", () => win.run ("draw-highlighter"));
                m.add_item (_("Eraser"), "slides-eraser-symbolic", () => win.run ("draw-eraser"));
                m.add_separator ();
                m.add_item (_("Freeform"), null, () => win.run ("draw-freeform"));
                m.add_item (_("Scribble"), null, () => win.run ("draw-scribble"));
                m.add_item (_("Convert to Freeform"), null, () => win.run ("convert-freeform"));
                m.add_item (_("Ink to Shape"), null, () => win.run ("ink-to-shape"));
            });
            c.add_separator ();
            menu (c, "view-paged-symbolic", _("Zoom"), _("Insert a Zoom"), (m) => {
                m.add_item (_("Summary Zoom…"), null, () => win.run ("insert-zoom-summary"));
                m.add_item (_("Section Zoom…"), null, () => win.run ("insert-zoom-section"));
                m.add_item (_("Slide Zoom…"), null, () => win.run ("insert-zoom-slide"));
            });
            menu (c, "video-x-generic-symbolic", _("Media"), null, (m) => {
                m.add_item (_("Video…"), "video-x-generic-symbolic", () => win.run ("insert-video"));
                m.add_item (_("Audio…"), "audio-x-generic-symbolic", () => win.run ("insert-audio"));
                m.add_separator ();
                m.add_item (_("Record Audio…"), "audio-input-microphone-symbolic", () => win.run ("record-audio"));
                m.add_item (_("Screen Recording…"), "media-record-symbolic", () => win.run ("record-screen"));
            });
        }

        private void build_design (RibbonContext c) {
            var themes = menu (c, "preferences-desktop-appearance-symbolic", _("Themes"), null, (m) => {
                foreach (var preset in ThemePreset.all ()) {
                    string id = preset.id;
                    m.add_item (preset.name, null, () => win.activate_action ("theme", new Variant.string (id)));
                }
                m.add_separator ();
                m.add_item (_("Browse for Themes…"), "document-open-symbolic", () => win.run ("import-theme"));
            });
            themes.label_in_compact = true;
            c.add_button ("preferences-color-symbolic", _("Variants"), _("Theme Variants"), "win.theme-variants");
            c.add_separator ();
            menu (c, "slides-slide-size-symbolic", _("Slide Size"), null, (m) => {
                m.add_item (_("Widescreen (16:9)"), null, () => win.activate_action ("slide-size", new Variant.string ("16:9")));
                m.add_item (_("Standard (4:3)"), null, () => win.activate_action ("slide-size", new Variant.string ("4:3")));
                m.add_item ("16:10", null, () => win.activate_action ("slide-size", new Variant.string ("16:10")));
                m.add_separator ();
                m.add_item (_("Custom Slide Size…"), null, () => win.run ("slide-size-custom"));
            });
            c.add_button ("preferences-desktop-wallpaper-symbolic", _("Format Background"), null, "win.background");
            c.add_separator ();
            var ideas = c.add_button ("emoji-objects-symbolic", _("Design Ideas"), null, "win.designer");
            ideas.label_in_compact = true;
            c.add_button ("font-x-generic-symbolic", _("Embed Fonts"), null, "win.embed-fonts");
            c.add_button ("document-save-as-symbolic", _("Save as Template"), null, "win.save-template");
        }

        private void build_transitions (RibbonContext c) {
            c.add_button ("media-playback-start-symbolic", _("Preview"), _("Preview Transition"), "win.preview-transition");
            c.add_separator ();
            var effect = menu (c, "slides-transition-symbolic", _("Transition"), _("Transition to This Slide"), (m) => win.anim_panel.fill_transitions (m));
            effect.label_in_compact = true;
            transition_options = menu (c, "emblem-system-symbolic", _("Effect Options"), null, (m) => {
                if (!win.anim_panel.fill_transition_options (m)) m.add_item (_("No Options for This Transition"), null, () => { }, "dim-label");
            });
            duration_selector = c.add_selector (_("Duration (seconds)"), 5, "preferences-system-time-symbolic");
            foreach (double d in DURATIONS) duration_selector.add_option (duration_id (d), seconds_label (d));
            duration_selector.changed.connect ((id) => {
                if (syncing) return;
                win.anim_panel.set_transition_duration (double.parse (id));
            });
            c.add_separator ();
            c.add_button ("edit-copy-symbolic", _("Apply to All"), _("Apply to All Slides"), "win.transition-all");
            panel_toggle (c, "slides-animate-symbolic", _("Timing"), "animate", "animations");
        }

        private void build_animations (RibbonContext c) {
            c.add_button ("media-playback-start-symbolic", _("Preview"), _("Preview Animations"), "win.preview-animations");
            c.add_separator ();
            var add = menu (c, "slides-build-in-symbolic", _("Add Animation"), null, (m) => win.anim_panel.fill_add_animation (m));
            add.label_in_compact = true;
            call (c, "slides-motion-path-symbolic", _("Custom Path"), _("Draw Custom Path"), () => win.anim_panel.draw_custom_path ());
            call (c, "slides-format-painter-symbolic", _("Animation Painter"), _("Copy animations to other objects"), () => win.anim_panel.paint_animations ());
            c.add_separator ();
            var pane = panel_toggle (c, "slides-animate-symbolic", _("Animation Pane"), "animate", "animations");
            pane.label_in_compact = true;
        }

        private void build_show (RibbonContext c) {
            var start = c.add_button ("media-playback-start-symbolic", _("From Beginning"), null, "win.play-start");
            start.label_in_compact = true;
            var current = c.add_button ("media-seek-forward-symbolic", _("From Current Slide"), null, "win.play-current");
            current.label_in_compact = true;
            c.add_button ("x-office-presentation-symbolic", _("Presenter View"), null, "win.presenter");
            c.add_button ("view-list-symbolic", _("Custom Shows"), null, "win.custom-shows");
            c.add_separator ();
            c.add_button ("emblem-system-symbolic", _("Set Up Slide Show"), null, "win.setup-show");
            c.add_button ("view-conceal-symbolic", _("Hide Slide"), null, "win.hide-slide");
            c.add_button ("preferences-system-time-symbolic", _("Rehearse Timings"), null, "win.rehearse");
            c.add_button ("audio-input-microphone-symbolic", _("Rehearse with Coach"), null, "win.rehearse-coach");
            menu (c, "media-record-symbolic", _("Record"), _("Record Slide Show"), (m) => {
                m.add_item (_("From Current Slide"), null, () => win.run ("record-show"));
                m.add_item (_("From Beginning"), null, () => win.run ("record-show-start"));
                m.add_item (_("With Camera"), "camera-web-symbolic", () => win.run ("record-show-camera"));
                m.add_separator ();
                m.add_item (_("Clear Narration on Current Slide"), null, () => win.run ("clear-narration"));
                m.add_item (_("Clear Narration on All Slides"), null, () => win.run ("clear-narration-all"), "destructive");
            });
            c.add_separator ();
            var timings = c.add_toggle ("preferences-system-time-symbolic", _("Use Timings"), _("Use Slide Timings"), "win.use-timings");
            timings.label_in_compact = true;
            var loop = c.add_toggle ("media-playlist-repeat-symbolic", _("Loop"), _("Loop Until Stopped"), "win.loop");
            loop.label_in_compact = true;
        }

        private void build_review (RibbonContext c) {
            c.add_button ("tools-check-spelling-symbolic", _("Spelling"), _("Check Spelling"), "win.spelling");
            c.add_button ("accessories-dictionary-symbolic", _("Thesaurus"), null, "win.thesaurus");
            c.add_button ("preferences-desktop-locale-symbolic", _("Translate"), null, "win.translate");
            c.add_button ("preferences-desktop-accessibility-symbolic", _("Check Accessibility"), null, "win.check-accessibility");
            c.add_separator ();
            c.add_button ("slides-comment-symbolic", _("New Comment"), null, "win.new-comment");
            var show = panel_toggle (c, "view-reveal-symbolic", _("Show Comments"), "comments", "comments");
            show.label_in_compact = true;
            c.add_separator ();
            c.add_button ("system-users-symbolic", _("Edit Together"), null, "win.live");
            c.add_button ("document-open-recent-symbolic", _("Version History"), null, "win.version-history");
            c.add_button ("dialog-password-symbolic", _("Protect"), _("Encrypt with Password"), "win.protect");
        }

        private void build_view (RibbonContext c) {
            mode_toggle (c, ViewMode.NORMAL, "x-office-presentation-symbolic", _("Normal"), "view-normal");
            var outline = panel_toggle (c, "view-list-symbolic", _("Outline"), "outline", "outline");
            outline.label_in_compact = true;
            mode_toggle (c, ViewMode.SORTER, "view-grid-symbolic", _("Slide Sorter"), "view-sorter");
            mode_toggle (c, ViewMode.MASTER, "slides-layout-symbolic", _("Slide Master"), "view-master");
            c.add_separator ();
            sidebar_toggle = c.add_toggle ("sidebar-show-symbolic", _("Slides"), _("Slides Sidebar"));
            sidebar_toggle.shortcut = accel ("win.sidebar");
            sidebar_toggle.toggled.connect (() => {
                if (!syncing) win.run ("sidebar");
            });
            notes_toggle = c.add_toggle ("accessories-text-editor-symbolic", _("Notes"), _("Speaker Notes"));
            notes_toggle.shortcut = accel ("win.notes");
            notes_toggle.toggled.connect (() => {
                if (!syncing) win.run ("notes");
            });
            panel_toggle (c, "sidebar-show-right-symbolic", _("Format Panel"), "format", "inspector");
            c.add_separator ();
            c.add_toggle ("slides-ruler-symbolic", _("Ruler"), null, "win.show-ruler");
            c.add_toggle ("view-grid-symbolic", _("Gridlines"), null, "win.show-grid");
            c.add_toggle ("slides-guides-symbolic", _("Guides"), null, "win.show-guides");
            menu (c, "emblem-system-symbolic", _("Grid and Guides"), null, (m) => {
                m.add_item (_("Smart Guides"), null, () => win.run ("guides"), action_on ("guides") ? "checked" : null);
                m.add_item (_("Snap to Grid"), null, () => win.run ("snap-grid"), action_on ("snap-grid") ? "checked" : null);
                m.add_separator ();
                m.add_item (_("Add Vertical Guide"), null, () => win.run ("add-guide-v"));
                m.add_item (_("Add Horizontal Guide"), null, () => win.run ("add-guide-h"));
                m.add_separator ();
                m.add_item (_("Grid and Guides…"), null, () => win.run ("grid-settings"));
            });
            c.add_separator ();
            c.add_button ("zoom-out-symbolic", _("Zoom Out"), null, "win.zoom-out");
            zoom_selector = c.add_selector (_("Zoom"), 5);
            zoom_selector.add_option ("fit", _("Fit Slide"));
            zoom_selector.add_separator ();
            foreach (int z in ZOOMS) zoom_selector.add_option (z.to_string (), "%d%%".printf (z));
            zoom_selector.text = "100%";
            zoom_selector.changed.connect ((id) => {
                if (syncing) return;
                if (id == "fit") win.run ("zoom-fit");
                else win.canvas.zoom_to (int.parse (id) / 100.0);
            });
            c.add_button ("zoom-in-symbolic", _("Zoom In"), null, "win.zoom-in");
            c.add_button ("zoom-fit-best-symbolic", _("Fit Slide"), null, "win.zoom-fit");
        }

        private void mode_toggle (RibbonContext c, ViewMode mode, string icon, string label, string action) {
            var t = c.add_toggle (icon, label);
            t.label_in_compact = true;
            t.shortcut = accel ("win." + action);
            t.toggled.connect ((on) => {
                if (syncing) return;
                if (!on && win.view_mode == mode) {
                    sync_modes ();
                    return;
                }
                win.set_view (mode);
            });
            modes[mode] = t;
        }

        private bool action_on (string name) {
            var a = win.lookup_action (name);
            return a != null && a.get_state () != null && a.get_state ().get_boolean ();
        }

        private static string size_id (double s) {
            return s == Math.floor (s) ? "%d".printf ((int) s) : "%.1f".printf (s);
        }

        private static string duration_id (double d) {
            return "%.2f".printf (d);
        }

        private static string seconds_label (double d) {
            return _("%s s").printf (d == Math.floor (d) ? "%d".printf ((int) d) : "%.2g".printf (d));
        }

        private void fill_fonts (string? heading, string? body) {
            font_selector.clear_options ();
            if (heading != null) font_selector.add_option (heading, _("%s (Headings)").printf (heading));
            if (body != null && body != heading) font_selector.add_option (body, _("%s (Body)").printf (body));
            if (heading != null || body != null) font_selector.add_separator ();
            var families = new Gee.HashSet<string> ();
            Pango.FontFamily[] list;
            win.get_pango_context ().list_families (out list);
            foreach (var f in list) families.add (f.get_name ());
            foreach (string f in FONTS) if (families.contains (f) && f != heading && f != body) font_selector.add_option (f, f);
            font_selector.add_separator ();
            font_selector.add_extra ((m) => m.add_item (_("Other Font…"), null, () => choose_font ()));
        }

        private void choose_font () {
            var dlg = new FontDialog ();
            dlg.title = _("Choose a Font");
            dlg.choose_family.begin (win, null, null, (o, res) => {
                try {
                    var fam = dlg.choose_family.end (res);
                    if (fam == null) return;
                    string name = fam.get_name ();
                    win.format_runs (_("Font"), (r) => r.font = name);
                    sync_text ();
                } catch (Error e) {
                }
            });
        }

        public void document_loaded () {
            string? heading = null, body = null;
            if (win.doc != null) {
                heading = win.doc.pres.theme.major_font;
                body = win.doc.pres.theme.minor_font;
            }
            fill_fonts (heading, body);
            sync ();
        }

        public void sync () {
            sync_history ();
            sync_text ();
            sync_modes ();
            sync_panels ();
            sync_transition ();
            sync_zoom ();
        }

        public void sync_history () {
            var d = win.doc;
            undo.button.sensitive = d != null && d.can_undo;
            redo.button.sensitive = d != null && d.can_redo;
            undo.tooltip = d != null && d.can_undo ? _("Undo %s").printf (d.undo_label) : _("Undo");
            redo.tooltip = d != null && d.can_redo ? _("Redo %s").printf (d.redo_label) : _("Redo");
        }

        public void sync_text () {
            watch_editor ();
            var rs = win.current_run_style ();
            syncing = true;
            bold.active = rs != null && rs.bold;
            italic.active = rs != null && rs.italic;
            underline.active = rs != null && rs.underline;
            strike.active = rs != null && rs.strike;
            bool has = rs != null;
            foreach (var t in new RibbonItem[] { bold, italic, underline, strike, font_selector, size_selector }) t.widget.sensitive = has;
            if (rs != null) {
                font_selector.selected = rs.font;
                font_selector.text = rs.font;
                size_selector.selected = size_id (Math.round (rs.size * 10) / 10);
                size_selector.text = size_id (Math.round (rs.size * 10) / 10);
            }
            syncing = false;
        }

        private void watch_editor () {
            var ed = win.canvas.editor;
            if (ed == watched_editor) return;
            if (watched_editor != null) watched_editor.format_changed.disconnect (sync_text);
            watched_editor = ed;
            if (ed != null) ed.format_changed.connect (sync_text);
        }

        public void sync_modes () {
            syncing = true;
            foreach (var e in modes.entries) e.value.active = win.doc != null && win.view_mode == e.key;
            syncing = false;
        }

        public void sync_panels () {
            syncing = true;
            string? shown = win.shown_panel ();
            foreach (var e in panels.entries) {
                string name = e.key.split ("/")[0];
                e.value.active = shown == name;
            }
            notes_toggle.active = win.notes_shown ();
            sidebar_toggle.active = win.get_sidebar_visible ();
            syncing = false;
        }

        public void sync_transition () {
            var s = win.canvas.slide;
            syncing = true;
            bool has = win.doc != null && s != null;
            duration_selector.widget.sensitive = has && s.transition.kind != TransitionKind.NONE;
            transition_options.widget.sensitive = has && s.transition.kind != TransitionKind.NONE;
            if (has) {
                duration_selector.selected = duration_id (s.transition.duration);
                duration_selector.text = seconds_label (s.transition.duration);
            }
            syncing = false;
        }

        public void sync_zoom () {
            syncing = true;
            zoom_selector.text = "%d%%".printf ((int) Math.round (win.canvas.scale * 100));
            syncing = false;
        }
    }
}
