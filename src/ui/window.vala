using Gtk;
using Singularity.Widgets;

namespace Singularity.Apps.Slides {

    public enum ViewMode {
        NORMAL,
        SORTER,
        MASTER
    }

    public class SlidesWindow : Singularity.Widgets.Window {
        public SlidesApp app;
        public Document? doc { get; private set; }
        public SlideCanvas canvas;
        public ViewMode view_mode = ViewMode.NORMAL;
        private Stack content_stack;
        private Stack view_stack;
        private Box recent_list;
        private Box recent_wrap;
        private SlidesSidebar sidebar;
        private SorterView sorter;
        private Inspector inspector;
        public AnimationPanel anim_panel;
        private CommentsPanel comments_panel;
        private OutlinePanel outline_panel;
        private Stack right_stack;
        private Revealer right_revealer;
        private Revealer notes_revealer;
        private TextView notes_view;
        private Label notes_hint;
        private Banner master_banner;
        private Overlay stage_overlay;
        private ScrolledWindow canvas_scroll;
        public SlidesRibbon ribbon;
        private SidebarTabs panel_tabs;
        private bool panel_switching = false;
        private Gee.ArrayList<Widget> doc_bubbles = new Gee.ArrayList<Widget> ();
        private Button find_bubble;
        private Button share_bubble;
        private bool close_confirmed = false;
        private bool notes_sync = false;
        private uint thumb_timer = 0;
        private uint autosave_id = 0;
        private SlideShow? slideshow = null;
        private ShowWindow? show_window = null;
        private PresenterWindow? presenter_window = null;
        private ShowStage? preview_stage = null;
        private Gee.ArrayList<Slide> slide_clip = new Gee.ArrayList<Slide> ();
        private Gee.ArrayList<Element> element_clip = new Gee.ArrayList<Element> ();
        private string[] doc_actions = {};
        private const string CLIP_MIME = "application/x-singularity-slides";
        private const string CHART_LINK_MIME = "application/x-singularity-chart-link";

        public SlidesWindow (SlidesApp app) {
            Object (application: app);
            this.app = app;
            set_default_size (1320, 840);
            set_title (_("Slides"));
            content_stack = new Stack ();
            content_stack.transition_type = StackTransitionType.CROSSFADE;
            content_stack.add_named (build_welcome (), "welcome");
            content_stack.add_named (build_editor (), "document");
            build_bubbles ();
            set_content (content_stack);
            install_actions ();
            var shortcuts = new ShortcutController ();
            shortcuts.propagation_phase = PropagationPhase.CAPTURE;
            shortcuts.scope = ShortcutScope.GLOBAL;
            shortcuts.add_shortcut (new Shortcut (ShortcutTrigger.parse_string ("F7"), new NamedAction ("win.spelling")));
            ((Widget) this).add_controller (shortcuts);
            close_request.connect (on_close_request);
            var drop = new DropTarget (typeof (Gdk.FileList), Gdk.DragAction.COPY);
            drop.drop.connect ((value, x, y) => {
                var list = (Gdk.FileList) value.get_boxed ();
                foreach (var file in list.get_files ()) {
                    string n = file.get_basename ().down ();
                    if (doc != null && (n.has_suffix (".png") || n.has_suffix (".jpg") || n.has_suffix (".jpeg") || n.has_suffix (".gif") || n.has_suffix (".svg") || n.has_suffix (".webp") || n.has_suffix (".bmp"))) {
                        insert_image_file (file);
                        continue;
                    }
                    app.open_file (file, this);
                    break;
                }
                return true;
            });
            ((Widget) this).add_controller (drop);
            show_welcome ();
        }

        public bool is_empty () {
            return doc == null || (!doc.modified && doc.path == null);
        }

        private Widget build_welcome () {
            var wp = new WelcomePage ();
            wp.app_icon_name = "dev.sinty.slides";
            wp.title = _("Slides");
            wp.subtitle = _("Create and present slideshows");
            wp.add_action ("x-office-presentation", _("New Presentation"), _("Start from a blank slide"), () => new_presentation ());
            wp.add_action ("folder-open", _("Open"), _("PowerPoint and OpenDocument presentations"), () => app.choose_file (this));
            wp.add_action ("x-office-presentation-template", _("Browse Templates"), _("Pick a design and a slide size"), () => Dialogs.templates (this));
            var extra = new Box (Orientation.VERTICAL, 20);
            var tpl_title = new Label (_("Templates"));
            tpl_title.add_css_class ("title-2");
            tpl_title.halign = Align.START;
            extra.append (tpl_title);
            var flow = new FlowBox ();
            flow.selection_mode = SelectionMode.NONE;
            flow.max_children_per_line = 4;
            flow.min_children_per_line = 2;
            flow.column_spacing = 10;
            flow.row_spacing = 10;
            flow.homogeneous = true;
            flow.halign = Align.START;
            int n = 0;
            foreach (var t in Templates.all ()) {
                if (n++ >= 8) break;
                var tt = t;
                flow.append (Dialogs.template_card (t, 176, () => new_from_template (tt.id, app.get_string ("default-aspect", "16:9"))));
            }
            extra.append (flow);
            recent_wrap = new Box (Orientation.VERTICAL, 12);
            var recent_title = new Label (_("Recent"));
            recent_title.add_css_class ("title-2");
            recent_title.halign = Align.START;
            recent_list = new Box (Orientation.VERTICAL, 0);
            recent_wrap.append (recent_title);
            recent_wrap.append (recent_list);
            extra.append (recent_wrap);
            wp.set_extra_widget (extra);
            return wp;
        }

        private static bool is_deck (string uri) {
            string u = uri.down ();
            return u.has_suffix (".pptx") || u.has_suffix (".odp") || u.has_suffix (".potx") || u.has_suffix (".ppsx") || u.has_suffix (".otp");
        }

        private void fill_recent () {
            Widget? child;
            while ((child = recent_list.get_first_child ()) != null) recent_list.remove (child);
            var items = new Gee.ArrayList<RecentInfo> ();
            if (Singularity.Runtime.file_history_enabled ()) {
                foreach (var info in RecentManager.get_default ().get_items ()) {
                    if (is_deck (info.get_uri ()) && info.exists ()) items.add (info);
                }
            }
            items.sort ((a, b) => b.get_modified ().compare (a.get_modified ()));
            int count = 0;
            foreach (var info in items) {
                if (count++ >= 6) break;
                var file = File.new_for_uri (info.get_uri ());
                var row = new Button ();
                row.add_css_class ("flat");
                row.add_css_class ("slides-recent-row");
                var box = new Box (Orientation.HORIZONTAL, 12);
                var icon = new Image.from_icon_name ("x-office-presentation-symbolic");
                icon.pixel_size = 20;
                box.append (icon);
                var texts = new Box (Orientation.VERTICAL, 2);
                texts.hexpand = true;
                var name = new Label (file.get_basename ());
                name.halign = Align.START;
                name.ellipsize = Pango.EllipsizeMode.MIDDLE;
                name.add_css_class ("heading");
                var path = new Label (friendly_folder (file));
                path.halign = Align.START;
                path.ellipsize = Pango.EllipsizeMode.START;
                path.add_css_class ("caption");
                path.add_css_class ("dim-label");
                texts.append (name);
                texts.append (path);
                box.append (texts);
                row.child = box;
                row.clicked.connect (() => app.open_file (file, this));
                recent_list.append (row);
            }
            recent_wrap.visible = count > 0;
        }

        private static string friendly_folder (File file) {
            var parent = file.get_parent ();
            if (parent == null) return "";
            string p = parent.get_path () ?? parent.get_uri ();
            string home = Environment.get_home_dir ();
            if (p.has_prefix (home)) p = "~" + p.substring (home.length);
            return p;
        }

        private Widget build_editor () {
            var page = new Box (Orientation.VERTICAL, 0);
            page.add_css_class ("slides-editor");
            apply_view_edge (page);
            ribbon = new SlidesRibbon (this);
            page.append (ribbon);
            var main = new Box (Orientation.HORIZONTAL, 0);
            main.vexpand = true;
            master_banner = new Banner (_("You are editing the master slides. Changes apply to every slide that uses them."), BannerStyle.INFO);
            master_banner.icon_name = "x-office-presentation-symbolic";
            master_banner.button_label = _("Close Master View");
            master_banner.button_clicked.connect (() => set_view (ViewMode.NORMAL));
            master_banner.visible = false;
            page.append (master_banner);
            view_stack = new Stack ();
            view_stack.transition_type = StackTransitionType.CROSSFADE;
            view_stack.vexpand = true;
            var center = new Paned (Orientation.VERTICAL);
            center.hexpand = true;
            center.resize_start_child = true;
            center.shrink_end_child = false;
            canvas = new SlideCanvas ();
            canvas.selection_changed.connect (on_selection_changed);
            canvas.edited.connect (on_canvas_edited);
            canvas.context_requested.connect (show_canvas_menu);
            canvas.zoom_changed.connect (update_zoom_label);
            canvas.page_requested.connect ((d) => go_to_slide (doc.current_slide + d));
            canvas.editing_changed.connect (() => {
                if (right_revealer.reveal_child && right_stack.visible_child_name == "format") inspector.rebuild ();
                ribbon.sync_text ();
            });
            canvas.double_clicked_empty.connect (() => {
                if (!right_revealer.reveal_child) toggle_panel ("format");
            });
            canvas_scroll = new ScrolledWindow ();
            canvas_scroll.child = canvas;
            canvas_scroll.hexpand = true;
            canvas_scroll.vexpand = true;
            canvas_scroll.add_css_class ("slides-stage");
            stage_overlay = new Overlay ();
            stage_overlay.child = canvas_scroll;
            center.start_child = stage_overlay;
            notes_view = new TextView ();
            notes_view.wrap_mode = WrapMode.WORD_CHAR;
            notes_view.top_margin = 10;
            notes_view.bottom_margin = 10;
            notes_view.left_margin = 12;
            notes_view.right_margin = 12;
            notes_view.buffer.changed.connect (on_notes_changed);
            var notes_scroll = new ScrolledWindow ();
            var notes_overlay = new Overlay ();
            notes_overlay.child = notes_view;
            notes_hint = new Label (_("Click to add speaker notes"));
            notes_hint.add_css_class ("dim-label");
            notes_hint.halign = Align.START;
            notes_hint.valign = Align.START;
            notes_hint.margin_start = 14;
            notes_hint.margin_top = 10;
            notes_hint.can_target = false;
            notes_overlay.add_overlay (notes_hint);
            notes_scroll.child = notes_overlay;
            notes_scroll.set_size_request (-1, 150);
            notes_scroll.add_css_class ("slides-notes");
            notes_scroll.tooltip_text = _("Speaker notes, visible only to you while presenting");
            notes_revealer = new Revealer ();
            notes_revealer.child = notes_scroll;
            notes_revealer.reveal_child = app.get_bool ("show-notes", true);
            notes_revealer.visible = notes_revealer.reveal_child;
            notes_revealer.notify["reveal-child"].connect (() => {
                if (notes_revealer.reveal_child) notes_revealer.visible = true;
            });
            notes_revealer.notify["child-revealed"].connect (() => {
                if (!notes_revealer.child_revealed && !notes_revealer.reveal_child) notes_revealer.visible = false;
            });
            center.end_child = notes_revealer;
            center.resize_end_child = false;
            center.position = int.MAX / 2;
            inspector = new Inspector (this);
            anim_panel = new AnimationPanel (this);
            right_stack = new Stack ();
            right_stack.transition_type = StackTransitionType.CROSSFADE;
            right_stack.vexpand = true;
            right_stack.add_titled (inspector, "format", _("Format"));
            right_stack.add_titled (anim_panel, "animate", _("Animations"));
            comments_panel = new CommentsPanel (this);
            right_stack.add_titled (comments_panel, "comments", _("Comments"));
            outline_panel = new OutlinePanel (this);
            right_stack.add_titled (outline_panel, "outline", _("Outline"));
            right_stack.notify["visible-child-name"].connect (() => {
                if (!panel_switching) panel_changed ();
            });
            panel_tabs = new SidebarTabs (right_stack);
            panel_tabs.margin_top = 8;
            panel_tabs.margin_start = 4;
            panel_tabs.margin_end = 12;
            var right_box = new Box (Orientation.VERTICAL, 0);
            right_box.add_css_class ("slides-panel");
            right_box.add_css_class ("sx-inspector");
            right_box.hexpand = false;
            right_box.set_size_request (372, -1);
            right_box.append (panel_tabs);
            right_box.append (right_stack);
            right_revealer = new Revealer ();
            right_revealer.transition_type = RevealerTransitionType.SLIDE_LEFT;
            right_revealer.child = right_box;
            right_revealer.reveal_child = true;
            right_revealer.notify["reveal-child"].connect (() => ribbon.sync_panels ());
            view_stack.add_named (center, "normal");
            sidebar = new SlidesSidebar ();
            sidebar.slide_activated.connect ((i) => go_to_slide (i));
            sidebar.master_activated.connect ((m, l) => {
                canvas.show_master (m, l);
                inspector.rebuild ();
            });
            sidebar.context_requested.connect (show_slide_menu);
            sidebar.move_requested.connect (move_slides);
            sidebar.section_toggled.connect ((i) => {
                if (doc == null || i >= doc.pres.slides.size || doc.pres.slides[i].section == null) return;
                var mark = doc.pres.slides[i].section;
                mark.collapsed = !mark.collapsed;
                sidebar.load (doc.pres, doc.current_slide);
            });
            sidebar.new_slide_requested.connect (() => {
                if (view_mode != ViewMode.MASTER) new_slide (null);
            });
            set_sidebar (sidebar);
            set_sidebar_width (224);
            sorter = new SorterView (sidebar.thumbs);
            sorter.slide_activated.connect ((i) => {
                set_view (ViewMode.NORMAL);
                go_to_slide (i);
            });
            sorter.selection_moved.connect ((i) => {
                if (doc != null) doc.current_slide = i;
            });
            sorter.context_requested.connect (show_slide_menu);
            sorter.move_requested.connect (move_slides);
            view_stack.add_named (sorter, "sorter");
            view_stack.hexpand = true;
            main.append (view_stack);
            main.append (right_revealer);
            page.append (main);
            return page;
        }

        private Widget track (Widget w) {
            doc_bubbles.add (w);
            return w;
        }

        private void anchor_to (Popover pop, Widget bubble) {
            if (pop.get_parent () == null) pop.set_parent (content_stack);
            Graphene.Rect bounds;
            if (bubble.compute_bounds (content_stack, out bounds)) {
                var rect = Gdk.Rectangle ();
                rect.x = (int) bounds.origin.x;
                rect.y = (int) bounds.origin.y;
                rect.width = (int) bounds.size.width;
                rect.height = (int) bounds.size.height;
                pop.pointing_to = rect;
            }
            pop.position = PositionType.BOTTOM;
        }

        public static void popup_menu (ContextMenu menu) {
            menu.closed.connect (() => Idle.add (() => {
                menu.unparent ();
                return Source.REMOVE;
            }));
            menu.popup ();
        }

        private void popup_anchored (Popover pop, Widget bubble) {
            anchor_to (pop, bubble);
            pop.closed.connect (() => Idle.add (() => {
                pop.unparent ();
                return Source.REMOVE;
            }));
            pop.popup ();
        }

        private void build_bubbles () {
            track (add_bubble_icon ("go-previous-symbolic", _("Close Presentation"), () => close_document ()));
            var side = add_bubble_icon ("sidebar-show-symbolic", _("Slides (F9)"), () => run ("sidebar"));
            track (side);
            ribbon.attach (this);
            track (ribbon.tabs);
            find_bubble = add_bubble_icon ("edit-find-symbolic", _("Find and Replace (Ctrl+F)"), () => open_find (false));
            track (find_bubble);
            share_bubble = add_bubble_icon ("singularity-share-symbolic", _("Share"), () => run ("share"));
            track (share_bubble);
            var play = add_bubble_suggested (_("Play"), () => run ("play-current"));
            play.tooltip_text = _("Play from Current Slide (Shift+F5)");
            track (play);
            set_bubble_priority (play, BUBBLE_PRIORITY_PINNED);
        }

        public void show_format_panel () {
            right_stack.visible_child_name = "format";
            right_revealer.reveal_child = true;
            inspector.rebuild ();
        }

        public void toggle_panel (string name) {
            if (right_revealer.reveal_child && right_stack.visible_child_name == name) {
                right_revealer.reveal_child = false;
            } else {
                panel_switching = true;
                right_stack.visible_child_name = name;
                panel_switching = false;
                right_revealer.reveal_child = true;
            }
            panel_changed ();
        }

        private void panel_changed () {
            string name = right_stack.visible_child_name;
            if (right_revealer.reveal_child && doc != null) {
                if (name == "animate") anim_panel.rebuild ();
                else if (name == "comments") comments_panel.rebuild ();
                else if (name == "outline") outline_panel.rebuild ();
                else inspector.rebuild ();
            }
            canvas.show_comments = right_revealer.reveal_child && name == "comments" || doc != null && doc.pres.comment_count () > 0;
            canvas.show_badges = right_revealer.reveal_child && name == "animate";
            canvas.queue_draw ();
            ribbon.sync_panels ();
        }

        private void show_welcome () {
            content_stack.visible_child_name = "welcome";
            foreach (var w in doc_bubbles) w.visible = false;
            set_sidebar_visible (false);
            fill_recent ();
            set_title (_("Slides"));
            sync_actions ();
        }

        public void new_presentation () {
            var preset = ThemePreset.find (app.get_string ("default-theme", "clean")) ?? ThemePreset.all ()[0];
            double w, h;
            aspect_size (app.get_string ("default-aspect", "16:9"), out w, out h);
            var d = new Document (Factory.new_presentation (preset, w, h));
            load_document (d);
        }

        public void new_from_outline (string outline) {
            var preset = ThemePreset.find (app.get_string ("default-theme", "clean")) ?? ThemePreset.all ()[0];
            double w, h;
            aspect_size (app.get_string ("default-aspect", "16:9"), out w, out h);
            var p = DeckOutline.from_text (outline, Factory.new_presentation (preset, w, h));
            if (p.slides.size == 0) return;
            load_or_open_new (new Document (p));
        }

        public void new_from_images (string title, string[] uris) {
            var preset = ThemePreset.find (app.get_string ("default-theme", "clean")) ?? ThemePreset.all ()[0];
            double w, h;
            aspect_size (app.get_string ("default-aspect", "16:9"), out w, out h);
            var p = Factory.new_presentation (preset, w, h);
            var cover = p.slides[0].placeholder (PlaceholderKind.TITLE);
            if (cover != null && cover.text_body () != null) cover.text_body ().set_plain (title);
            var blank = p.master.layout_of_kind (LayoutKind.BLANK);
            foreach (string uri in uris) {
                string? path = File.new_for_uri (uri).get_path ();
                if (path == null) continue;
                uint8[] data;
                try {
                    FileUtils.get_data (path, out data);
                } catch (Error e) {
                    continue;
                }
                var bytes = new Bytes (data);
                int pw, ph;
                if (!ImageCache.size_of (bytes, out pw, out ph) || pw <= 0 || ph <= 0) continue;
                var s = Factory.add_slide (p, blank, p.slides.size);
                var img = new ImageElement (bytes, ImageElement.mime_for (Path.get_basename (path)));
                img.pixel_width = pw;
                img.pixel_height = ph;
                img.name = Path.get_basename (path);
                double sc = double.min (w / pw, h / ph);
                img.set_geometry ((w - pw * sc) / 2, (h - ph * sc) / 2, pw * sc, ph * sc);
                p.assign_ids (img);
                s.elements.add (img);
            }
            if (p.slides.size < 2) return;
            load_or_open_new (new Document (p));
        }

