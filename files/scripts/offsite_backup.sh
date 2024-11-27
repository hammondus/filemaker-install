#!/bin/bash

if [ -z $1 ]; then
       echo "Offsite Backup. No paramater passed. Exiting"
	exit 1
fi

if [ $1 == "midday" ]; then
	echo "midday Backup"
	cd FM_BACKUPS/offsite/offsite_midday*
	#Check if we are in the right spot
	if [ ! -d "Databases" ]; then
        	echo "Not in the right spot. ABORT ABORT"
        	exit 1
	fi

	echo "We are good. Backup to Melbourne"
	# rsync -rtlpzh --bwlimit=5000 --del  --stats . southern@fm.hammond.zone:~/backup/midday/
	#rsync -rtlpzhv --progress --del  --stats . southern@fm.hammond.zone:~/backup/midday/
fi

if [ $1 == "night" ]; then
        echo "nighty night"
        cd /opt/FileMaker/Backups/offsite/offsite_night*

	#Check if we are in the right spot
	if [ ! -d "Databases" ]; then
        	echo "Not in the right spot. ABORT ABORT"
        	exit 1
	fi

	echo "We are good. Backup to AWS Server in Sydney"
  	#rsync -rtlpzh --del  --stats . southern@backup.southernairlines.com.au:~/backup/night/
	#rsync -rtlpzhv --progress --del  --stats . southern@backup.southernairlines.com.au:~/backup/night/
fi


#RSYNC options
# r - recursive
# t - copy modification times
# l - copy sim-links as sim-links
# p - copy file permissions
# v - verbose output
# z - compress transfer
# h - make output more human readable

# --bwlimit=50000   is about 50 MB/sec.  About 1/3 of what AWS is capable of between internal servers.
