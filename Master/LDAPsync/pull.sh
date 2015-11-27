#!/bin/bash
# Master
# Variable definitions
MASTER=os-master
SLAVE=os-slave

MASTER_USER="root"
SLAVE_USER="root"

# Location of storage definition
MASTER_DIR="/opt/Master/LDAPsync"
MASTER_OTC_DIR="/opt/openthinclient/server/default/data/nfs/root/"
MASTER_OTC_META=$(echo ${MASTER_OTC_DIR}{tftp/,sfs/,schema/})

# Location of Slaves sync Folder
SLAVE_DIR="/opt/Slave/LDAPsync"

# SSH configurations
SSH_SLAVE=$SLAVE_USER'@'$SLAVE
SSH_MASTER=$MASTER_USER'@'MASTER$
TODAYS_DATE=$(echo $(date +%F))
TODAYS_DATA=$(echo ${MASTER_DIR}/backup/$(date +%F))
SLAVE_TODAYS_DATA=$(echo ${SLAVE_DIR}/backup/$(date +%F))

# Parameters
key="$1"
MD5_HOST=""
LOCK=${MASTER_DIR}/Lock

# Regular Colors
Black='\033[0;30m'        # Black
Red='\033[0;31m'          # Red
Green='\033[0;32m'        # Green
Yellow='\033[0;33m'       # Yellow
Blue='\033[0;34m'         # Blue
Purple='\033[0;35m'       # Purple
Cyan='\033[0;36m'         # Cyan
White='\033[0;37m'        # White
NC='\033[0m'

myLogger () {
local head='%-10s%-30s%-30s'
    case $1 in
    1)
        head="${head}${Red}%8s${NC}\n"
        printf $head "ERROR:" "func: $2" "expr: $3" "[failed]"
        shift
        ;;
    2)
        head="${head}${Yellow}%8s${NC}\n"
        printf $head "WARNING:" "func: $2" "expr: $3" "[warn]"
        shift
        ;;
    3)
        head="${head}${Yellow}%8s${NC}\n"
        printf $head "INFO:" "func: $2" "expr: $3" "[debug]"
        shift
        ;;
    4)
        head="${head}${Green}%8s${NC}\n"
        printf $head "OK:" "func: $2" "expr: $3" "[OK]"
        shift
        ;;
    *)
        printf "log level not defined"
    ;;
    esac
}

check () {
   case $1 in
   -f)
     [ $2 -ne 0 ] && myLogger "1" "$3" "$4"
     myLogger "4" "$3" "$4"
     shift
     ;;
   -e)
     [ ! -e $2 ] && myLogger "1" "$3" "$4" \
     || myLogger "4" "$3" "$4"
     shift
     ;;  
   --enc)
     [ ! -e $2 ] && myLogger "2" "$3" "$4" \
     || myLogger "4" "$3" "$4"
     shift
     ;;
   *)     
     printf "not implementet yet\n"
     ;; 
   esac
} 

test_con () {
  for run in {1 .. 5} 
  do
    if ping -q -c 1 -W 1 $SLAVE >/dev/null; then
      myLogger "4" "test_con" "connection"
      break
    else
      myLogger "2" "test_con" "try $run"
    fi;
      myLogger "1" "test_con" "connection"
      exit 1
  done
}

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
      -o ldif-wrap=200 '(&(objectClass=organizationalUnit)(!(description=openthinclient.org Console)))' | tee ${TODAYS_DATA}.ldif #>/dev/null

  check -f $? "ldap_retrieve" "ldapsearch"
}

ldap_send () {
    if [[ -s ${TODAYS_DATA}.ldif ]]; then
        md5sum ${TODAYS_DATA}.ldif | awk '{print $1}' > ${TODAYS_DATA}.md5
        check -f $? "ldap_send" "md5sum"
        tar -zcvf ${TODAYS_DATA}.tar.gz --directory=${MASTER_DIR}/backup $(echo ${TODAYS_DATE}){.md5,.ldif} 
 # 2>/dev/null #| ssh ${SSH_SLAVE} "cat > ${SLAVE_TODAYS_DATA}\.\t\a\r\.\g\z"
        rsync -av --rsh="ssh" ${TODAYS_DATA}.tar.gz ${SSH_SLAVE}:${SLAVE_TODAYS_DATA}.tar.gz #>/dev/null
        
        check -f $? "ldap_send" "tar"
        echo -e "${SLAVE_TODAYS_DATA}" | ssh ${SSH_SLAVE} "cat >> ${SLAVE_DIR}/transactions.txt" >/dev/null
        check -f $? "ldap_send" "send"
    else
        myLogger "1" "ldap_send" "lookup ldif"
    fi;
}

check_remote () {
    ssh -q $SSH_SLAVE [[ -f "${SLAVE_TODAYS_DATA}\.\t\a\r\.\g\z" ]]  
    check -f $? "check_remote" "lookup archive"  
    ssh ${SSH_SLAVE} "bash ${SLAVE_DIR}/push.sh --ostart"    
    check -f $? "check_remote" "service start"
    
}

sync_sfs() {
  ssh ${SSH_SLAVE} "bash ${SLAVE_DIR}/push.sh --ostop"  
  check -f $? "sync_sfs" "service start"
  rsync -av --rsh="ssh" /opt/openthinclient/server/default/data/nfs/root/{tftp,sfs,schema} ${SSH_SLAVE}:/opt/openthinclient/server/default/data/nfs/root/ >/dev/null
  check -f $? "sync_sfs" "tftp,sfs,schema"
}

ldap_push () {
   ssh ${SSH_SLAVE} "bash ${SLAVE_DIR}/push.sh -p"  
   check -f $? "ldap_push" "invoke push"
   while [ -e ${LOCK} ]
   do
     myLogger "3" "ldap_push" "locked"
   done
     myLogger "3" "ldap_push" "unlocked" 
} 

clean() {
   rm ${MASTER_DIR}/backup/*{.ldif,.md5}
}

case $key in 
    -h|--help)
        echo -e "synopsis: sync.sh File [option]"  
        echo -e "\t-d or --daily \t\t stores a daily ldap dump from Master, syncs ldap and system folders with slave"
        shift
    ;;
    -t|--test)
        init
        test_con
        ldap_retrieve
        ldap_send
        shift
    ;;
    -d|--daily)
        init
        test_con
        ldap_retrieve
        ldap_send
        ldap_push
        sync_sfs
        check_remote
        clean
        shift
    ;;
    *)
    echo "parameter not known. -h | --help for manual"
    ;;
esac

