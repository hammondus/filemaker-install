#!/bin/bash
set -u  # treat unset variables as an error
set -o pipefail  #returns any error in the pipe, not just last command
#set -x    # uncomment for debugging.

OPTIONS=$1

if [ "$OPTIONS" != "token" ] && [ "$OPTIONS" != "dev" ] && [ "$OPTIONS" != "run" ] && [ "$OPTIONS" != "restore" ]; then
  echo "script must be run with 1 option. They are:"
  echo
  echo "token - Get an admin api token, display it and exit. The admin api only gives out so many tokens"
  echo "dev - once you have a token, manually update the token variable so the script can be rerun many times"
  echo "run - run the script as it would be run in production"
  echo "restore - once the server has been installed and is up and running ok, restore data from the old servr"
exit 1
fi

# Before running this script
# Make sure the below variables are set
# On existing production server
# - Disable all scheduled tasks
# - close all databases.
# - clone this repo to the new server and run it.


#
#
# Required
# ALL The following variables are required
# These are split into 3 groups.
# 1. Those that have to be changed to suit your environment for this to work
# 2. Those that are recommended to be changed.
# 3. Those that cannot be changed.
# 4. Variables that just set options for some

# Many of these variable contain sensitive info, so the real versions of these are kept
# in a private directory which git ignores.

#
#
### 1. Variables that are required to be overriden for this script to work at all.
#
DOWNLOAD=https://downloads.claris.com/filemaker.zip
HOSTNAME=fm.example.com
CERTBOT_EMAIL=me@you.com
#Server email notifications
EMAIL_SENDER="email@server.com"
EMAIL_REPLY="noreply@server.com"
EMAIL_RECIPIENTS="me@you.com, you@me.com"
SMTP_SERVER="smtp.server.com"
SMTP_USER="mysmtpuser"
SMTP_PASSWORD="mysmtppassword"

RESTORE_SSH=user@fm.backupserver.com
BACKUP_SSH=user@fm.backupserver.com

# Server scripts from one of the databases are scheduled to run automatically on the server.
# This is the user and password of that database so those scripts can be setup.
SCRIPT_USER="dog"
SCRIPT_PASS="cat"

# Microsoft OAuth settings.
OAuthID="a69asdfa2c"
OAuthKey="kU~0sadf"
OAuthDirectoryID="dsdafedf"

# Rsync Offsite Backup Settings
RSYNC_DAY=user@backup1.server.com
RSYNC_NIGHT=user@backup2.server.com

#Be careful with the drive settings. The script doesn't check that what you have put in is correct.
#Only put in devices that are completely blank. Devices listed below will be partitioned and formatted.
DRIVE_DATABASES=/dev/nvme2n1
DRIVE_CONTAINERS=/dev/nvme1n1
DRIVE_BACKUPS=/dev/nvme3n1

#
#
### 2. Variables that should be changed to suit, but script will work as is, except for the "secret" stuff below. These need to be set..
#
#
TIMEZONE=Australia/Melbourne
FM_ADMIN_USER=dog
FM_ADMIN_PASSWORD=pass
FM_ADMIN_PIN=1234

# If you change $HOME_LOCATION or $SCRIPT_LOCATION, those variables are used in other scripts.

#Databases, containers and backups are stored in these location which are then mounted on seperate drives
FM_DATA=/opt/FileMaker/Data
FM_DATABASES=$FM_DATA/Databases
FM_CONTAINERS=$FM_DATA/Containers
FM_BACKUPS=/opt/FileMaker/Backups


HOME_LOCATION=/home/ubuntu
SCRIPT_LOCATION=$HOME_LOCATION/filemaker-install   # this assumes you did the git clone from the home directory.
STATE=$SCRIPT_LOCATION/state
ASSISTED_FILE=$SCRIPT_LOCATION/fminstall/AssInst.txt
INSTALLED_SCRIPTS=$HOME_LOCATION/filemaker-scripts     # Various scripts used after the install are put here.

#
#
### SECRETS
#
# Many of the above variables need to be overriden with the proper values. hostname, usernames and passwords
# for obvious reasons, they aren't included in a public repo, so they are kept as a seperate file which overrides many
# of the above variables.
SECRETS=$SCRIPT_LOCATION/secrets/filemaker-install 

# Override variables with private data
. $SECRETS/variables    # variables that override many of the above variables.
. $SECRETS/fm_auth      # Filemaker server username and password used by various setup and post install scripts.

# Server Settings
PARALLEL_BACKUPS=Yes   # Enable parallel backups
EXTERNAL_AUTH=Yes


# Optional software to install
# Install optional programs I find handy. Change this to No if not needed
GLANCES=Yes
NCDU=Yes
IOTOP=Yes

#
#
### 3. Variables that should not be changed.
#
WEBROOTPATH="/opt/FileMaker/FileMaker Server/NginxServer/htdocs/httpsRoot/"

