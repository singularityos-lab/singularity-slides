using Gtk;
using Singularity.Widgets;

namespace Singularity.Apps.Slides {

    public class ShapeCatalog {
        public static string[] categories () {
            return { _("Lines"), _("Rectangles"), _("Basic Shapes"), _("Block Arrows"), _("Equation Shapes"), _("Flowchart"), _("Stars and Banners"), _("Callouts"), _("Action Buttons") };
        }

        public static string[] shapes (int category) {
            switch (category) {
                case 0: return { "line", "straightConnector1", "bentConnector3", "curvedConnector3" };
                case 1: return { "rect", "roundRect", "snip1Rect", "snip2SameRect", "snip2DiagRect", "snipRoundRect", "round1Rect", "round2SameRect", "round2DiagRect" };
                case 2: return { "ellipse", "triangle", "rtTriangle", "parallelogram", "trapezoid", "diamond", "pentagon", "hexagon", "heptagon", "octagon", "decagon", "dodecagon",
                    "pie", "chord", "teardrop", "frame", "halfFrame", "corner", "diagStripe", "plus", "plaque", "can", "cube", "bevel", "donut", "noSmoking", "blockArc",
                    "foldedCorner", "smileyFace", "heart", "lightningBolt", "sun", "moon", "cloud", "arc", "bracketPair", "bracePair", "leftBracket", "rightBracket", "leftBrace", "rightBrace",
                    "pieWedge", "funnel", "gear6", "gear9", "chartX", "chartStar", "chartPlus", "squareTabs", "plaqueTabs", "cornerTabs", "nonIsoscelesTrapezoid" };
                case 3: return { "rightArrow", "leftArrow", "upArrow", "downArrow", "leftRightArrow", "upDownArrow", "quadArrow", "leftRightUpArrow", "bentArrow", "uturnArrow",
                    "leftUpArrow", "bentUpArrow", "curvedRightArrow", "curvedLeftArrow", "curvedUpArrow", "curvedDownArrow", "stripedRightArrow", "notchedRightArrow", "homePlate",
                    "chevron", "rightArrowCallout", "downArrowCallout", "leftArrowCallout", "upArrowCallout", "leftRightArrowCallout", "quadArrowCallout", "circularArrow",
                    "leftCircularArrow", "leftRightCircularArrow", "swooshArrow", "upDownArrowCallout" };
                case 4: return { "mathPlus", "mathMinus", "mathMultiply", "mathDivide", "mathEqual", "mathNotEqual" };
                case 5: return { "flowChartProcess", "flowChartAlternateProcess", "flowChartDecision", "flowChartInputOutput", "flowChartPredefinedProcess", "flowChartInternalStorage",
                    "flowChartDocument", "flowChartMultidocument", "flowChartTerminator", "flowChartPreparation", "flowChartManualInput", "flowChartManualOperation",
                    "flowChartConnector", "flowChartOffpageConnector", "flowChartPunchedCard", "flowChartPunchedTape", "flowChartSummingJunction", "flowChartOr",
                    "flowChartCollate", "flowChartSort", "flowChartExtract", "flowChartMerge", "flowChartOnlineStorage", "flowChartDelay", "flowChartMagneticTape",
                    "flowChartMagneticDisk", "flowChartMagneticDrum", "flowChartDisplay", "flowChartOfflineStorage" };
                case 6: return { "irregularSeal1", "irregularSeal2", "star4", "star5", "star6", "star7", "star8", "star10", "star12", "star16", "star24", "star32",
                    "ribbon2", "ribbon", "ellipseRibbon2", "ellipseRibbon", "verticalScroll", "horizontalScroll", "wave", "doubleWave", "leftRightRibbon" };
                case 7: return { "wedgeRectCallout", "wedgeRoundRectCallout", "wedgeEllipseCallout", "cloudCallout", "borderCallout1", "borderCallout2", "borderCallout3",
                    "accentCallout1", "accentCallout2", "accentCallout3", "callout1", "callout2", "callout3", "accentBorderCallout1", "accentBorderCallout2", "accentBorderCallout3" };
                default: return { "actionButtonBackPrevious", "actionButtonForwardNext", "actionButtonBeginning", "actionButtonEnd", "actionButtonHome", "actionButtonInformation",
                    "actionButtonReturn", "actionButtonMovie", "actionButtonDocument", "actionButtonSound", "actionButtonHelp", "actionButtonBlank" };
            }
        }

