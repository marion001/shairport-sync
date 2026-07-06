# Hướng dẫn sửa thủ công cho VBot ALSA / D-Bus

Mục đích: cập nhật 3 file cần thiết để thêm hỗ trợ các lệnh D-Bus `Mute`, `Unmute`, `ChangeVolume(double)`, `EnableOpenALSA`, `DisableOpenALSA` và đồng bộ với `audio_alsa.c`.

## 1. `org.gnome.ShairportSync.xml`

### Nội dung cần thêm
Tìm phần `<interface name="org.gnome.ShairportSync.RemoteControl">` và thêm các method mới:

```xml
    <!-- VBot extensions -->
    <method name='Mute'/>
    <method name='Unmute'/>
    <method name='ChangeVolume'>
      <arg name="volume_value" type="d" direction="in" />
    </method>
    <method name='EnableOpenALSA'/>
    <method name='DisableOpenALSA'/>
```

### Giải thích
- `Mute`/`Unmute`: chỉ can thiệp cờ toàn cục, không xử lý mixer.
- `ChangeVolume(double)`: nhận volume kiểu double, tỷ lệ 0..100.
- `EnableOpenALSA` / `DisableOpenALSA`: chuyển chế độ mở ALSA giữa exclusive/shared.

---

## 2. `dbus-service.c`

### Thêm extern và biến global
Ở đầu file, sau include `dbus-service.h`, thêm:

```c
// VBot: ALSA control externs (implemented in audio_alsa.c)
extern volatile int vbot_shairport_silent_mode;
extern volatile int vbot_open_alsa;
extern float vbot_volume_factor;
extern int vbot_alsa_open(int do_auto_setup);
extern int vbot_alsa_close(void);
```

### Cập nhật handler D-Bus
Tìm và thêm hoặc thay thế các handler sau:

```c
static gboolean on_handle_mute(ShairportSyncRemoteControl *skeleton,
                               GDBusMethodInvocation *invocation,
                               __attribute__((unused)) gpointer user_data) {
  vbot_shairport_silent_mode = 1;
  debug(1, "VBot: Mute command received - silent mode enabled");
  shairport_sync_remote_control_complete_mute(skeleton, invocation);
  return TRUE;
}

static gboolean on_handle_unmute(ShairportSyncRemoteControl *skeleton,
                                 GDBusMethodInvocation *invocation,
                                 __attribute__((unused)) gpointer user_data) {
  vbot_shairport_silent_mode = 0;
  debug(1, "VBot: Unmute command received - silent mode disabled");
  shairport_sync_remote_control_complete_unmute(skeleton, invocation);
  return TRUE;
}

static gboolean on_handle_change_volume(ShairportSyncRemoteControl *skeleton,
                                        GDBusMethodInvocation *invocation,
                                        const gdouble volume_value,
                                        __attribute__((unused)) gpointer user_data) {
  vbot_volume_factor = (float)(volume_value / 100.0);
  if (vbot_volume_factor < 0.0f) vbot_volume_factor = 0.0f;
  if (vbot_volume_factor > 1.0f) vbot_volume_factor = 1.0f;
#ifdef CONFIG_DACP_CLIENT
  dacp_set_volume((int)volume_value);
#endif
  debug(1, "VBot: ChangeVolume command received - volume set to %.0f, factor: %.3f",
        volume_value, vbot_volume_factor);
  shairport_sync_remote_control_complete_change_volume(skeleton, invocation);
  return TRUE;
}

static gboolean on_handle_enable_open_alsa(ShairportSyncRemoteControl *skeleton,
                                           GDBusMethodInvocation *invocation,
                                           __attribute__((unused)) gpointer user_data) {
  debug(1, "VBot: EnableOpenALSA command received - setting exclusive mode");
  if (vbot_open_alsa == 1) {
    debug(1, "VBot: Exclusive mode already enabled");
    shairport_sync_remote_control_complete_enable_open_alsa(skeleton, invocation);
    return TRUE;
  }
  vbot_open_alsa = 1;
  debug(1, "VBot: Exclusive mode enabled - vbot_open_alsa = 1");

  debug(1, "VBot: Closing device to apply exclusive mode...");
  vbot_alsa_close();
  debug(1, "VBot: Reopening device in exclusive mode...");
  vbot_alsa_open(0);

  shairport_sync_remote_control_complete_enable_open_alsa(skeleton, invocation);
  return TRUE;
}

static gboolean on_handle_disable_open_alsa(ShairportSyncRemoteControl *skeleton,
                                            GDBusMethodInvocation *invocation,
                                            __attribute__((unused)) gpointer user_data) {
  debug(1, "VBot: DisableOpenALSA command received - setting shared mode");
  if (vbot_open_alsa == 0) {
    debug(1, "VBot: Shared mode already enabled");
    shairport_sync_remote_control_complete_disable_open_alsa(skeleton, invocation);
    return TRUE;
  }
  vbot_open_alsa = 0;
  debug(1, "VBot: Shared mode enabled - vbot_open_alsa = 0");

  debug(1, "VBot: Closing device to apply shared mode...");
  vbot_alsa_close();
  debug(1, "VBot: Reopening device in shared mode...");
  vbot_alsa_open(0);

  shairport_sync_remote_control_complete_disable_open_alsa(skeleton, invocation);
  return TRUE;
}
```

