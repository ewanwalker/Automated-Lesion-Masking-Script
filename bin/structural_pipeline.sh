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
convert_mask() { 
    local input="$1" 
    local output="$2"
    if [[ ! -e "$output" ]]; then 
        mrconvert -force "$input" "$output" # Convert mask to .mif format
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
        if ! "$BIAS_CORR_STRUCT" -i "$input" -o "$output"; then # Run bias correction tool
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
        mrgrid "$input" regrid -voxel "$MRGRID_ISO" "$output" # Resample to isotropic 1mm
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
        if ! $BRAIN_EXTRACTION_TOOL $BET_OPTIONS "$input" "$output"; then # Run brain extraction tool
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
                           -cost $REGISTRATION_COST # Register to template
        log_msg "Registered: $output"
    else
        log_msg "Already registered: $output"
    fi
}

mask_meningioma() {
    local identifier="$1"
    local input="${DERIVATIVES}/${identifier}/${identifier}_iso.nii.gz"
    local output="${DERIVATIVES}/${identifier}/${identifier}_mask.nii.gz"

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
    "$input" "${identifier}_mask"  # Run masking in Docker container

    if [[ -e "$output" ]]; then
        log_msg "Meningioma Masked, Brain ID: $identifier"
    else
        log_msg "ERROR: Masking failed for $identifier"
    fi
}

run_lesion_tractography() {
    local identifier="$1"

    # Define paths based on config variables
    local roi_nii="${DERIVATIVES}/${identifier}/${TRACT_SEED_MASK}"
    local roi_nifti="${DERIVATIVES}/${identifier}/${identifier}_space-temp_roi.nii.gz"
    local roi_mif="${DERIVATIVES}/${identifier}/${identifier}_space-temp_roi.mif"
    local tractogram="${DERIVATIVES}/${identifier}/${identifier}_tractogram.tck"
    local lesion_fixel_dir="${LESION_TRACK_DIR}"
    local lesion_fixel="${lesion_fixel_dir}/${identifier}_lesion-track.mif"
    local bin_fixel="${lesion_fixel_dir}/${identifier}_lesion-bin.mif"

    mkdir -p "${DERIVATIVES}/${identifier}"
    mkdir -p "${lesion_fixel_dir}"
    if [[ -e "$bin_fixel" ]]; then
        log_msg "Already generated lesion tractography for: $identifier"
        return
    fi
    log_msg "Starting lesion tractography for: $identifier"
    if [[ ! -e "$roi_nifti" ]]; then
        log_msg "Registering ROI to template space for $identifier..."
        ${REG_TOOL} \
            -in "${roi_nii}" \
            -ref "${TEMPLATE_BET_AVG}" \
            -init "${DERIVATIVES}/${identifier}/${identifier}_bet2std.mat" \
            -applyxfm \
            -out "${roi_nifti}" # Register ROI to template space
    else
        log_msg "ROI already in template space for $identifier."
    fi
    if [[ ! -e "$roi_mif" ]]; then
        mrconvert "${roi_nifti}" "${roi_mif}" # Convert ROI to .mif format
        log_msg "ROI converted to MRtrix format: $roi_mif"
    else
        log_msg "ROI MRtrix file already exists: $roi_mif"
    fi
    if [[ ! -e "$tractogram" ]]; then
        log_msg "Generating tractogram for $identifier..."
        tckgen \
            -angle ${TRACT_ANGLE} \
            -maxlen ${TRACT_MAXLEN} \
            -minlen ${TRACT_MINLEN} \
            -power ${TRACT_POWER} \
            "${TEMPLATE_WMFOD}" \
            -seed_image "${roi_mif}" \
            -mask "${TEMPLATE_MASK}" \
            -select ${TRACT_NSTREAMS} \
            -cutoff ${TRACT_CUTOFF} \
            "${tractogram}" \
            -nthreads ${NTHREADS} # Generate tractogram
    else
        log_msg "Tractogram already exists: $tractogram"
    fi
    if [[ ! -e "$lesion_fixel" ]]; then
        log_msg "Converting tractogram to fixel maps..."
        tck2fixel \
            "${tractogram}" \
            "${TEMPLATE_FIXEL_MASK}" \
            "${lesion_fixel_dir}" \
            "${lesion_fixel}" # Convert tractogram to fixel map
    else
        log_msg "Fixel map already exists: $lesion_fixel"
    fi
    if [[ ! -e "$bin_fixel" ]]; then
        log_msg "Binarizing fixel map..."
        mrthreshold \
            "${lesion_fixel}" \
            -abs 1 \
            "${bin_fixel}" # Binarize fixel map
    else
        log_msg "Binary fixel map already exists: $bin_fixel"
    fi
    if [[ -e "$bin_fixel" ]]; then
        log_msg "Lesion tractography completed for $identifier"
    else
        log_msg "ERROR: Lesion tractography failed for $identifier"
        return 1
    fi
}

# ---------------------------
# Pipeline per patient
# ---------------------------
process_patient() {
    local file="$1" 
    local patient=$(basename "$file" | cut -d'_' -f1)                                                     # Extract patient ID from filename
    local outdir="$DERIVATIVES/$patient"                                                                  # Output directory for patient
    mkdir -p "$outdir"                                                                                    # Create output directory

    log_msg "Processing $file for patient $patient"                                                       # Log patient processing start

    bias_correct "$file" "$outdir/${patient}_biascorr.nii.gz"                                             # Bias correction
    resample_iso "$biascorr" "$outdir/${patient}_iso.nii.gz"                                              # Resample to isotropic
    brain_extract "$iso" "$outdir/${patient}_bet.nii.gz"                                                  # Brain extraction
    register_to_template "$bet" "$outdir/${patient}_bet2std.nii.gz" "$outdir/${patient}_bet2std.mat"      # Register brain to template
    mask_meningioma "$patient"                                                                            # Run meningioma masking
    run_lesion_tractography "$patient"                                                                    # Run lesion tractography
}

# ---------------------------
# Run pipeline for all patients
# ---------------------------
for file in "$RAW_DATA"/meningioma_raw_data/*.nii.gz; do
    process_patient "$file" # Process each patient's data sequentially
done

log_msg "structural_pipeline finished" # Log completion of pipeline
