#!/usr/bin/env bash
set -euo pipefail

REPO="tsosunchia/iNetSpeed-CLI"
BINARY="speedtest"
RELEASE_BASE="https://github.com/${REPO}/releases/latest/download"
RELEASES_URL="https://github.com/${REPO}/releases/latest"

log() {
  local zh="$1"
  local en="$2"
  printf '==> %s / %s\n' "$zh" "$en"
}

warn() {
  local zh="$1"
  local en="$2"
  printf 'Warning: %s / %s\n' "$zh" "$en" >&2
}

die() {
  local zh="$1"
  local en="$2"
  printf 'Error: %s / %s\n' "$zh" "$en" >&2
  exit 1
}

has_cmd() {
  command -v "$1" >/dev/null 2>&1
}

read_input() {
  local __var_name="$1"
  local prompt_zh="$2"
  local prompt_en="$3"
  local answer

  printf '%s / %s ' "$prompt_zh" "$prompt_en" >&2
  if [[ -r /dev/tty ]]; then
    IFS= read -r answer < /dev/tty || return 1
  else
    IFS= read -r answer || return 1
  fi
  printf -v "$__var_name" '%s' "$answer"
  return 0
}

ask_yes_no() {
  local prompt_zh="$1"
  local prompt_en="$2"
  local default="${3:-n}"
  local prompt_suffix reply

  case "$default" in
    y|Y) prompt_suffix='[Y/n]' ;;
    n|N) prompt_suffix='[y/N]' ;;
    *) prompt_suffix='[y/n]' ;;
  esac

  while true; do
    if ! read_input reply "${prompt_zh} ${prompt_suffix}" "${prompt_en} ${prompt_suffix}"; then
      return 1
    fi

    reply="${reply#"${reply%%[![:space:]]*}"}"
    reply="${reply%"${reply##*[![:space:]]}"}"
    if [[ -z "$reply" ]]; then
      reply="$default"
    fi

    case "$reply" in
      y|Y|yes|YES|Yes|是|好|覆盖) return 0 ;;
      n|N|no|NO|No|否|不要|不覆盖) return 1 ;;
      *)
        warn "请输入 y 或 n。" "Please enter y or n."
        ;;
    esac
  done
}

download() {
  local url="$1"
  local output="$2"

  if has_cmd curl; then
    curl -fL --retry 3 --connect-timeout 10 -o "$output" "$url"
    return
  fi

  if has_cmd wget; then
    wget -qO "$output" "$url"
    return
  fi

  die "需要安装 curl 或 wget。" "curl or wget is required."
}

detect_platform() {
  local os arch
  os="$(uname -s)"
  arch="$(uname -m)"

  case "$os" in
    Linux) os="linux" ;;
    Darwin)
      die "该安装脚本不支持 macOS，请从这里下载：${RELEASES_URL}" "macOS is not supported by this installer. Please download from: ${RELEASES_URL}"
      ;;
    MINGW*|MSYS*|CYGWIN*|Windows_NT*)
      die "该安装脚本不支持 Windows，请从这里下载：${RELEASES_URL}" "Windows is not supported by this installer. Please download from: ${RELEASES_URL}"
      ;;
    *)
      die "不支持的操作系统：${os}。该安装脚本仅支持 Linux。二进制下载：${RELEASES_URL}" "unsupported OS: ${os}. This installer only supports Linux. Binaries: ${RELEASES_URL}"
      ;;
  esac

  case "$arch" in
    x86_64|amd64) arch="amd64" ;;
    arm64|aarch64) arch="arm64" ;;
    *)
      die "不支持的架构：${arch}。支持：amd64/arm64。" "unsupported architecture: ${arch}. Supported: amd64/arm64."
      ;;
  esac

  printf '%s/%s\n' "$os" "$arch"
}

choose_install_dir() {
  if [[ -n "${INSTALL_DIR:-}" ]]; then
    printf '%s\n' "${INSTALL_DIR}"
    return
  fi

  if [[ "$(id -u)" -eq 0 ]]; then
    printf '%s\n' "/usr/local/bin"
    return
  fi

  printf '%s\n' "${HOME}/.local/bin"
}

path_has_dir() {
  local target="$1"
  local item
  IFS=':' read -r -a path_dirs <<< "${PATH:-}"
  for item in "${path_dirs[@]}"; do
    [[ "$item" == "$target" ]] && return 0
  done
  return 1
}

