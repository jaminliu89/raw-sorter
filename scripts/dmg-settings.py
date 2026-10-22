import os

format = "UDZO"
compression_level = 9
window_rect = ((200, 120), (1000, 600))
icon_size = 128
text_size = 14
show_status_bar = False
show_toolbar = False
show_sidebar = False
show_pathbar = False
show_tab_view = False
default_view = "icon-view"
background = defines["background"]
files = [defines["app"], defines["manual"]]
symlinks = {"Applications": "/Applications"}
icon_locations = {os.path.basename(defines["app"]): (200, 230), "Applications": (740, 230), "使用说明.pdf": (470, 460)}
hide_extension = [os.path.basename(defines["app"])]
