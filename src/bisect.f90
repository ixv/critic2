! Copyright (c) 2015 Alberto Otero de la Roza <aoterodelaroza@gmail.com>,
! Ángel Martín Pendás <angel@fluor.quimica.uniovi.es> and Víctor Luaña
! <victor@fluor.quimica.uniovi.es>. 
!
! critic2 is free software: you can redistribute it and/or modify
! it under the terms of the GNU General Public License as published by
! the Free Software Foundation, either version 3 of the License, or (at
! your option) any later version.
! 
! critic2 is distributed in the hope that it will be useful,
! but WITHOUT ANY WARRANTY; without even the implied warranty of
! MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
! GNU General Public License for more details.
! 
! You should have received a copy of the GNU General Public License
! along with this program.  If not, see <http://www.gnu.org/licenses/>.

!> Integration and plotting of basins through bisection.
module bisect
  use global, only: INT_gauleg, INT_lebedev

  private 

  public :: basinplot
  public :: bundleplot
  public :: sphereintegrals
  public :: sphereintegrals_gauleg, sphereintegrals_lebedev
  public :: integrals

  integer, parameter :: maxpointscb(0:7) =  (/ 8, 26, 98, 386, 1538, 6146, 24578, 98306 /)
  integer, parameter :: maxfacescb(0:7) =   (/ 6, 24, 96, 384, 1536, 6144, 24576, 98304 /)
  integer, parameter :: maxpointstr(0:7) =  (/ 6, 18,  66, 258, 1026, 4098, 16386, 66003  /)
  integer, parameter :: maxfacestr(0:7) =   (/ 8, 32, 128, 512, 2048, 8192, 32768, 131072 /)
  integer, parameter :: progressivefactor = 3

  ! IAS representation files, intialized by integrals, uesd by its auxiliary routines
  character(len=1024), allocatable :: intfile(:)

  ! maximum num. of steps in gradient path tracing
  integer, parameter :: BS_mstep = 6000

  ! near-nuc
  real*8, parameter :: bs_rnearnuc2_grid = 5d-1
  real*8, parameter :: bs_rnearnuc_grid = sqrt(bs_rnearnuc2_grid)
  real*8, parameter :: bs_rnearnuc2 = 1d-5
  real*8, parameter :: bs_rnearnuc = sqrt(bs_rnearnuc2)

  ! default integratin parameters for atomic spheres
  integer, parameter :: bs_spherequad_type = INT_lebedev
  integer, parameter :: bs_spherequad_ntheta = 30
  integer, parameter :: bs_spherequad_nphi = 30
  integer, parameter :: bs_spherequad_nleb = 170

contains

  !> Determine the limit of the zero flux surface. xnuc are the
  !> coordinates of the cp generating the atomic basin. xin, xfin the
  !> lower and upper bounds for the radial coordinate. delta, the
  !> precision of the surface determination.  xmed is the final point
  !> on the IAS. All xnuc, xin, xfin and xmed are given in
  !> crystallographic coordinates. The cpid is an index from the non
  !> -equivalent CP list
  subroutine lim_surf (cpid, xin, xfin, delta, xmed, tstep, nwarn)
    use navigation
    use fields
    use varbas
    use global
    use struct_basic
    use tools_io
    implicit none

    integer, intent(in) :: cpid
    real*8, dimension(3), intent(in) :: xin, xfin
    real*8, intent(in) :: delta
    real*8, dimension(3), intent(out) :: xmed
    integer, intent(out) :: tstep
    integer, intent(inout) :: nwarn

    real*8 :: dist2, delta2
    real*8, dimension(3) :: xpoint, xnuc
    integer :: nstep, iup
    integer :: i, imin, ier
    real*8 :: xtemp(3), dtemp
    real*8 :: xin_(3), xfin_(3)
    real*8 :: bsr, bsr2

    ! define the close-to-nucleus condition
    if (f(refden)%type == type_grid) then
       bsr2 = bs_rnearnuc2_grid
       bsr = bs_rnearnuc_grid
    else
       bsr2 = bs_rnearnuc2
       bsr = bs_rnearnuc
    end if

    tstep = 0
