<?php

$db_host = getenv('TIKI_DB_HOST') ?: 'db';
$db_port = getenv('TIKI_DB_PORT') ?: 3306;
$db_user = getenv('TIKI_DB_USER') ?: 'tiki';
$db_pass = getenv('TIKI_DB_PASS') ?: 'wiki';
$db_name = getenv('TIKI_DB_NAME') ?: 'tikiwiki';

/* ConverseJS integration */
$of_fqdn = getenv('OF_PROP_FQDN');
$of_domain = getenv('OF_PROP_XMPP_DOMAIN');
$converse_name = 'ConverseJS OAuth Client';
$converse_id = 'org.tiki.rtc.internal-conversejs-id';   
$converse_secret = getenv('TIKI_OF_SECRET_KEY');
$converse_redirect = "https://${of_domain}/lib/xmpp/html/redirect.html";

$mysqli = null;
$mysqli = new mysqli($db_host, $db_user, $db_pass, $db_name);

while ($mysqli->connect_errno !== 0) {
    fwrite(STDERR, "Waiting MySQL to be available\n");
    sleep(5);
    $mysqli = new mysqli($db_host, $db_user, $db_pass, $db_name);
}

$return = 0;
$content = system(PHP_BINARY . ' /var/www/html/console.php database:install', $return);
fwrite($return ? STDERR : STDOUT, $content . PHP_EOL);

$return = 0;
$content = system(PHP_BINARY . ' /var/www/html/console.php database:update', $return);
fwrite($return ? STDERR : STDOUT, $content . PHP_EOL);

$content = <<<EOL
<?php
\$system_configuration_file       = dirname(__FILE__) . '/tikiwiki.ini';
\$system_configuration_identifier = 'tikiwiki';
EOL;
file_put_contents('/var/www/conf.d/tikiwiki-ini.php', $content);

$content = <<<EOL
[tikiwiki]
preference.xmpp_auth_method=oauth
preference.xmpp_feature=y
preference.xmpp_server_host=${of_fqdn}
preference.xmpp_server_http_bind=https://${of_fqdn}/http-bind/
preference.xmpp_muc_component_domain=${of_domain}
preference.auth_token_access=y
preference.login_http_basic = always
preference.feature_file_galleries_batch = y
preference.fgal_use_db = n
preference.gal_use_db = n
preference.t_use_db = n
preference.uf_use_db = n
preference.w_use_db = n
preference.fgal_batch_dir = /var/www/data/fgal_batch_dir
preference.fgal_use_dir = /var/www/data/fgal_use_dir
preference.gal_use_dir = /var/www/data/gal_use_dir
preference.t_use_dir = /var/www/data/t_use_dir
preference.uf_use_dir = /var/www/data/uf_use_dir
preference.w_use_dir = /var/www/data/w_use_dir
EOL;

mkdir('/var/www/data/fgal_batch_dir', 0775, true);
mkdir('/var/www/data/fgal_use_dir', 0775, true);
mkdir('/var/www/data/gal_use_dir', 0775, true);
mkdir('/var/www/data/t_use_dir', 0775, true);
mkdir('/var/www/data/uf_use_dir', 0775, true);
mkdir('/var/www/data/w_use_dir', 0775, true);
system('chown -R www-data:www-data /var/www/data');
file_put_contents('/var/www/conf.d/tikiwiki.ini', $content);

/* Converse secret TOKEN */
$sql = <<<SQL
INSERT INTO tiki_oauthserver_clients (name, client_id, client_secret, redirect_uri)
VALUES ('$converse_name', '$converse_id', '$converse_secret', '$converse_redirect')
ON DUPLICATE KEY UPDATE client_secret='$converse_secret'
SQL;
$content = $mysqli->query($sql);

/* Automatically create cypht config to new users */
$sql = <<<SQL
DELIMITER //
CREATE OR REPLACE TRIGGER create_cypht_conf
  AFTER INSERT ON users_users
  FOR EACH ROW
  BEGIN
    SET @user = NEW.login;
    SET @pass = LEFT(UUID(), 10);
    INSERT INTO tiki_user_preferences VALUES(@user, 'cypht_user_config', CONCAT('{"smtp_servers":[{"name":"postfix","server":"postfix","port":"25","tls":false,"object":false,"connected":true,"user":"', @user, '","pass":"', @pass, '"}],"pop3_servers":[],"version":0.1,"timezone_setting":"America\/Sao_Paulo","imap_servers":[{"name":"wikisuite.email","server":"cyrus-master","hide":false,"port":143,"tls":false,"object":false,"connected":true,"user":"', @user, '","pass":"', @pass, '"}]}'));
  END; //
DELIMITER ;

SQL;
$content = $mysqli->query($sql);

/* PAM will check this view to authenticate users */
$sql = <<<SQL
CREATE OR REPLACE VIEW cypht_auth AS
    SELECT user, JSON_UNQUOTE(JSON_EXTRACT(value, "$.imap_servers[0].pass")) AS password
    FROM tiki_user_preferences where prefName = 'cypht_user_config';
SQL;
$content = $mysqli->query($sql);