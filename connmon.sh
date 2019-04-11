#!/bin/sh

############################################################
##                   _  __  __              _  _          ##
##                  | ||  \/  |            | |(_)         ##
##   ___  _ __    __| || \  / |  ___  _ __ | | _  _ __    ##
##  / __|| '_ \  / _` || |\/| | / _ \| '__|| || || '_ \   ##
##  \__ \| |_) || (_| || |  | ||  __/| |   | || || | | |  ##
##  |___/| .__/  \__,_||_|  |_| \___||_|   |_||_||_| |_|  ##
##       | |                                              ##
##       |_|                                              ##
##                                                        ##
##          https://github.com/jackyaz/connmon            ##
##                                                        ##
############################################################

### Start of script variables ###
readonly CONNMON_NAME="connmon"
readonly CONNMON_VERSION="v1.0.0"
readonly CONNMON_BRANCH="master"
readonly CONNMON_REPO="https://raw.githubusercontent.com/jackyaz/""$CONNMON_NAME""/""$CONNMON_BRANCH"
readonly CONNMON_CONF="/jffs/configs/$CONNMON_NAME.config"
[ -z "$(nvram get odmpid)" ] && ROUTER_MODEL=$(nvram get productid) || ROUTER_MODEL=$(nvram get odmpid)
### End of script variables ###

### Start of output format variables ###
readonly CRIT="\\e[41m"
readonly ERR="\\e[31m"
readonly WARN="\\e[33m"
readonly PASS="\\e[32m"
### End of output format variables ###

# $1 = print to syslog, $2 = message to print, $3 = log level
Print_Output(){
	if [ "$1" = "true" ]; then
		logger -t "$CONNMON_NAME" "$2"
		printf "\\e[1m$3%s: $2\\e[0m\\n\\n" "$CONNMON_NAME"
	else
		printf "\\e[1m$3%s: $2\\e[0m\\n\\n" "$CONNMON_NAME"
	fi
}

### Code for this function courtesy of https://github.com/decoderman- credit to @thelonelycoder ###
Firmware_Version_Check(){
	echo "$1" | awk -F. '{ printf("%d%03d%03d%03d\n", $1,$2,$3,$4); }'
}
############################################################################

### Code for these functions inspired by https://github.com/Adamm00 - credit to @Adamm ###
Check_Lock(){
	if [ -f "/tmp/$CONNMON_NAME.lock" ]; then
		ageoflock=$(($(date +%s) - $(date +%s -r /tmp/$CONNMON_NAME.lock)))
		if [ "$ageoflock" -gt 120 ]; then
			Print_Output "true" "Stale lock file found (>120 seconds old) - purging lock" "$ERR"
			kill "$(sed -n '1p' /tmp/$CONNMON_NAME.lock)" >/dev/null 2>&1
			Clear_Lock
			echo "$$" > "/tmp/$CONNMON_NAME.lock"
			return 0
		else
			Print_Output "true" "Lock file found (age: $ageoflock seconds) - stopping to prevent duplicate runs" "$ERR"
			#if [ -z "$1" ]; then
				exit 1
			#else
			#	return 1
			#fi
		fi
	else
		echo "$$" > "/tmp/$CONNMON_NAME.lock"
		return 0
	fi
}

Clear_Lock(){
	rm -f "/tmp/$CONNMON_NAME.lock" 2>/dev/null
	return 0
}

