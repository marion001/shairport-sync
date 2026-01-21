DBUS:
    #Tắt tiếng
    $:> dbus-send --system --print-reply --dest=org.gnome.ShairportSync /org/gnome/ShairportSync org.gnome.ShairportSync.RemoteControl.Mute

    #Bật tiếng
    $:> dbus-send --system --print-reply --dest=org.gnome.ShairportSync /org/gnome/ShairportSync org.gnome.ShairportSync.RemoteControl.Unmute

    #Thay đổi âm lượng
    $:> dbus-send --system --print-reply --dest=org.gnome.ShairportSync /org/gnome/ShairportSync org.gnome.ShairportSync.RemoteControl.ChangeVolume double:85

MQTT:
    #bật tắt tiếng
    mosquitto_pub -h localhost -t "shairport/vbot/remote" -m "mute"
    mosquitto_pub -h localhost -t "shairport/vbot/remote" -m "unmute"
    #Set âm lượng
    mosquitto_pub -t "shairport/vbot/remote" -m "volumeset 70"
