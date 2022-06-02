FROM geerlingguy/docker-ubuntu2204-ansible:latest
ENV DEBIAN_FRONTEND noninteractive
RUN apt-get update -q

# Add default PHP version (8.1), and things that it/devops utils require
RUN apt-get install -qy rsync make findutils curl util-linux git php-fpm nginx postfix dirmngr

# Add secondary PHP version for testing
RUN add-apt-repository ppa:ondrej/php
RUN apt-get install -yq php7.4-common php7.4-bcmath php7.4-curl php7.4-fpm php7.4-gd php7.4-igbinary php7.4-mbstring php7.4-mysql php7.4-pgsql php7.4-oauth php7.4-opcache php7.4-redis php7.4-soap php7.4-xml php7.4-xmlrpc php7.4-zip

# Shim some things that are normally present on our servers
WORKDIR /etc/nginx/includes
RUN ln -s robots.production.conf robots.conf
WORKDIR /root
RUN touch /etc/nginx/includes/letsencrypt-acme-challenge.conf

# Add devops utils!
WORKDIR /root
ADD . ansible-role-devops-utils
WORKDIR /root/ansible-role-devops-utils/scripts/deployables
RUN make -s install
