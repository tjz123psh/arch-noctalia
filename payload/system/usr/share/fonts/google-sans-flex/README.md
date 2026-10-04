# Google Sans Flex (rounded build)

Source: https://github.com/google/fonts/tree/main/ofl/googlesansflex   (SIL OFL 1.1 -> OFL.txt)
Upstream file: GoogleSansFlex[GRAD,ROND,opsz,slnt,wdth,wght].ttf
Local change: variable axis ROND pinned to 100 (max roundness) and GRAD pinned to 0 using
              fontTools varLib.instancer; the named instances (Thin..Black + Italic) were
              re-added afterwards so fontconfig can still select real weights.
              Remaining variable axes: opsz 6-144, wght 1-1000, slnt -10-0, wdth 25-151.
Family name:  "Google Sans Flex"

Rollback: sudo rm -rf /usr/share/fonts/google-sans-flex && fc-cache -f
