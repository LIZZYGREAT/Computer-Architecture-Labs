# Lab8 / Lab9 known limitations

- The stronger T14 sequence with an older store, a faulting store, and a younger store is not covered by one dedicated RAM-scoreboard CPU test. Course Lab9 and the external-interrupt younger-store test cover related behavior, but do not replace that exact sequence.
- HI/LO cancellation is tested directly in the HI/LO unit, including preservation of previously committed values. There is no integrated CPU test that injects a synchronous exception while a divide is in flight.
- The Lab9 course image validates timer and software interrupts; CP0 tests validate their masks and clear semantics. Unlike the external IP2-IP7 paths, timer and software interrupts do not have separate standalone CPU directed ROMs in this work.
- WDBs and WCFGs have been generated and validated. The GUI screenshots, observed time windows, and observed values have not been collected. `workflow.md` assigns the final screenshot save step to the user; those observed fields remain blank in the capture CSV.
- SoC hardware mode synchronizes `switch[5:0]` into IP2-IP7 and no longer exposes an unconstrained `ext_int` board port. This task did not run synthesis/implementation, produce a bitstream, or verify switch polarity and behavior on the FPGA board.
