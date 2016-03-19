#!/bin/bash

#    Scan all your Cisco Probes config to find sla tasks and check if working with SNMP for troubleshooting
#    Copyright (C) 2014  Manolis Kartsonakis
#
#    This program is free software: you can redistribute it and/or modify
#    it under the terms of the GNU General Public License as published by
#    the Free Software Foundation, either version 3 of the License, or
#    (at your option) any later version.
#
#    This program is distributed in the hope that it will be useful,
#    but WITHOUT ANY WARRANTY; without even the implied warranty of
#    MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
#    GNU General Public License for more details.
#
#    You should have received a copy of the GNU General Public License
#    along with this program.  If not, see <http://www.gnu.org/licenses/>.
###########################################################################


#This is a file with all your cisco probes hostnames
probesList="/home/scripts/slaFind/probes.list"

#this is the place you have all your cisco probes config files (backup location)
configFolder="/newciscoboot/netbackups/last"

#remove old files just in case something is remaining from an aggressive stop.
/bin/rm -f /tmp/slafinding.tmp
/bin/rm -f /tmp/branchlist.tmp
/bin/rm -f /tmp/slafindResults.tmp
/bin/rm -f /tmp/slaCheck.output

#Argument 1 = branch Name
#If no arguments print Usage


#Checking the arguments and print usage if nothing found. If arguments ok pass the branchcodes in a temp file
#True of the length if "STRING" is zero.
if [ -z "$1" ]; then
	echo "Use this script if you want to check or delete multiple sla operations"
        echo -e "\nUsage: $0 sla tag part OR fileOfBranchCodes customer "
        echo "Example: $0 ATE-2121 agrotikibank"
        echo -e "Example: $0 toDelete.list comerbank\n"
        echo -e "***customer is optional but recommended!***\n"
        exit 0
#Argument $1 contains file with list of branchnames. True if it exists
elif [ -e $1 ]; then
	cat $1 > /tmp/branchlist.tmp
		#Ask for a customer if not given.
		if [ -z "$2" ]; then
#			echo -e "\nContinue without Bankname? Type \"y\" for Yes or the Bankname as it's in the task tag and press [Enter]"
#			read customer
			customer="y";
			echo -e "\n If you want to be more specific please type a Branchname as a second argument"
			echo -e "\n"
		else
			customer=$2
		fi
#Argument $1 contains the branchname. True if the length of "STRING" is non-zero
else [ -n "$1" ]
	echo $1 > /tmp/branchlist.tmp
		#Ask for a customer if not given.
		if [ -z "$2" ]; then
#			echo -e "\nContinue without Bankname? Type \"y\" for Yes or the Bankname as it's in the task tag and press [Enter]"
#			read customer
			customer="y";
			echo -e "\n If you want to be more specific please type a Branchname as a second argument"
			echo -e "\n"
		else
			customer=$2
		fi
fi

#If customer not given ignore it.
if [ "$customer" = "y" ]; then
unset customer
echo -e "\nSearching based only on Branchname...\nBe careful, maybe there are more than one branch in different customers with the same name!\n"
fi

#Creating the output temp files:
touch /tmp/slafinding.tmp
touch /tmp/slaCheck.output

#2 loops. Check in raw every probe (latest backup file) all branchcodes given as input. Results are stored in a temp file.
for probe in `cat $probesList`; do
	for katastima in `cat /tmp/branchlist.tmp`; do

                #If there is a backup file for this probe, grep in it.
	        newestFile="$configFolder/$probe"
		if [ `find $newestFile 2>/dev/null` ]; then	
			egrep -r "ip sla monitor {1,3}[1-9]|tag" $newestFile | \
			grep -B1 ".*$customer.*\_$katastima\_" | grep "ip sla monitor" | sed 's/^/no /' > /tmp/slafindResults.tmp
				if  [ -s /tmp/slafindResults.tmp ]; then
					echo -e "--------------------------------\nTASK INFO" >> /tmp/slafinding.tmp 
					echo "Probe: $probe" >> /tmp/slafinding.tmp
					echo "Branch Name: $katastima" >> /tmp/slafinding.tmp
					egrep -r "ip sla monitor {1,3}[1-9]|tag|type" $newestFile | grep -B2 ".*$customer.*\_$katastima\_"  | \
					awk -F"dest-ipaddr |ipIcmpEcho | source-ipaddr| dest-port" '/type/{print$2}' | \
					sort -u | awk 'BEGIN {print"Target IPs:"}{print$1}' >> /tmp/slafinding.tmp
					/bin/cat /tmp/slafindResults.tmp >> /tmp/slafinding.tmp
		        		echo "--------------------------------"  >> /tmp/slafinding.tmp
					echo "" > /tmp/slafindResults.tmp
				fi
		else
			echo "no backup file for probe $probe yet!"
		fi
	done
