#!/bin/bash
set -euo pipefail

# ---------------------------
# Load configuration
# ---------------------------
set -a
. ../config/global_params.config
set +a

# ---------------------------
# User and logging setup
# ---------------------------
idu=$(id -u)
idg=$(id -g)

# Ensure log directory exists
mkdir -p "$LOG_DIR"
LOGFILE="$LOG_DIR/structural_pipeline_$(date '+%Y%m%d_%H%M%S').log"

# Redirect stdout and stderr to log file AND terminal
exec > >(tee -a "$LOGFILE") 2>&1

# Timestamped logging function
log_msg() { echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*"; }

log_msg "Starting structural pipeline"

# ---------------------------
# Functions for each step
# ---------------------------

convert_mask() {
    local input="$1"
    local output="$2"
    if [[ ! -e "$output" ]]; then
        mrconvert -force "$input" "$output"
        log_msg "Mask converted: $output"
    else
        log_msg "Mask already exists: $output"
    fi
}

bias_correct() {
    local input="$1"
    local output="$2"
    if [[ ! -e "$output" ]]; then
        log_msg "Running $BIAS_CORR_STRUCT on $input..."
        if ! "$BIAS_CORR_STRUCT" -i "$input" -o "$output"; then
            log_msg "ERROR: Bias correction failed for $input"
        else
            log_msg "Bias Field Corrected: $output"
        fi
    else
        log_msg "Already bias corrected: $output"
    fi
}

resample_iso() {
    local input="$1"
    local output="$2"
    if [[ ! -e "$output" ]]; then
        mrgrid "$input" regrid -voxel 1.00 "$output"
        log_msg "Resampled to isotropic: $output"
    else
        log_msg "Already resampled: $output"
    fi
}

brain_extract() {
    local input="$1"
    local output="$2"
    if [[ ! -e "$output" ]]; then
        log_msg "Running $BRAIN_EXTRACTION_TOOL on $input..."
        if ! $BRAIN_EXTRACTION_TOOL $BET_OPTIONS "$input" "$output"; then
            log_msg "ERROR: Brain extraction failed for $input"
        else
            log_msg "Brain extracted: $output"
        fi
    else
        log_msg "Already brain extracted: $output"
    fi
}

register_to_template() {
    local input="$1"
    local output="$2"
    local matrix="$3"
    if [[ ! -e "$output" ]]; then
        log_msg "Registering $input to template..."
        $REGISTRATION_TOOL -in "$input" \
                           -ref "$DERIVATIVES/templates/bet-avg.nii.gz" \
                           -out "$output" \
                           -omat "$matrix" \
                           -dof $REGISTRATION_DOF \
                           -cost $REGISTRATION_COST
        log_msg "Registered: $output"
    else
        log_msg "Already registered: $output"
    fi
}

mask_meningioma() {
    local identifier="$1"
    local input="${identifier}_iso.nii.gz"
    local output="${identifier}_mask.nii.gz"

    if [[ -e "$output" ]]; then
        log_msg "Already masked meningioma: $identifier"
        return
    fi

    if ! command -v docker &> /dev/null; then
        log_msg "ERROR: Docker not found. Cannot run masking."
        return 1
    fi

    log_msg "Running meningioma masking for $identifier..."

    docker run --rm \
    -v "$(pwd)":/data \
    --user "${idu}:${idg}" \
    --cpus=$CPUS \
    neuronets/ams:latest-cpu \
    "$input" "${identifier}_mask"

    if [[ -e "$output" ]]; then
        log_msg "Meningioma Masked, Brain ID: $identifier"
    else
        log_msg "ERROR: Masking failed for $identifier"
    fi
}

# ---------------------------
# Pipeline per patient
# ---------------------------
process_patient() {
    local file="$1"
    local patient=$(basename "$file" | cut -d'_' -f1)
    local outdir="$DERIVATIVES/$patient"
    mkdir -p "$outdir"

    log_msg "Processing $file for patient $patient"

    # Paths for outputs
    local biascorr="$outdir/${patient}_biascorr.nii.gz"
    local iso="$outdir/${patient}_iso.nii.gz"
    local bet="$outdir/${patient}_bet.nii.gz"
    local bet2std="$outdir/${patient}_bet2std.nii.gz"
    local mat="$outdir/${patient}_bet2std.mat"
    local mask="$outdir/${patient}_mask.nii.gz"

    # Pipeline steps
    bias_correct "$file" "$biascorr"
    resample_iso "$biascorr" "$iso"
    brain_extract "$iso" "$bet"
    register_to_template "$bet" "$bet2std" "$mat"
    mask_meningioma "$outdir/${patient}"
}

# ---------------------------
# Run pipeline for all patients
# ---------------------------
for file in "$RAW_DATA"/meningioma_raw_data/*.nii.gz; do
    process_patient "$file"
done

log_msg "Structural pipeline finished"


