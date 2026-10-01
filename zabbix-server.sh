#!/bin/bash
# ─────────────────────────────────────────────────────────────
# Script para instalar o Zabbix Server com PostgreSQL 16 + TimescaleDB
# Compatível com AlmaLinux 9 e Rocky Linux 9
# Autor: Gabriel B. Machado
# ─────────────────────────────────────────────────────────────

# ▶ Detecta distribuição (AlmaLinux ou Rocky)
OS_ID=$(awk -F= '/^ID=/{gsub(/"/, "", $2); print $2}' /etc/os-release)
if [[ "$OS_ID" != "almalinux" && "$OS_ID" != "rocky" ]]; then
  echo "❌ Distribuição não suportada: $OS_ID"
  exit 1
fi

echo "➤ Distribuição detectada: $OS_ID"

# ▶ Solicita versão do Zabbix
read -p "Digite a versão do Zabbix que deseja instalar [padrão: 7.0]: " ZBX_VERSION
ZBX_VERSION=${ZBX_VERSION:-7.0}

# ▶ Solicita senha do PostgreSQL
read -s -p "Digite a senha para o usuário 'zabbix' no PostgreSQL: " ZBX_DB_PASS
echo

# ▶ Utilitários básicos
echo "➤ Instalando utilitários básicos..."
dnf install -y net-snmp net-snmp-utils glibc-langpack-pt whois

# ▶ Adiciona repositório Zabbix de acordo com a distro detectada
[[ "$OS_ID" == "almalinux" ]] && ZBX_OS="alma" || ZBX_OS="rocky"
REPO_URL="https://repo.zabbix.com/zabbix/$ZBX_VERSION/release/$ZBX_OS/9/noarch/zabbix-release-latest-$ZBX_VERSION.el9.noarch.rpm"
echo "➤ Adicionando repositório Zabbix versão $ZBX_VERSION para $OS_ID..."
rpm -Uvh "$REPO_URL" || {
  echo "❌ Erro ao adicionar o repositório. Verifique se a versão está correta."
  exit 1
}

# ▶ Instalação do Zabbix Server
echo "➤ Instalando pacotes principais do Zabbix..."
dnf clean all
dnf install -y \
  zabbix-server-pgsql \
  zabbix-web-pgsql \
  zabbix-apache-conf \
  zabbix-sql-scripts \
  zabbix-selinux-policy \
  zabbix-agent2

# ▶ PostgreSQL 16: repositório e instalação
echo "➤ Configurando repositório do PostgreSQL 16..."
dnf install -y https://download.postgresql.org/pub/repos/yum/reporpms/EL-9-x86_64/pgdg-redhat-repo-latest.noarch.rpm
dnf -qy module disable postgresql

echo "➤ Instalando PostgreSQL 16..."
dnf install -y postgresql16 postgresql16-server

echo "➤ Inicializando PostgreSQL 16..."
/usr/pgsql-16/bin/postgresql-16-setup initdb
systemctl enable --now postgresql-16
systemctl restart postgresql-16

# ▶ TimescaleDB: repositório manual (evita repo gerado incorretamente)
echo "➤ Configurando repositório do TimescaleDB..."
rm -f /etc/yum.repos.d/timescale_timescaledb.repo
rm -f /etc/yum.repos.d/timescale_timescaledb-source.repo

cat > /etc/yum.repos.d/timescaledb.repo << 'EOF'
[timescale_timescaledb]
name=timescale_timescaledb
baseurl=https://packagecloud.io/timescale/timescaledb/el/9/$basearch
repo_gpgcheck=1
gpgcheck=0
enabled=1
gpgkey=https://packagecloud.io/timescale/timescaledb/gpgkey
sslverify=1
sslcacert=/etc/pki/tls/certs/ca-bundle.crt
metadata_expire=300
EOF

rpm --import https://packagecloud.io/timescale/timescaledb/gpgkey
dnf makecache -y

echo "➤ Instalando TimescaleDB 2.26.0 para PostgreSQL 16..."
dnf install -y timescaledb-2-postgresql-16-2.26.0 timescaledb-2-loader-postgresql-16-2.26.0 timescaledb-tools

echo "➤ Corrigindo control file do TimescaleDB para versão 2.26.0..."
sed -i -E "s/^default_version = '[^']*'/default_version = '2.26.0'/" /usr/pgsql-16/share/extension/timescaledb.control

# ▶ Tuning automático do PostgreSQL via timescaledb-tune
echo "➤ Aplicando tuning do PostgreSQL com timescaledb-tune..."
timescaledb-tune --pg-config=/usr/pgsql-16/bin/pg_config --max-conns=300 --quiet --yes
systemctl restart postgresql-16

echo "➤ Aguardando PostgreSQL ficar disponível..."
until sudo -u postgres /usr/pgsql-16/bin/pg_isready -q; do sleep 1; done

# ▶ Banco de dados
echo "➤ Criando usuário e banco de dados 'zabbix' no PostgreSQL 16..."
sudo -u postgres /usr/pgsql-16/bin/psql -c "CREATE USER zabbix WITH PASSWORD '$ZBX_DB_PASS';"
sudo -u postgres /usr/pgsql-16/bin/psql -c "CREATE DATABASE zabbix OWNER zabbix ENCODING 'UTF8' LC_COLLATE='C' LC_CTYPE='C' TEMPLATE template0;"

# ▶ Habilita extensão TimescaleDB no banco zabbix
echo "➤ Habilitando extensão TimescaleDB no banco zabbix..."
echo "CREATE EXTENSION IF NOT EXISTS timescaledb CASCADE;" | sudo -u postgres /usr/pgsql-16/bin/psql zabbix

