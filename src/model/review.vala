namespace Singularity.Apps.Slides {

    public class Comment {
        public string id = "";
        public string author = "";
        public string initials = "";
        public string date = "";
        public string text = "";
        public double x = 0;
        public double y = 0;
        public bool resolved = false;
        public int anchor = -1;
        public Gee.ArrayList<Comment> replies = new Gee.ArrayList<Comment> ();

        public Comment () {
            id = Uuid.string_random ().up ();
        }

        public Comment clone () {
            var c = new Comment ();
            c.id = id;
            c.author = author;
            c.initials = initials;
            c.date = date;
            c.text = text;
            c.x = x;
            c.y = y;
            c.resolved = resolved;
            c.anchor = anchor;
            foreach (var r in replies) c.replies.add (r.clone ());
            return c;
        }

        public static string initials_of (string name) {
            var sb = new StringBuilder ();
            foreach (string part in name.split (" ")) {
                if (part == "") continue;
                sb.append_unichar (part.get_char (0).toupper ());
                if (sb.len >= 3) break;
            }
            return sb.str;
        }

        public static string now () {
            return new DateTime.now_utc ().format ("%Y-%m-%dT%H:%M:%S.000");
        }

        public string display_date () {
            var dt = new DateTime.from_iso8601 (date.has_suffix ("Z") || date.contains ("+") ? date : date + "Z", null);
            if (dt == null) return date;
            return dt.to_local ().format ("%x %H:%M");
        }

        public bool mentions (string who) {
            return who != "" && text.down ().contains ("@" + who.down ());
        }
    }

    public class SectionMark {
        public string name = "";
        public string id = "";
        public bool collapsed = false;

        public SectionMark (string name) {
            this.name = name;
            id = "{" + Uuid.string_random ().up () + "}";
        }

        public SectionMark clone () {
            var m = new SectionMark (name);
            m.id = id;
            m.collapsed = collapsed;
            return m;
        }
    }

    public class CustomShow {
        public string name = "";
        public Gee.ArrayList<int> slides = new Gee.ArrayList<int> ();

        public CustomShow clone () {
            var c = new CustomShow ();
            c.name = name;
            c.slides.add_all (slides);
            return c;
        }
    }

    public enum ActionKind {
        NONE,
        NEXT_SLIDE,
        PREVIOUS_SLIDE,
        FIRST_SLIDE,
        LAST_SLIDE,
        LAST_VIEWED,
        END_SHOW,
        SLIDE,
        URL,
        FILE,
        PROGRAM,
        CUSTOM_SHOW,
        PLAY_MEDIA;

        public string label () {
            switch (this) {
                case NEXT_SLIDE: return _("Next Slide");
                case PREVIOUS_SLIDE: return _("Previous Slide");
                case FIRST_SLIDE: return _("First Slide");
                case LAST_SLIDE: return _("Last Slide");
                case LAST_VIEWED: return _("Last Slide Viewed");
                case END_SHOW: return _("End Show");
                case SLIDE: return _("Slide");
                case URL: return _("Web Address");
                case FILE: return _("Other File");
                case PROGRAM: return _("Run Program");
                case CUSTOM_SHOW: return _("Custom Show");
                case PLAY_MEDIA: return _("Play Media");
                default: return _("None");
            }
        }

        public const ActionKind[] ALL = { NONE, NEXT_SLIDE, PREVIOUS_SLIDE, FIRST_SLIDE, LAST_SLIDE, LAST_VIEWED, END_SHOW, SLIDE, URL, FILE, PROGRAM, CUSTOM_SHOW };
    }

    public class ClickAction {
        public ActionKind kind = ActionKind.NONE;
        public int slide_uid = 0;
        public string target = "";
        public bool show_and_return = false;
        public string sound = "";
        public bool highlight = true;
        public string tooltip = "";

        public ClickAction (ActionKind kind = ActionKind.NONE) {
            this.kind = kind;
        }

        public ClickAction clone () {
            var a = new ClickAction (kind);
            a.slide_uid = slide_uid;
            a.target = target;
            a.show_and_return = show_and_return;
            a.sound = sound;
            a.highlight = highlight;
            a.tooltip = tooltip;
            return a;
        }

        public string? ppaction () {
            switch (kind) {
                case ActionKind.NEXT_SLIDE: return "ppaction://hlinkshowjump?jump=nextslide";
                case ActionKind.PREVIOUS_SLIDE: return "ppaction://hlinkshowjump?jump=previousslide";
                case ActionKind.FIRST_SLIDE: return "ppaction://hlinkshowjump?jump=firstslide";
                case ActionKind.LAST_SLIDE: return "ppaction://hlinkshowjump?jump=lastslide";
                case ActionKind.LAST_VIEWED: return "ppaction://hlinkshowjump?jump=lastslideviewed";
                case ActionKind.END_SHOW: return "ppaction://hlinkshowjump?jump=endshow";
                case ActionKind.SLIDE: return "ppaction://hlinksldjump";
                case ActionKind.FILE: return "ppaction://hlinkfile";
                case ActionKind.PROGRAM: return "ppaction://program";
                case ActionKind.CUSTOM_SHOW: return "ppaction://customshow?id=0" + (show_and_return ? "&return=true" : "");
                case ActionKind.PLAY_MEDIA: return "ppaction://media";
                default: return null;
            }
        }

        public static ClickAction? from_ppaction (string? action, string? target) {
            string act = action ?? "";
            var a = new ClickAction ();
            if (act == "" || act == "ppaction://noaction") {
                if (target == null || target == "") return act == "ppaction://noaction" ? null : null;
                a.kind = ActionKind.URL;
                a.target = target;
                return a;
            }
            if (act.has_prefix ("ppaction://hlinkshowjump")) {
                if (act.contains ("nextslide")) a.kind = ActionKind.NEXT_SLIDE;
                else if (act.contains ("previousslide")) a.kind = ActionKind.PREVIOUS_SLIDE;
                else if (act.contains ("firstslide")) a.kind = ActionKind.FIRST_SLIDE;
                else if (act.contains ("lastslideviewed")) a.kind = ActionKind.LAST_VIEWED;
                else if (act.contains ("lastslide")) a.kind = ActionKind.LAST_SLIDE;
                else if (act.contains ("endshow")) a.kind = ActionKind.END_SHOW;
                else return null;
                return a;
            }
            if (act.has_prefix ("ppaction://hlinksldjump")) {
                a.kind = ActionKind.SLIDE;
                a.target = target ?? "";
                return a;
            }
            if (act.has_prefix ("ppaction://hlinkfile") || act.has_prefix ("ppaction://hlinkpres")) {
                a.kind = ActionKind.FILE;
                a.target = target ?? "";
                return a;
            }
            if (act.has_prefix ("ppaction://program")) {
                a.kind = ActionKind.PROGRAM;
                a.target = target ?? "";
                return a;
            }
            if (act.has_prefix ("ppaction://customshow")) {
                a.kind = ActionKind.CUSTOM_SHOW;
                a.show_and_return = act.contains ("return=true");
                int at = act.index_of ("id=");
                if (at >= 0) {
                    string rest = act.substring (at + 3);
                    int amp = rest.index_of ("&");
                    a.target = amp >= 0 ? rest.substring (0, amp) : rest;
                }
                return a;
            }
            if (act.has_prefix ("ppaction://media")) {
                a.kind = ActionKind.PLAY_MEDIA;
                return a;
            }
            return null;
        }

        public string describe (Presentation? p) {
            switch (kind) {
                case ActionKind.SLIDE:
                    if (p != null) {
                        for (int i = 0; i < p.slides.size; i++) {
                            if (p.slides[i].uid == slide_uid) {
                                string t = p.slides[i].title ();
                                return t != "" ? _("Slide %d: %s").printf (i + 1, t) : _("Slide %d").printf (i + 1);
                            }
                        }
                    }
                    return _("Slide");
                case ActionKind.URL:
                case ActionKind.FILE:
                case ActionKind.PROGRAM:
                case ActionKind.CUSTOM_SHOW:
                    return target;
                default:
                    return kind.label ();
            }
        }
    }

    public class LinkTarget {
        public const string NEXT = "#next";
        public const string PREVIOUS = "#previous";
        public const string FIRST = "#first";
        public const string LAST = "#last";
        public const string END = "#end";
        public const string SLIDE_PREFIX = "#slide:";

        public static bool is_internal (string link) {
            return link.has_prefix ("#");
        }

        public static string for_slide (int uid) {
            return SLIDE_PREFIX + uid.to_string ();
        }

        public static int slide_uid (string link) {
            if (!link.has_prefix (SLIDE_PREFIX)) return 0;
            return int.parse (link.substring (SLIDE_PREFIX.length));
        }

        public static ClickAction? to_action (string link) {
            if (link == "") return null;
            var a = new ClickAction ();
            switch (link) {
                case NEXT: a.kind = ActionKind.NEXT_SLIDE; break;
                case PREVIOUS: a.kind = ActionKind.PREVIOUS_SLIDE; break;
                case FIRST: a.kind = ActionKind.FIRST_SLIDE; break;
                case LAST: a.kind = ActionKind.LAST_SLIDE; break;
                case END: a.kind = ActionKind.END_SHOW; break;
                default:
                    if (link.has_prefix (SLIDE_PREFIX)) {
                        a.kind = ActionKind.SLIDE;
                        a.slide_uid = slide_uid (link);
                    } else {
                        a.kind = ActionKind.URL;
                        a.target = link;
                    }
                    break;
            }
            return a;
        }

        public static string from_action (ClickAction a) {
            switch (a.kind) {
                case ActionKind.NEXT_SLIDE: return NEXT;
                case ActionKind.PREVIOUS_SLIDE: return PREVIOUS;
                case ActionKind.FIRST_SLIDE: return FIRST;
                case ActionKind.LAST_SLIDE: return LAST;
                case ActionKind.END_SHOW: return END;
                case ActionKind.SLIDE: return for_slide (a.slide_uid);
                default: return a.target;
            }
        }
    }
}