        public static ClickAction? default_action (string preset) {
            switch (preset) {
                case "actionButtonBackPrevious": return new ClickAction (ActionKind.PREVIOUS_SLIDE);
                case "actionButtonForwardNext": return new ClickAction (ActionKind.NEXT_SLIDE);
                case "actionButtonBeginning": case "actionButtonHome": return new ClickAction (ActionKind.FIRST_SLIDE);
                case "actionButtonEnd": return new ClickAction (ActionKind.LAST_SLIDE);
                case "actionButtonReturn": return new ClickAction (ActionKind.LAST_VIEWED);
                case "actionButtonMovie": case "actionButtonSound": return new ClickAction (ActionKind.PLAY_MEDIA);
                default: return null;
            }
        }

        public static void draw_icon (Cairo.Context cr, string preset, double w, double h, Gdk.RGBA fg) {
            double pad = 3;
            double bw = w - pad * 2, bh = h - pad * 2;
            if (preset.has_prefix ("line") || preset.contains ("Connector")) bh = bw * 0.6;
            double x = pad, y = pad + (h - pad * 2 - bh) / 2;
            cr.set_line_width (1.2);
            cr.set_line_join (Cairo.LineJoin.ROUND);
            var sink = new CairoSink (cr);
            PresetGeometry.build_each (preset, x, y, bw, bh, null, sink, (info) => {
                if (info.fill && info.fill_mode != "none") {
                    cr.set_source_rgba (fg.red, fg.green, fg.blue, info.fill_mode.has_prefix ("darken") ? 0.45 : (info.fill_mode.has_prefix ("lighten") ? 0.12 : 0.22));
                    cr.set_fill_rule (Cairo.FillRule.EVEN_ODD);
                    cr.fill_preserve ();
                }
                if (info.stroke) {
                    cr.set_source_rgba (fg.red, fg.green, fg.blue, 0.9);
                    cr.stroke_preserve ();
                }
                cr.new_path ();
            });
        }
    }

    public class Galleries {
        public delegate void PresetChosen (string preset);
        public delegate void LayoutChosen (DiagramLayout layout);
        public delegate void IconChosen (Bytes svg, string name);

        public static Button shape_button (string preset, owned PresetChosen chosen) {
            var b = new Button ();
            b.add_css_class ("flat");
            b.tooltip_text = PresetLabels.label (preset);
            var da = new DrawingArea ();
            da.set_size_request (30, 26);
            da.set_draw_func ((d, cr, w, h) => ShapeCatalog.draw_icon (cr, preset, w, h, d.get_color ()));
            b.child = da;
            b.clicked.connect (() => chosen (preset));
            return b;
        }

        public static void shapes (SlidesWindow win, string title, owned PresetChosen chosen) {
            var dlg = Dialogs.make (win, title, 520, 720);
            var box = Dialogs.body (dlg);
            var cats = ShapeCatalog.categories ();
            for (int c = 0; c < cats.length; c++) {
                var g = new PreferencesGroup (cats[c]);
                var flow = new FlowBox ();
                flow.selection_mode = SelectionMode.NONE;
                flow.max_children_per_line = 12;
                flow.min_children_per_line = 6;
                flow.column_spacing = 2;
                flow.row_spacing = 2;
                flow.margin_top = 6;
                flow.margin_bottom = 6;
                flow.margin_start = 6;
                flow.margin_end = 6;
                foreach (string p in ShapeCatalog.shapes (c)) {
                    if (!PresetGeometry.has (p)) continue;
                    flow.append (shape_button (p, (name) => {
                        dlg.close ();
                        chosen (name);
                    }));
                }
                g.add_row (flow);
                box.append (g);
            }
            var bar = new Box (Orientation.HORIZONTAL, 8);
            bar.margin_start = bar.margin_end = 18;
            bar.margin_bottom = 16;
            var spacer = new Box (Orientation.HORIZONTAL, 0);
            spacer.hexpand = true;
            bar.append (spacer);
            bar.append (dlg.add_cancel_button ());
            dlg.content_box.append (bar);
            dlg.open_dialog ();
        }

        public static Cairo.ImageSurface diagram_preview (Presentation pres, DiagramLayout layout, int w, int h) {
            var d = new DiagramElement ();
            d.layout = layout;
            d.set_geometry (8, 8, w * 3 - 16, h * 3 - 16);
            d.sample (4);
            if (layout.category () == DiagramCategory.HIERARCHY) d.nodes[0].children[0].children.add (new DiagramNode (_("Text")));
            else if (layout.category () != DiagramCategory.CYCLE) d.nodes[0].children.add (new DiagramNode (_("Text")));
            var surf = new Cairo.ImageSurface (Cairo.Format.ARGB32, w, h);
            var cr = new Cairo.Context (surf);
            cr.scale (1.0 / 3, 1.0 / 3);
            var slide = new Slide ();
            if (pres.slides.size > 0) slide.layout_id = pres.slides[0].layout_id;
            var ctx = new RenderContext (pres, slide, pres.layout_for (slide), pres.master_for (slide));
            var r = new Renderer ();
            foreach (var e in d.build ()) r.draw_element (cr, ctx, e, true);
            return surf;
        }

