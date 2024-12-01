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
./fm_install.sh run
```

This will link the script to the users home directory.
At various times during the install, the server need to be rebooted.
The script can just be rerun from  `./fm_install.sh run` from ubuntu's home directory

**Post Installation Tasks**

Once the installation has complete, logon to the admin console. Check everything looks ok, then restore the data from the old server
`./fm_install.sh restore`

Reboot
logon to  admin console, and if everything checks out, import the license certificate

Before letting users back on
Enable and run the backups, especially the hourly backup. The first backup of each type takes a while (about 45 minutes).
System runs a bit slower when running a full initial backup, so maybe an idea to run it before users get back on, or 
tell them the system might be a bit slower for a little while


**Offsite Backup**
The scripts are copied over and scheduled via systemd to run.
The actual rsync command is commented out so it can be checked manually it's running ok
~/filemaker-scripts/offsite_backup.sh



## TODO

- Change the colour of the shell prompt on the production server
- Setup a better way to download filemaker. Often very slow from Claris's server. Takes about 40 minutes to download.
- check the script around where certbot imports the certificate to FM. Had to logoff and on twice.
- get rid of the daytime offsite. Not needed anymore
- stop fmsserver when restoring data.
- setup my .bashrc with my preferences
- remove the dummy SA_MASTER files from /Removed_by_FMS/Removed in Databases and Containers directory.
- lost+found directorys of additional FM data drives get ownership changed. Probably should do this.
- maybe see if the admin api can set "block new users" as part of the install. Manually enable this after the installation has completed ok.
- container cleanup script set for wrong time. should be 5:30, not 5:00
- set the nighly offsite backup to do a database verify.
- GotNewSSL in letsencrypt wasn't created by sed correctly.  shouldn't have "DIR=" in it.
- A cleanup script that deletes all the install files that aren't needed after the install.
