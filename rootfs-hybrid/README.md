# LoongArch 2K0300 Hybrid Rootfs 使用说明

## 1. 这份包的用途

它完成的任务是：

1. 以一份已经能够在龙芯 2K0300 先锋派正常启动的 `rootfs.tar.gz + uImage + ramdisk.gz` 为基础系统；
2. 从 Buildroot 的 `output-qt6/target` 中，按 `config/components.yaml` 合入 Qt6、OpenCV、NumPy、sounddevice、ONNX Runtime、sherpa-onnx、FFmpeg 和 UTF-8 locale；
3. 自动补齐缺失的动态库依赖；
4. 检查 glibc / GLIBCXX / CXXABI 兼容性；
5. 清理旧 Qt5 运行环境并检查是否仍有 Qt5 消费者；
6. 对最终 rootfs 做完整 `DT_NEEDED` 依赖闭包检查；
7. 检查 ELF 架构，并检查新增 ELF 是否包含 2K0300 不支持的 LSX/LASX 向量指令；
8. 校验基础内核、模块、libc、libstdc++ 等受保护文件没有被误改；
9. 强制检查 `C.UTF-8` 的 `locale-archive` 已合入；
10. 重新打包生成可交付的 `rootfs.tar.gz`、`uImage`、`ramdisk.gz` 和 `SHA256SUMS`。

当前配置针对你现在的工程环境：**Loongson 2K0300 / LoongArch64、Buildroot 2024.08、Python 3.12、Qt6、glibc 2.38**。

---

## 2. 包内目录

解压后应只有以下文件：

```text
rootfs-hybrid/
├── config/
│   └── components.yaml
├── scripts/
│   ├── build-hybrid-rootfs.sh
│   ├── merge-components.py
│   ├── resolve-loongarch-deps.py
│   ├── verify-rootfs-deps.py
│   └── verify-loongarch-isa.py
└── 使用说明.md
```

其中：

- `build-hybrid-rootfs.sh`：唯一需要直接操作的主脚本；
- `merge-components.py`：按照 `components.yaml` 从 `output-qt6/target` 合并组件；
- `resolve-loongarch-deps.py`：递归补齐新增 ELF 的动态库依赖；
- `verify-rootfs-deps.py`：在 Qt5 删除和清理完成后，对整个 rootfs 做依赖闭包检查；
- `verify-loongarch-isa.py`：检查 LoongArch 架构以及 LSX/LASX 指令；
- `components.yaml`：正式组件清单及合并规则。

`rootfs/`、`install/`、`reports/` 和 `fakeroot.db` **不随包提供**，会由主脚本运行时自动生成。

---

## 3. 默认路径

主脚本当前默认使用：

```text
PROJECT_ROOT=/home/buildroot/my_buildroot/workspace/buildroot-2024.08
OUTPUT_DIR=$PROJECT_ROOT/output-qt6
QT6_TARGET=$OUTPUT_DIR/target
WORKDIR=$PROJECT_ROOT/rootfs-hybrid
```

基础板卡文件默认使用：

```text
NEW_ROOTFS_TAR=/home/justin/new-board/rootfs.tar.gz
NEW_UIMAGE=/home/justin/new-board/uImage
OFFICIAL_RAMDISK=/home/justin/new-board/ramdisk.gz
```

因此最省事的放置位置是：

```text
/home/buildroot/my_buildroot/workspace/buildroot-2024.08/rootfs-hybrid
```

如果你的实际路径与上面不同，不需要修改脚本源代码，可以通过环境变量覆盖，见后文“自定义路径”。

---

## 4. 构建前必须准备好的输入

### 4.1 已经正常启动过的基础板卡系统

必须准备同一套基础系统中的：

```text
rootfs.tar.gz
uImage
ramdisk.gz
```

默认放在：

```text
/home/justin/new-board/
```

主脚本会检查：

- gzip/tar 是否有效；
- rootfs 顶层结构是否正确；
- rootfs 内 `/boot/uImage` 是否与外部 `uImage` 完全一致；
- 内核模块目录是否唯一；
- 基础 glibc / libstdc++ 等信息。

不要把来自不同板卡镜像版本的 `rootfs.tar.gz` 和 `uImage` 混用。

### 4.2 已构建完成的 Buildroot Qt6/AI target

必须存在：

