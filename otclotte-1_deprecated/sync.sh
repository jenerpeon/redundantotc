#!/bin/bash

MASTER="172.29.36.230"
SLAVE="172.29.36.240"
BASE="/root/LDAPsync"
key="$1"

# dumps apacheds tree to ldif
ldap_retrieve () {
# filters instead of cropping the file manually for future implementation. NOT RECURSIVE BY NOW
#ldapsearch -p 10389 -h $MASTER -u -x -b ou=openthinclient,dc=openthinclient,dc=org -D uid=admin,ou=system -w0pen%TC  '(&(objectClass=organizationalUnit)(!(description=openthinclient.org Console)))' | tee /root/LDAPsync/ldap.ldif

  ldapsearch -p 10389 -h localhost -x -b ou=openthinclient,dc=openthinclient,dc=org -D uid=admin,ou=system -w0pen%TC -o ldif-wrap=200 | tee /root/LDAPsync/ldap.ldif
# Trims the output of ldap.ldif because "ou=openthinclient,dc=openthinclient,dc=org" is in the dump but not modifiable
  tail -n +16 ldap.ldif | tee ldap.ldif
}

ldap_push_slave () {
  ldapdelete -D 'uid=admin,ou=system' -w0pen%TC -h $SLAVE -p 10389  -f $BASE/del.ldif -r -c
  ldapadd -f /root/LDAPsync/ldap.ldif -S /root/LDAPsync/debug.txt -x -h $SLAVE -p 10389 -D uid=admin,ou=system -w0pen%TC
}
# Create Backup that lasts for 7days in the backup folder
ldap_backup () { 
  cp $BASE/ldap.ldif $BASE/backup/ldap_$(date +%F_%R).ldif
  find ~/LDAPsync/backup/*  -ctime +7 -exec rm {} \; 
  rsync -av --rsh="ssh" $BASE/backup/* tcos@$SLAVE:~/LDAPsync/backup/
}
recover () {
  ldapdelete -D 'uid=admin,ou=system' -w0pen%TC -h $SLAVE -p 10389  -f $BASE/del.ldif -r -c
  ldapadd -f $1 -S $BASE/debug.txt -x -h $SLAVE -p 10389 -D uid=admin,ou=system -w0pen%TC
}
sync_sfs() {
  rsync -av --rsh="ssh" /opt/openthinclient/server/default/data/nfs/root/{tftp,sfs,schema} root@$SLAVE:/opt/openthinclient/server/default/data/nfs/root/
}

case $key in 
    -h|--help)
        echo -e "-r or --recover \t takes a backupfile to recover slave"
        echo -e "-d or --daily \t stores a daily ldap dump from Master, syncs ldap and system folders with slave"
        shift
    ;;
    -r|--recover)
        recover $2
        shift
    ;;
    -d|--daily)
        ldap_retrieve
        ldap_push_slave
        sync_sfs
        ldap_backup
        shift
    ;;
    *)
    echo "parameter not known. -h | --help for manual"
    ;;
   
esac
