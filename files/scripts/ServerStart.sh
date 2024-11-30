#!/bin/bash

#Runs automatically on server restart via startup.service 

# Filemaker has been set to not automatically open databases after a server restart.
# The one time we do want this to happen is after a server restart due to the SSL Certificate being refreshed
# The SSL refresh script creates the SSLrefreshSuccessfull

DIR=xxx
FLAG_OPENDB=$DIR/OPENDBrequired

#Filemaker server user and password. load the fm_auth file
. FMAUTH=xxx


if [ -f $FLAG_OPENDB ]; then
	echo 'There was an SSL refresh. Open all filemaker databases automatically on boot. Sleeping 2m'
	sleep 2m
	echo 'Opening Filemaker databases'
	fmsadmin open -u $FM_ADMIN_USER -p $FM_ADMIN_PASSWORD
	rm $FLAG_OPENDB

else
	echo 'No SSL refresh. Databases not being opened automatically'
fi
