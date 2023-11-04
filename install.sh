#!/bin/bash

clear
echo "Hi. 欢迎使用我写的Reality+Vision脚本"
echo "有问题联系root@sitao.org"
echo "适用于Debian和Ubuntu系统,暂不支持centos"
echo "系统尽量干净(无nginx)"
echo
echo "实现：用nginx 建站监听127.0.0.1:16969，然后reality偷127.0.0.1:16969，fallback到127.0.0.1:16969,再配合vision解决 tls in tls"
echo
read -p "偷自己的域名吗？[y/n](默认y):" check

if [ -z "$check" ] || [ "$check" = "y" ]
  then
         local_web=1
         read -p "请输入你的域名:" domain
	 if [ -z $domain ]
   		then exit
         fi
         
  else
         local_web=0
         read -p "请输入你想偷的域名:" domain
	 if [ -z $domain ]
   		then exit
         fi
fi

read -p "输入节点端口[默认20230]:" port
            if [ -z $port ]
                then port=20230
            fi

read -p "要屏蔽回国流量吗?[y/n](默认n):" block
 if [ -z $block ]
                then block=n
 fi

clear
echo "OK! 一切已准备就绪，按回车键开始安装!"
read

#安装Xray，版本：1.8.4
echo "安装Xray，版本：1.8.4"
mkdir /xray
chmod 777 /xray
wget https://github.com/XTLS/Xray-core/releases/download/v1.8.4/Xray-linux-64.zip
apt-get install unzip -y
unzip Xray-linux-64.zip -d /xray
cp /xray/xray /usr/bin/xray
id=`xray uuid`
output=$(xray x25519)
# 提取 Private key 和 Public key
Privatekey=$(echo "$output" | awk '/Private key:/ {print $3}')
Publickey=$(echo "$output" | awk '/Public key:/ {print $3}')

cat << EOF > /etc/systemd/system/xray.service
[Unit]
Description=Xray Service
Documentation=https://github.com/xtls
After=network.target nss-lookup.target
[Service]
User=nobody
CapabilityBoundingSet=CAP_NET_ADMIN CAP_NET_BIND_SERVICE
AmbientCapabilities=CAP_NET_ADMIN CAP_NET_BIND_SERVICE
NoNewPrivileges=true
ExecStart=/xray/xray run -config /xray/config.json
Restart=on-failure
RestartPreventExitStatus=23
LimitNPROC=10000
LimitNOFILE=1000000
[Install]
WantedBy=multi-user.target
EOF

#不屏蔽回国流量
if [ "$block" = "n" ]
then
cat << EOF > /xray/config.json
{
	"inbounds": [{
		"listen": "0.0.0.0",
		"port":  $port,
		"protocol": "vless",
		"settings": {
			"clients": [{
				"id": "${id}",
				"flow": "xtls-rprx-vision"
			}],
			"decryption": "none"
		},
		"streamSettings": {
			"network": "tcp",
			"security": "reality",
			"realitySettings": {
				"show": false,
				"dest": "16969",
				"xver": 0,
				"serverNames": [
					"$domain"
			
				],
				"privateKey": "$Privatekey",

				"shortIds": [
					"",
					"1153456789abcdef"
				]
			}
		}
	}],
	"outbounds": [{
			"protocol": "freedom",
			"tag": "direct"
		}
	]
}
EOF

else 
#屏蔽回国流量
cat << EOF > /xray/config.json
{
"routing": {
        "domainStrategy": "IPIfNonMatch",
        "rules": [
            {
                "type": "field",
                "ip": [
                    "geoip:cn"
                ],
                "outboundTag": "block"
            }
        ]
    },
	"inbounds": [{
		"listen": "0.0.0.0",
		"port":  $port,
		"protocol": "vless",
		"settings": {
			"clients": [{
				"id": "${id}",
				"flow": "xtls-rprx-vision"
			}],
			"decryption": "none"
		},
		"streamSettings": {
			"network": "tcp",
			"security": "reality",
			"realitySettings": {
				"show": false,
				"dest": "16969",
				"xver": 0,
				"serverNames": [
					"$domain"
			
				],
				"privateKey": "$Privatekey",

				"shortIds": [
					"",
					"1153456789abcdef"
				]
			}
		}
	}],
	"outbounds": [{
			"protocol": "freedom",
			"tag": "direct"
		},
		{
			"protocol": "blackhole",
			"tag": "block"
		}
	]
}
EOF
fi

