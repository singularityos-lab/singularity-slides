using Gtk;
using Singularity.Widgets;

namespace Singularity.Apps.Slides {

    public class ColorButton : Button {
        public string spec = "";
        public bool allow_none = true;
        private Theme theme;
        private DrawingArea swatch;

        public signal void chosen (string spec);

        public ColorButton (Theme theme, string spec, bool allow_none = true) {
            this.theme = theme;
            this.spec = spec;
            this.allow_none = allow_none;
            add_css_class ("flat");
            valign = Align.CENTER;
            tooltip_text = _("Choose a Color");
            swatch = new DrawingArea ();
            swatch.set_size_request (26, 18);
            swatch.set_draw_func ((da, cr, w, h) => {
                if (this.spec == "") {
                    cr.set_source_rgba (0.5, 0.5, 0.5, 0.25);
                    Geometry.round_rect (cr, 1, 1, w - 2, h - 2, 4);
                    cr.fill ();
                    cr.set_source_rgba (0.85, 0.2, 0.2, 1);
                    cr.set_line_width (1.5);
                    cr.move_to (3, h - 3);
                    cr.line_to (w - 3, 3);
                    cr.stroke ();
                    return;
                }
                var c = this.theme.resolve (this.spec);
                Geometry.round_rect (cr, 1, 1, w - 2, h - 2, 4);
                cr.set_source_rgba (c.r, c.g, c.b, c.a);
                cr.fill_preserve ();
                cr.set_source_rgba (0, 0, 0, 0.25);
                cr.set_line_width (1);
                cr.stroke ();
            });
            child = swatch;
            clicked.connect (open_palette);
        }

        public void set_spec (string s) {
            spec = s;
            swatch.queue_draw ();
        }

        private Button swatch_button (string s, string tip) {
            var b = new Button ();
            b.add_css_class ("flat");
            b.add_css_class ("slides-swatch");
            b.tooltip_text = tip;
            var da = new DrawingArea ();
            da.set_size_request (20, 20);
            da.set_draw_func ((d, cr, w, h) => {
                var c = theme.resolve (s);
                cr.arc (w / 2.0, h / 2.0, w / 2.0 - 1, 0, 2 * Math.PI);
                cr.set_source_rgba (c.r, c.g, c.b, c.a);
                cr.fill_preserve ();
                cr.set_source_rgba (0.5, 0.5, 0.5, 0.35);
                cr.set_line_width (1);
                cr.stroke ();
            });
            b.child = da;
            return b;
        }

        private void open_palette () {
            var pop = new Popover ();
            pop.set_parent (this);
            var box = new Box (Orientation.VERTICAL, 8);
            box.margin_top = 10;
            box.margin_bottom = 10;
            box.margin_start = 10;
            box.margin_end = 10;
            var title = new Label (_("Theme Colors"));
            title.add_css_class ("caption");
            title.add_css_class ("dim-label");
            title.xalign = 0;
            box.append (title);
            var grid = new Grid ();
            grid.row_spacing = 4;
            grid.column_spacing = 4;
            string[] keys = { "lt1", "dk1", "lt2", "dk2", "accent1", "accent2", "accent3", "accent4", "accent5", "accent6" };
            string[] names = { _("Background 1"), _("Text 1"), _("Background 2"), _("Text 2"), _("Accent 1"), _("Accent 2"), _("Accent 3"), _("Accent 4"), _("Accent 5"), _("Accent 6") };
            double[,] mods = { { 1, 0 }, { 0.2, 0.8 }, { 0.4, 0.6 }, { 0.6, 0.4 }, { 0.75, 0 }, { 0.5, 0 } };
            for (int c = 0; c < keys.length; c++) {
                for (int r = 0; r < 6; r++) {
                    string s = r == 0 ? keys[c] : ColorSpec.tint (keys[c], mods[r, 0], mods[r, 1]);
                    var b = swatch_button (s, r == 0 ? names[c] : "%s, %d%%".printf (names[c], (int) Math.round ((mods[r, 0] + mods[r, 1]) * 100)));
                    b.clicked.connect (() => {
                        pop.popdown ();
                        set_spec (s);
                        chosen (s);
                    });
                    grid.attach (b, c, r > 0 ? r + 1 : 0);
                }
            }
            box.append (grid);
            var std_title = new Label (_("Standard Colors"));
            std_title.add_css_class ("caption");
            std_title.add_css_class ("dim-label");
            std_title.xalign = 0;
            box.append (std_title);
            var std = new Box (Orientation.HORIZONTAL, 4);
            foreach (string hex in new string[] { "#000000", "#ffffff", "#e01b24", "#ff7800", "#f6d32d", "#33d17a", "#2ec27e", "#3584e4", "#1c71d8", "#9141ac" }) {
                string h = hex;
                var b = swatch_button (h, h);
                b.clicked.connect (() => {
                    pop.popdown ();
                    set_spec (h);
                    chosen (h);
                });
                std.append (b);
            }
            box.append (std);
            var actions = new Box (Orientation.HORIZONTAL, 6);
            if (allow_none) {
                var none = new Button.with_label (_("No Color"));
                none.clicked.connect (() => {
                    pop.popdown ();
                    set_spec ("");
                    chosen ("");
                });
                actions.append (none);
            }
            var custom = new Button.with_label (_("Custom…"));
            custom.hexpand = true;
            custom.clicked.connect (() => {
                pop.popdown ();
                var dlg = new Gtk.ColorDialog ();
                dlg.with_alpha = true;
                dlg.title = _("Custom Color");
                var initial = Gdk.RGBA ();
                var cur = theme.resolve (spec == "" ? "#3584e4" : spec);
                initial.red = (float) cur.r;
                initial.green = (float) cur.g;
                initial.blue = (float) cur.b;
                initial.alpha = (float) cur.a;
                dlg.choose_rgba.begin (get_root () as Gtk.Window, initial, null, (o, res) => {
                    try {
                        var rgba = dlg.choose_rgba.end (res);
                        var c = Rgba (rgba.red, rgba.green, rgba.blue, rgba.alpha);
                        string s = c.to_hex ();
                        if (rgba.alpha < 0.999) s = ColorSpec.with_alpha (s, Math.round (rgba.alpha * 100) / 100);
                        set_spec (s);
                        chosen (s);
                    } catch (Error e) {
                    }
                });
            });
            actions.append (custom);
            box.append (actions);
            pop.child = box;
            pop.closed.connect (() => Idle.add (() => {
                pop.unparent ();
                return Source.REMOVE;
            }));
            pop.popup ();
        }
    }

    public class Inspector : Box {
        private SlidesWindow win;
        private Box content;
        private bool syncing = false;
        private SpinRow? x_row = null;
        private SpinRow? y_row = null;
        private SpinRow? w_row = null;
        private SpinRow? h_row = null;
        private SpinRow? r_row = null;

        public Inspector (SlidesWindow win) {
            Object (orientation: Orientation.VERTICAL, spacing: 0);
            this.win = win;
            var scroll = new ScrolledWindow ();
            scroll.hscrollbar_policy = PolicyType.NEVER;
            scroll.vexpand = true;
            scroll.add_css_class ("slides-inspector-scroll");
            scroll.min_content_width = 330;
            scroll.max_content_width = 330;
            scroll.propagate_natural_width = false;
            hexpand = false;
            content = new Box (Orientation.VERTICAL, 18);
            content.add_css_class ("slides-inspector");
            scroll.child = content;
            append (scroll);
        }

        private Document doc {
            get { return win.doc; }
        }

        private SlideCanvas canvas {
            get { return win.canvas; }
        }

        private Theme theme () {
            if (canvas.slide != null) return doc.pres.master_for (canvas.slide).theme;
            if (canvas.master != null) return canvas.master.theme;
            return doc.pres.theme;
        }

        private void edit (string label, owned Document.EditFunc f, string key = "") {
            if (syncing) return;
            doc.checkpoint (label, key);
            f ();
            doc.touch ();
            canvas.queue_draw ();
            win.content_edited ();
        }

        private PreferencesGroup group (string title, string? desc = null) {
            var g = new PreferencesGroup (title, desc);
            content.append (g);
            return g;
        }

        private SpinRow spin (PreferencesGroup g, string title, double min, double max, double step, double value, int digits, owned SpinApply apply, string key) {
            var row = new SpinRow (title, null, min, max, step, value);
            row.spin_btn.digits = digits;
            row.spin_btn.value_changed.connect (() => {
                double v = row.spin_btn.value;
                edit (title, () => apply (v), key);
            });
            g.add_row (row);
            return row;
        }

        public delegate void SpinApply (double v);
        public delegate void BoolApply (bool v);
        public delegate void StringApply (string v);

        private SwitchRow toggle (PreferencesGroup g, string title, string? subtitle, bool value, owned BoolApply apply) {
            var row = new SwitchRow (title, subtitle, value);
            row.switch_btn.notify["active"].connect (() => {
                bool v = row.switch_btn.active;
                edit (title, () => apply (v));
            });
            g.add_row (row);
            return row;
        }

        private SelectionRow choice (PreferencesGroup g, string title, owned string[] labels, int current, owned SpinApply apply) {
            var row = new SelectionRow (title, labels, current >= 0 && current < labels.length ? labels[current] : "");
            row.selected.connect ((item) => {
                for (int i = 0; i < labels.length; i++) {
                    if (labels[i] == item) {
                        int v = i;
                        edit (title, () => apply (v));
                        break;
                    }
                }
            });
            g.add_row (row);
            return row;
        }

        private ColorButton color (PreferencesGroup g, string title, string spec, bool allow_none, owned StringApply apply) {
            var row = new ActionRow (title);
            var b = new ColorButton (theme (), spec, allow_none);
            b.chosen.connect ((s) => edit (title, () => apply (s)));
            row.add_suffix (b);
            g.add_row (row);
            return b;
        }

        private ActionRow button_row (PreferencesGroup g, string title, string? subtitle, string icon, owned Document.EditFunc f) {
            var row = new ActionRow (title, subtitle);
            var b = new Button.from_icon_name (icon);
            b.valign = Align.CENTER;
            b.tooltip_text = title;
            b.clicked.connect (() => f ());
            row.add_suffix (b);
            row.activated.connect (() => f ());
            g.add_row (row);
            return row;
        }

