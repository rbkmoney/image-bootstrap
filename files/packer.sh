#!/bin/bash
source /lib/gentoo/functions.sh

export EMERGE="emerge -q"
SALT_VERSION="2015.8.13"

# Get utf-8 support with default locale
ebegin "Setting locales to generate"
# DK uses 24h time which we need
cat <<EOF> /etc/locale.gen
en_DK.UTF-8 UTF-8
EOF
eend $? "Failed" || exit $?
ebegin "Setting locales to preserve"
cat <<EOF> /etc/locale.nopurge
MANDELETE
SHOWFREEDSPACE
en_DK.UTF-8 UTF-8
EOF
eend $? "Failed" || exit $?

locale-gen || exit $?

eselect locale set en_DK.utf8 || exit $?

# Get cert for loading packages from bakka.su repo via HTTPS
ebegin "Downloading CA for the package repository"
mkdir -p /usr/local/share/ca-certificates \
    && wget -q http://bakka.su/ca/baka_bakka.crt -O /usr/local/share/ca-certificates/baka_bakka.crt
eend $? "Failed" || exit $?
ebegin "Updating CA cerificates"
update-ca-certificates --fresh > /dev/null
eend $? "Failed" || exit $?

# /tmp/data mount set in packer.json
ebegin "Copying portage/make.conf"
cp /tmp/data/portage.make.conf /etc/portage/make.conf
eend $? "Failed" || exit $?

ebegin "Adding repos.conf/gentoo"
mkdir -p /etc/portage/repos.conf \
    && cat <<EOF> /etc/portage/repos.conf/gentoo.conf
[DEFAULT]
main-repo = gentoo

[gentoo]
location = /usr/portage
sync-type = rsync
auto-sync = false
EOF
eend $? "Failed" || exit $?

# https://wiki.gentoo.org/wiki/Profile_(Portage)
ebegin "Selecting profile"
eselect profile set hardened/linux/amd64/no-multilib
eend $? "Failed" || exit $?


ebegin "Setting bootstrap flags"
# Salt is unstable, therefore we need to explicityly allow it using keywords
mkdir -p /etc/portage/package.{accept_keywords,keywords,use,env} \
    && cat <<EOF>> /etc/portage/package.keywords/bootstrap
=app-admin/salt-${SALT_VERSION} ~amd64
net-libs/zeromq:0/5 ~amd64
<dev-python/pyzmq-16 ~amd64
dev-python/cffi ~amd64
EOF
eend $? "Failed" || exit $?

ebegin "Removing openssh (to skip it's rebuilding with -bindist)"
${EMERGE} -C openssh
eend $? "Failed" || exit $?

# bakka.su cert is ECDSA and to get this supported we rebuild openssl without
# bindist
ebegin "Rebuilding openssl -bindist"
FEATURES="-getbinpkg" ${EMERGE} --verbose=n openssl
eend $? "Failed" || exit $?

# Now SSL is okay and we can enable bakka.su mirrors
ebegin "Uncommenting GENTOO_MIRRORS and other vars in make.conf"
sed -i "s|\# sed-remove||g" /etc/portage/make.conf
eend $? "Failed" || exit $?

ebegin "Emerging localepurge salt qemacs nvi openssh"
${EMERGE} --verbose=n ">=zeromq-4.1" "=app-admin/salt-${SALT_VERSION}" qemacs nvi app-admin/localepurge
eend $? "Failed" || exit $?

# Salt needs python2.7, not 3.x
ebegin "Selecting python2.7 as default python interpreter"
eselect python set python2.7
eend $? "Failed" || exit $?

ebegin "Selecting pager"
eselect pager set /usr/bin/less
eend $? "Failed" || exit $?

# This is works for perl better than emerge
einfo "Updating perl"
perl-cleaner --reallyall || exit $?

ebegin "Updating world"
${EMERGE} -uDN @world
eend $? "Failed" || exit $?

# Remove orphaned deps
ebegin "Cleaning deps"
${EMERGE} --verbose=n --depclean
eend $? "Failed" || exit $?

einfo "Purging extra locales"
localepurge || exit $?

if [ ! -d /var/salt ]; then
    ebegin "Creating /var/salt"
    mkdir -p /var/salt
    eend $? || exit $?
fi

find /usr/share/gtk-doc -delete
find /usr/share/man -delete
find /usr/share/doc -delete
find /usr/share/sgml -print -delete
find /usr/share/i18n -print
find /usr/share/misc -print
find / -name '*.pyc' -delete

ebegin "Removing temporary directories and logs"
rm -rf /var/tmp/{portage,packages,distfiles}
find /var/log -type f ! -name '.keep*' -print -delete
eend $? "Failed" || exit $?

einfo "And here are some resulting space consumption details"
find / -mindepth 2 -maxdepth 4 -exec 'du' '-hsx' '{}' ';' | sort -h | tail -n 50
find / -maxdepth 1 -exec 'du' '-hsx' '{}' ';' | sort -h | tail -n 50
