# Hướng dẫn port VBot ALSA/D-Bus sang phiên bản Shairport Sync mới

Tài liệu này mô tả chính xác các thay đổi đang dùng trên Shairport Sync v5.2.2. Mục đích là hỗ trợ việc đối chiếu và port lại ở các phiên bản sau, không phải thay thế việc review thay đổi upstream.

## 1. Hành vi cần giữ nguyên

| Phương thức | Hành vi |
|---|---|
| `Mute()` | Ghi mẫu PCM bằng 0 nhưng vẫn giữ phiên phát và kết nối ALSA. |
| `Unmute()` | Bỏ cờ mute VBot. Âm lượng vẫn chịu ảnh hưởng của `ChangeVolume`. |
| `ChangeVolume(double)` | Chuyển giá trị `0..100` thành hệ số tuyến tính `0.0..1.0` và nhân vào mẫu PCM. |
| `DisableOpenALSA()` | Đóng ALSA hiện tại và chặn mọi lần mở tiếp theo. |
| `EnableOpenALSA()` | Bỏ chặn và yêu cầu mở ALSA ngay. |

Các trạng thái trên chỉ nằm trong bộ nhớ tiến trình. Restart Shairport Sync sẽ đưa chúng về mặc định.

## 2. Sửa XML D-Bus

Trong interface `org.gnome.ShairportSync.RemoteControl` của `org.gnome.ShairportSync.xml`, thêm:

```xml
<method name='Mute'/>
<method name='Unmute'/>
<method name='ChangeVolume'>
  <arg name='volume_value' type='d' direction='in'/>
</method>
<method name='EnableOpenALSA'/>
<method name='DisableOpenALSA'/>
```

Chữ ký `d` là D-Bus double. Tên phương thức và chữ hoa/chữ thường phải khớp hoàn toàn với câu lệnh gọi.

Không sửa mã generated bằng tay. Rule trong `Makefile.am` sẽ chạy:

```bash
gdbus-codegen \
  --interface-prefix org.gnome \
  --generate-c-code dbus-interface \
  org.gnome.ShairportSync.xml
```

## 3. Khai báo giao tiếp với ALSA backend

Trong `dbus-service.c`, đặt các khai báo sau dưới `#ifdef CONFIG_ALSA`:

```c
extern volatile int vbot_shairport_silent_mode;
extern volatile int vbot_open_alsa;
extern float vbot_volume_factor;
extern int vbot_alsa_open(void);
extern int vbot_alsa_close(void);
```

Điều kiện compile giúp bản build không có ALSA vẫn biên dịch được và vẫn có thể trả lời D-Bus mà không truy cập symbol ALSA.

## 4. Handler D-Bus

Trong `dbus-service.c`, triển khai năm handler theo các nguyên tắc:

- Luôn gọi hàm `shairport_sync_remote_control_complete_*()` trước khi trả về `TRUE`.
- Phần truy cập biến/hàm ALSA phải nằm trong `#ifdef CONFIG_ALSA`.
- `ChangeVolume` chia giá trị nhận được cho `100.0`, sau đó clamp về `0.0f..1.0f`.
- `DisableOpenALSA` đặt cờ về 0 trước khi đóng thiết bị để ngăn luồng phát mở lại.
- `EnableOpenALSA` đặt cờ về 1 trước khi gọi hàm mở.
- Các lệnh lặp lại phải an toàn: disable khi đã disable và enable khi đã enable không làm gì thêm.

Đăng ký đủ signal trên `shairportSyncRemoteControlSkeleton`:

```c
g_signal_connect(skeleton, "handle-mute", G_CALLBACK(on_handle_mute), NULL);
g_signal_connect(skeleton, "handle-unmute", G_CALLBACK(on_handle_unmute), NULL);
g_signal_connect(skeleton, "handle-change-volume", G_CALLBACK(on_handle_change_volume), NULL);
g_signal_connect(skeleton, "handle-enable-open-alsa",
                 G_CALLBACK(on_handle_enable_open_alsa), NULL);
g_signal_connect(skeleton, "handle-disable-open-alsa",
                 G_CALLBACK(on_handle_disable_open_alsa), NULL);
```

Trong source thật, đối số đầu tiên là `shairportSyncRemoteControlSkeleton`; đoạn trên viết ngắn để dễ đọc.

## 5. Trạng thái VBot trong `audio_alsa.c`

Giá trị mặc định:

```c
volatile int vbot_shairport_silent_mode = 0;
volatile int vbot_open_alsa = 1;
float vbot_volume_factor = 1.0f;
```

- `silent_mode = 0`: không mute.
- `open_alsa = 1`: cho phép mở ALSA.
- `volume_factor = 1.0f`: giữ nguyên biên độ PCM.

## 6. Khóa việc mở ALSA

Ở đầu `do_open()`, trước khi thay đổi backend state:

```c
if (vbot_open_alsa == 0) {
  debug(1, "VBot: ALSA open blocked by DisableOpenALSA");
  return -EACCES;
}
```

