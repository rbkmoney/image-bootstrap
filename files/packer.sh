#!/bin/bash

source /lib/gentoo/functions.sh

OPENSSL_ATOM=">=dev-libs/openssl-3.5.0"

ebegin "Setting locales to generate"
cat <<EOF> /etc/locale.gen
en_DK.UTF-8 UTF-8
EOF
eend $? "Failed" || exit $?

locale-gen || exit $?

eselect locale set en_DK.utf8 || exit $?

ebegin "Updating /etc/rc.conf"
sed -i 's/^#\(rc_provide\)="!net"$/\1="net"/' /etc/rc.conf
eend $? "Failed" || exit $?

ebegin "Copying portage/make.conf"
cp /tmp/data/make.conf /etc/portage/make.conf
eend $? "Failed" || exit $?

ebegin "Adding repos.conf/gentoo"
mkdir -p /etc/portage/repos.conf \
    && cat <<EOF> /etc/portage/repos.conf/gentoo.conf
[DEFAULT]
main-repo = gentoo

[gentoo]
location = /var/db/repos/gentoo
sync-type = rsync
auto-sync = false
EOF
eend $? "Failed" || exit $?

ebegin "Replacing binhost configuration"
(
    set -ue
    rm -r /etc/portage/binrepos.conf
    cp /tmp/data/binrepos.conf /etc/portage/binrepos.conf
)
eend $? "Failed" || exit $?

getuto || exit $?

ebegin "Adding baka-bakka amd64 binhost key"
(
    set -ue
    cat /etc/portage/gnupg/gpg-agent.conf || true
    cat <<EOF  >> /etc/portage/gnupg/gpg-agent.conf
allow-preset-passphrase
max-cache-ttl 34560000
default-cache-ttl 34560000
EOF
    gpg --homedir=/etc/portage/gnupg --no-tty --batch --yes \
	--import /tmp/data/baka-bakka-amd64-binhost.pgp
    gpg --homedir=/etc/portage/gnupg --no-tty --batch --yes \
	--verbose \
	--pinentry-mode=loopback \
	--passphrase-file /etc/portage/gnupg/pass \
	--sign-key A18A4922C89EFC3188558873E3506766BD71FBE9
    echo -e "trust\n4\nsave\n" \
	| gpg --homedir=/etc/portage/gnupg --no-tty --batch --yes \
	      --command-fd 0 \
	      --edit-key A18A4922C89EFC3188558873E3506766BD71FBE9
    gpg --batch --homedir=/etc/portage/gnupg --check-trustdb
)
eend $? "Failed" || exit $?

ebegin "Selecting profile"
(
    eselect profile list
    eselect profile set default/linux/amd64/23.0/no-multilib/hardened
)
eend $? "Failed" || exit $?

ebegin "Copying portage flags"
cp -r /tmp/data/package.{accept_keywords,use,unmask,env} /etc/portage/
eend $? "Failed" || exit $?

einfo "Rebuilding openssl -bindist"
emerge --backtrack=200 --verbose-conflicts "${OPENSSL_ATOM}" openssh || exit $?

einfo "Updating portage"
emerge -uN portage || true

einfo "Installing Git and other tools"
emerge dev-vcs/git || exit $?

einfo "Updating system"
emerge -uDNt @system || exit $?

ebegin "Selecting pager"
eselect pager set /usr/bin/less
eend $? "Failed" || exit $?

einfo "Updating perl packages, if any"
perl-cleaner --all || exit $?

einfo "Updating world"
emerge -uDNt --with-bdeps=y @world || exit $?

einfo "Cleaning deps"
emerge --verbose=n --depclean || exit $?

find /usr/share/gtk-doc -delete
find /usr/share/man -delete
find /usr/share/doc -delete
find /usr/share/sgml -delete
find /usr/share/i18n -print
find /usr/share/misc -print

ebegin "Removing temporary directories and logs"
(
    set -e
    rm -rf /var/tmp/{portage,packages,distfiles}
    rm -rf /var/cache/{binpkgs,distfiles,binhost,edb}
    find /var/log -type f ! -name '.keep*' -delete
)
eend $? "Failed" || exit $?

einfo "And here are some resulting space consumption details"
find /var/ -mindepth 2 -maxdepth 4 ! -name gentoo -exec 'du' '-hsx' '{}' ';' | sort -h | tail -n 50
find /usr/ -mindepth 2 -maxdepth 4 -exec 'du' '-hsx' '{}' ';' | sort -h | tail -n 50
find / -mindepth 2 -maxdepth 4 -exec 'du' '-hsx' '{}' ';' | sort -h | tail -n 50
find / -maxdepth 1 -exec 'du' '-hsx' '{}' ';' | sort -h | tail -n 50
