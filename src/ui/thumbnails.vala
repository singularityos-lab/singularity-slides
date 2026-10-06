using Gtk;
using Singularity.Widgets;

namespace Singularity.Apps.Slides {

    public class ThumbCache {
        private Gee.HashMap<string, Gdk.Texture> cache = new Gee.HashMap<string, Gdk.Texture> ();
        private Renderer renderer = new Renderer ();

        private static string key (void* obj, int width) {
            return "%p:%d".printf (obj, width);
        }

        public static Gdk.Texture texture_of (Cairo.ImageSurface surf) {
            int w = surf.get_width (), h = surf.get_height ();
            surf.flush ();
            var bytes = new Bytes (surf.get_data ()[0 : surf.get_stride () * h]);
            return new Gdk.MemoryTexture (w, h, Gdk.MemoryFormat.B8G8R8A8_PREMULTIPLIED, bytes, surf.get_stride ());
        }

        public Gdk.Texture slide (Presentation p, Slide s, int width) {
            string k = key (s, width);
            var t = cache[k];
            if (t != null) return t;
            t = texture_of (renderer.thumbnail (p, s, width));
            cache[k] = t;
            return t;
        }

        public Gdk.Texture layout (Presentation p, Master m, Layout? l, int width) {
            string k = key (l != null ? (void*) l : (void*) m, width);
            var t = cache[k];
            if (t != null) return t;
            int height = (int) Math.round (width * p.height / p.width);
            var surf = new Cairo.ImageSurface (Cairo.Format.ARGB32, width, height);
            var cr = new Cairo.Context (surf);
            cr.scale (width / p.width, width / p.width);
            var r = new Renderer ();
            r.edit_mode = true;
            r.draw_master_view (cr, p, m, l);
            t = texture_of (surf);
            cache[k] = t;
            return t;
        }

        public void invalidate (void* obj) {
            var dead = new Gee.ArrayList<string> ();
            string prefix = "%p:".printf (obj);
            foreach (var k in cache.keys) if (k.has_prefix (prefix)) dead.add (k);
            foreach (var k in dead) cache.unset (k);
        }

        public void clear () {
            cache.clear ();
        }
    }

    public class SlideRow : ListBoxRow {
        public int index;
        public Picture picture;
        public Label number;
        public Image hidden_icon;
        public Button section_button;
        public Label section_label;
        public Image section_icon;
        public Label presence;

        public SlideRow (int index) {
            this.index = index;
            add_css_class ("slides-thumb-row");
            var outer = new Box (Orientation.VERTICAL, 4);
            section_button = new Button ();
            section_button.add_css_class ("flat");
            section_button.halign = Align.FILL;
            section_label = new Label ("");
            section_label.xalign = 0;
            section_label.hexpand = true;
            section_label.ellipsize = Pango.EllipsizeMode.END;
            section_label.add_css_class ("heading");
            section_icon = new Image.from_icon_name ("pan-down-symbolic");
            var sb = new Box (Orientation.HORIZONTAL, 6);
            sb.append (section_icon);
            sb.append (section_label);
            section_button.child = sb;
            section_button.visible = false;
            outer.append (section_button);
            var box = new Box (Orientation.HORIZONTAL, 8);
            var side = new Box (Orientation.VERTICAL, 4);
            side.valign = Align.START;
            number = new Label ((index + 1).to_string ());
            number.add_css_class ("caption");
            number.add_css_class ("dim-label");
            number.add_css_class ("slides-thumb-number");
            number.xalign = 1;
            hidden_icon = new Image.from_icon_name ("view-conceal-symbolic");
            hidden_icon.pixel_size = 12;
            hidden_icon.add_css_class ("dim-label");
            hidden_icon.tooltip_text = _("Hidden during the slideshow");
            presence = new Label ("");
            presence.add_css_class ("caption");
            presence.use_markup = true;
            presence.visible = false;
            side.append (number);
            side.append (hidden_icon);
            side.append (presence);
            box.append (side);
            picture = new Picture ();
            picture.add_css_class ("slides-thumb");
            picture.can_shrink = true;
            picture.content_fit = ContentFit.FILL;
            picture.halign = Align.START;
            picture.overflow = Overflow.HIDDEN;
            box.append (picture);
            outer.append (box);
            child = outer;
        }
    }

    public class SlidesSidebar : AppSidebar {
        public const int THUMB = 168;
        public signal void slide_activated (int index);
        public signal void master_activated (Master m, Layout? l);
        public signal void context_requested (int index, Widget row);
        public signal void move_requested (int[] indices, int to);
        public signal void new_slide_requested ();