        public static void aspect_size (string aspect, out double w, out double h) {
            h = 540;
            if (aspect == "4:3") w = 720;
            else if (aspect == "16:10") w = 864;
            else w = 960;
        }

        public void load_or_open_new (Document d) {
            if (doc != null && !is_empty ()) {
                var nw = new SlidesWindow (app);
                nw.present ();
                nw.load_document (d);
                return;
            }
            load_document (d);
        }

        public void new_from_template (string id, string aspect) {
            var p = Templates.build (id);
            double w, h;
            aspect_size (aspect, out w, out h);
            if (Math.fabs (w - p.width) > 1) SlideSize.resize (p, w, h);
            var d = new Document (p);
            if (doc != null && !is_empty ()) {
                var nw = new SlidesWindow (app);
                nw.present ();
                nw.load_document (d);
                return;
            }
            load_document (d);
        }

        public void load_document (Document d) {
            if (doc != null) {
                doc.changed.disconnect (on_doc_changed);
                doc.replaced.disconnect (on_doc_replaced);
            }
            doc = d;
            doc.changed.connect (on_doc_changed);
            doc.replaced.connect (on_doc_replaced);
            content_stack.visible_child_name = "document";
            foreach (var w in doc_bubbles) w.visible = true;
            view_mode = ViewMode.NORMAL;
            view_stack.visible_child_name = "normal";
            right_revealer.visible = true;
            master_banner.visible = false;
            canvas.doc = doc;
            sidebar.thumbs.clear ();
            doc.current_slide = 0;
            sidebar.load (doc.pres, 0);
            set_sidebar_visible (true);
            show_current ();
            update_title ();
            sync_actions ();
            setup_autosave ();
            ribbon.document_loaded ();
            canvas.grab_focus ();
        }

        private void setup_autosave () {
            if (autosave_id != 0) Source.remove (autosave_id);
            autosave_id = 0;
            int interval = app.get_int ("autosave-interval", 0);
            if (interval <= 0) return;
            autosave_id = Timeout.add_seconds (interval, () => {
                if (doc != null && doc.modified && doc.path != null && slideshow == null && !canvas.is_editing ()) {
                    try {
                        doc.save_to (doc.path);
                        CloudActions.sync_back (this, File.new_for_path (doc.path));
                    } catch (Error e) {
                        warning ("autosave: %s", e.message);
                    }
                }
                return Source.CONTINUE;
            });
        }

        private void show_current () {
            if (doc == null) return;
            if (live != null && doc.slide != null) live.presence (doc.slide.uid);
            if (doc.pres.slides.size == 0) {
                canvas.show_slide (null);
            } else {
                doc.current_slide = doc.current_slide.clamp (0, doc.pres.slides.size - 1);
                canvas.show_slide (doc.pres.slides[doc.current_slide]);
            }
            load_notes ();
            inspector.rebuild ();
            if (right_stack.visible_child_name == "animate") anim_panel.rebuild ();
            if (right_stack.visible_child_name == "comments") comments_panel.rebuild ();
            if (right_stack.visible_child_name == "outline") outline_panel.rebuild ();
            canvas.show_comments = doc.pres.comment_count () > 0 || right_revealer.reveal_child && right_stack.visible_child_name == "comments";
            ribbon.sync_transition ();
            ribbon.sync_text ();
        }

        private void load_notes () {
            notes_sync = true;
            var s = doc != null ? doc.slide : null;
            notes_view.buffer.text = s != null ? s.notes : "";
            notes_view.sensitive = s != null;
            notes_hint.visible = notes_view.buffer.text == "";
            notes_sync = false;
        }

        private void on_notes_changed () {
            notes_hint.visible = notes_view.buffer.text == "";
            if (notes_sync || doc == null || doc.slide == null) return;
            string t = notes_view.buffer.text;
            var s = doc.slide;
            if (s.notes == t) return;
            doc.checkpoint (_("Edit Notes"), "notes");
            s.notes = t;
            doc.touch ();
        }

        public void go_to_slide (int i) {
            if (doc == null || doc.pres.slides.size == 0) return;
            if (view_mode == ViewMode.MASTER) return;
            i = i.clamp (0, doc.pres.slides.size - 1);
            canvas.commit_edit ();
            doc.current_slide = i;
            show_current ();
            sidebar.select_index (i);
        }

        private void on_doc_changed () {
            update_title ();
            ribbon.sync_transition ();
            live_schedule ();
        }

        private void on_doc_replaced (int slide) {
            live_schedule ();
            canvas.editor = null;
            if (view_mode == ViewMode.MASTER) {
                var m = doc.pres.master;
                sidebar.thumbs.clear ();
                sidebar.load_masters (doc.pres, m, null);
                canvas.show_master (m, null);
                inspector.rebuild ();
                return;
            }
            int[] ids = canvas.selected_ids ();
            sidebar.thumbs.clear ();
            sidebar.load (doc.pres, doc.current_slide);
            show_current ();
            canvas.reselect_by_ids (ids);
            if (view_mode == ViewMode.SORTER) sorter.load (doc.pres, doc.current_slide);
        }

        private void update_title () {
            if (doc == null) return;
            string name;
            if (doc.path != null) name = Path.get_basename (doc.path);
            else if (doc.pres.properties.title != "") name = doc.pres.properties.title;
            else name = _("Untitled Presentation");
            set_title ((doc.modified ? "* " : "") + name);
            ribbon.sync_history ();
            sync_share ();
        }

        private void update_zoom_label () {
            ribbon.sync_zoom ();
        }

        private void on_selection_changed () {
            if (right_revealer.reveal_child) {
                if (right_stack.visible_child_name == "format") inspector.rebuild ();
                else anim_panel.rebuild ();
            }
            sync_actions ();
            ribbon.sync_text ();
        }

        private void on_canvas_edited () {
            inspector.sync_geometry ();
            schedule_thumbnail ();
        }

        public void content_edited () {
            canvas.queue_draw ();
            schedule_thumbnail ();
        }

        private void schedule_thumbnail () {
            if (thumb_timer != 0) Source.remove (thumb_timer);
            thumb_timer = Timeout.add (180, () => {
                thumb_timer = 0;
                refresh_current_thumbnail ();
                return Source.REMOVE;
            });
        }

        public void refresh_current_thumbnail () {
            if (doc == null) return;
            if (view_mode == ViewMode.MASTER) {
                sidebar.thumbs.clear ();
                sidebar.load_masters (doc.pres, canvas.master, canvas.layout);
                return;
            }
            sidebar.refresh_slide (doc.current_slide);
        }

        public void refresh_thumbnails () {
            if (doc == null) return;
            sidebar.refresh_all ();
            if (view_mode == ViewMode.SORTER) sorter.load (doc.pres, doc.current_slide);
        }

        public void set_view (ViewMode mode) {
            apply_view (mode);
            ribbon.sync_modes ();
            ribbon.sync_panels ();
        }

        private void apply_view (ViewMode mode) {
            if (doc == null) return;
            canvas.commit_edit ();
            view_mode = mode;
            master_banner.visible = mode == ViewMode.MASTER;
            right_revealer.visible = mode != ViewMode.SORTER;
            if (mode == ViewMode.SORTER) {
                sorter.load (doc.pres, doc.current_slide);
                view_stack.visible_child_name = "sorter";
                set_sidebar_visible (false);
                return;
            }
            view_stack.visible_child_name = "normal";
            set_sidebar_visible (true);
            if (mode == ViewMode.MASTER) {
                var s = doc.slide;
                var m = s != null ? doc.pres.master_for (s) : doc.pres.master;
                var l = s != null ? doc.pres.layout_for (s) : null;
                sidebar.load_masters (doc.pres, m, l);
                canvas.show_master (m, l);
                notes_revealer.reveal_child = false;
                inspector.rebuild ();
                return;
            }
            Factory.refresh_inherited (doc.pres);
            sidebar.thumbs.clear ();
            sidebar.load (doc.pres, doc.current_slide);
            notes_revealer.reveal_child = app.get_bool ("show-notes", true);
            show_current ();
        }

        public void close_document () {
            if (doc == null) {
                show_welcome ();
                return;
            }
            confirm_discard (() => {
                canvas.commit_edit ();
                canvas.doc = null;
                canvas.show_slide (null);
                doc = null;
                if (autosave_id != 0) Source.remove (autosave_id);
                autosave_id = 0;
                show_welcome ();
            });
        }

        public delegate void Then ();

        private void confirm_discard (owned Then then) {
            if (doc == null || !doc.modified) {
                then ();
                return;
            }
            var dlg = new ConfirmDialog (app, _("Save Changes?"), "dialog-warning",
                _("Your changes will be lost if you do not save them."),
                _("Discard"), ConfirmDialog.ActionStyle.DESTRUCTIVE);
            dlg.set_secondary (_("Save"), ConfirmDialog.ActionStyle.SUGGESTED);
            dlg.transient_for = this;
            dlg.response.connect ((r) => {
                if (r == ConfirmDialog.Response.CANCEL) return;
                if (r == ConfirmDialog.Response.SECONDARY) {
                    save.begin (false, (obj, res) => {
                        if (save.end (res)) then ();
                    });
                    return;
                }
                then ();
            });
            dlg.present ();
        }

        private bool on_close_request () {
            if (slideshow != null) end_show ();
            if (close_confirmed || doc == null || !doc.modified) return false;
            confirm_discard (() => {
                close_confirmed = true;
                close ();
            });
            return true;
        }

        private FileFilter filter (string name, string[] suffixes) {
            var f = new FileFilter ();
            f.name = name;
            foreach (string s in suffixes) f.add_suffix (s);
            return f;
        }

        private static string base_name (Document d, string fallback) {
            string n;
            if (d.path != null) n = Path.get_basename (d.path);
            else if (d.pres.properties.title != "") n = d.pres.properties.title;
            else n = fallback;
            int dot = n.last_index_of (".");
            if (dot > 0) n = n.substring (0, dot);
            return n;
        }

        public async bool save (bool save_as) {
            if (doc == null) return false;
            canvas.commit_edit ();
            string? target = save_as ? null : doc.path;
            if (target != null) {
                string low = target.down ();
                if (!low.has_suffix (".pptx") && !low.has_suffix (".odp")) target = null;
            }
            if (target == null) {
                var dialog = new FileDialog ();
                dialog.title = _("Save Presentation");
                dialog.initial_name = base_name (doc, _("Presentation")) + ".pptx";
                dialog.initial_folder = default_folder ();
                var filters = new GLib.ListStore (typeof (FileFilter));
                filters.append (filter (_("PowerPoint Presentation (.pptx)"), { "pptx" }));
                filters.append (filter (_("OpenDocument Presentation (.odp)"), { "odp" }));
                dialog.filters = filters;
                try {
                    var file = yield dialog.save (this, null);
                    if (file == null) return false;
                    target = file.get_path ();
                    string low = target.down ();
                    if (!low.has_suffix (".pptx") && !low.has_suffix (".odp")) target += ".pptx";
                } catch (Error e) {
                    return false;
                }
            }
            try {
                doc.save_to (target);
                if (Singularity.Runtime.file_history_enabled ()) RecentManager.get_default ().add_item (File.new_for_path (target).get_uri ());
                update_title ();
                var toast = new Toast (_("Saved \"%s\"").printf (Path.get_basename (target)));
                toast.timeout = 2;
                add_toast (toast);
                CloudActions.sync_back (this, File.new_for_path (target));
                return true;
            } catch (Error e) {
                show_error (_("Could Not Save"), e.message);
                return false;
            }
        }

        private File default_folder () {
            if (doc != null && doc.path != null) return File.new_for_path (Path.get_dirname (doc.path));
            string? docs = Environment.get_user_special_dir (UserDirectory.DOCUMENTS);
            return File.new_for_path (docs != null && FileUtils.test (docs, FileTest.IS_DIR) ? docs : Environment.get_home_dir ());
        }

        private async File? ask_save (string title, string name, string[] suffixes, string filter_name) {
            var dialog = new FileDialog ();
            dialog.initial_folder = default_folder ();
            dialog.title = title;
            dialog.initial_name = name;
            var filters = new GLib.ListStore (typeof (FileFilter));
            filters.append (filter (filter_name, suffixes));
            dialog.filters = filters;
            try {
                return yield dialog.save (this, null);
            } catch (Error e) {
                return null;
            }
        }

        public async void export_pdf (PrintWhat what, bool hidden, bool comments) {
            if (doc == null) return;
            canvas.commit_edit ();
            var file = yield ask_save (_("Export as PDF"), base_name (doc, _("Presentation")) + ".pdf", { "pdf" }, _("PDF Document"));
            if (file == null) return;
            try {
                var ex = new Exporter (doc.pres);
                ex.include_hidden = hidden;
                ex.export_layout (file.get_path (), what, comments);
                add_toast (new Toast (_("Exported \"%s\"").printf (file.get_basename ())));
            } catch (Error e) {
                show_error (_("Could Not Export"), e.message);
            }
        }

        public async void export_images (string ext, int width, bool hidden) {
            if (doc == null) return;
            canvas.commit_edit ();
            var dialog = new FileDialog ();
            dialog.title = _("Choose a Folder for the Images");
            try {
                var folder = yield dialog.select_folder (this, null);
                if (folder == null) return;
                var ex = new Exporter (doc.pres);
                ex.include_hidden = hidden;
                int n = ex.export_images (folder.get_path (), base_name (doc, _("Slide")), ext, width);
                add_toast (new Toast (ngettext ("Exported %d image", "Exported %d images", n).printf (n)));
            } catch (Error e) {
                if (!(e is Gtk.DialogError.DISMISSED)) show_error (_("Could Not Export"), e.message);
            }
        }

        private async void export_current (string ext) {
            if (doc == null || doc.slide == null) return;
            canvas.commit_edit ();
            string name = "%s %d.%s".printf (base_name (doc, _("Slide")), doc.current_slide + 1, ext);
            var file = yield ask_save (ext == "svg" ? _("Export Slide as SVG") : _("Export Slide as Image"), name, ext == "svg" ? new string[] { "svg" } : new string[] { "png", "jpg", "jpeg" }, ext == "svg" ? _("SVG Image") : _("Images"));
            if (file == null) return;
            try {
                var ex = new Exporter (doc.pres);
                if (ext == "svg") ex.export_svg (doc.slide, file.get_path ());
                else ex.export_image (doc.slide, file.get_path (), app.get_int ("export-width", 1920));
                add_toast (new Toast (_("Exported \"%s\"").printf (file.get_basename ())));
            } catch (Error e) {
                show_error (_("Could Not Export"), e.message);
            }
        }

        private Cancellable? video_cancel = null;

        public async void export_video (ShowFormat format, int width, double seconds, bool timings) {
            if (doc == null || video_cancel != null) return;
            canvas.commit_edit ();
            string ext = format.extension ();
            string label = format == ShowFormat.GIF ? _("Animated GIF") : (format == ShowFormat.WEBM ? _("WebM Video") : _("MP4 Video"));
            var file = yield ask_save (_("Export as Video"), base_name (doc, _("Presentation")) + "." + ext, { ext }, label);
            if (file == null) return;
            var ex = new ShowExport (doc.pres.clone ());
            ex.format = format;
            ex.width = width;
            ex.seconds_per_slide = seconds;
            ex.use_timings = timings;
            ex.include_audio = timings;
            var cancel = new Cancellable ();
            video_cancel = cancel;
            var bar = new ProgressBar ();
            bar.show_text = true;
            bar.valign = Align.CENTER;
            var dlg = new AppDialog ((Gtk.Application) application, true, false);
            dlg.set_title (_("Exporting Video"));
            dlg.transient_for = this;
            dlg.set_default_size (420, 200);
            var box = new Box (Orientation.VERTICAL, 12);
            box.margin_start = 24;
            box.margin_end = 24;
            box.margin_top = 12;
            box.margin_bottom = 12;
            var info = new Label (_("Rendering \"%s\"").printf (file.get_basename ()));
            info.xalign = 0;
            info.ellipsize = Pango.EllipsizeMode.MIDDLE;
            box.append (info);
            box.append (bar);
            dlg.content_box.append (box);
            var bottom = new Box (Orientation.HORIZONTAL, 8);
            bottom.halign = Align.END;
            bottom.margin_end = 18;
            bottom.margin_bottom = 16;
            var stop = dlg.add_cancel_button ();
            stop.clicked.connect (() => cancel.cancel ());
            bottom.append (stop);
            dlg.content_box.append (bottom);
            dlg.open_dialog ();
            ex.progress.connect ((f) => {
                bar.fraction = f.clamp (0, 1);
                bar.text = "%d%%".printf ((int) (f * 100));
            });
            try {
                yield ex.run (file.get_path (), cancel);
                string msg = _("Exported \"%s\"").printf (file.get_basename ());
                if (ex.audio_note != "") msg += " " + ex.audio_note;
                add_toast (new Toast (msg));
            } catch (Error e) {
                FileUtils.remove (file.get_path ());
                if (!(e is IOError.CANCELLED)) show_error (_("Could Not Export"), e.message);
            }
            video_cancel = null;
            dlg.close ();
        }

        private async void export_as (string ext) {
            if (doc == null) return;
            canvas.commit_edit ();
            string title, filter_name;
            switch (ext) {
                case "ppsx": title = _("Export as PowerPoint Show"); filter_name = _("PowerPoint Show (.ppsx)"); break;
                case "potx": title = _("Export as PowerPoint Template"); filter_name = _("PowerPoint Template (.potx)"); break;
                case "otp": title = _("Export as OpenDocument Template"); filter_name = _("OpenDocument Template (.otp)"); break;
                default: title = _("Export Outline"); filter_name = _("Rich Text (.rtf)"); break;
            }
            var file = yield ask_save (title, base_name (doc, _("Presentation")) + "." + ext, { ext }, filter_name);
            if (file == null) return;
            try {
                if (ext == "rtf") FileUtils.set_contents (file.get_path (), DeckOutline.to_rtf (doc.pres));
                else FileUtils.set_data (file.get_path (), Document.serialize_as (doc.pres, ext));
                add_toast (new Toast (_("Exported \"%s\"").printf (file.get_basename ())));
            } catch (Error e) {
                show_error (_("Could Not Export"), e.message);
            }
        }

        private async void export_copy (FileKind kind) {
            if (doc == null) return;
            canvas.commit_edit ();
            string ext = kind == FileKind.ODP ? "odp" : "pptx";
            var file = yield ask_save (kind == FileKind.ODP ? _("Export as OpenDocument") : _("Export as PowerPoint"), base_name (doc, _("Presentation")) + "." + ext, { ext }, kind == FileKind.ODP ? _("OpenDocument Presentation (.odp)") : _("PowerPoint Presentation (.pptx)"));
            if (file == null) return;
            try {
                FileUtils.set_data (file.get_path (), Document.serialize (doc.pres, kind));
                add_toast (new Toast (_("Exported \"%s\"").printf (file.get_basename ())));
            } catch (Error e) {
                show_error (_("Could Not Export"), e.message);
            }
        }

