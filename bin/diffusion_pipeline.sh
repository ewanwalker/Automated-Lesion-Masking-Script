#!/bin/bash
set -euo pipefail # Exit on error, undefined variable, or error in pipeline

# ---------------------------
# LOAD CONFIGURATION
set -a                           # Automatically export all variables
. ../config/global_params.config # Load global parameters
set +a                           # Stop automatically exporting variables

# ---------------------------
# USER AND LOGGING SETUP
LOGFILE="$LOG_DIR/structural_pipeline_$(date '+%Y%m%d_%H%M%S').log" # Create log file with timestamp
exec > >(tee -a "$LOGFILE") 2>&1                                    # Redirect stdout and stderr to log file and terminal
log_msg() { echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*"; }             # Function for timestamped logging
log_msg "Starting structural_pipeline"                              # Log start of pipeline

# ---------------------------
# FUNCTIONS