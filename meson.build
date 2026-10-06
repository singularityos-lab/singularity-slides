project('singularity-slides', ['vala', 'c'],
  version: '0.1.0',
  meson_version: '>= 0.59.0'
)

i18n = import('i18n')
add_project_arguments('-DGETTEXT_PACKAGE="singularity-slides"', language: 'c')
add_project_arguments('-w', language: 'c')
subdir('po')

cc         = meson.get_compiler('c')
gee_dep    = dependency('gee-0.8')
gio_dep    = dependency('gio-2.0')
xml_dep    = dependency('libxml-2.0')
zlib_dep   = dependency('zlib')
gtk_dep    = dependency('gtk4')
pango_dep  = dependency('pangocairo')
gst_dep    = dependency('gstreamer-1.0')
gst_app_dep = dependency('gstreamer-app-1.0')
gst_video_dep = dependency('gstreamer-video-1.0')
json_dep = dependency('json-glib-1.0')
soup_dep = dependency('libsoup-3.0')
math_dep   = cc.find_library('m')

core = files(
  'src/model/theme.vala',
  'src/model/chart_math.vala',
  'src/model/text.vala',
  'src/model/element.vala',
  'src/model/shape_effects.vala',
  'src/model/effects.vala',
  'src/model/review.vala',
  'src/model/objects.vala',
  'src/model/diagram.vala',
  'src/model/pathops.vala',
  'src/model/outline.vala',
  'src/model/accessibility.vala',
  'src/model/thesaurus.vala',
  'src/model/speech_coach.vala',
  'src/model/design_ideas.vala',
  'src/model/live_merge.vala',
  'src/model/slide.vala',
  'src/model/presentation.vala',
  'src/model/factory.vala',
  'src/model/templates.vala',
  'src/model/edits.vala',
  'src/model/versions.vala',
  'src/model/personal_templates.vala',
  'src/model/document.vala',
  'src/io/zip.vala',
  'src/io/aes.vala',
  'src/io/office_crypto.vala',
  'src/io/odf_crypto.vala',
  'src/io/xml.vala',
  'src/io/chart_workbook.vala',
  'src/io/pptx_common.vala',
  'src/io/pptx_transitions.vala',
  'src/io/pptx_ink.vala',
  'src/io/equation_codec.vala',
  'src/io/pptx_reader.vala',
  'src/io/pptx_writer.vala',
  'src/io/odp_common.vala',
  'src/io/odp_reader.vala',
  'src/io/odp_writer.vala',
)

render = files(
  'src/render/preset_data.vala',
  'src/render/presets.vala',
  'src/render/geometry.vala',
  'src/render/images.vala',
  'src/render/charts.vala',
  'src/render/chart_bridge.vala',
  'src/render/renderer.vala',
  'src/render/player.vala',
  'src/render/media_art.vala',
  'src/render/media_probe.vala',
  'src/render/shape_ops.vala',
  'src/render/text_effects.vala',
  'src/render/morph.vala',
  'src/render/print_layout.vala',
  'src/render/show_export.vala',
  'src/render/exporter.vala',
  'src/render/gif_encoder.vala',
  'src/render/video_encoder.vala',
  'src/render/audio_recorder.vala',
  'src/render/speech.vala',
  'src/render/screen_recorder.vala',
  'src/render/camera_recorder.vala',
  'src/render/model3d.vala',
  'src/render/font_embed.vala',
)

libsingularity_dep = dependency('singularity-1.0',
  fallback: ['libsingularity', 'libsingularity_dep']
)

if not meson.is_subproject() and libsingularity_dep.type_name() == 'internal'
  libsingularity_vapi_dir = join_paths(meson.project_build_root(), 'subprojects', 'libsingularity')
  add_project_arguments(['--vapidir=' + libsingularity_vapi_dir], language: 'vala')
endif

core_deps = [libsingularity_dep, gee_dep, gio_dep, xml_dep, zlib_dep, math_dep, gtk_dep, pango_dep, gst_dep, gst_app_dep, gst_video_dep, json_dep]

model_test = executable('slides-model-test',
  core + render + files('tests/model_test.vala'),
  dependencies: core_deps,
  vala_args: ['--pkg', 'zlib'],
)
test('model', model_test)

pptx_test = executable('slides-pptx-test',
  core + render + files('tests/pptx_test.vala'),
  dependencies: core_deps,
  vala_args: ['--pkg', 'zlib'],
)
test('pptx', pptx_test, workdir: meson.current_source_dir() / 'tests')

odp_test = executable('slides-odp-test',
  core + render + files('tests/odp_test.vala'),
  dependencies: core_deps,
  vala_args: ['--pkg', 'zlib'],
)
test('odp', odp_test, workdir: meson.current_source_dir() / 'tests')

fidelity_test = executable('slides-fidelity-test',
  core + render + files('src/ui/live_session.vala', 'tests/fidelity_test.vala'),
  dependencies: core_deps + [soup_dep],
  vala_args: ['--pkg', 'zlib'],
)
test('fidelity', fidelity_test, workdir: meson.current_source_dir() / 'tests', timeout: 120)

render_test = executable('slides-render-test',
  core + render + files('tests/render_test.vala'),
  dependencies: core_deps,
  vala_args: ['--pkg', 'zlib'],
)
test('render', render_test)


gnome = import('gnome')
resources = gnome.compile_resources(
  'singularity-slides-resources',
  'resources/dev.sinty.slides.gresource.xml',
  source_dir: meson.current_source_dir() / 'data' / 'icons',
)

ui = files(
  'src/ui/canvas.vala',
  'src/ui/text_editor.vala',
  'src/ui/thumbnails.vala',
  'src/ui/inspector.vala',
  'src/ui/animations.vala',
  'src/ui/ribbon.vala',
  'src/ui/dialogs.vala',
  'src/ui/presenter.vala',
  'src/ui/window.vala',
  'src/ui/app.vala',
  'src/ui/cloud_actions.vala',
  'src/ui/formula_bridge.vala',
  'src/ui/print_source.vala',
  'src/ui/galleries.vala',
  'src/ui/comments.vala',
  'src/ui/deck_dialogs.vala',
  'src/ui/language_tools.vala',
  'src/ui/outline_panel.vala',
  'src/ui/live_session.vala',
)

executable('singularity-slides',
  core + render + ui + files('src/ui/main.vala') + [resources],
  dependencies: core_deps + [libsingularity_dep, soup_dep],
  vala_args: ['--pkg', 'zlib'],
  install: true
)

ui_test = executable('slides-ui-test',
  core + render + ui + files('tests/ui_test.vala') + [resources],
  dependencies: core_deps + [libsingularity_dep, soup_dep],
  vala_args: ['--pkg', 'zlib'],
)
test('ui', ui_test, env: ['MALLOC_PERTURB_=165', 'GSETTINGS_BACKEND=memory', 'DISPLAY=', 'WAYLAND_DISPLAY='], timeout: 120)

install_data('data/dev.sinty.slides.desktop',
  install_dir: get_option('datadir') / 'applications'
)
install_data('data/dev.sinty.slides.gschema.xml',
  install_dir: get_option('datadir') / 'glib-2.0' / 'schemas'
)
install_data('data/dev.sinty.slides.json',
  install_dir: get_option('datadir') / 'singularity' / 'app-settings'
)
install_data('data/dev.sinty.slides.open.ini',
  install_dir: get_option('datadir') / 'singularity' / 'files-actions'
)
install_data('data/icons/dev.sinty.slides.svg',
  install_dir: get_option('datadir') / 'icons' / 'hicolor' / 'scalable' / 'apps'
)
