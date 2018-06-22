#!/bin/bash

if [[ -z $3 ]]; then
	echo "Usage: $(basename $0) <username> <group> <ldap_manager_password> [realm] [ldap_base_optional]"
	echo "Requires: KDC, LDAP up and running"
	exit 1
fi
GROUP=$1
USERNAME=$2
PW_LDAP=$3
PASSWORD=$4
REALM=${5:-TEST.LAB}
LDAP_BASE=${6:-dc=hadoop,dc=io}

function getNextUidNumber ()
{
   # Brute force
   maxUid=`ldapsearch -Y EXTERNAL -H ldapi:/// -b "ou=groups,${LDAP_BASE}" gidNumber 2> /dev/null | awk '/gidNumber: / {print $2}' | sort -n | tail -n 1`
   # minimum 2000
   echo -e "$(( ${maxUid} +1 ))\n2000" | sort -n | tail -1
}

echo "Creating ${USERNAME}@${REALM} principal in Kerberos."
echo "Creating dn: uid=${USERNAME},ou=users,${LDAP_BASE} user in LDAP."
echo "Press a key to continue."
read -n 1

# Create user in KERBEROS 
kadmin.local -q "addprinc -pw ${PASSWORD} ${USERNAME}@${REALM}"

# Create admin user in LDAP
UIDNUMBER=`getNextUidNumber`
mkdir -p /tmp/ldap
cat > /tmp/ldap/${USERNAME}.ldif << EOF
dn: uid=${USERNAME},ou=users,${LDAP_BASE}
changetype: add
objectClass: top
objectClass: account
objectClass: posixAccount
objectClass: shadowAccount
cn: ${USERNAME}
uid: ${USERNAME}
uidNumber: ${UIDNUMBER}
gidNumber: 100
homeDirectory: /home/${USERNAME}
loginShell: /bin/bash
userPassword: {SASL}${USERNAME}@${REALM}
shadowLastChange: 0
shadowMax: 0
shadowWarning: 0

dn: cn=users,ou=groups,${LDAP_BASE}
changetype: modify
add: memberUid
memberUid: ${USERNAME}
EOF
ldapadd -f /tmp/ldap/${USERNAME}.ldif -D cn=Manager,${LDAP_BASE} -w "${PW_LDAP}"

# Verify that SASL and LDAP work.
testsaslauthd -u ${USERNAME}@${REALM} -p ${PASSWORD}
ldapsearch -D "uid=${USERNAME},ou=users,${LDAP_BASE}" -b "${LDAP_BASE}" -w "${PASSWORD}"
