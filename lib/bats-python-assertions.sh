#!/usr/bin/env bash
# Scanner for unreadable inline Python assertions in BATS tests.

_CODEBASE_BATS_PYTHON_LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
_CODEBASE_BATS_PYTHON_RULE="$_CODEBASE_BATS_PYTHON_LIB_DIR/../rules/bats-python-assertions/inline-command.yml"
# shellcheck source=./shell-files.sh
source "$_CODEBASE_BATS_PYTHON_LIB_DIR/shell-files.sh"

bats_python_assertions_parse_targets() {
  local encoded="$1"
  local target

  [[ -n "$encoded" ]] || return 0

  while IFS= read -r target; do
    [[ -n "$target" ]] && printf '%s\n' "$target"
  done < <(printf '%s' "$encoded" | xargs printf '%s\n')
}

bats_python_assertions_has_reasoned_ignore() {
  local text="$1"
  [[ "$text" =~ codebase:ignore[[:space:]]+bats-python-assertions[[:space:]]+.+ ]]
}

bats_python_assertions_ident_char() {
  local char="$1"
  local LC_ALL=C

  [[ "$char" =~ [A-Za-z0-9_] ]] && return 0
  [[ -n "$char" ]] || return 1

  # Python identifiers may contain non-ASCII letters and combining marks.
  # Treat every non-ASCII character as identifier-like so a keyword-shaped
  # substring in a valid Unicode name does not become a lint false positive.
  # The C locale keeps the printable range byte-oriented on Bash 3.2.
  [[ "$char" == [[:cntrl:]] || "$char" == [\ -~] ]] && return 1
  return 0
}

