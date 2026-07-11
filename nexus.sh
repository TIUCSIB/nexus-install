#!/bin/bash
# Nexus Management Script
red='\033[0;31m'
green='\033[0;32m'
yellow='\033[0;33m'
cyan='\033[0;36m'
plain='\033[0m'
panel_dir="/opt/nexus"
agent_dir="/opt/nexus-agent"

# Detect service manager
if command -v systemctl &>/dev/null; then
    service_mgr="systemd"
elif command -v service &>/dev/null; then
    service_mgr="openrc"
else
    service_mgr="none"
fi

# Service control functions
start_service() {
    local svc=$1
    case $service_mgr in
        systemd) systemctl start $svc ;;
        openrc) service $svc start ;;
        none) echo -e "${red}No service manager found${plain}"; return 1 ;;
    esac
}

stop_service() {
    local svc=$1
    case $service_mgr in
        systemd) systemctl stop $svc ;;
        openrc) service $svc stop ;;
        none) echo -e "${red}No service manager found${plain}"; return 1 ;;
    esac
}

restart_service() {
    local svc=$1
    case $service_mgr in
        systemd) systemctl restart $svc ;;
        openrc) service $svc restart ;;
        none) echo -e "${red}No service manager found${plain}"; return 1 ;;
    esac
}

status_service() {
    local svc=$1
    case $service_mgr in
        systemd) systemctl status $svc ;;
        openrc) service $svc status ;;
        none) echo -e "${red}No service manager found${plain}"; return 1 ;;
    esac
}

show_logs() {
    local svc=$1
    case $service_mgr in
        systemd) journalctl -u $svc -f --no-pager ;;
        openrc) tail -f /var/log/$svc.log 2>/dev/null || echo -e "${yellow}Log file not found${plain}" ;;
        none) echo -e "${red}No service manager found${plain}"; return 1 ;;
    esac
}

show_menu() {
    echo -e "${cyan}========================================${plain}"
    echo -e "${cyan}         Nexus Management               ${plain}"
    echo -e "${cyan}========================================${plain}"
    echo -e "  System: ${green}${service_mgr}${plain}"
    echo ""
    echo -e "  ${yellow}1)${plain} Start Panel"
    echo -e "  ${yellow}2)${plain} Stop Panel"
    echo -e "  ${yellow}3)${plain} Restart Panel"
    echo -e "  ${yellow}4)${plain} Panel Status"
    echo -e "  ${yellow}5)${plain} Panel Logs"
    echo -e "  ${yellow}6)${plain} Edit Panel Config"
    echo ""
    echo -e "  ${yellow}7)${plain} Start Agent"
    echo -e "  ${yellow}8)${plain} Stop Agent"
    echo -e "  ${yellow}9)${plain} Restart Agent"
    echo -e "  ${yellow}10)${plain} Agent Status"
    echo -e "  ${yellow}11)${plain} Agent Logs"
    echo ""
    echo -e "  ${yellow}12)${plain} Update Panel"
    echo -e "  ${yellow}13)${plain} Update Agent"
    echo -e "  ${yellow}14)${plain} Create Admin User"
    echo ""
    echo -e "  ${yellow}0)${plain} Exit"
    echo ""
    read -p "  Select: " choice
    case $choice in
        1)  start_service nexus && echo -e "${green}Panel started${plain}" ;;
        2)  stop_service nexus && echo -e "${green}Panel stopped${plain}" ;;
        3)  restart_service nexus && echo -e "${green}Panel restarted${plain}" ;;
        4)  status_service nexus ;;
        5)  show_logs nexus ;;
        6)  ${EDITOR:-nano} "${panel_dir}/config.yaml" ;;
        7)  start_service nexus-agent && echo -e "${green}Agent started${plain}" ;;
        8)  stop_service nexus-agent && echo -e "${green}Agent stopped${plain}" ;;
        9)  restart_service nexus-agent && echo -e "${green}Agent restarted${plain}" ;;
        10) status_service nexus-agent ;;
        11) show_logs nexus-agent ;;
        12) update_panel ;;
        13) update_agent ;;
        14) create_admin ;;
        0)  exit 0 ;;
        *)  echo -e "${red}Invalid${plain}" ;;
    esac
    echo ""
    show_menu
}

update_panel() {
    echo -e "Updating panel..."
    local github_repo="TIUCSIB/nexus"
    local arch=$(uname -m)
    [[ $arch == "x86_64" || $arch == "x64" || $arch == "amd64" ]] && arch="amd64"
    [[ $arch == "aarch64" || $arch == "arm64" ]] && arch="arm64"
    local last_version=$(curl -Ls "https://api.github.com/repos/${github_repo}/releases/latest" | grep '"tag_name":' | sed -E 's/.*"([^"]+)".*/\1/')
    if [[ -n "${last_version}" ]]; then
        stop_service nexus 2>/dev/null
        wget --no-check-certificate -q -O "${panel_dir}/nexus" "https://github.com/${github_repo}/releases/download/${last_version}/nexus-linux-${arch}"
        chmod +x "${panel_dir}/nexus"
        start_service nexus 2>/dev/null
        echo -e "${green}Panel updated to ${last_version}${plain}"
    else
        echo -e "${red}Failed to get latest version${plain}"
    fi
}

update_agent() {
    echo -e "Updating agent..."
    local github_repo="TIUCSIB/nexus"
    local arch=$(uname -m)
    [[ $arch == "x86_64" || $arch == "x64" || $arch == "amd64" ]] && arch="amd64"
    [[ $arch == "aarch64" || $arch == "arm64" ]] && arch="arm64"
    local last_version=$(curl -Ls "https://api.github.com/repos/${github_repo}/releases/latest" | grep '"tag_name":' | sed -E 's/.*"([^"]+)".*/\1/')
    if [[ -n "${last_version}" ]]; then
        stop_service nexus-agent 2>/dev/null
        wget --no-check-certificate -q -O "${agent_dir}/nexus-agent" "https://github.com/${github_repo}/releases/download/${last_version}/nexus-agent-linux-${arch}"
        chmod +x "${agent_dir}/nexus-agent"
        start_service nexus-agent 2>/dev/null
        echo -e "${green}Agent updated to ${last_version}${plain}"
    else
        echo -e "${red}Failed to get latest version${plain}"
    fi
}

create_admin() {
    read -p "  Admin email: " email
    read -s -p "  Admin password: " pass
    echo ""
    if [[ -n "${email}" && -n "${pass}" ]]; then
        "${panel_dir}/nexus" -config "${panel_dir}/config.yaml" -admin-email "${email}" -admin-pass "${pass}"
        echo -e "${green}Admin created${plain}"
    fi
}

if [[ -n "$1" ]]; then
    case $1 in
        start)    systemctl start nexus ;;
        stop)     systemctl stop nexus ;;
        restart)  systemctl restart nexus ;;
        status)   systemctl status nexus ;;
        logs)     journalctl -u nexus -f --no-pager ;;
        update)   update_panel ;;
        admin)    create_admin ;;
        *)        show_menu ;;
    esac
else
    show_menu
fi
