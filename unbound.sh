#!/bin/bash
set -e

echo "==> Instalando pacotes..."
yum install -y unbound logrotate curl

echo "==> Ajustando unbound.conf..."
THREADS=$(nproc)
SLABS=1
while [[ $SLABS -lt $THREADS ]]; do SLABS=$((SLABS * 2)); done

MEM_MB=$(awk '/MemTotal/ {print int($2/1024)}' /proc/meminfo)
MSG_CACHE_MB=$((MEM_MB / 4))
RRSET_CACHE_MB=$((MSG_CACHE_MB * 2))
KEY_CACHE_MB=$((MEM_MB / 16))

sed -i \
  -e "s/# num-threads:.*/num-threads: ${THREADS}/" \
  -e "s/# msg-cache-slabs:.*/msg-cache-slabs: ${SLABS}/" \
  -e "s/# rrset-cache-slabs:.*/rrset-cache-slabs: ${SLABS}/" \
  -e "s/# infra-cache-slabs:.*/infra-cache-slabs: ${SLABS}/" \
  -e "s/# key-cache-slabs:.*/key-cache-slabs: ${SLABS}/" \
  -e "s/# rrset-cache-size:.*/rrset-cache-size: ${RRSET_CACHE_MB}m/" \
  -e "s/# msg-cache-size:.*/msg-cache-size: ${MSG_CACHE_MB}m/" \
  -e "s/# key-cache-size:.*/key-cache-size: ${KEY_CACHE_MB}m/" \
  -e 's/# so-rcvbuf:.*/so-rcvbuf: 4m/' \
  -e 's/# so-sndbuf:.*/so-sndbuf: 4m/' \
  -e 's/# interface: 0.0.0.0$/interface: 0.0.0.0/' \
  -e 's/# interface: ::0$/interface: ::0/' \
  -e 's/# interface: 192\.0\.2\.153$/interface: 0.0.0.0@853/' \
  -e 's/# interface: 192\.0\.2\.154$/interface: ::0@853/' \
  -e 's|# tls-service-key:.*|tls-service-key: "/etc/unbound/unbound_server.key"|' \
  -e 's|# tls-service-pem:.*|tls-service-pem: "/etc/unbound/unbound_server.pem"|' \
  -e 's/# tls-port:.*/tls-port: 853/' \
  -e 's/interface-automatic: no/interface-automatic: yes/' \
  -e 's/# outgoing-range:.*/outgoing-range: 8192/' \
  -e 's/# num-queries-per-thread:.*/num-queries-per-thread: 4096/' \
  -e 's/# cache-max-ttl:.*/cache-max-ttl: 14400/' \
  -e 's/# cache-min-ttl:.*/cache-min-ttl: 300/' \
  -e 's/# ip-ratelimit:.*/ip-ratelimit: 300/' \
  -e 's/# ip-ratelimit-factor:.*/ip-ratelimit-factor: 0/' \
  -e 's|# root-hints: ""|root-hints: "/var/lib/unbound/root.hints"|' \
  -e 's|# logfile: ""|logfile: "/var/log/unbound.log"|' \
  -e '/^[[:space:]]*prefetch:[[:space:]]*yes$/!s/^[# ]*prefetch:.*/prefetch: yes/' \
  -e '/^[[:space:]]*prefetch-key:[[:space:]]*yes$/!s/^[# ]*prefetch-key:.*/prefetch-key: yes/' \
  -e '/^[[:space:]]*serve-expired:[[:space:]]*yes$/!s/^[# ]*serve-expired:.*/serve-expired: yes/' \
  -e '/^[[:space:]]*serve-expired-ttl:[[:space:]]*[^0]/!s/^[# ]*serve-expired-ttl:.*/serve-expired-ttl: 3600/' \
  -e '/^[[:space:]]*hide-identity:[[:space:]]*yes$/!s/^[# ]*hide-identity:.*/hide-identity: yes/' \
  -e '/^[[:space:]]*hide-version:[[:space:]]*yes$/!s/^[# ]*hide-version:.*/hide-version: yes/' \
  -e '/^[[:space:]]*use-caps-for-id:[[:space:]]*yes$/!s/^[# ]*use-caps-for-id:.*/use-caps-for-id: yes/' \
  /etc/unbound/unbound.conf

echo "==> Adicionando access-control..."

insert_access_controls() {
    local conf_file="/etc/unbound/unbound.conf"
    local ips=("$@")

    for ip in "${ips[@]}"; do
        local ip_escaped
        ip_escaped=$(printf '%s\n' "$ip" | sed 's/[.[\*^$()+?{|]/\\&/g')

        # Verifica se já existe
        if grep -Eq "^[[:space:]]*access-control:[[:space:]]*${ip_escaped}[[:space:]]+allow" "$conf_file"; then
            echo "IP ${ip} já existe, pulando..."
            continue
        fi

        # Encontra a última linha com access-control (comentada ou não)
        local last_line
        last_line=$(grep -n "access-control:" "$conf_file" | tail -1 | cut -d: -f1)

        if [[ -n "$last_line" ]]; then
            local indent
            indent=$(sed -n "${last_line}p" "$conf_file" | sed -E 's/(^[[:space:]]*).*/\1/')
            sed -i "${last_line}a\\${indent}access-control: ${ip} allow" "$conf_file"
            echo "IP ${ip} adicionado."
        else
            echo "❌ Seção access-control não encontrada em $conf_file."
            exit 1
        fi
    done
}

