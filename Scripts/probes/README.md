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

Build with `make -C Scripts/probes`.

## What these established

- In-process GDI to a window DC composites.
- Cross-process GDI to a foreign window's DC returns success and never reaches
  the screen. Anything relying on it fails silently.
- A `WS_CHILD` window created in process B and parented into a window owned by
  process A *does* composite, including its GDI drawing.
- A Metal layer on such a child does not: `winemac.drv` only has a Cocoa view
  when this process owns the top-level window.

Together those are why DXMT presents cross-process swapchains by blitting into a
child window it owns.
