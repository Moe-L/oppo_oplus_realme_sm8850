#!/bin/bash
set -e

# ===== 获取脚本目录 =====
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
cd "$SCRIPT_DIR"

# ===== 设置自定义参数 =====
echo "===== 新版米系/通用GKI机型 6.12.69 GKI内核本地编译脚本 By Coolapk@cctv18 ====="
echo ">>> 读取用户配置..."
MANIFEST=${MANIFEST:-oppo+oplus+realme+mi}
read -p "请输入自定义内核后缀（默认：android16-5-ge7f2a9832757-ab13799791-4k）: " CUSTOM_SUFFIX
CUSTOM_SUFFIX=${CUSTOM_SUFFIX:-android16-5-ge7f2a9832757-ab13799791-4k}
read -p "是否启用susfs？(y/n，默认：y): " APPLY_SUSFS
APPLY_SUSFS=${APPLY_SUSFS:-y}
read -p "是否启用 KPM？(y-启用 KpatchNext独立kpm实现, n-关闭kpm，默认：n): " USE_PATCH_LINUX
USE_PATCH_LINUX=${USE_PATCH_LINUX:-n}
read -p "KSU分支版本(r=BakaSU, y=SukiSU Ultra, f=FinaSU, n=KernelSU Next, k=KSU, l=lkm模式(无内置KSU), 默认：r): " KSU_BRANCH
KSU_BRANCH=${KSU_BRANCH:-r}
read -p "KSU源码分支/标签(可选, 回车使用默认: BakaSU/SukiSU=main, FinaSU=master, KernelSU Next=dev-susfs, KSU=main, 例如: sync-up): " KSU_SRC_BRANCH
KSU_SRC_BRANCH=${KSU_SRC_BRANCH:-}
read -p "是否应用 lz4 1.10.0 & zstd 1.5.7 补丁？(y/n，默认：y): " APPLY_LZ4
APPLY_LZ4=${APPLY_LZ4:-y}
read -p "是否应用 lz4kd 补丁？(y/n，默认：n): " APPLY_LZ4KD
APPLY_LZ4KD=${APPLY_LZ4KD:-n}
read -p "是否启用网络功能增强优化配置？(y/n，默认：y): " APPLY_BETTERNET
APPLY_BETTERNET=${APPLY_BETTERNET:-y}
read -p "是否添加 BBR 等一系列拥塞控制算法？(y添加/n禁用/d默认，默认：n): " APPLY_BBR
APPLY_BBR=${APPLY_BBR:-n}
read -p "是否添加 Droidspaces 容器支持？(n禁用/s标准/e扩展，默认：n): " APPLY_DROIDSPACES
APPLY_DROIDSPACES=${APPLY_DROIDSPACES:-n}
read -p "是否启用ADIOS调度器？(y/n，默认：y): " APPLY_ADIOS
APPLY_ADIOS=${APPLY_ADIOS:-y}
read -p "是否启用Re-Kernel？(y/n，默认：n): " APPLY_REKERNEL
APPLY_REKERNEL=${APPLY_REKERNEL:-n}
read -p "是否启用内核级基带保护？(y/n，默认：y): " APPLY_BBG
APPLY_BBG=${APPLY_BBG:-y}

if [[ "$KSU_BRANCH" == "y" || "$KSU_BRANCH" == "Y" ]]; then
  KSU_TYPE="SukiSU Ultra"
elif [[ "$KSU_BRANCH" == "r" || "$KSU_BRANCH" == "R" ]]; then
  KSU_TYPE="BakaSU"
elif [[ "$KSU_BRANCH" == "f" || "$KSU_BRANCH" == "F" ]]; then
  KSU_TYPE="FinaSU"
elif [[ "$KSU_BRANCH" == "n" || "$KSU_BRANCH" == "N" ]]; then
  KSU_TYPE="KernelSU Next"
elif [[ "$KSU_BRANCH" == "k" || "$KSU_BRANCH" == "K" ]]; then
  KSU_TYPE="KernelSU"
else
  KSU_TYPE="no KSU"
fi

# ===== 解析 KSU 源码仓库与默认分支 =====
# 未指定分支时回落到各管理器默认分支，保证与旧行为一致
case "$KSU_BRANCH" in
  y|Y|r|R) KSU_REPO="Baka-SU/BakaSU";         KSU_DEFAULT_BRANCH="main" ;;
  f|F)     KSU_REPO="LyraVoid/FinaSU";         KSU_DEFAULT_BRANCH="master" ;;
  n|N)     KSU_REPO="pershoot/KernelSU-Next"; KSU_DEFAULT_BRANCH="dev-susfs" ;;
  k|K)     KSU_REPO="tiann/KernelSU";         KSU_DEFAULT_BRANCH="main" ;;
  *)       KSU_REPO="";                       KSU_DEFAULT_BRANCH="" ;;
esac

if [[ -n "$KSU_SRC_BRANCH" && -z "$KSU_REPO" ]]; then
  echo ">>> 警告：当前为无内置KSU模式，分支参数 '$KSU_SRC_BRANCH' 将被忽略"
  KSU_SRC_BRANCH=""
fi
KSU_SRC_BRANCH="${KSU_SRC_BRANCH:-$KSU_DEFAULT_BRANCH}"

# 仅 FinaSU 需要把管理器签名作为 make 参数传入，其它变体保持为空
KSU_MAKE_ARGS=""

# ===== 分支名合法性校验（防注入 / 非法 git ref） =====
if [[ -n "$KSU_SRC_BRANCH" ]]; then
  if ! [[ "$KSU_SRC_BRANCH" =~ ^[A-Za-z0-9][A-Za-z0-9._/-]{0,127}$ ]]; then
    echo "错误：KSU 分支名不合法 -> '$KSU_SRC_BRANCH'"
    echo "仅允许字母、数字、点、下划线、斜杠和连字符，且不能以连字符开头"
    exit 1
  fi
  case "$KSU_SRC_BRANCH" in
    *..*) echo "错误：KSU 分支名不合法（不允许包含 '..'）-> '$KSU_SRC_BRANCH'"; exit 1 ;;
  esac
