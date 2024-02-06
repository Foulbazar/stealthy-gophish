#!/bin/bash

# Example run:
# wget <location of this script>
# chmod +x gophish_image_setup.sh
# ./gophish_image_setup.sh phisher.com,www.phisher.com

# Check if the correct number of arguments are provided
if [ "$#" -lt 2 ]; then
    echo "Usage: $0 {setup|update} [domain_name] [ip|new_domain]"
    echo "       $0 setup <domain_name> <ip|new_domain>"
    echo "       $0 update <old_domain> <new_domain>"
    exit 1
fi
# Set variables based on the first argument
if [ "$1" = "setup" ]; then
    MODE="setup"
    domain_name="$2"
    IP="$3"

    # Install Prerequisites
    sudo apt -y update; sudo apt -y upgrade
    sudo apt -y install jq build-essential certbot
    sudo apt -y install sqlite3
    sudo apt -y install snap
    sudo apt-get install -qq -y opendkim opendkim-tools
    sudo apt-get install -qq -y mailutils
    
    # Setup the Firewall
    sudo ufw default deny incoming   
    sudo ufw default allow ongoing
    sudo ufw allow from $IP to any port 22
    sudo ufw allow from $IP to any port 3333
    sudo ufw allow 443
    sudo ufw allow 80
    sudo ufw enable

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

    # Install postfix
    sudo apt-get install -y postfix
    cd /etc/postfix/main.cf

    # Modify the config files /etc/postfix/generic
    current_domain=$(grep '^myhostname' /etc/postfix/main.cf | awk '{ print $2 }')
    sudo sed -i "s/$current_domain/$domain_name/g" /etc/postfix/generic

    # Modify the /etc/postfix/main.cf file
    sudo sed -i "s/$current_domain/$domain_name/g" /etc/postfix/main.cf

    # Configure Certificate
    sudo snap install --classic certbot
    sudo ln -s /snap/bin/certbot /usr/bin/certbot
    sudo certbot certonly --standalone -d $domain_name --agree-tos 
    sudo adduser ubuntu certs
    sudo chgrp -R certs /etc/letsencrypt/
    sudo chmod -R g+rx /etc/letsencrypt/
    sudo cat /etc/letsencrypt/live/$domain_name/fullchain.pem  

    # Create config
    echo "{
        \"admin_server\": {
                \"listen_url\": \"0.0.0.0:3333\",
                \"use_tls\": true,
                \"cert_path\": \"/etc/letsencrypt/live/$domain_name/fullchain.pem\",
                \"key_path\": \"/etc/letsencrypt/live/$domain_name/privkey.pem\"
        },
        \"phish_server\": {
                \"listen_url\": \"0.0.0.0:8080\",
                \"use_tls\": true,
                \"cert_path\": \"/etc/letsencrypt/live/$domain_name/fullchain.pem\",
                \"key_path\": \"/etc/letsencrypt/live/$domain_name/privkey.pem\"
        },
        \"db_name\": \"sqlite3\",
        \"db_path\": \"gophish.db\",
        \"migrations_prefix\": \"db/db_\",
        \"contact_address\": \"\",
        \"logging\": {
                \"filename\": \"\"
        }
    }" > $installPath/config.json

    # Configure DKIM
    sudo mkdir -p /etc/opendkim/keys
    sudo chown -R opendkim:opendkim /etc/opendkim
    sudo chmod 744 /etc/opendkim/keys
    sudo mkdir /etc/opendkim/keys/$dommain_name
    sudo opendkim-genkey -b 2048 -d $dommain_name -D /etc/opendkim/keys/$dommain_name -s default -v
    sudo chown opendkim:opendkim /etc/opendkim/keys/$dommain_name/default.private
    private=$(sudo cat /etc/opendkim/keys/$nom_de_domaine/default.txt)
    echo "The private key for DKIM is :
    \$private
    "

    # Configurer the nginx
    sudo apt-get -y install nginx
    echo "
    server {
        listen 443 ssl;
        listen [::]:443;
        server_name    $domain_name ;
        add_header X-Robots-Tag "noindex, nofollow, nosnippet, noarchive";

    if (\$http_user_agent\ ~* (google) ) {
        return 404;
	}
  
    if (\$http_user_agent\ = "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/57.0.2987.133 Safari/537.36"){
        return 404;
	}
    }" > /etc/nginx/sites-enabled/$domain_name.conf

    sudo service nginx reload
    sudo certbot --nginx -d $domain_name
    sudo service nginx reload

    # Restart the services 
    sudo systemctl restart gophish.service
    sudo /usr/sbin/postmap /etc/postfix/generic 
    sudo service postfix restart 

