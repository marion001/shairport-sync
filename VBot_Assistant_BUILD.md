# VBot Assistant – Build Shairport Sync v5.2.2

Tài liệu này hướng dẫn build và cài đặt Shairport Sync v5.2.2 có phần mở rộng VBot Assistant trên Raspberry Pi OS/Debian. Bản sửa bổ sung năm phương thức D-Bus để tắt tiếng, điều chỉnh âm lượng phần mềm và đóng/mở thiết bị ALSA.

## 1. Các file đã tùy biến

- `org.gnome.ShairportSync.xml`: khai báo năm phương thức D-Bus.
- `dbus-service.c`: nhận lệnh D-Bus và điều khiển phần ALSA.
- `audio_alsa.c`: xử lý mute, volume phần mềm và quyền mở ALSA.

Không chỉnh sửa trực tiếp `dbus-interface.c` hoặc `dbus-interface.h`. Hai file này được `gdbus-codegen` tự động tạo từ XML trong lúc build.

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

Nếu không cần MQTT, có thể bỏ `--with-mqtt-client` khi configure và không cần cài thư viện MQTT tương ứng. Nếu configure báo thiếu thư viện, đọc dòng `configure: error` cuối cùng và cài gói `-dev` được yêu cầu.

## 3. Chuẩn bị source

```bash
cd /duong-dan/toi/shairport-sync-master
chmod +x verify-gitversion
dos2unix verify-gitversion
```

Source tải dưới dạng ZIP không có thư mục `.git`, vì vậy `shairport-sync -V` có thể hiển thị phần git revision là `NA`. Phiên bản chính thức vẫn được khai báo là `5.2.2` trong `configure.ac`.

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

`--with-alsa` và `--with-dbus-interface` là hai tùy chọn bắt buộc đối với các lệnh VBot trong tài liệu này.

## 5. Khởi động dịch vụ

```bash
sudo systemctl daemon-reload
sudo systemctl enable --now shairport-sync
sudo systemctl status shairport-sync --no-pager
```

Theo dõi log trực tiếp:

```bash
sudo journalctl -u shairport-sync -f
```

Kiểm tra phiên bản:

```bash
shairport-sync -V
```

## 6. Kiểm tra D-Bus

Xác nhận dịch vụ đã đăng ký trên system bus:

```bash
gdbus introspect --system \
  --dest org.gnome.ShairportSync \
  --object-path /org/gnome/ShairportSync
```

Trong interface `org.gnome.ShairportSync.RemoteControl` phải xuất hiện:

- `Mute()`
- `Unmute()`
- `ChangeVolume(double volume_value)`
- `EnableOpenALSA()`
- `DisableOpenALSA()`

## 7. Các lệnh dành cho VBot Assistant

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

### Đặt âm lượng phần mềm

```bash
dbus-send --system --print-reply \
  --dest=org.gnome.ShairportSync \
  /org/gnome/ShairportSync \
  org.gnome.ShairportSync.RemoteControl.ChangeVolume double:10
```

Giá trị đầu vào dùng thang `0..100`:

- `0`: im lặng do hệ số âm lượng bằng 0.
- `10`: 10% biên độ mẫu PCM.
- `100`: giữ nguyên biên độ.
- Giá trị nhỏ hơn 0 được giới hạn thành 0; lớn hơn 100 được giới hạn thành 100.

Đây là phép nhân biên độ PCM, không phải thang dB và không cập nhật thanh âm lượng trên thiết bị phát AirPlay.

### Cho phép và mở ALSA ngay

```bash
dbus-send --system --print-reply \
  --dest=org.gnome.ShairportSync \
  /org/gnome/ShairportSync \
  org.gnome.ShairportSync.RemoteControl.EnableOpenALSA
```

### Đóng ALSA ngay và ngăn mở lại

```bash
dbus-send --system --print-reply \
  --dest=org.gnome.ShairportSync \
  /org/gnome/ShairportSync \
  org.gnome.ShairportSync.RemoteControl.DisableOpenALSA
```

`DisableOpenALSA` không chuyển ALSA sang chế độ shared/non-blocking. Nó đóng handle hiện tại và chặn các lần mở ALSA tiếp theo cho đến khi nhận `EnableOpenALSA` hoặc tiến trình được khởi động lại.

## 8. Kiểm tra nhanh sau khi cài

```bash
# Theo dõi log ở terminal thứ nhất
sudo journalctl -u shairport-sync -f

# Chạy lần lượt ở terminal thứ hai
dbus-send --system --print-reply --dest=org.gnome.ShairportSync /org/gnome/ShairportSync org.gnome.ShairportSync.RemoteControl.Mute
dbus-send --system --print-reply --dest=org.gnome.ShairportSync /org/gnome/ShairportSync org.gnome.ShairportSync.RemoteControl.Unmute
dbus-send --system --print-reply --dest=org.gnome.ShairportSync /org/gnome/ShairportSync org.gnome.ShairportSync.RemoteControl.ChangeVolume double:50
dbus-send --system --print-reply --dest=org.gnome.ShairportSync /org/gnome/ShairportSync org.gnome.ShairportSync.RemoteControl.DisableOpenALSA
sudo lsof /dev/snd/*
dbus-send --system --print-reply --dest=org.gnome.ShairportSync /org/gnome/ShairportSync org.gnome.ShairportSync.RemoteControl.EnableOpenALSA
```

Mỗi lệnh thành công phải trả về một `method return`. Log phải có dòng bắt đầu bằng `VBot:` tương ứng.

## 9. Xử lý lỗi thường gặp

### `ServiceUnknown` hoặc không tìm thấy `org.gnome.ShairportSync`

```bash
sudo systemctl status shairport-sync --no-pager
sudo journalctl -u shairport-sync -n 100 --no-pager
```

Kiểm tra bản build có dùng `--with-dbus-interface` và tiến trình đang kết nối system bus.

### `UnknownMethod`

Bản binary đang chạy chưa chứa phần mở rộng VBot hoặc chưa được cài lại. Chạy `gdbus introspect`, sau đó kiểm tra đường dẫn binary:

```bash
command -v shairport-sync
shairport-sync -V
```

### ALSA không mở lại

```bash
sudo lsof /dev/snd/*
sudo journalctl -u shairport-sync -n 100 --no-pager
```

Kiểm tra thiết bị có bị tiến trình khác chiếm giữ, tên thiết bị trong `/etc/shairport-sync.conf`, và các lỗi `EBUSY`, `ENOENT` hoặc `ENODEV`.

### Khôi phục trạng thái mặc định

Khởi động lại dịch vụ sẽ đặt lại:

- mute VBot: tắt;
- hệ số âm lượng VBot: `1.0`;
- quyền mở ALSA: bật.

```bash
sudo systemctl restart shairport-sync
```