        private void print_deck () {
            if (doc == null) return;
            canvas.commit_edit ();
            if (doc.pres.slides.size == 0) {
                add_toast (new Toast (_("There are no slides to print.")));
                return;
            }
            var source = new SlidesPrintSource (doc.pres, base_name (doc, _("Presentation")), doc.current_slide);
            var options = Singularity.Print.PresetStore.get_default ().last_used (app.application_id ?? "dev.sinty.slides") ?? new Singularity.Print.JobOptions ();
            options.landscape = doc.pres.width >= doc.pres.height;
            Singularity.Print.run_source.begin (this, source, options);
        }

        public void show_error (string title, string message) {
            var dlg = new ConfirmDialog (app, title, "dialog-error", message, _("OK"), ConfirmDialog.ActionStyle.SUGGESTED);
            dlg.transient_for = this;
            dlg.present ();
        }

        private void sync_actions () {
            foreach (string name in doc_actions) {
                var a = lookup_action (name) as SimpleAction;
                if (a != null) a.set_enabled (doc != null);
            }
            sync_share ();
        }

        private void sync_share () {
            var a = lookup_action ("share") as SimpleAction;
            bool can = doc != null && doc.path != null;
            if (a != null) a.set_enabled (can);
            if (share_bubble != null) share_bubble.sensitive = can;
        }

        public void run (string name) {
            activate_action (name, null);
        }

        private delegate void Act ();

        private static string? text_action (string name) {
            switch (name) {
                case "copy": return "clipboard.copy";
                case "cut": return "clipboard.cut";
                case "paste": return "clipboard.paste";
                case "select-all": return "selection.select-all";
                case "undo": return "text.undo";
                case "redo": return "text.redo";
                default: return null;
            }
        }

        private bool focus_in_text () {
            var f = get_focus ();
            return f != null && (f is Gtk.Text || f is Gtk.TextView) && f != canvas;
        }

        private bool focus_in_slides_list () {
            var f = get_focus ();
            return f != null && (f.is_ancestor (sidebar) || f.is_ancestor (sorter)) && view_mode != ViewMode.MASTER;
        }

        private void act (string name, owned Act handler, bool needs_doc = true) {
            var a = new SimpleAction (name, null);
            if (needs_doc) doc_actions += name;
            string? forward = text_action (name);
            a.activate.connect (() => {
                if (forward != null && focus_in_text ()) {
                    get_focus ().activate_action_variant (forward, null);
                    return;
                }
                if (needs_doc && doc == null) return;
                handler ();
            });
            add_action (a);
        }

        private void toggle_act (string name, bool initial, owned BoolAct handler) {
            var a = new SimpleAction.stateful (name, null, new Variant.boolean (initial));
            doc_actions += name;
            a.activate.connect (() => {
                if (doc == null) return;
                bool v = !a.get_state ().get_boolean ();
                a.set_state (new Variant.boolean (v));
                handler (v);
            });
            add_action (a);
        }

        private delegate void BoolAct (bool v);

        private Gee.List<Element> sel () {
            return canvas.selection;
        }

        private void edit (string label, owned Document.EditFunc f, string key = "") {
            if (doc == null) return;
            doc.checkpoint (label, key);
            f ();
            doc.touch ();
            canvas.queue_draw ();
            content_edited ();
            inspector.sync_geometry ();
        }

        public void format_runs (string label, RunEdit f, string key = "") {
            if (canvas.editor != null) {
                canvas.editor.apply_run (f);
                canvas.editor.grab_focus ();
                return;
            }
            var targets = text_targets ();
            if (targets.size == 0) return;
            edit (label, () => {
                foreach (var b in targets) b.apply_to_runs (f);
            }, key);
            foreach (var e in sel ()) canvas.fit_text_box (e);
        }

        public void format_paragraphs (string label, ParagraphEdit f, string key = "") {
            if (canvas.editor != null) {
                canvas.editor.apply_paragraph (f);
                return;
            }
            var targets = text_targets ();
            if (targets.size == 0) return;
            edit (label, () => {
                foreach (var b in targets) b.apply_to_paragraphs (f);
            }, key);
            foreach (var e in sel ()) canvas.fit_text_box (e);
        }

        private Gee.ArrayList<TextBody> text_targets () {
            var list = new Gee.ArrayList<TextBody> ();
            foreach (var e in sel ()) collect_bodies (e, list, e is TableElement && sel ().size == 1);
            return list;
        }

        private void collect_bodies (Element e, Gee.ArrayList<TextBody> list, bool cells_only) {
            var g = e as GroupElement;
            if (g != null) {
                foreach (var c in g.children) collect_bodies (c, list, false);
                return;
            }
            var t = e as TableElement;
            if (t != null) {
                bool range = cells_only && canvas.cell_r1 >= 0;
                int r1 = range ? int.min (canvas.cell_r1, canvas.cell_r2) : 0, r2 = range ? int.max (canvas.cell_r1, canvas.cell_r2) : t.rows - 1;
                int c1 = range ? int.min (canvas.cell_c1, canvas.cell_c2) : 0, c2 = range ? int.max (canvas.cell_c1, canvas.cell_c2) : t.cols - 1;
                for (int r = r1; r <= r2; r++) for (int c = c1; c <= c2; c++) list.add (t.cells[r][c].text);
                return;
            }
            var s = e as ShapeElement;
            if (s != null && s.shape != ShapeKind.LINE) list.add (s.ensure_text ());
        }

        private bool current_flag (RunFlag f) {
            TextRun r;
            if (canvas.editor != null) {
                var st = canvas.editor.current_style ();
                switch (f) {
                    case RunFlag.BOLD: return st.bold;
                    case RunFlag.ITALIC: return st.italic;
                    case RunFlag.UNDERLINE: return st.underline;
                    default: return st.strike;
                }
            }
            var bodies = text_targets ();
            if (bodies.size == 0) return false;
            r = new TextRun ();
            bodies[0].first_run_format (r);
            var e = sel ()[0];
            var ctx = canvas.context ();
            var ls = doc.pres.level_style (ctx.slide, ctx.layout, ctx.master, e, 0);
            var rs = doc.pres.run_style (ls, r, ctx.theme);
            switch (f) {
                case RunFlag.BOLD: return rs.bold;
                case RunFlag.ITALIC: return rs.italic;
                case RunFlag.UNDERLINE: return rs.underline;
                default: return rs.strike;
            }
        }

        private enum RunFlag {
            BOLD,
            ITALIC,
            UNDERLINE,
            STRIKE
        }

        private void toggle_flag (RunFlag f, string label) {
            int v = current_flag (f) ? 0 : 1;
            format_runs (label, (r) => {
                switch (f) {
                    case RunFlag.BOLD: r.bold = v; break;
                    case RunFlag.ITALIC: r.italic = v; break;
                    case RunFlag.UNDERLINE: r.underline = v; break;
                    default: r.strike = v; break;
                }
            });
        }

        private void font_step (double factor) {
            var ctx = canvas.context ();
            double base_size = 18;
            if (canvas.editor != null) base_size = canvas.editor.current_style ().size;
            else if (sel ().size > 0) {
                var bodies = text_targets ();
                if (bodies.size > 0) {
                    var r = new TextRun ();
                    bodies[0].first_run_format (r);
                    var ls = doc.pres.level_style (ctx.slide, ctx.layout, ctx.master, sel ()[0], 0);
                    base_size = doc.pres.run_style (ls, r, ctx.theme).size;
                }
            }
            double[] steps = { 8, 9, 10, 11, 12, 14, 16, 18, 20, 24, 28, 32, 36, 40, 44, 48, 54, 60, 66, 72, 80, 88, 96, 120, 144, 200 };
            double target = base_size;
            if (factor > 1) {
                foreach (double s in steps) if (s > base_size + 0.1) {
                    target = s;
                    break;
                }
            } else {
                for (int i = steps.length - 1; i >= 0; i--) if (steps[i] < base_size - 0.1) {
                    target = steps[i];
                    break;
                }
            }
            format_runs (_("Font Size"), (r) => r.size = target);
        }

        private void install_actions () {
            act ("save", () => save.begin (false));
            act ("save-as", () => save.begin (true));
            act ("save-online", () => CloudActions.save_document (this));
            act ("export-pdf", () => Dialogs.export_pdf (this));
            act ("export-image", () => export_current.begin ("png"));
            act ("export-svg", () => export_current.begin ("svg"));
            act ("export-images", () => Dialogs.export_images (this));
            act ("export-pptx", () => export_copy.begin (FileKind.PPTX));
            act ("export-odp", () => export_copy.begin (FileKind.ODP));
            act ("export-ppsx", () => export_as.begin ("ppsx"));
            act ("export-potx", () => export_as.begin ("potx"));
            act ("export-otp", () => export_as.begin ("otp"));
            act ("export-rtf", () => export_as.begin ("rtf"));
            act ("export-video", () => Dialogs.export_video (this));
            act ("print", () => print_deck ());
            Singularity.Share.add_action (this, this, () => {
                return doc != null && doc.path != null ? new Singularity.ShareContent.for_files ({ File.new_for_path (doc.path) }) : null;
            });
            act ("properties", () => Dialogs.properties (this));
            act ("close-doc", () => close_document ());
            act ("close", () => close (), false);
            act ("undo", () => {
                canvas.commit_edit ();
                doc.undo ();
            });
            act ("redo", () => {
                canvas.commit_edit ();
                doc.redo ();
            });
            act ("cut", () => {
                if (focus_in_slides_list ()) {
                    copy_slides ();
                    delete_slides ();
                    return;
                }
                copy_elements ();
                delete_elements (_("Cut"));
            });
            act ("copy", () => {
                if (focus_in_slides_list ()) copy_slides ();
                else copy_elements ();
            });
            act ("paste", () => {
                if (focus_in_slides_list () && slide_clip.size > 0) paste_slides ();
                else paste.begin (false);
            });
            act ("paste-style", () => paste.begin (true));
            act ("update-charts", () => update_linked_charts.begin ());
            act ("duplicate", () => {
                if (focus_in_slides_list () || sel ().size == 0) duplicate_slides ();
                else duplicate_elements ();
            });
            act ("delete", () => {
                if (focus_in_slides_list ()) delete_slides ();
                else delete_elements (_("Delete"));
            });
            act ("select-all", () => {
                if (view_mode == ViewMode.SORTER) sorter.flow.select_all ();
                else if (focus_in_slides_list ()) sidebar.list.select_all ();
                else canvas.select_all ();
            });
            act ("find", () => open_find (false));
            act ("replace", () => open_find (true));
            act ("spelling", () => Dialogs.spelling (this));
            act ("view-normal", () => set_view (ViewMode.NORMAL));
            act ("view-sorter", () => set_view (ViewMode.SORTER));
            act ("view-master", () => set_view (ViewMode.MASTER));
            act ("sidebar", () => {
                set_sidebar_visible (!get_sidebar_visible ());
                ribbon.sync_panels ();
            });
            act ("notes", () => {
                notes_revealer.reveal_child = !notes_revealer.reveal_child;
                if (app.settings != null) app.settings.set_boolean ("show-notes", notes_revealer.reveal_child);
                ribbon.sync_panels ();
            });
            act ("inspector", () => toggle_panel ("format"));
            act ("animations", () => toggle_panel ("animate"));
            toggle_act ("guides", app.get_bool ("snap-to-guides", true), (v) => {
                canvas.snap = v;
                if (app.settings != null) app.settings.set_boolean ("snap-to-guides", v);
            });
            canvas.snap = app.get_bool ("snap-to-guides", true);
            act ("zoom-in", () => canvas.zoom_to (canvas.scale * 1.25));
            act ("zoom-out", () => canvas.zoom_to (canvas.scale / 1.25));
            act ("zoom-fit", () => canvas.zoom_fit ());
            act ("zoom-actual", () => canvas.zoom_to (96.0 / 72.0));
            act ("new-slide", () => new_slide (null));
            act ("duplicate-slide", () => duplicate_slides ());
            act ("delete-slide", () => delete_slides ());
            act ("hide-slide", () => {
                var idx = selected_slides ();
                bool hide = !doc.pres.slides[idx[0]].hidden;
                edit (hide ? _("Hide Slide") : _("Show Slide"), () => {
                    foreach (int i in idx) doc.pres.slides[i].hidden = hide;
                });
                refresh_thumbnails ();
            });
            act ("slide-up", () => {
                int[] idx = selected_slides ();
                if (idx[0] > 0) move_slides (idx, idx[0] - 1);
            });
            act ("slide-down", () => {
                int[] idx = selected_slides ();
                if (idx[idx.length - 1] < doc.pres.slides.size - 1) move_slides (idx, idx[idx.length - 1] + 2);
            });
            act ("reset-layout", () => {
                var s = doc.slide;
                if (s == null) return;
                var l = doc.pres.layout_for (s);
                if (l == null) return;
                edit (_("Reset Layout"), () => {
                    foreach (var e in s.elements) if (e.placeholder != PlaceholderKind.NONE) e.inherit_geometry = true;
                    Factory.apply_layout (doc.pres, s, l);
                });
                canvas.clear_selection ();
            });
            act ("background", () => {
                canvas.clear_selection ();
                right_stack.visible_child_name = "format";
                right_revealer.reveal_child = true;
                inspector.rebuild ();
            });
            act ("transition-all", () => {
                var s = doc.slide;
                if (s == null) return;
                edit (_("Apply Transition to All Slides"), () => {
                    foreach (var o in doc.pres.slides) if (o != s) o.transition = s.transition.clone ();
                });
                add_toast (new Toast (_("Transition applied to all slides")));
            });
            act ("insert-text", () => {
                var p = doc.pres;
                var tb = Factory.text_box (p, p.width / 2 - 150, p.height / 2 - 20, 300, _("Text"));
                add_element (tb, _("Insert Text Box"));
                canvas.begin_edit (tb, -1, -1, -1, -1);
            });
            var shape = new SimpleAction ("insert-shape", VariantType.STRING);
            shape.activate.connect ((v) => {
                if (doc != null) insert_shape (ShapeKind.from_ooxml (v.get_string ()));
            });
            add_action (shape);
            doc_actions += "insert-shape";
            var chart = new SimpleAction ("insert-chart", VariantType.INT32);
            chart.activate.connect ((v) => {
                if (doc != null) insert_chart ((ChartKind) v.get_int32 ());
            });
            add_action (chart);
            doc_actions += "insert-chart";
            act ("insert-image", () => {
                choose_image.begin ((obj, res) => {
                    string mime;
                    var data = choose_image.end (res, out mime);
                    if (data != null) insert_image (data, mime, _("Picture"));
                });
            });
            act ("insert-equation", () => insert_equation.begin ());
            act ("insert-table", () => Dialogs.insert_table (this));
            act ("insert-link", () => insert_link ());
            act ("insert-slide-number", () => insert_field ("slidenum"));
            act ("insert-date", () => insert_field ("datetime1"));
            act ("header-footer", () => {
                canvas.clear_selection ();
                right_stack.visible_child_name = "format";
                right_revealer.reveal_child = true;
                inspector.rebuild ();
            });
            act ("bold", () => toggle_flag (RunFlag.BOLD, _("Bold")));
            act ("italic", () => toggle_flag (RunFlag.ITALIC, _("Italic")));
            act ("underline", () => toggle_flag (RunFlag.UNDERLINE, _("Underline")));
            act ("strike", () => toggle_flag (RunFlag.STRIKE, _("Strikethrough")));
            act ("superscript", () => format_runs (_("Superscript"), (r) => r.baseline = r.baseline > 0 ? 0 : 1));
            act ("subscript", () => format_runs (_("Subscript"), (r) => r.baseline = r.baseline < 0 ? 0 : -1));
            act ("font-bigger", () => font_step (1.1));
            act ("font-smaller", () => font_step (0.9));
            act ("align-left", () => format_paragraphs (_("Align"), (p) => p.align = TextAlign.LEFT));
            act ("align-center", () => format_paragraphs (_("Align"), (p) => p.align = TextAlign.CENTER));
            act ("align-right", () => format_paragraphs (_("Align"), (p) => p.align = TextAlign.RIGHT));
            act ("align-justify", () => format_paragraphs (_("Align"), (p) => p.align = TextAlign.JUSTIFY));
            act ("bullets", () => format_paragraphs (_("Bullets"), (p) => {
                p.bullet = p.bullet == BulletKind.CHAR ? BulletKind.NONE : BulletKind.CHAR;
                p.bullet_char = "•";
            }));
            act ("numbering", () => format_paragraphs (_("Numbering"), (p) => p.bullet = p.bullet == BulletKind.NUMBER ? BulletKind.NONE : BulletKind.NUMBER));
            act ("no-bullets", () => format_paragraphs (_("Bullets"), (p) => p.bullet = BulletKind.NONE));
            act ("indent-more", () => format_paragraphs (_("Indent"), (p) => p.level = int.min (p.level + 1, 8)));
            act ("indent-less", () => format_paragraphs (_("Indent"), (p) => p.level = int.max (p.level - 1, 0)));
            act ("clear-format", () => format_runs (_("Clear Formatting"), (r) => {
                string t = r.text;
                string link = r.link;
                string field = r.field;
                r.copy_format (new TextRun ());
                r.text = t;
                r.link = link;
                r.field = field;
            }));
            var theme = new SimpleAction ("theme", VariantType.STRING);
            theme.activate.connect ((v) => {
                var preset = ThemePreset.find (v.get_string ());
                if (doc != null && preset != null) apply_theme (preset);
            });
            add_action (theme);
            doc_actions += "theme";
            var size = new SimpleAction ("slide-size", VariantType.STRING);
            size.activate.connect ((v) => {
                if (doc == null) return;
                double w, h;
                aspect_size (v.get_string (), out w, out h);
                if (Math.fabs (w - doc.pres.width) < 1 && Math.fabs (h - doc.pres.height) < 1) return;
                canvas.commit_edit ();
                edit (_("Slide Size"), () => SlideSize.resize (doc.pres, w, h));
                on_doc_replaced (doc.current_slide);
            });
            add_action (size);
            doc_actions += "slide-size";
            act ("bring-front", () => reorder (2));
            act ("bring-forward", () => reorder (1));
            act ("send-backward", () => reorder (-1));
            act ("send-back", () => reorder (-2));
            act ("arrange-left", () => align_objects (0));
            act ("arrange-center", () => align_objects (1));
            act ("arrange-right", () => align_objects (2));
            act ("arrange-top", () => align_objects (3));
            act ("arrange-middle", () => align_objects (4));
            act ("arrange-bottom", () => align_objects (5));
            act ("distribute-h", () => distribute (true));
            act ("distribute-v", () => distribute (false));
            act ("group", () => group_selection ());
            act ("ungroup", () => ungroup_selection ());
            act ("flip-h", () => edit (_("Flip"), () => {
                foreach (var e in sel ()) e.flip_h = !e.flip_h;
            }));
            act ("flip-v", () => edit (_("Flip"), () => {
                foreach (var e in sel ()) e.flip_v = !e.flip_v;
            }));
            act ("rotate-left", () => edit (_("Rotate"), () => {
                foreach (var e in sel ()) e.rotation = Math.fmod (e.rotation + 270, 360);
            }));
            act ("rotate-right", () => edit (_("Rotate"), () => {
                foreach (var e in sel ()) e.rotation = Math.fmod (e.rotation + 90, 360);
            }));
            act ("lock", () => {
                bool lk = sel ().size > 0 && !sel ()[0].locked;
                edit (lk ? _("Lock") : _("Unlock"), () => {
                    foreach (var e in sel ()) e.locked = lk;
                });
                inspector.rebuild ();
            });
            act ("table-row-above", () => table_op (0));
            act ("table-row-below", () => table_op (1));
            act ("table-row-delete", () => table_op (2));
            act ("table-col-left", () => table_op (3));
            act ("table-col-right", () => table_op (4));
            act ("table-col-delete", () => table_op (5));
            act ("table-merge", () => table_op (6));
            act ("table-split", () => table_op (7));
            act ("table-distribute", () => table_op (8));
            act ("play-start", () => start_show (0, false, false));
            act ("play-current", () => start_show (doc.current_slide, false, false));
            act ("presenter", () => start_show (doc.current_slide, true, false));
            act ("rehearse", () => start_show (0, true, true));
            act ("rehearse-coach", () => start_show (0, true, true, "", false, true));
            toggle_act ("use-timings", true, (v) => edit (_("Use Slide Timings"), () => doc.pres.use_timings = v));
            toggle_act ("loop", false, (v) => edit (_("Loop"), () => doc.pres.loop = v));
            install_more_actions ();
            sync_actions ();
        }

