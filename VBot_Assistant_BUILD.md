# VBot Assistant – Build Shairport Sync 5.5

Tài liệu này hướng dẫn build, cài đặt và kiểm tra Shairport Sync 5.5 có phần mở rộng VBot ALSA/D-Bus trên Raspberry Pi OS hoặc Debian.

## 1. Các file đã tùy biến

- `org.gnome.ShairportSync.xml`: khai báo năm phương thức D-Bus.
- `dbus-service.c`: nhận lệnh, kiểm tra backend và trả kết quả D-Bus.
- `audio_alsa.c`: mute PCM, volume tuyến tính và đóng/mở ALSA an toàn.

Không cần file source hoặc header VBot riêng. Không sửa trực tiếp `dbus-interface.c` hay `dbus-interface.h`; build sẽ sinh chúng từ XML bằng `gdbus-codegen`.

## 2. Cài thư viện build

```bash
sudo apt update
sudo apt install --no-install-recommends \
  build-essential git autoconf automake libtool pkg-config \
  libpopt-dev libconfig-dev libasound2-dev \
  avahi-daemon libavahi-client-dev \
  libssl-dev libsoxr-dev libglib2.0-dev \
  libmosquitto-dev \
  libplist-dev libplist-utils libsodium-dev uuid-dev libgcrypt-dev xxd \
  libavutil-dev libavcodec-dev libavformat-dev
```

`libasound2-dev` và `libglib2.0-dev` là các gói trực tiếp cần cho phần mở rộng ALSA/D-Bus. Các gói khác phục vụ những tính năng được bật trong lệnh configure bên dưới.

Nếu không cần MQTT, bỏ `--with-mqtt-client` và có thể bỏ `libmosquitto-dev`. Nếu configure báo thiếu thư viện, đọc dòng `configure: error` cuối cùng và cài gói `-dev` tương ứng.

## 3. Chuẩn bị source

```bash
cd /duong-dan/toi/shairport-sync-master_NEW
chmod +x verify-gitversion
sed -i 's/\r$//' verify-gitversion
```

Source tải từ ZIP có thể không chứa `.git`, vì vậy phần git revision trong `shairport-sync -V` có thể là `NA`. Phiên bản source này được khai báo là `5.5` trong `configure.ac`.

## 4. Configure và build

```bash
make clean 2>/dev/null || true
autoreconf -fi

./configure \
  --sysconfdir=/etc \
  --with-alsa \
  --with-soxr \
  --with-avahi \
  --with-dbus-interface \
  --with-ssl=openssl \
  --with-systemd-startup \
  --with-airplay-2 \
  --with-mqtt-client

make -j"$(nproc)"
sudo make install
```

Hai tùy chọn bắt buộc cho năm lệnh VBot là:

```text
--with-alsa
--with-dbus-interface
```

Sau khi build, kiểm tra file generated có chứa các hàm complete mới:

```bash
grep -E 'complete_(mute|unmute|change_volume|enable_open_alsa|disable_open_alsa)' \
  dbus-interface.h
```

## 5. Khởi động dịch vụ

```bash
sudo systemctl daemon-reload
sudo systemctl enable --now shairport-sync
sudo systemctl status shairport-sync --no-pager
```

Theo dõi log:

```bash
sudo journalctl -u shairport-sync -f
```

Kiểm tra phiên bản và tùy chọn build:

```bash
shairport-sync -V
```

## 6. Kiểm tra introspection D-Bus

```bash
gdbus introspect --system \
  --dest org.gnome.ShairportSync \
  --object-path /org/gnome/ShairportSync
```

Trong `org.gnome.ShairportSync.RemoteControl` phải xuất hiện:

- `Mute()`
- `Unmute()`
- `ChangeVolume(double volume_value)`
- `EnableOpenALSA()`
- `DisableOpenALSA()`

## 7. Các lệnh VBot

### Tắt tiếng đầu ra Shairport Sync

```bash
dbus-send --system --print-reply \
  --dest=org.gnome.ShairportSync \
  /org/gnome/ShairportSync \
  org.gnome.ShairportSync.RemoteControl.Mute
```

### Bật lại tiếng

```bash
dbus-send --system --print-reply \
  --dest=org.gnome.ShairportSync \
  /org/gnome/ShairportSync \
  org.gnome.ShairportSync.RemoteControl.Unmute
```

Unmute chỉ bỏ trạng thái mute. Hệ số của lần `ChangeVolume` gần nhất vẫn còn hiệu lực.

### Đặt âm lượng phần mềm

```bash
dbus-send --system --print-reply \
  --dest=org.gnome.ShairportSync \
  /org/gnome/ShairportSync \
  org.gnome.ShairportSync.RemoteControl.ChangeVolume double:10
```

Giá trị đầu vào dùng thang `0..100`:

- `0`: biên độ PCM bằng 0;
- `10`: 10% biên độ PCM;
- `100`: giữ nguyên biên độ;
- nhỏ hơn 0: giới hạn thành 0;
- lớn hơn 100: giới hạn thành 100.

Đây là phép nhân biên độ tuyến tính, không phải thang dB và không cập nhật thanh âm lượng AirPlay.

### Cho phép và mở ALSA ngay

```bash
dbus-send --system --print-reply \
  --dest=org.gnome.ShairportSync \
  /org/gnome/ShairportSync \
  org.gnome.ShairportSync.RemoteControl.EnableOpenALSA
```

