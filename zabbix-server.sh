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

# ▶ Otimização do PostgreSQL
PG_CONF="/var/lib/pgsql/16/data/postgresql.conf"
echo "➤ Otimizando parâmetros do PostgreSQL para Zabbix..."

cat <<EOF >> "$PG_CONF"

# ────────────────────────────────
# Ajustes de performance - Zabbix
# ────────────────────────────────
shared_buffers = 2GB
work_mem = 32MB
maintenance_work_mem = 512MB
effective_cache_size = 4GB
wal_buffers = 16MB
checkpoint_timeout = 15min
max_wal_size = 4GB
min_wal_size = 1GB
random_page_cost = 1.1
effective_io_concurrency = 200
autovacuum_vacuum_scale_factor = 0.05
autovacuum_analyze_scale_factor = 0.02
autovacuum_vacuum_cost_limit = 400
autovacuum_max_workers = 6
max_connections = 200
EOF

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

echo "➤ Ajustando parâmetros de desempenho do Zabbix..."
sed -i "s/^# DBPassword=.*/DBPassword=$ZBX_DB_PASS/" "$ZBX_CONF"
sed -i "/^#\?StartDBSyncers=/c\StartDBSyncers=8" "$ZBX_CONF"
sed -i "/^#\?StartDiscoverers=/c\StartDiscoverers=3" "$ZBX_CONF"
sed -i "/^#\?StartTrappers=/c\StartTrappers=5" "$ZBX_CONF"
sed -i "/^#\?HistoryCacheSize=/c\HistoryCacheSize=128M" "$ZBX_CONF"
sed -i "/^#\?HistoryIndexCacheSize=/c\HistoryIndexCacheSize=32M" "$ZBX_CONF"
sed -i "/^#\?TrendCacheSize=/c\TrendCacheSize=64M" "$ZBX_CONF"
sed -i "/^#\?ValueCacheSize=/c\ValueCacheSize=128M" "$ZBX_CONF"
sed -i "/^#\?CacheSize=/c\CacheSize=1024M" "$ZBX_CONF"
sed -i "/^#\?StartPingers=/c\StartPingers=10" "$ZBX_CONF"
sed -i "/^#\?StartPollers=/c\StartPollers=10" "$ZBX_CONF"
sed -i "/^#\?StartPollersUnreachable=/c\StartPollersUnreachable=10" "$ZBX_CONF"
sed -i "/^#\?Timeout=/c\Timeout=30" "$ZBX_CONF"

# ▶ Evitar sobrecarga do Housekeeper
echo "➤ Ajustando parâmetros do Housekeeper..."
sed -i "/^#\?HousekeepingFrequency=/c\HousekeepingFrequency=12" "$ZBX_CONF"
sed -i "/^#\?MaxHousekeeperDelete=/c\MaxHousekeeperDelete=1000000" "$ZBX_CONF"
sed -i "/^#\?HistoryStoragePeriod=/c\HistoryStoragePeriod=90d" "$ZBX_CONF"
sed -i "/^#\?TrendStoragePeriod=/c\TrendStoragePeriod=365d" "$ZBX_CONF"

# ▶ Plugins adicionais
echo "➤ Instalando plugins adicionais do zabbix-agent2..."
dnf install -y zabbix-agent2-plugin-postgresql

# ▶ Ativação de serviços
echo "➤ Habilitando e iniciando serviços..."
systemctl enable --now zabbix-server zabbix-agent2 httpd php-fpm

# ▶ Manutenção automática do banco
echo "➤ Configurando manutenção automática do banco de dados..."
cat <<'EOF' > /etc/cron.d/zabbix_db_maintenance
# Otimização automática do banco Zabbix
30 2 * * 4 postgres /usr/pgsql-16/bin/vacuumdb --analyze zabbix
30 4 * * 0 postgres /usr/pgsql-16/bin/reindexdb zabbix
EOF
chmod 644 /etc/cron.d/zabbix_db_maintenance

# ▶ Backup automático do banco de dados
read -p "Deseja configurar o backup automático do banco de dados do Zabbix? [s/N]: " CONFIG_DUMP
if [[ "$CONFIG_DUMP" =~ ^[sS]$ ]]; then
    echo "➤ Executando script de configuração de backup..."
    bash <(curl -s https://raw.githubusercontent.com/0LB-i/menu/main/dump-zabbix.sh)
else
    echo "ℹ️ Configuração de backup ignorada."
fi

echo "✅ Instalação concluída com sucesso para o Zabbix $ZBX_VERSION com PostgreSQL 16 em $OS_ID!"