        public static void smartart (SlidesWindow win, owned LayoutChosen chosen) {
            var dlg = Dialogs.make (win, _("Choose a SmartArt Graphic"), 720, 720);
            var box = Dialogs.body (dlg);
            foreach (var cat in DiagramCategory.ALL) {
                var g = new PreferencesGroup (cat.label ());
                var flow = new FlowBox ();
                flow.selection_mode = SelectionMode.NONE;
                flow.max_children_per_line = 5;
                flow.min_children_per_line = 3;
                flow.column_spacing = 8;
                flow.row_spacing = 8;
                flow.margin_top = 8;
                flow.margin_bottom = 8;
                flow.margin_start = 8;
                flow.margin_end = 8;
                foreach (var l in DiagramLayout.ALL) {
                    if (l.category () != cat) continue;
                    var ll = l;
                    var b = new Button ();
                    b.add_css_class ("flat");
                    var v = new Box (Orientation.VERTICAL, 4);
                    var pic = new Picture.for_paintable (ThumbCache.texture_of (diagram_preview (win.doc.pres, l, 150, 100)));
                    pic.set_size_request (150, 100);
                    pic.can_shrink = false;
                    v.append (pic);
                    var lbl = new Label (l.label ());
                    lbl.wrap = true;
                    lbl.max_width_chars = 18;
                    lbl.justify = Justification.CENTER;
                    v.append (lbl);
                    b.child = v;
                    b.clicked.connect (() => {
                        dlg.close ();
                        chosen (ll);
                    });
                    flow.append (b);
                }
                g.add_row (flow);
                box.append (g);
            }
            var bar = new Box (Orientation.HORIZONTAL, 8);
            bar.margin_start = bar.margin_end = 18;
            bar.margin_bottom = 16;
            var spacer = new Box (Orientation.HORIZONTAL, 0);
            spacer.hexpand = true;
            bar.append (spacer);
            bar.append (dlg.add_cancel_button ());
            dlg.content_box.append (bar);
            dlg.open_dialog ();
        }

        public static void icons (SlidesWindow win, owned IconChosen chosen) {
            var dlg = Dialogs.make (win, _("Insert Icons"), 640, 720);
            var box = Dialogs.body (dlg);
            var search = new Gtk.SearchEntry ();
            search.placeholder_text = _("Search icons");
            search.margin_top = 6;
            box.append (search);
            var g = new PreferencesGroup (_("Icons"), _("Scalable pictures you can recolour after inserting"));
            var flow = new FlowBox ();
            flow.selection_mode = SelectionMode.NONE;
            flow.max_children_per_line = 10;
            flow.min_children_per_line = 5;
            flow.column_spacing = 4;
            flow.row_spacing = 4;
            flow.margin_top = 8;
            flow.margin_bottom = 8;
            flow.margin_start = 8;
            flow.margin_end = 8;
            g.add_row (flow);
            box.append (g);
            var theme = IconTheme.get_for_display (win.get_display ());
            var names = new Gee.ArrayList<string> ();
            foreach (string n in theme.get_icon_names ()) if (n.has_suffix ("-symbolic")) names.add (n);
            names.sort ();
            int shown = 0;
            Gee.ArrayList<string> filtered = names;
            ChooseAny fill = () => {
                Widget? child;
                while ((child = flow.get_first_child ()) != null) flow.remove (child);
                string q = search.text.down ().strip ();
                shown = 0;
                foreach (string n in filtered) {
                    if (q != "" && !n.contains (q)) continue;
                    if (shown++ >= 240) break;
                    var b = new Button.from_icon_name (n);
                    b.add_css_class ("flat");
                    b.tooltip_text = n.replace ("-symbolic", "").replace ("-", " ");
                    string nn = n;
                    b.clicked.connect (() => {
                        var paintable = theme.lookup_icon (nn, null, 256, 1, TextDirection.NONE, 0);
                        var f = paintable.get_file ();
                        if (f == null || f.get_path () == null) return;
                        try {
                            uint8[] data;
                            FileUtils.get_data (f.get_path (), out data);
                            dlg.close ();
                            chosen (new Bytes (data), nn.replace ("-symbolic", ""));
                        } catch (Error e) {
                            warning ("icon: %s", e.message);
                        }
                    });
                    flow.append (b);
                }
            };
            search.search_changed.connect (() => fill ());
            fill ();
            var bar = new Box (Orientation.HORIZONTAL, 8);
            bar.margin_start = bar.margin_end = 18;
            bar.margin_bottom = 16;
            var spacer = new Box (Orientation.HORIZONTAL, 0);
            spacer.hexpand = true;
            bar.append (spacer);
            bar.append (dlg.add_cancel_button ());
            dlg.content_box.append (bar);
            dlg.open_dialog ();
        }

