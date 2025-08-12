#!/bin/bash

prompt_input() {
    local var_name=$1 prompt_text=$2 default_value=$3
    read -p "$prompt_text [$default_value]: " input
    export "$var_name"="${input:-$default_value}"
}

echo "===== ZABBIX AGENT INSTALLER ====="

prompt_input ZBX_VERSION "Informe a versão do Zabbix" "7.0"

echo "Qual agente deseja instalar?"
select ZBX_AGENT in "zabbix-agent2" "zabbix-agent"; do
    [[ -n "$ZBX_AGENT" ]] && break
done

prompt_input ZBX_SERVER "Informe o IP do Zabbix Server" "127.0.0.1"
prompt_input ZBX_PROXY "Informe o IP do Zabbix Proxy (ou deixe vazio)" ""
prompt_input ZBX_HOSTNAME "Informe o Hostname do agente" "$(hostname)"

# Detectar sistema e arquitetura
if [[ -f /etc/os-release ]]; then
    source /etc/os-release
    OS_ID=$ID
    OS_VER=${VERSION_ID%%.*}
    ARCH=$(dpkg --print-architecture 2>/dev/null || uname -m)
else
    echo "❌ Não foi possível detectar a distribuição."
    exit 1
fi

# Detectar gerenciador de pacotes para RHEL based
if command -v dnf &>/dev/null; then
  PKG_MGR=dnf
else
  PKG_MGR=yum
fi

declare -A ZBX_REPO_RPMS=(
  ["7.4"]="https://repo.zabbix.com/zabbix/7.4/release/rhel/{OS_VER}/noarch/zabbix-release-latest-7.4.el{OS_VER}.noarch.rpm"
  ["7.0"]="https://repo.zabbix.com/zabbix/7.0/rhel/{OS_VER}/x86_64/zabbix-release-latest-7.0.el{OS_VER}.noarch.rpm"
  ["6.4"]="https://repo.zabbix.com/zabbix/6.4/rhel/{OS_VER}/x86_64/zabbix-release-latest-6.4.el{OS_VER}.noarch.rpm"
  ["6.0"]="https://repo.zabbix.com/zabbix/6.0/rhel/{OS_VER}/x86_64/zabbix-release-latest-6.0.el{OS_VER}.noarch.rpm"
  ["4.4"]="https://repo.zabbix.com/zabbix/4.4/rhel/{OS_VER}/x86_64/zabbix-release-4.4-1.el{OS_VER}.noarch.rpm"
)

install_rhel_repo() {
  local url_template="${ZBX_REPO_RPMS[$ZBX_VERSION]}"
  if [[ -z "$url_template" ]]; then
    echo "❌ Versão $ZBX_VERSION não encontrada na lista."
    exit 1
  fi
  local url="${url_template//\{OS_VER\}/$OS_VER}"
  echo "Instalando repositório Zabbix para RHEL com link fixo..."
  rpm -Uvh "$url"
  $PKG_MGR clean all
  $PKG_MGR install -y "$ZBX_AGENT"
}

install_debian_repo() {
    echo "Adicionando repositório Zabbix para Debian-based..."
    wget "https://repo.zabbix.com/zabbix/${ZBX_VERSION}/${OS_ID}/pool/main/z/zabbix/zabbix-release_${ZBX_VERSION}-1+${OS_ID}${OS_VER}_all.deb" -O /tmp/zabbix-release.deb
    dpkg -i /tmp/zabbix-release.deb
    apt-get update
    apt-get install -y $ZBX_AGENT
}

case "$OS_ID" in
    rhel|centos|rocky|almalinux|fedora)
        install_rhel_repo
        ;;
    debian|ubuntu)
        install_debian_repo
        ;;
    *)
        echo "❌ Sistema $OS_ID não suportado."
        exit 1
        ;;
esac

# Definir arquivo de configuração
if [[ "$ZBX_AGENT" == "zabbix-agent" ]]; then
    CONF_FILE="/etc/zabbix/zabbix_agentd.conf"
else
    CONF_FILE="/etc/zabbix/${ZBX_AGENT}.conf"
fi

# Atualizar configuração
if [[ -f "$CONF_FILE" ]]; then
    sed -i "s|^Server=.*|Server=${ZBX_SERVER}|" "$CONF_FILE"
    sed -i "s|^ServerActive=.*|ServerActive=${ZBX_PROXY:-$ZBX_SERVER}|" "$CONF_FILE"
    sed -i "s|^Hostname=.*|Hostname=${ZBX_HOSTNAME}|" "$CONF_FILE"
else
    echo "❌ Arquivo de configuração não encontrado: $CONF_FILE"
    exit 1
fi

# Ativar e iniciar serviço
systemctl enable "$ZBX_AGENT"
systemctl restart "$ZBX_AGENT"

echo -e "\n✅ Instalação concluída!"
echo "Servidor: $ZBX_SERVER"
echo "Proxy: ${ZBX_PROXY:-<não usado>}"
echo "Hostname: $ZBX_HOSTNAME"