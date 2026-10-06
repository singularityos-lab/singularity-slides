namespace Singularity.Apps.Slides {

    public class FormulaResult {
        public Bytes image;
        public string mime = "image/png";
        public string latex = "";
        public string mathml = "";
        public double width = 0;
        public double height = 0;
    }

    public class FormulaBridge : Object {
        public static bool available () {
            return Singularity.Equations.Equation.editor_available ();
        }

        public static Singularity.Equations.Equation object_for (EquationElement? q) {
            Singularity.Equations.Equation? eq = null;
            if (q != null) {
                if (q.mathml != "") eq = new Singularity.Equations.Equation.from_mathml (q.mathml);
                else if (q.omml != "") eq = Singularity.Equations.Equation.from_omml (q.omml);
                if (eq == null && q.latex != "") eq = new Singularity.Equations.Equation.from_latex (q.latex);
            }
            if (eq == null) eq = new Singularity.Equations.Equation.from_mathml ("<math xmlns=\"http://www.w3.org/1998/Math/MathML\" display=\"block\"><mrow></mrow></math>");
            eq.display = true;
            return eq;
        }

        public static async FormulaResult? edit (Gtk.Window parent, EquationElement? q) {
            var eq = object_for (q);
            bool changed = yield eq.edit (parent);
            if (!changed) return null;
            var result = new FormulaResult ();
            result.mathml = eq.mathml;
            result.latex = eq.latex;
            if (yield eq.render (28, 2)) {
                result.width = eq.width_pt;
                result.height = eq.ascent_pt + eq.descent_pt;
                if (eq.texture != null) result.image = eq.texture.save_to_png_bytes ();
            }
            if (result.image == null) {
                var surf = new Cairo.ImageSurface (Cairo.Format.ARGB32, 2, 2);
                var bytes = new ByteArray ();
                surf.write_to_png_stream ((data) => {
                    bytes.append (data);
                    return Cairo.Status.SUCCESS;
                });
                result.image = ByteArray.free_to_bytes (bytes);
            }
            return result;
        }
    }
}
