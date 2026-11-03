"""Build local Vivado Wave configurations from the capture handoff signal lists.

The source WCFGs in figures/ are kept untouched. This script creates local
copies under figures/waveforms/ and binds each copy to a WDB that exists in the
current checkout. It does not run a simulation or export screenshots.
"""

from __future__ import annotations

from pathlib import Path
import xml.etree.ElementTree as ET


REPORT = Path(__file__).resolve().parents[1]
FIGURES = REPORT / "figures"
OUTPUT = FIGURES / "waveforms/recaptured-20261102"
LAB = REPORT.parents[1]
TEMPLATE = FIGURES / "waveforms/01_alu_directed_full_run.wcfg"

ALU_WDB = LAB / "results/lab3_lab4/lab3-20261028T132600Z/lab3-20261028T132600Z-forwarding.wdb"
LAB6_WDB = LAB / "results/lab6_lab7/lab6-20261102T054949Z/lab6-20261102T054949Z-forwarding.wdb"
LAB7_WDB = LAB / "results/lab6_lab7/lab7-20261102T055526Z/lab7-20261102T055526Z-forwarding.wdb"


def sig(scope: str, name: str, bit_range: str | None = None, radix: str = "HEXRADIX") -> tuple[str, str, str | None, str]:
    return (scope, name, bit_range, radix)


TB = ""
ID = "soc_lite/cpu/id_stage"
IF = "soc_lite/cpu/if_stage"
EX = "soc_lite/cpu/exe_stage"
HILO = "soc_lite/cpu/exe_stage/u_hilo_unit"
MEM = "soc_lite/cpu/mem_stage"

CLK = sig(TB, "clk", None, "BINARYRADIX")
WB = [
    sig(TB, "debug_wb_pc", "31:0"),
    sig(TB, "debug_wb_rf_wen", "3:0", "BINARYRADIX"),
    sig(TB, "debug_wb_rf_wnum", "4:0", "UNSIGNEDDECRADIX"),
    sig(TB, "debug_wb_rf_wdata", "31:0"),
]

