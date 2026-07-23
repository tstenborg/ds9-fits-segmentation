#!/bin/bash

# This shell script metaprograms DS9 commands.
# The DS9 commands segment target FITS files into small JPEG images.
# Output is saved in the same directory as the script.
#
# Usage notes are available:
#
# a) At the command line via...
#    > ./fits_segmenter.sh -h
#
# b) In the "display_usage" function definition, below.


######
# Initialise variables.

# Constants.
FILE_ARRAY=""
CURRENT_DIR=$(pwd)
readonly CURRENT_DIR
PLATFORM=$(uname -s)
readonly PLATFORM

# Boolean variables (type not enforced).
bool_double_skip=false
bool_mode_dual=false
bool_mode_single=false

# Floating-point variables (type not enforced).
flt_pan_tmp=0.0
flt_pan_x_comp2=0.0
flt_pan_y_comp2=0.0

# String variables (type not enforced).
str_command=""
str_fits_file_long=""
str_fits_file_short=""
str_fits_header=""
str_fits_header_subset=""
str_geometry=""
str_missing_msg=""
str_mode=""
str_path=""
str_path_previous=""
str_permissions=""
str_resolution=""
str_segment=""

# Integer variables.
declare -i int_digits=0
declare -i int_files=0
declare -i int_naxis1=0
declare -i int_naxis2=0
declare -i int_pan_x=0
declare -i int_pan_x_comp1=0
declare -i int_pan_y=0
declare -i int_pan_y_comp1=0
declare -i int_resolution_x=0
declare -i int_resolution_y=0
declare -i int_segments=0
declare -i int_target_index=0
declare -i int_targets=0
declare -i int_x=0
declare -i int_x_max=0
declare -i int_y=0
declare -i int_y_max=0
######


######
# Function definitions.

function display_usage() {
   # Display user instructions for the shell script.
   echo ""
   echo "This shell script metaprograms DS9 commands."
   echo "The DS9 commands segment target FITS files into small JPEG images."
   echo "Output is saved in the same directory as the script."
   echo ""
   echo "Usage: ./fits_segmenter.sh [-h] [-m <mode argument>] [target FITS files list]"
   echo ""
   echo "[-h]"
   echo "   Displays script help information."
   echo ""
   echo "[-m <mode argument>]"
   echo "   Ensure <mode argument> is either single or dual."
   echo "   Single mode"
   echo "      - Assumes one FITS file per DS9 frame."
   echo "   Dual mode"
   echo "      - Assumes two FITS files per DS9 frame."
   echo "      - The first is rendered red and the second green, in an RGB frame."
   echo "      - An even number of target FITS files should be specified."
   echo ""
   echo "[target FITS files list]"
   echo "   A list of FITS files to be segmented should be specified as a script parameter."
   echo "   Target FITS files should be in the same directory as fits_segmenter.sh."
   echo "   Omit file extensions, a '.fits' extension is assumed for each target file."
   echo "   For dual mode, specify complementary FITS file pairs, e.g., narrowband and broadband filter exposures."
   echo ""
   echo "Examples:"
   echo "   ./fits_segmenter.sh -m single F1759-2841_diff F1759-2915_diff F1803-2807_diff"
   echo "   ./fits_segmenter.sh -m dual F1759-2841_O3 F1759-2841_O3_off F1759-2915_O3 F1759-2915_O3_off F1803-2807_O3 F1803-2807_O3_off"
   echo ""
}

function error_messager() {
   # Send a date-time stamped error message to STDERR.
   echo "[$(date +'%Y-%m-%dT%H:%M:%S%z')] Error: $*" >&2
}

function get_ceiling_division() {

   # Implement a ceiling division operation applicable to positive integers.
   # I.e. ceiling division = (numerator + denominator - 1) / denominator.
   # N.B. Fractions will be truncated.
   #
   # Positional input 1: numerator
   # Positional input 2: denominator
   #
   # Example: (get_ceiling_division 10 2)   returns 5.
   # Example: (get_ceiling_division 10 3)   returns 4.

   local int_ceiling=0

   # Ensure positive inputs.
   if (( $1 <= 0 )); then
      error_messager "Numerators passed to ceiling() must be > 0, exiting."
      exit 1
   fi
   if (( $2 <= 0 )); then
      error_messager "Denominators passed to ceiling() must be > 0, exiting."
      exit 1
   fi

   int_ceiling=$(( ($1 + $2 - 1) / $2 ))
   echo "${int_ceiling}"
}

