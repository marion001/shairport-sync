# Kết quả kiểm thử trên Pi ngày 15/10/2026

- Máy: Raspberry Pi ARMv7, Linux 6.1.21-v7+.
- Source: `/home/pi/shairport-sync`, commit `7e27a325`, Shairport Sync 5.6.
- Build: ALSA, D-Bus, AirPlay 2, OpenSSL, Avahi, soxr và MQTT.
- NQPTP: nâng từ 1.2.6 / SMI 10 lên 1.2.9 / SMI 11 để tương thích 5.6.
- `autoreconf`, configure và `make -j2`: thành công, không có compiler warning.
- Bộ kiểm thử PCM chạy bằng GCC và UBSan: đạt 560 trường hợp signed/unsigned,
  LE/BE, 8/16/24/32-bit, bao gồm S24 trong container 4 byte; giới hạn volume đạt.
- Introspection: đủ năm method; ChangeVolume nhận D-Bus double.
- Trên cấu hình thật `vbot_aec_media`: Mute, Unmute, các mức volume
  -10/0/10/100/150 đều trả method return; Disable/Enable lặp ba lần đạt.
- Kiểm tra `/proc/<pid>/fd`: Disable không còn PCM handle, Enable có handle ngay.
- Đọc thuộc tính D-Bus AirplayVolume trước/sau ChangeVolume: không thay đổi.
- Với `hw:Loopback,0,0` và `disable_standby_mode = "always"`:
  Disable nhả thiết bị và không bị luồng giữ DAC mở lại; Enable mở ngay;
  gọi Enable lặp đạt.
- Dùng handle ALSA khác chiếm thiết bị: Enable trả
  `org.freedesktop.DBus.Error.Failed: ALSA control failed: Device or resource busy`;
  tiến trình vẫn chạy và luồng giữ DAC mở lại được khi handle chiếm được nhả.

Binary mới được cài ở `/usr/local/bin/shairport-sync` và `/usr/local/bin/nqptp`.
Cấu hình `/etc/shairport-sync.conf` và `/etc/asound.conf` được giữ nguyên.
Source gốc, binary cũ, cấu hình và log build nằm ở
`/home/pi/shairport-sync-vbot-backup`.

Các kết quả trên chưa xác nhận âm thanh nghe được trong một phiên AirPlay thật.

## Điều tra mất tiếng sau kiểm thử

Trong phiên AirPlay thật, Shairport báo Playing nhưng luồng player bị chặn trong
ALSA. `vbot_aec_media` trỏ tới `hw:Loopback,0,1`, còn cầu nối ra loa đang đọc
`plughw:Loopback,1,0`. Hai đầu dùng khác subdevice.
Đã sao lưu cấu hình thành `shairport-sync.conf.before-route-fix` trong thư mục
backup và đổi riêng `alsa.output_device` sang `plughw:Loopback,0,0` để khớp
cầu nối hiện tại. Chưa thay đổi `/etc/asound.conf` hoặc mã nguồn vì bước này.

Sau khi kết nối lại, bộ đếm PCM `appl_ptr` tăng và người dùng xác nhận đã có tiếng.
