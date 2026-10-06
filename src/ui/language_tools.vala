using Gtk;
using Singularity.Widgets;

namespace Singularity.Apps.Slides {

    public class LanguageTools {
        private const string BUS = "dev.sinty.TranslateService";
        private const string PATH = "/dev/sinty/TranslateService";

        private static bool word_bounds (TextEditor ed, out TextIter a, out TextIter b) {
            var buf = ed.buffer;
            if (buf.get_selection_bounds (out a, out b)) return true;
            buf.get_iter_at_mark (out a, buf.get_insert ());
            b = a;
            if (!a.starts_word () && !a.inside_word () && !a.ends_word ()) return false;
            if (!a.starts_word ()) a.backward_word_start ();
            if (!b.ends_word ()) b.forward_word_end ();
            return !a.equal (b);
        }

        private static void replace_in_editor (TextEditor ed, string text) {
            TextIter a, b;
            if (!word_bounds (ed, out a, out b)) return;
            var buf = ed.buffer;
            buf.begin_user_action ();
            buf.delete (ref a, ref b);
            buf.insert (ref a, text, -1);
            buf.end_user_action ();
        }

        public static void thesaurus (SlidesWindow win) {
            var ed = win.canvas.editor;
            string word = "";
            if (ed != null) {
                TextIter a, b;
                if (word_bounds (ed, out a, out b)) word = a.get_text (b).strip ();
            }
            var dlg = Dialogs.make (win, _("Thesaurus"), 440, 560);
            var box = Dialogs.body (dlg);
            var sg = new PreferencesGroup (null, ed != null ? _("Choose a word to replace the one in the text") : _("Select a word in a text box to replace it"));
            var entry = new EntryRow (_("Word"));
            entry.text = word;
            sg.add_row (entry);
            box.append (sg);
            var results = new Box (Orientation.VERTICAL, 14);
            box.append (results);
            Dialogs.Apply refresh = null;
            refresh = () => {
                Widget? c;
                while ((c = results.get_first_child ()) != null) results.remove (c);
                string w = entry.text.strip ();
                if (w == "") return;
                var meanings = Thesaurus.lookup (w);
                if (meanings.size == 0) {
                    var sp = new StatusPage ();
                    sp.icon_name = "dictionary-symbolic";
                    sp.title = _("No Synonyms Found");
                    sp.description = Thesaurus.file_for (Thesaurus.current_language ()) == null ? _("No thesaurus is installed for the current language") : _("Try another form of the word");
                    results.append (sp);
                    return;
                }
                foreach (var m in meanings) {
                    var g = new PreferencesGroup (m.part != "" ? m.part : _("Synonyms"));
                    foreach (string syn in m.words) {
                        var row = new ActionRow (syn);
                        string chosen = syn;
                        if (ed != null) {
                            var use = new Button.with_label (_("Insert"));
                            use.valign = Align.CENTER;
                            use.clicked.connect (() => {
                                replace_in_editor (ed, chosen);
                                dlg.close ();
                            });
                            row.add_suffix (use);
                        }
                        var look = new Button.from_icon_name ("system-search-symbolic");
                        look.valign = Align.CENTER;
                        look.add_css_class ("flat");
                        look.tooltip_text = _("Look Up");
                        look.clicked.connect (() => {
                            entry.text = chosen;
                            refresh ();
                        });
                        row.add_suffix (look);
                        g.add_row (row);
                    }
                    results.append (g);
                }
            };
            entry.entry_activated.connect (() => refresh ());
            refresh ();
            dlg.open_dialog ();
        }

        private static async string translate_text (string text, string target) throws Error {
            var bus = yield Bus.get (BusType.SESSION);
            var reply = yield bus.call (BUS, PATH, BUS, "Translate", new Variant ("(sss)", text, "auto", target), new VariantType ("(sss)"), DBusCallFlags.NONE, 30000, null);
            string translation, detected, provider;
            reply.get ("(sss)", out translation, out detected, out provider);
            return translation;
        }

        private static async Gee.ArrayList<string> languages (out Gee.ArrayList<string> codes, out string default_target) {
            var names = new Gee.ArrayList<string> ();
            codes = new Gee.ArrayList<string> ();
            default_target = "en";
            try {
                var bus = yield Bus.get (BusType.SESSION);
                var reply = yield bus.call (BUS, PATH, BUS, "LanguageNames", null, new VariantType ("(a{ss})"), DBusCallFlags.NONE, 5000, null);
                var iter = reply.get_child_value (0).iterator ();
                string code, name;
                var pairs = new Gee.TreeMap<string, string> ();
                while (iter.next ("{ss}", out code, out name)) pairs[name] = code;
                foreach (var e in pairs.entries) {
                    names.add (e.key);
                    codes.add (e.value);
                }
                var dt = yield bus.call (BUS, PATH, BUS, "DefaultTarget", null, new VariantType ("(s)"), DBusCallFlags.NONE, 5000, null);
                dt.get ("(s)", out default_target);
            } catch (Error e) {
            }
            return names;
        }

