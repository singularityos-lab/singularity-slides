namespace Singularity.Apps.Slides {

    public class GifEncoder {
        public bool dither = true;
        public int width { get; private set; }
        public int height { get; private set; }

        private OutputStream output;
        private int loop_count;
        private bool header_written = false;
        private bool finished = false;
        private int frames_written = 0;
        private uint32[] previous;
        private bool has_previous = false;
        private ByteArray? pending = null;
        private int pending_delay = 0;
        private int[] dict_code;
        private int[] dict_stamp;
        private int stamp = 0;
        private int16[] lookup;
        private int[] pal_r;
        private int[] pal_g;
        private int[] pal_b;
        private int pal_size = 0;
        private uint32 bit_acc = 0;
        private int bit_count = 0;
        private uint8[] block;
        private int block_len = 0;
        private ByteArray? sink = null;

        public GifEncoder (OutputStream out, int width, int height, int loop_count = 0) {
            this.output = out;
            this.width = int.max (1, width);
            this.height = int.max (1, height);
            this.loop_count = loop_count;
            dict_code = new int[4096 * 256];
            dict_stamp = new int[4096 * 256];
            lookup = new int16[1 << 18];
            pal_r = new int[256];
            pal_g = new int[256];
            pal_b = new int[256];
            block = new uint8[255];
        }

        public void add_frame (Cairo.ImageSurface frame, int delay_centiseconds) throws Error {
            if (finished) throw new IOError.CLOSED (_("The animation has already been finished."));
            int delay = delay_centiseconds.clamp (0, 65535);
            var cur = read_pixels (frame);
            if (!header_written) write_header ();
            int x0 = 0, y0 = 0, x1 = width - 1, y1 = height - 1;
            if (has_previous && !changed_rect (cur, out x0, out y0, out x1, out y1)) {
                if (pending != null && pending_delay + delay <= 65535) {
                    pending_delay += delay;
                    return;
                }
                x0 = 0;
                y0 = 0;
                x1 = 0;
                y1 = 0;
            }
            var body = encode_region (cur, x0, y0, x1 - x0 + 1, y1 - y0 + 1);
            flush_pending ();
            pending = body;
            pending_delay = delay;
            previous = (owned) cur;
            has_previous = true;
        }

        public void finish () throws Error {
            if (finished) return;
            flush_pending ();
            if (frames_written == 0) throw new IOError.INVALID_DATA (_("There are no frames to export."));
            write_bytes ({ 0x3B });
            output.flush ();
            finished = true;
        }

        private uint32[] read_pixels (Cairo.ImageSurface frame) {
            Cairo.ImageSurface surf = frame;
            bool opaque = frame.get_format () == Cairo.Format.RGB24;
            if (frame.get_width () != width || frame.get_height () != height || (frame.get_format () != Cairo.Format.ARGB32 && !opaque)) {
                surf = new Cairo.ImageSurface (Cairo.Format.ARGB32, width, height);
                var cr = new Cairo.Context (surf);
                cr.scale ((double) width / int.max (1, frame.get_width ()), (double) height / int.max (1, frame.get_height ()));
                cr.set_source_surface (frame, 0, 0);
                cr.get_source ().set_filter (Cairo.Filter.GOOD);
                cr.paint ();
                opaque = false;
            }
            surf.flush ();
            var px = new uint32[width * height];
            uint8* data = (uint8*) surf.get_data ();
            int stride = surf.get_stride ();
            for (int y = 0; y < height; y++) {
                uint32* row = (uint32*) (data + y * stride);
                int o = y * width;
                for (int x = 0; x < width; x++) {
                    uint32 p = row[x];
                    if (opaque) {
                        px[o + x] = p & 0xFFFFFF;
                        continue;
                    }
                    uint32 a = p >> 24;
                    if (a == 255) {
                        px[o + x] = p & 0xFFFFFF;
                        continue;
                    }
                    uint32 k = 255 - a;
                    uint32 r = uint32.min (255, ((p >> 16) & 255) + k);
                    uint32 g = uint32.min (255, ((p >> 8) & 255) + k);
                    uint32 b = uint32.min (255, (p & 255) + k);
                    px[o + x] = (r << 16) | (g << 8) | b;
                }
            }
            return px;
        }

        private bool changed_rect (uint32[] cur, out int x0, out int y0, out int x1, out int y1) {
            x0 = 0;
            y0 = 0;
            x1 = width - 1;
            y1 = height - 1;
            size_t row_bytes = width * sizeof (uint32);
            int top = 0;
            while (top < height && Memory.cmp (&cur[top * width], &previous[top * width], row_bytes) == 0) top++;
            if (top == height) return false;
            int bottom = height - 1;
            while (bottom > top && Memory.cmp (&cur[bottom * width], &previous[bottom * width], row_bytes) == 0) bottom--;
            int left = width, right = -1;
            for (int y = top; y <= bottom; y++) {
                int o = y * width;
                for (int x = 0; x < left; x++) {
                    if (cur[o + x] != previous[o + x]) {
                        left = x;
                        break;
                    }
                }
                for (int x = width - 1; x > right; x--) {
                    if (cur[o + x] != previous[o + x]) {
                        right = x;
                        break;
                    }
                }
            }
            if (right < left) return false;
            x0 = left;
            y0 = top;
            x1 = right;
            y1 = bottom;
            return true;
        }

        private ByteArray encode_region (uint32[] cur, int rx, int ry, int rw, int rh) {
            var region = new uint32[rw * rh];
            for (int y = 0; y < rh; y++) Memory.copy (&region[y * rw], &cur[(ry + y) * width + rx], rw * sizeof (uint32));
            var indices = new uint8[rw * rh];
            if (!exact_palette (region, indices)) {
                median_cut (region);
                map_pixels (region, indices, rw, rh);
            }
            int bits = 1;
            while ((1 << bits) < pal_size) bits++;
            var body = new ByteArray ();
            body.append ({ 0x2C });
            put16 (body, rx);
            put16 (body, ry);
            put16 (body, rw);
            put16 (body, rh);
            body.append ({ (uint8) (0x80 | (bits - 1)) });
            var table = new uint8[3 << bits];
            for (int i = 0; i < pal_size; i++) {
                table[i * 3] = (uint8) pal_r[i];
                table[i * 3 + 1] = (uint8) pal_g[i];
                table[i * 3 + 2] = (uint8) pal_b[i];
            }
            body.append (table);
            lzw (body, indices, int.max (2, bits));
            return body;
        }

        private bool exact_palette (uint32[] region, uint8[] indices) {
            var keys = new uint32[1024];
            var vals = new uint8[1024];
            int count = 0;
            uint32 last = uint32.MAX;
            uint8 last_index = 0;
            for (int i = 0; i < region.length; i++) {
                uint32 c = region[i];
                if (c == last) {
                    indices[i] = last_index;
                    continue;
                }
                uint32 tagged = c | 0x1000000;
                uint32 m = c * (uint32) 0x9E3779B1;
                uint h = (uint) (m >> 22) & 1023;
                while (keys[h] != 0 && keys[h] != tagged) h = (h + 1) & 1023;
                if (keys[h] == 0) {
                    if (count == 256) return false;
                    keys[h] = tagged;
                    vals[h] = (uint8) count;
                    pal_r[count] = (int) ((c >> 16) & 255);
                    pal_g[count] = (int) ((c >> 8) & 255);
                    pal_b[count] = (int) (c & 255);
                    count++;
                }
                last = c;
                last_index = vals[h];
                indices[i] = last_index;
            }
            pal_size = int.max (1, count);
            return true;
        }

        private void median_cut (uint32[] region) {
            var hist = new int[32768];
            var sum_r = new int64[32768];
            var sum_g = new int64[32768];
            var sum_b = new int64[32768];
            for (int i = 0; i < region.length; i++) {
                uint32 c = region[i];
                int r = (int) ((c >> 16) & 255), g = (int) ((c >> 8) & 255), b = (int) (c & 255);
                int k = ((r >> 3) << 10) | ((g >> 3) << 5) | (b >> 3);
                hist[k]++;
                sum_r[k] += r;
                sum_g[k] += g;
                sum_b[k] += b;
            }
            int nbins = 0;
            for (int k = 0; k < 32768; k++) if (hist[k] > 0) nbins++;
            var bins = new int[nbins];
            var scratch = new int[nbins];
            nbins = 0;
            for (int k = 0; k < 32768; k++) if (hist[k] > 0) bins[nbins++] = k;
            var box_start = new int[256];
            var box_end = new int[256];
            var box_count = new int64[256];
            var box_axis = new int[256];
            var box_range = new int[256];
            var box_volume = new int64[256];
            int boxes = 1;
            box_start[0] = 0;
            box_end[0] = nbins;
            measure_box (bins, hist, 0, box_start, box_end, box_count, box_axis, box_range, box_volume);
            while (boxes < 256) {
                int best = -1;
                double best_score = 0;
                bool by_volume = boxes >= 128;
                for (int i = 0; i < boxes; i++) {
                    if (box_end[i] - box_start[i] < 2 || box_range[i] == 0) continue;
                    double score = by_volume ? (double) box_count[i] * box_volume[i] : (double) box_count[i];
                    if (score > best_score) {
                        best_score = score;
                        best = i;
                    }
                }
                if (best < 0) break;
                int s = box_start[best], e = box_end[best];
                int shift = box_axis[best] == 0 ? 10 : (box_axis[best] == 1 ? 5 : 0);
                var buckets = new int[33];
                for (int i = s; i < e; i++) buckets[((bins[i] >> shift) & 31) + 1]++;
                for (int v = 1; v < 33; v++) buckets[v] += buckets[v - 1];
                for (int i = s; i < e; i++) scratch[s + buckets[(bins[i] >> shift) & 31]++] = bins[i];
                Memory.copy (&bins[s], &scratch[s], (e - s) * sizeof (int));
                int64 half = box_count[best] / 2, acc = 0;
                int split = s + 1;
                for (int i = s; i < e - 1; i++) {
                    acc += hist[bins[i]];
                    split = i + 1;
                    if (acc >= half) break;
                }
                int run_value = (bins[split - 1] >> shift) & 31;
                while (split < e && ((bins[split] >> shift) & 31) == run_value) split++;
                if (split == e) {
                    split--;
                    while (((bins[split - 1] >> shift) & 31) == run_value) split--;
                }
                box_start[boxes] = split;
                box_end[boxes] = e;
                box_end[best] = split;
                measure_box (bins, hist, best, box_start, box_end, box_count, box_axis, box_range, box_volume);
                measure_box (bins, hist, boxes, box_start, box_end, box_count, box_axis, box_range, box_volume);
                boxes++;
            }
            pal_size = boxes;
            for (int i = 0; i < boxes; i++) {
                int64 n = 0, r = 0, g = 0, b = 0;
                for (int j = box_start[i]; j < box_end[i]; j++) {
                    int k = bins[j];
                    n += hist[k];
                    r += sum_r[k];
                    g += sum_g[k];
                    b += sum_b[k];
                }
                if (n == 0) n = 1;
                pal_r[i] = (int) ((r + n / 2) / n);
                pal_g[i] = (int) ((g + n / 2) / n);
                pal_b[i] = (int) ((b + n / 2) / n);
            }
            if (nbins <= 4096) {
                var acc_r = new int64[256];
                var acc_g = new int64[256];
                var acc_b = new int64[256];
                var acc_n = new int64[256];
                for (int j = 0; j < nbins; j++) {
                    int k = bins[j];
                    int n = hist[k];
                    int r = (int) (sum_r[k] / n), g = (int) (sum_g[k] / n), b = (int) (sum_b[k] / n);
                    int p = nearest (r, g, b);
                    acc_r[p] += sum_r[k];
                    acc_g[p] += sum_g[k];
                    acc_b[p] += sum_b[k];
                    acc_n[p] += n;
                }
                for (int i = 0; i < pal_size; i++) {
                    if (acc_n[i] == 0) continue;
                    pal_r[i] = (int) ((acc_r[i] + acc_n[i] / 2) / acc_n[i]);
                    pal_g[i] = (int) ((acc_g[i] + acc_n[i] / 2) / acc_n[i]);
                    pal_b[i] = (int) ((acc_b[i] + acc_n[i] / 2) / acc_n[i]);
                }
            }
        }

        private void measure_box (int[] bins, int[] hist, int i, int[] box_start, int[] box_end, int64[] box_count, int[] box_axis, int[] box_range, int64[] box_volume) {
            int r0 = 31, r1 = 0, g0 = 31, g1 = 0, b0 = 31, b1 = 0;
            int64 n = 0;
            for (int j = box_start[i]; j < box_end[i]; j++) {
                int k = bins[j];
                int r = k >> 10, g = (k >> 5) & 31, b = k & 31;
                if (r < r0) r0 = r;
                if (r > r1) r1 = r;
                if (g < g0) g0 = g;
                if (g > g1) g1 = g;
                if (b < b0) b0 = b;
                if (b > b1) b1 = b;
                n += hist[k];
            }
            box_count[i] = n;
            int dr = (r1 - r0) * 3, dg = (g1 - g0) * 4, db = (b1 - b0) * 2;
            if (dg >= dr && dg >= db) {
                box_axis[i] = 1;
                box_range[i] = g1 - g0;
            } else if (dr >= db) {
                box_axis[i] = 0;
                box_range[i] = r1 - r0;
            } else {
                box_axis[i] = 2;
                box_range[i] = b1 - b0;
            }
            box_volume[i] = (int64) (r1 - r0 + 1) * (g1 - g0 + 1) * (b1 - b0 + 1);
        }

        private int nearest (int r, int g, int b) {
            int best = 0, best_d = int.MAX;
            for (int i = 0; i < pal_size; i++) {
                int dr = r - pal_r[i], dg = g - pal_g[i], db = b - pal_b[i];
                int d = 3 * dr * dr + 4 * dg * dg + 2 * db * db;
                if (d < best_d) {
                    best_d = d;
                    best = i;
                    if (d == 0) break;
                }
            }
            return best;
        }

        private int lookup_index (int r, int g, int b) {
            int k = ((r >> 2) << 12) | ((g >> 2) << 6) | (b >> 2);
            int v = lookup[k];
            if (v < 0) {
                v = nearest ((r & ~3) + 2, (g & ~3) + 2, (b & ~3) + 2);
                lookup[k] = (int16) v;
            }
            return v;
        }

        private void map_pixels (uint32[] region, uint8[] indices, int rw, int rh) {
            Memory.set (lookup, 0xFF, lookup.length * sizeof (int16));
            if (!dither) {
                for (int i = 0; i < region.length; i++) {
                    uint32 c = region[i];
                    indices[i] = (uint8) lookup_index ((int) ((c >> 16) & 255), (int) ((c >> 8) & 255), (int) (c & 255));
                }
                return;
            }
            var err_cur = new int[(rw + 2) * 3];
            var err_next = new int[(rw + 2) * 3];
            for (int y = 0; y < rh; y++) {
                Memory.set (err_next, 0, err_next.length * sizeof (int));
                int o = y * rw;
                for (int x = 0; x < rw; x++) {
                    uint32 c = region[o + x];
                    int e = (x + 1) * 3;
                    int r = ((int) ((c >> 16) & 255) + (err_cur[e] / 16).clamp (-24, 24)).clamp (0, 255);
                    int g = ((int) ((c >> 8) & 255) + (err_cur[e + 1] / 16).clamp (-24, 24)).clamp (0, 255);
                    int b = ((int) (c & 255) + (err_cur[e + 2] / 16).clamp (-24, 24)).clamp (0, 255);
                    int p = lookup_index (r, g, b);
                    indices[o + x] = (uint8) p;
                    int er = r - pal_r[p], eg = g - pal_g[p], eb = b - pal_b[p];
                    err_cur[e + 3] += er * 7;
                    err_cur[e + 4] += eg * 7;
                    err_cur[e + 5] += eb * 7;
                    err_next[e - 3] += er * 3;
                    err_next[e - 2] += eg * 3;
                    err_next[e - 1] += eb * 3;
                    err_next[e] += er * 5;
                    err_next[e + 1] += eg * 5;
                    err_next[e + 2] += eb * 5;
                    err_next[e + 3] += er;
                    err_next[e + 4] += eg;
                    err_next[e + 5] += eb;
                }
                var t = (owned) err_cur;
                err_cur = (owned) err_next;
                err_next = (owned) t;
            }
        }

        private void lzw (ByteArray body, uint8[] indices, int min_size) {
            sink = body;
            bit_acc = 0;
            bit_count = 0;
            block_len = 0;
            body.append ({ (uint8) min_size });
            int clear = 1 << min_size;
            int eoi = clear + 1;
            int next = clear + 2;
            int bits = min_size + 1;
            stamp++;
            put_code (clear, bits);
            int prefix = indices[0];
            for (int i = 1; i < indices.length; i++) {
                int c = indices[i];
                int key = (prefix << 8) | c;
                if (dict_stamp[key] == stamp) {
                    prefix = dict_code[key];
                    continue;
                }
                put_code (prefix, bits);
                if (next >= (1 << bits) && bits < 12) bits++;
                if (next >= 4095) {
                    put_code (clear, bits);
                    stamp++;
                    next = clear + 2;
                    bits = min_size + 1;
                } else {
                    dict_stamp[key] = stamp;
                    dict_code[key] = next++;
                }
                prefix = c;
            }
            put_code (prefix, bits);
            if (next >= (1 << bits) && bits < 12) bits++;
            put_code (eoi, bits);
            if (bit_count > 0) put_byte ((uint8) (bit_acc & 255));
            if (block_len > 0) flush_block ();
            body.append ({ 0 });
            sink = null;
        }

        private void put_code (int code, int bits) {
            bit_acc |= ((uint32) code) << bit_count;
            bit_count += bits;
            while (bit_count >= 8) {
                put_byte ((uint8) (bit_acc & 255));
                bit_acc >>= 8;
                bit_count -= 8;
            }
        }

        private void put_byte (uint8 b) {
            block[block_len++] = b;
            if (block_len == 255) flush_block ();
        }

        private void flush_block () {
            sink.append ({ (uint8) block_len });
            sink.append (block[0 : block_len]);
            block_len = 0;
        }

        private void put16 (ByteArray b, int v) {
            b.append ({ (uint8) (v & 255), (uint8) ((v >> 8) & 255) });
        }

        private void write_header () throws Error {
            var h = new ByteArray ();
            h.append ("GIF89a".data);
            put16 (h, width);
            put16 (h, height);
            h.append ({ 0x70, 0, 0 });
            if (loop_count >= 0) {
                h.append ({ 0x21, 0xFF, 0x0B });
                h.append ("NETSCAPE2.0".data);
                h.append ({ 0x03, 0x01 });
                put16 (h, int.min (loop_count, 65535));
                h.append ({ 0 });
            }
            write_bytes (h.data);
            header_written = true;
        }

        private void flush_pending () throws Error {
            if (pending == null) return;
            var g = new ByteArray ();
            g.append ({ 0x21, 0xF9, 0x04, 0x04 });
            put16 (g, pending_delay);
            g.append ({ 0, 0 });
            write_bytes (g.data);
            write_bytes (pending.data);
            pending = null;
            pending_delay = 0;
            frames_written++;
        }

        private void write_bytes (uint8[] data) throws Error {
            size_t written;
            output.write_all (data, out written);
        }
    }
}
