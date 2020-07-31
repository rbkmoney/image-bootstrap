#!/bin/bash
source /lib/gentoo/functions.sh

OPENSSL_ATOM=">=dev-libs/openssl-1.1.1g"
SALT_VERSION="3000.2-r4"
SALT_ATOM=">=app-admin/salt-${SALT_VERSION}"
PYTHON_SLOT="3.7"

ebegin "Setting locales to generate"
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

ebegin "Selecting profile"
eselect profile set default/linux/amd64/17.0/no-multilib/hardened
eend $? "Failed" || exit $?

ebegin "Setting bootstrap flags"
mkdir -p /etc/portage/package.{accept_keywords,keywords,use,unmask,env} 
eend $? "Failed" || exit $?

ebegin "Rebuilding openssl -bindist"
emerge --backtrack=200 --verbose-conflicts "${OPENSSL_ATOM}" openssh
eend $? "Failed" || exit $?

ebegin "Emerging salt qemacs nvi"
emerge -q --verbose=n "${SALT_ATOM}" qemacs
eend $? "Failed" || exit $?

ebegin "Selecting python${PYTHON_SLOT} as default python interpreter"
eselect python set "python${PYTHON_SLOT}"
eend $? "Failed" || exit $?

ebegin "Selecting pager"
eselect pager set /usr/bin/less
eend $? "Failed" || exit $?

einfo "Updating perl"
perl-cleaner --all || exit $?

ebegin "Updating system"
emerge -q -uDNt @system
eend $? "Failed" || exit $?

ebegin "Updating world"
emerge -q -uDNt @world
eend $? "Failed" || exit $?

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
find /usr/share/sgml -delete
find /usr/share/i18n -print
find /usr/share/misc -print
find / -name '*.pyc' -delete

ebegin "Removing temporary directories and logs"
rm -rf /var/tmp/{portage,packages,distfiles}
find /var/log -type f ! -name '.keep*' -delete
eend $? "Failed" || exit $?

einfo "And here are some resulting space consumption details"
find / -mindepth 2 -maxdepth 4 -exec 'du' '-hsx' '{}' ';' | sort -h | tail -n 50
find / -maxdepth 1 -exec 'du' '-hsx' '{}' ';' | sort -h | tail -n 50