done

#Running a loop to print all task that wasn't found.
for branch in `cat /tmp/branchlist.tmp`; do
	grep -q $branch /tmp/slafinding.tmp
	if [ $? -eq 1 ]; then
		echo -e "\nno task for $branch"
	fi
done

#Print the results from grep.
cat /tmp/slafinding.tmp
#Check sla tasks if working ok.
#while getopts ":a" opt; do
#  case $opt in
#     c)
	echo "Checking the tasks . . . "
	for taskNum in `awk '/Probe:/ {probe=$NF} { if ($1=="no") print probe "~" $NF }' /tmp/slafinding.tmp`; do
		probeName=`echo $taskNum | awk -F"~" '{print$1}'`
		opNum=`echo $taskNum | awk -F"~" '{print$2}' | sed 's/\r//'`
		tag=`snmpwalk -c fur1Nk9zan -v2c $probeName 1.3.6.1.4.1.9.9.42.1.2.1.1.3.$opNum | awk -F"STRING: " '{print$2}'`
		protType=`snmpwalk -c fur1Nk9zan -v2c $probeName 1.3.6.1.4.1.9.9.42.1.2.2.1.1.$opNum | awk '{print$4}'`
		returnCode=`snmpwalk -c fur1Nk9zan -v2c $probeName 1.3.6.1.4.1.9.9.42.1.2.10.1.2.$opNum | awk '{print$4}'`
	
		#Checking the result of snmpget about the Protocol type of the task	
		case "$protType" in
		1)
		protType="Type:notApplicable"
		;;
		2)
		protType="Type:ipIcmpEcho"
		;;
		3)
		protType="Type:ipUdpEchoAppl"
		;;
		13)
		protType="Type:ipxEcho"
		;;
		14)
		protType="Type:ipxEchoAppl"
		;;
		24)
		protType="Type:ipTcpConn"
		;;
		25)
		protType="Type:httpAppl"
		;;
		26)
		protType="Type:dnsAppl"
		;;
		27)
		protType="Type:jitterAppl"
		;;
		29)
		protType="Type:dhcpAppl"
		;;
		esac
		
		
		#Checking the result of snmpget about the status of the task	
		case "$returnCode" in
		0)
		returnCode="Status:other"
		;;
		1)
		returnCode="Status:ok"
		;;
		2)
		returnCode="Status:disconnected"
		;;
		3)
		returnCode="Status:overThreshold"
		;;
		4)
		returnCode="Status:timeout"
		;;
		5)
		returnCode="Status:busy"
		;;
		6)
		returnCode="Status:notConnected"
		;;
		7)
		returnCode="Status:dropped"
		;;
		8)
		returnCode="Status:sequenceError"
		;;
		9)
		returnCode="Status:verifyError"
		;;
		10)
		returnCode="Status:applicationSpecific"
		;;
		11)
		returnCode="Status:dnsServerTimeout"
		;;
		12)
		returnCode="Status:tcpConnectTimeout"
		;;
		13)
		returnCode="Status:httpTransactionTimeout"
		;;
		14)
		returnCode="Status:dnsQueryError"
		;;
		15)
		returnCode="Status:httpError"
		;;
		16)
		returnCode="Status:error"
		;;
		esac
		
		echo -e $tag $protType  $returnCode >> /tmp/slaCheck.output
	
	
	done
	
		cat /tmp/slaCheck.output | column -t -s\"
#Clean all temp files.
/bin/rm -f /tmp/slafinding.tmp 
/bin/rm -f /tmp/branchlist.tmp 
/bin/rm -f /tmp/slafindResults.tmp
/bin/rm -f /tmp/slaCheck.output
