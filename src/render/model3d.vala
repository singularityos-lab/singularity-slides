namespace Singularity.Apps.Slides {

    public class Mesh {
        public float[] pos = {};
        public int[] tris = {};
        public float[] tri_color = {};
        public double cx;
        public double cy;
        public double cz;
        public double radius = 1;

        public int triangle_count () {
            return tris.length / 3;
        }

        public void bounds () {
            if (pos.length < 3) return;
            double x0 = double.MAX, y0 = double.MAX, z0 = double.MAX, x1 = -double.MAX, y1 = -double.MAX, z1 = -double.MAX;
            for (int i = 0; i + 2 < pos.length; i += 3) {
                x0 = double.min (x0, pos[i]);
                y0 = double.min (y0, pos[i + 1]);
                z0 = double.min (z0, pos[i + 2]);
                x1 = double.max (x1, pos[i]);
                y1 = double.max (y1, pos[i + 1]);
                z1 = double.max (z1, pos[i + 2]);
            }
            cx = (x0 + x1) / 2;
            cy = (y0 + y1) / 2;
            cz = (z0 + z1) / 2;
            radius = 0;
            for (int i = 0; i + 2 < pos.length; i += 3) {
                double dx = pos[i] - cx, dy = pos[i + 1] - cy, dz = pos[i + 2] - cz;
                radius = double.max (radius, Math.sqrt (dx * dx + dy * dy + dz * dz));
            }
            if (radius <= 0) radius = 1;
        }
    }

    public class MeshBuilder {
        private float[] pos = {};
        private int[] tris = {};
        private float[] col = {};

        public int vertex_count () {
            return pos.length / 3;
        }

        public void vertex (double x, double y, double z) {
            pos += (float) x;
            pos += (float) y;
            pos += (float) z;
        }

        public void triangle (int a, int b, int c, float r, float g, float bl) {
            tris += a;
            tris += b;
            tris += c;
            col += r;
            col += g;
            col += bl;
        }

        public Mesh build () {
            var m = new Mesh ();
            m.pos = pos;
            m.tris = tris;
            m.tri_color = col;
            return m;
        }
    }

    public class MeshLoader {
        private static Gee.HashMap<string, Mesh>? cache = null;

        public static Mesh? load (Bytes data, string format) {
            if (cache == null) cache = new Gee.HashMap<string, Mesh> ();
            string key = "%s:%u:%d".printf (format, data.hash (), (int) data.get_size ());
            if (cache.has_key (key)) return cache[key];
            Mesh? m = null;
            try {
                m = format == "obj" ? load_obj (data) : load_glb (data);
            } catch (Error e) {
                warning ("3d model: %s", e.message);
                return null;
            }
            if (m == null || m.triangle_count () == 0) return null;
            m.bounds ();
            if (cache.size > 16) cache.clear ();
            cache[key] = m;
            return m;
        }

        public static string format_of (Bytes data, string name) {
            unowned uint8[] d = data.get_data ();
            if (d.length >= 4 && d[0] == 'g' && d[1] == 'l' && d[2] == 'T' && d[3] == 'F') return "glb";
            return name.down ().has_suffix (".obj") ? "obj" : "glb";
        }

        public static Mesh? load_obj (Bytes data) throws Error {
            string text = ForeignPart.bytes_text (data);
            var mb = new MeshBuilder ();
            var verts = new Gee.ArrayList<double?> ();
            float[] col = { 0.72f, 0.74f, 0.78f };
            foreach (string raw in text.split ("\n")) {
                string line = raw.strip ();
                if (line.has_prefix ("v ")) {
                    var p = line.substring (2).strip ().split_set (" \t");
                    int k = 0;
                    foreach (string t in p) {
                        if (t == "") continue;
                        if (k++ < 3) verts.add (double.parse (t));
                    }
                    while (k++ < 3) verts.add (0.0);
                } else if (line.has_prefix ("f ")) {
                    var idx = new Gee.ArrayList<int> ();
                    foreach (string t in line.substring (2).strip ().split_set (" \t")) {
                        if (t == "") continue;
                        int v = int.parse (t.split ("/")[0]);
                        int n = verts.size / 3;
                        if (v < 0) v = n + v + 1;
                        if (v >= 1 && v <= n) idx.add (v - 1);
                    }
                    for (int i = 1; i + 1 < idx.size; i++) mb.triangle (idx[0], idx[i], idx[i + 1], col[0], col[1], col[2]);
                } else if (line.has_prefix ("usemtl ")) {
                    string nm = line.substring (7).strip ();
                    uint h = nm.hash ();
                    var c = Rgba.from_hsl ((h % 360) / 360.0, 0.35, 0.6);
                    col = { (float) c.r, (float) c.g, (float) c.b };
                }
            }
            for (int i = 0; i + 2 < verts.size; i += 3) mb.vertex (verts[i], verts[i + 1], verts[i + 2]);
            return mb.build ();
        }

        private static uint32 u32 (uint8[] d, int o) {
            return (uint32) d[o] | ((uint32) d[o + 1] << 8) | ((uint32) d[o + 2] << 16) | ((uint32) d[o + 3] << 24);
        }

        private static float f32 (uint8[] d, int o) {
            uint32 v = u32 (d, o);
            float f = 0;
            Memory.copy (&f, &v, 4);
            return f;
        }

        private static double[] mat_identity () {
            return { 1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1 };
        }

        private static double[] mat_mul (double[] a, double[] b) {
            var r = new double[16];
            for (int c = 0; c < 4; c++) for (int rr = 0; rr < 4; rr++) {
                double s = 0;
                for (int k = 0; k < 4; k++) s += a[k * 4 + rr] * b[c * 4 + k];
                r[c * 4 + rr] = s;
            }
            return r;
        }

        private static double[] node_matrix (Json.Object n) {
            if (n.has_member ("matrix")) {
                var a = n.get_array_member ("matrix");
                var m = new double[16];
                for (int i = 0; i < 16 && i < a.get_length (); i++) m[i] = a.get_double_element (i);
                return m;
            }
            double tx = 0, ty = 0, tz = 0, qx = 0, qy = 0, qz = 0, qw = 1, sx = 1, sy = 1, sz = 1;
            if (n.has_member ("translation")) {
                var t = n.get_array_member ("translation");
                tx = t.get_double_element (0);
                ty = t.get_double_element (1);
                tz = t.get_double_element (2);
            }
            if (n.has_member ("rotation")) {
                var q = n.get_array_member ("rotation");
                qx = q.get_double_element (0);
                qy = q.get_double_element (1);
                qz = q.get_double_element (2);
                qw = q.get_double_element (3);
            }
            if (n.has_member ("scale")) {
                var sc = n.get_array_member ("scale");
                sx = sc.get_double_element (0);
                sy = sc.get_double_element (1);
                sz = sc.get_double_element (2);
            }
            return {
                (1 - 2 * (qy * qy + qz * qz)) * sx, (2 * (qx * qy + qz * qw)) * sx, (2 * (qx * qz - qy * qw)) * sx, 0,
                (2 * (qx * qy - qz * qw)) * sy, (1 - 2 * (qx * qx + qz * qz)) * sy, (2 * (qy * qz + qx * qw)) * sy, 0,
                (2 * (qx * qz + qy * qw)) * sz, (2 * (qy * qz - qx * qw)) * sz, (1 - 2 * (qx * qx + qy * qy)) * sz, 0,
                tx, ty, tz, 1
            };
        }

        private class Gltf {
            public Json.Object root;
            public uint8[] bin;
        }

        private static int comp_size (int64 ct) {
            switch (ct) {
                case 5120: case 5121: return 1;
                case 5122: case 5123: return 2;
                default: return 4;
            }
        }

        private static double read_comp (uint8[] b, int o, int64 ct) {
            switch (ct) {
                case 5126: return f32 (b, o);
                case 5125: return u32 (b, o);
                case 5123: return b[o] | (b[o + 1] << 8);
                case 5121: return b[o];
                case 5122: return (int16) (b[o] | (b[o + 1] << 8));
                default: return (int8) b[o];
            }
        }

        private static double[] accessor (Gltf g, int index, out int comps) throws Error {
            var accs = g.root.get_array_member ("accessors");
            var a = accs.get_object_element (index);
            int64 count = a.get_int_member ("count");
            int64 ct = a.get_int_member ("componentType");
            string type = a.get_string_member ("type");
            comps = type == "SCALAR" ? 1 : (type == "VEC2" ? 2 : (type == "VEC3" ? 3 : 4));
            var result = new double[count * comps];
            if (!a.has_member ("bufferView")) return result;
            var bv = g.root.get_array_member ("bufferViews").get_object_element ((uint) a.get_int_member ("bufferView"));
            int64 off = (bv.has_member ("byteOffset") ? bv.get_int_member ("byteOffset") : 0) + (a.has_member ("byteOffset") ? a.get_int_member ("byteOffset") : 0);
            int cs = comp_size (ct);
            int64 stride = bv.has_member ("byteStride") ? bv.get_int_member ("byteStride") : cs * comps;
            for (int64 i = 0; i < count; i++) {
                for (int c = 0; c < comps; c++) {
                    int64 o = off + i * stride + c * cs;
                    if (o + cs > g.bin.length) throw new IOError.INVALID_DATA (_("The 3D model is damaged"));
                    result[i * comps + c] = read_comp (g.bin, (int) o, ct);
                }
            }
            return result;
        }

        private static void add_node (Gltf g, MeshBuilder m, int index, double[] parent, int depth) throws Error {
            if (depth > 32) return;
            var n = g.root.get_array_member ("nodes").get_object_element (index);
            var mat = mat_mul (parent, node_matrix (n));
            if (n.has_member ("mesh")) {
                var mesh = g.root.get_array_member ("meshes").get_object_element ((uint) n.get_int_member ("mesh"));
                foreach (var pn in mesh.get_array_member ("primitives").get_elements ()) {
                    var prim = pn.get_object ();
                    if (prim.has_member ("mode") && prim.get_int_member ("mode") != 4) continue;
                    var attrs = prim.get_object_member ("attributes");
                    if (!attrs.has_member ("POSITION")) continue;
                    int pc;
                    var p = accessor (g, (int) attrs.get_int_member ("POSITION"), out pc);
                    int base_index = m.vertex_count ();
                    for (int i = 0; i + 2 < p.length; i += pc) {
                        double x = p[i], y = p[i + 1], z = p[i + 2];
                        m.vertex (mat[0] * x + mat[4] * y + mat[8] * z + mat[12], mat[1] * x + mat[5] * y + mat[9] * z + mat[13], mat[2] * x + mat[6] * y + mat[10] * z + mat[14]);
                    }
                    float r = 0.75f, gg = 0.76f, b = 0.8f;
                    if (prim.has_member ("material") && g.root.has_member ("materials")) {
                        var mt = g.root.get_array_member ("materials").get_object_element ((uint) prim.get_int_member ("material"));
                        if (mt.has_member ("pbrMetallicRoughness")) {
                            var pbr = mt.get_object_member ("pbrMetallicRoughness");
                            if (pbr.has_member ("baseColorFactor")) {
                                var f = pbr.get_array_member ("baseColorFactor");
                                r = (float) f.get_double_element (0);
                                gg = (float) f.get_double_element (1);
                                b = (float) f.get_double_element (2);
                            }
                        }
                    }
                    int verts = p.length / pc;
                    int[] idx = {};
                    if (prim.has_member ("indices")) {
                        int ic;
                        var ind = accessor (g, (int) prim.get_int_member ("indices"), out ic);
                        foreach (double v in ind) idx += (int) v;
                    } else {
                        for (int i = 0; i < verts; i++) idx += i;
                    }
                    for (int i = 0; i + 2 < idx.length; i += 3) {
                        if (idx[i] >= verts || idx[i + 1] >= verts || idx[i + 2] >= verts) continue;
                        m.triangle (base_index + idx[i], base_index + idx[i + 1], base_index + idx[i + 2], r, gg, b);
                    }
                }
            }
            if (n.has_member ("children")) foreach (var c in n.get_array_member ("children").get_elements ()) add_node (g, m, (int) c.get_int (), mat, depth + 1);
        }

        public static Mesh? load_glb (Bytes data) throws Error {
            unowned uint8[] d = data.get_data ();
            if (d.length < 20 || d[0] != 'g' || d[1] != 'l' || d[2] != 'T' || d[3] != 'F') throw new IOError.INVALID_DATA (_("Only binary glTF (.glb) models are supported"));
            int off = 12;
            string? json = null;
            uint8[] bin = {};
            while (off + 8 <= d.length) {
                int len = (int) u32 (d, off);
                uint32 type = u32 (d, off + 4);
                if (off + 8 + len > d.length) break;
                if (type == 0x4E4F534A) {
                    var buf = new uint8[len + 1];
                    Memory.copy (buf, &d[off + 8], len);
                    buf[len] = 0;
                    json = ((string) buf).dup ();
                }
                else if (type == 0x004E4942) bin = d[off + 8:off + 8 + len];
                off += 8 + len;
            }
            if (json == null) throw new IOError.INVALID_DATA (_("The 3D model is damaged"));
            var parser = new Json.Parser ();
            parser.load_from_data (json.make_valid (), -1);
            var g = new Gltf ();
            g.root = parser.get_root ().get_object ();
            g.bin = bin;
            var m = new MeshBuilder ();
            var roots = new Gee.ArrayList<int> ();
            if (g.root.has_member ("scenes")) {
                int sc = g.root.has_member ("scene") ? (int) g.root.get_int_member ("scene") : 0;
                var scene = g.root.get_array_member ("scenes").get_object_element (sc);
                if (scene.has_member ("nodes")) foreach (var n in scene.get_array_member ("nodes").get_elements ()) roots.add ((int) n.get_int ());
            } else if (g.root.has_member ("nodes")) {
                for (int i = 0; i < g.root.get_array_member ("nodes").get_length (); i++) roots.add (i);
            }
            foreach (int r in roots) add_node (g, m, r, mat_identity (), 0);
            return m.build ();
        }
    }

    public class MeshPainter {
        private static Gee.HashMap<string, Cairo.ImageSurface>? cache = null;

        public static void draw (Cairo.Context cr, Mesh m, double w, double h, double rx, double ry, double rz, double zoom) {
            double ax = rx * Math.PI / 180, ay = ry * Math.PI / 180, az = rz * Math.PI / 180;
            double cxr = Math.cos (ax), sxr = Math.sin (ax), cyr = Math.cos (ay), syr = Math.sin (ay), czr = Math.cos (az), szr = Math.sin (az);
            int nv = m.pos.length / 3;
            var px = new double[nv];
            var py = new double[nv];
            var pz = new double[nv];
            double r = m.radius;
            double dist = r * 3.2;
            double scale = double.min (w, h) * 0.5 / r * zoom * 1.05;
            for (int i = 0; i < nv; i++) {
                double x = m.pos[i * 3] - m.cx, y = m.pos[i * 3 + 1] - m.cy, z = m.pos[i * 3 + 2] - m.cz;
                double y1 = y * cxr - z * sxr, z1 = y * sxr + z * cxr;
                double x2 = x * cyr + z1 * syr, z2 = -x * syr + z1 * cyr;
                double x3 = x2 * czr - y1 * szr, y3 = x2 * szr + y1 * czr;
                double persp = dist / (dist - z2);
                px[i] = w / 2 + x3 * scale * persp * 0.8;
                py[i] = h / 2 - y3 * scale * persp * 0.8;
                pz[i] = z2;
            }
            int nt = m.triangle_count ();
            var order = new int[nt];
            var depth = new double[nt];
            for (int t = 0; t < nt; t++) {
                order[t] = t;
                depth[t] = pz[m.tris[t * 3]] + pz[m.tris[t * 3 + 1]] + pz[m.tris[t * 3 + 2]];
            }
            sort_by_depth (order, depth);
            cr.save ();
            cr.set_line_width (0.6);
            cr.set_line_join (Cairo.LineJoin.ROUND);
            double lx = -0.35, ly = 0.55, lz = 0.76;
            foreach (int t in order) {
                int a = m.tris[t * 3], b = m.tris[t * 3 + 1], c = m.tris[t * 3 + 2];
                double e1x = px[b] - px[a], e1y = -(py[b] - py[a]), e1z = pz[b] - pz[a];
                double e2x = px[c] - px[a], e2y = -(py[c] - py[a]), e2z = pz[c] - pz[a];
                double nx = e1y * e2z - e1z * e2y, ny = e1z * e2x - e1x * e2z, nz = e1x * e2y - e1y * e2x;
                double len = Math.sqrt (nx * nx + ny * ny + nz * nz);
                if (len <= 0) continue;
                nx /= len;
                ny /= len;
                nz /= len;
                double lambert = Math.fabs (nx * lx + ny * ly + nz * lz);
                double shade = 0.32 + 0.68 * lambert;
                cr.set_source_rgb (m.tri_color[t * 3] * shade, m.tri_color[t * 3 + 1] * shade, m.tri_color[t * 3 + 2] * shade);
                cr.move_to (px[a], py[a]);
                cr.line_to (px[b], py[b]);
                cr.line_to (px[c], py[c]);
                cr.close_path ();
                cr.fill_preserve ();
                cr.stroke ();
            }
            cr.restore ();
        }

        private static void sort_by_depth (int[] order, double[] depth) {
            var list = new Gee.ArrayList<int> ();
            foreach (int o in order) list.add (o);
            list.sort ((a, b) => depth[a] < depth[b] ? -1 : (depth[a] > depth[b] ? 1 : 0));
            for (int i = 0; i < order.length; i++) order[i] = list[i];
        }

        public static Cairo.ImageSurface? surface (Model3DElement e, int pw, int ph) {
            if (e.data == null || pw <= 0 || ph <= 0) return null;
            if (cache == null) cache = new Gee.HashMap<string, Cairo.ImageSurface> ();
            string key = "%s|%d|%d|%u".printf (e.signature (), pw, ph, e.data.hash ());
            if (cache.has_key (key)) return cache[key];
            var mesh = MeshLoader.load (e.data, e.format);
            if (mesh == null) return null;
            var surf = new Cairo.ImageSurface (Cairo.Format.ARGB32, pw, ph);
            var cr = new Cairo.Context (surf);
            draw (cr, mesh, pw, ph, e.rot_x, e.rot_y, e.rot_z, e.zoom);
            if (cache.size > 24) cache.clear ();
            cache[key] = surf;
            return surf;
        }

        public static Bytes? png (Model3DElement e, int pw, int ph) {
            var surf = surface (e, pw, ph);
            if (surf == null) return null;
            var mem = new ByteArray ();
            surf.write_to_png_stream ((data) => {
                mem.append (data);
                return Cairo.Status.SUCCESS;
            });
            return ByteArray.free_to_bytes (mem);
        }
    }
}
