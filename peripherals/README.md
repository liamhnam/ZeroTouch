# PERIPHERALS

Công cụ **Thiết bị ngoại vi** (shortcut `Thiet bi ngoai vi` trên Desktop, chép vào `C:\ZeroTouch\Peripherals` lúc cài máy): tick thiết bị đang cắm → **Cài đặt**. Chạy lại bất cứ lúc nào (đổi máy in…). Log: `C:\ZeroTouch\logs\peripherals-*.log`.

Máy in hóa đơn được chọn (Epson / Xprinter / SPRT) luôn có tên hàng đợi **`XP-80C`** và là **máy in mặc định** — đổi hãng máy in không phải cấu hình lại phần mềm POS. Máy in phải **được cắm và bật** khi bấm Cài đặt (công cụ tìm cổng `USB00x` đang kết nối).

Dòng lệnh (thử nghiệm / tự động): `Peripherals.ps1 -Install xprinter-q260,hanel-hn212 [-PortName USB001]`.

## Thiết bị

| Thư mục | Thiết bị | Nội dung cần có | Trạng thái |
|---|---|---|---|
| `xprinter-q260/driver/` | Xprinter Q260 | INF "XP-80C" tách từ `XPrinter Driver Setup V8.2.exe` (`app\Windows x64\*`) | ✅ cài im lặng |
| `sprt-80mm/driver/` | SPRT 80mm | `POS88EN.inf/.GPD` + `Drv2152s.cat` tách từ `SP-DRV2155Win.exe` | ✅ cài im lặng |
| `hanel-hn212/` | Hanel HN212 (đọc CCCD) | `ReadIdCard\` (**không** kèm `Logs\` – chứa ảnh CCCD), `windowsdesktop-runtime-6.0.36-win-x64.exe`, `vcredist2015_2017_2019_2022_x64/x86.exe` | ✅ cài im lặng, tự chạy khi đăng nhập |
| `barcode-icw97201/`, `barcode-zebra-ds9308/` | Máy quét mã 2D | – (chế độ bàn phím, driver có sẵn) | ✅ |
| `epson-tm-t81/` | Epson TM-T81 | `apd\APD_513_T81II.exe` – Epson Advanced Printer Driver 5.13SA (South Asia) từ download-center.epson.com | ✅ wizard Epson (chọn TM-T81II, USB) rồi tự đổi tên queue thành `XP-80C` |
| `ricoh-fi-800r/` | Ricoh fi-800R | `PSIPTWAIN-3_40_2.exe` – PaperStream IP (TWAIN) 3.40.2 từ [pfu.ricoh.com fi-800R](https://www.pfu.ricoh.com/global/scanners/fi/dl/win-11-fi-800r.html) | ✅ wizard PFU |
| `brother-ads-1300/` | Brother ADS-1300 | `Y23B_C1_U_PP-inst-F1.EXE` – Full Driver & Software Package F1 từ [support.brother.com](https://support.brother.com/g/b/downloadtop.aspx?c=us&lang=en&prod=ads1300_us_eu_as) | ✅ wizard Brother |
| `avision-av332u/` | Avision AV332U | `driver\` – TWAIN V6.21 (`AV332U_V6.21.09112026.zip` từ [avision.com](https://www.avision.com/en/download/?model=AV332U)) | ✅ cài im lặng (InstallShield `setup.iss`) |
| `brother-hl-l2361dn/` | Brother HL-L2361DN (in A4) | `driver\32_64\BROHL13A.INF` – Printer Driver 1.11.0.0 (`Y14A_C1-hostm-1110.EXE` từ [support.brother.com](https://support.brother.com/g/b/downloadtop.aspx?c=vn&lang=en&prod=hll2361dn_as)) | ✅ cài im lặng; Windows tự tạo máy in khi cắm USB (tên riêng, không phải `XP-80C`) |

Chỉ cần thả bộ cài vào đúng thư mục rồi tạo lại USB — không phải sửa script.

## Thêm thiết bị

1. Tạo `peripherals\<id>\install.ps1` (`param([string] $Dir)`; máy in thêm `[string] $PortName`), in ra thông tin, lỗi thì `throw`. Có sẵn trong `lib.ps1`: `Install-PosPrinterDriver`, `Set-PosPrinter`, `Invoke-Installer`.
2. Thêm dòng vào `devices.json` (`group`: `printer` = chọn 1, `device` = chọn nhiều).

File nhị phân (driver, bộ cài) không đưa vào git.
