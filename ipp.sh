#!/bin/bash
# SCRIPT INSTALL LIMIT IP - AUTO LOCK MULTI LOGIN
# Jalankan sekali, auto lock selamanya!

clear
echo -e "\033[1;32m════════════════════════════════════════════╗\033[0m"
echo -e "\033[1;36m     INSTALL LIMIT IP - AUTO LOCK\033[0m"
echo -e "\033[1;32m════════════════════════════════════════════╝\033[0m"
echo ""

# ============================================
# 1. BUAT SCRIPT LIMIT IP
# ============================================
cat > /usr/local/bin/limit-ip.sh << 'EOF'
#!/bin/bash
# AUTO LOCK IP - MAX 3 PER USER
LOG="/var/log/limit-ip.log"
DEFAULT_LIMIT=3

# Bikin log jika belum ada
mkdir -p /var/log
touch $LOG

echo "$(date '+%Y-%m-%d %H:%M:%S') | START | Limit IP Service Started" >> $LOG

while true; do
    # Cek dari log Xray
    tail -n 300 /var/log/xray/access.log 2>/dev/null | \
    grep -E "vless|vmess|trojan" | \
    grep -oE 'email: [^,]+|([0-9]{1,3}\.){3}[0-9]{1,3}' | \
    paste - - | \
    while read email ip; do
        user=$(echo "$email" | awk '{print $2}')
        ip_addr=$(echo "$ip" | awk '{print $2}')
        
        # Skip local IP
        [[ "$ip_addr" == "127.0.0.1" ]] && continue
        [[ "$ip_addr" == "::1" ]] && continue
        [[ -z "$ip_addr" ]] && continue
        [[ -z "$user" ]] && continue
        
        # Cek limit per user
        MAX_IP=$DEFAULT_LIMIT
        
        # Cek dari berbagai folder limit
        if [[ -f "/etc/kyt/limit/vmess/ip/$user" ]]; then
            MAX_IP=$(cat "/etc/kyt/limit/vmess/ip/$user")
        elif [[ -f "/etc/kyt/limit/vless/ip/$user" ]]; then
            MAX_IP=$(cat "/etc/kyt/limit/vless/ip/$user")
        elif [[ -f "/etc/kyt/limit/trojan/ip/$user" ]]; then
            MAX_IP=$(cat "/etc/kyt/limit/trojan/ip/$user")
        elif [[ -f "/etc/limit/vmess/$user" ]]; then
            MAX_IP=$(cat "/etc/limit/vmess/$user")
        elif [[ -f "/etc/limit/vless/$user" ]]; then
            MAX_IP=$(cat "/etc/limit/vless/$user")
        elif [[ -f "/etc/limit/trojan/$user" ]]; then
            MAX_IP=$(cat "/etc/limit/trojan/$user")
        fi
        
        # Jika MAX_IP = 0, skip (unlimited)
        [[ $MAX_IP -eq 0 ]] && continue
        
        # Hitung jumlah IP unik user
        count=$(tail -n 300 /var/log/xray/access.log 2>/dev/null | \
                grep "email: $user" | \
                grep -oE '([0-9]{1,3}\.){3}[0-9]{1,3}' | \
                sort -u | wc -l)
        
        # Jika melebihi limit, LOCK
        if [[ $count -gt $MAX_IP ]]; then
            # Cek apakah IP sudah di-lock
            if ! iptables -L INPUT -n | grep -q "$ip_addr"; then
                iptables -I INPUT -s $ip_addr -j DROP 2>/dev/null
                iptables -I FORWARD -s $ip_addr -j DROP 2>/dev/null
                echo "$(date '+%Y-%m-%d %H:%M:%S') | 🔒 LOCKED | IP: $ip_addr | User: $user | (${count}/${MAX_IP})" >> $LOG
            fi
        else
            # Jika sudah di bawah limit, UNLOCK
            if iptables -L INPUT -n | grep -q "$ip_addr"; then
                # Cek apakah IP masih dipakai user lain
                used_by_other=$(tail -n 300 /var/log/xray/access.log 2>/dev/null | \
                               grep "$ip_addr" | \
                               grep -v "email: $user" | \
                               wc -l)
                
                if [[ $used_by_other -eq 0 ]]; then
                    iptables -D INPUT -s $ip_addr -j DROP 2>/dev/null
                    iptables -D FORWARD -s $ip_addr -j DROP 2>/dev/null
                    echo "$(date '+%Y-%m-%d %H:%M:%S') | 🔓 UNLOCKED | IP: $ip_addr | User: $user | (${count}/${MAX_IP})" >> $LOG
                fi
            fi
        fi
    done
    
    # Juga cek dari koneksi aktif (netstat)
    netstat -tnpa 2>/dev/null | grep 'ESTABLISHED.*xray' | awk '{print $5}' | cut -d: -f1 | sort -u | while read ip_addr; do
        [[ -z "$ip_addr" ]] && continue
        [[ "$ip_addr" == "127.0.0.1" ]] && continue
        
        # Cek user dari IP ini
        user=$(tail -n 300 /var/log/xray/access.log 2>/dev/null | grep "$ip_addr" | grep -oE 'email: [^,]+' | head -1 | awk '{print $2}')
        [[ -z "$user" ]] && continue
        
        # Cek limit user
        MAX_IP=$DEFAULT_LIMIT
        if [[ -f "/etc/kyt/limit/vmess/ip/$user" ]]; then
            MAX_IP=$(cat "/etc/kyt/limit/vmess/ip/$user")
        elif [[ -f "/etc/kyt/limit/vless/ip/$user" ]]; then
            MAX_IP=$(cat "/etc/kyt/limit/vless/ip/$user")
        elif [[ -f "/etc/kyt/limit/trojan/ip/$user" ]]; then
            MAX_IP=$(cat "/etc/kyt/limit/trojan/ip/$user")
        fi
        
        [[ $MAX_IP -eq 0 ]] && continue
        
        # Hitung IP user
        count=$(tail -n 300 /var/log/xray/access.log 2>/dev/null | \
                grep "email: $user" | \
                grep -oE '([0-9]{1,3}\.){3}[0-9]{1,3}' | \
                sort -u | wc -l)
        
        if [[ $count -gt $MAX_IP ]]; then
            if ! iptables -L INPUT -n | grep -q "$ip_addr"; then
                iptables -I INPUT -s $ip_addr -j DROP 2>/dev/null
                echo "$(date '+%Y-%m-%d %H:%M:%S') | 🔒 LOCKED (netstat) | IP: $ip_addr | User: $user" >> $LOG
            fi
        fi
    done
    
    sleep 20
