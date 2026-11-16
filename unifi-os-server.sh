#!/bin/bash
# Instalação do UniFi OS Server (self-hosted, roda em container Podman)
# Baseado no unifi.sh (UniFi Network Server legado)

set -o pipefail

# Precisa ser root
if [[ $EUID -ne 0 ]]; then
  echo "ERRO: execute este script como root."
  exit 1
fi

# Detectar arquitetura (a Ubiquiti publica apenas x64 e arm64 para Linux)
case "$(uname -m)" in
  x86_64)  platform="linux-x64" ;;
  aarch64) platform="linux-arm64" ;;
  *)
    echo "ERRO: arquitetura $(uname -m) não suportada pelo UniFi OS Server."
    exit 1
    ;;
esac

# Detectar gerenciador de pacotes
if command -v dnf &> /dev/null; then
  PKG="dnf"
elif command -v yum &> /dev/null; then
  PKG="yum"
elif command -v apt-get &> /dev/null; then
  PKG="apt-get"
else
  echo "ERRO: nenhum gerenciador de pacotes suportado encontrado (dnf/yum/apt-get)."
  exit 1
fi

# Verificar espaço em disco (recomendado: 15 GB livres)
free_gb=$(df -BG --output=avail / | tail -1 | tr -dc '0-9')
if [[ "$free_gb" -lt 15 ]]; then
  echo "AVISO: apenas ${free_gb} GB livres em /. O recomendado são pelo menos 15 GB."
  read -p "Deseja continuar mesmo assim? (y/n): " cont
  [[ "$cont" =~ ^[Yy]$ ]] || exit 1
fi

# Aviso se o UniFi Network Server legado (unifi.sh) estiver rodando — conflita nas portas 8080/8443
if systemctl is-active --quiet unifi.service 2>/dev/null; then
  echo "AVISO: o serviço legado unifi.service (UniFi Network Server) está ativo e usa as mesmas portas."
  read -p "Deseja parar e desabilitar o unifi.service agora? (y/n): " stop_legacy
  if [[ "$stop_legacy" =~ ^[Yy]$ ]]; then
    systemctl disable --now unifi.service
  else
    echo "Continuando com o unifi.service ativo — a instalação pode falhar por conflito de portas."
  fi
fi

# Atualizar e instalar dependências
if [[ "$PKG" == "apt-get" ]]; then
  apt-get update -y
  apt-get install -y podman slirp4netns uidmap curl jq
else
  $PKG update -y
  $PKG install -y podman slirp4netns curl jq
fi

# Verificar versão mínima do Podman (4.3.1)
podman_ver=$(podman --version 2>/dev/null | awk '{print $3}')
if [[ -z "$podman_ver" ]]; then
  echo "ERRO: Podman não foi instalado corretamente."
  exit 1
fi
if [[ "$(printf '%s\n' "4.3.1" "$podman_ver" | sort -V | head -1)" != "4.3.1" ]]; then
  echo "ERRO: Podman ${podman_ver} encontrado, mas o UniFi OS Server exige 4.3.1 ou superior."
  exit 1
fi
echo "Podman ${podman_ver} OK."

# Buscar a versão mais recente na API de firmware da Ubiquiti
API="https://fw-update.ui.com/api"
FILTER="filter=eq~~product~~unifi-os-server&filter=eq~~platform~~${platform}"

default_version=$(curl -fsSL "${API}/firmware-latest?${FILTER}&filter=eq~~channel~~release" \
  | jq -r '._embedded.firmware[0].version // empty' | sed 's/^v//')

if [[ -z "$default_version" ]]; then
  echo "AVISO: não foi possível consultar a versão mais recente na API da Ubiquiti."
fi

# Perguntar a versão do UniFi OS Server, com valor padrão
read -p "Enter the version of UniFi OS Server you want to install [press Enter for ${default_version:-<none>}]: " uos_version
uos_version=${uos_version:-$default_version}
uos_version=${uos_version#v}

if [[ ! "$uos_version" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
  echo "ERRO: versão inválida '${uos_version}'. Use o formato X.Y.Z (ex.: 5.1.42)."
  exit 1
fi

IFS='.' read -r v_major v_minor v_patch <<< "$uos_version"

# Obter link de download e checksum da versão escolhida
fw_json=$(curl -fsSL "${API}/firmware?${FILTER}&filter=eq~~version_major~~${v_major}&filter=eq~~version_minor~~${v_minor}&filter=eq~~version_patch~~${v_patch}&limit=1")
download_url=$(echo "$fw_json" | jq -r '._embedded.firmware[0]._links.data.href // empty')
sha256=$(echo "$fw_json" | jq -r '._embedded.firmware[0].sha256_checksum // empty')

if [[ -z "$download_url" ]]; then
  echo "ERRO: versão ${uos_version} não encontrada para ${platform}."
  echo "Versões disponíveis:"
  curl -fsSL "${API}/firmware?${FILTER}&sort=-version&limit=10" | jq -r '._embedded.firmware[].version'
  exit 1
fi

# Baixar o instalador
installer="/opt/unifi-os-server-${uos_version}-${platform}"
echo "Baixando UniFi OS Server ${uos_version} (${platform})..."
cd /opt || exit 1
if ! curl -fL --progress-bar -o "$installer" "$download_url"; then
  echo "ERRO: falha no download de ${download_url}"
  rm -f "$installer"
  exit 1
fi

# Verificar integridade
if [[ -n "$sha256" ]]; then
  echo "Verificando SHA-256..."
  if ! echo "${sha256}  ${installer}" | sha256sum -c -; then
    echo "ERRO: checksum não confere. Arquivo removido."
    rm -f "$installer"
    exit 1
  fi
fi

chmod +x "$installer"

# Liberar portas no firewalld (se estiver ativo)
if systemctl is-active --quiet firewalld 2>/dev/null; then
  echo "Liberando portas do UniFi OS Server no firewalld..."
  for p in 11443/tcp 8080/tcp 8443/tcp 8444/tcp 8880-8882/tcp 6789/tcp \
           3478/udp 5514/udp 10001/udp 10003/udp; do
    firewall-cmd --permanent --add-port="$p" > /dev/null
  done
  firewall-cmd --reload
fi

# Executar o instalador (ele pede confirmação: "Proceed? (y/N)")
echo "Iniciando o instalador (pode levar alguns minutos)..."
"$installer"
install_rc=$?

# Limpar o instalador
rm -f "$installer"

if [[ $install_rc -ne 0 ]]; then
  echo "ERRO: o instalador terminou com código ${install_rc}."
  exit $install_rc
fi

ip_addr=$(hostname -I 2>/dev/null | awk '{print $1}')
echo
echo "UniFi OS Server ${uos_version} instalado."
echo "Acesse: https://${ip_addr:-<IP-do-servidor>}:11443"
echo "Gerenciamento: comando 'uosserver' (ex.: uosserver status | start | stop)"

# Reboot para garantir que o sistema esteja pronto
read -p "Installation is complete. Would you like to restart your system now? (y/n): " reboot_choice
if [[ "$reboot_choice" =~ ^[Yy]$ ]]; then
  reboot
else
  echo "Installation complete. You can manually restart the system later."
fi
