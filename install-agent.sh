#!/bin/bash
# Nexus Agent Installer
# Usage: bash <(curl -fsSL https://raw.githubusercontent.com/TIUCSIB/nexus-install/master/install-agent.sh) --panel URL --token TOKEN --node-id ID
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
node_id=""
stats_port=9090

[[ $EUID -ne 0 ]] && echo -e "${red}Error: must run as root!${plain}" && exit 1

while [[ $# -gt 0 ]]; do
    case $1 in
        --panel)    panel_url="$2"; shift 2 ;;
        --token)    token="$2"; shift 2 ;;
        --node-id)  node_id="$2"; shift 2 ;;
        --port)     stats_port="$2"; shift 2 ;;
        --dir)      install_dir="$2"; shift 2 ;;
        *)          echo -e "${red}Unknown: $1${plain}"; exit 1 ;;
    esac
done

if [[ -z "${panel_url}" || -z "${token}" || -z "${node_id}" ]]; then
    echo -e "${red}Usage:${plain}"
    echo "  bash install-agent.sh --panel https://panel.com --token SERVER_TOKEN --node-id 1"
    echo ""
    echo "  --panel    Panel URL"
    echo "  --token    Server token (在面板 系统设置 中获取)"
    echo "  --node-id  节点 ID (在面板 节点管理 中创建后查看)"
    echo "  --port     Stats API 端口 (默认 9090)"
    echo "  --dir      安装目录 (默认 /opt/nexus-agent)"
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
echo -e "  Panel:   ${green}${panel_url}${plain}"
echo -e "  Node ID: ${green}${node_id}${plain}"
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

# 获取最新版本号（多种方式）
get_latest_version() {
    local ver=""
    if command -v gh &>/dev/null; then
        ver=$(gh release list -R "${github_repo}" --json tagName -q '.[0].tagName' 2>/dev/null || true)
    fi
    if [[ -z "${ver}" ]]; then
        ver=$(curl -sL "https://api.github.com/repos/${github_repo}/releases/latest" | grep '"tag_name":' | sed -E 's/.*"([^"]+)".*/\1/' 2>/dev/null || true)
    fi
    echo "${ver}"
}

# 下载文件（多种方式）
download_file() {
    local name="$1"
    local output="$2"
    local ver="${3:-$(get_latest_version)}"
    local url="https://github.com/${github_repo}/releases/download/${ver}/${name}"

    if command -v gh &>/dev/null; then
        if gh release download "${ver}" -R "${github_repo}" -p "${name}" -O "${output}" --clobber 2>/dev/null; then
            if [[ -s "${output}" ]]; then return 0; fi
        fi
    fi

    local api_url="https://api.github.com/repos/${github_repo}/releases/tags/${ver}"
    local asset_id=$(curl -sL "${api_url}" | grep -A20 "\"name\": \"${name}\"" | grep '"id"' | head -1 | sed -E 's/.*"id": ([0-9]+).*/\1/' 2>/dev/null || true)
    if [[ -n "${asset_id}" ]]; then
        curl -sL -H "Accept: application/octet-stream" \
            "https://api.github.com/repos/${github_repo}/releases/assets/${asset_id}" \
            -o "${output}" 2>/dev/null || true
        if [[ -s "${output}" ]]; then return 0; fi
    fi

    if command -v wget &>/dev/null; then
        wget --no-check-certificate -q --show-progress -O "${output}" "${url}" 2>/dev/null || true
    else
        curl -sL -o "${output}" "${url}" 2>/dev/null || true
    fi
    if [[ -s "${output}" ]]; then return 0; fi

    rm -f "${output}" 2>/dev/null || true
    return 1
}

mkdir -p "${install_dir}"

# Download agent binary
echo -e "  Downloading agent..."
binary_name="nexus-agent-linux-${arch}"
last_version=$(get_latest_version)
if [[ -n "${last_version}" ]]; then
    echo -e "  Version: ${green}${last_version}${plain}"
fi
if download_file "${binary_name}" "${install_dir}/nexus-agent" "${last_version}"; then
    chmod +x "${install_dir}/nexus-agent"
    echo -e "  Agent: ${green}OK${plain}"
else
    echo -e "  Agent: ${red}FAILED${plain}"
    exit 1
fi

# Download ns CLI
echo -e "  Downloading ns CLI..."
ns_binary_name="ns-linux-${arch}"
if download_file "${ns_binary_name}" "${install_dir}/ns" "${last_version}"; then
    chmod +x "${install_dir}/ns"
    echo -e "  ns CLI: ${green}OK${plain}"
else
    echo -e "  ns CLI: ${yellow}skipped${plain}"
fi
ln -sf "${install_dir}/ns" /usr/local/bin/ns

# Create agent.yaml using ns bind
"${install_dir}/ns" bind \
    --panel "${panel_url}" \
    --token "${token}" \
    --node-id "${node_id}" \
    --stats-port "${stats_port}" \
    --config "${install_dir}/agent.yaml"

echo -e "  Config:  ${green}${install_dir}/agent.yaml${plain}"

# Install systemd service
if [[ x"${release}" == x"alpine" ]]; then
    cat << SVCEOF > /etc/init.d/nexus-agent
#!/sbin/openrc-run
name="nexus-agent"
command="${install_dir}/nexus-agent"
command_args="-config ${install_dir}/agent.yaml"
command_background="yes"
depend() { need net; }
SVCEOF
    chmod +x /etc/init.d/nexus-agent
    rc-update add nexus-agent default
    service nexus-agent start 2>/dev/null
else
    cat << SVCEOF > /etc/systemd/system/nexus-agent.service
[Unit]
Description=Nexus Agent (node ${node_id})
After=network.target

[Service]
Type=simple
ExecStart=${install_dir}/nexus-agent -config ${install_dir}/agent.yaml
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
echo -e "  Panel:   ${cyan}${panel_url}${plain}"
echo -e "  Node ID: ${green}${node_id}${plain}"
echo -e "  Dir:     ${install_dir}"
echo ""
echo -e "  ${yellow}Manage with ns:${plain}"
echo -e "    ns list                  List nodes"
echo -e "    ns status                Check status"
echo -e "    ns service restart       Restart agent"
echo -e "    ns service stop          Stop agent"
echo ""
echo -e "  ${yellow}Or with systemctl:${plain}"
echo -e "    systemctl start/stop/restart nexus-agent"
echo -e "    journalctl -u nexus-agent -f"
echo ""