#偷自己
if [ "$local_web" = "1" ]
then
         mkdir /web
         wget https://raw.githubusercontent.com/cnsitao/Trojan-gRPC-tls/main/web/game.tar.gz
         tar -zvxf game.tar.gz -C /web

#申请证书
echo "开始申请证书"
apt update
mkdir -p /xray/tls
chmod 777 /xray/tls
apt install cron curl socat -y
curl https://get.acme.sh | sh
ln -s  /root/.acme.sh/acme.sh /usr/local/bin/acme.sh
source ~/.bashrc
acme.sh --set-default-ca --server letsencrypt
acme.sh --issue -d $domain --standalone -k ec-256 --force
acme.sh --installcert -d $domain --ecc  --key-file   /xray/tls/server.key   --fullchain-file /xray/tls/server.crt
acme.sh --upgrade --auto-upgrade

if `test -s /xray/tls/server.crt` 
  then 
        echo -e "证书申请成功!\n"
        echo -n "证书路径:"
        echo
        echo -e "/xray/tls/server.crt"
        echo -e "/xray/tls/server.key\n"
   else
		rm -rf /xray
		rm /etc/systemd/system/xray.service
		systemctl daemon-reload
		rm -rf ~/game.tar.gz Xray-linux-64.zip
		echo "证书安装失败！请检查原因！有问题联系root@sitao.org"
        exit
fi

#安装nginx
#安装依赖
apt install build-essential libpcre3 libpcre3-dev zlib1g-dev openssl libssl-dev -y
#下载Nginx源码
wget https://nginx.org/download/nginx-1.25.2.tar.gz
tar -xzvf nginx-1.25.2.tar.gz
cd nginx-1.25.2
./configure \
--prefix=/usr/local/nginx \
--user=nginx \
--group=nginx \
--sbin-path=/usr/local/nginx/sbin/nginx \
--conf-path=/usr/local/nginx/nginx.conf \
--error-log-path=/var/log/nginx/error.log \
--http-log-path=/var/log/nginx/access.log \
--with-file-aio \
--with-threads \
--with-http_addition_module \
--with-http_auth_request_module \
--with-http_dav_module \
--with-http_flv_module \
--with-http_gunzip_module \
--with-http_gzip_static_module \
--with-http_mp4_module \
--with-http_random_index_module \
--with-http_realip_module \
--with-http_secure_link_module \
--with-http_slice_module \
--with-http_ssl_module \
--with-http_stub_status_module \
--with-http_sub_module \
--with-http_v2_module \
--with-mail_ssl_module \
--with-stream \
--with-stream_realip_module \
--with-stream_ssl_module \
--with-stream_ssl_preread_module
echo "开始编译安装nginx"
make -j$(nproc) && make install
/usr/sbin/groupadd nginx
/usr/sbin/useradd -g nginx nginx
cat << EOF > /etc/systemd/system/nginx.service
[Unit]
Description=nginx
After=network.target
  
[Service]
Type=forking
ExecStart=/usr/local/nginx/sbin/nginx
ExecReload=/usr/local/nginx/sbin/nginx -s reload
ExecStop=/usr/local/nginx/sbin/nginx -s quit
PrivateTmp=true
  