### Đăng ký handler
Xác nhận trong phần khởi tạo D-Bus đã có:

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

---

## 3. `audio_alsa.c`

### Thêm biến và wrapper
Ở đầu file, thêm:

```c
volatile int vbot_shairport_silent_mode = 0;
volatile int vbot_open_alsa = 1;  // default: exclusive allowed
float vbot_volume_factor = 1.0f;
```

và ở gần cuối file:

```c
/* VBot helper wrappers to allow external control (called from D-Bus handlers) */
int vbot_alsa_open(int do_auto_setup) { (void)do_auto_setup; return do_open(); }
int vbot_alsa_close(void) { return do_close(); }
```

### Áp dụng `vbot_open_alsa` khi mở ALSA
Trong `get_permissible_configuration_settings()` và `actual_open_alsa_device()`, thay giá trị `mode` bằng:

```c
int mode = vbot_open_alsa ? 0 : SND_PCM_NONBLOCK;
```

và dùng `mode` khi gọi `snd_pcm_open()` thay vì cố định `0`.

### Chặn mở ALSA khi `vbot_open_alsa == 0`
Trong `do_open()`, thêm kiểm tra đầu hàm:

```c
static int do_open() {
  extern volatile int vbot_open_alsa;
  if (!vbot_open_alsa) {
    debug(1, "do_open() BI CHAN vi vbot_open_alsa = 0 -> KHONG mo ALSA");
    return -EACCES;
  }
```

### Xử lý mute / volume phần mềm
Trong `do_play()` trước khi gọi `alsa_pcm_write()`:

```c
      void *write_buf = buf;
      void *procbuf = NULL;
      if ((vbot_shairport_silent_mode != 0) || (vbot_volume_factor != 1.0f)) {
        int channels = CHANNELS_FROM_ENCODED_FORMAT(current_encoded_output_format);
        sps_format_t fmt = (sps_format_t)FORMAT_FROM_ENCODED_FORMAT(current_encoded_output_format);
        int sample_bytes = 1;
        if ((fmt >= 0) && (fmt <= SPS_FORMAT_HIGHEST_NATIVE))
          sample_bytes = fr[fmt].sample_size;
        size_t bytes = (size_t)samples * (size_t)channels * (size_t)sample_bytes;
        procbuf = malloc(bytes);
        if (procbuf != NULL) {
          if (vbot_shairport_silent_mode != 0) {
            memset(procbuf, 0, bytes);
          } else {
            /* scale sample data by vbot_volume_factor */
            ...
          }
          write_buf = procbuf;
        }
      }

      ret = alsa_pcm_write(alsa_handle, write_buf, samples);

      if (procbuf)
        free(procbuf);
```

> Ghi chú: nếu dùng volume phần mềm thì nên giữ `sample_bytes` chính xác với định dạng `current_encoded_output_format`.

---

## 4. Quy trình sửa thủ công cho phiên bản tiếp theo

1. Mở `org.gnome.ShairportSync.xml`, thêm các method dưới cùng của interface `org.gnome.ShairportSync.RemoteControl`.
2. Chạy `gdbus-codegen` để tạo lại `dbus-interface.c`:

```bash
gdbus-codegen --interface-prefix org.gnome --generate-c-code dbus-interface org.gnome.ShairportSync.xml
```

3. Kiểm tra `dbus-service.c`:
   - thêm `extern` và handler mới
   - thêm `g_signal_connect(...)` với các handler tương ứng
4. Kiểm tra `audio_alsa.c`:
   - thêm biến `vbot_shairport_silent_mode`, `vbot_open_alsa`, `vbot_volume_factor`
   - thêm wrapper `vbot_alsa_open()` / `vbot_alsa_close()`
   - bật `vbot_open_alsa` trong mọi lần `snd_pcm_open()`
   - chặn `do_open()` khi `vbot_open_alsa == 0`
   - thêm xử lý mute/volume phần mềm trong `do_play()`
5. Build lại bằng `make` và kiểm tra không có lỗi compile/link.
6. Khởi động lại service và thử các lệnh D-Bus:
   - `Mute`, `Unmute`
   - `ChangeVolume 50`
   - `DisableOpenALSA`
   - `EnableOpenALSA`

---

## 5. Lưu ý quan trọng

- `Mute` / `Unmute` chỉ thay đổi cờ toàn cục `vbot_shairport_silent_mode`.
- `DisableOpenALSA` không nên mở lại ALSA nếu đang ở chế độ `vbot_open_alsa == 0`.
- `EnableOpenALSA` phải đóng và mở lại thiết bị sau khi đổi chế độ.
- Nếu service bị disconnect khi gọi lại `EnableOpenALSA`, cần kiểm tra log `journalctl -u shairport-sync` và trạng thái `alsa_handle`.

---

## 6. Nếu muốn nhanh hơn

Sao chép file `VBot_ALSA_DBus_Manual_Update_Guide.md` vào dự án và dùng nó làm checklist cho các phiên bản sau.


## 7 Thay đổi phiên bản build

Chỉnh sửa file: verify-gitversion