Không thay các lệnh `snd_pcm_open()` sang `SND_PCM_NONBLOCK`. Mục tiêu của `DisableOpenALSA` là nhường hoàn toàn thiết bị âm thanh cho VBot/ứng dụng khác, không phải mở ALSA theo một mode khác.

## 7. Wrapper đóng/mở an toàn

`do_open()` và `do_close()` là hàm static. Cung cấp wrapper và dùng cùng `alsa_mutex` với backend:

```c
int vbot_alsa_open(void) {
  int result;
  pthread_mutex_lock(&alsa_mutex);
  result = do_open();
  pthread_mutex_unlock(&alsa_mutex);
  return result;
}

int vbot_alsa_close(void) {
  int result;
  pthread_mutex_lock(&alsa_mutex);
  result = do_close();
  pthread_mutex_unlock(&alsa_mutex);
  return result;
}
```

Không gọi trực tiếp `snd_pcm_close()` từ `dbus-service.c`; việc đó bỏ qua quản lý state của ALSA backend.

## 8. Xử lý buffer PCM

Ngay trước `alsa_pcm_write()` trong `do_play()`:

1. Nếu không mute và factor bằng 1, ghi buffer gốc để không phát sinh allocation.
2. Nếu mute hoặc cần đổi volume, cấp một buffer có cùng kích thước.
3. Khi mute, dùng `memset(..., 0, ...)`.
4. Với mẫu 16-bit, nhân từng `int16_t` bằng factor và làm tròn bằng `lrintf`.
5. Với mẫu 32-bit, nhân từng `int32_t` bằng factor và làm tròn bằng `llrint`.
6. Format không hỗ trợ được copy nguyên trạng để tránh diễn giải sai layout.
7. Gọi `free()` sau `alsa_pcm_write()`. `free(NULL)` là hợp lệ.

Số byte phải được tính từ số frame, số channel và kích thước sample của `current_encoded_output_format`:

```c
size_t byte_count =
    (size_t)samples * (size_t)channels * (size_t)sample_bytes;
```

Không giả định cố định stereo hoặc 16-bit.

## 9. Checklist khi nâng phiên bản

- [ ] So sánh `org.gnome.ShairportSync.xml` và thêm đúng năm method.
- [ ] Xác nhận tên type generated vẫn là `ShairportSyncRemoteControl`.
- [ ] Xác nhận chữ ký callback generated của `ChangeVolume` vẫn nhận `gdouble`.
- [ ] Port extern, năm handler và năm `g_signal_connect`.
- [ ] Port ba biến trạng thái sang ALSA backend.
- [ ] Xác định lại vị trí gọi `alsa_pcm_write()`; không dựa vào số dòng cũ.
- [ ] Xác định lại `do_open()`, `do_close()` và mutex bảo vệ ALSA.
- [ ] Build cả với `--with-alsa --with-dbus-interface`.
- [ ] Nếu dự án hỗ trợ, build thêm cấu hình D-Bus không ALSA để kiểm tra `#ifdef`.
- [ ] Dùng `gdbus introspect` kiểm tra chữ ký runtime.
- [ ] Thử cả năm lệnh khi đang phát và khi không có phiên AirPlay.
- [ ] Kiểm tra `lsof /dev/snd/*` sau disable và enable.
- [ ] Theo dõi log để phát hiện deadlock, `EBUSY`, `ENOENT`, `ENODEV` hoặc crash.

## 10. Build kiểm tra

```bash
autoreconf -fi
./configure \
  --sysconfdir=/etc \
  --with-alsa \
  --with-soxr \
  --with-avahi \
  --with-dbus-interface \
  --with-ssl=openssl \
  --with-systemd-startup \
  --with-airplay-2
make -j"$(nproc)"
```

Build thành công mới chỉ xác nhận interface và symbol khớp nhau. Cần thử runtime trên máy Linux có ALSA thật để xác nhận quyền system bus, thiết bị âm thanh và tương tác với VBot.

## 11. Kiểm thử runtime tối thiểu

```bash
gdbus introspect --system --dest org.gnome.ShairportSync \
  --object-path /org/gnome/ShairportSync

dbus-send --system --print-reply --dest=org.gnome.ShairportSync \
  /org/gnome/ShairportSync org.gnome.ShairportSync.RemoteControl.Mute

dbus-send --system --print-reply --dest=org.gnome.ShairportSync \
  /org/gnome/ShairportSync org.gnome.ShairportSync.RemoteControl.Unmute

dbus-send --system --print-reply --dest=org.gnome.ShairportSync \
  /org/gnome/ShairportSync org.gnome.ShairportSync.RemoteControl.ChangeVolume double:50

dbus-send --system --print-reply --dest=org.gnome.ShairportSync \
  /org/gnome/ShairportSync org.gnome.ShairportSync.RemoteControl.DisableOpenALSA

dbus-send --system --print-reply --dest=org.gnome.ShairportSync \
  /org/gnome/ShairportSync org.gnome.ShairportSync.RemoteControl.EnableOpenALSA
```

Kết quả đạt yêu cầu khi tất cả lệnh trả về `method return`, mute/volume nghe đúng, ALSA được giải phóng sau disable và mở lại được sau enable.
