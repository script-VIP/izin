#!/bin/bash
#Color
DF='\e[39m'
Bold='\e[1m'
Blink='\e[5m'
yell='\e[33m'
RED='\033[0;31m'
green='\e[32m'
PURPLE='\e[35m'
cyan='\e[36m'
LRED='\e[91m'
Lgreen='\e[92m'
Lyellow='\e[93m'
NC='\e[0m'
GREEN='\033[0;32m'
ORANGE='\033[0;33m'
LIGHT='\033[0;37m'
grenbo="\e[92;1m"
blue="\033[0;34m"
WhiteBe="\033[5;37m"
Blue="\033[36m"
clear

echo -e "\e[32mloading...\e[0m"
clear

# ============================================
# CEK STATUS (PAKAI CRON)
# ============================================
if crontab -l 2>/dev/null | grep -q "limit-ip-cron.sh"; then
   status_limip="${GREEN}ON$NC${blue} │$NC"
else
   status_limip="${RED}OFF${NC} "
fi

if crontab -l 2>/dev/null | grep -q "limit-quota-cron.sh"; then
   status_limq="${GREEN}ON$NC${blue} │$NC"
else
   status_limq="${RED}OFF${NC} "
fi

echo -e "\033[5;36m┌──────────────────────────────────────────┐\033[0m"
echo -e "       Status limit ip      : $status_limip"
echo -e "       Status limit quota   : $status_limq"
echo -e "\033[5;36m└──────────────────────────────────────────┘\033[0m"
echo -e "\033[5;36m┌──────────────────────────────────────────┐\033[0m"
echo -e " ${WhiteBe}1. TURN OFF LIMIT IP${NC}"
echo -e " ${WhiteBe}2. TURN ON  LIMIT IP${NC}"
echo -e " ${WhiteBe}3. TURN OFF LIMIT QUOTA${NC}"
echo -e " ${WhiteBe}4. TURN ON  LIMIT QUOTA${NC}"
echo -e " ${WhiteBe}x. Back To Main Menu ${NC}"
echo -e "\033[5;36m└──────────────────────────────────────────┘\033[0m"

# ============================================
# FUNGSI TURN ON LIMIT IP
# ============================================
start_limip() {
clear
    echo -e "${yell}Mengaktifkan Limit IP...${NC}"
    
    # Buat script limit IP (BACA LIMIT DARI FILE USER)
    cat > /usr/local/bin/limit-ip-cron.sh << 'EOF'
#!/bin/bash
# LIMIT IP - BACA LIMIT DARI FILE USER
LOG="/var/log/limit-ip.log"

tail -n 50 /var/log/xray/access.log 2>/dev/null | \
grep -E "vless|vmess|trojan" | \
grep -oE 'email: [^,]+|([0-9]{1,3}\.){3}[0-9]{1,3}' | \
paste - - | \
while read email ip; do
    user=$(echo "$email" | awk '{print $2}')
    ip_addr=$(echo "$ip" | awk '{print $2}')
    
    [[ "$ip_addr" == "127.0.0.1" ]] && continue
    [[ -z "$ip_addr" ]] && continue
    [[ -z "$user" ]] && continue
    
    # BACA LIMIT DARI FILE (SUDAH DI SET PAS BIKIN AKUN)
    MAX_IP=3
    [[ -f "/etc/kyt/limit/vmess/ip/$user" ]] && MAX_IP=$(cat "/etc/kyt/limit/vmess/ip/$user")
    [[ -f "/etc/kyt/limit/vless/ip/$user" ]] && MAX_IP=$(cat "/etc/kyt/limit/vless/ip/$user")
    [[ -f "/etc/kyt/limit/trojan/ip/$user" ]] && MAX_IP=$(cat "/etc/kyt/limit/trojan/ip/$user")
    [[ -f "/etc/limit/vmess/$user" ]] && MAX_IP=$(cat "/etc/limit/vmess/$user")
    [[ -f "/etc/limit/vless/$user" ]] && MAX_IP=$(cat "/etc/limit/vless/$user")
    [[ -f "/etc/limit/trojan/$user" ]] && MAX_IP=$(cat "/etc/limit/trojan/$user")
    
    # JIKA 0 = UNLIMITED
    [[ $MAX_IP -eq 0 ]] && continue
    
    # HITUNG IP USER
    count=$(tail -n 50 /var/log/xray/access.log 2>/dev/null | grep "email: $user" | grep -oE '([0-9]{1,3}\.){3}[0-9]{1,3}' | sort -u | wc -l)
    
    # LOCK JIKA MELEBIHI LIMIT
    if [[ $count -gt $MAX_IP ]]; then
        if ! iptables -L INPUT -n 2>/dev/null | grep -q "$ip_addr"; then
            iptables -I INPUT -s $ip_addr -j DROP 2>/dev/null
            echo "$(date '+%Y-%m-%d %H:%M:%S') | LOCKED | $ip_addr | $user | (${count}/${MAX_IP})" >> $LOG
        fi
    else
        # UNLOCK JIKA SUDAH DI BAWAH LIMIT
        if iptables -L INPUT -n 2>/dev/null | grep -q "$ip_addr"; then
            used=$(tail -n 50 /var/log/xray/access.log 2>/dev/null | grep "$ip_addr" | grep -v "email: $user" | wc -l)
            if [[ $used -eq 0 ]]; then
                iptables -D INPUT -s $ip_addr -j DROP 2>/dev/null
                echo "$(date '+%Y-%m-%d %H:%M:%S') | UNLOCKED | $ip_addr" >> $LOG
            fi
        fi
    fi
done
EOF

    chmod +x /usr/local/bin/limit-ip-cron.sh
    
    # Tambahkan ke cron (jalan tiap 2 menit)
    (crontab -l 2>/dev/null | grep -v "limit-ip-cron.sh"; echo "*/2 * * * * /usr/local/bin/limit-ip-cron.sh") | crontab -
    
    clear
    echo -e "${GREEN}════════════════════════════════════════${NC}"
    echo -e "${GREEN}  ✅ LIMIT IP AKTIF${NC}"
    echo -e "${GREEN}════════════════════════════════════════${NC}"
    echo -e " Limit sesuai setting pas buat akun"
    echo -e " Log: ${YELLOW}/var/log/limit-ip.log${NC}"
    echo -e "${GREEN}════════════════════════════════════════${NC}"
    sleep 2
    exec bash "$0"
}