        private int[] selected_slides () {
            int[] idx = view_mode == ViewMode.SORTER ? sorter.selected_indices () : sidebar.selected_indices ();
            if (idx.length == 0) idx = { doc.current_slide };
            return idx;
        }

        public void new_slide (Layout? layout) {
            if (doc == null) return;
            canvas.commit_edit ();
            var cur = doc.slide;
            Layout? l = layout;
            if (l == null && cur != null) {
                var cl = doc.pres.layout_for (cur);
                if (cl != null && cl.kind == LayoutKind.TITLE) l = doc.pres.master_for (cur).layout_of_kind (LayoutKind.TITLE_CONTENT);
                else l = cl;
            }
            if (l == null) l = doc.pres.master.layout_of_kind (LayoutKind.TITLE_CONTENT) ?? doc.pres.master.layouts[0];
            int at = doc.pres.slides.size == 0 ? 0 : doc.current_slide + 1;
            edit (_("New Slide"), () => {
                var s = Factory.add_slide (doc.pres, l, at);
                if (cur != null) s.transition = cur.transition.clone ();
            });
            doc.current_slide = at;
            sidebar.load (doc.pres, at);
            if (view_mode == ViewMode.SORTER) sorter.load (doc.pres, at);
            show_current ();
        }

        private void duplicate_slides () {
            int[] idx = selected_slides ();
            int at = idx[idx.length - 1] + 1;
            edit (_("Duplicate Slide"), () => {
                int k = 0;
                foreach (int i in idx) {
                    var c = doc.pres.slides[i].duplicate ();
                    reassign_ids (c);
                    doc.pres.slides.insert (at + k++, c);
                }
            });
            doc.current_slide = at;
            sidebar.load (doc.pres, at);
            if (view_mode == ViewMode.SORTER) sorter.load (doc.pres, at);
            show_current ();
        }

        private void reassign_ids (Slide s) {
            var map = new Gee.HashMap<int, int> ();
            foreach (var e in s.elements) remap (e, map);
            foreach (var a in s.animations) if (map.has_key (a.target)) a.target = map[a.target];
        }

        private void remap (Element e, Gee.HashMap<int, int> map) {
            int old = e.id;
            e.id = doc.pres.new_id ();
            map[old] = e.id;
            var g = e as GroupElement;
            if (g != null) foreach (var c in g.children) remap (c, map);
        }

        private void delete_slides () {
            int[] idx = selected_slides ();
            if (doc.pres.slides.size <= idx.length) {
                add_toast (new Toast (_("A presentation needs at least one slide")));
                return;
            }
            canvas.commit_edit ();
            edit (idx.length == 1 ? _("Delete Slide") : _("Delete Slides"), () => {
                for (int i = idx.length - 1; i >= 0; i--) doc.pres.slides.remove_at (idx[i]);
            });
            doc.current_slide = int.min (idx[0], doc.pres.slides.size - 1);
            sidebar.load (doc.pres, doc.current_slide);
            if (view_mode == ViewMode.SORTER) sorter.load (doc.pres, doc.current_slide);
            show_current ();
            var t = new Toast (idx.length == 1 ? _("Slide deleted") : _("Slides deleted"));
            t.button_label = _("Undo");
            t.button_clicked.connect (() => run ("undo"));
            add_toast (t);
        }

        public void move_slides (int[] idx, int to) {
            if (doc == null || idx.length == 0) return;
            var moving = new Gee.ArrayList<Slide> ();
            foreach (int i in idx) if (i >= 0 && i < doc.pres.slides.size) moving.add (doc.pres.slides[i]);
            if (moving.size == 0) return;
            int before = 0;
            foreach (int i in idx) if (i < to) before++;
            int dest = (to - before).clamp (0, doc.pres.slides.size - moving.size);
            bool same = true;
            for (int k = 0; k < moving.size; k++) if (doc.pres.slides.index_of (moving[k]) != dest + k) same = false;
            if (same) return;
            edit (_("Move Slides"), () => {
                foreach (var s in moving) doc.pres.slides.remove (s);
                for (int k = 0; k < moving.size; k++) doc.pres.slides.insert (dest + k, moving[k]);
            });
            doc.current_slide = dest;
            sidebar.load (doc.pres, dest);
            if (view_mode == ViewMode.SORTER) sorter.load (doc.pres, dest);
            show_current ();
        }

        private void show_slide_menu (int index, Widget anchor) {
            var menu = new ContextMenu (anchor);
            menu.add_item (_("New Slide"), "list-add-symbolic", () => new_slide (null));
            var layouts = menu.add_submenu (_("New Slide with Layout"), "slides-layout-symbolic");
            foreach (var l in doc.pres.master_for (doc.pres.slides[index.clamp (0, doc.pres.slides.size - 1)]).layouts) {
                var ll = l;
                layouts.add_item (l.name, null, () => new_slide (ll));
            }
            menu.add_item (_("Duplicate"), "edit-copy-symbolic", () => duplicate_slides ());
            menu.add_separator ();
            menu.add_item (_("Cut"), "edit-cut-symbolic", () => {
                copy_slides ();
                delete_slides ();
            });
            menu.add_item (_("Copy"), "edit-copy-symbolic", () => copy_slides ());
            menu.add_item (_("Paste"), "edit-paste-symbolic", () => paste_slides ());
            menu.add_separator ();
            bool hidden = doc.pres.slides[index].hidden;
            menu.add_item (hidden ? _("Show Slide") : _("Hide Slide"), hidden ? "view-reveal-symbolic" : "view-conceal-symbolic", () => run ("hide-slide"));
            var apply = menu.add_submenu (_("Layout"), "slides-layout-symbolic");
            foreach (var l in doc.pres.master_for (doc.pres.slides[index]).layouts) {
                var ll = l;
                apply.add_item (l.name, null, () => {
                    int[] idx = selected_slides ();
                    edit (_("Change Layout"), () => {
                        foreach (int i in idx) Factory.apply_layout (doc.pres, doc.pres.slides[i], ll);
                    });
                    refresh_thumbnails ();
                    show_current ();
                });
            }
            menu.add_item (_("Play from Here"), "media-playback-start-symbolic", () => start_show (index, false, false));
            var sections = menu.add_submenu (_("Section"), "view-list-symbolic");
            sections.add_item (_("Add Section"), null, () => run ("add-section"));
            if (doc.pres.section_start (index) >= 0) {
                sections.add_item (_("Rename Section"), null, () => run ("rename-section"));
                sections.add_item (_("Move Section Up"), null, () => run ("section-up"));
                sections.add_item (_("Move Section Down"), null, () => run ("section-down"));
                sections.add_item (_("Remove Section"), null, () => run ("remove-section"));
                sections.add_item (_("Remove Section and Slides"), null, () => run ("remove-section-slides"));
            }
            menu.add_separator ();
            menu.add_item (_("Delete"), "user-trash-symbolic", () => delete_slides (), "destructive");
            popup_menu (menu);
        }

        private Gdk.Rectangle point_rect (double x, double y) {
            var rect = Gdk.Rectangle ();
            rect.x = (int) x;
            rect.y = (int) y;
            rect.width = 1;
            rect.height = 1;
            return rect;
        }

        private void show_canvas_menu (double x, double y) {
            var menu = new ContextMenu (canvas);
            menu.pointing_to = point_rect (x, y);
            if (sel ().size > 0) {
                menu.add_item (_("Cut"), "edit-cut-symbolic", () => run ("cut"));
                menu.add_item (_("Copy"), "edit-copy-symbolic", () => run ("copy"));
                menu.add_item (_("Paste"), "edit-paste-symbolic", () => run ("paste"));
                menu.add_item (_("Duplicate"), "edit-copy-symbolic", () => duplicate_elements ());
                menu.add_separator ();
                var e = sel ()[0];
                if (sel ().size == 1 && e is ShapeElement && ((ShapeElement) e).shape != ShapeKind.LINE) menu.add_item (_("Edit Text"), "document-edit-symbolic", () => canvas.begin_edit (e, -1, -1, -1, -1));
                if (sel ().size == 1 && e is ChartElement) menu.add_item (_("Edit Data"), "document-edit-symbolic", () => edit_chart_data ((ChartElement) e));
                if (sel ().size == 1 && e is ImageElement) {
                    menu.add_item (_("Crop"), "slides-crop-symbolic", () => {
                        canvas.crop_mode = true;
                        canvas.queue_draw ();
                    });
                    menu.add_item (_("Replace Picture"), "document-open-symbolic", () => replace_image ((ImageElement) e));
                }
                var arrange = menu.add_submenu (_("Arrange"), "slides-bring-front-symbolic");
                arrange.add_item (_("Bring to Front"), null, () => run ("bring-front"));
                arrange.add_item (_("Bring Forward"), null, () => run ("bring-forward"));
                arrange.add_item (_("Send Backward"), null, () => run ("send-backward"));
                arrange.add_item (_("Send to Back"), null, () => run ("send-back"));
                var align = menu.add_submenu (_("Align"), "slides-align-center-symbolic");
                align.add_item (_("Left"), null, () => run ("arrange-left"));
                align.add_item (_("Center"), null, () => run ("arrange-center"));
                align.add_item (_("Right"), null, () => run ("arrange-right"));
                align.add_item (_("Top"), null, () => run ("arrange-top"));
                align.add_item (_("Middle"), null, () => run ("arrange-middle"));
                align.add_item (_("Bottom"), null, () => run ("arrange-bottom"));
                if (sel ().size > 1) menu.add_item (_("Group"), "slides-group-symbolic", () => run ("group"));
                if (sel ().size == 1 && e is GroupElement) menu.add_item (_("Ungroup"), "slides-ungroup-symbolic", () => run ("ungroup"));
                if (canvas.slide != null) {
                    menu.add_item (_("Add Animation"), "slides-animate-symbolic", () => {
                        right_stack.visible_child_name = "animate";
                        right_revealer.reveal_child = true;
                        anim_panel.rebuild ();
                    });
                }
                menu.add_item (_("Format"), "slides-format-symbolic", () => {
                    right_stack.visible_child_name = "format";
                    right_revealer.reveal_child = true;
                    inspector.rebuild ();
                });
                menu.add_separator ();
                menu.add_item (_("Delete"), "user-trash-symbolic", () => run ("delete"), "destructive");
            } else {
                menu.add_item (_("Paste"), "edit-paste-symbolic", () => run ("paste"));
                menu.add_item (_("Select All"), "edit-select-all-symbolic", () => run ("select-all"));
                menu.add_separator ();
                if (canvas.slide != null) {
                    menu.add_item (_("New Slide"), "list-add-symbolic", () => new_slide (null));
                    var layouts = menu.add_submenu (_("Layout"), "slides-layout-symbolic");
                    foreach (var l in doc.pres.master_for (canvas.slide).layouts) {
                        var ll = l;
                        layouts.add_item (l.name, null, () => {
                            edit (_("Change Layout"), () => Factory.apply_layout (doc.pres, canvas.slide, ll));
                            show_current ();
                        });
                    }
                    menu.add_item (_("Reset Layout"), "view-refresh-symbolic", () => run ("reset-layout"));
                }
                menu.add_item (_("Background"), "slides-format-symbolic", () => run ("background"));
            }
            popup_menu (menu);
        }

        private void add_element (Element e, string label) {
            canvas.commit_edit ();
            for (int guard = 0; guard < 40; guard++) {
                bool clash = false;
                foreach (var o in canvas.elements ()) if (o.kind == e.kind && Math.fabs (o.x - e.x) < 0.5 && Math.fabs (o.y - e.y) < 0.5) clash = true;
                if (!clash) break;
                e.move_by (18, 18);
            }
            edit (label, () => {
                if (e.id == 0) doc.pres.assign_ids (e);
                canvas.elements ().add (e);
            });
            canvas.select (e);
        }

        public void insert_shape (ShapeKind k) {
            var p = doc.pres;
            double w = k == ShapeKind.LINE ? 240 : 160, h = k == ShapeKind.LINE ? 0 : 160;
            if (k == ShapeKind.ARROW_RIGHT || k == ShapeKind.CHEVRON || k == ShapeKind.CALLOUT) h = 100;
            var s = Factory.shape (p, k, (p.width - w) / 2, (p.height - h) / 2, w, h);
            add_element (s, _("Insert Shape"));
        }

        private ShapeElement? empty_content_placeholder () {
            if (canvas.slide == null) return null;
            foreach (var e in canvas.slide.elements) {
                var sh = e as ShapeElement;
                if (sh != null && e.placeholder == PlaceholderKind.OBJECT && (sh.text == null || sh.text.is_empty ())) return sh;
            }
            return null;
        }

        private void replace_placeholder (Element ph, Element e, string label) {
            canvas.commit_edit ();
            edit (label, () => {
                doc.pres.assign_ids (e);
                var list = canvas.elements ();
                int i = list.index_of (ph);
                if (i >= 0) list[i] = e;
                else list.add (e);
                canvas.slide.remove_animations_for (ph.id);
            });
            canvas.select (e);
        }

        public void insert_chart (ChartKind k) {
            var p = doc.pres;
            var ch = new ChartElement (k);
            ch.sample_data ();
            var ph = empty_content_placeholder ();
            if (ph != null) {
                ch.set_geometry (ph.x, ph.y, ph.w, ph.h);
                replace_placeholder (ph, ch, _("Insert Chart"));
                return;
            }
            ch.set_geometry (p.width * 0.15, p.height * 0.2, p.width * 0.7, p.height * 0.65);
            add_element (ch, _("Insert Chart"));
        }

        public void insert_table (int rows, int cols) {
            var p = doc.pres;
            var ph = empty_content_placeholder ();
            double w = ph != null ? ph.w : double.min (p.width * 0.8, cols * 180);
            double rh = ph != null ? double.min (40, ph.h / rows) : 40;
            var t = new TableElement (rows, cols, w, rh);
            if (ph != null) {
                t.set_geometry (ph.x, ph.y, w, rows * rh);
                replace_placeholder (ph, t, _("Insert Table"));
                return;
            }
            t.set_geometry ((p.width - w) / 2, (p.height - rows * rh) / 2, w, rows * rh);
            add_element (t, _("Insert Table"));
        }

        public void edit_chart_data (ChartElement ch) {
            Dialogs.chart_data (this, ch);
        }

        public async Bytes? choose_image (out string mime) {
            mime = "";
            var dialog = new FileDialog ();
            dialog.title = _("Insert Image");
            var filters = new GLib.ListStore (typeof (FileFilter));
            var f = new FileFilter ();
            f.name = _("Images");
            f.add_mime_type ("image/*");
            filters.append (f);
            dialog.filters = filters;
            try {
                var file = yield dialog.open (this, null);
                if (file == null) return null;
                uint8[] data;
                FileUtils.get_data (file.get_path (), out data);
                mime = ImageElement.mime_for (file.get_basename ());
                return new Bytes (data);
            } catch (Error e) {
                if (!(e is Gtk.DialogError.DISMISSED)) show_error (_("Could Not Open Image"), e.message);
                return null;
            }
        }

        private void insert_image_file (File file) {
            try {
                uint8[] data;
                FileUtils.get_data (file.get_path (), out data);
                insert_image (new Bytes (data), ImageElement.mime_for (file.get_basename ()), file.get_basename ());
            } catch (Error e) {
                show_error (_("Could Not Open Image"), e.message);
            }
        }

        public void insert_image (Bytes data, string mime, string name) {
            int pw, ph;
            if (!ImageCache.size_of (data, out pw, out ph) || pw <= 0) {
                show_error (_("Could Not Open Image"), _("The file is not a supported image."));
                return;
            }
            var p = doc.pres;
            var img = new ImageElement (data, mime);
            img.pixel_width = pw;
            img.pixel_height = ph;
            img.name = name;
            foreach (var e in canvas.elements ()) {
                var sh = e as ShapeElement;
                if (canvas.slide != null && sh != null && e.placeholder == PlaceholderKind.PICTURE && (sh.text == null || sh.text.is_empty ())) {
                    double sc = double.max (e.w / pw, e.h / ph);
                    double vw = e.w / (pw * sc), vh = e.h / (ph * sc);
                    img.crop_left = img.crop_right = (1 - vw) / 2;
                    img.crop_top = img.crop_bottom = (1 - vh) / 2;
                    img.set_geometry (e.x, e.y, e.w, e.h);
                    img.placeholder = PlaceholderKind.PICTURE;
                    img.placeholder_idx = e.placeholder_idx;
                    edit (_("Insert Image"), () => {
                        doc.pres.assign_ids (img);
                        int i = canvas.elements ().index_of (e);
                        canvas.elements ()[i] = img;
                    });
                    canvas.select (img);
                    return;
                }
            }
            var content = empty_content_placeholder ();
            if (content != null) {
                double fsc = double.min (content.w / pw, content.h / ph);
                double fw = pw * fsc, fh = ph * fsc;
                img.set_geometry (content.x + (content.w - fw) / 2, content.y + (content.h - fh) / 2, fw, fh);
                replace_placeholder (content, img, _("Insert Image"));
                return;
            }
            double max_w = p.width * 0.7, max_h = p.height * 0.7;
            double sc = double.min (1, double.min (max_w / pw, max_h / ph));
            double w = pw * sc, h = ph * sc;
            img.set_geometry ((p.width - w) / 2, (p.height - h) / 2, w, h);
            add_element (img, _("Insert Image"));
        }

        private async void insert_equation () {
            if (!FormulaBridge.available ()) {
                add_toast (new Toast (_("Install Formula to insert equations")));
                return;
            }
            var res = yield FormulaBridge.edit (this, null);
            if (res == null || doc == null) return;
            var p = doc.pres;
            var q = new EquationElement ();
            q.image = res.image;
            q.image_mime = res.mime;
            q.latex = res.latex;
            q.mathml = res.mathml;
            double w = res.width > 0 ? res.width : 200, h = res.height > 0 ? res.height : 60;
            double sc = double.min (1, double.min (p.width * 0.8 / w, p.height * 0.8 / h));
            w *= sc;
            h *= sc;
            q.set_geometry ((p.width - w) / 2, (p.height - h) / 2, w, h);
            add_element (q, _("Insert Equation"));
        }

