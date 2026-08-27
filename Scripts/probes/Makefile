MINGW ?= x86_64-w64-mingw32-gcc
MINGW_CFLAGS ?= -O1
WINEXE = enumwin.exe winapp.exe paintwin.exe d3dchild.exe d3d9probe.exe d3d12probe.exe
NATIVE = imgstat winshot

all: $(WINEXE) $(NATIVE)

enumwin.exe: enumwin.c ; $(MINGW) $(MINGW_CFLAGS) -o $@ $< -luser32
winapp.exe: winapp.c ; $(MINGW) $(MINGW_CFLAGS) -o $@ $< -lgdi32 -luser32
paintwin.exe: paintwin.c ; $(MINGW) $(MINGW_CFLAGS) -o $@ $< -lgdi32 -luser32
d3d12probe.exe: d3d12probe.c ; $(MINGW) $(MINGW_CFLAGS) -o $@ $< -ld3d12 -ldxgi -luser32 -luuid
d3d9probe.exe: d3d9probe.c ; $(MINGW) $(MINGW_CFLAGS) -o $@ $< -ld3d9 -lgdi32 -luser32
d3dchild.exe: d3dchild.c ; $(MINGW) $(MINGW_CFLAGS) -o $@ $< -ld3d11 -ldxgi -lgdi32 -luser32 -luuid
imgstat: imgstat.swift ; swiftc -O -o $@ $<
winshot: winshot.swift ; swiftc -O -o $@ $<

clean: ; rm -f $(WINEXE) $(NATIVE)
.PHONY: all clean