Update_Version(){
	if [ -z "$1" ]; then
		doupdate="false"
		localver=$(grep "CONNMON_VERSION=" /jffs/scripts/"$CONNMON_NAME" | grep -m1 -oE 'v[0-9]{1,2}([.][0-9]{1,2})([.][0-9]{1,2})')
		/usr/sbin/curl -fsL --retry 3 "$CONNMON_REPO/$CONNMON_NAME.sh" | grep -qF "jackyaz" || { Print_Output "true" "404 error detected - stopping update" "$ERR"; return 1; }
		serverver=$(/usr/sbin/curl -fsL --retry 3 "$CONNMON_REPO/$CONNMON_NAME.sh" | grep "CONNMON_VERSION=" | grep -m1 -oE 'v[0-9]{1,2}([.][0-9]{1,2})([.][0-9]{1,2})')
		if [ "$localver" != "$serverver" ]; then
			doupdate="version"
		else
			localmd5="$(md5sum "/jffs/scripts/$CONNMON_NAME" | awk '{print $1}')"
			remotemd5="$(curl -fsL --retry 3 "$CONNMON_REPO/$CONNMON_NAME.sh" | md5sum | awk '{print $1}')"
			if [ "$localmd5" != "$remotemd5" ]; then
				doupdate="md5"
			fi
		fi
		
		if [ "$doupdate" = "version" ]; then
			Print_Output "true" "New version of $CONNMON_NAME available - updating to $serverver" "$PASS"
		elif [ "$doupdate" = "md5" ]; then
			Print_Output "true" "MD5 hash of $CONNMON_NAME does not match - downloading updated $serverver" "$PASS"
		fi
		
		Update_File "connmonstats_www.asp"
		Modify_WebUI_File
		
		if [ "$doupdate" != "false" ]; then
			/usr/sbin/curl -fsL --retry 3 "$CONNMON_REPO/$CONNMON_NAME.sh" -o "/jffs/scripts/$CONNMON_NAME" && Print_Output "true" "$CONNMON_NAME successfully updated"
			chmod 0755 /jffs/scripts/"$CONNMON_NAME"
			Clear_Lock
			exit 0
		else
			Print_Output "true" "No new version - latest is $localver" "$WARN"
			Clear_Lock
		fi
	fi
	
	case "$1" in
		force)
			serverver=$(/usr/sbin/curl -fsL --retry 3 "$CONNMON_REPO/$CONNMON_NAME.sh" | grep "CONNMON_VERSION=" | grep -m1 -oE 'v[0-9]{1,2}([.][0-9]{1,2})([.][0-9]{1,2})')
			Print_Output "true" "Downloading latest version ($serverver) of $CONNMON_NAME" "$PASS"
			Update_File "connmonstats_www.asp"
			Modify_WebUI_File
			/usr/sbin/curl -fsL --retry 3 "$CONNMON_REPO/$CONNMON_NAME.sh" -o "/jffs/scripts/$CONNMON_NAME" && Print_Output "true" "$CONNMON_NAME successfully updated"
			chmod 0755 /jffs/scripts/"$CONNMON_NAME"
			Clear_Lock
			exit 0
		;;
	esac
}
############################################################################

Update_File(){
	if [ "$1" = "connmonstats_www.asp" ]; then
		tmpfile="/tmp/$1"
		Download_File "$CONNMON_REPO/$1" "$tmpfile"
		if ! diff -q "$tmpfile" "/jffs/scripts/$1" >/dev/null 2>&1; then
			Print_Output "true" "New version of $1 downloaded" "$PASS"
			rm -f "/jffs/scripts/$1"
			Mount_CONNMON_WebUI
		fi
		rm -f "$tmpfile"
	else
		return 1
	fi
}

Validate_Number(){
	if [ "$2" -eq "$2" ] 2>/dev/null; then
		return 0
	else
		formatted="$(echo "$1" | sed -e 's/|/ /g')"
		if [ -z "$3" ]; then
			Print_Output "false" "$formatted - $2 is not a number" "$ERR"
		fi
		return 1
	fi
}

Validate_TrueFalse(){
	case "$2" in
		true|TRUE|false|FALSE)
			return 0
		;;
		*)
			Print_Output "false" "$1 - $2 - must be either true or false" "$ERR"
			return 1
		;;
	esac
}

Conf_Exists(){
	if [ -f "$CONNMON_CONF" ]; then
		dos2unix "$CONNMON_CONF"
		chmod 0644 "$CONNMON_CONF"
		sed -i -e 's/"//g' "$CONNMON_CONF"
		return 0
	else
		echo "PREFERREDSERVER=8.8.8.8" > "$CONNMON_CONF"
		return 1
	fi
}

