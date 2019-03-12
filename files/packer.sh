#!/bin/bash
source /lib/gentoo/functions.sh

SALT_VERSION="2017.7.8"

# Get utf-8 support with default locale
ebegin "Setting locales to generate"
# DK uses 24h time which we need
cat <<EOF> /etc/locale.gen
en_DK.UTF-8 UTF-8
EOF
eend $? "Failed" || exit $?

locale-gen || exit $?

eselect locale set en_DK.utf8 || exit $?

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
eselect profile set default/linux/amd64/17.0/no-multilib/hardened
eend $? "Failed" || exit $?


ebegin "Setting bootstrap flags"
# Salt is unstable, therefore we need to explicityly allow it using keywords
mkdir -p /etc/portage/package.{accept_keywords,keywords,use,env} \
    && cat <<EOF>> /etc/portage/package.keywords/bootstrap
dev-python/pycryptodome ~amd64
=app-admin/salt-${SALT_VERSION} ~amd64
EOF
eend $? "Failed" || exit $?

ebegin "Removing openssh (to skip it's rebuilding with -bindist)"
emerge -q -C openssh
eend $? "Failed" || exit $?

# bakka.su cert is ECDSA and to get this supported we rebuild openssl without
# bindist
ebegin "Rebuilding openssl -bindist"
FEATURES="-getbinpkg" emerge -q --verbose=n openssl
eend $? "Failed" || exit $?

# Now SSL is okay and we can enable bakka.su mirrors
ebegin "Uncommenting GENTOO_MIRRORS and other vars in make.conf"
sed -i "s|\# sed-remove||g" /etc/portage/make.conf
eend $? "Failed" || exit $?

ebegin "Emerging salt qemacs nvi openssh"
emerge -q --verbose=n ">=zeromq-4.1" "=app-admin/salt-${SALT_VERSION}" qemacs nvi
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

ebegin "Updating system"
emerge -q -uDNt @system
eend $? "Failed" || exit $?

ebegin "Updating world"
emerge -q -uDNt @world
eend $? "Failed" || exit $?

# Remove orphaned deps
ebegin "Cleaning deps"
emerge -q --verbose=n --depclean
eend $? "Failed" || exit $?

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
