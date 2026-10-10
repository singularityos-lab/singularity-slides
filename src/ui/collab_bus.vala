namespace Singularity.Apps.Slides {

    [DBus (name = "dev.sinty.Collab.Presentation1")]
    public class SlidesCollabBus : Object {
        private unowned SlidesApp app;

        public SlidesCollabBus (SlidesApp app) {
            this.app = app;
        }

        public void receive (string title, string payload, string from) throws Error {
            throw new IOError.NOT_SUPPORTED ("presentations are shared through a session");
        }

        public void join (string session, string title, string snapshot, string role, string from) throws Error {
            var w = new SlidesWindow (app);
            w.present ();
            w.new_presentation ();
            w.join_live_collab (session, snapshot, from);
        }
    }
}
