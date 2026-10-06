namespace Singularity.Apps.Slides {

    public class Template {
        public string id;
        public string name;
        public string description;
        public string theme;

        public Template (string id, string name, string description, string theme) {
            this.id = id;
            this.name = name;
            this.description = description;
            this.theme = theme;
        }
    }

    public class Templates {

        public static Gee.ArrayList<Template> all () {
            var list = new Gee.ArrayList<Template> ();
            list.add (new Template ("blank", _("Blank"), _("An empty presentation"), "clean"));
            list.add (new Template ("pitch", _("Pitch Deck"), _("Problem, solution, market and team"), "vivid"));
            list.add (new Template ("lecture", _("Lecture"), _("Agenda, sections and a summary"), "paper"));
            list.add (new Template ("status", _("Project Status"), _("Timeline, tasks and budget"), "forest"));
            list.add (new Template ("review", _("Quarterly Review"), _("Key figures and charts"), "slate"));
            list.add (new Template ("portfolio", _("Portfolio"), _("Showcase work with large visuals"), "midnight"));
            list.add (new Template ("workshop", _("Workshop"), _("Agenda, activities and takeaways"), "coral"));
            list.add (new Template ("minimal", _("Minimal"), _("Black and white with one accent"), "mono"));
            return list;
        }

        public static Presentation build (string id) {
            switch (id) {
                case "pitch": return pitch ();
                case "lecture": return lecture ();
                case "status": return status ();
                case "review": return review ();
                case "portfolio": return portfolio ();
                case "workshop": return workshop ();
                case "minimal": return minimal ();
                default: return Factory.new_presentation (ThemePreset.find ("clean"));
            }
        }

        private static void set_text (Slide s, PlaceholderKind k, string text, int nth = 0) {
            int seen = 0;
            foreach (var e in s.elements) {
                if (!e.placeholder.matches (k)) continue;
                if (seen++ < nth) continue;
                var sh = e as ShapeElement;
                if (sh == null) continue;
                sh.text.set_plain (text);
                return;
            }
        }

        private static void bullets (Slide s, string[] lines, int nth = 0) {
            int seen = 0;
            foreach (var e in s.elements) {
                if (e.placeholder != PlaceholderKind.OBJECT && e.placeholder != PlaceholderKind.BODY) continue;
                if (seen++ < nth) continue;
                var sh = (ShapeElement) e;
                sh.text.paragraphs.clear ();
                foreach (string l in lines) {
                    var p = new Paragraph ();
                    string t = l;
                    while (t.has_prefix ("  ")) {
                        p.level++;
                        t = t.substring (2);
                    }
                    p.runs.add (new TextRun (t));
                    sh.text.paragraphs.add (p);
                }
                return;
            }
        }

        private static Slide add (Presentation p, LayoutKind k) {
            return Factory.add_slide (p, p.master.layout_of_kind (k), p.slides.size);
        }

        private static void transition (Presentation p, TransitionKind k, Direction d = Direction.FROM_RIGHT) {
            foreach (var s in p.slides) {
                s.transition.kind = k;
                s.transition.direction = d;
            }
        }

        private static void animate (Slide s, Element e, AnimEffect effect, AnimTrigger trigger = AnimTrigger.ON_CLICK, Direction dir = Direction.FROM_BOTTOM) {
            var a = new Animation (e.id);
            a.effect = effect;
            a.trigger = trigger;
            a.direction = dir;
            s.animations.add (a);
        }

        private static ShapeElement card (Presentation p, Slide s, double x, double y, double w, double h, string fill, string title, string body) {
            var c = Factory.shape (p, ShapeKind.ROUND_RECT, x, y, w, h);
            c.fill = new Fill.solid (fill);
            c.corner = 0.08;
            c.text.paragraphs.clear ();
            var t = new Paragraph (title);
            t.align = TextAlign.LEFT;
            t.runs[0].bold = 1;
            t.runs[0].size = 22 * p.height / 540;
            c.text.paragraphs.add (t);
            var b = new Paragraph (body);
            b.align = TextAlign.LEFT;
            b.runs[0].size = 14 * p.height / 540;
            b.space_before = 6;
            c.text.paragraphs.add (b);
            c.text.anchor = TextAnchor.TOP;
            c.text.inset_left = 16;
            c.text.inset_right = 16;
            c.text.inset_top = 16;
            s.elements.add (c);
            return c;
        }

        private static ChartElement chart (Presentation p, Slide s, ChartKind kind, double x, double y, double w, double h) {
            var c = new ChartElement (kind);
            c.set_geometry (x, y, w, h);
            c.sample_data ();
            p.assign_ids (c);
            s.elements.add (c);
            return c;
        }

        private static void remove_placeholder (Slide s, PlaceholderKind k, int nth = 0) {
            int seen = 0;
            for (int i = 0; i < s.elements.size; i++) {
                if (!s.elements[i].placeholder.matches (k)) continue;
                if (seen++ < nth) continue;
                s.elements.remove_at (i);
                return;
            }
        }

        private static Presentation pitch () {
            var p = Factory.new_presentation (ThemePreset.find ("vivid"));
            var s = p.slides[0];
            set_text (s, PlaceholderKind.CENTER_TITLE, _("Orbit"));
            set_text (s, PlaceholderKind.SUBTITLE, _("Groceries delivered in fifteen minutes"));
            s = add (p, LayoutKind.TITLE_CONTENT);
            set_text (s, PlaceholderKind.TITLE, _("The Problem"));
            bullets (s, { _("Weekly shopping takes more than two hours"), _("Delivery windows are hours long"), _("Small shops cannot reach online customers") });
            s = add (p, LayoutKind.TITLE_ONLY);
            set_text (s, PlaceholderKind.TITLE, _("Our Solution"));
            double W = p.width;
            var c1 = card (p, s, 60, 150, (W - 160) / 3, 280, "lt1@0.14", _("Order"), _("Pick from local shops in one app."));
            var c2 = card (p, s, 80 + (W - 160) / 3, 150, (W - 160) / 3, 280, "lt1@0.14", _("Match"), _("The nearest rider takes the order."));
            var c3 = card (p, s, 100 + 2 * (W - 160) / 3, 150, (W - 160) / 3, 280, "lt1@0.14", _("Deliver"), _("At your door in fifteen minutes."));
            animate (s, c1, AnimEffect.FLY);
            animate (s, c2, AnimEffect.FLY, AnimTrigger.AFTER_PREVIOUS);
            animate (s, c3, AnimEffect.FLY, AnimTrigger.AFTER_PREVIOUS);
            s = add (p, LayoutKind.BIG_NUMBER);
            set_text (s, PlaceholderKind.TITLE, "€4.2B");
            set_text (s, PlaceholderKind.BODY, _("Addressable market in our first three cities"));
            s = add (p, LayoutKind.TITLE_ONLY);
            set_text (s, PlaceholderKind.TITLE, _("Growth"));
            var ch = chart (p, s, ChartKind.COLUMN, 60, 130, W - 120, 360);
            ch.categories.clear ();
            ch.series.clear ();
            foreach (string m in new string[] { _("Jan"), _("Feb"), _("Mar"), _("Apr"), _("May"), _("Jun") }) ch.categories.add (m);
            var ser = new ChartSeries (_("Orders (thousands)"));
            foreach (double v in new double[] { 12, 18, 26, 35, 49, 64 }) ser.values.add (v);
            ser.color = "lt1";
            ch.series.add (ser);
            ch.data_labels = true;
            ch.legend = LegendPosition.NONE;
            animate (s, ch, AnimEffect.WIPE, AnimTrigger.AFTER_PREVIOUS);
            s = add (p, LayoutKind.SECTION);
            set_text (s, PlaceholderKind.TITLE, _("Thank You"));
            set_text (s, PlaceholderKind.BODY, _("hello@orbit.example"));
            transition (p, TransitionKind.PUSH, Direction.FROM_RIGHT);
            p.slides[0].transition.kind = TransitionKind.FADE;
            p.properties.title = _("Pitch Deck");
            return p;
        }

        private static Presentation lecture () {
            var p = Factory.new_presentation (ThemePreset.find ("paper"));
            var s = p.slides[0];
            set_text (s, PlaceholderKind.CENTER_TITLE, _("Introduction to Astronomy"));
            set_text (s, PlaceholderKind.SUBTITLE, _("Lecture 1: The Night Sky"));
            s = add (p, LayoutKind.TITLE_CONTENT);
            set_text (s, PlaceholderKind.TITLE, _("Agenda"));
            bullets (s, { _("Constellations and how to find them"), _("The motion of the stars"), "  " + _("Daily and yearly cycles"), _("Planets and the ecliptic"), _("Questions") });
            foreach (var par in ((ShapeElement) s.elements[1]).text.paragraphs) par.bullet = BulletKind.NUMBER;
            s = add (p, LayoutKind.SECTION);
            set_text (s, PlaceholderKind.TITLE, _("Constellations"));
            set_text (s, PlaceholderKind.BODY, _("Patterns we draw between the stars"));
            s = add (p, LayoutKind.TWO_CONTENT);
            set_text (s, PlaceholderKind.TITLE, _("Northern and Southern Sky"));
            bullets (s, { _("Ursa Major"), _("Cassiopeia"), _("Orion"), _("Cygnus") }, 0);
            bullets (s, { _("Crux"), _("Centaurus"), _("Carina"), _("Scorpius") }, 1);
            s = add (p, LayoutKind.QUOTE);
            set_text (s, PlaceholderKind.BODY, _("Look up at the stars and not down at your feet."));
            set_text (s, PlaceholderKind.BODY, _("Stephen Hawking"), 1);
            s = add (p, LayoutKind.TITLE_CONTENT);
            set_text (s, PlaceholderKind.TITLE, _("Summary"));
            bullets (s, { _("Stars rise in the east and set in the west"), _("Constellations help us navigate"), _("Planets wander along the ecliptic") });
            s.notes = _("Remind the class about the observation night on Friday.");
            transition (p, TransitionKind.FADE);
            p.properties.title = _("Lecture");
            return p;
        }

        private static Presentation status () {
            var p = Factory.new_presentation (ThemePreset.find ("forest"));
            double W = p.width;
            var s = p.slides[0];
            set_text (s, PlaceholderKind.CENTER_TITLE, _("Project Status"));
            set_text (s, PlaceholderKind.SUBTITLE, _("Website redesign, week 12"));
            s = add (p, LayoutKind.TITLE_ONLY);
            set_text (s, PlaceholderKind.TITLE, _("Timeline"));
            string[] phases = { _("Research"), _("Design"), _("Build"), _("Launch") };
            double cw = (W - 120) / 4;
            for (int i = 0; i < 4; i++) {
                var c = Factory.shape (p, i == 0 ? ShapeKind.HOME_PLATE : ShapeKind.CHEVRON, 60 + i * cw, 200, cw + 10, 90);
                c.fill = new Fill.solid (i < 2 ? "accent1" : (i == 2 ? "accent3" : "lt2~0.85"));
                c.text.set_plain (phases[i]);
                c.text.paragraphs[0].align = TextAlign.CENTER;
                c.text.paragraphs[0].runs[0].bold = 1;
                s.elements.add (c);
                animate (s, c, AnimEffect.WIPE, i == 0 ? AnimTrigger.ON_CLICK : AnimTrigger.AFTER_PREVIOUS, Direction.FROM_LEFT);
            }
            var note = Factory.text_box (p, 60, 330, W - 120, _("We are here: building the new checkout."), 18);
            s.elements.add (note);
            s = add (p, LayoutKind.TITLE_ONLY);
            set_text (s, PlaceholderKind.TITLE, _("Tasks"));
            var t = new TableElement (5, 3, W - 120, 48);
            t.set_geometry (60, 140, W - 120, 240);
            string[,] cells = {
                { _("Task"), _("Owner"), _("Status") },
                { _("Checkout flow"), "Ada", _("In progress") },
                { _("Product pages"), "Luca", _("Done") },
                { _("Search"), "Sara", _("In review") },
                { _("Analytics"), "Marco", _("Not started") }
            };
            for (int r = 0; r < 5; r++) for (int c = 0; c < 3; c++) t.cells[r][c].text.set_plain (cells[r, c]);
            p.assign_ids (t);
            s.elements.add (t);
            s = add (p, LayoutKind.TITLE_ONLY);
            set_text (s, PlaceholderKind.TITLE, _("Budget"));
            var ch = chart (p, s, ChartKind.BAR, 60, 130, W - 120, 360);
            ch.categories.clear ();
            ch.series.clear ();
            foreach (string c in phases) ch.categories.add (c);
            var planned = new ChartSeries (_("Planned"));
            var spent = new ChartSeries (_("Spent"));
            foreach (double v in new double[] { 20, 45, 80, 25 }) planned.values.add (v);
            foreach (double v in new double[] { 18, 49, 52, 0 }) spent.values.add (v);
            ch.series.add (planned);
            ch.series.add (spent);
            s = add (p, LayoutKind.TITLE_CONTENT);
            set_text (s, PlaceholderKind.TITLE, _("Next Steps"));
            bullets (s, { _("Finish checkout by Friday"), _("Usability test with ten customers"), _("Plan the launch campaign") });
            transition (p, TransitionKind.WIPE, Direction.FROM_RIGHT);
            p.properties.title = _("Project Status");
            return p;
        }

        private static Presentation review () {
            var p = Factory.new_presentation (ThemePreset.find ("slate"));
            double W = p.width;
            var s = p.slides[0];
            set_text (s, PlaceholderKind.CENTER_TITLE, _("Quarterly Review"));
            set_text (s, PlaceholderKind.SUBTITLE, _("Third quarter results"));
            s = add (p, LayoutKind.TITLE_ONLY);
            set_text (s, PlaceholderKind.TITLE, _("Key Figures"));
            string[] nums = { "+18%", "2.4M", "96%" };
            string[] labels = { _("Revenue growth"), _("Active users"), _("Customer satisfaction") };
            double cw = (W - 160) / 3;
            for (int i = 0; i < 3; i++) {
                var c = card (p, s, 60 + i * (cw + 20), 170, cw, 220, "dk2", nums[i], labels[i]);
                c.text.paragraphs[0].runs[0].size = 54;
                c.text.paragraphs[0].runs[0].color = "accent%d".printf (i + 1);
                c.text.anchor = TextAnchor.MIDDLE;
                c.shadow.enabled = true;
                c.shadow.blur = 14;
                c.shadow.distance = 6;
                animate (s, c, AnimEffect.ZOOM, i == 0 ? AnimTrigger.ON_CLICK : AnimTrigger.WITH_PREVIOUS);
                s.animations[s.animations.size - 1].delay = i * 0.15;
            }
            s = add (p, LayoutKind.TITLE_ONLY);
            set_text (s, PlaceholderKind.TITLE, _("Revenue by Month"));
            var ch = chart (p, s, ChartKind.LINE, 60, 130, W - 120, 360);
            ch.categories.clear ();
            ch.series.clear ();
            foreach (string m in new string[] { _("Jul"), _("Aug"), _("Sep") }) ch.categories.add (m);
            var a = new ChartSeries (_("This year"));
            var b = new ChartSeries (_("Last year"));
            foreach (double v in new double[] { 1.2, 1.5, 1.9 }) a.values.add (v);
            foreach (double v in new double[] { 1.0, 1.2, 1.4 }) b.values.add (v);
            ch.series.add (a);
            ch.series.add (b);
            ch.smooth = true;
            s = add (p, LayoutKind.TWO_CONTENT);
            set_text (s, PlaceholderKind.TITLE, _("Where Users Come From"));
            remove_placeholder (s, PlaceholderKind.OBJECT, 1);
            var pie = chart (p, s, ChartKind.DOUGHNUT, W / 2 + 20, 130, W / 2 - 80, 360);
            pie.categories.clear ();
            pie.series.clear ();
            foreach (string c in new string[] { _("Search"), _("Social"), _("Direct"), _("Email") }) pie.categories.add (c);
            var ps = new ChartSeries (_("Share"));
            foreach (double v in new double[] { 42, 27, 21, 10 }) ps.values.add (v);
            pie.series.add (ps);
            pie.data_labels = true;
            pie.legend = LegendPosition.RIGHT;
            bullets (s, { _("Search keeps growing"), _("Social doubled since spring"), _("Email is steady") });
            transition (p, TransitionKind.ZOOM);
            p.properties.title = _("Quarterly Review");
            return p;
        }

        private static Presentation portfolio () {
            var p = Factory.new_presentation (ThemePreset.find ("midnight"));
            double W = p.width, H = p.height;
            var s = p.slides[0];
            set_text (s, PlaceholderKind.CENTER_TITLE, _("Selected Work"));
            set_text (s, PlaceholderKind.SUBTITLE, _("Brand and product design, 2020 to 2026"));
            s = add (p, LayoutKind.BLANK);
            string[,] grads = { { "accent1", "accent5" }, { "accent2", "accent6" }, { "accent3", "accent4" } };
            string[] titles = { _("Aurora"), _("Tidal"), _("Canopy") };
            double cw = (W - 160) / 3;
            for (int i = 0; i < 3; i++) {
                var c = Factory.shape (p, ShapeKind.ROUND_RECT, 60 + i * (cw + 20), 70, cw, H - 170);
                c.fill = new Fill.gradient (grads[i, 0], grads[i, 1], 60 + i * 30);
                c.corner = 0.06;
                c.text.set_plain (titles[i]);
                c.text.anchor = TextAnchor.BOTTOM;
                c.text.inset_bottom = 18;
                c.text.paragraphs[0].runs[0].size = 26;
                c.text.paragraphs[0].runs[0].bold = 1;
                c.shadow.enabled = true;
                c.shadow.blur = 20;
                c.shadow.distance = 10;
                c.shadow.opacity = 0.5;
                s.elements.add (c);
                animate (s, c, AnimEffect.FLOAT, i == 0 ? AnimTrigger.ON_CLICK : AnimTrigger.AFTER_PREVIOUS);
            }
            s = add (p, LayoutKind.SECTION);
            set_text (s, PlaceholderKind.TITLE, _("Aurora"));
            set_text (s, PlaceholderKind.BODY, _("A calm identity for a meditation app"));
            s = add (p, LayoutKind.QUOTE);
            set_text (s, PlaceholderKind.BODY, _("Design is not just what it looks like. Design is how it works."));
            set_text (s, PlaceholderKind.BODY, _("Steve Jobs"), 1);
            transition (p, TransitionKind.FADE_BLACK);
            p.properties.title = _("Portfolio");
            return p;
        }

        private static Presentation workshop () {
            var p = Factory.new_presentation (ThemePreset.find ("coral"));
            double W = p.width;
            var s = p.slides[0];
            set_text (s, PlaceholderKind.CENTER_TITLE, _("Design Sprint Workshop"));
            set_text (s, PlaceholderKind.SUBTITLE, _("Five days from problem to tested prototype"));
            s = add (p, LayoutKind.TITLE_ONLY);
            set_text (s, PlaceholderKind.TITLE, _("The Week"));
            string[] days = { _("Map"), _("Sketch"), _("Decide"), _("Prototype"), _("Test") };
            double cw = (W - 120 - 4 * 16) / 5;
            for (int i = 0; i < 5; i++) {
                var c = Factory.shape (p, ShapeKind.ELLIPSE, 60 + i * (cw + 16), 190, cw, cw);
                c.fill = new Fill.solid ("accent%d".printf (i + 1));
                c.text.set_plain ("%d\n%s".printf (i + 1, days[i]));
                foreach (var par in c.text.paragraphs) par.align = TextAlign.CENTER;
                c.text.paragraphs[0].runs[0].size = 32;
                c.text.paragraphs[0].runs[0].bold = 1;
                s.elements.add (c);
                animate (s, c, AnimEffect.ZOOM, i == 0 ? AnimTrigger.ON_CLICK : AnimTrigger.AFTER_PREVIOUS);
            }
            s = add (p, LayoutKind.COMPARISON);
            set_text (s, PlaceholderKind.TITLE, _("Roles"));
            set_text (s, PlaceholderKind.BODY, _("Decider"), 0);
            bullets (s, { _("Makes the final call"), _("Keeps the team focused") }, 1);
            set_text (s, PlaceholderKind.BODY, _("Facilitator"), 2);
            bullets (s, { _("Runs the schedule"), _("Keeps discussions short") }, 3);
            s = add (p, LayoutKind.TITLE_CONTENT);
            set_text (s, PlaceholderKind.TITLE, _("Takeaways"));
            bullets (s, { _("Start with the long-term goal"), _("Sketch alone, decide together"), _("Test with five real users") });
            transition (p, TransitionKind.COVER, Direction.FROM_BOTTOM);
            p.properties.title = _("Workshop");
            return p;
        }

        private static Presentation minimal () {
            var p = Factory.new_presentation (ThemePreset.find ("mono"));
            var s = p.slides[0];
            set_text (s, PlaceholderKind.CENTER_TITLE, _("Less, but Better"));
            set_text (s, PlaceholderKind.SUBTITLE, _("Ten principles for good design"));
            s = add (p, LayoutKind.TITLE_CONTENT);
            set_text (s, PlaceholderKind.TITLE, _("Principles"));
            bullets (s, { _("Good design is innovative"), _("Good design makes a product useful"), _("Good design is unobtrusive"), _("Good design is honest") });
            s = add (p, LayoutKind.BIG_NUMBER);
            set_text (s, PlaceholderKind.TITLE, "10");
            set_text (s, PlaceholderKind.BODY, _("principles, one idea"));
            transition (p, TransitionKind.DISSOLVE);
            p.properties.title = _("Minimal");
            return p;
        }
    }
}