fi

echo
echo "===== 配置信息 ====="
echo "适用机型: $MANIFEST"
echo "自定义内核后缀: -$CUSTOM_SUFFIX"
echo "KSU分支版本: $KSU_TYPE"
echo "KSU源码分支: ${KSU_SRC_BRANCH:-（不适用）}"
echo "启用susfs: $APPLY_SUSFS"
echo "启用 KPM: $USE_PATCH_LINUX"
echo "应用 lz4&zstd 补丁: $APPLY_LZ4"
echo "应用 lz4kd 补丁: $APPLY_LZ4KD"
echo "应用网络功能增强优化配置: $APPLY_BETTERNET"
echo "应用 BBR 等算法: $APPLY_BBR"
echo "应用 Droidspaces 容器支持: $APPLY_DROIDSPACES"
echo "启用ADIOS调度器: $APPLY_ADIOS"
echo "启用Re-Kernel: $APPLY_REKERNEL"
echo "启用内核级基带保护: $APPLY_BBG"
echo "===================="
echo

# ===== 创建工作目录 =====
WORKDIR="$SCRIPT_DIR"
cd "$WORKDIR"

# ===== 安装构建依赖 =====
echo ">>> 安装构建依赖..."
# Function to run a command with sudo if not already root
SU() {
    if [ "$(id -u)" -eq 0 ]; then
        "$@"
    else
        sudo "$@"
    fi
}

SU apt-mark hold firefox && apt-mark hold libc-bin && apt-mark hold man-db
SU rm -rf /var/lib/man-db/auto-update
SU apt-get update
SU apt-get install --no-install-recommends -y curl bison flex clang binutils dwarves git lld pahole zip perl make gcc python3 python-is-python3 bc libssl-dev libelf-dev libdw-dev cpio xz-utils tar unzip aria2

# ===== 初始化仓库 =====
echo ">>> 初始化仓库..."
rm -rf kernel_workspace
mkdir kernel_workspace
cd kernel_workspace

echo "正在克隆源码仓库..."
aria2c -s16 -x16 -k1M https://github.com/cctv18/android_gki_kernel_common/archive/refs/heads/android16-6.12-2026-03.zip -o common.zip &&
unzip -q common.zip &&
mv "android_gki_kernel_common-android16-6.12-2026-03" common &&
rm -rf common.zip &

echo "正在克隆llvm-clang19工具链..." &&
mkdir -p clang19 &&
aria2c -s16 -x16 -k1M https://github.com/cctv18/oneplus_sm8650_toolchain/releases/download/LLVM-Clang19-r536225/clang-r536225.zip -o clang.zip &&
unzip -q clang.zip -d clang19 &&
rm -rf clang.zip &

echo "正在克隆Rust 1.82.0工具链..." &&
mkdir -p rust &&
aria2c -s16 -x16 -k1M https://github.com/cctv18/oneplus_sm8650_toolchain/releases/download/LLVM-Clang19-r536225/rust.zip -o rust.zip &&
unzip -q rust.zip -d rust &&
rm -rf rust.zip &

echo "正在克隆构建工具..." &&
aria2c -s16 -x16 -k1M https://github.com/cctv18/oneplus_sm8650_toolchain/releases/download/LLVM-Clang19-r536225/build-tools.zip -o build-tools.zip &&
unzip -q build-tools.zip &&
rm -rf build-tools.zip &

wait
echo "所有源码及llvm-clang19工具链初始化完成！"
echo ">>> 初始化仓库完成!"

for f in common/scripts/setlocalversion; do
  sed -i 's/ -dirty//g' "$f"
  sed -i '$i res=$(echo "$res" | sed '\''s/-dirty//g'\'')' "$f"
done

# ===== 替换版本后缀 =====
echo ">>> 替换内核版本后缀..."
for f in ./common/scripts/setlocalversion; do
  sed -i "\$s|echo \"\\\$res\"|echo \"-${CUSTOM_SUFFIX}\"|" "$f"
done
sudo sed -i 's/^CONFIG_LOCALVERSION=.*/CONFIG_LOCALVERSION="-'${CUSTOM_SUFFIX}'"/' ./common/arch/arm64/configs/gki_defconfig
sed -i 's/${scm_version}//' ./common/scripts/setlocalversion
echo "CONFIG_LOCALVERSION_AUTO=n" >> ./common/arch/arm64/configs/gki_defconfig

# ===== 拉取 KSU 并设置版本号 =====
# 校验指定的分支/标签在远端确实存在，不存在则立即退出，避免白等一次完整编译
if [[ -n "$KSU_REPO" ]]; then
  echo ">>> 校验 KSU 源码分支：$KSU_REPO @ $KSU_SRC_BRANCH"
  if ! git ls-remote --exit-code "https://github.com/$KSU_REPO" "refs/heads/$KSU_SRC_BRANCH" "refs/tags/$KSU_SRC_BRANCH" > /dev/null 2>&1; then
    echo "错误：$KSU_REPO 中不存在分支/标签 '$KSU_SRC_BRANCH'，请检查后重试"
    echo "该仓库当前可用的分支："
    git ls-remote --heads "https://github.com/$KSU_REPO" | sed 's#.*refs/heads/##' | sort || true
    exit 1
  fi
fi

# 校验上游 setup.sh 是否真的切到了指定分支（上游在 checkout 失败时只打印提示、不会退出）
verify_ksu_ref() {
  local dir="$1"
  local want="$2"
  local actual=""
  if [[ ! -d "$dir" ]]; then
    echo "错误：未找到 KSU 源码目录 $dir（上游 setup.sh 可能执行失败）"
    return 1
  fi
  actual="$(git -C "$dir" rev-parse --abbrev-ref HEAD 2>/dev/null || true)"
  if [[ "$actual" == "HEAD" || -z "$actual" ]]; then
    actual="$(git -C "$dir" describe --tags --exact-match 2>/dev/null || true)"
  fi
  if [[ -z "$actual" ]]; then
    actual="$(git -C "$dir" rev-parse --short HEAD 2>/dev/null || true)"
  fi
  if [[ "$actual" != "$want" ]]; then
    echo "错误：KSU 源码实际位于 '$actual'，与指定的 '$want' 不一致"
    return 1
  fi
  echo ">>> KSU 源码已确认位于：$actual"
}

