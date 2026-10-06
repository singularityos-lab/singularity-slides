namespace Singularity.Apps.Slides {

    public class ChartBridge {
        public static Singularity.Charts.ChartType engine_type (ChartKind k) {
            switch (k) {
                case ChartKind.BAR: return Singularity.Charts.ChartType.BAR;
                case ChartKind.LINE: return Singularity.Charts.ChartType.LINE;
                case ChartKind.AREA: return Singularity.Charts.ChartType.AREA;
                case ChartKind.PIE: return Singularity.Charts.ChartType.PIE;
                case ChartKind.DOUGHNUT: return Singularity.Charts.ChartType.DOUGHNUT;
                case ChartKind.SCATTER: return Singularity.Charts.ChartType.SCATTER;
                case ChartKind.BUBBLE: return Singularity.Charts.ChartType.BUBBLE;
                case ChartKind.RADAR: return Singularity.Charts.ChartType.RADAR;
                case ChartKind.STOCK: return Singularity.Charts.ChartType.STOCK;
                case ChartKind.HISTOGRAM: return Singularity.Charts.ChartType.HISTOGRAM;
                case ChartKind.PARETO: return Singularity.Charts.ChartType.PARETO;
                case ChartKind.BOX_WHISKER: return Singularity.Charts.ChartType.BOX_WHISKER;
                case ChartKind.WATERFALL: return Singularity.Charts.ChartType.WATERFALL;
                case ChartKind.FUNNEL: return Singularity.Charts.ChartType.FUNNEL;
                case ChartKind.TREEMAP: return Singularity.Charts.ChartType.TREEMAP;
                case ChartKind.SUNBURST: return Singularity.Charts.ChartType.SUNBURST;
                default: return Singularity.Charts.ChartType.COLUMN;
            }
        }

        public static ChartKind kind_of (Singularity.Charts.ChartType t) {
            switch (t) {
                case Singularity.Charts.ChartType.BAR: return ChartKind.BAR;
                case Singularity.Charts.ChartType.LINE: return ChartKind.LINE;
                case Singularity.Charts.ChartType.AREA: return ChartKind.AREA;
                case Singularity.Charts.ChartType.PIE: return ChartKind.PIE;
                case Singularity.Charts.ChartType.DOUGHNUT: return ChartKind.DOUGHNUT;
                case Singularity.Charts.ChartType.SCATTER: return ChartKind.SCATTER;
                case Singularity.Charts.ChartType.BUBBLE: return ChartKind.BUBBLE;
                case Singularity.Charts.ChartType.RADAR: return ChartKind.RADAR;
                case Singularity.Charts.ChartType.STOCK: return ChartKind.STOCK;
                case Singularity.Charts.ChartType.HISTOGRAM: return ChartKind.HISTOGRAM;
                case Singularity.Charts.ChartType.PARETO: return ChartKind.PARETO;
                case Singularity.Charts.ChartType.BOX_WHISKER: return ChartKind.BOX_WHISKER;
                case Singularity.Charts.ChartType.WATERFALL: return ChartKind.WATERFALL;
                case Singularity.Charts.ChartType.FUNNEL: return ChartKind.FUNNEL;
                case Singularity.Charts.ChartType.TREEMAP: return ChartKind.TREEMAP;
                case Singularity.Charts.ChartType.SUNBURST: return ChartKind.SUNBURST;
                default: return ChartKind.COLUMN;
            }
        }

        private static void axis_to (ChartAxis a, Singularity.Charts.Axis b) {
            b.title = a.title;
            b.min = a.min;
            b.max = a.max;
            b.major_unit = a.major > 0 ? a.major : double.NAN;
            b.log_base = a.log_base;
            b.number_format = a.format;
            b.visible = a.visible;
            b.reverse = a.reverse;
        }

        private static void axis_from (Singularity.Charts.Axis b, ChartAxis a) {
            a.title = b.title;
            a.min = b.min;
            a.max = b.max;
            a.major = b.major_unit.is_nan () ? 0 : b.major_unit;
            a.log_base = b.log_base;
            a.format = b.number_format;
            a.visible = b.visible;
            a.reverse = b.reverse;
        }

        public static Singularity.Charts.ChartSpec to_spec (ChartElement ch, Theme? theme) {
            var spec = new Singularity.Charts.ChartSpec ();
            spec.kind = engine_type (ch.chart);
            spec.grouping = ch.grouping == ChartGrouping.STACKED ? Singularity.Charts.Grouping.STACKED : (ch.grouping == ChartGrouping.PERCENT ? Singularity.Charts.Grouping.PERCENT : Singularity.Charts.Grouping.CLUSTERED);
            spec.title = ch.title;
            switch (ch.legend) {
                case LegendPosition.NONE: spec.legend = Singularity.Charts.LegendPosition.NONE; break;
                case LegendPosition.TOP: spec.legend = Singularity.Charts.LegendPosition.TOP; break;
                case LegendPosition.LEFT: spec.legend = Singularity.Charts.LegendPosition.LEFT; break;
                case LegendPosition.BOTTOM: spec.legend = Singularity.Charts.LegendPosition.BOTTOM; break;
                default: spec.legend = Singularity.Charts.LegendPosition.RIGHT; break;
            }
            spec.data_labels = ch.data_labels;
            spec.smooth = ch.smooth;
            spec.filled_radar = ch.chart == ChartKind.RADAR && ch.grouping == ChartGrouping.STACKED;
            axis_to (ch.cat_axis, spec.x_axis);
            axis_to (ch.val_axis, spec.y_axis);
            axis_to (ch.sec_axis, spec.y2_axis);
            spec.y_axis.gridlines = ch.gridlines;
            string[] cats = {};
            foreach (string c in ch.categories) cats += c;
            spec.categories = cats;
            for (int i = 0; i < ch.series.size; i++) {
                var s = ch.series[i];
                var es = new Singularity.Charts.Series ();
                es.name = s.name;
                double[] vals = {};
                foreach (var v in s.values) vals += v != null ? v : double.NAN;
                es.values = vals;
                es.categories = cats;
                double[] sz = {};
                foreach (var v in s.sizes) sz += v != null ? v : double.NAN;
                es.sizes = sz;
                if (ch.chart == ChartKind.SCATTER || ch.chart == ChartKind.BUBBLE) {
                    double[] xs = {};
                    foreach (string c in cats) xs += double.parse (c);
                    es.xvalues = xs;
                }
                if (s.color != "" && theme != null) es.color = theme.resolve (s.color).to_hex ();
                else if (theme != null && !ch.chart.uses_engine ()) es.color = theme.resolve (ChartPainter.series_color (ch, i)).to_hex ();
                es.secondary = s.secondary;
                if (s.kind != SeriesKind.AUTO) {
                    es.has_type = true;
                    es.kind = s.kind == SeriesKind.LINE ? Singularity.Charts.ChartType.LINE : (s.kind == SeriesKind.AREA ? Singularity.Charts.ChartType.AREA : Singularity.Charts.ChartType.COLUMN);
                }
                if (s.trend != TrendKind.NONE) {
                    var t = new Singularity.Charts.Trendline ();
                    t.kind = Singularity.Charts.TrendType.from_id (s.trend.to_ooxml ());
                    t.order = s.trend_order;
                    t.period = s.trend_period;
                    t.show_equation = s.trend_equation;
                    t.show_r2 = s.trend_r2;
                    es.trendline = t;
                }
                spec.series.add (es);
            }
            return spec;
        }

        public static ChartElement from_spec (Singularity.Charts.ChartSpec spec) {
            var ch = new ChartElement (kind_of (spec.kind));
            ch.grouping = spec.grouping == Singularity.Charts.Grouping.STACKED ? ChartGrouping.STACKED : (spec.grouping == Singularity.Charts.Grouping.PERCENT ? ChartGrouping.PERCENT : ChartGrouping.CLUSTERED);
            if (spec.filled_radar) ch.grouping = ChartGrouping.STACKED;
            ch.title = spec.title;
            switch (spec.legend) {
                case Singularity.Charts.LegendPosition.NONE: ch.legend = LegendPosition.NONE; break;
                case Singularity.Charts.LegendPosition.TOP: ch.legend = LegendPosition.TOP; break;
                case Singularity.Charts.LegendPosition.LEFT: ch.legend = LegendPosition.LEFT; break;
                case Singularity.Charts.LegendPosition.BOTTOM: ch.legend = LegendPosition.BOTTOM; break;
                default: ch.legend = LegendPosition.RIGHT; break;
            }
            ch.data_labels = spec.data_labels;
            ch.smooth = spec.smooth;
            ch.gridlines = spec.y_axis.gridlines;
            axis_from (spec.x_axis, ch.cat_axis);
            axis_from (spec.y_axis, ch.val_axis);
            axis_from (spec.y2_axis, ch.sec_axis);
            foreach (string c in spec.category_labels ()) ch.categories.add (c);
            foreach (var es in spec.series) {
                var s = new ChartSeries (es.name);
                foreach (double v in es.values) s.values.add (v.is_nan () ? null : (double?) v);
                foreach (double v in es.sizes) s.sizes.add (v.is_nan () ? null : (double?) v);
                s.color = es.color;
                s.secondary = es.secondary;
                if (es.has_type && es.kind != spec.kind) {
                    if (es.kind == Singularity.Charts.ChartType.LINE) s.kind = SeriesKind.LINE;
                    else if (es.kind == Singularity.Charts.ChartType.AREA) s.kind = SeriesKind.AREA;
                    else if (es.kind == Singularity.Charts.ChartType.COLUMN) s.kind = SeriesKind.COLUMN;
                }
                if (es.trendline != null) {
                    s.trend = TrendKind.from_ooxml (es.trendline.kind.to_id ());
                    s.trend_order = es.trendline.order;
                    s.trend_period = es.trendline.period;
                    s.trend_equation = es.trendline.show_equation;
                    s.trend_r2 = es.trendline.show_r2;
                }
                ch.series.add (s);
            }
            return ch;
        }

        public static void draw (Cairo.Context cr, RenderContext ctx, ChartElement ch, double x, double y, double w, double h) {
            var spec = to_spec (ch, ctx.theme);
            var painter = new Singularity.Charts.ChartPainter ();
            painter.dark = ctx.dark;
            painter.frame = false;
            painter.font_family = ctx.theme.minor_font;
            painter.font_scale = ((h * 0.05).clamp (8, 24)) / 12.0;
            painter.set_formatter ((v, fmt) => {
                string f = ch.val_axis.format != "" ? ch.val_axis.format : fmt;
                var a = new ChartAxis ();
                a.format = f;
                string r = a.format_value (v);
                return r != "" ? r : ChartPainter.format_value (v);
            });
            cr.save ();
            cr.translate (x, y);
            painter.draw (cr, spec, w, h);
            cr.restore ();
        }
    }
}
