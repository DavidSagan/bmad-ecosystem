#!/usr/bin/env python

# To execute this file from within the Python interpreter:
#   execfile('this_file_name')

import sys
import re
import numpy as np
import matplotlib.pyplot as plt
import matplotlib.ticker as ticker

T = True    # For converting from det_pix file header T/F notation
F = False

# Check version

if sys.version_info[0] == 2 and sys.version_info[1] < 7: sys.exit("MUST USE PYTHON 2.7 OR GREATER!")

# Help

def print_help():
  print ('''
Usage:
    det_pix_plot.py {-scale <scale>} {-plot <who_to_plot>} {<data_file_name>}
  <who_to_plot> = x         # Intensity of x-polarized photons
                = y         # Intensity of y-polarized photons
                = i         # Total intensity (sum of x & y polarizations)
                = e         # Energy
  Defaults:
    <scale>          = 1e3
    <data_file_name> = det_pix
    <who_to_plot>    = i
''')
  exit() 

# Defaults

dat_file_name = 'det.pix'

scale = 1e3

x_margin = 10
y_margin = 10
who_to_plot = 'i'

# Command line arguments

i = 1
while i < len(sys.argv):
  n = len(sys.argv[i])
  if sys.argv[i] == '-':
    print_help()
    
  if sys.argv[i] == '-scale'[:n]:
    scale = sys.argv[i+1]
    i += 1

  elif sys.argv[i] == '-plot'[:n]:
    who_to_plot = sys.argv[i+1]
    i += 1

  elif sys.argv[i][0] == '-':
    print_help()
    
  else:
    dat_file_name = sys.argv[i]

  i += 1

# Select appropriate column in file to use.
# First column has index 0.

if who_to_plot == 'x':
  p_col = 4
elif who_to_plot == 'y':
  p_col = 6
elif who_to_plot == 'i':
  p_col = 8
elif who_to_plot == 'e':
  p_col = 10
else:
  print_help()

# Read data file parameters in header lines and data file data

dat_file = open (dat_file_name)

for n_header in range(1, 1000):
  line = dat_file.readline()
  if line[0:3] == '#--': break
  print (line.strip())
  exec (line)

dat_file.close()

pix_dat = np.loadtxt(dat_file_name, usecols=(0,1,p_col), skiprows = n_header)

## print(str(pix_dat))

# Create density matrix

nx_min = nx_active_min - x_margin  # For border
nx_max = nx_active_max + x_margin
ny_min = ny_active_min - y_margin  # For border
ny_max = ny_active_max + y_margin

print ('nx min/max: ' + str(nx_min) + ', ' + str(nx_max))
print ('ny min/max: ' + str(ny_min) + ', ' + str(ny_max))

pix_mat = np.zeros((nx_max+1-nx_min, ny_max+1-ny_min))

for pix in pix_dat:
  pix_mat[int(round(pix[0]))-nx_min, int(round(pix[1]))-ny_min] = pix[2]

# And plot

x_min = scale * nx_min * dx_pixel
x_max = scale * nx_max * dx_pixel
y_min = scale * ny_min * dy_pixel
y_max = scale * ny_max * dy_pixel

if 'ix_plot' not in locals(): ix_plot = 0
ix_plot = ix_plot + 1

fig = plt.figure(ix_plot)
ax = fig.add_subplot(111)

if x_max-x_min > y_max - y_min:
  it = max(1, int((y_max-y_min) * 8 / (x_max-x_min)))
  ax.yaxis.set_major_locator(ticker.MaxNLocator(it))
else:
  it = max(1, int((x_max-x_min) * 8 / (y_max-y_min)))
  ax.xaxis.set_major_locator(ticker.MaxNLocator(it))

dens = ax.imshow(np.transpose(pix_mat), origin = 'lower', extent = (x_min, x_max, y_min, y_max))
dens.set_cmap('gnuplot2')

##plt.set_cmap('gnuplot2_r')

fig.colorbar(dens)

plt.show()
