#!/bin/sh
#
# Traffic logging tool for DD-WRT-based routers using InfluxDB
#
# Cron Jobs:
# * * * * * root /jffs/bin/trafficmon update
# 0 * * * * root /jffs/bin/trafficmon setup
#

#
# Set Vars
#
DBURL=http://1xx.xxx.xxx.xxx:8086
DBNAME=influxDatabase
#$(nvram get wan_ifname)
LAN_IFNAME=$(nvram get lan_ifname)
WAN_IFNAME="eth1"
DEVICE="WZR-HP-AG300H"
PINGDEST="www.google.com"
USER="InfluxUsername"
PASSWORD="Influxpassword"

lock()
{
	while [ -f /tmp/trafficmon.lock ]; do
		if [ ! -d /proc/$(cat /tmp/trafficmon.lock) ]; then
			echo "WARNING : Lockfile detected but process $(cat /tmp/trafficmon.lock) does not exist !"
			rm -f /tmp/trafficmon.lock
		fi
		sleep 1
	done
	echo $$ > /tmp/trafficmon.lock
}

unlock()
{
	rm -f /tmp/trafficmon.lock
}

case ${1} in

"setup" )

	# Create the RRDIPT2 CHAIN (it doesn't matter if it already exists).
	# This one is for the whole LAN -> WAN and WAN -> LAN traffic measurement
	iptables -N RRDIPT2 2> /dev/null
	
	# Add the RRDIPT2 CHAIN to the FORWARD chain (if non existing).
	iptables -L FORWARD -n | grep RRDIPT2 > /dev/null
	if [ $? -ne 0 ]; then
		iptables -L FORWARD -n | grep "RRDIPT2" > /dev/null
		if [ $? -eq 0 ]; then
			echo "DEBUG : iptables chain misplaced, recreating it..."
			iptables -D FORWARD -j RRDIPT2
		fi
		iptables -I FORWARD -j RRDIPT2
	fi
	 
	# Add the LAN->WAN and WAN->LAN rules to the RRDIPT2 chain
	iptables -nvL RRDIPT2 | grep ${WAN_IFNAME}.*${LAN_IFNAME} >/dev/null
	if [ $? -ne 0 ]; then
		iptables -I RRDIPT2 -i ${WAN_IFNAME} -o ${LAN_IFNAME} -j RETURN
	fi

	iptables -nvL RRDIPT2 | grep ${LAN_IFNAME}.*${WAN_IFNAME} >/dev/null
	if [ $? -ne 0 ]; then
		iptables -I RRDIPT2 -i ${LAN_IFNAME} -o ${WAN_IFNAME} -j RETURN
	fi

	# Create the RRDIPT CHAIN (it doesn't matter if it already exists).
	iptables -N RRDIPT 2> /dev/null

	# Add the RRDIPT CHAIN to the FORWARD chain (if non existing).
	iptables -L FORWARD -n | grep RRDIPT[^2] > /dev/null
	if [ $? -ne 0 ]; then
		iptables -L FORWARD -n | grep "RRDIPT" > /dev/null
		if [ $? -eq 0 ]; then
			echo "DEBUG : iptables chain misplaced, recreating it..."
			iptables -D FORWARD -j RRDIPT
		fi
		iptables -I FORWARD -j RRDIPT
	fi

	# For each host in the ARP table
	grep ${LAN_IFNAME} /proc/net/arp | while read IP TYPE FLAGS MAC MASK IFACE
	do
		# Add iptable rules (if non existing).
		iptables -nL RRDIPT | grep "${IP} " > /dev/null
		if [ $? -ne 0 ]; then
			iptables -I RRDIPT -d ${IP} -j RETURN
			iptables -I RRDIPT -s ${IP} -j RETURN
		fi
	done	
	
	CURDATE=`date +%s`
	#
	# Uptime.  Really only needs once per hour.
	#
	UPTIME=`cat /proc/uptime | awk '{print $1}'`
	#echo ${UPTIME}
	curl -is -XPOST "$DBURL/write?db=$DBNAME&u=$USER&p=$PASSWORD" --data-binary "uptime,Device=${DEVICE} Uptime=${UPTIME} ${CURDATE}000000000" >/dev/null 2>&1
	;;
	
