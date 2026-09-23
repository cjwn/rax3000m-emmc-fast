# RAX3000M eMMC：自己构建 ImmortalWrt 24.10.2

适用：你当前这台 CMCC RAX3000M、64GB eMMC、ImmortalWrt 24.10.2。不是 RAX3000Me、XR30 或 NAND 版的通用刷机包。

本套件只构建，不连接、不重启、不刷写路由器。推荐先做 **26 MHz + high-speed**。52 MHz 是单独的实验选项，不承诺速度提升或稳定性。

## 1. 我们究竟改了什么

原版 `target/linux/mediatek/dts/mt7981b-cmcc-rax3000m-emmc.dtso` 的 `fragment@3` 指向 `&mmc0`。保持 8 位总线，只增加 `cap-mmc-highspeed;`，频率上限选择 26000000 或 52000000。

```dts
bus-width = <8>;
cap-mmc-highspeed;
max-frequency = <26000000>;
```

`high-speed` 是时序能力，不是 HS200，也不意味着在 26 MHz 下自动翻倍。频率上限不一定等于实际时钟，以启动后的 `ios` 为准。原装 RAX3000M 有 52 MHz 下读写错误和启动失败的报告。

这是内核设备树改动，所以需要源码构建；仅使用 ImageBuilder/在线固件选择器添加软件包，不能完成这项改动。无需为此修改 U-Boot 或重新分区。

源码固定为官方 v24.10.2，commit `cee53da5b58c6241eced0ef17956adda5515634b`；其 feeds.conf.default 已锁定四个软件源的提交。版本固定便于对照你当前系统，不表示 24.10.2 是最新版本。

## 2. 文件说明

| 文件 | 用途 |
| --- | --- |
| `build.sh` | 下载源码、应用补丁、准备配置、下载依赖、编译、导出固件 |
| `patch-emmc.py` | 精确修改 eMMC overlay；重复运行不会重复插入属性 |
| `seed.config` | RAX3000M、LuCI 中文、ksmbd 文件共享等基础配置 |
| `.github/workflows/build.yml` | 在 GitHub 的临时 Ubuntu 主机上构建 |

这是一份基础配置，**不是你当前系统的完整克隆**。没有打包 OpenClash、订阅、密码、SSH 私钥或你现有的自定义服务。保留配置升级也不会自动保留所有额外安装的软件包。先把需要的软件补齐，再决定是否刷入。

## 3. 方式 A：Mac 上最省事——GitHub Actions 在线构建

不需要在 Mac 上装编译工具链，也不会上传路由器里的文件。

1. 在 GitHub 创建一个空仓库，可设为私有。私有仓库 Actions 可能消耗免费额度，超出后的费用取决于账户设置。
2. 在 Mac 终端进入本套件目录，把套件内容作为仓库根目录提交；尤其要包含隐藏目录 `.github`。下面假设套件位于 `~/rax3000m-build`，实际请替换为你的解压目录。只提交本目录，不要提交上一级目录里的个人文档。

```bash
cd ~/rax3000m-build
git init
git add README.md build.sh patch-emmc.py seed.config .gitignore .github
git commit -m "Add RAX3000M eMMC firmware build kit"
git branch -M main
# 把下面地址换成你刚创建的空仓库地址：
git remote add origin https://github.com/YOUR_NAME/YOUR_REPO.git
git push -u origin main
```

3. 打开仓库 → **Actions** → **Build RAX3000M eMMC** → **Run workflow**。
4. 第一次选择 `frequency: 26`、`mode: highspeed`，风险复选框不勾选。
5. 等待构建结束，在该次运行页面下方 **Artifacts** 下载压缩包。
6. 解压后检查 `build-info.txt`、`emmc.patch`、`SHA256SUMS` 和 `*.itb`。

想做未启用 high-speed 的基线：26 + legacy。想实验 52 MHz：52 + highspeed，并显式勾选风险复选框。工作流脚本会拒绝未勾选的 52 MHz 构建。

首次源码构建可能需要数小时。工作流限时 6 小时；GitHub 主机的磁盘和额度也可能造成失败。工作流只在一次性云主机上清理预装 Android/.NET/GHC 工具以腾出空间，不操作你的 Mac。

## 4. 方式 B：Ubuntu 自己构建

推荐 Ubuntu 22.04/24.04 x86_64，普通用户，8GB 以上内存、约 60–100GB 空闲磁盘；这些是实用预留量，不是保证的最低要求。Mac 用户可用 Ubuntu 虚拟机；本脚本不在 macOS 原生运行。Apple Silicon 上 ARM Ubuntu 的依赖和主机构建兼容性可能不同，新手优先使用方式 A。

**源码放在 Linux 虚拟磁盘内**，不要放到 Mac 共享目录：构建要求区分大小写的文件系统，路径不要带空格。不要使用 root 编译。

安装依赖（仅以下安装命令用 sudo）：

```bash
sudo apt-get update
sudo apt-get install -y build-essential clang flex bison g++ gawk \
  gcc-multilib g++-multilib gettext git libncurses-dev libssl-dev \
  python3 python3-setuptools python3-pyelftools rsync swig unzip \
  zlib1g-dev file wget curl ca-certificates time perl patch diffutils \
  bzip2 xz-utils zstd libelf-dev
```

将整个套件复制到例如 `~/rax3000m-build`，然后：

```bash
cd ~/rax3000m-build
bash build.sh --frequency 26 --mode highspeed --jobs 2
```

