module spacecharge_example_mod

use beam_utils
use open_spacecharge_mod

implicit none

contains

!------------------------------------------------------------------------
!------------------------------------------------------------------------
!------------------------------------------------------------------------
!+
subroutine track1_bunch_spacecharge (bunch, ele, mesh3d, err, s_start, s_end)
implicit none
type (bunch_struct), target :: bunch
type(mesh3d_struct) :: mesh3d
type (ele_struct), target :: ele
type (branch_struct), pointer :: branch
type (ele_struct), save :: runt
type (bunch_params_struct) :: bunch_params
type (coord_struct) :: orb0
type (coord_struct), pointer :: p

real(rp) :: gamma0, beta0, Evec(3)
real(rp), optional :: s_start, s_end  ! Not used yet!

integer :: i, j, i_step, n_step
integer :: iu

character(*), parameter :: r_name = 'track1_bunch_spacecharge'
logical err

err = .true.
branch => ele%branch

if (ele%value(l$) == 0 .or. ele%key == taylor$ .or. bunch%charge_live == 0 ) then
  print *, 'Skipping space charge calc'
  !!ele%csr_calc_on = .false.
  call track1_bunch_hom (bunch, ele, branch%param, bunch)
  bunch%ix_ele = ele%ix_ele
  err = .false.
  return
endif

! n_step is the number of steps to take when tracking through the element.
! csr%ds_step is the true step length.

! Split the usual element steps
n_step = 2*ele%value(num_steps$)

open(newunit=iu, file = 'temp_diagnostics.dat')
write(iu, *) 'step  ds  sigma_x sigma_y sigma_z'

i_step = 0
do 
  i_step = i_step + 1
  
  ! track through the runt
  ! First Half step
  call create_uniform_element_slice (ele, branch%param, i_step, n_step, runt, s_start, s_end)
  call track1_bunch_hom (bunch, runt, branch%param, bunch)
  
  ! Get gamma0
  call calc_bunch_params (bunch, bunch_params, err, print_err = .true.)
  orb0 = bunch_params%centroid
  call convert_pc_to((orb0%vec(6) + 1)*bunch%particle(1)%p0c, bunch%particle(1)%species, gamma = gamma0)
  mesh3d%gamma = gamma0
  
  ! Deposit particles on mesh
  call deposit_particles(bunch%particle%vec(1), bunch%particle%vec(3), bunch%particle%vec(5), &
                          mesh3d, qa=bunch%particle%charge)
  
  ! Space charge calc
  call space_charge_freespace(mesh3d, direct_field_calc=.false., integrated_green_function=.true.)
  !call print_mesh3d(mesh3d)
  
  ! kick
  do i = 1, size(bunch%particle) 
   call spacecharge_kick1( bunch%particle(i), mesh3d, 2*runt%value(L$))
  enddo
  
  ! Second Half step
  i_step = i_step + 1
  call create_uniform_element_slice (ele, branch%param, i_step, n_step, runt, s_start, s_end)
  call track1_bunch_hom (bunch, runt, branch%param, bunch)


  ! Diagnostics
  call calc_bunch_params (bunch, bunch_params, err, print_err = .true.)
  write(iu, *) i_step*runt%value(L$), sqrt(bunch_params%sigma(1,1)), &
      sqrt(bunch_params%sigma(3,3)), &
      sqrt(bunch_params%sigma(5,5))

  if (i_step == n_step) exit

enddo

close(iu)

bunch%ix_ele = ele%ix_ele

err = .false.

end subroutine  


!------------------------------------------------------------------------
!------------------------------------------------------------------------
!------------------------------------------------------------------------
!+
subroutine spacecharge_kick1(orb, mesh3d, ds)
type (coord_struct) :: orb
type(mesh3d_struct) :: mesh3d
real(rp) :: Evec(3), factor, ds, pz0

! Interpolate field at this particle
call interpolate_field(orb%vec(1), orb%vec(3), orb%vec(5),  mesh3d, E=Evec)

! Step size factor
factor = ds/(orb%p0c  * orb%beta) ! *-charge_of(orb%species)*

pz0 = sqrt( (1.0_rp + orb%vec(6))**2 - orb%vec(2)**2 - orb%vec(4)**2 ) ! * p0 

! Considering magnetic field also, effectively reduces this force by 1/gamma^2
orb%vec(2) = orb%vec(2) + Evec(1)*factor / mesh3d%gamma**2
orb%vec(4) = orb%vec(4) + Evec(2)*factor / mesh3d%gamma**2
orb%vec(6) = sqrt(orb%vec(2)**2 + orb%vec(4)**2 + (Evec(3)*factor + pz0)**2) -1.0_rp

! Set beta
call convert_pc_to (orb%p0c * (1 + orb%vec(6)), orb%species, beta = orb%beta)

end subroutine




!------------------------------------------------------------------------
!------------------------------------------------------------------------
!------------------------------------------------------------------------
!+
subroutine write_space_charge_lines(bunch, mesh3d, label)
type(bunch_struct) :: bunch
type(mesh3d_struct) :: mesh3d
character(*), optional :: label
character(20) :: suffix
character(40) :: fname
integer :: i, j, k, iu
real(rp) :: x, y, z, Evec(3)

!------------------------------------------
! initialize mesh
print *, 'depositing bunch...'             
call deposit_particles(bunch%particle%vec(1), bunch%particle%vec(3), bunch%particle%vec(5), &
                          mesh3d, qa=bunch%particle%charge)         
print *, '...done'

if (present(label)) then
  suffix = label
else
  suffix = '.dat'
endif

fname = 'charge_z'//trim(suffix)
open(newunit=iu, file = fname)

! Line along z
i = mesh3d%nhi(1)/2
j = mesh3d%nhi(2)/2
do k = 1,  mesh3d%nhi(3)
  z = mesh3d%min(3)+ (k-1)* mesh3d%delta(3)
  write(iu, *)  z,  mesh3d%rho(i,j,k)
enddo
close(iu)

!------------------------------------------
! space charge calc
call space_charge_freespace(mesh3d)

fname='field_z_Ez'//trim(suffix)
open(newunit=iu, file = fname)
do k = 1,  mesh3d%nhi(3)-1
  z = mesh3d%min(3)+ (k-1)* mesh3d%delta(3)
  call interpolate_field(0.0_rp, 0.0_rp, z, mesh3d, E=Evec)
  write(iu, *)  z,  mesh3d%efield(i,j,k,3), Evec(3)
enddo
close(iu)

fname='field_x_Ex'//trim(suffix)
j = mesh3d%nhi(2)/2
k = mesh3d%nhi(3)/2
open(newunit=iu, file = fname)
do i = 1,  mesh3d%nhi(1)-1
  x = mesh3d%min(1)+ (i-1)* mesh3d%delta(1)
  call interpolate_field(x, 0.0_rp, 0.0_rp,  mesh3d, E=Evec)
  write(iu, *)  x,  mesh3d%efield(i,j,k,1), Evec(1)
enddo
close(iu)

fname='field_y_Ey'//trim(suffix)
i = mesh3d%nhi(1)/2
k = mesh3d%nhi(3)/2
open(newunit=iu, file = fname)
do j = 1,  mesh3d%nhi(2)-1
  y = mesh3d%min(2)+ (j-1)* mesh3d%delta(2)
  call interpolate_field(0.0_rp, y, 0.0_rp, mesh3d, E=Evec)
  write(iu, *)  y,  mesh3d%efield(i,j,k,2), Evec(2)
enddo
close(iu)

end subroutine


end module
