# SDIO

Put Snappy Driver Installer Origin here (copied to `\AutoInstaller\sdio` on the USB and run offline by `payload/AutoInstaller/steps/10-drivers.ps1`):

```
drivers/sdio/
├── SDIO_x64_R*.exe
├── drivers/     DP_*.7z driver packs
├── indexes/     SDI/*.bin indexes matching the packs (ship them: building missing indexes on every target machine is slow)
└── tools/
```

For Intel 9th–14th gen desktops without a discrete GPU and with USB Wi-Fi, the packs that matter are: Chipset, LAN (Intel/Realtek/Others), WLAN-WiFi, Video_Intel, Sound (Realtek/Others), MassStorage, Bluetooth, USB, Misc. Every file must be under 4 GiB (the USB drive is FAT32).
