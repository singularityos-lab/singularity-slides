namespace Singularity.Apps.Slides {

    public class LivePeer {
        public string id = "";
        public string name = "";
        public string color = "#1c71d8";
        public int slide = -1;
    }

    public class LiveSession : Object {
        public signal void remote_deck (Bytes deck, Gee.ArrayList<int> dirty, Gee.ArrayList<int> order, bool design, string who);
        public signal void peers_changed ();
        public signal void ended (string reason);

        public bool hosting = false;
        public string link = "";
        public string name;
        public string color;
        public string my_id = "host";
        public Gee.HashMap<string, LivePeer> peers = new Gee.HashMap<string, LivePeer> ();

        private Soup.Server? server = null;
        private Gee.HashMap<string, Soup.WebsocketConnection> sockets = new Gee.HashMap<string, Soup.WebsocketConnection> ();
        private string token = "";
        private string current_deck = "";
        private Gee.ArrayList<int> current_order = new Gee.ArrayList<int> ();
        private int next_id = 1;
        private Soup.WebsocketConnection? ws = null;
        public string collab_session = "";
        public bool collab = false;
        private ulong collab_raw_id = 0;
        private ulong collab_joined_id = 0;
        private ulong collab_ended_id = 0;

        public LiveSession (string name) {
            this.name = name;
            string[] colors = { "#e01b24", "#2ec27e", "#9141ac", "#ff7800", "#1c71d8", "#c64600", "#26a269", "#813d9c" };
            color = colors[Random.int_range (0, colors.length)];
        }

        private static string encode (Json.Object o) {
            var node = new Json.Node (Json.NodeType.OBJECT);
            node.set_object (o);
            return Json.to_string (node, false);
        }

        private static Json.Object? decode (Bytes bytes) {
            string text = ((string) bytes.get_data ()).make_valid ((ssize_t) bytes.get_size ());
            try {
                var parser = new Json.Parser ();
                parser.load_from_data (text);
                return parser.get_root ().get_object ();
            } catch (Error e) {
                return null;
            }
        }

        private static Json.Array ints (Gee.Collection<int> list) {
            var a = new Json.Array ();
            foreach (int v in list) a.add_int_element (v);
            return a;
        }

        private static Gee.ArrayList<int> int_list (Json.Object o, string key) {
            var list = new Gee.ArrayList<int> ();
            if (!o.has_member (key)) return list;
            foreach (var n in o.get_array_member (key).get_elements ()) list.add ((int) n.get_int ());
            return list;
        }

        private static string lan_address () {
            try {
                var sock = new Socket (SocketFamily.IPV4, SocketType.DATAGRAM, SocketProtocol.UDP);
                sock.connect (new InetSocketAddress (new InetAddress.from_string ("192.0.2.1"), 9));
                var local = (InetSocketAddress) sock.get_local_address ();
                string a = local.address.to_string ();
                sock.close ();
                if (a != "0.0.0.0") return a;
            } catch (Error e) {
            }
            return "127.0.0.1";
        }

        public static bool parse_link (string link, out string url, out string key) {
            url = "";
            key = "";
            string l = link.strip ();
            if (l.has_prefix ("slides-live://")) l = "ws://" + l.substring (14);
            try {
                var uri = Uri.parse (l, UriFlags.NONE);
                string? q = uri.get_query ();
                if (q == null) return false;
                var p = Uri.parse_params (q, -1, "&", UriParamsFlags.NONE);
                key = p["key"] ?? "";
                url = "ws://%s:%d/slides".printf (uri.get_host (), uri.get_port () > 0 ? uri.get_port () : 7790);
                return key != "";
            } catch (Error e) {
                return false;
            }
        }

        private Json.Array peer_array () {
            var a = new Json.Array ();
            var me = new Json.Object ();
            me.set_string_member ("id", "host");
            me.set_string_member ("name", name);
            me.set_string_member ("color", color);
            me.set_int_member ("slide", my_slide);
            a.add_object_element (me);
            foreach (var p in peers.values) {
                var o = new Json.Object ();
                o.set_string_member ("id", p.id);
                o.set_string_member ("name", p.name);
                o.set_string_member ("color", p.color);
                o.set_int_member ("slide", p.slide);
                a.add_object_element (o);
            }
            return a;
        }

        private int my_slide = -1;

        public void host (Bytes deck, Gee.List<int> order, uint port = 0) throws Error {
            hosting = true;
            token = Uuid.string_random ().replace ("-", "").substring (0, 20);
            current_deck = Base64.encode (deck.get_data ());
            current_order.clear ();
            current_order.add_all (order);
            server = new Soup.Server ("server-header", "SingularitySlidesLive");
            server.add_websocket_handler ("/slides", null, null, on_socket);
            server.listen_all (port, Soup.ServerListenOptions.IPV4_ONLY);
            uint bound = 0;
            foreach (var uri in server.get_uris ()) bound = uri.get_port ();
            link = "slides-live://%s:%u/?key=%s".printf (lan_address (), bound, token);
        }

        private void broadcast (Json.Object o, string? except) {
            string text = encode (o);
            foreach (var e in sockets.entries) if (e.key != except && e.value.state == Soup.WebsocketState.OPEN) e.value.send_text (text);
        }

        private void on_socket (Soup.Server srv, Soup.ServerMessage msg, string path, Soup.WebsocketConnection conn) {
            string cid = "p%d".printf (next_id++);
            bool accepted = false;
            conn.max_incoming_payload_size = 256 * 1024 * 1024;
            conn.message.connect ((type, bytes) => {
                if (type != Soup.WebsocketDataType.TEXT) return;
                var o = decode (bytes);
                if (o == null) return;
                string t = o.has_member ("t") ? o.get_string_member ("t") : "";
                if (!accepted) {
                    if (t != "hello" || !o.has_member ("key") || o.get_string_member ("key") != token) {
                        conn.close (Soup.WebsocketCloseCode.POLICY_VIOLATION, null);
                        return;
                    }
                    accepted = true;
                    var p = new LivePeer ();
                    p.id = cid;
                    p.name = o.has_member ("name") ? o.get_string_member ("name") : _("Guest");
                    p.color = o.has_member ("color") ? o.get_string_member ("color") : "#1c71d8";
                    peers[cid] = p;
                    sockets[cid] = conn;
                    var w = new Json.Object ();
                    w.set_string_member ("t", "welcome");
                    w.set_string_member ("id", cid);
                    w.set_string_member ("deck", current_deck);
                    w.set_array_member ("order", ints (current_order));
                    w.set_array_member ("peers", peer_array ());
                    conn.send_text (encode (w));
                    var pj = new Json.Object ();
                    pj.set_string_member ("t", "peers");
                    pj.set_array_member ("peers", peer_array ());
                    broadcast (pj, cid);
                    peers_changed ();
                    return;
                }
                if (t == "deck") {
                    current_deck = o.get_string_member ("deck");
                    current_order = int_list (o, "order");
                    o.set_string_member ("who", peers.has_key (cid) ? peers[cid].name : "");
                    broadcast (o, cid);
                    emit_deck (o);
                } else if (t == "presence") {
                    if (peers.has_key (cid)) peers[cid].slide = (int) o.get_int_member ("slide");
                    var pj = new Json.Object ();
                    pj.set_string_member ("t", "peers");
                    pj.set_array_member ("peers", peer_array ());
                    broadcast (pj, null);
                    peers_changed ();
                }
            });
            conn.closed.connect (() => {
                sockets.unset (cid);
                if (peers.unset (cid)) {
                    var pj = new Json.Object ();
                    pj.set_string_member ("t", "peers");
                    pj.set_array_member ("peers", peer_array ());
                    broadcast (pj, null);
                    peers_changed ();
                }
            });
        }

        private void emit_deck (Json.Object o) {
            var data = Base64.decode (o.get_string_member ("deck"));
            remote_deck (new Bytes (data), int_list (o, "dirty"), int_list (o, "order"), o.has_member ("design") && o.get_boolean_member ("design"), o.has_member ("who") ? o.get_string_member ("who") : "");
        }

        public async void join (string link) throws Error {
            string url, key;
            if (!parse_link (link, out url, out key)) throw new IOError.INVALID_ARGUMENT (_("This is not a live presentation link"));
            this.link = link;
            var session = new Soup.Session ();
            var msg = new Soup.Message ("GET", url);
            ws = yield session.websocket_connect_async (msg, null, null, Priority.DEFAULT, null);
            ws.max_incoming_payload_size = 256 * 1024 * 1024;
            ws.message.connect ((type, bytes) => {
                if (type != Soup.WebsocketDataType.TEXT) return;
                var o = decode (bytes);
                if (o == null) return;
                string t = o.has_member ("t") ? o.get_string_member ("t") : "";
                if (t == "welcome") {
                    my_id = o.get_string_member ("id");
                    read_peers (o);
                    var data = Base64.decode (o.get_string_member ("deck"));
                    remote_deck (new Bytes (data), new Gee.ArrayList<int> (), int_list (o, "order"), true, "");
                } else if (t == "deck") {
                    emit_deck (o);
                } else if (t == "peers") {
                    read_peers (o);
                }
            });
            ws.closed.connect (() => {
                ws = null;
                ended (_("The live presentation ended"));
            });
            var hello = new Json.Object ();
            hello.set_string_member ("t", "hello");
            hello.set_string_member ("key", key);
            hello.set_string_member ("name", name);
            hello.set_string_member ("color", color);
            ws.send_text (encode (hello));
        }

        private void read_peers (Json.Object o) {
            peers.clear ();
            if (!o.has_member ("peers")) return;
            foreach (var n in o.get_array_member ("peers").get_elements ()) {
                var po = n.get_object ();
                var p = new LivePeer ();
                p.id = po.get_string_member ("id");
                if (p.id == my_id) continue;
                p.name = po.get_string_member ("name");
                p.color = po.get_string_member ("color");
                p.slide = (int) po.get_int_member ("slide");
                peers[p.id] = p;
            }
            peers_changed ();
        }

        private Json.Object snapshot_json () {
            var o = new Json.Object ();
            o.set_string_member ("deck", current_deck);
            o.set_array_member ("order", ints (current_order));
            return o;
        }

        private Json.Object presence_json () {
            var o = new Json.Object ();
            o.set_string_member ("t", "presence");
            o.set_string_member ("id", my_id);
            o.set_string_member ("name", name);
            o.set_string_member ("color", color);
            o.set_int_member ("slide", my_slide);
            return o;
        }

        private void collab_wire (string session) {
            collab = true;
            collab_session = session;
            var client = Singularity.Collab.Client.get_default ();
            collab_raw_id = client.raw.connect ((sid, author, data) => {
                if (sid != collab_session) return;
                Json.Object? o = null;
                try {
                    var parser = new Json.Parser ();
                    parser.load_from_data (data);
                    o = parser.get_root ().get_object ();
                } catch (Error e) {
                    return;
                }
                string t = o.has_member ("t") ? o.get_string_member ("t") : "";
                if (t == "deck") {
                    current_deck = o.get_string_member ("deck");
                    current_order = int_list (o, "order");
                    emit_deck (o);
                } else if (t == "presence") {
                    string id = o.get_string_member ("id");
                    if (id == my_id) return;
                    var p = peers.has_key (id) ? peers[id] : new LivePeer ();
                    p.id = id;
                    p.name = o.get_string_member ("name");
                    p.color = o.get_string_member ("color");
                    p.slide = (int) o.get_int_member ("slide");
                    peers[id] = p;
                    peers_changed ();
                } else if (t == "bye") {
                    if (peers.unset (o.get_string_member ("id"))) peers_changed ();
                }
            });
            collab_joined_id = client.joined.connect ((sid, who) => {
                if (sid != collab_session || !hosting) return;
                client.update_snapshot.begin (collab_session, encode (snapshot_json ()));
                client.send_raw (collab_session, encode (presence_json ()));
            });
            collab_ended_id = client.ended.connect ((sid) => {
                if (sid != collab_session) return;
                collab_unwire ();
                ended (_("The live presentation ended"));
            });
        }

        private void collab_unwire () {
            var client = Singularity.Collab.Client.get_default ();
            if (collab_raw_id != 0) client.disconnect (collab_raw_id);
            if (collab_joined_id != 0) client.disconnect (collab_joined_id);
            if (collab_ended_id != 0) client.disconnect (collab_ended_id);
            collab_raw_id = collab_joined_id = collab_ended_id = 0;
            collab_session = "";
        }

        public async void host_collab (Bytes deck, Gee.List<int> order, Singularity.Collab.Person person, string title) throws Error {
            var client = Singularity.Collab.Client.get_default ();
            current_deck = Base64.encode (deck.get_data ());
            current_order.clear ();
            current_order.add_all (order);
            if (collab && collab_session != "") {
                yield client.invite (collab_session, person.id);
                return;
            }
            hosting = true;
            my_id = "u" + Uuid.string_random ().substring (0, 8);
            string sid = yield client.share (person.id, "Presentation", title, encode (snapshot_json ()));
            link = "";
            collab_wire (sid);
        }

        public void join_collab (string session, string snapshot) {
            hosting = false;
            my_id = "u" + Uuid.string_random ().substring (0, 8);
            collab_wire (session);
            try {
                var parser = new Json.Parser ();
                parser.load_from_data (snapshot);
                var o = parser.get_root ().get_object ();
                current_deck = o.get_string_member ("deck");
                current_order = int_list (o, "order");
                var data = Base64.decode (current_deck);
                remote_deck (new Bytes (data), new Gee.ArrayList<int> (), current_order, true, "");
            } catch (Error e) {
                warning ("slides: %s", e.message);
            }
            Singularity.Collab.Client.get_default ().send_raw (collab_session, encode (presence_json ()));
        }

        public void publish (Bytes deck, Gee.Collection<int> dirty, Gee.List<int> order, bool design) {
            var o = new Json.Object ();
            o.set_string_member ("t", "deck");
            o.set_string_member ("deck", Base64.encode (deck.get_data ()));
            o.set_array_member ("dirty", ints (dirty));
            o.set_array_member ("order", ints (order));
            o.set_boolean_member ("design", design);
            o.set_string_member ("who", name);
            if (collab) {
                current_deck = o.get_string_member ("deck");
                current_order.clear ();
                current_order.add_all (order);
                if (collab_session != "") Singularity.Collab.Client.get_default ().send_raw (collab_session, encode (o));
            } else if (hosting) {
                current_deck = o.get_string_member ("deck");
                current_order.clear ();
                current_order.add_all (order);
                broadcast (o, null);
            } else if (ws != null && ws.state == Soup.WebsocketState.OPEN) {
                ws.send_text (encode (o));
            }
        }

        public void presence (int slide_uid) {
            my_slide = slide_uid;
            if (collab) {
                if (collab_session != "") Singularity.Collab.Client.get_default ().send_raw (collab_session, encode (presence_json ()));
                return;
            }
            if (hosting) {
                var pj = new Json.Object ();
                pj.set_string_member ("t", "peers");
                pj.set_array_member ("peers", peer_array ());
                broadcast (pj, null);
                return;
            }
            if (ws == null || ws.state != Soup.WebsocketState.OPEN) return;
            var o = new Json.Object ();
            o.set_string_member ("t", "presence");
            o.set_int_member ("slide", slide_uid);
            ws.send_text (encode (o));
        }

        public void leave () {
            if (collab && collab_session != "") {
                var bye = new Json.Object ();
                bye.set_string_member ("t", "bye");
                bye.set_string_member ("id", my_id);
                var client = Singularity.Collab.Client.get_default ();
                client.send_raw (collab_session, encode (bye));
                string sid = collab_session;
                collab_unwire ();
                client.leave.begin (sid);
            }
            if (server != null) {
                foreach (var s in sockets.values) if (s.state == Soup.WebsocketState.OPEN) s.close (Soup.WebsocketCloseCode.GOING_AWAY, null);
                server.disconnect ();
                server = null;
            }
            if (ws != null && ws.state == Soup.WebsocketState.OPEN) ws.close (Soup.WebsocketCloseCode.NORMAL, null);
            ws = null;
            sockets.clear ();
            peers.clear ();
        }
    }
}
