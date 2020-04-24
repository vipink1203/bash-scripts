#!/bin/bash

#Author: @vipink1203
#Web: www.vipinkumar.me
#UseCase: Script to login to all the servers when you have Gravitational Teleport as a gateway and checks the node and php version. 
#LastEdited: April 24 2020

outputFile='output.csv'
#Edit this line
tsh login --proxy=teleport.example.com --auth=<your sso>
tsh ls | awk '{print $4}' | cut -d= -f2 | sort -u | egrep -v "Labels|zone|packer|^dev|^qa|aspera" | grep -v ^$ > list.txt
echo "Stack,Node-Version,PHP-Version" >> $outputFile
for line in `cat list.txt`;
do
    ip=$(tsh ls | grep -m1 ${line} | awk '{print $2}' | cut -d: -f1)
    node=$(tsh ssh root@${ip} "node -v" 2>&1)
    php=$(tsh ssh root@${ip} "php -v | grep cli | cut -d ' ' -f 2"  2>&1)
    if [[ $node != *error* ]]
    then
        echo "${line},${node},NA" >> $outputFile
    elif [[ $php != *command* ]]
    then
        echo "${line},NA,${php}" >> $outputFile
    fi
done
echo "Your output csv file is located - " `pwd`/$outputFile
# cleanup
rm -rf list.txt