        public async void edit_equation (EquationElement q) {
            if (!FormulaBridge.available ()) {
                add_toast (new Toast (_("Install Formula to edit equations")));
                return;
            }
            var res = yield FormulaBridge.edit (this, q);
            if (res == null || doc == null) return;
            edit (_("Edit Equation"), () => {
                double cx = q.x, cy = q.y;
                double ratio = q.h > 0 && res.height > 0 ? q.h / res.height : 1;
                q.image = res.image;
                q.image_mime = res.mime;
                q.latex = res.latex;
                q.mathml = res.mathml;
                q.omml = "";
                if (res.width > 0) q.set_geometry (cx, cy, res.width * ratio, res.height * ratio);
            });
            canvas.queue_draw ();
        }

        public void insert_preset (string preset) {
            if (ShapeKind.is_native (preset)) {
                insert_shape (ShapeKind.from_ooxml (preset));
                return;
            }
            var p = doc.pres;
            bool line = preset.contains ("Connector");
            double w = 160, h = line ? 0 : 160;
            if (preset.has_suffix ("Arrow") || preset.has_suffix ("Callout") || preset.has_prefix ("ribbon") || preset.contains ("Scroll")) h = 110;
            if (preset.has_prefix ("actionButton")) {
                w = 72;
                h = 56;
            }
            var s = Factory.shape (p, ShapeKind.RECT, (p.width - w) / 2, (p.height - h) / 2, w, h);
            s.shape = line ? ShapeKind.LINE : ShapeKind.PRESET;
            s.preset = line ? "" : preset;
            if (line) {
                s.fill = new Fill.none ();
                if (preset == "straightConnector1") s.line.tail = ArrowKind.TRIANGLE;
                if (s.line.color == "") s.line.color = "accent1";
            }
            s.click = ShapeCatalog.default_action (preset);
            add_element (s, _("Insert Shape"));
        }

        public void insert_diagram (DiagramLayout layout) {
            var p = doc.pres;
            var d = new DiagramElement ();
            d.layout = layout;
            d.sample (layout.category () == DiagramCategory.CYCLE ? 5 : 3);
            var ph = empty_content_placeholder ();
            if (ph != null) {
                d.set_geometry (ph.x, ph.y, ph.w, ph.h);
                replace_placeholder (ph, d, _("Insert SmartArt"));
                return;
            }
            d.set_geometry (p.width * 0.1, p.height * 0.18, p.width * 0.8, p.height * 0.72);
            add_element (d, _("Insert SmartArt"));
        }

        public async void insert_media (bool video) {
            var dialog = new FileDialog ();
            dialog.title = video ? _("Insert Video") : _("Insert Audio");
            var filters = new GLib.ListStore (typeof (FileFilter));
            var f = new FileFilter ();
            f.name = video ? _("Videos") : _("Audio");
            f.add_mime_type (video ? "video/*" : "audio/*");
            filters.append (f);
            dialog.filters = filters;
            try {
                var file = yield dialog.open (this, null);
                if (file == null) return;
                uint8[] data;
                FileUtils.get_data (file.get_path (), out data);
                insert_media_bytes (new Bytes (data), file.get_basename (), video);
            } catch (Error e) {
                if (!(e is Gtk.DialogError.DISMISSED)) show_error (_("Could Not Insert"), e.message);
            }
        }

        public void insert_media_bytes (Bytes data, string name, bool video) {
            var p = doc.pres;
            var m = new MediaElement ();
            m.data = data;
            m.mime = MediaElement.mime_for (name);
            if (m.mime == "application/octet-stream") m.mime = video ? "video/mp4" : "audio/mpeg";
            m.is_video = m.mime.has_prefix ("video/");
            m.name = name;
            m.start = MediaStart.IN_SEQUENCE;
            if (m.is_video) {
                double w = p.width * 0.6, h = w * 9 / 16;
                m.set_geometry ((p.width - w) / 2, (p.height - h) / 2, w, h);
                MediaProbe.fill.begin (m, (o, r) => {
                    MediaProbe.fill.end (r);
                    canvas.queue_draw ();
                    refresh_current_thumbnail ();
                });
            } else {
                m.set_geometry (p.width - 72, p.height - 72, 48, 48);
                MediaProbe.fill.begin (m);
            }
            var ph = m.is_video ? empty_content_placeholder () : null;
            if (ph != null) {
                m.set_geometry (ph.x, ph.y, ph.w, ph.h);
                replace_placeholder (ph, m, _("Insert Video"));
                return;
            }
            add_element (m, m.is_video ? _("Insert Video") : _("Insert Audio"));
        }

        public void insert_zoom (ZoomKind kind, Gee.List<Slide> targets) {
            var p = doc.pres;
            if (targets.size == 0) return;
            double w = p.width * (targets.size > 1 ? 0.22 : 0.3), h = w * p.height / p.width;
            double gap = 16;
            int cols = int.min (targets.size, 4);
            double total_w = cols * w + (cols - 1) * gap;
            var added = new Gee.ArrayList<Element> ();
            for (int i = 0; i < targets.size; i++) {
                var z = new ZoomElement ();
                z.zoom = kind == ZoomKind.SLIDE ? ZoomKind.SLIDE : ZoomKind.SECTION;
                z.target_uid = targets[i].uid;
                if (targets[i].section != null) z.section_id = targets[i].section.id;
                z.return_to_zoom = kind != ZoomKind.SLIDE;
                int r = i / cols, c = i % cols;
                z.set_geometry ((p.width - total_w) / 2 + c * (w + gap), p.height * 0.3 + r * (h + gap), w, h);
                added.add (z);
            }
            canvas.commit_edit ();
            if (kind == ZoomKind.SUMMARY) {
                edit (_("Insert Summary Zoom"), () => {
                    var s = Factory.add_slide (p, p.master.layout_of_kind (LayoutKind.TITLE_ONLY) ?? p.master.layouts[0], p.slides.index_of (targets[0]));
                    var t = s.placeholder (PlaceholderKind.TITLE);
                    if (t != null && t.text_body () != null) t.text_body ().set_plain (_("Summary"));
                    foreach (var e in added) {
                        p.assign_ids (e);
                        s.elements.add (e);
                    }
                    doc.current_slide = p.slides.index_of (s);
                });
                sidebar.load (p, doc.current_slide);
                show_current ();
                return;
            }
            edit (_("Insert Zoom"), () => {
                foreach (var e in added) {
                    p.assign_ids (e);
                    canvas.elements ().add (e);
                }
            });
            canvas.select (added[0]);
        }

        public async void insert_model () {
            var dialog = new FileDialog ();
            dialog.title = _("Insert 3D Model");
            var filters = new GLib.ListStore (typeof (FileFilter));
            var f = new FileFilter ();
            f.name = _("3D Models");
            f.add_suffix ("glb");
            f.add_suffix ("obj");
            filters.append (f);
            dialog.filters = filters;
            try {
                var file = yield dialog.open (this, null);
                if (file == null) return;
                uint8[] data;
                FileUtils.get_data (file.get_path (), out data);
                var m = new Model3DElement ();
                m.data = new Bytes (data);
                m.format = MeshLoader.format_of (m.data, file.get_basename ());
                if (MeshLoader.load (m.data, m.format) == null) {
                    show_error (_("Could Not Insert"), _("The 3D model could not be read. Binary glTF (.glb) and OBJ files are supported."));
                    return;
                }
                m.name = file.get_basename ();
                m.rot_x = 15;
                m.rot_y = -25;
                var p = doc.pres;
                double side = double.min (p.width, p.height) * 0.5;
                m.set_geometry ((p.width - side) / 2, (p.height - side) / 2, side, side);
                add_element (m, _("Insert 3D Model"));
            } catch (Error e) {
                if (!(e is Gtk.DialogError.DISMISSED)) show_error (_("Could Not Insert"), e.message);
            }
        }

        public void insert_icon (Bytes svg, string name) {
            var p = doc.pres;
            string text = ForeignPart.bytes_text (svg);
            string recolored = text.replace ("fill=\"currentColor\"", "fill=\"#2f5496\"").replace ("#bebebe", "#2f5496").replace ("#2e3436", "#2f5496");
            var data = new Bytes (recolored.data);
            var img = new ImageElement (data, "image/svg+xml");
            img.name = name;
            img.description = name.replace ("-", " ");
            double sz = p.height * 0.18;
            img.set_geometry ((p.width - sz) / 2, (p.height - sz) / 2, sz, sz);
            add_element (img, _("Insert Icon"));
        }

        public void replace_image (ImageElement img) {
            choose_image.begin ((obj, res) => {
                string mime;
                var data = choose_image.end (res, out mime);
                if (data == null) return;
                edit (_("Replace Picture"), () => {
                    img.data = data;
                    img.mime = mime;
                    int pw, ph;
                    if (ImageCache.size_of (data, out pw, out ph)) {
                        img.pixel_width = pw;
                        img.pixel_height = ph;
                    }
                });
            });
        }

        private void insert_link () {
            string current = "";
            if (canvas.editor != null) current = canvas.editor.current_format ().link;
            Dialogs.hyperlink (this, current, (url) => {
                if (canvas.editor != null) {
                    canvas.editor.set_link (url);
                    return;
                }
                format_runs (_("Hyperlink"), (r) => r.link = url);
            });
        }

        private void insert_field (string field) {
            if (canvas.editor != null) {
                canvas.editor.insert_field (field);
                return;
            }
            var p = doc.pres;
            var tb = Factory.text_box (p, p.width - 200, p.height - 60, 140, "");
            tb.text.paragraphs[0].runs.clear ();
            tb.text.paragraphs[0].runs.add (Factory.field_run (field, field == "slidenum" ? "‹#›" : ""));
            tb.text.paragraphs[0].align = TextAlign.RIGHT;
            add_element (tb, field == "slidenum" ? _("Insert Slide Number") : _("Insert Date"));
        }

        private void delete_elements (string label) {
            if (sel ().size == 0) return;
            var victims = new Gee.ArrayList<Element> ();
            victims.add_all (sel ());
            edit (label, () => {
                foreach (var e in victims) {
                    canvas.elements ().remove (e);
                    if (canvas.slide != null) canvas.slide.remove_animations_for (e.id);
                }
            });
            canvas.clear_selection ();
        }

        private void duplicate_elements () {
            var copies = new Gee.ArrayList<Element> ();
            edit (_("Duplicate"), () => {
                foreach (var e in sel ()) {
                    var c = e.clone ();
                    doc.pres.assign_ids (c);
                    c.placeholder = PlaceholderKind.NONE;
                    c.inherit_geometry = false;
                    c.move_by (18, 18);
                    canvas.elements ().add (c);
                    copies.add (c);
                }
            });
            canvas.selection.clear ();
            canvas.selection.add_all (copies);
            canvas.selection_changed ();
            canvas.queue_draw ();
        }

        private void reorder (int how) {
            var list = canvas.elements ();
            var moving = new Gee.ArrayList<Element> ();
            foreach (var e in list) if (sel ().contains (e)) moving.add (e);
            if (moving.size == 0) return;
            edit (_("Arrange"), () => {
                if (how == 2 || how == -2) {
                    foreach (var e in moving) list.remove (e);
                    if (how == 2) list.add_all (moving);
                    else for (int i = moving.size - 1; i >= 0; i--) list.insert (0, moving[i]);
                } else if (how == 1) {
                    for (int i = list.size - 2; i >= 0; i--) {
                        if (moving.contains (list[i]) && !moving.contains (list[i + 1])) {
                            var t = list[i];
                            list[i] = list[i + 1];
                            list[i + 1] = t;
                        }
                    }
                } else {
                    for (int i = 1; i < list.size; i++) {
                        if (moving.contains (list[i]) && !moving.contains (list[i - 1])) {
                            var t = list[i];
                            list[i] = list[i - 1];
                            list[i - 1] = t;
                        }
                    }
                }
            });
        }

        private void align_objects (int how) {
            var items = sel ();
            if (items.size == 0) return;
            double x1 = double.MAX, y1 = double.MAX, x2 = -double.MAX, y2 = -double.MAX;
            if (items.size == 1) {
                x1 = 0;
                y1 = 0;
                x2 = doc.pres.width;
                y2 = doc.pres.height;
            } else {
                foreach (var e in items) {
                    double bx, by, bw, bh;
                    e.bounds (out bx, out by, out bw, out bh);
                    x1 = double.min (x1, bx);
                    y1 = double.min (y1, by);
                    x2 = double.max (x2, bx + bw);
                    y2 = double.max (y2, by + bh);
                }
            }
            edit (_("Align"), () => {
                foreach (var e in items) {
                    if (e.locked) continue;
                    double bx, by, bw, bh;
                    e.bounds (out bx, out by, out bw, out bh);
                    e.inherit_geometry = false;
                    switch (how) {
                        case 0: e.move_by (x1 - bx, 0); break;
                        case 1: e.move_by ((x1 + x2) / 2 - (bx + bw / 2), 0); break;
                        case 2: e.move_by (x2 - (bx + bw), 0); break;
                        case 3: e.move_by (0, y1 - by); break;
                        case 4: e.move_by (0, (y1 + y2) / 2 - (by + bh / 2)); break;
                        default: e.move_by (0, y2 - (by + bh)); break;
                    }
                }
            });
        }

        private void distribute (bool horizontal) {
            var items = new Gee.ArrayList<Element> ();
            items.add_all (sel ());
            if (items.size < 3) return;
            items.sort ((a, b) => {
                double ax, ay, aw, ah, bx, by, bw, bh;
                a.bounds (out ax, out ay, out aw, out ah);
                b.bounds (out bx, out by, out bw, out bh);
                double ka = horizontal ? ax : ay, kb = horizontal ? bx : by;
                return ka < kb ? -1 : (ka > kb ? 1 : 0);
            });
            double total = 0, start = 0, end = 0;
            for (int i = 0; i < items.size; i++) {
                double bx, by, bw, bh;
                items[i].bounds (out bx, out by, out bw, out bh);
                total += horizontal ? bw : bh;
                if (i == 0) start = horizontal ? bx : by;
                if (i == items.size - 1) end = horizontal ? bx + bw : by + bh;
            }
            double gap = (end - start - total) / (items.size - 1);
            edit (_("Distribute"), () => {
                double pos = start;
                foreach (var e in items) {
                    double bx, by, bw, bh;
                    e.bounds (out bx, out by, out bw, out bh);
                    e.inherit_geometry = false;
                    if (horizontal) e.move_by (pos - bx, 0);
                    else e.move_by (0, pos - by);
                    pos += (horizontal ? bw : bh) + gap;
                }
            });
        }

        private void group_selection () {
            if (sel ().size < 2) return;
            var list = canvas.elements ();
            var members = new Gee.ArrayList<Element> ();
            foreach (var e in list) if (sel ().contains (e)) members.add (e);
            var g = new GroupElement ();
            edit (_("Group"), () => {
                int at = list.index_of (members[members.size - 1]);
                foreach (var e in members) {
                    e.placeholder = PlaceholderKind.NONE;
                    e.inherit_geometry = false;
                    g.children.add (e);
                }
                g.fit ();
                doc.pres.assign_ids (g);
                g.id = doc.pres.new_id ();
                list.insert (at + 1, g);
                foreach (var e in members) list.remove (e);
            });
            canvas.select (g);
        }

        private void ungroup_selection () {
            var groups = new Gee.ArrayList<GroupElement> ();
            foreach (var e in sel ()) if (e is GroupElement) groups.add ((GroupElement) e);
            if (groups.size == 0) return;
            var freed = new Gee.ArrayList<Element> ();
            edit (_("Ungroup"), () => {
                var list = canvas.elements ();
                foreach (var g in groups) {
                    int at = list.index_of (g);
                    list.remove (g);
                    foreach (var c in g.children) {
                        list.insert (at++, c);
                        freed.add (c);
                    }
                    if (canvas.slide != null) canvas.slide.remove_animations_for (g.id);
                }
            });
            canvas.selection.clear ();
            canvas.selection.add_all (freed);
            canvas.selection_changed ();
            canvas.queue_draw ();
        }

        private void table_op (int op) {
            var t = sel ().size == 1 ? sel ()[0] as TableElement : null;
            if (t == null) return;
            canvas.commit_edit ();
            int r1 = canvas.cell_r1 >= 0 ? int.min (canvas.cell_r1, canvas.cell_r2) : 0;
            int r2 = canvas.cell_r1 >= 0 ? int.max (canvas.cell_r1, canvas.cell_r2) : 0;
            int c1 = canvas.cell_r1 >= 0 ? int.min (canvas.cell_c1, canvas.cell_c2) : 0;
            int c2 = canvas.cell_r1 >= 0 ? int.max (canvas.cell_c1, canvas.cell_c2) : 0;
            edit (_("Edit Table"), () => {
                switch (op) {
                    case 0: t.insert_row (r1); break;
                    case 1: t.insert_row (r2 + 1); break;
                    case 2: t.delete_row (r1); break;
                    case 3: t.insert_col (c1); t.scale_into (t.x, t.y, t.w * (t.cols - 1) / t.cols, t.h); break;
                    case 4: t.insert_col (c2 + 1); t.scale_into (t.x, t.y, t.w * (t.cols - 1) / t.cols, t.h); break;
                    case 5: t.delete_col (c1); break;
                    case 6: if (r2 > r1 || c2 > c1) t.merge (r1, c1, r2, c2); break;
                    case 7: t.split (r1, c1); break;
                    default:
                        double avg = t.h / t.rows;
                        for (int i = 0; i < t.rows; i++) t.row_heights[i] = avg;
                        t.sync_size ();
                        break;
                }
            });
            canvas.cell_r1 = -1;
            inspector.rebuild ();
        }

        public void apply_theme (ThemePreset preset) {
            canvas.commit_edit ();
            edit (_("Change Theme"), () => Factory.apply_theme (doc.pres, preset));
            sidebar.thumbs.clear ();
            if (view_mode == ViewMode.MASTER) sidebar.load_masters (doc.pres, canvas.master, canvas.layout);
            else sidebar.load (doc.pres, doc.current_slide);
            if (view_mode == ViewMode.SORTER) sorter.load (doc.pres, doc.current_slide);
            inspector.rebuild ();
        }

        public void open_find (bool replace) {
            if (doc == null) return;
            popup_anchored (new FindPopover (this, replace), find_bubble);
        }

        public void reveal_spot (TextSpot spot) {
            if (view_mode != ViewMode.NORMAL) set_view (ViewMode.NORMAL);
            if (spot.slide != doc.current_slide) go_to_slide (spot.slide);
            if (spot.notes) {
                notes_revealer.reveal_child = true;
                TextIter a, b;
                notes_view.buffer.get_iter_at_offset (out a, spot.start);
                notes_view.buffer.get_iter_at_offset (out b, spot.start + spot.length);
                notes_view.buffer.select_range (a, b);
                notes_view.scroll_to_iter (a, 0.1, false, 0, 0);
                return;
            }
            var e = doc.slide.find (spot.element);
            if (e == null) return;
            var top = e;
            foreach (var x in doc.slide.elements) if (x == e || (x is GroupElement && ((GroupElement) x).children.contains (e))) top = x;
            if (top is GroupElement) {
                canvas.select (top);
                return;
            }
            canvas.select (e);
            canvas.begin_edit (e, spot.row, spot.col, -1, -1);
            Idle.add (() => {
                if (canvas.editor != null) canvas.editor.select_offsets (spot.start, spot.start + spot.length);
                return Source.REMOVE;
            });
        }

        public bool replace_spot (TextSpot spot, string replacement) {
            if (canvas.editor != null && !spot.notes) {
                TextIter a, b;
                if (canvas.editor.buffer.get_selection_bounds (out a, out b)) {
                    canvas.editor.buffer.delete (ref a, ref b);
                    canvas.editor.buffer.insert (ref a, replacement, -1);
                    return true;
                }
            }
            canvas.commit_edit ();
            edit (_("Replace"), () => SpotEdit.replace (doc.pres, spot, replacement));
            if (spot.notes) load_notes ();
            return true;
        }

