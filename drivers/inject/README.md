# INJECT

Drivers injected into Windows during installation. `make-usb` copies this folder to `$WinPEDriver$` on the USB drive; `src/pe.cmd` loads every `.inf` in Windows PE (`drvload`) and adds them to the new installation (`dism /Add-Driver /Recurse`), so the devices work from the very first boot. One sub-folder per device, containing the extracted `.inf`/`.sys`/`.cat` files (not installers).

| Folder | Device | Source |
|---|---|---|
| `mercusys-mu6h/` | Mercusys MU6H (RTL8811CU, `USB\VID_2C4E&PID_0105`, `USB\VID_0BDA&PID_C811`) | `MU6H(EU)_V1.30_250716_Windows.zip` from mercusys.com, copy the **whole** folder `plugins\Driver Files\Driver\Windows_11_64bit` (WHQL, 1030.29.0329.2019) – the INF also lists `LIM_MU6H_1.txt`/`PBR_MU6H_1.txt`; without them DISM rejects the package |

Storage drivers go here too when Windows PE cannot see the internal disk ("No disk satisfied the given criteria", e.g. Intel VMD/RST): extract the Intel RST "F6" driver (folder with `iaStorVD.inf`) into its own sub-folder.

Driver files are not committed to git – download them from the source above.