```text
/home/buildroot/my_buildroot/workspace/buildroot-2024.08/output-qt6/target
```

至少应已经包含你需要合并的 Qt6、Python/AI 运行时。

特别是本次 Qt6 locale 修复要求以下文件必须存在：

```bash
ls -lh output-qt6/target/usr/lib/locale/locale-archive
```

当前正确环境应看到约 457 KiB 的：

```text
usr/lib/locale/locale-archive
```

你的 Buildroot 配置目前对应：

```text
BR2_ENABLE_LOCALE=y
BR2_GENERATE_LOCALE="C.UTF-8"
```

如果这个文件不存在，应先修复/重新完成 Buildroot 构建，而不是强行运行 Hybrid Rootfs 合并。

### 4.3 Buildroot 交叉工具

默认要求：

```text
output-qt6/host/bin/loongarch64-loongson-linux-gnu-readelf
output-qt6/host/bin/loongarch64-loongson-linux-gnu-objdump
```

如果你的 toolchain 前缀不同，可以通过 `CROSS_PREFIX`、`READELF`、`OBJDUMP` 覆盖。

### 4.4 主机工具

主脚本会检查这些命令：

```text
fakeroot
tar
gzip
file
stat
sha256sum
strings
awk
sed
grep
find
sort
cmp
xargs
diff
du
tee
head
python3
```

Python 还需要 PyYAML：

```bash
python3 -c 'import yaml; print(yaml.__version__)'
```

Ubuntu/WSL 一般可以安装：

```bash
sudo apt update
sudo apt install -y fakeroot python3-yaml file
```

如果你使用虚拟环境，也可以用：

```bash
python3 -m pip install pyyaml
```

---

## 5. 安装这份精简目录

如果当前工程里已经存在旧的 `rootfs-hybrid`，**不要直接解压覆盖**，否则旧的 `phase*.sh` 会继续残留，看起来仍然不是精简版。

推荐先完整备份：

```bash
cd /home/buildroot/my_buildroot/workspace/buildroot-2024.08
mv rootfs-hybrid rootfs-hybrid.backup-$(date +%Y%m%d-%H%M%S)
```

然后把本压缩包解压到 `PROJECT_ROOT`，最终确保：

```bash
ls /home/buildroot/my_buildroot/workspace/buildroot-2024.08/rootfs-hybrid/scripts
```

只看到：

```text
build-hybrid-rootfs.sh
merge-components.py
resolve-loongarch-deps.py
verify-rootfs-deps.py
verify-loongarch-isa.py
```

如果执行权限丢失：

```bash
chmod +x rootfs-hybrid/scripts/build-hybrid-rootfs.sh
chmod +x rootfs-hybrid/scripts/*.py
```

---

## 6. 第一次使用：先确认路径

进入工程根目录：

```bash
cd /home/buildroot/my_buildroot/workspace/buildroot-2024.08
```

执行：

```bash
./rootfs-hybrid/scripts/build-hybrid-rootfs.sh print-config
```

重点确认：

```text
PROJECT_ROOT
QT6_TARGET
NEW_ROOTFS_TAR
NEW_UIMAGE
OFFICIAL_RAMDISK
WORKDIR
COMPONENTS_YAML
READELF
OBJDUMP
```

全部指向实际文件后再继续。

---

## 7. 如果路径不同：使用环境变量，不要改脚本

例如基础系统在：

```text
/home/justin/board-backup/rootfs.tar.gz
/home/justin/board-backup/uImage
/home/justin/board-backup/ramdisk.gz
```

可以：

```bash
export PROJECT_ROOT=/home/buildroot/my_buildroot/workspace/buildroot-2024.08
export NEW_ROOTFS_TAR=/home/justin/board-backup/rootfs.tar.gz
export NEW_UIMAGE=/home/justin/board-backup/uImage
export OFFICIAL_RAMDISK=/home/justin/board-backup/ramdisk.gz

./rootfs-hybrid/scripts/build-hybrid-rootfs.sh print-config
```

也可以只对一条命令临时生效：

```bash
NEW_ROOTFS_TAR=/path/to/rootfs.tar.gz \
NEW_UIMAGE=/path/to/uImage \
OFFICIAL_RAMDISK=/path/to/ramdisk.gz \
./rootfs-hybrid/scripts/build-hybrid-rootfs.sh audit
```

