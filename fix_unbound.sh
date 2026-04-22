#!/bin/bash
set -e

CONF="/etc/unbound/unbound.conf"

echo "==> Calculando parâmetros do sistema..."
THREADS=$(nproc)
SLABS=1
while [[ $SLABS -lt $THREADS ]]; do SLABS=$((SLABS * 2)); done

MEM_MB=$(awk '/MemTotal/ {print int($2/1024)}' /proc/meminfo)
MSG_CACHE_MB=$((MEM_MB / 4))
RRSET_CACHE_MB=$((MSG_CACHE_MB * 2))
KEY_CACHE_MB=$((MEM_MB / 16))
SO_BUF_MB=$((MEM_MB / 256))
NETDEV_BACKLOG=$((THREADS * 1024))
UDP_MEM_PRESSURE=$((MEM_MB * 1024 / 4 / 4))
UDP_MEM_LIMIT=$((MEM_MB * 1024 / 4 / 2))
UDP_MEM_MAX=$((MEM_MB * 1024 / 4))
FILE_MAX=$((THREADS * 16384 * 4))

echo "  Threads: $THREADS | Slabs: $SLABS | RAM: ${MEM_MB}MB"
echo "  msg-cache: ${MSG_CACHE_MB}m | rrset-cache: ${RRSET_CACHE_MB}m | key-cache: ${KEY_CACHE_MB}m"
echo "  so-rcvbuf/so-sndbuf: ${SO_BUF_MB}m | netdev_backlog: $NETDEV_BACKLOG | file-max: $FILE_MAX"
echo "  udp_mem: $UDP_MEM_PRESSURE $UDP_MEM_LIMIT $UDP_MEM_MAX"

echo "==> Ajustando parâmetros do kernel..."
sysctl_set() {
  local key=$1 val=$2
  sysctl -w "${key}=${val}"
  grep -q "^${key}" /etc/sysctl.conf \
    && sed -i "s|^${key}=.*|${key}=${val}|" /etc/sysctl.conf \
    || echo "${key}=${val}" >> /etc/sysctl.conf
}

sysctl_set net.core.rmem_max         $((SO_BUF_MB * 1024 * 1024))
sysctl_set net.core.wmem_max         $((SO_BUF_MB * 1024 * 1024))
sysctl_set net.core.netdev_max_backlog $NETDEV_BACKLOG
sysctl_set net.ipv4.udp_mem          "$UDP_MEM_PRESSURE $UDP_MEM_LIMIT $UDP_MEM_MAX"
sysctl_set net.ipv4.ip_local_port_range "1024 65535"
sysctl_set vm.swappiness             10
sysctl_set fs.file-max               $FILE_MAX

echo "==> Fazendo backup de $CONF..."
cp "$CONF" "${CONF}.bak.$(date +%Y%m%d_%H%M%S)"

