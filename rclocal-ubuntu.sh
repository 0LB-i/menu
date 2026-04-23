#!/bin/bash

cat << 'EOF' > /etc/rc.local
#!/bin/bash
exit 0
EOF

chmod +x /etc/rc.local
# Cria o serviço systemd para compatibilidade com rc.local
cat << 'EOF' > /etc/systemd/system/rc-local.service
[Unit]
Description=/etc/rc.local Compatibility
ConditionPathExists=/etc/rc.local
After=network.target

[Service]
Type=oneshot
ExecStart=/etc/rc.local
TimeoutSec=0
StandardOutput=journal
RemainAfterExit=yes

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
systemctl enable --now rc-local
systemctl status rc-local --no-pager