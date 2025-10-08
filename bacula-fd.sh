#!/bin/bash

set -e

echo "[INFO] Baixando Bacula 9.4.4 source..."
wget -O /tmp/bacula-9.4.4.tar.gz https://sourceforge.net/projects/bacula/files/bacula/9.4.4/bacula-9.4.4.tar.gz/download

echo "[INFO] Instalando dependências de compilação..."
dnf install -y gcc-c++ zlib-devel lzo-devel libacl-devel openssl-devel chkconfig make wget

echo "[INFO] Extraindo source..."
tar -xf /tmp/bacula-9.4.4.tar.gz -C /usr/src
cd /usr/src/bacula-9.4.4

echo "[INFO] Configurando build..."
./configure \
  --enable-client-only \
  --enable-build-dird=no \
  --enable-build-stored=no \
  --bindir=/usr/bin \
  --sbindir=/usr/sbin \
  --with-scriptdir=/etc/bacula/scripts \
  --with-working-dir=/var/lib/bacula \
  --with-logdir=/var/log \
  --enable-smartalloc

echo "[INFO] Compilando e instalando..."
make -j$(nproc) && make install

echo "[INFO] Criando unidade systemd..."
cat <<EOL > /etc/systemd/system/bacula-fd.service
[Unit]
Description=Bacula File Daemon service
After=network.target

[Service]
Type=simple
User=root
Group=root
ExecStart=/usr/sbin/bacula-fd -f

[Install]
WantedBy=multi-user.target
EOL

echo "[INFO] Ativando serviço..."
systemctl daemon-reload
systemctl enable --now bacula-fd.service

echo "[OK] Bacula File Daemon instalado e iniciado com sucesso."