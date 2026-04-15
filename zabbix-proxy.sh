#!/bin/bash
# ─────────────────────────────────────────────────────────────
# Script para instalar o Zabbix Proxy com SQLite3
# Compatível com AlmaLinux 9 e Rocky Linux 9
# Versões suportadas: 6.0, 6.4, 7.0, 7.4
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
echo ""
echo "Versões disponíveis: 6.0 | 6.4 | 7.0 | 7.4"
read -p "Digite a versão do Zabbix Proxy que deseja instalar [padrão: 7.0]: " ZBX_VERSION
ZBX_VERSION=${ZBX_VERSION:-7.0}

if [[ "$ZBX_VERSION" != "6.0" && "$ZBX_VERSION" != "6.4" && "$ZBX_VERSION" != "7.0" && "$ZBX_VERSION" != "7.4" ]]; then
  echo "❌ Versão inválida: $ZBX_VERSION. Use uma das versões suportadas: 6.0, 6.4, 7.0, 7.4"
  exit 1
fi

# ▶ Solicita IP do servidor Zabbix
echo ""
read -p "Digite o IP do servidor Zabbix (Server=): " ZBX_SERVER_IP
if [[ -z "$ZBX_SERVER_IP" ]]; then
  echo "❌ O IP do servidor Zabbix é obrigatório."
  exit 1
fi

# ▶ Solicita nome único do proxy
read -p "Digite o nome único deste proxy (Hostname=): " ZBX_PROXY_NAME
if [[ -z "$ZBX_PROXY_NAME" ]]; then
  echo "❌ O nome do proxy é obrigatório."
  exit 1
fi

# ▶ Instala utilitários básicos
echo ""
echo "➤ Instalando utilitários básicos..."
dnf install -y net-snmp net-snmp-utils glibc-langpack-pt

# ▶ Adiciona repositório Zabbix de acordo com a distro detectada
REPO_URL="https://repo.zabbix.com/zabbix/$ZBX_VERSION/release/$OS_ID/9/noarch/zabbix-release-latest-$ZBX_VERSION.el9.noarch.rpm"
echo "➤ Adicionando repositório Zabbix versão $ZBX_VERSION para $OS_ID..."
rpm -Uvh "$REPO_URL" || {
  echo "❌ Erro ao adicionar o repositório. Verifique se a versão está correta."
  exit 1
}

echo "➤ Limpando cache do DNF..."
dnf clean all

# ▶ Cria diretório de dados do proxy
echo "➤ Criando diretório /var/lib/zabbix..."
mkdir -p /var/lib/zabbix

# ▶ Instala pacotes do Zabbix Proxy com SQLite3
echo "➤ Instalando pacotes do Zabbix Proxy..."
dnf install -y \
  sqlite \
  sqlite-devel \
  gcc \
  make \
  libcurl-devel \
  libevent-devel \
  zabbix-sql-scripts \
  zabbix-proxy-sqlite3 \
  zabbix-selinux-policy || {
  echo "❌ Erro ao instalar pacotes do Zabbix Proxy."
  exit 1
}

# ▶ Localiza o arquivo SQL do proxy (caminho varia por versão)
PROXY_SQL=$(find /usr/share -name "proxy.sql" 2>/dev/null | head -1)
if [[ -z "$PROXY_SQL" ]]; then
  echo "❌ Arquivo proxy.sql não encontrado. Verifique a instalação do zabbix-sql-scripts."
  exit 1
fi
echo "➤ Arquivo SQL encontrado: $PROXY_SQL"

# ▶ Importa schema do banco SQLite3
echo "➤ Importando schema para o banco SQLite3..."
sqlite3 /var/lib/zabbix/zabbix_proxy.db < "$PROXY_SQL" || {
  echo "❌ Erro ao importar schema para o banco SQLite3."
  exit 1
}

# ▶ Ajusta permissões do diretório
echo "➤ Ajustando permissões do diretório /var/lib/zabbix..."
chown -R zabbix:zabbix /var/lib/zabbix/
chmod 750 /var/lib/zabbix/

# ▶ Configura o zabbix_proxy.conf
ZBX_CONF="/etc/zabbix/zabbix_proxy.conf"
echo "➤ Configurando $ZBX_CONF..."

sed -i "s/^Server=.*/Server=$ZBX_SERVER_IP/" "$ZBX_CONF"
sed -i "s/^Hostname=.*/Hostname=$ZBX_PROXY_NAME/" "$ZBX_CONF"
sed -i "s|^DBName=.*|DBName=/var/lib/zabbix/zabbix_proxy.db|" "$ZBX_CONF"

# ▶ Tuning de performance do proxy
echo "➤ Ajustando parâmetros de performance do Zabbix Proxy..."
sed -i "/^#\?StartPollers=/c\StartPollers=10"                   "$ZBX_CONF"
sed -i "/^#\?StartPollersUnreachable=/c\StartPollersUnreachable=10" "$ZBX_CONF"
sed -i "/^#\?StartPingers=/c\StartPingers=5"                    "$ZBX_CONF"
sed -i "/^#\?StartSNMPTrapper=/c\StartSNMPTrapper=5"            "$ZBX_CONF"
sed -i "/^#\?StartTrappers=/c\StartTrappers=5"                  "$ZBX_CONF"
sed -i "/^#\?CacheSize=/c\CacheSize=512M"                       "$ZBX_CONF"
sed -i "/^#\?HistoryCacheSize=/c\HistoryCacheSize=128M"         "$ZBX_CONF"
sed -i "/^#\?HistoryIndexCacheSize=/c\HistoryIndexCacheSize=32M" "$ZBX_CONF"
sed -i "/^#\?Timeout=/c\Timeout=30"                             "$ZBX_CONF"

# ▶ Habilita e inicia o serviço
echo "➤ Habilitando e iniciando o serviço zabbix-proxy..."
systemctl enable zabbix-proxy
systemctl restart zabbix-proxy

# ▶ Verifica status do serviço
if systemctl is-active --quiet zabbix-proxy; then
  echo ""
  echo "✅ Zabbix Proxy $ZBX_VERSION instalado e em execução!"
  echo "   Server  : $ZBX_SERVER_IP"
  echo "   Hostname: $ZBX_PROXY_NAME"
  echo "   Banco   : /var/lib/zabbix/zabbix_proxy.db"
else
  echo ""
  echo "⚠️  O serviço zabbix-proxy não iniciou corretamente."
  echo "   Verifique os logs com: journalctl -u zabbix-proxy -n 50"
  echo "   Se necessário, reinicie a VM e execute:"
  echo "   systemctl enable zabbix-proxy && systemctl restart zabbix-proxy && systemctl status zabbix-proxy"
fi
