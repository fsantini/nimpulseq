Porting Guide
=============

This page summarises key differences when converting PyPulseq scripts to NimPulseq.
For the full guide see ``PORTING_GUIDE.md`` in the repository root.

Naming Conventions
------------------

Nim uses ``camelCase`` for identifiers. The mapping from PyPulseq snake_case is direct:

.. list-table::
   :header-rows: 1
   :widths: 50 50

   * - PyPulseq (Python)
     - NimPulseq (Nim)
   * - ``make_trapezoid``
     - ``makeTrapezoid``
   * - ``make_sinc_pulse``
     - ``makeSincPulse``
   * - ``make_adc``
     - ``makeAdc``
   * - ``make_delay``
     - ``makeDelay``
   * - ``seq.add_block(...)``
     - ``seqObj.addBlock(...)``
   * - ``seq.check_timing()``
     - ``seqObj.checkTiming()``
   * - ``seq.write(path)``
     - ``seqObj.writeSeq(path)``

Type System
-----------

All events are represented as a single ``Event`` variant object. The active branch
is selected by the ``kind: EventKind`` discriminator field.

.. code-block:: nim

   # Access RF-specific fields
   echo rf.rfShapeDur    # only valid when rf.kind == ekRf

   # Access trapezoid fields
   echo gz.trapAmplitude # only valid when gz.kind == ekTrap

Units
-----

All internal values use SI units:

- Gradient amplitudes: **Hz/m** (convert with ``newOpts(gradUnit = "mT/m")``)
- Slew rates: **Hz/m/s** (convert with ``newOpts(slewUnit = "T/m/s")``)
- Time: **seconds**
- Angles: **radians**

Not Implemented
---------------

NimPulseq focuses on ``.seq`` file generation. The following PyPulseq features are
not implemented:

- Visualisation / plotting
- k-space and gradient spectral analysis
- ``.seq`` file reading/parsing
- PNS safety prediction
- SigPy integration
