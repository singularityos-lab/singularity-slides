namespace Singularity.Apps.Slides {

    public class OdfCrypto {
        private const string NS = "urn:oasis:names:tc:opendocument:xmlns:manifest:1.0";
        private const int ITERATIONS = 100000;

        private static uint8[] digest (ChecksumType t, uint8[] d) {
            var ck = new Checksum (t);
            ck.update (d, d.length);
            size_t len = 64;
            var buf = new uint8[64];
            ck.get_digest (buf, ref len);
            buf.length = (int) len;
            return buf;
        }

        private static uint8[] hmac_sha1 (uint8[] key, uint8[] data) {
            var h = new Hmac (ChecksumType.SHA1, key);
            h.update (data);
            size_t len = 20;
            var buf = new uint8[20];
            h.get_digest (buf, ref len);
            return buf;
        }

        public static uint8[] pbkdf2_sha1 (uint8[] password, uint8[] salt, int iterations, int length) {
            var out_k = new uint8[length];
            int blocks = (length + 19) / 20;
            for (int b = 1; b <= blocks; b++) {
                var s = new uint8[salt.length + 4];
                Memory.copy (s, salt, salt.length);
                s[salt.length] = (uint8) (b >> 24);
                s[salt.length + 1] = (uint8) (b >> 16);
                s[salt.length + 2] = (uint8) (b >> 8);
                s[salt.length + 3] = (uint8) b;
                var u = hmac_sha1 (password, s);
                var t = new uint8[20];
                for (int k = 0; k < 20; k++) t[k] = u[k];
                for (int i = 1; i < iterations; i++) {
                    u = hmac_sha1 (password, u);
                    for (int k = 0; k < 20; k++) t[k] ^= u[k];
                }
                for (int k = 0; k < 20 && (b - 1) * 20 + k < length; k++) out_k[(b - 1) * 20 + k] = t[k];
            }
            return out_k;
        }

        private static uint8[] random_bytes (int n) {
            var r = new uint8[n];
            try {
                var s = File.new_for_path ("/dev/urandom").read ();
                size_t got;
                s.read_all (r, out got);
                s.close ();
                if (got == n) return r;
            } catch (Error e) {
            }
            for (int i = 0; i < n; i++) r[i] = (uint8) Random.int_range (0, 256);
            return r;
        }

        private static uint8[] deflate (uint8[] data) throws Error {
            var conv = new ZlibCompressor (ZlibCompressorFormat.RAW, 6);
            var mem = new MemoryOutputStream.resizable ();
            var stream = new ConverterOutputStream (mem, conv);
            size_t written;
            stream.write_all (data, out written);
            stream.close ();
            var out_d = mem.steal_data ();
            out_d.length = (int) mem.get_data_size ();
            return out_d;
        }

        private static uint8[] inflate (uint8[] data) throws Error {
            var conv = new ZlibDecompressor (ZlibCompressorFormat.RAW);
            var mem = new MemoryOutputStream.resizable ();
            var stream = new ConverterOutputStream (mem, conv);
            size_t written;
            stream.write_all (data, out written);
            stream.close ();
            var out_d = mem.steal_data ();
            out_d.length = (int) mem.get_data_size ();
            return out_d;
        }

        private static bool should_encrypt (string name) {
            return name != "mimetype" && name != "META-INF/manifest.xml" && !name.has_suffix ("/") && !name.has_prefix ("Thumbnails/");
        }

        public static bool is_encrypted (uint8[] data) {
            try {
                var zip = new ZipReader (data);
                string? m = zip.read_text ("META-INF/manifest.xml");
                return m != null && m.contains ("encryption-data");
            } catch (Error e) {
                return false;
            }
        }

        public static uint8[] encrypt (uint8[] package, string password) throws Error {
            var zip = new ZipReader (package);
            string manifest = zip.read_text ("META-INF/manifest.xml") ?? "";
            var start_key = digest (ChecksumType.SHA256, password.data);
            var out_zip = new ZipWriter ();
            uint8[]? mime = zip.read ("mimetype");
            if (mime != null) out_zip.add ("mimetype", mime, false);
            var entries = new Gee.HashMap<string, string> ();
            var names = new Gee.ArrayList<string> ();
            names.add_all (zip.names ());
            names.sort ((a, b) => strcmp (a, b));
            foreach (string name in names) {
                if (name == "mimetype" || name == "META-INF/manifest.xml") continue;
                uint8[]? data = zip.read (name);
                if (data == null) continue;
                if (!should_encrypt (name)) {
                    out_zip.add (name, data, true);
                    continue;
                }
                var packed = deflate (data);
                var salt = random_bytes (16);
                var iv = random_bytes (16);
                var key = pbkdf2_sha1 (start_key, salt, ITERATIONS, 32);
                int pad = 16 - packed.length % 16;
                var padded = new uint8[packed.length + pad];
                Memory.copy (padded, packed, packed.length);
                for (int i = packed.length; i < padded.length; i++) padded[i] = (uint8) pad;
                var enc = new Aes (key).cbc_encrypt (iv, padded);
                int ck_len = int.min (1024, packed.length);
                var checksum = digest (ChecksumType.SHA256, packed[0:ck_len]);
                out_zip.add (name, enc, false);
                entries[name] = ("<manifest:encryption-data manifest:checksum-type=\"urn:oasis:names:tc:opendocument:xmlns:manifest:1.0#sha256-1k\" manifest:checksum=\"%s\">" +
                    "<manifest:algorithm manifest:algorithm-name=\"http://www.w3.org/2001/04/xmlenc#aes256-cbc\" manifest:initialisation-vector=\"%s\"/>" +
                    "<manifest:start-key-generation manifest:start-key-generation-name=\"http://www.w3.org/2000/09/xmldsig#sha256\" manifest:key-size=\"32\"/>" +
                    "<manifest:key-derivation manifest:key-derivation-name=\"PBKDF2\" manifest:key-size=\"32\" manifest:iteration-count=\"%d\" manifest:salt=\"%s\"/>" +
                    "</manifest:encryption-data>").printf (Base64.encode (checksum), Base64.encode (iv), ITERATIONS, Base64.encode (salt));
                entries[name + "|size"] = data.length.to_string ();
            }
            var sb = new StringBuilder ();
            int pos = 0;
            while (true) {
                int a = manifest.index_of ("<manifest:file-entry", pos);
                if (a < 0) {
                    sb.append (manifest.substring (pos));
                    break;
                }
                int e = manifest.index_of (">", a);
                bool self_close = manifest[e - 1] == '/';
                string tag = manifest.substring (a, e - a + 1);
                sb.append (manifest.substring (pos, a - pos));
                int p1 = tag.index_of ("manifest:full-path=\"");
                string path = "";
                if (p1 >= 0) {
                    int s1 = p1 + 20;
                    path = tag.substring (s1, tag.index_of ("\"", s1) - s1);
                }
                if (entries.has_key (path) && self_close) {
                    sb.append (tag.substring (0, tag.length - 2));
                    sb.append (" manifest:size=\"%s\">".printf (entries[path + "|size"]));
                    sb.append (entries[path]);
                    sb.append ("</manifest:file-entry>");
                } else {
                    sb.append (tag);
                }
                pos = e + 1;
            }
            string final_manifest = sb.str;
            foreach (string name in names) {
                if (!entries.has_key (name) || final_manifest.contains ("full-path=\"%s\"".printf (name))) continue;
                string add = "<manifest:file-entry manifest:full-path=\"%s\" manifest:media-type=\"\" manifest:size=\"%s\">%s</manifest:file-entry>".printf (name, entries[name + "|size"], entries[name]);
                final_manifest = final_manifest.replace ("</manifest:manifest>", add + "</manifest:manifest>");
            }
            out_zip.add ("META-INF/manifest.xml", final_manifest.data, true);
            return out_zip.finish ();
        }

        public static uint8[] decrypt (uint8[] package, string password) throws Error {
            var zip = new ZipReader (package);
            string manifest = zip.read_text ("META-INF/manifest.xml") ?? "";
            Xml.Doc* doc = Xml.Parser.read_memory (manifest, manifest.length, null, null, Xml.ParserOption.NONET);
            if (doc == null) throw new CryptoError.UNSUPPORTED (_("The file list of the presentation is damaged."));
            var sha256 = digest (ChecksumType.SHA256, password.data);
            var sha1 = digest (ChecksumType.SHA1, password.data);
            var plain = new Gee.HashMap<string, Bytes> ();
            bool checked = false;
            try {
                for (Xml.Node* n = doc->get_root_element ()->children; n != null; n = n->next) {
                    if (n->type != Xml.ElementType.ELEMENT_NODE || n->name != "file-entry") continue;
                    string path = n->get_ns_prop ("full-path", NS) ?? "";
                    Xml.Node* ed = null;
                    for (Xml.Node* c = n->children; c != null; c = c->next) if (c->type == Xml.ElementType.ELEMENT_NODE && c->name == "encryption-data") ed = c;
                    if (ed == null) continue;
                    string alg = "", iv64 = "", salt64 = "", start = "", ck_type = "", ck64 = "";
                    int iter = 1024, key_size = 16;
                    ck_type = ed->get_ns_prop ("checksum-type", NS) ?? "";
                    ck64 = ed->get_ns_prop ("checksum", NS) ?? "";
                    for (Xml.Node* c = ed->children; c != null; c = c->next) {
                        if (c->type != Xml.ElementType.ELEMENT_NODE) continue;
                        switch (c->name) {
                            case "algorithm":
                                alg = c->get_ns_prop ("algorithm-name", NS) ?? "";
                                iv64 = c->get_ns_prop ("initialisation-vector", NS) ?? "";
                                break;
                            case "key-derivation":
                                salt64 = c->get_ns_prop ("salt", NS) ?? "";
                                iter = int.parse (c->get_ns_prop ("iteration-count", NS) ?? "1024");
                                key_size = int.parse (c->get_ns_prop ("key-size", NS) ?? "16");
                                break;
                            case "start-key-generation":
                                start = c->get_ns_prop ("start-key-generation-name", NS) ?? "";
                                break;
                            default:
                                break;
                        }
                    }
                    if (!alg.has_suffix ("aes256-cbc")) throw new CryptoError.UNSUPPORTED (_("This encryption method is not supported."));
                    uint8[]? raw = zip.read (path);
                    if (raw == null) continue;
                    var key = pbkdf2_sha1 (start.has_suffix ("sha256") ? sha256 : sha1, Base64.decode (salt64), iter, key_size);
                    var dec = new Aes (key).cbc_decrypt (Base64.decode (iv64), raw);
                    if (dec.length == 0) throw new CryptoError.WRONG_PASSWORD (_("The password is not correct."));
                    int pad = dec[dec.length - 1];
                    if (pad < 1 || pad > 16) throw new CryptoError.WRONG_PASSWORD (_("The password is not correct."));
                    var packed = dec[0:dec.length - pad];
                    if (!checked && ck_type.has_suffix ("sha256-1k")) {
                        var ck = digest (ChecksumType.SHA256, packed[0:int.min (1024, packed.length)]);
                        if (Base64.encode (ck) != ck64) throw new CryptoError.WRONG_PASSWORD (_("The password is not correct."));
                        checked = true;
                    }
                    plain[path] = new Bytes (inflate (packed));
                }
            } finally {
                delete doc;
            }
            var out_zip = new ZipWriter ();
            uint8[]? mime = zip.read ("mimetype");
            if (mime != null) out_zip.add ("mimetype", mime, false);
            foreach (string name in zip.names ()) {
                if (name == "mimetype") continue;
                if (plain.has_key (name)) {
                    out_zip.add (name, plain[name].get_data (), true);
                    continue;
                }
                uint8[]? d = zip.read (name);
                if (d != null) out_zip.add (name, d, true);
            }
            return out_zip.finish ();
        }
    }
}