        public delegate void ChooseAny ();

        public delegate void ImageChosen (Bytes data, string mime, string name);

        private static void scan_images (string dir, int depth, Gee.List<string> into) {
            if (depth < 0 || into.size > 400) return;
            try {
                var d = Dir.open (dir);
                string? n;
                while ((n = d.read_name ()) != null) {
                    string p = Path.build_filename (dir, n);
                    if (FileUtils.test (p, FileTest.IS_DIR)) {
                        scan_images (p, depth - 1, into);
                        continue;
                    }
                    string low = n.down ();
                    if (low.has_suffix (".png") || low.has_suffix (".jpg") || low.has_suffix (".jpeg") || low.has_suffix (".webp") || low.has_suffix (".svg")) into.add (p);
                }
            } catch (FileError e) {
            }
        }

        public static Gee.ArrayList<string> stock_images () {
            var list = new Gee.ArrayList<string> ();
            var dirs = new Gee.ArrayList<string> ();
            dirs.add (Path.build_filename (Environment.get_user_data_dir (), "backgrounds"));
            foreach (string d in Environment.get_system_data_dirs ()) dirs.add (Path.build_filename (d, "backgrounds"));
            foreach (string d in dirs) scan_images (d, 2, list);
            return list;
        }

        public static void stock (SlidesWindow win, owned ImageChosen chosen) {
            var dlg = Dialogs.make (win, _("Stock Images"), 700, 720);
            var box = Dialogs.body (dlg);
            var search = new Gtk.SearchEntry ();
            search.placeholder_text = _("Search images");
            search.margin_top = 6;
            box.append (search);
            var files = stock_images ();
            var g = new PreferencesGroup (_("Images"), _("Photographs and artwork installed on this computer, free to use in presentations"));
            box.append (g);
            if (files.size == 0) {
                var sp = new StatusPage ();
                sp.icon_name = "image-x-generic-symbolic";
                sp.title = _("No Stock Images Installed");
                sp.description = _("Install a wallpaper collection to use its images here");
                g.add_row (sp);
                dlg.open_dialog ();
                return;
            }
            var flow = new FlowBox ();
            flow.selection_mode = SelectionMode.NONE;
            flow.max_children_per_line = 4;
            flow.min_children_per_line = 3;
            flow.column_spacing = 8;
            flow.row_spacing = 8;
            flow.margin_top = flow.margin_bottom = flow.margin_start = flow.margin_end = 8;
            g.add_row (flow);
            ChooseAny fill = () => {
                Widget? child;
                while ((child = flow.get_first_child ()) != null) flow.remove (child);
                string q = search.text.down ().strip ();
                int shown = 0;
                foreach (string f in files) {
                    string name = Path.get_basename (f);
                    if (q != "" && !f.down ().contains (q)) continue;
                    if (shown++ >= 120) break;
                    var b = new Button ();
                    b.add_css_class ("flat");
                    var pic = new Picture ();
                    pic.can_shrink = true;
                    pic.content_fit = ContentFit.COVER;
                    pic.set_size_request (150, 90);
                    try {
                        var pb = new Gdk.Pixbuf.from_file_at_scale (f, 300, 180, true);
                        pic.paintable = Gdk.Texture.for_pixbuf (pb);
                    } catch (Error e) {
                        continue;
                    }
                    b.child = pic;
                    b.tooltip_text = name;
                    string path = f;
                    b.clicked.connect (() => {
                        try {
                            uint8[] data;
                            FileUtils.get_data (path, out data);
                            string low = path.down ();
                            string mime = low.has_suffix (".png") ? "image/png" : (low.has_suffix (".svg") ? "image/svg+xml" : (low.has_suffix (".webp") ? "image/webp" : "image/jpeg"));
                            dlg.close ();
                            chosen (new Bytes (data), mime, name);
                        } catch (Error e) {
                            warning ("stock: %s", e.message);
                        }
                    });
                    flow.append (b);
                }
            };
            search.search_changed.connect (() => fill ());
            fill ();
            dlg.open_dialog ();
        }
    }
}
