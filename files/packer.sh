#!/bin/bash
source /lib/gentoo/functions.sh

OPENSSL_ATOM=">=dev-libs/openssl-3.0.9"

ebegin "Setting locales to generate"
cat <<EOF> /etc/locale.gen
en_DK.UTF-8 UTF-8
EOF
eend $? "Failed" || exit $?

locale-gen || exit $?

eselect locale set en_DK.utf8 || exit $?

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

ebegin "Selecting profile"
(
    eselect profile list
    eselect profile set default/linux/amd64/23.0/no-multilib/hardened
)
eend $? "Failed" || exit $?

ebegin "Copying portage flags"
cp -r /tmp/data/package.{accept_keywords,use,unmask,env} /etc/portage/
eend $? "Failed" || exit $?

ebegin "Rebuilding openssl -bindist"
emerge --backtrack=200 --verbose-conflicts "${OPENSSL_ATOM}" openssh
eend $? "Failed" || exit $?

ebegin "Updating portage"
emerge -uN portage || true
eend $? "Failed" || exit $?

ebegin "Updating system"
emerge -uDNt @system
eend $? "Failed" || exit $?

ebegin "Selecting pager"
eselect pager set /usr/bin/less
eend $? "Failed" || exit $?

einfo "Updating perl packages, if any"
perl-cleaner --all || exit $?

ebegin "Updating world"
emerge -uDNt --with-bdeps=y @world
eend $? "Failed" || exit $?

ebegin "Cleaning deps"
emerge --verbose=n --depclean
eend $? "Failed" || exit $?

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