        private Box tool_row (PreferencesGroup g, string title) {
            var row = new ActionRow (title);
            var box = new Box (Orientation.HORIZONTAL, 2);
            box.valign = Align.CENTER;
            row.add_suffix (box);
            g.add_row (row);
            return box;
        }

        private Button tool (Box box, string icon, string tip, string action) {
            var b = new Button.from_icon_name (icon);
            b.add_css_class ("flat");
            b.tooltip_text = tip;
            b.action_name = action;
            box.append (b);
            return b;
        }

        public void rebuild () {
            Widget? child;
            while ((child = content.get_first_child ()) != null) content.remove (child);
            fill_editors.clear ();
            x_row = y_row = w_row = h_row = r_row = null;
            if (doc == null) return;
            syncing = true;
            var sel = canvas.selection;
            if (sel.size == 0) {
                if (canvas.slide != null) build_slide ();
                else build_master ();
            } else if (sel.size == 1) {
                var e = sel[0];
                switch (e.kind) {
                    case ElementKind.SHAPE:
                        build_shape ((ShapeElement) e);
                        break;
                    case ElementKind.IMAGE:
                        build_image ((ImageElement) e);
                        break;
                    case ElementKind.TABLE:
                        build_table ((TableElement) e);
                        break;
                    case ElementKind.CHART:
                        build_chart ((ChartElement) e);
                        break;
                    case ElementKind.GROUP:
                        build_group ((GroupElement) e);
                        break;
                    case ElementKind.MEDIA:
                        build_media ((MediaElement) e);
                        break;
                    case ElementKind.DIAGRAM:
                        build_diagram ((DiagramElement) e);
                        break;
                    case ElementKind.ZOOM:
                        build_zoom ((ZoomElement) e);
                        break;
                    case ElementKind.EQUATION:
                        build_equation ((EquationElement) e);
                        break;
                    case ElementKind.INK:
                        build_ink ((InkElement) e);
                        break;
                    case ElementKind.FOREIGN:
                        build_foreign ((ForeignElement) e);
                        break;
                    case ElementKind.MODEL3D:
                        build_model ((Model3DElement) e);
                        break;
                }
            } else {
                build_multi ();
            }
            syncing = false;
        }

        public void sync_geometry () {
            if (canvas.selection.size != 1 || x_row == null) return;
            var e = canvas.selection[0];
            syncing = true;
            x_row.value = Math.round (e.x * 10) / 10;
            y_row.value = Math.round (e.y * 10) / 10;
            w_row.value = Math.round (e.w * 10) / 10;
            h_row.value = Math.round (e.h * 10) / 10;
            if (r_row != null) r_row.value = e.rotation;
            syncing = false;
        }

        private void build_slide () {
            var s = canvas.slide;
            var p = doc.pres;
            var lg = group (_("Layout"), _("Placeholders and their positions"));
            var layouts = p.master_for (s).layouts;
            string[] names = new string[layouts.size];
            int cur = -1;
            for (int i = 0; i < layouts.size; i++) {
                names[i] = layouts[i].name;
                if (layouts[i].id == s.layout_id) cur = i;
            }
            choice (lg, _("Slide Layout"), names, cur, (v) => {
                Factory.apply_layout (p, s, layouts[(int) v]);
                canvas.clear_selection ();
            });
            toggle (lg, _("Hide Slide"), _("Skip this slide while presenting"), s.hidden, (v) => s.hidden = v);
            toggle (lg, _("Show Theme Decorations"), null, s.show_master_shapes, (v) => s.show_master_shapes = v);

            var bg = group (_("Background"));
            fill_editor (bg, s.background ?? p.background_for (s).clone (), true, s.background == null, (f) => s.background = f);
            button_row (bg, _("Apply to All Slides"), null, "edit-copy-symbolic", () => {
                edit (_("Background"), () => {
                    foreach (var o in p.slides) o.background = s.background != null ? s.background.clone () : null;
                });
                win.refresh_thumbnails ();
            });

            var tg = group (_("Theme"), _("Colors, fonts and backgrounds for the whole presentation"));
            var flow = new FlowBox ();
            flow.selection_mode = SelectionMode.NONE;
            flow.max_children_per_line = 2;
            flow.min_children_per_line = 2;
            flow.column_spacing = 6;
            flow.row_spacing = 6;
            flow.margin_top = 6;
            flow.margin_bottom = 6;
            flow.margin_start = 6;
            flow.margin_end = 6;
            foreach (var preset in ThemePreset.all ()) {
                var b = new ToggleButton ();
                b.add_css_class ("flat");
                b.add_css_class ("slides-theme-card");
                b.active = p.theme.id == preset.id;
                b.tooltip_text = preset.name;
                var vb = new Box (Orientation.VERTICAL, 4);
                var pic = new Picture ();
                pic.paintable = theme_preview (preset);
                pic.can_shrink = true;
                pic.set_size_request (120, 68);
                vb.append (pic);
                var l = new Label (preset.name);
                l.add_css_class ("caption");
                vb.append (l);
                b.child = vb;
                var pr = preset;
                b.clicked.connect (() => {
                    if (syncing) return;
                    win.apply_theme (pr);
                });
                flow.append (b);
            }
            tg.add_row (flow);

            var hf = group (_("Header and Footer"), _("Shown on every slide"));
            bool has_num = false, has_ftr = false, has_dt = false;
            foreach (var o in p.slides) {
                foreach (var e in o.elements) {
                    if (e.placeholder == PlaceholderKind.SLIDE_NUMBER) has_num = true;
                    if (e.placeholder == PlaceholderKind.FOOTER) has_ftr = true;
                    if (e.placeholder == PlaceholderKind.DATE) has_dt = true;
                }
            }
            toggle (hf, _("Slide Number"), null, has_num, (v) => HeaderFooter.set_meta (p, PlaceholderKind.SLIDE_NUMBER, v, ""));
            toggle (hf, _("Date"), null, has_dt, (v) => HeaderFooter.set_meta (p, PlaceholderKind.DATE, v, ""));
            var ftr = new EntryRow (_("Footer"));
            ftr.text = p.footer_text;
            ftr.entry_changed.connect (() => {
                string t = ftr.text;
                edit (_("Footer"), () => {
                    p.footer_text = t;
                    HeaderFooter.set_meta (p, PlaceholderKind.FOOTER, t != "", t);
                }, "footer");
                win.refresh_thumbnails ();
            });
            hf.add_row (ftr);
        }

        public Gdk.Texture theme_preview (ThemePreset preset) {
            var p = Factory.new_presentation (preset, 960, 540);
            var s = p.slides[0];
            ((ShapeElement) s.elements[0]).text.set_plain (preset.name);
            ((ShapeElement) s.elements[1]).text.set_plain (_("Aa Bb Cc"));
            var r = new Renderer ();
            var surf = r.thumbnail (p, s, 240);
            return ThumbCache.texture_of (surf);
        }

        private void build_master () {
            var p = doc.pres;
            var m = canvas.master ?? p.master;
            if (canvas.layout != null) {
                var l = canvas.layout;
                var lg = group (_("Layout"));
                var name = new EntryRow (_("Name"));
                name.text = l.name;
                name.entry_changed.connect (() => {
                    string t = name.text;
                    edit (_("Rename Layout"), () => l.name = t, "layout-name");
                });
                lg.add_row (name);
                toggle (lg, _("Show Master Decorations"), null, l.show_master_shapes, (v) => l.show_master_shapes = v);
                var bg = group (_("Background"));
                fill_editor (bg, l.background ?? m.background.clone (), true, l.background == null, (f) => l.background = f);
                return;
            }
            var bg = group (_("Background"));
            fill_editor (bg, m.background, false, false, (f) => m.background = f);
            var cg = group (_("Theme Colors"), _("Every object that uses a theme color follows these"));
            string[] keys = { "dk1", "lt1", "dk2", "lt2", "accent1", "accent2", "accent3", "accent4", "accent5", "accent6", "hlink", "folHlink" };
            string[] names = { _("Text 1"), _("Background 1"), _("Text 2"), _("Background 2"), _("Accent 1"), _("Accent 2"), _("Accent 3"), _("Accent 4"), _("Accent 5"), _("Accent 6"), _("Hyperlink"), _("Followed Hyperlink") };
            for (int i = 0; i < keys.length; i++) {
                string k = keys[i];
                var row = new ActionRow (names[i]);
                var b = new ColorButton (m.theme, m.theme.colors[k], false);
                b.chosen.connect ((s) => {
                    var c = m.theme.resolve (s);
                    edit (_("Theme Color"), () => m.theme.colors[k] = c.to_hex ());
                    win.refresh_thumbnails ();
                });
                row.add_suffix (b);
                cg.add_row (row);
            }
            var fg = group (_("Theme Fonts"));
            var major = new EntryRow (_("Headings"));
            major.text = m.theme.major_font;
            major.entry_changed.connect (() => {
                string t = major.text;
                if (t.strip () != "") edit (_("Theme Font"), () => m.theme.major_font = t.strip (), "major");
            });
            fg.add_row (major);
            var minor = new EntryRow (_("Body"));
            minor.text = m.theme.minor_font;
            minor.entry_changed.connect (() => {
                string t = minor.text;
                if (t.strip () != "") edit (_("Theme Font"), () => m.theme.minor_font = t.strip (), "minor");
            });
            fg.add_row (minor);
            var ts = group (_("Text Styles"), _("Default sizes for titles and body levels"));
            spin (ts, _("Title Size"), 8, 200, 1, m.title_style.levels[0].size, 0, (v) => m.title_style.levels[0].size = v, "title-size");
            for (int i = 0; i < 3; i++) {
                int lv = i;
                spin (ts, _("Body Level %d Size").printf (i + 1), 6, 120, 1, m.body_style.levels[i].size, 0, (v) => m.body_style.levels[lv].size = v, "body-size-%d".printf (i));
            }
        }

        public delegate void FillApply (Fill? f);

