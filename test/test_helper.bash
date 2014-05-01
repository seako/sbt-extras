export TEST_ROOT="$BATS_TMPDIR/$(basename "$BATS_TEST_FILENAME").$$" && mkdir -p "$TEST_ROOT"
export TEST_BIN="$TEST_ROOT/bin"
export HOME="$TEST_ROOT" # todo - eliminate
export PATH="$BATS_TEST_DIRNAME/../bin:$TEST_BIN:/usr/bin:/usr/sbin:/bin:/sbin"

# echo >&2 "TEST_ROOT=$TEST_ROOT $(ls -1 $TEST_ROOT/bin)"

unset JAVA_HOME JVM_OPTS SBT_OPTS

export sbt_latest_07="0.7.7"
export sbt_latest_10="0.10.1"
export sbt_latest_11="0.11.3"
export sbt_latest_12="0.12.4"
export sbt_latest_13="0.13.2"
export sbt_latest_dev="0.13.5-M4"
export sbt_release_version="$sbt_latest_13"

write_version_to_properties () { echo "sbt.version=$1" > "$test_build_properties"; }

sbt_version_from_test_filename () {
  case "$BATS_TEST_FILENAME" in
    *-0.13.bats) echo $sbt_latest_13 ;;
    *-0.12.bats) echo $sbt_latest_12 ;;
    *-0.11.bats) echo $sbt_latest_11 ;;
    *-0.10.bats) echo $sbt_latest_10 ;;
     *-0.7.bats) echo $sbt_latest_07 ;;
              *) echo $sbt_release_version ;;
  esac
}

setup () { sbt_test_setup; }
sbt_test_setup () {
  export sbt_test_version="$(sbt_version_from_test_filename)"
  create_project_with_launcher "$sbt_test_version"
  write_version_to_properties "$sbt_test_version"
}

teardown () { [[ -d "$TEST_ROOT" ]] && rm -rf -- "$TEST_ROOT"; }

# Usage: f <string which should be in output> [args to sbt]
sbt_expecting () { sbt_anticipating expect "$@"; }
# Usage: f <string which must not be in output> [args to sbt]
sbt_rejecting () { sbt_anticipating reject "$@"; }

sbt_anticipating () {
  case "$1" in
    expect) grep_opts="-F" && shift ;;
    reject) grep_opts="-Fv" && shift ;;
         *) return 1
  esac

  local text="$1" && shift
  stub_java
  run sbt "$@"
  assert_success
  assert_grep "$text" "$grep_opts"
  unstub java
}

create_project_with_launcher() {
  local version="${1:-$sbt_release_version}"
  create_project $version
  create_launcher $version
}

create_project() {
  export sbt_project="$TEST_ROOT/myproject"
  local pdir="$sbt_project/project"
  export test_build_properties="$pdir/build.properties"
  mkdir -p "$pdir" && cd "$sbt_project"
}

create_launcher() { mkdir_and_touch "$TEST_ROOT/.sbt/launchers/$1/sbt-launch.jar"; }

stub() {
  local program="$1" && shift
  local prefix="$(echo "$program" | tr a-z- A-Z_)"
  local stubPlan="$TEST_ROOT/$program-stub-plan"
  local stubRun="$TEST_ROOT/$program-stub-run"

  export "${prefix}_STUB_PLAN"="$stubPlan"
  export "${prefix}_STUB_RUN"="$stubRun"
  export "${prefix}_STUB_END"=""

  mkdir -p "$TEST_BIN" && ln -sf "$BATS_TEST_DIRNAME/stubs/stub" "$TEST_BIN/$program"
  touch "$stubPlan" && printf "%s\n" "$@" >> "$stubPlan"
}

unstub() {
  local program="$1"
  local prefix="$(echo "$program" | tr a-z- A-Z_)"
  local path="$TEST_BIN/$program"
  local STATUS=0

  export "${prefix}_STUB_END"=1
  "$path" || STATUS="$?"

  rm -f "$path" "$TEST_ROOT/${program}-stub-plan" "$TEST_ROOT/${program}-stub-run"
  return "$STATUS"
}

assert_success() {
  [ $status -ne 0 ] && printf "command failed with exit status $status\noutput: $output\n" | flunk
  [[ $# -eq 0 ]] || assert_output "$1"
}

assert_failure() {
  [ $status -eq 0 ] && printf "expected failure" | flunk
  [[ $# -eq 0 ]] || assert_output "$1"
}

stdin_or_args () { if [[ $# -eq 0 ]]; then cat - ; else echo "$@"; fi; }
normalize_paths () {
  stdin_or_args "$@" | \
    sed "s:$TEST_ROOT:\$ROOT:g" | \
    sed "s:$HOME:\$ROOT:g"
}

mkdir_and_touch () { mkdir -p "$(dirname "$1")" && touch "$1"; }
mkdircd () { mkdir -p "$1" && cd "$1"; }

assert()        { "$@" || flunk "failed: $@"; }
flunk()         { normalize_paths "$@" ; return 1; }
assert_equal()  { [ "$1" == "$2" ] || printf "expected: %s\nactual:   %s\n" "$1" "$2" | flunk; }
assert_output() { assert_equal "${1:-$(cat -)}" "$output"; }
flunk_message() { printf "expected: %s\nactual:   %s\n" "$1" "$2"; return 1; }

assert_grep() {
  local expected="$1" && shift

  grep "$@" -- "$expected" <<<"$output" >/dev/null || flunk_message "$expected" "$output"
}

stub_java () {
  stub java 'for arg; do echo "$arg"; done'
}
