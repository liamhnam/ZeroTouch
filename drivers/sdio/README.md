# SDIO

Snappy Driver Installer Origin, copied to `\AutoInstaller\sdio` on the USB and run offline (twice) by `payload/AutoInstaller/steps/10-drivers.ps1` with `-autoinstall -autoclose -license -norestorepnt`.

Source: `SDIO_Update.torrent` from [glenn.delahoy.com](https://www.glenn.delahoy.com/snappy-driver-installer-origin/) (SDIO R887), downloading **only** these packs (+ their `indexes/SDIO/*.bin`) for Intel 9th–14th gen desktops without a discrete GPU — about 5.2 GB instead of 70 GB:

| Pack | Why |
|---|---|
| `DP_Chipset` | Intel chipset, ME, SMBus, PMC, thermal |
| `DP_Video_Intel_DCH31x`, `DP_Video_Intel_DCH32x` | Intel UHD 6xx (9th/10th gen) and Iris Xe / UHD 7xx (11th–14th gen) |
| `DP_Sounds_Realtek_DCH`, `DP_Sounds_Realtek`, `DP_Sounds_HDMI` | Realtek HD audio (DCH and legacy), HDMI audio |
| `DP_LAN_Intel`, `DP_LAN_Realtek-NT` | Onboard Ethernet |
| `DP_MassStorage` | Intel RST / VMD, SATA/NVMe controllers |
| `DP_xUSB`, `DP_zUSB3`, `DP_USB_SDIO01`, `DP_HID_SDIO01` | USB controllers, HID |

Layout:

```
drivers/sdio/
├── SDIO_x64_R887.exe
├── drivers/         DP_*.7z
├── indexes/SDIO/    DP_*.bin (matching the packs)
├── tools/, scripts/, docs/
```

Every file must be under 4 GiB (the USB drive is FAT32); the largest pack is 2.1 GB. Nothing here is committed to git.
