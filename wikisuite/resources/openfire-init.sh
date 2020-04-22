#!/bin/sh
set -x

while ! nc -z "${OF_DB_HOST}" 3306;
do
    echo 'Waiting for database connection before continue in entrypoint'
    sleep 5;
done

db_host="${OF_DB_HOST:-db}"
db_name="${OF_DB_NAME:-openfire}"
db_user="${OF_DB_USER:-ofuser}"
db_pass="${OF_DB_PASS:-ofpass}"
db_root_pass="${MYSQL_ROOT_PASSWORD}"

ofmysql () {
    /usr/bin/mysql          \
        -u"${db_user}"      \
        -p"${db_pass}"      \
        -h "${db_host}"     \
        "${db_name}"        \
        "$@";
}

rootmysql () {
    /usr/bin/mysql          \
        -uroot              \
        -p"${db_root_pass}" \
        -h "${db_host}"     \
        "$@";
}

rootmysql -v <<EOF
CREATE DATABASE IF NOT EXISTS \`${db_name}\`
    DEFAULT CHARACTER SET utf8mb4
    COLLATE utf8mb4_unicode_ci;
GRANT ALL PRIVILEGES ON \`${db_name}\`.*
    TO '${db_user}'@'%'
    IDENTIFIED BY '${db_pass}';
FLUSH PRIVILEGES;
EOF

result=$(ofmysql -N -s -e 'SELECT count(1) FROM INFORMATION_SCHEMA.TABLES WHERE TABLE_SCHEMA = "openfire";')
if [[ "$result" -eq "0" ]];
then
    cat /opt/openfire/resources/database/openfire_mysql.sql | rootmysql "${db_name}" -v
fi

ofmysql -v <<EOF
CREATE TABLE IF NOT EXISTS \`ofOauthbearer\` (
  \`name\` varchar(255) NOT NULL,
  \`clientId\` varchar(255) NOT NULL,
  \`clientSecret\` varchar(255) NOT NULL,
  PRIMARY KEY (\`clientId\`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;
EOF

ofmysql -v <<EOF
INSERT INTO ofOauthbearer (name, clientId, clientSecret)
    VALUES (
        'ConverseJS OAuth Client',
        'org.tiki.rtc.internal-conversejs-id',
        '${TIKI_OF_SECRET_KEY}'
    )
    ON DUPLICATE KEY UPDATE clientSecret='${TIKI_OF_SECRET_KEY}'
EOF

wget -O /opt/openfire/plugins/oauthbearer.jar http://server.wikisuite.chat/oauthbearer.jar

cat > /opt/openfire/conf/openfire.xml <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<jive>
  <adminConsole>
    <port>9090</port>
    <securePort>-1</securePort>
  </adminConsole>
  <locale>en</locale>
  <connectionProvider>
    <className>org.jivesoftware.database.DefaultConnectionProvider</className>
  </connectionProvider>
  <database>
    <defaultProvider>
      <driver>com.mysql.cj.jdbc.Driver</driver>
      <serverURL>jdbc:mysql://${OF_DB_HOST}:3306/${OF_DB_NAME}?rewriteBatchedStatements=true&amp;characterEncoding=UTF-8&amp;characterSetResults=UTF-8&amp;serverTimezone=UTC</serverURL>
      <username>${OF_DB_USER}</username>
      <password>${OF_DB_PASS}</password>
      <testSQL>select 1</testSQL>
      <testBeforeUse>false</testBeforeUse>
      <testAfterUse>false</testAfterUse>
      <testTimeout>500</testTimeout>
      <timeBetweenEvictionRuns>30000</timeBetweenEvictionRuns>
      <minIdleTime>900000</minIdleTime>
      <maxWaitTime>500</maxWaitTime>
      <minConnections>5</minConnections>
      <maxConnections>25</maxConnections>
      <connectionTimeout>1.0</connectionTimeout>
    </defaultProvider>
  </database>

  <jdbcProvider>
    <driver>com.mysql.jdbc.Driver</driver>
    <connectionString>jdbc:mysql://${TIKI_DB_HOST}/${TIKI_DB_NAME}?user=${TIKI_DB_USER}&amp;password=${TIKI_DB_PASS}</connectionString>
  </jdbcProvider>

  <provider>
    <user> <className>org.jivesoftware.openfire.user.JDBCUserProvider</className> </user>
    <group> <className>org.jivesoftware.openfire.group.JDBCGroupProvider</className> </group>
    <admin> <className>org.jivesoftware.openfire.admin.JDBCAdminProvider</className> </admin>
    <auth> <className>org.jivesoftware.openfire.auth.JDBCAuthProvider</className > </auth>
  </provider>

  <jdbcUserProvider>
    <loadUserSQL>SELECT value, email FROM users_users uu LEFT JOIN tiki_user_preferences up ON (uu.login = up.user AND up.prefName LIKE 'realName') WHERE login=?</loadUserSQL>
    <userCountSQL>SELECT COUNT(*) FROM users_users</userCountSQL>
    <allUsersSQL>SELECT login FROM users_users</allUsersSQL>
    <searchSQL>SELECT login FROM users_users uu LEFT JOIN tiki_user_preferences up ON (uu.login = up.user AND up.prefName LIKE 'realName') WHERE</searchSQL>
    <usernameField>login</usernameField>
    <nameField>value</nameField>
    <emailField>email</emailField>
  </jdbcUserProvider>
  <jdbcGroupProvider>
      <groupCountSQL>SELECT count(*) FROM users_groups</groupCountSQL>
      <allGroupsSQL>SELECT groupName FROM users_groups</allGroupsSQL>
      <userGroupsSQL>SELECT DISTINCT groupName FROM users_usergroups ug JOIN users_users uu ON (ug.userId = uu.userId AND login = ?)</userGroupsSQL>
      <descriptionSQL>SELECT groupDesc FROM users_groups WHERE groupName=?</descriptionSQL>
      <loadMembersSQL>SELECT login FROM users_usergroups ug JOIN users_users uu ON (ug.userId = uu.userId AND ug.groupName = ?)</loadMembersSQL>
      <loadAdminsSQL>SELECT login FROM users_usergroups ug JOIN users_users uu ON ug.userId = uu.userId WHERE ug.groupName = ? AND EXISTS(SELECT userId FROM users_usergroups WHERE userId = ug.userId and groupName = 'Admins')</loadAdminsSQL>
  </jdbcGroupProvider>
  <jdbcAdminProvider>
    <getAdminsSQL>SELECT login FROM users_grouppermissions ugp JOIN users_usergroups ug JOIN users_users uu ON ugp.groupName = ug.groupName AND ug.userId = uu.userId AND ugp.permName = 'tiki_p_admin'</getAdminsSQL>
  </jdbcAdminProvider>

  <jdbcAuthProvider>
    <passwordSQL>SELECT hash FROM users_users WHERE login = ?</passwordSQL>
    <passwordType>bcrypt</passwordType>
    <allowUpdate>false</allowUpdate>
    <bcrypt><cost>10</cost></bcrypt>
  </jdbcAuthProvider>

  <setup>true</setup>
  <fqdn>${OF_PROP_FQDN}</fqdn>
  <xmpp>
    <domain>${OF_PROP_XMPP_DOMAIN}</domain>
  </xmpp>
</jive>
EOF

tee /etc/nginx/vhost.d/${OF_PROP_FQDN} <<NGINX
location ^~ /http-bind/ {
  proxy_http_version 1.1;
  proxy_set_header Upgrade \$http_upgrade;
  proxy_set_header Connection "Upgrade";
  proxy_set_header Host \$host;
  proxy_pass http://${HOSTNAME}:7070;
}
NGINX