########################
### END OF VARIABLES ###
########################

# load in functions
. $SCRIPT_LOCATION/functions

#######################

# Create directory where post install filemaker scripts will live
if [ ! -d $INSTALLED_SCRIPTS ]; then
  mkdir $INSTALLED_SCRIPTS || { echo "Couldn't create filemaker scripts directory: $INSTALLED_SCRIPTS"; exit 1; }
fi




#Check we are on the correct version of Ubuntu
if [ -f /etc/os-release ]; then
  . /etc/os-release
  VER=$VERSION_ID
  if [ "$VER" != "22.04" ]; then
    echo "Wrong version of Ubuntu. Must be 22.04"
    echo "You are running" $VER 
    exit 1
  else
    echo "Good. You are Ubuntu" $VER
  fi
fi

# Link this script to the home directory so it can easily be run it after login
if [ ! -f ~/fm_install.sh ]; then
  ln -s $SCRIPT_LOCATION/fm_install.sh $HOME_LOCATION/fm_install.sh
  echo "----------------------------------------------------------------------------------------"
  echo "When this install asks you to reboot and rerun the script, it is copied to ~/fm_install.sh"
  read -p "Press return to continue "
fi


# The state directory is used so that this script can keep track of where it is up to between reboots
if [ ! -d $STATE ]; then
  echo "creating state directory"
  mkdir $STATE || { echo "Couldn't create state directory"; exit 1; }
fi


if [ ! -f $STATE/timezone-set ]; then 
  sudo timedatectl set-timezone $TIMEZONE || { echo "Error setting timezone"; exit 1; }
  timedatectl
  touch $STATE/timezone-set
fi

if [ ! -f $STATE/hostname-set ]; then
  sudo hostnamectl set-hostname $HOSTNAME || { echo "Error setting hostname"; exit 1; }
  touch $STATE/hostname-set
fi

#Make sure the system is up to date and reboot if necessary
if [ ! -f $STATE/apt-upgrade ]; then
  echo 'apt update/upgrade not done. doing it now'
  sudo apt update || { echo "Error running apt update"; exit 1; }
  sudo DEBIAN_FRONTEND=noninteractive apt upgrade -y || { echo "Error running apt upgrade"; exit 1; }
  touch $STATE/apt-upgrade
  if [ -f /var/run/reboot-required ]; then
    echo "Reboot is required. Reboot then rerun this script"
    reboot_rerun
  fi
fi


#Install unzip if it's not installed. Not optional
#The download from claris needs to be unzipped.
#jq is used to process JSON in the admin api

type unzip > /dev/null 2>&1 || sudo apt install unzip -y
type jq > /dev/null 2>&1 || sudo apt install jq -y

#Install optional software if they have been selected
if [ "$GLANCES" == "Yes" ]; then
  type glances > /dev/null 2>&1 || sudo apt install glances -y || { echo "Error installing Glances"; exit 9; }
fi
if [ "$NCDU" == "Yes" ]; then
  type ncdu > /dev/null 2>&1 || sudo apt install ncdu -y || { echo "Error installing NCDU"; exit 9; }
fi
if [ "$IOTOP" == "Yes" ]; then
  type iotop > /dev/null 2>&1 || sudo apt install iotop-c -y || { echo "Error installing iotop-c"; exit 9; }
fi


# Partition, format and attached the additional drives.
#

if [ ! -f $STATE/drive-setup ]; then
  echo "Label the drives"
  sudo parted -s $DRIVE_DATABASES mklabel gpt || { echo "error with mklabel on database drive"; exit 1; }
  sudo parted -s $DRIVE_CONTAINERS mklabel gpt || { echo "error with mklabel on containers drive"; exit 1; }
  sudo parted -s $DRIVE_BACKUPS mklabel gpt || { echo "error with mklabel on backup drive"; exit 1; }

  echo "Partition the drives"
  sudo parted -s $DRIVE_DATABASES mkpart Databases 0% 100% || { echo "error with mkpark on database drive"; exit 1; }
  sudo parted -s $DRIVE_CONTAINERS mkpart Containers 0% 100% || { echo "error with mkpart on containers drive"; exit 1; }
  sudo parted -s $DRIVE_BACKUPS mkpart Backups 0% 100% || { echo "error with mkpart on backup drive"; exit 1; }
  
  echo "Format the drives"
  sudo mkfs.ext4 -m 0 ${DRIVE_DATABASES}p1 || { echo "error with mkfs on database drive"; exit 1; }
  sudo mkfs.ext4 -m 0 ${DRIVE_CONTAINERS}p1 || { echo "error with mkfs on containers drive"; exit 1; }
  sudo mkfs.ext4 -m 0 ${DRIVE_BACKUPS}p1 || { echo "error with mkfs on backup drive"; exit 1; }

  touch $STATE/drive-setup
