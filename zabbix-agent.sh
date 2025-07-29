#!/bin/bash

# Função para perguntar com valor padrão
prompt_input() {
    local var_name=$1
    local prompt_text=$2
    local default_value=$3
    read -p "$prompt_text [$default_value]: " input
    export $var_name="${input:-$default_value}"
}

echo "===== ZABBIX AGENT INSTALLER ====="
prompt_input ZBX_VERSION "Informe a versão do Zabbix" "7.0"

echo "Qual agente deseja instalar?"
select ZBX_AGENT in "zabbix-agent2" "zabbix-agent"; do
    [[ -n "$ZBX_AGENT" ]] && break
done

prompt_input ZBX_SERVER "Informe o IP do Zabbix Server:" "127.0.0.1"
prompt_input ZBX_PROXY "Informe o IP do Zabbix Proxy (ou deixe em branco se não usar proxy):" ""
prompt_input ZBX_HOSTNAME "Informe o Hostname do agente:" "$(hostname)"

# Detectar OS
if [ -f /etc/os-release ]; then
    source /etc/os-release
    OS_ID=$ID
    OS_VER=${VERSION_ID%%.*}
    ARCH=$(dpkg --print-architecture 2>/dev/null || uname -m)
else
    echo "❌ Não foi possível detectar a distribuição."
    exit 1
fi

# Forçar uso do repositório RHEL para Rocky, AlmaLinux e CentOS
if [[ "$OS_ID" =~ ^(rocky|almalinux|centos)$ ]]; then
    REPO_BASE="rhel"
else
    REPO_BASE="$OS_ID"
fi

# Instalação para sistemas RHEL-based
install_rhel_agent() {
    rpm -Uvh "https://repo.zabbix.com/zabbix/${ZBX_VERSION}/${REPO_BASE}/${OS_VER}/${ARCH}/zabbix-release-${ZBX_VERSION}-1.el${OS_VER}.noarch.rpm"
    dnf clean all
    dnf install -y "$ZBX_AGENT"
}

# Instalação para sistemas Debian-based
install_debian_agent() {
    wget "https://repo.zabbix.com/zabbix/${ZBX_VERSION}/${OS_ID}/pool/main/z/zabbix-release/zabbix-release_${ZBX_VERSION}-1+${OS_ID}${OS_VER}_all.deb" -O /tmp/zabbix-release.deb
    dpkg -i /tmp/zabbix-release.deb
    apt update
    apt install -y "$ZBX_AGENT"
}

# Executar instalação de acordo com o sistema
if [[ "$OS_ID" =~ ^(rhel|centos|rocky|almalinux|fedora)$ ]]; then
    install_rhel_agent
elif [[ "$OS_ID" =~ ^(debian|ubuntu)$ ]]; then
    install_debian_agent
else
    echo "❌ Sistema $OS_ID não suportado."
    exit 1
fi

CONF_FILE="/etc/zabbix/${ZBX_AGENT}.conf"

# Editar config
sed -i "s|^Server=.*|Server=${ZBX_SERVER}|" "$CONF_FILE"
sed -i "s|^ServerActive=.*|ServerActive=${ZBX_PROXY:-$ZBX_SERVER}|" "$CONF_FILE"
sed -i "s|^Hostname=.*|Hostname=${ZBX_HOSTNAME}|" "$CONF_FILE"

systemctl enable "$ZBX_AGENT"
systemctl restart "$ZBX_AGENT"

echo -e "\n✅ Instalação concluída!"
echo "Servidor: $ZBX_SERVER"
echo "Proxy: ${ZBX_PROXY:-<não usado>}"
echo "Hostname: $ZBX_HOSTNAME"