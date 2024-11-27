# Filemaker v21 Installation
## A somewhat automated install of Filemaker on Ubuntu.

- Only sets up a main server. No secondaries.
- Uses Certbot for it's SSL certificate from Lets Encrypt.
- Certbot will renew a cert about every 2 months. This requires a restart of filemaker which is automated.


## Prerequisites before running this script.
- Preferrably a fresh installation of Ubuntu 22.04.
- Any additional drives that Filemaker will use for databases, containers, backups etc are connected to the VM.
  - Drives need not be partitioned or formatted. The script will do that.
- Ports 22, 80, 443 & 5003 opened up to the VM
- The public IP address of the VM has been assigned to a DNS host record


From the users home directory on the VM
```bash
git clone https://github.com/hammondus/filemaker-install
cd filemaker-install
```

Edit `fm_install.sh`

The following variables at the top of the script need to be set.

`DOWNLOAD=https://dowloads.claris.com....`   needs to be to the location where you can download the filemaker installation .zip file
`HOSTNAME=fm.example.com`  needs to be set to the hostname that has been set to the public IP address of your VM
`CERTBOT_EMAIL=me@you.com`


Following that, are variables that will work, but should be set as requried.
TIMEZONE, FM_ADMIN_USER, PASSWORD & PIN

```bash
./fm_install.sh
```

This will copy the script to the users home directory.
At various times during the install, the server need to be rebooted.
The script can just be rerun from  `~/fm._install.sh`
