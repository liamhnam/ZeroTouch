# ZeroTouch

Cắm **1 USB** vào máy (ổ cứng trống, boot UEFI) → Windows tự cài từ đầu đến cuối, không cần chạm vào máy.

Dành cho máy kiosk/POS cài hàng loạt: Intel đời 9–14, không card đồ họa rời, USB Wi-Fi.

## Máy sau khi cài

| Hạng mục | Kết quả |
|---|---|
| Ổ cứng | Ổ SATA/NVMe **duy nhất** bị xóa, toàn bộ dung lượng thành `C:` (GPT, không có phân vùng Recovery) |
| Tên máy | `GOODM-` + 9 ký tự cuối số serial BIOS (serial rác → 6 ký tự cuối MAC) |
| Tài khoản | `GOODM`, không mật khẩu, tự đăng nhập vĩnh viễn |
| Bảo mật | Defender tắt (ngay trong WinPE), tường lửa tắt, SmartScreen tắt |
| Windows Update | Tắt (policy + dịch vụ + task tạm dừng), không tải driver qua Windows Update |
| Nguồn | Ultimate Performance, không sleep, không tắt màn hình, không hibernate, không ngắt USB |
| Vùng miền | Giao diện en-US, định dạng en-US, khu vực Việt Nam, UTC+7 |
| Driver | SDIO chạy offline 2 lượt |
| Wi-Fi | Kết nối mạng trong `secrets.env` sau khi có driver |
| Phần mềm | UltraViewer (cài im lặng) |
| Kết thúc | 1 dòng trong `inventory.csv` trên USB, log, file `HOAN-TAT.txt` hoặc `LOI.txt` trên Desktop, khởi động lại 1 lần |

Bản quyền Windows: cài bằng key Pro chung (chưa kích hoạt), nhập key thật sau.

## Quy trình

```
WinPE       pe.cmd: chọn ổ SATA/NVMe duy nhất (bỏ qua USB; ≥2 ổ hoặc 0 ổ → DỪNG, không xóa)
            → xóa + chia ổ → bung install.wim/.swm → tắt Defender offline → khởi động lại
            (chặn cài lặp: nếu ổ đang cài dở mà máy lại boot vào USB → trả về ổ cứng)
Specialize  computername.ps1 + specialize.ps1: tên máy, tường lửa, Update, nguồn
OOBE        bỏ qua toàn bộ → tài khoản GOODM
First logon firstlogon.ps1: tự đăng nhập vĩnh viễn, ổ cứng lên đầu thứ tự boot
            → USB \AutoInstaller\postinstall.ps1 chạy steps\*.ps1 theo thứ tự:
              10-drivers (SDIO) → 15-peripherals → 20-wifi → 30-apps
            → inventory.csv + log lên USB → khởi động lại → Desktop
```

Bước nào lỗi thì ghi `FAIL` và làm tiếp; lọc `inventory.csv` theo cột `Result` để tìm máy lỗi.

## Tạo USB (trên Windows, PowerShell quyền Administrator)

