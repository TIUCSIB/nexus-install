# Nexus Install Scripts

Nexus Panel 和 Agent 的一键安装脚本。

## 安装面板

```bash
# 默认端口 6100
bash <(curl -fsSL https://raw.githubusercontent.com/TIUCSIB/nexus-install/main/install-panel.sh)

# 自定义端口
bash <(curl -fsSL https://raw.githubusercontent.com/TIUCSIB/nexus-install/main/install-panel.sh) --port 8080
```

## 安装 Agent

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/TIUCSIB/nexus-install/main/install-agent.sh) \
  --panel https://your-panel.com \
  --token YOUR_REGISTER_TOKEN \
  --name my-node
```
