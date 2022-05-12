#!/bin/bash
set -Eeuo pipefail
echo "install curl"

export DEBIAN_FRONTEND=noninteractive
export LANG=C.UTF-8

apt-get update
apt-get install -y gnupg curl wget

echo "Install the postgres repo"
echo "deb http://apt.postgresql.org/pub/repos/apt bullseye-pgdg main" > /etc/apt/sources.list.d/pgdg.list
wget --quiet -O - https://www.postgresql.org/media/keys/ACCC4CF8.asc | apt-key add -

apt-get update 
apt-get upgrade -y
echo "install required packages"
PACKAGES=$(cat /scripts/package-list-buster)
apt-get install -yq --no-install-recommends $PACKAGES
/usr/sbin/update-ca-certificates --fresh
#Clean up after apt
rm -rf /var/lib/apt/lists/*

echo "Install nodejs version 14"
curl -sL https://deb.nodesource.com/setup_14.x | bash -