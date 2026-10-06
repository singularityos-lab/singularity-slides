namespace Singularity.Apps.Slides {

    public class SlidesPrintSource : Singularity.Print.PageSource {
        private PrintLayout layout;
        private Singularity.Print.PageFormat format = new Singularity.Print.PageFormat ();

        public SlidesPrintSource (Presentation pres, string title, int current) {
            layout = new PrintLayout (pres);
            this.title = title;
            current_page = current;
            var x = new Singularity.Print.ExtraOptions (_("Slides"), _("What to print and how slides are laid out on the paper"));
            string[] ids = {};
            string[] labels = {};
            foreach (var w in PrintWhat.ALL) {
                ids += w.key ();
                labels += w.label ();
            }
            x.add_choice ("what", _("Print"), ids, labels, "slides");
            x.add_switch ("frame", _("Frame Slides"), null, false);
            x.add_switch ("hidden", _("Print Hidden Slides"), null, false);
            x.add_switch ("comments", _("Print Comments"), _("Adds a page with the comments after each slide that has them"), false);
            x.add_switch ("numbers", _("Page Numbers"), null, true);
            x.show_when ("comments", "what", { "slides", "notes", "handout1" });
            extra_options = x;
            document_pages = pres.slides.size;
        }

        private void sync () {
            var x = extra_options;
            layout.what = PrintWhat.from_key (x.get_choice ("what"));
            layout.frame_slides = x.get_bool ("frame");
            layout.include_hidden = x.get_bool ("hidden");
            layout.include_comments = x.is_visible ("comments") && x.get_bool ("comments");
            layout.footer_numbers = x.get_bool ("numbers");
        }

        public override async int paginate (Singularity.Print.PageFormat format) throws Error {
            this.format = format;
            page_width = format.width;
            page_height = format.height;
            sync ();
            return layout.pages (format.content_width, format.content_height);
        }

        public override void render_page (Cairo.Context cr, int index) {
            sync ();
            layout.draw_page (cr, index, format.margin_left, format.margin_top, format.content_width, format.content_height);
        }
    }
}