if [[ $KSU_BRANCH == [yYrR] ]]; then
  echo ">>> 拉取 BakaSU 并设置版本（由于SukiSU长期未维护无法正常编译，且BakaSU兼容sukisu管理器，故SukiSU源码仓库已重定向为bakasu）..."
  curl -LSs "https://raw.githubusercontent.com/Baka-SU/BakaSU/main/kernel/setup.sh" | bash -s "$KSU_SRC_BRANCH"
  verify_ksu_ref ./KernelSU "$KSU_SRC_BRANCH" || exit 1
  echo 'CONFIG_KSU_FULL_NAME_FORMAT="%TAG_NAME%-%COMMIT_SHA%@cctv18"' >> ./common/arch/arm64/configs/gki_defconfig
elif [[ "$KSU_BRANCH" == "n" || "$KSU_BRANCH" == "N" ]]; then
  echo ">>> 拉取 KernelSU Next 并设置版本..."
  curl -LSs "https://raw.githubusercontent.com/pershoot/KernelSU-Next/refs/heads/dev-susfs/kernel/setup.sh" | bash -s "$KSU_SRC_BRANCH"
  verify_ksu_ref ./KernelSU-Next "$KSU_SRC_BRANCH" || exit 1
  cd KernelSU-Next
  # 版本号按当前分支本地提交计数生成，换分支后依然准确，也不再依赖 GitHub API 分页
  KSU_VERSION=$(expr $(git rev-list --count HEAD) + 30000 2>/dev/null || echo 114514)
  rm -rf .git
  sed -i "s/KSU_VERSION_FALLBACK := 1/KSU_VERSION_FALLBACK := $KSU_VERSION/g" kernel/Kbuild
  KSU_GIT_TAG=$(curl -sL "https://api.github.com/repos/KernelSU-Next/KernelSU-Next/tags" | grep -o '"name": *"[^"]*"' | head -n 1 | sed 's/"name": "//;s/"//' || true)
  if [[ -z "$KSU_GIT_TAG" ]]; then
    echo ">>> 警告：未能从 GitHub API 获取 KernelSU Next 最新 tag，保留 Kbuild 中的默认值"
  else
    sed -i "s/KSU_VERSION_TAG_FALLBACK := v0.0.1/KSU_VERSION_TAG_FALLBACK := $KSU_GIT_TAG/g" kernel/Kbuild
  fi
  #为KernelSU Next添加WildKSU管理器支持
  cd ../common/drivers/kernelsu
  wget https://github.com/cctv18/oppo_oplus_realme_sm8850/raw/refs/heads/main/other_patch/apk_sign.patch
  patch -p2 -N -F 3 < apk_sign.patch || true
elif [[ "$KSU_BRANCH" == "f" || "$KSU_BRANCH" == "F" ]]; then
  echo ">>> 拉取 FinaSU 并设置版本..."
  # 不依赖上游 kernel/setup.sh 是否存在，直接按其通用布局接入（symlink + Makefile + Kconfig）
  git clone "https://github.com/$KSU_REPO" ./KernelSU
  git -C ./KernelSU checkout "$KSU_SRC_BRANCH"
  if [[ ! -d ./KernelSU/kernel ]]; then
    echo "错误：FinaSU 源码布局异常，缺少 KernelSU/kernel 目录"
    exit 1
  fi
  ln -sfn "$(realpath --relative-to=./common/drivers ./KernelSU/kernel)" ./common/drivers/kernelsu
  grep -q 'kernelsu' ./common/drivers/Makefile || printf '\nobj-$(CONFIG_KSU) += kernelsu/\n' >> ./common/drivers/Makefile
  grep -q 'drivers/kernelsu/Kconfig' ./common/drivers/Kconfig || sed -i '/endmenu/i\source "drivers/kernelsu/Kconfig"' ./common/drivers/Kconfig
  # FinaSU 的 Kbuild 用 $(KSU_KERNEL_DIR)=$(srctree)/$(src) 推导 include 路径，内联进 GKI 树时可能落空，
  # 这里追加构建期解析出的绝对路径，保证 kernel/include/klog.h 与仓库根 uapi/*.h 都能被找到
  KSU_ABS_DIR="$(cd ./KernelSU && pwd)"
  printf '\nccflags-y += -I%s -I%s/kernel -I%s/kernel/include\n' "$KSU_ABS_DIR" "$KSU_ABS_DIR" "$KSU_ABS_DIR" >> ./KernelSU/kernel/Kbuild
  echo ">>> 已为 FinaSU Kbuild 追加 include 路径：$KSU_ABS_DIR"
  # FinaSU 内核校验管理器 APK 签名，Kbuild 默认值是上游占位值，必须传入 FinaSU 正式管理器的证书信息
  KSU_EXPECTED_SIZE="0x02cc"
  KSU_EXPECTED_HASH="2d89b50aaf1db013c2b6738f973f48b62ea21a3a8d7216bfec3521065d448458"
  KSU_MAKE_ARGS="KSU_EXPECTED_SIZE=$KSU_EXPECTED_SIZE KSU_EXPECTED_HASH=$KSU_EXPECTED_HASH"
  echo ">>> FinaSU 管理器签名：$KSU_EXPECTED_SIZE / $KSU_EXPECTED_HASH"
  verify_ksu_ref ./KernelSU "$KSU_SRC_BRANCH" || exit 1
  # 与 FinaSU Kbuild 自身公式（30000 + 提交数）保持一致
  KSU_VERSION=$(expr $(git -C ./KernelSU rev-list --count HEAD) + 30000 2>/dev/null || echo 114514)
  echo ">>> FinaSU 版本号：$KSU_VERSION"
