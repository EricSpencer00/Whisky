# Upstream, for Eric to review

Nothing here has been filed. Each entry says what it is and whether I think it
should go anywhere.

## Wine dbghelp DWARF divide — do not file

Already fixed upstream, after the CrossOver 26.1.0 tree we build from. Our
patch is a backport of their change. Nothing to report.

## DXMT: SwapDeviceContextState returns no previous state — worth a PR

Direct2D releases the previous state unconditionally, so returning null on the
first swap faults inside `d2d1`. One line: give the context a state at
construction.

Small, self-contained, and it is what stops the Rockstar Games Launcher and
anything else using an `ID2D1DCRenderTarget`.

## DXMT: no GDI interop on textures — worth a PR

`ID2D1DCRenderTarget::BindDC` queries `IDXGISurface1` and does not check the
result, so a texture that cannot produce a device context leaves d2d1 with a
null surface and it faults on present. Implemented `GetDC`/`ReleaseDC` over a
staging copy and a DIB section.

Wine's unchecked QueryInterface there is arguably its own bug, but the missing
interface is ours to provide.

## DXMT: cross-process presentation — ask on issue 141 first, do not open a PR

3Shain/dxmt#141 is this, and the code says "not supported yet", which reads like
there is a plan. What works here: parent a `WS_CHILD` window that the presenting
process owns into the target, on a thread that pumps messages, and blit into it.

It is a way around a `winemac.drv` limitation rather than a fix for one — there
is no Cocoa view on the far side of a process boundary to hang a Metal layer on.
Worth asking whether that is the direction they want before sending a diff.

## Not established

- Whether the child-window approach holds up outside Chromium. Two apps is not a
  sample.
- The GZDoom colour fault. Red and blue sit at 255 with the image in green.
  D3D9 through the same MoltenVK is correct, so it is GZDoom's own setup, but I
  have not found where.
