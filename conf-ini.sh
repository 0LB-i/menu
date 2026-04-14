#!/bin/bash

# Verificar root
[[ $EUID -ne 0 ]] && echo "❌ Execute como root." && exit 1

# Detectar distro
if [[ -f /etc/os-release ]]; then
    source /etc/os-release
    OS_ID=$ID
    OS_VER=${VERSION_ID%%.*}
else
    echo "❌ Não foi possível detectar a distribuição."
    exit 1
fi

# Validar distros suportadas
case "$OS_ID" in
    centos)
        if [[ "$OS_VER" != "7" ]]; then
            echo "❌ CentOS $VERSION_ID não suportado. Use CentOS 7."
            exit 1
        fi
        ;;
    almalinux|rocky)
        if [[ "$OS_VER" -lt 9 ]]; then
            echo "❌ $NAME $VERSION_ID não suportado. Use versão 9 ou superior."
            exit 1
        fi
        ;;
    *)
        echo "❌ Distro não suportada: $OS_ID. Use CentOS 7, AlmaLinux ou Rocky Linux 9/10."
        exit 1
        ;;
esac

# === FUNÇÕES ===
perguntar_hostname() {
    echo -n "Digite o novo hostname (ou pressione Enter para manter o atual): "
    read NOVO_HOSTNAME

    if [[ -n "$NOVO_HOSTNAME" ]]; then
        echo "➤ Definindo hostname para: $NOVO_HOSTNAME"
        hostnamectl set-hostname "$NOVO_HOSTNAME"
    else
        echo "[*] Hostname não alterado."
    fi
}

instalar_pacotes() {
    echo "➤ Instalando pacotes essenciais: vim wget ntsysv open-vm-tools net-tools bind-utils"
    yum install -y vim wget ntsysv open-vm-tools net-tools bind-utils
}

desativar_selinux() {
    echo "➤ Desativando SELinux (permanente)"
    sed -i 's/^SELINUX=.*/SELINUX=disabled/' /etc/selinux/config
    setenforce 0 2>/dev/null || true
}

desabilitar_firewalld() {
    echo "➤ Parando e desabilitando firewalld"
    systemctl stop firewalld
    systemctl disable firewalld
    systemctl status firewalld --no-pager
}

atualizar_sistema() {
    echo "➤ Atualizando sistema com YUM"
    yum update -y
}

# === EXECUÇÃO ===
echo "➤ INÍCIO DA CONFIGURAÇÃO INICIAL ($NAME $VERSION_ID)"
perguntar_hostname
instalar_pacotes
desativar_selinux
desabilitar_firewalld
atualizar_sistema
echo "➤ CONFIGURAÇÃO INICIAL FINALIZADA"

echo "➤ Reinicie o sistema para aplicar todas as mudanças (especialmente o SELinux)."
