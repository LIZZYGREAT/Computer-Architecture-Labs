`ifndef MYCPU_H
    `define MYCPU_H

    `define BR_BUS_WD       34
    `define FS_TO_DS_BUS_WD 103
    `define EXC_INT         5'd0
    `define EXC_ADEL        5'd4
    `define EXC_ADES        5'd5
    `define EXC_SYS         5'd8
    `define EXC_BP          5'd9
    `define EXC_RI          5'd10
    `define EXC_OV          5'd12

    `define CP0_OP_NONE     2'b00
    `define CP0_OP_MFC0     2'b01
    `define CP0_OP_MTC0     2'b10
    `define CP0_OP_ERET     2'b11
    `define HILO_OP_MULT  0
    `define HILO_OP_MULTU 1
    `define HILO_OP_DIV   2
    `define HILO_OP_DIVU  3
    `define HILO_OP_MFHI  4
    `define HILO_OP_MFLO  5
    `define HILO_OP_MTHI  6
    `define HILO_OP_MTLO  7
    `define HILO_OP_WD    8

    `define MEM_OP_WD     12
    `define MEM_OP_LW      0
    `define MEM_OP_LB      1
    `define MEM_OP_LBU     2
    `define MEM_OP_LH      3
    `define MEM_OP_LHU     4
    `define MEM_OP_LWL     5
    `define MEM_OP_LWR     6
    `define MEM_OP_SW      7
    `define MEM_OP_SB      8
    `define MEM_OP_SH      9
    `define MEM_OP_SWL    10
    `define MEM_OP_SWR    11

    `define DS_TO_ES_BUS_WD 235
    `define ES_TO_MS_BUS_WD 195
    `define MS_TO_WS_BUS_WD 70
    `define WS_TO_RF_BUS_WD 38
`endif
