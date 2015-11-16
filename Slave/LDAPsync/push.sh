#!/bin/bash

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

DIR:="/opt/LDAPsync/"
TRANSACTIONS=${DIR}"/transactions.txt"
#MASTER="10.224.129.216"
#SLAVE="10.224.129.66"
MASTER_HOST="root"
SLAVE:=10.224.129.216
MASTER:=10.224.129.66
TODAYS_ARCHIVE=$(tail -n1 ${TRANSACTIONS})
MD5_SLAVE=""
key="$1"

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
     [ $2 -ne 0 ] && myLogger "1" "$3" "$4" \
     || myLogger "4" "$3" "$4" 
     shift
   ;;
   -e)
     [ ! -e $2 ] && myLogger "1" "$3" "$4" \
     || myLogger "4" "$3" "$4"
     shift
     ;;
   *)
     printf "not implementet yet\n"
     ;;
   esac
}


unpack () {
    # archive does not exist
    check -e "${TODAYS_ARCHIVE}.tar.gz" "unpack" "lookup archive"  
    tar xf ${TODAYS_ARCHIVE}.tar.gz -C /
    check -f $? "unpack" "tar"
}

md5check () {
    eval "TODAYS_ARCHIVE=$(tail -n1 ${TRANSACTIONS})" 
    # test if all files were transmitted by master
    check -e "${TODAYS_ARCHIVE}.tar.gz" "md5check" "lookup archive" 
    check -e "${TODAYS_ARCHIVE}.md5" "md5check" "lookup checksum" 
    check -e "${TODAYS_ARCHIVE}.ldif" "md5check" "lookup ldif"
   
    eval "SLAVE_SUM=$(md5sum ${TODAYS_ARCHIVE}.ldif | awk '{print $1}')"
    eval "MASTER_SUM=$(cat ${TODAYS_ARCHIVE}.md5 | awk '{print $1}')"
 
    # unexpected difference between master and slave. Aborting...
    [[ ! -z $(diff <(echo ${MASTER_SUM}) <(echo ${SLAVE_SUM})) ]] && myLogger "1" "md5sum" "comparison"
    myLogger "4" "md5check" "comparison"
}
delete () {
    eval "TODAYS_ARCHIVE=$(tail -n1 ${TRANSACTIONS})" 
    check -e "${TODAYS_ARCHIVE}.ldif"  "delete" "lookup ldif"
    ldapdelete -D 'uid=admin,ou=system' -w0pen%TC -h localhost -p 10389 -f ${DIR}/del.ldif -r -c 
    check -f $? "delete" "ldapdelete"
}

push () {
    eval "TODAYS_ARCHIVE=$(tail -n1 ${TRANSACTIONS})" 
    check -e "${TODAYS_ARCHIVE}.ldif" "push" "lookup ldif"
    ldapadd -f ${TODAYS_ARCHIVE}.ldif -S /root/LDAPsync/logs/$(date +%F_%R).log -x -h localhost -p 10389 -D uid=admin,ou=system -w0pen%TC >/dev/null
    check -f $? "push" "ldapadd"
}

otc_stop () {
     if [[ ! $(/opt/openthinclient/bin/start.sh status) =~ .*"not running".* ]]; then
         /opt/openthinclient/bin/start.sh stop >/dev/null
         sleep 10
         check -f $? "otc_stop" "stopping service" 
     else
         myLogger "3" "otc_stop" "not running"
     fi;
     
}

otc_start () {
     if [[  $(/opt/openthinclient/bin/start.sh status) =~ .*"not running".* ]]; then
       /opt/openthinclient/bin/start.sh start >/dev/null
       sleep 10
       check -f $? "otc_start" "starting service"
     else 
       myLogger "3" "otc_start" "not running"
     fi;
}    

unlock () {
     ssh ${MASTER_HOST}@${MASTER} "rm ${DIR}/Lock"
     ssh ${MASTER_HOST}@${MASTER} "[[ -e ${DIR}/Lock ]] && failed \"unlocking\""      
    
}

lock () {
    ssh ${MASTER_HOST}@${MASTER} "touch ${DIR}/Lock"
    ssh ${MASTER_HOST}@${MASTER} "[[ ! -e ${DIR}/Lock ]] && echo \"Locking master failed. Aborting\" && exit 1"
}
clean () {
     rm ${TODAYS_ARCHIVE}*.ldif
     myLogger "3" "clean" "remove ldif"     
     rm ${TODAYS_ARCHIVE}*.md5
     myLogger "3" "clean" "remove md5"
} 
ldap_restore () {
    ldapadd -f $1 -S /root/LDAPsync/logs/$(date +%F_%R).log -x -h localhost -p 10389 -D uid=admin,ou=system -w0pen%TC >/dev/null
    check -f $? "push" "ldapadd"
} 

case $key in 
    -h|--help)
        echo -e "synopsis: push.sh File [option]"  
        shift
    ;;
    --ostart)
        otc_start
        shift
    ;;
    --ostop)
        otc_stop
        shift
    ;;
    -u)
        unlock
        shift
    ;;
    -l)
        lock
        shift
    ;;
   -p)
        lock
        unpack
        md5check
        otc_start
        delete
        push
        clean
        otc_stop
        unlock
        shift
    ;;
    -d)
        delete
    ;;
    -r)
        ldap_restore $2
        shift
    ;;
    *)
        echo -e "try push.sh -h for help!"
    ;; 

esac

