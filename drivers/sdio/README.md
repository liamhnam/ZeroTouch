# SDIO

Snappy Driver Installer Origin, copied to `\AutoInstaller\sdio` on the USB and run offline (twice) by `payload/AutoInstaller/steps/10-drivers.ps1` with `-autoinstall -autoclose -license -norestorepnt`.

Source: `SDIO_Update.torrent` from [glenn.delahoy.com](https://www.glenn.delahoy.com/snappy-driver-installer-origin/) (SDIO R887), downloading **only** these packs (+ their `indexes/SDIO/*.bin`) for Intel 9th–14th gen desktops without a discrete GPU — about 5.2 GB instead of 70 GB:

| Pack | Why |
|---|---|
| `DP_Chipset` | Intel chipset, ME, SMBus, PMC, thermal (An toàn, cần thiết) |
| `DP_Video_Intel_DCH31x`, `DP_Video_Intel_DCH32x` | Intel UHD 6xx (9th/10th) và Iris Xe / UHD 7xx (11th–14th) |
| `DP_WLAN-WiFi`, `DP_LAN_Realtek-NT`, `DP_LAN_Intel` | Wi-Fi và mạng LAN onboard |
| *(Tùy chọn)* `DP_Sounds_Realtek_DCH` | Âm thanh Realtek HD Audio |

> [!WARNING]
> **KHÔNG NÊN TẢI** `DP_MassStorage` (gây nguy cơ màn hình xanh BSOD 0x7B do đè driver AHCI/NVMe chuẩn của Microsoft) và `DP_xUSB` (dễ làm đơ/ngắt cổng USB và màn hình cảm ứng).

Layout:

```
drivers/sdio/
├── SDIO_x64_R887.exe
├── drivers/         DP_*.7z
├── indexes/SDIO/    DP_*.bin (matching the packs)
├── tools/, scripts/, docs/
```

Every file must be under 4 GiB (the USB drive is FAT32); the largest pack is 2.1 GB. Nothing here is committed to git.
