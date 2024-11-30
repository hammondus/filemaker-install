#!/bin/bash

echo "night offsite backup"
cd /opt/FileMaker/Backups/offsite/offsite_night*

#Check if we are in the right spot
if [ ! -d "Databases" ]; then
  echo "Not in the right spot. ABORT ABORT"
  exit 1
fi

echo "We are good. Backup to AWS Server in Sydney"
#rsync -rtlpzh --del  --stats . RSYNC_NIGHT:~/backup/night/


#RSYNC options
# r - recursive
# t - copy modification times
# l - copy sim-links as sim-links
# p - copy file permissions
# v - verbose output
# z - compress transfer
# h - make output more human readable

# --bwlimit=50000   is about 50 MB/sec.  About 1/3 of what AWS is capable of between internal servers.