Auto_Startup(){
	case $1 in
		create)
			if [ -f /jffs/scripts/services-start ]; then
				STARTUPLINECOUNT=$(grep -c '# '"$CONNMON_NAME" /jffs/scripts/services-start)
				STARTUPLINECOUNTEX=$(grep -cx "/jffs/scripts/$CONNMON_NAME startup"' # '"$CONNMON_NAME" /jffs/scripts/services-start)
				
				if [ "$STARTUPLINECOUNT" -gt 1 ] || { [ "$STARTUPLINECOUNTEX" -eq 0 ] && [ "$STARTUPLINECOUNT" -gt 0 ]; }; then
					sed -i -e '/# '"$CONNMON_NAME"'/d' /jffs/scripts/services-start
				fi
				
				if [ "$STARTUPLINECOUNTEX" -eq 0 ]; then
					echo "/jffs/scripts/$CONNMON_NAME startup"' # '"$CONNMON_NAME" >> /jffs/scripts/services-start
				fi
			else
				echo "#!/bin/sh" > /jffs/scripts/services-start
				echo "" >> /jffs/scripts/services-start
				echo "/jffs/scripts/$CONNMON_NAME startup"' # '"$CONNMON_NAME" >> /jffs/scripts/services-start
				chmod 0755 /jffs/scripts/services-start
			fi
		;;
		delete)
			if [ -f /jffs/scripts/services-start ]; then
				STARTUPLINECOUNT=$(grep -c '# '"$CONNMON_NAME" /jffs/scripts/services-start)
				
				if [ "$STARTUPLINECOUNT" -gt 0 ]; then
					sed -i -e '/# '"$CONNMON_NAME"'/d' /jffs/scripts/services-start
				fi
			fi
		;;
	esac
}

Auto_Cron(){
	case $1 in
		create)
			STARTUPLINECOUNT=$(cru l | grep -c "$CONNMON_NAME")
			
			if [ "$STARTUPLINECOUNT" -eq 0 ]; then
				cru a "$CONNMON_NAME" "*/1 * * * * /jffs/scripts/$CONNMON_NAME generate"
			fi
		;;
		delete)
			STARTUPLINECOUNT=$(cru l | grep -c "$CONNMON_NAME")
			
			if [ "$STARTUPLINECOUNT" -gt 0 ]; then
				cru d "$CONNMON_NAME"
			fi
		;;
	esac
}

Download_File(){
	/usr/sbin/curl -fsL --retry 3 "$1" -o "$2"
}

RRD_Initialise(){
	if [ ! -f /jffs/scripts/connmonstats_rrd.rrd ]; then
		Download_File "$CONNMON_REPO/connmonstats_xml.xml" "/jffs/scripts/connmonstats_xml.xml"
		rrdtool restore -f /jffs/scripts/connmonstats_xml.xml /jffs/scripts/connmonstats_rrd.rrd
		rm -f /jffs/scripts/connmonstats_xml.xml
	fi
}

Mount_CONNMON_WebUI(){
	umount /www/AdaptiveQoS_ROG.asp 2>/dev/null
	if [ ! -f /jffs/scripts/connmonstats_www.asp ]; then
		Download_File "$CONNMON_REPO/connmonstats_www.asp" "/jffs/scripts/connmonstats_www.asp"
	fi
	
	mount -o bind /jffs/scripts/connmonstats_www.asp /www/AdaptiveQoS_ROG.asp
}

Modify_WebUI_File(){
	### menuTree.js ###
	umount /www/require/modules/menuTree.js 2>/dev/null
	tmpfile=/tmp/menuTree.js
	cp "/www/require/modules/menuTree.js" "$tmpfile"
	
	sed -i '/{url: "AdaptiveQoS_ROG.asp", tabName: /d' "$tmpfile"
	sed -i '/"Tools_OtherSettings.asp", tabName: "Other Settings"/a {url: "AdaptiveQoS_ROG.asp", tabName: "Uptime Monitoring"},' "$tmpfile"
	sed -i '/retArray.push("AdaptiveQoS_ROG.asp");/d' "$tmpfile"
	
	if [ -f "/jffs/scripts/spdmerlin" ]; then
		sed -i '/{url: "Advanced_Feedback.asp", tabName: /d' "$tmpfile"
		sed -i '/"Tools_OtherSettings.asp", tabName: "Other Settings"/a {url: "Advanced_Feedback.asp", tabName: "SpeedTest"},' "$tmpfile"
		sed -i '/retArray.push("Advanced_Feedback.asp");/d' "$tmpfile"
	fi
	
	if [ -f "/jffs/scripts/ntpmerlin" ]; then
		sed -i '/"Tools_OtherSettings.asp", tabName: "Other Settings"/a {url: "Feedback_Info.asp", tabName: "NTP Daemon"},' "$tmpfile"
	fi
	
	if ! diff -q "$tmpfile" "/jffs/scripts/custom_menuTree.js" >/dev/null 2>&1; then
		cp "$tmpfile" "/jffs/scripts/custom_menuTree.js"
	fi
	
	rm -f "$tmpfile"
	
	mount -o bind "/jffs/scripts/custom_menuTree.js" "/www/require/modules/menuTree.js"
	### ###
}