done
EOF

# Kasih permission
chmod +x /usr/local/bin/limit-ip.sh

# ============================================
# 2. BUAT SERVICE SYSTEMD
# ============================================
cat > /etc/systemd/system/vmip.service << 'EOF'
[Unit]
Description=Limit IP Service - Auto Lock
After=network.target xray.service

[Service]
Type=simple
ExecStart=/usr/local/bin/limit-ip.sh
Restart=always
RestartSec=10
User=root
StandardOutput=journal
StandardError=journal

[Install]
WantedBy=multi-user.target
EOF

# Copy untuk vless & trojan
cp /etc/systemd/system/vmip.service /etc/systemd/system/vlip.service
cp /etc/systemd/system/vmip.service /etc/systemd/system/trip.service

# ============================================
# 3. RELOAD & START
# ============================================
systemctl daemon-reload
systemctl enable vmip vlip trip
systemctl start vmip vlip trip

# ============================================
# 4. CEK STATUS
# ============================================
clear
echo -e "\033[1;32m════════════════════════════════════════════╗\033[0m"
echo -e "\033[1;36m     ✅ LIMIT IP AUTO LOCK INSTALLED\033[0m"
echo -e "\033[1;32m════════════════════════════════════════════╝\033[0m"
echo ""

for service in vmip vlip trip; do
    if systemctl is-active --quiet $service; then
        echo -e " \033[1;32m●\033[0m $service : \033[1;32mRUNNING ✓\033[0m"
    else
        echo -e " \033[1;31m●\033[0m $service : \033[1;31mFAILED ✗\033[0m"
    fi