"update" )
	lock

	# Read and reset counters
	iptables -L RRDIPT -vnxZ -t filter > /tmp/traffic_$$.tmp
	iptables -L RRDIPT2 -vnxZ -t filter > /tmp/global_$$.tmp
	CURDATE=`date +%s`

	grep -Ev "0x0|IP" /proc/net/arp  | while read IP TYPE FLAGS MAC MASK IFACE
	do
		IN=0
		OUT=0
		# Add new data to the graph. 
          	grep ${IP} /tmp/traffic_$$.tmp | while read PKTS BYTES TARGET PROT OPT IFIN IFOUT SRC DST
          	do
			if [ "${DST}" = "${IP}" ]; then
				IN=${BYTES}
			fi
                        
			if [ "${SRC}" = "${IP}" ]; then
				OUT=${BYTES}
			fi
			
			# Get the hostname from the static leases table of nvram and parse it out
			HOSTNAME=`nvram get static_leases |sed -e 's/\s\+/\n/g' | sed 's/=/ /g' | awk 'BEGIN{IGNORECASE = 1}'"/$MAC/"'{print $2}'`
			if [[ -z "$HOSTNAME" ]]; then
				# Insert record without the hostname -- Use MAC instead for filtering in Grafana
				# Can also do an ARP lookup to see if it gets results.
				# HOSTNAME=`arp -a | awk 'BEGIN{IGNORECASE = 1}'"/$MAC/"'{print $2}'`
				curl -is -XPOST "$DBURL/write?db=$DBNAME&u=$USER&p=$PASSWORD" --data-binary "hostsData,MAC=$MAC,Hostname=${MAC} inBytes=${IN},outBytes=${OUT} ${CURDATE}000000000" >/dev/null 2>&1
			else
				 # Insert a record with the hostname
				curl -is -XPOST "$DBURL/write?db=$DBNAME&u=$USER&p=$PASSWORD" --data-binary "hostsData,MAC=$MAC,Hostname=${HOSTNAME} inBytes=${IN},outBytes=${OUT} ${CURDATE}000000000" >/dev/null 2>&1
			fi
		done
	done
	
	# Chain RRDIPT2 Processing
	IN=0
	OUT=0
	grep ${LAN_IFNAME} /tmp/global_$$.tmp | while read PKTS BYTES TARGET PROT OPT IFIN IFOUT SRC DST
	do
		if [ "${IFIN}" = "${LAN_IFNAME}" ]; then
			IN=${BYTES}
		fi
                        
		if [ "${IFIN}" = "${WAN_IFNAME}" ]; then
			OUT=${BYTES}
		fi
				
		curl -is -XPOST "$DBURL/write?db=$DBNAME&u=$USER&p=$PASSWORD" --data-binary "hostsData,MAC=00:00:00:00:00:00 inBytes=${IN},outBytes=${OUT} ${CURDATE}000000000" >/dev/null 2>&1
	done
	
	top -bn1 | head -3 | awk '/CPU/ {print $2,$4,$6,$8,$10,$12,$14}' | sed 's/%//g' | while read CPUusr CPUsys CPUnic CPUidle CPUio CPUirq CPUsirq
	do
		top -bn1 | head -3 | awk '/Load average/ {print $3,$4,$5}' | while read LAVG1 LAVG5 LAVG15
		do
			curl -is -XPOST "$DBURL/write?db=$DBNAME&u=$USER&p=$PASSWORD" --data-binary "cpuStats,Device=${DEVICE} CPUusr=${CPUusr},CPUsys=${CPUsys},CPUnic=${CPUnic},CPUidle=${CPUidle},CPUio=${CPUio},CPUirq=${CPUirq},CPUsirq=${CPUsirq},CPULoadAvg1m=${LAVG1},CPULoadAvg5m=${LAVG5},CPULoadAvg15m=${LAVG15} ${CURDATE}000000000" >/dev/null 2>&1		
		done			
	done

	top -bn1 | head -3 | awk '/Mem/ {print $2,$4}' | sed 's/K//g' | while read used free
	do
		curl -is -XPOST "$DBURL/write?db=$DBNAME&u=$USER&p=$PASSWORD" --data-binary "memoryStats,Device=${DEVICE} memUsed=${used},memFree=${free} ${CURDATE}000000000" >/dev/null 2>&1	
	done

	IPCONNECTIONS=`wc -l < /proc/net/ip_conntrack`

	ath0CONNECTIONS=`wl_atheros -i ath0 assoclist | awk '{print $2}' | wc -l`

	ath1CONNECTIONS=`wl_atheros -i ath1 assoclist | awk '{print $2}' | wc -l`

	PING=`ping -c1 -W1 $PINGDEST | grep 'seq=' | sed 's/.*time=\([0-9]*\.[0-9]*\).*$/\1/'`
	
	curl -is -XPOST "$DBURL/write?db=$DBNAME&u=$USER&p=$PASSWORD" --data-binary "connectionStats,Device=${DEVICE} IPConnections=${IPCONNECTIONS},WiFiG=${ath0CONNECTIONS},WiFiN=${ath1CONNECTIONS},Ping=${PING} ${CURDATE}000000000" >/dev/null 2>&1
	
	cat /proc/net/dev | awk '/ath0/ {print $2,$10}' | while read bytesout bytesin
	do
		# Prevent negative numbers when the counters reset.  Could miss data but it should be a marginal amount.
		if [ ${bytesin} -le 0 ] ; then
			bytesin=0
		fi
			
		if [ ${bytesout} -le 0 ] ; then
			bytesout=0
		fi
		curl -is -XPOST "$DBURL/write?db=$DBNAME&u=$USER&p=$PASSWORD" --data-binary "interfaceStats,Interface=ath0,Device=${DEVICE} bytesIn=${bytesin},bytesOut=${bytesout} ${CURDATE}000000000" >/dev/null 2>&1
	done 
	
	cat /proc/net/dev | awk '/ath1/ {print $2,$10}' | while read bytesout bytesin
	do
		# Prevent negative numbers when the counters reset.  Could miss data but it should be a marginal amount.
		if [ ${bytesin} -le 0 ] ; then
			bytesin=0
		fi
			
		if [ ${bytesout} -le 0 ] ; then
			bytesout=0
		fi
		curl -is -XPOST "$DBURL/write?db=$DBNAME&u=$USER&p=$PASSWORD" --data-binary "interfaceStats,Interface=ath1,Device=${DEVICE} bytesIn=${bytesin},bytesOut=${bytesout} ${CURDATE}000000000" >/dev/null 2>&1
	done
	cat /proc/net/dev | awk '/eth0/ {print $2,$10}' | while read bytesin bytesout
	do
		# Prevent negative numbers when the counters reset.  Could miss data but it should be a marginal amount.
		if [ ${bytesin} -le 0 ] ; then
			bytesin=0
		fi
			
		if [ ${bytesout} -le 0 ] ; then
			bytesout=0
		fi
		curl -is -XPOST "$DBURL/write?db=$DBNAME&u=$USER&p=$PASSWORD" --data-binary "interfaceStats,Interface=eth0,Device=${DEVICE} bytesIn=${bytesin},bytesOut=${bytesout} ${CURDATE}000000000" >/dev/null 2>&1
	done
	cat /proc/net/dev | awk '/eth1/ {print $2,$10}' | while read bytesin bytesout
	do
		# Prevent negative numbers when the counters reset.  Could miss data but it should be a marginal amount.
		if [ ${bytesin} -le 0 ] ; then
			bytesin=0
		fi
			
		if [ ${bytesout} -le 0 ] ; then
			bytesout=0
		fi
		curl -is -XPOST "$DBURL/write?db=$DBNAME&u=$USER&p=$PASSWORD" --data-binary "interfaceStats,Interface=eth1,Device=${DEVICE} bytesIn=${bytesin},bytesOut=${bytesout} ${CURDATE}000000000" >/dev/null 2>&1
	done 

	#
	# OpenVPN bytes count and clients count.
	#
	if [[ -f /jffs/bin/byteCount.tmp ]] ; then

	# Read the last values from the tmpfile - Line "OpenVPN"
	grep "OpenVPN" /jffs/bin/byteCount.tmp | while read dev n lastBytesIn lastBytesOut
	do
		#echo  bytesin: ${lastBytesIn}
		#echo  bytesout: ${lastBytesOut}
	 
		/bin/echo "load-stats" | /usr/bin/nc 127.0.0.1 14 | grep SUCCESS | awk -F "," '{split($1, a, "="); split($2, b, "="); split($3, c, "="); print a[2],b[2],c[2];}' | tr '\r' ' ' | while read nc currentBytesIn currentBytesOut 
		do
			# Write out the current stats to the temp file for the next read
			echo "OpenVPN" ${nc} ${currentBytesIn} ${currentBytesOut} > /jffs/bin/byteCount.tmp
			
			totalBytesIn=`expr ${currentBytesIn} - ${lastBytesIn}`
			totalBytesOut=`expr ${currentBytesOut} - ${lastBytesOut}`
			
			# Prevent negative numbers when the counters reset.  Could miss data but it should be a marginal amount.
			if [ ${totalBytesIn} -le 0 ] ; then
				totalBytesIn=0
			fi
			
			if [ ${totalBytesOut} -le 0 ] ; then
				totalBytesOut=0
			fi
			
			curl -is -XPOST "$DBURL/write?db=$DBNAME&u=$USER&p=$PASSWORD" --data-binary "router_VPNTraffic inBytes=${totalBytesIn},outBytes=${totalBytesOut},clients=${nc} ${CURDATE}000000000" >/dev/null 2>&1
	 
		done
	done 

else
    # Write out blank file
	echo "OpenVPN 0 0 0" > /jffs/bin/byteCount.tmp
fi


	
	# Free some memory
	rm -f /tmp/*_$$.tmp
	unlock
	;;

*)
	echo "Usage : $0 {setup|update}"
	echo "Options : "
	echo "   $0 setup"
	echo "   $0 update"
	exit
	;;
esac