elif [[ "$KSU_BRANCH" == "k" || "$KSU_BRANCH" == "K" ]]; then
  echo "正在配置原版 KernelSU (tiann/KernelSU)..."
  curl -LSs "https://raw.githubusercontent.com/tiann/KernelSU/refs/heads/main/kernel/setup.sh" | bash -s "$KSU_SRC_BRANCH"
  verify_ksu_ref ./KernelSU "$KSU_SRC_BRANCH" || exit 1
  cd ./KernelSU
  KSU_VERSION=$(expr $(git rev-list --count HEAD) + 30000 2>/dev/null || echo 114514)
  sed -i "s/DKSU_VERSION=16/DKSU_VERSION=${KSU_VERSION}/" kernel/Kbuild
else
  echo "已选择无内置KernelSU模式，跳过配置..."
fi

# ===== 克隆补丁仓库&应用 SUSFS 补丁 =====
cd "$WORKDIR/kernel_workspace"
echo ">>> 应用 SUSFS&hook 补丁..."
# FinaSU 的 SUSFS 只做驱动侧集成（kernel/extension/susfs.c），内核侧 fs/susfs.c 仍需打补丁
if [[ "$APPLY_SUSFS" == [yY] ]]; then
  echo ">>> 克隆补丁仓库..."
  # 按 KSU 源码需要的 SUSFS 契约选择补丁来源：
  #   1) 引用 susfs_add_sus_type（v2.4.0 类型注册，如 BakaSU sync-up / FinaSU）→ 必须用上游 v2.4.0 补丁，
  #      否则内核侧的反检测修复会被编译剔除，检测照样命中；
  #   2) 仅引用 CMD_SUSFS_SET_PRIORITY_UID_FILTER → cctv18 fork 的 -dev 分支；
  #   3) 其余 → cctv18 fork 稳定分支。
  SUSFS_NEEDS_V240=0
  if grep -Rqs 'susfs_add_sus_type' ./KernelSU ./KernelSU-Next 2>/dev/null; then
    SUSFS_NEEDS_V240=1
    SUSFS_REPO="https://gitlab.com/simonpunk/susfs4ksu.git"
    SUSFS_BRANCH="gki-android16-6.12"
    echo ">>> 检测到 KSU 需要 SUSFS v2.4.0 类型注册接口，使用上游 v2.4.0 补丁"
  else
    SUSFS_REPO="https://github.com/cctv18/susfs4oki.git"
    SUSFS_BRANCH="oki-android16-6.12"
    if grep -Rqs 'CMD_SUSFS_SET_PRIORITY_UID_FILTER' ./KernelSU ./KernelSU-Next 2>/dev/null; then
      SUSFS_BRANCH="${SUSFS_BRANCH}-dev"
      echo ">>> 检测到 KSU 需要 priority-uid 命令，使用 dev 分支补丁"
    fi
  fi
  echo ">>> 使用 SUSFS 补丁：$SUSFS_REPO @ $SUSFS_BRANCH"
  git clone --depth=1 "$SUSFS_REPO" susfs4ksu -b "$SUSFS_BRANCH"
  cp ./susfs4ksu/kernel_patches/50_add_susfs_in_gki-android16-6.12.patch ./common/
  cp ./susfs4ksu/kernel_patches/fs/* ./common/fs/
  cp ./susfs4ksu/kernel_patches/include/linux/* ./common/include/linux/
  cd ./common
  if ! patch -p1 -F 3 < 50_add_susfs_in_gki-android16-6.12.patch; then
    echo ">>> 警告：susfs 内核侧补丁有 hunk 未应用（源码可能已包含或已变化）"
    if [[ "$SUSFS_NEEDS_V240" == "1" ]]; then
      echo "错误：v2.4.0 补丁未完整应用，SUSFS 类型注册会缺失，中止"
      exit 1
    fi
  fi
  cd ..
  # 实现体在 fs/susfs.c（头文件里没有声明）
  if [[ "$SUSFS_NEEDS_V240" == "1" ]] && ! grep -qs 'susfs_add_sus_type' ./common/fs/susfs.c ./common/include/linux/susfs.h; then
    echo "错误：KSU 需要 SUSFS v2.4.0 类型注册接口，但补丁未提供"
    exit 1
  fi
else
  echo ">>> 未开启susfs，跳过susfs补丁配置..."
fi

cd "$WORKDIR/kernel_workspace"
if [[ "$KSU_BRANCH" == [kK] && "$APPLY_SUSFS" == [yY] ]]; then
  cp ./susfs4ksu/kernel_patches/KernelSU/10_enable_susfs_for_ksu.patch ./KernelSU/
  cd ./KernelSU
  patch -p1 -F 3 < 10_enable_susfs_for_ksu.patch || true
fi
cd "$WORKDIR/kernel_workspace"

# ===== 应用 LZ4 & ZSTD 补丁 =====
if [[ "$APPLY_LZ4" == "y" || "$APPLY_LZ4" == "Y" ]]; then
  echo ">>> 正在添加lz4 1.10.0 & zstd 1.5.7补丁..."
  git clone --depth=1 https://github.com/cctv18/oppo_oplus_realme_sm8850.git
  cp ./oppo_oplus_realme_sm8850/zram_patch/001-lz4.patch ./common/
  cp ./oppo_oplus_realme_sm8850/zram_patch/002-zstd.patch ./common/
  cd "$WORKDIR/kernel_workspace/common"
  patch -p1 -F 3 < 001-lz4.patch || true
  patch -p1 -F 3 < 002-zstd.patch || true
  cd "$WORKDIR/kernel_workspace"
else
  echo ">>> 跳过 LZ4&ZSTD 补丁..."
  cd "$WORKDIR/kernel_workspace"
fi

# ===== 应用 LZ4KD 补丁 =====
if [[ "$APPLY_LZ4KD" == "y" || "$APPLY_LZ4KD" == "Y" ]]; then
  echo ">>> 应用 LZ4KD 补丁..."
  cd "$WORKDIR/kernel_workspace/common"
  wget https://github.com/cctv18/oppo_oplus_realme_sm8850/raw/refs/heads/main/other_patch/lz4kd.patch
  patch -p1 -F 3 < lz4kd.patch || true
  cd "$WORKDIR/kernel_workspace"
else
  echo ">>> 跳过 LZ4KD 补丁..."
  cd "$WORKDIR/kernel_workspace"
fi

# ===== 添加 defconfig 配置项 =====
echo ">>> 添加 defconfig 配置项..."
DEFCONFIG_FILE=./common/arch/arm64/configs/gki_defconfig

# 写入通用 SUSFS/KSU 配置
echo "CONFIG_KSU=y" >> "$DEFCONFIG_FILE"
if [[ "$APPLY_SUSFS" == [yY] ]]; then
  echo "CONFIG_KSU_SUSFS=y" >> "$DEFCONFIG_FILE"
  echo "CONFIG_KSU_SUSFS_HAS_MAGIC_MOUNT=y" >> "$DEFCONFIG_FILE"
  echo "CONFIG_KSU_SUSFS_SUS_PATH=y" >> "$DEFCONFIG_FILE"
  echo "CONFIG_KSU_SUSFS_SUS_MOUNT=y" >> "$DEFCONFIG_FILE"
  echo "CONFIG_KSU_SUSFS_AUTO_ADD_SUS_KSU_DEFAULT_MOUNT=y" >> "$DEFCONFIG_FILE"
  echo "CONFIG_KSU_SUSFS_AUTO_ADD_SUS_BIND_MOUNT=y" >> "$DEFCONFIG_FILE"
  echo "CONFIG_KSU_SUSFS_SUS_KSTAT=y" >> "$DEFCONFIG_FILE"
  echo "CONFIG_KSU_SUSFS_TRY_UMOUNT=y" >> "$DEFCONFIG_FILE"
  echo "CONFIG_KSU_SUSFS_AUTO_ADD_TRY_UMOUNT_FOR_BIND_MOUNT=y" >> "$DEFCONFIG_FILE"
  echo "CONFIG_KSU_SUSFS_SPOOF_UNAME=y" >> "$DEFCONFIG_FILE"
  echo "CONFIG_KSU_SUSFS_ENABLE_LOG=y" >> "$DEFCONFIG_FILE"
  echo "CONFIG_KSU_SUSFS_HIDE_KSU_SUSFS_SYMBOLS=y" >> "$DEFCONFIG_FILE"
  echo "CONFIG_KSU_SUSFS_SPOOF_CMDLINE_OR_BOOTCONFIG=y" >> "$DEFCONFIG_FILE"
  echo "CONFIG_KSU_SUSFS_OPEN_REDIRECT=y" >> "$DEFCONFIG_FILE"
  echo "CONFIG_KSU_SUSFS_SUS_MAP=y" >> "$DEFCONFIG_FILE"
else
  echo "CONFIG_KSU_SUSFS=n" >> "$DEFCONFIG_FILE"
fi
#添加对 Mountify (backslashxx/mountify) 模块的支持
echo "CONFIG_TMPFS_XATTR=y" >> "$DEFCONFIG_FILE"
echo "CONFIG_TMPFS_POSIX_ACL=y" >> "$DEFCONFIG_FILE"

# 开启O2编译优化配置
echo "CONFIG_CC_OPTIMIZE_FOR_PERFORMANCE=y" >> "$DEFCONFIG_FILE"
# 跳过将 uapi 标准头安装到 usr/include 以节省编译时间；
# 但 FinaSU 的内置编译依赖 usr/include（preinit 与部分 uapi 头），必须保持 =y
if [[ "$KSU_BRANCH" == [fF] ]]; then
  echo "CONFIG_HEADERS_INSTALL=y" >> "$DEFCONFIG_FILE"
  echo "CONFIG_KPROBES=y" >> "$DEFCONFIG_FILE"
  echo "CONFIG_KALLSYMS_ALL=y" >> "$DEFCONFIG_FILE"
  echo "CONFIG_EXT4_FS=y" >> "$DEFCONFIG_FILE"
  echo "CONFIG_THREAD_INFO_IN_TASK=y" >> "$DEFCONFIG_FILE"
else
  echo "CONFIG_HEADERS_INSTALL=n" >> "$DEFCONFIG_FILE"
fi

# 应用 CVE_2026_43499 修复补丁（新版内核源码已应用补丁，无需再应用）
# cd common
# wget https://github.com/cctv18/oppo_oplus_realme_sm8850/raw/refs/heads/main/other_patch/cve-2026-43499-rtmutex-6.12.patch
# patch -p1 -F 3 < cve-2026-43499-rtmutex-6.12.patch
# cd ..

# 6.12内核Rust配置
echo "CONFIG_RUST=y" >> ./common/arch/arm64/configs/gki_defconfig
echo "CONFIG_ANDROID_BINDER_IPC_RUST=m" >> ./common/arch/arm64/configs/gki_defconfig

# 仅在启用了 LZ4KD 补丁时添加相关算法支持
if [[ "$APPLY_LZ4KD" == "y" || "$APPLY_LZ4KD" == "Y" ]]; then
  cat >> "$DEFCONFIG_FILE" <<EOF
CONFIG_ZSMALLOC=y
CONFIG_CRYPTO_LZ4HC=y
CONFIG_CRYPTO_LZ4K=y
CONFIG_CRYPTO_LZ4KD=y
CONFIG_CRYPTO_842=y
CONFIG_ZRAM_BACKEND_LZ4HC=y
CONFIG_ZRAM_BACKEND_LZ4K=y
CONFIG_ZRAM_BACKEND_LZ4KD=y
CONFIG_ZRAM_BACKEND_842=y
EOF

fi

# ===== 启用网络功能增强优化配置 =====
if [[ "$APPLY_BETTERNET" == "y" || "$APPLY_BETTERNET" == "Y" ]]; then
  echo ">>> 正在启用网络功能增强优化配置..."
  echo "CONFIG_NETFILTER_XT_MATCH_ADDRTYPE=y" >> "$DEFCONFIG_FILE"
  echo "CONFIG_NETFILTER_XT_SET=y" >> "$DEFCONFIG_FILE"
  echo "CONFIG_IP_SET=y" >> "$DEFCONFIG_FILE"
  echo "CONFIG_IP_SET_MAX=65534" >> "$DEFCONFIG_FILE"
  echo "CONFIG_IP_SET_BITMAP_IP=y" >> "$DEFCONFIG_FILE"
  echo "CONFIG_IP_SET_BITMAP_IPMAC=y" >> "$DEFCONFIG_FILE"
  echo "CONFIG_IP_SET_BITMAP_PORT=y" >> "$DEFCONFIG_FILE"
  echo "CONFIG_IP_SET_HASH_IP=y" >> "$DEFCONFIG_FILE"
  echo "CONFIG_IP_SET_HASH_IPMARK=y" >> "$DEFCONFIG_FILE"
  echo "CONFIG_IP_SET_HASH_IPPORT=y" >> "$DEFCONFIG_FILE"
  echo "CONFIG_IP_SET_HASH_IPPORTIP=y" >> "$DEFCONFIG_FILE"
  echo "CONFIG_IP_SET_HASH_IPPORTNET=y" >> "$DEFCONFIG_FILE"
  echo "CONFIG_IP_SET_HASH_IPMAC=y" >> "$DEFCONFIG_FILE"
  echo "CONFIG_IP_SET_HASH_MAC=y" >> "$DEFCONFIG_FILE"
  echo "CONFIG_IP_SET_HASH_NETPORTNET=y" >> "$DEFCONFIG_FILE"
  echo "CONFIG_IP_SET_HASH_NET=y" >> "$DEFCONFIG_FILE"
  echo "CONFIG_IP_SET_HASH_NETNET=y" >> "$DEFCONFIG_FILE"
  echo "CONFIG_IP_SET_HASH_NETPORT=y" >> "$DEFCONFIG_FILE"
  echo "CONFIG_IP_SET_HASH_NETIFACE=y" >> "$DEFCONFIG_FILE"
  echo "CONFIG_IP_SET_LIST_SET=y" >> "$DEFCONFIG_FILE"
  echo "CONFIG_IP6_NF_NAT=y" >> "$DEFCONFIG_FILE"
  echo "CONFIG_IP6_NF_TARGET_MASQUERADE=y" >> "$DEFCONFIG_FILE"
  #由于部分机型的vintf兼容性检测规则，在开启CONFIG_IP6_NF_NAT后开机会出现"您的设备内部出现了问题。请联系您的设备制造商了解详情。"的提示，故添加一个配置修复补丁，在编译内核时隐藏CONFIG_IP6_NF_NAT=y但不影响对应功能编译
  cd common
  wget https://github.com/cctv18/oppo_oplus_realme_sm8850/raw/refs/heads/main/other_patch/config.patch
  patch -p1 -F 3 < config.patch || true
  cd ..
fi

# ===== 添加 BBR 等一系列拥塞控制算法 =====
if [[ "$APPLY_BBR" == "y" || "$APPLY_BBR" == "Y" || "$APPLY_BBR" == "d" || "$APPLY_BBR" == "D" ]]; then
  echo ">>> 正在添加 BBR 等一系列拥塞控制算法..."
  echo "CONFIG_TCP_CONG_ADVANCED=y" >> "$DEFCONFIG_FILE"
  echo "CONFIG_TCP_CONG_BBR=y" >> "$DEFCONFIG_FILE"
  echo "CONFIG_TCP_CONG_CUBIC=y" >> "$DEFCONFIG_FILE"
  echo "CONFIG_TCP_CONG_VEGAS=y" >> "$DEFCONFIG_FILE"
  echo "CONFIG_TCP_CONG_NV=y" >> "$DEFCONFIG_FILE"
  echo "CONFIG_TCP_CONG_WESTWOOD=y" >> "$DEFCONFIG_FILE"
  echo "CONFIG_TCP_CONG_HTCP=y" >> "$DEFCONFIG_FILE"
  echo "CONFIG_TCP_CONG_BRUTAL=y" >> "$DEFCONFIG_FILE"
  if [[ "$APPLY_BBR" == "d" || "$APPLY_BBR" == "D" ]]; then
    echo "CONFIG_DEFAULT_TCP_CONG=bbr" >> "$DEFCONFIG_FILE"
  else
    echo "CONFIG_DEFAULT_TCP_CONG=cubic" >> "$DEFCONFIG_FILE"
  fi
fi

# ===== 启用 Droidspaces 容器支持 =====
if [[ "$APPLY_DROIDSPACES" == [sSeE] ]]; then
  echo ">>> 正在添加 Droidspaces 容器支持..."
  # 开启 Droidspaces 容器所需内核支持
  echo "CONFIG_PID_NS=y" >> "$DEFCONFIG_FILE"
  echo "CONFIG_IPC_NS=y" >> "$DEFCONFIG_FILE"
  echo "CONFIG_USER_NS=y" >> "$DEFCONFIG_FILE"
  echo "CONFIG_SYSVIPC=y" >> "$DEFCONFIG_FILE"
  echo "CONFIG_DEVTMPFS=y" >> "$DEFCONFIG_FILE"
  echo "CONFIG_NAMESPACES=y" >> "$DEFCONFIG_FILE"
  echo "CONFIG_POSIX_MQUEUE=y" >> "$DEFCONFIG_FILE"
  echo "CONFIG_NETFILTER_XT_MATCH_ADDRTYPE=y" >> "$DEFCONFIG_FILE"
  echo "CONFIG_NETFILTER_XT_TARGET_LOG=y" >> "$DEFCONFIG_FILE"
  echo "CONFIG_NETFILTER_XT_MATCH_RECENT=y" >> "$DEFCONFIG_FILE"
  # 开启 NTSync
  echo "CONFIG_NTSYNC=y" >> "$DEFCONFIG_FILE"
  cd common
  # 应用 Droidspaces 容器必须补丁
  wget https://github.com/cctv18/oppo_oplus_realme_sm8850/raw/refs/heads/main/droidspaces_patch/fix_sysvipc_kabi_a16-6.12.patch
  patch -p1 -F 3 < fix_sysvipc_kabi_a16-6.12.patch || true
  # 修补 oplus_bsp_midas 行为，避免开机崩溃
  wget https://github.com/cctv18/oppo_oplus_realme_sm8850/raw/refs/heads/main/droidspaces_patch/fix_oplus_bsp_midas.patch
  patch -p1 -F 3 < fix_oplus_bsp_midas.patch || true
  # 应用 NTSync 补丁
  wget https://github.com/cctv18/oppo_oplus_realme_sm8850/raw/refs/heads/main/droidspaces_patch/ntsync_compat_android16-6.12.patch
  patch -p1 -F 3 < ntsync_compat_android16-6.12.patch || true
  cd ..
  if [[ "$APPLY_DROIDSPACES" == [eE] ]]; then
    echo "正在启用容器环境扩展支持..."
    # 开启虚拟 HCI 设备支持
    echo "CONFIG_BT_HCIVHCI=y" >> "$DEFCONFIG_FILE"
    # 开启 systemd-coredump 支持
    echo "CONFIG_STATIC_USERMODEHELPER=n" >> "$DEFCONFIG_FILE"
    # 添加 Lindroid EVDI DRM 驱动
    # echo "CONFIG_DRM_LINDROID_EVDI=y" >> "$DEFCONFIG_FILE"
    # cd common
    # wget https://github.com/cctv18/oppo_oplus_realme_sm8850/raw/refs/heads/main/droidspaces_patch/evdi_drm.patch
    # patch -p1 -F 3 < evdi_drm.patch || true
    # cd ..
  fi
fi

# ===== 启用ADIOS调度器 =====
if [[ "$APPLY_ADIOS" == "y" || "$APPLY_ADIOS" == "Y" ]]; then
  echo ">>> 正在启用ADIOS调度器..."
  echo "CONFIG_MQ_IOSCHED_ADIOS=y" >> "$DEFCONFIG_FILE"
  echo "CONFIG_MQ_IOSCHED_DEFAULT_ADIOS=y" >> "$DEFCONFIG_FILE"
fi

# ===== 启用Re-Kernel =====
if [[ "$APPLY_REKERNEL" == "y" || "$APPLY_REKERNEL" == "Y" ]]; then
  echo ">>> 正在启用Re-Kernel..."
  echo "CONFIG_REKERNEL=y" >> "$DEFCONFIG_FILE"
  echo "CONFIG_REKERNEL_NETWORK=y" >> "$DEFCONFIG_FILE"
fi

# ===== 启用内核级基带保护 =====
if [[ "$APPLY_BBG" == "y" || "$APPLY_BBG" == "Y" ]]; then
  echo ">>> 正在启用内核级基带保护..."
  echo "CONFIG_BBG=y" >> "$DEFCONFIG_FILE"
  cd ./common
  curl -sSL https://github.com/cctv18/Baseband-guard/raw/master/setup.sh | bash
  sed -i '/^config LSM$/,/^help$/{ /^[[:space:]]*default/ { /baseband_guard/! s/selinux/selinux,baseband_guard/ } }' security/Kconfig
  cd ..
fi

# ===== 禁用 defconfig 检查 =====
echo ">>> 禁用 defconfig 检查..."
sed -i 's/check_defconfig//' ./common/build.config.gki

# Kbuild 用 $(srctree)/$(src) 推导 KSU_KERNEL_DIR，在 O=out + 外置软链的布局下会错一层
# （表现为 klog.h / uapi 头找不到、preinit/runner/runner.c 找不到），这里用绝对路径覆盖
if [[ -d ./KernelSU/kernel ]]; then
  KSU_MAKE_ARGS="KSU_KERNEL_DIR=$(cd ./KernelSU/kernel && pwd) $KSU_MAKE_ARGS"
elif [[ -d ./KernelSU-Next/kernel ]]; then
  KSU_MAKE_ARGS="KSU_KERNEL_DIR=$(cd ./KernelSU-Next/kernel && pwd) $KSU_MAKE_ARGS"
fi

# ===== 编译内核 =====
echo ">>> 开始编译内核..."
WORKDIR="$(pwd)"
export PATH="$WORKDIR/clang19/bin:$PATH"
export PATH="$WORKDIR/build-tools/bin:$PATH"
export PATH="$WORKDIR/rust/bin:$PATH"
CLANG_DIR="$WORKDIR/clang19/bin"
CLANG_VERSION="$($CLANG_DIR/clang --version | head -n 1)"
LLD_VERSION="$($CLANG_DIR/ld.lld --version | head -n 1)"
RUSTC_VERSION="$(rustc -V 2>/dev/null | head -n1)"
BINDGEN_VERSION="$(bindgen --version 2>/dev/null | head -n1)"
export CC="$CLANG_DIR/clang"
export HOSTCC="$CLANG_DIR/clang"
export RUSTC="rustc"
export BINDGEN="bindgen"
export LIBCLANG_PATH="$WORKDIR/clang19/lib"
export LLVM=1 LLVM_IAS=1
export ARCH=arm64 SUBARCH=arm64
export CROSS_COMPILE=aarch64-linux-gnu-
export LD=ld.lld HOSTLD=ld.lld AR=llvm-ar NM=llvm-nm AS=clang READELF=llvm-readelf
export OBJCOPY=llvm-objcopy OBJDUMP=llvm-objdump OBJSIZE=llvm-size STRIP=llvm-strip
KCFLAGS+=" -no-canonical-prefixes"
KCFLAGS+=" -O2"
KCFLAGS+=" -pipe"
KCFLAGS+=" -Wno-error"
KCFLAGS+=" -fno-stack-protector"
KCFLAGS+=" -D__ANDROID_COMMON_KERNEL__"
export KCFLAGS
echo "编译器信息:"
echo "Clang版本: $CLANG_VERSION"
echo "LLD版本: $LLD_VERSION"
echo "Rustc版本: $RUSTC_VERSION"
echo "Bindgen版本: $BINDGEN_VERSION"
pahole_version=$(pahole --version 2>/dev/null | head -n1); [ -z "$pahole_version" ] && echo "pahole版本：未安装" || echo "pahole版本：$pahole_version"

cd common

COMMON_REAL_PATH=$(pwd -P)
ROOT_REAL_PATH=$(dirname "$COMMON_REAL_PATH")
KCFLAGS+=" -fdebug-prefix-map=$ROOT_REAL_PATH=."
KCFLAGS+=" -fmacro-prefix-map=$ROOT_REAL_PATH=."
KCFLAGS+=" -ffile-prefix-map=$ROOT_REAL_PATH=."
export KCFLAGS
source "./_setup_env.sh" 2>/dev/null || true
echo "KCFLAGS=$KCFLAGS"

make -j$(nproc --all) \
    LLVM=1 \
    ARCH=arm64 \
    CROSS_COMPILE=aarch64-linux-gnu- \
    CC="$CLANG_DIR/clang" \
    HOSTCC="$CLANG_DIR/clang" \
    LD=ld.lld \
    HOSTLD=ld.lld \
    RUSTC="rustc" \
    OBJCOPY="llvm-objcopy" \
    O=out \
    $KSU_MAKE_ARGS \
    gki_defconfig Image 2>&1 | tee $WORKDIR/build.log
echo ">>> 内核编译成功！"

# ===== 选择使用 patch_linux (KPM补丁)=====
WORKDIR="$SCRIPT_DIR"
OUT_DIR="$WORKDIR/kernel_workspace/common/out/arch/arm64/boot"
if [[ "$USE_PATCH_LINUX" == [yY] ]]; then
  echo ">>> 使用 kptools-linux 工具处理输出..."
  cd "$OUT_DIR"
  wget https://github.com/KernelSU-Next/KPatch-Next/releases/latest/download/kptools-linux
  wget https://github.com/KernelSU-Next/KPatch-Next/releases/latest/download/kpimg-linux
  chmod +x ./kptools-linux
  ./kptools-linux -p -i ./Image -k ./kpimg-linux -o ./oImage
  rm -f Image
  mv oImage Image
  echo ">>> 已成功打上KP-N补丁!"
fi

# ===== 克隆并打包 AnyKernel3 =====
cd "$WORKDIR/kernel_workspace"
echo ">>> 克隆 AnyKernel3 项目..."
git clone https://github.com/cctv18/AnyKernel3 --depth=1

echo ">>> 清理 AnyKernel3 Git 信息..."
rm -rf ./AnyKernel3/.git

echo ">>> 拷贝内核镜像到 AnyKernel3 目录..."
cp "$OUT_DIR/Image" ./AnyKernel3/

echo ">>> 进入 AnyKernel3 目录并打包 zip..."
cd "$WORKDIR/kernel_workspace/AnyKernel3"

# ===== 如果启用 lz4kd，则下载 zram.zip 并放入当前目录 =====
if [[ "$APPLY_LZ4KD" == "y" || "$APPLY_LZ4KD" == "Y" ]]; then
  wget https://raw.githubusercontent.com/cctv18/oppo_oplus_realme_sm8850/refs/heads/main/zram.zip
fi

if [[ "$USE_PATCH_LINUX" == [yY] ]]; then
  wget https://github.com/cctv18/KPatch-Next/releases/latest/download/kpn.zip
fi

# ===== 生成 ZIP 文件名 =====
ZIP_NAME="Anykernel3-${MANIFEST}"

if [[ "$APPLY_SUSFS" == "y" || "$APPLY_SUSFS" == "Y" ]]; then
  ZIP_NAME="${ZIP_NAME}-susfs"
fi
if [[ "$APPLY_LZ4KD" == "y" || "$APPLY_LZ4KD" == "Y" ]]; then
  ZIP_NAME="${ZIP_NAME}-lz4kd"
fi
if [[ "$APPLY_LZ4" == "y" || "$APPLY_LZ4" == "Y" ]]; then
  ZIP_NAME="${ZIP_NAME}-lz4-zstd"
fi
if [[ "$USE_PATCH_LINUX" == [yY] ]]; then
  ZIP_NAME="${ZIP_NAME}-kpm"
fi
if [[ "$APPLY_BBR" == "y" || "$APPLY_BBR" == "Y" ]]; then
  ZIP_NAME="${ZIP_NAME}-bbr"
fi
if [[ "$APPLY_DROIDSPACES" == [sSeE] ]]; then
  ZIP_NAME="${ZIP_NAME}-dss"
fi
if [[ "$APPLY_ADIOS" == "y" || "$APPLY_ADIOS" == "Y" ]]; then
  ZIP_NAME="${ZIP_NAME}-adios"
fi
if [[ "$APPLY_REKERNEL" == "y" || "$APPLY_REKERNEL" == "Y" ]]; then
  ZIP_NAME="${ZIP_NAME}-rek"
fi
if [[ "$APPLY_BBG" == "y" || "$APPLY_BBG" == "Y" ]]; then
  ZIP_NAME="${ZIP_NAME}-bbg"
fi

# 非默认 KSU 分支时在包名中带上分支标识（斜杠替换为连字符，避免影响路径）
if [[ -n "$KSU_SRC_BRANCH" && "$KSU_SRC_BRANCH" != "$KSU_DEFAULT_BRANCH" ]]; then
  ZIP_NAME="${ZIP_NAME}-${KSU_SRC_BRANCH//\//-}"
fi

ZIP_NAME="${ZIP_NAME}-v$(date +%Y%m%d).zip"

# ===== 打包 ZIP 文件，包括 zram.zip（如果存在） =====
echo ">>> 打包文件: $ZIP_NAME"
zip -r "../$ZIP_NAME" ./*

ZIP_PATH="$(realpath "../$ZIP_NAME")"
echo ">>> 打包完成 文件所在目录: $ZIP_PATH"
