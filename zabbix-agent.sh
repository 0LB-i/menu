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

# Buscar última subversão (patch) do Zabbix agent
get_latest_agent_version() {
    local base_version="$1"  # ex: 5.0
    local repo_url="https://repo.zabbix.com/zabbix/${base_version}/${REPO_BASE}/${OS_VER}/${ARCH}/"

    echo "🔍 Buscando a versão mais recente do agente para $base_version..."

    latest_agent_version=$(curl -s "$repo_url" | \
        grep -oP "${ZBX_AGENT}-${base_version}\.[0-9.]+-1\.el${OS_VER}\.${ARCH}\.rpm" | \
        sed -E "s/${ZBX_AGENT}-(${base_version}\.[0-9.]+)-1\.el${OS_VER}\.${ARCH}\.rpm/\1/" | \
        sort -V | tail -n1)

    if [[ -z "$latest_agent_version" ]]; then
        echo "❌ Não foi possível localizar a versão do agente."
        exit 1
    fi

    echo "📦 Versão do agente detectada: $latest_agent_version"
    ZBX_AGENT_VERSION_FULL="$latest_agent_version"
}

get_latest_agent_version "$ZBX_VERSION"

# Instalação para sistemas RHEL-based
install_rhel_agent() {
    local agent_pkg="${ZBX_AGENT}-${ZBX_AGENT_VERSION_FULL}-1.el${OS_VER}.${ARCH}.rpm"
    local url="https://repo.zabbix.com/zabbix/${ZBX_VERSION}/${REPO_BASE}/${OS_VER}/${ARCH}/${agent_pkg}"
    echo "⬇️ Baixando: $url"
    curl -LO "$url"
    rpm -Uvh "$agent_pkg"
}

# Instalação para sistemas Debian-based
install_debian_agent() {
    local agent_pkg="${ZBX_AGENT}_${ZBX_AGENT_VERSION_FULL}-1+${OS_ID}${OS_VER}_${ARCH}.deb"
    local url="https://repo.zabbix.com/zabbix/${ZBX_VERSION}/${OS_ID}/pool/main/z/zabbix/${agent_pkg}"
    echo "⬇️ Baixando: $url"
    wget -O "/tmp/${agent_pkg}" "$url"
    dpkg -i "/tmp/${agent_pkg}"
    apt-get install -f -y
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

if [[ "$ZBX_AGENT" == "zabbix-agent" ]]; then
    CONF_FILE="/etc/zabbix/zabbix_agentd.conf"
else
    CONF_FILE="/etc/zabbix/${ZBX_AGENT}.conf"
fi

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