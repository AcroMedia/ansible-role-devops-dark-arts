# Useful for all users including root
USCRIPTS    = backdir
USCRIPTS   += backdir.exclusions.example
USCRIPTS   += check-innodb-file-per-table-status.sh
USCRIPTS   += dbdump
USCRIPTS   += dbrestore
USCRIPTS   += lsipv4
USCRIPTS   += lsipv4.quiet
USCRIPTS   += strip-comments
USCRIPTS   += strip-comments.php
USCRIPTS   += require-named-parameter
USCRIPTS   += optional-parameter-exists
USCRIPTS   += backfile
USCRIPTS   += nmap-ish

# Acro Developers
SUDOER_SCRIPTS  = acro-add-website.sh
SUDOER_SCRIPTS += acro-remove-website.sh
SUDOER_SCRIPTS += reset-drupal-permissions.sh

# Only server admins are ever going to use these
ROOTONLY_SCRIPTS  = acro-add-user.sh
ROOTONLY_SCRIPTS += revoke-ssh-key.sh
ROOTONLY_SCRIPTS += optimize-big-innodb-tables.sh
ROOTONLY_SCRIPTS += fix-mysql-root-password
ROOTONLY_SCRIPTS += acro-iptables-restrict-port
ROOTONLY_SCRIPTS += list-cron-jobs-for-all-users.sh
ROOTONLY_SCRIPTS += list-nginx-access-logs.php
ROOTONLY_SCRIPTS += list-nginx-server-names.php
ROOTONLY_SCRIPTS += make-fake-swap-file.sh
ROOTONLY_SCRIPTS += passwordless-sudo.sh
ROOTONLY_SCRIPTS += set_fqdn.sh
ROOTONLY_SCRIPTS += back_up_vhost_to_s3
ROOTONLY_SCRIPTS += back_up_database_to_s3
ROOTONLY_SCRIPTS += back_up_directory_to_s3

RCNFFILE  = apache-vhost-template-d7-ssl-conf.j2
RCNFFILE += apache-vhost-template-d7-conf.j2
RCNFFILE += apache-acme-challenge-conf.j2
RCNFFILE += nginx-vhost-template-d7-ssl-conf.j2
RCNFFILE += nginx-vhost-template-d7-conf.j2
RCNFFILE += nginx-vhost-template-static-ssl-conf.j2
RCNFFILE += nginx-vhost-template-static-conf.j2
RCNFFILE += nginx-acme-challenge-conf.j2
RCNFFILE += php5-fpm-pool-conf-template.j2
RCNFFILE += php5.6-fpm-pool-conf-template.j2
RCNFFILE += php7.0-fpm-pool-conf-template.j2
RCNFFILE += php7.1-fpm-pool-conf-template.j2
RCNFFILE += php7.2-fpm-pool-conf-template.j2
RCNFFILE += php7.3-fpm-pool-conf-template.j2
RCNFFILE += php7.4-fpm-pool-conf-template.j2
RCNFFILE += placeholder
RCNFFILE += drupal-settings-local-php.j2
RCNFFILE += logrotate.d-vhost.j2
RCNFFILE += add-website.conf.php5
RCNFFILE += add-website.conf.php5.6-redhat
RCNFFILE += add-website.conf.php5.6
RCNFFILE += add-website.conf.php7.0
RCNFFILE += add-website.conf.php7.1
RCNFFILE += add-website.conf.php7.2
RCNFFILE += add-website.conf.php7.3
RCNFFILE += add-website.conf.php7.4
RCNFFILE += add-website.conf.phpnone
RCNFFILE += add-user.conf.example
RCNFFILE += add-user.data.example

# Nginx includes
NGINC_FILE  = robots.development.conf
NGINC_FILE += robots.production.conf
NGINC_FILE += robots.staging.conf


UDEST  ?= /usr/local/bin
SDEST  ?= /usr/local/sbin
CFDST  ?= /etc/acro
LIBDEST ?= /usr/local/lib/acro/bash
NGINCL_DEST ?= /etc/nginx/includes


# These are no longer in use. Any instances found will be toasted.
OBSOLETES  = /usr/local/bin/acro-add-php7.0-website.sh
OBSOLETES += /usr/local/sbin/acro-add-php7.0-website.sh
OBSOLETES += /usr/local/sbin/redis_iptables_secure.sh


build:
	@echo There is nothing to configure or build. This is just a collection of shell-scripts.
	@echo Run \'sudo make install\' or \'sudo make uninstall\'.