1. Chuẩn bị (một lần):
   - `secrets.env`: chép từ `secrets.env.example`, điền Wi-Fi.
   - `drivers\sdio\`: SDIO + gói driver + indexes (xem [drivers/sdio/README.md](drivers/sdio/README.md)).
   - `apps\UltraViewer\UltraViewer_setup_*.exe`.
2. Tìm số ổ USB: `Get-Disk`
3. Tạo USB (**xóa sạch USB**):
   ```powershell
   Set-ExecutionPolicy -Scope Process Bypass
   .\tools\make-usb.ps1 -Iso 'D:\tiny11 23H2 x64.iso' -DiskNumber 2
   ```
   Lần đầu sẽ chuyển `install.esd` → `install.wim` (bung nhanh hơn khi cài) và chia `.swm` cho FAT32; kết quả được lưu cache ở `%LOCALAPPDATA%\ZeroTouch`.

Script từ chối mọi ổ không phải USB, ổ hệ thống, ổ lớn hơn 256 GB, và bắt gõ lại số ổ trước khi xóa.

## Tạo USB (trên macOS)

Chuẩn bị giống bước 1 ở trên, cài thêm `wimlib` một lần: `brew install wimlib`.

```bash
diskutil list external physical                              # tìm USB, ví dụ disk2
tools/make-usb.sh ~/Downloads/"tiny11 23H2 x64.iso" disk2    # XÓA SẠCH USB
tools/make-usb.sh ~/Downloads/"tiny11 23H2 x64.iso" --stage ./out   # chỉ dựng nội dung USB vào thư mục, không đụng ổ nào
```

Cache image ở `~/Library/Caches/ZeroTouch`. Script từ chối ổ không phải USB gắn ngoài, ổ lớn hơn 256 GB, và bắt gõ lại mã ổ trước khi xóa.

## Cài máy

Cắm USB → bật máy → (ổ trống nên tự boot USB; nếu không, chọn USB trong menu boot) → chờ đến khi Desktop có `HOAN-TAT.txt` hoặc `LOI.txt` → rút USB.

## Gộp inventory từ nhiều USB

```powershell
.\tools\merge-inventory.ps1 -Path E:\, F:\ -Output .\inventory-all.csv
```

Cột: `FinishedAt, InstalledAt, Result, FailedSteps, ComputerName, Serial, Manufacturer, Model, CPU, RAM_GB, Disk_GB, MAC, MissingDrivers, MissingList, WifiAdapter, Wifi5GHz, WifiStatus, UltraViewerID`.

## Mở rộng

- **Thêm phần mềm:** tạo `apps\<Tên>\` gồm bộ cài + `install.ps1` (`param([string] $AppDir, $Context)`, lỗi thì `throw`). Không cần build lại XML.
- **Thêm bước:** thêm `payload\AutoInstaller\steps\NN-ten.ps1` trả về `@{ Status = 'OK'|'SKIP'|'FAIL'; Detail = '...' }`.
- **Driver ngoại vi (giai đoạn 2):** `\AutoInstaller\peripherals\install.ps1` được bước `15-peripherals` gọi nếu tồn tại.
- **Máy có Intel VMD/RST** (dừng với "No disk satisfied the given criteria"): tắt VMD trong BIOS hoặc đặt driver F6 vào `drivers\winpe\`.

## Sửa file cài đặt (autounattend.xml)

Chỉ sửa trong `src\`, rồi build lại (cần Python 3 và Internet – dùng [schneegans.de unattend generator](https://schneegans.de/windows/unattend-generator/); tên tài khoản được thay tại máy, không gửi đi):

```
python build.py        →  dist\autounattend.xml
```

| File | Chạy lúc | Vai trò |
|---|---|---|
| `src/pe.cmd` | WinPE | chọn ổ, chia ổ, bung image, tắt Defender, chặn cài lặp |
| `src/computername.ps1` | Specialize | tên máy |
| `src/specialize.ps1` | Specialize (SYSTEM) | tường lửa, Update, Defender policy, nguồn |
| `src/firstlogon.ps1` | Đăng nhập đầu | tự đăng nhập, thứ tự boot, gọi payload trên USB |

## Xử lý sự cố

| Hiện tượng | Nguyên nhân / cách xử lý |
|---|---|
| WinPE dừng: *No disk satisfied the given criteria* | Không thấy ổ SATA/NVMe: bật AHCI, tắt Intel VMD/RST, hoặc thêm driver vào `drivers\winpe\` |
| WinPE dừng: *Several disks (...) satisfied* | Máy có ≥2 ổ — rút bớt ổ hoặc cài tay |
| WinPE dừng: *Cannot put Windows Boot Manager first* | Firmware ép boot USB trước — rút USB, bật lại máy |
| `LOI.txt` trên Desktop | Xem bước `FAIL` trong file, log ở `C:\AutoInstaller\logs` và USB `\AutoInstaller\logs\<máy>-<giờ>` |
| `WifiStatus = NO_ADAPTER` | SDIO không có driver cho USB Wi-Fi đó |
| `WifiStatus = NOT_CONNECTED`, `Wifi5GHz = NO` | USB Wi-Fi không hỗ trợ 5 GHz |
