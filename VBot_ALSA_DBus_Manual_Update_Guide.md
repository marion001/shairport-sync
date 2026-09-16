# Hướng dẫn port VBot ALSA/D-Bus cho Shairport Sync 5.5

Tài liệu này mô tả phần mở rộng VBot đang dùng trong source Shairport Sync 5.5 ở thư mục hiện tại. Bản port chỉ sửa ba file mã nguồn:

- `org.gnome.ShairportSync.xml`
- `dbus-service.c`
- `audio_alsa.c`

Không cần tạo header hoặc source riêng cho VBot. Không sửa trực tiếp `dbus-interface.c` và `dbus-interface.h`; hai file đó được sinh lại từ XML bằng `gdbus-codegen` trong lúc build.

## 1. Hành vi D-Bus

| Phương thức | Hành vi |
|---|---|
| `Mute()` | Ghi PCM im lặng nhưng vẫn giữ phiên phát và kết nối ALSA. |
| `Unmute()` | Bỏ mute; hệ số đã đặt bằng `ChangeVolume` vẫn được giữ. |
| `ChangeVolume(double)` | Giới hạn đầu vào về `0..100`, đổi thành gain tuyến tính `0.0..1.0` và nhân vào PCM. |
| `DisableOpenALSA()` | Tắt quyền mở, đóng handle hiện tại và chặn mọi đường mở ALSA tiếp theo. |
| `EnableOpenALSA()` | Bật quyền mở, chọn cấu hình mặc định nếu cần và thử mở ALSA ngay. |

Đây là volume phần mềm tuyến tính, không phải dB. Nó không gửi DACP và không cập nhật thanh âm lượng trên thiết bị phát AirPlay. Mute và volume tác động từ lần ghi PCM tiếp theo; dữ liệu đã nằm trong bộ đệm phần cứng có thể còn phát trong một khoảng ngắn.

Trạng thái chỉ nằm trong bộ nhớ tiến trình. Khi khởi động lại Shairport Sync:

- mute tắt;
- gain trở về `1.0`;
- quyền mở ALSA được bật.

## 2. Khai báo XML D-Bus

Trong interface `org.gnome.ShairportSync.RemoteControl` của `org.gnome.ShairportSync.xml`, thêm:

```xml
<method name="Mute"/>
<method name="Unmute"/>
<method name="ChangeVolume">
  <arg name="volume_value" type="d" direction="in"/>
</method>
<method name="EnableOpenALSA"/>
<method name="DisableOpenALSA"/>
```

Chữ ký `d` là D-Bus `double`. Tên phương thức có phân biệt chữ hoa và chữ thường.

Rule hiện có trong `Makefile.am` tự sinh giao diện:

```bash
gdbus-codegen \
  --interface-prefix org.gnome \
  --generate-c-code dbus-interface \
  org.gnome.ShairportSync.xml
```

## 3. Kết nối `dbus-service.c` với ALSA

Các API được định nghĩa trong `audio_alsa.c` và khai báo dưới `CONFIG_ALSA` trong `dbus-service.c`:

```c
#ifdef CONFIG_ALSA
#include "audio.h"
extern void vbot_alsa_set_mute(int muted);
extern void vbot_alsa_set_volume(double percent);
extern int vbot_alsa_set_enabled(int enabled);
#endif
```

Năm handler phải:

1. Kiểm tra binary có ALSA và backend đang chọn có tên `alsa`.
2. Trả `G_DBUS_ERROR_NOT_SUPPORTED` nếu lệnh được gọi với backend khác.
3. Gọi API tương ứng của `audio_alsa.c`.
4. Với Enable/Disable, trả `G_DBUS_ERROR_FAILED` nếu thao tác ALSA thất bại.
5. Khi thành công, gọi đúng hàm `shairport_sync_remote_control_complete_*()` rồi trả `TRUE`.

Đăng ký đủ năm signal trên `shairportSyncRemoteControlSkeleton`:

```c
g_signal_connect(shairportSyncRemoteControlSkeleton, "handle-mute",
                 G_CALLBACK(on_handle_mute), NULL);
g_signal_connect(shairportSyncRemoteControlSkeleton, "handle-unmute",
                 G_CALLBACK(on_handle_unmute), NULL);
g_signal_connect(shairportSyncRemoteControlSkeleton, "handle-change-volume",
                 G_CALLBACK(on_handle_change_volume), NULL);
g_signal_connect(shairportSyncRemoteControlSkeleton, "handle-enable-open-alsa",
                 G_CALLBACK(on_handle_enable_open_alsa), NULL);
g_signal_connect(shairportSyncRemoteControlSkeleton, "handle-disable-open-alsa",
                 G_CALLBACK(on_handle_disable_open_alsa), NULL);
```

