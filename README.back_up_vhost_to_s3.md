# back_up_vhost_to_s3

Backs up the specified directories and databases to the specified bucket.

This is a convenience wrapper for [back_up_database_to_s3](https://github.com/AcroMedia/ansible-role-devops-utils/blob/master/scripts/deployables/back_up_database_to_s3) and [back_up_directory_to_s3](https://github.com/AcroMedia/ansible-role-devops-utils/blob/master/scripts/deployables/back_up_directory_to_s3), to save typing and apply consistent naming to archives.

The file naming convention used is `$BUCKET.$HOSTNAME.$DATE.(db|dir).$OBJECTNAME.$ext`.

**If an archive already exists in the s3 bucket, the script returns an error, and the archive will not be overwritten.**

Hostname is pulled from the internal `hostname -f` command on the server.


## Requirements
- AWS cli installed
- GNU Coreutils installed on the Ec2 instance the script is running from
- The two other back_up_* scripts (mentioned above) available in $PATH
- Read/write access to the specified S3 bucket from the Ec2 instance the script is running from (either via IAM role, or from ~/.aws/ config)
- Passwordless mysql as root operations; it's assumed that mysql credentials will be stored securely at /root/.my.cnf


## Required variables

All variables must be provided as environment variables. The tool does not accept any command line arguments.

* **BUCKET** is the only required variable, in the form of `s3://bucket-name/` or `s3://bucket-name/prefix`

* **DIRECTORIES**, if provided, is a quoted, space-separated list of absolute paths.

* **DATABASES**, if provided, is a quoted, space-separated list of databases.



## Tested on
- Ubuntu 18


## Example usage

```bash
sudo su -l
export BUCKET=s3://my-big-s3-bucket/bigcorp   # BUCKET can also include a meaningful prefix for your archive names.
export DIRECTORIES='/usr/local/ssl /etc /var/www/html'
export DATABASES='bigblog bigstore mysql'
/usr/local/sbin/back_up_vhost_to_s3
```

The above produces a set of S3 files that looks like the following:
```
s3://my-big-s3-bucket/bigcorp.ip-10-0-0-5.2020-09-04.db.bigblog.sql.gz
s3://my-big-s3-bucket/bigcorp.ip-10-0-0-5.2020-09-04.db.bigstore.sql.gz
s3://my-big-s3-bucket/bigcorp.ip-10-0-0-5.2020-09-04.db.mysql.sql.gz
s3://my-big-s3-bucket/bigcorp.ip-10-0-0-5.2020-09-04.dir.etc.tgz
s3://my-big-s3-bucket/bigcorp.ip-10-0-0-5.2020-09-04.dir.usr-local-ssl.tgz
s3://my-big-s3-bucket/bigcorp.ip-10-0-0-5.2020-09-04.dir.var-www-html.tgz
```
