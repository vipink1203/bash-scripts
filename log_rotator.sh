#!/bin/bash

# Author: @vipink1203
# Web:	www.vipinkumar.me
# Script to check the log directory . if the size is more than 3 GB, it will keep the last two written log and delete the old ones
# LastEdited: March 6 2017

if [ "$1" == "" ]; then
  echo "Usage: <script.sh> <directory path>"  # DOnt use a trailing slash after directory name
  exit 1
fi
dir=$1

if [ -d $1 ]; then
	size=$(du -sh --block-size=G $1 | cut -c1-1 )
	if [ "$size" > 3 ]; then
		xargs rm -f <<< $(ls -t ${dir}/* | tail -n +3)
		
  	else
    		echo "Size is less than 3 GB."
  	fi
 
else
  echo "The passed parameter is not a directory"
  echo "Usage: <script.sh> <directory path>"
  exit
fi
