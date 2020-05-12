#!/bin/bash

# Created by @vipink1203
# The GeoIP2 Country, City, ISP, Connection Type, and Enterprise databases are updated weekly, every Tuesday.
# Reference: https://support.maxmind.com/geoip-faq/geoip2-and-geoip-legacy-database-updates/how-often-are-the-geoip2-and-geoip-legacy-databases-updated/
# 0 05 * * 2 -->>> "At 05:00 on Tuesday."

## Description:
# When downloading the file, each file has the format of name such as 'GeoIP2-Country_20200512'.
# we are adding $dbname as GeoIP2-Country type DB and $dirday as 20200512 which is the date. $dirname refers to directory name 'GeoIP2-Country_20200512'
# Also, if the backup is downloaded to the S3 make sure to have the hirarchy as s3://databases-backup/maxmind/${dbname}/${dirday}



#Getting license from SSM
license=`aws ssm get-parameter --name /dev/MAXMIND/MAX_MIND_LICENSE --region us-east-1| jq -r ".Parameter.Value"`

# Permlinks for all the DB downloads
declare -a arr=("https://download.maxmind.com/app/geoip_download?edition_id=GeoIP2-City&license_key=${license}&suffix=tar.gz"
                "https://download.maxmind.com/app/geoip_download?edition_id=GeoIP2-Connection-Type&license_key=${license}&suffix=tar.gz"
                "https://download.maxmind.com/app/geoip_download?edition_id=GeoIP2-Country&license_key=${license}&suffix=tar.gz"
                "https://download.maxmind.com/app/geoip_download?edition_id=GeoIP2-ISP&license_key=${license}&suffix=tar.gz"
               )

declare -a updateDay

for links in "${arr[@]}"; do
   
   if wget -c "${links}" -O - | tar -xz; then
      # Getting DB name and date of update
      dirname=$(ls -d Geo*)
      dbname=$(ls -d ${dirname} | cut -d_ -f1)
      dirday=$(ls -d ${dirname} | cut -d_ -f2)

      # checking if date already exists in S3
      wordcount=`aws s3 ls s3://databases-backup/maxmind/${dbname}/${dirday}|wc -l`
      if [[ "${wordcount}" -ne 0 ]]; then
         echo "DB already present for $dirday date"

         # cleaning the downloaded item
         rm -rf $dirname
         sleep 5
         echo "****************************************${dirname} Completed ****************************************"
         continue
      fi

      # Renaming the directory as per the naming convention and uploading to S3
      mv $dirname $dirday
      updateDay=("${updateDay[@]}" "${dirday}")
      aws s3 cp $dirday s3://databases-backup/maxmind/${dbname}/${dirday} --recursive
      rm -rf $dirday
      sleep 5
      echo "****************************************${dirname} Completed ****************************************"
   
   else echo "${links} is not reachable"
   fi
done

# Send SNS alarm
if [[ ${#updateDay[0]} -ne 0 ]]; then

   message="The maxmind DB update is now available for ${updateDay[0]} and downloaded in databases-backup S3 bucket,

   Databases Downloaded:

   `aws s3 ls s3://databases-backup/maxmind/ | grep -v 'PRE'`

   "
   aws sns publish --topic-arn arn:aws:sns:us-east-1:XXXXXXXXX:alert --subject "MaxMind DB Update Available" --message "$message" --region us-east-1
   echo "SNS message sent!"
fi
