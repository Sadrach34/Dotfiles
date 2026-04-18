#!/usr/bin/env python3
import gi
gi.require_version("Gtk", "4.0")
gi.require_version("Adw", "1")
from gi.repository import Gtk, Adw, GLib, Gio

import json
import subprocess
import time
from pathlib import Path
from copy import deepcopy
import re

HOME = Path.home()
CONFIG_PATH          = HOME / ".config/quickshell/data/config.json"
APPS_PATH            = HOME / ".config/quickshell/data/apps.json"
KEYBINDS_SYSTEM_PATH = HOME / ".config/hypr/configs/Keybinds.conf"
KEYBINDS_USER_PATH   = HOME / ".config/hypr/UserConfigs/UserKeybinds.conf"
POWER_SCRIPT         = HOME / ".config/hypr/scripts/PowerProfileAuto.sh"
WAYBAR_LAYOUTS_DIR   = HOME / ".config/waybar/configs"
WAYBAR_STYLES_DIR    = HOME / ".config/waybar/style"
WAYBAR_CONFIG_LINK   = HOME / ".config/waybar/config"
WAYBAR_STYLE_LINK    = HOME / ".config/waybar/style.css"
WAYBAR_STARTUP_LOG   = HOME / ".cache/quickshell/waybar-startup.log"

_LAST_WAYBAR_LOG_POS = 0
_LAST_WAYBAR_STYLE = ""


# ── Config I/O ────────────────────────────────────────────────────────────────

def load_json(path: Path) -> dict:
    try:
        return json.loads(path.read_text())
    except Exception:
        return {}

def save_json(path: Path, data: dict):
    path.write_text(json.dumps(data, indent=2) + "\n")

def get_nested(data, keys, fallback=None):
    o = data
    for k in keys:
        if not isinstance(o, dict):
            return fallback
        o = o.get(k)
        if o is None:
            return fallback
    return o if o is not None else fallback

def set_nested(data, keys, value):
    o = data
    for k in keys[:-1]:
        if k not in o or not isinstance(o[k], dict):
            o[k] = {}
        o = o[k]
    o[keys[-1]] = value


# ── Keybind helpers ───────────────────────────────────────────────────────────

def _auto_description(dispatcher: str, arg: str) -> str:
    d = (dispatcher or "").lower().strip()
    a = (arg or "").strip()
    if d == "exec":
        if "kitty" in a or "$term" in a: return "Open terminal"
        if "firefox" in a: return "Open Firefox"
        if "screenshot" in a or "ScreenShot" in a: return "Screenshot"
        if "windowswitcher" in a: return "Window switcher"
        if "applauncher" in a: return "App launcher"
        if "config toggle" in a: return "Config panel"
        return "Run command"
    if d == "killactive": return "Close window"
    if d == "workspace": return "Switch workspace"
    if d == "movefocus": return "Move focus"
    if d == "fullscreen": return "Toggle fullscreen"
    if d == "togglefloating": return "Toggle floating"
    return dispatcher or "Custom bind"

def _split_spec(spec: str) -> list[str]:
    out, current = [], ""
    for ch in spec:
        if ch == "," and len(out) < 3:
            out.append(current.strip())
            current = ""
        else:
            current += ch
    out.append(current.strip())
    return out

def _is_bind_line(line: str) -> bool:
    return bool(re.match(r'^(#\s*)?(bind[a-z]*)\s*=\s*', line.strip(), re.I))

def _parse_keybinds(text: str, source_tag: str) -> list[dict]:
    binds = []
    for i, original in enumerate(text.splitlines()):
        trimmed = original.strip()
        if not trimmed:
            continue
        commented = trimmed.startswith("#")
        parse = re.sub(r'^#\s*', '', trimmed) if commented else trimmed
        m = re.match(r'^(bind[a-z]*)\s*=\s*(.+)$', parse, re.I)
        if not m:
            continue
        bind_type, spec = m.group(1), m.group(2)
        description = ""
        if "#" in spec:
            idx = spec.index("#")
            description = spec[idx+1:].strip()
            spec = spec[:idx].strip()
        parts = _split_spec(spec)
        if len(parts) < 3:
            continue
        mods, key, dispatcher = parts[0], parts[1], parts[2]
        arg = ", ".join(parts[3:]) if len(parts) > 3 else ""
        binds.append({
            "uid": f"{source_tag}:{i}",
            "source": source_tag,
            "line_index": i,
            "enabled": not commented,
            "type": bind_type,
            "mods": mods.strip(),
            "key": key.strip(),
            "dispatcher": dispatcher.strip(),
            "arg": arg.strip(),
            "description": description or _auto_description(dispatcher, arg),
        })
    return binds

def _compose_bind_line(bind: dict) -> str:
    line = f"{bind['type']} = {bind['mods']}, {bind['key']}, {bind['dispatcher']}"
    if bind["arg"]:
        line += f", {bind['arg']}"
    if bind["description"]:
        line += f" # {bind['description']}"
    return ("# " if not bind["enabled"] else "") + line

def rebuild_keybind_file(original_lines: list[str], binds: list[dict]) -> str:
    keep = [l for l in original_lines if not _is_bind_line(l)]
    while keep and not keep[-1].strip():
        keep.pop()
    bind_lines = [_compose_bind_line(b) for b in binds]
    if bind_lines and keep:
        keep.append("")
    return "\n".join(keep + bind_lines) + "\n"


# ── Apply side effects ────────────────────────────────────────────────────────

