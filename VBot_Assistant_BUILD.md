	#Bản Build: 5.0.4
	
	#Ngày Build: 02/05/2026
	
	Các File Can Thiệp:
		- audio_alsa.c
		- dbus-service.c
		- org.gnome.ShairportSync.xml
		- verify-gitversion	(Thay Đổi Phiên Bản Build)
		- audio_alsa_vbot.h	(Tạo Mới File)

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
    $:> chmod +x verify-gitversion
    $:> dos2unix verify-gitversion
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

    #Lấy mức âm lượng hiện tại. Hàm này trả về giá trị nằm giữa -30.0 và 0.0
    tương ứng với mức âm lượng trên giao diện người dùng. Nó cũng có thể trả về -144.0 để báo hiệu chế độ tắt tiếng
    	$:> dbus-send --print-reply --system --dest=org.gnome.ShairportSync /org/gnome/ShairportSync org.freedesktop.DBus.Properties.Get string:org.gnome.ShairportSync string:Volume
    
    #Xác định ngưỡng âm lượng
    	$:> dbus-send --print-reply --system --dest=org.gnome.ShairportSync /org/gnome/ShairportSync org.freedesktop.DBus.Properties.Get string:org.gnome.ShairportSync string:LoudnessThreshold
    
    #Lấy trạng thái đang phát hay không
    	$:> dbus-send --print-reply --system --dest=org.gnome.ShairportSync /org/gnome/ShairportSync org.freedesktop.DBus.Properties.Get string:org.gnome.ShairportSync string:Active
    
    #Đặt mức âm lượng hiện tại. Giá trị này nên nằm trong khoảng từ -30.0 đến 0.0
    Đặt giá trị -144.0 để tắt tiếng. Lưu ý rằng tất cả các thao tác này được thực hiện cục bộ trên thiết bị Shairport Sync
    Việc điều chỉnh âm lượng của nguồn âm thanh (ví dụ: iTunes / macOS Music / iOS) sẽ không được cập nhật để phản ánh bất kỳ thay đổi nào.
    	$:> dbus-send --print-reply --system --dest=org.gnome.ShairportSync /org/gnome/ShairportSync org.freedesktop.DBus.Properties.Set string:org.gnome.ShairportSync string:Volume variant:double:-10.0
    
    #Hãy dừng phiên phát hiện tại ngay lập tức
    Shairport Sync sẽ ngừng phát và ngắt kết nối với nguồn âm thanh ngay lập tức
    Điều này có thể hiển thị dưới dạng lỗi ở nguồn phát.
    	$:> dbus-send --system --print-reply --type=method_call --dest=org.gnome.ShairportSync '/org/gnome/ShairportSync' org.gnome.ShairportSync.DropSession
    
    #Giao thức mà Shairport Sync được thiết kế cho -- AirPlay hoặc AirPlay 2:
    	$:> dbus-send --print-reply --system --dest=org.gnome.ShairportSync /org/gnome/ShairportSync org.freedesktop.DBus.Properties.Get string:org.gnome.ShairportSync string:Protocol
    
    #kiểm tra thông tin các lệnh có thể giao tiếp với dbus:
        $:> gdbus introspect --system --dest org.gnome.ShairportSync --object-path /org/gnome/ShairportSync