fi


#Download filemaker
if [ ! -f $STATE/filemaker-downloaded ]; then
  rm -rf $SCRIPT_LOCATION/fmdownload
  if mkdir $SCRIPT_LOCATION/fmdownload; then
    cd $SCRIPT_LOCATION/fmdownload
    if wget $DOWNLOAD; then
      unzip ./fms*
    else
      echo "Error downloading filemaker."
      exit 1
    fi
    touch $STATE/filemaker-downloaded
  else
    echo "Error creating Filemaker download directory at $SCRIPT_LOCATION/fmdownload"
    exit 1
  fi
fi

#Copy install file
# The only thing we want from the claris .zip file is the *.deb installer.
if [ ! -f $STATE/filemaker-install-file ]; then
  mkdir $SCRIPT_LOCATION/fminstall
  cp $SCRIPT_LOCATION/fmdownload/filemaker-server*.deb $SCRIPT_LOCATION/fminstall || { echo "Error copying .deb file to fminstall directory"; exit 1; }
  touch $STATE/filemaker-install-file
fi


#Install filemaker
if [ ! -f $STATE/filemaker-installed ]; then
  cd $SCRIPT_LOCATION/fminstall
  # Create the assisted install file.
  echo "[Assisted Install]" > $ASSISTED_FILE
  echo "License Accepted=1" >> $ASSISTED_FILE
  echo "Deployment Options=0" >> $ASSISTED_FILE
  echo "Admin Console User=$FM_ADMIN_USER" >> $ASSISTED_FILE
  echo "Admin Console Password=$FM_ADMIN_PASSWORD" >> $ASSISTED_FILE
  echo "Admin Console PIN=$FM_ADMIN_PIN" >> $ASSISTED_FILE
  echo "Filter Databases=0" >> $ASSISTED_FILE
  echo "Remove Sample Database=1" >> $ASSISTED_FILE
  echo "Use HTTPS Tunneling=1" >> $ASSISTED_FILE
  echo "Swap File Size=4G" >> $ASSISTED_FILE
  echo "Swappiness=10" >> $ASSISTED_FILE

  echo "Install Filemaker Server"
  sudo FM_ASSISTED_INSTALL=$ASSISTED_FILE apt install ./filemaker-server*.deb -y || { echo "Error installing Filemaker"; exit 1; }
  touch $STATE/filemaker-installed
fi

if [ ! -f $STATE/certbot-installed ]; then
  echo "Install Certbot"
  sudo snap install --classic certbot || { echo "Error installing Certbot."; exit 1; }
  sudo ln -s /snap/bin/certbot /usr/bin/certbot
  touch $STATE/certbot-installed
fi

if [ ! -f $STATE/certbot-certificate ]; then
  echo "install Certbot certificate"
  sudo ufw allow http
  sudo certbot certonly --webroot \
    -w "$WEBROOTPATH" \
    -d $HOSTNAME \
    --agree-tos --non-interactive \
    -m $CERTBOT_EMAIL \
    || { echo "Error getting Certificate with Certbot."; sudo service ufw start; exit 1; }
  sudo ufw deny http

  # Setup certbot triggers to enable / disable http when it attempts to renew the certificate
  sudo cp $SCRIPT_LOCATION/files/scripts/certbot-pre-openhttp /etc/letsencrypt/renewal-hooks/pre/openhttp
  sudo cp $SCRIPT_LOCATION/files/scripts/certbot-post-closehttp /etc/letsencrypt/renewal-hooks/post/closehttp
  
  sed "s#DIR=xxx#DIR=$INSTALLED_SCRIPTS#" \
    $SCRIPT_LOCATION/files/scripts/certbot-deploy-GotNewSSL | sudo tee /etc/letsencrypt/renewal-hooks/deploy/GotNewSSL > /dev/null

  sudo chmod +x /etc/letsencrypt/renewal-hooks/pre/openhttp
  sudo chmod +x /etc/letsencrypt/renewal-hooks/post/closehttp
  sudo chmod +x /etc/letsencrypt/renewal-hooks/deploy/GotNewSSL

  touch $STATE/certbot-certificate

  logoff_rerun   # need to logoff and on again now otherwise fmsadmin doesn't work without sudo
fi

if [ ! -f $STATE/certbot-certificate-loaded-filemaker ]; then
  echo "Importing Certificates to filemaker:"
  # The certs in the live directory are just links to the certs.
  # fmsadmin can't handle using links to files, so we need to find where the actual certs are.
  CERTFILEPATH=$(sudo realpath "/etc/letsencrypt/live/$HOSTNAME/fullchain.pem")
  PRIVKEYPATH=$(sudo realpath "/etc/letsencrypt/live/$HOSTNAME/privkey.pem")
  sudo fmsadmin certificate import $CERTFILEPATH --keyfile $PRIVKEYPATH \
    -u $FM_ADMIN_USER -p $FM_ADMIN_PASSWORD -y || { echo "Filemaker unable to import certificate"; exit 1; }
  sudo service fmshelper restart

  touch $STATE/certbot-certificate-loaded-filemaker
  sudo service fmshelper restart
  logoff_rerun   # need to logoff and on again now otherwise fmsadmin doesn't work without sudo
