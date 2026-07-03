#!/bin/bash
# Nexus Agent Installer
# Usage: bash <(curl -fsSL https://raw.githubusercontent.com/TIUCSIB/nexus/main/scripts/install-agent.sh) --panel https://panel.com --token YOUR_TOKEN
set -e

red='\033[0;31m'
green='\033[0;32m'
yellow='\033[0;33m'
cyan='\033[0;36m'
plain='\033[0m'

install_dir="/opt/nexus-agent"
github_repo="TIUCSIB/nexus"
panel_url=""
token=""
node_name="node-1"
stats_port=9090

[[ $EUID -ne 0 ]] && echo -e "${red}Error: must run as root!${plain}" && exit 1

while [[ $# -gt 0 ]]; do
    case $1 in
        --panel)  panel_url="$2"; shift 2 ;;
        --token)  token="$2"; shift 2 ;;
        --name)   node_name="$2"; shift 2 ;;
        --port)   stats_port="$2"; shift 2 ;;
        --dir)    install_dir="$2"; shift 2 ;;
        *)        echo -e "${red}Unknown: $1${plain}"; exit 1 ;;
    esac
done

if [[ -z "${panel_url}" || -z "${token}" ]]; then
    echo -e "${red}Usage:${plain}"
    echo "  bash install-agent.sh --panel https://panel.com --token TOKEN [--name node-1]"
    exit 1
fi

if [[ -f /etc/redhat-release ]]; then release="centos"
elif cat /etc/issue 2>/dev/null | grep -Eqi "alpine"; then release="alpine"
elif cat /etc/issue 2>/dev/null | grep -Eqi "debian|ubuntu"; then release="debian"
elif cat /proc/version 2>/dev/null | grep -Eqi "debian|ubuntu"; then release="debian"
elif cat /proc/version 2>/dev/null | grep -Eqi "centos|redhat|rocky"; then release="centos"
else release="centos"; fi

arch=$(uname -m)
if [[ $arch == "x86_64" || $arch == "x64" || $arch == "amd64" ]]; then arch="amd64"
elif [[ $arch == "aarch64" || $arch == "arm64" ]]; then arch="arm64"
else echo -e "${red}Unsupported: ${arch}${plain}"; exit 1; fi

echo -e "${cyan}========================================${plain}"
echo -e "${cyan}       Nexus Agent Installer            ${plain}"
echo -e "${cyan}========================================${plain}"
echo -e "  Panel:  ${green}${panel_url}${plain}"
echo -e "  Name:   ${green}${node_name}${plain}"
echo ""

if [[ x"${release}" == x"centos" ]]; then
    yum install -y wget curl ca-certificates socat >/dev/null 2>&1
elif [[ x"${release}" == x"alpine" ]]; then
    apk add --no-cache wget curl ca-certificates socat >/dev/null 2>&1
else
    apt-get update -y >/dev/null 2>&1
    apt-get install -y wget curl ca-certificates socat unzip >/dev/null 2>&1
fi

# Install sing-box
if ! command -v sing-box &>/dev/null; then
    echo -e "  Installing sing-box..."
    sb_ver=$(curl -Ls "https://api.github.com/repos/SagerNet/sing-box/releases/latest" | grep '"tag_name":' | sed -E 's/.*"v([^"]+)".*/\1/')
    if [[ -n "${sb_ver}" ]]; then
        wget --no-check-certificate -q -O /tmp/sb.tar.gz "https://github.com/SagerNet/sing-box/releases/download/v${sb_ver}/sing-box-${sb_ver}-linux-${arch}.tar.gz" 2>/dev/null
        if [[ $? -eq 0 ]]; then
            tar -xzf /tmp/sb.tar.gz -C /tmp/
            cp /tmp/sing-box-*/sing-box /usr/local/bin/
            chmod +x /usr/local/bin/sing-box
            rm -rf /tmp/sb.tar.gz /tmp/sing-box-*
            echo -e "  sing-box: ${green}v${sb_ver}${plain}"
        fi
    fi
else
    echo -e "  sing-box: ${green}installed${plain}"
fi

mkdir -p "${install_dir}"

echo -e "  Downloading agent..."
binary_name="nexus-agent-linux-${arch}"
last_version=$(curl -Ls "https://api.github.com/repos/${github_repo}/releases/latest" | grep '"tag_name":' | sed -E 's/.*"([^"]+)".*/\1/')
if [[ -n "${last_version}" ]]; then
    echo -e "  Version: ${green}${last_version}${plain}"
    wget --no-check-certificate -q --show-progress -O "${install_dir}/nexus-agent" "https://github.com/${github_repo}/releases/download/${last_version}/${binary_name}"
else
    wget --no-check-certificate -q --show-progress -O "${install_dir}/nexus-agent" "https://github.com/${github_repo}/releases/latest/download/${binary_name}"
fi
chmod +x "${install_dir}/nexus-agent"

if [[ x"${release}" == x"alpine" ]]; then
    cat << SVCEOF > /etc/init.d/nexus-agent
#!/sbin/openrc-run
name="nexus-agent"
command="${install_dir}/nexus-agent"
command_args="--panel ${panel_url} --token ${token} --name ${node_name}"
command_background="yes"
depend() { need net; }
SVCEOF
    chmod +x /etc/init.d/nexus-agent
    rc-update add nexus-agent default
    service nexus-agent start 2>/dev/null
else
    cat << SVCEOF > /etc/systemd/system/nexus-agent.service
[Unit]
Description=Nexus Agent (${node_name})
After=network.target

[Service]
Type=simple
ExecStart=${install_dir}/nexus-agent --panel ${panel_url} --token ${token} --name ${node_name}
Restart=always
RestartSec=5

[Install]
WantedBy=multi-user.target
SVCEOF
    systemctl daemon-reload
    systemctl enable nexus-agent >/dev/null 2>&1
    systemctl start nexus-agent 2>/dev/null
fi

sleep 1

echo ""
echo -e "${green}========================================${plain}"
echo -e "${green}  Nexus Agent installed successfully!   ${plain}"
echo -e "${green}========================================${plain}"
echo ""
echo -e "  Panel:  ${cyan}${panel_url}${plain}"
echo -e "  Node:   ${green}${node_name}${plain}"
echo -e "  Dir:    ${install_dir}"
echo ""
echo -e "  systemctl start/stop/restart nexus-agent"
echo -e "  journalctl -u nexus-agent -f"
echo ""