脚本会在 `work/24.10.2-26-highspeed/` 内构建。默认两线程降低内存压力；资源充足可以选择 `--jobs 4`。不要同时对同一个目录启动两次构建。

如果要先选额外软件：

```bash
bash build.sh --frequency 26 --mode highspeed --stage prepare
cd work/24.10.2-26-highspeed
make menuconfig
# 保存并退出；不要更改目标机型
cd ../..
bash build.sh --frequency 26 --mode highspeed --jobs 2
```

已有 `.config` 会保留，`seed.config` 只在首次准备时复制。准备后修改 seed.config 不会自动覆盖现有配置，后续请用 menuconfig。脚本检查 RAX3000M、LuCI 与 ksmbd 是否选中。

其他变体分别使用独立目录，避免增量编译混用：

```bash
# 原版 legacy 基线
bash build.sh --frequency 26 --mode legacy --jobs 2

# 仅实验使用
bash build.sh --frequency 52 --mode highspeed --accept-52mhz-risk --jobs 2
```

下载中断后，用相同参数重跑即可。编译失败不会自动掩盖错误；可以改为 `--jobs 1` 重跑，查看 output 里的 build.log。磁盘不足则扩容；不要因为报错就强制刷入残留文件。

## 5. 构建输出与验证

默认输出目录：`output/26-highspeed/`。

- `immortalwrt-...-cmcc_rax3000m-squashfs-sysupgrade.itb`：本机型升级镜像。
- `SHA256SUMS`：镜像校验值。
- `emmc.patch`：确认只修改目标 overlay 的 high-speed/频率属性。
- `build-info.txt`、`feeds.lock`：源码与软件源版本记录。
- `full.config`、`diffconfig`：完整与精简构建配置。
- `download.log`、`build.log`：定位失败原因。

在 Mac 解压后的输出目录校验：

```bash
shasum -a 256 -c SHA256SUMS
```

校验通过只说明文件一致，不代表设备兼容或运行稳定。

## 6. 刷入之前——你这台有一个特别要注意的地方

之前实测，你的 `/share` 位于根文件系统 overlay，底层是 `mmcblk0p7`，并非独立 USB 数据盘。**不能把“保留配置”理解成保留 `/share` 所有文件。** 配置备份也不是整盘备份。

先把 `/Volumes/wifismb` 的业务文件复制到电脑或另一个磁盘，核实文件大小/校验值；保存路由器配置、当前软件包列表、原版固件，并确认现有 U-Boot 恢复方法。不要照搬别人的分区表、preloader 或 U-Boot 刷写命令。本套件故意只导出 sysupgrade 镜像。

不要直接通过 SMB 把升级镜像放到 `/share` 后随意刷写。真正升级时，先核对机型与镜像，评估当前分区布局和保留数据方式；上传 `/tmp` 后可先执行 `sysupgrade -T /tmp/实际镜像名.itb` 做兼容性检查。`-T` 只测试，不刷写；通过也不保证数据保留，失败不可用 `-F` 强刷。

本说明不自动执行升级。构建结束可以先检查产物，再决定刷入。

## 7. 启动后的检查和 A/B 对比

将 `ROUTER_SSH_ALIAS` 替换为你自己的 SSH 别名或 `root@路由器地址`。

```bash
ssh ROUTER_SSH_ALIAS 'cat /sys/kernel/debug/mmc0/ios'
ssh ROUTER_SSH_ALIAS 'dmesg | grep -iE "mmc|I/O error|timeout|CRC"'
```

high-speed 成功协商后应看到 `timing spec: 1 (mmc high-speed)`；同时核对 `actual clock`。52 MHz 上限不代表实际恰好 52 MHz。

用同一台 Mac、同一 Wi-Fi 位置和同一大文件，对比本机磁盘读取、SMB 读取、SMB 写入并等待落盘；不要只看短时间的缓存峰值。写入后校验文件内容，运行一段时间并检查日志，单次没有报错不代表长期稳定。出现 MMC/I/O 错误就停止性能测试，恢复已验证固件。

原始对照数据：SMB 读约 8.9–9.7 MB/s，含落盘写约 11.4 MB/s；路由器本机读约 12.3、写约 11.9 MB/s。不要把不同固件、缓存条件下的结果直接归因于 high-speed。

## 8. 依据与验证范围

- [ImmortalWrt v24.10.2 源码](https://github.com/immortalwrt/immortalwrt/tree/v24.10.2)
- [本机型 eMMC overlay](https://github.com/immortalwrt/immortalwrt/blob/v24.10.2/target/linux/mediatek/dts/mt7981b-cmcc-rax3000m-emmc.dtso)
- [Linux MMC 属性定义](https://github.com/torvalds/linux/blob/v6.6/Documentation/devicetree/bindings/mmc/mmc-controller.yaml)
- [OpenWrt 构建流程](https://openwrt.org/docs/guide-developer/toolchain/use-buildsystem)
- [RAX3000M 适配作者的频率与稳定性说明](https://github.com/lgs2007m/Actions-OpenWrt/blob/main/Tutorial/RAX3000M-eMMC_XR30-eMMC.md)

本套件交付时检查了 Bash 语法和真实官方 overlay 的补丁行为，包括重复执行、26/52 MHz、legacy 还原与错误输入；未执行完整工具链/固件编译，也未在路由器上刷机验证。首次云构建仍可能遇到上游下载或环境问题。
