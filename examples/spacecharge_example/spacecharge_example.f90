program spacecharge_example

use beam_mod
use spacecharge_example_mod
use open_spacecharge_mod
use time_tracker_mod

implicit none

type (lat_struct), target :: lat
type (branch_struct), pointer :: branch
type (ele_struct), pointer :: ele
type (coord_struct) :: orb0
type(bunch_struct) :: bunch, bunch1
type (beam_init_struct) :: beam_init
type (bunch_params_struct) :: bunch_params

type (mesh3d_struct) :: mesh3d

real(rp) :: gamma0, x, y, z, sig_x, sig_y, sig_z, Evec(3)

integer :: ix_bunch = 1, n
integer :: namelist_file, n_char, open_status
integer :: i, j, k, nx, ny, nz
logical :: err, diagnostics
integer :: iu
character(100) :: lat_name, lat_path, base_name, in_file
character(30), parameter :: r_name = 'spacecharge_example'

namelist / spacecharge_example_params / &
    lat_name, beam_init, nx, ny, nz, diagnostics

!------------------------------------------
!Defaults for namelist
lat_name = 'lat.bmad'
nx = 64
ny = 64
nz = 64
diagnostics = .true.
beam_init%species = 'electron'
beam_init%n_particle = 100000
beam_init%random_engine = 'quasi' ! or: 'pseudo'
beam_init%a_emit = 1e-9
beam_init%b_emit = 1e-9
beam_init%sig_pz = 1e-9
beam_init%sig_z  = 1e-4
beam_init%bunch_charge        = 1e-9
beam_init%random_sigma_cutoff = 4

!Read namelist
in_file = 'spacecharge_example.in'
if (command_argument_count() > 0) call get_command_argument(1, in_file)
open(newunit=namelist_file, file = in_file, status = 'old', iostat=open_status)
if (open_status /= 0) then
  print *, 'Input file missing: ', in_file
  print *, 'Using defaults'
else 
  read (namelist_file, nml = spacecharge_example_params)
  close (namelist_file)
endif

!Trim filename
n_char= SplitFileName(lat_name, lat_path, base_name) 

!Parse Lattice
call bmad_parser (lat_name, lat)
branch => lat%branch(0)

ele => lat%ele(0)

!------------------------------------------
! Initialize bunch and calc some statistics

call init_bunch_distribution (ele, lat%param, beam_init, ix_bunch, bunch)

bunch_params%centroid%p0c =  ele%value(p0c_start$)
print *, 'bunch%particle(99)%p0c: ', bunch%particle(99)%p0c
print *, 'bunch_params%centroid%p0c: ', bunch_params%centroid%p0c
call calc_bunch_params (bunch, bunch_params, err, .true.)
print *, 'bunch%n_live: ', bunch%n_live
print *, 'bunch%charge_live : ', bunch%charge_live 

orb0 = bunch_params%centroid
call convert_pc_to((orb0%vec(6) + 1)*orb0%p0c, bunch%particle(1)%species, gamma = gamma0)

sig_x = sqrt(bunch_params%sigma(1,1))
sig_y = sqrt(bunch_params%sigma(3,3))
sig_z = sqrt(bunch_params%sigma(5,5))

print *, 'charge_tot', bunch%charge_tot
print *, 'charge_live', bunch%charge_live
print *, 'sigma_x, y, z: ', sig_x, sig_y, sig_z
print *, 'vec0: ', bunch_params%centroid%vec
print *, 'p0c:, ', orb0%p0c
print *, 'gamma0:', gamma0

print *, 'x (min, max)/sig:',  minval(bunch%particle%vec(1))/sig_x, maxval(bunch%particle%vec(1))/sig_x
print *, 'y (min, max)/sig:',  minval(bunch%particle%vec(3))/sig_y, maxval(bunch%particle%vec(3))/sig_y
print *, 'z (min, max)/sig:',  minval(bunch%particle%vec(5))/sig_z, maxval(bunch%particle%vec(5))/sig_z

!------------------------------------------
! Write to file for comparison with Astra
iu=lunget()
open(iu, file = 'beginning_astra.particles')
call write_time_particle_distribution  (iu, bunch, ele, 'ASTRA', branch)
print *, 'Written: beginning_astra.particles'
close(iu)

! Assign test particle
bunch%particle(1)%vec(1) = sig_x
bunch%particle(1)%vec(2:6) = 0

!------------------------------------------
! initialize mesh
mesh3d%nhi = [nx, ny, nz]
print *, 'n: ', mesh3d%nhi

! Track
bunch1 = bunch
do n = 1, branch%n_ele_track
  ele => branch%ele(n)
  print *, 'track1_bunch_spacecharge, ele = '//trim(ele%name)
  call track1_bunch_spacecharge (bunch1, ele, mesh3d, err)  
enddo


call calc_bunch_params (bunch1, bunch_params, err, print_err = .true.)
print *, 'End: sigma_x,y,z', sqrt(bunch_params%sigma(1,1)), sqrt(bunch_params%sigma(3,3)), sqrt(bunch_params%sigma(5,5))

open(iu, file = 'end.particles')
ele => branch%ele(bunch1%ix_ele)
print *, 'final bunch is at: ', trim(ele%name), ele%ix_ele
call write_time_particle_distribution  (iu, bunch1, ele, 'ASTRA', branch)
close(iu)


if (diagnostics) then
  ! Write e-field on lines around initial bunch
  call write_space_charge_lines(bunch, mesh3d, label='.dat')
endif

end program
