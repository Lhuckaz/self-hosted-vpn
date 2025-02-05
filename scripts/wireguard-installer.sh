#!/bin/bash
dnf update && dnf upgrade -y

dnf install wireguard-tools iptables cronie -y

# Set DNS server to Cloudflare's DNS
sed -i 's/^#DNS=/DNS=1.1.1.1/' /etc/systemd/resolved.conf
sed -i 's/^#FallbackDNS=/FallbackDNS=1.1.1.1/' /etc/systemd/resolved.conf

# Sets up a scheduled task to update and upgrade packages weekly
systemctl start crond
systemctl enable crond
echo "0 0 * * 6 /usr/bin/dnf update -y && /usr/bin/dnf upgrade -y" > cronupdateweekly
crontab cronupdateweekly

# Save keys to files
cd /etc/wireguard/

# Retrieve the default network interface
INTERFACE=$(ip route list default | awk '{print $5}')

# Create and write VPN configuration
cat <<EOF > /etc/wireguard/wg0.conf
[Interface]
Address = 10.0.1.0/24
ListenPort = 51820
PrivateKey = ${SERVER_PRIVATE_KEY} 
PostUp = sysctl net.ipv4.ip_forward=1
PostUp = iptables -t nat -I POSTROUTING 1 -s 10.0.1.0/16 -o $INTERFACE -j MASQUERADE
PostUp = iptables -I INPUT 1 -i wg0 -j ACCEPT
PostUp = iptables -I FORWARD 1 -i $INTERFACE -o wg0 -j ACCEPT
PostUp = iptables -I FORWARD 1 -i wg0 -o $INTERFACE -j ACCEPT
PostUp = iptables -I INPUT 1 -i $INTERFACE -p udp --dport 51820 -j ACCEPT
PostDown = sysctl net.ipv4.ip_forward=0
PostDown = iptables -t nat -D POSTROUTING -s 10.0.1.0/16 -o $INTERFACE -j MASQUERADE
PostDown = iptables -D INPUT -i wg0 -j ACCEPT
PostDown = iptables -D FORWARD -i $INTERFACE -o wg0 -j ACCEPT
PostDown = iptables -D FORWARD -i wg0 -o $INTERFACE -j ACCEPT
PostDown = iptables -D INPUT -i $INTERFACE -p udp --dport 51820 -j ACCEPT

[Peer]
PublicKey = ${CLIENT_PUBLIC_KEY}  
PresharedKey = ${CLIENT_PRESHARED_KEY} 
AllowedIPs = 10.0.0.2/32
EOF

# Start and enable the WireGuard service to run on boot
systemctl start wg-quick@wg0
systemctl enable wg-quick@wg0