elif [ "$1" = "update" ]; then
    MODE="update"
    old_domain="$2"
    domain_name="$3"
    systemctl stop gophish.service
    systemctl stop nginx
    systemctl stop postfix

    # Add the domain name 
    hostname $domain_name 
    echo "$domain_name" > /etc/hostname  
    echo "127.0.1.1 $domain_name" >> /etc/hosts

    # Change the hostname
    hostnamectl set-hostname $domain_name
    hostnamectl
    hostnamectl set-hostname $domain_name --pretty
    hostnamectl ##Pour confirmer les changements

    # Modify the postfix
    sudo sed -i "s/$old_domain/$domain_name/g" /etc/postfix/generic

    # Modify the /etc/postfix/main.cf file
    sudo sed -i "s/$old_domain/$domain_name/g" /etc/postfix/main.cf
    
    # Generate the certificate
    sudo certbot certonly --standalone -d $domain_name --agree-tos

    # Modify the config file
    echo "{
        \"admin_server\": {
                \"listen_url\": \"0.0.0.0:3333\",
                \"use_tls\": true,
                \"cert_path\": \"/etc/letsencrypt/live/$domain_name/fullchain.pem\",
                \"key_path\": \"/etc/letsencrypt/live/$domain_name/privkey.pem\"
        },
        \"phish_server\": {
                \"listen_url\": \"0.0.0.0:8080\",
                \"use_tls\": true,
                \"cert_path\": \"/etc/letsencrypt/live/$domain_name/fullchain.pem\",
                \"key_path\": \"/etc/letsencrypt/live/$domain_name/privkey.pem\"
        },
        \"db_name\": \"sqlite3\",
        \"db_path\": \"gophish.db\",
        \"migrations_prefix\": \"db/db_\",
        \"contact_address\": \"\",
        \"logging\": {
                \"filename\": \"\"
        }
    }" > /opt/gophish/config.json

    # Modify the DKIM
    sudo mkdir /etc/opendkim/keys/$dommain_name
    sudo opendkim-genkey -b 2048 -d $dommain_name -D /etc/opendkim/keys/$dommain_name -s default -v
    sudo chown opendkim:opendkim /etc/opendkim/keys/$dommain_name/default.private
    private=$(sudo cat /etc/opendkim/keys/$nom_de_domaine/default.txt)
    echo "The private key for DKIM is :
    \$private
    "

    # Modify the nginx conf

    echo "
    server {
        listen 443 ssl;
        listen [::]:443;
        server_name    $domain_name ;
        add_header X-Robots-Tag "noindex, nofollow, nosnippet, noarchive";

    if (\$http_user_agent\ ~* (google) ) {
        return 404;
	}
  
    if (\$http_user_agent\ = "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/57.0.2987.133 Safari/537.36"){
        return 404;
	}
    }" > /etc/nginx/sites-enabled/$domain_name.conf

else
    echo "Invalid mode. Use 'setup' or 'update'"
    echo "Usage: $0 {setup|update} [domain_name|old_domain] [ip|new_domain]"
    echo "       $0 setup <domain_name> <ip|new_domain>"
    echo "       $0 update <old_domain> <new_domain>"
    exit 1
fi