CONFIGS: list[tuple[str, Path, tuple[str, str], list[tuple[str, str, str | None, str]]]] = [
    (
        "01_alu_immediate.wcfg",
        ALU_WDB,
        ("0 ns", "800 ns"),
        [
            CLK, sig(TB, "resetn", None, "BINARYRADIX"),
            sig(EX, "es_pc", "31:0"), sig(EX, "es_valid", None, "BINARYRADIX"),
            sig(EX, "es_imm", "31:0"), sig(EX, "es_src2_is_imm", None, "BINARYRADIX"),
            sig(EX, "es_imm_zero_extend", None, "BINARYRADIX"), sig(EX, "es_alu_op", "11:0", "BINARYRADIX"),
            sig(EX, "es_alu_src1", "31:0"), sig(EX, "es_alu_src2", "31:0"),
            sig(EX, "es_alu_result", "31:0"), sig(EX, "es_dest", "4:0", "UNSIGNEDDECRADIX"),
            sig(EX, "es_gr_we", None, "BINARYRADIX"), *WB,
        ],
    ),
    (
        "02_variable_shift.wcfg",
        ALU_WDB,
        ("0 ns", "800 ns"),
        [
            CLK,
            sig(EX, "es_pc", "31:0"), sig(EX, "es_valid", None, "BINARYRADIX"),
            sig(EX, "es_rs_value", "31:0"), sig(EX, "es_rt_value", "31:0"),
            sig(EX, "es_alu_src1", "31:0"), sig(EX, "es_alu_src2", "31:0"),
            sig(EX, "es_alu_op", "11:0", "BINARYRADIX"), sig(EX, "es_alu_result", "31:0"),
            sig(EX, "es_dest", "4:0", "UNSIGNEDDECRADIX"), *WB,
        ],
    ),
    (
        "03_forwarding_load_use.wcfg",
        ALU_WDB,
        ("0 ns", "800 ns"),
        [
            CLK,
            sig(ID, "ds_pc", "31:0"), sig(ID, "ds_inst", "31:0"),
            sig(ID, "ds_valid", None, "BINARYRADIX"), sig(ID, "ds_rs_hazard", None, "BINARYRADIX"),
            sig(ID, "ds_rt_hazard", None, "BINARYRADIX"), sig(ID, "ds_stall", None, "BINARYRADIX"),
            sig(ID, "ds_forward_rs_ex", None, "BINARYRADIX"), sig(ID, "ds_forward_rs_ms", None, "BINARYRADIX"),
            sig(ID, "ds_forward_rs_ws", None, "BINARYRADIX"), sig(ID, "ds_forward_rt_ex", None, "BINARYRADIX"),
            sig(ID, "ds_forward_rt_ms", None, "BINARYRADIX"), sig(ID, "ds_forward_rt_ws", None, "BINARYRADIX"),
            sig(ID, "rs_value", "31:0"), sig(ID, "rt_value", "31:0"), sig(ID, "ds_allowin", None, "BINARYRADIX"),
            sig(EX, "es_pc", "31:0"), sig(EX, "es_allowin", None, "BINARYRADIX"),
            sig(EX, "es_ready_go", None, "BINARYRADIX"), sig(EX, "es_alu_result", "31:0"), *WB,
        ],
    ),
    (
        "04_mult_hilo.wcfg",
        LAB6_WDB,
        ("887201.350 ns", "887343.251 ns"),
        [
            CLK, sig(EX, "es_pc", "31:0"), sig(EX, "es_valid", None, "BINARYRADIX"),
            sig(EX, "es_rs_value", "31:0"), sig(EX, "es_rt_value", "31:0"),
            sig(EX, "es_hilo_start", None, "BINARYRADIX"), sig(EX, "es_hilo_busy", None, "BINARYRADIX"),
            sig(EX, "es_hilo_done", None, "BINARYRADIX"), sig(EX, "es_hilo_consume", None, "BINARYRADIX"),
            sig(EX, "es_ready_go", None, "BINARYRADIX"), sig(EX, "es_allowin", None, "BINARYRADIX"),
            sig(EX, "hilo_hi_value", "31:0"), sig(EX, "hilo_lo_value", "31:0"),
            sig(HILO, "state", "1:0", "BINARYRADIX"), sig(HILO, "accept_mult", None, "BINARYRADIX"),
            sig(HILO, "mult_product", "65:0"), sig(HILO, "hi_reg", "31:0"), sig(HILO, "lo_reg", "31:0"), *WB,
        ],
    ),
    (
        "05_div_hilo_full_lab6.wcfg",
        LAB6_WDB,
        ("0 ns", "1,094,390 ns"),
        [
            CLK, sig(ID, "ds_pc", "31:0"), sig(ID, "ds_inst", "31:0"),
            sig(ID, "ds_valid", None, "BINARYRADIX"), sig(ID, "ds_allowin", None, "BINARYRADIX"),
            sig(ID, "br_taken", None, "BINARYRADIX"), sig(ID, "br_target", "31:0"),
            sig(EX, "es_pc", "31:0"), sig(EX, "es_valid", None, "BINARYRADIX"),
            sig(EX, "es_rs_value", "31:0"), sig(EX, "es_rt_value", "31:0"),
            sig(EX, "es_hilo_start", None, "BINARYRADIX"), sig(EX, "es_hilo_busy", None, "BINARYRADIX"),
            sig(EX, "es_hilo_done", None, "BINARYRADIX"), sig(EX, "es_hilo_consume", None, "BINARYRADIX"),
            sig(EX, "es_ready_go", None, "BINARYRADIX"), sig(EX, "es_allowin", None, "BINARYRADIX"),
            sig(EX, "hilo_hi_value", "31:0"), sig(EX, "hilo_lo_value", "31:0"),
            sig(HILO, "state", "1:0", "BINARYRADIX"), sig(HILO, "accept_div", None, "BINARYRADIX"),
            sig(HILO, "dividend_ready", None, "BINARYRADIX"), sig(HILO, "divisor_ready", None, "BINARYRADIX"),
            sig(HILO, "div_result_valid", None, "BINARYRADIX"), sig(HILO, "div_result", "63:0"), *WB,
        ],
    ),
    (
        "06_branch_delay_slot_jalr.wcfg",
        LAB7_WDB,
        ("0 ns", "1,663,300 ns"),
        [
            CLK, sig(IF, "fs_pc", "31:0"), sig(IF, "nextpc", "31:0"),
            sig(ID, "ds_pc", "31:0"), sig(ID, "ds_inst", "31:0"),
            sig(ID, "ds_valid", None, "BINARYRADIX"), sig(ID, "rs_value", "31:0"),
            sig(ID, "ds_branch_cond_taken", None, "BINARYRADIX"), sig(ID, "br_taken", None, "BINARYRADIX"),
            sig(ID, "br_target", "31:0"), sig(ID, "ds_allowin", None, "BINARYRADIX"),
            sig(ID, "ds_forward_rs_ex", None, "BINARYRADIX"), sig(ID, "ds_forward_rs_ms", None, "BINARYRADIX"),
            sig(ID, "ds_forward_rs_ws", None, "BINARYRADIX"), sig(EX, "es_pc", "31:0"),
            sig(EX, "es_allowin", None, "BINARYRADIX"), *WB,
        ],
    ),
    (
        "07_partial_store_mask.wcfg",
        LAB7_WDB,
        ("0 ns", "1,663,300 ns"),
        [
            CLK, sig(ID, "ds_pc", "31:0"), sig(ID, "ds_inst", "31:0"),
            sig(ID, "ds_forward_rt_ex", None, "BINARYRADIX"), sig(ID, "ds_forward_rt_ms", None, "BINARYRADIX"),
            sig(ID, "ds_forward_rt_ws", None, "BINARYRADIX"), sig(EX, "es_pc", "31:0"),
            sig(EX, "es_valid", None, "BINARYRADIX"), sig(EX, "es_mem_op", "11:0", "BINARYRADIX"),
            sig(EX, "es_alu_result", "31:0"), sig(EX, "es_rt_value", "31:0"),
            sig(EX, "es_store_wen", "3:0", "BINARYRADIX"), sig(EX, "es_store_data", "31:0"),
            sig(EX, "data_sram_en", None, "BINARYRADIX"), sig(EX, "data_sram_addr", "31:0"),
            sig(EX, "data_sram_wen", "3:0", "BINARYRADIX"), sig(EX, "data_sram_wdata", "31:0"),
        ],
    ),
    (
        "08_byte_half_load.wcfg",
        LAB7_WDB,
        ("0 ns", "1,663,300 ns"),
        [
            CLK, sig(ID, "ds_pc", "31:0"), sig(ID, "ds_inst", "31:0"),
            sig(ID, "inst_lb", None, "BINARYRADIX"), sig(ID, "inst_lbu", None, "BINARYRADIX"),
            sig(ID, "inst_lh", None, "BINARYRADIX"), sig(ID, "inst_lhu", None, "BINARYRADIX"),
            sig(EX, "es_pc", "31:0"), sig(EX, "es_alu_result", "31:0"),
            sig(EX, "data_sram_en", None, "BINARYRADIX"), sig(EX, "data_sram_addr", "31:0"),
            sig(MEM, "ms_pc", "31:0"), sig(MEM, "ms_mem_op", "11:0", "BINARYRADIX"),
            sig(MEM, "ms_alu_result", "31:0"), sig(MEM, "data_sram_rdata", "31:0"),
            sig(MEM, "mem_result", "31:0"), sig(MEM, "ms_final_result", "31:0"), *WB,
        ],
    ),
    (
        "09_unaligned_load_merge.wcfg",
        LAB7_WDB,
        ("0 ns", "1,663,300 ns"),
        [
            CLK, sig(ID, "ds_pc", "31:0"), sig(ID, "ds_inst", "31:0"),
            sig(ID, "inst_lwl", None, "BINARYRADIX"), sig(ID, "inst_lwr", None, "BINARYRADIX"),
            sig(EX, "es_pc", "31:0"), sig(EX, "es_rt_value", "31:0"), sig(EX, "es_alu_result", "31:0"),
            sig(MEM, "ms_pc", "31:0"), sig(MEM, "ms_mem_op", "11:0", "BINARYRADIX"),
            sig(MEM, "ms_alu_result", "31:0"), sig(MEM, "ms_rt_value", "31:0"),
            sig(MEM, "data_sram_rdata", "31:0"), sig(MEM, "mem_result", "31:0"),
            sig(MEM, "ms_final_result", "31:0"), *WB,
        ],
    ),
    (
        "10_store_readback.wcfg",
        LAB7_WDB,
        ("0 ns", "1,663,300 ns"),
        [
            CLK, sig(ID, "ds_pc", "31:0"), sig(ID, "ds_inst", "31:0"),
            sig(ID, "inst_sb", None, "BINARYRADIX"), sig(ID, "inst_sh", None, "BINARYRADIX"),
            sig(ID, "inst_swl", None, "BINARYRADIX"), sig(ID, "inst_swr", None, "BINARYRADIX"),
            sig(EX, "es_pc", "31:0"), sig(EX, "es_alu_result", "31:0"), sig(EX, "es_rt_value", "31:0"),
            sig(EX, "es_store_wen", "3:0", "BINARYRADIX"), sig(EX, "es_store_data", "31:0"),
            sig(EX, "data_sram_en", None, "BINARYRADIX"), sig(EX, "data_sram_addr", "31:0"),
            sig(EX, "data_sram_wen", "3:0", "BINARYRADIX"), sig(EX, "data_sram_wdata", "31:0"),
            sig(MEM, "ms_pc", "31:0"), sig(MEM, "data_sram_rdata", "31:0"),
            sig(MEM, "ms_alu_result", "31:0"), sig(MEM, "mem_result", "31:0"), *WB,
        ],
    ),
    (
        "11_hilo_unsigned_optional.wcfg",
        LAB6_WDB,
        ("0 ns", "1,094,390 ns"),
        [
            CLK, sig(ID, "inst_divu", None, "BINARYRADIX"), sig(EX, "es_pc", "31:0"),
            sig(EX, "es_rs_value", "31:0"), sig(EX, "es_rt_value", "31:0"),
            sig(EX, "es_hilo_start", None, "BINARYRADIX"), sig(EX, "es_hilo_busy", None, "BINARYRADIX"),
            sig(EX, "es_hilo_done", None, "BINARYRADIX"), sig(EX, "es_hilo_consume", None, "BINARYRADIX"),
            sig(EX, "es_ready_go", None, "BINARYRADIX"), sig(EX, "es_allowin", None, "BINARYRADIX"),
            sig(EX, "hilo_hi_value", "31:0"), sig(EX, "hilo_lo_value", "31:0"),
            sig(HILO, "state", "1:0", "BINARYRADIX"), sig(HILO, "accept_div", None, "BINARYRADIX"),
            sig(HILO, "div_result_valid", None, "BINARYRADIX"), sig(HILO, "div_result", "63:0"), *WB,
        ],
    ),
]


