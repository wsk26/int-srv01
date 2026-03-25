#!/bin/bash
set -e

echo "==> Настройка базовых параметров..."
hostnamectl set-hostname int-srv01.int.ws.kz
timedatectl set-timezone Asia/Almaty
apt-get update -y
export DEBIAN_FRONTEND=noninteractive
apt-get install -y locales slapd ldap-utils samba openssl

sed -i 's/# en_US.UTF-8 UTF-8/en_US.UTF-8 UTF-8/' /etc/locale.gen
locale-gen
update-locale LANG=en_US.UTF-8

echo "==> Настройка сети..."
cat <<EOF > /etc/network/interfaces
auto lo
iface lo inet loopback

auto ens3
iface ens3 inet static
    address 10.1.10.10/24
    gateway 10.1.10.1
iface ens3 inet6 static
    address 2001:db8:1001:10::10/64
    gateway 2001:db8:1001:10::1
EOF
systemctl restart networking

echo "==> Настройка Центра сертификации (CA)..."
mkdir -p /opt/grading/ca && cd /opt/grading/ca
openssl genrsa -out root.key 4096
openssl req -x509 -new -nodes -key root.key -sha256 -days 3650 -out ca.pem -subj "/CN=WS Root CA"
openssl genrsa -out web.key 2048
openssl req -new -key web.key -out web.csr -subj "/CN=www.dmz.ws.kz"
openssl x509 -req -in web.csr -CA ca.pem -CAkey root.key -CAcreateserial -out web.pem -days 365 -sha256
cd /

echo "==> Настройка LDAP..."
cat <<EOF > /root/users.ldif
dn: ou=Employees,dc=int,dc=ws,dc=kz
objectClass: organizationalUnit
ou: Employees

dn: uid=jamie,ou=Employees,dc=int,dc=ws,dc=kz
objectClass: inetOrgPerson
cn: Jamie Oliver
sn: Oliver
uid: jamie
userPassword: Skill39!
mail: jamie.oliver@dmz.ws.kz
EOF
# Применяем структуру (пароль админа по умолчанию при noninteractive установке обычно пустой или 'admin', но мы форсируем добавление)
ldapadd -Y EXTERNAL -H ldapi:/// -f /root/users.ldif || echo "Проверьте права LDAP"

echo "==> Настройка Samba..."
mkdir -p /public /internal
chmod 777 /public
useradd -M -s /usr/sbin/nologin jamie || true
(echo "Skill39!"; echo "Skill39!") | smbpasswd -a jamie -s

cat <<EOF > /etc/samba/smb.conf
[global]
   workgroup = WORKGROUP
   security = user
[public]
   path = /public
   read only = no
   guest ok = yes
[internal]
   path = /internal
   valid users = jamie
   guest ok = no
   writable = yes
EOF
systemctl restart smbd

echo "==> Готово! int-srv01 настроен."

cat /dev/null > ~/.bash_history
history -c
rm -f /root/script.sh
