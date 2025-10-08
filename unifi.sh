#!/bin/bash

# Versão padrão do UniFi Server
default_version="9.0.108"

# Perguntar a versão do UniFi Server, com valor padrão
read -p "Enter the version of UniFi Server you want to install [press Enter for 9.0.108]: " unifi_version
unifi_version=${unifi_version:-$default_version}

cat << 'EOF' > /etc/yum.repos.d/mongodb-org-8.0.repo
[mongodb-org-8.0]
name=MongoDB Repository
baseurl=https://repo.mongodb.org/yum/redhat/$releasever/mongodb-org/8.0/x86_64/
gpgcheck=1
enabled=1
gpgkey=https://pgp.mongodb.com/server-8.0.asc
EOF

# Atualizar e instalar dependências
yum -y update
yum install epel-release -y
yum install mongodb-org java-17-openjdk-devel unzip wget -y

useradd ubnt

# Iniciar e habilitar o serviço MongoDB
systemctl enable --now mongod.service
systemctl status mongod.service --no-pager

# Baixar o UniFi Server na versão escolhida
cd /opt
wget "https://dl.ui.com/unifi/${unifi_version}/UniFi.unix.zip"

# Descompactar o UniFi Server
unzip -qo /opt/UniFi.unix.zip -d /opt

# Ajustar permissões
chown -R ubnt:ubnt /opt/UniFi

# Criar arquivo de serviço systemd
cat << 'EOF' > /etc/systemd/system/unifi.service
# Systemd unit file for UniFi Controller
[Unit]
Description=UniFi AP Web Controller
After=syslog.target network.target

[Service]
Type=simple
User=ubnt
WorkingDirectory=/opt/UniFi
# CONF PARA ALMA 9
ExecStart=/usr/lib/jvm/jre-17/bin/java --add-opens=java.base/java.time=ALL-UNNAMED $JAVA_OPTS -jar /opt/UniFi/lib/ace.jar start
# ExecStart=/usr/bin/java -Xmx1024M -jar /opt/UniFi/lib/ace.jar start
ExecStop=/usr/bin/java -jar /opt/UniFi/lib/ace.jar stop
SuccessExitStatus=143

[Install]
WantedBy=multi-user.target
EOF

# Habilitar e iniciar o serviço UniFi
systemctl daemon-reexec
systemctl daemon-reload
systemctl enable --now unifi.service
systemctl status unifi.service --no-pager

# Limpar o arquivo zip
rm -rf /opt/UniFi.unix.zip

# Reboot para garantir que o sistema esteja pronto
read -p "Installation is complete. Would you like to restart your system now? (y/n): " reboot_choice
if [[ "$reboot_choice" =~ ^[Yy]$ ]]; then
  reboot
else
  echo "Installation complete. You can manually restart the system later."
fi