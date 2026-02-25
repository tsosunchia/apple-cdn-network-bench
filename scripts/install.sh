#!/usr/bin/env bash
set -euo pipefail

REPO="tsosunchia/apple-cdn-network-bench"
BINARY="speedtest"
RELEASE_BASE="https://github.com/${REPO}/releases/latest/download"

log() {
  printf '==> %s\n' "$*"
}

warn() {
  printf 'Warning: %s\n' "$*" >&2
}

die() {
  printf 'Error: %s\n' "$*" >&2
  exit 1
}

has_cmd() {
  command -v "$1" >/dev/null 2>&1
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

  die "curl or wget is required"
}

detect_platform() {
  local os arch
  os="$(uname -s)"
  arch="$(uname -m)"

  case "$os" in
    Linux) os="linux" ;;
    Darwin) os="darwin" ;;
    *)
      die "unsupported OS: ${os}. This installer only supports Linux/macOS."
      ;;
  esac

  case "$arch" in
    x86_64|amd64) arch="amd64" ;;
    arm64|aarch64) arch="arm64" ;;
    *)
      die "unsupported architecture: ${arch}. Supported: amd64/arm64."
      ;;
  esac

  printf '%s/%s\n' "$os" "$arch"
}

choose_install_dir() {
  if [[ -n "${INSTALL_DIR:-}" ]]; then
    printf '%s\n' "${INSTALL_DIR}"
    return
  fi

  local dir
  IFS=':' read -r -a path_dirs <<< "${PATH:-}"
  for dir in "${path_dirs[@]}"; do
    [[ -n "$dir" ]] || continue
    case "$dir" in
      "$HOME"/*)
        if [[ -d "$dir" && -w "$dir" ]]; then
          printf '%s\n' "$dir"
          return
        fi
        ;;
    esac
  done

  printf '%s\n' "$HOME/.local/bin"
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

profile_file_for_shell() {
  local shell_name
  shell_name="$(basename "${SHELL:-}")"
  case "$shell_name" in
    zsh) printf '%s\n' "$HOME/.zprofile" ;;
    bash)
      if [[ "$(uname -s)" == "Darwin" ]]; then
        printf '%s\n' "$HOME/.bash_profile"
      else
        printf '%s\n' "$HOME/.bashrc"
      fi
      ;;
    *)
      printf '%s\n' "$HOME/.profile"
      ;;
  esac
}

ensure_path() {
  local install_dir="$1"
  if path_has_dir "$install_dir"; then
    return
  fi

  local profile profile_dir profile_path line
  profile="$(profile_file_for_shell)"
  profile_dir="$(dirname "$profile")"
  mkdir -p "$profile_dir"

  if [[ "$install_dir" == "$HOME/"* ]]; then
    profile_path="\$HOME/${install_dir#"$HOME/"}"
  else
    profile_path="$install_dir"
  fi
  line="export PATH=\"${profile_path}:\$PATH\""

  touch "$profile"
  if ! grep -Fq "$line" "$profile"; then
    printf '\n%s\n' "$line" >> "$profile"
    log "Added ${install_dir} to PATH in ${profile}"
    warn "run 'source ${profile}' or open a new shell to use '${BINARY}' from PATH."
  fi
}

verify_checksum() {
  local file="$1"
  local checksum_file="$2"
  local asset="$3"
  local expected actual

  expected="$(awk -v asset="$asset" '$2 == asset { print $1; exit }' "$checksum_file")"
  [[ -n "$expected" ]] || die "checksum for ${asset} not found in checksums-sha256.txt"

  if has_cmd sha256sum; then
    actual="$(sha256sum "$file" | awk '{print $1}')"
  elif has_cmd shasum; then
    actual="$(shasum -a 256 "$file" | awk '{print $1}')"
  else
    die "sha256sum or shasum is required for checksum verification"
  fi

  [[ "$actual" == "$expected" ]] || die "checksum mismatch for ${asset}"
}

main() {
  local platform os arch asset tmp_dir bin_path sum_path install_dir target
  platform="$(detect_platform)"
  os="${platform%/*}"
  arch="${platform#*/}"
  asset="${BINARY}-${os}-${arch}"

  tmp_dir="$(mktemp -d)"
  trap 'rm -rf "$tmp_dir"' EXIT
  bin_path="${tmp_dir}/${asset}"
  sum_path="${tmp_dir}/checksums-sha256.txt"

  log "Downloading ${asset} from latest release"
  download "${RELEASE_BASE}/${asset}" "$bin_path"

  log "Downloading checksums"
  download "${RELEASE_BASE}/checksums-sha256.txt" "$sum_path"

  log "Verifying checksum"
  verify_checksum "$bin_path" "$sum_path" "$asset"

  install_dir="$(choose_install_dir)"
  mkdir -p "$install_dir"
  [[ -w "$install_dir" ]] || die "install dir is not writable: ${install_dir}"

  target="${install_dir}/${BINARY}"
  if has_cmd install; then
    install -m 0755 "$bin_path" "$target"
  else
    cp "$bin_path" "$target"
    chmod 0755 "$target"
  fi

  ensure_path "$install_dir"

  log "Installed to ${target}"
  if "$target" --version >/dev/null 2>&1; then
    "$target" --version
  fi
}

main "$@"
