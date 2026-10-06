namespace Singularity.Apps.Slides {

    public enum TextAlign {
        INHERIT,
        LEFT,
        CENTER,
        RIGHT,
        JUSTIFY
    }

    public enum TextAnchor {
        TOP,
        MIDDLE,
        BOTTOM
    }

    public enum AutoFit {
        NONE,
        SHRINK,
        RESIZE
    }

    public enum BulletKind {
        INHERIT,
        NONE,
        CHAR,
        NUMBER
    }

    public enum NumberStyle {
        ARABIC_PERIOD,
        ARABIC_PAREN,
        ALPHA_LOWER,
        ALPHA_UPPER,
        ROMAN_LOWER,
        ROMAN_UPPER;

        public string to_ooxml () {
            switch (this) {
                case ARABIC_PAREN: return "arabicParenR";
                case ALPHA_LOWER: return "alphaLcPeriod";
                case ALPHA_UPPER: return "alphaUcPeriod";
                case ROMAN_LOWER: return "romanLcPeriod";
                case ROMAN_UPPER: return "romanUcPeriod";
                default: return "arabicPeriod";
            }
        }

        public static NumberStyle from_ooxml (string s) {
            if (s.has_prefix ("arabicParen")) return ARABIC_PAREN;
            if (s.has_prefix ("alphaLc")) return ALPHA_LOWER;
            if (s.has_prefix ("alphaUc")) return ALPHA_UPPER;
            if (s.has_prefix ("romanLc")) return ROMAN_LOWER;
            if (s.has_prefix ("romanUc")) return ROMAN_UPPER;
            return ARABIC_PERIOD;
        }

        private static string roman (int n) {
            int[] vals = { 1000, 900, 500, 400, 100, 90, 50, 40, 10, 9, 5, 4, 1 };
            string[] syms = { "m", "cm", "d", "cd", "c", "xc", "l", "xl", "x", "ix", "v", "iv", "i" };
            var sb = new StringBuilder ();
            for (int i = 0; i < vals.length; i++) {
                while (n >= vals[i]) {
                    sb.append (syms[i]);
                    n -= vals[i];
                }
            }
            return sb.str;
        }

        public string label (int n) {
            switch (this) {
                case ARABIC_PAREN: return "%d)".printf (n);
                case ALPHA_LOWER: return "%c.".printf ((char) ('a' + (n - 1) % 26));
                case ALPHA_UPPER: return "%c.".printf ((char) ('A' + (n - 1) % 26));
                case ROMAN_LOWER: return roman (n) + ".";
                case ROMAN_UPPER: return roman (n).up () + ".";
                default: return "%d.".printf (n);
            }
        }
    }

    public class TextRun {
        public string text = "";
        public int bold = -1;
        public int italic = -1;
        public int underline = -1;
        public int strike = -1;
        public double size = 0;
        public string font = "";
        public string color = "";
        public string highlight = "";
        public int baseline = 0;
        public string link = "";
        public string field = "";

        public TextRun (string text = "") {
            this.text = text;
        }

        public TextRun clone () {
            var r = new TextRun (text);
            r.copy_format (this);
            return r;
        }

        public void copy_format (TextRun o) {
            bold = o.bold;
            italic = o.italic;
            underline = o.underline;
            strike = o.strike;
            size = o.size;
            font = o.font;
            color = o.color;
            highlight = o.highlight;
            baseline = o.baseline;
            link = o.link;
            field = o.field;
        }

        public bool same_format (TextRun o) {
            return bold == o.bold && italic == o.italic && underline == o.underline && strike == o.strike
                && size == o.size && font == o.font && color == o.color && highlight == o.highlight
                && baseline == o.baseline && link == o.link && field == "" && o.field == "";
        }
    }

    public class Paragraph {
        public Gee.ArrayList<TextRun> runs = new Gee.ArrayList<TextRun> ();
        public TextAlign align = TextAlign.INHERIT;
        public int level = 0;
        public BulletKind bullet = BulletKind.INHERIT;
        public string bullet_char = "";
        public string bullet_color = "";
        public NumberStyle number_style = NumberStyle.ARABIC_PERIOD;
        public int number_start = 1;
        public double space_before = -1;
        public double space_after = -1;
        public double line_spacing = 0;
        public TextRun end_format = new TextRun ();

        public Paragraph (string text = "") {
            if (text != "") runs.add (new TextRun (text));
        }

        public Paragraph clone () {
            var p = new Paragraph ();
            foreach (var r in runs) p.runs.add (r.clone ());
            p.copy_format (this);
            p.end_format = end_format.clone ();
            return p;
        }

        public void copy_format (Paragraph o) {
            align = o.align;
            level = o.level;
            bullet = o.bullet;
            bullet_char = o.bullet_char;
            bullet_color = o.bullet_color;
            number_style = o.number_style;
            number_start = o.number_start;
            space_before = o.space_before;
            space_after = o.space_after;
            line_spacing = o.line_spacing;
        }

        public string text () {
            var sb = new StringBuilder ();
            foreach (var r in runs) sb.append (r.text);
            return sb.str;
        }

        public void normalize () {
            for (int i = runs.size - 1; i >= 0; i--) {
                if (runs[i].text == "" && runs.size > 1) {
                    runs.remove_at (i);
                    continue;
                }
                if (i > 0 && runs[i - 1].same_format (runs[i])) {
                    runs[i - 1].text += runs[i].text;
                    runs.remove_at (i);
                }
            }
        }
    }

    public class TextBody {
        public Gee.ArrayList<Paragraph> paragraphs = new Gee.ArrayList<Paragraph> ();
        public TextAnchor anchor = TextAnchor.TOP;
        public bool anchor_set = false;
        public double inset_left = 7.2;
        public double inset_top = 3.6;
        public double inset_right = 7.2;
        public double inset_bottom = 3.6;
        public bool wrap = true;
        public AutoFit autofit = AutoFit.NONE;
        public double font_scale = 1;
        public double line_reduction = 0;
        public int columns = 1;
        public bool vertical = false;

        public TextBody () {
        }

        public TextBody.with_text (string text) {
            set_plain (text);
        }

        public TextBody clone () {
            var t = new TextBody ();
            foreach (var p in paragraphs) t.paragraphs.add (p.clone ());
            t.anchor = anchor;
            t.anchor_set = anchor_set;
            t.inset_left = inset_left;
            t.inset_top = inset_top;
            t.inset_right = inset_right;
            t.inset_bottom = inset_bottom;
            t.wrap = wrap;
            t.autofit = autofit;
            t.font_scale = font_scale;
            t.line_reduction = line_reduction;
            t.columns = columns;
            t.vertical = vertical;
            return t;
        }

        public void set_plain (string text) {
            paragraphs.clear ();
            foreach (string line in text.split ("\n")) paragraphs.add (new Paragraph (line));
            if (paragraphs.size == 0) paragraphs.add (new Paragraph ());
        }

        public string plain_text () {
            var sb = new StringBuilder ();
            for (int i = 0; i < paragraphs.size; i++) {
                if (i > 0) sb.append ("\n");
                sb.append (paragraphs[i].text ());
            }
            return sb.str;
        }

        public bool is_empty () {
            foreach (var p in paragraphs) if (p.text () != "") return false;
            return true;
        }

        public void apply_to_runs (RunEdit edit) {
            foreach (var p in paragraphs) {
                foreach (var r in p.runs) edit (r);
                edit (p.end_format);
            }
        }

        public void apply_to_paragraphs (ParagraphEdit edit) {
            foreach (var p in paragraphs) edit (p);
        }

        public int replace_all (string find, string replacement, bool match_case) {
            int count = 0;
            foreach (var p in paragraphs) {
                foreach (var r in p.runs) {
                    int n;
                    r.text = TextBody.replace_in (r.text, find, replacement, match_case, out n);
                    count += n;
                }
            }
            return count;
        }

        public static string replace_in (string text, string find, string replacement, bool match_case, out int count) {
            count = 0;
            if (find == "") return text;
            var sb = new StringBuilder ();
            string hay = match_case ? text : text.casefold ();
            string needle = match_case ? find : find.casefold ();
            if (hay.length != text.length) {
                hay = text;
                needle = find;
            }
            int pos = 0;
            while (true) {
                int i = hay.index_of (needle, pos);
                if (i < 0) break;
                sb.append (text.substring (pos, i - pos));
                sb.append (replacement);
                pos = i + find.length;
                count++;
            }
            sb.append (text.substring (pos));
            return sb.str;
        }

        public void first_run_format (TextRun into) {
            foreach (var p in paragraphs) {
                if (p.runs.size > 0) {
                    into.copy_format (p.runs[0]);
                    return;
                }
            }
            if (paragraphs.size > 0) into.copy_format (paragraphs[0].end_format);
        }
    }

    public delegate void RunEdit (TextRun run);
    public delegate void ParagraphEdit (Paragraph p);

    public class LevelStyle {
        public double size = 0;
        public string font = "";
        public string color = "";
        public int bold = -1;
        public int italic = -1;
        public TextAlign align = TextAlign.INHERIT;
        public BulletKind bullet = BulletKind.INHERIT;
        public string bullet_char = "";
        public double margin = -1;
        public double indent = 0;
        public double space_before = -1;
        public double space_after = -1;
        public double line_spacing = 0;
        public bool caps = false;

        public LevelStyle clone () {
            var l = new LevelStyle ();
            l.size = size;
            l.font = font;
            l.color = color;
            l.bold = bold;
            l.italic = italic;
            l.align = align;
            l.bullet = bullet;
            l.bullet_char = bullet_char;
            l.margin = margin;
            l.indent = indent;
            l.space_before = space_before;
            l.space_after = space_after;
            l.line_spacing = line_spacing;
            l.caps = caps;
            return l;
        }

        public void overlay (LevelStyle o) {
            if (o.size > 0) size = o.size;
            if (o.font != "") font = o.font;
            if (o.color != "") color = o.color;
            if (o.bold >= 0) bold = o.bold;
            if (o.italic >= 0) italic = o.italic;
            if (o.align != TextAlign.INHERIT) align = o.align;
            if (o.bullet != BulletKind.INHERIT) {
                bullet = o.bullet;
                bullet_char = o.bullet_char;
            }
            if (o.margin >= 0) {
                margin = o.margin;
                indent = o.indent;
            }
            if (o.space_before >= 0) space_before = o.space_before;
            if (o.space_after >= 0) space_after = o.space_after;
            if (o.line_spacing > 0) line_spacing = o.line_spacing;
        }

        public bool is_empty () {
            return size <= 0 && font == "" && color == "" && bold < 0 && italic < 0 && align == TextAlign.INHERIT
                && bullet == BulletKind.INHERIT && margin < 0 && space_before < 0 && space_after < 0 && line_spacing <= 0;
        }
    }

    public class TextStyle {
        public LevelStyle[] levels = new LevelStyle[9];

        public TextStyle () {
            for (int i = 0; i < 9; i++) levels[i] = new LevelStyle ();
        }

        public TextStyle clone () {
            var t = new TextStyle ();
            for (int i = 0; i < 9; i++) t.levels[i] = levels[i].clone ();
            return t;
        }

        public LevelStyle level (int i) {
            return levels[i.clamp (0, 8)];
        }

        public bool is_empty () {
            foreach (var l in levels) if (!l.is_empty ()) return false;
            return true;
        }
    }
}
