#!/bin/bash
set -e

echo "==> Instalahttps://www.empregos.com.br/vaga/10817321/desenvolvedor-de-software-trainee-em-lajeado-rs-CK10817321IN?Origem=L554&bb_click_id=e948d1d3ndo pacotes..."
yum install -y unbound logrotate curl

echo "==> Ajustando unbound.conf..."
sed -i -e 's/num-threads: 4/num-threads: 8/' \
       -e 's/# msg-cache-slabs: 4/msg-cache-slabs: 8/' \
       -e 's/# rrset-cache-slabs: 4/rrset-cache-slabs: 8/' \
       -e 's/# infra-cache-slabs: 4/infra-cache-slabs: 8/' \
       -e 's/# key-cache-slabs: 4/key-cache-slabs: 8/' \
       -e 's/# rrset-cache-size: 4m/rrset-cache-size: 512m/' \
       -e 's/# msg-cache-size: 4m/msg-cache-size: 512m/' \
       -e 's/# key-cache-size: 4m/key-cache-size: 64m/' \
       -e 's/# so-rcvbuf: 0/so-rcvbuf: 4m/' \
       -e 's/# so-sndbuf: 0/so-sndbuf: 4m/' \
       -e 's/# interface: 0.0.0.0$/interface: 0.0.0.0/' \
       -e 's/# interface: ::0$/interface: ::0/' \
       -e 's/interface-automatic: no/interface-automatic: yes/' \
       -e 's/# outgoing-range: 4096/outgoing-range: 8192/' \
       -e 's/# num-queries-per-thread: 1024/num-queries-per-thread: 4096/' \
       -e 's/# cache-max-ttl: 86400/cache-max-ttl: 14400/' \
       -e 's/# cache-min-ttl: 0/cache-min-ttl: 300/' \
       -e 's/# ip-ratelimit: 0/ip-ratelimit: 500/' \
       -e 's/# ip-ratelimit-factor: 10/ip-ratelimit-factor: 1/' \
       -e 's|# root-hints: ""|root-hints: "/var/lib/unbound/root.hints"|' \
       -e 's|# logfile: ""|logfile: "/var/log/unbound.log"|' \
       -e 's/# hide-identity: no/hide-identity: yes/' \
       -e 's/# hide-version: no/hide-version: yes/' \
       /etc/unbound/unbound.conf

echo "==> Adicionando access-control..."

insert_access_controls() {
    local conf_file="/etc/unbound/unbound.conf"
    local ips=("$@")

    for ip in "${ips[@]}"; do
        # Verifica se o IP já está configurado
        if grep -q "^\s*access-control: ${ip} allow" "$conf_file"; then
            echo "IP ${ip} já existe no arquivo, pulando..."
        else
            # Insere abaixo do primeiro "# access-control:"
            sed -i "/# access-control:/a\\
        access-control: ${ip} allow" "$conf_file"
            echo "IP ${ip} adicionado ao arquivo."
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

echo "==> Configurando unbound-control..."
unbound-control-setup

echo "==> Reiniciando unbound..."
systemctl restart unbound
systemctl enable unbound

echo "==> Instalando e configurando Zabbix Agent..."
bash <(curl -s https://raw.githubusercontent.com/0LB-i/menu/main/zabbix-agent.sh)

echo "==> Criando userparameter para Unbound no Zabbix Agent..."
cat << 'EOF' > /etc/zabbix/zabbix_agentd.d/userparameter_unbound.conf
UserParameter=unbound.type[*],echo -n 0; sudo /usr/sbin/unbound-control stats_noreset | grep num.query.type.$1= | cut -d= -f2
UserParameter=unbound.mem[*],sudo /usr/sbin/unbound-control stats_noreset | grep mem.$1= | cut -d= -f2
UserParameter=unbound.flag[*],sudo /usr/sbin/unbound-control stats_noreset | grep num.query.$1= | cut -d= -f2
UserParameter=unbound.total[*],sudo /usr/sbin/unbound-control stats_noreset | grep total.num.$1= | cut -d= -f2
UserParameter=unbound.rcode[*],sudo /usr/sbin/unbound-control stats_noreset | grep num.answer.rcode.$1= | cut -d= -f2
UserParameter=unbound.class[*],sudo /usr/sbin/unbound-control stats_noreset | grep num.query.class.$1= | cut -d= -f2
UserParameter=unbound.time.up[*],sudo /usr/sbin/unbound-control stats_noreset | grep time.up | cut -d= -f2
UserParameter=unbound.histogram[*],sudo /usr/sbin/unbound-control stats_noreset | grep histogram.$1= | cut -d= -f2
UserParameter=unbound.histogram.total[*],sudo /usr/sbin/unbound-control stats_noreset | grep histogram.$1= | cut -d= -f2
UserParameter=unbound.ips.abuso,cat /var/log/unbound.log | grep ratelimit | grep -v for | grep -v through | sort -r | awk '{print "DATA: " $1, $2, "HORA: " $3, "Abuso de DNS do IP: " $8}'
EOF

cat << 'EOF' >> /etc/sudoers
Defaults:zabbix !requiretty
zabbix ALL = NOPASSWD: /usr/sbin/unbound-control
EOF

echo "==> Reiniciando Zabbix Agent..."
systemctl restart zabbix-agent

echo "==> Verificando status do Unbound..."
systemctl status unbound --no-pager

echo "==> Consultando status via unbound-control..."
unbound-control status