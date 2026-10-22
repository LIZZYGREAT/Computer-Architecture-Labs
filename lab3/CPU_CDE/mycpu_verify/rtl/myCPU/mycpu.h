`ifndef MYCPU_H
    `define MYCPU_H

    `define BR_BUS_WD       33
    `define FS_TO_DS_BUS_WD 64
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

    `define DS_TO_ES_BUS_WD 154
    `define ES_TO_MS_BUS_WD 114
    `define MS_TO_WS_BUS_WD 70
    `define WS_TO_RF_BUS_WD 38
`endif