function is_odd() {

   # A function that tests if a value is odd.
   #
   # Positional input 1: value to test.

   local bool_is_odd=false
   if (( $1 % 2 == 1 )); then
      bool_is_odd=true
   fi
   echo "${bool_is_odd}"
}
######


# Ensure the bc package is available.
if ! command -v bc &>/dev/null; then
   error_messager "Please ensure the bc package is available."
   exit 1
fi


######
# Determine screen resolution and DS9 image area geometry.

# Ensure screen resolution can be determined.
# Assumes a single-monitor setup.
if [[ "${PLATFORM}" == "Darwin" ]]; then

   # For the macOS, ensure XQuartz is available.
   if ! command -v xquartz &>/dev/null; then
      error_messager "Please ensure XQuartz is available."
      exit 1
   fi

   # For the macOS, ensure system_profiler is available.
   if ! command -v system_profiler &>/dev/null; then
      error_messager "Please ensure system_profiler is available."
      exit 1
   fi

   # For the macOS, get the screen resolution with system_profiler.
   str_resolution=$(system_profiler SPDisplaysDataType | grep Resolution)
   # Assumed example format of str_resolution after the command above:
   # "        Resolution: 1440 x 900 (Widescreen eXtended Graphics Array Plus)"

else

   # If the current platform isn't the macOS, assume it's Linux.
   # For Linux, ensure the xrandr package is available.
   if ! command -v xrandr &>/dev/null; then
      error_messager "Please ensure the xrandr package is available."
      exit 1
   fi

   # For Linux, get the screen resolution with xrandr.
   # Extract the xrandr output line holding a * character.
   # Take care to handle potential duplicate configurations with uniq.
   str_resolution=$(xrandr | grep "\*" | uniq)
   # Assumed example format of str_resolution after the command above:
   # "   1920x1080     59.96*+"
fi

# Parse screen resolution.

# Trim leading and trailing spaces and collapse multiple spaces to singles.
str_resolution=$(echo "${str_resolution}" | xargs)

# Convert any instances of " x ", to "x".
str_resolution="${str_resolution// x /x}"

# Parse numbers straddling an "x", along with the "x".
if [[ "${str_resolution}" =~ ^[^0-9]*([0-9]+x[0-9]+) ]]; then
   # $BASH_REMATCH is a special array variable that stores Bash regex results.
   str_resolution=${BASH_REMATCH[1]}
else
   error_messager "Unable to determine screen resolution, exiting."
   exit 1
fi

# Get x and y components.
int_resolution_x=$(echo "${str_resolution}" | cut -d "x" -f1)
int_resolution_y=$(echo "${str_resolution}" | cut -d "x" -f2)

# Make allowance for 20% screen space taken up by fixed OS GUI elements.
# E.g., menus, taskbars, etc.
# Some are oriented at the top or bottom of the screen, e.g., macOS.
# Others are oriented at the side of the screen, e.g., the GNOME desktop.
#
# N.B. By default, bc truncates. Rounding with bc needs...
#      a) adding 0.5 to the target value b) scale=0 c) explicit division.
# N.B. Reduction by 20% = multiply by 0.8 = 1 / 1.25.
#
int_resolution_x=$(echo "scale=0; (${int_resolution_x} + 0.5) / 1.25" | bc)
int_resolution_y=$(echo "scale=0; (${int_resolution_y} + 0.5) / 1.25" | bc)

# Set DS9 display geometry.
# N.B. DS9 "geometry" means the whole DS9 window, not just the image space.
str_geometry="${int_resolution_x}x${int_resolution_y}"

# Make allowance for screen space taken up by fixed DS9 GUI elements.
# E.g., app frame borders, menus, etc. Space taken up varies from OS to OS.
# Assume values slightly higher than those obtained via empirical testing as
# insurance against expansive rendering on untested platforms / configurations.
(( int_resolution_x = int_resolution_x - 14 ))
(( int_resolution_y = int_resolution_y - 80 ))
######


######
# Process input arguments.
while getopts ":hm:" opt; do
   case $opt in
      h)
         display_usage
         exit 0
         ;;
      m)
         str_mode="${OPTARG}"
         ;;
      \?)
         error_messager "Invalid parameter -${OPTARG}."
         exit 1
         ;;
      :)
         error_messager "Parameter -${OPTARG} requires an argument."
         exit 1
         ;;
   esac
done

# Shift arguments to make positional arguments accessible.
shift $((OPTIND - 1))

# Save all positional input arguments as an array of strings.
readonly FILE_ARRAY=("$@")

# Ensure a 'mode' (-m) argument was provided.
if [[ ${str_mode} == "" ]]; then
   error_messager "A mode argument -m is required."
   display_usage
   exit 1