### WORKDIR 安全限制

为了避免误删目录，脚本要求：

```text
WORKDIR 必须位于 PROJECT_ROOT 之下
```

因此不要把 `WORKDIR` 设置为 `/`、`PROJECT_ROOT` 本身或工程外部目录。

---

## 8. 查看当前要合并哪些组件

执行：

```bash
./rootfs-hybrid/scripts/build-hybrid-rootfs.sh list-components
```

当前默认组件包括：

```text
locale
qt6
opencv
numpy
sounddevice
onnxruntime
sherpa_onnx
ffmpeg
project
```

其中 `project` 当前默认：

```yaml
enabled: false
optional: true
```

也就是当前先构建通用 Qt6 + AI 系统，不会强制要求你的最终机器宠物业务程序已经安装进 `output-qt6/target`。

---

## 9. 建议重点检查 locale 组件

在正式构建前先执行：

```bash
./rootfs-hybrid/scripts/build-hybrid-rootfs.sh check-component locale
```

正常应匹配：

```text
usr/lib/locale/locale-archive
```

然后可以检查 Qt6：

```bash
./rootfs-hybrid/scripts/build-hybrid-rootfs.sh check-component qt6
```

检查 ONNX Runtime：

```bash
./rootfs-hybrid/scripts/build-hybrid-rootfs.sh check-component onnxruntime
```

如果 `locale` 显示没有文件匹配，不要继续 build，应先检查：

```bash
ls -lh output-qt6/target/usr/lib/locale/locale-archive
```

---

## 10. 正式构建前先运行 audit

推荐每次新 target 或新基础 rootfs 第一次合并前执行：

```bash
./rootfs-hybrid/scripts/build-hybrid-rootfs.sh audit
```

`audit` 会：

1. 清空上一次生成的临时 `rootfs/install/reports`；
2. 校验并解压基础 rootfs；
3. 检查内核、glibc、libstdc++、Python 等基础信息；
4. 记录受保护文件哈希；
5. 扫描旧 Qt5 消费者；
6. 对 `components.yaml` 做 dry-run，确认所有必需组件都能匹配。

`audit` **不会生成最终可交付包**。

正常情况下最后应显示：

```text
required components missing : 0
```

如果不是 0，应先解决缺失组件。

---

## 11. 正式构建

确认 `audit` 正常后执行：

```bash
./rootfs-hybrid/scripts/build-hybrid-rootfs.sh build
```

建议不要用 `sudo` 直接运行整个脚本。脚本内部通过 `fakeroot` 保存 rootfs 的目标 ownership/perms。

### build 内部会自动完成

```text
基础 rootfs 校验与解压
        ↓
受保护文件哈希记录
        ↓
Qt5 使用情况扫描
        ↓
components.yaml 组件合并
        ↓
递归补齐新增 ELF 的 DT_NEEDED 动态依赖
        ↓
新增 ELF 的 GLIBC / GLIBCXX / CXXABI 兼容检查
        ↓
删除旧 Qt5 runtime/demo
        ↓
重新确认不存在 Qt5 消费者
        ↓
清理合入软件中的非必要测试/开发文件
        ↓
完整 rootfs DT_NEEDED 闭包检查
        ↓
LoongArch 架构 + LSX/LASX ISA 检查
        ↓
受保护基础文件前后哈希比对
        ↓
C.UTF-8 locale 验证
        ↓
重新打包 + 最终 archive 必需文件检查
        ↓
生成 SHA256SUMS 和 merge-report.md
```

这些检查已经集成在主脚本中，不需要也不应该再调用旧的 `phase*.sh`。

---

## 12. 最终输出在哪里

构建成功后：

```text
rootfs-hybrid/install/
├── rootfs.tar.gz
├── uImage
├── ramdisk.gz
└── SHA256SUMS
```

运行时报告会自动生成到：

```text
rootfs-hybrid/reports/
```

其中最重要的是：

```text
merge-report.md
```

以及在构建失败时用于定位原因的自动报告文件。

这些是**构建产物**，不是额外诊断脚本。

---

## 13. 构建完成后的本机验收

### 13.1 校验 SHA256

```bash
cd rootfs-hybrid/install
sha256sum -c SHA256SUMS
```

全部应该为：

```text
OK
```

### 13.2 确认 locale 已进入最终包

