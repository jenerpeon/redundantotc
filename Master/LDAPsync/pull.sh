#!/usr/bin/env bash

## BOOTSTRAP ##
source "$( cd "${BASH_SOURCE[0]%/*}" && pwd )/lib/oo-framework.sh"

import lib/type-core
import lib/system/00_log
import lib/lars/logger
import lib/lars/check
import lib/lars/test_con

SRC=${SRC-10.224.129.216}
HOST_USER="root"
TARGET="10.224.129.66"
TARGET_USER="root"

# Location of storage definition
SRC_DIR="/root/LDAPsync"
SRC_OTC_DIR="/opt/openthinclient/server/default/data/nfs/root/"
SRC_OTC_META=$(echo ${SRC_OTC_DIR}{tftp/,sfs/,schema/})
TARGET_DIR="/root/LDAPsync"


# SSH configurations
SSH_TARGET=$TARGET_USER'@'$TARGET
SSH_SRC=$HOST_USER'@'$SRC

TODAYS_DATA=$(echo ${SRC_DIR}/backup/$(date +%F))

# Parameters
MD5_HOST=""
LOCK=${SRC_DIR}/Lock

init() {
  check --enc ${LOCK} "init" "lookup LOCK" "rm ${LOCK}"
}

ldap_retrieve () {
  ldapsearch \
      -p 10389 \
      -h localhost \
      -x \
      -b ou=openthinclient,dc=openthinclient,dc=org \
      -D uid=admin,ou=system \
      -w0pen%TC \
      -o ldif-wrap=200 '(&(objectClass=organizationalUnit)(!(description=openthinclient.org Console)))' | tee ${TODAYS_DATA}.ldif >/dev/null

  check -f $? "ldap_retrieve" "ldapsearch"
}

ldap_send () {
    if [[ -s ${TODAYS_DATA}.ldif ]]; then
        md5sum ${TODAYS_DATA}.ldif | awk '{print $1}' > ${TODAYS_DATA}.md5
        check -f $? "ldap_send" "md5sum"
        tar -cf - ${TODAYS_DATA}{.md5,.ldif} 2>/dev/null | ssh ${SSH_TARGET} "cat > ${TODAYS_DATA}\.\t\a\r\.\g\z"
        check -f $? "ldap_send" "tar"
        echo -e "${TODAYS_DATA}" | ssh ${SSH_TARGET} "cat >> ${TARGET_DIR}/transactions.txt" >/dev/null
        check -f $? "ldap_send" "send"
    else
        myLogger "1" "ldap_send" "lookup ldif"
    fi;
}

check_remote () {
    ssh -q $SSH_TARGET [[ -f "${TODAYS_DATA}\.\t\a\r\.\g\z" ]]  
    check -f $? "check_remote" "lookup archive"  
    ssh ${SSH_TARGET} "bash ${TARGET_DIR}/push.sh --ostart"    
    check -f $? "check_remote" "service start"
    
}

sync_sfs() {
  ssh ${SSH_TARGET} "bash ${TARGET_DIR}/push.sh --ostop"  
  check -f $? "sync_sfs" "service start"
  rsync -av --rsh="ssh" /opt/openthinclient/server/default/data/nfs/root/{tftp,sfs,schema} ${SSH_TARGET}:/opt/openthinclient/server/default/data/nfs/root/ >/dev/null
  check -f $? "sync_sfs" "tftp,sfs,schema"
}

ldap_push () {
   ssh ${SSH_TARGET} "bash ${TARGET_DIR}/push.sh -p"  
   check -f $? "ldap_push" "invoke push"
   while [ -e ${LOCK} ]
   do
     myLogger "3" "ldap_push" "locked"
   done
     myLogger "3" "ldap_push" "unlocked" 
} 

while [[ $# > 1 ]]
do
   key="$1"
   case $key in 
       -h|--help)
           echo -e "synopsis: sync.sh file [option]"  
           echo -e "\t-d or --daily \t\t stores a daily ldap dump from master, syncs ldap and system folders with slave"
           shift
       ;;
       -d|--daily)
           init
           test_con $TARGET
           ldap_retrieve
           ldap_send
           ldap_push
           sync_sfs
           check_remote
           shift
       ;;
       *)
       echo "parameter not known. -h | --help for manual"
       ;;
   esac

