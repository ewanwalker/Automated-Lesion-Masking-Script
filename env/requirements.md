# Neuroimaging Pipeline Dependencies

This document lists the software dependencies required to run the provided shell scripts:

- `meningioma_tracts.sh`
- `Pipeline_Diffusion.sh`
- `Pipeline_Structural.sh`

---

## 1. Core Dependencies

### MRtrix3
- Website: https://www.mrtrix.org/
- Installation:
  ```bash
  # Ubuntu / Debian
  sudo apt-get install mrtrix3

  # Conda
  conda install -c mrtrix3 mrtrix3
  ```

---

## 2. FSL (FMRIB Software Library)
- Website: https://fsl.fmrib.ox.ac.uk/fsl/fslwiki
- Tools used: `eddy`, `topup`, `fslmaths`, `bet`, `flirt`
- Installation:
  ```bash
  # Ubuntu / Debian
  sudo apt-get install fsl

  # Conda
  conda install -c conda-forge fsl
  ```

---

## 3. ANTs (Advanced Normalization Tools)
- Website: http://stnava.github.io/ANTs/
- Tools used: `ants`, `N4BiasFieldCorrection`
- Installation:
  ```bash
  # Ubuntu / Debian
  sudo apt-get install ants

  # Conda
  conda install -c conda-forge ants
  ```

---

## 4. FreeSurfer
- Website: https://surfer.nmr.mgh.harvard.edu/
- Tools used: `mri_synthstrip`
- Installation:
  ```bash
  # Download from official site
  https://surfer.nmr.mgh.harvard.edu/fswiki/DownloadAndInstall
  ```

---

## 5. AFNI (Analysis of Functional NeuroImages)
- Website: https://afni.nimh.nih.gov/
- Tools used: `3dClusterize`
- Installation:
  ```bash
  # Ubuntu / Debian
  sudo apt-get install afni

  # Conda
  conda install -c conda-forge afni
  ```

---

## 6. Additional Notes
- Ensure environment variables are set properly for **FSL**, **FreeSurfer**, and **AFNI** (these typically require sourcing a setup script in `.bashrc`).
- GPU acceleration (CUDA) may be required for optimal performance of `eddy` in FSL.