        private void fill_editor (PreferencesGroup g, Fill initial, bool can_inherit, bool inherited, owned FillApply apply) {
            var fe = new FillEditor (this, win, theme (), g, initial, can_inherit, inherited, (owned) apply);
            fill_editors.add (fe);
        }

        private Gee.ArrayList<FillEditor> fill_editors = new Gee.ArrayList<FillEditor> ();

        public void run_edit (string label, owned Document.EditFunc f, string key = "") {
            edit (label, (owned) f, key);
        }

        private void build_shape (ShapeElement s) {
            bool is_line = s.shape == ShapeKind.LINE;
            if (!is_line) build_text (s);
            if (!is_line) {
                var fg = group (_("Fill"));
                fill_editor (fg, s.fill, false, false, (f) => s.fill = f ?? new Fill.none ());
                double alpha = s.fill.kind == FillKind.SOLID ? ColorSpec.parse (s.fill.color).alpha : 1;
                spin (fg, _("Opacity"), 0, 100, 5, Math.round (alpha * 100), 0, (v) => {
                    if (s.fill.kind == FillKind.SOLID) s.fill.color = ColorSpec.with_alpha (s.fill.color, v / 100);
                }, "opacity");
            }
            build_line (s, is_line);
            build_shadow (s);
            if (!is_line) {
                build_shape_kind (s);
                build_effects (s);
            }
            if (s.text != null && !s.text.is_empty ()) build_wordart (s);
            build_action (s);
            build_position (s);
            build_accessibility (s);
        }

        private void build_line (Element e, bool is_line) {
            var lg = group (is_line ? _("Line") : _("Border"));
            color (lg, _("Color"), e.line.color, !is_line, (v) => {
                e.line.color = v;
                if (v != "" && e.line.width <= 0) e.line.width = 1;
            });
            spin (lg, _("Width"), 0, 50, 0.5, e.line.width, 1, (v) => e.line.width = v, "line-width");
            string[] dashes = { _("Solid"), _("Dashed"), _("Dotted"), _("Dash Dot"), _("Long Dash") };
            choice (lg, _("Style"), dashes, (int) e.line.dash, (v) => e.line.dash = (DashKind) (int) v);
            if (is_line) {
                string[] arrows = { _("None"), _("Triangle"), _("Arrow"), _("Circle"), _("Diamond") };
                choice (lg, _("Start"), arrows, (int) e.line.head, (v) => e.line.head = (ArrowKind) (int) v);
                choice (lg, _("End"), arrows, (int) e.line.tail, (v) => e.line.tail = (ArrowKind) (int) v);
            }
        }

        private void build_shadow (Element e) {
            var sg = group (_("Shadow"));
            toggle (sg, _("Drop Shadow"), null, e.shadow.enabled, (v) => e.shadow.enabled = v);
            color (sg, _("Color"), e.shadow.color, false, (v) => e.shadow.color = v);
            spin (sg, _("Opacity"), 0, 100, 5, Math.round (e.shadow.opacity * 100), 0, (v) => e.shadow.opacity = v / 100, "shadow-opacity");
            spin (sg, _("Blur"), 0, 100, 1, e.shadow.blur, 0, (v) => e.shadow.blur = v, "shadow-blur");
            spin (sg, _("Distance"), 0, 100, 1, e.shadow.distance, 0, (v) => e.shadow.distance = v, "shadow-distance");
            spin (sg, _("Angle"), 0, 359, 15, e.shadow.angle, 0, (v) => e.shadow.angle = v, "shadow-angle");
        }

        private void build_text (ShapeElement s) {
            var tg = group (_("Text"));
            var ctx = canvas.context ();
            var probe = new TextRun ();
            if (canvas.editor != null) probe = canvas.editor.current_format ();
            else if (s.text != null) s.text.first_run_format (probe);
            var level = doc.pres.level_style (ctx.slide, ctx.layout, ctx.master, s, 0);
            string dc = canvas.renderer.default_text_color (ctx, s);
            if (dc != "") level.color = dc;
            var rs = doc.pres.run_style (level, probe, ctx.theme);
            var font_row = new ActionRow (_("Font"));
            var font_btn = new Button.with_label (rs.font);
            font_btn.valign = Align.CENTER;
            font_btn.clicked.connect (() => {
                var dlg = new FontDialog ();
                dlg.title = _("Choose a Font");
                var initial = Pango.FontDescription.from_string (rs.font);
                dlg.choose_family.begin (get_root () as Gtk.Window, null, null, (o, res) => {
                    try {
                        var fam = dlg.choose_family.end (res);
                        if (fam == null) return;
                        string name = fam.get_name ();
                        font_btn.label = name;
                        win.format_runs (_("Font"), (r) => r.font = name);
                    } catch (Error e) {
                    }
                });
                initial = null;
            });
            font_row.add_suffix (font_btn);
            tg.add_row (font_row);
            var size = new SpinRow (_("Size"), null, 4, 400, 1, rs.size);
            size.spin_btn.value_changed.connect (() => {
                if (syncing) return;
                double v = size.spin_btn.value;
                win.format_runs (_("Font Size"), (r) => r.size = v, "font-size");
            });
            tg.add_row (size);
            var styles = tool_row (tg, _("Style"));
            tool (styles, "format-text-bold-symbolic", _("Bold (Ctrl+B)"), "win.bold");
            tool (styles, "format-text-italic-symbolic", _("Italic (Ctrl+I)"), "win.italic");
            tool (styles, "format-text-underline-symbolic", _("Underline (Ctrl+U)"), "win.underline");
            tool (styles, "format-text-strikethrough-symbolic", _("Strikethrough"), "win.strike");
            var crow = new ActionRow (_("Color"));
            var cb = new ColorButton (theme (), probe.color != "" ? probe.color : (level.color != "" ? level.color : "tx1"), false);
            cb.chosen.connect ((v) => win.format_runs (_("Text Color"), (r) => r.color = v));
            crow.add_suffix (cb);
            tg.add_row (crow);
            var hrow = new ActionRow (_("Highlight"));
            var hb = new ColorButton (theme (), probe.highlight, true);
            hb.chosen.connect ((v) => win.format_runs (_("Highlight"), (r) => r.highlight = v));
            hrow.add_suffix (hb);
            tg.add_row (hrow);
            var aligns = tool_row (tg, _("Alignment"));
            tool (aligns, "format-justify-left-symbolic", _("Align Left (Ctrl+L)"), "win.align-left");
            tool (aligns, "format-justify-center-symbolic", _("Center (Ctrl+E)"), "win.align-center");
            tool (aligns, "format-justify-right-symbolic", _("Align Right (Ctrl+R)"), "win.align-right");
            tool (aligns, "format-justify-fill-symbolic", _("Justify (Ctrl+J)"), "win.align-justify");
            var lists = tool_row (tg, _("Lists"));
            tool (lists, "slides-bullets-symbolic", _("Bullets"), "win.bullets");
            tool (lists, "slides-numbering-symbolic", _("Numbering"), "win.numbering");
            tool (lists, "format-indent-less-symbolic", _("Decrease Indent (Alt+Shift+Left)"), "win.indent-less");
            tool (lists, "format-indent-more-symbolic", _("Increase Indent (Alt+Shift+Right)"), "win.indent-more");
            var para = s.text != null && s.text.paragraphs.size > 0 ? s.text.paragraphs[0] : new Paragraph ();
            if (canvas.editor != null) para = canvas.editor.current_paragraph ();
            var ps = doc.pres.para_style (level, para, ctx.theme);
            var spacing = new SpinRow (_("Line Spacing"), null, 0.5, 4, 0.1, ps.line_spacing);
            spacing.spin_btn.digits = 1;
            spacing.spin_btn.value_changed.connect (() => {
                if (syncing) return;
                double v = spacing.spin_btn.value;
                win.format_paragraphs (_("Line Spacing"), (p) => p.line_spacing = v, "line-spacing");
            });
            tg.add_row (spacing);
            var before = new SpinRow (_("Space Before"), null, 0, 200, 1, ps.space_before);
            before.spin_btn.value_changed.connect (() => {
                if (syncing) return;
                double v = before.spin_btn.value;
                win.format_paragraphs (_("Spacing"), (p) => p.space_before = v, "space-before");
            });
            tg.add_row (before);
            var after = new SpinRow (_("Space After"), null, 0, 200, 1, ps.space_after);
            after.spin_btn.value_changed.connect (() => {
                if (syncing) return;
                double v = after.spin_btn.value;
                win.format_paragraphs (_("Spacing"), (p) => p.space_after = v, "space-after");
            });
            tg.add_row (after);
            var bg = group (_("Text Box"));
            var body = s.ensure_text ();
            string[] anchors = { _("Top"), _("Middle"), _("Bottom") };
            var anchor = doc.pres.effective_anchor (ctx.slide, ctx.layout, ctx.master, s, body);
            choice (bg, _("Vertical Alignment"), anchors, (int) anchor, (v) => {
                body.anchor = (TextAnchor) (int) v;
                body.anchor_set = true;
            });
            string[] fits = { _("Do Not Fit"), _("Shrink Text on Overflow"), _("Resize Shape to Fit Text") };
            choice (bg, _("Autofit"), fits, (int) body.autofit, (v) => {
                body.autofit = (AutoFit) (int) v;
                if (body.autofit != AutoFit.SHRINK) body.font_scale = 1;
                canvas.fit_text_box (s);
            });
            toggle (bg, _("Wrap Text"), null, body.wrap, (v) => body.wrap = v);
            spin (bg, _("Left Margin"), 0, 200, 1, body.inset_left, 1, (v) => body.inset_left = v, "inset-l");
            spin (bg, _("Right Margin"), 0, 200, 1, body.inset_right, 1, (v) => body.inset_right = v, "inset-r");
            spin (bg, _("Top Margin"), 0, 200, 1, body.inset_top, 1, (v) => body.inset_top = v, "inset-t");
            spin (bg, _("Bottom Margin"), 0, 200, 1, body.inset_bottom, 1, (v) => body.inset_bottom = v, "inset-b");
        }

