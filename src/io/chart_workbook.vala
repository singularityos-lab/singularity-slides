namespace Singularity.Apps.Slides {

    public class ChartWorkbook {
        public static string col_name (int i) {
            var sb = new StringBuilder ();
            int n = i + 1;
            while (n > 0) {
                int m = (n - 1) % 26;
                sb.prepend_c ((char) ('A' + m));
                n = (n - 1) / 26;
            }
            return sb.str;
        }

        public static string full (double v) {
            return "%.15g".printf (v).replace (",", ".");
        }

        private static void text_cell (XmlOut x, string r, string v) {
            x.start ("c").a ("r", r).a ("t", "inlineStr").start ("is").start ("t").a ("xml:space", "preserve").text (v).end ().end ().end ();
        }

        private static void cat_cell (XmlOut x, string r, string v) {
            double d = 0;
            if (v != "" && double.try_parse (v, out d)) x.start ("c").a ("r", r).element ("v", full (d)).end ();
            else text_cell (x, r, v);
        }

        public static uint8[] build (ChartElement ch) throws Error {
            int ncat = ch.categories.size;
            foreach (var s in ch.series) ncat = int.max (ncat, s.values.size);
            bool bubble = ch.chart == ChartKind.BUBBLE;
            int cols = 1 + ch.series.size * (bubble ? 2 : 1);
            var x = new XmlOut ();
            x.start ("worksheet").a ("xmlns", "http://schemas.openxmlformats.org/spreadsheetml/2006/main").a ("xmlns:r", Ooxml.NS_R);
            x.start ("dimension").a ("ref", "A1:%s%d".printf (col_name (cols - 1), ncat + 1)).end ();
            x.start ("sheetData");
            x.start ("row").ai ("r", 1);
            text_cell (x, "A1", "");
            for (int i = 0; i < ch.series.size; i++) {
                int c = bubble ? 1 + i * 2 : 1 + i;
                text_cell (x, "%s1".printf (col_name (c)), ch.series[i].name);
                if (bubble) text_cell (x, "%s1".printf (col_name (c + 1)), _("Size"));
            }
            x.end ();
            for (int r = 0; r < ncat; r++) {
                x.start ("row").ai ("r", r + 2);
                cat_cell (x, "A%d".printf (r + 2), r < ch.categories.size ? ch.categories[r] : "");
                for (int i = 0; i < ch.series.size; i++) {
                    var s = ch.series[i];
                    int c = bubble ? 1 + i * 2 : 1 + i;
                    if (r < s.values.size && s.values[r] != null) x.start ("c").a ("r", "%s%d".printf (col_name (c), r + 2)).element ("v", full (s.values[r])).end ();
                    if (bubble && r < s.sizes.size && s.sizes[r] != null) x.start ("c").a ("r", "%s%d".printf (col_name (c + 1), r + 2)).element ("v", full (s.sizes[r])).end ();
                }
                x.end ();
            }
            x.end ();
            x.end ();
            string sheet = "<?xml version=\"1.0\" encoding=\"UTF-8\" standalone=\"yes\"?>" + x.finish ();
            var zip = new ZipWriter ();
            zip.add_text ("[Content_Types].xml", "<?xml version=\"1.0\" encoding=\"UTF-8\" standalone=\"yes\"?><Types xmlns=\"http://schemas.openxmlformats.org/package/2006/content-types\"><Default Extension=\"rels\" ContentType=\"application/vnd.openxmlformats-package.relationships+xml\"/><Default Extension=\"xml\" ContentType=\"application/xml\"/><Override PartName=\"/xl/workbook.xml\" ContentType=\"application/vnd.openxmlformats-officedocument.spreadsheetml.sheet.main+xml\"/><Override PartName=\"/xl/worksheets/sheet1.xml\" ContentType=\"application/vnd.openxmlformats-officedocument.spreadsheetml.worksheet+xml\"/></Types>");
            zip.add_text ("_rels/.rels", "<?xml version=\"1.0\" encoding=\"UTF-8\" standalone=\"yes\"?><Relationships xmlns=\"http://schemas.openxmlformats.org/package/2006/relationships\"><Relationship Id=\"rId1\" Type=\"http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument\" Target=\"xl/workbook.xml\"/></Relationships>");
            zip.add_text ("xl/workbook.xml", "<?xml version=\"1.0\" encoding=\"UTF-8\" standalone=\"yes\"?><workbook xmlns=\"http://schemas.openxmlformats.org/spreadsheetml/2006/main\" xmlns:r=\"http://schemas.openxmlformats.org/officeDocument/2006/relationships\"><sheets><sheet name=\"Sheet1\" sheetId=\"1\" r:id=\"rId1\"/></sheets></workbook>");
            zip.add_text ("xl/_rels/workbook.xml.rels", "<?xml version=\"1.0\" encoding=\"UTF-8\" standalone=\"yes\"?><Relationships xmlns=\"http://schemas.openxmlformats.org/package/2006/relationships\"><Relationship Id=\"rId1\" Type=\"http://schemas.openxmlformats.org/officeDocument/2006/relationships/worksheet\" Target=\"worksheets/sheet1.xml\"/></Relationships>");
            zip.add_text ("xl/worksheets/sheet1.xml", sheet);
            return zip.finish ();
        }
    }
}