        private Presentation clip_deck (Gee.List<Slide> slides) {
            var p = new Presentation ();
            p.width = doc.pres.width;
            p.height = doc.pres.height;
            foreach (var m in doc.pres.masters) p.masters.add (m.clone ());
            foreach (var s in slides) p.slides.add (s.clone ());
            return p;
        }

        private void copy_elements () {
            if (sel ().size == 0) return;
            canvas.commit_edit ();
            element_clip.clear ();
            foreach (var e in sel ()) element_clip.add (e.clone ());
            var s = new Slide ();
            s.layout_id = canvas.slide != null ? canvas.slide.layout_id : "";
            foreach (var e in element_clip) s.elements.add (e.clone ());
            var list = new Gee.ArrayList<Slide> ();
            list.add (s);
            var deck = clip_deck (list);
            var providers = new Gee.ArrayList<Gdk.ContentProvider> ();
            try {
                var bytes = new Bytes (Document.serialize (deck, FileKind.PPTX));
                providers.add (new Gdk.ContentProvider.for_bytes (CLIP_MIME, bytes));
            } catch (Error e) {
                warning ("copy: %s", e.message);
            }
            var text = new StringBuilder ();
            foreach (var e in element_clip) {
                var b = e.text_body ();
                if (b != null && !b.is_empty ()) {
                    if (text.len > 0) text.append ("\n");
                    text.append (b.plain_text ().replace ("\v", "\n"));
                }
            }
            if (text.len > 0) providers.add (new Gdk.ContentProvider.for_value (text.str));
            var png = render_selection_png ();
            if (png != null) providers.add (new Gdk.ContentProvider.for_bytes ("image/png", png));
            get_clipboard ().set_content (new Gdk.ContentProvider.union (providers.to_array ()));
        }

        private Bytes? render_selection_png () {
            double x1 = double.MAX, y1 = double.MAX, x2 = -double.MAX, y2 = -double.MAX;
            foreach (var e in sel ()) {
                double bx, by, bw, bh;
                e.bounds (out bx, out by, out bw, out bh);
                x1 = double.min (x1, bx - e.shadow.distance - e.shadow.blur);
                y1 = double.min (y1, by - e.shadow.distance - e.shadow.blur);
                x2 = double.max (x2, bx + bw + e.shadow.distance + e.shadow.blur);
                y2 = double.max (y2, by + bh + e.shadow.distance + e.shadow.blur);
            }
            double sc = 2;
            int w = (int) Math.ceil ((x2 - x1) * sc), h = (int) Math.ceil ((y2 - y1) * sc);
            if (w <= 0 || h <= 0 || w > 8000 || h > 8000) return null;
            var surf = new Cairo.ImageSurface (Cairo.Format.ARGB32, w, h);
            var cr = new Cairo.Context (surf);
            cr.scale (sc, sc);
            cr.translate (-x1, -y1);
            var r = new Renderer ();
            var ctx = canvas.context ();
            foreach (var e in canvas.elements ()) if (sel ().contains (e)) r.draw_element (cr, ctx, e, false);
            surf.flush ();
            var pb = Exporter.to_pixbuf (surf);
            try {
                uint8[] buf;
                pb.save_to_buffer (out buf, "png");
                return new Bytes (buf);
            } catch (Error e) {
                return null;
            }
        }

        private void insert_elements (Gee.List<Element> items, bool match_style) {
            var added = new Gee.ArrayList<Element> ();
            edit (_("Paste"), () => {
                foreach (var e in items) {
                    var c = e.clone ();
                    doc.pres.assign_ids (c);
                    c.placeholder = PlaceholderKind.NONE;
                    c.inherit_geometry = false;
                    var sh = c as ShapeElement;
                    if (sh != null && sh.text != null && e.placeholder != PlaceholderKind.NONE) {
                        sh.text_box = true;
                        sh.text.anchor_set = true;
                    }
                    if (match_style && c.text_body () != null) c.text_body ().apply_to_runs ((r) => {
                        string t = r.text;
                        string f = r.field;
                        r.copy_format (new TextRun ());
                        r.text = t;
                        r.field = f;
                    });
                    bool clash = false;
                    foreach (var o in canvas.elements ()) if (Math.fabs (o.x - c.x) < 0.5 && Math.fabs (o.y - c.y) < 0.5) clash = true;
                    if (clash) c.move_by (18, 18);
                    canvas.elements ().add (c);
                    added.add (c);
                }
            });
            canvas.selection.clear ();
            canvas.selection.add_all (added);
            canvas.selection_changed ();
            canvas.queue_draw ();
        }

        private async void update_linked_charts () {
            var targets = new Gee.ArrayList<ChartElement> ();
            var specs = new Gee.ArrayList<Singularity.Charts.ChartSpec> ();
            int failed = 0;
            string last_error = "";
            var all = new Gee.ArrayList<Element> ();
            foreach (var s in doc.pres.slides) all.add_all (s.elements);
            foreach (var e in all) {
                var ch = e as ChartElement;
                if (ch == null || ch.link == "") continue;
                string[] parts = ch.link.split ("\t");
                if (parts.length < 3) continue;
                try {
                    var reply = yield Capabilities.call (Contracts.SPREADSHEET, "ChartXml", new Variant ("(sss)", parts[0], parts[1], parts[2]), new VariantType ("(s)"));
                    var spec = Singularity.Charts.DrawingML.read_chart (reply.get_child_value (0).get_string ());
                    if (spec == null) throw new IOError.INVALID_DATA (_("The chart could not be read"));
                    targets.add (ch);
                    specs.add (spec);
                } catch (Error e) {
                    failed++;
                    if (e is DBusError.SERVICE_UNKNOWN || e is IOError.NOT_SUPPORTED) {
                        last_error = _("Spreadsheet is not available");
                    } else {
                        DBusError.strip_remote_error (e);
                        last_error = e.message;
                    }
                }
            }
            if (targets.size > 0) {
                ChartElement? reselect = null;
                edit (_("Update Linked Charts"), () => {
                    for (int i = 0; i < targets.size; i++) {
                        var old = targets[i];
                        var fresh = ChartBridge.from_spec (specs[i]);
                        fresh.id = old.id;
                        fresh.name = old.name;
                        fresh.description = old.description;
                        fresh.link = old.link;
                        fresh.set_geometry (old.x, old.y, old.w, old.h);
                        foreach (var s in doc.pres.slides) {
                            int at = s.elements.index_of (old);
                            if (at >= 0) s.elements[at] = fresh;
                        }
                        if (canvas.selection.contains (old)) reselect = fresh;
                    }
                });
                if (reselect != null) canvas.select (reselect);
            }
            int updated = targets.size;
            if (updated + failed == 0) add_toast (new Toast (_("This presentation has no linked charts")));
            else if (failed == 0) add_toast (new Toast (ngettext ("%d linked chart updated", "%d linked charts updated", updated).printf (updated)));
            else add_toast (new Toast (_("%d updated, %d could not be updated: %s").printf (updated, failed, last_error)));
        }

        private async void paste (bool match_style) {
            if (doc == null) return;
            canvas.commit_edit ();
            var cb = get_clipboard ();
            var formats = cb.get_formats ().union_deserialize_gtypes ();
            if (cb.is_local () && element_clip.size > 0 && formats.contain_mime_type (CLIP_MIME)) {
                insert_elements (element_clip, match_style);
                return;
            }
            try {
                if (formats.contain_mime_type (CHART_LINK_MIME)) {
                    string link_mime;
                    var link_stream = yield cb.read_async ({ CHART_LINK_MIME }, Priority.DEFAULT, null, out link_mime);
                    var link_mem = new MemoryOutputStream.resizable ();
                    yield link_mem.splice_async (link_stream, OutputStreamSpliceFlags.CLOSE_SOURCE | OutputStreamSpliceFlags.CLOSE_TARGET, Priority.DEFAULT, null);
                    uint8[] link_data = link_mem.steal_data ();
                    link_data.length = (int) link_mem.get_data_size ();
                    var link_text = new StringBuilder ();
                    link_text.append_len ((string) link_data, link_data.length);
                    string payload = link_text.str;
                    int nl = payload.index_of_char ('\n');
                    var spec = nl > 0 ? Singularity.Charts.DrawingML.read_chart (payload.substring (nl + 1)) : null;
                    if (spec != null) {
                        var p = doc.pres;
                        var ch = ChartBridge.from_spec (spec);
                        ch.link = payload.substring (0, nl);
                        var ph = empty_content_placeholder ();
                        if (ph != null) {
                            ch.set_geometry (ph.x, ph.y, ph.w, ph.h);
                            replace_placeholder (ph, ch, _("Paste"));
                            return;
                        }
                        ch.set_geometry (p.width * 0.15, p.height * 0.2, p.width * 0.7, p.height * 0.65);
                        add_element (ch, _("Paste"));
                        return;
                    }
                }
                if (formats.contain_mime_type (CLIP_MIME)) {
                    string out_mime;
                    var stream = yield cb.read_async ({ CLIP_MIME }, Priority.DEFAULT, null, out out_mime);
                    var mem = new MemoryOutputStream.resizable ();
                    yield mem.splice_async (stream, OutputStreamSpliceFlags.CLOSE_SOURCE | OutputStreamSpliceFlags.CLOSE_TARGET, Priority.DEFAULT, null);
                    uint8[] data = mem.steal_data ();
                    data.length = (int) mem.get_data_size ();
                    var p = Document.load_bytes (data, "clip.pptx");
                    if (p.slides.size > 0) {
                        insert_elements (p.slides[0].elements, match_style);
                        return;
                    }
                }
                if (formats.contain_gtype (typeof (Gdk.FileList))) {
                    var val = yield cb.read_value_async (typeof (Gdk.FileList), Priority.DEFAULT, null);
                    var files = (Gdk.FileList) val.get_boxed ();
                    bool any = false;
                    foreach (var f in files.get_files ()) {
                        string n = f.get_basename ().down ();
                        if (n.has_suffix (".png") || n.has_suffix (".jpg") || n.has_suffix (".jpeg") || n.has_suffix (".gif") || n.has_suffix (".svg") || n.has_suffix (".webp")) {
                            insert_image_file (f);
                            any = true;
                        }
                    }
                    if (any) return;
                }
                if (formats.contain_mime_type ("image/svg+xml")) {
                    string svg_mime;
                    var svg_stream = yield cb.read_async ({ "image/svg+xml" }, Priority.DEFAULT, null, out svg_mime);
                    var svg_mem = new MemoryOutputStream.resizable ();
                    yield svg_mem.splice_async (svg_stream, OutputStreamSpliceFlags.CLOSE_SOURCE | OutputStreamSpliceFlags.CLOSE_TARGET, Priority.DEFAULT, null);
                    uint8[] svg = svg_mem.steal_data ();
                    svg.length = (int) svg_mem.get_data_size ();
                    if (svg.length > 0) {
                        insert_image (new Bytes (svg), "image/svg+xml", _("Drawing"));
                        return;
                    }
                }
                if (formats.contain_gtype (typeof (Gdk.Texture)) && !formats.contain_mime_type ("text/plain")) {
                    var tex = yield cb.read_texture_async (null);
                    if (tex != null) {
                        insert_image (tex.save_to_png_bytes (), "image/png", _("Pasted Image"));
                        return;
                    }
                }
                string? text = yield cb.read_text_async (null);
                if (text != null && text.strip () != "") {
                    var p = doc.pres;
                    string t = text.replace ("\r", "").strip ();
                    var tb = Factory.text_box (p, p.width * 0.15, p.height * 0.3, p.width * 0.7, t);
                    add_element (tb, _("Paste"));
                    canvas.fit_text_box (tb);
                    return;
                }
                if (formats.contain_gtype (typeof (Gdk.Texture))) {
                    var tex = yield cb.read_texture_async (null);
                    if (tex != null) insert_image (tex.save_to_png_bytes (), "image/png", _("Pasted Image"));
                }
            } catch (Error e) {
                show_error (_("Could Not Paste"), e.message);
            }
        }

        private void copy_slides () {
            int[] idx = selected_slides ();
            slide_clip.clear ();
            foreach (int i in idx) slide_clip.add (doc.pres.slides[i].clone ());
            try {
                var bytes = new Bytes (Document.serialize (clip_deck (slide_clip), FileKind.PPTX));
                var providers = new Gdk.ContentProvider[] { new Gdk.ContentProvider.for_bytes (CLIP_MIME + "-deck", bytes) };
                get_clipboard ().set_content (new Gdk.ContentProvider.union (providers));
            } catch (Error e) {
                warning ("copy slides: %s", e.message);
            }
            add_toast (new Toast (ngettext ("%d slide copied", "%d slides copied", idx.length).printf (idx.length)));
        }

        private void paste_slides () {
            if (slide_clip.size == 0) return;
            int at = doc.current_slide + 1;
            edit (_("Paste Slides"), () => {
                int k = 0;
                foreach (var s in slide_clip) {
                    var c = s.duplicate ();
                    reassign_ids (c);
                    if (doc.pres.find_layout (c.layout_id) == null) {
                        var l = doc.pres.master.layout_of_kind (LayoutKind.TITLE_CONTENT) ?? doc.pres.master.layouts[0];
                        Factory.apply_layout (doc.pres, c, l);
                    }
                    doc.pres.slides.insert (at + k++, c);
                }
            });
            doc.current_slide = at;
            sidebar.load (doc.pres, at);
            if (view_mode == ViewMode.SORTER) sorter.load (doc.pres, at);
            show_current ();
        }

        private void end_preview () {
            if (preview_stage == null) return;
            preview_stage.slideshow.stop ();
            stage_overlay.remove_overlay (preview_stage);
            preview_stage = null;
        }

        private void start_preview (SlideShow sh) {
            end_preview ();
            preview_stage = new ShowStage (sh);
            preview_stage.interactive = false;
            preview_stage.can_target = true;
            stage_overlay.add_overlay (preview_stage);
            var stop_click = new GestureClick ();
            stop_click.pressed.connect (() => end_preview ());
            preview_stage.add_controller (stop_click);
            sh.finished.connect (() => Idle.add (() => {
                end_preview ();
                return Source.REMOVE;
            }));
        }

        public void canvas_preview_transition () {
            if (doc == null || doc.slide == null) return;
            canvas.commit_edit ();
            start_preview (new SlideShow.preview (doc.pres, doc.current_slide, true, 0));
        }

        public void canvas_preview_animations (int from) {
            if (doc == null || doc.slide == null || doc.slide.animations.size == 0) return;
            canvas.commit_edit ();
            start_preview (new SlideShow.preview (doc.pres, doc.current_slide, false, from));
        }

        public void start_custom_show (string name) {
            if (doc == null) return;
            var cs = doc.pres.find_custom_show (name);
            if (cs == null || cs.slides.size == 0) return;
            int first = doc.pres.index_of_uid (cs.slides[0]);
            start_show (int.max (first, 0), false, false, name);
        }

        private bool coach_mode = false;

        public void start_show (int from, bool presenter, bool rehearse, string custom = "", bool narrate = false, bool coach = false) {
            if (doc == null || doc.pres.slides.size == 0 || slideshow != null) return;
            canvas.commit_edit ();
            end_preview ();
            slideshow = new SlideShow (doc.pres, from.clamp (0, doc.pres.slides.size - 1), true, custom);
            slideshow.rehearse = rehearse;
            slideshow.caption_command = app.get_string ("caption-command", "");
            coach_mode = coach;
            if (narrate || coach) begin_narration ();
            if (doc.pres.show_kind == 2) presenter = false;
            Rgba lc, pc;
            if (Rgba.parse_hex (app.get_string ("laser-color", "#ff3b30"), out lc)) slideshow.laser_color = lc;
            if (Rgba.parse_hex (app.get_string ("pen-color", "#ffcc00"), out pc)) slideshow.pen_color = pc;
            if (rehearse) slideshow.pres.use_timings = slideshow.pres.use_timings;
            slideshow.finished.connect (() => Idle.add (() => {
                end_show ();
                return Source.REMOVE;
            }));
            slideshow.open_link.connect ((uri) => {
                string target = uri;
                if (!target.contains ("://") && doc.path != null && !Path.is_absolute (target)) target = Path.build_filename (Path.get_dirname (doc.path), target);
                if (!target.contains ("://")) target = File.new_for_path (target).get_uri ();
                var launcher = new Gtk.UriLauncher (target);
                launcher.launch.begin (show_window, null);
            });
            slideshow.run_program.connect ((path) => {
                var launcher = new Gtk.FileLauncher (File.new_for_path (path));
                launcher.launch.begin (show_window, null);
            });
            var display = get_display ();
            var monitors = display.get_monitors ();
            uint n = monitors.get_n_items ();
            Gdk.Monitor? here = null;
            var surface = get_surface ();
            if (surface != null) here = display.get_monitor_at_surface (surface);
            Gdk.Monitor? other = null;
            for (uint i = 0; i < n; i++) {
                var m = (Gdk.Monitor) monitors.get_item (i);
                if (m != here) {
                    other = m;
                    break;
                }
            }
            bool want_presenter = presenter || rehearse || app.get_bool ("presenter-view", true) && other != null && doc.pres.show_kind != 2;
            bool in_window = app.get_bool ("presenter-in-window", false) || other == null;
            if (doc.pres.show_kind == 1 && !want_presenter) {
                show_window = new ShowWindow (app, slideshow);
                show_window.set_default_size (960, 540);
                show_window.decorated = true;
                show_window.present ();
                slideshow.total.start ();
                return;
            }
            show_window = new ShowWindow (app, slideshow);
            if (want_presenter) {
                presenter_window = new PresenterWindow (app, slideshow);
                if (other != null && !in_window) {
                    show_window.set_default_size (other.geometry.width, other.geometry.height);
                    show_window.fullscreen_on_monitor (other);
                    show_window.present ();
                    presenter_window.present ();
                    if (here != null) presenter_window.maximize ();
                } else {
                    show_window.set_default_size (960, 540);
                    show_window.decorated = true;
                    show_window.present ();
                    presenter_window.present ();
                }
            } else {
                if (here != null) {
                    var geo = here.geometry;
                    show_window.set_default_size (geo.width, geo.height);
                    show_window.fullscreen_on_monitor (here);
                } else {
                    show_window.fullscreen ();
                }
                show_window.present ();
            }
            slideshow.total.start ();
        }

        public void end_show () {
            if (slideshow == null) return;
            var s = slideshow;
            slideshow = null;
            s.stop ();
            if (show_window != null) {
                show_window.destroy ();
                show_window = null;
            }
            if (presenter_window != null) {
                presenter_window.destroy ();
                presenter_window = null;
            }
            go_to_slide (s.slide_index);
            present ();
            bool coached = coach_mode;
            if (s.rehearse) s.finish_rehearsal ();
            finish_narration (s);
            if (s.rehearse && !coached) Dialogs.keep_timings (this, s);
            Dialogs.keep_ink (this, s);
        }

