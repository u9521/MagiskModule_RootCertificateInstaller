MODDIR=${0%/*}

exec > ${MODDIR}/certInstaller.log
exec 2>&1

set -x


set_context() {
    [ "$(getenforce)" = "Enforcing" ] || return 0

    default_selinux_context=u:object_r:system_security_cacerts_file:s0
    chcon -R $default_selinux_context $1

}

# Android hashes the subject to get the filename, field order is significant.
# (`openssl x509 -in ... -noout -hash`)
# AdGuard's certificate is "/C=EN/O=AdGuard/CN=AdGuard Personal CA".
# The filename is then <hash>.<n> where <n> is an integer to disambiguate
# different certs with the same hash (e.g. when the same cert is installed repeatedly).
# 
# Due to https://github.com/AdguardTeam/AdguardForAndroid/issues/2108
# 1. Retrieve the most recent certificate with our hash from the user store.
#    It is assumed that the last installed AdGuard's cert is the correct one.
# 2. Copy the AdGuard certificate to the system store under the name "<hash>.0". 
#    Note that some apps may ignore other certs.
# 3. Remove all certs with our hash from the `cacerts-removed` directory.
#    They get there if a certificate is "disabled" in the security settings.
#    Apps will reject certs that are in the `cacerts-removed`.

if ! [ "$(ls ${MODDIR}/system/etc/security/cacerts)" ]; then
    exit 0
fi


chown -R 0:0 ${MODDIR}/system/etc/security/cacerts
set_context ${MODDIR}/system/etc/security/cacerts

# Android 14 support
# Since Magisk ignore /apex for module file injections, use non-Magisk way
if [ -d /apex/com.android.conscrypt/cacerts ]; then
    # Clone directory into tmpfs
    rm -f /data/local/tmp/adg-ca-copy
    mkdir -p /data/local/tmp/adg-ca-copy
    mount -t tmpfs tmpfs /data/local/tmp/adg-ca-copy
    cp -f /apex/com.android.conscrypt/cacerts/* /data/local/tmp/adg-ca-copy/

    # Do the same as in Magisk module
    cp -fv ${MODDIR}/system/etc/security/cacerts/* /data/local/tmp/adg-ca-copy
    chown -R 0:0 /data/local/tmp/adg-ca-copy
    set_context /data/local/tmp/adg-ca-copy

    # Mount directory inside APEX if it is valid, and remove temporary one.
    CERTS_NUM="$(ls -1 /data/local/tmp/adg-ca-copy | wc -l)"
    if [ "$CERTS_NUM" -gt 10 ]; then
        mount --bind /data/local/tmp/adg-ca-copy /apex/com.android.conscrypt/cacerts
        mountTimes=1
        for pid in 1 $(pgrep zygote) $(pgrep zygote64); do
        mountTimes=$(expr $mountTimes + 1)
            nsenter --mount=/proc/${pid}/ns/mnt -- \
                /bin/mount --bind /data/local/tmp/adg-ca-copy /apex/com.android.conscrypt/cacerts
        done
    else
        echo "Cancelling replacing CA storage due to safety"
    fi
    while [ "$mountTimes" -gt 0 ]; do
        umount /data/local/tmp/adg-ca-copy
        mountTimes=$(expr $mountTimes - 1)
    done
    rmdir /data/local/tmp/adg-ca-copy
fi