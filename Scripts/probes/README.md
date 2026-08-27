# Probes

Small instruments for deciding *where* a Windows app breaks under Wine, rather
than guessing. Each answers one question and nothing else.

| Probe | Question it answers |
|---|---|
| `enumwin.c` | Does the app have windows, are they visible, and what is the child tree? |
| `winshot.swift` | Which macOS windows exist, on any Space, and are they on screen? |
| `imgstat.swift` | Is a captured window rendered, blank, or fully transparent? |
| `winapp.c` | Positive control: does in-process GDI reach the screen? |
| `paintwin.c` | Does GDI drawing from *another* process reach the screen? (No — see below.) |
| `d3dchild.c` | Does a second process presenting D3D11 into a foreign window reach the screen? |
| `d3d9probe.c` | Does D3D9 work, and does a known colour survive to the screen? |
| `d3d12probe.c` | Does D3D12 work, and at what resource binding tier? |
| `focuswin.c` | Brings a window to the front so it can be captured. |
| `winshot2.swift` | Captures one window through ScreenCaptureKit, on any Space. |
| `sendkeys.c` | Drives an app past a menu, so a run shows more than a title screen. |
| `d3d11probe.c` | Does D3D11 work, at what feature level, and is the colour right? |

`sendkeys` takes a single-word substring of the window title. Wine splits an
argument containing a space, so `sendkeys "Cave Story" ...` finds nothing while
`sendkeys Doukutsu ...` works.

Build with `make -C Scripts/probes`.

## What these established

- In-process GDI to a window DC composites.
- Cross-process GDI to a foreign window's DC returns success and never reaches
  the screen. Anything relying on it fails silently.
- A `WS_CHILD` window created in process B and parented into a window owned by
  process A *does* composite, including its GDI drawing.
- A Metal layer on such a child does not: `winemac.drv` only has a Cocoa view
  when this process owns the top-level window.

- A window whose thread does not pump messages is never composited, however it
  is drawn into.

Together those are why DXMT presents a cross-process swapchain by blitting into
a child window it owns, on a thread of its own that answers messages.

`screencapture -l` returns a fully transparent image for a window on another
Space, which reads as "the app drew nothing". `winshot2` is the check on that,
and `imgstat` scores both so the difference is visible.