```bash
tar -tzf rootfs.tar.gz | grep -E '^\./usr/lib/locale/locale-archive$|^\./etc/profile.d/locale.sh$'
```

必须同时看到：

```text
./usr/lib/locale/locale-archive
./etc/profile.d/locale.sh
```

### 13.3 确认 Qt6 platform plugin

```bash
tar -tzf rootfs.tar.gz | grep './usr/lib/qt6/plugins/platforms/libqlinuxfb.so'
```

### 13.4 确认旧 Qt5 没有重新进入包

```bash
tar -tzf rootfs.tar.gz | grep -E '^\./usr/lib/libQt5|^\./usr/lib/qt/|^\./usr/qml/'
```

正常应无输出。

---

## 14. 如何部署到板卡

这套脚本的交付物是：

```text
rootfs.tar.gz
uImage
ramdisk.gz
```

**请继续使用你已经验证过的先锋派板卡恢复/安装流程部署这三份文件。**

不要把 `rootfs.tar.gz` 当成 raw ext4 磁盘镜像直接 `dd` 到分区；它是 tar.gz 根文件系统包。具体如何写入 eMMC/TF 卡取决于你当前板卡已有的安装/恢复脚本和启动方式。

在没有确认板卡刷写流程前，不要对 `/dev/mmcblk*` 执行不确定的 `dd` 命令。

---

## 15. 部署后先验证 UTF-8 locale

重新启动板卡并重新登录 shell 后：

```bash
echo "LANG=$LANG LC_ALL=$LC_ALL"
```

预期至少：

```text
LANG=C.UTF-8
```

然后验证 glibc/Python：

```bash
python3 - <<'PY'
import locale
print("setlocale =", locale.setlocale(locale.LC_ALL, ''))
print("encoding  =", locale.getpreferredencoding(False))
PY
```

正确输出：

```text
setlocale = C.UTF-8
encoding  = UTF-8
```

如果当前 shell 是升级后一直没退出的旧登录会话，可以先：

```bash
source /etc/profile.d/locale.sh
```

再测一次。正常产品使用应以**重新登录后的环境**为准。

---

## 16. 部署后验证 Qt6

先加载 Qt6 环境：

```bash
source /etc/profile.d/qt6.sh
```

检查关键文件：

```bash
ls -l /usr/lib/libQt6Core.so.6
ls -l /usr/lib/qt6/plugins/platforms/libqlinuxfb.so
ls -l /usr/lib/qt6/plugins/platforminputcontexts/libqtvirtualkeyboardplugin.so
```

然后运行你的程序：

```bash
./qt_first_project
```

之前的：

```text
Detected locale "C" with character encoding "ANSI_X3.4-1968"
Qt depends on a UTF-8 locale...
```

不应再次出现。

如果需要插件详细日志，可临时使用：

```bash
QT_DEBUG_PLUGINS=1 ./qt_first_project
```

这是临时调试变量，不需要写入产品环境。

---

## 17. 如果 Qt 程序以后由 systemd 自动启动

`/etc/profile.d/*.sh` 主要服务于登录 shell。systemd service 不应假定会读取这些文件。

因此你的 Qt 应用 service 建议明确加入：

```ini
[Service]
Environment=LANG=C.UTF-8
Environment=QT_QPA_PLATFORM=linuxfb
Environment=QT_QPA_FB_TSLIB=1
Environment=QT_IM_MODULE=qtvirtualkeyboard
Environment=QT_QUICK_BACKEND=software
Environment=QT_PLUGIN_PATH=/usr/lib/qt6/plugins
Environment=QML_IMPORT_PATH=/usr/lib/qt6/qml
```

是否需要这些 Qt 变量应按最终应用实际使用的 Widgets/Quick/触摸/虚拟键盘功能决定。

---

## 18. components.yaml 怎么改

### 18.1 `enabled`

```yaml
enabled: true
```

表示正式合入。

### 18.2 `include`

指定从 `output-qt6/target` 中需要复制的文件/目录：

```yaml
include:
  - /usr/lib/libonnxruntime.so*
```

### 18.3 `exclude`

从 include 结果中排除开发文件、测试等：

```yaml
exclude:
  - "**/*.a"
  - "**/tests/**"
```

### 18.4 `optional`

```yaml
optional: true
```

表示这个组件没有匹配到文件时只警告，不让整个构建失败。