        private void build_position (Element e) {
            var pg = group (_("Arrange"));
            x_row = spin (pg, _("X"), -10000, 10000, 1, Math.round (e.x * 10) / 10, 1, (v) => {
                e.inherit_geometry = false;
                e.move_by (v - e.x, 0);
            }, "x");
            y_row = spin (pg, _("Y"), -10000, 10000, 1, Math.round (e.y * 10) / 10, 1, (v) => {
                e.inherit_geometry = false;
                e.move_by (0, v - e.y);
            }, "y");
            w_row = spin (pg, _("Width"), 1, 20000, 1, Math.round (e.w * 10) / 10, 1, (v) => {
                e.inherit_geometry = false;
                e.scale_into (e.x, e.y, v, e.h);
                canvas.fit_text_box (e);
            }, "w");
            h_row = spin (pg, _("Height"), 1, 20000, 1, Math.round (e.h * 10) / 10, 1, (v) => {
                e.inherit_geometry = false;
                e.scale_into (e.x, e.y, e.w, v);
            }, "h");
            r_row = spin (pg, _("Rotation"), 0, 359, 1, e.rotation, 0, (v) => e.rotation = v, "rot");
            var order = tool_row (pg, _("Order"));
            tool (order, "slides-bring-front-symbolic", _("Bring to Front"), "win.bring-front");
            tool (order, "slides-bring-forward-symbolic", _("Bring Forward"), "win.bring-forward");
            tool (order, "slides-send-backward-symbolic", _("Send Backward"), "win.send-backward");
            tool (order, "slides-send-back-symbolic", _("Send to Back"), "win.send-back");
            var flips = tool_row (pg, _("Flip and Rotate"));
            tool (flips, "object-flip-horizontal-symbolic", _("Flip Horizontally"), "win.flip-h");
            tool (flips, "object-flip-vertical-symbolic", _("Flip Vertically"), "win.flip-v");
            tool (flips, "object-rotate-left-symbolic", _("Rotate Left"), "win.rotate-left");
            tool (flips, "object-rotate-right-symbolic", _("Rotate Right"), "win.rotate-right");
            build_align (pg);
            toggle (pg, _("Lock"), _("Prevent moving and resizing"), e.locked, (v) => e.locked = v);
        }

        private void build_align (PreferencesGroup pg) {
            var al = tool_row (pg, canvas.selection.size > 1 ? _("Align Objects") : _("Align to Slide"));
            tool (al, "slides-align-left-symbolic", _("Align Left"), "win.arrange-left");
            tool (al, "slides-align-center-symbolic", _("Align Center"), "win.arrange-center");
            tool (al, "slides-align-right-symbolic", _("Align Right"), "win.arrange-right");
            tool (al, "slides-align-top-symbolic", _("Align Top"), "win.arrange-top");
            tool (al, "slides-align-middle-symbolic", _("Align Middle"), "win.arrange-middle");
            tool (al, "slides-align-bottom-symbolic", _("Align Bottom"), "win.arrange-bottom");
            if (canvas.selection.size > 2) {
                var dist = tool_row (pg, _("Distribute"));
                tool (dist, "slides-distribute-h-symbolic", _("Distribute Horizontally"), "win.distribute-h");
                tool (dist, "slides-distribute-v-symbolic", _("Distribute Vertically"), "win.distribute-v");
            }
        }

        private void build_accessibility (Element e) {
            var ag = group (_("Accessibility"));
            var alt = new EntryRow (_("Alternative Text"));
            alt.text = e.description;
            alt.entry_changed.connect (() => {
                string t = alt.text;
                edit (_("Alternative Text"), () => e.description = t, "alt");
            });
            ag.add_row (alt);
        }

        private void build_image (ImageElement img) {
            var ig = group (_("Image"));
            spin (ig, _("Brightness"), -100, 100, 5, Math.round (img.brightness * 100), 0, (v) => img.brightness = v / 100, "bright");
            spin (ig, _("Contrast"), -100, 100, 5, Math.round (img.contrast * 100), 0, (v) => img.contrast = v / 100, "contrast");
            spin (ig, _("Saturation"), 0, 200, 5, Math.round (img.saturation * 100), 0, (v) => img.saturation = v / 100, "sat");
            spin (ig, _("Blur"), 0, 50, 1, img.blur, 0, (v) => img.blur = v, "blur");
            toggle (ig, _("Sepia"), null, img.sepia, (v) => img.sepia = v);
            spin (ig, _("Opacity"), 0, 100, 5, Math.round (img.opacity * 100), 0, (v) => img.opacity = v / 100, "img-opacity");
            spin (ig, _("Rounded Corners"), 0, 50, 1, Math.round (img.corner * 100), 0, (v) => img.corner = v / 100, "img-corner");
            string[] labels = { _("Custom"), _("Original"), _("Black and White"), _("Sepia"), _("Vivid"), _("Faded") };
            choice (ig, _("Preset"), labels, 0, (v) => {
                int k = (int) v;
                if (k == 0) return;
                img.brightness = 0;
                img.contrast = 0;
                img.saturation = 1;
                img.sepia = false;
                img.blur = 0;
                if (k == 2) img.saturation = 0;
                if (k == 3) img.sepia = true;
                if (k == 4) {
                    img.saturation = 1.5;
                    img.contrast = 0.15;
                }
                if (k == 5) {
                    img.saturation = 0.6;
                    img.brightness = 0.12;
                    img.contrast = -0.2;
                }
                Idle.add (() => {
                    rebuild ();
                    return Source.REMOVE;
                });
            });
            var cg = group (_("Crop"), _("Double-click the picture to crop it on the slide"));
            spin (cg, _("Left"), 0, 95, 1, Math.round (img.crop_left * 100), 0, (v) => set_crop (img, v / 100, img.crop_top, img.crop_right, img.crop_bottom), "crop-l");
            spin (cg, _("Top"), 0, 95, 1, Math.round (img.crop_top * 100), 0, (v) => set_crop (img, img.crop_left, v / 100, img.crop_right, img.crop_bottom), "crop-t");
            spin (cg, _("Right"), 0, 95, 1, Math.round (img.crop_right * 100), 0, (v) => set_crop (img, img.crop_left, img.crop_top, v / 100, img.crop_bottom), "crop-r");
            spin (cg, _("Bottom"), 0, 95, 1, Math.round (img.crop_bottom * 100), 0, (v) => set_crop (img, img.crop_left, img.crop_top, img.crop_right, v / 100), "crop-b");
            button_row (cg, _("Crop on Slide"), null, "slides-crop-symbolic", () => {
                canvas.crop_mode = true;
                canvas.queue_draw ();
            });
            button_row (cg, _("Reset Picture"), _("Remove crop and adjustments"), "edit-undo-symbolic", () => {
                edit (_("Reset Picture"), () => {
                    set_crop (img, 0, 0, 0, 0);
                    img.brightness = 0;
                    img.contrast = 0;
                    img.saturation = 1;
                    img.sepia = false;
                    img.blur = 0;
                    img.opacity = 1;
                    int pw, ph;
                    if (ImageCache.size_of (img.data, out pw, out ph) && pw > 0) img.h = img.w * ph / pw;
                });
                rebuild ();
            });
            button_row (cg, _("Replace Picture…"), null, "document-open-symbolic", () => win.replace_image (img));
            button_row (cg, _("Remove Background…"), _("Makes the area around the subject transparent"), "slides-remove-background-symbolic", () => Dialogs.remove_background (win, img));
            build_line (img, false);
            build_shadow (img);
            build_action (img);
            build_position (img);
            build_accessibility (img);
        }

        private void set_crop (ImageElement img, double l, double t, double r, double b) {
            double fw = img.w / double.max (1 - img.crop_left - img.crop_right, 0.01);
            double fh = img.h / double.max (1 - img.crop_top - img.crop_bottom, 0.01);
            double fx = img.x - img.crop_left * fw, fy = img.y - img.crop_top * fh;
            if (l + r > 0.95) r = 0.95 - l;
            if (t + b > 0.95) b = 0.95 - t;
            img.crop_left = l;
            img.crop_top = t;
            img.crop_right = r;
            img.crop_bottom = b;
            img.set_geometry (fx + l * fw, fy + t * fh, fw * (1 - l - r), fh * (1 - t - b));
        }