        public ListBox list;
        public ThumbCache thumbs = new ThumbCache ();
        private Presentation? pres = null;
        private bool syncing = false;
        public bool master_mode = false;
        private Gee.ArrayList<Layout?> master_items = new Gee.ArrayList<Layout?> ();
        private Gee.ArrayList<Master?> master_owner = new Gee.ArrayList<Master?> ();

        public SlidesSidebar () {
            Object ();
            box.remove_css_class ("navigation-sidebar");
            list = new ListBox ();
            list.selection_mode = SelectionMode.MULTIPLE;
            list.activate_on_single_click = false;
            list.add_css_class ("navigation-sidebar");
            list.row_selected.connect ((row) => {
                if (syncing || row == null) return;
                on_row_chosen ((SlideRow) row);
            });
            list.selected_rows_changed.connect (() => {
                if (syncing) return;
                var rows = list.get_selected_rows ();
                if (rows.length () == 1) on_row_chosen ((SlideRow) rows.data);
            });
            var scroll = new ScrolledWindow ();
            scroll.hscrollbar_policy = PolicyType.NEVER;
            scroll.vexpand = true;
            scroll.child = list;
            box.append (scroll);
            var add = add_bubble_icon ("list-add-symbolic", _("New Slide (Ctrl+M)"), () => new_slide_requested ());
            add.visible = true;
            var keys = new EventControllerKey ();
            keys.key_pressed.connect ((keyval, code, state) => {
                if (master_mode) return false;
                if (keyval == Gdk.Key.Delete || keyval == Gdk.Key.BackSpace) {
                    activate_action ("win.delete-slide", null);
                    return true;
                }
                if (keyval == Gdk.Key.Return || keyval == Gdk.Key.KP_Enter) {
                    new_slide_requested ();
                    return true;
                }
                return false;
            });
            list.add_controller (keys);
        }

        private void on_row_chosen (SlideRow row) {
            if (master_mode) {
                int i = row.index;
                if (i < 0 || i >= master_items.size) return;
                var m = master_owner[i];
                var l = master_items[i];
                master_activated (m, l);
            } else {
                slide_activated (row.index);
            }
        }

        public int[] selected_indices () {
            int[] out_ = {};
            foreach (var r in list.get_selected_rows ()) out_ += ((SlideRow) r).index;
            for (int i = 0; i < out_.length; i++) {
                for (int j = i + 1; j < out_.length; j++) {
                    if (out_[j] < out_[i]) {
                        int t = out_[i];
                        out_[i] = out_[j];
                        out_[j] = t;
                    }
                }
            }
            return out_;
        }

        private void clear () {
            Widget? child;
            while ((child = list.get_first_child ()) != null) list.remove (child);
        }

        public signal void section_toggled (int index);
        public Gee.HashMap<int, string> presence = new Gee.HashMap<int, string> ();

        public void load (Presentation p, int current) {
            pres = p;
            master_mode = false;
            syncing = true;
            clear ();
            bool collapsed = false;
            for (int i = 0; i < p.slides.size; i++) {
                var row = new SlideRow (i);
                fill_row (row);
                var mark = p.slides[i].section;
                if (mark != null) {
                    collapsed = mark.collapsed;
                    int count = p.section_end (i) - i;
                    row.section_button.visible = true;
                    row.section_label.label = "%s (%d)".printf (mark.name, count);
                    row.section_icon.icon_name = mark.collapsed ? "pan-end-symbolic" : "pan-down-symbolic";
                    row.section_button.tooltip_text = mark.collapsed ? _("Expand Section") : _("Collapse Section");
                    int si = i;
                    row.section_button.clicked.connect (() => section_toggled (si));
                } else if (collapsed) {
                    row.visible = false;
                }
                attach_dnd (row);
                var click = new GestureClick ();
                click.button = Gdk.BUTTON_SECONDARY;
                int idx = i;
                click.pressed.connect ((n, x, y) => {
                    if (!row.is_selected ()) {
                        list.unselect_all ();
                        list.select_row (row);
                    }
                    context_requested (idx, row);
                });
                row.add_controller (click);
                list.append (row);
            }
            select_index (current);
            syncing = false;
        }

        private void fill_row (SlideRow row) {
            var s = pres.slides[row.index];
            row.picture.paintable = thumbs.slide (pres, s, THUMB * int.max (1, get_scale_factor ()));
            row.picture.set_size_request (THUMB, (int) Math.round (THUMB * pres.height / pres.width));
            row.number.label = (row.index + 1).to_string ();
            row.hidden_icon.visible = s.hidden;
            if (s.hidden) row.add_css_class ("slides-thumb-hidden");
            else row.remove_css_class ("slides-thumb-hidden");
            if (presence.has_key (s.uid)) {
                row.presence.label = presence[s.uid];
                row.presence.visible = true;
            }
            string title = s.title ();
            row.tooltip_text = title != "" ? _("Slide %d: %s").printf (row.index + 1, title) : _("Slide %d").printf (row.index + 1);
        }