fi


## At this point, the server should be up and running with an SSL cert.

#Create additional directories for Databases, Containers & Backups and attached drives
if [ ! -f $STATE/additional-directories ]; then
  sudo mkdir -p $FM_DATABASES $FM_CONTAINERS $FM_BACKUPS || { echo "Unable to create Data / Backup directories"; exit 1; }

  DATABASE_UUID=$(lsblk -n -o UUID ${DRIVE_DATABASES}p1)
  CONTAINER_UUID=$(lsblk -n -o UUID ${DRIVE_CONTAINERS}p1)
  BACKUP_UUID=$(lsblk -n -o UUID ${DRIVE_BACKUPS}p1)

  #Check we have UUID's for all drives
  if [ -z $DATABASE_UUID ] || [ -z $CONTAINER_UUID ] || [ -z $BACKUP_UUID ]; then
    echo "Don't have all required UUID's"
    echo DATABASE_UUID: $DATABASE_UUID
    echo CONTAINER_UUID: $CONTAINER_UUID
    echo BACKUP_UUID: $BACKUP_UUID
    exit 1
  fi
  
  if [ ! -f $STATE/fstab ]; then
    echo "UUID=$DATABASE_UUID  $FM_DATABASES ext4 defaults,nofail 0 2" | sudo tee -a /etc/fstab
    echo "UUID=$CONTAINER_UUID $FM_CONTAINERS ext4 defaults,nofail 0 2" | sudo tee -a /etc/fstab
    echo "UUID=$BACKUP_UUID $FM_BACKUPS ext4 defaults,nofail 0 2" | sudo tee -a /etc/fstab
    touch $STATE/fstab
  fi

  sudo mount -a || { echo "Error mounting additional drives. Check /etc/fstab before rerunning fm_install.sh"; exit 1; }
  sudo chown -R fmserver:fmsadmin $FM_DATA || { echo "Error setting permissions on additional directories $FM_DATA/*"; exit 1; }
  sudo chown -R fmserver:fmsadmin $FM_BACKUPS || { echo "Error setting permissions on additional directory $FM_BACKUPS/"; exit 1; }
  touch $STATE/additional-directories
fi


# The SA_MASTER.fmp12 database needs to be uploaded to the server and started to setup
# some of the scheduled scripts on the server.
# You can just upload a dummy .fmp12 files that has scripts of the same name that you want to schedule.
# After the script schedules are setup, the dummy database can be deleted.
# Later on, all the production data can be copied over to the new server.

# These scripts schedules are setup later on when the admin api is turned on.
# The copying is done here as if you copy the database files, then try to start them straight
# away, filemaker doesn't like it. By copying them now, there will be a bit of time before
# trying to start the databases, 

if [ ! -f $STATE/copy-dummy-samaster ]; then
  sudo cp $SCRIPT_LOCATION/files/SA_MASTER_DUMMY.fmp12 $FM_DATABASES/SA_MASTER.fmp12 || { echo "Error copying dummy database"; exit 1; }
  sudo chmod 664 $FM_DATABASES/SA_MASTER.fmp12 || { echo "Error setting permissions on dummy database"; exit 1; }
  sudo chown fmserver:fmsadmin $FM_DATABASES/SA_MASTER.fmp12  || { echo "Error setting ownership on dummy database"; exit 1; }
  touch $STATE/copy-dummy-samaster
fi

## Need to enable the data api. Then rest of server config can be done via the admin api
if [ ! -f $STATE/admin-api-enabled ]; then
  fmsadmin enable fmdapi -u $FM_ADMIN_USER -p $FM_ADMIN_PASSWORD || { echo "Error enabling data api"; exit 1; }
  fmsadmin start fmdapi -u $FM_ADMIN_USER -p $FM_ADMIN_PASSWORD || { echo "Error starting data api"; exit 1; }
  touch $STATE/admin-api-enabled
fi

#This is the most basic request to tell the admin api is working. Not auth is required for this to work.
resp=`curl -s https://$HOSTNAME/fmi/data/v2/productInfo | jq --raw-output '.messages[0].message' 2>/dev/null` 
if [ "$resp" != 'OK' ]; then
  echo "Can't connect to server: $HOSTNAME"
  echo $resp
  exit 9
fi


## This is where snapshot of server was taken for the purpose of restoring to a known
# point and reruning some of the setup scripts


API_URL="$HOSTNAME/fmi/admin/api/v2"

