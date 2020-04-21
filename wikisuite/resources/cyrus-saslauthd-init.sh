#!/bin/bash

db_host=${TIKI_DB_HOST:-db}
db_name=${TIKI_DB_NAME:-tikiwiki}
db_user=${TIKI_DB_USER:-tiki}
db_pass=${TIKI_DB_PASS:-wiki}

cat > /etc/pam.d/imap <<EOF
auth       sufficient    pam_mysql.so config_file=/etc/pam_mysql.conf
account    sufficient    pam_mysql.so config_file=/etc/pam_mysql.conf
session    sufficient    pam_mysql.so config_file=/etc/pam_mysql.conf
EOF

cat > /etc/pam_mysql.conf <<EOF
users.host              = ${db_host}
users.database          = ${db_name}
users.db_user           = ${db_user}
users.db_passwd         = ${db_pass}
users.table             = users_users
users.user_column       = login
users.password_column   = hash
users.password_crypt    = 1
users.use_sha512        = 1
users.rounds            = 2500
verbose                 = 1
EOF