        private void install_more_actions () {
            act ("insert-shapes", () => Galleries.shapes (this, _("Insert Shape"), (name) => insert_preset (name)));
            var preset = new SimpleAction ("insert-preset", VariantType.STRING);
            preset.activate.connect ((v) => {
                if (doc != null) insert_preset (v.get_string ());
            });
            add_action (preset);
            doc_actions += "insert-preset";
            act ("insert-icons", () => Galleries.icons (this, (data, name) => insert_icon (data, name)));
            act ("insert-model", () => insert_model.begin ());
            act ("insert-stock", () => Galleries.stock (this, (data, mime, name) => insert_image (data, mime, name)));
            act ("insert-smartart", () => Galleries.smartart (this, (l) => insert_diagram (l)));
            act ("insert-video", () => insert_media.begin (true));
            act ("insert-audio", () => insert_media.begin (false));
            act ("record-audio", () => DeckDialogs.record_audio (this));
            act ("record-screen", () => DeckDialogs.record_screen (this));
            act ("insert-zoom-summary", () => DeckDialogs.choose_zoom (this, ZoomKind.SUMMARY));
            act ("insert-zoom-section", () => DeckDialogs.choose_zoom (this, ZoomKind.SECTION));
            act ("insert-zoom-slide", () => DeckDialogs.choose_zoom (this, ZoomKind.SLIDE));
            act ("convert-freeform", () => convert_freeform ());
            act ("ink-to-shape", () => ink_to_shape ());
            act ("diagram-to-shapes", () => diagram_to_shapes ());
            act ("merge-union", () => merge_shapes (MergeMode.UNION));
            act ("merge-combine", () => merge_shapes (MergeMode.COMBINE));
            act ("merge-fragment", () => merge_shapes (MergeMode.FRAGMENT));
            act ("merge-intersect", () => merge_shapes (MergeMode.INTERSECT));
            act ("merge-subtract", () => merge_shapes (MergeMode.SUBTRACT));
            act ("draw-pen", () => canvas.set_tool (CanvasTool.INK_PEN));
            act ("draw-highlighter", () => canvas.set_tool (CanvasTool.INK_HIGHLIGHTER));
            act ("draw-eraser", () => canvas.set_tool (CanvasTool.INK_ERASER));
            act ("draw-freeform", () => canvas.set_tool (CanvasTool.FREEFORM));
            act ("draw-scribble", () => canvas.set_tool (CanvasTool.SCRIBBLE));
            act ("draw-select", () => canvas.set_tool (CanvasTool.SELECT));
            act ("format-painter", () => {
                if (sel ().size != 1) {
                    add_toast (new Toast (_("Select an object to copy its format")));
                    return;
                }
                canvas.painter = FormatClip.from (sel ()[0]);
                canvas.painter_sticky = false;
                canvas.set_tool (CanvasTool.PAINTER);
            });
            toggle_act ("show-ruler", false, (v) => {
                doc.pres.show_ruler = v;
                canvas.queue_draw ();
            });
            toggle_act ("show-grid", false, (v) => {
                doc.pres.show_grid = v;
                canvas.queue_draw ();
            });
            toggle_act ("snap-grid", false, (v) => doc.pres.snap_to_grid = v);
            toggle_act ("show-guides", false, (v) => {
                doc.pres.show_guides = v;
                if (v && doc.pres.guides_x.size == 0 && doc.pres.guides_y.size == 0) {
                    doc.pres.guides_x.add (doc.pres.width / 2);
                    doc.pres.guides_y.add (doc.pres.height / 2);
                }
                canvas.queue_draw ();
            });
            act ("add-guide-v", () => {
                doc.pres.show_guides = true;
                doc.pres.guides_x.add (doc.pres.width / 2);
                sync_view_toggles ();
                canvas.queue_draw ();
            });
            act ("add-guide-h", () => {
                doc.pres.show_guides = true;
                doc.pres.guides_y.add (doc.pres.height / 2);
                sync_view_toggles ();
                canvas.queue_draw ();
            });
            act ("grid-settings", () => DeckDialogs.grid_settings (this));
            act ("add-section", () => add_section ());
            act ("rename-section", () => rename_section ());
            act ("remove-section", () => remove_section (false));
            act ("remove-section-slides", () => remove_section (true));
            act ("section-up", () => move_section (-1));
            act ("section-down", () => move_section (1));
            act ("custom-shows", () => DeckDialogs.custom_shows (this));
            act ("setup-show", () => DeckDialogs.setup_show (this));
            act ("record-show", () => start_show (doc.current_slide, true, true, "", true));
            act ("record-show-start", () => start_show (0, true, true, "", true));
            act ("record-show-camera", () => {
                camera_mode = true;
                start_show (doc.current_slide, true, true, "", true);
            });
            act ("clear-narration", () => clear_narration (false));
            act ("clear-narration-all", () => clear_narration (true));
            act ("new-comment", () => new_comment ());
            act ("comments", () => toggle_panel ("comments"));
            act ("check-accessibility", () => DeckDialogs.accessibility (this));
            act ("outline", () => toggle_panel ("outline"));
            act ("slide-size-custom", () => DeckDialogs.slide_size (this));
            act ("new-master", () => new_master ());
            act ("new-layout", () => new_layout ());
            act ("duplicate-layout", () => duplicate_layout ());
            act ("delete-layout", () => delete_layout ());
            act ("import-theme", () => import_theme.begin ());
            act ("theme-variants", () => DeckDialogs.variants (this));
            act ("embed-fonts", () => DeckDialogs.embed_fonts (this));
            act ("protect", () => DeckDialogs.protect (this));
            act ("version-history", () => DeckDialogs.versions (this));
            act ("save-template", () => {
                DeckDialogs.ask_text (this, _("Save as Template"), _("Template Name"), doc.pres.properties.title != "" ? doc.pres.properties.title : _("My Template"), (name) => {
                    try {
                        PersonalTemplates.save (doc.pres, name);
                        add_toast (new Toast (_("Saved to your templates")));
                    } catch (Error e) {
                        show_error (_("Could Not Save Template"), e.message);
                    }
                });
            });
            act ("thesaurus", () => LanguageTools.thesaurus (this));
            act ("designer", () => DeckDialogs.designer (this));
            act ("live", () => DeckDialogs.live (this));
            act ("translate", () => LanguageTools.translate (this));
            var ph = new SimpleAction ("insert-placeholder", VariantType.STRING);
            ph.activate.connect ((v) => {
                if (doc != null) insert_placeholder (v.get_string ());
            });
            add_action (ph);
            doc_actions += "insert-placeholder";
            act ("preview-transition", () => canvas_preview_transition ());
            act ("preview-animations", () => canvas_preview_animations (0));
            canvas.selection_changed.connect (() => {
                if (right_revealer.reveal_child && right_stack.visible_child_name == "comments") comments_panel.rebuild ();
            });
        }

        public void sync_view_toggles () {
            if (doc == null) return;
            var p = doc.pres;
            string[] names = { "show-ruler", "show-grid", "snap-grid", "show-guides" };
            bool[] vals = { p.show_ruler, p.show_grid, p.snap_to_grid, p.show_guides };
            for (int i = 0; i < names.length; i++) {
                var a = lookup_action (names[i]) as SimpleAction;
                if (a != null) a.set_state (new Variant.boolean (vals[i]));
            }
        }

        public void resize_slides (double w, double h) {
            if (doc == null || (Math.fabs (w - doc.pres.width) < 0.5 && Math.fabs (h - doc.pres.height) < 0.5)) return;
            canvas.commit_edit ();
            edit (_("Slide Size"), () => SlideSize.resize (doc.pres, w, h));
            on_doc_replaced (doc.current_slide);
        }

        public void apply_theme_colors (Theme t) {
            edit (_("Theme Variant"), () => {
                foreach (var m in doc.pres.masters) {
                    string major = m.theme.major_font, minor = m.theme.minor_font;
                    m.theme = t.clone ();
                    m.theme.major_font = major;
                    m.theme.minor_font = minor;
                }
            });
            refresh_thumbnails ();
            canvas.queue_draw ();
            inspector.rebuild ();
        }

        public void apply_design (Slide idea) {
            var s = doc.slide;
            if (s == null) return;
            canvas.commit_edit ();
            edit (_("Design Idea"), () => {
                s.elements.clear ();
                foreach (var e in idea.elements) s.elements.add (e.clone ());
            });
            show_current ();
            refresh_thumbnails ();
        }

        public void reveal_object (int slide, Element? e) {
            if (doc == null || slide < 0 || slide >= doc.pres.slides.size) return;
            if (view_mode != ViewMode.NORMAL) set_view (ViewMode.NORMAL);
            go_to_slide (slide);
            if (e != null && doc.pres.slides[slide].elements.contains (e)) canvas.select (e);
        }

        public void apply_outline (string text) {
            canvas.commit_edit ();
            edit (_("Edit Outline"), () => DeckOutline.apply (doc.pres, text), "outline");
            doc.current_slide = doc.current_slide.clamp (0, doc.pres.slides.size - 1);
            sidebar.load (doc.pres, doc.current_slide);
            show_current ();
        }

        private bool camera_mode = false;
        private CameraRecorder? camera = null;
        private Gee.HashMap<int, Bytes> cameos = new Gee.HashMap<int, Bytes> ();
        private AudioRecorder? narrator = null;
        private int narration_slide = -1;
        private Gee.HashMap<int, Bytes> narrations = new Gee.HashMap<int, Bytes> ();
        private string narration_mime = "audio/ogg";

        private void begin_narration () {
            narrations.clear ();
            cameos.clear ();
            if (camera_mode) {
                camera_mode = false;
                if (CameraRecorder.available ()) {
                    camera = new CameraRecorder ();
                    narration_slide = slideshow.slide_index;
                    if (camera.start (true)) {
                        slideshow.slide_changed.connect (on_camera_slide);
                        return;
                    }
                    add_toast (new Toast (_("Recording without camera: %s").printf (camera.error_message)));
                    camera = null;
                } else {
                    add_toast (new Toast (_("No camera was found, recording narration only")));
                }
            }
            if (!AudioRecorder.available ()) {
                add_toast (new Toast (_("Recording timings only: no microphone support is installed")));
                return;
            }
            narrator = new AudioRecorder ();
            narrator.speech_wav = coach_mode;
            narration_slide = slideshow.slide_index;
            if (!narrator.start ()) {
                add_toast (new Toast (_("Recording timings only: %s").printf (narrator.error_message)));
                narrator = null;
                return;
            }
            slideshow.slide_changed.connect (on_narration_slide);
        }

        private void on_camera_slide () {
            if (camera == null || slideshow == null) return;
            var clip = camera.stop ();
            if (clip != null && narration_slide >= 0) cameos[narration_slide] = clip;
            narration_slide = slideshow.slide_index;
            camera.start (true);
        }

        private void finish_camera () {
            if (camera == null) return;
            var clip = camera.stop ();
            if (clip != null && narration_slide >= 0) cameos[narration_slide] = clip;
            camera = null;
            if (cameos.size == 0) return;
            var p = doc.pres;
            edit (_("Record Slide Show"), () => {
                foreach (var e in cameos.entries) {
                    if (e.key < 0 || e.key >= p.slides.size) continue;
                    var slide = p.slides[e.key];
                    remove_narration (slide);
                    var m = new MediaElement ();
                    m.data = e.value;
                    m.mime = "video/webm";
                    m.is_video = true;
                    m.name = _("Narration");
                    m.start = MediaStart.AUTOMATIC;
                    double w = p.width * 0.22, h = w * 9 / 16;
                    m.set_geometry (p.width - w - 12, p.height - h - 12, w, h);
                    p.assign_ids (m);
                    slide.elements.add (m);
                    MediaProbe.fill.begin (m);
                }
            });
            add_toast (new Toast (ngettext ("Camera recording added to %d slide", "Camera recording added to %d slides", cameos.size).printf (cameos.size)));
            cameos.clear ();
            refresh_thumbnails ();
        }

        private void on_narration_slide () {
            if (narrator == null || slideshow == null) return;
            var clip = narrator.stop ();
            if (clip != null && narration_slide >= 0) narrations[narration_slide] = clip;
            narration_mime = narrator.mime;
            narration_slide = slideshow.slide_index;
            narrator.start ();
        }

        private void finish_narration (SlideShow s) {
            if (camera != null) {
                finish_camera ();
                return;
            }
            if (narrator == null) return;
            var clip = narrator.stop ();
            if (clip != null && narration_slide >= 0) narrations[narration_slide] = clip;
            narration_mime = narrator.mime;
            narrator = null;
            if (coach_mode) {
                coach_mode = false;
                run_coach.begin (s);
                return;
            }
            if (narrations.size == 0) return;
            var p = doc.pres;
            edit (_("Record Narration"), () => {
                foreach (var e in narrations.entries) {
                    if (e.key < 0 || e.key >= p.slides.size) continue;
                    var slide = p.slides[e.key];
                    remove_narration (slide);
                    var m = new MediaElement ();
                    m.data = e.value;
                    m.mime = narration_mime;
                    m.is_video = false;
                    m.name = _("Narration");
                    m.start = MediaStart.AUTOMATIC;
                    m.hide_when_stopped = true;
                    m.set_geometry (p.width - 56, p.height - 56, 40, 40);
                    p.assign_ids (m);
                    slide.elements.add (m);
                    MediaProbe.fill.begin (m);
                }
            });
            add_toast (new Toast (ngettext ("Narration recorded on %d slide", "Narration recorded on %d slides", narrations.size).printf (narrations.size)));
            narrations.clear ();
            refresh_thumbnails ();
        }

        private async void run_coach (SlideShow s) {
            var order = new Gee.ArrayList<int> ();
            var secs = new Gee.ArrayList<double?> ();
            var texts = new Gee.ArrayList<string> ();
            var clips = new Gee.TreeMap<int, Bytes> ();
            foreach (var e in narrations.entries) clips[e.key] = e.value;
            narrations.clear ();
            if (clips.size == 0) {
                add_toast (new Toast (_("Nothing was recorded, so no rehearsal report is available")));
                return;
            }
            if (!SpeechService.present ()) {
                show_error (_("Speech Recognition Unavailable"), _("Turn on dictation in Settings to get a rehearsal report."));
                return;
            }
            var progress = new Toast (_("Preparing the rehearsal report"));
            add_toast (progress);
            foreach (var e in clips.entries) {
                string t = "";
                try {
                    t = yield SpeechService.transcribe (e.value);
                } catch (Error err) {
                    warning ("coach: %s", err.message);
                }
                order.add (e.key);
                secs.add (s.rehearsed.has_key (e.key) ? s.rehearsed[e.key] : 0);
                texts.add (t);
            }
            var report = SpeechCoach.analyse (doc.pres, order, secs, texts);
            DeckDialogs.coach_report (this, report);
        }

        private static void remove_narration (Slide slide) {
            for (int i = slide.elements.size - 1; i >= 0; i--) {
                var m = slide.elements[i] as MediaElement;
                if (m != null && m.name == _("Narration") && (m.hide_when_stopped || m.is_video)) {
                    slide.remove_animations_for (m.id);
                    slide.elements.remove_at (i);
                }
            }
        }

        private void clear_narration (bool all) {
            edit (_("Clear Narration"), () => {
                if (all) foreach (var s in doc.pres.slides) remove_narration (s);
                else if (doc.slide != null) remove_narration (doc.slide);
            });
            refresh_thumbnails ();
            canvas.queue_draw ();
        }

        private void convert_freeform () {
            var targets = new Gee.ArrayList<ShapeElement> ();
            foreach (var e in sel ()) {
                var s = e as ShapeElement;
                if (s != null && s.shape != ShapeKind.CUSTOM && s.shape != ShapeKind.LINE) targets.add (s);
            }
            if (targets.size == 0) return;
            var result = new Gee.ArrayList<ShapeElement> ();
            edit (_("Convert to Freeform"), () => {
                var list = canvas.elements ();
                foreach (var s in targets) {
                    var f = ShapeOps.to_freeform (s);
                    if (f == null) continue;
                    f.placeholder = s.placeholder;
                    f.placeholder_idx = s.placeholder_idx;
                    int i = list.index_of (s);
                    if (i >= 0) list[i] = f;
                    result.add (f);
                }
            });
            if (result.size > 0) {
                canvas.select (result[0]);
                canvas.points_mode = true;
                canvas.queue_draw ();
                inspector.rebuild ();
            }
        }

        private void ink_to_shape () {
            var inks = new Gee.ArrayList<InkElement> ();
            foreach (var e in sel ()) if (e is InkElement) inks.add ((InkElement) e);
            if (inks.size == 0) return;
            var made = new Gee.ArrayList<Element> ();
            edit (_("Convert Ink to Shape"), () => {
                var list = canvas.elements ();
                foreach (var ink in inks) {
                    int at = list.index_of (ink);
                    foreach (var st in ink.strokes) {
                        var poly = ShapeOps.simplify_stroke (st.pts, 1.2);
                        var ops = new Gee.ArrayList<PathOp> ();
                        foreach (var c in ShapeOps.smooth (poly)) ops.add (new PathOp (c.op, c.pts));
                        var style = new ShapeElement (ShapeKind.CUSTOM);
                        style.fill = new Fill.none ();
                        style.line.color = st.color;
                        style.line.width = st.width;
                        var s = ShapeOps.from_ops (ops, style);
                        if (s == null) continue;
                        s.name = _("Freeform");
                        doc.pres.assign_ids (s);
                        list.insert (at++, s);
                        made.add (s);
                    }
                    list.remove (ink);
                }
            });
            canvas.selection.clear ();
            canvas.selection.add_all (made);
            canvas.selection_changed ();
            canvas.queue_draw ();
        }

        private void diagram_to_shapes () {
            var d = sel ().size == 1 ? sel ()[0] as DiagramElement : null;
            if (d == null) return;
            var g = new GroupElement ();
            edit (_("Convert to Shapes"), () => {
                foreach (var e in d.build ()) {
                    doc.pres.assign_ids (e);
                    g.children.add (e);
                }
                g.fit ();
                doc.pres.assign_ids (g);
                g.name = d.display_name ();
                var list = canvas.elements ();
                int i = list.index_of (d);
                if (i >= 0) list[i] = g;
            });
            canvas.select (g);
        }

        private void merge_shapes (MergeMode mode) {
            var shapes = new Gee.ArrayList<ShapeElement> ();
            foreach (var e in sel ()) {
                var s = e as ShapeElement;
                if (s != null && s.shape != ShapeKind.LINE) shapes.add (s);
            }
            if (shapes.size < 2) {
                add_toast (new Toast (_("Select two or more shapes to merge")));
                return;
            }
            var result = ShapeOps.merge (shapes, mode);
            string[] names = { _("Union"), _("Combine"), _("Fragment"), _("Intersect"), _("Subtract") };
            edit (names[(int) mode], () => {
                var list = canvas.elements ();
                int at = list.size;
                foreach (var s in shapes) {
                    int k = list.index_of (s);
                    if (k >= 0) at = int.min (at, k);
                }
                foreach (var s in shapes) {
                    list.remove (s);
                    if (canvas.slide != null) canvas.slide.remove_animations_for (s.id);
                }
                at = at.clamp (0, list.size);
                foreach (var r in result) {
                    doc.pres.assign_ids (r);
                    list.insert (at++, r);
                }
            });
            canvas.selection.clear ();
            canvas.selection.add_all (result);
            canvas.selection_changed ();
            canvas.queue_draw ();
        }

        private void add_section () {
            int at = doc.current_slide;
            if (doc.pres.slides.size == 0) return;
            DeckDialogs.ask_text (this, _("Add Section"), _("Section Name"), _("Untitled Section"), (name) => {
                edit (_("Add Section"), () => {
                    var p = doc.pres;
                    if (!p.has_sections () && at > 0) p.slides[0].section = new SectionMark (_("Default Section"));
                    p.slides[at].section = new SectionMark (name);
                });
                sidebar.load (doc.pres, doc.current_slide);
            });
        }

