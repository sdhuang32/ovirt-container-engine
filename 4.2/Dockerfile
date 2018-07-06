FROM sdhuang32/c7-systemd

# Database
ENV POSTGRES_USER engine
ENV POSTGRES_PASSWORD engine
ENV POSTGRES_DB engine
ENV POSTGRES_HOST localhost
ENV POSTGRES_PORT 5432

# oVirt
ENV OVIRT_FQDN qcvm.local

USER root
WORKDIR /root/

# Install basic tools
RUN yum -y install vim net-tools libselinux-python rsync patch wget less openssh-server cronie
# Set rc.local to executable
RUN chmod 0755 /etc/rc.d/rc.local
# Set ssh key to remote host
RUN mkdir -p .ssh && touch .ssh/authorized_keys
RUN echo "ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAABAQDfyXxcew1oOyT4IF92nIR/AmB56R5ve9K27WMYkKeIiE3bs9sqJNOckim+zO5UmUJl0vxC1iXgUfBx8zI4igs0SfWdnr1j5cNPBRu37ovIuZyoJ3pLvnrSZgN0QjurECFc9dKY7cG1Jdnm/G7ZTctzXG2XhWN+oNiEa8EkMchvYd8l8nm+hTJkGrVqEfXdo0THFmQxsWBb0/0LCLQP8VEVrfhKwtHilUjqVfJtu5QzJvjIyiXiW7pbVkCMPthjgH8eaN9ZKZVg68q5e5DPZJj2cwA37T1R7HW5+N722dPD7TMrWLhszEsP6mKYDKeI0lRmOSaHmBK8FBkpc+n4wPbV youremail@gmail.com" > /root/.ssh/authorized_keys

# utility and tool script
## qcvm_ipconfig.sh
COPY config/misc/qcvm_ipconfig.sh . 
RUN chmod 0755 /root/qcvm_ipconfig.sh \
     && ln -s /root/qcvm_ipconfig.sh /root/qcvm_ipconfig_s.sh
