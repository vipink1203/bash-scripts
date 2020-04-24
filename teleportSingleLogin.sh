#!/bin/bash

# Author: @vipink1203
# Web:	www.vipinkumar.me
# UseCase: Script to login to a single server when you have Gravitational Teleport as a gateway for managing access to clusters of Linux servers via SSH 
# LastEdited: April 24 2020



#Edit this line
#tsh login --proxy=teleport.example.com --auth=<your sso>
echo "Which Server?"
read server
ip_count=`tsh ls | grep $server | awk '{print $2}' | cut -d: -f1 | wc -l`
ip=`tsh ls | grep $server | awk '{print $2}' | cut -d: -f1`

if [ $ip_count != 1 ];then
	echo "there are more than one servers"
	single=`tsh ls | grep -m1 $server | awk '{print $2}' | cut -d: -f1`
	tsh ssh root@${single}
else
	tsh ssh root@$ip
fi 

