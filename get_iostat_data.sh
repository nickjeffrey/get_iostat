#!/bin/sh

# CHANGE LOG
# -----------
# 2021-09-22    njeffrey        script created
# 2022-10-29    njeffrey        add vmstat output
# 2022-11-24    njeffrey        add df output
# 2026-01-19    njeffrey        convert iostat CPU data to CSV format for easy graphing and visualization
# 2026-01-20    njeffrey        add optional gnuplot visualization 
# 2026-02-18    njeffrey        convert iostat disk data to CSV format for easy graphing and visualization
# 2026-02-18    njeffrey        add "top" and "ps -ef" output


# USAGE
# -----
# this script runs once per minute from cron
# * * * * * /root/get_iostat_data.sh >/dev/null 2>&1  #capture iostat perf data

# OUTSTANDING TASKS
# ------------------
# /bin/sh is symlinked to /bin/fish on ubuntu, if statements may not work, test on ubuntu, or change to /bin/bash


# NOTES
# -----
# This script captures iostat data for performance troubleshooting
# Old files are automatically deleted after 14 days
# This script has GNU-isms like "df -h" and "sed -i", so will likely not work on BSD, AIX, etc.


# declare variables
datestamp=`date +%Y%m%d%H%M`
YEAR=`date +%Y`
MONTH=`date +%m`
DAY=`date +%d`
HOUR=`date +%H`
MINUTE=`date +%M`


# confirm required files exist
test -f /usr/bin/nmon   || echo ERROR: Cannot find /usr/bin/nmon.   Please install with yum install nmon
test -f /usr/bin/iostat || echo ERROR: Cannot find /usr/bin/iostat. Please install with yum install sysstat
test -f /usr/bin/vmstat || echo ERROR: Cannot find /usr/bin/vmstat. Please install with yum install procps-ng
test -f /usr/bin/top    || echo ERROR: Cannot find /usr/bin/top.    Please install with yum install procps-ng
test -f /usr/bin/ps     || echo ERROR: Cannot find /usr/bin/ps.     Please install with appropriate commands for your distro.


# confirm target folder exists
test -d /tmp/iostat || mkdir -p /tmp/iostat
test -d /tmp/iostat || echo ERROR: could not create directory /tmp/iostat
test -d /tmp/iostat || exit


# delete files older than 7 days to avoid filling up the filesystem
echo Deleting old files from /tmp/iostat/
find /tmp/iostat -type f -mtime +7   -name 'iostat.cpu.[0-9]*.txt'    -execdir rm -- '{}' \;
find /tmp/iostat -type f -mtime +7   -name 'iostat.disk.[0-9]*.txt'   -execdir rm -- '{}' \;
find /tmp/iostat -type f -mtime +7   -name 'vmstat.[0-9]*.txt'        -execdir rm -- '{}' \;
find /tmp/iostat -type f -mtime +7   -name 'nmon.*.csv'               -execdir rm -- '{}' \;
find /tmp/iostat -type f -mtime +7   -name 'df.[0-9]*.txt'            -execdir rm -- '{}' \;
find /tmp/iostat -type f -mtime +7   -name 'top.[0-9]*.txt'           -execdir rm -- '{}' \;
find /tmp/iostat -type f -mtime +7   -name 'ps.[0-9]*.txt'            -execdir rm -- '{}' \;
find /tmp/iostat -type f -mtime +365 -name 'iostat.cpu.summary*.csv'  -execdir rm -- '{}' \;  #keep monthly summary files for a year
find /tmp/iostat -type f -mtime +365 -name 'iostat.disk.summary*.csv' -execdir rm -- '{}' \;  #keep monthly summary files for a year


#capture iostat data
echo Capturing iostat metrics
#get 10 iterations one per second worth of CPU
/usr/bin/iostat -t -y -c 1 10 > /tmp/iostat/iostat.cpu.$datestamp.txt
#get 1 iteration of disk
/usr/bin/iostat -t -y -d -x -m 1 1 > /tmp/iostat/iostat.disk.$datestamp.txt


# capture vmstat data, because the DBA team wants to see vmstat output, even though it gives the same CPU usage info as iostat
# only capture once every 10 minutes to save disk space
echo $MINUTE | grep -E "00|10|20|30|40|50" && echo Capturing vmstat metrics && /usr/bin/vmstat 1 10 >/tmp/iostat/vmstat.$datestamp.txt


# capture top data to find any big CPU or RAM users
# only capture once every 10 minutes to save disk space
echo $MINUTE | grep -E "00|10|20|30|40|50" && echo Capturing top metrics && /usr/bin/top -b -n 1 >/tmp/iostat/top.$datestamp.txt


