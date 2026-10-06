using Gtk;
using Singularity.Widgets;

namespace Singularity.Apps.Slides {

    public class CommentsPanel : Box {
        private SlidesWindow win;
        private Box content;
        private Comment? pending = null;
        private bool show_resolved = true;

        public CommentsPanel (SlidesWindow win) {
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

        private void edit (string label, owned Document.EditFunc f) {
            win.doc.checkpoint (label);
            f ();
            win.doc.touch ();
            win.canvas.queue_draw ();
            win.content_edited ();
        }

        public static string me () {
            string n = Environment.get_real_name ();
            return n != "" && n != "Unknown" ? n : Environment.get_user_name ();
        }

        public void start_new (Comment c) {
            pending = c;
            rebuild ();
        }

        public void rebuild () {
            Widget? child;
            while ((child = content.get_first_child ()) != null) content.remove (child);
            var slide = win.canvas.slide;
            if (win.doc == null || slide == null) return;
            var g = new PreferencesGroup (_("Comments"), _("Slide %d").printf (win.doc.current_slide + 1));
            var add = new Button.from_icon_name ("list-add-symbolic");
            add.tooltip_text = _("New Comment");
            add.action_name = "win.new-comment";
            g.add_header_suffix (add);
            var filter = new ToggleButton ();
            filter.icon_name = "object-select-symbolic";
            filter.tooltip_text = _("Show Resolved Comments");
            filter.active = show_resolved;
            filter.toggled.connect (() => {
                show_resolved = filter.active;
                rebuild ();
            });
            g.add_header_suffix (filter);
            content.append (g);
            if (pending != null) g.add_row (composer (slide, null));
            int shown = 0;
            foreach (var c in slide.comments) {
                if (c.resolved && !show_resolved) continue;
                g.add_row (thread (slide, c));
                shown++;
            }
            if (shown == 0 && pending == null) {
                var sp = new WelcomePage ();
                sp.is_section = true;
                sp.embedded = true;
                sp.title = _("No Comments");
                sp.subtitle = _("Start a conversation about this slide");
                sp.add_action ("x-office-presentation", _("New Comment"), _("Comment on the slide or the selected object"), () => win.new_comment ());
                g.add_row (sp);
            }
            var nav = new Box (Orientation.HORIZONTAL, 6);
            nav.halign = Align.END;
            var prev = new Button.from_icon_name ("go-previous-symbolic");
            prev.tooltip_text = _("Previous Comment");
            prev.clicked.connect (() => jump (-1));
            var next = new Button.from_icon_name ("go-next-symbolic");
            next.tooltip_text = _("Next Comment");
            next.clicked.connect (() => jump (1));
            nav.append (prev);
            nav.append (next);
            content.append (nav);
        }

        private void jump (int dir) {
            var p = win.doc.pres;
            int n = p.slides.size;
            for (int k = 1; k <= n; k++) {
                int i = ((win.doc.current_slide + dir * k) % n + n) % n;
                if (p.slides[i].comments.size > 0) {
                    win.go_to_slide (i);
                    rebuild ();
                    return;
                }
            }
        }

        private Widget composer (Slide slide, Comment? parent) {
            var box = new Box (Orientation.VERTICAL, 6);
            box.margin_start = box.margin_end = 12;
            box.margin_top = box.margin_bottom = 10;
            var view = new TextView ();
            view.wrap_mode = WrapMode.WORD_CHAR;
            view.add_css_class ("slides-comment-entry");
            view.set_size_request (-1, 64);
            view.accepts_tab = false;
            var frame = new Frame (null);
            frame.child = view;
            box.append (frame);
            var bar = new Box (Orientation.HORIZONTAL, 6);
            bar.halign = Align.END;
            var cancel = new Button.with_label (_("Cancel"));
            var post = new Button.with_label (parent != null ? _("Reply") : _("Post"));
            post.add_css_class ("suggested-action");
            cancel.clicked.connect (() => {
                if (parent == null) pending = null;
                rebuild ();
            });
            post.clicked.connect (() => {
                string text = view.buffer.text.strip ();
                if (text == "") return;
                if (parent == null) {
                    var c = pending;
                    pending = null;
                    c.text = text;
                    edit (_("New Comment"), () => slide.comments.add (c));
                } else {
                    var r = new Comment ();
                    r.author = me ();
                    r.initials = Comment.initials_of (r.author);
                    r.date = Comment.now ();
                    r.text = text;
                    edit (_("Reply"), () => parent.replies.add (r));
                }
                rebuild ();
            });
            bar.append (cancel);
            bar.append (post);
            box.append (bar);
            Idle.add (() => {
                view.grab_focus ();
                return Source.REMOVE;
            });
            return box;
        }

        private Widget initials (Comment c) {
            var da = new DrawingArea ();
            da.content_width = 28;
            da.content_height = 28;
            da.valign = Align.CENTER;
            string ini = c.initials != "" ? c.initials : Comment.initials_of (c.author);
            uint hash = c.author.hash ();
            da.set_draw_func ((d, cr, w, h) => {
                var col = Rgba.from_hsl ((hash % 360) / 360.0, 0.55, 0.45);
                cr.arc (w / 2.0, h / 2.0, double.min (w, h) / 2.0, 0, 2 * Math.PI);
                cr.set_source_rgb (col.r, col.g, col.b);
                cr.fill ();
                var layout = d.create_pango_layout (ini);
                layout.set_font_description (Pango.FontDescription.from_string ("Inter Bold 9"));
                int lw, lh;
                layout.get_pixel_size (out lw, out lh);
                cr.set_source_rgb (1, 1, 1);
                cr.move_to ((w - lw) / 2.0, (h - lh) / 2.0);
                Pango.cairo_show_layout (cr, layout);
            });
            return da;
        }

        private Widget bubble (Comment c, bool reply) {
            var box = new Box (Orientation.VERTICAL, 4);
            box.margin_start = reply ? 28 : 12;
            box.margin_end = 12;
            box.margin_top = 8;
            var head = new Box (Orientation.HORIZONTAL, 8);
            head.append (initials (c));
            var names = new Box (Orientation.VERTICAL, 0);
            var who = new Label (c.author != "" ? c.author : _("Unknown Author"));
            who.xalign = 0;
            who.add_css_class ("heading");
            var when = new Label (c.display_date ());
            when.xalign = 0;
            when.add_css_class ("dim-label");
            when.add_css_class ("caption");
            names.append (who);
            names.append (when);
            names.hexpand = true;
            head.append (names);
            box.append (head);
            var text = new Label (c.text);
            text.xalign = 0;
            text.wrap = true;
            text.wrap_mode = Pango.WrapMode.WORD_CHAR;
            text.selectable = true;
            if (c.mentions (me ())) text.add_css_class ("accent");
            box.append (text);
            return box;
        }

        private Widget thread (Slide slide, Comment c) {
            var box = new Box (Orientation.VERTICAL, 2);
            box.margin_bottom = 8;
            if (c.resolved) box.add_css_class ("dim-label");
            var top = bubble (c, false);
            box.append (top);
            var click = new GestureClick ();
            click.pressed.connect (() => {
                if (c.anchor >= 0) {
                    var e = slide.find (c.anchor);
                    if (e != null && slide.elements.contains (e)) win.canvas.select (e);
                }
            });
            top.add_controller (click);
            foreach (var r in c.replies) box.append (bubble (r, true));
            var bar = new Box (Orientation.HORIZONTAL, 2);
            bar.halign = Align.END;
            bar.margin_end = 8;
            var reply = new Button.from_icon_name ("mail-reply-sender-symbolic");
            reply.add_css_class ("flat");
            reply.tooltip_text = _("Reply");
            var resolve = new Button.from_icon_name (c.resolved ? "edit-undo-symbolic" : "object-select-symbolic");
            resolve.add_css_class ("flat");
            resolve.tooltip_text = c.resolved ? _("Reopen Thread") : _("Resolve Thread");
            resolve.clicked.connect (() => {
                edit (c.resolved ? _("Reopen Thread") : _("Resolve Thread"), () => c.resolved = !c.resolved);
                rebuild ();
            });
            var del = new Button.from_icon_name ("user-trash-symbolic");
            del.add_css_class ("flat");
            del.tooltip_text = _("Delete Thread");
            del.clicked.connect (() => {
                edit (_("Delete Comment"), () => slide.comments.remove (c));
                rebuild ();
            });
            bar.append (reply);
            bar.append (resolve);
            bar.append (del);
            box.append (bar);
            reply.clicked.connect (() => {
                reply.sensitive = false;
                box.append (composer (slide, c));
            });
            return box;
        }
    }
}
