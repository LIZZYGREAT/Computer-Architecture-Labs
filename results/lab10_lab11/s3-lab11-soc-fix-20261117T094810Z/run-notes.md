# Lab11 S3 full SoC run

- Run ID: `s3-lab11-soc-fix-20261117T094810Z`
- Vivado: 2025.2
- Status: PASS
- Functional points: 94/94
- Strict golden-trace comparison: PASS, 111,625 records consumed (111,583 valid writebacks)
- AXI3 response faults: none
- Waveform: `wave-full.wdb`, captured with recursive `log_wave -r /`; local SHA-256 `62D27FCF8B371554F7B46333DA2D448380A3A3C466DC10FD19F307990D600B4E`
- Directed regression: `s3-lab11-unit-final-20261117T105757Z`, PASS; 2 read transactions, 2 stores, AW-first and W-first, malformed RID/RRESP/RLAST/BID/BRESP, redirect while AR is stalled, and redirect after AR acceptance.
- The earlier failing full run is retained separately as `s3-lab11-soc-20261117T093323Z`; its mismatch was the first exception-vector instruction after redirect. The adapter now acknowledges when it locks an upstream request, so IF tracks stale work even while AXI ARREADY is low.
- This run preceded explicit zero-extension of the crossbar's 4-bit CONFREG LEN outputs to the wrapper's 8-bit LEN inputs. The zero-extension is behavior-preserving for the configured single-beat subset; the final regression phase must re-elaborate and rerun the current source.
- Implemented AXI3 subset: single-beat requests only (`ARLEN=AWLEN=0`, `RLAST=WLAST=1`), one outstanding shared read and one outstanding write, no burst reordering/interleaving claim.