install: uninstall

	# Make sure acro user/group exists.
	getent passwd acro || /usr/sbin/useradd acro || /usr/sbin/useradd acro -g acro

	# Make sure repository source dir exists and is writeable by acro staff
	install -v -o acro -g acro -m 2775 -d /usr/local/src/acro

	# Make sure config dir exists
	install -v -o root -g root -m 755 -d $(CFDST)

	# Make sure nginx includes dir exists
	install -v -o root -g root -m 755 -d $(NGINCL_DEST)

	# Install user-runnable utils
	$(foreach file,$(USCRIPTS), install -v -o root -g root -m 755 $(file) $(DESTDIR)$(UDEST);)

	# Install sudoer utils
	$(foreach file,$(SUDOER_SCRIPTS), install -v -o root -g root -m 755 $(file) $(DESTDIR)$(SDEST);)

	# Install root-only utils
	$(foreach file,$(ROOTONLY_SCRIPTS), install -v -o root -g root -m 755 $(file) $(DESTDIR)$(SDEST);)

	# Install config files
	$(foreach file,$(RCNFFILE), install -v -o root -g root -m 644 $(file) $(DESTDIR)$(CFDST);)

	# Install nginx includes
	$(foreach file,$(NGINC_FILE), install -v -o root -g root -m 644 $(file) $(DESTDIR)$(NGINCL_DEST);)

	# Provide links both ways; environments can't always see both bin dirs.
	$(foreach file,$(SUDOER_SCRIPTS), ln -sv $(DESTDIR)$(SDEST)/$(file) $(DESTDIR)$(UDEST)/$(file);)
	$(foreach file,$(USCRIPTS), ln -sv $(DESTDIR)$(UDEST)/$(file) $(DESTDIR)$(SDEST)/$(file);)

	# Make sure lib dir exists
	install -v -o root -g root -m 755 -d $(DESTDIR)/usr/local/lib/acro/bash
	# Install shell includes
	install -v -o root -g root -m 755 functions.sh $(DESTDIR)/usr/local/lib/acro/bash



uninstall:

	# Get rid of any lingering symbolic links, or any old versions in case we've moved things around.

	# Scripts
	$(foreach file,$(USCRIPTS), if [ -f $(DESTDIR)$(SDEST)/$(file) ]; then rm -fv $(DESTDIR)$(SDEST)/$(file);fi ;)
	$(foreach file,$(USCRIPTS), if [ -f $(DESTDIR)$(UDEST)/$(file) ]; then rm -fv $(DESTDIR)$(UDEST)/$(file);fi ;)
	$(foreach file,$(SUDOER_SCRIPTS), if [ -f $(DESTDIR)$(SDEST)/$(file) ]; then rm -fv $(DESTDIR)$(SDEST)/$(file);fi ;)
	$(foreach file,$(SUDOER_SCRIPTS), if [ -f $(DESTDIR)$(UDEST)/$(file) ]; then rm -fv $(DESTDIR)$(UDEST)/$(file);fi ;)
	$(foreach file,$(ROOTONLY_SCRIPTS), if [ -f $(DESTDIR)$(SDEST)/$(file) ]; then rm -fv $(DESTDIR)$(SDEST)/$(file);fi ;)
	$(foreach file,$(ROOTONLY_SCRIPTS), if [ -f $(DESTDIR)$(UDEST)/$(file) ]; then rm -fv $(DESTDIR)$(UDEST)/$(file);fi ;)

	# Configs
	$(foreach file,$(RCNFFILE), if [ -f $(DESTDIR)$(CFDST)/$(file) ]; then rm -fv $(DESTDIR)$(CFDST)/$(file);fi ;)

	# NGINX includes
	$(foreach file,$(NGINC_FILE), if [ -f $(DESTDIR)$(NGINCL_DEST)/$(file) ]; then rm -fv $(DESTDIR)$(NGINCL_DEST)/$(file);fi ;)

	# The tab completion helper links
	$(foreach file,$(USCRIPTS), if [ -L $(DESTDIR)$(SDEST)/$(file) ]; then rm -fv $(DESTDIR)$(SDEST)/$(file);fi ;)
	$(foreach file,$(USCRIPTS), if [ -L $(DESTDIR)$(UDEST)/$(file) ]; then rm -fv $(DESTDIR)$(UDEST)/$(file);fi ;)
	$(foreach file,$(SUDOER_SCRIPTS), if [ -L $(DESTDIR)$(SDEST)/$(file) ]; then rm -fv $(DESTDIR)$(SDEST)/$(file);fi ;)
	$(foreach file,$(SUDOER_SCRIPTS), if [ -L $(DESTDIR)$(UDEST)/$(file) ]; then rm -fv $(DESTDIR)$(UDEST)/$(file);fi ;)
	$(foreach file,$(ROOTONLY_SCRIPTS), if [ -L $(DESTDIR)$(SDEST)/$(file) ]; then rm -fv $(DESTDIR)$(SDEST)/$(file);fi ;)
	$(foreach file,$(ROOTONLY_SCRIPTS), if [ -L $(DESTDIR)$(UDEST)/$(file) ]; then rm -fv $(DESTDIR)$(UDEST)/$(file);fi ;)

	# Obsolete files
	$(foreach file,$(OBSOLETES), if [ -e $(DESTDIR)$(file) ]; then rm -fv $(DESTDIR)$(file);fi ;)

	# Shared bash functions
	if test -e $(DESTDIR)/usr/local/lib/acro/bash/functions.sh; then rm -fv $(DESTDIR)/usr/local/lib/acro/bash/functions.sh; fi