#Base64 encode the username and password for the api
AUTH=$(echo -n $FM_ADMIN_USER:$FM_ADMIN_PASSWORD | base64)

# Setting token is just for testing and development
# You can't get and admin api token too often. The server stops handing them out

if [ $OPTIONS == "token" ]; then
 json=`curl -s https://$API_URL/user/auth \
  -X POST \
  -H "Authorization: Basic $AUTH" \
  -H 'Content-Type: application/json'`

  ok=`echo $json | jq --raw-output '.messages[0].text'`
  if [ "$ok" != 'OK' ]; then
    echo "Can't get authorisation token"
    echo $json
    exit 9
  fi

  #Get token from json. This token is used for the remainder of requests.
  token=`echo $json | jq --raw-output '.response.token'` || { echo "Error parsing token json"; exit 1; }
  echo "token: $token"
  exit 9
fi

if [ $OPTIONS == "dev" ]; then
  #token for testing
  token=eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJzaWQiOiJiNTE0YzBhZC01YzY4LTRjMjktODVjOC0yMjNkOTVmM2JiMmUiLCJpYXQiOjE3MzIzNTY0NTJ9.0BKUFtU0i5LLYLQrScL_bLBp3GerS6eFxhWkFQEKkY8
  token=eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJzaWQiOiIyZGQ1Y2EwNy1mNTA0LTQ4OGYtOGYyMy03NjMxYjQwZTA0OTEiLCJpYXQiOjE3MzI5Mjk2OTV9.sY0Kt4-MBOC6UcovkiGN97iasbMa6ZjTRvJdRTpmI7o
fi

if [ $OPTIONS == "run" ]; then
 json=`curl -s https://$API_URL/user/auth \
  -X POST \
  -H "Authorization: Basic $AUTH" \
  -H 'Content-Type: application/json'`

  ok=`echo $json | jq --raw-output '.messages[0].text'`
  if [ "$ok" != 'OK' ]; then
    echo "Can't get authorisation token"
    echo $json
    exit 9
  fi

  #Get token from json. This token is used for the remainder of requests.
  token=`echo $json | jq --raw-output '.response.token'` || { echo "Error parsing token json"; exit 1; }
fi


#Check token works
json=`curl -s https://$API_URL/server/metadata \
 -H "Authorization: Bearer $token" \
 -H "Content-Type: application/json"`
#jsonok "Token not working"

echo "Admin API Token works. Lets continue...."


# echo "Server General Settings"
if [ ! -f $STATE/server-general-settings ]; then
  echo "Server General Settings"
  echo "Increase cache from default of 512M to 1G"
  echo "Set it so databases aren't automatically opened on server start"
  END_POINT="server/config/general"
  method="PATCH"
  data='{ "cacheSize": 1024,
 "openDatabasesOnStart": false }'

  api_curl $method $data
  jsonok "Couldn't set general database settings"
  touch $STATE/server-general-settings
fi

# Enable parallel backups
if [ "$PARALLEL_BACKUPS" == "Yes" ] && [ ! -f $STATE/parallel-backups ]; then
  END_POINT="server/config/parallelbackup"
  echo "Enable Parallel Backups"
  method="PATCH"
  data='{ "parallelBackupEnabled": true }'
  api_curl $method $data
  jsonok "Couldn't enable parallel backups"
  touch $STATE/parallel-backups
fi

#
#
if [ ! -f $STATE/additional-folders-configured ]; then
  echo "Setting up additional folders for databases and containers"
  END_POINT="server/config/additionaldbfolder"
  method="PATCH"
  data=' { "UseOtherDatabaseRoot": true,
   "DatabaseRootPath": "filelinux:/opt/FileMaker/Data/Databases/",
   "UseDatabaseRoot1_RC": true,
   "DatabaseRootPath1_RC": "filelinux:/opt/FileMaker/Data/Containers/",
   "backupDatabaseRoot1_RC": true
  }'
  api_curl $method $data
  jsonok "Couldn't set additional database/container directories"
  touch $STATE/additional-folders-configured
fi

if [ ! -f $STATE/backup-path ]; then
  echo "Setting up backup to use seperate backup drive"
  END_POINT="server/backuppath"
  method="PATCH"
  data=' { "backupPath": "filelinux:/opt/FileMaker/Backups/" }'
  api_curl $method $data
  jsonok "Couldn't set backup location"

  touch $STATE/backup-path
fi


#
#
if [ ! -f $STATE/enable-webdirect ]; then
  echo enabling web direct
  END_POINT="webdirect/config"
  method="PATCH"
  data=' { "enabled": true }'
  api_curl $method $data
  jsonok "Couldn't enable webdirect"
  touch $STATE/enable-webdirect
