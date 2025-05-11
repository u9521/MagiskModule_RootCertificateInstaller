# Root Certificate Installer
# 系统根证书安装模块
安装自定义的CA证书到系统。

- 支持Android 14。
- 支持任意X509格式的CA证书。
- 支持主体(subject)冲突检测，并自动添加索引。
- Android 14 后无须挂载到系统。
# 安装方法

1. 去Release下载本模块
2. 把要装的crt证书添加到压缩包中的`certificates`文件夹，文件名没什么限制(`.gitkeep`不能用，模块在安装时会自动忽略这个文件)，证书必须是**x509**格式的**CA证书**，能在设置里面正常安装
3. 直接在`Magisk`,`KernelSU`或`Apatch`里面刷入就行了
# 更新方法

模块装好了并正常使用，但我又有新的证书要安装了，下面就是更新方法
1. 备份已经安装的证书，这里以KernelSU为例
拷贝`/data/adb/modules/RootCertificateInstaller/system/etc/security/cacerts/`目录下面的所有证书到安全的地方
2. 把要装的crt证书和备份好的证书(xxx.0)一起添加到压缩包中的`certificates`文件夹
3. 去`KernelSU`卸载本模块并重启
> 因模块在安装时无法区分证书是系统自带的还是模块装上去的，所以要先卸载干净，不然安装时模块检测到老证书冲突会自动跳过
4. 正常刷入修改后的压缩包并重启，完成安装

# 生成自定义CA证书
1. 下载并安装好OpenSSL
2. 创建私钥，这里以`RSA 4096`为例，当然椭圆曲线也是可以的，记得放好私钥。
```
openssl genrsa -out ca1.key 4096
```
3. 生成CA证书，OpenSSL生成的最大有效期到`9999-12-31`，这里以10年为例，证书一定要是x509格式的，subject记得修改，Android是以subjectHash为文件名，推荐不要使用重复的subject，硬要用的话记得修改索引
```
openssl req -x509 -new -key ca1.key -days 3650 -out ca1.crt -subj "/C=XX/ST=State/L=City/O=Test Organization/OU=Test Unit/CN=Test common Name"
```
4. 有了证书和私钥就可以配置抓包软件愉快抓包了

下面是计算当天到`9999-12-31`有多少天的Python脚本，想要超长证书的可以算好后可以直接填到OpenSSL

```
from datetime import datetime

start_date = datetime.now()
end_date = datetime(9999, 12, 31)
delta = end_date - start_date
total_days = delta.days
print(f"从 {start_date.strftime('%Y-%m-%d')} 到 {end_date.strftime('%Y-%m-%d')} 共 {total_days} 天")
```
> 不要使用testcase里面的CA证书，因为没有实际作用，我也没有私钥(除非你能算出来RSA4096)，仅用来测试模块用的
# 感谢名单
- [OpenSSL](https://github.com/openssl/openssl)
- [AdguardTeam/adguardcert](https://github.com/AdguardTeam/adguardcert/blob/master/module/post-fs-data.sh) Android 14 证书注入方案
- 酷安@fsxitutu2 感谢他的证书安装模块和预编译的OpenSSL，思路大多来自他的模块。 [原帖地址](https://www.coolapk.com/feed/53987025)
- [LIghtJUNction/RootManage-Module-Model](https://github.com/LIghtJUNction/RootManage-Module-Model) Magisk模块模板