Generate_Stats(){
	Auto_Startup create 2>/dev/null
	Auto_Cron create 2>/dev/null
	Conf_Exists
	mkdir -p "$(readlink /www/ext)"
	
	pingresult=$(ping -w 10 -q 8.8.8.8)
	
	ping="$(echo "$pingresult" | tail -n 1 | cut -f4 -d"/")"
	pktloss="$(echo "$pingresult" | tail -n 2 | head -n 1 | cut -f3 -d"," | awk '{$1=$1};1' | cut -f1 -d"%")"
	
	TZ=$(cat /etc/TZ)
	export TZ
	DATE=$(date "+%a %b %e %H:%M %Y")
	
	Print_Output "true" "Test results - Ping $ping ms - Packet Loss $pktloss %" "$PASS"
	
	RDB=/jffs/scripts/connmonstats_rrd.rrd
	rrdtool update $RDB N:"$ping":"$pktloss"
	
	COMMON="-c SHADEA#475A5F -c SHADEB#475A5F -c BACK#475A5F -c CANVAS#92A0A520 -c AXIS#92a0a520 -c FONT#ffffff -c ARROW#475A5F -n TITLE:9 -n AXIS:8 -n LEGEND:9 -w 650 -h 200"
	
	D_COMMON='--start -86400 --x-grid MINUTE:20:HOUR:2:HOUR:2:0:%H:%M'
	W_COMMON='--start -604800 --x-grid HOUR:3:DAY:1:DAY:1:0:%Y-%m-%d'
	
	#shellcheck disable=SC2086
	rrdtool graph --imgformat PNG /www/ext/nstats-connmon-ping.png \
		$COMMON $D_COMMON \
		--title "Ping - $DATE" \
		--vertical-label "mSec" \
		DEF:ping="$RDB":ping:LAST \
		CDEF:nping=ping,1000,/ \
		LINE1.5:ping#fc8500:"ping" \
		GPRINT:ping:MIN:"Min\: %3.2lf %s" \
		GPRINT:ping:MAX:"Max\: %3.2lf %s" \
		GPRINT:ping:AVERAGE:"Avg\: %3.2lf %s" \
		GPRINT:ping:LAST:"Curr\: %3.2lf %s\n" >/dev/null 2>&1
	
	#shellcheck disable=SC2086
	rrdtool graph --imgformat PNG /www/ext/nstats-connmon-pktloss.png \
		$COMMON $D_COMMON \
		--title "Packet loss - $DATE" \
		--vertical-label "%" \
		DEF:pktloss="$RDB":pktloss:LAST \
		CDEF:npktloss=pktloss,1000,/ \
		AREA:pktloss#778787:"download" \
		GPRINT:pktloss:MIN:"Min\: %3.2lf \%" \
		GPRINT:pktloss:MAX:"Max\: %3.2lf \%" \
		GPRINT:pktloss:AVERAGE:"Avg\: %3.2lf \%" \
		GPRINT:pktloss:LAST:"Curr\: %3.2lf \%\n" >/dev/null 2>&1
	
	#shellcheck disable=SC2086
	rrdtool graph --imgformat PNG /www/ext/nstats-week-connmon-ping.png \
		$COMMON $W_COMMON \
		--title "Ping - $DATE" \
		--vertical-label "mSec" \
		DEF:ping="$RDB":ping:LAST \
		CDEF:nping=ping,1000,/ \
		LINE1.5:nping#fc8500:"ping" \
		GPRINT:nping:MIN:"WAN Min\: %3.1lf %s" \
		GPRINT:nping:MAX:"WAN Max\: %3.1lf %s" \
		GPRINT:nping:AVERAGE:"Avg\: %3.1lf %s" \
		GPRINT:nping:LAST:"WAN Curr\: %3.1lf %s\n" >/dev/null 2>&1
	
	#shellcheck disable=SC2086
	rrdtool graph --imgformat PNG /www/ext/nstats-week-connmon-pktloss.png \
		$COMMON $W_COMMON --alt-autoscale-max \
		--title "Packet loss - $DATE" \
		--vertical-label "%" \
		DEF:pktloss="$RDB":pktloss:LAST \
		CDEF:npktloss=pktloss,1000,/ \
		AREA:pktloss#778787:"download" \
		GPRINT:pktloss:MIN:"Min\: %3.1lf \%" \
		GPRINT:pktloss:MAX:"Max\: %3.1lf \%" \
		GPRINT:pktloss:AVERAGE:"Avg\: %3.1lf \%" \
		GPRINT:pktloss:LAST:"Curr\: %3.1lf \%\n" >/dev/null 2>&1
}