# capture ps output to show running processes
# only capture once every 10 minutes to save disk space
echo $MINUTE | grep -E "00|10|20|30|40|50" && echo Capturing ps metrics && /usr/bin/ps -ef  >/tmp/iostat/ps.$datestamp.txt


# capture nmon data, because it shows the utilization of each processor core
# the nmon data is quote verbose, so consumes a lot of space, so only capture once every 10 minutes
echo Capturing nmon metrics
echo $MINUTE | grep -E "01|11|21|31|41|51" && test -f /usr/bin/nmon && /usr/bin/nmon -F /tmp/iostat/nmon.$datestamp.csv -s 1 -c 10


# capture filesystem usage hourly
if [[ "$MINUTE" == "00" ]]; then
   /bin/df -h > /tmp/iostat/df.$datestamp.txt
fi


# hourly task, convert iostat CPU data to CSV format
if [[ "$MINUTE" == "59" ]]; then
   echo Converting iostat CPU output to CSV
   set -euo pipefail
   INPUT_DIR="/tmp/iostat"
   GLOB_PREFIX="iostat.cpu.${YEAR}${MONTH}${DAY}${HOUR}"
   OUT_CSV="/tmp/iostat/iostat.cpu.summary.$YEAR-$MONTH.csv"

   # If the CSV file does not already exist, create the header once
   if [[ ! -f "$OUT_CSV" ]]; then
      echo "timestamp,user,nice,system,iowait,steal,idle" > "$OUT_CSV"
   fi
   #
   find "$INPUT_DIR" -type f -name "${GLOB_PREFIX}*" | sort | while IFS= read -r file; do
      echo Appending iostat data from $file into CSV format to $OUT_CSV
      #
      # Sample contents of input file:
      # Linux 5.14.0-651.el9.x86_64 (myserver.example.com)  01/20/2026      _x86_64_        (1 CPU)
      # 01/20/2026 10:24:08 AM
      # avg-cpu:  %user   %nice %system %iowait  %steal   %idle
      #     2.02    0.00    1.01    0.00    0.00   96.97
      #
      # 01/20/2026 10:24:09 AM
      # avg-cpu:  %user   %nice %system %iowait  %steal   %idle
      #     4.00    0.00    5.00    0.00    0.00   91.00
      #
      # Explanation to grep/sed/awk manipulation:
      # grep -v "^Linux"							Get rid of header line in iostat output
      # grep -v "^avg-cpu"							Get rid of header line in iostat output
      # sed '/^[0-9]\{2\}\/[0-9]\{2\}\/[0-9]\{4\}/{N;s/\n[[:space:]]*/,/}' 	Capture the datestamp line, remove \n newline at end to join with data values line, remove spaces at beginning of next line
      # grep [0-9] 								Skip any blank linkes
      # awk -F',' '{gsub(/[[:space:]]+/, ",", $2); print $1 "," $2}'		Convert the space-separated numbers to CSV
      # The final outcome after all of the above is a single CSV line similar to: 01/20/2026 10:24:09 AM,4.00,0.00,5.00,0.00,0.00,91.00
      #
      cat $file | grep -v "^Linux" | grep -v ^avg-cpu | sed '/^[0-9]\{2\}\/[0-9]\{2\}\/[0-9]\{4\}/{N;s/\n[[:space:]]*/,/}' | grep [0-9] | awk -F',' '{gsub(/[[:space:]]+/, ",", $2); print $1 "," $2}' >> "$OUT_CSV"
   done
   echo "Appended hourly iostat CPU summary to: $OUT_CSV"
   #
   #
   # iostat will output datestamps in this format: 01/20/2026 10:34:08 PM
   # But we want the timestamps in ISO8601 format: 2026-01-20T22:22:34:08 because gnuplot prefers ISO8601 dates
   # Perform an in-place conversion of the CSV file to modify the formatting of the timestamps.
   # This conversion is idempotent so it can be run multiple times without problems
   # Before this conversion process runs, the CSV file will look like this: 01/20/2026 10:24:09 AM,4.00,0.00,5.00,0.00,0.00,91.00
   # After  this conversion process runs, the CSV file will look like this: 2026-10-20T22:24:09,4.00,0.00,5.00,0.00,0.00,91.00
   #
   file=$OUT_CSV
   tmpfile="$(mktemp)"
   {
      IFS= read -r header
      echo "$header"
      while IFS=, read -r ts rest; do
         ts=${ts#\"}; ts=${ts%\"}                               # strip optional quotes
         iso="$(date -d "$ts" '+%Y-%m-%dT%H:%M:%S' 2>/dev/null)" || continue
         printf '%s,%s\n' "$iso" "$rest"
      done
   } < "$file" > "$tmpfile" && mv -f "$tmpfile" "$file" 		#write to temporary file then rename back to original file
   #
   #
   # if gnuplot is available, visualize the data
   #
   if [ -x "/bin/gnuplot" ]; then
      #
      # creating gnuplot script
      #
      GNUPLOT_SCRIPT=/tmp/iostat/iostat.cpu.gnuplot
      test -f $GNUPLOT_SCRIPT && rm -f $GNUPLOT_SCRIPT 
      test -f $GNUPLOT_SCRIPT && echo ERROR: could not delete old version of $GNUPLOT_SCRIPT 
      #
      echo 'set terminal pngcairo size 1400,650'					>> $GNUPLOT_SCRIPT 
      echo "set output \"/tmp/iostat/iostat.cpu.stacked.$YEAR-$MONTH.png\""		>> $GNUPLOT_SCRIPT 	#output filename includes $YEAR-$MONTH timestamp 
      echo ' '	                                                                        >> $GNUPLOT_SCRIPT
      echo 'set datafile separator ","'							>> $GNUPLOT_SCRIPT 
      echo 'set xdata time'								>> $GNUPLOT_SCRIPT 
      echo 'set timefmt "%Y-%m-%dT%H:%M:%S"'						>> $GNUPLOT_SCRIPT 
      echo '#set format x "%H:%M:%S"'							>> $GNUPLOT_SCRIPT 
      echo 'set format x "%Y-%m-%d %H:%M"'						>> $GNUPLOT_SCRIPT 
      echo 'set xtics rotate by 90 right'						>> $GNUPLOT_SCRIPT 
      echo '# reduce clutter if many points'						>> $GNUPLOT_SCRIPT 
      echo 'set xtics nomirror'								>> $GNUPLOT_SCRIPT 
      echo 'set xtics out'								>> $GNUPLOT_SCRIPT 
      echo 'set xtics rotate by 90 right'						>> $GNUPLOT_SCRIPT 
      echo '# prevent x axis labels from overlapping by reducing tick frequency'	>> $GNUPLOT_SCRIPT 
      echo '#set xtics auto'								>> $GNUPLOT_SCRIPT 
      echo '#set xtics rotate by 90 right'						>> $GNUPLOT_SCRIPT 
      echo '#set xtics 60   # one label every 60 seconds (time axis)'			>> $GNUPLOT_SCRIPT 
      echo ' '	                                                                        >> $GNUPLOT_SCRIPT
      echo 'set xlabel "Time"'								>> $GNUPLOT_SCRIPT
      echo 'set ylabel "CPU %"'								>> $GNUPLOT_SCRIPT
      echo 'set title "CPU Utilization (stacked)"'					>> $GNUPLOT_SCRIPT
      echo 'set yrange [0:100]'								>> $GNUPLOT_SCRIPT
      echo ' '	                                                                        >> $GNUPLOT_SCRIPT
      echo 'set key outside'								>> $GNUPLOT_SCRIPT
      echo 'set style fill solid 1.0 border -1'						>> $GNUPLOT_SCRIPT
      echo ' '	                                                                        >> $GNUPLOT_SCRIPT
      echo '# Styles'									>> $GNUPLOT_SCRIPT
      echo 'set style line 1 lc rgb "#4C72B0" lw 1   # user (blue)'			>> $GNUPLOT_SCRIPT
      echo 'set style line 2 lc rgb "#ADD8E6" lw 1   # nice (lightblue)'		>> $GNUPLOT_SCRIPT
      echo 'set style line 3 lc rgb "#800080" lw 1   # system (purple)'			>> $GNUPLOT_SCRIPT
      echo 'set style line 4 lc rgb "#FF0000" lw 1   # iowait (red)'			>> $GNUPLOT_SCRIPT
      echo 'set style line 5 lc rgb "#A52A2A" lw 1   # steal (brown)'			>> $GNUPLOT_SCRIPT
      echo 'set style line 6 lc rgb "#90EE90" lw 1   # idle (lightgreen)'		>> $GNUPLOT_SCRIPT
      echo ' '	                                                                        >> $GNUPLOT_SCRIPT
      echo 'plot \'									>> $GNUPLOT_SCRIPT
      echo "  \"$OUT_CSV\" using 1:2 with filledcurves x1 ls 1 notitle, \\"		>> $GNUPLOT_SCRIPT	#input filename is based on a variable, fiddly with escaping " and \
      echo '  ""      using 1:2 with lines ls 1 title "user", \'			>> $GNUPLOT_SCRIPT
      echo '  ""      using 1:($2+$3) with filledcurves x1 ls 2 notitle, \'		>> $GNUPLOT_SCRIPT
      echo '  ""      using 1:($2+$3) with lines ls 2 title "nice", \'			>> $GNUPLOT_SCRIPT
      echo '  ""      using 1:($2+$3+$4) with filledcurves x1 ls 3 notitle, \'		>> $GNUPLOT_SCRIPT
      echo '  ""      using 1:($2+$3+$4) with lines ls 3 title "system", \'		>> $GNUPLOT_SCRIPT
      echo '  ""      using 1:($2+$3+$4+$5) with filledcurves x1 ls 4 notitle, \'	>> $GNUPLOT_SCRIPT
      echo '  ""      using 1:($2+$3+$4+$5) with lines ls 4 title "iowait", \'		>> $GNUPLOT_SCRIPT
      echo '  ""      using 1:($2+$3+$4+$5+$6) with filledcurves x1 ls 5 notitle, \'	>> $GNUPLOT_SCRIPT
      echo '  ""      using 1:($2+$3+$4+$5+$6) with lines ls 5 title "steal", \'	>> $GNUPLOT_SCRIPT
      echo '  ""      using 1:($2+$3+$4+$5+$6+$7) with filledcurves x1 ls 6 notitle, \'	>> $GNUPLOT_SCRIPT
      echo '  ""      using 1:($2+$3+$4+$5+$6+$7) with lines ls 6 title "idle"'		>> $GNUPLOT_SCRIPT
      #
      echo Creating gnuplot diagram of iostat CPU
      /bin/gnuplot $GNUPLOT_SCRIPT
   fi 
fi




# hourly task, convert iostat disk data to CSV format
#
if [[ "$MINUTE" == "59" ]]; then
   echo Converting iostat disk output to CSV
   set -euo pipefail
   INPUT_DIR="/tmp/iostat"
   GLOB_PREFIX="iostat.disk.${YEAR}${MONTH}${DAY}${HOUR}"
   OUT_CSV="/tmp/iostat/iostat.disk.summary.$YEAR-$MONTH.csv"
   #
   # If the CSV file does not already exist, create the header once
   if [[ ! -f "$OUT_CSV" ]]; then
      echo "timestamp,device,iops_r,MBps_r,rrqmps,rrqm_pct,r_await,rareq_sz,ws,MBps_w,wrqmps,wrqm_pct,w_await,wareq_sz,ds,dMBps,drqm_pct,d_await,dareq_sz,fs,f_await,aqu_sz,util_pct" > "$OUT_CSV"
   fi
   #
   find "$INPUT_DIR" -type f -name "${GLOB_PREFIX}*" | sort | while IFS= read -r file; do
      echo Appending iostat data from $file into CSV format to $OUT_CSV
      #
      # Sample contents of input file:
      # Linux 5.14.0-651.el9.x86_64 (myserver.example.com)  01/20/2026      _x86_64_        (1 CPU)
      # 02/18/2026 12:45:12 PM
      # Device            r/s     rMB/s   rrqm/s  %rrqm r_await rareq-sz     w/s     wMB/s   wrqm/s  %wrqm w_await wareq-sz     d/s     dMB/s   drqm/s  %drqm d_await dareq-sz     f/s f_await  aqu-sz  %util
      # dm-0             0.00      0.00     0.00   0.00    0.00     0.00    0.00      0.00     0.00   0.00    0.00     0.00    0.00      0.00     0.00   0.00    0.00     0.00    0.00    0.00    0.00   0.00
      # dm-1             0.00      0.00     0.00   0.00    0.00     0.00    0.00      0.00     0.00   0.00    0.00     0.00    0.00      0.00     0.00   0.00    0.00     0.00    0.00    0.00    0.00   0.00
      # sda              0.00      0.00     0.00   0.00    0.00     0.00    0.00      0.00     0.00   0.00    0.00     0.00    0.00      0.00     0.00   0.00    0.00     0.00    0.00    0.00    0.00   0.00
      # sdb              0.00      0.00     0.00   0.00    0.00     0.00    0.00      0.00     0.00   0.00    0.00     0.00    0.00      0.00     0.00   0.00    0.00     0.00    0.00    0.00    0.00   0.00
      #
      # Explanation to awk manipulation:
      # <to be written>
      # The final outcome after all of the above is a single CSV line similar to: 01/20/2026 10:24:09 AM,4.00,0.00,5.00,0.00,0.00,91.00
      # 02/18/2026 03:31:13 PM,dm-0,0.00,0.00,0.00,0.00,0.00,0.00,0.00,0.00,0.00,0.00,0.00,0.00,0.00,0.00,0.00,0.00,0.00,0.00,0.00,0.00,0.00,0.00
      # 02/18/2026 03:31:13 PM,dm-1,0.00,0.00,0.00,0.00,0.00,0.00,0.00,0.00,0.00,0.00,0.00,0.00,0.00,0.00,0.00,0.00,0.00,0.00,0.00,0.00,0.00,0.00
      # 02/18/2026 03:31:13 PM,sda,0.00,0.00,0.00,0.00,0.00,0.00,0.00,0.00,0.00,0.00,0.00,0.00,0.00,0.00,0.00,0.00,0.00,0.00,0.00,0.00,0.00,0.00
      # 02/18/2026 03:31:13 PM,sdb,0.00,0.00,0.00,0.00,0.00,0.00,0.00,0.00,0.00,0.00,0.00,0.00,0.00,0.00,0.00,0.00,0.00,0.00,0.00,0.00,0.00,0.00
      #
      awk '
         BEGIN { OFS=","; header_printed=0; ts=""; in_table=0 }
         #
         # handle CRLF files (Windows-style line endings)
         { sub(/\r$/, "", $0) }
         # 
         # Timestamp line (allow leading whitespace)
         $0 ~ /^[[:space:]]*[0-9]{2}\/[0-9]{2}\/[0-9]{4}[[:space:]]+[0-9]{2}:[0-9]{2}:[0-9]{2}[[:space:]]+[AP]M[[:space:]]*$/ {
            ts=$0
            sub(/^[[:space:]]+/, "", ts)
            sub(/[[:space:]]+$/, "", ts)
            in_table=0
            next
         }
         # 
         # Ignore Linux banner header line and blank lines
         $0 ~ /^[[:space:]]*Linux[[:space:]]/ { next }
         $0 ~ /^[[:space:]]*$/ { next }
         # 
         # Device header (allow leading whitespace)
         $0 ~ /^[[:space:]]*Device[[:space:]]+/ {
            in_table=1
            if (!header_printed) {
               line=$0
               sub(/^[[:space:]]+/, "", line)
               sub(/[[:space:]]+$/, "", line)
               gsub(/[[:space:]]+/, ",", line)
               print "timestamp", line
               header_printed=1
            }
            next
         }
         #
         # Device rows
         in_table==1 && ts!="" {
            line=$0
            sub(/^[[:space:]]+/, "", line)
            sub(/[[:space:]]+$/, "", line)
            gsub(/[[:space:]]+/, ",", line)
            print ts, line
            next
         }
      ' $file >> $OUT_CSV
   done
   echo "Appended hourly iostat disk summary to: $OUT_CSV"
   #
   #
   # iostat will output datestamps in this format: 01/20/2026 10:34:08 PM
   # But we want the timestamps in ISO8601 format: 2026-01-20T22:22:34:08 because gnuplot prefers ISO8601 dates
   # Perform an in-place conversion of the CSV file to modify the formatting of the timestamps.
   # This conversion is idempotent so it can be run multiple times without problems
   # Before this conversion process runs, the CSV file will look like this: 12/18/2026 4:56:12 PM,sda,0.00,0.00,0.00,0.00,0.00,0.00,0.00,0.00,0.00,0.00,0.00,0.00,0.00,0.00,0.00,0.00,0.00,0.00,0.00,0.00,0.00,0.00
   # After  this conversion process runs, the CSV file will look like this: 2026-02-18T16:56:12,sda,0.00,0.00,0.00,0.00,0.00,0.00,0.00,0.00,0.00,0.00,0.00,0.00,0.00,0.00,0.00,0.00,0.00,0.00,0.00,0.00,0.00,0.00
   #
   file=$OUT_CSV
   tmpfile="$(mktemp)"
   {
      IFS= read -r header
      echo "$header"
      while IFS=, read -r ts rest; do
         ts=${ts#\"}; ts=${ts%\"}                               # strip optional quotes
         iso="$(date -d "$ts" '+%Y-%m-%dT%H:%M:%S' 2>/dev/null)" || continue
         printf '%s,%s\n' "$iso" "$rest"
      done
   } < "$file" > "$tmpfile" && mv -f "$tmpfile" "$file" 		#write to temporary file then rename back to original file
fi

