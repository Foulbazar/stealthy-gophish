#!/bin/bash

# Example run:
# wget <location of this script>
# chmod +x gophish_image_setup.sh
# ./gophish_image_setup.sh phisher.com,www.phisher.com


# Check if the required parameters are provided
if [ -z "$1" ] || [ -z "$2" ] || [ -z "$3" ]
then
  echo "Usage: $0 -d <domain_name> -ip <ip_address> -m [complete|partial]"
  exit 1
fi
domain_name=$1
IP=$2
mode=$3

if [ "$mode" = "complete" ]
then
    # Install Prerequisites
    sudo apt -y update; sudo apt -y upgrade
    sudo apt -y install jq build-essential certbot
    sudo apt -y install sqlite3
    sudo apt-get install -qq -y opendkim opendkim-tools
    sudo apt-get install -qq -y mailutils
    
    # Setup the Firewall
    ufw allow from $IP to any port 22
    ufw allow from $IP to any port 3333
    ufw allow 443
    ufw allow 80

    # Install go
    VERSION=$(curl -s https://go.dev/dl/?mode=json | jq -r '.[0].version')
    wget https://go.dev/dl/$VERSION.linux-amd64.tar.gz
    rm -rf /usr/local/go && tar -C /usr/local -xzf $VERSION.linux-amd64.tar.gz
    echo "export PATH=/usr/local/go/bin:${PATH}" | sudo tee /etc/profile.d/go.sh
    source /etc/profile.d/go.sh

    installPath=/opt/gophish
    cd /opt/

    # Install gophish
    git clone https://github.com/Foulbazar/stealthy-gophish.git
    cd gophish

    # We regenerate a rid
    rid=$(cat /dev/urandom | LC_ALL=C tr -dc 'a-z0-9' | fold -w 7 | head -n 1)
    sed -i '' "s/const RecipientParameter = \"rid\"/const RecipientParameter = \"$rid\"/g" models/campaign.go
    go build
    sed -i 's!127.0.0.1!0.0.0.0!g' gophish/config.json

    # Automate the launch of the service
    echo "
        [Unit]
        Description=Gophish Server
        After=network.target
        StartLimitIntervalSec=0 
        [Service]
        Type=simple
        User=ubuntu
        WorkingDirectory=$installpath
        ExecStart=$installpath/gophish
        [Install]
        WantedBy=multi-user.target
    " > /etc/systemd/system/gophish.service
    systemctl daemon-reload
    systemctl start gophish
    systemctl start gophish.service
    systemctl status gophish.service

    # Add the domain name 
    hostname $domain_name 
    echo "$domain_name" > /etc/hostname  
    echo "127.0.1.1 $domain_name" >> /etc/hosts

    # Change the hostname
    hostnamectl set-hostname $domain_name
    hostnamectl
    hostnamectl set-hostname $domain_name --pretty
    hostnamectl ##Pour confirmer les changements
fi

if [ "$mode" = "partial" ]
then
    systemctl stop gophish.service
    systemctl stop nginx
fi










# Generate SSL certificate
certbot certonly --expand -d $HOSTS -n --standalone --agree-tos --email info@onvio.nl

unset -v latest
for file in /etc/letsencrypt/live/*; do
  [[ $file =~ README ]] && continue
  [[ $file -nt $letsencryptPath ]] && letsencryptPath=$file
done

# Create config
echo "{
        \"admin_server\": {
                \"listen_url\": \"0.0.0.0:3333\",
                \"use_tls\": true,
                \"cert_path\": \"$letsencryptPath/fullchain.pem\",
                \"key_path\": \"$letsencryptPath/privkey.pem\"
        },
        \"phish_server\": {
                \"listen_url\": \"0.0.0.0:443\",
                \"use_tls\": true,
                \"cert_path\": \"$letsencryptPath/fullchain.pem\",
                \"key_path\": \"$letsencryptPath/privkey.pem\"
        },
        \"db_name\": \"sqlite3\",
        \"db_path\": \"gophish.db\",
        \"migrations_prefix\": \"db/db_\",
        \"contact_address\": \"\",
        \"logging\": {
                \"filename\": \"\"
        }
}" > $installPath/config.json