fi
#
#
if [ ! -f $STATE/enable-wpe ]; then
  echo enabling web publishing engine
  END_POINT="wpe/config/1"
  method="PATCH"
  data=' { "enabled": true }'
  api_curl $method $data
  jsonok "Couldn't enable web publishing engine"
  touch $STATE/enable-wpe
fi

#
#
if [ ! -f $STATE/enable-email ]; then
  echo enabling email notifications
  END_POINT="server/notifications/email/available"
  method="PATCH"
  data=' { "emailNotification": 1 }'
  api_curl $method $data
  jsonok "Couldn't enable email notifications"
  touch $STATE/enable-email
fi

#
#
if [ ! -f $STATE/setup-email ]; then
  echo enabling email notifications
  END_POINT="server/notifications/email"
  method="PATCH"
  data=' { "emailSenderAddress": "'$EMAIL_SENDER'",
    "emailReplyAddress": "'$EMAIL_REPLY'",
    "emailRecipients": "'$EMAIL_RECIPIENTS'",
    "smtpServerAddress": "'$SMTP_SERVER'",
    "smtpServerPort": 587,
    "smtpUsername": "'$SMTP_USER'",
    "smtpPassword": "'$SMTP_PASSWORD'",
    "smtpAuthType": 3,
    "smtpSecurity": 4,
    "notifyLevel": 1
  }'
  api_curl $method $data
  jsonok "Couldn't configure email settings"
  touch $STATE/setup-email
fi


if [ $OPTIONS == "list" ]; then
  END_POINT="schedules"
  method="GET"
  data="{}"
  api_curl $method $data
  jsonok "list schedules"
  echo $json
  exit 9
fi

#########################################################################
##                            BACKUPS                                  ##
#########################################################################
## Setup all the backups that run in addition to the default daily backup.

# Offsite backups.
# One runs at midday, the other at 1am. The one at 1am does a verify. Each only keeps 1 generation.

# Hourly
# backup that runs every hour from 6:05 to 23:05 every day.
# 40 generations are kept

# Clone Only backup.
# There take up bugger all space, so keep heaps of them as.. why not.

if [ ! -f $STATE/configure-backups ]; then
#offsite backups
  END_POINT="schedules/backup"
  method="POST"
  data='{
  "name": "offsite_day",
  "backupType": {
    "resourceType": "ALL_DB",
    "backupTarget": "filelinux:/opt/FileMaker/Backups/",
    "maxBackups": 1,
    "clone": false,
    "verify": false
  },
  "enabled": false,
  "everyndaysType": {
    "startTimeStamp": "2024-11-16T11:30:00",
    "dailyDays": 1
  }
}'
api_curl $method $data
jsonok "Couldn't configure backup"
  data='{
  "name": "offsite_night",
  "backupType": {
    "resourceType": "ALL_DB",
    "backupTarget": "filelinux:/opt/FileMaker/Backups/",
    "maxBackups": 1,
    "clone": false,
    "verify": false
  },
  "enabled": false,
  "everyndaysType": {
    "startTimeStamp": "2024-11-16T01:00:00",
    "dailyDays": 1
  }
}'
api_curl $method $data
jsonok "Couldn't configure backup"

#Clone backup. These are very small, so can keep lots of generations.
  data='{
  "name": "clone",
  "backupType": {
    "resourceType": "ALL_DB",
    "backupTarget": "filelinux:/opt/FileMaker/FileMaker Server/Data/ClonesOnly/",
    "maxBackups": 60,
    "clone": false,
    "cloneOnly": true,
    "verify": false
  },
  "enabled": false,
  "everyndaysType": {
    "startTimeStamp": "2024-11-16T05:00:00",
    "dailyDays": 1
  }
}'
api_curl $method $data
jsonok "Couldn't configure backup"

echo "hourly backups"
  END_POINT="schedules/backup"
  method="POST"
  data='{
  "name": "hourly",
  "backupType": {
    "resourceType": "ALL_DB",
    "backupTarget": "filelinux:/opt/FileMaker/Backups/",
    "maxBackups": 40,
    "clone": false,
    "verify": false
  },
  "enabled": false,
  "everyndaysType": {
    "startTimeStamp": "2024-11-16T06:05:00",
    "dailyDays": 1,
    "repeatTask": {
      "repeatFrequency": 1,
      "repeatInterval": "HOURS",
      "endTime": "23:05:00"
    }
  }
}'

  api_curl $method $data
  jsonok "Couldn't configure backup"

  touch $STATE/configure-backups
fi


##############################
##  Setup Script Schedules  ##
##############################

