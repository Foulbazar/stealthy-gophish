    #!/bin/bash

    # Example run:
    # wget <location of this script>
    # chmod +x gophish_image_setup.sh
    # ./gophish_image_setup.sh phisher.com,www.phisher.com

    # Check if the correct number of arguments are provided
    if [ "$#" -lt 2 ] 
    then
        echo "Usage: $0 {setup|update} [domain_name] [ip|new_domain]"
        echo "       $0 setup <domain_name> <ip|new_domain>"
        echo "       $0 update <old_domain> <new_domain>"
        exit 1
    fi
    # Set variables based on the first argument
    if [ "$1" = "setup" ]
    then
        MODE="setup"
        domain_name="$2"
        IP="$3"
        USER=$(whoami)
        GROUP=$(id -gn)
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
        sudo wget https://go.dev/dl/$VERSION.linux-amd64.tar.gz
        sudo rm -rf /usr/local/go && sudo tar -C /usr/local -xzf $VERSION.linux-amd64.tar.gz
        echo "export PATH=/usr/local/go/bin:${PATH}" | sudo tee /etc/profile.d/go.sh
        sudo sh /etc/profile.d/go.sh

        installPath=/home/$USER
        cd $installPath

        # Install gophish
        git clone https://github.com/Foulbazar/stealthy-gophish.git
        cd stealthy-gophish

        # We regenerate a rid
        # rid=$(cat /dev/urandom | LC_ALL=C tr -dc 'a-z0-9' | fold -w 7 | head -n 1)
        # sed -i '' "s/const RecipientParameter = \"rid\"/const RecipientParameter = \"$rid\"/g" $installPath/stealthy-gophish/models/campaign.go          Pas besoin car déjà changer
        go build
        # sed -i 's!127.0.0.1!0.0.0.0!g' $installPath/stealthy-gophish/config.json

        # Automate the launch of the service
        sudo touch /etc/systemd/system/gophish.service # problem ici
        sudo sh -c "echo '[Unit]
        Description=Gophish Server
        After=network.target
        StartLimitIntervalSec=0 
        [Service]
        Type=simple
        User=$USER
        WorkingDirectory=$installPath
        ExecStart=$installPath/stealthy-gophish/gophish
        [Install]
        WantedBy=multi-user.target' > /etc/systemd/system/gophish.service"  
        

        # Configure Certificate
        sudo snap install --classic certbot
        sudo apt -y install python3-certbot-nginx
        sudo ln -s /snap/bin/certbot /usr/bin/certbot
        sudo certbot certonly --standalone -d $domain_name --register-unsafely-without-email --agree-tos 
        sudo certbot certonly -d passwordupdate.support --manual --preferred-challenges dns
        # Verify
        sudo chgrp -R $GROUP /etc/letsencrypt/
        sudo chmod -R g+rx /etc/letsencrypt/
        sudo cat /etc/letsencrypt/live/$domain_name/fullchain.pem  

        # Add the domain name 
        hostname $domain_name
        sudo sh -c "echo '$domain_name' > /etc/hostname" 
        sudo sh -c "echo '127.0.1.1 $domain_name' >> /etc/hosts"

        # Change the hostname
        hostnamectl set-hostname $domain_name
        hostnamectl
        hostnamectl set-hostname $domain_name --pretty
        hostnamectl ##Pour confirmer les changements

        # Install postfix
        sudo apt-get install -y postfix

        # Modifier le fichier /etc/postfix/main.cf
        sudo sh -c "echo 'smtpd_banner = \$myhostname ESMTP \$mail_name (Debian/GNU)
        biff = no
        append_dot_mydomain = no
        readme_directory = no
        smtpd_tls_cert_file=/etc/letsencrypt/live/$domain_name/fullchain.pem
        smtpd_tls_key_file=/etc/letsencrypt/live/$domain_nam/privkey.pem
        smtpd_tls_security_level = may
        smtp_tls_security_level = encrypt
        smtpd_tls_session_cache_database = btree:\${data_directory}/smtpd_scache
        smtp_tls_session_cache_database = btree:\${data_directory}/smtp_scache
        smtpd_relay_restrictions = permit_mynetworks permit_sasl_authenticated defer_unauth_destination
        myhostname = \${primary_domain}
        alias_maps = hash:/etc/aliases
        alias_database = hash:/etc/aliases
        myorigin = /etc/mailname
        mydestination = \${primary_domain}, localhost.com, , localhost
        relayhost =
        mynetworks = 127.0.0.0/8 [::ffff:127.0.0.0]/104 [::1]/128 \${relay_ip}
        mailbox_command = procmail -a "\$EXTENSION"
        mailbox_size_limit = 0
        recipient_delimiter = +
        inet_interfaces = all
        inet_protocols = ipv4
        milter_default_action = accept
        milter_protocol = 6
        smtpd_milters = inet:12301,inet:localhost:54321
        non_smtpd_milters = inet:12301,inet:localhost:54321' > /etc/postfix/main.cf"
        cat /etc/postfix/main.cf

        # Modify the config files /etc/postfix/generic
        current_domain=$(grep '^myhostname' /etc/postfix/main.cf | awk '{ print $2 }')
        #sudo sed -i "s/$current_domain/$domain_name/g" /etc/postfix/generic            #MARCHE PAS

        # Modify the /etc/postfix/main.cf file
        sudo sed -i "s/$current_domain/$domain_name/g" /etc/postfix/main.cf

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
        }" > $installPath/stealthy-gophish/config.json

        # Configure DKIM
        sudo mkdir -p /etc/opendkim/keys
        sudo chown -R opendkim:opendkim /etc/opendkim
        sudo chmod 744 /etc/opendkim/keys
        sudo mkdir /etc/opendkim/keys/$domain_name
        sudo opendkim-genkey -b 2048 -d $domain_name -D /etc/opendkim/keys/$domain_name -s default -v
        sudo chown opendkim:opendkim /etc/opendkim/keys/$domain_name/default.private
        private=$(sudo cat /etc/opendkim/keys/$domain_name/default.txt)
        echo "The private key for DKIM is :
        $private
        "

        sudo sh -c "echo '*@$domain_name    default._domainkey.$domain_name
        *@*.$domain_name    default._domainkey.$domain_name' > /etc/opendkim/signing.table"

        sudo sh -c "echo 'default._domainkey.$domain_name     $domain_name:default:/etc/opendkim/keys/$domain_name/default.private' > /etc/opendkim/key.table"

        sudo sh -c "echo '127.0.0.1
        $domain_name
        localhost' > /etc/opendkim/signing.table"
        
        sudo systemctl restart opendkim

        # Configurer the nginx
        sudo apt-get -y install nginx   ## PLEIN DE SOUCIS A VOIR
        sudo sh -c "echo 'server {
            listen 443 ssl;
            listen [::]:443;
            server_name    $domain_name;

            #Add a blocklist
            include /etc/nginx/cond.d/blocklist.conf;

            # Add the SSL certificate and key directives
            ssl_certificate /etc/letsencrypt/live/$domain_name/fullchain.pem;
            ssl_certificate_key /etc/letsencrypt/live/$domain_name/privkey.pem;
            #Add header
            add_header X-Robots-Tag \"noindex, nofollow, nosnippet, noarchive\";

        if (\$http_user_agent ~* (google) ) {
            return 404;
        }

        if (\$http_user_agent = \"Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/57.0.2987.133 Safari/537.36\"){
            return 404;
        }

        location = /robots.txt {
            add_header Content-Type text/plain;
            return 200 \"User-agent: *\nDisallow: / \";
        }
        }' > /etc/nginx/sites-enabled/$domain_name.conf" # Permision denied
        
        #sudo certbot --nginx -d $domain_name
        sudo service nginx reload

        # Restart the services 
        sudo systemctl start gophish
        sudo systemctl start gophish.service
        sudo systemctl status gophish.service            # PB EGALEMENT ICI SErvIce PAS LANCER
        sudo systemctl daemon-reload #marche pas access denied
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
        sudo sh -c "echo '$domain_name' > /etc/hostname"
        sudo sed -i "s/$old_domain/$domain_name/g" /etc/hosts
        

        # Change the hostname
        hostnamectl set-hostname $domain_name
        hostnamectl
        hostnamectl set-hostname $domain_name --pretty
        hostnamectl ##Pour confirmer les changements

        # Modify the postfix
        sudo sed -i "s/$old_domain/$domain_name/g" /etc/postfix/generic

        # Modify the /etc/postfix/main.cf file
        sudo sed -i "s/$old_domain/$domain_name/g" /etc/postfix/main.cf
        
        # Delete old certificate:
        sudo certbot delete --cert-name $old_domain

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
        }" > $installPath/stealthy-gophish/config.json

        # Modify the DKIM
        sudo mkdir /etc/opendkim/keys/$domain_name
        sudo opendkim-genkey -b 2048 -d $domain_name -D /etc/opendkim/keys/$domain_name -s default -v
        sudo chown opendkim:opendkim /etc/opendkim/keys/$domain_name/default.private
        private=$(sudo cat /etc/opendkim/keys/$domain_name/default.txt)
        echo "The private key for DKIM is :
        \$private
        "
        sudo sed -i "s/$old_domain/$domain_name/g" /etc/opendkim/signing.table
        sudo sed -i "s/$old_domain/$domain_name/g" /etc/opendkim/key.table
        sudo sed -i "s/$old_domain/$domain_name/g" /etc/opendkim/signing.table
        sudo systemctl restart opendkim

        # Modify the nginx conf

        echo "
        server {
            listen 443 ssl;
            listen [::]:443;
            server_name    $domain_name ;
            add_header X-Robots-Tag "noindex, nofollow, nosnippet, noarchive";

        if ($http_user_agent ~* (google) ) {
            return 404;
        }
    
        if ($http_user_agent = \"Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/57.0.2987.133 Safari/537.36\"){
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
