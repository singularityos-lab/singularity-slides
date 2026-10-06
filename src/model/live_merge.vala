namespace Singularity.Apps.Slides {

    public class LiveMerge {
        public static void apply (Presentation local, Presentation remote, Gee.Collection<int> dirty, Gee.List<int> order, bool design) {
            if (design) {
                local.masters.clear ();
                foreach (var m in remote.masters) local.masters.add (m.clone ());
                local.width = remote.width;
                local.height = remote.height;
                local.custom_shows.clear ();
                foreach (var c in remote.custom_shows) local.custom_shows.add (c.clone ());
            }
            foreach (int uid in dirty) {
                var rs = remote.slide_by_uid (uid);
                int li = local.index_of_uid (uid);
                if (rs == null) {
                    if (li >= 0 && order.size > 0 && !order.contains (uid)) local.slides.remove_at (li);
                    continue;
                }
                var copy = rs.clone ();
                copy.uid = uid;
                Slide.reserve_uid (uid);
                if (li >= 0) local.slides[li] = copy;
                else local.slides.add (copy);
            }
            if (order.size == 0) return;
            for (int i = local.slides.size - 1; i >= 0; i--) {
                int uid = local.slides[i].uid;
                if (!order.contains (uid) && remote.slide_by_uid (uid) == null && dirty.contains (uid)) local.slides.remove_at (i);
            }
            var rank = new Gee.HashMap<int, int> ();
            for (int i = 0; i < order.size; i++) rank[order[i]] = i;
            var known = new Gee.ArrayList<Slide> ();
            var local_only = new Gee.ArrayList<Slide> ();
            var after = new Gee.HashMap<Slide, int> ();
            int last_uid = -1;
            foreach (var s in local.slides) {
                if (rank.has_key (s.uid)) {
                    known.add (s);
                    last_uid = s.uid;
                } else {
                    local_only.add (s);
                    after[s] = last_uid;
                }
            }
            known.sort ((a, b) => rank[a.uid] - rank[b.uid]);
            var result = new Gee.ArrayList<Slide> ();
            foreach (var s in local_only) if (after[s] == -1) result.add (s);
            foreach (var s in known) {
                result.add (s);
                foreach (var o in local_only) if (after[o] == s.uid) result.add (o);
            }
            local.slides.clear ();
            local.slides.add_all (result);
        }
    }
}
