#!/bin/bash

domain="$1"
psname="$2"
uuid="51be9a06-299f-43b9-b713-1ec5eb76e3d7"
path="3o38nn5h"
aid="64"
bin="xray"

if [ ! "$3" ] ;then
  uuid=$(uuidgen)
  echo "uuid 将会随机生成为 ${uuid} / uuid will be randomly generated to ${uuid}"
else
  uuid="$3"
fi

if [ ! "$4" ] ;then
  path=$(cat /dev/urandom | tr -dc 'a-z0-9' | fold -w 8 | head -n 1)
  echo "ws_path 和 trojan_password 将会随机生成为 ${path} / ws_path and trojan_password will be randomly generated to ${path}"
else
  path="$4"
fi

if [ ! "$5" ] ;then
  aid=$(shuf -i 30-100 -n 1)
  echo "alertId 将会随机生成为 ${aid} / alertId will be randomly generated to ${aid}"
else
  aid="$5"
fi

if [ ! "$6" ] ;then
  bin="xray"
  echo "bin 将默认为 ${bin} / bin will be ${bin} by default"
else
  bin="$6"
fi

xray=true
ntwork="tcp"
sectls="xtls"
desc="xray(VLESS+${ntwork}+${sectls})+caddy2"
trojan=false

if [[ "$bin" == *ray ]]; then
  if [ "$bin" != "xray" ]; then
    xray=false
    ntwork="ws"
    sectls="tls"
    desc="v2ray(vmess+${ntwork}+${sectls})+caddy2"
  else
    aid="0"
  fi
else
  trojan=true
  xray=false
  sectls="tls"
  desc="trojan(${ntwork}+${sectls})+caddy2"
fi

config="/srv/${bin}_config.json"
cp /etc/v2ray/config.json ${config}