正式运行必需组件不要设为 optional。

### 18.5 `post_install`

用于合并完成后写少量目标系统配置。例如当前 `locale` 组件会自动创建：

```text
/etc/profile.d/locale.sh
```

内容为：

```bash
export LANG=C.UTF-8
```

### 18.6 `protected_paths`

这些路径用于避免组件覆盖稳定基础系统里的关键文件，例如：

```text
/boot/**
/lib/modules/**
/lib/firmware/**
/lib/libc.so*
/usr/lib/libstdc++.so*
/usr/lib/systemd/**
/etc/**
```

规则是：**如果目标文件已经存在于基础 rootfs 且属于 protected path，则组件复制不会覆盖它；如果对应目标文件原本不存在，则允许创建新文件。**

不要为了“让复制成功”随意删除 libc、kernel、systemd 等保护规则。

---

## 19. 如何把你自己的机器宠物程序加入最终 rootfs

当前 `components.yaml` 已预留：

```yaml
project:
  enabled: false
  optional: true
  include:
    - /opt/fanfan/**
    - /usr/bin/fanfan-*
    - /usr/lib/systemd/system/fanfan-*.service
```

建议先把业务程序安装进 Buildroot target，例如：

```text
output-qt6/target/opt/fanfan/...
```

或者：

```text
output-qt6/target/usr/bin/fanfan-ui
```

确认：

```bash
./rootfs-hybrid/scripts/build-hybrid-rootfs.sh check-component project
```

可以匹配以后，把：

```yaml
enabled: false
```

改为：

```yaml
enabled: true
```

如果程序变成最终产品必需组件，建议同时把：

```yaml
optional: true
```

改为：

```yaml
optional: false
```

这样业务程序漏装时 build 会直接失败，而不是生成一个缺业务程序的镜像。

新增 ELF 可执行文件后，后面的动态依赖、ABI 和 ISA 检查会自动覆盖它，不需要再新增所谓“phase 脚本”。

---

## 20. 每次重新编译 output-qt6 后的推荐流程

如果你重新编译了 Qt6、OpenCV、ONNX Runtime、sherpa-onnx 或其他 target 内容：

```bash
cd /home/buildroot/my_buildroot/workspace/buildroot-2024.08

./rootfs-hybrid/scripts/build-hybrid-rootfs.sh clean
./rootfs-hybrid/scripts/build-hybrid-rootfs.sh check-component locale
./rootfs-hybrid/scripts/build-hybrid-rootfs.sh audit
./rootfs-hybrid/scripts/build-hybrid-rootfs.sh build
```

注意：

```bash
./build-hybrid-rootfs.sh clean
```

会删除：

```text
rootfs-hybrid/rootfs
rootfs-hybrid/install
rootfs-hybrid/reports
rootfs-hybrid/fakeroot.db
```

如果之前的正式包需要留档，应先复制 `install/` 和重要报告。

---

## 21. 主脚本命令速查

### 帮助

```bash
./rootfs-hybrid/scripts/build-hybrid-rootfs.sh help
```

### 查看实际路径

```bash
./rootfs-hybrid/scripts/build-hybrid-rootfs.sh print-config
```

### 查看组件

```bash
./rootfs-hybrid/scripts/build-hybrid-rootfs.sh list-components
```

### 查看某组件具体匹配

```bash
./rootfs-hybrid/scripts/build-hybrid-rootfs.sh check-component locale
```

### 构建前审计

```bash
./rootfs-hybrid/scripts/build-hybrid-rootfs.sh audit
```

### 正式构建

```bash
./rootfs-hybrid/scripts/build-hybrid-rootfs.sh build
```

### 清理自动生成目录

```bash
./rootfs-hybrid/scripts/build-hybrid-rootfs.sh clean
```

---

## 22. 常见错误处理

### 22.1 `ERROR: missing input ...`

说明基础 `rootfs.tar.gz/uImage/ramdisk.gz` 路径不对。

先：

```bash
./rootfs-hybrid/scripts/build-hybrid-rootfs.sh print-config
```

再检查文件。

### 22.2 `cross readelf missing` / `cross objdump missing`

检查：

```bash
ls output-qt6/host/bin/*loongarch*readelf
ls output-qt6/host/bin/*loongarch*objdump
```

如果你的交叉工具前缀不同，设置 `READELF`/`OBJDUMP`。

