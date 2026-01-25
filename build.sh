#!/usr/bin/env bash
set -e

echo "==> make clean"
make clean

echo "==> autoreconf"
autoreconf -fi

echo "==> configure"
./configure --with-mqtt-client \
  --sysconfdir=/etc \
  --with-alsa \
  --with-soxr \
  --with-avahi \
  --with-dbus-interface \
  --with-ssl=openssl \
  --with-systemd \
  --with-airplay-2

echo "==> make"
make

echo "==> make install"
sudo make install

echo "==> systemd reload & restart"
sudo systemctl daemon-reload
sudo systemctl restart shairport-sync

echo "==> shairport-sync status"
sudo systemctl status shairport-sync