caddy_v2ray_ws() {
  cat > /etc/Caddyfile <<'EOF'
{
  order reverse_proxy before header
}
domain {
  log {
    output file ./caddy.log {
      roll_size 10mb
      roll_keep 30
      roll_keep_for 72h
    }
    level  WARN
  }
  tls {
    ciphers TLS_ECDHE_ECDSA_WITH_AES_256_GCM_SHA384 TLS_ECDHE_ECDSA_WITH_AES_128_GCM_SHA256 TLS_ECDHE_ECDSA_WITH_CHACHA20_POLY1305_SHA256
    alpn h2 http/1.1
    on_demand
  }
  @v2ray_ws {
    path /onepath
    header Connection *Upgrade*
    header Upgrade websocket
  }
  reverse_proxy @v2ray_ws unix//dev/shm/vws.sock
  @blocked {
    path *.js *.log *.json /node_modules/*
  }
  respond @blocked 404
  file_server
  header {
    Strict-Transport-Security "max-age=31536000; includeSubDomains; preload"
  }
}
EOF
}

caddy_fallback_shared_momery() {
  cat > /etc/Caddyfile <<'EOF'
{
  servers unix//dev/shm/h1h2c.sock {
    protocol {
      allow_h2c
    }
  }
}
:80 {
  redir https://{host}{uri} permanent
}
:88 {
  bind unix//dev/shm/h1h2c.sock
  log {
    output file ./caddy.log {
      roll_size 10mb
      roll_keep 30
      roll_keep_for 72h
    }
    level  WARN
  }
  @blocked {
    path *.js *.log *.json /node_modules/*
  }
  respond @blocked 404
  file_server
  header {
    Strict-Transport-Security "max-age=31536000; includeSubDomains; preload"
  }
}
EOF
}

caddy_fallback_sock() {
  cat > /etc/Caddyfile <<'EOF'
{
  servers 127.0.0.1:88 {
    protocol {
      allow_h2c
    }
  }
}
:80 {
  redir https://{host}{uri} permanent
}
:88 {
  bind 127.0.0.1
  log {
    output file ./caddy.log {
      roll_size 10mb
      roll_keep 30
      roll_keep_for 72h
    }
    level  WARN
  }
  @blocked {
    path *.js *.log *.json /node_modules/*
  }
  respond @blocked 404
  file_server
  header {
    Strict-Transport-Security "max-age=31536000; includeSubDomains; preload"
  }
}
EOF
}

if $xray; then
  caddy_fallback_shared_momery
elif $trojan; then
  caddy_fallback_sock
else
  caddy_v2ray_ws
fi

sed -i "s/domain/${domain}/" /etc/Caddyfile
sed -i "s/onepath/${path}/" /etc/Caddyfile

v2ray_vmess_ws() {
  cat > ${config} <<'EOF'
{
  "log": {
    "loglevel": "warning",
    "error": "/srv/v2ray_error.log"
  },
  "inbounds": [{
    "listen": "/dev/shm/vws.sock",
    "protocol": "vmess",
    "settings": {
      "clients": [{
        "id": "uuid",
        "alterId": 64
      }],
    "disableInsecureEncryption": true
    },
    "streamSettings": {
      "network": "ws",
      "security": "none",
      "wsSettings": {
        "path": "/onepath"
      }
    },
    "sniffing": {
      "enabled": false,
      "destOverride": [
        "http",
        "tls"
    ]}
  }],
  "routing": {
    "domainStrategy": "IPIfNonMatch",
    "rules": [{
      "type": "field",
      "protocol": [
        "bittorrent"
      ],
      "outboundTag": "blocked"
    }]
  },
  "outbounds": [
    {
    "protocol": "freedom",
      "settings": {}
    },
    {
      "tag": "blocked",
      "protocol": "blackhole",
      "settings": {}
    }
  ]
}
EOF
}

xray_trojan_vless_tcp_ws_tls() {
  cat > ${config} <<'EOF'
{
  "log": {
    "loglevel": "warning",
    "error": "/srv/v2ray_error.log"
  },
  "inbounds": [{
    "port": 443,
    "protocol": "vless",
    "settings": {
      "clients": [{
        "id": "uuid",
        "flow": "xtls-rprx-direct"
      }],
      "decryption": "none",
	  "fallbacks": [{
          "dest": "@trojan-tcp",
          "xver": 0
        },
        {
          "path": "/onepath",
          "dest": "@vless-ws",
          "xver": 0
        }]
    },
    "streamSettings": {
      "network": "tcp",
      "security": "xtls",
      "xtlsSettings": {
          "alpn":[
            "h2",
            "http/1.1"
          ],
          "minVersion": "1.2",
          "preferServerCipherSuites": true,
          "cipherSuites": "TLS_ECDHE_ECDSA_WITH_AES_256_GCM_SHA384:TLS_ECDHE_ECDSA_WITH_AES_128_GCM_SHA256:TLS_ECDHE_ECDSA_WITH_CHACHA20_POLY1305_SHA256",
          "certificates": [{
              "ocspStapling": 3600,
              "certificateFile": "/root/.caddy/acme/acme-v02.api.letsencrypt.org/sites/full_domain/full_domain.crt",
              "keyFile": "/root/.caddy/acme/acme-v02.api.letsencrypt.org/sites/full_domain/full_domain.key"
          }]
      }
    },
    "sniffing": {
      "enabled": false,
      "destOverride": [
        "http",
        "tls"
    ]}
  },
  {
    "listen": "@vless-ws",
    "protocol": "vless",
    "settings": {
      "clients": [
        {
          "id": "uuid"
        }],
      "decryption": "none"
    },
    "streamSettings": {
      "network": "ws",
      "security": "none",
      "wsSettings": {
          "path": "/onepath"
      }
    },
    "sniffing": {
      "enabled": false,
      "destOverride": [
        "http",
        "tls"
    ]}
  },
  {
    "listen": "@trojan-tcp",
    "protocol": "trojan",
    "settings": {
      "clients": [{
            "password":"onepath"
      }],
      "fallbacks": [{
            "dest": "/dev/shm/h1h2c.sock",
            "xver": 0
      }]
    },
    "streamSettings": {
        "network": "tcp",
        "security": "none"
    },
    "sniffing": {
        "enabled": false,
        "destOverride": [
          "http",
          "tls"
    ]}
  }],
  "routing": {
    "domainStrategy": "IPIfNonMatch",
    "rules": [{
      "type": "field",
      "protocol": [
        "bittorrent"
      ],
      "outboundTag": "blocked"
    }]
  },
  "outbounds": [{
    "protocol": "freedom",
      "settings": {}
    },
    {
      "tag": "blocked",
      "protocol": "blackhole",
      "settings": {}
  }]
}
EOF
}

trojan_tcp_tls() {
  cat > ${config} <<'EOF'
{
  "run_type": "server",
  "local_addr": "0.0.0.0",
  "local_port": 443,
  "remote_addr": "127.0.0.1",
  "remote_port": 88,
  "log_level": 2,
  "log_file": "/srv/v2ray_error.log",
  "password": [
    "onepath"
  ],
  "disable_http_check": false,
  "udp_timeout": 60,
  "ssl": {
    "verify_hostname": true,
    "cert": "/root/.caddy/acme/acme-v02.api.letsencrypt.org/sites/full_domain/full_domain.crt",
    "key": "/root/.caddy/acme/acme-v02.api.letsencrypt.org/sites/full_domain/full_domain.key",
    "key_password": "",
    "cipher": "",
    "curves": "",
    "prefer_server_cipher": true,
    "sni": "full_domain",
    "alpn":[
      "h2",
      "http/1.1"
    ],
    "session_ticket": true,
    "reuse_session": true,
    "plain_http_response": "",
    "fallback_addr": "",
    "fallback_port": 0
  },
  "tcp": {
    "no_delay": true,
    "keep_alive": true,
    "prefer_ipv4": false
  },
  "router": {
    "enabled": true,
    "block": [
      "geoip:private"
    ],
    "geoip": "/usr/bin/geoip.dat",
    "geosite": "/usr/bin/geosite.dat"
  },
  "websocket": {
    "enabled": false,
    "path": "/onepath",
    "host": "full_domain"
  },
  "shadowsocks": {
    "enabled": false,
    "method": "AES-128-GCM",
    "password": ""
  },
  "transport_plugin": {
    "enabled": false,
    "type": "plaintext",
    "command": "",
    "option": "",
    "arg": [],
    "env": []
  }
}
EOF
}

if $xray; then
  xray_trojan_vless_tcp_ws_tls
elif $trojan; then
  trojan_tcp_tls
else
  v2ray_vmess_ws
fi

sed -i "s/uuid/${uuid}/" ${config}
sed -i "s/onepath/${path}/" ${config}
sed -i "s/64/${aid}/" ${config}
sed -i "s/v2ray/${bin}/" ${config}
sed -i "s/full_domain/${domain}/g" ${config}

#https://github.com/2dust/v2rayN/wiki/分享链接格式说明(ver-2)
cat > /srv/sebs.js <<'EOF'
{
  "add":"domain",
  "aid":"64",
  "host":"domain",
  "id":"uuid",
  "net":"ntwork",
  "path":"/onepath",
  "port":"443",
  "ps":"sebsclub",
  "tls":"sectls",
  "type":"none",
  "v":"2",
  "sni": "domain"
}
EOF

if [ "$psname" != "" ] && [ "$psname" != "-c" ]; then
  sed -i "s/sebsclub/${psname}/" /srv/sebs.js
  sed -i "s/domain/${domain}/" /srv/sebs.js
  sed -i "s/uuid/${uuid}/" /srv/sebs.js
  sed -i "s/onepath/${path}/" /srv/sebs.js
  sed -i "s/64/${aid}/" /srv/sebs.js
  sed -i "s/ntwork/${ntwork}/" /srv/sebs.js
  sed -i "s/sectls/${sectls}/" /srv/sebs.js
else
  $*
fi

pwd

cp /etc/Caddyfile .

echo "caddy 模块列表 / modules list of caddy"
echo " "
/usr/bin/caddy list-modules
echo " "

nohup /bin/parent caddy run --environ &

echo "caddy Caddyfile 配置详情 / Content of caddy Caddyfile"
echo " "
cat Caddyfile
echo " "

echo "${config} 配置详情 / Content of ${config}"
echo " "
cat ${config}
echo " "

if ! $trojan; then
  node link-qrcode.js
fi

echo " "
echo "当前选择是: ${desc} / Current selection: ${desc}"
if $xray; then
  echo "注意：VLESS 并没有正式的链接和二维码标准，使用前仍需手动修改 / Attention: There is no official standards for VLESS link or QR code, you need modify it manually before use"
fi

if $xray; then
  /usr/bin/xray -config ${config}
elif $trojan; then
  /usr/bin/trojan-go -config ${config}
else
  /usr/bin/v2ray -config ${config}
fi