echo "==> Ajustando unbound.conf..."
sed -i \
  -e "s/^\([[:space:]]*\)[[:space:]#]*num-threads:.*/\1num-threads: ${THREADS}/" \
  -e "s/^\([[:space:]]*\)[[:space:]#]*msg-cache-slabs:.*/\1msg-cache-slabs: ${SLABS}/" \
  -e "s/^\([[:space:]]*\)[[:space:]#]*rrset-cache-slabs:.*/\1rrset-cache-slabs: ${SLABS}/" \
  -e "s/^\([[:space:]]*\)[[:space:]#]*infra-cache-slabs:.*/\1infra-cache-slabs: ${SLABS}/" \
  -e "s/^\([[:space:]]*\)[[:space:]#]*key-cache-slabs:.*/\1key-cache-slabs: ${SLABS}/" \
  -e "s/^\([[:space:]]*\)[[:space:]#]*rrset-cache-size:.*/\1rrset-cache-size: ${RRSET_CACHE_MB}m/" \
  -e "s/^\([[:space:]]*\)[[:space:]#]*msg-cache-size:.*/\1msg-cache-size: ${MSG_CACHE_MB}m/" \
  -e "s/^\([[:space:]]*\)[[:space:]#]*key-cache-size:.*/\1key-cache-size: ${KEY_CACHE_MB}m/" \
  -e "s/^\([[:space:]]*\)[[:space:]#]*so-rcvbuf:.*/\1so-rcvbuf: ${SO_BUF_MB}m/" \
  -e "s/^\([[:space:]]*\)[[:space:]#]*so-sndbuf:.*/\1so-sndbuf: ${SO_BUF_MB}m/" \
  -e 's/\([[:space:]]*\)# interface: 0.0.0.0$/\1interface: 0.0.0.0/' \
  -e 's/\([[:space:]]*\)# interface: ::0$/\1interface: ::0/' \
  -e 's/\([[:space:]]*\)# interface: 192\.0\.2\.153$/\1interface: 0.0.0.0@853/' \
  -e 's/\([[:space:]]*\)# interface: 192\.0\.2\.154$/\1interface: ::0@853/' \
  -e 's|\([[:space:]]*\)# tls-service-key:.*|\1tls-service-key: "/etc/unbound/unbound_server.key"|' \
  -e 's|\([[:space:]]*\)# tls-service-pem:.*|\1tls-service-pem: "/etc/unbound/unbound_server.pem"|' \
  -e 's/^\([[:space:]]*\)[[:space:]#]*tls-port:.*/\1tls-port: 853/' \
  -e 's/\([[:space:]]*\)interface-automatic: no/\1interface-automatic: yes/' \
  -e 's/^\([[:space:]]*\)[[:space:]#]*outgoing-range:.*/\1outgoing-range: 65535/' \
  -e 's/^\([[:space:]]*\)[[:space:]#]*num-queries-per-thread:.*/\1num-queries-per-thread: 16384/' \
  -e 's/^\([[:space:]]*\)[[:space:]#]*cache-max-ttl:.*/\1cache-max-ttl: 14400/' \
  -e 's/^\([[:space:]]*\)[[:space:]#]*cache-min-ttl:.*/\1cache-min-ttl: 60/' \
  -e 's/^\([[:space:]]*\)[[:space:]#]*ip-ratelimit:.*/\1ip-ratelimit: 300/' \
  -e 's/^\([[:space:]]*\)[[:space:]#]*ip-ratelimit-factor:.*/\1ip-ratelimit-factor: 0/' \
  -e 's|^\([[:space:]]*\)[[:space:]#]*root-hints:.*|\1root-hints: "/var/lib/unbound/root.hints"|' \
  -e 's|^\([[:space:]]*\)[[:space:]#]*logfile:.*|\1logfile: "/var/log/unbound.log"|' \
  -e '/^[[:space:]]*prefetch:[[:space:]]*yes$/!s/^\([[:space:]]*\)[[:space:]#]*prefetch:.*/\1prefetch: yes/' \
  -e '/^[[:space:]]*prefetch-key:[[:space:]]*yes$/!s/^\([[:space:]]*\)[[:space:]#]*prefetch-key:.*/\1prefetch-key: yes/' \
  -e '/^[[:space:]]*serve-expired:[[:space:]]*yes$/!s/^\([[:space:]]*\)[[:space:]#]*serve-expired:.*/\1serve-expired: yes/' \
  -e '/^[[:space:]]*serve-expired-ttl:[[:space:]]*[^0]/!s/^\([[:space:]]*\)[[:space:]#]*serve-expired-ttl:.*/\1serve-expired-ttl: 3600/' \
  -e '/^[[:space:]]*hide-identity:[[:space:]]*yes$/!s/^\([[:space:]]*\)[[:space:]#]*hide-identity:.*/\1hide-identity: yes/' \
  -e '/^[[:space:]]*hide-version:[[:space:]]*yes$/!s/^\([[:space:]]*\)[[:space:]#]*hide-version:.*/\1hide-version: yes/' \
  -e '/^[[:space:]]*use-caps-for-id:[[:space:]]*yes$/!s/^\([[:space:]]*\)[[:space:]#]*use-caps-for-id:.*/\1use-caps-for-id: yes/' \
  -e 's/^\([[:space:]]*\)[[:space:]#]*edns-buffer-size:.*/\1edns-buffer-size: 1232/' \
  -e '/^[[:space:]]*aggressive-nsec:[[:space:]]*yes$/!s/^\([[:space:]]*\)[[:space:]#]*aggressive-nsec:.*/\1aggressive-nsec: yes/' \
  -e 's/^\([[:space:]]*\)[[:space:]#]*infra-cache-numhosts:.*/\1infra-cache-numhosts: 100000/' \
  "$CONF"

echo "==> Verificando configuração..."
if unbound-checkconf "$CONF"; then
  echo "==> Configuração válida. Reiniciando unbound..."
  systemctl restart unbound
  echo "==> Concluído!"
else
  echo "ERRO: configuração inválida. Restaurando backup..."
  cp "${CONF}.bak.$(date +%Y%m%d)_"* "$CONF" 2>/dev/null || true
  exit 1
fi
