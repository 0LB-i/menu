#!/bin/bash

check_whiptail() {
    if ! command -v whiptail &> /dev/null; then
        echo "➤ whiptail não encontrado. Instalando..."
        dnf install -y newt || {
            echo "Erro ao instalar whiptail (newt). Saindo."
            exit 1
        }
    fi
}

menu_scripts() {
    while true; do
        OPCAO=$(whiptail --title "Menu de Scripts - Gabriel (0LB-i)" --menu "Escolha um script para executar:" 20 60 15 \
            "0" "Sair" \
            "1" "Conf inicial" \
            "2" "Corrigir repositórios CentOS 7" \
            "3" "Instalar Zabbix agent" \
            "4" "Instalar Unifi controller" \
            "5" "Instalar Zabbix Server" \
            "6" "Instalar Speedtest" \
            "7" "Instalar Bacula-fd em distros Rhel 9" \
            "8" "Instalar Unbound" \
            "9" "Configuração do rc.local Ubuntu" \
            "10" "Configuração de Dump do Zabbix" \
            3>&1 1>&2 2>&3)
        RET=$?

        if [ $RET -ne 0 ]; then
            echo "➤ Cancelado pelo usuário."
            exit 0
        fi

        case "$OPCAO" in
            0)
                echo "Saindo..."
                exit 0
                ;;
            1)
                bash <(curl -s https://raw.githubusercontent.com/0LB-i/menu/main/conf-ini.sh)
                ;;
            2)
                bash <(curl -s https://raw.githubusercontent.com/0LB-i/menu/main/fix-centos-repos.sh)
                ;;
            3)
                bash <(curl -s https://raw.githubusercontent.com/0LB-i/menu/main/zabbix-agent.sh)
                ;;
            4)
                bash <(curl -s https://raw.githubusercontent.com/0LB-i/menu/main/unifi.sh)
                ;;
            5)
                bash <(curl -s https://raw.githubusercontent.com/0LB-i/menu/main/zabbix-server.sh)
                ;;
            6)
                bash <(curl -s https://raw.githubusercontent.com/0LB-i/menu/main/speedtest.sh)
                ;;
            7)
                bash <(curl -s https://raw.githubusercontent.com/0LB-i/menu/main/bacula-fd.sh)
                ;;
            8)
                bash <(curl -s https://raw.githubusercontent.com/0LB-i/menu/main/unbound.sh)
                ;;
            9)
                bash <(curl -s https://raw.githubusercontent.com/0LB-i/menu/main/rclocal-ubuntu.sh)
                ;;
            10)
                bash <(curl -s https://raw.githubusercontent.com/0LB-i/menu/main/dump-zabbix.sh)
                ;;
            *)
                whiptail --msgbox "Opção inválida!" 8 30
                ;;
        esac
        whiptail --msgbox "Execução finalizada. Pressione OK para voltar ao menu." 8 45
    done
}

# === Execução ===
check_whiptail
menu_scripts