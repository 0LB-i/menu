#!/bin/bash

# ─────────────────────────────────────────────────────────────
# Script para instalar o Zabbix Server com PostgreSQL 16
# Compatível com AlmaLinux 9 e Rocky Linux 9
# Autor: Gabriel B. Machado
# ─────────────────────────────────────────────────────────────

# ▶ Ajustes iniciais do sistema
echo "➤ Instalando utilitários básicos..."
dnf install -y net-snmp net-snmp-utils glibc-langpack-pt

# ▶ Detecta distribuição (AlmaLinux ou Rocky)
OS_ID=$(awk -F= '/^ID=/{gsub(/"/, "", $2); print $2}' /etc/os-release)
if [[ "$OS_ID" != "almalinux" && "$OS_ID" != "rocky" ]]; then
  echo "❌ Distribuição não suportada: $OS_ID"
  exit 1
fi

# ▶ Solicita versão do Zabbix
read -p "Digite a versão do Zabbix que deseja instalar [padrão: 7.0]: " ZBX_VERSION
ZBX_VERSION=${ZBX_VERSION:-7.0}

# ▶ Solicita senha do PostgreSQL
read -s -p "Digite a senha para o usuário 'zabbix' no PostgreSQL: " ZBX_DB_PASS
echo

# ▶ Adiciona repositório Zabbix de acordo com a distro detectada
REPO_URL="https://repo.zabbix.com/zabbix/$ZBX_VERSION/release/$OS_ID/9/noarch/zabbix-release-latest-$ZBX_VERSION.el9.noarch.rpm"
echo "➤ Adicionando repositório Zabbix versão $ZBX_VERSION para $OS_ID..."
rpm -Uvh "$REPO_URL" || {
    echo "❌ Erro ao adicionar o repositório. Verifique se a versão está correta."
    exit 1
}

# ▶ PostgreSQL 16: repositório e instalação
echo "➤ Configurando repositório do PostgreSQL 16..."
dnf install -y https://download.postgresql.org/pub/repos/yum/reporpms/EL-9-x86_64/pgdg-redhat-repo-latest.noarch.rpm
dnf -qy module disable postgresql

echo "➤ Limpando e atualizando cache do DNF..."
dnf clean all
dnf makecache

echo "➤ Instalando PostgreSQL 16..."
dnf install -y postgresql16 postgresql16-server

echo "➤ Inicializando PostgreSQL 16..."
/usr/pgsql-16/bin/postgresql-16-setup initdb
systemctl enable --now postgresql-16
systemctl restart postgresql-16

# ▶ Instalação do Zabbix
echo "➤ Instalando pacotes principais do Zabbix..."
dnf install -y \
    zabbix-server-pgsql \
    zabbix-web-pgsql \
    zabbix-apache-conf \
    zabbix-sql-scripts \
    zabbix-selinux-policy \
    zabbix-agent2

# ▶ Banco de dados
echo "➤ Criando usuário e banco de dados 'zabbix' no PostgreSQL 16..."
sudo -u postgres /usr/pgsql-16/bin/psql -c "CREATE USER zabbix WITH PASSWORD '$ZBX_DB_PASS';"
sudo -u postgres /usr/pgsql-16/bin/psql -c "CREATE DATABASE zabbix OWNER zabbix ENCODING 'UTF8' LC_COLLATE='C' LC_CTYPE='C' TEMPLATE template0;"

echo "➤ Importando schema do Zabbix para o banco de dados..."
zcat /usr/share/zabbix/sql-scripts/postgresql/server.sql.gz | sudo -u zabbix /usr/pgsql-16/bin/psql zabbix

# ▶ Configuração do Zabbix Server
ZBX_CONF="/etc/zabbix/zabbix_server.conf"
echo "➤ Atualizando configurações no zabbix_server.conf..."

sed -i "s/^# DBPassword=.*/DBPassword=$ZBX_DB_PASS/" "$ZBX_CONF"
sed -i "/^#\?CacheSize=/c\CacheSize=512M" "$ZBX_CONF"
sed -i "/^#\?StartPingers=/c\StartPingers=10" "$ZBX_CONF"
sed -i "/^#\?StartPollers=/c\StartPollers=10" "$ZBX_CONF"
sed -i "/^#\?StartPollersUnreachable=/c\StartPollersUnreachable=8" "$ZBX_CONF"
sed -i "/^#\?Timeout=/c\Timeout=30" "$ZBX_CONF"

# ▶ Plugins adicionais
echo "➤ Instalando plugins adicionais do zabbix-agent2..."
dnf install -y zabbix-agent2-plugin-postgresql

# ▶ Ativação de serviços
echo "➤ Habilitando e iniciando serviços..."
systemctl enable --now zabbix-server zabbix-agent2 httpd php-fpm

# ▶ Backup automático do banco de dados
read -p "Deseja configurar o backup automático do banco de dados do Zabbix? [s/N]: " CONFIG_DUMP
if [[ "$CONFIG_DUMP" =~ ^[sS]$ ]]; then
    echo "➤ Executando script de configuração de backup..."
    bash <(curl -s https://raw.githubusercontent.com/0LB-i/menu/main/dump-zabbix.sh)
else
    echo "ℹ️ Configuração de backup ignorada."
fi

echo "✅ Instalação concluída com sucesso para o Zabbix $ZBX_VERSION com PostgreSQL 16 em $OS_ID!"