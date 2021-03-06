!+
! Subroutine track_a_beambeam (orbit, ele, param, mat6, make_matrix)
!
! Bmad_standard tracking through a beambeam element. 
!
! Input:
!   orbit       -- Coord_struct: Starting position.
!   ele         -- ele_struct: Beambeam element.
!   param       -- lat_param_struct: Lattice parameters.
!   make_matrix -- logical, optional: Propagate the transfer matrix? Default is false.
!
! Output:
!   orbit      -- coord_struct: End position.
!   mat6(6,6)  -- real(rp), optional: Transfer matrix through the element.
!-

subroutine track_a_beambeam (orbit, ele, param, mat6, make_matrix)

use fringe_mod, except_dummy => track_a_beambeam

implicit none

type (coord_struct) :: orbit
type (ele_struct), target :: ele
type (lat_param_struct) :: param
type (em_field_struct) field

real(rp), optional :: mat6(6,6)
real(rp) sig_x, sig_y, x_center, y_center
real(rp) s_pos, s_pos_old, k0_x, k0_y, k_xx1, k_xy1, k_yx1, k_yy1, k_xx2, k_xy2, k_yx2, k_yy2, coef, del
real(rp) mat21, mat23, mat41, mat43, del_s, x_pos, y_pos, ratio, bbi_const, z
real(rp), allocatable :: z_slice(:)
real(rp) om(3), quat(0:3)

integer i, n_slice

logical, optional :: make_matrix

character(*), parameter :: r_name = 'track_a_beambeam'

!

if (ele%value(charge$) == 0 .or. param%n_part == 0) return

if (logic_option(.false., make_matrix)) call mat_make_unit(mat6)

del = 0.001
if (ele%value(sig_x$) == 0 .or. ele%value(sig_x$) == 0) then
  call out_io (s_error$, r_name, 'STRONG BEAM SIGMAS NOT SET FOR BEAMBEAM ELEMENT: ' // ele%name, &
                                 'PARTICLE WILL BE MARKED AS LOST.')
  orbit%state = lost$
  return
endif

call offset_particle (ele, set$, orbit)
call canonical_to_angle_coords (orbit)

n_slice = max(1, nint(ele%value(n_slice$)))
allocate(z_slice(n_slice))
call bbi_slice_calc (ele, n_slice, z_slice)

s_pos = 0    ! end at the ip

do i = 1, n_slice
  z = z_slice(i)   ! Positive z_slice is the tail of the strong beam.
  s_pos_old = s_pos
  s_pos = (orbit%vec(5) + z) / 2
  del_s = s_pos - s_pos_old

  call track_a_drift (orbit, del_s, mat6, make_matrix)

  call strong_beam_sigma_calc (ele, s_pos, -z, sig_x, sig_y, bbi_const, x_center, y_center)

  ratio = sig_y / sig_x

  x_pos = (orbit%vec(1) - x_center) / sig_x
  y_pos = (orbit%vec(3) - y_center) / sig_y

  call bbi_kick (x_pos, y_pos, ratio, k0_x, k0_y)

  coef = bbi_const / (n_slice * (1 + orbit%vec(6)))
  orbit%vec(2) = orbit%vec(2) + k0_x * coef
  orbit%vec(4) = orbit%vec(4) + k0_y * coef

  if (logic_option(.false., make_matrix)) then
    call bbi_kick (x_pos-del, y_pos, ratio, k_xx1, k_yx1)
    call bbi_kick (x_pos, y_pos-del, ratio, k_xy1, k_yy1)
    call bbi_kick (x_pos+del, y_pos, ratio, k_xx2, k_yx2)
    call bbi_kick (x_pos, y_pos+del, ratio, k_xy2, k_yy2)

    coef = bbi_const / (ele%value(n_slice$) * del * (1 + orbit%vec(6)))
    mat21 = coef * (k_xx2 - k_xx1) / (2 * sig_x)
    mat23 = coef * (k_xy2 - k_xy1) / (2 * sig_y)
    mat41 = coef * (k_yx2 - k_yx1) / (2 * sig_x)
    mat43 = coef * (k_yy2 - k_yy1) / (2 * sig_y)

    mat6(2,:) = mat6(2,:) + mat21 * mat6(1,:) + mat23 * mat6(3,:)
    mat6(4,:) = mat6(4,:) + mat41 * mat6(1,:) + mat43 * mat6(3,:)
  endif

  if (bmad_com%spin_tracking_on) then
    field%E = [ k0_x, k0_y, 0.0_rp] * orbit%p0c * orbit%beta / (2 * charge_of(orbit%species))
    field%B = [-k0_y, k0_x, 0.0_rp] * orbit%p0c / (2 * c_light * charge_of(orbit%species))
    om = spin_omega (field, orbit, +1)
    quat = omega_to_quat(om)
    orbit%spin = quat_rotate(quat, orbit%spin)
  endif
enddo

call track_a_drift (orbit, -s_pos, mat6, make_matrix)

call angle_to_canonical_coords (orbit)
call offset_particle (ele, unset$, orbit)  

end subroutine