bats_python_assertions_program_has_assert() {
  local program="$1"
  local outer=""
  local state=code quote="" triple=false
  local length i=0 char next previous after slash_count cursor
  local escaped_triple='\"\"\"'

  length=${#program}
  if [[ "$length" -ge 3 \
    && "${program:0:2}" == "\$'" \
    && "${program:$((length - 1)):1}" == "'" ]]; then
    # ast-grep preserves ANSI-C shell quoting. Decode it before applying
    # Python lexical rules so escaped newlines end Python comments correctly.
    program="${program:2:$((length - 3))}"
    printf -v program '%b' "$program"
    length=${#program}
  elif [[ "$length" -ge 2 ]]; then
    char="${program:0:1}"
    next="${program:$((length - 1)):1}"
    if [[ ( "$char" == "'" || "$char" == '"' ) && "$next" == "$char" ]]; then
      outer="$char"
      program="${program:1:$((length - 2))}"
      length=${#program}
    fi
  fi

  while [[ "$i" -lt "$length" ]]; do
    char="${program:$i:1}"

    if [[ "$state" == comment ]]; then
      if [[ "$char" == $'\n' || "$char" == $'\r' ]]; then
        state=code
      fi
      i=$((i + 1))
      continue
    fi

    if [[ "$state" == string ]]; then
      # Inside an outer shell double quote, Python quote delimiters remain
      # backslash-escaped in the source ast-grep captures. Three adjacent \"
      # sequences close a triple string. In an ordinary string, a 1 mod 4 run
      # becomes even before the Python quote and closes it; a 3 mod 4 run
      # remains an escaped quote inside the string.
      if [[ "$outer" == '"' && "$quote" == '"' && "$char" == "\\" ]]; then
        if $triple && [[ "${program:$i:6}" == "$escaped_triple" ]]; then
          state=code
          triple=false
          i=$((i + 6))
          continue
        fi
        slash_count=0
        cursor="$i"
        while [[ "$cursor" -lt "$length" && "${program:$cursor:1}" == "\\" ]]; do
          slash_count=$((slash_count + 1))
          cursor=$((cursor + 1))
        done
        if [[ "${program:$cursor:1}" == '"' ]]; then
          if ! $triple && [[ $((slash_count % 4)) -eq 1 ]]; then
            state=code
          fi
          i=$((cursor + 1))
          continue
        fi
      fi
      if [[ "$char" == "\\" ]]; then
        i=$((i + 2))
        continue
      fi
      if $triple; then
        if [[ "${program:$i:3}" == "$quote$quote$quote" ]]; then
          state=code
          triple=false
          i=$((i + 3))
          continue
        fi
      elif [[ "$char" == "$quote" ]]; then
        state=code
        i=$((i + 1))
        continue
      fi
      i=$((i + 1))
      continue
    fi

    if [[ "$char" == '#' ]]; then
      state=comment
      i=$((i + 1))
      continue
    fi

    if [[ "$char" == "'" || "$char" == '"' ]]; then
      quote="$char"
      state=string
      if [[ "${program:$i:3}" == "$char$char$char" ]]; then
        triple=true
        i=$((i + 3))
      else
        triple=false
        i=$((i + 1))
      fi
      continue
    fi

    # A double-quoted shell word keeps Python double quotes escaped in the raw
    # source. Three adjacent \" sequences begin a triple string. Otherwise,
    # a 1 mod 4 backslash run begins an ordinary Python string; a 3 mod 4 run
    # represents an escaped quote within an already-open Python string.
    if [[ "$outer" == '"' && "${program:$i:6}" == "$escaped_triple" ]]; then
      quote='"'
      state=string
      triple=true
      i=$((i + 6))
      continue
    fi

    if [[ "$outer" == '"' && "$char" == "\\" ]]; then
      slash_count=0
      cursor="$i"
      while [[ "$cursor" -lt "$length" && "${program:$cursor:1}" == "\\" ]]; do
        slash_count=$((slash_count + 1))
        cursor=$((cursor + 1))
      done
      if [[ "${program:$cursor:1}" == '"' ]]; then
        if [[ $((slash_count % 4)) -eq 1 ]]; then
          quote='"'
          state=string
          triple=false
        fi
        i=$((cursor + 1))
        continue
      fi
    fi

    if [[ "${program:$i:6}" == assert ]]; then
      previous=""
      after=""
      [[ "$i" -eq 0 ]] || previous="${program:$((i - 1)):1}"
      [[ $((i + 6)) -ge "$length" ]] || after="${program:$((i + 6)):1}"
      if ! bats_python_assertions_ident_char "$previous" && ! bats_python_assertions_ident_char "$after"; then
        return 0
      fi
    fi

    i=$((i + 1))
  done

  return 1
}

bats_python_assertions_program_offsets() {
  local record="$1"
  local tail start end

  tail="${record#*\"PROGRAM\":{\"text\":}"
  [[ "$tail" != "$record" ]] || return 1
  tail="${tail#*,\"range\":{\"byteOffset\":{\"start\":}"
  start="${tail%%,*}"
  tail="${tail#*,\"end\":}"
  end="${tail%%\}*}"
  [[ "$start" =~ ^[0-9]+$ && "$end" =~ ^[0-9]+$ ]] || return 1
  printf '%s %s\n' "$start" "$end"
}

bats_python_assertions_scan_file() {
  local file="$1"
  local ast_output record offsets program_offsets start end zero_based lineno command program source_line

  if ! ast_output=$(ast-grep scan --stdin --rule "$_CODEBASE_BATS_PYTHON_RULE" --json=stream < "$file" 2>&1); then
    printf 'ERROR: ast-grep could not scan %s\n' "$file" >&2
    printf '%s\n' "$ast_output" >&2
    return 2
  fi

  while IFS= read -r record; do
    [[ -n "$record" ]] || continue
    offsets=$(printf '%s\n' "$record" | sed -nE 's/.*"range":\{"byteOffset":\{"start":([0-9]+),"end":([0-9]+)\}.*\},"file":.*/\1 \2/p')
    zero_based=$(printf '%s\n' "$record" | sed -nE 's/.*"range":\{.*"start":\{"line":([0-9]+),"column":[0-9]+\}.*\},"file":.*/\1/p')
    if ! program_offsets=$(bats_python_assertions_program_offsets "$record"); then
      printf 'ERROR: could not parse Python program match for %s\n' "$file" >&2
      return 2
    fi
    [[ -n "$offsets" && -n "$zero_based" ]] || {
      printf 'ERROR: could not parse ast-grep match for %s\n' "$file" >&2
      return 2
    }

    lineno=$((zero_based + 1))
    source_line=$(sed -n "${lineno}p" "$file")
    start="${offsets%% *}"
    end="${offsets#* }"
    command=$(dd if="$file" bs=1 skip="$start" count="$((end - start))" 2>/dev/null)
    if bats_python_assertions_has_reasoned_ignore "$command" \
      || bats_python_assertions_has_reasoned_ignore "$source_line"; then
      continue
    fi

    start="${program_offsets%% *}"
    end="${program_offsets#* }"
    program=$(dd if="$file" bs=1 skip="$start" count="$((end - start))" 2>/dev/null)
    bats_python_assertions_program_has_assert "$program" || continue

    printf '%s|%s\n' "$lineno" "${source_line#"${source_line%%[![:space:]]*}"}"
  done <<< "$ast_output"
}

bats_python_assertions_discover_files() {
  local target="$1"

  if [[ -f "$target" ]]; then
    [[ "$target" == *.bats ]] && printf '%s\n' "$target"
  elif [[ -d "$target" ]]; then
    fd -t f -e bats --exclude fixtures . "$target"
  fi
}

bats_python_assertions_lint() {
  local encoded_targets="$1"
  local target name toml discovered file rel findings finding lineno line
  local failures=0 hit_count target_output
  local -a targets files

  targets=()
  while IFS= read -r target; do
    [[ -n "$target" ]] && targets+=("$(resolve_target "$target")")
  done < <(bats_python_assertions_parse_targets "$encoded_targets")

  if [[ ${#targets[@]} -eq 0 ]]; then
    printf 'ERROR: at least one target is required\n' >&2
    return 1
  fi

  for target in "${targets[@]}"; do
    if [[ ! -e "$target" ]]; then
      printf 'ERROR: target does not exist: %s\n' "$target" >&2
      return 1
    fi

    name=$(basename "$target")
    toml="$target/mise.toml"
    if [[ -f "$toml" ]] && rg -q 'codebase:ignore[[:space:]]+bats-python-assertions([[:space:]]|$)' "$toml"; then
      printf 'SKIP  %s (codebase:ignore)\n' "$name"
      continue
    fi

    if ! discovered=$(bats_python_assertions_discover_files "$target"); then
      printf 'ERROR: could not discover BATS files in %s\n' "$target" >&2
      return 1
    fi
    files=()
    while IFS= read -r file; do
      [[ -n "$file" ]] && files+=("$file")
    done <<< "$discovered"

    if [[ ${#files[@]} -eq 0 ]]; then
      printf 'OK    %s (no BATS files found)\n' "$name"
      continue
    fi

    hit_count=0
    target_output=""
    for file in "${files[@]}"; do
      rel="${file#"$target"/}"
      if ! findings=$(bats_python_assertions_scan_file "$file"); then
        return 1
      fi
      while IFS= read -r finding; do
        [[ -n "$finding" ]] || continue
        lineno="${finding%%|*}"
        line="${finding#*|}"
        target_output+="  $rel:$lineno: $line"$'\n'
        hit_count=$((hit_count + 1))
      done <<< "$findings"
    done

    if [[ "$hit_count" -gt 0 ]]; then
      printf 'FAIL  %s: %s inline Python assertion(s) in BATS\n' "$name" "$hit_count"
      printf '%s' "$target_output"
      printf '%s\n' '  hint: write output to a temporary file and use a readable Python heredoc'
      printf '%s\n' '        see fold/notes/bats-tool-testing.md for the maintained BATS test pattern'
      printf '%s\n' "        annotate an intentional exception with '# codebase:ignore bats-python-assertions — <reason>'"
      failures=$((failures + 1))
    else
      printf 'OK    %s (%s BATS file(s) clean)\n' "$name" "${#files[@]}"
    fi
  done

  [[ "$failures" -le 255 ]] || failures=255
  return "$failures"
}
