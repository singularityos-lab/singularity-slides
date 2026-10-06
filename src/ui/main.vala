namespace Singularity.Apps.Slides {

    public static int main (string[] args) {
        Intl.setlocale (LocaleCategory.ALL, "");
        string locale_dir = "/usr/share/locale";
        try {
            string exe = FileUtils.read_link ("/proc/self/exe");
            locale_dir = Path.build_filename (Path.get_dirname (Path.get_dirname (exe)), "share", "locale");
        } catch (Error e) {
        }
        Intl.bindtextdomain ("singularity-slides", locale_dir);
        Intl.bind_textdomain_codeset ("singularity-slides", "UTF-8");
        Intl.textdomain ("singularity-slides");
        return new SlidesApp ().run (args);
    }
}
