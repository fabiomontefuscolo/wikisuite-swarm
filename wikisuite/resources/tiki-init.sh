#!/bin/bash
set -x

while ! php -r "exit(@fsockopen('${TIKI_DB_HOST}', 3306) ? 0 : 1);";
do
    echo "Waiting for database connection" >&2;
    sleep 5;
done

php /var/www/html/console.php database:install
php /var/www/html/console.php database:update

tee /var/www/conf.d/tikiwiki-ini.php <<EOF
<?php
\$system_configuration_file       = dirname(__FILE__) . '/tikiwiki.ini';
\$system_configuration_identifier = 'tikiwiki';
EOF

tee /var/www/conf.d/tikiwiki.ini <<EOF
[tikiwiki]
preference.xmpp_auth_method=oauth
preference.xmpp_feature=y
preference.xmpp_server_host=${OF_PROP_FQDN}
preference.xmpp_server_http_bind=https://${OF_PROP_FQDN}/http-bind/
preference.xmpp_muc_component_domain=${OF_PROP_XMPP_DOMAIN}
preference.auth_token_access=y
preference.login_http_basic = always
preference.feature_file_galleries_batch = y
preference.fgal_use_db = n
preference.gal_use_db = n
preference.t_use_db = n
preference.uf_use_db = n
preference.w_use_db = n
EOF

while read preference;
do
    data_dir="/var/www/data/${preference}/"
    mkdir -p "$data_dir"
    chown www-data:www-data "$data_dir"
    echo "preference.${preference} = ${data_dir}" >> /var/www/conf.d/tikiwiki.ini
done <<EOF
fgal_batch_dir
fgal_use_dir
gal_use_dir
t_use_dir
uf_use_dir
w_use_dir
EOF

php -d error_reporting=E_ALL -d display_errors=1 <<EOF
<?php

\$name = 'ConverseJS OAuth Client';
\$client_id = 'org.tiki.rtc.internal-conversejs-id';
\$client_secret = '${TIKI_OF_SECRET_KEY}';
\$redirect_uri = 'https://${OF_PROP_XMPP_DOMAIN}/lib/xmpp/html/redirect.html';

\$sql = "INSERT INTO tiki_oauthserver_clients (name, client_id, client_secret, redirect_uri)"
    . " VALUES ('\$name', '\$client_id', '\$client_secret', '\$redirect_uri')"
    . " ON DUPLICATE KEY UPDATE client_secret='\$client_secret'"
    . ";";

\$mysqli = new mysqli('${TIKI_DB_HOST}', '${TIKI_DB_USER}', '${TIKI_DB_PASS}', '${TIKI_DB_NAME}');
! \$mysqli->connect_errno && \$mysqli->query(\$sql);
EOF
