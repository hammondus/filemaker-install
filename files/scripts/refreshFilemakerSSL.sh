#!/bin/bash

# When certbot renews it's cert, it creates a file /home/ubuntu/filemaker-scripts/newFilemakerSSL
# If that file exists, need to do the following.
# Import Cert into filemaker

# Restart server.
# Only a filemaker restart is required, but might as well reboot the entire server as
# filemaker is the only thing running.

# This script runs at 4am every sunday to keep the reboots when no-one is using.
# This is the one time we want the databases to automatically open when the server starts, so this
# script will also set a flag.

# The ServerStart.sh script which runs on every server start will check for this flag, and if set
# will automatically open the databases.

DIR=xxx
FLAG_SSL=$DIR/newFilemakerSSL
FLAG_OPENDB=$DIR/OPENDBrequired
DOMAIN=xxx

#Filemaker server user and password
FMAUTH=xxx
#load the fm auth variables
. $FMAUTH

if [ ! -f $FLAG_SSL ]; then
	echo 'No new cert. Bye bye.'
	exit 0
fi

echo 'We have a new SSL Cert. Import to filemaker and restart'

  # The certs in the live directory are just links to the certs.
  # fmsadmin can't handle using links to files, so we need to find where the actual certs are.
  # For this, fmsadmin requires sudo as the letsencrypt directories are only accessable
  # by the root user.
  CERTFILEPATH=$(sudo realpath "/etc/letsencrypt/live/$HOSTNAME/fullchain.pem")
  PRIVKEYPATH=$(sudo realpath "/etc/letsencrypt/live/$HOSTNAME/privkey.pem")
  sudo fmsadmin certificate import $CERTFILEPATH --keyfile $PRIVKEYPATH \
    -u $FM_ADMIN_USER -p $FM_ADMIN_PASSWORD -y || { echo "Filemaker unable to import certificate"; exit 1; }

echo 'cert files imported in to Filemaker'

fmsadmin send -m "Server will be rebooted at 4am and will be unavailable for 5 minutes " -u $FM_ADMIN_USER -p $FM_ADMIN_PASSWORD
sleep 5m

# Shutdown filemaker
sudo service fmshelper stop || { echo 'fmshelper stop - Failed to stop filemaker..'; exit 1; }

# If we got this far, the SSL cert should have imported and filemaker has been shutdown.
# Only thing left to do is set a flag and reboot.


# Remove the flag to say a SSL cert needs to be imported
# Set a flag so that the databases are opened automatically on boot

rm $FLAG_SSL
touch $FLAG_OPENDB 
sudo reboot