        private void rename_section () {
            int st = doc.pres.section_start (doc.current_slide);
            if (st < 0) return;
            var mark = doc.pres.slides[st].section;
            DeckDialogs.ask_text (this, _("Rename Section"), _("Section Name"), mark.name, (name) => {
                edit (_("Rename Section"), () => mark.name = name);
                sidebar.load (doc.pres, doc.current_slide);
            });
        }

        private void remove_section (bool with_slides) {
            var p = doc.pres;
            int st = p.section_start (doc.current_slide);
            if (st < 0) return;
            int end = p.section_end (st);
            edit (with_slides ? _("Remove Section and Slides") : _("Remove Section"), () => {
                if (with_slides) {
                    for (int i = end - 1; i >= st; i--) p.slides.remove_at (i);
                    if (p.slides.size == 0) Factory.add_slide (p, p.master.layouts.size > 0 ? p.master.layouts[0] : null, 0);
                    doc.current_slide = int.min (st, p.slides.size - 1);
                    if (st < p.slides.size && st > 0 && p.slides[st].section == null && p.has_sections ()) {
                        int prev = p.section_start (st - 1);
                        if (prev < 0) p.slides[st].section = new SectionMark (_("Default Section"));
                    }
                } else {
                    p.slides[st].section = null;
                    if (st == 0 && p.has_sections ()) p.slides[0].section = new SectionMark (_("Default Section"));
                }
            });
            sidebar.load (p, doc.current_slide);
            show_current ();
        }

        private void move_section (int delta) {
            var p = doc.pres;
            int st = p.section_start (doc.current_slide);
            if (st < 0) return;
            int end = p.section_end (st);
            if (delta < 0 && st == 0) return;
            if (delta > 0 && end >= p.slides.size) return;
            int other = delta < 0 ? p.section_start (st - 1) : end;
            if (other < 0) return;
            int oend = p.section_end (other);
            edit (_("Move Section"), () => {
                var block = new Gee.ArrayList<Slide> ();
                for (int i = st; i < end; i++) block.add (p.slides[i]);
                for (int i = end - 1; i >= st; i--) p.slides.remove_at (i);
                int insert_at = delta < 0 ? other : oend - block.size;
                for (int k = 0; k < block.size; k++) p.slides.insert (insert_at + k, block[k]);
                doc.current_slide = insert_at;
            });
            sidebar.load (p, doc.current_slide);
            show_current ();
        }

        public void new_comment () {
            if (canvas.slide == null) return;
            var c = new Comment ();
            c.author = CommentsPanel.me ();
            c.initials = Comment.initials_of (c.author);
            c.date = Comment.now ();
            if (sel ().size > 0) {
                c.x = sel ()[0].x + sel ()[0].w;
                c.y = sel ()[0].y;
                c.anchor = sel ()[0].id;
            } else {
                c.x = 20;
                c.y = 20;
            }
            right_stack.visible_child_name = "comments";
            right_revealer.reveal_child = true;
            canvas.show_comments = true;
            canvas.queue_draw ();
            comments_panel.start_new (c);
        }

        private void insert_placeholder (string kind) {
            if (view_mode != ViewMode.MASTER || canvas.layout == null) {
                add_toast (new Toast (_("Open a layout in the slide master to add placeholders")));
                return;
            }
            var p = doc.pres;
            PlaceholderKind k;
            switch (kind) {
                case "title": k = PlaceholderKind.TITLE; break;
                case "text": k = PlaceholderKind.BODY; break;
                case "picture": k = PlaceholderKind.PICTURE; break;
                case "chart": k = PlaceholderKind.CHART; break;
                case "table": k = PlaceholderKind.TABLE; break;
                case "media": k = PlaceholderKind.MEDIA; break;
                case "smartart": k = PlaceholderKind.DIAGRAM; break;
                default: k = PlaceholderKind.OBJECT; break;
            }
            var s = new ShapeElement (ShapeKind.RECT);
            s.fill = new Fill.none ();
            s.line = new Line ();
            s.text = new TextBody ();
            s.placeholder = k;
            int idx = 10;
            foreach (var e in canvas.layout.elements) idx = int.max (idx, e.placeholder_idx + 1);
            s.placeholder_idx = k.is_title () ? -1 : idx;
            s.inherit_geometry = false;
            s.set_geometry (p.width * 0.2, p.height * 0.3, p.width * 0.6, k == PlaceholderKind.TITLE ? p.height * 0.15 : p.height * 0.4);
            s.name = k.label ();
            edit (_("Insert Placeholder"), () => {
                p.assign_ids (s);
                canvas.layout.elements.add (s);
            });
            canvas.select (s);
        }

        private void open_master (Master m, Layout? l) {
            if (view_mode != ViewMode.MASTER) set_view (ViewMode.MASTER);
            sidebar.load_masters (doc.pres, m, l);
            canvas.show_master (m, l);
            inspector.rebuild ();
        }

        private void new_master () {
            var p = doc.pres;
            Master? m = null;
            edit (_("Insert Slide Master"), () => {
                m = Factory.build_master (ThemePreset.all ()[0], p.width, p.height);
                m.id = "master%d".printf (p.masters.size + 1);
                m.name = _("Master %d").printf (p.masters.size + 1);
                var used = new Gee.HashSet<string> ();
                foreach (var l in p.all_layouts ()) used.add (l.id);
                foreach (var l in m.layouts) {
                    string base_id = l.id;
                    int n = 2;
                    while (used.contains (l.id)) l.id = "%s-%d".printf (base_id, n++);
                    used.add (l.id);
                }
                foreach (var e in m.elements) p.assign_ids (e);
                foreach (var l in m.layouts) foreach (var e in l.elements) p.assign_ids (e);
                p.masters.add (m);
            });
            open_master (m, null);
        }

        private void new_layout () {
            var p = doc.pres;
            var m = canvas.master ?? p.master;
            Layout? l = null;
            edit (_("Insert Layout"), () => {
                l = new Layout ();
                l.id = "layout-%s".printf (Uuid.string_random ().substring (0, 8));
                l.name = _("Custom Layout");
                l.kind = LayoutKind.CUSTOM;
                var title = m.find_placeholder (PlaceholderKind.TITLE);
                if (title != null) {
                    var t = title.clone ();
                    p.assign_ids (t);
                    l.elements.add (t);
                }
                foreach (var e in m.elements) {
                    if (!e.placeholder.is_meta ()) continue;
                    var c = e.clone ();
                    p.assign_ids (c);
                    l.elements.add (c);
                }
                m.layouts.add (l);
            });
            open_master (m, l);
        }

        private void duplicate_layout () {
            var p = doc.pres;
            var m = canvas.master ?? p.master;
            var src = canvas.layout;
            if (src == null) return;
            Layout? copy = null;
            edit (_("Duplicate Layout"), () => {
                copy = src.clone ();
                copy.id = "layout-%s".printf (Uuid.string_random ().substring (0, 8));
                copy.name = _("%s Copy").printf (src.name);
                copy.kind = LayoutKind.CUSTOM;
                foreach (var e in copy.elements) p.assign_ids (e);
                m.layouts.insert (m.layouts.index_of (src) + 1, copy);
            });
            open_master (m, copy);
        }

        private void delete_layout () {
            var p = doc.pres;
            var m = canvas.master ?? p.master;
            var l = canvas.layout;
            if (l == null) return;
            foreach (var s in p.slides) {
                if (s.layout_id == l.id) {
                    add_toast (new Toast (_("This layout is used by slides and cannot be deleted")));
                    return;
                }
            }
            if (m.layouts.size <= 1) return;
            edit (_("Delete Layout"), () => m.layouts.remove (l));
            open_master (m, null);
        }

        private async void import_theme () {
            var dialog = new FileDialog ();
            dialog.title = _("Browse for Themes");
            var filters = new GLib.ListStore (typeof (FileFilter));
            var f = new FileFilter ();
            f.name = _("Themes and Presentations");
            foreach (string ext in new string[] { "thmx", "pptx", "potx", "ppsx", "odp", "otp" }) f.add_suffix (ext);
            filters.append (f);
            dialog.filters = filters;
            try {
                var file = yield dialog.open (this, null);
                if (file == null) return;
                uint8[] data;
                FileUtils.get_data (file.get_path (), out data);
                Theme? theme = null;
                var zip = new ZipReader (data);
                if (zip.has ("ppt/presentation.xml") || zip.has ("content.xml")) {
                    var src = Document.load_bytes (data, file.get_basename ());
                    theme = src.master.theme;
                } else {
                    theme = new PptxReader (zip).read_theme_part ();
                }
                if (theme == null) {
                    show_error (_("Could Not Use Theme"), _("The file does not contain a theme."));
                    return;
                }
                var t = theme;
                edit (_("Apply Theme"), () => {
                    foreach (var m in doc.pres.masters) m.theme = t.clone ();
                });
                refresh_thumbnails ();
                canvas.queue_draw ();
                inspector.rebuild ();
            } catch (Error e) {
                if (!(e is Gtk.DialogError.DISMISSED)) show_error (_("Could Not Use Theme"), e.message);
            }
        }

        public LiveSession? live = null;
        private Gee.HashMap<int, string> live_sigs = new Gee.HashMap<int, string> ();
        private string live_design = "";
        private uint live_timer = 0;
        private bool live_applying = false;

        private static string slide_sig (Slide s) {
            var sb = new StringBuilder ();
            sb.append ("%s|%s|%s|%d|%d|%g|".printf (s.layout_id, s.hidden.to_string (), s.notes, (int) s.transition.kind, s.animations.size, s.transition.duration));
            foreach (var a in s.animations) sb.append (a.signature ());
            foreach (var e in s.elements) sb.append (e.light_signature () + ";" + e.description + ";");
            foreach (var c in s.comments) sb.append (c.id + c.text + c.resolved.to_string () + c.replies.size.to_string ());
            if (s.background != null) sb.append (s.background.first_color ());
            return Checksum.compute_for_string (ChecksumType.SHA1, sb.str);
        }

        private string design_sig () {
            var sb = new StringBuilder ();
            sb.append ("%g|%g|".printf (doc.pres.width, doc.pres.height));
            foreach (var m in doc.pres.masters) {
                foreach (var e in m.theme.colors.entries) sb.append (e.key + e.value);
                sb.append (m.theme.major_font + m.theme.minor_font + m.background.first_color ());
                foreach (var e in m.elements) sb.append (e.light_signature ());
                foreach (var l in m.layouts) {
                    sb.append (l.id + l.name);
                    foreach (var e in l.elements) sb.append (e.light_signature ());
                }
            }
            foreach (var c in doc.pres.custom_shows) sb.append (c.name + c.slides.size.to_string ());
            return Checksum.compute_for_string (ChecksumType.SHA1, sb.str);
        }

        private void live_snapshot () {
            live_sigs.clear ();
            foreach (var s in doc.pres.slides) live_sigs[s.uid] = slide_sig (s);
            live_design = design_sig ();
        }

        private void live_schedule () {
            if (live == null || live_applying || doc == null) return;
            if (live_timer != 0) Source.remove (live_timer);
            live_timer = Timeout.add (700, () => {
                live_timer = 0;
                live_publish ();
                return Source.REMOVE;
            });
        }

        private void live_publish () {
            if (live == null || doc == null) return;
            canvas.commit_edit ();
            var dirty = new Gee.HashSet<int> ();
            var order = new Gee.ArrayList<int> ();
            foreach (var s in doc.pres.slides) {
                order.add (s.uid);
                string sig = slide_sig (s);
                if (!live_sigs.has_key (s.uid) || live_sigs[s.uid] != sig) dirty.add (s.uid);
            }
            foreach (int uid in live_sigs.keys) if (doc.pres.slide_by_uid (uid) == null) dirty.add (uid);
            string dsig = design_sig ();
            bool design = dsig != live_design;
            bool reordered = false;
            var old_order = new Gee.ArrayList<int> ();
            old_order.add_all (live_sigs.keys);
            if (old_order.size != order.size) reordered = true;
            if (dirty.size == 0 && !design && !reordered && live_order_sig == order_sig (order)) return;
            try {
                var bytes = new Bytes (Document.serialize_as (doc.pres, "pptx"));
                live.publish (bytes, dirty, order, design);
                live_snapshot ();
                live_order_sig = order_sig (order);
            } catch (Error e) {
                warning ("live: %s", e.message);
            }
        }

        private string live_order_sig = "";

        private static string order_sig (Gee.List<int> order) {
            var sb = new StringBuilder ();
            foreach (int u in order) sb.append ("%d,".printf (u));
            return sb.str;
        }

        private void live_apply (Bytes deck, Gee.ArrayList<int> dirty, Gee.ArrayList<int> order, bool design, string who) {
            if (doc == null) return;
            Presentation remote;
            try {
                remote = Document.load_bytes (deck.get_data (), "live.pptx");
            } catch (Error e) {
                warning ("live: %s", e.message);
                return;
            }
            canvas.commit_edit ();
            live_applying = true;
            bool full = dirty.size == 0 && design;
            if (full) {
                foreach (var s in remote.slides) dirty.add (s.uid);
            }
            int cur_uid = doc.slide != null ? doc.slide.uid : -1;
            edit (who != "" ? _("Changes by %s").printf (who) : _("Live Changes"), () => {
                if (full) doc.pres.slides.clear ();
                LiveMerge.apply (doc.pres, remote, dirty, order, design);
            });
            int idx = doc.pres.index_of_uid (cur_uid);
            doc.current_slide = (idx >= 0 ? idx : doc.current_slide).clamp (0, int.max (doc.pres.slides.size - 1, 0));
            live_snapshot ();
            live_order_sig = order_sig (order);
            sidebar.thumbs.clear ();
            sidebar.load (doc.pres, doc.current_slide);
            show_current ();
            live_applying = false;
            if (who != "" && dirty.size > 0) {
                string where = "";
                foreach (int u in dirty) {
                    int i = doc.pres.index_of_uid (u);
                    if (i >= 0) {
                        where = _("slide %d").printf (i + 1);
                        break;
                    }
                }
                add_toast (new Toast (where != "" ? _("%s changed %s").printf (who, where) : _("%s made changes").printf (who)));
            }
        }

        private void live_peers () {
            sidebar.presence.clear ();
            if (live != null) {
                foreach (var p in live.peers.values) {
                    if (p.slide < 0) continue;
                    string chip = "<span foreground=\"%s\" weight=\"bold\">%s</span>".printf (p.color, Markup.escape_text (Comment.initials_of (p.name)));
                    sidebar.presence[p.slide] = sidebar.presence.has_key (p.slide) ? sidebar.presence[p.slide] + " " + chip : chip;
                }
            }
            if (doc != null && view_mode != ViewMode.MASTER) sidebar.load (doc.pres, doc.current_slide);
        }

        public void start_live (bool host, string link) {
            stop_live ();
            live = new LiveSession (CommentsPanel.me ());
            live.remote_deck.connect (live_apply);
            live.peers_changed.connect (live_peers);
            live.ended.connect ((reason) => {
                add_toast (new Toast (reason));
                stop_live ();
            });
            if (host) {
                try {
                    var order = new Gee.ArrayList<int> ();
                    foreach (var s in doc.pres.slides) order.add (s.uid);
                    live.host (new Bytes (Document.serialize_as (doc.pres, "pptx")), order);
                    live_snapshot ();
                    live_order_sig = order_sig (order);
                    if (doc.slide != null) live.presence (doc.slide.uid);
                } catch (Error e) {
                    show_error (_("Could Not Share"), e.message);
                    stop_live ();
                }
                return;
            }
            live.join.begin (link, (o, r) => {
                try {
                    live.join.end (r);
                    add_toast (new Toast (_("Joined the live presentation")));
                } catch (Error e) {
                    show_error (_("Could Not Join"), e.message);
                    stop_live ();
                }
            });
        }

        public void start_live_collab (Singularity.Collab.Person person) {
            var order = new Gee.ArrayList<int> ();
            foreach (var sl in doc.pres.slides) order.add (sl.uid);
            Bytes deck;
            try {
                deck = new Bytes (Document.serialize_as (doc.pres, "pptx"));
            } catch (Error e) {
                show_error (_("Could Not Share"), e.message);
                return;
            }
            string t = title ?? "";
            if (t == "") t = _("Presentation");
            if (live == null || !live.collab) {
                stop_live ();
                live = new LiveSession (CommentsPanel.me ());
                live.remote_deck.connect (live_apply);
                live.peers_changed.connect (live_peers);
                live.ended.connect ((reason) => {
                    add_toast (new Toast (reason));
                    stop_live ();
                });
            }
            var session = live;
            session.host_collab.begin (deck, order, person, t, (o, res) => {
                try {
                    session.host_collab.end (res);
                    live_snapshot ();
                    live_order_sig = order_sig (order);
                    if (doc.slide != null) session.presence (doc.slide.uid);
                    add_toast (new Toast (_("Invitation sent to %s").printf (person.name)));
                } catch (Error e) {
                    show_error (_("Could Not Share"), e.message);
                    stop_live ();
                }
            });
        }

        public void join_live_collab (string session, string snapshot, string from) {
            stop_live ();
            live = new LiveSession (CommentsPanel.me ());
            live.remote_deck.connect (live_apply);
            live.peers_changed.connect (live_peers);
            live.ended.connect ((reason) => {
                add_toast (new Toast (reason));
                stop_live ();
            });
            live.join_collab (session, snapshot);
            add_toast (new Toast (_("You are editing with %s").printf (from)));
        }

        public void stop_live () {
            if (live_timer != 0) {
                Source.remove (live_timer);
                live_timer = 0;
            }
            if (live != null) live.leave ();
            live = null;
            sidebar.presence.clear ();
        }

        public void fill_layout_menu (ContextMenu menu, bool as_new) {
            if (doc == null || doc.pres.slides.size == 0) return;
            var cur = doc.pres.slides[doc.current_slide.clamp (0, doc.pres.slides.size - 1)];
            var current = doc.pres.layout_for (cur);
            foreach (var l in doc.pres.master_for (cur).layouts) {
                var ll = l;
                if (as_new) {
                    menu.add_item (l.name, null, () => new_slide (ll));
                    continue;
                }
                menu.add_item (l.name, null, () => {
                    int[] idx = selected_slides ();
                    edit (_("Change Layout"), () => {
                        foreach (int i in idx) Factory.apply_layout (doc.pres, doc.pres.slides[i], ll);
                    });
                    refresh_thumbnails ();
                    show_current ();
                }, l == current ? "checked" : null);
            }
        }

        public RunStyle? current_run_style () {
            if (doc == null || canvas.slide == null && canvas.master == null) return null;
            if (canvas.editor != null) return canvas.editor.current_style ();
            var bodies = text_targets ();
            if (bodies.size == 0) return null;
            var r = new TextRun ();
            bodies[0].first_run_format (r);
            var ctx = canvas.context ();
            var ls = doc.pres.level_style (ctx.slide, ctx.layout, ctx.master, sel ()[0], 0);
            return doc.pres.run_style (ls, r, ctx.theme);
        }

        public string? shown_panel () {
            if (doc == null || !right_revealer.reveal_child || !right_revealer.visible) return null;
            return right_stack.visible_child_name;
        }

        public bool notes_shown () {
            return doc != null && notes_revealer.reveal_child;
        }
    }
}
