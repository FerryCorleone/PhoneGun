# dmgbuild 配置：安装窗口里左边是 PhoneGun，右边是「应用程序」，中间背景画了箭头
# 用法：dmgbuild -s scripts/dmg/settings.py -D app=/path/to/PhoneGun.app "PhoneGun" PhoneGun.dmg
import os.path

app = defines.get("app", "PhoneGun.app")  # noqa: F821
here = os.path.dirname(os.path.abspath(__file__)) if "__file__" in globals() else "scripts/dmg"

format = "UDZO"
filesystem = "HFS+"
files = [app]
symlinks = {"应用程序": "/Applications"}
background = os.path.join(here, "background.tiff")
window_rect = ((200, 160), (640, 400))
icon_size = 112
text_size = 13
icon_locations = {
    os.path.basename(app): (160, 200),
    "应用程序": (480, 200),
}
show_status_bar = False
show_tab_view = False
show_toolbar = False
show_pathbar = False
show_sidebar = False
default_view = "icon-view"
show_icon_preview = False
