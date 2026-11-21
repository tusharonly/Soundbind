# dmgbuild settings for the Soundbind disk image. Used by scripts/make_dmg.sh:
#   dmgbuild -s scripts/dmg/settings.py -D app=<path to Soundbind.app> "Soundbind" <output.dmg>
app = defines["app"]  # noqa: F821 - `defines` is injected by dmgbuild

format = "UDZO"
filesystem = "HFS+"
files = [app]
symlinks = {"Applications": "/Applications"}

background = defines["background"]  # noqa: F821
window_rect = ((240, 180), (660, 400))
default_view = "icon-view"
show_toolbar = False
show_status_bar = False
show_pathbar = False
show_sidebar = False
show_tab_view = False
show_icon_preview = False

icon_size = 128
text_size = 14
arrange_by = None
icon_locations = {
    "Soundbind.app": (170, 185),
    "Applications": (490, 185),
}
