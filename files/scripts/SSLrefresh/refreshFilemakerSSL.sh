#!/bin/bash

#location
#/home/ubuntu/SSLrefresh/

# When certbot renews it's cert, it creates a file /home/ubuntu/SSLrefresh/newFilemakerSSL
# If that file exists, need to do the following.
# Import Cert into filemaker
# Restart filemaker. Only a filemaker restart is required, but might as well reboot server to clear out any memory leaks.
# As the databases don't automatically restart, start the databases.

# This script runs at 4am every sunday to keep the reboots when no-one is using.
# This is the one time we want the databases to automatically open when the server starts, so this
# script will also set a flag.
# The ServerStarted.sh script which runs on every server start will check for this flag, and if set
# will automatically open the databases.

DIR=/home/ubuntu/SSLrefresh
FLAG_SSL=$DIR/newFilemakerSSL
FLAG_OPENDB=$DIR/OPENDBrequired
#DOMAIN=fm.southernairlines.com.au
DOMAIN=fm.southernairlines.com.au
TMPDIR=/tmp/$DOMAIN

#Filemaker server user and password
FMUSER=doggy
FMPASS=pass

if [ ! -f $FLAG_SSL ]; then
	echo 'No new cert. Bye bye.'
	exit 0
fi

echo 'We have a new SSL Cert. Import to filemaker and restart'

# The filemaker import doesn't always work getting the files from /etc/letsencrypt, so copy the cert files to /tmp, then import
# There directory shouldn't exist in /tmp, but check anyway
if [ -d $TMPDIR ]; then
	echo 'tmp directory exists. Delete it'
	rm -rf $TMPDIR || { echo 'Failed to remove tmp folder..'; exit 9; }
fi

echo 'tmp dir deleted'

mkdir $TMPDIR || { echo 'Failed to create tmp directory..'; exit 9; }
cp /etc/letsencrypt/live/$DOMAIN/* $TMPDIR/ || { echo 'Failed to copy cert files to /tmp..'; exit 9; }

echo 'cert files copied'
# Import SSL cert into filemaker.
fmsadmin certificate import $TMPDIR/cert.pem \
    	--keyfile $TMPDIR/privkey.pem \
      	--intermediateCA $TMPDIR/fullchain.pem \
       	-u $FMUSER -p $FMPASS -y \
	|| { echo 'Filemaker cert import failed..'; exit 9; }

echo 'cert files imported to fm'

fmsadmin send -m "Server will be rebooted at 4am and will be unavailable for 5 minutes " -u $FMUSER -p $FMPASS
sleep 5m

# Shutdown filemaker
service fmshelper stop || { echo 'fmshelper stop - Failed to stop filemaker..'; exit 9; }

# If we got this far, the SSL cert should have imported and filemaker has been shutdown.
# Only thing left to do is set a flag and reboot.

echo 'fm shutdown'

# Remove the flag to say a SSL cert needs to be imported
# Set a flag so that the databases are opened automatically on boot

rm $FLAG_SSL
touch $FLAG_OPENDB 
reboot