if [ ! -f $STATE/configure-schedules ]; then
  echo "setup scheduled scripts"
  END_POINT="schedules/systemscript"
  method="POST"
  data='{
    "name": "Garbage Collection",
    "systemScriptType": {
      "osScript": "filelinux:/opt/FileMaker/FileMaker Server/Data/Scripts/Sys_Default_RunGarbageCollection",
      "osScriptParam": "",
      "timeout": 0
    },
    "enabled": true,
    "everyndaysType": {
      "startTimeStamp": "2024-11-16T04:15:00",
      "dailyDays": 1
    }
  }'
  api_curl $method $data
  jsonok "Couldn't setup garbage collection system script."

  END_POINT="schedules/systemscript"
  method="POST"
  data='{
    "name": "Purge Temp DB",
    "systemScriptType": {
      "osScript": "filelinux:/opt/FileMaker/FileMaker Server/Data/Scripts/Sys_Default_PurgeTempDB",
      "osScriptParam": "",
      "timeout": 0
    },
    "enabled": true,
    "everyndaysType": {
      "startTimeStamp": "2024-11-16T04:30:00",
      "dailyDays": 1
    }
  }'
  api_curl $method $data
  jsonok "Couldn't setup Purge Temp DB system script"

  # Open the dummy SA_MASTER database that was copied previously.
  fmsadmin open SA_MASTER -u $FM_ADMIN_USER -p $FM_ADMIN_PASSWORD  || { echo "Unable to open SA_MASTER db"; exit 1; }
  sleep 1

  END_POINT="schedules/filemakerscript"
  method="POST"
  data='{
    "name": "Server Master 3 hourly",
    "filemakerScriptType": {
      "autoAbort": false,
      "fmScriptName": "SERVER_MASTER",
      "fmScriptAccount": "'$SCRIPT_USER'",
      "fmScriptPassword": "'$SCRIPT_PASS'",
      "resource": "file:SA_MASTER",
      "timeout": 0
    },
    "enabled": false,
    "everyndaysType": {
      "startTimeStamp": "2024-11-16T06:00:00",
      "dailyDays": 1,
      "repeatTask": {
        "repeatFrequency": 3,
        "repeatInterval": "HOURS",
        "endTime": "23:01:00"
      }
    }
  }'
  api_curl $method $data
  jsonok "Couldn't setup SERVER_MASTER 3 hourly script"

  touch $STATE/configure-schedules

  END_POINT="schedules/filemakerscript"
  method="POST"
  data='{
    "name": "Container Cleanup",
    "filemakerScriptType": {
      "autoAbort": false,
      "fmScriptName": "Container_Cleanup",
      "fmScriptAccount": "'$SCRIPT_USER'",
      "fmScriptPassword": "'$SCRIPT_PASS'",
      "resource": "file:SA_MASTER",
      "timeout": 0
    },
    "enabled": false,
    "everyndaysType": {
      "startTimeStamp": "2024-11-16T05:00:00",
      "dailyDays": 1
    }
  }'
  api_curl $method $data
  jsonok "Couldn't setup Container Cleanup script"

  #now the scripts have been setup, the dummy SA_MASTER is no longer needed.
  fmsadmin close SA_MASTER -y -u $FM_ADMIN_USER -p $FM_ADMIN_PASSWORD
  fmsadmin remove SA_MASTER -y -u $FM_ADMIN_USER -p $FM_ADMIN_PASSWORD

  touch $STATE/configure-schedules
fi


###############################################
##  Setup External Authentication Schedules  ##
###############################################
if [ "$EXTERNAL_AUTH" == "Yes"  ] && [ ! -f $STATE/external-auth ]; then
  echo "Setting up External Auth"
  END_POINT="extauth/dbsignin/externalserver"
  method="PATCH"
  data='{ "EnableExtServerSignin": true }'
  api_curl $method $data
  jsonok "Couldn't enable External Server Signin"

  END_POINT="extauth/provider/microsoft"
  method="PATCH"
  data='{
    "AzureID": "'$OAuthID'",
    "AzureKey": "'$OAuthKey'",
    "AzureDirectoryID": "'$OAuthDirectoryID'"
  }'
  api_curl $method $data
  jsonok "Couldn't confgure Microsoft OAuth"

  END_POINT="extauth/dbsignin/microsoft"
  method="PATCH"
  data='{ "EnableMSSignin": true }'
  api_curl $method $data
  jsonok "Couldn't confgure Microsoft DB Signin"

  touch $STATE/external-auth
fi