        public static void translate (SlidesWindow win) {
            translate_async.begin (win);
        }

        private static async void translate_async (SlidesWindow win) {
            Gee.ArrayList<string> codes;
            string def;
            var names = yield languages (out codes, out def);
            if (names.size == 0) {
                win.show_error (_("Translation Unavailable"), _("The translation service is not running. Open Translate once to set up a translation provider."));
                return;
            }
            var ed = win.canvas.editor;
            string source = "";
            bool from_editor = false;
            if (ed != null) {
                TextIter a, b;
                if (ed.buffer.get_selection_bounds (out a, out b)) {
                    from_editor = true;
                    source = a.get_text (b);
                }
            }
            var paras = new Gee.ArrayList<Paragraph> ();
            if (!from_editor) {
                var targets = new Gee.ArrayList<Element> ();
                if (win.canvas.selection.size > 0) targets.add_all (win.canvas.selection);
                else if (win.canvas.slide != null) targets.add_all (win.canvas.slide.elements);
                foreach (var e in targets) collect (e, paras);
                var sb = new StringBuilder ();
                foreach (var p in paras) {
                    if (sb.len > 0) sb.append ("\n");
                    sb.append (p.text ());
                }
                source = sb.str;
            }
            if (source.strip () == "") {
                win.show_error (_("Nothing to Translate"), _("Select text, or objects with text, to translate them."));
                return;
            }
            var dlg = Dialogs.make (win, _("Translate"), 520, 640);
            var box = Dialogs.body (dlg);
            var g = new PreferencesGroup (_("Translator"));
            int cur = int.max (codes.index_of (def), 0);
            var lang = new SelectionRow (_("Translate To"), names.to_array (), names[cur]);
            g.add_row (lang);
            box.append (g);
            var og = new PreferencesGroup (_("Original"));
            var orig = new Label (source);
            orig.wrap = true;
            orig.xalign = 0;
            orig.selectable = true;
            orig.margin_start = orig.margin_end = orig.margin_top = orig.margin_bottom = 12;
            og.add_row (orig);
            box.append (og);
            var tg = new PreferencesGroup (_("Translation"));
            var result = new Label (_("Translating"));
            result.wrap = true;
            result.xalign = 0;
            result.selectable = true;
            result.margin_start = result.margin_end = result.margin_top = result.margin_bottom = 12;
            tg.add_row (result);
            box.append (tg);
            string translated = "";
            Dialogs.Apply run = null;
            run = () => {
                int li = names.index_of (lang.current_value);
                string code = li >= 0 ? codes[li] : def;
                result.label = _("Translating");
                translate_text.begin (source, code, (o, r) => {
                    try {
                        translated = translate_text.end (r);
                        result.label = translated;
                    } catch (Error e) {
                        DBusError.strip_remote_error (e);
                        result.label = _("Could not translate: %s").printf (e.message);
                        translated = "";
                    }
                });
            };
            lang.selected.connect (() => run ());
            Dialogs.footer (dlg, _("Insert"), () => {
                if (translated == "") return;
                if (from_editor) {
                    ed.buffer.begin_user_action ();
                    TextIter s1, s2;
                    if (ed.buffer.get_selection_bounds (out s1, out s2)) {
                        ed.buffer.delete (ref s1, ref s2);
                        ed.buffer.insert (ref s1, translated, -1);
                    }
                    ed.buffer.end_user_action ();
                    return;
                }
                string[] lines = translated.split ("\n");
                win.doc.checkpoint (_("Translate"));
                for (int i = 0; i < paras.size && i < lines.length; i++) {
                    var p = paras[i];
                    var first = p.runs.size > 0 ? p.runs[0].clone () : new TextRun ();
                    first.text = lines[i];
                    first.field = "";
                    p.runs.clear ();
                    p.runs.add (first);
                }
                win.doc.touch ();
                win.content_edited ();
                win.canvas.queue_draw ();
            });
            dlg.open_dialog ();
            run ();
        }

        private static void collect (Element e, Gee.List<Paragraph> paras) {
            var body = e.text_body ();
            if (body != null) foreach (var p in body.paragraphs) if (p.text ().strip () != "") paras.add (p);
            var g = e as GroupElement;
            if (g != null) foreach (var c in g.children) collect (c, paras);
            var t = e as TableElement;
            if (t != null) foreach (var row in t.cells) foreach (var cell in row) foreach (var p in cell.text.paragraphs) if (p.text ().strip () != "") paras.add (p);
        }
    }
}
