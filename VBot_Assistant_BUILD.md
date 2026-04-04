#Bản Build: 5.0.2
#Ngày Build: 04/04/2026

GitHub: https://github.com/marion001/shairport-sync
GitHub Source Gốc: https://github.com/mikebrady/shairport-sync

Dự án này sử dụng hệ thống hai tập lệnh để cài đặt an toàn và đáng tin cậy:

$:> dos2unix install_airplay_v3.sh
$:> dos2unix pre_check_airplay_on_pi.sh

pre_check_airplay_on_pi.sh: Một tập lệnh không xâm phạm, kiểm tra hệ thống của bạn về các sự cố thường gặp mà không thực hiện bất kỳ thay đổi nào. Nếu tất cả các kiểm tra đều đạt, nó sẽ tự động tải xuống và chạy trình cài đặt chính.

install_airplay_v3.sh: Trình cài đặt chính mạnh mẽ thực hiện tất cả các hành động cần thiết để xây dựng và cấu hình phần mềm AirPlay 2 (Shairport-Sync và nqptp).

#Cài Bổ Sung Thư Viện:
$:> sudo apt install libplist-utils

#Cài Bổ Sung Thư Viện Đầy Đủ:
$:> sudo apt install --no-install-recommends build-essential git autoconf automake libtool \
    libpopt-dev libconfig-dev libasound2-dev avahi-daemon libavahi-client-dev libssl-dev libsoxr-dev \
    libplist-dev libsodium-dev uuid-dev libgcrypt-dev xxd libplist-utils \
    libavutil-dev libavcodec-dev libavformat-dev

#Build lại shairport:
$:> cd shairport-sync
$:> make clean
$:> autoreconf -fi
$:> ./configure --with-mqtt-client --sysconfdir=/etc --with-alsa \
    --with-soxr --with-avahi --with-dbus-interface --with-ssl=openssl --with-systemd-startup --with-airplay-2
$:> make
$:> sudo make install

$:> sudo systemctl daemon-reload
$:> sudo systemctl restart shairport-sync
$:> sudo systemctl status shairport-sync

#Tạm dừng shairport khi đang chạy tự động
$:> sudo systemctl stop shairport-sync

#Kiểm tra cái nào đang chiếm quyền sử dụng alsa
$:> sudo lsof /dev/snd/*

#Chạy shairport thủ công xem logs
$:> shairport-sync -vv

📋 Useful commands:
   View live logs:    sudo journalctl -u shairport-sync -f
   Restart service:   sudo systemctl restart shairport-sync
   Check status:      sudo systemctl status shairport-sync
   Edit config:       sudo nano /etc/shairport-sync.conf
   Installation log:  /tmp/airplay_install_20260118_105020.log

DBUS (Mặc Định Các Lệnh Tương Tác Với VBot Assistant):
    #Tắt tiếng
    $:> dbus-send --system --print-reply --dest=org.gnome.ShairportSync /org/gnome/ShairportSync org.gnome.ShairportSync.RemoteControl.Mute

    #Bật tiếng
    $:> dbus-send --system --print-reply --dest=org.gnome.ShairportSync /org/gnome/ShairportSync org.gnome.ShairportSync.RemoteControl.Unmute

    #Thay đổi âm lượng
    $:> dbus-send --system --print-reply --dest=org.gnome.ShairportSync /org/gnome/ShairportSync org.gnome.ShairportSync.RemoteControl.ChangeVolume double:10

    #Bật quyền mở ALSA (mở ngay)
    $:> dbus-send --system --print-reply --dest=org.gnome.ShairportSync /org/gnome/ShairportSync org.gnome.ShairportSync.RemoteControl.EnableOpenALSA

    #Tắt quyền mở ALSA (đóng ngay)
    $:> dbus-send --system --print-reply --dest=org.gnome.ShairportSync /org/gnome/ShairportSync org.gnome.ShairportSync.RemoteControl.DisableOpenALSA
