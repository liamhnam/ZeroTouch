# INJECT

Drivers injected into Windows during installation. `make-usb` copies this folder to `$WinPEDriver$` on the USB drive; `src/pe.cmd` loads every `.inf` in Windows PE (`drvload`) and adds them to the new installation (`dism /Add-Driver /Recurse`), so the devices work from the very first boot. One sub-folder per device, containing the extracted `.inf`/`.sys`/`.cat` files (not installers).

| Folder | Device | Source |
|---|---|---|
| `wifi-mu6h/` | Mercusys MU6H (RTL8811CU, `USB\VID_2C4E&PID_0105`, `USB\VID_0BDA&PID_C811`) | File zip từ mercusys.com, copy toàn bộ thư mục `Windows_11_64bit` chứa `.inf`, `.sys`, `.cat`. |
| `intel-chipset/` | Intel Chipset Device Software (INF Utility) | Tải từ Intel / Asus / GoodM, giải nén bằng lệnh `SetupChipset.exe -extract drivers` |
| `intel-graphics/` | Intel UHD / Iris Xe Graphics | Tải driver DCH từ Intel, dùng 7-Zip giải nén file `.exe` lấy thư mục chứa các file `.inf` đồ họa |

Storage drivers go here too when Windows PE cannot see the internal disk ("No disk satisfied the given criteria", e.g. Intel VMD/RST): extract the Intel RST "F6" driver (folder with `iaStorVD.inf`) into its own sub-folder.

Driver files are not committed to git – download them from the source above.
