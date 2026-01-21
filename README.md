# get_iostat

This is a shell script that a sysadmin will run via cron on a Linux host to collect iostat performance metrics.

Data is saved in CSV format for further analysis in a spreadsheet, if gnuplot is available, graphs will be automatically generated.

# Usage
Sample installation:
```
sudo bash
cd /tmp
git clone https://github.com/nickjeffrey/get_iostat
cd get_iostat
cp get_iostat_data.sh /root/get_iostat_data.sh
chmod +x /root/get_iostat_data.sh
```

Create a crontab entry similar to the following.  You will notice that the script runs every minute, but several of the tasks check the current time and only run every 10 minutes or every hour.
```
* * * * * /root/get_iostat_data.sh >/dev/null 2>&1  #capture iostat perf data
```

# Ongoing Maintenance
The script automatically deletes files older than 7 days, so this is intended as a rolling reference point to help a sysadmin troubleshoot performance issues.  
This is not intended to be a long-term performance monitoring / metrics collection tool.

# Output
Look in /tmp/iostat/
```
ls -l /tmp/iostat/*.csv
ls -l /tmp/iostat/*.png
```


