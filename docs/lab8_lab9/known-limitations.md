# Lab8 / Lab9 known limitations

- WDBs and WCFGs have been generated and validated. The GUI screenshots, observed time windows, and observed values have not been collected. `workflow.md` assigns the final screenshot save step to the user; those observed fields remain blank in the capture CSV.
- SoC hardware mode synchronizes `switch[5:0]` into IP2-IP7 and no longer exposes an unconstrained `ext_int` board port. This task did not run synthesis/implementation, produce a bitstream, or verify switch polarity and behavior on the FPGA board.
