# This IRAF script scales, then subtracts, [OIII] off-band data from corresponding on-band Mosaic II data.

# Load the images package.
images

# Variable initialisation.
int num_frames = 3

# Define target Mosaic II frame names.
string frame_array[3]
frame_array[1] = "F1759-2841"   # Pixels: on-band 8769 x 8888, off-band 8768 x 8887.
frame_array[2] = "F1759-2915"   # Pixels: on-band 8769 x 8887, off-band 8767 x 8885.
frame_array[3] = "F1803-2807"   # Pixels: on-band 8773 x 8887, off-band 8770 x 8886.

# Define scaling factors that are the ratio of the median pixel value in the off-band to on-band data.
real scale_array[3]
scale_array[1] = 8.220282133
scale_array[2] = 9.221359680
scale_array[3] = 8.069132572

# Define image trim ranges.
# Optimum ranges were determined by visually inspecting the results of every potential range.
string trim_range[3]
trim_range[1] = "2:8769,2:8888"
trim_range[2] = "1:8767,1:8885"
trim_range[3] = "1:8770,1:8886"

# Data reduction.
for (i = 1; i <= num_frames; i+=1) {

   # Scale down the intensity of every pixel in the off-band frames.
   imarith (frame_array[i]//"_O3_off_stacked.fits", "/", scale_array[i], frame_array[i]//"_O3_off_stacked_scaled.fits")

   # Resolve minor image size differences.
   imcopy (frame_array[i]//"_O3_stacked.fits["//trim_range[i]//"]", frame_array[i]//"_O3_stacked_trimmed.fits")

   # Subtract the (scaled down) off-band data from the on-band data.
   imarith (frame_array[i]//"_O3_stacked_trimmed.fits", "-", frame_array[i]//"_O3_off_stacked_scaled.fits ", frame_array[i]//"_O3_stacked_diff.fits")

   # Delete unneeded intermediate processing files.
   imdel (frame_array[i]//"_O3_off_stacked_scaled.fits")
   imdel (frame_array[i]//"_O3_stacked_trimmed.fits")
}
