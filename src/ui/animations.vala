using Gtk;
using Singularity.Widgets;

namespace Singularity.Apps.Slides {

    public class AnimationPanel : Box {
        private SlidesWindow win;
        private Box content;
        private bool syncing = false;
        private DrawingArea? timeline = null;
        private int expanded_index = -1;

        public delegate void Picked (int section, int index);

        public AnimationPanel (SlidesWindow win) {
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

        private void edit (string label, owned Document.EditFunc f, string key = "") {
            if (syncing) return;
            var doc = win.doc;
            doc.checkpoint (label, key);
            f ();
            doc.touch ();
            win.canvas.queue_draw ();
            win.content_edited ();
            if (timeline != null) timeline.queue_draw ();
        }

        private void later_rebuild () {
            Idle.add (() => {
                rebuild ();
                return Source.REMOVE;
            });
        }

        private SelectionRow choice (string title, owned string[] labels, int current, owned Inspector.SpinApply apply) {
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

        private SpinRow spin (string title, double min, double max, double step, double value, int digits, owned Inspector.SpinApply apply, string key) {
            var row = new SpinRow (title, null, min, max, step, value);
            row.spin_btn.digits = digits;
            row.spin_btn.value_changed.connect (() => {
                double v = row.spin_btn.value;
                edit (title, () => apply (v), key);
            });
            return row;
        }

        private SwitchRow toggle (string title, string? sub, bool value, owned Inspector.SpinApply apply) {
            var row = new SwitchRow (title, sub, value);
            row.switch_btn.notify["active"].connect (() => {
                bool v = row.switch_btn.active;
                edit (title, () => apply (v ? 1 : 0));
            });
            return row;
        }

        public static void gallery (Widget anchor, string[] sections, Gee.List<Gee.ArrayList<string>> labels, int cur_section, int cur_index, owned Picked picked) {
            var pop = new Popover ();
            pop.add_css_class ("slides-gallery-popover");
            var scroll = new ScrolledWindow ();
            scroll.hscrollbar_policy = PolicyType.NEVER;
            scroll.propagate_natural_height = true;
            scroll.max_content_height = 460;
            scroll.min_content_width = 340;
            var box = new Box (Orientation.VERTICAL, 10);
            box.margin_start = box.margin_end = box.margin_top = box.margin_bottom = 8;
            for (int s = 0; s < sections.length; s++) {
                if (labels[s].size == 0) continue;
                var head = new Label (sections[s]);
                head.xalign = 0;
                head.add_css_class ("heading");
                box.append (head);
                var flow = new FlowBox ();
                flow.selection_mode = SelectionMode.NONE;
                flow.max_children_per_line = 3;
                flow.min_children_per_line = 3;
                flow.column_spacing = 4;
                flow.row_spacing = 4;
                flow.homogeneous = true;
                for (int i = 0; i < labels[s].size; i++) {
                    var b = new ToggleButton.with_label (labels[s][i]);
                    b.add_css_class ("flat");
                    b.active = s == cur_section && i == cur_index;
                    ((Label) b.child).ellipsize = Pango.EllipsizeMode.END;
                    b.tooltip_text = labels[s][i];
                    int ss = s, ii = i;
                    b.clicked.connect (() => {
                        pop.popdown ();
                        picked (ss, ii);
                    });
                    flow.append (b);
                }
                box.append (flow);
            }
            scroll.child = box;
            pop.child = scroll;
            pop.set_parent (anchor);
            pop.closed.connect (() => Idle.add (() => {
                pop.unparent ();
                return Source.REMOVE;
            }));
            pop.popup ();
        }

        public void rebuild () {
            Widget? child;
            while ((child = content.get_first_child ()) != null) content.remove (child);
            timeline = null;
            var doc = win.doc;
            var slide = win.canvas.slide;
            if (doc == null || slide == null) {
                var sp = new StatusPage ();
                sp.icon_name = "x-office-presentation";
                sp.title = _("No Slide Selected");
                sp.description = _("Animations belong to slides. Leave the master view to edit them.");
                content.append (sp);
                return;
            }
            syncing = true;
            build_transition (slide);
            build_object (slide);
            build_order (slide);
            syncing = false;
        }

        private static TransitionGroup[] GROUPS = { TransitionGroup.SUBTLE, TransitionGroup.EXCITING, TransitionGroup.DYNAMIC };

        private void build_transition (Slide slide) {
            var g = new PreferencesGroup (_("Transition"), _("How this slide appears"));
            var preview = new Button.from_icon_name ("media-playback-start-symbolic");
            preview.tooltip_text = _("Preview Transition");
            preview.clicked.connect (() => win.canvas_preview_transition ());
            g.add_header_suffix (preview);
            content.append (g);
            var t = slide.transition;
            string[] sections = { _("Subtle"), _("Exciting"), _("Dynamic Content") };
            var kinds = new Gee.ArrayList<Gee.ArrayList<TransitionKind>> ();
            var labels = new Gee.ArrayList<Gee.ArrayList<string>> ();
            int cs = -1, ci = -1;
            for (int s = 0; s < 3; s++) {
                var list = new Gee.ArrayList<TransitionKind> ();
                var names = new Gee.ArrayList<string> ();
                foreach (var k in TransitionKind.ALL) {
                    if (TransitionCatalog.group (k) != GROUPS[s]) continue;
                    if (k == t.kind) {
                        cs = s;
                        ci = list.size;
                    }
                    list.add (k);
                    names.add (k.label ());
                }
                kinds.add (list);
                labels.add (names);
            }
            var eff = new ActionRow (_("Effect"), t.kind.label ());
            var pick = new Button.from_icon_name ("view-grid-symbolic");
            pick.valign = Align.CENTER;
            pick.tooltip_text = _("Choose a Transition");
            pick.clicked.connect (() => gallery (pick, sections, labels, cs, ci, (s, i) => set_transition (kinds[s][i])));
            eff.add_suffix (pick);
            eff.activated.connect (() => pick.clicked ());
            g.add_row (eff);
            if (t.kind != TransitionKind.NONE) {
                var o = TransitionCatalog.options (t.kind);
                if (o == TransitionOptions.DIR4 || o == TransitionOptions.DIR8) {
                    var eo = o == TransitionOptions.DIR4 ? EffectOptions.DIR4 : EffectOptions.DIR8;
                    var vals = EffectCatalog.option_values (eo);
                    int cur = 0;
                    for (int i = 0; i < vals.length; i++) if (vals[i] == t.subtype) cur = i;
                    g.add_row (choice (_("Effect Options"), EffectCatalog.option_labels (eo), cur, (v) => t.subtype = vals[(int) v]));
                } else {
                    var vl = TransitionCatalog.variant_labels (o);
                    if (vl.length > 0) g.add_row (choice (_("Effect Options"), vl, t.variant, (v) => t.variant = (int) v));
                }
                g.add_row (spin (_("Duration (seconds)"), 0.01, 59, 0.1, t.duration, 2, (v) => t.duration = v, "tr-dur"));
            }
            g.add_row (sound_row (t.sound, t.sound_data != null, (name, data) => {
                t.sound = name;
                t.sound_data = data;
            }));
            if (t.sound_data != null) g.add_row (toggle (_("Loop Until Next Sound"), null, t.sound_loop, (v) => t.sound_loop = v > 0));
            var click = new SwitchRow (_("Advance on Click"), null, t.on_click);
            click.switch_btn.notify["active"].connect (() => {
                bool v = click.switch_btn.active;
                edit (_("Advance"), () => t.on_click = v);
            });
            g.add_row (click);
            var auto = new SwitchRow (_("Advance Automatically"), _("Also used by Rehearse Timings"), t.advance_after >= 0);
            var after = new SpinRow (_("After (seconds)"), null, 0, 3600, 0.5, double.max (t.advance_after, 0));
            after.spin_btn.digits = 1;
            after.visible = t.advance_after >= 0;
            auto.switch_btn.notify["active"].connect (() => {
                bool v = auto.switch_btn.active;
                after.visible = v;
                double sec = after.spin_btn.value;
                edit (_("Advance"), () => t.advance_after = v ? sec : -1);
            });
            after.spin_btn.value_changed.connect (() => {
                double v = after.spin_btn.value;
                edit (_("Advance"), () => t.advance_after = v, "tr-after");
            });
            g.add_row (auto);
            g.add_row (after);
            var all = new ActionRow (_("Apply to All Slides"));
            var all_btn = new Button.from_icon_name ("edit-copy-symbolic");
            all_btn.valign = Align.CENTER;
            all_btn.tooltip_text = _("Apply to All Slides");
            all_btn.action_name = "win.transition-all";
            all.add_suffix (all_btn);
            g.add_row (all);
        }

        public delegate void SoundApply (string name, Bytes? data);

        private ActionRow sound_row (string current, bool has, owned SoundApply apply) {
            var row = new ActionRow (_("Sound"), has ? (current != "" ? current : _("Custom Sound")) : _("No Sound"));
            var choose = new Button.from_icon_name ("document-open-symbolic");
            choose.valign = Align.CENTER;
            choose.tooltip_text = _("Choose a Sound");
            choose.clicked.connect (() => pick_sound.begin ((obj, res) => {
                string name;
                var data = pick_sound.end (res, out name);
                if (data == null) return;
                edit (_("Sound"), () => apply (name, data));
                later_rebuild ();
            }));
            row.add_suffix (choose);
            if (has) {
                var clear = new Button.from_icon_name ("edit-clear-symbolic");
                clear.valign = Align.CENTER;
                clear.tooltip_text = _("Remove Sound");
                clear.clicked.connect (() => {
                    edit (_("Sound"), () => apply ("", null));
                    later_rebuild ();
                });
                row.add_suffix (clear);
            }
            return row;
        }

        private async Bytes? pick_sound (out string name) {
            name = "";
            var dialog = new FileDialog ();
            dialog.title = _("Choose a Sound");
            var filters = new GLib.ListStore (typeof (FileFilter));
            var f = new FileFilter ();
            f.name = _("Audio");
            f.add_mime_type ("audio/*");
            filters.append (f);
            dialog.filters = filters;
            try {
                var file = yield dialog.open (win, null);
                if (file == null) return null;
                uint8[] data;
                FileUtils.get_data (file.get_path (), out data);
                name = file.get_basename ();
                return new Bytes (data);
            } catch (Error e) {
                return null;
            }
        }

        private void effect_lists (Element? target, out string[] sections, out Gee.ArrayList<Gee.ArrayList<string>> labels, out Gee.ArrayList<AnimClass> classes, out Gee.ArrayList<Gee.ArrayList<int>> values) {
            sections = { _("Entrance"), _("Emphasis"), _("Exit"), _("Motion Paths"), _("Media") };
            labels = new Gee.ArrayList<Gee.ArrayList<string>> ();
            classes = new Gee.ArrayList<AnimClass> ();
            values = new Gee.ArrayList<Gee.ArrayList<int>> ();
            AnimClass[] cls = { AnimClass.ENTRANCE, AnimClass.EMPHASIS, AnimClass.EXIT, AnimClass.PATH, AnimClass.MEDIA };
            for (int s = 0; s < 5; s++) {
                var names = new Gee.ArrayList<string> ();
                var vals = new Gee.ArrayList<int> ();
                if (cls[s] == AnimClass.ENTRANCE || cls[s] == AnimClass.EXIT) {
                    foreach (var e in AnimEffect.ENTRANCE) {
                        names.add (e.label (cls[s]));
                        vals.add ((int) e);
                    }
                } else if (cls[s] == AnimClass.EMPHASIS) {
                    foreach (var e in AnimEffect.EMPHASIS) {
                        names.add (e.label (cls[s]));
                        vals.add ((int) e);
                    }
                } else if (cls[s] == AnimClass.PATH) {
                    foreach (var m in MotionPreset.ALL) {
                        names.add (m.label ());
                        vals.add ((int) m);
                    }
                } else if (target is MediaElement) {
                    foreach (var e in new AnimEffect[] { AnimEffect.MEDIA_PLAY, AnimEffect.MEDIA_PAUSE, AnimEffect.MEDIA_STOP }) {
                        names.add (e.label (cls[s]));
                        vals.add ((int) e);
                    }
                }
                labels.add (names);
                classes.add (cls[s]);
                values.add (vals);
            }
        }

        private void apply_pick (Animation a, AnimClass cls, int value) {
            a.anim_class = cls;
            if (cls == AnimClass.PATH) {
                var mp = (MotionPreset) value;
                a.effect = AnimEffect.MOTION_PATH;
                a.path_preset = mp;
                a.path.clear ();
                if (mp != MotionPreset.CUSTOM) a.path.add_all (mp.build (win.doc.pres.width / win.doc.pres.height));
                if (a.duration < 1) a.duration = 2;
            } else {
                a.set_effect ((AnimEffect) value);
                if (cls == AnimClass.MEDIA) a.duration = 0.001;
            }
        }

        private void build_object (Slide slide) {
            var sel = win.canvas.selection;
            var g = new PreferencesGroup (_("Object Animation"), sel.size == 1 ? sel[0].display_name () : (sel.size > 1 ? _("%d objects").printf (sel.size) : _("Select an object on the slide to animate it")));
            content.append (g);
            if (sel.size == 0) return;
            var add_row = new ActionRow (_("Add Animation"), _("Entrance, emphasis, exit, motion path or media"));
            var add_btn = new Button.from_icon_name ("list-add-symbolic");
            add_btn.valign = Align.CENTER;
            add_btn.tooltip_text = _("Add Animation");
            add_btn.clicked.connect (() => {
                string[] sections;
                Gee.ArrayList<Gee.ArrayList<string>> labels;
                Gee.ArrayList<AnimClass> classes;
                Gee.ArrayList<Gee.ArrayList<int>> values;
                effect_lists (sel[0], out sections, out labels, out classes, out values);
                gallery (add_btn, sections, labels, -1, -1, (s, i) => add_animation (classes[s], values[s][i]));
            });
            add_row.add_suffix (add_btn);
            add_row.activated.connect (() => add_btn.clicked ());
            g.add_row (add_row);
            var draw = new ActionRow (_("Draw Custom Path"), _("Drag on the slide to draw the path"));
            var draw_btn = new Button.from_icon_name ("slides-motion-path-symbolic");
            draw_btn.valign = Align.CENTER;
            draw_btn.tooltip_text = _("Draw Custom Path");
            draw_btn.clicked.connect (() => {
                win.canvas.path_animation = null;
                win.canvas.set_tool (CanvasTool.MOTION_PATH);
            });
            draw.add_suffix (draw_btn);
            draw.activated.connect (() => draw_btn.clicked ());
            g.add_row (draw);
            if (sel.size == 1) {
                var painter = new ActionRow (_("Animation Painter"), _("Copy these animations to other objects"));
                var pb = new Button.from_icon_name ("edit-copy-symbolic");
                pb.valign = Align.CENTER;
                pb.tooltip_text = _("Copy Animations");
                pb.clicked.connect (() => copy_animations (slide, sel[0]));
                painter.add_suffix (pb);
                g.add_row (painter);
            }
        }

        private Gee.ArrayList<Animation> anim_clip = new Gee.ArrayList<Animation> ();

        public void set_transition (TransitionKind k) {
            var slide = win.canvas.slide;
            if (win.doc == null || slide == null) return;
            var t = slide.transition;
            edit (_("Transition"), () => {
                t.kind = k;
                var o = TransitionCatalog.options (k);
                if (o == TransitionOptions.DIR8 || o == TransitionOptions.DIR4) {
                    if (t.subtype == 0) t.subtype = 2;
                }
                t.variant = 0;
                if (k == TransitionKind.MORPH && t.duration < 1) t.duration = 2;
            });
            later_rebuild ();
            win.canvas_preview_transition ();
        }

        public void fill_transitions (ContextMenu menu) {
            var slide = win.canvas.slide;
            if (win.doc == null || slide == null) return;
            var current = slide.transition.kind;
            string[] sections = { _("Subtle"), _("Exciting"), _("Dynamic Content") };
            for (int s = 0; s < 3; s++) {
                var sub = menu.add_submenu (sections[s], null);
                foreach (var k in TransitionKind.ALL) {
                    if (TransitionCatalog.group (k) != GROUPS[s]) continue;
                    var kk = k;
                    sub.add_item (k.label (), null, () => set_transition (kk), k == current ? "checked" : null);
                }
            }
        }

        public bool fill_transition_options (ContextMenu menu) {
            var slide = win.canvas.slide;
            if (win.doc == null || slide == null) return false;
            var t = slide.transition;
            if (t.kind == TransitionKind.NONE) return false;
            var o = TransitionCatalog.options (t.kind);
            if (o == TransitionOptions.DIR4 || o == TransitionOptions.DIR8) {
                var eo = o == TransitionOptions.DIR4 ? EffectOptions.DIR4 : EffectOptions.DIR8;
                var vals = EffectCatalog.option_values (eo);
                var names = EffectCatalog.option_labels (eo);
                for (int i = 0; i < vals.length; i++) {
                    int v = vals[i];
                    menu.add_item (names[i], null, () => {
                        edit (_("Effect Options"), () => t.subtype = v);
                        later_rebuild ();
                        win.canvas_preview_transition ();
                    }, v == t.subtype ? "checked" : null);
                }
                return true;
            }
            var vl = TransitionCatalog.variant_labels (o);
            for (int i = 0; i < vl.length; i++) {
                int v = i;
                menu.add_item (vl[i], null, () => {
                    edit (_("Effect Options"), () => t.variant = v);
                    later_rebuild ();
                    win.canvas_preview_transition ();
                }, v == t.variant ? "checked" : null);
            }
            return vl.length > 0;
        }

        public void set_transition_duration (double seconds) {
            var slide = win.canvas.slide;
            if (win.doc == null || slide == null) return;
            var t = slide.transition;
            edit (_("Duration (seconds)"), () => t.duration = seconds);
            later_rebuild ();
        }

        public void add_animation (AnimClass cls, int v) {
            var slide = win.canvas.slide;
            var sel = win.canvas.selection;
            if (win.doc == null || slide == null || sel.size == 0) return;
            var targets = new Gee.ArrayList<Element> ();
            targets.add_all (sel);
            edit (_("Add Animation"), () => {
                bool first = true;
                foreach (var e in targets) {
                    var a = new Animation (e.id);
                    apply_pick (a, cls, v);
                    a.trigger = first ? AnimTrigger.ON_CLICK : AnimTrigger.WITH_PREVIOUS;
                    first = false;
                    slide.animations.add (a);
                }
            });
            expanded_index = slide.animations.size - 1;
            later_rebuild ();
            win.canvas_preview_animations (slide.animations.size - targets.size);
        }

        public void fill_add_animation (ContextMenu menu) {
            var sel = win.canvas.selection;
            if (win.doc == null || win.canvas.slide == null) return;
            if (sel.size == 0) {
                menu.add_item (_("Select an object on the slide to animate it"), null, () => { }, "dim-label");
                return;
            }
            string[] sections;
            Gee.ArrayList<Gee.ArrayList<string>> labels;
            Gee.ArrayList<AnimClass> classes;
            Gee.ArrayList<Gee.ArrayList<int>> values;
            effect_lists (sel[0], out sections, out labels, out classes, out values);
            for (int s = 0; s < sections.length; s++) {
                if (labels[s].size == 0) continue;
                var sub = menu.add_submenu (sections[s], null);
                for (int i = 0; i < labels[s].size; i++) {
                    var cls = classes[s];
                    int v = values[s][i];
                    sub.add_item (labels[s][i], null, () => add_animation (cls, v));
                }
            }
        }

        public void draw_custom_path () {
            if (win.doc == null || win.canvas.selection.size == 0) {
                win.add_toast (new Toast (_("Select an object on the slide to animate it")));
                return;
            }
            win.canvas.path_animation = null;
            win.canvas.set_tool (CanvasTool.MOTION_PATH);
        }

        public void paint_animations () {
            var slide = win.canvas.slide;
            var sel = win.canvas.selection;
            if (win.doc == null || slide == null || sel.size != 1) {
                win.add_toast (new Toast (_("Select an object to copy its animations")));
                return;
            }
            copy_animations (slide, sel[0]);
        }

        private void copy_animations (Slide slide, Element src) {
            anim_clip.clear ();
            foreach (var a in slide.animations) if (a.target == src.id) anim_clip.add (a.clone ());
            if (anim_clip.size == 0) {
                win.add_toast (new Toast (_("The object has no animations")));
                return;
            }
            win.add_toast (new Toast (_("Select objects, then choose Paste Animations")));
            ulong id = 0;
            id = win.canvas.selection_changed.connect (() => {
                var s = win.canvas.selection;
                if (s.size == 0 || s.contains (src)) return;
                win.canvas.disconnect (id);
                var targets = new Gee.ArrayList<Element> ();
                targets.add_all (s);
                edit (_("Animation Painter"), () => {
                    foreach (var e in targets) {
                        for (int k = slide.animations.size - 1; k >= 0; k--) if (slide.animations[k].target == e.id) slide.animations.remove_at (k);
                        foreach (var a in anim_clip) {
                            var c = a.clone ();
                            c.target = e.id;
                            c.raw = "";
                            slide.animations.add (c);
                        }
                    }
                });
                later_rebuild ();
            });
        }

        private void build_order (Slide slide) {
            var g = new PreferencesGroup (_("Animation Pane"), slide.animations.size == 0 ? _("Animations play in this order while presenting") : null);
            var play = new Button.from_icon_name ("media-playback-start-symbolic");
            play.tooltip_text = _("Play All");
            play.sensitive = slide.animations.size > 0;
            play.clicked.connect (() => win.canvas_preview_animations (0));
            g.add_header_suffix (play);
            content.append (g);
            if (slide.animations.size == 0) {
                var sp = new WelcomePage ();
                sp.is_section = true;
                sp.embedded = true;
                sp.title = _("No Animations");
                sp.subtitle = _("Select an object and add an entrance, emphasis, exit or motion path effect");
                sp.add_action ("x-office-presentation", _("Animate the Title"), _("Fade the title in on click"), () => {
                    var title = slide.placeholder (PlaceholderKind.TITLE);
                    if (title == null) title = slide.elements.size > 0 ? slide.elements[0] : null;
                    if (title == null) return;
                    edit (_("Add Animation"), () => slide.animations.add (new Animation (title.id)));
                    later_rebuild ();
                });
                g.add_row (sp);
                return;
            }
            timeline = new DrawingArea ();
            timeline.content_height = 22 + slide.animations.size * 16;
            timeline.set_draw_func ((da, cr, w, h) => draw_timeline (cr, w, h, slide));
            timeline.margin_top = 6;
            timeline.margin_bottom = 6;
            timeline.margin_start = 10;
            timeline.margin_end = 10;
            timeline.tooltip_text = _("Timeline: each bar shows when an effect starts and how long it lasts");
            g.add_row (timeline);
            int click = 0;
            string last_trigger = "";
            for (int i = 0; i < slide.animations.size; i++) {
                var a = slide.animations[i];
                string tkey = a.trigger_shape >= 0 ? "t%d%s".printf (a.trigger_shape, a.trigger_bookmark) : "";
                if (tkey != "" && tkey != last_trigger) {
                    var te = slide.find (a.trigger_shape);
                    string tn = te != null ? te.display_name () : _("Missing Object");
                    var th = new Label (a.trigger_bookmark != "" ? _("Trigger: Bookmark %s of %s").printf (a.trigger_bookmark, tn) : _("Trigger: %s").printf (tn));
                    th.xalign = 0;
                    th.add_css_class ("dim-label");
                    th.margin_start = 12;
                    th.margin_top = 6;
                    g.add_row (th);
                }
                last_trigger = tkey;
                if (a.trigger == AnimTrigger.ON_CLICK && tkey == "") click++;
                g.add_row (anim_row (slide, a, i, click));
            }
        }

        private ExpanderRow anim_row (Slide slide, Animation a, int i, int click) {
            var e = slide.find (a.target);
            string ename = e != null ? e.display_name () : _("Missing Object");
            var row = new ExpanderRow ("%s: %s".printf (a.anim_class.label (), a.label ()), "%s, %s".printf (ename, a.trigger.label ()));
            var badge = new Label (a.trigger == AnimTrigger.ON_CLICK && a.trigger_shape < 0 ? click.to_string () : "");
            badge.add_css_class ("slides-anim-index");
            badge.valign = Align.CENTER;
            badge.width_chars = 2;
            row.add_prefix (badge);
            if (i == expanded_index) row.expanded = true;
            int idx = i;
            row.notify["expanded"].connect (() => {
                if (row.expanded) expanded_index = idx;
            });
            var eff = new ActionRow (_("Effect"), a.label ());
            var pick = new Button.from_icon_name ("view-grid-symbolic");
            pick.valign = Align.CENTER;
            pick.tooltip_text = _("Change Effect");
            pick.clicked.connect (() => {
                string[] sections;
                Gee.ArrayList<Gee.ArrayList<string>> labels;
                Gee.ArrayList<AnimClass> classes;
                Gee.ArrayList<Gee.ArrayList<int>> values;
                effect_lists (e, out sections, out labels, out classes, out values);
                int cs = classes.index_of (a.anim_class);
                int cur = cs >= 0 ? values[cs].index_of (a.anim_class == AnimClass.PATH ? (int) a.path_preset : (int) a.effect) : -1;
                gallery (pick, sections, labels, cs, cur, (s, k) => {
                    var cls = classes[s];
                    int v = values[s][k];
                    edit (_("Change Effect"), () => {
                        apply_pick (a, cls, v);
                        a.raw = "";
                    });
                    later_rebuild ();
                    win.canvas_preview_animations (idx);
                });
            });
            eff.add_suffix (pick);
            row.add_row (eff);
            add_options (row, a, e);
            string[] triggers = { AnimTrigger.ON_CLICK.label (), AnimTrigger.WITH_PREVIOUS.label (), AnimTrigger.AFTER_PREVIOUS.label () };
            row.add_row (choice (_("Start"), triggers, (int) a.trigger, (v) => {
                a.trigger = (AnimTrigger) (int) v;
                later_rebuild ();
            }));
            if (!a.effect.is_media () && a.effect != AnimEffect.APPEAR) row.add_row (spin (_("Duration (seconds)"), 0.01, 59, 0.1, a.duration, 2, (v) => a.duration = v, "anim-dur-%d".printf (i)));
            row.add_row (spin (_("Delay (seconds)"), 0, 60, 0.1, a.delay, 1, (v) => a.delay = v, "anim-delay-%d".printf (i)));
            if (!a.effect.is_media ()) add_timing (row, a, i);
            add_trigger (row, slide, a);
            if (a.anim_class != AnimClass.PATH && !a.effect.is_media ()) add_enhance (row, a, e);
            var tools = new ActionRow (_("Reorder"));
            var up = new Button.from_icon_name ("go-up-symbolic");
            up.add_css_class ("flat");
            up.tooltip_text = _("Move Earlier");
            up.sensitive = i > 0;
            up.clicked.connect (() => {
                edit (_("Reorder Animation"), () => {
                    var x = slide.animations.remove_at (idx);
                    slide.animations.insert (idx - 1, x);
                });
                expanded_index = idx - 1;
                later_rebuild ();
            });
            var down = new Button.from_icon_name ("go-down-symbolic");
            down.add_css_class ("flat");
            down.tooltip_text = _("Move Later");
            down.sensitive = i < slide.animations.size - 1;
            down.clicked.connect (() => {
                edit (_("Reorder Animation"), () => {
                    var x = slide.animations.remove_at (idx);
                    slide.animations.insert (idx + 1, x);
                });
                expanded_index = idx + 1;
                later_rebuild ();
            });
            var playb = new Button.from_icon_name ("media-playback-start-symbolic");
            playb.add_css_class ("flat");
            playb.tooltip_text = _("Play From Here");
            playb.clicked.connect (() => win.canvas_preview_animations (idx));
            var del = new Button.from_icon_name ("user-trash-symbolic");
            del.add_css_class ("flat");
            del.tooltip_text = _("Remove Animation");
            del.clicked.connect (() => {
                edit (_("Remove Animation"), () => slide.animations.remove_at (idx));
                expanded_index = -1;
                later_rebuild ();
            });
            var box = new Box (Orientation.HORIZONTAL, 2);
            box.valign = Align.CENTER;
            box.append (playb);
            box.append (up);
            box.append (down);
            box.append (del);
            tools.add_suffix (box);
            row.add_row (tools);
            var sel_click = new GestureClick ();
            sel_click.pressed.connect (() => {
                var el = slide.find (a.target);
                if (el != null && slide.elements.contains (el)) win.canvas.select (el);
            });
            badge.add_controller (sel_click);
            return row;
        }

        private static string[] COLOR_KEYS = { "accent1", "accent2", "accent3", "accent4", "accent5", "accent6", "dk1", "lt1", "#ff0000", "#ffc000", "#00b050", "#0070c0" };

        private string[] color_labels () {
            return { _("Accent 1"), _("Accent 2"), _("Accent 3"), _("Accent 4"), _("Accent 5"), _("Accent 6"), _("Dark"), _("Light"), _("Red"), _("Orange"), _("Green"), _("Blue") };
        }

        private void add_options (ExpanderRow row, Animation a, Element? e) {
            if (a.anim_class == AnimClass.PATH) {
                string[] names = new string[MotionPreset.ALL.length];
                int cur = 0;
                for (int k = 0; k < names.length; k++) {
                    names[k] = MotionPreset.ALL[k].label ();
                    if (MotionPreset.ALL[k] == a.path_preset) cur = k;
                }
                row.add_row (choice (_("Path"), names, cur, (v) => {
                    var mp = MotionPreset.ALL[(int) v];
                    a.path_preset = mp;
                    if (mp != MotionPreset.CUSTOM) {
                        a.path.clear ();
                        a.path.add_all (mp.build (win.doc.pres.width / win.doc.pres.height));
                    }
                    a.raw = "";
                }));
                var redraw = new ActionRow (_("Edit Path"), _("Draw a new path on the slide"));
                var rb = new Button.from_icon_name ("slides-motion-path-symbolic");
                rb.valign = Align.CENTER;
                rb.tooltip_text = _("Draw Path");
                rb.clicked.connect (() => {
                    win.canvas.path_animation = a;
                    win.canvas.set_tool (CanvasTool.MOTION_PATH);
                });
                redraw.add_suffix (rb);
                row.add_row (redraw);
                var rev = new ActionRow (_("Reverse Path Direction"));
                var revb = new Button.from_icon_name ("object-flip-horizontal-symbolic");
                revb.valign = Align.CENTER;
                revb.tooltip_text = _("Reverse Path Direction");
                revb.clicked.connect (() => {
                    edit (_("Reverse Path Direction"), () => reverse_path (a));
                    win.canvas_preview_animations (win.canvas.slide.animations.index_of (a));
                });
                rev.add_suffix (revb);
                row.add_row (rev);
                row.add_row (toggle (_("Orient Shape to Path"), null, a.path_rotate, (v) => a.path_rotate = v > 0));
                return;
            }
            var o = EffectCatalog.options (a.effect);
            var labels = EffectCatalog.option_labels (o);
            if (labels.length > 0) {
                var vals = EffectCatalog.option_values (o);
                int cur = 0;
                for (int k = 0; k < vals.length; k++) if (vals[k] == a.subtype) cur = k;
                row.add_row (choice (_("Effect Options"), labels, cur, (v) => {
                    a.subtype = vals[(int) v];
                    a.raw = "";
                }));
            }
            switch (o) {
                case EffectOptions.SPIN:
                    row.add_row (spin (_("Amount (degrees)"), -3600, 3600, 15, a.amount, 0, (v) => {
                        a.amount = v;
                        a.raw = "";
                    }, "anim-amount"));
                    break;
                case EffectOptions.SCALE:
                    row.add_row (spin (_("Size (percent)"), 10, 1000, 10, a.amount * 100, 0, (v) => {
                        a.amount = v / 100;
                        a.raw = "";
                    }, "anim-amount"));
                    break;
                case EffectOptions.ALPHA:
                    row.add_row (spin (_("Transparency (percent)"), 0, 100, 5, a.amount * 100, 0, (v) => {
                        a.amount = v / 100;
                        a.raw = "";
                    }, "anim-amount"));
                    break;
                case EffectOptions.COLOR:
                    int ci = 0;
                    for (int k = 0; k < COLOR_KEYS.length; k++) if (COLOR_KEYS[k] == a.color) ci = k;
                    row.add_row (choice (_("Color"), color_labels (), ci, (v) => {
                        a.color = COLOR_KEYS[(int) v];
                        a.raw = "";
                    }));
                    break;
                default:
                    break;
            }
            if (a.effect.is_media ()) {
                var m = e as MediaElement;
                if (m != null && a.effect == AnimEffect.MEDIA_PLAY) {
                    row.add_row (toggle (_("Play Across Slides"), null, m.across_slides, (v) => m.across_slides = v > 0));
                    row.add_row (toggle (_("Hide While Not Playing"), null, m.hide_when_stopped, (v) => m.hide_when_stopped = v > 0));
                }
            }
        }

        private void reverse_path (Animation a) {
            var pts = new Gee.ArrayList<double?> ();
            foreach (var c in a.path) for (int k = 0; k + 1 < c.pts.length; k += 2) {
                pts.add (c.pts[k]);
                pts.add (c.pts[k + 1]);
            }
            if (pts.size < 4) return;
            double ex = pts[pts.size - 2], ey = pts[pts.size - 1];
            var rev = new Gee.ArrayList<PathCommand> ();
            rev.add (new PathCommand ('M', { 0, 0 }));
            for (int k = a.path.size - 1; k >= 1; k--) {
                var c = a.path[k];
                var prev = a.path[k - 1];
                double px = prev.pts.length >= 2 ? prev.pts[prev.pts.length - 2] : 0;
                double py = prev.pts.length >= 2 ? prev.pts[prev.pts.length - 1] : 0;
                if (c.op == 'C' && c.pts.length >= 6) rev.add (new PathCommand ('C', { c.pts[2] - ex, c.pts[3] - ey, c.pts[0] - ex, c.pts[1] - ey, px - ex, py - ey }));
                else if (c.op != 'Z') rev.add (new PathCommand ('L', { px - ex, py - ey }));
            }
            a.path.clear ();
            a.path.add_all (rev);
            a.path_preset = MotionPreset.CUSTOM;
            a.raw = "";
        }

        private void add_timing (ExpanderRow row, Animation a, int i) {
            string[] reps = { _("None"), "2", "3", "4", "5", "10", _("Until Next Click"), _("Until End of Slide") };
            double[] rv = { 1, 2, 3, 4, 5, 10, -1, -2 };
            int cur = 0;
            for (int k = 0; k < rv.length; k++) if (rv[k] == a.repeat) cur = k;
            if (a.repeat < 0) cur = 6;
            row.add_row (choice (_("Repeat"), reps, cur, (v) => {
                a.repeat = rv[(int) v] == -2 ? -1 : rv[(int) v];
                a.raw = "";
            }));
            row.add_row (toggle (_("Rewind When Done Playing"), null, a.rewind, (v) => {
                a.rewind = v > 0;
                a.raw = "";
            }));
            row.add_row (toggle (_("Auto-Reverse"), null, a.auto_reverse, (v) => {
                a.auto_reverse = v > 0;
                a.raw = "";
            }));
            row.add_row (toggle (_("Smooth Start"), null, a.accel > 0, (v) => {
                a.accel = v > 0 ? 0.5 : 0;
                a.raw = "";
            }));
            row.add_row (toggle (_("Smooth End"), null, a.decel > 0, (v) => {
                a.decel = v > 0 ? 0.5 : 0;
                a.raw = "";
            }));
        }

        private void add_trigger (ExpanderRow row, Slide slide, Animation a) {
            string[] names = { _("As Part of Click Sequence") };
            var ids = new Gee.ArrayList<int> ();
            var marks = new Gee.ArrayList<string> ();
            ids.add (-1);
            marks.add ("");
            int cur = 0;
            foreach (var el in slide.elements) {
                if (el.id == a.target && !(el is MediaElement)) continue;
                names += _("On Click of %s").printf (el.display_name ());
                ids.add (el.id);
                marks.add ("");
                if (a.trigger_shape == el.id && a.trigger_bookmark == "") cur = ids.size - 1;
                var m = el as MediaElement;
                if (m != null) {
                    foreach (var b in m.bookmarks) {
                        names += _("On Bookmark %s").printf (b.name);
                        ids.add (el.id);
                        marks.add (b.name);
                        if (a.trigger_shape == el.id && a.trigger_bookmark == b.name) cur = ids.size - 1;
                    }
                }
            }
            row.add_row (choice (_("Trigger"), names, cur, (v) => {
                a.trigger_shape = ids[(int) v];
                a.trigger_bookmark = marks[(int) v];
                if (a.trigger_shape >= 0) a.trigger = AnimTrigger.ON_CLICK;
                a.raw = "";
                later_rebuild ();
            }));
        }

        private void add_enhance (ExpanderRow row, Animation a, Element? e) {
            row.add_row (sound_row (a.sound, a.sound_data != null, (name, data) => {
                a.sound = name;
                a.sound_data = data;
                a.raw = "";
            }));
            if (a.anim_class != AnimClass.EXIT) {
                string[] afters = { AfterEffect.NONE.label (), AfterEffect.HIDE.label (), AfterEffect.HIDE_ON_CLICK.label (), AfterEffect.DIM.label () };
                row.add_row (choice (_("After Animation"), afters, (int) a.after, (v) => {
                    a.after = (AfterEffect) (int) v;
                    if (a.after == AfterEffect.DIM && a.dim_color == "") a.dim_color = "#a0a0a0";
                    a.raw = "";
                    later_rebuild ();
                }));
                if (a.after == AfterEffect.DIM) {
                    string[] dims = { _("Gray"), _("Accent 1"), _("Accent 2"), _("Dark"), _("Light") };
                    string[] dv = { "#a0a0a0", "accent1", "accent2", "dk1", "lt1" };
                    int dc = 0;
                    for (int k = 0; k < dv.length; k++) if (dv[k] == a.dim_color) dc = k;
                    row.add_row (choice (_("Dim Color"), dims, dc, (v) => {
                        a.dim_color = dv[(int) v];
                        a.raw = "";
                    }));
                }
            }
            var s = e as ShapeElement;
            if (s == null || s.text == null || s.text.is_empty ()) return;
            string[] units = { TextUnit.ALL.label (), TextUnit.WORD.label (), TextUnit.LETTER.label () };
            row.add_row (choice (_("Animate Text"), units, (int) a.text_unit, (v) => {
                a.text_unit = (TextUnit) (int) v;
                a.raw = "";
                later_rebuild ();
            }));
            if (a.text_unit != TextUnit.ALL) row.add_row (spin (_("Delay Between (percent)"), 0, 100, 5, a.unit_delay * 100, 0, (v) => {
                a.unit_delay = v / 100;
                a.raw = "";
            }, "anim-unit"));
            string[] builds = { TextBuild.AS_ONE.label (), TextBuild.ALL_AT_ONCE.label (), TextBuild.BY_PARAGRAPH.label () };
            row.add_row (choice (_("Group Text"), builds, (int) a.text_build, (v) => {
                a.text_build = (TextBuild) (int) v;
                a.raw = "";
                later_rebuild ();
            }));
            if (a.text_build == TextBuild.BY_PARAGRAPH) row.add_row (spin (_("By Paragraph Level"), 1, 5, 1, a.build_level, 0, (v) => {
                a.build_level = (int) v;
                a.raw = "";
            }, "anim-level"));
        }

        private void draw_timeline (Cairo.Context cr, int w, int h, Slide slide) {
            var player = new Player (win.doc.pres, slide);
            if (player.timed.size == 0) return;
            double total = 0;
            var offsets = new double[player.step_count + 1];
            for (int i = 0; i < player.step_count; i++) {
                offsets[i] = total;
                total += double.max (player.step_length (i), 0.2) + 0.3;
            }
            if (total <= 0) return;
            var acc = Gdk.RGBA ();
            acc.parse (Singularity.Style.StyleManager.get_default ().accent_hex);
            var fg = get_color ();
            double lw = w - 4;
            cr.set_line_width (1);
            for (int i = 0; i < player.step_count; i++) {
                double x = 2 + offsets[i] / total * lw;
                cr.set_source_rgba (fg.red, fg.green, fg.blue, 0.25);
                cr.move_to (Math.round (x) + 0.5, 0);
                cr.line_to (Math.round (x) + 0.5, h);
                cr.stroke ();
                var layout = create_pango_layout ((i + 1).to_string ());
                var fd = Pango.FontDescription.from_string ("Inter 7");
                layout.set_font_description (fd);
                cr.set_source_rgba (fg.red, fg.green, fg.blue, 0.6);
                cr.move_to (x + 3, 0);
                Pango.cairo_show_layout (cr, layout);
            }
            int row = 0;
            foreach (var ta in player.timed) {
                double x1 = 2 + (offsets[ta.step] + ta.start) / total * lw;
                double x2 = 2 + (offsets[ta.step] + ta.end) / total * lw;
                double y = 14 + row * 16;
                Geometry.round_rect (cr, x1, y, double.max (x2 - x1, 4), 10, 4);
                double alpha = ta.anim.anim_class == AnimClass.EXIT ? 0.55 : (ta.anim.anim_class == AnimClass.EMPHASIS ? 0.75 : 1);
                cr.set_source_rgba (acc.red, acc.green, acc.blue, alpha);
                cr.fill ();
                row++;
            }
        }
    }
}