def add_signal(root: ET.Element, top_path: str, spec: tuple[str, str, str | None, str]) -> None:
    scope, name, bit_range, radix = spec
    object_name = f"{top_path}{scope}/{name}"
    label = f"{name}[{bit_range}]" if bit_range else name
    element = ET.SubElement(root, "wvobject", {"fp_name": object_name, "type": "array" if bit_range else "logic"})
    for prop_name, value in (
        ("ElementShortName", label),
        ("ObjectShortName", label),
    ):
        prop = ET.SubElement(element, "obj_property", {"name": prop_name})
        prop.text = value
    if bit_range:
        style = ET.SubElement(element, "obj_property", {"name": "WaveformStyle"})
        style.text = "STYLE_DIGITAL"
    radix_prop = ET.SubElement(element, "obj_property", {"name": "Radix"})
    radix_prop.text = radix


def build_one(filename: str, wdb: Path, zoom: tuple[str, str], signals: list[tuple[str, str, str | None, str]]) -> None:
    if not wdb.is_file():
        raise FileNotFoundError(f"WDB required for {filename} is missing: {wdb}")
    tree = ET.parse(TEMPLATE)
    root = tree.getroot()
    db_ref = root.find("./db_ref_list/db_ref")
    if db_ref is None:
        raise ValueError(f"WCFG has no db_ref: {TEMPLATE}")
    db_ref.set("path", wdb.resolve().as_posix())

    top_module = root.find("./db_ref_list/db_ref/top_modules/top_module")
    if top_module is None or not top_module.get("name"):
        raise ValueError(f"WCFG has no top-module name: {TEMPLATE}")
    top_path = f"/{top_module.get('name')}/"

    for old in root.findall("./wvobject"):
        root.remove(old)
    object_count = root.find("./WVObjectSize")
    if object_count is not None:
        object_count.set("size", str(len(signals)))
    markers = root.find("./wave_markers")
    if markers is not None:
        markers.clear()
    zoom_start = root.find("./zoom_setting/ZoomStartTime")
    zoom_end = root.find("./zoom_setting/ZoomEndTime")
    cursor = root.find("./zoom_setting/Cursor1Time")
    if zoom_start is not None:
        zoom_start.set("time", zoom[0])
    if zoom_end is not None:
        zoom_end.set("time", zoom[1])
    if cursor is not None:
        cursor.set("time", zoom[0])

    for signal in signals:
        add_signal(root, top_path, signal)
    ET.indent(tree, space="   ")
    output = OUTPUT / filename
    tree.write(output, encoding="UTF-8", xml_declaration=True)
    ET.parse(output)  # Ensure every generated config is well-formed XML.


def main() -> None:
    OUTPUT.mkdir(parents=True, exist_ok=True)
    for filename, wdb, zoom, signals in CONFIGS:
        build_one(filename, wdb, zoom, signals)
    # Recreate the previous directed-ALU convenience filename from the
    # preserved ALU signal layout, while binding it to the available WDB.
    alias = OUTPUT / "01_alu_directed_full_run.wcfg"
    alias.write_bytes((OUTPUT / "01_alu_immediate.wcfg").read_bytes())
    ET.parse(alias)
    print(f"Generated {len(CONFIGS)} Vivado Wave configs and one ALU compatibility copy in {OUTPUT}")


if __name__ == "__main__":
    main()