        private void build_table (TableElement t) {
            var tg = group (_("Table Style"));
            color (tg, _("Style Color"), t.style_color, false, (v) => t.style_color = v);
            toggle (tg, _("Header Row"), null, t.first_row, (v) => t.first_row = v);
            toggle (tg, _("Total Row"), null, t.last_row, (v) => t.last_row = v);
            toggle (tg, _("First Column"), null, t.first_col, (v) => t.first_col = v);
            toggle (tg, _("Banded Rows"), null, t.banded_rows, (v) => t.banded_rows = v);
            toggle (tg, _("Banded Columns"), null, t.banded_cols, (v) => t.banded_cols = v);
            color (tg, _("Border Color"), t.border.color, true, (v) => t.border.color = v);
            spin (tg, _("Border Width"), 0, 20, 0.5, t.border.width, 1, (v) => t.border.width = v, "tborder");
            var rc = group (_("Rows and Columns"), _("Click a cell to choose where; Tab in the last cell adds a row"));
            var rows = tool_row (rc, _("Rows"));
            tool (rows, "slides-row-above-symbolic", _("Insert Row Above"), "win.table-row-above");
            tool (rows, "slides-row-below-symbolic", _("Insert Row Below"), "win.table-row-below");
            tool (rows, "list-remove-symbolic", _("Delete Row"), "win.table-row-delete");
            var cols = tool_row (rc, _("Columns"));
            tool (cols, "slides-col-left-symbolic", _("Insert Column Left"), "win.table-col-left");
            tool (cols, "slides-col-right-symbolic", _("Insert Column Right"), "win.table-col-right");
            tool (cols, "list-remove-symbolic", _("Delete Column"), "win.table-col-delete");
            var cells = tool_row (rc, _("Cells"));
            tool (cells, "slides-merge-symbolic", _("Merge Cells"), "win.table-merge");
            tool (cells, "slides-split-symbolic", _("Split Cell"), "win.table-split");
            tool (cells, "slides-distribute-v-symbolic", _("Distribute Rows"), "win.table-distribute");
            if (canvas.cell_r1 >= 0) {
                var cg = group (_("Selected Cells"));
                int r1 = int.min (canvas.cell_r1, canvas.cell_r2), r2 = int.max (canvas.cell_r1, canvas.cell_r2);
                int c1 = int.min (canvas.cell_c1, canvas.cell_c2), c2 = int.max (canvas.cell_c1, canvas.cell_c2);
                color (cg, _("Cell Fill"), t.cells[r1][c1].fill, true, (v) => {
                    for (int r = r1; r <= r2; r++) for (int c = c1; c <= c2; c++) t.cells[r][c].fill = v;
                });
                string[] anchors = { _("Top"), _("Middle"), _("Bottom") };
                choice (cg, _("Vertical Alignment"), anchors, (int) t.cells[r1][c1].anchor, (v) => {
                    for (int r = r1; r <= r2; r++) for (int c = c1; c <= c2; c++) t.cells[r][c].anchor = (TextAnchor) (int) v;
                });
            }
            var txt = group (_("Text"));
            var styles = tool_row (txt, _("Style"));
            tool (styles, "format-text-bold-symbolic", _("Bold (Ctrl+B)"), "win.bold");
            tool (styles, "format-text-italic-symbolic", _("Italic (Ctrl+I)"), "win.italic");
            tool (styles, "format-text-underline-symbolic", _("Underline (Ctrl+U)"), "win.underline");
            var aligns = tool_row (txt, _("Alignment"));
            tool (aligns, "format-justify-left-symbolic", _("Align Left (Ctrl+L)"), "win.align-left");
            tool (aligns, "format-justify-center-symbolic", _("Center (Ctrl+E)"), "win.align-center");
            tool (aligns, "format-justify-right-symbolic", _("Align Right (Ctrl+R)"), "win.align-right");
            var size = new SpinRow (_("Size"), null, 4, 200, 1, 18);
            size.spin_btn.value_changed.connect (() => {
                if (syncing) return;
                double v = size.spin_btn.value;
                win.format_runs (_("Font Size"), (r) => r.size = v, "font-size");
            });
            txt.add_row (size);
            var crow = new ActionRow (_("Color"));
            var cb = new ColorButton (theme (), "tx1", false);
            cb.chosen.connect ((v) => win.format_runs (_("Text Color"), (r) => r.color = v));
            crow.add_suffix (cb);
            txt.add_row (crow);
            build_position (t);
            build_accessibility (t);
        }

        private void build_chart (ChartElement ch) {
            var cg = group (_("Chart"));
            ChartKind[] kinds = { ChartKind.COLUMN, ChartKind.BAR, ChartKind.LINE, ChartKind.AREA, ChartKind.PIE, ChartKind.DOUGHNUT, ChartKind.SCATTER, ChartKind.BUBBLE, ChartKind.RADAR,
                ChartKind.STOCK, ChartKind.HISTOGRAM, ChartKind.PARETO, ChartKind.BOX_WHISKER, ChartKind.WATERFALL, ChartKind.FUNNEL, ChartKind.TREEMAP, ChartKind.SUNBURST };
            string[] labels = new string[kinds.length];
            int cur = 0;
            for (int i = 0; i < kinds.length; i++) {
                labels[i] = kinds[i].label ();
                if (kinds[i] == ch.chart) cur = i;
            }
            choice (cg, _("Type"), labels, cur, (v) => {
                var k = kinds[(int) v];
                ch.chart = k;
                if (k == ChartKind.BUBBLE) {
                    foreach (var se in ch.series) {
                        if (se.sizes.size > 0) continue;
                        foreach (var val in se.values) se.sizes.add (val != null ? Math.fabs (val) : 1);
                    }
                }
                later_rebuild ();
            });
            bool xy = ch.chart == ChartKind.SCATTER || ch.chart == ChartKind.BUBBLE;
            if (!ch.chart.is_radial () && !xy && ch.chart != ChartKind.RADAR) {
                string[] groups = { _("Clustered"), _("Stacked"), _("100% Stacked") };
                choice (cg, _("Grouping"), groups, (int) ch.grouping, (v) => ch.grouping = (ChartGrouping) (int) v);
            }
            if (ch.chart == ChartKind.RADAR) toggle (cg, _("Filled"), null, ch.grouping == ChartGrouping.STACKED, (v) => ch.grouping = v ? ChartGrouping.STACKED : ChartGrouping.CLUSTERED);
            var title = new EntryRow (_("Title"));
            title.text = ch.title;
            title.entry_changed.connect (() => {
                string t = title.text;
                edit (_("Chart Title"), () => ch.title = t, "chart-title");
            });
            cg.add_row (title);
            string[] legends = { _("None"), _("Bottom"), _("Right"), _("Top"), _("Left") };
            choice (cg, _("Legend"), legends, (int) ch.legend, (v) => ch.legend = (LegendPosition) (int) v);
            toggle (cg, _("Data Labels"), null, ch.data_labels, (v) => ch.data_labels = v);
            if (!ch.chart.is_radial ()) toggle (cg, _("Gridlines"), null, ch.gridlines, (v) => ch.gridlines = v);
            if (ch.chart == ChartKind.LINE || ch.chart == ChartKind.SCATTER) toggle (cg, _("Smooth Lines"), null, ch.smooth, (v) => ch.smooth = v);
            color (cg, _("Text Color"), ch.text_color, true, (v) => ch.text_color = v);
            button_row (cg, _("Edit Data…"), _("Categories, series and values"), "document-edit-symbolic", () => win.edit_chart_data (ch));
            if (!ch.chart.is_radial () && !ch.chart.is_chartex () && ch.series.size > 0) {
                var sg = group (_("Series"), _("Chart type, axis and trendline for each series"));
                for (int i = 0; i < ch.series.size; i++) {
                    var s = ch.series[i];
                    var row = new ExpanderRow (s.name, s.trend != TrendKind.NONE ? _("Trendline: %s").printf (s.trend.label ()) : null);
                    var cb = new ColorButton (theme (), ChartPainter.series_color (ch, i), false);
                    cb.valign = Align.CENTER;
                    cb.chosen.connect ((v) => edit (_("Series Color"), () => s.color = v));
                    row.add_suffix (cb);
                    bool combo = !xy && ch.chart != ChartKind.RADAR && ch.chart != ChartKind.BAR;
                    if (combo) {
                        SeriesKind[] sk = { SeriesKind.AUTO, SeriesKind.COLUMN, SeriesKind.LINE, SeriesKind.AREA };
                        string[] sl = new string[sk.length];
                        for (int k = 0; k < sk.length; k++) sl[k] = sk[k].label ();
                        row.add_row (sub_choice (_("Chart Type"), sl, (int) s.kind, (v) => s.kind = sk[(int) v]));
                        row.add_row (sub_toggle (_("Secondary Axis"), s.secondary, (v) => {
                            s.secondary = v;
                            later_rebuild ();
                        }));
                    }
                    if (ch.chart != ChartKind.RADAR) {
                        TrendKind[] tk = { TrendKind.NONE, TrendKind.LINEAR, TrendKind.EXPONENTIAL, TrendKind.LOGARITHMIC, TrendKind.POLYNOMIAL, TrendKind.POWER, TrendKind.MOVING_AVERAGE };
                        string[] tl = new string[tk.length];
                        for (int k = 0; k < tk.length; k++) tl[k] = tk[k].label ();
                        row.add_row (sub_choice (_("Trendline"), tl, (int) s.trend, (v) => {
                            s.trend = tk[(int) v];
                            later_rebuild ();
                        }));
                        if (s.trend == TrendKind.POLYNOMIAL) row.add_row (sub_spin (_("Order"), 2, 6, 1, s.trend_order, (v) => s.trend_order = (int) v, "trend-order-%d".printf (i)));
                        if (s.trend == TrendKind.MOVING_AVERAGE) row.add_row (sub_spin (_("Period"), 2, 50, 1, s.trend_period, (v) => s.trend_period = (int) v, "trend-period-%d".printf (i)));
                        if (s.trend != TrendKind.NONE && s.trend != TrendKind.MOVING_AVERAGE) {
                            row.add_row (sub_toggle (_("Display Equation"), s.trend_equation, (v) => s.trend_equation = v));
                            row.add_row (sub_toggle (_("Display R-squared Value"), s.trend_r2, (v) => s.trend_r2 = v));
                        }
                    }
                    sg.add_row (row);
                }
                build_chart_axis (ch.chart == ChartKind.BAR ? _("Horizontal Axis") : _("Vertical Axis"), ch.val_axis, true);
                if (ch.chart != ChartKind.RADAR) build_chart_axis (xy ? _("Horizontal Axis") : (ch.chart == ChartKind.BAR ? _("Vertical Axis") : _("Horizontal Axis")), ch.cat_axis, xy);
                if (ch.has_secondary ()) build_chart_axis (_("Secondary Vertical Axis"), ch.sec_axis, true);
            }
            build_position (ch);
            build_accessibility (ch);
        }

        private void build_chart_axis (string title, ChartAxis ax, bool values) {
            var g = group (title);
            var t = new EntryRow (_("Axis Title"));
            t.text = ax.title;
            t.entry_changed.connect (() => {
                string v = t.text;
                edit (_("Axis Title"), () => ax.title = v, "axis-title-" + title);
            });
            g.add_row (t);
            toggle (g, _("Show Axis"), null, ax.visible, (v) => ax.visible = v);
            toggle (g, _("Values in Reverse Order"), null, ax.reverse, (v) => ax.reverse = v);
            if (!values) return;
            toggle (g, _("Fixed Minimum"), null, !ax.min.is_nan (), (v) => {
                ax.min = v ? 0 : double.NAN;
                later_rebuild ();
            });
            if (!ax.min.is_nan ()) spin (g, _("Minimum"), -1e9, 1e9, 1, ax.min, 2, (v) => ax.min = v, "axis-min-" + title);
            toggle (g, _("Fixed Maximum"), null, !ax.max.is_nan (), (v) => {
                ax.max = v ? 100 : double.NAN;
                later_rebuild ();
            });
            if (!ax.max.is_nan ()) spin (g, _("Maximum"), -1e9, 1e9, 1, ax.max, 2, (v) => ax.max = v, "axis-max-" + title);
            spin (g, _("Major Unit (0 for Automatic)"), 0, 1e9, 1, ax.major, 2, (v) => ax.major = v, "axis-major-" + title);
            toggle (g, _("Logarithmic Scale"), null, ax.log_base > 1, (v) => ax.log_base = v ? 10 : 0);
            string[] fmts = { "", "0", "0.0", "0.00", "#,##0", "#,##0.00", "0%", "0.0%", "\"$\"#,##0", "#,##0\" €\"" };
            string[] fl = { _("General"), "0", "0.0", "0.00", "1,234", "1,234.00", "0%", "0.0%", "$1,234", "1,234 €" };
            int fc = 0;
            for (int k = 0; k < fmts.length; k++) if (fmts[k] == ax.format) fc = k;
            choice (g, _("Number Format"), fl, fc, (v) => ax.format = fmts[(int) v]);
        }