        public void load_masters (Presentation p, Master? cur_master, Layout? cur_layout) {
            pres = p;
            master_mode = true;
            syncing = true;
            clear ();
            master_items.clear ();
            master_owner.clear ();
            int i = 0;
            foreach (var m in p.masters) {
                var row = new SlideRow (i++);
                row.number.label = "M";
                row.hidden_icon.visible = false;
                row.picture.paintable = thumbs.layout (p, m, null, THUMB * int.max (1, get_scale_factor ()));
                row.picture.set_size_request (THUMB, (int) Math.round (THUMB * p.height / p.width));
                row.tooltip_text = _("Master: %s").printf (m.name);
                master_items.add (null);
                master_owner.add (m);
                list.append (row);
                if (m == cur_master && cur_layout == null) list.select_row (row);
                foreach (var l in m.layouts) {
                    var lr = new SlideRow (i++);
                    lr.number.label = "";
                    lr.hidden_icon.visible = false;
                    lr.picture.paintable = thumbs.layout (p, m, l, (THUMB - 24) * int.max (1, get_scale_factor ()));
                    lr.picture.set_size_request (THUMB - 24, (int) Math.round ((THUMB - 24) * p.height / p.width));
                    lr.picture.margin_start = 24;
                    lr.tooltip_text = l.name;
                    master_items.add (l);
                    master_owner.add (m);
                    list.append (lr);
                    if (l == cur_layout) list.select_row (lr);
                }
            }
            syncing = false;
        }

        public void select_index (int index) {
            syncing = true;
            list.unselect_all ();
            var row = list.get_row_at_index (index);
            if (row != null) {
                list.select_row (row);
                Idle.add (() => {
                    var r = list.get_row_at_index (index);
                    if (r != null) {
                        Graphene.Rect bounds;
                        if (r.compute_bounds (list, out bounds)) {
                            var adj = ((ScrolledWindow) list.get_parent ().get_parent ()).vadjustment;
                            if (bounds.origin.y < adj.value) adj.value = bounds.origin.y - 8;
                            else if (bounds.origin.y + bounds.size.height > adj.value + adj.page_size) adj.value = bounds.origin.y + bounds.size.height - adj.page_size + 8;
                        }
                    }
                    return Source.REMOVE;
                });
            }
            syncing = false;
        }

        public void refresh_slide (int index) {
            if (pres == null || master_mode || index < 0 || index >= pres.slides.size) return;
            thumbs.invalidate (pres.slides[index]);
            var row = list.get_row_at_index (index) as SlideRow;
            if (row != null) fill_row (row);
        }

        public void refresh_all () {
            thumbs.clear ();
            if (pres == null) return;
            if (master_mode) return;
            for (int i = 0; ; i++) {
                var row = list.get_row_at_index (i) as SlideRow;
                if (row == null) break;
                if (row.index < pres.slides.size) fill_row (row);
            }
        }

        private void attach_dnd (SlideRow row) {
            var src = new DragSource ();
            src.actions = Gdk.DragAction.MOVE;
            src.prepare.connect ((x, y) => {
                if (!row.is_selected ()) {
                    list.unselect_all ();
                    list.select_row (row);
                }
                int[] idx = selected_indices ();
                var sb = new StringBuilder ();
                foreach (int i in idx) {
                    if (sb.len > 0) sb.append (",");
                    sb.append (i.to_string ());
                }
                return new Gdk.ContentProvider.for_value (sb.str);
            });
            src.drag_begin.connect ((drag) => {
                var paint = new WidgetPaintable (row.picture);
                src.set_icon (paint, 20, 20);
            });
            row.add_controller (src);
            var drop = new DropTarget (typeof (string), Gdk.DragAction.MOVE);
            drop.drop.connect ((value, x, y) => {
                string s = (string) value;
                int[] idx = {};
                foreach (string p in s.split (",")) {
                    if (p != "") idx += int.parse (p);
                }
                int to = y > row.get_height () / 2 ? row.index + 1 : row.index;
                move_requested (idx, to);
                return true;
            });
            row.add_controller (drop);
        }
    }

    public class SorterView : Box {
        public signal void slide_activated (int index);
        public signal void context_requested (int index, Widget cell);
        public signal void move_requested (int[] indices, int to);
        public signal void selection_moved (int index);

        public FlowBox flow;
        private Presentation? pres = null;
        public ThumbCache thumbs;
        public int thumb_width = 220;