def _run(cmd, shell=False):
    try:
        subprocess.Popen(cmd, shell=shell, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    except Exception:
        pass

def _run_wait(cmd, shell=False):
    try:
        subprocess.run(cmd, shell=shell, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    except Exception:
        pass

def _is_waybar_running() -> bool:
    try:
        return subprocess.run(
            ["pgrep", "-x", "waybar"],
            stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL,
        ).returncode == 0
    except Exception:
        return False

def _start_waybar_checked(
    cfg_path: str,
    style_path: str,
    timeout_sec: float = 5.0,
    stable_sec: float = 1.8,
) -> bool:
    global _LAST_WAYBAR_LOG_POS, _LAST_WAYBAR_STYLE
    try:
        WAYBAR_STARTUP_LOG.parent.mkdir(parents=True, exist_ok=True)
        try:
            _LAST_WAYBAR_LOG_POS = WAYBAR_STARTUP_LOG.stat().st_size
        except Exception:
            _LAST_WAYBAR_LOG_POS = 0
        _LAST_WAYBAR_STYLE = style_path
        with WAYBAR_STARTUP_LOG.open("a", encoding="utf-8") as logf:
            proc = subprocess.Popen(
                ["waybar", "-c", cfg_path, "-s", style_path],
                stdout=logf,
                stderr=subprocess.STDOUT,
                start_new_session=True,
            )
    except Exception:
        return False

    start_ts = time.time()
    first_seen_ts = None
    deadline = time.time() + timeout_sec
    while time.time() < deadline:
        running = _is_waybar_running()

        # Some environments can make the parent process exit while Waybar keeps
        # running in a child/session. Only fail when BOTH are not alive.
        if proc.poll() is not None and not running:
            return False

        if running and first_seen_ts is None:
            first_seen_ts = time.time()

        # Require the process to remain alive for a short grace period.
        if running and first_seen_ts is not None and (time.time() - first_seen_ts) >= stable_sec:
            return True

        # Hard guard: if process never appeared quickly enough, fail fast.
        if first_seen_ts is None and (time.time() - start_ts) > timeout_sec:
            return False

        time.sleep(0.1)
    return _is_waybar_running() and proc.poll() is None

def _waybar_last_error_summary(max_lines: int = 160, style_path: str = "") -> str:
    try:
        if not WAYBAR_STARTUP_LOG.exists():
            return ""

        start_pos = _LAST_WAYBAR_LOG_POS if _LAST_WAYBAR_LOG_POS >= 0 else 0
        with WAYBAR_STARTUP_LOG.open("rb") as fh:
            fh.seek(start_pos)
            chunk = fh.read()
        text = chunk.decode("utf-8", errors="ignore")
        lines = text.splitlines()
        tail = lines[-max_lines:] if len(lines) > max_lines else lines

        style_hint = Path(style_path or _LAST_WAYBAR_STYLE).name.strip().lower()

        if style_hint:
            for line in reversed(tail):
                line_s = line.strip()
                if "[error]" in line_s and style_hint in line_s.lower():
                    msg = line_s.split("[error]", 1)[-1].strip()
                    return msg[:180]

        for line in reversed(tail):
            line_s = line.strip()
            if "[error]" in line_s:
                # Keep the part after [error] when present.
                msg = line_s.split("[error]", 1)[-1].strip()
                return msg[:180]
        return ""
    except Exception:
        return ""

def apply_waybar(enabled: bool, cfg_path: str, style_path: str, restart: bool = False):
    if enabled:
        if restart:
            # Stop must be synchronous; async pkill can kill the new process.
            _run_wait("pkill -x waybar || true", shell=True)
            return _start_waybar_checked(cfg_path, style_path)
        else:
            if _is_waybar_running():
                return True
            return _start_waybar_checked(cfg_path, style_path)
    else:
        _run_wait("pkill -x waybar || true", shell=True)
        return True

def sync_waybar_links(cfg_path: str, style_path: str):
    _run(f"ln -sf {json.dumps(cfg_path)} {json.dumps(str(WAYBAR_CONFIG_LINK))}", shell=True)
    _run(f"ln -sf {json.dumps(style_path)} {json.dumps(str(WAYBAR_STYLE_LINK))}", shell=True)

def apply_power_profile():
    if POWER_SCRIPT.exists():
        _run([str(POWER_SCRIPT)])

def apply_optimization(enabled: bool):
    if enabled:
        batch = "keyword animations:enabled 0;keyword decoration:blur:enabled 0;keyword decoration:shadow:enabled 0;keyword decoration:dim_inactive 0;keyword decoration:active_opacity 1.0;keyword decoration:inactive_opacity 1.0;keyword general:gaps_in 0;keyword general:gaps_out 0;keyword general:border_size 1;keyword decoration:rounding 0;keyword misc:vfr 0;keyword misc:vrr 2"
    else:
        batch = "keyword animations:enabled 1;keyword decoration:blur:enabled 1;keyword decoration:shadow:enabled 1;keyword decoration:dim_inactive 1;keyword decoration:active_opacity 1.0;keyword decoration:inactive_opacity 0.9;keyword general:gaps_in 2;keyword general:gaps_out 4;keyword general:border_size 2;keyword decoration:rounding 10;keyword misc:vfr 1;keyword misc:vrr 0"
    _run(["hyprctl", "--batch", batch])

def apply_hypr_reload():
    _run(["hyprctl", "reload"])


# ── Window ────────────────────────────────────────────────────────────────────

PAGES = [
    ("General",      "preferences-system-symbolic"),
    ("Bar",          "view-sidebar-start-symbolic"),
    ("Components",   "view-app-grid-symbolic"),
    ("Power",        "battery-symbolic"),
    ("Wallpaper",    "image-x-generic-symbolic"),
    ("Integrations", "applications-engineering-symbolic"),
    ("Apps",         "applications-symbolic"),
    ("Intervals",    "preferences-system-time-symbolic"),
    ("Keybinds",     "input-keyboard-symbolic"),
]


class ConfigWindow(Adw.ApplicationWindow):
    def __init__(self, **kwargs):
        super().__init__(**kwargs)
        self.set_default_size(1020, 740)
        self.set_size_request(760, 520)
        self.set_title("SdrxDots Settings")
        self.set_icon_name("preferences-system-symbolic")

        self._config = load_json(CONFIG_PATH)
        self._apps   = load_json(APPS_PATH)
        self._defaults_config = deepcopy(self._config)
        self._defaults_apps   = deepcopy(self._apps)
        self._saved_config    = deepcopy(self._config)
        self._saved_apps      = deepcopy(self._apps)
        self._unsaved = False

        self._keybinds_system_lines: list[str] = []
        self._keybinds_user_lines:   list[str] = []
        self._keybinds_all:   list[dict] = []
        self._keybinds_saved: list[dict] = []
        self._external_conflict_paths: list[str] = []
        self._suppress_external_reload_until = 0.0
        self._file_mtimes: dict[str, float | None] = {}
        self._load_keybinds()

        self._build_ui()
        self._install_css()
        self._setup_file_monitor()
        self._setup_shortcuts()
        self._update_title()

    # ── UI skeleton ───────────────────────────────────────────────────────────

    def _build_ui(self):
        toolbar_view = Adw.ToolbarView()

        # Header bar
        header_bar = Adw.HeaderBar()
        header_bar.set_show_title(True)

        self._save_btn    = Gtk.Button(label="Save")
        self._discard_btn = Gtk.Button(label="Discard")
        self._defaults_btn = Gtk.Button(label="Defaults")
        self._save_btn.add_css_class("suggested-action")
        self._discard_btn.add_css_class("destructive-action")
        self._save_btn.set_sensitive(False)
        self._discard_btn.set_sensitive(False)
        self._save_btn.connect("clicked", self._on_save)
        self._discard_btn.connect("clicked", self._on_discard)
        self._defaults_btn.connect("clicked", self._on_defaults)

        header_bar.pack_end(self._save_btn)
        header_bar.pack_end(self._discard_btn)
        header_bar.pack_start(self._defaults_btn)
        toolbar_view.add_top_bar(header_bar)

        # Unsaved banner
        self._banner = Adw.Banner(title="Unsaved changes")
        self._banner.set_button_label("Save now")
        self._banner.connect("button-clicked", self._on_save)
        toolbar_view.add_top_bar(self._banner)

        self._reload_banner = Adw.Banner(title="External changes detected")
        self._reload_banner.set_button_label("Reload now")
        self._reload_banner.connect("button-clicked", self._on_reload_external)
        toolbar_view.add_top_bar(self._reload_banner)

        # Split view: sidebar left, content right
        split = Adw.OverlaySplitView()
        split.set_sidebar_width_fraction(0.22)
        split.set_min_sidebar_width(180)
        split.set_max_sidebar_width(260)
        split.set_collapsed(False)
        split.set_show_sidebar(True)

        split.set_sidebar(self._build_sidebar())

        self._stack = Gtk.Stack()
        self._stack.set_transition_type(Gtk.StackTransitionType.CROSSFADE)
        self._stack.set_transition_duration(180)
        self._stack.set_vexpand(True)
        self._stack.set_hexpand(True)

        self._page_builders = [
            self._build_general_page,
            self._build_bar_page,
            self._build_components_page,
            self._build_power_page,
            self._build_wallpaper_page,
            self._build_integrations_page,
            self._build_apps_page,
            self._build_intervals_page,
            self._build_keybinds_page,
        ]
        for i, (name, _icon) in enumerate(PAGES):
            page_widget = self._page_builders[i]()
            scroll = Gtk.ScrolledWindow(vexpand=True, hexpand=True)
            scroll.set_child(page_widget)
            scroll.set_policy(Gtk.PolicyType.NEVER, Gtk.PolicyType.AUTOMATIC)
            self._stack.add_named(scroll, name.lower())

        split.set_content(self._stack)
        toolbar_view.set_content(split)

        self._toast_overlay = Adw.ToastOverlay()
        self._toast_overlay.set_child(toolbar_view)
        self.set_content(self._toast_overlay)
        self._nav_list.select_row(self._nav_list.get_row_at_index(0))
        self._banner.set_revealed(False)
        self._reload_banner.set_revealed(False)

    def _build_sidebar(self) -> Gtk.Widget:
        box = Gtk.Box(orientation=Gtk.Orientation.VERTICAL)
        box.add_css_class("navigation-sidebar")

        # Search bar
        self._search_entry = Gtk.SearchEntry(placeholder_text="Search…")
        self._search_entry.set_margin_start(8)
        self._search_entry.set_margin_end(8)
        self._search_entry.set_margin_top(10)
        self._search_entry.set_margin_bottom(6)
        self._search_entry.connect("search-changed", self._on_global_search)
        box.append(self._search_entry)

        sep = Gtk.Separator(orientation=Gtk.Orientation.HORIZONTAL)
        sep.set_margin_bottom(4)
        box.append(sep)

        self._nav_list = Gtk.ListBox()
        self._nav_list.set_selection_mode(Gtk.SelectionMode.SINGLE)
        self._nav_list.add_css_class("navigation-sidebar")
        self._nav_list.set_vexpand(True)
        self._nav_list.connect("row-selected", self._on_nav_select)

        for name, icon in PAGES:
            row = Gtk.ListBoxRow()
            hbox = Gtk.Box(orientation=Gtk.Orientation.HORIZONTAL, spacing=12)
            hbox.set_margin_start(12)
            hbox.set_margin_end(12)
            hbox.set_margin_top(8)
            hbox.set_margin_bottom(8)
            img = Gtk.Image.new_from_icon_name(icon)
            img.set_pixel_size(16)
            lbl = Gtk.Label(label=name, xalign=0.0, hexpand=True)
            hbox.append(img)
            hbox.append(lbl)
            row.set_child(hbox)
            self._nav_list.append(row)

        box.append(self._nav_list)
        return box

    def _on_nav_select(self, listbox, row):
        if row is None or not hasattr(self, "_stack"):
            return
        idx = row.get_index()
        if 0 <= idx < len(PAGES):
            self._stack.set_visible_child_name(PAGES[idx][0].lower())

    def _on_global_search(self, entry):
        query = entry.get_text().strip().lower()
        if not query:
            return
        # Jump to first page whose name matches
        for i, (name, _) in enumerate(PAGES):
            if query in name.lower():
                self._nav_list.select_row(self._nav_list.get_row_at_index(i))
                return

    # ── Unsaved state ─────────────────────────────────────────────────────────

    def _mark_unsaved(self):
        if not self._unsaved:
            self._unsaved = True
            self._save_btn.set_sensitive(True)
            self._discard_btn.set_sensitive(True)
            self._banner.set_revealed(True)
            self._update_title()

    def _mark_saved(self):
        self._unsaved = False
        self._save_btn.set_sensitive(False)
        self._discard_btn.set_sensitive(False)
        self._banner.set_revealed(False)
        self._update_title()

    # ── Keyboard shortcuts ────────────────────────────────────────────────────

    def _setup_shortcuts(self):
        ctrl = Gtk.ShortcutController()
        ctrl.set_scope(Gtk.ShortcutScope.GLOBAL)

        trigger = Gtk.ShortcutTrigger.parse_string("<Ctrl>s")
        if trigger is not None:
            save_sc = Gtk.Shortcut(
                trigger=trigger,
                action=Gtk.CallbackAction.new(lambda *_: self._on_save(None) or True),
            )
            ctrl.add_shortcut(save_sc)
        self.add_controller(ctrl)

    # ── File monitor ──────────────────────────────────────────────────────────

    def _setup_file_monitor(self):
        self._file_mtimes = self._snapshot_file_mtimes()
        GLib.timeout_add(1500, self._poll_external_changes)

    def _tracked_files(self) -> dict[str, Path]:
        return {
            "config.json": CONFIG_PATH,
            "apps.json": APPS_PATH,
            "Keybinds.conf": KEYBINDS_SYSTEM_PATH,
            "UserKeybinds.conf": KEYBINDS_USER_PATH,
        }

    def _mtime(self, path: Path) -> float | None:
        try:
            return path.stat().st_mtime
        except FileNotFoundError:
            return None

    def _snapshot_file_mtimes(self) -> dict[str, float | None]:
        return {name: self._mtime(path) for name, path in self._tracked_files().items()}

    def _poll_external_changes(self):
        now = time.time()
        current = self._snapshot_file_mtimes()
        if now < self._suppress_external_reload_until:
            self._file_mtimes = current
            return True

        changed = [
            name for name, mtime in current.items()
            if mtime != self._file_mtimes.get(name)
        ]
        if changed:
            if self._unsaved:
                self._external_conflict_paths = changed
                self._reload_banner.set_title(
                    "External changes in " + ", ".join(changed) + ". Reload to discard local edits."
                )
                self._reload_banner.set_revealed(True)
            else:
                self._reload_from_disk(changed)
        self._file_mtimes = current
        return True

    def _reload_from_disk(self, changed: list[str] | None = None):
        self._config = load_json(CONFIG_PATH)
        self._apps = load_json(APPS_PATH)
        self._load_keybinds()
        self._saved_config = deepcopy(self._config)
        self._saved_apps = deepcopy(self._apps)
        self._mark_saved()
        self._reload_banner.set_revealed(False)
        self._external_conflict_paths = []
        self._refresh_pages()
        if changed:
            self._toast("Reloaded external changes: " + ", ".join(changed))

    # ── Save / Discard / Defaults ─────────────────────────────────────────────

    def _on_save(self, _widget):
        prev_bar    = get_nested(self._saved_config, ["components", "bar", "enabled"], True)
        prev_cfg_raw = get_nested(self._saved_config, ["components", "bar", "waybarConfig"], "~/.config/waybar/config")
        prev_sty_raw = get_nested(self._saved_config, ["components", "bar", "waybarStyle"], "~/.config/waybar/style.css")
        prev_pow_t  = get_nested(self._saved_config, ["power", "deviceType"], "auto")
        prev_pow_p  = get_nested(self._saved_config, ["power", "profile"], "performance")
        prev_opt    = get_nested(self._saved_config, ["optimization", "enabled"], False)

        self._normalize_apps_data()
        save_json(CONFIG_PATH, self._config)
        save_json(APPS_PATH, self._apps)

        cur_bar = get_nested(self._config, ["components", "bar", "enabled"], True)
        cur_cfg_raw = get_nested(self._config, ["components", "bar", "waybarConfig"], "~/.config/waybar/config")
        cur_sty_raw = get_nested(self._config, ["components", "bar", "waybarStyle"], "~/.config/waybar/style.css")
        prev_cfg = str(Path(str(prev_cfg_raw).replace("~", str(HOME))))
        prev_sty = str(Path(str(prev_sty_raw).replace("~", str(HOME))))
        cur_cfg = str(Path(str(cur_cfg_raw).replace("~", str(HOME))))
        cur_sty = str(Path(str(cur_sty_raw).replace("~", str(HOME))))
        bar_paths_changed = (cur_cfg != prev_cfg) or (cur_sty != prev_sty)

        # Keep ~/.config/waybar/config and style.css aligned so external refresh scripts
        # (e.g. Win+Alt+R Refresh.sh) preserve the selected preset.
        sync_waybar_links(cur_cfg, cur_sty)

        if cur_bar != prev_bar:
            ok = apply_waybar(cur_bar, cur_cfg, cur_sty, restart=cur_bar)
            if cur_bar and not ok:
                set_nested(self._config, ["components", "bar", "waybarConfig"], prev_cfg_raw)
                set_nested(self._config, ["components", "bar", "waybarStyle"], prev_sty_raw)
                sync_waybar_links(prev_cfg, prev_sty)
                apply_waybar(True, prev_cfg, prev_sty, restart=True)
                save_json(CONFIG_PATH, self._config)
                reason = _waybar_last_error_summary(style_path=cur_sty)
                style_name = Path(cur_sty).name
                msg = f"Waybar failed for {style_name}; restored previous working style"
                if reason:
                    msg += f" ({reason})"
                self._toast(msg, timeout=4)
        elif cur_bar and bar_paths_changed:
            ok = apply_waybar(True, cur_cfg, cur_sty, restart=True)
            if not ok:
                set_nested(self._config, ["components", "bar", "waybarConfig"], prev_cfg_raw)
                set_nested(self._config, ["components", "bar", "waybarStyle"], prev_sty_raw)
                sync_waybar_links(prev_cfg, prev_sty)
                apply_waybar(True, prev_cfg, prev_sty, restart=True)
                save_json(CONFIG_PATH, self._config)
                reason = _waybar_last_error_summary(style_path=cur_sty)
                style_name = Path(cur_sty).name
                msg = f"Selected style failed: {style_name}; reverted to previous working style"
                if reason:
                    msg += f" ({reason})"
                self._toast(msg, timeout=4)

        if (get_nested(self._config, ["power", "deviceType"], "auto") != prev_pow_t or
                get_nested(self._config, ["power", "profile"], "performance") != prev_pow_p):
            apply_power_profile()

        cur_opt = get_nested(self._config, ["optimization", "enabled"], False)
        if cur_opt != prev_opt:
            apply_optimization(cur_opt)

        if self._keybinds_all != self._keybinds_saved:
            sys_binds = [b for b in self._keybinds_all if b["source"] == "SYSTEM"]
            usr_binds = [b for b in self._keybinds_all if b["source"] == "USER"]
            KEYBINDS_SYSTEM_PATH.write_text(rebuild_keybind_file(self._keybinds_system_lines, sys_binds))
            KEYBINDS_USER_PATH.write_text(rebuild_keybind_file(self._keybinds_user_lines, usr_binds))
            self._keybinds_saved = deepcopy(self._keybinds_all)
            apply_hypr_reload()

        self._saved_config = deepcopy(self._config)
        self._saved_apps   = deepcopy(self._apps)
        self._suppress_external_reload_until = time.time() + 1.2
        self._mark_saved()
        self._reload_banner.set_revealed(False)
        self._external_conflict_paths = []

        self._toast("Settings saved")

    def _on_discard(self, _widget):
        self._config = deepcopy(self._saved_config)
        self._apps   = deepcopy(self._saved_apps)
        self._keybinds_all = deepcopy(self._keybinds_saved)
        self._mark_saved()
        self._reload_banner.set_revealed(False)
        self._external_conflict_paths = []
        self._refresh_pages()

    def _on_defaults(self, _widget):
        self._config = deepcopy(self._defaults_config)
        self._apps   = deepcopy(self._defaults_apps)
        self._mark_unsaved()
        self._refresh_pages()

    def _on_reload_external(self, _widget):
        self._reload_from_disk(self._external_conflict_paths)

    def _update_title(self):
        self.set_title("SdrxDots Settings*" if self._unsaved else "SdrxDots Settings")

    def _toast(self, text: str, timeout: int = 2):
        self._toast_overlay.add_toast(Adw.Toast(title=text, timeout=timeout))

    def _install_css(self):
        css = b"""
        .navigation-sidebar {
            border-right: 1px solid alpha(@window_fg_color, 0.08);
        }

        .dim-label {
            opacity: 0.7;
        }
        """
        provider = Gtk.CssProvider()
        provider.load_from_data(css)
        Gtk.StyleContext.add_provider_for_display(
            self.get_display(),
            provider,
            Gtk.STYLE_PROVIDER_PRIORITY_APPLICATION,
        )

    def _normalize_apps_data(self):
        for app_key, app_data in self._apps.items():
            if app_key.startswith("_") or not isinstance(app_data, dict):
                continue
            tags = app_data.get("tags")
            if isinstance(tags, str):
                app_data["tags"] = [t.strip() for t in tags.split(",") if t.strip()]

    def _refresh_pages(self):
        current = self._stack.get_visible_child_name()
        # Remove all pages and rebuild
        for name, _ in PAGES:
            child = self._stack.get_child_by_name(name.lower())
            if child:
                self._stack.remove(child)
        for i, (name, _icon) in enumerate(PAGES):
            page_widget = self._page_builders[i]()
            scroll = Gtk.ScrolledWindow(vexpand=True, hexpand=True)
            scroll.set_child(page_widget)
            scroll.set_policy(Gtk.PolicyType.NEVER, Gtk.PolicyType.AUTOMATIC)
            self._stack.add_named(scroll, name.lower())
        if current:
            self._stack.set_visible_child_name(current)

    # ── Keybinds ──────────────────────────────────────────────────────────────

    def _load_keybinds(self):
        sys_text = KEYBINDS_SYSTEM_PATH.read_text() if KEYBINDS_SYSTEM_PATH.exists() else ""
        usr_text = KEYBINDS_USER_PATH.read_text()   if KEYBINDS_USER_PATH.exists()   else ""
        self._keybinds_system_lines = sys_text.splitlines()
        self._keybinds_user_lines   = usr_text.splitlines()
        self._keybinds_all   = _parse_keybinds(sys_text, "SYSTEM") + _parse_keybinds(usr_text, "USER")
        self._keybinds_saved = deepcopy(self._keybinds_all)

    # ── Row builders ──────────────────────────────────────────────────────────

    def _entry_row(self, title: str, keys: list[str]) -> Adw.EntryRow:
        row = Adw.EntryRow(title=title)
        val = get_nested(self._config, keys, "")
        row.set_text(str(val) if val else "")
        def on_changed(r, k=keys):
            set_nested(self._config, k, r.get_text())
            self._mark_unsaved()
        row.connect("changed", on_changed)
        return row

    def _switch_row(self, title: str, keys: list[str], subtitle: str = "") -> Adw.SwitchRow:
        row = Adw.SwitchRow(title=title)
        if subtitle:
            row.set_subtitle(subtitle)
        row.set_active(bool(get_nested(self._config, keys, False)))
        def on_toggle(r, _p, k=keys):
            set_nested(self._config, k, r.get_active())
            self._mark_unsaved()
        row.connect("notify::active", on_toggle)
        return row

    def _combo_row(self, title: str, keys: list[str], choices: list[str]) -> Adw.ComboRow:
        row = Adw.ComboRow(title=title)
        store = Gtk.StringList()
        for c in choices:
            store.append(c)
        row.set_model(store)
        val = get_nested(self._config, keys, choices[0] if choices else "")
        if val in choices:
            row.set_selected(choices.index(val))
        def on_changed(r, _p, k=keys, ch=choices):
            idx = r.get_selected()
            if 0 <= idx < len(ch):
                set_nested(self._config, k, ch[idx])
                self._mark_unsaved()
        row.connect("notify::selected", on_changed)
        return row

    def _spin_row(self, title: str, keys: list[str],
                  min_val=0, max_val=9_999_999, step=1, subtitle: str = "") -> Adw.SpinRow:
        adj = Gtk.Adjustment(
            value=float(get_nested(self._config, keys, 0) or 0),
            lower=min_val, upper=max_val, step_increment=step,
        )
        row = Adw.SpinRow(title=title, adjustment=adj)
        if subtitle:
            row.set_subtitle(subtitle)
        def on_changed(r, k=keys):
            set_nested(self._config, k, int(r.get_value()))
            self._mark_unsaved()
        row.connect("changed", on_changed)
        return row

    def _combo_row_direct(self, title: str, choices: list[str], current: str,
                          on_change, subtitle: str = "") -> Adw.ComboRow:
        row = Adw.ComboRow(title=title)
        if subtitle:
            row.set_subtitle(subtitle)

        if not choices:
            choices = ["No options found"]
            row.set_sensitive(False)

        store = Gtk.StringList()
        for c in choices:
            store.append(c)
        row.set_model(store)

        selected = 0
        if current in choices:
            selected = choices.index(current)
        row.set_selected(selected)

        def on_selected(r, _p, ch=choices):
            idx = r.get_selected()
            if 0 <= idx < len(ch):
                on_change(ch[idx])
                self._mark_unsaved()

        row.connect("notify::selected", on_selected)
        return row

    def _waybar_layout_options(self) -> list[str]:
        if not WAYBAR_LAYOUTS_DIR.exists():
            return []
        return sorted([p.name for p in WAYBAR_LAYOUTS_DIR.iterdir() if p.is_file()])

    def _waybar_style_options(self) -> list[str]:
        if not WAYBAR_STYLES_DIR.exists():
            return []
        return sorted([p.stem for p in WAYBAR_STYLES_DIR.glob("*.css") if p.is_file()])

    def _waybar_current_layout_name(self) -> str:
        raw = str(get_nested(self._config, ["components", "bar", "waybarConfig"], "~/.config/waybar/config"))
        fallback = Path(raw.replace("~", str(HOME)))
        if WAYBAR_CONFIG_LINK.exists():
            try:
                return WAYBAR_CONFIG_LINK.resolve().name
            except Exception:
                pass
        return fallback.name

    def _waybar_current_style_name(self) -> str:
        raw = str(get_nested(self._config, ["components", "bar", "waybarStyle"], "~/.config/waybar/style.css"))
        fallback = Path(raw.replace("~", str(HOME)))
        if WAYBAR_STYLE_LINK.exists():
            try:
                return WAYBAR_STYLE_LINK.resolve().stem
            except Exception:
                pass
        return fallback.stem

    def _waybar_layout_row(self) -> Adw.ComboRow:
        choices = self._waybar_layout_options()
        current = self._waybar_current_layout_name()
        custom_prefix = "Custom: "
        if current and current not in choices:
            choices = [custom_prefix + current] + choices

        def on_change(choice: str):
            if choice.startswith(custom_prefix) or choice == "No options found":
                return
            set_nested(self._config, ["components", "bar", "waybarConfig"], f"~/.config/waybar/configs/{choice}")
            set_nested(self._config, ["components", "bar", "waybarLayoutPreset"], choice)

        return self._combo_row_direct(
            "Layout preset",
            choices,
            custom_prefix + current if current and current not in choices else current,
            on_change,
            subtitle="Based on ~/.config/hypr/scripts/WaybarLayout.sh options",
        )

    def _waybar_style_row(self) -> Adw.ComboRow:
        choices = self._waybar_style_options()
        current = self._waybar_current_style_name()
        custom_prefix = "Custom: "
        if current and current not in choices:
            choices = [custom_prefix + current] + choices

        def on_change(choice: str):
            if choice.startswith(custom_prefix) or choice == "No options found":
                return
            set_nested(self._config, ["components", "bar", "waybarStyle"], f"~/.config/waybar/style/{choice}.css")
            set_nested(self._config, ["components", "bar", "waybarStylePreset"], choice)

        return self._combo_row_direct(
            "Style preset",
            choices,
            custom_prefix + current if current and current not in choices else current,
            on_change,
            subtitle="Based on ~/.config/hypr/scripts/WaybarStyles.sh options",
        )

    def _waybar_apply_row(self) -> Adw.ActionRow:
        row = Adw.ActionRow(
            title="Apply preset now",
            subtitle="Restart Waybar immediately with selected layout/style",
        )
        btn = Gtk.Button(label="Apply")
        btn.add_css_class("suggested-action")

        def _on_apply(_btn):
            prev_cfg = str(WAYBAR_CONFIG_LINK.resolve()) if WAYBAR_CONFIG_LINK.exists() else ""
            prev_sty = str(WAYBAR_STYLE_LINK.resolve()) if WAYBAR_STYLE_LINK.exists() else ""
            cfg_raw = str(get_nested(self._config, ["components", "bar", "waybarConfig"], "~/.config/waybar/config"))
            sty_raw = str(get_nested(self._config, ["components", "bar", "waybarStyle"], "~/.config/waybar/style.css"))
            cfg = str(Path(cfg_raw.replace("~", str(HOME))))
            sty = str(Path(sty_raw.replace("~", str(HOME))))
            sync_waybar_links(cfg, sty)
            ok = apply_waybar(True, cfg, sty, restart=True)
            if ok:
                self._toast("Waybar preset applied")
            else:
                if prev_cfg and prev_sty:
                    sync_waybar_links(prev_cfg, prev_sty)
                    apply_waybar(True, prev_cfg, prev_sty, restart=True)
                reason = _waybar_last_error_summary(style_path=sty)
                style_name = Path(sty).name
                msg = f"Waybar failed for {style_name}; restored previous working preset"
                if reason:
                    msg += f" ({reason})"
                self._toast(msg, timeout=4)

        btn.connect("clicked", _on_apply)
        row.add_suffix(btn)
        row.set_activatable_widget(btn)
        return row

    def _waybar_preview_row(self) -> Adw.ActionRow:
        row = Adw.ActionRow(
            title="Preview",
            subtitle="Placeholder only for now; add screenshots later",
        )

        frame = Gtk.Frame()
        frame.set_hexpand(True)
        frame.set_vexpand(False)
        frame.set_size_request(540, 180)

        box = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=10)
        box.set_valign(Gtk.Align.CENTER)
        box.set_halign(Gtk.Align.CENTER)
        box.set_margin_top(18)
        box.set_margin_bottom(18)
        box.set_margin_start(18)
        box.set_margin_end(18)

        icon = Gtk.Image.new_from_icon_name("image-x-generic-symbolic")
        icon.set_pixel_size(56)

        title = Gtk.Label(label="Waybar Preview Placeholder")
        title.add_css_class("title-4")

        subtitle = Gtk.Label(label="When ready, replace with per-preset screenshots")
        subtitle.add_css_class("dim-label")

        box.append(icon)
        box.append(title)
        box.append(subtitle)
        frame.set_child(box)
        row.set_child(frame)
        return row

    def _group(self, title: str, rows: list, description: str = "") -> Adw.PreferencesGroup:
        group = Adw.PreferencesGroup(title=title)
        if description:
            group.set_description(description)
        for row in rows:
            group.add(row)
        return group

    def _page(self, groups: list[Adw.PreferencesGroup]) -> Adw.PreferencesPage:
        page = Adw.PreferencesPage()
        for g in groups:
            page.add(g)
        return page

    # ── Pages ─────────────────────────────────────────────────────────────────

    def _build_general_page(self) -> Adw.PreferencesPage:
        return self._page([
            self._group("System", [
                self._entry_row("Compositor", ["compositor"]),
                self._entry_row("Terminal",   ["terminal"]),
                self._entry_row("Monitor",    ["monitor"]),
            ]),
            self._group("Paths", [
                self._entry_row("Scripts",   ["paths", "scripts"]),
                self._entry_row("Cache",     ["paths", "cache"]),
                self._entry_row("Wallpaper", ["paths", "wallpaper"]),
                self._entry_row("Steam",     ["paths", "steam"]),
            ]),
            self._group("Ollama", [
                self._entry_row("URL",   ["ollama", "url"]),
                self._entry_row("Model", ["ollama", "model"]),
            ]),
            self._group("Matugen", [
                self._combo_row("Scheme type", ["matugen", "schemeType"], [
                    "scheme-fidelity", "scheme-tonal-spot", "scheme-content",
                    "scheme-expressive", "scheme-monochrome", "scheme-neutral",
                    "scheme-rainbow", "scheme-fruit-salad",
                ]),
                self._entry_row("KDE color scheme name", ["matugen", "kdeColorScheme"]),
            ]),
            self._group("Performance", [
                self._switch_row("Optimization mode", ["optimization", "enabled"],
                                 subtitle="Disables animations, blur, and shadows"),
            ]),
        ])

    def _build_bar_page(self) -> Adw.PreferencesPage:
        return self._page([
            self._group("Bar", [
                self._switch_row("Enabled", ["components", "bar", "enabled"]),
                self._combo_row("Backend", ["components", "bar", "backend"], ["waybar", "quickshell"]),
                self._entry_row("Waybar config path", ["components", "bar", "waybarConfig"]),
                self._entry_row("Waybar style path",  ["components", "bar", "waybarStyle"]),
            ]),
            self._group("Waybar presets", [
                self._waybar_layout_row(),
                self._waybar_style_row(),
                self._waybar_apply_row(),
            ], description="Switch among existing Waybar layouts/styles without Rofi"),
            self._group("Waybar preview", [
                self._waybar_preview_row(),
            ]),
            self._group("Widgets", [
                self._switch_row("Volume",    ["components", "bar", "volume"]),
                self._switch_row("Calendar",  ["components", "bar", "calendar"]),
                self._switch_row("Bluetooth", ["components", "bar", "bluetooth"]),
            ]),
            self._group("Weather", [
                self._switch_row("Enabled", ["components", "bar", "weather", "enabled"]),
                self._entry_row("City",     ["components", "bar", "weather", "city"]),
            ]),
            self._group("Wifi", [
                self._switch_row("Enabled",  ["components", "bar", "wifi", "enabled"]),
                self._entry_row("Interface", ["components", "bar", "wifi", "interface"]),
            ]),
            self._group("Music / MPRIS", [
                self._switch_row("Enabled",           ["components", "bar", "music", "enabled"]),
                self._entry_row("Preferred player",    ["components", "bar", "music", "preferredPlayer"]),
                self._combo_row("Visualizer",          ["components", "bar", "music", "visualizer"],
                                ["wave", "bars", "off"]),
                self._switch_row("Visualizer top",     ["components", "bar", "music", "visualizerTop"]),
                self._switch_row("Visualizer bottom",  ["components", "bar", "music", "visualizerBottom"]),
            ]),
        ])

    def _build_components_page(self) -> Adw.PreferencesPage:
        return self._page([
            self._group("Components", [
                self._switch_row("App launcher",    ["components", "appLauncher"]),
                self._switch_row("Window switcher", ["components", "windowSwitcher"]),
                self._switch_row("Notifications",   ["components", "notifications"]),
                self._switch_row("Lockscreen",      ["components", "lockscreen"]),
                self._switch_row("Smart home",      ["components", "smartHome"]),
            ]),
            self._group("Power menu", [
                self._switch_row("Enabled", ["components", "powerMenu", "enabled"]),
            ]),
            self._group("Wallpaper selector", [
                self._switch_row("Enabled",        ["components", "wallpaperSelector", "enabled"]),
                self._switch_row("Show color dots", ["components", "wallpaperSelector", "showColorDots"]),
            ]),
        ])

    def _build_power_page(self) -> Adw.PreferencesPage:
        return self._page([
            self._group("Device", [
                self._combo_row("Device type", ["power", "deviceType"],
                                ["auto", "laptop", "desktop"]),
            ]),
            self._group("Profile", [
                self._combo_row("Power profile", ["power", "profile"],
                                ["power-saver", "balanced", "performance"]),
            ]),
        ])

    def _build_wallpaper_page(self) -> Adw.PreferencesPage:
        return self._page([
            self._group("General", [
                self._switch_row("Mute wallpaper audio", ["wallpaperMute"]),
            ]),
            self._group("Selector", [
                self._combo_row("Display mode",
                                ["components", "wallpaperSelector", "displayMode"],
                                ["grid", "list", "hex", "slice"]),
                self._switch_row("Auto change",
                                 ["components", "wallpaperSelector", "autoChangeEnabled"]),
                self._spin_row("Auto change interval (minutes)",
                               ["components", "wallpaperSelector", "autoChangeIntervalMinutes"],
                               min_val=1, max_val=1440, step=5),
                self._spin_row("Columns",
                               ["components", "wallpaperSelector", "wallhavenColumns"],
                               min_val=1, max_val=20),
                self._spin_row("Rows",
                               ["components", "wallpaperSelector", "wallhavenRows"],
                               min_val=1, max_val=20),
            ]),
            self._group("Paths", [
                self._entry_row("Steam Workshop",  ["paths", "steamWorkshop"]),
                self._entry_row("Steam WE assets", ["paths", "steamWeAssets"]),
            ]),
        ])

    def _build_integrations_page(self) -> Adw.PreferencesPage:
        return self._page([
            self._group("Theme integrations", [
                self._entry_row("Kitty",         ["integrations", "kitty"]),
                self._entry_row("KDE colors",    ["integrations", "kde"]),
                self._entry_row("VSCode",        ["integrations", "vscode"]),
                self._entry_row("Vesktop",       ["integrations", "vesktop"]),
                self._entry_row("Zen browser",   ["integrations", "zen"]),
                self._entry_row("Spicetify",     ["integrations", "spicetify"]),
                self._entry_row("Spicetify CSS", ["integrations", "spicetifyCss"]),
                self._entry_row("Yazi",          ["integrations", "yazi"]),
                self._entry_row("Qt6ct",         ["integrations", "qt6ct"]),
            ]),
        ])

    def _build_apps_page(self) -> Adw.PreferencesPage:
        page = Adw.PreferencesPage()
        group = Adw.PreferencesGroup(
            title="App customization",
            description="Override display name, icon, and appearance per app",
        )

        for app_key, app_data in self._apps.items():
            if app_key.startswith("_"):
                continue
            if not isinstance(app_data, dict):
                continue

            expander = Adw.ExpanderRow(
                title=app_data.get("displayName") or app_key,
                subtitle=", ".join(app_data.get("tags") or []) or app_key,
            )

            def _make_entry(a_key: str, field: str, label: str, initial: str) -> Adw.EntryRow:
                r = Adw.EntryRow(title=label)
                r.set_text(str(initial or ""))
                def on_ch(row, k=a_key, f=field):
                    if k not in self._apps or not isinstance(self._apps[k], dict):
                        self._apps[k] = {}
                    text = row.get_text()
                    if f == "tags":
                        self._apps[k][f] = [t.strip() for t in text.split(",") if t.strip()]
                    else:
                        self._apps[k][f] = text
                    self._mark_unsaved()
                r.connect("changed", on_ch)
                return r

            def _make_switch(a_key: str, field: str, label: str, initial: bool) -> Adw.SwitchRow:
                r = Adw.SwitchRow(title=label)
                r.set_active(bool(initial))
                def on_tg(row, _p, k=a_key, f=field):
                    if k not in self._apps or not isinstance(self._apps[k], dict):
                        self._apps[k] = {}
                    self._apps[k][f] = row.get_active()
                    self._mark_unsaved()
                r.connect("notify::active", on_tg)
                return r

            expander.add_row(_make_entry(app_key, "displayName", "Display name",
                                         app_data.get("displayName", "")))
            expander.add_row(_make_entry(app_key, "icon", "Icon glyph",
                                         app_data.get("icon", "")))
            expander.add_row(_make_entry(app_key, "tags", "Tags (comma separated)",
                                         ", ".join(app_data.get("tags") or [])))
            expander.add_row(_make_switch(app_key, "hidden", "Hidden",
                                          app_data.get("hidden", False)))
            expander.add_row(_make_entry(app_key, "background", "Background path",
                                         app_data.get("background", "")))
            group.add(expander)

        page.add(group)
        return page

    def _build_intervals_page(self) -> Adw.PreferencesPage:
        return self._page([
            self._group("Poll intervals (milliseconds)", [
                self._spin_row("Weather",             ["intervals", "weatherPollMs"],
                               min_val=1000, max_val=3_600_000, step=1000),
                self._spin_row("Wifi",                ["intervals", "wifiPollMs"],
                               min_val=1000, max_val=60_000, step=1000),
                self._spin_row("Smart home",          ["intervals", "smartHomePollMs"],
                               min_val=1000, max_val=60_000, step=1000),
                self._spin_row("Ollama status",       ["intervals", "ollamaStatusPollMs"],
                               min_val=1000, max_val=60_000, step=1000),
                self._spin_row("Notification expire", ["intervals", "notificationExpireMs"],
                               min_val=500,  max_val=30_000, step=500),
            ]),
        ])

    def _build_keybinds_page(self) -> Adw.PreferencesPage:
        page = Adw.PreferencesPage()

        # Filter controls
        filter_group = Adw.PreferencesGroup()
        filter_box = Gtk.Box(orientation=Gtk.Orientation.HORIZONTAL, spacing=8)
        filter_box.set_margin_top(6)
        filter_box.set_margin_bottom(6)

        self._kb_search = Gtk.SearchEntry(placeholder_text="Filter keybinds…", hexpand=True)
        filter_box.append(self._kb_search)

        self._kb_all_btn = Gtk.ToggleButton(label="All",  active=True)
        self._kb_on_btn  = Gtk.ToggleButton(label="On",   group=self._kb_all_btn)
        self._kb_off_btn = Gtk.ToggleButton(label="Off",  group=self._kb_all_btn)
        for btn in (self._kb_all_btn, self._kb_on_btn, self._kb_off_btn):
            btn.add_css_class("flat")
            filter_box.append(btn)

        refresh_btn = Gtk.Button(label="↺ Reload")
        refresh_btn.add_css_class("flat")
        filter_box.append(refresh_btn)

        filter_row = Adw.ActionRow()
        filter_row.set_child(filter_box)
        filter_group.add(filter_row)
        page.add(filter_group)

        self._kb_group = Adw.PreferencesGroup(title="Binds")
        page.add(self._kb_group)

        self._kb_state = "all"
        self._kb_query = ""
        self._rebuild_keybind_rows()

        self._kb_search.connect("search-changed", lambda s: self._kb_filter_update(query=s.get_text()))
        self._kb_all_btn.connect("toggled",  lambda b: b.get_active() and self._kb_filter_update(state="all"))
        self._kb_on_btn.connect("toggled",   lambda b: b.get_active() and self._kb_filter_update(state="on"))
        self._kb_off_btn.connect("toggled",  lambda b: b.get_active() and self._kb_filter_update(state="off"))
        refresh_btn.connect("clicked",       lambda _: self._reload_keybinds())

        return page

    def _kb_filter_update(self, *, query: str | None = None, state: str | None = None):
        if query is not None:
            self._kb_query = query.lower()
        if state is not None:
            self._kb_state = state
        self._rebuild_keybind_rows()

    def _reload_keybinds(self):
        self._load_keybinds()
        self._rebuild_keybind_rows()

    def _rebuild_keybind_rows(self):
        # Clear rows (skip non-ActionRow children like the header)
        to_remove = []
        child = self._kb_group.get_first_child()
        while child:
            if isinstance(child, Adw.ActionRow):
                to_remove.append(child)
            child = child.get_next_sibling()
        for c in to_remove:
            self._kb_group.remove(c)

        q = self._kb_query
        state = self._kb_state
        shown = 0

        for bind in self._keybinds_all:
            if state == "on"  and not bind["enabled"]: continue
            if state == "off" and     bind["enabled"]: continue
            row_text = f"{bind['source']} {bind['mods']} {bind['key']} {bind['dispatcher']} {bind['arg']} {bind['description']}".lower()
            if q and q not in row_text:
                continue

            mods_str = f"{bind['mods']} + " if bind["mods"].strip() else ""
            subtitle  = f"{mods_str}{bind['key']}  →  {bind['dispatcher']}"
            if bind["arg"]:
                subtitle += f",  {bind['arg']}"

            row = Adw.ActionRow(
                title=GLib.markup_escape_text(bind["description"] or bind["dispatcher"]),
                subtitle=GLib.markup_escape_text(subtitle),
            )

            source_lbl = Gtk.Label(
                label=bind["source"],
                css_classes=["caption", "dim-label"],
                valign=Gtk.Align.CENTER,
            )
            sw = Gtk.Switch(valign=Gtk.Align.CENTER, active=bind["enabled"])

            def on_sw(s, _p, uid=bind["uid"]):
                for b in self._keybinds_all:
                    if b["uid"] == uid:
                        b["enabled"] = s.get_active()
                        break
                self._mark_unsaved()

            sw.connect("notify::active", on_sw)
            row.add_suffix(source_lbl)
            row.add_suffix(sw)
            self._kb_group.add(row)
            shown += 1

        self._kb_group.set_title(f"Binds ({shown})")


# ── Application ───────────────────────────────────────────────────────────────

class ConfigApp(Adw.Application):
    def __init__(self):
        super().__init__(
            application_id="com.sdrxdots.ConfigPanel",
            flags=Gio.ApplicationFlags.FLAGS_NONE,
        )
        self._win = None
        self.connect("activate", self._on_activate)

    def _on_activate(self, app):
        if self._win is None:
            self._win = ConfigWindow(application=app)
        self._win.present()


if __name__ == "__main__":
    import sys
    app = ConfigApp()
    sys.exit(app.run(None))
