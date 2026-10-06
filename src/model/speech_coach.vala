namespace Singularity.Apps.Slides {

    public class CoachSlide {
        public int index;
        public double seconds;
        public string transcript = "";
        public int words;
        public double wpm;
        public int fillers;
        public double read_ratio;
    }

    public class CoachReport {
        public Gee.ArrayList<CoachSlide> slides = new Gee.ArrayList<CoachSlide> ();
        public double seconds;
        public int words;
        public double wpm;
        public Gee.TreeMap<string, int> fillers = new Gee.TreeMap<string, int> ();
        public Gee.ArrayList<string> repeated = new Gee.ArrayList<string> ();
        public double read_ratio;

        public string pace_label () {
            if (words == 0) return _("No speech was recognised");
            if (wpm < 100) return _("A little slow: try to keep a livelier pace");
            if (wpm > 165) return _("Fast: slow down so the audience can follow");
            return _("Good pace");
        }
    }

    public class SpeechCoach {
        public const string[] FILLERS = {
            "um", "uh", "erm", "er", "ah", "like", "basically", "actually", "literally", "you know", "i mean", "sort of", "kind of", "okay so",
            "ehm", "eh", "cioè", "tipo", "allora", "praticamente", "diciamo", "insomma", "ecco", "comunque"
        };

        public static string[] words_of (string text) {
            var list = new Gee.ArrayList<string> ();
            var sb = new StringBuilder ();
            unichar c;
            int i = 0;
            string low = text.down ();
            while (low.get_next_char (ref i, out c)) {
                if (c.isalnum () || c == '\'') {
                    sb.append_unichar (c);
                } else if (sb.len > 0) {
                    list.add (sb.str);
                    sb.truncate (0);
                }
            }
            if (sb.len > 0) list.add (sb.str);
            return list.to_array ();
        }

        public static int count_phrase (string[] w, string phrase) {
            string[] p = phrase.split (" ");
            int n = 0;
            for (int i = 0; i + p.length <= w.length; i++) {
                bool ok = true;
                for (int k = 0; k < p.length && ok; k++) if (w[i + k] != p[k]) ok = false;
                if (ok) n++;
            }
            return n;
        }

        public static double read_ratio (string[] spoken, string[] slide) {
            if (spoken.length == 0 || slide.length == 0) return 0;
            var grams = new Gee.HashSet<string> ();
            for (int i = 0; i + 4 <= slide.length; i++) grams.add ("%s %s %s %s".printf (slide[i], slide[i + 1], slide[i + 2], slide[i + 3]));
            if (grams.size == 0) return 0;
            var covered = new bool[spoken.length];
            for (int i = 0; i + 4 <= spoken.length; i++) {
                if (grams.contains ("%s %s %s %s".printf (spoken[i], spoken[i + 1], spoken[i + 2], spoken[i + 3]))) for (int k = 0; k < 4; k++) covered[i + k] = true;
            }
            int n = 0;
            foreach (bool b in covered) if (b) n++;
            return n / (double) spoken.length;
        }

        public static string slide_text (Slide s) {
            var sb = new StringBuilder ();
            foreach (var e in s.elements) {
                var body = e.text_body ();
                if (body == null) continue;
                sb.append (body.plain_text ());
                sb.append (" ");
            }
            return sb.str;
        }

        public static CoachReport analyse (Presentation p, Gee.List<int> slide_order, Gee.List<double?> seconds, Gee.List<string> transcripts) {
            var r = new CoachReport ();
            var all = new Gee.ArrayList<string> ();
            int spoken_read = 0, spoken_total = 0;
            for (int i = 0; i < transcripts.size; i++) {
                var cs = new CoachSlide ();
                cs.index = i < slide_order.size ? slide_order[i] : i;
                cs.seconds = i < seconds.size ? seconds[i] : 0;
                cs.transcript = transcripts[i];
                var w = words_of (cs.transcript);
                cs.words = w.length;
                cs.wpm = cs.seconds > 0 ? cs.words / (cs.seconds / 60.0) : 0;
                foreach (string f in FILLERS) {
                    int n = count_phrase (w, f);
                    if (n == 0) continue;
                    if (f == "like" || f == "so" || f == "comunque" || f == "ecco") n = n / 2;
                    if (n == 0) continue;
                    cs.fillers += n;
                    r.fillers[f] = (r.fillers.has_key (f) ? r.fillers[f] : 0) + n;
                }
                if (cs.index >= 0 && cs.index < p.slides.size) cs.read_ratio = read_ratio (w, words_of (slide_text (p.slides[cs.index])));
                spoken_read += (int) Math.round (cs.read_ratio * w.length);
                spoken_total += w.length;
                foreach (string x in w) all.add (x);
                r.slides.add (cs);
                r.seconds += cs.seconds;
                r.words += cs.words;
            }
            r.wpm = r.seconds > 0 ? r.words / (r.seconds / 60.0) : 0;
            r.read_ratio = spoken_total > 0 ? spoken_read / (double) spoken_total : 0;
            var counts = new Gee.HashMap<string, int> ();
            for (int i = 0; i + 3 <= all.size; i++) {
                string g = "%s %s %s".printf (all[i], all[i + 1], all[i + 2]);
                counts[g] = (counts.has_key (g) ? counts[g] : 0) + 1;
            }
            foreach (var e in counts.entries) if (e.value >= 3) r.repeated.add ("%s (%d)".printf (e.key, e.value));
            r.repeated.sort ();
            return r;
        }
    }
}