# Lista padrão de IPs
ips=(
    "127.0.0.0/8"
    "10.0.0.0/8"
    "100.64.0.0/10"
    "172.16.0.0/12"
    "192.168.0.0/16"
    "::1"
)

read -p "Quer adicionar IPs extras para access-control? Separe por espaço ou deixe vazio para pular: " extra_ips
if [[ -n "$extra_ips" ]]; then
    for ip in $extra_ips; do
        ips+=("$ip")
    done
fi

insert_access_controls "${ips[@]}"

echo "==> Baixando root.hints..."
curl -s -o /var/lib/unbound/root.hints https://www.internic.net/domain/named.cache

echo "==> Criando log e configurando logrotate..."
touch /var/log/unbound.log
chown unbound:unbound /var/log/unbound.log

cat << 'EOF' > /etc/logrotate.d/unbound
/var/log/unbound.log {
    daily
    rotate 12
    compress
    delaycompress
    missingok
    notifempty
    create 0664 unbound unbound
    postrotate
        unbound-control log_reopen
    endscript
}
EOF

cat << EOF > /etc/logrotate.d/syslog
/var/log/messages /var/log/secure {
    daily
    rotate 7
    missingok
    notifempty
    compress
    delaycompress
    sharedscripts
    postrotate
        /usr/bin/systemctl reload rsyslog >/dev/null 2>&1 || true
    endscript
}
EOF

echo "==> Configurando unbound-control..."
unbound-control-setup

echo "==> Reiniciando unbound..."
systemctl restart unbound
systemctl enable unbound

echo "==> Instalando e configurando Zabbix Agent..."
bash <(curl -s https://raw.githubusercontent.com/0LB-i/menu/main/zabbix-agent.sh) || { echo "❌ Falha na instalação do Zabbix Agent."; exit 1; }

# Detectar qual agente foi instalado
if systemctl list-unit-files | grep -q "^zabbix-agent2.service"; then
    ZBX_AGENT="zabbix-agent2"
    ZBX_AGENT_CONF_DIR="/etc/zabbix/zabbix_agent2.d"
else
    ZBX_AGENT="zabbix-agent"
    ZBX_AGENT_CONF_DIR="/etc/zabbix/zabbix_agentd.d"
fi

echo "==> Criando userparameter para Unbound no Zabbix Agent..."
cat << 'EOF' > "${ZBX_AGENT_CONF_DIR}/userparameter_unbound.conf"
UserParameter=unbound.type[*],echo -n 0; sudo /usr/sbin/unbound-control stats_noreset | grep num.query.type.$1= | cut -d= -f2
UserParameter=unbound.mem[*],sudo /usr/sbin/unbound-control stats_noreset | grep mem.$1= | cut -d= -f2
UserParameter=unbound.flag[*],sudo /usr/sbin/unbound-control stats_noreset | grep num.query.$1= | cut -d= -f2
UserParameter=unbound.total[*],sudo /usr/sbin/unbound-control stats_noreset | grep total.num.$1= | cut -d= -f2
UserParameter=unbound.rcode[*],sudo /usr/sbin/unbound-control stats_noreset | grep num.answer.rcode.$1= | cut -d= -f2
UserParameter=unbound.class[*],sudo /usr/sbin/unbound-control stats_noreset | grep num.query.class.$1= | cut -d= -f2
UserParameter=unbound.time.up[*],sudo /usr/sbin/unbound-control stats_noreset | grep time.up | cut -d= -f2
UserParameter=unbound.histogram[*],sudo /usr/sbin/unbound-control stats_noreset | grep histogram.$1= | cut -d= -f2
UserParameter=unbound.histogram.total[*],sudo /usr/sbin/unbound-control stats_noreset | grep '^histogram\.' | cut -d= -f2 | awk '{s+=$1} END {print s+0}'
UserParameter=unbound.ips.abuso,grep ratelimit /var/log/unbound.log | grep -v for | grep -v through | sort -r | awk '{print "DATA: " $1, $2, "HORA: " $3, "Abuso de DNS do IP: " $8}'
EOF

cat << 'EOF' > /etc/sudoers.d/zabbix-unbound
Defaults:zabbix !requiretty
zabbix ALL = NOPASSWD: /usr/sbin/unbound-control
EOF
chmod 440 /etc/sudoers.d/zabbix-unbound

echo "==> Reiniciando Zabbix Agent..."
systemctl restart "$ZBX_AGENT"

echo "==> Verificando status do Unbound..."
systemctl status unbound --no-pager

echo "==> Consultando status via unbound-control..."
unbound-control status