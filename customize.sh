
if [ "$BOOTMODE" ] && [ "$KSU" ]; then
  ui_print "- Installing from KernelSU app"
  ui_print "- KernelSU version: $KSU_KERNEL_VER_CODE (kernel) + $KSU_VER_CODE (ksud)"
  if [ "$(which magisk)" ]; then
    ui_print "*********************************************************"
    ui_print "! Multiple root implementation is NOT supported!"
    ui_print "! Please uninstall Magisk before installing Zygisk Next"
    abort    "*********************************************************"
  fi
elif [ "$BOOTMODE" ] && [ "$APATCH" = "true" ]; then
  ui_print "- Installing from Apatch app"
  APATCH_VER=$(cat "/data/adb/ap/version")
  ui_print "- APatch version: $APATCH_VER"
  ui_print "- KERNEL_VERSION: $KERNEL_VERSION"
  ui_print "- KERNELPATCH_VERSION: $KERNELPATCH_VERSION"
  if [ "$(which magisk)" ]; then
    ui_print "*********************************************************"
    ui_print "! Multiple root implementation is NOT supported!"
    ui_print "! Please uninstall Magisk before installing Zygisk Next"
    abort    "*********************************************************"
  fi
elif [ "$BOOTMODE" ] && [ "$MAGISK_VER_CODE" ]; then
  ui_print "- Installing from Magisk app"
else
  ui_print "*********************************************************"
  ui_print "! Install from recovery is not supported"
  ui_print "! Please install from KernelSU or Magisk app"
  abort    "*********************************************************"
fi

print_sepline() {
  local len bar
  len=50
  bar=$(printf "%${len}s" | tr ' ' '*')
  ui_print "$bar"
}

install_certificate(){
    local ModuleCertPath="${TMPDIR}/certificates/${1}"
    local suffix=${2}
    local ModuleCertSubHash=$(${OPENSSL} x509 -in "$ModuleCertPath" -noout -subject_hash_old)
    local ModuleCertFingerprint=$(${OPENSSL} x509 -in "$ModuleCertPath" -noout -fingerprint -sha256)
    if [ -z ${ModuleCertSubHash} ];then
    ui_print "无效的证书： ${1}，请检查证书是否为x509格式"
    return
    fi
    ui_print "正在安装 ${1}(${ModuleCertSubHash}.${suffix})"

    if [ -f "${SYSTEMCERT_DIR}/${ModuleCertSubHash}.${suffix}" ];then
      print_sepline
      ui_print "发现冲突证书: ${1} -> ${SYSTEMCERT_DIR}/${ModuleCertSubHash}.${suffix}"
      ui_print "建议不要和其他证书模块混合使用"
      SystemCertFingerprint=$(${OPENSSL} x509 -in "${SYSTEMCERT_DIR}/${ModuleCertSubHash}.${suffix}" -noout -fingerprint -sha256)
      if [ "${ModuleCertFingerprint}" == "${SystemCertFingerprint}" ];then
        ui_print "证书内容完全相同 (解决方式 : 跳过 ${1})"
        return
      else
        ui_print "证书指纹不同 (解决方式 : 增加索引号)"
        install_certificate ${1} $(expr ${suffix} + 1)
        return
      fi
    fi

    if [ -f "${MODULECERT_DIR}/${ModuleCertSubHash}.${suffix}" ];then
      print_sepline
      ui_print "发现模块内冲突证书: ${1} -> ${MODULECERT_DIR}/${ModuleCertSubHash}.${suffix}"
      ModuleCertFingerprintOrg=$(${OPENSSL} x509 -in "${MODULECERT_DIR}/${ModuleCertSubHash}.${suffix}" -noout -fingerprint -sha256)
      if [ "${ModuleCertFingerprint}" == "${ModuleCertFingerprintOrg}" ];then
        ui_print "证书内容完全相同 (解决方式 : 跳过 ${1})"
        return
      else
        ui_print "证书指纹不同 (解决方式 : 增加索引号)"
        install_certificate ${1} $(expr ${suffix} + 1)
        return
      fi
    fi

    ${OPENSSL} x509 -in "$ModuleCertPath" -outform PEM > "${MODULECERT_DIR}/${ModuleCertSubHash}.${suffix}"
    if [ ${API} -ge 30 ];then
        ${OPENSSL} x509 -in "$ModuleCertPath" -noout -text >> "${MODULECERT_DIR}/${ModuleCertSubHash}.${suffix}"
        ${OPENSSL} x509 -in "$ModuleCertPath" -sha1 -noout -fingerprint >> "${MODULECERT_DIR}/${ModuleCertSubHash}.${suffix}"
    fi
}