fi

# Ensure the 'mode' (-m) argument is either "single" or "dual".
case ${str_mode} in
   "single")
      bool_mode_single=true
      ;;
   "dual")
      # For dual mode, ensure an even number of input files were specified.
      int_targets=${#FILE_ARRAY[@]}
      if [[ $(is_odd int_targets) == true ]]; then
         error_messager "Dual mode needs an even number of target FITS files. Files specified: ${int_targets}."
         exit 1
      else
         bool_mode_dual=true
      fi
      ;;
   *)
      error_messager "Invalid -m argument: ${str_mode}"
      display_usage
      exit 1
      ;;
esac
######


######
# Process FITS files.
int_target_index=-1
for str_path in "${FILE_ARRAY[@]}"; do

   # Assume the target FITS files are in the same directory as the shell script.
   (( int_target_index++ ))
   str_fits_file_short="${str_path}.fits"
   str_fits_file_long="${CURRENT_DIR}/${str_fits_file_short}"

   ######
   # Ensure the target FITS file exists.
   if [[ ${bool_double_skip} == true ]]; then
      # Implement two file skips.
      # Needed in dual mode, if the first file in a FITS file pair is missing.
      bool_double_skip=false
      continue   # Skip to the next loop iteration.
   fi
   if ! test -f "${str_fits_file_long}"; then

      str_missing_msg="Missing file. Skipping FITS file"

      if [[ ${bool_mode_single} == true ]]; then
         # Single mode, file missing.
         error_messager "${str_missing_msg}: ${str_fits_file_short}."
      elif [[ ${bool_mode_dual} == true ]]; then
         if [[ $(is_odd int_target_index) == true ]]; then
            # Dual mode, second file of pair. I.e. Target index = 1, 3, 5, ...
            error_messager "${str_missing_msg} pair: ${FILE_ARRAY[int_target_index - 1]} and ${str_fits_file_short}."
         else
            # Dual mode, first file of pair. I.e. Target index 0, 2, 4, ... Activate double skip.
            error_messager "${str_missing_msg} pair: ${str_fits_file_short} and ${FILE_ARRAY[int_target_index + 1]}."
            bool_double_skip=true
         fi
      fi
      continue   # Skip to the next loop iteration.
   fi
   ######

   echo "Processing file ${str_fits_file_short}…"

   ######
   # Get the dimensions of the target FITS file.
   # Do for each file to allow for segmenting heterogeneous FITS files.
   #
   # Get the FITS file header, stripping null bytes.
   # N.B. Set LC_ALL=C to let tr handle unexpected FITS header characters.
   str_fits_header=$(head -n 1 "${str_fits_file_long}" | LC_ALL=C tr -d "\0")

   # Discard the FITS " END " card and everything after it.
   str_fits_header="${str_fits_header%% END *}"

   # Collapse repeated spaces into single spaces.
   str_fits_header=$(echo "${str_fits_header}" | LC_ALL=C tr -s " ")

   # Convert all instances of " = ", to "=".
   str_fits_header="${str_fits_header// = /=}"

   # Assume the NAXIS1 keyword holds the x-dimension.
   str_fits_header_subset="${str_fits_header#*NAXIS1=}"
   int_naxis1="${str_fits_header_subset%% *}"
   #
   # Assume the NAXIS2 keyword holds the y-dimension.
   str_fits_header_subset="${str_fits_header#*NAXIS2=}"
   int_naxis2="${str_fits_header_subset%% *}"

   # Ensure the NAXIS1 and NAXIS2 values are valid non-zero integers.
   if (( int_naxis1 <= 0 )); then
      str_missing_msg="No valid NAXIS1 value in FITS header. Skipping FITS file"
   fi
   if (( int_naxis2 <= 0 )); then
      str_missing_msg="No valid NAXIS2 value in FITS header. Skipping FITS file"
   fi
   if (( int_naxis1 <= 0 )) || (( int_naxis2 <= 0 )); then
      if [[ ${bool_mode_single} == true ]]; then
         error_messager "${str_missing_msg}."
      elif [[ ${bool_mode_dual} == true ]]; then
         if [[ $(is_odd int_target_index) == true ]]; then
            # Dual mode, second file of pair. I.e. Target index = 1, 3, 5, ...
            error_messager "${str_missing_msg} pair: ${FILE_ARRAY[int_target_index - 1]} and ${str_fits_file_short}."
         else
            # Dual mode, first file of pair. I.e. Target index 0, 2, 4, ... Activate double skip.
            error_messager "${str_missing_msg} pair: ${str_fits_file_short} and ${FILE_ARRAY[int_target_index + 1]}."
            bool_double_skip=true
         fi
      fi
      continue   # Skip to the next loop iteration.
   fi
   ######

   # In dual mode, only activate DS9 for the second file of a FITS pair.
   # I.e. Skip to the next file for target index 0, 2, 4, ...
   if [[ ${bool_mode_dual} == true ]]; then
      if [[ $(is_odd int_target_index) == false ]]; then
         continue   # Skip to the next loop iteration.
      fi
   fi

   # Prepare for panning.
   int_x_max="$(get_ceiling_division int_naxis1 int_resolution_x) - 1"
   (( int_pan_x_comp1 = int_x_max + 1 ))
   flt_pan_x_comp2=$(echo "${int_x_max} / (2 * ${int_pan_x_comp1})" | bc -l)
   #
   int_y_max="$(get_ceiling_division int_naxis2 int_resolution_y) - 1"
   (( int_pan_y_comp1 = int_y_max + 1 ))
   flt_pan_y_comp2=$(echo "${int_y_max} / (2 * ${int_pan_y_comp1})" | bc -l)

   # Prepare for segment file naming.
   int_segments=0
   (( int_digits = int_pan_x_comp1 * int_pan_y_comp1 ))
   int_digits=${#int_digits}

   # Segment the FITS file.
   for (( int_x=0; int_x <= int_x_max; int_x++ )); do

      # Calculate horizontal pan.
      # N.B. By default, bc truncates. Rounding with bc needs...
      #      a) adding 0.5 to the target value b) scale=0 c) explicit division.
      #
      flt_pan_tmp=$(echo "${int_naxis1} * (${int_x} / ${int_pan_x_comp1} - ${flt_pan_x_comp2}) + 0.5" | bc -l)
      int_pan_x=$(echo "scale=0; ${flt_pan_tmp} / 1" | bc)

      for (( int_y=0; int_y <= int_y_max; int_y++ )); do

         # Calculate vertical pan.
         flt_pan_tmp=$(echo "${int_naxis2} * (${int_y} / ${int_pan_y_comp1} - ${flt_pan_y_comp2}) + 0.5" | bc -l)
         int_pan_y=$(echo "scale=0; ${flt_pan_tmp} / 1" | bc)

         (( int_files++ ))
         (( int_segments++ ))

         # Prepare for segment naming.
         str_segment=$(printf "%0*d\n" "${int_digits}" "${int_segments}")

         # Open the FITS file, then...
         # - Apply IRAF's zscale display range algorithm.
         # - Hide the GUI's colour bar, buttons, info, magnifier and panner.
         # - Set the DS9 window geometry to fill the current screen resolution.
         # - Pan to a new segment of the FITS file.
         # - Save the segment as a JPEG of quality 100 (on a 1-100 scale).
         if [[ ${bool_mode_single} == true ]]; then
            str_segment="${CURRENT_DIR}/segment_${str_segment}_${str_path}.jpeg"
            str_command="ds9 ${str_fits_file_long} -zscale -colorbar no -view buttons no -view info no -view magnifier no -view panner no -geometry ${str_geometry} -pan $int_pan_x $int_pan_y -saveimage jpeg ${str_segment} 100 -exit"
         elif [[ ${bool_mode_dual} == true ]]; then
            str_path_previous="${FILE_ARRAY[int_target_index - 1]}"
            str_segment="${CURRENT_DIR}/segment_${str_segment}_${str_path_previous}_${str_path}.jpeg"
            str_command="ds9 -rgb -rgb red ${CURRENT_DIR}/${str_path_previous}.fits -zscale -rgb green ${str_fits_file_long} -zscale -colorbar no -view buttons no -view info no -view magnifier no -view panner no -geometry ${str_geometry} -pan $int_pan_x $int_pan_y -saveimage jpeg ${str_segment} 100 -exit"
         fi

         $str_command
         echo "${str_command}"

         # Check for file creation failure.
         if ! test -f "${str_segment}"; then
            error_messager "Unable to create ${str_segment}."
            (( int_files-- ))

            # Get the permissions for the current directory.
            # Assumes 10-character symbolic POSIX permissions strings.
            str_permissions=$(stat -c "%A" "${CURRENT_DIR}")

            # Test if the user has write access to the current directory.
            if [[ "${str_permissions:2:1}" != "w" ]]; then
               error_messager "No user write access to ${CURRENT_DIR}, exiting."
               exit 1
            fi
         fi
      done
   done
done
echo "Processing complete. Files created: ${int_files}."
######
