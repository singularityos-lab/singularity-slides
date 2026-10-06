using Gtk;
using Singularity.Widgets;

namespace Singularity.Apps.Slides {

    public class OutlinePanel : Box {
        private SlidesWindow win;
        private TextView view;
        private bool loading = false;
        private uint pending = 0;
        private string last = "";

        public OutlinePanel (SlidesWindow win) {
            Object (orientation: Orientation.VERTICAL, spacing: 8);
            this.win = win;
            hexpand = false;
            var g = new PreferencesGroup (_("Outline"), _("Slide titles at the left edge, bullet points indented with Tab"));
            g.margin_start = 4;
            g.margin_end = 12;
            append (g);
            view = new TextView ();
            view.wrap_mode = WrapMode.WORD_CHAR;
            view.top_margin = view.bottom_margin = view.left_margin = view.right_margin = 10;
            view.accepts_tab = true;
            view.add_css_class ("slides-outline");
            var scroll = new ScrolledWindow ();
            scroll.hscrollbar_policy = PolicyType.NEVER;
            scroll.vexpand = true;
            scroll.child = view;
            scroll.margin_start = 4;
            scroll.margin_end = 12;
            scroll.margin_bottom = 12;
            scroll.min_content_width = 320;
            append (scroll);
            view.buffer.changed.connect (() => {
                if (loading) return;
                if (pending != 0) Source.remove (pending);
                pending = Timeout.add (700, () => {
                    pending = 0;
                    commit ();
                    return Source.REMOVE;
                });
            });
            var focus = new EventControllerFocus ();
            focus.leave.connect (() => commit ());
            view.add_controller (focus);
        }

        public void commit () {
            if (pending != 0) {
                Source.remove (pending);
                pending = 0;
            }
            if (win.doc == null) return;
            string text = view.buffer.text;
            if (text == last) return;
            last = text;
            win.apply_outline (text);
        }

        public void rebuild () {
            if (win.doc == null) return;
            if (view.has_focus) return;
            loading = true;
            last = DeckOutline.to_text (win.doc.pres);
            view.buffer.text = last;
            loading = false;
        }
    }
}