done

echo ""
echo -e "\033[1;33m📁 Log File:\033[0m"
echo "   tail -f /var/log/limit-ip.log"
echo ""
echo -e "\033[1;33m🔒 Cek IP yang di-lock:\033[0m"
echo "   iptables -L INPUT -n | grep DROP"
echo ""
echo -e "\033[1;33m📊 Cek limit per user:\033[0m"
echo "   cat /etc/kyt/limit/vmess/ip/username"
echo ""
echo -e "\033[1;32m════════════════════════════════════════════╗\033[0m"

# ============================================
# 5. BUAT MENU ON/OFF
# ============================================
cat > /usr/local/bin/limit-menu << 'EOF'
#!/bin/bash
# Menu Limit IP

clear
echo -e "\033[1;32m════════════════════════════════════════════╗\033[0m"
echo -e "\033[1;36m     MENU LIMIT IP\033[0m"
echo -e "\033[1;32m════════════════════════════════════════════╝\033[0m"
echo ""

# Cek status
if systemctl is-active --quiet vmip; then
    echo -e " Status : \033[1;32mON (Auto Lock Active)\033[0m"
else
    echo -e " Status : \033[1;31mOFF (No Limit)\033[0m"
fi

echo ""
echo -e " \033[1;33m1.\033[0m Turn ON Limit IP (Auto Lock)"
echo -e " \033[1;33m2.\033[0m Turn OFF Limit IP (Unlock All)"
echo -e " \033[1;33m3.\033[0m Cek Log Limit"
echo -e " \033[1;33m4.\033[0m Cek IP yang di-lock"
echo -e " \033[1;33m5.\033[0m Unlock IP Manual"
echo -e " \033[1;33mx.\033[0m Exit"
echo ""
read -p "Pilih [1-5/x] : " menu

case $menu in
    1)
        systemctl start vmip vlip trip
        systemctl enable vmip vlip trip
        echo -e "\033[1;32m✅ Limit IP Aktif!\033[0m"
        sleep 2
        limit-menu
        ;;
    2)
        systemctl stop vmip vlip trip
        systemctl disable vmip vlip trip
        # Unlock semua IP
        iptables -L INPUT -n | grep DROP | awk '{print $4}' | while read ip; do
            iptables -D INPUT -s $ip -j DROP 2>/dev/null
            iptables -D FORWARD -s $ip -j DROP 2>/dev/null
        done
        echo -e "\033[1;31m❌ Limit IP Off, semua IP di-unlock!\033[0m"
        sleep 2
        limit-menu
        ;;
    3)
        tail -50 /var/log/limit-ip.log
        echo ""
        read -p "Press ENTER to back..."
        limit-menu
        ;;
    4)
        echo -e "\033[1;33mIP yang di-lock:\033[0m"
        iptables -L INPUT -n | grep DROP
        echo ""
        read -p "Press ENTER to back..."
        limit-menu
        ;;
    5)
        read -p "Masukkan IP yang mau di-unlock: " ip_unlock
        iptables -D INPUT -s $ip_unlock -j DROP 2>/dev/null
        iptables -D FORWARD -s $ip_unlock -j DROP 2>/dev/null
        echo -e "\033[1;32m✅ IP $ip_unlock di-unlock!\033[0m"
        sleep 2
        limit-menu
        ;;
    x|X)
        clear
        exit 0
        ;;
    *)
        echo -e "\033[1;31mPilihan salah!\033[0m"
        sleep 1
        limit-menu
        ;;
esac
EOF

chmod +x /usr/local/bin/limit-menu

echo ""
echo -e "\033[1;33m📋 Menu Limit IP:\033[0m"
echo "   limit-menu"
echo ""
echo -e "\033[1;32m════════════════════════════════════════════╗\033[0m"
