# amzn2/centos8 x86_64 # version 15 supported
# https://www.percona.com/doc/postgresql/15/installing.html
# https://docs.timescale.com/install/latest/self-hosted/installation-redhat/#install-self-hosted-timescaledb-on-red-hat-based-systems
dnf -y install https://dl.fedoraproject.org/pub/epel/epel-release-latest-8.noarch.rpm
sudo yum install -y https://repo.percona.com/yum/percona-release-latest.noarch.rpm
sudo percona-release setup -y ppg-15
sudo yum install -y percona-postgresql15-server percona-postgresql15-contrib percona-pg-stat-monitor15 percona-pgbadger
sudo /usr/pgsql-15/bin/postgresql-15-setup initdb
sudo echo "listen_addresses = '*'" >> /var/lib/pgsql/15/data/postgresql.conf
sudo sed -i 's@127.0.0.1/32@0.0.0.0/0@' /var/lib/pgsql/15/data/pg_hba.conf
sudo systemctl start postgresql-15
# sudo -u postgres psql
# https://www.datadoghq.com/blog/postgresql-monitoring
# https://www.postgresql.org/docs/current/pgstatstatements.html
echo "ALTER SYSTEM SET shared_preload_libraries = 'pg_stat_statements', 'pg_stat_monitor';" | sudo -u postgres psql 
sudo systemctl restart postgresql-15

# add timescaledb extension
# https://docs.timescale.com/install/latest/self-hosted/installation-redhat/#setting-up-the-timescaledb-extension
cat <<EOF | sudo tee /etc/yum.repos.d/timescale_timescaledb.repo
[timescale_timescaledb]
name=timescale_timescaledb
baseurl=https://packagecloud.io/timescale/timescaledb/el/$(rpm -E %{rhel})/\$basearch
repo_gpgcheck=1
gpgcheck=0
enabled=1
gpgkey=https://packagecloud.io/timescale/timescaledb/gpgkey
sslverify=1
sslcacert=/etc/pki/tls/certs/ca-bundle.crt
metadata_expire=300
EOF
sudo dnf install -y timescaledb-2-postgresql-15
echo "ALTER SYSTEM SET shared_preload_libraries = 'timescaledb';" | sudo -u postgres psql 
# CREATE EXTENSION IF NOT EXISTS timescaledb;
