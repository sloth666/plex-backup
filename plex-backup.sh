#!/bin/bash
#
# Plex Linux Server backup tool
#
# Req: apt-get install p7zip-full p7zip-rar lbzip2
#
##############################################################################

if [ -z "${BASH_VERSINFO}" ]; then
	echo "ERROR: You must execute this script with BASH" >&2
	exit 255
fi

# Defaults, editable. Make sure paths end with /
SERVICE_NAME="plexmediaserver"
PLEXDB_PATH="/var/lib/plexmediaserver/Library/Application Support/Plex Media Server/"
BACKUP_PATH="plexdb/"
BACKUP_DEST="//mnt/nas/backups/plex/"
COMPRESS_RATE=9  # 1-9
VERIFY_ARCHIVE="y"

# Internal vars (do not edit!)
LOG_PATH=$BACKUP_DEST
SCRIPT_NAME="$(basename ${0})"
NOW="$(date +%Y%m%d-%H_%M_%S)"
LOGFILE="${SERVICE_NAME}_${NOW}.log"
LOG="${BACKUP_DEST}${LOGFILE}"
TAR_FILE="${SERVICE_NAME}_${NOW}.tar"
PLEX_PID=""

export LBZIP2=-v

# Check for root permissions
#if [[ $EUID -ne 0 ]]; then
#  echo -e "${SCRIPT_NAME} requires root privledges.\n"
#  echo -e "sudo $0 $*\n"
#  exit 1
#fi

[[ -d $BACKUP_PATH ]] || mkdir $BACKUP_PATH
[[ -d $LOG_PATH ]] || mkdir $LOG_PATH

function print_db_size {
  printf "...current backup disk size is: %s\n" "$(du -sh plexdb)"
}

#function e {
#  echo $1 
#} 

# systemctl is-active
 

{
    printf "...starting backup at: %s\n" "$(date +%Y-%m-%d-%H:%M:%S)"
    print_db_size
    
    PLEX_PID=$(pidof "Plex Media Server")
    
    if [[ $PLEX_PID -eq 0 ]]; then
      printf "...plex media server is not running.\n"     
    else
      printf "...stop service: %s (%s)\n" "$SERVICE_NAME" "$PLEX_PID" 
      sudo /bin/systemctl stop $SERVICE_NAME
      
      while kill -s 0 $PLEX_PID;
      do
        printf "."
        sleep 0.5
      done
    
      printf "...stopped: %s (%s)\n" "$SERVICE_NAME" "$PLEX_PID"
    fi
    
    printf "...start rsync.\n"
    rsync -azhm --no-owner --no-group --stats --exclude-from="plex.excludes" "$PLEXDB_PATH" "$BACKUP_PATH"
    printf "...rsync done.\n"    

    printf "...create archive: %s\n" "$TAR_FILE"
    # tar cf -ML 1048576 --totals --checkpoint 100 "${TAR_FILE}.bz2" -C "$BACKUP_PATH" --use-compress-program lbzip2 
    tar -cf "$TAR_FILE" "$BACKUP_PATH" --totals --checkpoint=100000
    
    printf "...start compressing /w block size: (%s).\n" "$COMPRESS_RATE"
    lbzip2 --verbose -$COMPRESS_RATE $TAR_FILE
    
    if [[ $VERIFY_ARCHIVE -eq "y" ]]; then
        printf "Verify archive: %s" "${TAR_FILE}.bz2"
        lbzip2 -tv "${TAR_FILE}.bz2"
    fi
    
    printf "...move %s -> %s.\n" "${TAR_FILE}.bz2" "$BACKUP_DEST"
    cp "${TAR_FILE}.bz2" "${BACKUP_DEST}" && rm "${TAR_FILE}.bz2"
   
    printf "...start service: %s\n" "$SERVICE_NAME"        
    
    PLEX_PID=$(pidof "Plex Media Server")
    sudo /bin/systemctl start $SERVICE_NAME
        
    while ! kill -s 0 $PLEX_PID;
    do
      printf "."
      sleep 0.5
      PLEX_PID=$(pidof "Plex Media Server")
    done
    
    PLEX_PID=$(pidof "Plex Media Server")
    printf "...started with plex with pid: %s\n" "$PLEX_PID"   
    
    print_db_size
    printf "...backup done at: %s\n" "$(date +%Y-%m-%d-%H:%M:%S)"
    
} 2>&1 | tee -a $LOG