        public SorterView (ThumbCache thumbs) {
            Object (orientation: Orientation.VERTICAL, spacing: 0);
            this.thumbs = thumbs;
            flow = new FlowBox ();
            flow.selection_mode = SelectionMode.MULTIPLE;
            flow.homogeneous = true;
            flow.row_spacing = 12;
            flow.column_spacing = 12;
            flow.max_children_per_line = 12;
            flow.valign = Align.START;
            flow.add_css_class ("slides-sorter");
            flow.activate_on_single_click = false;
            flow.child_activated.connect ((child) => slide_activated (child.get_index ()));
            flow.selected_children_changed.connect (() => {
                var sel = flow.get_selected_children ();
                if (sel.length () == 1) selection_moved (sel.data.get_index ());
            });
            var scroll = new ScrolledWindow ();
            scroll.hscrollbar_policy = PolicyType.NEVER;
            scroll.vexpand = true;
            scroll.hexpand = true;
            scroll.child = flow;
            append (scroll);
        }

        public int[] selected_indices () {
            int[] out_ = {};
            foreach (var c in flow.get_selected_children ()) out_ += c.get_index ();
            for (int i = 0; i < out_.length; i++) {
                for (int j = i + 1; j < out_.length; j++) {
                    if (out_[j] < out_[i]) {
                        int t = out_[i];
                        out_[i] = out_[j];
                        out_[j] = t;
                    }
                }
            }
            return out_;
        }

        public void load (Presentation p, int current) {
            pres = p;
            Widget? child;
            while ((child = flow.get_first_child ()) != null) flow.remove (child);
            for (int i = 0; i < p.slides.size; i++) {
                var s = p.slides[i];
                var cell = new FlowBoxChild ();
                cell.add_css_class ("slides-sorter-cell");
                var box = new Box (Orientation.VERTICAL, 6);
                var pic = new Picture ();
                pic.add_css_class ("slides-thumb");
                pic.paintable = thumbs.slide (p, s, thumb_width * int.max (1, get_scale_factor ()));
                pic.can_shrink = true;
                pic.content_fit = ContentFit.FILL;
                pic.set_size_request (thumb_width, (int) Math.round (thumb_width * p.height / p.width));
                pic.overflow = Overflow.HIDDEN;
                box.append (pic);
                var caption = new Box (Orientation.HORIZONTAL, 6);
                var num = new Label ((i + 1).to_string ());
                num.add_css_class ("caption");
                num.add_css_class ("heading");
                caption.append (num);
                string title = s.title ();
                var name = new Label (title != "" ? title : _("Untitled"));
                name.add_css_class ("caption");
                name.add_css_class ("dim-label");
                name.ellipsize = Pango.EllipsizeMode.END;
                name.max_width_chars = 24;
                name.hexpand = true;
                name.xalign = 0;
                caption.append (name);
                if (s.hidden) {
                    var hid = new Image.from_icon_name ("view-conceal-symbolic");
                    hid.pixel_size = 12;
                    hid.tooltip_text = _("Hidden during the slideshow");
                    caption.append (hid);
                    pic.opacity = 0.45;
                }
                if (s.transition.kind != TransitionKind.NONE) {
                    var tr = new Image.from_icon_name ("slides-transition-symbolic");
                    tr.pixel_size = 12;
                    tr.tooltip_text = s.transition.kind.label ();
                    caption.append (tr);
                }
                box.append (caption);
                cell.child = box;
                int idx = i;
                var click = new GestureClick ();
                click.button = Gdk.BUTTON_SECONDARY;
                click.pressed.connect ((n, x, y) => {
                    if (!cell.is_selected ()) {
                        flow.unselect_all ();
                        flow.select_child (cell);
                    }
                    context_requested (idx, cell);
                });
                cell.add_controller (click);
                var src = new DragSource ();
                src.actions = Gdk.DragAction.MOVE;
                src.prepare.connect ((x, y) => {
                    if (!cell.is_selected ()) {
                        flow.unselect_all ();
                        flow.select_child (cell);
                    }
                    var sb = new StringBuilder ();
                    foreach (int k in selected_indices ()) {
                        if (sb.len > 0) sb.append (",");
                        sb.append (k.to_string ());
                    }
                    return new Gdk.ContentProvider.for_value (sb.str);
                });
                src.drag_begin.connect ((drag) => src.set_icon (new WidgetPaintable (pic), 20, 20));
                cell.add_controller (src);
                var drop = new DropTarget (typeof (string), Gdk.DragAction.MOVE);
                drop.drop.connect ((value, x, y) => {
                    int[] list = {};
                    foreach (string part in ((string) value).split (",")) if (part != "") list += int.parse (part);
                    int to = x > cell.get_width () / 2 ? idx + 1 : idx;
                    move_requested (list, to);
                    return true;
                });
                cell.add_controller (drop);
                flow.append (cell);
            }
            var cur = flow.get_child_at_index (current);
            if (cur != null) flow.select_child (cur);
        }
    }
}