Nếu thiết bị không mở được, ví dụ đang bị ứng dụng khác chiếm, lệnh trả D-Bus error thay vì `method return`. Quyền mở vẫn được bật để có thể thử lại sau.

### Đóng ALSA ngay và ngăn mở lại

```bash
dbus-send --system --print-reply \
  --dest=org.gnome.ShairportSync \
  /org/gnome/ShairportSync \
  org.gnome.ShairportSync.RemoteControl.DisableOpenALSA
```

Disable đóng handle hiện tại và chặn cả phiên phát, luồng giữ DAC và các lần dò cấu hình mở ALSA. Nó không đổi ALSA sang chế độ shared hoặc non-blocking. Trạng thái chặn tồn tại đến khi nhận Enable hoặc tiến trình khởi động lại.

## 8. Kiểm tra nhanh sau khi cài

Theo dõi log ở terminal thứ nhất:

```bash
sudo journalctl -u shairport-sync -f
```

Chạy ở terminal thứ hai:

```bash
dbus-send --system --print-reply --dest=org.gnome.ShairportSync /org/gnome/ShairportSync org.gnome.ShairportSync.RemoteControl.Mute
dbus-send --system --print-reply --dest=org.gnome.ShairportSync /org/gnome/ShairportSync org.gnome.ShairportSync.RemoteControl.ChangeVolume double:10
dbus-send --system --print-reply --dest=org.gnome.ShairportSync /org/gnome/ShairportSync org.gnome.ShairportSync.RemoteControl.Unmute
dbus-send --system --print-reply --dest=org.gnome.ShairportSync /org/gnome/ShairportSync org.gnome.ShairportSync.RemoteControl.ChangeVolume double:100
dbus-send --system --print-reply --dest=org.gnome.ShairportSync /org/gnome/ShairportSync org.gnome.ShairportSync.RemoteControl.DisableOpenALSA
sudo lsof /dev/snd/*
dbus-send --system --print-reply --dest=org.gnome.ShairportSync /org/gnome/ShairportSync org.gnome.ShairportSync.RemoteControl.EnableOpenALSA
sudo lsof /dev/snd/*
```

Các lệnh thành công trả `method return`. Sau Disable, tiến trình Shairport Sync không còn giữ PCM handle. Sau Enable, handle phải xuất hiện lại nếu thiết bị rảnh và cấu hình hợp lệ.

Thử thêm các biên volume:

```bash
dbus-send --system --print-reply --dest=org.gnome.ShairportSync /org/gnome/ShairportSync org.gnome.ShairportSync.RemoteControl.ChangeVolume double:-10
dbus-send --system --print-reply --dest=org.gnome.ShairportSync /org/gnome/ShairportSync org.gnome.ShairportSync.RemoteControl.ChangeVolume double:0
dbus-send --system --print-reply --dest=org.gnome.ShairportSync /org/gnome/ShairportSync org.gnome.ShairportSync.RemoteControl.ChangeVolume double:150
```

## 9. Xử lý lỗi

### `ServiceUnknown`

```bash
sudo systemctl status shairport-sync --no-pager
sudo journalctl -u shairport-sync -n 100 --no-pager
```

Xác nhận binary được build với `--with-dbus-interface` và tiến trình kết nối system bus.

### `UnknownMethod`

Binary đang chạy chưa chứa XML mới, mã generated chưa được tạo lại hoặc bản mới chưa được cài:

```bash
command -v shairport-sync
shairport-sync -V
gdbus introspect --system --dest org.gnome.ShairportSync \
  --object-path /org/gnome/ShairportSync
```

Chạy lại `autoreconf -fi`, configure, build và install nếu cần.

### `NotSupported`

Năm lệnh này chỉ hoạt động khi output backend đang chọn là ALSA. Kiểm tra cấu hình output và xác nhận build có `--with-alsa`.

### `ALSA control failed`

```bash
sudo lsof /dev/snd/*
sudo journalctl -u shairport-sync -n 100 --no-pager
```

Kiểm tra thiết bị trong `/etc/shairport-sync.conf`, quyền truy cập `/dev/snd`, tiến trình đang chiếm thiết bị và các lỗi `EBUSY`, `ENOENT` hoặc `ENODEV`.

### Khôi phục trạng thái mặc định

```bash
sudo systemctl restart shairport-sync
```

Sau restart: mute tắt, gain bằng 1 và quyền mở ALSA được bật.

## 10. Kiểm thử bắt buộc trên thiết bị thật

Build thành công chỉ xác nhận XML, callback và symbol khớp nhau. Trên Raspberry Pi hoặc máy Debian có ALSA thật, cần thử:

1. Năm lệnh khi đang phát AirPlay.
2. Năm lệnh khi không có phiên phát.
3. Disable/Enable lặp nhiều lần.
4. Disable/Enable khi cấu hình giữ DAC hoạt động được bật.
5. Enable khi thiết bị bị ứng dụng khác chiếm, sau đó giải phóng thiết bị và thử lại.
6. Theo dõi `lsof` và journal để phát hiện handle chưa đóng, deadlock hoặc crash.

Chi tiết triển khai nằm trong `VBot_ALSA_DBus_Manual_Update_Guide.md`.
