Quick Start
===========

Requirements
------------

- `Nim <https://nim-lang.org/>`_ >= 2.0.0

Installation
------------

Add NimPulseq to your ``.nimble`` project:

.. code-block:: nim

   requires "nimpulseq"

Or clone and use directly:

.. code-block:: bash

   git clone https://github.com/your-org/nimpulseq
   nim c -r examples/write_gre.nim

Minimal Example
---------------

.. code-block:: nim

   import std/math
   import nimpulseq

   let system = newOpts(
     maxGrad = 28, gradUnit = "mT/m",
     maxSlew = 150, slewUnit = "T/m/s",
     rfRingdownTime = 20e-6,
     rfDeadTime = 100e-6,
     adcDeadTime = 10e-6,
   )
   var seqObj = newSequence(system)

   # Create a sinc RF pulse with slice-select gradient
   var (rf, gz, _) = makeSincPulse(
     flipAngle = PI / 2.0,
     duration = 3e-3,
     sliceThickness = 3e-3,
     apodization = 0.5,
     timeBwProduct = 4.0,
     system = system,
     returnGz = true,
     use = "excitation",
   )

   # Create readout gradient and ADC
   let gx = makeTrapezoid(
     channel = "x",
     flatArea = 16384.0,
     flatTime = 3.2e-3,
     system = system,
   )
   let adc = makeAdc(
     numSamples = 64,
     duration = gx.trapFlatTime,
     delay = gx.trapRiseTime,
     system = system,
   )

   # Assemble blocks
   seqObj.addBlock(rf, gz)
   seqObj.addBlock(gx, adc)

   # Validate and write
   let (ok, _) = seqObj.checkTiming()
   assert ok
   seqObj.writeSeq("my_sequence.seq", createSignature = true)

Design Pattern
--------------

NimPulseq follows the same pipeline as PyPulseq:

.. code-block:: text

   Opts → make_*(...) → Event objects → addBlock(*events) → writeSeq(...)

Events within the same ``addBlock()`` call execute simultaneously. The ``Sequence``
object deduplicates identical events automatically.

Example Sequences
-----------------

The ``examples/`` directory contains 11 complete pulse sequences ported from PyPulseq:

.. list-table::
   :header-rows: 1
   :widths: 35 65

   * - File
     - Description
   * - ``write_gre.nim``
     - Gradient-recalled echo
   * - ``write_epi.nim``
     - Echo-planar imaging
   * - ``write_epi_se.nim``
     - Spin-echo EPI
   * - ``write_haste.nim``
     - Half-Fourier single-shot TSE
   * - ``write_tse.nim``
     - Turbo spin echo
   * - ``write_mprage.nim``
     - Magnetization-prepared rapid gradient echo
   * - ``write_radial_gre.nim``
     - Radial GRE
   * - ``write_ute.nim``
     - Ultrashort echo time

Run any example:

.. code-block:: bash

   nim c -r examples/write_haste.nim

Running Tests
-------------

.. code-block:: bash

   bash tests/run_tests.sh