## 4. Trạng thái và đồng bộ trong `audio_alsa.c`

Trạng thái mặc định:

```c
static int vbot_open_alsa = 1;
static int vbot_silent = 0;
static double vbot_gain = 1.0;
```

Mọi lần đọc hoặc ghi ba biến này diễn ra khi giữ `alsa_mutex`. Không dùng `volatile` để đồng bộ giữa luồng D-Bus, luồng phát và luồng giữ DAC hoạt động.

API công khai trong file:

```c
void vbot_alsa_set_mute(int muted);
void vbot_alsa_set_volume(double percent);
int vbot_alsa_set_enabled(int enabled);
```

`vbot_alsa_set_volume()` giới hạn đầu vào như sau:

- NaN và giá trị nhỏ hơn hoặc bằng 0 thành gain 0;
- từ 100 trở lên thành gain 1;
- giá trị còn lại được chia cho 100.

## 5. Chặn và mở ALSA

Kiểm tra `vbot_open_alsa` phải nằm ở tất cả các đường có thể mở thiết bị:

- `do_open_device()` dùng cho phiên phát và Enable;
- handle tạm trong `get_permissible_configuration_settings()`;
- handle tạm trong `get_configuration()`;
- luồng `alsa_buffer_monitor_thread_code()` khi `keep_dac_busy` được bật.

`DisableOpenALSA` đổi cờ về 0 và gọi `do_close()` trong cùng vùng bảo vệ của `alsa_mutex`. Nhờ vậy luồng phát không thể chen vào và mở lại thiết bị giữa hai thao tác.

`EnableOpenALSA` bật cờ trước, dò cấu hình nếu chưa thực hiện, rồi mở thiết bị. Nếu chưa có phiên AirPlay và `current_encoded_output_format` chưa được chọn, nó tìm cấu hình bằng các giá trị:

- `alsa.disable_standby_mode_default_channels`;
- `alsa.disable_standby_mode_default_rate`;
- `alsa.disable_standby_mode_default_format`.

Nếu thiết bị đang mở, gọi Enable lặp lại không đóng/mở handle. Nếu lần mở thất bại, D-Bus trả lỗi nhưng quyền mở vẫn được bật để phiên phát hoặc lần Enable sau có thể thử lại.

Không thêm `SND_PCM_NONBLOCK`, không chuyển sang dmix/shared và không gọi trực tiếp `snd_pcm_close()` từ `dbus-service.c`.

## 6. Xử lý PCM

Ngay trước `alsa_pcm_write()` trong `do_play()`:

1. Nếu không mute và gain bằng 1, dùng buffer gốc, không cấp phát thêm.
2. Nếu mute hoặc gain khác 1, cấp buffer theo `samples × channels × physical sample bytes`.
3. Xử lý theo `snd_pcm_format_physical_width()`, `snd_pcm_format_width()`, signed/unsigned và LE/BE.
4. Hỗ trợ S8, U8, S16, S24 đóng gói 3 byte, S24 trong container 4 byte và S32.
5. Với PCM unsigned, mẫu im lặng nằm ở midpoint; ví dụ U8 là 128, không phải byte 0.
6. Nếu không xác định được định dạng hoặc cấp phát thất bại, trả lỗi và không phát buffer gốc ở âm lượng ngoài ý muốn.
7. Giải phóng buffer sau `alsa_pcm_write()`.

## 7. Checklist port và kiểm thử

- [ ] XML có đủ năm method và `ChangeVolume` nhận `double`.
- [ ] Không sửa tay file generated.
- [ ] Extern, năm handler và năm `g_signal_connect` khớp tên generated.
- [ ] Trạng thái VBot được bảo vệ bằng `alsa_mutex`.
- [ ] Tất cả đường mở ALSA đều kiểm tra quyền mở.
- [ ] Disable đổi cờ trước khi đóng handle.
- [ ] Enable mở ngay và trả lỗi D-Bus nếu mở thất bại.
- [ ] PCM hoạt động với 8/16/24/32-bit, signed/unsigned và LE/BE.
- [ ] Build với `--with-alsa --with-dbus-interface`.
- [ ] Nếu cần duy trì cấu hình khác, build thêm D-Bus không ALSA để kiểm tra `#ifdef`.
- [ ] Thử năm lệnh khi idle, đang phát và khi `keep_dac_busy` bật.
- [ ] Dùng `lsof /dev/snd/*` xác nhận Disable đã nhả handle.
- [ ] Thử Enable khi thiết bị rảnh và khi đang bị tiến trình khác chiếm.
- [ ] Theo dõi log để phát hiện deadlock, `EBUSY`, `ENOENT`, `ENODEV` hoặc crash.

Các lệnh build và kiểm tra runtime nằm trong `VBot_Assistant_BUILD.md`.