##############################
##  Setup Systemd scripts   ##
##############################
if [ ! -f $STATE/systemd-scripts ];then
  echo
  echo "configuring systemd scripts"
  sed "s#DIR=xxx#DIR=$INSTALLED_SCRIPTS#;s#DOMAIN=xxx#DOMAIN=$HOSTNAME#;s#FMAUTH=xxx#FMAUTH=$INSTALLED_SCRIPTS/fm_auth#" \
   $SCRIPT_LOCATION/files/scripts/refreshFilemakerSSL.sh > $INSTALLED_SCRIPTS/refreshFilemakerSSL.sh

  sed "s#DIR=xxx#DIR=$INSTALLED_SCRIPTS#;s#FMAUTH=xxx#$INSTALLED_SCRIPTS/fm_auth#" \
   $SCRIPT_LOCATION/files/scripts/ServerStart.sh > $INSTALLED_SCRIPTS/ServerStart.sh

  sed "s#FM_BACKUPS#$FM_BACKUPS#;s#FMAUTH=xxx#FMAUTH=$INSTALLED_SCRIPTS/fm_auth#" \
   $SCRIPT_LOCATION/files/scripts/offsite_backup.sh > $INSTALLED_SCRIPTS/offsite_backup.sh



  cp $SECRETS/fm_auth $INSTALLED_SCRIPTS
  chmod +x $INSTALLED_SCRIPTS/*.sh
  chmod 600 $INSTALLED_SCRIPTS/fm_auth

  # Copy over all the systemd services and timers that will be setup
  sudo cp $SCRIPT_LOCATION/files/systemd/*.timer /etc/systemd/system
  sudo cp $SCRIPT_LOCATION/files/systemd/htmlemail.service /etc/systemd/system

  SERVICE=fmSSLrefresh.service; sed_systemd
  SERVICE=offsite-backup-night.service; sed_systemd
  SERVICE=startup.service; sed_systemd

  # Enable the systemd services.
  sudo systemctl enable startup
  sudo systemctl enable --now offsite-backup-night.timer
  sudo systemctl enable --now fmSSLrefresh.timer
  sudo systemctl enable --now htmlemail

  touch $STATE/systemd-scripts
fi

echo "Installation complete"
echo "To restore data, run this script with the 'restore' parameter"
echo "Logon to the filemaker admin console and enable the backups and scheduled scripts"

###########################################################
##             Restore data from current server          ##
###########################################################

#Everything in filemaker should be owned by fmserver:fmsadmin

## Database & Container files should be   664 rw-rw-r--
## Database folders should be             775 rwxrwxr-x

if [ "$OPTIONS" == "restore" ]; then
  echo
  echo
  echo "Will logon to the backup server to check it works before continuing on with installation"
  echo "If it does logon, CTRL-D to exit back and continue installation"
  read -p "Press enter to attempt logon to backup server:"

  ssh -i "$SECRETS/fm.pem" -o "StrictHostKeyChecking=accept-new" $RESTORE_SSH || { echo "Error SSHing into server to restore data"; exit 1; }
  echo "Logon to backup server successful. Continuing on with install"
  
  cp $SECRETS/fm_auth $INSTALLED_SCRIPTS || { echo "Error copying fm_auth"; exit 1; }
  cp -f $SECRETS/id_rsa $HOME_LOCATION/.ssh || { echo "Error copying id_rsa"; exit 1; }
  chmod 400 $HOME_LOCATION/.ssh/id_rsa  || { echo "Error chmodding id_rsa to 400"; exit 1; }


  echo
  echo "restore databases"
  sleep 1
  sudo rsync -ptlvzh --progress --stats --chmod=F664,D775 \
   -e "ssh -i $SECRETS/fm.pem" \
   $RESTORE_SSH:/opt/FileMaker/Data/Databases/*.fmp12 \
   /opt/FileMaker/Data/Databases/

  echo
  echo "restore containers"
  sleep 1
  sudo rsync -rptlvzh --progress --stats --chmod=F664,D775 \
   -e "ssh -i $SECRETS/fm.pem" \
   $RESTORE_SSH:/opt/FileMaker/Data/Containers/RC_Data_FMS/* \
   /opt/FileMaker/Data/Containers/RC_Data_FMS/

  sudo chown -R fmserver:fmsadmin /opt/FileMaker/Data/

  #sudo find /opt/FileMaker/Data/ -type d -exec chmod 775 {} +
  #sudo find /opt/FileMaker/Data/ -type f -exec chmod 664 {} +

fi

exit 99

## TO DO

# I just uploaded a zipped clone of SA_MASTER to the repository.
# This needs to be unzipped, and loaded up as a database so the schedule can be setup.
# Hopefully the database can be deleted without breaking the scheduled tasks??

cp $SCRIPT_LOCATION/secrets/fm_auth $INSTALLED_SCRIPTS

FILE=$SCRIPT_LOCATION/files/scripts/refreshFilemakerSSL.sh
cp $FILE $INSTALLED_SCRIPTS

sed -i -e "s/DIR=xxx/DIR=$INSTALLED_SCRIPTS/" -e "s/DOMAIN=xxx/DOMAIN=$HOSTNAME/" -e "s/FMAUTH=xxx/FMAUTH=$INSTALLED_SCRIPTS/fm_auth/" \
 $SCRIPT_LOCATION/files/scripts/refreshFilemaker.SSL.sh > $INSTALLED_SCRIPTS/refreshFilemakerSSL.sh


# gomail

