# TUN 模块补齐

2026-09-28 检查：原 52-highspeed/full.config 中 `CONFIG_PACKAGE_kmod-tun` 未选中。运行中内核没有导出 /proc/config.gz。旧备份模块尝试正常加载，被内核以 struct module 大小不匹配拒绝，不能复用。

本次改动：seed.config 加入 `CONFIG_PACKAGE_kmod-tun=y`；build.sh 对旧构建目录也会显式启用 TUN，并导出固件、kmods/*.ipk、kernel.config、kernel-abi.txt。不包含其他 OpenClash 功能所需模块，不自动刷机。

## 上传并重新构建

在构建仓库目录执行以下命令，仅提交本次构建相关文件：

```bash
git add seed.config build.sh .gitignore docs/TUN模块构建与安装.md
git diff --cached
git commit -m "Include TUN and export kernel module packages"
git push origin main
```

然后在 Actions 运行现有工作流，保持与你当前固件相同的 52/highspeed 选项及风险确认。全新云主机仍要构建工具链，耗时参考上一次运行；没有承诺只编译一个模块就能在几分钟内完成。

## 能否直接安装

下载完成后，先比较新产物 kernel-abi.txt 与**当前启动固件**的内核 ABI。路由器使用旧 extroot，不能仅用 `opkg status kernel` 判断，因为它显示的是旧数据库。检查当前只读固件：

```bash
ssh r3f 'sed -n "/^Package: kernel$/,+4p" /rom/usr/lib/opkg/status'
```

本次检查时实际固件 ABI 为 `b4d8516f5e161bdca9a28de6f30e4191`；旧 overlay 数据库为 `2ccac7a75355327cb6dfb4df1ecb575e`。

新增模块也可能改变 OpenWrt 构建的内核 ABI 标识。**只有核对包的 Depends、实际固件 ABI 和软件包数据库一致性后，才可普通 opkg 安装。** 不能盲目修改包依赖、替换 ABI 文件、使用 --force-depends 或强制加载旧模块。

如果 ABI 不匹配，使用这次包含 TUN 的新固件升级；不要直接把新包装到旧固件。升级前保全数据并参考 overlay 修复记录；首次启动恢复配置后可能需要再重启才切回 extroot。安装/刷写是后续步骤，本次脚本不会执行。

## 验收

```sh
modprobe tun
ls -l /dev/net/tun
lsmod | grep '^tun'
dmesg | tail -20
```

TUN 节点和模块正常后，再检查 OpenClash 的 TUN 模式。不要把模块加载成功等同于代理、DNS 和路由规则已全部正常。
