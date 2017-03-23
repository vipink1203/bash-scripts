#!/bin/bash

#	Author:	@vipink1203
#	Web:	www.webnuxpro.com
#	Automated deployment Script using scp (secure copy - ssh) 	
#	Last	Edited:	March	23	2017


git clone https://github.com/vipink1203/random-quote-machine.git Public/.
ssh -p2200 root@host.example.com "rm -rf /home/vipinkumar/public_html/*" && scp -r -P2200 Public/* root@host.example.com:/home/vipinkumar/public_html/ && ssh -p2200 root@host.example.com "chown -R vipinkumar:vipinkumar /home/vipinkumar/public_html/*"
