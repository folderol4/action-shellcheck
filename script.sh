#!/bin/sh

echo '::group:: Installing shellcheck ... https://github.com/koalaman/shellcheck'
TEMP_PATH="$(mktemp -d)"
cd "${TEMP_PATH}" || exit
wget -qO- "https://github.com/koalaman/shellcheck/releases/download/v${SHELLCHECK_VERSION}/shellcheck-v${SHELLCHECK_VERSION}.linux.x86_64.tar.xz" | tar -xJf -
mkdir bin
cp "shellcheck-v$SHELLCHECK_VERSION/shellcheck" ./bin
PATH="${TEMP_PATH}/bin:$PATH"
echo '::endgroup::'

cd "${GITHUB_WORKSPACE}" || exit

export REVIEWDOG_GITHUB_API_TOKEN="${INPUT_GITHUB_TOKEN}"

pattern="${INPUT_PATTERN:-'*.sh'}"
exclude="${INPUT_EXCLUDE:-}"
path="${INPUT_PATH:-'.'}"

# Match all files matching the pattern
files_with_pattern=$(find "${path}" -not -path "${exclude}" -type f -name "${pattern}")

# Match all files with a shebang (e.g. "#!/usr/bin/env zsh" or even "#!/my/path/bash") in the first two lines
# Ignore files which match "$pattern" in order to avoid duplicates
if [ "${INPUT_CHECK_ALL_FILES_WITH_SHEBANGS}" = "true" ]; then
  files_with_shebang=$(find "${path}" -not -path "${path}/.git/*" -not -path "${exclude}" -not -name "${pattern}" -type f -print0 | xargs -0 grep -m2 -IrlZ "^#\\!/.*sh" | xargs -r -0 echo)
fi

FILES="${files_with_pattern} ${files_with_shebang}"

echo '::group:: Running shellcheck ...'
if [ "${INPUT_REPORTER}" = 'github-pr-review' ]; then
  # erroformat: https://git.io/JeGMU
  # shellcheck disable=SC2086
  shellcheck -f json  ${INPUT_SHELLCHECK_FLAGS:-'--external-sources'} ${FILES} \
    | jq -r '.[] | "\(.file):\(.line):\(.column):\(.level):\(.message) [SC\(.code)](https://github.com/koalaman/shellcheck/wiki/SC\(.code))"' \
    | reviewdog \
        -efm="%f:%l:%c:%t%*[^:]:%m" \
        -name="shellcheck" \
        -reporter=github-pr-review \
        -filter-mode="${INPUT_FILTER_MODE}" \
        -fail-on-error="${INPUT_FAIL_ON_ERROR}" \
        -level="${INPUT_LEVEL}" \
        ${INPUT_REVIEWDOG_FLAGS} || EXIT_CODE=$?
else
  # github-pr-check,github-check (GitHub Check API) doesn't support markdown annotation.
  # shellcheck disable=SC2086
  shellcheck -f checkstyle ${INPUT_SHELLCHECK_FLAGS:-'--external-sources'} ${FILES} \
    | reviewdog \
        -f="checkstyle" \
        -name="shellcheck" \
        -reporter="${INPUT_REPORTER:-github-pr-check}" \
        -filter-mode="${INPUT_FILTER_MODE}" \
        -fail-on-error="${INPUT_FAIL_ON_ERROR}" \
        -level="${INPUT_LEVEL}" \
        ${INPUT_REVIEWDOG_FLAGS} || EXIT_CODE=$?
fi
echo '::endgroup::'

echo '::group:: Running shellcheck (suggestion) ...'
# -reporter must be github-pr-review for the suggestion feature.
# shellcheck disable=SC2086
shellcheck -f diff ${FILES} \
  | reviewdog \
      -name="shellcheck (suggestion)" \
      -f=diff \
      -f.diff.strip=1 \
      -reporter="github-pr-review" \
      -filter-mode="${INPUT_FILTER_MODE}" \
      -fail-on-error="${INPUT_FAIL_ON_ERROR}" \
      ${INPUT_REVIEWDOG_FLAGS} || EXIT_CODE_SUGGESTION=$?
echo '::endgroup::'

if [ -n "${EXIT_CODE}" ] || [ -n "${EXIT_CODE_SUGGESTION}" ]; then
  exit 1
fi