Shortcut_connmon(){
	case $1 in
		create)
			if [ -d "/opt/bin" ] && [ ! -f "/opt/bin/$CONNMON_NAME" ] && [ -f "/jffs/scripts/$CONNMON_NAME" ]; then
				ln -s /jffs/scripts/"$CONNMON_NAME" /opt/bin
				chmod 0755 /opt/bin/"$CONNMON_NAME"
			fi
		;;
		delete)
			if [ -f "/opt/bin/$CONNMON_NAME" ]; then
				rm -f /opt/bin/"$CONNMON_NAME"
			fi
		;;
	esac
}

PressEnter(){
	while true; do
		printf "Press enter to continue..."
		read -r "key"
		case "$key" in
			*)
				break
			;;
		esac
	done
	return 0
}

ScriptHeader(){
	clear
	
	printf "\\n"
	printf "\\e[1m############################################################\\e[0m\\n"
	printf "\\e[1m##                   _  __  __              _  _          ##\\e[0m\\n"
	printf "\\e[1m##                  | ||  \/  |            | |(_)         ##\\e[0m\\n"
	printf "\\e[1m##   ___  _ __    __| || \  / |  ___  _ __ | | _  _ __    ##\\e[0m\\n"
	printf "\\e[1m##  / __|| '_ \  / _  || |\/| | / _ \| '__|| || || '_ \   ##\\e[0m\\n"
	printf "\\e[1m##  \__ \| |_) || (_| || |  | ||  __/| |   | || || | | |  ##\\e[0m\\n"
	printf "\\e[1m##  |___/| .__/  \__,_||_|  |_| \___||_|   |_||_||_| |_|  ##\\e[0m\\n"
	printf "\\e[1m##      | |                                               ##\\e[0m\\n"
	printf "\\e[1m##      |_|                                               ##\\e[0m\\n"
	printf "\\e[1m##                                                        ##\\e[0m\\n"
	printf "\\e[1m##                 %s on %-9s                    ##\\e[0m\\n" "$CONNMON_VERSION" "$ROUTER_MODEL"
	printf "\\e[1m##                                                        ##\\e[0m\\n"
	printf "\\e[1m##        https://github.com/jackyaz/connmon            ##\\e[0m\\n"
	printf "\\e[1m##                                                        ##\\e[0m\\n"
	printf "\\e[1m############################################################\\e[0m\\n"
	printf "\\n"
}

MainMenu(){
	printf "1.    Check connection now\\n\\n"
	printf "u.    Check for updates\\n"
	printf "uf.   Update %s with latest version (force update)\\n\\n" "$CONNMON_NAME"
	printf "e.    Exit %s\\n\\n" "$CONNMON_NAME"
	printf "z.    Uninstall %s\\n" "$CONNMON_NAME"
	printf "\\n"
	printf "\\e[1m##########################################################\\e[0m\\n"
	printf "\\n"
	
	while true; do
		printf "Choose an option:    "
		read -r "menu"
		case "$menu" in
			1)
				printf "\\n"
				Menu_GenerateStats
				PressEnter
				break
			;;
			u)
				printf "\\n"
				Menu_Update
				PressEnter
				break
			;;
			uf)
				printf "\\n"
				Menu_ForceUpdate
				PressEnter
				break
			;;
			e)
				ScriptHeader
				printf "\\n\\e[1mThanks for using %s!\\e[0m\\n\\n\\n" "$CONNMON_NAME"
				exit 0
			;;
			z)
				while true; do
					printf "\\n\\e[1mAre you sure you want to uninstall %s? (y/n)\\e[0m\\n" "$CONNMON_NAME"
					read -r "confirm"
					case "$confirm" in
						y|Y)
							Menu_Uninstall
							exit 0
						;;
						*)
							break
						;;
					esac
				done
			;;
			*)
				printf "\\nPlease choose a valid option\\n\\n"
			;;
		esac
	done
	
	ScriptHeader
	MainMenu
}

