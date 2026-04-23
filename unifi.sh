#!/bin/bash

# Verificar suporte a AVX (exigido pelo MongoDB 5.0+)
AVX_SUPPORTED=true
if ! grep -q avx /proc/cpuinfo; then
  AVX_SUPPORTED=false
  echo "AVISO: Este processador não suporta AVX. Usando MongoDB 4.4 como alternativa."
fi

# Detectar versão do RHEL
OS_VER=$(rpm -E %{rhel} 2>/dev/null || echo "8")

# Versão padrão do UniFi Server
default_version="9.0.108"

# Perguntar a versão do UniFi Server, com valor padrão
read -p "Enter the version of UniFi Server you want to install [press Enter for ${default_version}]: " unifi_version
unifi_version=${unifi_version:-$default_version}

if [[ "$AVX_SUPPORTED" == "true" ]]; then
    echo "AVX detectado. Prosseguindo com MongoDB 8.0..."
    cat << 'EOF' > /etc/yum.repos.d/mongodb-org-8.0.repo
[mongodb-org-8.0]
name=MongoDB Repository
baseurl=https://repo.mongodb.org/yum/redhat/$releasever/mongodb-org/8.0/x86_64/
gpgcheck=1
enabled=1
gpgkey=https://pgp.mongodb.com/server-8.0.asc
EOF
else
    # MongoDB 4.4 não tem pacotes para RHEL 9 — usa repo do RHEL 8 como fallback
    MONGO_RELVER="$OS_VER"
    if [[ "$OS_VER" == "9" ]]; then
        echo "RHEL 9 detectado sem AVX. Usando repositório MongoDB 4.4 para RHEL 8 como fallback..."
        MONGO_RELVER="8"
    fi
    cat > /etc/yum.repos.d/mongodb-org-4.4.repo << EOF
[mongodb-org-4.4]
name=MongoDB 4.4 Repository
baseurl=https://repo.mongodb.org/yum/redhat/${MONGO_RELVER}/mongodb-org/4.4/x86_64/
gpgcheck=1
enabled=1
gpgkey=https://pgp.mongodb.com/server-4.4.asc
EOF
fi

# Atualizar e instalar dependências
yum update -y
yum install -y epel-release
yum install -y mongodb-org java-17-openjdk-devel unzip wget

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
ExecStart=/usr/lib/jvm/jre-17/bin/java --add-opens=java.base/java.time=ALL-UNNAMED -jar /opt/UniFi/lib/ace.jar start
# ExecStart=/usr/bin/java -Xmx1024M -jar /opt/UniFi/lib/ace.jar start
ExecStop=/usr/bin/java -jar /opt/UniFi/lib/ace.jar stop
SuccessExitStatus=143

[Install]
WantedBy=multi-user.target
EOF

# Habilitar e iniciar o serviço UniFi
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