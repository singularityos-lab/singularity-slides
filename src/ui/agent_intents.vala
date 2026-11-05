namespace Singularity.Apps.Slides {

    internal class SlidesIntents : Object {
        private const string[] LAYOUTS = { "title", "title_content", "section", "two_content", "comparison", "title_only", "blank", "content_caption", "picture_caption", "quote", "big_number" };

        private static string text (Json.Object args, string key) {
            return args.has_member (key) ? args.get_string_member (key) : "";
        }

        private static SlidesWindow window (SlidesApp app) {
            SlidesWindow? found = null;
            var active = app.get_active_window () as SlidesWindow;
            if (active != null && active.doc != null) found = active;
            if (found == null) {
                foreach (var w in app.get_windows ()) {
                    var sw = w as SlidesWindow;
                    if (sw != null && sw.doc != null) {
                        found = sw;
                        break;
                    }
                }
            }
            if (found == null) {
                app.activate ();
                found = app.get_active_window () as SlidesWindow;
                if (found == null) {
                    foreach (var w in app.get_windows ()) {
                        found = w as SlidesWindow;
                        if (found != null) break;
                    }
                }
                if (found == null) found = new SlidesWindow (app);
                if (found.doc == null) found.new_presentation ();
            }
            found.present ();
            return found;
        }

        private static int slide_index (SlidesWindow w, Json.Object args) throws Error {
            int n = w.doc.pres.slides.size;
            int i = args.has_member ("slide") ? (int) args.get_int_member ("slide") - 1 : w.doc.current_slide;
            if (i < 0 || i >= n) throw new IOError.INVALID_ARGUMENT ("slide must be between 1 and %d", n);
            return i;
        }

        private static string layout_name (Presentation p, Slide s) {
            var l = p.layout_for (s);
            if (l == null || (int) l.kind >= LAYOUTS.length) return "custom";
            return LAYOUTS[(int) l.kind];
        }

        private static Layout? layout_named (Presentation p, string name) throws Error {
            if (name == "") return null;
            for (int i = 0; i < LAYOUTS.length; i++) {
                if (LAYOUTS[i] == name) {
                    var l = p.master.layout_of_kind ((LayoutKind) i);
                    if (l == null) throw new IOError.NOT_FOUND ("this theme has no %s layout", name);
                    return l;
                }
            }
            throw new IOError.INVALID_ARGUMENT ("unknown layout %s, use one of %s", name, string.joinv (", ", LAYOUTS));
        }

        private static void set_bullets (Slide s, Json.Array bullets) throws Error {
            var b = DeckOutline.body_of (s);
            if (b == null || b.text_body () == null) throw new IOError.NOT_SUPPORTED ("this slide layout has no body for bullets");
            var body = b.text_body ();
            body.paragraphs.clear ();
            foreach (var node in bullets.get_elements ()) {
                string line;
                int level = 0;
                if (node.get_node_type () == Json.NodeType.OBJECT) {
                    var o = node.get_object ();
                    line = o.has_member ("text") ? o.get_string_member ("text") : "";
                    level = o.has_member ("level") ? (int) o.get_int_member ("level") : 0;
                } else {
                    line = node.get_string ();
                }
                var para = new Paragraph (line);
                para.level = level.clamp (0, 8);
                body.paragraphs.add (para);
            }
            if (body.paragraphs.size == 0) body.paragraphs.add (new Paragraph (""));
        }

        private static void set_title (Slide s, string title) throws Error {
            var t = s.placeholder (PlaceholderKind.TITLE);
            if (t == null || t.text_body () == null) throw new IOError.NOT_SUPPORTED ("this slide layout has no title");
            t.text_body ().set_plain (title);
        }

        private static void fill (Slide s, Json.Object args) throws Error {
            if (args.has_member ("title")) set_title (s, text (args, "title"));
            if (args.has_member ("bullets")) set_bullets (s, args.get_array_member ("bullets"));
            if (args.has_member ("subtitle")) {
                var sub = s.placeholder (PlaceholderKind.SUBTITLE);
                if (sub == null || sub.text_body () == null) throw new IOError.NOT_SUPPORTED ("this slide layout has no subtitle");
                sub.text_body ().set_plain (text (args, "subtitle"));
            }
            if (args.has_member ("notes")) s.notes = text (args, "notes");
            if (args.has_member ("hidden")) s.hidden = args.get_boolean_member ("hidden");
        }

        private static Json.Node describe (Presentation p, int i) {
            var s = p.slides[i];
            var o = new Json.Object ();
            o.set_int_member ("slide", i + 1);
            o.set_string_member ("layout", layout_name (p, s));
            o.set_string_member ("title", s.title ());
            var bullets = new Json.Array ();
            var b = DeckOutline.body_of (s);
            if (b != null && b.text_body () != null) {
                foreach (var para in b.text_body ().paragraphs) {
                    string t = para.text ().replace ("\v", " ").strip ();
                    if (t == "") continue;
                    var item = new Json.Object ();
                    item.set_string_member ("text", t);
                    item.set_int_member ("level", para.level);
                    bullets.add_object_element (item);
                }
            }
            o.set_array_member ("bullets", bullets);
            int images = 0, shapes = 0;
            foreach (var e in s.elements) {
                if (e is ImageElement) images++;
                else shapes++;
            }
            o.set_int_member ("images", images);
            o.set_int_member ("other_elements", shapes);
            if (s.notes != "") o.set_string_member ("notes", s.notes);
            if (s.hidden) o.set_boolean_member ("hidden", true);
            var node = new Json.Node (Json.NodeType.OBJECT);
            node.set_object (o);
            return node;
        }

        private static Json.Node outline (SlidesWindow w) {
            var p = w.doc.pres;
            var list = new Json.Array ();
            for (int i = 0; i < p.slides.size; i++) list.add_element (describe (p, i));
            var o = new Json.Object ();
            o.set_string_member ("file", w.doc.path ?? "");
            o.set_int_member ("current_slide", w.doc.current_slide + 1);
            o.set_string_member ("theme", p.master.theme.name);
            o.set_array_member ("slides", list);
            var node = new Json.Node (Json.NodeType.OBJECT);
            node.set_object (o);
            return node;
        }

        private static void add_image (SlidesWindow w, string path) throws Error {
            uint8[] data;
            FileUtils.get_data (path, out data);
            bool uncertain;
            string mime = ContentType.get_mime_type (ContentType.guess (path, data, out uncertain)) ?? "image/png";
            if (!mime.has_prefix ("image/")) throw new IOError.INVALID_DATA ("%s is not an image", path);
            var bytes = new Bytes (data);
            int pw, ph;
            if (!ImageCache.size_of (bytes, out pw, out ph) || pw <= 0) throw new IOError.INVALID_DATA ("%s cannot be decoded as an image", path);
            w.insert_image (bytes, mime, Path.get_basename (path));
        }

        internal static void install (SlidesApp app) {
            var agent = app.agent;
            agent.add_intent ("slides_outline", "Read the presentation: every slide with layout, title, bullets, images and speaker notes.",
                "{\"type\":\"object\",\"properties\":{}}",
                Singularity.AppIntentRisk.READ, (args) => outline (window (app)));

            agent.add_intent ("slides_add", "Add a slide with a layout, a title, bullets (strings or {text, level}), a subtitle, speaker notes and an optional image file, after the current slide or at a 1-based position.",
                "{\"type\":\"object\",\"properties\":{\"layout\":{\"type\":\"string\",\"enum\":[\"title\",\"title_content\",\"section\",\"two_content\",\"comparison\",\"title_only\",\"blank\",\"content_caption\",\"picture_caption\",\"quote\",\"big_number\"]},\"title\":{\"type\":\"string\"},\"subtitle\":{\"type\":\"string\"},\"bullets\":{\"type\":\"array\"},\"notes\":{\"type\":\"string\"},\"image\":{\"type\":\"string\"},\"position\":{\"type\":\"integer\"}}}",
                Singularity.AppIntentRisk.UNDOABLE, (args) => {
                    var w = window (app);
                    var p = w.doc.pres;
                    var layout = layout_named (p, text (args, "layout"));
                    if (layout == null) layout = p.master.layout_of_kind (LayoutKind.TITLE_CONTENT) ?? p.master.layouts[0];
                    int at = args.has_member ("position") ? (int) args.get_int_member ("position") - 1 : w.doc.current_slide + 1;
                    at = at.clamp (0, p.slides.size);
                    Error? problem = null;
                    w.agent_edit (_("New Slide"), () => {
                        var s = Factory.add_slide (p, layout, at);
                        try {
                            fill (s, args);
                        } catch (Error e) {
                            problem = e;
                        }
                    });
                    w.go_to_slide (at);
                    if (problem != null) throw problem;
                    if (text (args, "image") != "") add_image (w, text (args, "image"));
                    return describe (p, at);
                });

            agent.add_intent ("slides_update", "Change a slide (1-based): title, bullets, subtitle, notes, hidden, layout, add an image file, move it to a new position or delete it.",
                "{\"type\":\"object\",\"properties\":{\"slide\":{\"type\":\"integer\"},\"layout\":{\"type\":\"string\"},\"title\":{\"type\":\"string\"},\"subtitle\":{\"type\":\"string\"},\"bullets\":{\"type\":\"array\"},\"notes\":{\"type\":\"string\"},\"hidden\":{\"type\":\"boolean\"},\"image\":{\"type\":\"string\"},\"move_to\":{\"type\":\"integer\"},\"delete\":{\"type\":\"boolean\"}},\"required\":[\"slide\"]}",
                Singularity.AppIntentRisk.UNDOABLE, (args) => {
                    var w = window (app);
                    var p = w.doc.pres;
                    int i = slide_index (w, args);
                    if (args.has_member ("delete") && args.get_boolean_member ("delete")) {
                        if (p.slides.size == 1) throw new IOError.FAILED ("a presentation keeps at least one slide");
                        w.agent_edit (_("Delete Slide"), () => p.slides.remove_at (i));
                        w.go_to_slide (int.min (i, p.slides.size - 1));
                        return outline (w);
                    }
                    var layout = layout_named (p, text (args, "layout"));
                    Error? problem = null;
                    int target = i;
                    w.agent_edit (_("Edit Slide"), () => {
                        var s = p.slides[i];
                        if (layout != null) Factory.apply_layout (p, s, layout);
                        try {
                            fill (s, args);
                        } catch (Error e) {
                            problem = e;
                        }
                        if (args.has_member ("move_to")) {
                            target = ((int) args.get_int_member ("move_to") - 1).clamp (0, p.slides.size - 1);
                            if (target != i) {
                                p.slides.remove_at (i);
                                p.slides.insert (target, s);
                            }
                        }
                    });
                    w.go_to_slide (target);
                    if (problem != null) throw problem;
                    if (text (args, "image") != "") add_image (w, text (args, "image"));
                    return describe (p, target);
                });

            agent.add_intent ("slides_theme", "Apply a theme to the whole presentation. Without a theme, list the available ones.",
                "{\"type\":\"object\",\"properties\":{\"theme\":{\"type\":\"string\"}}}",
                Singularity.AppIntentRisk.UNDOABLE, (args) => {
                    var w = window (app);
                    string id = text (args, "theme");
                    var themes = new Json.Array ();
                    ThemePreset? chosen = null;
                    foreach (var t in ThemePreset.all ()) {
                        var o = new Json.Object ();
                        o.set_string_member ("id", t.id);
                        o.set_string_member ("name", t.name);
                        themes.add_object_element (o);
                        if (id != "" && (t.id == id || t.name.down () == id.down ())) chosen = t;
                    }
                    var result = new Json.Object ();
                    if (id != "") {
                        if (chosen == null) throw new IOError.NOT_FOUND ("no theme %s; call slides_theme without a theme to list them", id);
                        w.apply_theme (chosen);
                        result.set_string_member ("applied", chosen.id);
                    }
                    result.set_string_member ("current", w.doc.pres.master.theme.name);
                    result.set_array_member ("themes", themes);
                    var node = new Json.Node (Json.NodeType.OBJECT);
                    node.set_object (result);
                    return node;
                });

            agent.add_intent ("slides_present", "Start the slideshow from a slide (1-based, default the first).",
                "{\"type\":\"object\",\"properties\":{\"slide\":{\"type\":\"integer\"}}}",
                Singularity.AppIntentRisk.UNDOABLE, (args) => {
                    var w = window (app);
                    int from = args.has_member ("slide") ? (int) args.get_int_member ("slide") - 1 : 0;
                    w.start_show (from.clamp (0, w.doc.pres.slides.size - 1), false, false);
                    var o = new Json.Object ();
                    o.set_boolean_member ("presenting", true);
                    o.set_int_member ("slide", from.clamp (0, w.doc.pres.slides.size - 1) + 1);
                    var node = new Json.Node (Json.NodeType.OBJECT);
                    node.set_object (o);
                    return node;
                });

            agent.add_intent ("slides_save", "Save the presentation as .pptx or .odp, to its file, a given path, or the Documents folder.",
                "{\"type\":\"object\",\"properties\":{\"path\":{\"type\":\"string\"}}}",
                Singularity.AppIntentRisk.IRREVERSIBLE, (args) => {
                    var w = window (app);
                    string saved = w.save_quietly (text (args, "path"));
                    var o = new Json.Object ();
                    o.set_string_member ("file", saved);
                    o.set_boolean_member ("verified", FileUtils.test (saved, FileTest.EXISTS));
                    var node = new Json.Node (Json.NodeType.OBJECT);
                    node.set_object (o);
                    return node;
                });
        }
    }
}