# ▶ Importa schema do Zabbix
echo "➤ Importando schema do Zabbix para o banco de dados..."
zcat /usr/share/zabbix/sql-scripts/postgresql/server.sql.gz | sudo -u zabbix /usr/pgsql-16/bin/psql zabbix

# ▶ Aplica schema TimescaleDB por cima
echo "➤ Aplicando schema TimescaleDB..."
sudo -u zabbix /usr/pgsql-16/bin/psql zabbix < /usr/share/zabbix/sql-scripts/postgresql/timescaledb/schema.sql

# ▶ Configuração do Zabbix Server
ZBX_CONF="/etc/zabbix/zabbix_server.conf"

set_zbx_param() {
    local param="$1"
    local value="$2"
    local file="$3"

    if grep -qE "^[[:space:]]*${param}=" "$file"; then
        # Já existe linha ativa: remove duplicadas e atualiza só a primeira
        sed -i -E "0,/^[[:space:]]*${param}=/{s/^[[:space:]]*${param}=.*/${param}=${value}/;t;};/^[[:space:]]*${param}=/d" "$file"
        echo "  ✔ ${param} atualizado (linha existente)"
    elif grep -qE "^[[:space:]]*#[[:space:]]*${param}=" "$file"; then
        # Só existe comentada: descomenta apenas a primeira ocorrência
        sed -i -E "0,/^[[:space:]]*#[[:space:]]*${param}=/s//${param}=/;s/^${param}=.*/${param}=${value}/" "$file"
        echo "  ✔ ${param} atualizado (linha comentada ativada)"
    else
        echo "${param}=${value}" >> "$file"
        echo "  ➕ ${param} adicionado (não existia no arquivo)"
    fi
}

echo "➤ Configurando $ZBX_CONF..."

set_zbx_param "DBPassword" "$ZBX_DB_PASS" "$ZBX_CONF"

TOTAL_RAM_MB=$(awk '/MemTotal/ {print int($2/1024)}' /proc/meminfo)
CACHE_SIZE_MB=$((TOTAL_RAM_MB / 3))
echo "➤ RAM total: ${TOTAL_RAM_MB}MB — CacheSize definido para ${CACHE_SIZE_MB}MB (1/3 da RAM)"

echo "➤ Ajustando parâmetros de performance do Zabbix Server..."
set_zbx_param "CacheSize"               "${CACHE_SIZE_MB}M" "$ZBX_CONF"
set_zbx_param "StartPingers"            "10"                "$ZBX_CONF"
set_zbx_param "StartPollers"            "10"                "$ZBX_CONF"
set_zbx_param "StartPollersUnreachable" "8"                 "$ZBX_CONF"
set_zbx_param "StartTrappers"           "5"                 "$ZBX_CONF"
set_zbx_param "StartDBSyncers"          "8"                 "$ZBX_CONF"
set_zbx_param "StartDiscoverers"        "3"                 "$ZBX_CONF"
set_zbx_param "HistoryCacheSize"        "128M"              "$ZBX_CONF"
set_zbx_param "HistoryIndexCacheSize"   "32M"               "$ZBX_CONF"
set_zbx_param "TrendCacheSize"          "64M"               "$ZBX_CONF"
set_zbx_param "ValueCacheSize"          "128M"              "$ZBX_CONF"
set_zbx_param "Timeout"                 "30"                "$ZBX_CONF"

# ▶ Housekeeper
echo "➤ Ajustando parâmetros do Housekeeper..."
set_zbx_param "HousekeepingFrequency" "12"      "$ZBX_CONF"
set_zbx_param "MaxHousekeeperDelete"  "1000000" "$ZBX_CONF"

# ▶ Plugins adicionais
echo "➤ Instalando plugins adicionais do zabbix-agent2..."
dnf install -y zabbix-agent2-plugin-postgresql

# ▶ Ativação de serviços
echo "➤ Habilitando e iniciando serviços..."
systemctl restart zabbix-server zabbix-agent2 httpd php-fpm
systemctl enable zabbix-server zabbix-agent2 httpd php-fpm

# ▶ Manutenção automática do banco
echo "➤ Configurando manutenção automática do banco de dados..."
cat <<'EOF' > /etc/cron.d/zabbix_db_maintenance
# Otimização automática do banco Zabbix
30 2 * * 4 postgres /usr/pgsql-16/bin/vacuumdb --analyze zabbix
30 4 * * 0 postgres /usr/pgsql-16/bin/reindexdb zabbix
EOF
chmod 644 /etc/cron.d/zabbix_db_maintenance

# ▶ PHP OPcache
dnf install -y php-opcache
cat <<'EOF' > /etc/php.d/10-opcache.ini
zend_extension=opcache.so
opcache.enable=1
opcache.enable_cli=1
opcache.memory_consumption=256
opcache.interned_strings_buffer=16
opcache.max_accelerated_files=10000
opcache.revalidate_freq=60
opcache.validate_timestamps=1
EOF
echo "➤ Reiniciando serviços web (php-fpm e httpd)..."
systemctl restart php-fpm httpd

# ▶ Backup automático do banco de dados
read -p "Deseja configurar o backup automático do banco de dados do Zabbix? [s/N]: " CONFIG_DUMP
if [[ "$CONFIG_DUMP" =~ ^[sS]$ ]]; then
  echo "➤ Executando script de configuração de backup..."
  bash <(curl -s https://raw.githubusercontent.com/0LB-i/menu/main/dump-zabbix.sh)
else
  echo "ℹ️ Configuração de backup ignorada."
fi

echo ""
echo "✅ Instalação concluída: Zabbix $ZBX_VERSION + PostgreSQL 16 + TimescaleDB em $OS_ID!"