SKIPUNZIP=1


unzip -j -o -q "${ZIPFILE}" "module.prop" -d "${MODPATH}"

# 打印信息到控制台
MODDESC=`grep_prop description $TMPDIR/module.prop`
MODDVER=`grep_prop version $TMPDIR/module.prop`
MODDVERCODE=`grep_prop versionCode $TMPDIR/module.prop`
ui_print "- 开始安装 $MODNAME"
ui_print "- 模块路径: $MODPATH"
ui_print "- 模块版本: $MODDVER"
ui_print "- 模块版本号: $MODDVERCODE"
ui_print "- 设备架构: $ARCH"
ui_print "- Android API 版本: $API"

ui_print "- 正在解压证书到临时文件夹"
unzip -j -o "${ZIPFILE}" "certificates/*" -x "certificates/.gitkeep" -d "${TMPDIR}/certificates"

ui_print "- 正在解压 openssl"

# 检查设备架构
case "$ARCH" in
    "arm")
        unzip -j -o -q "${ZIPFILE}" "openssl/openssl-arm" -d "${TMPDIR}"
        mv "${TMPDIR}/openssl-arm" "${TMPDIR}/openssl"
        ;;
    "arm64")
        unzip -j -o -q "${ZIPFILE}" "openssl/openssl-arm64" -d "${TMPDIR}"
        mv "${TMPDIR}/openssl-arm64" "${TMPDIR}/openssl"
        ;;
    "x86")
        unzip -j -o -q "${ZIPFILE}" "openssl/openssl-x86" -d "${TMPDIR}"
        mv "${TMPDIR}/openssl-x86" "${TMPDIR}/openssl"
        ;;
    "x64")
        unzip -j -o -q "${ZIPFILE}" "openssl/openssl-x64" -d "${TMPDIR}"
        mv "${TMPDIR}/openssl-x64" "${TMPDIR}/openssl"
        ;;
    *)
        abort "不支持的设备架构: $ARCH"
        ;;
esac

set_perm "${TMPDIR}/openssl" 0 0 0755
OPENSSL="${TMPDIR}/openssl"

# Android 14 挂载证书
if [ ${API} -ge 34 ];then
    unzip -j -o -q "${ZIPFILE}" "post-fs-data.sh" -d "${MODPATH}"
    touch "${MODPATH}/skip_mount"
    SYSTEMCERT_DIR="/apex/com.android.conscrypt/cacerts"
else
    SYSTEMCERT_DIR="/system/etc/security/cacerts"
fi
# 检查证书
if [ "$(ls ${TMPDIR}/certificates/)" ];then
    ui_print "开始安装证书"
else
    ui_print "请把需要安装到系统的证书放到模块中的certificates目录中再刷入"
    abort "没有要安装的证书"
fi


mkdir -p "${MODPATH}/system/etc/security/cacerts"
MODULECERT_DIR="${MODPATH}/system/etc/security/cacerts"

for FILE in $(ls ${TMPDIR}/certificates/);do
  [ -f "${TMPDIR}/certificates/${FILE}" ] || continue
  ui_print "开始安装 ${FILE}"
  install_certificate ${FILE} 0
  print_sepline
done

# post install

print_sepline
ui_print "$MODDESC"
print_sepline

# 设置文件权限
set_perm_recursive "$MODPATH" 0 0 0755 0644
set_perm_recursive "$MODULECERT_DIR" 0 0 0755 0644 u:object_r:system_security_cacerts_file:s0

ui_print "- 安装完成"
