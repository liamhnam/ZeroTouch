# WINPE

Storage drivers that Windows PE needs to *see* the internal disk (copied to `$WinPEDriver$` on the USB, loaded with `drvload` and injected into the new installation).

Only needed when the installer stops with "No disk satisfied the given criteria", typically Intel 11th–14th gen machines with **Intel VMD / RST** enabled. Either disable VMD in the BIOS, or extract the Intel RST "F6" driver (the folder with `iaStorVD.inf`) here.
