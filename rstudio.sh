#!/bin/bash
#
# Loosely based on https://www.rocker-project.org/use/singularity/
#
# TODO:
#  - Set the LC_* environment variables to suppress warnings in Rstudio console
#  - Use an actually writable common Singularity cache somewhere to share images between users
#    (current setup has permissions issue).
#  - Determine why laptop -> login-node -> compute-node SSH forwarding isn't working (sshd_config ?)
#  - Allow srun/sbatch from within the container.
#

export RSTUDIO_PORT=8787
# we bind those directories
dir_lab=/data
dir_home="/home/${USER}"

#set -o xtrace

# We use this modified version of rocker/rstudio by default, with Seurat and required
# dependencies already installed.
# This version tag is actually {R_version}-{Seurat_version}
IMAGE=${IMAGE:-yosuketanigawa/rocker-geospatial-seurat:4.2.0-4.3.0}
# You can uncomment this if you've like vanilla rocker/rstudio
#IMAGE=${IMAGE:-rocker/rstudio:4.1.1}

# Fully qualify the image location if not specified
if [[ "$IMAGE" =~ ^docker-daemon:|^docker://|^\.|^/ ]]; then
  IMAGE_LOCATION=$IMAGE
else
  IMAGE_LOCATION="docker://$IMAGE"
fi

PORT=${RSTUDIO_PORT:-8787}

# Create a new password, or use whatever password is passed in the environment
if [[ -z "$PASSWORD" ]]; then
  PASSWORD=$(openssl rand -base64 15)
fi
export PASSWORD

SINGULARITY_VERSION=3.5.0
module load singularity/${SINGULARITY_VERSION}
# Use a shared cache location if unspecified
# export SINGULARITY_CACHEDIR=${SINGULARITY_CACHEDIR:-"/scratch/df22/andrewpe/singularity_cache"}


function get_port {
    # lsof doesn't return open ports for system services, so we use netstat
    # until ! lsof -i -P -n | grep -qc ':'${PORT}' (LISTEN)';

    until ! netstat -ln | grep "  LISTEN  " | grep -iEo  ":[0-9]+" | cut -d: -f2 | grep -wqc "${PORT}";
    do
        ((PORT++))
        echo "Checking port: ${PORT}"
    done
    echo "Got one !"
}

# Make a dir name from the IMAGE
IMAGE_SLASHED=$(echo "${IMAGE}" | sed 's/:/\//g' | sed 's/\.\./__/g')
R_DIRS="${HOME}/.rstudio-rocker/${IMAGE_SLASHED}/"
RSTUDIO_DOT_LOCAL="${R_DIRS}/.local/share/rstudio"
RSTUDIO_DOT_CONFIG="${R_DIRS}/.config/rstudio"
RSTUDIO_HOME="${R_DIRS}/session"
RSTUDIO_TMP="${R_DIRS}/tmp"
R_LIBS_USER="${R_DIRS}/R"
R_ENV_CACHE="${R_DIRS}/renv-local"
mkdir -p "${RSTUDIO_HOME}"
mkdir -p "${RSTUDIO_DOT_LOCAL}"
mkdir -p "${RSTUDIO_DOT_CONFIG}"
mkdir -p "${R_LIBS_USER}"
mkdir -p "${RSTUDIO_TMP}/var/run"
mkdir -p "${R_ENV_CACHE}"



echo "Getting required containers ... this may take a while ..."
CACHE_DIR=${SINGULARITY_CACHEDIR:-$HOME/.singularity/cache/}
echo "  Storing image in $CACHE_DIR"
singularity exec "${IMAGE_LOCATION}" true


echo
echo "Finding an available port ..."
get_port

LOCALPORT=${PORT}
# LOCALPORT=8787
PUBLIC_IP=$(curl --silent https://checkip.amazonaws.com)

echo "On you local machine, open an SSH tunnel like:"
# echo "  ssh -N -L ${LOCALPORT}:localhost:${PORT} ${USER}@m3-bio1.erc.monash.edu.au"
echo "  ssh -N -L ${LOCALPORT}:localhost:${PORT} ${USER}@$(hostname -f)"
echo "  or"
echo "  ssh -N -L ${LOCALPORT}:localhost:${PORT} ${USER}@${PUBLIC_IP}"

# For smux/srun/sbatch jobs, route via the login node to a the compute node where rserver runs - not working for me
# echo "  ssh -N -L ${LOCALPORT}:${HOSTNAME}:${PORT} ${USER}@m3.massive.org.au"
echo
echo "Point your web browser at http://localhost:${LOCALPORT}"
echo
echo "Login to RStudio with:"
echo "  username: ${USER}"
echo "  password: ${PASSWORD}"
echo
echo "Protip: You can choose your version of R from any of the tags listed here: https://hub.docker.com/r/rocker/rstudio/tags"
echo "        and set the environment variable IMAGE, eg"
echo "        IMAGE=rocker/rstudio:4.1.1 $(basename "$0")"
echo
echo "Starting RStudio Server (R version from image ${IMAGE})"

# Set some locales to suppress warnings
LC_CTYPE="C"
LC_TIME="C"
LC_MONETARY="C"
# shellcheck disable=SC2034
LC_PAPER="C"
# shellcheck disable=SC2034
LC_MEASUREMENT="C"

SINGULARITYENV_PASSWORD="${PASSWORD}" \
singularity exec \
  --bind "${RSTUDIO_HOME}:${HOME}/.rstudio" \
  --bind "${RSTUDIO_TMP}:/tmp" \
  --bind "${RSTUDIO_TMP}/var:/var/lib/rstudio-server" \
  --bind "${RSTUDIO_TMP}/var/run:/var/run/rstudio-server" \
  --bind "${R_ENV_CACHE}:/home/rstudio/.local/share/renv" \
  --bind "${RSTUDIO_DOT_LOCAL}:/home/rstudio/.local/share/rstudio" \
  --bind "${RSTUDIO_DOT_CONFIG}:/home/rstudio/.config/rstudio" \
  --bind "${R_LIBS_USER}:/home/rstudio/R" \
  --bind "${dir_lab}:${dir_lab}" \
  --bind "${dir_home}:${dir_home}" \
  "${IMAGE_LOCATION}" \
  rserver --auth-none=1 --auth-pam-helper-path=pam-helper --www-port="${PORT}" --server-user="${USER}"

printf 'rserver exited' 1>&2