# ============================================
# FUNGSI TURN OFF LIMIT IP
# ============================================
stop_limip() {
clear
    echo -e "${yell}Mematikan Limit IP...${NC}"
    
    # Hapus dari cron
    crontab -l 2>/dev/null | grep -v "limit-ip-cron.sh" | crontab -
    
    # Unlock semua IP
    iptables -L INPUT -n 2>/dev/null | grep DROP | awk '{print $4}' | while read ip; do
        iptables -D INPUT -s $ip -j DROP 2>/dev/null
        echo "$(date): UNLOCKED $ip" >> /var/log/limit-ip.log
    done
    
    clear
    echo -e "${RED}════════════════════════════════════════${NC}"
    echo -e "${RED}  ❌ LIMIT IP DINONAKTIFKAN${NC}"
    echo -e "${RED}════════════════════════════════════════${NC}"
    echo -e " Semua IP sudah di-unlock"
    echo -e "${RED}════════════════════════════════════════${NC}"
    sleep 2
    exec bash "$0"
}

# ============================================
# FUNGSI TURN ON LIMIT QUOTA
# ============================================
start_limq() {
clear
    echo -e "${yell}Mengaktifkan Limit Quota...${NC}"
    
    # Buat script quota
    cat > /usr/local/bin/limit-quota-cron.sh << 'EOF'
#!/bin/bash
# LIMIT QUOTA
LOG="/var/log/limit-quota.log"
MAX_QUOTA=1073741824 # 1GB

mkdir -p /var/log/user_usage

tail -n 100 /var/log/xray/access.log 2>/dev/null | \
grep -E "vless|vmess|trojan" | \
grep -oE 'email: [^,]+|bytes: [0-9]+' | \
paste - - | \
while read email bytes; do
    user=$(echo "$email" | awk '{print $2}')
    used=$(echo "$bytes" | awk '{print $2}')
    
    if [[ ! -z "$user" ]] && [[ ! -z "$used" ]]; then
        total=$(cat /var/log/user_usage/$user 2>/dev/null || echo 0)
        total=$((total + used))
        echo $total > /var/log/user_usage/$user
        
        if [[ $total -gt $MAX_QUOTA ]]; then
            echo "$(date '+%Y-%m-%d %H:%M:%S') | QUOTA EXCEEDED | $user | $(($total/1073741824))GB" >> $LOG
            # Lock user di config
            sed -i "s/\"email\": \"$user\"/\"email\": \"$user-LOCKED\"/g" /etc/xray/config.json 2>/dev/null
            systemctl restart xray
        fi
    fi
done
EOF

    chmod +x /usr/local/bin/limit-quota-cron.sh
    
    # Tambahkan ke cron (jalan tiap 5 menit)
    (crontab -l 2>/dev/null | grep -v "limit-quota-cron.sh"; echo "*/5 * * * * /usr/local/bin/limit-quota-cron.sh") | crontab -
    
    clear
    echo -e "${GREEN}════════════════════════════════════════${NC}"
    echo -e "${GREEN}  ✅ LIMIT QUOTA AKTIF${NC}"
    echo -e "${GREEN}════════════════════════════════════════${NC}"
    echo -e " Log: ${YELLOW}/var/log/limit-quota.log${NC}"
    echo -e "${GREEN}════════════════════════════════════════${NC}"
    sleep 2
    exec bash "$0"
}

# ============================================
# FUNGSI TURN OFF LIMIT QUOTA
# ============================================
stop_limq() {
clear
    echo -e "${yell}Mematikan Limit Quota...${NC}"
    
    # Hapus dari cron
    crontab -l 2>/dev/null | grep -v "limit-quota-cron.sh" | crontab -
    
    clear
    echo -e "${RED}════════════════════════════════════════${NC}"
    echo -e "${RED}  ❌ LIMIT QUOTA DINONAKTIFKAN${NC}"
    echo -e "${RED}════════════════════════════════════════${NC}"
    sleep 2
    exec bash "$0"
}

# ============================================
# MENU PILIHAN
# ============================================
read -p "Select From Options [ 1-4 / x ] : " menu
case $menu in
    1) stop_limip ;;
    2) start_limip ;;
    3) stop_limq ;;
    4) start_limq ;;
    x|X) 
        clear
        echo -e "${GREEN}Back to Main Menu...${NC}"
        sleep 1
        menu
        ;;
    *)
        echo -e "${RED}Option not found!${NC}"
        sleep 1
        exec bash "$0"
        ;;
esac