Check_Requirements(){
	CHECKSFAILED="false"
	
	if [ "$(nvram get jffs2_scripts)" -ne 1 ]; then
		nvram set jffs2_scripts=1
		nvram commit
		Print_Output "true" "Custom JFFS Scripts enabled" "$WARN"
	fi
	
	if [ ! -f "/opt/bin/opkg" ]; then
		Print_Output "true" "Entware not detected!" "$ERR"
		CHECKSFAILED="true"
	fi
	
	if [ "$CHECKSFAILED" = "false" ]; then
		return 0
	else
		return 1
	fi
}

Menu_Install(){
	Print_Output "true" "Welcome to $CONNMON_NAME $CONNMON_VERSION, a script by JackYaz"
	sleep 1
	
	Print_Output "true" "Checking your router meets the requirements for $CONNMON_NAME"
	
	if ! Check_Requirements; then
		Print_Output "true" "Requirements for $CONNMON_NAME not met, please see above for the reason(s)" "$CRIT"
		PressEnter
		Clear_Lock
		exit 1
	fi
	
	opkg update
	opkg install rrdtool
	
	Conf_Exists
	
	Mount_CONNMON_WebUI
	
	Modify_WebUI_File
	
	RRD_Initialise
	
	Shortcut_connmon create
	
	Menu_GenerateStats
}

Menu_Startup(){
	Check_Lock
	Auto_Startup create 2>/dev/null
	Auto_Cron create 2>/dev/null
	Mount_CONNMON_WebUI
	Modify_WebUI_File
	RRD_Initialise
	CacheGraphImages extract 2>/dev/null
	Clear_Lock
}

Menu_GenerateStats(){
	Check_Lock
	Generate_Stats
	Clear_Lock
}

Menu_Update(){
	Check_Lock
	Update_Version
	Clear_Lock
}

Menu_ForceUpdate(){
	Check_Lock
	Update_Version force
	Clear_Lock
}

Menu_Uninstall(){
	Check_Lock
	Print_Output "true" "Removing $CONNMON_NAME..." "$PASS"
	Auto_Startup delete 2>/dev/null
	Auto_Cron delete 2>/dev/null
	while true; do
		printf "\\n\\e[1mDo you want to delete %s stats? (y/n)\\e[0m\\n" "$CONNMON_NAME"
		read -r "confirm"
		case "$confirm" in
			y|Y)
				rm -f "/jffs/scripts/connmonstats_rrd.rrd" 2>/dev/null
				break
			;;
			*)
				break
			;;
		esac
	done
	Shortcut_connmon delete
	umount /www/AdaptiveQoS_ROG.asp 2>/dev/null
	sed -i '/{url: "AdaptiveQoS_ROG.asp", tabName: "Uptime Monitoring"}/d' "/jffs/scripts/custom_menuTree.js"
	umount /www/require/modules/menuTree.js 2>/dev/null
	
	if [ ! -f "/jffs/scripts/ntpmerlin" ] && [ ! -f "/jffs/scripts/spdmerlin" ]; then
		opkg remove --autoremove rrdtool
		rm -f "/jffs/scripts/custom_menuTree.js" 2>/dev/null
	else
		mount -o bind "/jffs/scripts/custom_menuTree.js" "/www/require/modules/menuTree.js"
	fi
	rm -f "/jffs/scripts/connmonstats_www.asp" 2>/dev/null
	rm -f "/jffs/scripts/$CONNMON_NAME" 2>/dev/null
	Clear_Lock
	Print_Output "true" "Uninstall completed" "$PASS"
}

if [ -z "$1" ]; then
	Check_Lock
	Auto_Startup create 2>/dev/null
	Auto_Cron create 2>/dev/null
	Shortcut_connmon create
	Clear_Lock
	Conf_Exists
	ScriptHeader
	MainMenu
	exit 0
fi

case "$1" in
	install)
		Menu_Install
		exit 0
	;;
	startup)
		Menu_Startup
		exit 0
	;;
	generate)
		Menu_GenerateStats
		exit 0
	;;
	update)
		Menu_Update
		exit 0
	;;
	forceupdate)
		Menu_ForceUpdate
		exit 0
	;;
	uninstall)
		Menu_Uninstall
		exit 0
	;;
	*)
		Check_Lock
		echo "Command not recognised, please try again"
		Clear_Lock
		exit 1
	;;
esac