## qnap_backup.sh
COPY config/misc/qnap_backup.sh . 
RUN chmod 0644 qnap_backup.sh
## qcvm_ip.template
COPY config/misc/qcvm_ip.template . 
RUN chmod 0644 qcvm_ip.template
## qcvm_network.template
COPY config/misc/qcvm_network.template . 
RUN chmod 0644 qcvm_network.template
## Create root bin for excutable scripts
RUN mkdir -p bin
## init_ovirte.sh & post__init_ovirte.sh
COPY config/misc/init_ovirte.sh bin/
COPY config/misc/post_init_ovirte.sh bin/
RUN chmod 0755 bin/*
## ovirtshellrc
COPY config/misc/ovirtshellrc ./ovirtshellrc_new
RUN chmod 0644 ovirtshellrc_new
## deactivate_hosts.sh
COPY config/misc/deactivate_hosts.sh .
RUN chmod 0755 deactivate_hosts.sh

# Install & Setup oVirt
## Install basic tools
RUN yum -y install yum-plugin-priorities createrepo
RUN cat /etc/yum/pluginconf.d/priorities.conf

## Install ovirt repo
COPY config/ovirt/packages/*.repo /etc/yum.repos.d/
RUN chmod 0644 /etc/yum.repos.d/*

## Copy ansible repo
COPY config/ovirt/packages/ansible/ansible-2.5.2-1.el7.noarch.rpm /tmp/ansible/
COPY config/ovirt/packages/ansible/repodata* /tmp/ansible/repodata/
RUN chmod 0755 /tmp/ansible/ansible-2.5.2-1.el7.noarch.rpm

## Copy qcs repo
COPY  config/ovirt/packages/qcs/noarch/* /tmp/qcs/noarch/
COPY  config/ovirt/packages/qcs/repodata/* /tmp/qcs/repodata/
RUN ls /tmp/qcs
RUN chmod -R 755 /tmp/qcs/noarch

COPY config/repmgr/* /root/
RUN wget https://copr.fedorainfracloud.org/coprs/manageiq/ManageIQ-Master/repo/epel-7/manageiq-ManageIQ-Master-epel-7.repo -O /etc/yum.repos.d/manageiq-ManageIQ-Master-epel-7.repo
RUN yum -y install ovirt-engine-extension-aaa-ldap-setup rh-postgresql95-repmgr
RUN yum -y clean all \
    && rm -rf /var/cache/yum

# Clean up rpm files
RUN rm -rf /tmp/qcs/noarch/* \
    && rm -f /tmp/ansible/ansible-2.5.2-1.el7.noarch.rpm

# # dockerize helps us waiting for postgres being ready
ENV DOCKERIZE_VERSION v0.6.1
RUN curl -OL https://github.com/jwilder/dockerize/releases/download/$DOCKERIZE_VERSION/dockerize-linux-amd64-$DOCKERIZE_VERSION.tar.gz \
    && tar -C /usr/local/bin -xzvf dockerize-linux-amd64-$DOCKERIZE_VERSION.tar.gz

# # engine-setup needs the link to initctl
RUN ln -s /usr/bin/systemctl /usr/bin/initctl

# #oVirt
ENV OVIRT_PASSWORD admin
ENV OVIRT_PKI_ORGANIZATION local

COPY entrypoint.sh answers.conf.in qcs-engine-setup.sh /
COPY 999-ovirt-engine.conf /etc/ovirt-engine/engine.conf.d/
COPY patch/* patch/

COPY config/repmgr/auto_start_engine.sh /opt/rh/rh-postgresql95/root/usr/bin/
COPY config/repmgr/disable_node.sh /opt/rh/rh-postgresql95/root/usr/bin/
COPY config/repmgr/restore_old_master.sh /opt/rh/rh-postgresql95/root/usr/bin/
COPY config/ovirt/rh-postgresql95.sh /etc/profile.d/
RUN chmod 0644 /etc/profile.d/rh-postgresql95.sh
ADD config/repmgr/auto-start-engine-cron /etc/cron.d/auto-start-engine-cron
RUN chmod 0644 /etc/cron.d/auto-start-engine-cron

# # patch engine-setup so that it does not try to start or stop services with systemd
RUN patch -d/ -p0 < patch/setup.patch
RUN patch -d/ -p0 < patch/qts-otopi-420.patch
RUN patch -d/ -p0 < patch/qts-ovirt-host-deploy-420.patch
RUN patch -d/ -p0 < patch/otopi-admin-user-420.patch
RUN patch -d/ -p0 < patch/engine-iso-uploader-420.patch

# # For kubernetes copy pki template files to a backup directory
RUN cp -a --no-preserve=ownership /etc/pki/ovirt-engine /etc/pki/ovirt-engine.tmpl

# Persist this folder to keep the generated TLS certificates on the first start
VOLUME /etc/pki/ovirt-engine
# Persist this folder to keep the database backups
VOLUME /var/lib/ovirt-engine/backups

# Encrypt host communication
ENV HOST_ENCRYPT=false
# Try to provision hosts when they are added
ENV HOST_INSTALL=false
# use SSL connect to VDSM
ENV SSL_ENABLED=false
# Use host identifier when talking with the host, so that the host sees who it is from the engines view.
# This is valuable when working with ovirt-vdsmfake
ENV HOST_USE_IDENTIFIER=false
# HACK: Config BlockMigrationOnSwapUsagePercentage so that the vm will start in ovirt-engine
# For some reason this check fails the start vm - this should be figured out instead of this hack
ENV BLOCK_MIGRATION_ON_SWAP_USAGE_PERCENTAGE=9999

# If attaching a fresh engine to an already existing DB, override this UID with
# the UID of the admin user in that DB, to avoid the recration of the admin
# user.
ENV OVIRT_ADMIN_UID=49ec00bb-34d9-4cd0-a996-44b88b7c1098

EXPOSE 8080 8443

# Public reachable HTTPS port
ENV HTTPS_PORT 8443
ENV SSO_ALTERNATE_ENGINE_FQDNS="" 
#"localhost:8443 127.0.0.1:8443 ovirtengine.qnap:8443"

CMD /usr/sbin/init #; bash /entrypoint.sh
