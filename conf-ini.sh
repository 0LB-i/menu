#!/bin/bash

# === FUNÇÕES ===
perguntar_hostname() {
    echo -n "Digite o novo hostname (ou pressione Enter para manter o atual): "
    read NOVO_HOSTNAME

    if [[ -n "$NOVO_HOSTNAME" ]]; then
        echo "[+] Definindo hostname para: $NOVO_HOSTNAME"
        hostnamectl set-hostname "$NOVO_HOSTNAME"
    else
        echo "[*] Hostname não alterado."
    fi
}

instalar_pacotes() {
    echo "[+] Instalando pacotes essenciais: vim wget ntsysv open-vm-tools net-tools"
    yum install -y vim wget ntsysv open-vm-tools net-tools
}

desativar_selinux() {
    echo "[+] Desativando SELinux (permanente)"
    sed -i 's/^SELINUX=enforcing/SELINUX=disabled/g' /etc/selinux/config
}

desabilitar_firewalld() {
    echo "[+] Parando e desabilitando firewalld"
    systemctl stop firewalld
    systemctl disable firewalld
    systemctl status firewalld --no-pager
}

atualizar_sistema() {
    echo "[+] Atualizando sistema com YUM"
    yum update -y
}

# === EXECUÇÃO ===
echo "====== INÍCIO DA CONFIGURAÇÃO INICIAL ======"
perguntar_hostname
instalar_pacotes
desativar_selinux
desabilitar_firewalld
atualizar_sistema
echo "====== CONFIGURAÇÃO INICIAL FINALIZADA ======"

echo "Reinicie o sistema para aplicar todas as mudanças (especialmente o SELinux)."