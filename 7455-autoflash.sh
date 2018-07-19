#/bin/bash
# sudo bash <(curl -Ss https://url/7455-autoflash.sh)

if [ "$EUID" -ne 0 ]
  then echo "Please run with sudo or as root"
  exit
fi

echo "---"
echo 'Searching for Qualcomm USB modems...'
modemcount=`lsusb | grep -E '1199:9071|1199:9079|413C:81B6' | wc -l`
while [ $modemcount -eq 0 ]
do
    echo "---"
    echo "Could not find any Qualcomm USB modems"
	echo 'Unplug and reinsert the EM7455 USB connector...'
    modemcount=`lsusb | grep -E '1199:9071|1199:9079|413C:81B6' | wc -l`
    sleep 5
done

echo "Found EM/MC 7455: 
`lsusb | grep -E '1199:9071|1199:9079|413C:81B6'`
"

if [ $modemcount -gt 1 ]
then 
	echo "---"
	echo "Found more than one EM7455/MC7455, remove the one you dont want to flash and try again."
	exit
fi

# Stop modem manager to prevent AT command spam and allow firmware-update
systemctl stop ModemManager

# Install all needed prerequisites
apt-get update
apt-get install git make gcc curl -y
yes | cpan install UUID::Tiny IPC::Shareable JSON

# Install Modem Mode Switcher
git clone https://github.com/mavstuff/swi_setusbcomp.git
chmod +x ~/swi_setusbcomp/scripts_swi_setusbcomp.pl

# Modem Mode Switch to usbcomp=8 (DM   NMEA  AT    MBIM)
~/swi_setusbcomp/scripts_swi_setusbcomp.pl --usbcomp=8

startcount=`dmesg | grep 'Qualcomm USB modem converter detected' | wc -l`
endcount=0

echo "---"
echo 'Unplug and reinsert the EM7455 USB connector...'
while [ $endcount -le $startcount ]
do
    endcount=`dmesg | grep 'Qualcomm USB modem converter detected' | wc -l`
    echo 'Unplug and reinsert the EM7455 USB connector...'
    sleep 5
done

ttyUSB=`dmesg | grep '.3: Qualcomm USB modem converter detected' -A1 | grep ttyUSB | awk '{print $12}' | sort -u`

# Cat the serial port to monitor output and commands. cat will exit when AT!RESET kicks off.
cat /dev/$ttyUSB &

# Display current modem settings
echo 'ATE
ATI
AT!ENTERCND="A710"
AT!IMPREF?
AT!GOBIIMPREF?
AT!USBCOMP?
AT!USBVID?
AT!USBPID?
AT!USBPRODUCT?
AT!PRIID?
AT!SELRAT?
AT!BAND?
AT!IMAGE?' |
while read newline; 
do
	printf "$newline\r\n" > /dev/$ttyUSB
	printf "\r\n" > /dev/$ttyUSB
	sleep 1
done 


while [[ ! $REPLY =~ ^[Yy]$ ]]
do
	read -p '
	Warning: This will overwrite all settings with generic EM7455 Settings?
	Are you sure you want to continue? (CTRL+C to exit) ' -n 1 -r
	if [[ $REPLY =~ ^[Nn]$ ]]
	then
		printf '\r\n'; break
	fi
done

# Set Generic Sierra Wireless VIDs/PIDs
if [[ $REPLY =~ ^[Yy]$ ]]
then
	echo 'AT!IMPREF="GENERIC"
AT!GOBIIMPREF="GENERIC"
AT!USBCOMP=1,1,0000100D
AT!USBVID=1199
AT!USBPID=9071,9070
AT!USBPRODUCT="EM7455"
AT!PRIID="9904609","002.026","Generic-Laptop"
AT!SELRAT=06
AT!BAND=00
AT!IMAGE=0
AT!RESET
AT!RESET' | 
	while read newline; do
		printf "$newline\r\n" > /dev/$ttyUSB
		printf "\r\n" > /dev/$ttyUSB
		sleep 1
	done 
fi

# Install qmi-utilities
curl -o libqmi-utils_1.18.0-3ubuntu1_amd64.deb -L http://mirrors.edge.kernel.org/ubuntu/pool/universe/libq/libqmi/libqmi-utils_1.18.0-3ubuntu1_amd64.deb
dpkg -i libqmi-utils_1.18.0-3ubuntu1_amd64.deb

# Download and unzip firmware
curl -o SWI9X30C_02.24.05.06_Generic_002.026_000.zip -L https://source.sierrawireless.com/~/media/support_downloads/airprime/74xx/fw/02_24_05_06/7430/swi9x30c_02.24.05.06_generic_002.026_000.ashx 
unzip SWI9X30C_02.24.05.06_Generic_002.026_000.zip

# Flash SWI9X30C_02.24.05.06_GENERIC_002.026_000 onto Generic Sierra Modem
qmi-firmware-update --update -d "1199:9071" SWI9X30C_02.24.05.06.cwe SWI9X30C_02.24.05.06_GENERIC_002.026_000.nvu
sleep 10

#Done, restart ModemManager
systemctl start ModemManager

echo "Done!"
echo "Please unplug your modem and reinsert it."