        private SelectionRow sub_choice (string title, owned string[] labels, int current, owned SpinApply apply) {
            var row = new SelectionRow (title, labels, current >= 0 && current < labels.length ? labels[current] : "");
            row.selected.connect ((item) => {
                for (int i = 0; i < labels.length; i++) {
                    if (labels[i] == item) {
                        int v = i;
                        edit (title, () => apply (v));
                        break;
                    }
                }
            });
            return row;
        }

        private SwitchRow sub_toggle (string title, bool value, owned BoolApply apply) {
            var row = new SwitchRow (title, null, value);
            row.switch_btn.notify["active"].connect (() => {
                bool v = row.switch_btn.active;
                edit (title, () => apply (v));
            });
            return row;
        }

        private SpinRow sub_spin (string title, double min, double max, double step, double value, owned SpinApply apply, string key) {
            var row = new SpinRow (title, null, min, max, step, value);
            row.spin_btn.value_changed.connect (() => {
                double v = row.spin_btn.value;
                edit (title, () => apply (v), key);
            });
            return row;
        }

        private void build_group (GroupElement g) {
            var gg = group (_("Group"), _("%d objects").printf (g.children.size));
            button_row (gg, _("Ungroup"), null, "slides-ungroup-symbolic", () => win.run ("ungroup"));
            build_shadow (g);
            build_position (g);
        }

        private void build_multi () {
            var sel = canvas.selection;
            var mg = group (_("Selection"), _("%d objects").printf (sel.size));
            button_row (mg, _("Group"), null, "slides-group-symbolic", () => win.run ("group"));
            var first = sel[0] as ShapeElement;
            if (first != null && first.shape != ShapeKind.LINE) {
                var fg = group (_("Fill"));
                color (fg, _("Color"), first.fill.first_color (), true, (v) => {
                    foreach (var e in sel) {
                        var s = e as ShapeElement;
                        if (s != null && s.shape != ShapeKind.LINE) s.fill = v == "" ? new Fill.none () : new Fill.solid (v);
                    }
                });
            }
            var lg = group (_("Border"));
            color (lg, _("Color"), sel[0].line.color, true, (v) => {
                foreach (var e in sel) {
                    e.line.color = v;
                    if (v != "" && e.line.width <= 0) e.line.width = 1;
                }
            });
            var sg = group (_("Shadow"));
            toggle (sg, _("Drop Shadow"), null, sel[0].shadow.enabled, (v) => {
                foreach (var e in sel) e.shadow.enabled = v;
            });
            build_merge ();
            var pg = group (_("Arrange"));
            var order = tool_row (pg, _("Order"));
            tool (order, "slides-bring-front-symbolic", _("Bring to Front"), "win.bring-front");
            tool (order, "slides-send-back-symbolic", _("Send to Back"), "win.send-back");
            build_align (pg);
        }

        private void build_shape_kind (ShapeElement s) {
            var sg = group (_("Shape"));
            var change = new ActionRow (_("Change Shape"), s.shape == ShapeKind.CUSTOM ? _("Freeform") : PresetLabels.label (s.preset_name ()));
            var cbtn = new Button.with_label (_("Choose…"));
            cbtn.valign = Align.CENTER;
            cbtn.clicked.connect (() => {
                Galleries.shapes (win, _("Change Shape"), (name) => {
                    edit (_("Change Shape"), () => {
                        if (ShapeKind.is_native (name)) {
                            s.shape = ShapeKind.from_ooxml (name);
                            s.preset = "";
                        } else {
                            s.shape = ShapeKind.PRESET;
                            s.preset = name;
                        }
                        s.adjust_values.clear ();
                        s.path.clear ();
                    });
                    rebuild ();
                });
            });
            change.add_suffix (cbtn);
            sg.add_row (change);
            if (s.shape == ShapeKind.RECT || s.shape == ShapeKind.ROUND_RECT) {
                spin (sg, _("Rounded Corners"), 0, 50, 1, s.shape == ShapeKind.ROUND_RECT ? Math.round (s.corner * 100) : 0, 0, (v) => {
                    s.corner = v / 100;
                    s.shape = v > 0 ? ShapeKind.ROUND_RECT : ShapeKind.RECT;
                }, "corner");
            } else if (Geometry.uses_preset (s)) {
                var defs = PresetGeometry.defaults (s.preset_name ());
                var keys = new Gee.ArrayList<string> ();
                keys.add_all (defs.keys);
                keys.sort ();
                int n = 0;
                foreach (string k in keys) {
                    string kk = k;
                    double cur = s.adjust_values.has_key (k) ? s.adjust_values[k] : defs[k];
                    spin (sg, keys.size == 1 ? _("Adjustment") : _("Adjustment %d").printf (++n), -200000, 200000, 1000, cur, 0, (v) => s.adjust_values[kk] = v, "adj-" + k);
                }
            }
            if (s.shape == ShapeKind.CUSTOM) {
                toggle (sg, _("Edit Points"), _("Drag points; double-click a line to add one, right-click a point to remove it"), canvas.points_mode, (v) => {
                    canvas.points_mode = v;
                    canvas.queue_draw ();
                });
            } else {
                button_row (sg, _("Convert to Freeform"), _("Lets you edit the points of this shape"), "slides-shape-symbolic", () => win.run ("convert-freeform"));
            }
        }

        private void build_effects (ShapeElement s) {
            var fx = s.effects;
            var eg = group (_("Effects"));
            color (eg, _("Glow"), fx.glow_color, true, (v) => {
                fx.glow_color = v;
                if (v != "" && fx.glow_radius <= 0) fx.glow_radius = 8;
            });
            spin (eg, _("Glow Size"), 0, 100, 1, fx.glow_radius, 0, (v) => fx.glow_radius = v, "glow");
            spin (eg, _("Soft Edges"), 0, 100, 1, fx.soft_edge, 0, (v) => fx.soft_edge = v, "soft");
            toggle (eg, _("Reflection"), null, fx.reflection, (v) => fx.reflection = v);
            spin (eg, _("Reflection Size"), 5, 100, 5, Math.round (fx.reflection_size * 100), 0, (v) => fx.reflection_size = v / 100, "refl-size");
            string[] bevels = { _("None"), _("Circle"), _("Relaxed Inset"), _("Cross"), _("Cool Slant"), _("Angle"), _("Soft Round"), _("Convex"), _("Slope"), _("Divot"), _("Riblet"), _("Hard Edge"), _("Art Deco") };
            int bcur = 0;
            for (int i = 0; i < ShapeEffects.BEVELS.length; i++) if (ShapeEffects.BEVELS[i] == fx.bevel) bcur = i + 1;
            choice (eg, _("Bevel"), bevels, bcur, (v) => fx.bevel = v > 0 ? ShapeEffects.BEVELS[(int) v - 1] : "");
            spin (eg, _("3-D Rotation X"), -80, 80, 5, fx.rot_y, 0, (v) => fx.rot_y = v, "rot3dx");
            spin (eg, _("3-D Rotation Y"), -80, 80, 5, fx.rot_x, 0, (v) => fx.rot_x = v, "rot3dy");
        }

        private void build_wordart (ShapeElement s) {
            var fx = s.effects;
            var wg = group (_("Text Effects"));
            color (wg, _("Text Outline"), fx.text_outline, true, (v) => fx.text_outline = v);
            spin (wg, _("Outline Width"), 0.25, 20, 0.25, fx.text_outline_width, 2, (v) => fx.text_outline_width = v, "to-width");
            string grad_a = fx.text_fill.contains (">") ? fx.text_fill.split (">")[0] : "";
            color (wg, _("Gradient Text"), grad_a, true, (v) => fx.text_fill = v == "" ? "" : v + ">" + ColorSpec.tint (v, 0.55, 0));
            color (wg, _("Text Glow"), fx.text_glow, true, (v) => {
                fx.text_glow = v;
                if (v != "" && fx.text_glow_radius <= 0) fx.text_glow_radius = 5;
            });
            toggle (wg, _("Text Shadow"), null, fx.text_shadow, (v) => fx.text_shadow = v);
            toggle (wg, _("Text Reflection"), null, fx.text_reflection, (v) => fx.text_reflection = v);
            string[] warps = { _("None"), _("Arch Up"), _("Arch Down"), _("Circle"), _("Button"), _("Wave 1"), _("Wave 2"), _("Double Wave"),
                _("Inflate"), _("Deflate"), _("Slant Up"), _("Slant Down"), _("Triangle Up"), _("Triangle Down"), _("Chevron Up"), _("Chevron Down"),
                _("Fade Right"), _("Fade Left"), _("Fade Up"), _("Fade Down"), _("Curve Up"), _("Curve Down"), _("Can Up"), _("Can Down"), _("Stop") };
            int wcur = 0;
            for (int i = 0; i < ShapeEffects.WARPS.length - 1; i++) if (ShapeEffects.WARPS[i] == fx.text_warp) wcur = i + 1;
            choice (wg, _("Transform"), warps, wcur, (v) => fx.text_warp = v > 0 ? ShapeEffects.WARPS[(int) v - 1] : "");
        }

        private void build_action (Element e) {
            var ag = group (_("Action"), _("What happens during the slideshow"));
            action_rows (ag, _("On Click"), e.click, (a) => e.click = a);
            action_rows (ag, _("On Mouse Over"), e.hover, (a) => e.hover = a);
        }

