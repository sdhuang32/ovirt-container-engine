FROM sdhuang32/c7-systemd

# Database
ENV REPMGR_USER repmgr
ENV REPMGR_DB repmgr
ENV POSTGRES_PORT 5432

RUN yum update -y
RUN yum install -y vim git net-tools rsync patch wget less openssh-server

RUN wget https://copr.fedorainfracloud.org/coprs/manageiq/ManageIQ-Master/repo/epel-7/manageiq-ManageIQ-Master-epel-7.repo -O /etc/yum.repos.d/manageiq-ManageIQ-Master-epel-7.repo
RUN yum -y install centos-release-scl-rh 
RUN yum -y install rh-postgresql95-postgresql-server rh-postgresql95-repmgr

RUN yum clean all && rm -rf /var/cache/yum

COPY ovirt-postgres-setup.sh entrypoint.sh /
COPY config/pg_hba.conf.append /root/
COPY config/postgresql.replication.conf /root/
COPY config/repmgr.conf.in /root/
COPY config/rh-postgresql95.sh /etc/profile.d/
RUN chmod 0644 /etc/profile.d/rh-postgresql95.sh
COPY config/disable_node.sh /opt/rh/rh-postgresql95/root/usr/bin/
COPY config/restore_old_master.sh /opt/rh/rh-postgresql95/root/usr/bin/

EXPOSE ${POSTGRES_PORT}

CMD /usr/sbin/init