verify_checksum() {
  local file="$1"
  local checksum_file="$2"
  local asset="$3"
  local expected actual

  expected="$(awk -v asset="$asset" '$2 == asset { print $1; exit }' "$checksum_file")"
  [[ -n "$expected" ]] || die "在 checksums-sha256.txt 中未找到 ${asset} 的校验值。" "checksum for ${asset} not found in checksums-sha256.txt."

  if has_cmd sha256sum; then
    actual="$(sha256sum "$file" | awk '{print $1}')"
  elif has_cmd shasum; then
    actual="$(shasum -a 256 "$file" | awk '{print $1}')"
  else
    die "校验需要 sha256sum 或 shasum。" "sha256sum or shasum is required for checksum verification."
  fi

  [[ "$actual" == "$expected" ]] || die "${asset} 的校验失败。" "checksum mismatch for ${asset}."
}

main() {
  local platform os arch asset tmp_dir bin_path sum_path install_dir target trap_cmd run_hint new_install_dir
  platform="$(detect_platform)"
  os="${platform%/*}"
  arch="${platform#*/}"
  asset="${BINARY}-${os}-${arch}"

  tmp_dir="$(mktemp -d)"
  trap_cmd="$(printf 'rm -rf -- %q' "$tmp_dir")"
  trap "$trap_cmd" EXIT
  bin_path="${tmp_dir}/${asset}"
  sum_path="${tmp_dir}/checksums-sha256.txt"

  log "正在从最新发布下载 ${asset}" "Downloading ${asset} from latest release"
  download "${RELEASE_BASE}/${asset}" "$bin_path"

  log "正在下载校验文件" "Downloading checksums"
  download "${RELEASE_BASE}/checksums-sha256.txt" "$sum_path"

  log "正在校验文件完整性" "Verifying checksum"
  verify_checksum "$bin_path" "$sum_path" "$asset"

  install_dir="$(choose_install_dir)"
  install_dir="${install_dir%/}"
  if [[ -z "$install_dir" ]]; then
    die "安装目录为空。" "install dir resolved to empty."
  fi
  if ! path_has_dir "$install_dir"; then
    warn "安装目录不在 PATH 中：${install_dir}" "install dir not in PATH: ${install_dir}"
    warn "将回退到当前目录：${PWD}" "falling back to current directory: ${PWD}"
    install_dir="$PWD"
  fi

  mkdir -p "$install_dir"
  [[ -w "$install_dir" ]] || die "安装目录不可写：${install_dir}" "install dir is not writable: ${install_dir}"

  target="${install_dir}/${BINARY}"
  while [[ -e "$target" ]]; do
    warn "目标文件已存在：${target}" "Target file already exists: ${target}"
    if ask_yes_no "是否覆盖安装？" "Overwrite existing file?" "n"; then
      break
    fi

    if ask_yes_no "是否安装到其他路径？" "Install to another path?" "y"; then
      if ! read_input new_install_dir "请输入新的安装目录：" "Enter a new install directory:"; then
        die "无法读取输入，安装中止。" "Failed to read input. Installation aborted."
      fi
      new_install_dir="${new_install_dir%/}"
      if [[ -z "$new_install_dir" ]]; then
        warn "安装目录不能为空，请重试。" "Install directory cannot be empty. Please try again."
        continue
      fi
      mkdir -p "$new_install_dir"
      if [[ ! -w "$new_install_dir" ]]; then
        warn "目录不可写：${new_install_dir}" "Directory is not writable: ${new_install_dir}"
        continue
      fi
      if ! path_has_dir "$new_install_dir"; then
        warn "新目录不在 PATH 中：${new_install_dir}" "New directory is not in PATH: ${new_install_dir}"
      fi
      install_dir="$new_install_dir"
      target="${install_dir}/${BINARY}"
      continue
    fi

    die "用户取消安装。" "Installation cancelled by user."
  done

  if has_cmd install; then
    install "$bin_path" "$target"
  else
    cp "$bin_path" "$target"
  fi
  chmod +x "$target"

  log "安装完成：${target}" "Installed to ${target}"
  if [[ "$install_dir" == "$PWD" ]]; then
    run_hint="./${BINARY}"
  else
    run_hint="${BINARY}"
  fi
  log "运行命令：${run_hint}" "Run with: ${run_hint}"

  log "正在检查版本信息" "Checking version output"
  if "$target" --version >/dev/null 2>&1; then
    "$target" --version
  fi
}

main "$@"