        public delegate void ActionApply (ClickAction? a);

        private void action_rows (PreferencesGroup g, string title, ClickAction? current, owned ActionApply apply) {
            var kinds = ActionKind.ALL;
            string[] labels = {};
            int cur = 0;
            for (int i = 0; i < kinds.length; i++) {
                labels += kinds[i].label ();
                if (current != null && current.kind == kinds[i]) cur = i;
            }
            var p = doc.pres;
            choice (g, title, labels, cur, (v) => {
                var k = kinds[(int) v];
                if (k == ActionKind.NONE) {
                    apply (null);
                } else {
                    var a = new ClickAction (k);
                    if (k == ActionKind.SLIDE && p.slides.size > 0) a.slide_uid = p.slides[0].uid;
                    if (k == ActionKind.CUSTOM_SHOW && p.custom_shows.size > 0) a.target = p.custom_shows[0].name;
                    apply (a);
                }
                later_rebuild ();
            });
            if (current == null) return;
            if (current.kind == ActionKind.SLIDE) {
                string[] names = {};
                int sc = 0;
                for (int i = 0; i < p.slides.size; i++) {
                    string t = p.slides[i].title ();
                    names += t != "" ? _("%d. %s").printf (i + 1, t) : _("Slide %d").printf (i + 1);
                    if (p.slides[i].uid == current.slide_uid) sc = i;
                }
                choice (g, _("Slide"), names, sc, (v) => current.slide_uid = p.slides[(int) v].uid);
            } else if (current.kind == ActionKind.URL || current.kind == ActionKind.FILE || current.kind == ActionKind.PROGRAM) {
                var entry = new EntryRow (current.kind == ActionKind.URL ? _("Address") : _("File"));
                entry.text = current.target;
                entry.entry_changed.connect (() => {
                    string t = entry.text;
                    edit (_("Action"), () => current.target = t, "action-target");
                });
                g.add_row (entry);
            } else if (current.kind == ActionKind.CUSTOM_SHOW) {
                string[] shows = {};
                int ci = 0;
                for (int i = 0; i < p.custom_shows.size; i++) {
                    shows += p.custom_shows[i].name;
                    if (p.custom_shows[i].name == current.target) ci = i;
                }
                if (shows.length > 0) choice (g, _("Custom Show"), shows, ci, (v) => current.target = p.custom_shows[(int) v].name);
                toggle (g, _("Show and Return"), null, current.show_and_return, (v) => current.show_and_return = v);
            }
            if (current.kind != ActionKind.NONE) toggle (g, _("Highlight When Clicked"), null, current.highlight, (v) => current.highlight = v);
        }

        private void later_rebuild () {
            Idle.add (() => {
                rebuild ();
                return Source.REMOVE;
            });
        }

        private void build_media (MediaElement m) {
            var mg = group (m.is_video ? _("Video") : _("Audio"), m.length > 0 ? _("%s long").printf (fmt_time (m.length)) : null);
            string[] starts = { MediaStart.IN_SEQUENCE.label (), MediaStart.AUTOMATIC.label (), MediaStart.ON_CLICK.label () };
            choice (mg, _("Start"), starts, (int) m.start, (v) => m.start = (MediaStart) (int) v);
            spin (mg, _("Volume"), 0, 100, 5, Math.round (m.volume * 100), 0, (v) => m.volume = v / 100, "volume");
            toggle (mg, _("Mute"), null, m.muted, (v) => m.muted = v);
            toggle (mg, _("Loop Until Stopped"), null, m.loop, (v) => m.loop = v);
            toggle (mg, _("Rewind After Playing"), null, m.rewind, (v) => m.rewind = v);
            toggle (mg, _("Hide While Not Playing"), null, m.hide_when_stopped, (v) => m.hide_when_stopped = v);
            if (m.is_video) toggle (mg, _("Play Full Screen"), null, m.full_screen, (v) => m.full_screen = v);
            toggle (mg, _("Play Across Slides"), null, m.across_slides, (v) => m.across_slides = v);
            var tg = group (_("Trim and Fade"));
            double len = m.length > 0 ? m.length : 3600;
            spin (tg, _("Start Time (seconds)"), 0, len, 0.1, m.trim_start, 1, (v) => m.trim_start = v, "trim-start");
            spin (tg, _("End Time (seconds)"), 0, len, 0.1, m.length > 0 ? m.length - m.trim_end : 0, 1, (v) => m.trim_end = m.length > 0 ? double.max (m.length - v, 0) : 0, "trim-end");
            spin (tg, _("Fade In (seconds)"), 0, 30, 0.25, m.fade_in, 2, (v) => m.fade_in = v, "fade-in");
            spin (tg, _("Fade Out (seconds)"), 0, 30, 0.25, m.fade_out, 2, (v) => m.fade_out = v, "fade-out");
            var bg = group (_("Bookmarks"), _("Points you can trigger animations from"));
            foreach (var b in m.bookmarks) {
                var row = new ActionRow (b.name, fmt_time (b.time));
                var del = new Button.from_icon_name ("user-trash-symbolic");
                del.add_css_class ("flat");
                del.valign = Align.CENTER;
                del.tooltip_text = _("Remove Bookmark");
                var bb = b;
                del.clicked.connect (() => {
                    edit (_("Remove Bookmark"), () => m.bookmarks.remove (bb));
                    later_rebuild ();
                });
                row.add_suffix (del);
                bg.add_row (row);
            }
            var add = new SpinRow (_("Add at (seconds)"), null, 0, len, 0.5, m.trim_start);
            var add_btn = new Button.from_icon_name ("list-add-symbolic");
            add_btn.valign = Align.CENTER;
            add_btn.tooltip_text = _("Add Bookmark");
            add_btn.clicked.connect (() => {
                double t = add.value;
                edit (_("Add Bookmark"), () => m.bookmarks.add (new MediaBookmark (_("Bookmark %d").printf (m.bookmarks.size + 1), t)));
                later_rebuild ();
            });
            add.add_suffix (add_btn);
            bg.add_row (add);
            if (m.is_video) {
                var pg = group (_("Poster Frame"));
                button_row (pg, _("Choose Image…"), _("Shown before the video plays"), "insert-image-symbolic", () => {
                    win.choose_image.begin ((o, r) => {
                        string mime;
                        var data = win.choose_image.end (r, out mime);
                        if (data == null) return;
                        edit (_("Poster Frame"), () => {
                            m.poster = data;
                            m.poster_mime = mime;
                        });
                    });
                });
            }
            build_position (m);
            build_accessibility (m);
        }

        private static string fmt_time (double secs) {
            int s = (int) Math.round (secs);
            return "%d:%02d".printf (s / 60, s % 60);
        }

        private void build_diagram (DiagramElement d) {
            var lg = group (_("SmartArt"), d.layout.label ());
            var change = new ActionRow (_("Layout"), d.layout.category ().label ());
            var cbtn = new Button.with_label (_("Change…"));
            cbtn.valign = Align.CENTER;
            cbtn.clicked.connect (() => {
                Galleries.smartart (win, (l) => {
                    edit (_("SmartArt Layout"), () => d.layout = l);
                    rebuild ();
                });
            });
            change.add_suffix (cbtn);
            lg.add_row (change);
            string[] colors = {};
            foreach (var c in DiagramColors.ALL) colors += c.label ();
            choice (lg, _("Colors"), colors, (int) d.colors, (v) => d.colors = (DiagramColors) (int) v);
            string[] styles = {};
            foreach (var st in DiagramStyle.ALL) styles += st.label ();
            choice (lg, _("Style"), styles, (int) d.style, (v) => d.style = (DiagramStyle) (int) v);
            var tg = group (_("Text Pane"), _("Each row is a shape; indent to make a bullet under the one above"));
            foreach (var n in d.flat ()) {
                int depth = 0;
                var p = d.parent_of (n);
                while (p != null && depth < 10) {
                    depth++;
                    p = d.parent_of (p);
                }
                var row = new EntryRow ((depth > 0 ? string.nfill (depth * 2, ' ') + "• " : "") + _("Text"));
                row.text = n.plain ();
                var nn = n;
                row.entry_changed.connect (() => {
                    string t = row.text;
                    edit (_("SmartArt Text"), () => nn.set_plain (t), "dg-%p".printf (nn));
                });
                var box = new Box (Orientation.HORIZONTAL, 0);
                box.valign = Align.CENTER;
                string[] icons = { "format-indent-less-symbolic", "format-indent-more-symbolic", "go-up-symbolic", "go-down-symbolic", "list-add-symbolic", "user-trash-symbolic" };
                string[] tips = { _("Promote"), _("Demote"), _("Move Up"), _("Move Down"), _("Add Shape After"), _("Remove") };
                for (int k = 0; k < icons.length; k++) {
                    var b = new Button.from_icon_name (icons[k]);
                    b.add_css_class ("flat");
                    b.tooltip_text = tips[k];
                    int op = k;
                    b.clicked.connect (() => {
                        edit (tips[op], () => {
                            switch (op) {
                                case 0: d.promote (nn); break;
                                case 1: d.demote (nn); break;
                                case 2: d.move (nn, -1); break;
                                case 3: d.move (nn, 1); break;
                                case 4: d.add_after (nn, new DiagramNode (_("Text"))); break;
                                default: d.remove (nn); break;
                            }
                        });
                        later_rebuild ();
                    });
                    box.append (b);
                }
                row.add_suffix (box);
                tg.add_row (row);
            }
            button_row (tg, _("Add Shape"), null, "list-add-symbolic", () => {
                edit (_("Add Shape"), () => d.nodes.add (new DiagramNode (_("Text"))));
                later_rebuild ();
            });
            if (d.original != null && d.pristine ()) {
                var note = new ActionRow (_("Original PowerPoint Graphic"), _("Kept exactly as it came until you edit it"));
                tg.add_row (note);
            }
            var cg = group (_("Convert"));
            button_row (cg, _("Convert to Shapes"), _("Turns the graphic into a group you can edit freely"), "slides-ungroup-symbolic", () => win.run ("diagram-to-shapes"));
            build_position (d);
            build_accessibility (d);
        }