[Install]
WantedBy=multi-user.target
EOF
cp /usr/local/nginx/sbin/nginx /usr/bin/nginx
systemctl enable nginx
systemctl start nginx
mkdir -p /usr/local/nginx/conf.d
sed -i '/default_type  application\/octet-stream;/a\    include \/usr\/local\/nginx\/conf.d\/\*.conf\;' /usr/local/nginx/nginx.conf
echo
nginx -v
echo "Nginx安装成功!"
cat << EOF > /usr/local/nginx/conf.d/reality.conf
server {
    listen 127.0.0.1:16969 ssl;
    http2 on;
    server_name $domain;
    error_page 497 https://\$host:16969\$request_uri;

    location / {
              root /web;
              index index.html;
    }
    ssl_certificate /xray/tls/server.crt;
    ssl_certificate_key /xray/tls/server.key;
    ssl_stapling on;
    ssl_stapling_verify on;
    resolver 8.8.8.8 8.8.4.4 valid=300s;
    resolver_timeout 5s;
    ssl_session_cache shared:SSL:10m;
    ssl_session_timeout 5m;
    ssl_protocols TLSv1.3;
    ssl_ciphers "ECDHE-RSA-AES256-GCM-SHA384:ECDHE-RSA-AES128-GCM-SHA256:DHE-RSA-AES256-GCM-SHA384:DHE-RSA-AES128-GCM-SHA256:ECDHE-RSA-AES256-SHA384:ECDHE-RSA-AES128-SHA256:ECDHE-RSA-AES256-SHA:ECDHE-RSA-AES128-SHA:DHE-RSA-AES256-SHA256:DHE-RSA-AES128-SHA256:DHE-RSA-AES256-SHA:DHE-RSA-AES128-SHA:ECDHE-RSA-DES-CBC3-SHA:EDH-RSA-DES-CBC3-SHA:AES256-GCM-SHA384:AES128-GCM-SHA256:AES256-SHA256:AES128-SHA256:AES256-SHA:AES128-SHA:DES-CBC3-SHA:HIGH:!aNULL:!eNULL:!EXPORT:!DES:!MD5:!PSK:!RC4";
    ssl_prefer_server_ciphers on;
}
EOF
systemctl enable nginx
systemctl restart nginx

#偷别人
else 
echo "无需安装nginx"
echo "即将完成安装..."
fi

systemctl enable xray.service
systemctl start xray.service

cat << EOF > /xray/node
ip: `curl ip.sb -4`
端口: $port
用户id: $id
流控: xtls-rprx-vision
加密方式: none
传输协议: TCP
伪装类型: none
传输层安全(TLS): reality
SNI:$domain
Fingerprint: chrome
Publickey:$Publickey
ShortId: 1153456789abcdef (客户端可用的 shortId 列表，可用于区分不同的客户端，可留空，想自定义需自行修改配置文件/xray/config然后重启xray)
SpiderX ：留空
EOF
echo $Privatekey > /xray/Privatekey
apt install jq -y
curl  https://raw.githubusercontent.com/LSitao/Xray_Reality-Vision/main/daiyu_menu > /xray/daiyu.sh
cp /xray/daiyu.sh /usr/bin/daiyu
chmod 777 /usr/bin/daiyu
rm -rf ~/Xray-linux-64.zip  game.tar.gz  nginx-1.25.2  nginx-1.25.2.tar.gz
clear
echo "安装完成！"
echo "以下的信息能帮助你在客户端添加该节点"
echo 
cat /xray/node
echo
echo
echo "之后可以执行cat /xray/node 命令查看节点信息，cat /xray/Privatekey查看私钥"
echo
echo "vless://${id}@`curl ip.sb -4`:$port?encryption=none&flow=xtls-rprx-vision&security=reality&sni=$domain&fp=chrome&pbk=$Publickey&sid=1153456789abcdef&type=tcp&headerType=none#Reality+Vision" > /xray/example_node
echo
echo "你也可以直接使用下面的示例链接"
cat /xray/example_node
echo
echo "输入daiyu可调出菜单"
echo 
echo
echo "感谢使用"
