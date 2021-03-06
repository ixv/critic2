# Critic2
## Overview

Critic2 is a program for the topological anaylisis of real-space
scalar fields in periodic systems. The functionality includes Bader's
atoms in molecules theory (critical point search, basin integration
via different methods, basin plotting,...), analysis of other
chemically-interesting fields (e.g. elf, laplacian of the
density,...), non-covalent interaction plots (NCIplots), and much
more.

Critic2 is designed to provide an abstraction layer on top of the
underlying electronic structure calculation. Different methods
(FPLAPW, pseudopotentials, local orbitals,...) represent the electron
density and other fields in diverse ways. Critic2 interfaces to many
of these and applies common techinques and algorithms to them. At the
moment of writing this, critic2 can interface to WIEN2k, elk, PI,
Quantum ESPRESSO, abinit, VASP, and any program capable of writing the
scalar field of interest to a grid.

The electron density is the usual field critic2 works with, but any
other (ELF, molecular electrostatic potential,...) can be analysed
using the same techniques. Hence, it is possible to compute, for
instance, the charges inside the basins of ELF, or the gradient paths
of the molecular electrostatic potential. New scalar fields can be
computed using critic2's powerful arithmetic expressions.

## Files

* README: this file.
* AUTHORS: the authors of the package.
* LICENSE: a copy of the licence. Critic2 is distributed under the
  GNU/GPL license v3.  
* NEWS: a summary of changes from the last stable version.
* INSTALL: installation instructions.
* THANKS: acknowledgements. Please read this for details on the
  license of code that critic2 uses.
* src/: source code.
* doc/: documentation (user's guide) and syntax reference
        (syntax.txt). 
* tools/: some tools to work with the files produced by critic2.
* dat/: atomic density and cif database data.

## Compilation and installation

If you got the code from the git repository and not from a package,
you will need to run:

    autoreconf -i

Prepare for compilation doing:

    ./configure

Use <code>configure --help</code> for information about the
compilation options. The --prefix option sets the installation
path. Once critic2 is configured, compile using:

    make

This should create the critic2 executable inside the src/
subdirectory. The binary can be used directly or the entire critic2
distribution can be installed to the 'prefix' path by doing:

    make install

Critic2 is parallelized for shared-memory architectures (unless
compiled with --disable-openmp). You modify the number of parallel
threads by setting the OMP_NUM_THREADS environment variable. The
following are parallelized in critic2:

* CP search (over starting seeds)
* Bisection (over integration rays)
* Generation of 3D grids in CUBE, WRITE,... (over planes)
* Qtree (over tetrahedra)

Note that the compilation flags for compilers different from ifort and
gfortran regarding parallelization may not be correct.

The environment variable CRITIC_HOME is necessary if critic2 was not
installed with 'make install'. It must point to the root directory of
the distribution:

    export CRITIC_HOME=/home/alberto/programs/critic2dir

This variable is necessary for critic2 to find the atomic densities,
the cif dictionary and the library data. These should be located in
${CRITIC_HOME}/dat/.

## Compiling and using libxc

Critic2 can be compiled with libxc support. Libxc is used in critic2
to calculate exchange and correlation energy densities via the xc()
function in arithmetic expressions. To do this, the --with-libxc
options must be passed to configure:

    ./configure --with-libxc-prefix=/opt/libxc --with-libxc-include=/opt/libxc/include

Here the /opt/libxc directory is the target for the libxc installation
(use --prefix=/opt/libxc when you configure libxc). Make sure that you
use the same compiler for libxc and for critic2; otherwise the library
will not be linked. You can choose the compiler by changing the FC and
F77 flags before configure:

    FC=gfortran F77=gfortran ./configure ...

See 'Use of LIBXC in arithmetic expressions' in the user's guide for
instructions on how to use libxc in critic2.

Some notes: 

* Older versions of the intel fortran compiler have a bug in how
openmp deals with allocatable arrays which affects the qtree
integrator and maybe other parts of the code. These problems have been
solved in version 13.1.

* critic2 as it is distributed can be compiled only with the more
recent versions of gfortran (somewhere along 4.8.x, and all versions
starting at 4.9). If a recent compiler is not available, a possibility
is to compile the program elsewhere with the static linking option:

      LDFLAGS=-static ./configure ...

## Use (documentation)

The user's guide is in the doc/ directory in plain text
(user-guide.txt) and PDF formats (user-guide.pdf). A concise summary
of the syntax can be found in the syntax.txt file.  Input examples can
be found in the examples/ subdirectory. 

Critic2 reads a single input file (the cri file). A simple input is:

    crytal cubicBN.cube
    load cubicBN.cube
    zpsp B 3 N 5
    yt

which reads the crystal structure from a cube file, then the electron
density from the same cube file, and then calculates the atomic
charges and volumes. Run critic2 as:

    critic2 cubicBN.cri cubicBN.cro

A detailed description of the keywords accepted by critic2 is given in
the user's guide and a short reference in the syntax.txt file. 

## References and citation

The basic references for critic2 are:

* A. Otero-de-la-Roza, E. R. Johnson and V. Luaña, 
  Comput. Phys. Commun. **185**, 1007-1018 (2014)
  (http://dx.doi.org/10.1016/j.cpc.2013.10.026) 
* A. Otero-de-la-Roza, M. A. Blanco, A. Martín Pendás and V. Luaña, 
  Comput. Phys. Commun. **180**, 157–166 (2009)
  (http://dx.doi.org/10.1016/j.cpc.2008.07.018) 

See the outputs and the manual for references pertaining particular keywords. 

## Copyright notice

Copyright (c) 2013-2015 Alberto Otero de la Roza, Ángel Martín Pendás and
Víctor Luaña.

critic2 is free software: you can redistribute it and/or modify
it under the terms of the GNU General Public License as published by
the Free Software Foundation, either version 3 of the License, or (at
your option) any later version.

critic2 is distributed in the hope that it will be useful,
but WITHOUT ANY WARRANTY; without even the implied warranty of
MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
GNU General Public License for more details.

You should have received a copy of the GNU General Public License
along with this program.  If not, see <http://www.gnu.org/licenses/>.
