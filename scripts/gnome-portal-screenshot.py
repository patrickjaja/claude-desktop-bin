#!/usr/bin/env python3
"""
XDG ScreenCast portal screenshot with PipeWire restore token support.

On GNOME Wayland (46+), the org.gnome.Shell.Screenshot D-Bus interface is
restricted and Electron's desktopCapturer triggers a portal permission dialog
on every screenshot. This script uses the ScreenCast portal with restore tokens:
first invocation shows the permission dialog, subsequent invocations reuse the
saved token and capture silently.

Usage: gnome-portal-screenshot.py <output.png> [x y w h]
Exit codes: 0=success, 1=capture error, 2=missing dependencies
"""

import sys
import os
import signal
import subprocess

TOKEN_FILE = os.path.expanduser("~/.config/Claude/pipewire-restore-token")
TIMEOUT_SECS = 15


def main():
    if len(sys.argv) < 2:
        print("Usage: gnome-portal-screenshot.py <output.png> [x y w h]",
              file=sys.stderr)
        return 1

    output_path = sys.argv[1]
    crop = None
    if len(sys.argv) >= 6:
        crop = tuple(int(x) for x in sys.argv[2:6])

    try:
        import gi
        gi.require_version('Gst', '1.0')
        from gi.repository import GLib, Gio, Gst
    except (ImportError, ValueError) as e:
        print(f"[portal-screenshot] missing deps: {e}", file=sys.stderr)
        return 2

    Gst.init(None)

    # Load saved restore token
    restore_token = ""
    try:
        with open(TOKEN_FILE) as f:
            restore_token = f.read().strip()
    except FileNotFoundError:
        pass

    bus = Gio.bus_get_sync(Gio.BusType.SESSION)
    loop = GLib.MainLoop()
    state = {
        "node_id": None,
        "new_token": "",
        "session": None,
        "error": None,
        "done": False,
    }

    unique = bus.get_unique_name().replace(".", "_").replace(":", "")
    counter = [0]

    def next_token():
        counter[0] += 1
        return f"claude_{os.getpid()}_{counter[0]}"

    def subscribe_response(handle_path, callback):
        """Subscribe to portal Response signal, auto-unsubscribe on receipt."""
        sub = [None]

        def on_signal(conn, sender, path, iface, sig_name, params):
            bus.signal_unsubscribe(sub[0])
            resp, results = params.unpack()
            callback(resp, results)

        sub[0] = bus.signal_subscribe(
            "org.freedesktop.portal.Desktop",
            "org.freedesktop.portal.Request",
            "Response",
            handle_path,
            None,
            Gio.DBusSignalFlags.NO_MATCH_RULE,
            on_signal,
        )
        return sub[0]

    def portal_call(method, args_variant):
        """Call a ScreenCast portal method."""
        return bus.call_sync(
            "org.freedesktop.portal.Desktop",
            "/org/freedesktop/portal/desktop",
            "org.freedesktop.portal.ScreenCast",
            method,
            args_variant,
            None,
            Gio.DBusCallFlags.NONE,
            TIMEOUT_SECS * 1000,
            None,
        )

    def fail(msg):
        state["error"] = msg
        if loop.is_running():
            loop.quit()

    # Step 3: Start the session (may show dialog if no valid restore token)
    def do_start():
        ht = next_token()
        handle = f"/org/freedesktop/portal/desktop/request/{unique}/{ht}"

        def on_start(resp, results):
            if resp != 0:
                fail(f"Start rejected (response={resp})")
                return
            # Extract PipeWire streams
            streams = results.get("streams", None)
            new_token = results.get("restore_token", "")
            if new_token:
                state["new_token"] = new_token
            if streams:
                # streams is a(ua{sv}) — list of (node_id, properties)
                stream_list = streams.unpack() if hasattr(streams, 'unpack') else streams
                if stream_list:
                    first = stream_list[0]
                    state["node_id"] = first[0] if isinstance(first, tuple) else first
            state["done"] = True
            loop.quit()

        subscribe_response(handle, on_start)

        portal_call("Start", GLib.Variant("(osa{sv})", (
            state["session"],
            "",  # parent_window
            {"handle_token": GLib.Variant("s", ht)},
        )))

    # Step 2: SelectSources (monitor, persist mode, restore token)
    def do_select():
        ht = next_token()
        handle = f"/org/freedesktop/portal/desktop/request/{unique}/{ht}"

        def on_select(resp, results):
            if resp != 0:
                fail(f"SelectSources rejected (response={resp})")
                return
            do_start()

        subscribe_response(handle, on_select)

        opts = {
            "handle_token": GLib.Variant("s", ht),
            "types": GLib.Variant("u", 1),           # MONITOR
            "multiple": GLib.Variant("b", False),
            "persist_mode": GLib.Variant("u", 2),     # until explicitly revoked
        }
        if restore_token:
            opts["restore_token"] = GLib.Variant("s", restore_token)

        portal_call("SelectSources", GLib.Variant("(oa{sv})", (
            state["session"],
            opts,
        )))

    # Step 1: CreateSession
    def do_create():
        ht = next_token()
        st = f"claude_sess_{os.getpid()}"
        handle = f"/org/freedesktop/portal/desktop/request/{unique}/{ht}"

        def on_create(resp, results):
            if resp != 0:
                fail(f"CreateSession rejected (response={resp})")
                return
            session_handle = results.get("session_handle", "")
            if not session_handle:
                fail("No session handle returned")
                return
            state["session"] = session_handle
            do_select()

        subscribe_response(handle, on_create)

        portal_call("CreateSession", GLib.Variant("(a{sv})", ({
            "handle_token": GLib.Variant("s", ht),
            "session_handle_token": GLib.Variant("s", st),
        },)))

    # Timeout guard
    def on_timeout():
        if not state["done"]:
            fail("Timed out waiting for portal response")
        return False

    GLib.timeout_add_seconds(TIMEOUT_SECS, on_timeout)

    # Kick off the portal session chain
    try:
        do_create()
        loop.run()
    except Exception as e:
        fail(str(e))

    if state["error"]:
        print(f"[portal-screenshot] {state['error']}", file=sys.stderr)
        return 1

    if not state["node_id"]:
        print("[portal-screenshot] no PipeWire node ID received", file=sys.stderr)
        return 1

    # Save restore token for next time (no more dialogs)
    if state["new_token"]:
        try:
            os.makedirs(os.path.dirname(TOKEN_FILE), exist_ok=True)
            with open(TOKEN_FILE, "w") as f:
                f.write(state["new_token"])
            print("[portal-screenshot] restore token saved", file=sys.stderr)
        except OSError as e:
            print(f"[portal-screenshot] warning: could not save token: {e}",
                  file=sys.stderr)

    # Capture a frame from PipeWire via GStreamer
    node_id = state["node_id"]
    try:
        pipeline = Gst.parse_launch(
            f'pipewiresrc path={node_id} num-buffers=3 ! '
            f'videorate ! video/x-raw,framerate=1/1 ! '
            f'videoconvert ! pngenc ! filesink location="{output_path}"'
        )
        pipeline.set_state(Gst.State.PLAYING)
        gst_bus = pipeline.get_bus()
        msg = gst_bus.timed_pop_filtered(
            10 * Gst.SECOND,
            Gst.MessageType.EOS | Gst.MessageType.ERROR,
        )
        if msg and msg.type == Gst.MessageType.ERROR:
            err, dbg = msg.parse_error()
            print(f"[portal-screenshot] GStreamer error: {err.message}",
                  file=sys.stderr)
            pipeline.set_state(Gst.State.NULL)
            return 1
        pipeline.set_state(Gst.State.NULL)
    except Exception as e:
        print(f"[portal-screenshot] GStreamer failed: {e}", file=sys.stderr)
        # Fallback: try gst-launch-1.0 CLI
        try:
            subprocess.run([
                "gst-launch-1.0",
                f"pipewiresrc", f"path={node_id}", "num-buffers=3", "!",
                "videorate", "!", "video/x-raw,framerate=1/1", "!",
                "videoconvert", "!", "pngenc", "!",
                "filesink", f"location={output_path}",
            ], timeout=10, check=True, capture_output=True)
        except Exception as e2:
            print(f"[portal-screenshot] gst-launch fallback failed: {e2}",
                  file=sys.stderr)
            return 1

    if not os.path.exists(output_path):
        print("[portal-screenshot] output file not created", file=sys.stderr)
        return 1

    # Crop if coordinates provided
    if crop:
        x, y, w, h = crop
        try:
            from gi.repository import GdkPixbuf
            pixbuf = GdkPixbuf.Pixbuf.new_from_file(output_path)
            pw, ph = pixbuf.get_width(), pixbuf.get_height()
            # Clamp to image bounds
            cx = min(x, pw - 1)
            cy = min(y, ph - 1)
            cw = min(w, pw - cx)
            ch = min(h, ph - cy)
            cropped = GdkPixbuf.Pixbuf.new(
                GdkPixbuf.Colorspace.RGB, pixbuf.get_has_alpha(), 8, cw, ch)
            pixbuf.copy_area(cx, cy, cw, ch, cropped, 0, 0)
            cropped.savev(output_path, "png", [], [])
        except ImportError:
            # Fall back to ImageMagick convert
            try:
                subprocess.run([
                    "convert", output_path,
                    "-crop", f"{w}x{h}+{x}+{y}", "+repage",
                    output_path,
                ], timeout=5, check=True, capture_output=True)
            except Exception:
                pass  # Return uncropped screenshot rather than failing

    # Close the portal session
    if state["session"]:
        try:
            bus.call_sync(
                "org.freedesktop.portal.Desktop",
                state["session"],
                "org.freedesktop.portal.Session",
                "Close",
                None,
                None,
                Gio.DBusCallFlags.NONE,
                1000,
                None,
            )
        except Exception:
            pass

    print("[portal-screenshot] success", file=sys.stderr)
    return 0


if __name__ == "__main__":
    # Don't hang on SIGALRM
    signal.signal(signal.SIGALRM, lambda *_: sys.exit(1))
    signal.alarm(TIMEOUT_SECS + 5)
    sys.exit(main())