        private void build_zoom (ZoomElement z) {
            var p = doc.pres;
            var zg = group (z.zoom == ZoomKind.SLIDE ? _("Slide Zoom") : _("Section Zoom"), _("Click it during the slideshow to jump there"));
            string[] names = {};
            int cur = 0;
            for (int i = 0; i < p.slides.size; i++) {
                string t = p.slides[i].title ();
                string sec = p.slides[i].section != null ? p.slides[i].section.name + ": " : "";
                names += "%d. %s%s".printf (i + 1, sec, t);
                if (p.slides[i].uid == z.target_uid) cur = i;
            }
            choice (zg, _("Go To"), names, cur, (v) => {
                var s = p.slides[(int) v];
                z.target_uid = s.uid;
                if (z.zoom != ZoomKind.SLIDE) {
                    int st = p.section_start ((int) v);
                    if (st >= 0) z.section_id = p.slides[st].section.id;
                }
            });
            toggle (zg, _("Return to Zoom"), _("Come back here when the slide or section ends"), z.return_to_zoom, (v) => z.return_to_zoom = v);
            toggle (zg, _("Zoom Transition"), null, z.zoom_transition, (v) => z.zoom_transition = v);
            spin (zg, _("Duration (seconds)"), 0.1, 10, 0.1, z.transition_duration, 1, (v) => z.transition_duration = v, "zoom-dur");
            button_row (zg, _("Change Image…"), _("Shows a picture instead of the live slide"), "insert-image-symbolic", () => {
                win.choose_image.begin ((o, r) => {
                    string mime;
                    var data = win.choose_image.end (r, out mime);
                    if (data == null) return;
                    edit (_("Zoom Image"), () => {
                        z.image = data;
                        z.image_mime = mime;
                    });
                });
            });
            if (z.image != null) button_row (zg, _("Use the Slide Again"), null, "edit-undo-symbolic", () => edit (_("Zoom Image"), () => z.image = null));
            build_position (z);
        }

        private void build_equation (EquationElement q) {
            var eg = group (_("Equation"), q.latex != "" ? q.latex : null);
            button_row (eg, _("Edit Equation…"), _("Opens Formula"), "document-edit-symbolic", () => win.edit_equation.begin (q));
            color (eg, _("Color"), q.color, true, (v) => q.color = v);
            build_position (q);
            build_accessibility (q);
        }

        private void build_ink (InkElement ink) {
            var ig = group (_("Ink"), ngettext ("%d stroke", "%d strokes", ink.strokes.size).printf (ink.strokes.size));
            color (ig, _("Color"), ink.strokes.size > 0 ? ink.strokes[0].color : "#000000", false, (v) => {
                var c = theme ().resolve (v);
                foreach (var st in ink.strokes) st.color = c.to_hex ();
            });
            spin (ig, _("Thickness"), 0.5, 60, 0.5, ink.strokes.size > 0 ? ink.strokes[0].width : 2, 1, (v) => {
                foreach (var st in ink.strokes) st.width = v;
            }, "ink-width");
            button_row (ig, _("Convert to Shape"), _("Turns the strokes into a freeform line"), "slides-shape-symbolic", () => win.run ("ink-to-shape"));
            build_position (ink);
        }

        private void build_model (Model3DElement m) {
            var mg = group (_("3D Model"), m.data == null ? _("The model file is missing; the saved picture is shown") : null);
            string[] views = { _("Front"), _("Back"), _("Left"), _("Right"), _("Top"), _("Bottom"), _("Above Front Left"), _("Above Front Right") };
            double[,] rots = { { 0, 0 }, { 0, 180 }, { 0, 90 }, { 0, -90 }, { 90, 0 }, { -90, 0 }, { 25, 35 }, { 25, -35 } };
            choice (mg, _("View"), views, -1, (v) => {
                m.rot_x = rots[(int) v, 0];
                m.rot_y = rots[(int) v, 1];
                m.rot_z = 0;
                later_rebuild ();
            });
            spin (mg, _("Rotation X"), -360, 360, 5, m.rot_x, 0, (v) => m.rot_x = v, "m3d-x");
            spin (mg, _("Rotation Y"), -360, 360, 5, m.rot_y, 0, (v) => m.rot_y = v, "m3d-y");
            spin (mg, _("Rotation Z"), -360, 360, 5, m.rot_z, 0, (v) => m.rot_z = v, "m3d-z");
            spin (mg, _("Zoom"), 0.2, 5, 0.1, m.zoom, 1, (v) => m.zoom = v, "m3d-zoom");
            button_row (mg, _("Reset 3D Model"), null, "edit-undo-symbolic", () => {
                m.rot_x = m.rot_y = m.rot_z = 0;
                m.zoom = 1;
                later_rebuild ();
            });
            build_position (m);
            build_accessibility (m);
        }

        private void build_foreign (ForeignElement f) {
            var fg = group (f.display_name (), _("This object is kept exactly as it came so other apps can still edit it"));
            fg.add_row (new ActionRow (_("Editable Here"), _("Move, resize, animate or delete it")));
            build_position (f);
            build_accessibility (f);
        }

        private void build_merge () {
            int shapes = 0;
            foreach (var e in canvas.selection) {
                var s = e as ShapeElement;
                if (s != null && s.shape != ShapeKind.LINE) shapes++;
            }
            if (shapes < 2) return;
            var mg = group (_("Merge Shapes"), _("The first selected shape gives the style"));
            var tools_box = tool_row (mg, _("Merge"));
            tool (tools_box, "slides-merge-union-symbolic", _("Union"), "win.merge-union");
            tool (tools_box, "slides-merge-combine-symbolic", _("Combine"), "win.merge-combine");
            tool (tools_box, "slides-merge-fragment-symbolic", _("Fragment"), "win.merge-fragment");
            tool (tools_box, "slides-merge-intersect-symbolic", _("Intersect"), "win.merge-intersect");
            tool (tools_box, "slides-merge-subtract-symbolic", _("Subtract"), "win.merge-subtract");
        }

    }

    public class FillEditor : Object {
        private Inspector owner;
        private SlidesWindow win;
        private Fill f;
        private bool can_inherit;
        private string[] labels;
        private SelectionRow type;
        private ActionRow c1row;
        private ColorButton c1;
        private ActionRow c2row;
        private ColorButton c2;
        private SpinRow angle;
        private SwitchRow radial;
        private ActionRow pick;
        private Button pick_btn;
        private Inspector.FillApply apply;

        public FillEditor (Inspector owner, SlidesWindow win, Theme theme, PreferencesGroup g, Fill initial, bool can_inherit, bool inherited, owned Inspector.FillApply apply) {
            this.owner = owner;
            this.win = win;
            this.apply = (owned) apply;
            this.can_inherit = can_inherit;
            f = initial.clone ();
            labels = can_inherit ? new string[] { _("Same as Layout"), _("Solid Color"), _("Gradient"), _("Picture") } : new string[] { _("None"), _("Solid Color"), _("Gradient"), _("Picture") };
            int cur = inherited ? 0 : (f.kind == FillKind.SOLID ? 1 : (f.kind == FillKind.GRADIENT ? 2 : (f.kind == FillKind.IMAGE ? 3 : 0)));
            type = new SelectionRow (_("Type"), labels, labels[cur]);
            g.add_row (type);
            c1row = new ActionRow (_("Color"));
            c1 = new ColorButton (theme, f.first_color () != "" ? f.first_color () : "accent1", false);
            c1row.add_suffix (c1);
            g.add_row (c1row);
            c2row = new ActionRow (_("Second Color"));
            string second = f.kind == FillKind.GRADIENT && f.stops.size > 1 ? f.stops[f.stops.size - 1].color : ColorSpec.tint (c1.spec, 0.6, 0);
            c2 = new ColorButton (theme, second, false);
            c2row.add_suffix (c2);
            g.add_row (c2row);
            angle = new SpinRow (_("Angle"), null, 0, 359, 5, f.angle);
            g.add_row (angle);
            radial = new SwitchRow (_("Radial"), null, f.radial);
            g.add_row (radial);
            pick = new ActionRow (_("Picture"), _("Fills the area, keeping the proportions"));
            pick_btn = new Button.with_label (_("Choose…"));
            pick_btn.valign = Align.CENTER;
            pick.add_suffix (pick_btn);
            g.add_row (pick);
            update_visibility (cur);
            type.selected.connect ((item) => {
                int k = kind_index (item);
                update_visibility (k);
                if (k == 3 && f.kind != FillKind.IMAGE) {
                    choose_picture ();
                    return;
                }
                changed ();
            });
            c1.chosen.connect (() => changed ());
            c2.chosen.connect (() => changed ());
            angle.spin_btn.value_changed.connect (() => changed ("fill-angle"));
            radial.switch_btn.notify["active"].connect (() => {
                update_visibility (2);
                changed ();
            });
            pick_btn.clicked.connect (choose_picture);
        }

        private int kind_index (string item) {
            for (int i = 0; i < labels.length; i++) if (labels[i] == item) return i;
            return 0;
        }

        private void update_visibility (int k) {
            c1row.visible = k == 1 || k == 2;
            c2row.visible = k == 2;
            angle.visible = k == 2 && !radial.active;
            radial.visible = k == 2;
            pick.visible = k == 3;
        }

        private void choose_picture () {
            win.choose_image.begin ((obj, res) => {
                string mime;
                var data = win.choose_image.end (res, out mime);
                if (data == null) return;
                f = new Fill.picture (data, mime);
                type.current_value = labels[3];
                update_visibility (3);
                changed ();
            });
        }

        private void changed (string key = "") {
            int k = kind_index (type.current_value);
            Fill? nf = null;
            if (k == 1) nf = new Fill.solid (c1.spec);
            else if (k == 2) nf = new Fill.gradient (c1.spec, c2.spec, angle.value, radial.active);
            else if (k == 3) nf = f.kind == FillKind.IMAGE ? f.clone () : null;
            else if (!can_inherit) nf = new Fill.none ();
            if (k == 3 && nf == null) return;
            owner.run_edit (_("Fill"), () => apply (nf), key);
            win.refresh_current_thumbnail ();
        }
    }
}
