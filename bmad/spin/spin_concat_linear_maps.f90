!+
! Subroutine spin_concat_linear_maps (map1, branch, n1, n2, q_ele, orbit)
!
! Routine to concatenate element spin/orbit maps in the range branch%ele(n1+1:n2)
! This routine will wrap around the ends of the lattice so n2 may be less than n1.
! In this case the range will be [n1+1:end] + [beginning:n2].
!
! If a Taylor map exists for an individual element, that map will be reused.
! If not, a new map will be made for the element. If a map is made, orbit(:) will be 
! used as the reference orbit. If it is not present, ele%map_ref_orb_in will be used.
!
! Input:
!   branch    -- branch_struct: Lattice branch.
!   n1        -- integer: Starting element index. Start at element downstream end.
!   n2        -- integer: Ending element index. End at element downstream end
!   orbit(0:) -- coord_struct, optional: Reference orbit used if maps must be created.
!
! Output:
!   map1     -- spin_orbit_map1_struct: Map with element spin/orbit maps concatenated.
!   q_ele(:)  -- spin_orbit_map1_struct, optional: Individual spin/orbit maps.
!-

subroutine spin_concat_linear_maps (map1, branch, n1, n2, map1_ele, orbit)

use ptc_interface_mod, dummy => spin_concat_linear_maps

implicit none

type (spin_orbit_map1_struct) map1
type (spin_orbit_map1_struct), optional :: map1_ele(:)
type (branch_struct), target :: branch
type (coord_struct), optional :: orbit(0:)

integer n1, n2

!

call map1_make_unit(map1)

if (n2 <= n1) then
  call concat_this_map(n1+1, branch%n_ele_track)
  call concat_this_map(1, n2)
else
  call concat_this_map(n1+1, n2)
endif

call spin_map1_normalize(map1%spin_q)

!------------------------------------------------------
contains

subroutine concat_this_map(n1, n2)

type (ele_struct), pointer :: ele
type (taylor_struct), pointer :: st
type (spin_orbit_map1_struct) q1

real(rp) vec0(6), ref_orb(6)
integer n1, n2
integer ie, i, k, n, p
logical st_on

!

do ie = n1, n2
  if (ie == 0) cycle
  ele => branch%ele(ie)

  if (present(orbit)) then
    ref_orb = orbit(ie-1)%vec
  else
    ref_orb = 0
  endif

  if (.not. associated(ele%spin_taylor(0)%term)) then
    st_on = bmad_com%spin_tracking_on
    bmad_com%spin_tracking_on = .true.
    if (present(orbit)) then
      call ele_to_taylor(ele, branch%param, orbit(ie-1), include_damping = bmad_com%radiation_damping_on)
    else
      call ele_to_taylor(ele, branch%param, ele%map_ref_orb_in, include_damping = bmad_com%radiation_damping_on)
    endif
    bmad_com%spin_tracking_on = st_on
  endif

  q1%spin_q = spin_taylor_to_linear(ele%spin_taylor, ref_orb - ele%spin_taylor_ref_orb_in)

  call taylor_to_mat6 (ele%taylor, ref_orb, vec0, q1%orb_mat)
  if (present(map1_ele)) then
    map1_ele(ie) = q1
  endif

  map1 = q1 * map1
enddo

end subroutine

end subroutine
