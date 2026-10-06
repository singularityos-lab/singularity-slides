namespace Singularity.Apps.Slides {

    public enum SeriesKind {
        AUTO,
        COLUMN,
        LINE,
        AREA;

        public string label () {
            switch (this) {
                case COLUMN: return _("Clustered Column");
                case LINE: return _("Line");
                case AREA: return _("Area");
                default: return _("Same as Chart");
            }
        }
    }

    public enum TrendKind {
        NONE,
        LINEAR,
        EXPONENTIAL,
        LOGARITHMIC,
        POLYNOMIAL,
        POWER,
        MOVING_AVERAGE;

        public string label () {
            switch (this) {
                case LINEAR: return _("Linear");
                case EXPONENTIAL: return _("Exponential");
                case LOGARITHMIC: return _("Logarithmic");
                case POLYNOMIAL: return _("Polynomial");
                case POWER: return _("Power");
                case MOVING_AVERAGE: return _("Moving Average");
                default: return _("None");
            }
        }

        public string to_ooxml () {
            switch (this) {
                case EXPONENTIAL: return "exp";
                case LOGARITHMIC: return "log";
                case POLYNOMIAL: return "poly";
                case POWER: return "power";
                case MOVING_AVERAGE: return "movingAvg";
                default: return "linear";
            }
        }

        public static TrendKind from_ooxml (string? s) {
            switch (s) {
                case "exp": return EXPONENTIAL;
                case "log": return LOGARITHMIC;
                case "poly": return POLYNOMIAL;
                case "power": return POWER;
                case "movingAvg": return MOVING_AVERAGE;
                case "linear": return LINEAR;
                default: return NONE;
            }
        }

        public string to_odf () {
            switch (this) {
                case EXPONENTIAL: return "exponential";
                case LOGARITHMIC: return "logarithmic";
                case POLYNOMIAL: return "polynomial";
                case POWER: return "power";
                case MOVING_AVERAGE: return "moving-average";
                default: return "linear";
            }
        }

        public static TrendKind from_odf (string? s) {
            switch (s) {
                case "exponential": return EXPONENTIAL;
                case "logarithmic": return LOGARITHMIC;
                case "polynomial": return POLYNOMIAL;
                case "power": return POWER;
                case "moving-average": return MOVING_AVERAGE;
                case "linear": return LINEAR;
                default: return NONE;
            }
        }
    }

    public class ChartAxis {
        public string title = "";
        public double min = double.NAN;
        public double max = double.NAN;
        public double major = 0;
        public string format = "";
        public double log_base = 0;
        public bool reverse = false;
        public bool visible = true;

        public ChartAxis clone () {
            var a = new ChartAxis ();
            a.title = title;
            a.min = min;
            a.max = max;
            a.major = major;
            a.format = format;
            a.log_base = log_base;
            a.reverse = reverse;
            a.visible = visible;
            return a;
        }

        public string signature () {
            return "|%s|%g|%g|%g|%s|%g|%s|%s".printf (title, min, max, major, format, log_base, reverse.to_string (), visible.to_string ());
        }

        public string format_value (double v) {
            switch (format) {
                case "0%": return "%.0f%%".printf (v * 100);
                case "0.0%": return "%.1f%%".printf (v * 100);
                case "0": return "%.0f".printf (v);
                case "0.0": return "%.1f".printf (v);
                case "0.00": return "%.2f".printf (v);
                case "#,##0": return thousands (v, 0);
                case "#,##0.00": return thousands (v, 2);
                case "\"$\"#,##0": case "$#,##0": return "$" + thousands (v, 0);
                case "#,##0\" €\"": case "#,##0 €": return thousands (v, 0) + " €";
                default: return "";
            }
        }

        private static string thousands (double v, int digits) {
            string s = "%.*f".printf (digits, Math.fabs (v));
            string ip = s, fp = "";
            int dot = s.index_of (".");
            if (dot >= 0) {
                ip = s.substring (0, dot);
                fp = s.substring (dot);
            }
            var sb = new StringBuilder ();
            for (int i = 0; i < ip.length; i++) {
                if (i > 0 && (ip.length - i) % 3 == 0) sb.append_c (',');
                sb.append_c (ip[i]);
            }
            return (v < 0 ? "-" : "") + sb.str + fp;
        }
    }

    public class TrendFit {
        public TrendKind kind;
        public double[] coef = {};
        public double r2 = 0;
        public bool ok = false;
        public int period = 2;

        public double eval (double x) {
            switch (kind) {
                case TrendKind.LINEAR: return coef[0] + coef[1] * x;
                case TrendKind.EXPONENTIAL: return coef[0] * Math.exp (coef[1] * x);
                case TrendKind.LOGARITHMIC: return x > 0 ? coef[0] + coef[1] * Math.log (x) : double.NAN;
                case TrendKind.POWER: return x > 0 ? coef[0] * Math.pow (x, coef[1]) : double.NAN;
                case TrendKind.POLYNOMIAL:
                    double y = 0, p = 1;
                    foreach (double c in coef) {
                        y += c * p;
                        p *= x;
                    }
                    return y;
                default: return double.NAN;
            }
        }

        private static string num (double v) {
            double a = Math.fabs (v);
            string s = a >= 1000 || a < 0.001 && a > 0 ? "%.3e".printf (a) : "%.4g".printf (a);
            return s;
        }

        private static string term (double c, string tail, bool first) {
            string sign = c < 0 ? (first ? "-" : " - ") : (first ? "" : " + ");
            return sign + num (c) + tail;
        }

        public string equation () {
            if (!ok) return "";
            switch (kind) {
                case TrendKind.LINEAR: return "y = " + term (coef[1], "x", true) + term (coef[0], "", false);
                case TrendKind.EXPONENTIAL: return "y = " + num (coef[0]) + "e^(" + (coef[1] < 0 ? "-" : "") + num (coef[1]) + "x)";
                case TrendKind.LOGARITHMIC: return "y = " + term (coef[1], "ln(x)", true) + term (coef[0], "", false);
                case TrendKind.POWER: return "y = " + num (coef[0]) + "x^" + (coef[1] < 0 ? "-" : "") + num (coef[1]);
                case TrendKind.POLYNOMIAL:
                    var sb = new StringBuilder ("y = ");
                    bool first = true;
                    for (int i = coef.length - 1; i >= 0; i--) {
                        string tail = "";
                        if (i == 1) tail = "x";
                        else if (i > 1) tail = "x^%d".printf (i);
                        sb.append (term (coef[i], tail, first));
                        first = false;
                    }
                    return sb.str;
                default: return "";
            }
        }

        public static TrendFit fit (double[] xs, double[] ys, TrendKind kind, int order, int period) {
            var f = new TrendFit ();
            f.kind = kind;
            f.period = int.max (period, 2);
            int n = int.min (xs.length, ys.length);
            if (kind == TrendKind.MOVING_AVERAGE) {
                f.ok = n >= f.period;
                return f;
            }
            var fx = new Gee.ArrayList<double?> ();
            var fy = new Gee.ArrayList<double?> ();
            for (int i = 0; i < n; i++) {
                double x = xs[i], y = ys[i];
                if (x.is_nan () || y.is_nan ()) continue;
                switch (kind) {
                    case TrendKind.EXPONENTIAL:
                        if (y <= 0) continue;
                        fx.add (x);
                        fy.add (Math.log (y));
                        break;
                    case TrendKind.LOGARITHMIC:
                        if (x <= 0) continue;
                        fx.add (Math.log (x));
                        fy.add (y);
                        break;
                    case TrendKind.POWER:
                        if (x <= 0 || y <= 0) continue;
                        fx.add (Math.log (x));
                        fy.add (Math.log (y));
                        break;
                    default:
                        fx.add (x);
                        fy.add (y);
                        break;
                }
            }
            int deg = kind == TrendKind.POLYNOMIAL ? order.clamp (2, 6) : 1;
            if (fx.size <= deg) return f;
            var c = polyfit (fx, fy, deg);
            if (c == null) return f;
            switch (kind) {
                case TrendKind.EXPONENTIAL:
                case TrendKind.POWER:
                    f.coef = { Math.exp (c[0]), c[1] };
                    break;
                default:
                    f.coef = c;
                    break;
            }
            f.ok = true;
            double mean = 0;
            int m = 0;
            for (int i = 0; i < n; i++) {
                if (ys[i].is_nan ()) continue;
                mean += ys[i];
                m++;
            }
            if (m == 0) return f;
            mean /= m;
            double ss_tot = 0, ss_res = 0;
            bool log_space = kind == TrendKind.EXPONENTIAL || kind == TrendKind.POWER;
            double lmean = 0;
            if (log_space) {
                foreach (var v in fy) lmean += v;
                lmean /= fy.size;
                for (int i = 0; i < fx.size; i++) {
                    double pred = c[0] + c[1] * fx[i];
                    ss_res += (fy[i] - pred) * (fy[i] - pred);
                    ss_tot += (fy[i] - lmean) * (fy[i] - lmean);
                }
            } else {
                for (int i = 0; i < n; i++) {
                    if (ys[i].is_nan ()) continue;
                    double pred = f.eval (xs[i]);
                    if (pred.is_nan ()) continue;
                    ss_res += (ys[i] - pred) * (ys[i] - pred);
                    ss_tot += (ys[i] - mean) * (ys[i] - mean);
                }
            }
            f.r2 = ss_tot > 0 ? 1 - ss_res / ss_tot : 1;
            return f;
        }

        private static double[]? polyfit (Gee.List<double?> xs, Gee.List<double?> ys, int deg) {
            int m = deg + 1;
            var a = new double[m * (m + 1)];
            for (int r = 0; r < m; r++) {
                for (int c = 0; c < m; c++) {
                    double s = 0;
                    for (int i = 0; i < xs.size; i++) s += Math.pow (xs[i], r + c);
                    a[r * (m + 1) + c] = s;
                }
                double t = 0;
                for (int i = 0; i < xs.size; i++) t += ys[i] * Math.pow (xs[i], r);
                a[r * (m + 1) + m] = t;
            }
            for (int col = 0; col < m; col++) {
                int piv = col;
                for (int r = col + 1; r < m; r++) if (Math.fabs (a[r * (m + 1) + col]) > Math.fabs (a[piv * (m + 1) + col])) piv = r;
                if (Math.fabs (a[piv * (m + 1) + col]) < 1e-12) return null;
                if (piv != col) {
                    for (int k = 0; k <= m; k++) {
                        double tmp = a[col * (m + 1) + k];
                        a[col * (m + 1) + k] = a[piv * (m + 1) + k];
                        a[piv * (m + 1) + k] = tmp;
                    }
                }
                for (int r = 0; r < m; r++) {
                    if (r == col) continue;
                    double fac = a[r * (m + 1) + col] / a[col * (m + 1) + col];
                    for (int k = col; k <= m; k++) a[r * (m + 1) + k] -= fac * a[col * (m + 1) + k];
                }
            }
            var res = new double[m];
            for (int r = 0; r < m; r++) res[r] = a[r * (m + 1) + m] / a[r * (m + 1) + r];
            return res;
        }

        public static double[] moving_average (double[] ys, int period) {
            var out_v = new double[ys.length];
            for (int i = 0; i < ys.length; i++) {
                if (i + 1 < period) {
                    out_v[i] = double.NAN;
                    continue;
                }
                double s = 0;
                int k = 0;
                for (int j = i - period + 1; j <= i; j++) {
                    if (ys[j].is_nan ()) continue;
                    s += ys[j];
                    k++;
                }
                out_v[i] = k > 0 ? s / k : double.NAN;
            }
            return out_v;
        }
    }
}