1   continue
    xin_ = xin
    xfin_ = xfin

    delta2 = delta * delta
    xnuc = cr%x2c(cp(cpid)%x)

    iup = -sign(1,f(refden)%typnuc)

    ! do bisection between xin and xfin, until they converge within delta
    dist2 = dot_product(xin_-xfin_,xin_-xfin_)
    do while (dist2 > delta2)
       xmed = 0.5d0 * (xin_ + xfin_)

       xpoint = xmed
       call gradient(f(refden),xpoint,iup,nstep,BS_mstep,ier,0,up2beta=.true.)
       tstep = tstep + nstep

       if (ier <= 0) then
          ! normal gradient termination
          xpoint = xpoint - xnuc

          dist2 = dot_product(xpoint,xpoint)
          if (dist2 <= bsr2) then
             xin_ = xmed
          else
             xfin_ = xmed
          endif
       elseif (ier == 3) then
          ! the gradient started at infinity (molecule)
          xfin_ = xmed
       else
          ! error in gradient. Calculate the nearest nucleus
          if (ier > 0) nwarn = nwarn + 1
          xpoint = cr%c2x(xpoint)
          call nearest_cp(xpoint,imin,dtemp,f(refden)%typnuc)
          if (dtemp <= bsr) then
             xin_ = xmed
          else
             xfin_ = xmed
          endif
       end if
       dist2 = dot_product(xin_-xfin_,xin_-xfin_)
    enddo
    xmed = 0.5d0 * (xin_ + xfin_)

    ! check if it is on the surface of a beta-sphere 
    xpoint = cr%c2x(xmed)

    ! check if it is inside a beta-sphere
    do i = 1, ncpcel
       if (cpcel(i)%typ /= cp(cpid)%typ) cycle
       xtemp = cpcel(i)%x - xpoint
       call cr%shortest(xtemp,dtemp)
       dtemp = sqrt(dtemp)
       if (dtemp <= cp(cpcel(i)%idx)%rbeta ) then
          cp(cpcel(i)%idx)%rbeta = 0.75d0 * cp(cpcel(i)%idx)%rbeta
          ! start over again
          goto 1
       end if
    end do

  end subroutine lim_surf

  !> Determine by bisection the limit of the primary bundle around
  !> x0() with up-limit in xup(), dn-limit in xdn(), along the
  !> line that connects xin() and xfin(), with precision delta; the
  !> limit is returned in xmed(). All parameters in cartesian
  !> coordinates. nstep is the number of function evaluations.
  subroutine lim_bundle (xup, xdn, xin, xfin, delta, xmed, tstep, nwarn)
    use navigation
    use varbas
    use fields
    use struct_basic
    use global
    use tools_io
    implicit none
    !
    real*8, intent(in) :: xup(3), xdn(3)
    real*8, intent(inout) :: xin(3), xfin(3)
    real*8, intent(in) :: delta
    real*8, intent(out) :: xmed(3)
    integer, intent(out) :: tstep
    integer, intent(inout) :: nwarn

    real*8 :: xpoint(3), delta2, rr2
    integer :: nstep
    integer :: ier
    logical :: inbundle
    real*8 :: bsr, bsr2

    ! define the close-to-nucleus condition
    if (f(refden)%type == type_grid) then
       bsr2 = bs_rnearnuc2_grid
       bsr = bs_rnearnuc_grid
    else
       bsr2 = bs_rnearnuc2
       bsr = bs_rnearnuc
    end if

    tstep = 0
    delta2 = delta * delta

    do while (dot_product(xin-xfin,xin-xfin) >= delta2)

       !.take mean value, test if interior
       xmed = 0.5d0*(xin+xfin)

       !.alpha limit
       xpoint = xmed

       call gradient(f(refden),xpoint,+1,nstep,BS_mstep,ier,0,up2beta=.true.)
       tstep = tstep + nstep
       if (ier == 3) then
          inbundle = .false.
       else 
          if (ier > 0) nwarn = nwarn + 1
          xpoint = xpoint - xup
          rr2 = dot_product(xpoint,xpoint)
          inbundle = (rr2 <= bsr2)
       endif

       !.omega limit
       if (inbundle) then
          xpoint = xmed
          call gradient(f(refden),xpoint,-1,nstep,BS_mstep,ier,0,up2beta=.true.)
          tstep = tstep + nstep
          if (ier == 3) then
             inbundle = .false.
          else
             if (ier > 0) nwarn = nwarn + 1
             xpoint = xpoint - xdn
             rr2 = dot_product(xpoint,xpoint)
             inbundle = inbundle .and. (rr2 <= bsr2)
          endif
       endif

       !.bipartition
       if (inbundle) then
          xin = xmed
       else
          xfin = xmed
       endif
    enddo

    !.Final value
    xmed = 0.5d0 * (xin+xfin)
    !
  end subroutine lim_bundle

  !> The rays contained in the input minisurface srf are lim_surfed up
  !> to the IAS of the CP cpid (non-equivalent CP list). Adaptive
  !> bracketing + bisection.
  subroutine bisect_msurface(srf,cpid,prec,verbose)
    use navigation
    use surface
    use fields
    use varbas
    use global
    use struct_basic
    use tools
    use tools_io
    use types
    use param
    implicit none

    integer, intent(in) :: cpid
    type(minisurf), intent(inout) :: srf
    real*8, intent(in) :: prec
    logical, intent(in) :: verbose

    integer, parameter :: ntries = 7

    real*8  :: xin(3), xfin(3), xcar(3), unit(3)
    real*8  :: xmed(3), xnuc(3), xtemp(3)
    real*8  :: rr2, raprox, riaprox, rmin, rminsame
    real*8  :: rtry(ntries), rother
    integer :: itry(ntries)
    integer :: iup, nstep, id1, id2
    integer :: j, k, idone
    real*8  :: rnearsum, rfarsum, rzfssum, rnearmin, rfarmax, rlim
    integer :: ier, nwarn, nwarn0
    real*8 :: bsr, bsr2

    ! define the close-to-nucleus condition
    if (f(refden)%type == type_grid) then
       bsr2 = bs_rnearnuc2_grid
       bsr = bs_rnearnuc_grid
    else
       bsr2 = bs_rnearnuc2
       bsr = bs_rnearnuc
    end if

    iup = -sign(1,f(refden)%typnuc)

    xcar = cp(cpid)%x
    xnuc = xcar
    xcar = cr%x2c(xcar)

    ! get the distance to the nearest cp and the nearest cp of the
    ! same type
    rmin = VBIG
    rminsame = VBIG
    do j = 1, ncpcel
       xtemp = cpcel(j)%x - xnuc
       call cr%shortest(xtemp,rr2)
       if (rr2 < 1d-10) cycle
       if (rr2 < rmin) rmin = rr2
       if (rr2 < rminsame .and. cpcel(j)%typ == cp(cpid)%typ) rminsame = rr2
    end do
    rmin = sqrt(rmin)
    rminsame = sqrt(rminsame)
    rnearsum = 0d0
    rfarsum = 0d0
    rzfssum = 0d0
    rnearmin = VBIG
    rfarmax = 0d0

    if (verbose) then
       write (uout,'("+ Starting bisection ")')
       write (uout,'("  CP (non-equivalent) : ",I4)') cpid
       write (uout,'("  GP tracing maximum num. of steps : ",I6)') BS_mstep
       write (uout,*)
       write (uout,'(A)') "r0_{near} ids: (0)One r0_{far}  (1)2d-5    (2)0.9*(rminCP)      (3)0.99*(rminCP) "
       write (uout,'(A)') "               (4)0.9*(last r_{zfs}) (5)0.99* min(r_{near}) (6) mean(r_{near}) "
       write (uout,'(A)') "               (7) 0.8*mean(r_{zfs})"
       write (uout,'(A)') "r0_{far} ids : (0)One r0_{near} (1)min(aa) (2)0.99*(rminCPsame) (3)0.75*(rminCPsame) "
       write (uout,'(A)') "               (4)1.1*(last r_{zfs}) (5)1.01* max(r_{far})  (6) mean(r_{far}) "
       write (uout,'(A)') "               (7) 1.2*mean(r_{zfs})"
       write (uout,'("Units: ",A)') string(iunitname0(iunit))
       write (uout,'("* (",A5,"/",A5,") ",4(A12,2X))') "nray","total","r0_{near}","r_{ZFS}","r0_{far}","nsteps"
    end if

    idone = 0
    nwarn = 0
    nwarn0 = 0
    !$omp parallel do private(unit,raprox,rother,riaprox,rtry,itry,id1,id2,&
    !$omp xin,xtemp,ier,rr2,xfin,nstep,xmed,rlim,nwarn) schedule(guided)
    do j = 1, srf%nv
       nwarn = 0
       ! skip surfed points
       if (srf%r(j) > 0d0) cycle

       ! unitary vector for the direction of the ray
       unit = (/ sin(srf%th(j)) * cos(srf%ph(j)),&
                 sin(srf%th(j)) * sin(srf%ph(j)),&
                 cos(srf%th(j)) /)

       ! initialize bracket
       raprox = VBIG
       rother = VBIG
       riaprox = 0d0
       ! possible initial radii for inner point
       rtry(1) = 2d-5                   ! very poor
       rtry(2) = 0.9d0 * rmin           ! 90% to nearest CP
       rtry(3) = 0.99d0 * rmin          ! 99% to nearest CP
       if (idone > 0) then
          rtry(4) = 0.99d0 * rnearmin      ! 99% of the nearest initial point up to now
          rtry(5) = rnearsum / real(idone,8) ! mean of the in-basin initial points up to now
          rtry(6) = 0.8d0*rzfssum / real(idone,8) ! 80% of the mean of the r_{zfs} up to now
          rtry(7) = 0d0  ! really REALLY poor
       else
          rtry(4) = 0d0                 ! VERY poor
          rtry(5) = 0d0
          rtry(6) = 0d0
          rtry(7) = 0d0
       end if
       itry = (/ (k,k=1,ntries) /)           ! sort from smaller to larger
       call mergesort(rtry,itry)
       id1 = 0
       do k = ntries,1,-1                    ! find best initial point
          riaprox = rtry(itry(k))
          xin = xcar + riaprox * unit
          xtemp = xin
          call gradient(f(refden),xtemp,iup,nstep,BS_mstep,ier,0,up2beta=.true.)
          if (ier == 3) then
             ! started outside molcell
             if (rtry(itry(k)) < rother) rother = rtry(itry(k))
          else
             if (ier > 0) nwarn = nwarn + 1
             xtemp = xtemp - xcar
             rr2 = dot_product(xtemp,xtemp)
             if (rr2 <= bsr2) then
                id1 = itry(k)
                exit
             else
                if (rtry(itry(k)) < rother) rother = rtry(itry(k))
             end if
          endif
       end do

       ! possible initial radii for outer point
       rtry(1) = min(cr%aa(1),cr%aa(2),cr%aa(3)) ! very poor
       rtry(2) = 0.99d0 * rminsame      ! 99% to nearest same type CP 
       rtry(3) = 0.75d0 * rminsame      ! 75% to nearest same type CP 
       if (idone > 0) then
          rtry(4) = 1.01d0 * rfarmax       ! 101% of the farthest initial point up to now
          rtry(5) = rfarsum / real(idone,8)  ! mean of the out-basin initial points up to now
          rtry(6) = 1.2d0*rzfssum / real(idone,8) ! 120% of the mean of the r_{zfs} up to now
          rtry(7) = max(cr%aa(1),cr%aa(2),cr%aa(3)) ! really, REALLY poor
       else
          rtry(4) = max(cr%aa(1),cr%aa(2),cr%aa(3))  ! VERY poor
          rtry(5) = max(cr%aa(1),cr%aa(2),cr%aa(3))  
          rtry(6) = max(cr%aa(1),cr%aa(2),cr%aa(3))  
          rtry(7) = max(cr%aa(1),cr%aa(2),cr%aa(3))  
       end if
       itry = (/ (k,k=1,ntries) /)       ! sort from smaller to larger
       call mergesort(rtry,itry)
       id2 = 0
       raprox = rother
       do k = 1,ntries                   ! find best initial point
          ! If I already have a bracket, the try must be better than a bisection step. 
          ! Note that raprox is initialized to VBIG, so in case I do not have a bracket, 
          ! all the rtrys are tested
          raprox = rtry(itry(k))
          if (raprox > (rother+riaprox) / 2d0 .or. raprox < riaprox) then
             raprox = rother
             cycle  
          end if
          xfin = xcar + raprox * unit
          xtemp = xfin
          call gradient (f(refden),xtemp,iup,nstep,BS_mstep,ier,0,up2beta=.true.)
          if (ier == 3)  then
             ! started outside molcell
             ! it is in the inner part of the basin: is it better than riaprox?
             if (raprox > riaprox) then
                id1 = 0
                riaprox = raprox
             end if
             ! default to rother
             raprox = rother
          else
             if (ier > 0) nwarn = nwarn + 1
             xtemp = xtemp - xcar
             rr2 = dot_product(xtemp,xtemp)
             if (rr2 > bsr2) then
                id2 = itry(k)
                exit
             else
                ! it is in the inner part of the basin: is it better than riaprox?
                if (raprox > riaprox) then
                   id1 = 0
                   riaprox = raprox
                end if
                ! default to rother
                raprox = rother
             end if
          end if
       end do

       ! Use final riaprox and raprox
       if (raprox == VBIG .or. riaprox == 0d0) then
          call ferror('bisect_msurface','Can not find ray limits.',faterr)
       else
          xin = xcar + riaprox * unit
          xfin = xcar + raprox * unit
       end if

       call lim_surf(cpid,xin,xfin,prec,xmed,nstep,nwarn)
       xmed = xmed - xcar
       rlim = sqrt(dot_product(xmed,xmed))
       if (verbose) then
          !$omp critical (IO)
          write (uout,'("  (",I5,"/",I5,") ",E14.6,1X,"(",I1,")",1X,E14.6,2X,E14.6,1X,"(",I1,") ",I8)') &
             j,srf%nv,riaprox*dunit,id1,rlim*dunit,raprox*dunit,id2,nstep
          !$omp end critical (IO)
       end if

       ! accumulate 
       !$omp ATOMIC
       nwarn0 = nwarn0 + nwarn
       !$omp ATOMIC
       rnearsum = rnearsum + riaprox
       !$omp ATOMIC
       rfarsum = rfarsum + raprox
       !$omp ATOMIC
       rzfssum = rzfssum + rlim
       !$omp ATOMIC
       rnearmin = min(rnearmin,riaprox)
       !$omp ATOMIC
       rfarmax = max(rfarmax,raprox)
       !$omp ATOMIC
       idone = idone + 1
       !$omp critical (srfwrite)
       srf%r(j) = rlim
       !$omp end critical (srfwrite)
    enddo
    !$omp end parallel do

    if (verbose) then
       if (nwarn0 > 0) then
          write (uout,'("+ nwarns = ",I8)') nwarn0
          ! call ferror('bisect_msurface',"Some gradient paths were not terminated",warning)
       end if
       write (uout,'(A/)') "+ End of bisection "
    end if

  end subroutine bisect_msurface

  !> Determine the surface representing the primary bundle with seed
  !> srf%n (cartesian) by bisection.
  subroutine bundle_msurface(srf,prec,verbose)
    use surface
    use navigation
    use fields
    use varbas
    use global
    use struct_basic
    use tools_math
    use tools_io
    use types
    use param
    implicit none

    type(minisurf), intent(inout) :: srf
    real*8, intent(in) :: prec
    logical, intent(in) :: verbose

    integer :: i, j, nwarn, nwarn0
    integer :: nstep, iup, ier
    real*8 :: xtemp(3), xseed(3), xup(3), xdn(3), xin(3), xfin(3)
    real*8 :: xmed(3), unit(3), raprox, riaprox
    logical :: ok
    real*8 :: oldrbeta(ncp), rmin, rmax
    real*8 :: bsr, bsr2

    ! define the close-to-nucleus condition
    if (f(refden)%type == type_grid) then
       bsr2 = bs_rnearnuc2_grid
       bsr = bs_rnearnuc_grid
    else
       bsr2 = bs_rnearnuc2
       bsr = bs_rnearnuc
    end if

    iup = -sign(1,f(refden)%typnuc)

    xseed = srf%n

    ! beta spheres + primary bundles is not such a good idea.
    oldrbeta = cp(1:ncp)%rbeta
    cp(1:ncp)%rbeta = Rbetadef

    ! alpha-limit
    xtemp = xseed
    call gradient (f(refden),xtemp,+1,nstep,BS_mstep,ier,0,up2beta=.true.)
    xup = xtemp
    ! omega-limit
    xtemp = xseed
    call gradient (f(refden),xtemp,-1,nstep,BS_mstep,ier,0,up2beta=.true.)
    xdn = xtemp

    if (verbose) then
       write (uout,'("+ Starting bisection (primary bundle)")')
       write (uout,'("  Seed (cartesian coords.) : ",3(A,X))') (string(xseed(j),'e',decimal=6),j=1,3)
       write (uout,'("  Seed up-limit (omega) : ",3(A,X))') (string(xup(j),'e',decimal=6),j=1,3)
       write (uout,'("  Seed dn-limit (alpha) : ",3(A,X))') (string(xdn(j),'e',decimal=6),j=1,3)
       write (uout,'("  GP tracing maximum num. of steps : ",A)') string(BS_mstep)
       write (uout,*)
       write (uout,'("  (",A5,"/",A5,") ",A12,1X,A12,2X,A12,1X,A8)') &
          "nray","mray","r_inner","r_ias","r_outer","nstep"
       write (uout,'(64("-"))') 
    end if

    rmin = VBIG
    rmax = 0d0
    nwarn = 0
    nwarn0 = 0
    !$omp parallel do private(unit,raprox,riaprox,ok,xtemp,nstep,ier,&
    !$omp  xin,xfin,xmed,nwarn) schedule(guided)
    do i = 1, srf%nv
       nwarn = 0
       ! skip surfed points
       if (srf%r(i) > 0d0) cycle

       ! unitary vector for the direction of the ray
       unit = (/ sin(srf%th(i)) * cos(srf%ph(i)),&
          sin(srf%th(i)) * sin(srf%ph(i)),&
          cos(srf%th(i)) /)

       raprox = 0.5d0 * maxval(cr%aa)
       riaprox = 0.5d0 * maxval(cr%aa)

       ! inner limit, reuse previous steps riaprox
       if (rmin /= VBIG) then
          riaprox = rmin
       end if
       ok = .false.
       do while (riaprox > 1d-5)
          xtemp = xseed + riaprox * unit
          call gradient (f(refden),xtemp,+1,nstep,BS_mstep,ier,0,up2beta=.true.)
          if (ier == 3)  then
             ok = .false.
          else
             if (ier > 0) nwarn = nwarn + 1
             xtemp = xtemp - xup
             ok = (dot_product(xtemp,xtemp) <= bsr2)
          end if
          if (ok) then
             ! omega-limit
             xtemp = xseed + riaprox * unit
             call gradient (f(refden),xtemp,-1,nstep,BS_mstep,ier,0,up2beta=.true.)
             if (ier == 3)  then
                ok = .false.
             else
                if (ier > 0) nwarn = nwarn + 1
                xtemp = xtemp - xdn
                ok = ok .and. (dot_product(xtemp,xtemp) <= bsr2)
             end if
          end if
          if (ok) then
             exit
          else
             raprox = riaprox
             riaprox = 0.5d0 * riaprox
          end if
       end do
       if (riaprox <= 1d-5) then
          call ferror ('bundle_msurface','Can not find inner bracket limit.',faterr)
       end if

       ! outer limit, reuse previous steps raprox
       if (rmax /= 0d0) raprox = rmax
       ok = .false.
       do while (raprox < 10d0 * maxval(cr%aa))
          xtemp = xseed + raprox * unit
          call gradient (f(refden),xtemp,+1,nstep,BS_mstep,ier,0,up2beta=.true.)
          if (ier == 3)  then
             ok = .false.
          else
             if (ier > 0) nwarn = nwarn + 1
             xtemp = xtemp - xup
             ok = (dot_product(xtemp,xtemp) > bsr2)
          endif
          if (.not.ok) then
             ! omega-limit
             xtemp = xseed + raprox * unit
             call gradient (f(refden),xtemp,-1,nstep,BS_mstep,ier,0,up2beta=.true.)
             if (ier == 3)  then
                ok = .false.
             else
                if (ier > 0) nwarn = nwarn + 1
                xtemp = xtemp - xdn
                ok = ok .or. (dot_product(xtemp,xtemp) > bsr2)
             end if
          end if
          if (ok) then
             exit
          else
             if (raprox > riaprox) riaprox = raprox
             raprox = 2d0 * raprox
          end if
       end do
       if (raprox > 10d0 * maxval(cr%aa)) then
          call ferror ('bundle_msurface','Can not find outer bracket limit.',faterr)
       end if

       xin = xseed + riaprox * unit
       xfin = xseed + raprox * unit

       call lim_bundle(xup,xdn,xin,xfin,prec,xmed,nstep,nwarn)

       xmed = xmed - xseed

       !$omp ATOMIC
       nwarn0 = nwarn0 + nwarn
       !$omp ATOMIC
       rmin = min(rmin,riaprox)
       !$omp ATOMIC
       rmax = max(rmax,raprox)
       !$omp critical (srfwrite)
       srf%r(i) = norm(xmed)
       !$omp end critical (srfwrite)
       if (verbose) then
          !$omp critical (IO)
          write (uout,'("  (",I5,"/",I5,") ",E14.6,1X,E14.6,2X,E14.6,1X,I8)') &
             i,srf%nv,riaprox,srf%r(i),raprox,nstep
          !$omp end critical (IO)
       end if
    enddo
    !$omp end parallel do

    if (nwarn0 > 0) then
       write (uout,'("* nwarns = ",A)') string(nwarn0)
       ! call ferror('bundle_msurface',"Some gradient paths were not terminated",warning)
    end if
    if (verbose) then
       write (uout,'(A/)') "+ End of bisection "
    end if

    ! Restore the original beta radius
    cp(1:ncp)%rbeta = oldrbeta

  end subroutine bundle_msurface

  !> Generalized plotting of atomic basins using the bisection
  !> algorithm. The method parameter indicates the initial
  !> distribution of rays: bcb (subdivision of a cube), btr
  !> (subdivision of an octahedron), bsp (uniform on a sphere).  level
  !> is the level of subdivision. ntheta and nphi apply to the bsp
  !> method, and indicate the number of rays in the azimuthal (phi) and
  !> polar (theta) angle. outputm, the output method: "off", geomview
  !> OFF file; "bas", basin file; "dbs", dbasin file. npts is the
  !> number of points along each ray in the dbasin output mode.
  !> cpid is the CP basin (equivalent CP list) to be represented. 
  subroutine basinplot(line)
    use integration
    use surface
    use graphics
    use fields
    use varbas
    use global
    use struct_basic
    use tools_io
    use types
    use param
    implicit none

    character*(*), intent(in) :: line

    integer :: lp, lp2
    character(len=:), allocatable :: word, expr
    character*3 :: method, outputm
    integer :: level, ntheta, nphi, npts, cpid, idum
    type(minisurf) :: srf
    integer :: i, linmin, linmax, iz
    character*(40) :: file
    integer :: cpn
    integer :: m, nf, j
    logical :: neqdone(ncp), ok, verbose
    real*8 :: xnuc(3), prec

    ! default values
    verbose = .false.
    cpid = 0
    outputm = 'obj'
    method = 'btr'
    level = 3
    ntheta = 5
    nphi = 5
    npts = 11
    prec = 1d-5
    expr = ""

    ! read input
    lp = 1
    do while(.true.)
       word = lgetword(line,lp)
       if (equal(word,'cube')) then
          method = 'bcb'
          lp2 = lp
          ok = eval_next (level,line,lp)
          if (.not.ok) then
             level = 3
             lp = lp2
          end if
       else if (equal(word,'triang')) then
          method = 'btr'
          lp2 = lp
          ok = eval_next (level,line,lp)
          if (.not.ok) then
             level = 3
             lp = lp2
          end if
       else if (equal(word,'sphere')) then
          method = 'bsp'
          lp2 = lp
          ok = eval_next (ntheta,line,lp)
          ok = ok .and. eval_next(nphi,line,lp)
          if (.not.ok) then
             ntheta = 5
             nphi = 5
             lp = lp2
          end if
       elseif (equal(word,'off')) then
          outputm = 'off'
       elseif (equal(word,'obj')) then
          outputm = 'obj'
       elseif (equal(word,'ply')) then
          outputm = 'ply'
       else if (equal(word,'basin')) then
          outputm = 'bas'
       else if (equal(word,'dbasin')) then
          outputm = 'dbs'
          lp2 = lp
          ok = eval_next(npts,line,lp)
          if (.not.ok) then
             npts = 11
             lp = lp2
          end if
       else if (equal(word,'cp')) then
          ok = eval_next(cpid,line,lp)
          if (.not.ok) then
             call ferror('basinplot','Unknown CP',faterr,line,syntax=.true.)
             return
          else
             if (cpcel(cpid)%typ /= f(refden)%typnuc) then
                call ferror('basinplot','cp: bad CP (bad syntax or type /= nuc.)',faterr,line,syntax=.true.)
                return
             end if
          end if
       else if (equal(word,'prec')) then
          ok = eval_next(prec,line,lp)
          if (.not.ok) then
             call ferror('basinplot','Unknown basinplot prec',faterr,line,syntax=.true.)
             return
          end if
       else if (equal(word,'verbose')) then
          verbose = .true.
       else if (equal(word,'map')) then
          lp2 = lp
          word = getword(line,lp)
          idum = fieldname_to_idx(word)
          if (idum < 0) then
             lp = lp2
             ok = isexpression_or_word(expr,line,lp)
             if (.not.ok) then
                call ferror('basinplot','Unknown baisnplot map',faterr,line,syntax=.true.)
                return
             end if
          else
             if (.not.goodfield(idum)) then
                call ferror('basinplot','field not allocated',faterr,line,syntax=.true.)
                return
             end if
             expr = "$" // string(idum)
          endif
       else if (len_trim(word) > 0) then
          call ferror('basinplot','Unknown extra keyword',faterr,line,syntax=.true.)
          return
       else
          exit
       end if
    end do

    if (cpid > 0) then
       if (cpcel(cpid)%typ /= f(refden)%typnuc) then
          call ferror('basinplot','selected CP does not have nuc. type',faterr,syntax=.true.)
          return
       end if
    end if

    ! print header to stdout
    write (uout,'("* Attraction basins plot (BASINPLOT)")')
    if (method == "bcb") then
       write (uout,'("  Starting polyhedron: cube ")') 
       write (uout,'("  Subdivision level: ",A)') string(level)
    else if (method == "btr") then
       write (uout,'("  Starting polyhedron: octahedron ")') 
       write (uout,'("  Subdivision level: ",A)') string(level)
    else
       write (uout,'("  Starting polyhedron: tesselated sphere ")') 
       write (uout,'("  n_theta: ",A)') string(ntheta)
       write (uout,'("  n_phi: ",A)') string(nphi)
    end if
    write (uout,'("  IAS precision: ",A)') string(prec,'e',decimal=6)
    if (outputm == "off") then
       write (uout,'("  Output file format: OFF")') 
    elseif (outputm == "obj") then
       write (uout,'("  Output file format: OBJ")') 
    elseif (outputm == "ply") then
       write (uout,'("  Output file format: PLY")') 
    else if (outputm == "bas") then
       write (uout,'("  Output file format: BASIN")') 
    else 
       write (uout,'("  Output file format: DBASIN with ",A," radial points")') string(npts)
    end if
    if (.not.cr%ismolecule) then
       write (uout,'("+ List of CP basins to be plotted (cryst. coord.): ")') 
    else
       write (uout,'("+ List of CP basins to be plotted (",A,"): ")') iunitname0(iunit)
    endif
    write (uout,'("#  ncp   cp       x             y             z")')
    if (cpid <= 0) then
       neqdone = .false.
       do i = 1, ncpcel
          if (cpid == 0 .and. ((cpcel(i)%typ /= f(refden)%typnuc .and. i>cr%nneq) .or.&
             neqdone(cpcel(i)%idx))) cycle
          neqdone(cpcel(i)%idx) = .true.
          if (.not.cr%ismolecule) then
             xnuc = cpcel(i)%x
          else
             xnuc = (cpcel(i)%r+cr%molx0)*dunit
          endif
          write (uout,'(99(A,2X))') string(cpcel(i)%idx,length=5,justify=ioj_right),&
             string(i,length=5,justify=ioj_right), &
             (string(xnuc(j),'e',length=12,decimal=6,justify=4),j=1,3)
       end do
    else
       if (.not.cr%ismolecule) then
          xnuc = cpcel(cpid)%x
       else
          xnuc = (cpcel(cpid)%r+cr%molx0)*dunit
       endif
       write (uout,'(99(A,2X))') string(cpcel(cpid)%idx,length=5,justify=ioj_right),&
          string(cpid,length=5,justify=ioj_right), &
          (string(xnuc(j),'e',length=12,decimal=6,justify=4),j=1,3)
    end if
    write (uout,*)

    ! initialize the surface
    if (method == 'bcb') then
       m = maxpointscb(level) + 1
       nf = maxfacescb(level) + 1
    else if (method == 'btr') then
       m = maxpointstr(level) + 1
       nf = maxfacestr(level) + 1
    else if (method == 'bsp') then
       m = 2*nphi*(2**ntheta-1)+2
       nf = 6*nphi*(2**(ntheta-1)-1)+nphi+nphi
    end if

    call minisurf_init(srf,m,nf)
    
    if (cpid <= 0) then
       linmin = 1
       linmax = ncpcel
    else
       linmin = cpid
       linmax = cpid
    end if
    neqdone = .false.
    
    ! run over selected non-eq. CPs, only the same type as nuclei
    do i = linmin, linmax
       cpn = cpcel(i)%idx
       if (cpid == 0 .and. ((cpcel(i)%typ /= f(refden)%typnuc .and. cpn>cr%nneq) .or.&
          neqdone(cpn))) cycle
       neqdone(cpn) = .true.

       write (uout,'("  Plotting CP number (cp/ncp): ",A,"/",A)') string(i), string(cpn)

       ! clean the surface 
       call minisurf_clean(srf)

       ! tesselate the unit sphere and set all the rays to unsurfed
       xnuc = cr%x2c(cp(cpn)%x)

       if (method == 'bcb') then
          call minisurf_spherecub(srf,xnuc,level)
       else if (method == 'btr') then
          call minisurf_spheretriang(srf,xnuc,level)
       else if (method == 'bsp') then
          call minisurf_spheresphere(srf,xnuc,nphi,ntheta)
       end if
       srf%n = xnuc
       srf%r = -1d0

       write (uout,'("  Number of vertices: ",A)') string(srf%nv)
       write (uout,'("  Number of faces: ",A)') string(srf%nf)

       ! bisect using the tesselated unit sphere
       call bisect_msurface(srf,cpn,prec,verbose)
       call minisurf_transform(srf,cpcel(i)%ir,cpcel(i)%lvec+cr%cen(:,cpcel(i)%ic))

       ! set the color
       if (cp(cpn)%isnuc .and. cpn > 0 .and. cpn <= cr%nneq) then
          iz = cr%at(cpn)%z
          if (iz > 0) then
             srf%rgb = jmlcol(:,iz)
          endif
       endif

       ! output surface
       file = trim(fileroot) // "-" // string(i)
       if (outputm == 'off' .or. outputm == 'ply' .or. outputm == 'obj') then
          file = trim(file) // '.' // trim(outputm)
          if (len_trim(expr) > 0) then
             call minisurf_write3dmodel(srf,outputm,file,expr)
          else
             call minisurf_write3dmodel(srf,outputm,file)
          end if
       else if (outputm == 'bas') then
          file = trim(file) //'.basin'
          call minisurf_writebasin(srf,file,.true.)
       else if (outputm == 'dbs') then
          file = trim(file) //'.dbasin'
          call minisurf_writedbasin(srf,npts,file)
       end if

       write (uout,'("  Written file: ",A/)') string(file)

    end do

    call minisurf_close(srf)

  end subroutine basinplot

  !> Plotting of primary bundles using the bisection algorithm. The
  !> seed of the primary bundle is x0 (cryst. coordinates). The method
  !> parameter indicates the initial distribution of rays: bcb
  !> (subdivision of a cube), btr (subdivision of an octahedron), bsp
  !> (uniform on a sphere).  level is the level of subdivision. ntheta
  !> and nphi apply to the bsp method, and indicate the number of rays
  !> in the azimuthal (phi) and polar (theta) angle. outputm, the
  !> output method: "off", geomview OFF file; "bas", basin file;
  !> "dbs", dbasin file. npts is the number of points along each ray
  !> in the dbasin output mode. rootfile is the root of the files written.
  subroutine bundleplot(line)
    use struct_basic
    use surface
    use fields
    use global
    use types
    use tools_io
    implicit none

    character*(*), intent(in) :: line

    character*3 :: method, outputm
    integer :: level, npts, ntheta, nphi
    real*8 :: x0(3)
    character(len=:), allocatable :: surfile, word, expr, file
    type(minisurf) :: srf
    integer :: m, nf, lp, lp2, idum, j
    real*8 :: xorig(3), prec
    logical :: ok, verbose

    ! default values
    verbose = .false.
    method = 'btr'
    level = 3
    ntheta = 5
    nphi = 5
    outputm = 'obj'
    npts = 11
    surfile = trim(fileroot) // '-bundle' 
    prec = 1d-5
    expr = ""

    ! read input
    lp = 1
    ok = eval_next (x0(1),line,lp)
    ok = ok .and. eval_next (x0(2),line,lp)
    ok = ok .and. eval_next (x0(3),line,lp)
    if (.not.ok) then
       call ferror ('bundleplot','bundleplot needs an initial point',faterr,syntax=.true.)
       return
    end if
    if (cr%ismolecule) &
       x0 = cr%c2x(x0 / dunit - cr%molx0)

    do while(.true.)
       word = lgetword(line,lp)
       if (equal(word,'cube')) then
          method = 'bcb'
          lp2 = lp
          ok = eval_next (level,line,lp)
          if (.not.ok) then
             level = 3
             lp = lp2
          end if
       else if (equal(word,'triang')) then
          method = 'btr'
          lp2 = lp
          ok = eval_next (level,line,lp)
          if (.not.ok) then
             level = 3
             lp = lp2
          end if
       else if (equal(word,'sphere')) then
          method = 'bsp'
          lp2 = lp
          ok = eval_next (ntheta,line,lp)
          ok = ok .and. eval_next(nphi,line,lp)
          if (.not.ok) then
             ntheta = 5
             nphi = 5
             lp = lp2
          end if
       elseif (equal(word,'off')) then
          outputm = 'off'
       elseif (equal(word,'obj')) then
          outputm = 'obj'
       elseif (equal(word,'ply')) then
          outputm = 'ply'
       else if (equal(word,'basin')) then
          outputm = 'bas'
       else if (equal(word,'dbasin')) then
          outputm = 'dbs'
          lp2 = lp
          ok = eval_next(npts,line,lp)
          if (.not.ok) then
             npts = 11
             lp = lp2
          end if
       else if (equal(word,'prec')) then
          ok = eval_next(prec,line,lp)
          if (.not.ok) then
             call ferror('bundleplot','bundleplot delta: bad syntax',faterr,line,syntax=.true.)
             return
          end if
          prec = prec / dunit
       else if (equal(word,'verbose')) then
          verbose = .true.
       else if (equal(word,'root')) then
          surfile = getword(line,lp)
       else if (equal(word,'map')) then
          lp2 = lp
          word = getword(line,lp)
          idum = fieldname_to_idx(word)
          if (idum < 0) then
             lp = lp2
             ok = isexpression_or_word(expr,line,lp)
             if (.not.ok) then
                call ferror('bundleplot','Unknown bundleplot map',faterr,line,syntax=.true.)
                return
             end if
          else
             if (.not.goodfield(idum)) then
                call ferror('bundleplot','field not allocated',faterr,line,syntax=.true.)
                return
             end if
             expr = "$" // string(idum)
          endif
       else if (len_trim(word) > 0) then
          call ferror('bundleplot','Unknown extra keyword',faterr,line,syntax=.true.)
          return
       else
          exit
       end if
    end do

    ! print header to stdout
    write (uout,'("* Primary bundle plot")') 
    if (method == "bcb") then
       write (uout,'("  Starting polyhedron: cube")') 
       write (uout,'("  Subdivision level: ",A)') string(level)
    else if (method == "btr") then
       write (uout,'("  Starting polyhedron: octahedron ")') 
       write (uout,'("  Subdivision level: ",A)') string(level)
    else
       write (uout,'("  Starting polyhedron: tesselated sphere ")') 
       write (uout,'("  n_theta: ",A)') string(ntheta)
       write (uout,'("  n_phi:   ",A)') string(nphi)
    end if
    write (uout,'("  IAS precision: ",A)') string(prec,'e',decimal=6)
    if (outputm == "off") then
       write (uout,'("  Output file format: OFF")') 
    elseif (outputm == "obj") then
       write (uout,'("  Output file format: OBJ")') 
    elseif (outputm == "ply") then
       write (uout,'("  Output file format: PLY")') 
    else if (outputm == "bas") then
       write (uout,'("  Output file format: BASIN")') 
    else 
       write (uout,'("  Output file format: DBASIN with ",A," radial points")') string(npts)
    end if
    write (uout,'("  Primary bundle seed: ",3(A,X))') (string(x0(j),'e',decimal=6),j=1,3)

    ! initialize the surface
    if (method == 'bcb') then
       m = maxpointscb(level) + 1
       nf = maxfacescb(level) + 1
    else if (method == 'btr') then
       m = maxpointstr(level) + 1
       nf = maxfacestr(level) + 1
    else if (method == 'bsp') then
       m = 2*nphi*(2**ntheta-1)+2
       nf = 6*nphi*(2**(ntheta-1)-1)+nphi+nphi
    end if

    call minisurf_init(srf,m,nf)

    ! clean the surface 
    call minisurf_clean(srf)

    ! tesselate the unit sphere and set all the rays to unsurfed
    xorig = cr%x2c(x0)

    if (method == 'bcb') then
       call minisurf_spherecub(srf,xorig,level)
    else if (method == 'btr') then
       call minisurf_spheretriang(srf,xorig,level)
    else if (method == 'bsp') then
       call minisurf_spheresphere(srf,xorig,nphi,ntheta)
    end if
    srf%n = xorig
    srf%r = -1d0

    write (uout,'("  Number of vertices: ",A)') string(srf%nv)
    write (uout,'("  Number of faces: ",A)') string(srf%nf)

    call bundle_msurface(srf,prec,verbose)

    ! output surface
    file = surfile
    if (outputm == 'off' .or. outputm == 'ply' .or. outputm == 'obj') then
       file = trim(file) // '.' // trim(outputm)
       if (len_trim(expr) > 0) then
          call minisurf_write3dmodel(srf,outputm,file,expr)
       else
          call minisurf_write3dmodel(srf,outputm,file)
       end if
    else if (outputm == 'bas') then
       file = trim(file) // '.basin'
       call minisurf_writebasin(srf,file,.true.)
    else if (outputm == 'dbs') then
       file = trim(file) // '.dbasin' 
       call minisurf_writedbasin(srf,npts,file)
    end if
    write (uout,'("+ Written file : ",A)') string(file)
    write (uout,*)

    call minisurf_close(srf)

  end subroutine bundleplot

  !> Find the integrated properties in a sphere cenetered at x0
  !> (cartesian coordinates) with radius rad using a Gauss-Legendre
  !> angular quadrature with ntheta * nphi nodes. The INT_radquad_*
  !> apply to the radial integration. The properties are written in
  !> the sprop array. abserr is integrated radial absoulte error.
  !> neval, number of evaluations; meaneval, mean number of
  !> evaluations per ray
  subroutine sphereintegrals_gauleg(x0,rad,ntheta,nphi,sprop,abserr,neval,meaneval)
    use integration
    use surface
    use fields
    use types
    implicit none
    
    real*8, intent(in) :: x0(3), rad
    integer, intent(in) :: ntheta, nphi
    real*8, intent(out) :: sprop(Nprops) 
    real*8, intent(out) :: abserr
    integer, intent(out) :: neval, meaneval

    type(minisurf) :: srf
    integer :: m
    real*8 :: iaserr(Nprops)

    m = 3 * ntheta * nphi + 1
    call minisurf_init(srf,m,0)
    call minisurf_clean(srf)
    call gauleg_msetnodes(srf,ntheta,nphi)

    srf%n = x0
    srf%r = rad
    call gauleg_mquad(srf,ntheta,nphi,0d0,sprop,abserr,neval,iaserr)
    meaneval = ceiling(real(neval,8) / srf%nv)

    call minisurf_close(srf)

  end subroutine sphereintegrals_gauleg

  !> Find the integrated properties in a sphere cenetered at x0
  !> (cartesian coordinates) with radius rad using a Lebedev angular
  !> quadrature with nleb nodes. The INT_radquad_* apply to the radial
  !> integration. The properties are written in the sprop
  !> array. abserr is the integrated radial absolute error.
  !> Neval, number of evaluations; meaneval, mean number of
  !> evaluations per ray
  subroutine sphereintegrals_lebedev(x0,rad,nleb,sprop,abserr,neval,meaneval)
    use integration
    use surface
    use fields
    use types
    implicit none
    
    real*8, intent(in) :: x0(3), rad
    integer, intent(in) :: nleb
    real*8, intent(out) :: sprop(Nprops) 
    real*8, intent(out) :: abserr
    integer, intent(out) :: neval, meaneval

    type(minisurf) :: srf
    real*8 :: iaserr(Nprops)

    call minisurf_init(srf,nleb,0)
    call minisurf_clean(srf)
    call lebedev_msetnodes(srf,nleb)

    srf%n = x0
    srf%r = rad
    call lebedev_mquad(srf,nleb,0d0,sprop,abserr,neval,iaserr)
    meaneval = ceiling(real(neval,8) / srf%nv)

    call minisurf_close(srf)

  end subroutine sphereintegrals_lebedev

  !> Spherical integration driver. meth is the angular quadrature
  !> method with number of nodes n1 and n2, cpid is the cp identifier
  !> (non-equivalent atom list, 0 = all). nr is the number of
  !> logarithmically spaced sphere radii. r0 and rend are the limits
  !> of the radial grid. This routine handles the
  !> output and calls the low-level sphereintegrals_*.
  subroutine sphereintegrals(line)
    use fields
    use varbas
    use global
    use struct_basic
    use tools_io
    use tools_math
    implicit none

    character*(*), intent(in) :: line

    character(len=:), allocatable :: word
    integer :: meth, nr, ntheta, nphi, np, cpid
    real*8 :: r0, rend
    integer :: linmin, linmax
    integer :: lp, i, j, n, nn, k
    real*8 :: sprop(Nprops)
    real*8 :: xnuc(3), h, r, abserr
    integer :: neval, meaneval
    logical :: ok
    character(10) :: pname

    ntheta = 20
    nphi = 20
    np = 770
    lp = 1
    word = lgetword(line,lp)
    meth = INT_gauleg
    if (equal(word,'gauleg')) then
       meth = INT_gauleg
       ok= eval_next(nn,line,lp)
       if (ok) ntheta = nn
       ok = eval_next(nn,line,lp)
       if (ok) nphi = nn
    elseif (equal(word,'lebedev')) then
       meth = INT_lebedev
       ok= eval_next(nn,line,lp)
       if (ok) np = nn
       call good_lebedev(np)
    else
       call ferror('sphereintegrals','sphereintegrals: bad method',faterr,line,syntax=.true.)
       return
    end if

    cpid = 0
    nr = 100
    r0 = 1d-3 / dunit
    rend = -1d0
    do while (.true.)
       word = lgetword(line,lp)
       if (equal(word,'nr')) then
          ok= eval_next (nr,line,lp)
          if (.not. ok) then
             call ferror('sphereintegrals','sphereintegrals: bad NR',faterr,line,syntax=.true.)
             return
          end if
       else if (equal(word,'r0')) then
          ok= eval_next (r0,line,lp)
          if (.not. ok) then
             call ferror('sphereintegrals','sphereintegrals: bad R0',faterr,line,syntax=.true.)
             return
          end if
          r0 = r0 / dunit
       else if (equal(word,'rend')) then
          ok= eval_next (rend,line,lp)
          if (.not. ok) then
             call ferror('sphereintegrals','sphereintegrals: bad REND',faterr,line,syntax=.true.)
             return
          end if
          rend = rend / dunit
       else if (equal(word,'cp')) then
          ok= eval_next (cpid,line,lp)
          if (.not. ok) then
             call ferror('sphereintegrals','sphereintegrals: bad CP',faterr,line,syntax=.true.)
             return
          end if
       else if (len_trim(word) > 0) then
          call ferror('sphereintegrals','Unknown extra keyword',faterr,line,syntax=.true.)
          return
       else
          exit
       end if
    end do

    if (INT_radquad_errprop > 0 .and. INT_radquad_errprop <= Nprops) then
       pname = integ_prop(INT_radquad_errprop)%prop_name
    else
       pname = "max       "
    end if

    write (uout,'("* Integration of spheres")')
    write (uout,'("  Attractor signature: ",A)') string(f(refden)%typnuc)
    !
    write (uout,'("+ ANGULAR integration")')
    if (meth == INT_gauleg) then
       write (uout,'("  Method : Gauss-Legendre, non-adaptive quadrature ")')       
       write (uout,'("  Polar angle (theta) num. of nodes: ",A)') string(ntheta)
       write (uout,'("  Azimuthal angle (phi) num. of nodes: ",A)') string(nphi)
    else if (meth == INT_lebedev) then
       write (uout,'("  Method : Lebedev, non-adaptive quadrature ")')
       write (uout,'("  Number of nodes: ",A)') string(np)
    end if
    write (uout,'("  Target attractors (0 = all): ",A)') string(cpid)
    !
    write (uout,'("+ RADIAL integration")')       
    if (INT_radquad_type == INT_gauleg) then
       write (uout,'("  Method : Gauss-Legendre, non-adaptive quadrature ")')       
       write (uout,'("  Number of radial nodes: ",A)') string(INT_radquad_nr)
    else if (INT_radquad_type == INT_qags) then
       write (uout,'("  Method : quadpack QAGS ")')       
       write (uout,'("  Required absolute error: ",A)') string(INT_radquad_abserr,'e',decimal=4)
       write (uout,'("  Required relative error: ",A)') string(INT_radquad_relerr,'e',decimal=4)
    else if (INT_radquad_type == INT_qng) then
       write (uout,'("  Method : quadpack QNG ")')       
       write (uout,'("  Required absolute error: ",A)') string(INT_radquad_abserr,'e',decimal=4)
       write (uout,'("  Required relative error: ",A)') string(INT_radquad_relerr,'e',decimal=4)
    else if (INT_radquad_type == INT_qag) then
       write (uout,'("  Method : quadpack QAG ")')       
       write (uout,'("  Number of radial nodes: ",A)') string(INT_radquad_nr)
       write (uout,'("  Required absolute error: ",A)') string(INT_radquad_abserr,'e',decimal=4)
       write (uout,'("  Required relative error: ",A)') string(INT_radquad_relerr,'e',decimal=4)
    end if
    write (uout,'("  Error applies to ppty: ",a)') trim(pname)
    write (uout,*)
    !
    if (INT_radquad_type == INT_qags .or. &
       INT_radquad_type == INT_qags .or. &
       INT_radquad_type == INT_qags) then
       write (uout,'("+ Using the QUADPACK library ")') 
       write (uout,'("  R. Piessens, E. deDoncker-Kapenga, C. Uberhuber and D. Kahaner,")')
       write (uout,'("  Quadpack: a subroutine package for automatic integration, Springer-Verlag 1983.")')
    end if
    if (ncp > 0) then
       if (cpid <= 0) then
          linmin = 1
          linmax = ncp
       else
          linmin = cpid
          linmax = cpid
       end if
    else
       call ferror('sphereintegrals','calling sphereintegrals without the CP list',warning)
       write (uout,*)
       if (cpid <= 0) then
          linmin = 1
          linmax = cr%nneq
       else
          linmin = cpid
          linmax = cpid
       end if
    end if

    do i = linmin, linmax
       if ((cp(i)%typ /= f(refden)%typnuc .and. i>cr%nneq)) cycle

       if (nr > 1) then
          if (rend < 0d0) then
             h = log(cr%at(i)%rnn2 * abs(rend) / r0) / (nr - 1)
          else
             h = log(rend / r0) / (nr - 1)
          end if
       else
          h = 0d0
       end if
       xnuc = cr%x2c(cp(i)%x)

       write (uout,'("+ Non-equivalent CP : ",A)') string(i)
       write (uout,'("  CP at: ",3(A,X))') (string(cp(i)%x(j),'e',decimal=4),j=1,3)
       write (uout,'("  Initial radius (r0,",A,"): ",A)') iunitname0(iunit), &
          string(r0,'e',decimal=6)
       if (rend < 0d0) then
          write (uout,'("  Final radius (rend,",A,"): ",A)') iunitname0(iunit), &
             string(cr%at(i)%rnn2 * abs(rend),'e',decimal=6)
       else
          write (uout,'("  Final radius (rend,",A,"): ",A)') iunitname0(iunit), string(rend,'e',decimal=6)
       end if
       write (uout,'("  Logarithmic step h ( r = r0*exp(h*(n-1)) ): ",A)') string(h,'e',decimal=6)
       write (uout,'("  Radial points: ",A)') string(nr)


       write (uout,'("#  r (",A,")   Eval/ray   Int. r_err       Volume          Charge          Lap        ")') &
          iunitname0(iunit)
       do n = 1, nr
          if (nr == 1) then
             if (rend < 0d0) then
                r = cr%at(i)%rnn2 * abs(rend)
             else
                r = r0
             end if
          else
             r = r0 * exp((n-1)*h)
          end if
          if (meth == INT_gauleg) then
             call sphereintegrals_gauleg(xnuc,r,ntheta,nphi,sprop,abserr,neval,meaneval)
          else if (meth == INT_lebedev) then
             call sphereintegrals_lebedev(xnuc,r,np,sprop,abserr,neval,meaneval)
          else
             call ferror('sphereintegrals','unknown method',faterr)
          end if

          r = r * dunit
          write (uout,'(2X,99(A,2X))') &
             string(r,'e',decimal=6,length=12,justify=4),&
             string(meaneval,length=6,justify=ioj_right),&
             string(abserr,'e',decimal=6,length=12,justify=4),&
             (string(sprop(k),'e',decimal=8,length=14,justify=4),k=1,Nprops)
       end do
       write (uout,*)
    end do

  end subroutine sphereintegrals

  !> Integrate the atomic basin of the non-equivalent CP cpid 
  !> using a fixed 2d Gauss-Legendre quadrature with n1 = ntheta
  !> and n2 = nphi. If usefiles, read and/or write the .int files
  !> containing the ZFS description for each atom. 
  subroutine integrals_gauleg(atprop,n1,n2,cpid,usefiles,verbose)
    use integration
    use surface
    use varbas
    use global
    use fields
    use struct_basic
    use tools_io
    use types
    implicit none

    real*8, intent(out) :: atprop(Nprops)
    integer, intent(in) :: n1, n2, cpid
    logical, intent(in) :: usefiles
    logical, intent(in) :: verbose

    type(minisurf) :: srf

    real*8 :: xnuc(3)
    integer :: ierr
    integer :: ntheta, nphi, m
    integer :: j
    logical :: existfile
    real*8 :: sprop(Nprops)
    real*8 :: r_betaint, abserr, iaserr(Nprops)
    integer :: neval, meaneval
    integer :: smin, smax

    smin = 1
    smax = cr%nneq

    ntheta = n1
    nphi = n2
    m = 3 * ntheta * nphi + 1
    call minisurf_init(srf,m,0)
    call minisurf_clean(srf)
    call gauleg_msetnodes(srf,ntheta,nphi)

    atprop = 0d0

    ! initialize the surface for this atom
    xnuc = cr%x2c(cp(cpid)%x)
    srf%n = xnuc
    srf%r = -1d0

    ! Read the input file
    if (usefiles .and. allocated(intfile)) then
       inquire(file=intfile(cpid),exist=existfile)
       if (existfile) then
          call minisurf_readint(srf,ntheta,nphi,INT_gauleg,intfile(cpid),ierr)
          ! The reading was not successful -> bisect
          if (ierr > 0) then
             existfile = .false.
             srf%r = -1d0
          end if
       end if
    end if
       
    ! bisect the surface 
    if (.not.(usefiles .and. existfile)) then
       ! bisect the surface
       call bisect_msurface(srf,cpid,INT_iasprec,verbose)
    end if
       
    ! beta-sphere... skip:
    ! 1. by user's request
    ! 2. the scalar field has shells and this is an effective nucleus
    r_betaint = 0.95d0 * minval(srf%r(1:srf%nv)) 

    if (verbose) then
       write (uout,'(a)') " Integrating the sphere..."
    end if
    ! integrate the sphere
    if (bs_spherequad_type == INT_gauleg) then
       call sphereintegrals_gauleg(xnuc,r_betaint,bs_spherequad_ntheta,bs_spherequad_nphi,sprop,&
          abserr,neval,meaneval)
    else
       call sphereintegrals_lebedev(xnuc,r_betaint,bs_spherequad_nleb,sprop,abserr,neval,meaneval)
    end if
    if (verbose) then
       write (uout,'(a,i10)') " Number of evaluations : ", neval
       write (uout,'(a,i10)') " Avg. evaluations per ray : ", meaneval

       write (uout,'(a,1p,E12.4)') " Beta-sphere radius : ",r_betaint
       write (uout,'(2x,a2,x,a10,x,a12,x,a17)') "id","property",&
          "IAS error","Integral (sph.)"
       write (uout,'(2x,42("-"))')
       do j = 1, Nprops
          write (uout,'(2x,i2,x,a10,x,1p,e14.6,x,e17.9)') j,integ_prop(j)%prop_name,0d0,sprop(j)
       end do
       write (uout,*)
    end if

    ! calculate properties
    if (verbose) then
       write (uout,'(a)') " Summing the quadrature formula..."
    end if
    call gauleg_mquad(srf,ntheta,nphi,r_betaint,atprop,abserr,neval,iaserr)
    if (verbose) then
       write (uout,'(a,i10)') " Number of evaluations : ", neval
       write (uout,'(a,i10)') " Avg. evaluations per ray : ", ceiling(real(neval,8) / srf%nv)
       write (uout,'(2xa2,x,a10,x,a12,x,a17)') "id","property",&
          "IAS error","Integral"
       write (uout,'(2x,42("-"))')
       do j = 1, Nprops
          write (uout,'(2x,i2,x,a10,x,1p,e14.6,x,e17.9)') j,integ_prop(j)%prop_name,iaserr(j),atprop(j)
       end do
       write (uout,*)
    end if

    ! sum 
    atprop = atprop + sprop

    if (usefiles) then
       ! write the surface
       write (uout,'(" Writing basin in file : ",A)') trim(intfile(cpid))
       write (uout,*)
       call minisurf_writeint(srf,ntheta,nphi,INT_gauleg,intfile(cpid))
    end if

    call minisurf_close(srf)

  end subroutine integrals_gauleg

  !> Integrate the atomic basin of the non-equivalent CP cpid (0 for
  !> all) using a fixed Lebedev quadrature with nleb points If
  !> usefiles, read and/or write the .int files containing the ZFS
  !> description for each atom.
  subroutine integrals_lebedev(atprop,nleb,cpid,usefiles,verbose)
    use integration
    use surface
    use varbas
    use fields
    use global
    use struct_basic
    use tools_io
    use types
    implicit none

    real*8, intent(out) :: atprop(Nprops)
    integer, intent(in) :: nleb, cpid
    logical, intent(in) :: usefiles
    logical, intent(in) :: verbose

    type(minisurf) :: srf

    real*8 :: xnuc(3)
    integer :: ierr
    integer :: j
    logical :: existfile
    real*8 :: sprop(Nprops)
    real*8 :: r_betaint, abserr, iaserr(Nprops)
    integer :: neval, meaneval
    integer :: smin, smax

    smin = 1
    smax = cr%nneq

    call minisurf_init(srf,nleb,0)
    call minisurf_clean(srf)
    call lebedev_msetnodes(srf,nleb)

    atprop = 0d0

    ! initialize the surface for this atom
    xnuc = cr%x2c(cp(cpid)%x)
    srf%n = xnuc
    srf%r = -1d0
       
    ! Read the input file
    if (usefiles .and. allocated(intfile)) then
       ! Name of the input / output file
       inquire(file=intfile(cpid),exist=existfile)
       if (existfile) then
          call minisurf_readint(srf,nleb,0,INT_lebedev,intfile(cpid),ierr)
          ! The reading was not successful -> bisect
          if (ierr > 0) then
             existfile = .false.
             srf%r = -1d0
          end if
       end if
    end if

    ! bisect the surface 
    ! 1. It is not loaded from an int file
    ! 2. This is not a 'spheres-only' block run
    if (.not.(usefiles .and. existfile)) then
       ! bisect the surface
       call bisect_msurface(srf,cpid,INT_iasprec,verbose)
    end if
    
    ! beta-sphere integration
    r_betaint = 0.95d0 * minval(srf%r(1:srf%nv)) 
    if (verbose) then
       write (uout,'(a)') " Integrating the sphere..."
    end if
    ! integrate the sphere
    if (bs_spherequad_type == INT_gauleg) then
       call sphereintegrals_gauleg(xnuc,r_betaint, &
          bs_spherequad_ntheta,bs_spherequad_nphi,sprop,&
          abserr,neval,meaneval)
    else
       call sphereintegrals_lebedev(xnuc,r_betaint, &
          bs_spherequad_nleb,sprop,abserr,neval,meaneval)
    end if

    if (verbose) then
       write (uout,'(a,1p,E12.4)') " Beta-sphere radius : ",r_betaint
       write (uout,'(a,i10)') " Number of evaluations : ", neval
       write (uout,'(a,i10)') " Avg. evaluations per ray : ", meaneval
       write (uout,'(2x,a2,x,a10,x,a12,x,a17)') "id","property",&
          "IAS error","Integral (sph.)"
       write (uout,'(2x,42("-"))')
       do j = 1, Nprops
          write (uout,'(2x,i2,x,a10,x,1p,e14.6,x,e17.9)') j,integ_prop(j)%prop_name,0d0,sprop(j)
       end do
       write (uout,*)
    end if

    ! calculate properties
    if (verbose) then
       write (uout,'(a)') " Summing the quadrature formula..."
    end if
    call lebedev_mquad(srf,nleb,r_betaint,atprop,abserr,neval,iaserr)
    if (verbose) then
       write (uout,'(a,i10)') " Number of evaluations : ", neval
       write (uout,'(a,i10)') " Avg. evaluations per ray : ", ceiling(real(neval,8) / srf%nv)
       write (uout,'(2x,a2,x,a10,x,a12,x,a17)') "id","property",&
          "IAS error","Integral (neg.)"
       write (uout,'(2x,42("-"))')
       do j = 1, Nprops
          write (uout,'(2x,i2,x,a10,x,1p,e14.6,x,e17.9)') j,integ_prop(j)%prop_name,iaserr(j),atprop(j)
       end do
       write (uout,*)
    end if
       
    ! sum 
    atprop = atprop + sprop

    if (usefiles) then
       ! write the surface
       write (uout,'(" Writing basin in file : ",A)') trim(intfile(cpid))
       write (uout,*)
       call minisurf_writeint(srf,nleb,0,INT_lebedev,intfile(cpid))
    end if

    call minisurf_close(srf)

  end subroutine integrals_lebedev

  !> Atomic basin integration driver. meth is the angular quadrature
  !> method with number of nodes n1 and n2, cpid is the cp identifier
  !> (non-equivalent atom list, 0 = all) and if usefiles is true then
  !> read and/or write the int files containing the IAS description
  !> for this method. This routine handles the output and calls the
  !> low-level integrals_*.
  subroutine integrals(line)
    use integration
    use varbas
    use fields
    use global
    use struct_basic
    use tools_math
    use tools_io
    implicit none

    character*(*), intent(in) :: line

    integer :: meth, cpid, ntheta, nphi, np
    logical :: usefiles, verbose
    integer :: lp
    integer :: linmin, linmax
    integer :: i, j, n
    real*8, allocatable :: atprop(:,:)
    logical :: maskprop(nprops), ok
    character(len=:), allocatable :: aux, word
    character*(10) :: pname
    character*(30) :: reason(nprops)
    integer, allocatable :: icp(:)
    real*8, allocatable :: xattr(:,:)

    ntheta = 0
    nphi = 0
    np = 0
    lp = 1
    word = lgetword(line,lp)
    if (equal(word,'gauleg')) then
       meth = INT_gauleg
       ok= eval_next(ntheta,line,lp)
       ok = ok .and. eval_next(nphi,line,lp)
    elseif (equal(word,'lebedev')) then
       meth = INT_lebedev
       ok= eval_next(np,line,lp)
       call good_lebedev(np)
    else
       call ferror('integrals','Unknown method in INTEGRALS', faterr,line,syntax=.true.)
       return
    end if
    if (.not.ok) then
       call ferror('integrals','integrals: bad method', faterr,line,syntax=.true.)
       return
    end if

    cpid = 0
    usefiles = .false.
    verbose = .false.
    do while (.true.)
       word = lgetword(line,lp)
       if (equal(word,'cp')) then
          ok= eval_next (cpid,line,lp)
          if (.not. ok) then
             call ferror('integrals','integrals: bad CP',faterr,line,syntax=.true.)
             return
          end if
       else if (equal(word,'rwint')) then
          usefiles = .true.
       else if (equal(word,'verbose')) then
          verbose = .true.
       else if (len_trim(word) > 0) then
          call ferror('integrals','Unknown extra keyword',faterr,line,syntax=.true.)
          return
       else
          exit
       end if
    end do

    if (.not.quiet) call tictac("Start INTEGRALS")
    maskprop = .true.
    do i = 1, nprops
       reason(i) = ""
    end do

    if (INT_radquad_errprop > 0 .and. INT_radquad_errprop <= Nprops) then
       pname = integ_prop(INT_radquad_errprop)%prop_name
    else
       pname = "max       "
    end if

    if (ncp > 0) then
       if (cpid <= 0) then
          linmin = 1
          linmax = ncp
       else
          linmin = cpid
          linmax = cpid
       end if
    else
       if (cpid <= 0) then
          linmin = 1
          linmax = cr%nneq
       else
          linmin = cpid
          linmax = cpid
       end if
    end if

    ! allocate space for results
    n = linmax - linmin + 1
    allocate(icp(n),xattr(3,n))
    allocate(atprop(nprops,n))

    ! define the int files
    if (usefiles) then
       if (.not.allocated(intfile)) allocate(intfile(linmin:linmax))
       do i = linmin, linmax
          aux = string(i)
          write (intfile(i),'(A,"-",A,".int")') trim(fileroot), string(aux)
       end do
    end if

    call integrals_header(meth,ntheta,nphi,np,cpid,usefiles,pname)

    n = 0
    do i = linmin, linmax
       if ((cp(i)%typ /= f(refden)%typnuc .and. i>cr%nneq)) cycle
       n = n + 1
       write (uout,'("+ Integrating CP: ",A)') string(i)
       if (meth == INT_gauleg) then
          call integrals_gauleg(atprop(:,n),ntheta,nphi,i,usefiles,verbose)
       else if (meth == INT_lebedev) then
          call integrals_lebedev(atprop(:,n),np,i,usefiles,verbose)
       else
          call ferror('integrals','unknown method',faterr)
       end if

       ! arrange results for int_output
       do j = 1, ncpcel
          if (cpcel(j)%idx == i) then
             icp(n) = j
             xattr(:,n) = cpcel(j)%x
             exit
          end if
       end do
    end do
    write (uout,*)

    call int_output(maskprop,reason,n,icp(1:n),xattr(:,1:n),atprop(:,1:n),.true.)

    ! Cleanup files
    if (allocated(intfile)) deallocate(intfile)
    if (allocated(icp)) deallocate(icp)
    if (allocated(xattr)) deallocate(xattr)
    if (allocated(atprop)) deallocate(atprop)

    if (.not.quiet) call tictac("End INTEGRALS")

  end subroutine integrals

  !> Header output for the integrals subroutine.
  subroutine integrals_header(meth,ntheta,nphi,np,cpid,usefiles,pname)
    use fields
    use varbas
    use global
    use struct_basic
    use tools_io
    implicit none

    integer, intent(in) :: meth, ntheta, nphi, np, cpid
    logical, intent(in) :: usefiles
    character(10), intent(in) :: pname

    logical :: existfile
    integer :: i, linmin, linmax

    write (uout,'("* Integration of basin properties by bisection")')       
    write (uout,'("  Basins of the scalar field: ",A)') string(refden)
    write (uout,'("  Attractor signature: ",A)') string(f(refden)%typnuc)
    !
    write (uout,'("+ ANGULAR integration")')       
    if (meth == INT_gauleg) then
       write (uout,'("  Method: Gauss-Legendre, non-adaptive quadrature ")')       
       write (uout,'("  Polar angle (theta) num. of nodes: ",A)') string(ntheta)
       write (uout,'("  Azimuthal angle (phi) num. of nodes: ",A)') string(nphi)
    else if (meth == INT_lebedev) then
       write (uout,'("  Method: Lebedev, non-adaptive quadrature ")')       
       write (uout,'("  Number of nodes: ",A)') string(np)
    end if
    write (uout,'("  Target attractors (0 = all): ",A)') string(cpid)
    !
    write (uout,'("+ RADIAL integration")')       
    if (INT_radquad_type == INT_gauleg) then
       write (uout,'("  Method: Gauss-Legendre, non-adaptive quadrature ")')       
       write (uout,'("  Number of radial nodes: ",A)') string(INT_radquad_nr)
    else if (INT_radquad_type == INT_qags) then
       write (uout,'("  Method: quadpack QAGS ")')       
       write (uout,'("  Required absolute error: ",A)') string(INT_radquad_abserr,'e',decimal=4)
       write (uout,'("  Required relative error: ",A)') string(INT_radquad_relerr,'e',decimal=4)
    else if (INT_radquad_type == INT_qng) then
       write (uout,'("  Method: quadpack QNG ")')       
       write (uout,'("  Required absolute error: ",A)') string(INT_radquad_abserr,'e',decimal=4)
       write (uout,'("  Required relative error: ",A)') string(INT_radquad_relerr,'e',decimal=4)
    else if (INT_radquad_type == INT_qag) then
       write (uout,'("  Method: quadpack QAG ")')       
       write (uout,'("  Number of radial nodes: ",A)') string(INT_radquad_nr)
       write (uout,'("  Required absolute error: ",A)') string(INT_radquad_abserr,'e',decimal=4)
       write (uout,'("  Required relative error: ",A)') string(INT_radquad_relerr,'e',decimal=4)
    end if
    write (uout,'("  Error applies to ppty: ",A)') string(pname)
    if (INT_radquad_type == INT_qags .or. &
       INT_radquad_type == INT_qags .or. &
       INT_radquad_type == INT_qags) then
       write (uout,'("+ Using the QUADPACK library ")') 
       write (uout,'("  R. Piessens, E. deDoncker-Kapenga, C. Uberhuber and D. Kahaner,")')
       write (uout,'("  Quadpack: a subroutine package for automatic integration, Springer-Verlag 1983.")')
    end if

    write (uout,'("+ IAS determination")')          
    write (uout,'("  Bisection precision: ",A)') string(INT_iasprec,'e',decimal=4)
    write (uout,'("  Use of precomputed files: ",L)') usefiles

    write (uout,'("+ BETA sphere integration details")')          
    if (bs_spherequad_type == INT_gauleg) then
       write (uout,'("  Method: Gauss-Legendre, non-adaptive quadrature ")')       
       write (uout,'("  Polar angle (theta) num. of nodes: ",A)') string(bs_spherequad_ntheta)
       write (uout,'("  Azimuthal angle (phi) num. of nodes: ",A)') string(bs_spherequad_nphi)
    else if (bs_spherequad_type == INT_lebedev) then
       write (uout,'("  Method: Lebedev, non-adaptive quadrature ")')
       write (uout,'("  Number of nodes: ",A)') string(bs_spherequad_nleb)
    end if

    if (usefiles .and. allocated(intfile)) then
       write (uout,'("+ FILES connected for integration")') 
       write (uout,'(A3,A25)') "CP", "       INT file (exists?) "
       if (cpid /= 0) then
          inquire(file=intfile(cpid),exist=existfile)
          write (uout,'(A,A20," (",L1,")")') string(cpid,length=3,justify=ioj_left), trim(intfile(cpid)), existfile
       else
          if (ncp > 0) then
             linmin = 1
             linmax = ncp
          else
             linmin = 1
             linmax = cr%nneq
          end if
          do i = linmin, linmax
             if ((cp(i)%typ /= f(refden)%typnuc .and. i>cr%nneq)) cycle
             inquire(file=intfile(i),exist=existfile)
             write (uout,'(A,A20," (",L1,")")') string(i,length=3,justify=ioj_left), trim(intfile(i)), existfile
          end do
       end if
    end if
    write (uout,*)

  end subroutine integrals_header

end module bisect

