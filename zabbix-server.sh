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
REPO_URL="https://repo.zabbix.com/zabbix/$ZBX_VERSION/release/$OS_ID/9/noarch/zabbix-release-latest-$ZBX_VERSION.el9.noarch.rpm"
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

dnf makecache

echo "➤ Instalando TimescaleDB para PostgreSQL 16..."
dnf install -y timescaledb-2-postgresql-16

# ▶ Tuning automático do PostgreSQL via timescaledb-tune
echo "➤ Aplicando tuning do PostgreSQL com timescaledb-tune..."
timescaledb-tune --pg-config=/usr/pgsql-16/bin/pg_config --quiet --yes
systemctl restart postgresql-16

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
cat /usr/share/zabbix/sql-scripts/postgresql/timescaledb/schema.sql | sudo -u zabbix /usr/pgsql-16/bin/psql zabbix

# ▶ Configuração do Zabbix Server
ZBX_CONF="/etc/zabbix/zabbix_server.conf"
echo "➤ Configurando $ZBX_CONF..."

sed -i "s/^# DBPassword=.*/DBPassword=$ZBX_DB_PASS/" "$ZBX_CONF"

# ▶ Tuning do Zabbix Server
TOTAL_RAM_MB=$(awk '/MemTotal/ {print int($2/1024)}' /proc/meminfo)
CACHE_SIZE_MB=$((TOTAL_RAM_MB / 3))
echo "➤ RAM total: ${TOTAL_RAM_MB}MB — CacheSize definido para ${CACHE_SIZE_MB}MB (1/3 da RAM)"

echo "➤ Ajustando parâmetros de performance do Zabbix Server..."
sed -i "/^#\?CacheSize=/c\CacheSize=${CACHE_SIZE_MB}M"                "$ZBX_CONF"
sed -i "/^#\?StartPingers=/c\StartPingers=10"                         "$ZBX_CONF"
sed -i "/^#\?StartPollers=/c\StartPollers=10"                         "$ZBX_CONF"
sed -i "/^#\?StartPollersUnreachable=/c\StartPollersUnreachable=8"    "$ZBX_CONF"
sed -i "/^#\?StartTrappers=/c\StartTrappers=5"                        "$ZBX_CONF"
sed -i "/^#\?StartDBSyncers=/c\StartDBSyncers=8"                      "$ZBX_CONF"
sed -i "/^#\?StartDiscoverers=/c\StartDiscoverers=3"                  "$ZBX_CONF"
sed -i "/^#\?HistoryCacheSize=/c\HistoryCacheSize=128M"               "$ZBX_CONF"
sed -i "/^#\?HistoryIndexCacheSize=/c\HistoryIndexCacheSize=32M"      "$ZBX_CONF"
sed -i "/^#\?TrendCacheSize=/c\TrendCacheSize=64M"                    "$ZBX_CONF"
sed -i "/^#\?ValueCacheSize=/c\ValueCacheSize=128M"                   "$ZBX_CONF"
sed -i "/^#\?Timeout=/c\Timeout=30"                                   "$ZBX_CONF"

# ▶ Housekeeper
echo "➤ Ajustando parâmetros do Housekeeper..."
sed -i "/^#\?HousekeepingFrequency=/c\HousekeepingFrequency=12"       "$ZBX_CONF"
sed -i "/^#\?MaxHousekeeperDelete=/c\MaxHousekeeperDelete=1000000"    "$ZBX_CONF"

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
