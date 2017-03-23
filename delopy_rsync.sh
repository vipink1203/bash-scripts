#!/bin/bash

#	Author:	@vipink1203
#	Web:	www.webnuxpro.com
#	Automated deployment Script using rsync (secure copy - ssh) 	
#	Last	Edited:	March	23	2017


rsync -rzcSLhe "ssh -p2200" Public/ root@host.example.com:/home/vipinkumar/public_html && ssh -p2200 root@host.example.com "chown -R vipinkumar:vipinkumar /home/vipinkumar/public_html/"
