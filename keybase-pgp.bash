# Some code comes from:
# https://github.com/mbauhardt/pass-keybase
# https://www.passwordstore.org/

cmd_version() {
  echo 'v0.1'
}

cmd_description() {
  cat << _EOF
================================================
= pass-keybase-pgp: Use keybase cli to do pgp  =
=                                              =
=                  v0.1                        =
=                                              =
=                                              =
=  https://github.com/jecxjo/pass-keybase-pgp  =
================================================
_EOF
}

cmd_help() {
  cmd_description
  echo
  cat << _EOF
Usage:
  pass keybase-pgp help
    Show this help text
  pass keybase-pgp version
    Show the version
  pass keybase-pgp decrypt pass-name
    Decrypt the given pass-name with keybase.
  pass keybase-pgp encrypt pass-name
    Create a new password.
  pass keybase-pgp edit pass-name
    Edit an existing password.
_EOF
}

cmd_decrypt() {
  local path="$1"
  local passfile="$PREFIX/$path.gpg"
  check_sneaky_paths "$path"

  if [[ -f $passfile ]]; then
    keybase pgp decrypt -i "$passfile" 
  elif [[ -z $path ]]; then
    die ""
  else
    die "Error: $path is not in the password store."
  fi
}

cmd_encrypt() {
  local opts multiline=0 noecho=1 force=0
  opts="$($GETOPT -o mef -l multiline,echo,force -n "$PROGRAM" -- "$@")"
  local err=$?
  eval set -- "$opts"
  while true; do case $1 in
    -m|--multiline) multiline=1; shift ;;
    -e|--echo) noecho=0; shift ;;
    -f|--force) force=1; shift ;;
    --) shift; break ;;
  esac done

  [[ $err -ne 0 || ( $multiline -eq 1 && $noecho -eq 0 ) || $# -ne 1 ]] && die "Usage: $PROGRAM $COMMAND [--echo,-e | --multiline,-m] [--force,-f] pass-name"
  local path="${1%/}"
  local passfile="$PREFIX/$path.gpg"
  check_sneaky_paths "$path"
  set_git "$passfile"

  [[ $force -eq 0 && -e $passfile ]] && yesno "An entry already exists for $path. Overwrite it?"

  mkdir -p -v "$PREFIX/$(dirname -- "$path")"
  #set_gpg_recipients "$(dirname -- "$path")"

  if [[ $multiline -eq 1 ]]; then
    echo "Enter contents of $path and press Ctrl+D when finished:"
    echo
    keybase pgp encrypt -b -o "$passfile" || die "Password encryption aborted."
  elif [[ $noecho -eq 1 ]]; then
    local password password_again
    while true; do
      read -r -p "Enter password for $path: " -s password || exit 1
      echo
      read -r -p "Retype password for $path: " -s password_again || exit 1
      echo
      if [[ $password == "$password_again" ]]; then
         keybase pgp encrypt -b -o "$passfile" -m "$password"  || die "Password encryption aborted."
        break
      else
        die "Error: the entered passwords do not match."
      fi
    done
  else
    local password
    read -r -p "Enter password for $path: " -e password
    keybase pgp encrypt -b -o "$passfile" -m "$password" || die "Password encryption aborted."
  fi
  git_add_file "$passfile" "Add given password for $path to store."
}

cmd_edit() {
  [[ $# -ne 1 ]] && die "Usage: $PROGRAM $COMMAND pass-name"

  local path="${1%/}"
  check_sneaky_paths "$path"
  mkdir -p -v "$PREFIX/$(dirname -- "$path")"
  #set_gpg_recipients "$(dirname -- "$path")"
  local passfile="$PREFIX/$path.gpg"
  set_git "$passfile"

  tmpdir #Defines $SECURE_TMPDIR
  local tmp_file="$(mktemp -u "$SECURE_TMPDIR/XXXXXX")-${path//\//-}.txt"

  local action="Add"
  if [[ -f $passfile ]]; then
    keybase pgp decrypt -o "$tmp_file" -i "$passfile" || exit 1
    action="Edit"
  fi
  ${EDITOR:-vi} "$tmp_file"
  [[ -f $tmp_file ]] || die "New password not saved."
  keybase pgp decrypt -i"$passfile" 2>/dev/null | diff - "$tmp_file" &>/dev/null && die "Password unchanged."
  while ! keybase pgp encrypt -i "$tmp_file" -o "$passfile" ; do
    yesno "GPG encryption failed. Would you like to try again?"
  done
  git_add_file "$passfile" "$action password for $path using ${EDITOR:-vi}."
}

case "$1" in
  help)
    cmd_help
    ;;
  version)
    cmd_version
    ;;
  encrypt)
    shift;
    cmd_encrypt "$@"
    ;;
  decrypt)
    shift;
    cmd_decrypt "$@"
    ;;
  edit)
    shift;
    cmd_edit "$@"
    ;;
  *)
    cmd_help
    ;;
esac
exit 0
