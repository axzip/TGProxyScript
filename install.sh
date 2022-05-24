#!/bin/bash

exiterr()  { echo -e "\e[1;31mError: $1 \e[0m" >&2; exit 1; }
echogree() { echo -e "\e[1;32m$1 \e[0m" >&2;}
base_dir=$(pwd)

check_domain() {
  FQDN_REGEX='^(?=^.{3,255}$)[a-zA-Z0-9][-a-zA-Z0-9]{0,62}(\.[a-zA-Z0-9][-a-zA-Z0-9]{0,62})+$'
   printf '%s' "$1" | tr -d '\n' | grep -Pq "$FQDN_REGEX"
}

check_port() {
  FQDN_REGEX='^([0-9]|[1-9]\d{1,3}|[1-5]\d{4}|6[0-4]\d{3}|65[0-4]\d{2}|655[0-2]\d|6553[0-5])$'
   printf '%s' "$1" | tr -d '\n' | grep -Pq "$FQDN_REGEX"
}
rm -rf MTProxy
read -p "Enter the domain name for fakeTLS: " domain
until check_domain "$domain"; do
    echo "Invalid domain."
    read -p "Enter the domain name for fakeTLS: " domain
done

read -p "Ennter port:" port
until check_port "$port"; do
    echo "Invalid port."
    read -p "Ennter port:" port
done

(set -x
apt-get -yqq install git curl build-essential libssl-dev zlib1g-dev net-tools >/dev/null) || exiterr "apt install failed!"
git clone https://github.com/TelegramMessenger/MTProxy || exiterr "git clone failed!"
echogree "compiling..."
cd $base_dir/MTProxy
sed -i 's/^CFLAGS.*/\0 -fcommon/g' Makefile
make -j$(nproc) >/dev/null 2>&1;
if [ -x objs/bin/mtproto-proxy ];then
    mv objs/bin/mtproto-proxy .
    ls | grep -v mtproto-proxy | xargs rm -rf
    chmod +x ./mtproto-proxy
    curl -s https://core.telegram.org/getProxySecret -o proxy-secret
    curl -s https://core.telegram.org/getProxyConfig -o proxy-multi.conf
else
    exiterr "make faile!"
fi
insideIp=`ifconfig -a|grep inet|grep -v 127.0.0.1|grep -v inet6|awk '{print $2}'|tr -d "addr:"​`
outsideIp=$(wget -t 3 -T 15 -qO- http://ipv4.icanhazip.com)

if [ insideIp != outsideIp ];then
    natInfo=$(echo "--nat-info $insideIp:$outsideIp")
fi


secret=`head -c 16 /dev/urandom | xxd -ps`
rm -rf crontabtmp
cat > crontabtmp  <<EOF
0 0 * * * curl -s https://core.telegram.org/getProxyConfig -o $base_dir/MTProxy/proxy-multi.conf
EOF
crontab ./crontabtmp
rm ./crontabtmp
systemctl restart cron
rm -rf /lib/systemd/system/MTProxy.service
cat > /lib/systemd/system/MTProxy.service <<EOF
[Unit]
Description=mtproxy
After=network.target

[Service]
Type=simple
PIDFile=/run/mtproxy.pid
WorkingDirectory=$base_dir/MTProxy
ExecStart=$base_dir/MTProxy/mtproto-proxy -u nobody -H $port $natInfo -S $secret --aes-pwd $base_dir/MTProxy/proxy-secret $base_dir/MTProxy/proxy-multi.conf -D "$domain" --cpu-threads 16 --io-threads 16
ExecReload=/bin/sh -c "/bin/kill -s HUP \$(/bin/cat /run/mtproxy.pid)"
ExecStop=/bin/sh -c "/bin/kill -s TERM \$(/bin/cat /run/mtproxy.pid)"

[Install]
WantedBy=multi-user.target
EOF
systemctl daemon-reload
systemctl enable MTProxy.service
systemctl restart MTProxy.service
echo ""
echo -e "\e[1;32m"
printf "%-5s\n" Info:
printf "%-5s %-10s\n" 'Client secret:' ee$secret$(printf "$domain" | xxd -ps)
printf "%-5s %-10s\n" IP: $outsideIp
printf "%-5s %-10s\n" Port: $port
printf "%-5s %-5s\n" Link: https://t.me/proxy?server=$outsideIp\&port\=$port\&secret\=ee$secret$(printf "$domain" | xxd -ps)
echo -e "\e[0m"
