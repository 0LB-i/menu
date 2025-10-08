#!/bin/bash

SCRIPT_PATH="/usr/local/bin/zabbix-db-backup.sh"
BACKUP_DIR="/var/backups/zabbix"
LOG_FILE="/var/log/zabbix-dump.log"
CRON_ENTRY="0 2 * * * $SCRIPT_PATH >> $LOG_FILE 2>&1"

echo "➤ Criando diretório de backups: $BACKUP_DIR"
mkdir -p "$BACKUP_DIR"

echo "➤ Criando script de dump em: $SCRIPT_PATH"
cat << 'EOF' > "$SCRIPT_PATH"
#!/bin/bash

# Zabbix PostgreSQL Backup Script
DB_NAME="zabbix"
DB_USER="zabbix"
BACKUP_DIR="/var/backups/zabbix"
TIMESTAMP=$(date +%F_%H-%M)
DUMP_FILE="zabbix_dump_$TIMESTAMP.sql"
DUMP_PATH="$BACKUP_DIR/$DUMP_FILE"

mkdir -p "$BACKUP_DIR"
find "$BACKUP_DIR" -type f -name "zabbix_dump_*.sql" -delete

sudo -u "$DB_USER" /usr/bin/pg_dump -U "$DB_USER" "$DB_NAME" \
  --exclude-table=history \
  --exclude-table=history_uint \
  --exclude-table=history_str \
  --exclude-table=history_log \
  --exclude-table=history_text \
  --exclude-table=trends \
  --exclude-table=trends_uint > "$DUMP_PATH"

chmod 600 "$DUMP_PATH"
EOF

chmod +x "$SCRIPT_PATH"
chown root:root "$SCRIPT_PATH"

echo "➤ Adicionando cron para execução diária às 2h..."
# Evita duplicidade no crontab
(crontab -l 2>/dev/null | grep -v "$SCRIPT_PATH" ; echo "$CRON_ENTRY") | crontab -

echo "✅ Script criado e agendado com sucesso!"