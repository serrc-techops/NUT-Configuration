#!/bin/bash
# Setup upsmon launchd for autostart on OSX slave

# check if root/sudo
if [ "$EUID" -ne 0 ]
  then echo "Must be run as root"
  exit
fi

# create launchd plist for upsmon
cat << EOF > /Library/LaunchDaemons/org.networkupstools.upsmon.plist
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
    <dict>
        <key>KeepAlive</key>
        <true/>
        <key>Label</key>
        <string>org.networkupstools.upsmon</string>
        <key>ProgramArguments</key>
        <array>
            <string>/usr/local/sbin/upsmon</string>
            <string>-D</string>
        </array>
        <key>RunAtLoad</key>
        <true/>
    </dict>
</plist>
EOF

# load launchd plist
/bin/launchctl load /Library/LaunchDaemons/org.networkupstools.upsmon.plist