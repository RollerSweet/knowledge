# Xtrabackup Usage on Rocky Linux

This guide provides instructions for installing, using, and configuring Xtrabackup on Rocky Linux.

## Installation

Run the following commands to install Xtrabackup:

```bash
# Install the Percona repository
yum -y install https://repo.percona.com/yum/percona-release-latest.noarch.rpm

# Import the GPG key
rpm --import /etc/pki/rpm-gpg/RPM-GPG-KEY-Percona

# Enable the Percona tools repository
percona-release enable-only tools release
percona-release enable-only tools

# Install Xtrabackup and lz4
yum -y install percona-xtrabackup-80
yum -y install lz4
```

## Backup and Restore

### Creating a Backup

To create a backup:

```bash
xtrabackup --backup --user=root --password='password' --target-dir=/root/backup
```

### Preparing the Backup

Before restoring, prepare the backup:

```bash
xtrabackup --prepare --target-dir=/root/backup
```

### Restoring the Backup

To restore the backup:

```bash
# Stop MySQL service
systemctl stop mysqld

# Remove existing MySQL data
rm -rf /var/lib/mysql/*

# Copy back the prepared backup
xtrabackup --copy-back --target-dir=/root/backup

# Set correct ownership and start MySQL
chown -R mysql:mysql /var/lib/mysql
systemctl start mysqld
```

## Configuring a Replica

To configure a server as a replica:

1. Stop the existing replication and reset:

```sql
STOP REPLICA;
RESET REPLICA ALL;
```

2. Configure the new replication settings:

```sql
CHANGE REPLICATION SOURCE TO
  SOURCE_HOST='master',
  SOURCE_USER='repl_user',
  SOURCE_PASSWORD='password',
  SOURCE_HEARTBEAT_PERIOD = 10,
  SOURCE_DELAY = 0,           
  SOURCE_AUTO_POSITION=1;
```

3. Start the replica:

```sql
START REPLICA;
```

4. Check the replica status:

```sql
SHOW REPLICA STATUS;
```

Remember to replace 'password' with your actual MySQL root password, and adjust other parameters (like hostnames and usernames) according to your specific setup.