### 22.3 `python3 PyYAML required`

安装：

```bash
sudo apt install python3-yaml
```

或：

```bash
python3 -m pip install pyyaml
```

### 22.4 `component 'locale': required, no files matched`

检查：

```bash
ls -lh output-qt6/target/usr/lib/locale/locale-archive
```

没有该文件就先修 Buildroot locale 生成。

### 22.5 `base glibc X != QT6_TARGET glibc Y`

不要强行绕过。

`locale-archive` 和大量 Qt/AI userland 都与 libc/ABI 相关。应使用与基础板 rootfs 兼容的 Buildroot target，或者重新统一基础系统和 target。

### 22.6 `base /boot/uImage does not match external NEW_UIMAGE`

说明 `rootfs.tar.gz` 和传入的 `uImage` 不是同一套基础系统。重新选择匹配文件。

### 22.7 `Qt5 consumers remain after Qt5 runtime removal`

查看：

```text
rootfs-hybrid/reports/qt5-consumers-after.txt
```

不要直接删除检查。应该判断这些程序是否仍要保留，或者将对应程序一并迁移 Qt6。

### 22.8 `full-rootfs DT_NEEDED` 检查失败

查看：

```text
rootfs-hybrid/reports/full-rootfs-deps.txt
```

其中 `MISSING:` 表示某个 ELF 的动态依赖没有出现在最终 rootfs 中。

### 22.9 LSX/LASX 检查失败

2K0300 不支持 LSX/LASX。不要把检测关闭后继续出包。

应该重新检查对应软件编译参数，确保使用通用 LoongArch64 标量代码；尤其 ONNX Runtime 必须继续使用你已经验证过的 scalar MLAS 修复版本。

### 22.10 `protected base files changed`

查看：

```text
rootfs-hybrid/reports/protected-files.diff
```

这表示合并过程修改了本应保持不变的 kernel/module/libc/libstdc++ 等基础文件，应先定位原因。

### 22.11 板上又出现 Qt `ANSI_X3.4-1968`

先检查：

```bash
ls -lh /usr/lib/locale/locale-archive
cat /etc/profile.d/locale.sh
printf 'LANG=%s\n' "$LANG"
```

再测：

```bash
LANG=C.UTF-8 LC_ALL=C.UTF-8 python3 - <<'PY'
import locale
print(locale.setlocale(locale.LC_ALL, ''))
print(locale.getpreferredencoding(False))
PY
```

如果 `locale-archive` 在且 Python 返回 `C.UTF-8 / UTF-8`，locale 数据正常；若登录 shell 的 `LANG` 为空，重新登录或检查 `/etc/profile` 是否加载 `/etc/profile.d/*.sh`。

---

## 23. 当前 `C.UTF-8` 修复是如何保证不再漏掉的

这份精简版中，locale 不再依赖基础 rootfs “碰巧带有”语言数据。

`components.yaml` 明确把：

```text
/usr/lib/locale/locale-archive
```

作为一个**必需组件**从 `output-qt6/target` 合入。

同时创建：

```text
/etc/profile.d/locale.sh
```

导出：

```bash
LANG=C.UTF-8
```

主脚本在最终打包时还会强制检查以下两个文件存在：

```text
./usr/lib/locale/locale-archive
./etc/profile.d/locale.sh
```

并比较 `locale-archive` 打包前后 SHA256。

因此，如果将来 locale 又被漏掉，`build` 应直接失败，不会像之前一样等到板上运行 Qt6 才发现。

---

## 24. 最推荐的固定操作流程

以后正常使用基本只需要记住以下命令：

```bash
cd /home/buildroot/my_buildroot/workspace/buildroot-2024.08

# 1. 看路径
./rootfs-hybrid/scripts/build-hybrid-rootfs.sh print-config

# 2. 关键组件检查
./rootfs-hybrid/scripts/build-hybrid-rootfs.sh check-component locale

# 3. 预检查
./rootfs-hybrid/scripts/build-hybrid-rootfs.sh audit

# 4. 正式构建
./rootfs-hybrid/scripts/build-hybrid-rootfs.sh build

# 5. 校验成品
cd rootfs-hybrid/install
sha256sum -c SHA256SUMS
```

只要这五步通过，就使用 `install/` 中的三份板卡文件进入你原有的部署流程。
