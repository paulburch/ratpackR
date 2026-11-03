#!/usr/bin/env bash
# setup_linux.sh -- install R, a C++ toolchain and the R packages ratpackR needs,
# on a fresh x86-64 Linux machine (tested on Ubuntu 24.04 in a Claude Code cloud
# container). See docs/cloud_setup.md for the reasoning behind each step.
#
# Usage:   bash setup_linux.sh            # installs into $HOME/ratpack-env
#          RATPACK_ENV=/opt/r bash setup_linux.sh
# Then:    source "$HOME/ratpack-env/activate.sh"
#
# The script is idempotent: re-running it skips steps that are already done.
#
# Why conda-forge rather than CRAN/apt: the cloud network policy used for this
# work blocked CRAN, r-universe and Posit Package Manager, but allowed
# conda.anaconda.org and git access to github.com. conda-forge supplies R, the
# compilers and every compiled dependency as binaries; r4ss (current release
# lives only on GitHub; the CRAN r4ss is now a compatibility stub) and RTMB
# (not on conda-forge) are built from source from GitHub git clones.
set -euo pipefail

ENV_DIR="${RATPACK_ENV:-$HOME/ratpack-env}"
MAMBA_VERSION="2.10.0"
R_VERSION="4.5"
R4SS_REF="${R4SS_REF:-v1.56.0}"   # tag on github.com/r4ss/r4ss
RTMB_REF="${RTMB_REF:-2.0}"       # tag on github.com/cran/RTMB (CRAN mirror)

BIN_DIR="$ENV_DIR/bin"
MAMBA="$BIN_DIR/micromamba"
export MAMBA_ROOT_PREFIX="$ENV_DIR/mamba"
RENV="$MAMBA_ROOT_PREFIX/envs/ratpack"
SRC_DIR="$ENV_DIR/src"
mkdir -p "$BIN_DIR" "$SRC_DIR"

# ---- 1. micromamba (single static binary from conda-forge) -------------------
if [ ! -x "$MAMBA" ]; then
  echo ">> Downloading micromamba $MAMBA_VERSION"
  tmp=$(mktemp -d)
  curl -fsSL "https://conda.anaconda.org/conda-forge/linux-64/micromamba-${MAMBA_VERSION}-0.tar.bz2" \
    -o "$tmp/mm.tar.bz2"
  tar -xjf "$tmp/mm.tar.bz2" -C "$tmp" bin/micromamba
  mv "$tmp/bin/micromamba" "$MAMBA"
  rm -rf "$tmp"
fi
"$MAMBA" --version

# ---- 2. R + toolchain + binary R packages ------------------------------------
# gxx_linux-64/gcc_linux-64/gfortran_linux-64 are the compilers that conda's R
# is configured to use for Rcpp::sourceCpp and for source package installs.
if [ ! -x "$RENV/bin/R" ]; then
  echo ">> Creating conda env with R $R_VERSION"
  "$MAMBA" create -y -q -n ratpack -c conda-forge --override-channels \
    "r-base=$R_VERSION" make gcc_linux-64 gxx_linux-64 gfortran_linux-64 \
    r-rcpp r-rcpparmadillo r-rcppeigen r-tmb r-matrix r-mass r-readxl \
    r-cli r-coda r-corpcor "r-dplyr>=1.2.0" r-forcats r-furrr r-future \
    r-ggplot2 r-gh r-glue r-kableextra r-lifecycle r-purrr r-stringr \
    r-tibble r-tidyr r-viridis r-foreach r-doparallel git
fi

run_r() { "$MAMBA" run -n ratpack "$@"; }

# ---- 3. Source packages from GitHub (r4ss, RTMB) -----------------------------
install_from_git() {  # $1 = package name, $2 = git url, $3 = ref
  local pkg=$1 url=$2 ref=$3
  if run_r Rscript -e "q(status = !requireNamespace('$pkg', quietly = TRUE))" >/dev/null 2>&1; then
    echo ">> $pkg already installed"; return
  fi
  echo ">> Installing $pkg ($ref) from $url"
  rm -rf "$SRC_DIR/$pkg"
  git clone -q --depth 1 --branch "$ref" "$url" "$SRC_DIR/$pkg"
  # MAKEFLAGS=-j speeds up the RTMB compile (it is the slow step, ~5-10 min)
  MAKEFLAGS="-j$(nproc)" run_r R CMD INSTALL --no-docs --no-multiarch "$SRC_DIR/$pkg"
}
install_from_git RTMB https://github.com/cran/RTMB.git "$RTMB_REF"
install_from_git r4ss https://github.com/r4ss/r4ss.git "$R4SS_REF"

# ---- 4. Activation helper ----------------------------------------------------
cat > "$ENV_DIR/activate.sh" <<EOF
# source this file to put the ratpackR R environment on PATH
export MAMBA_ROOT_PREFIX="$MAMBA_ROOT_PREFIX"
eval "\$("$MAMBA" shell hook -s bash)"
micromamba activate ratpack
EOF

# ---- 5. Check: packages load and sourceCpp compiles a trivial function -------
run_r Rscript -e '
for (p in c("r4ss","RTMB","Rcpp","RcppArmadillo")) {
  suppressPackageStartupMessages(library(p, character.only = TRUE))
  cat(sprintf("%-14s %s\n", p, as.character(packageVersion(p))))
}
Rcpp::cppFunction("int one() { return 1; }", depends = "RcppArmadillo")
stopifnot(one() == 1L); cat(R.version.string, ": sourceCpp OK\n")'

# Stock Synthesis Linux binary must be executable (git can lose the bit)
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
[ -f "$here/CodeBase/ss3_linux" ] && chmod +x "$here/CodeBase/ss3_linux" || true

echo ">> Done. Run:  source \"$ENV_DIR/activate.sh\""
