"""Build report figures from the committed Lab6/Lab7 verification summaries."""

from __future__ import annotations

from pathlib import Path
import re

import matplotlib.pyplot as plt
from matplotlib.patches import FancyArrowPatch, FancyBboxPatch
from matplotlib.path import Path as MplPath


REPORT_ROOT = Path(__file__).resolve().parents[1]
LAB_ROOT = REPORT_ROOT.parents[1]
FIGURES = REPORT_ROOT / "figures"
RESULTS = LAB_ROOT / "results" / "lab6_lab7"

NAVY = "#17324D"
BLUE = "#3B78A5"
TEAL = "#42A596"
GOLD = "#E6A64C"
RED = "#C65353"
PALE = "#F2F6F8"
INK = "#203040"
MUTED = "#617486"


def parse_result(path: Path) -> dict[str, str]:
    data: dict[str, str] = {}
    for line in path.read_text(encoding="utf-8-sig").splitlines():
        if "=" in line:
            key, value = line.split("=", 1)
            data[key.strip()] = value.strip()
    return data


def box(ax, xy, width, height, title, subtitle="", color=BLUE, fill=PALE,
        title_size=12, subtitle_size=9, lw=1.5):
    x, y = xy
    patch = FancyBboxPatch(
        (x, y), width, height,
        boxstyle="round,pad=0.04,rounding_size=0.08",
        linewidth=lw, edgecolor=color, facecolor=fill,
    )
    ax.add_patch(patch)
    ax.text(x + width / 2, y + height * 0.63, title,
            ha="center", va="center", color=INK,
            fontsize=title_size, fontweight="bold")
    if subtitle:
        ax.text(x + width / 2, y + height * 0.28, subtitle,
                ha="center", va="center", color=MUTED,
                fontsize=subtitle_size, linespacing=1.25)
    return patch


def arrow(ax, start, end, color=MUTED, lw=1.7, style="-|>",
          connection="arc3,rad=0", linestyle="solid", mutation=13):
    p = FancyArrowPatch(
        start, end, arrowstyle=style, mutation_scale=mutation,
        connectionstyle=connection, linewidth=lw, color=color,
        linestyle=linestyle, shrinkA=3, shrinkB=3,
    )
    ax.add_patch(p)
    return p


def save(fig, name: str) -> None:
    FIGURES.mkdir(parents=True, exist_ok=True)
    fig.savefig(FIGURES / name, dpi=220, bbox_inches="tight", facecolor="white")
    plt.close(fig)


def draw_pipeline() -> None:
    fig, ax = plt.subplots(figsize=(13.0, 5.4))
    ax.set_xlim(0, 13)
    ax.set_ylim(-0.1, 5.2)
    ax.axis("off")
    ax.text(6.5, 4.92, "Five-stage CPU and Lab6/Lab7 control points",
            ha="center", va="center", fontsize=16, color=NAVY, fontweight="bold")

    xs = [0.35, 2.85, 5.35, 7.85, 10.35]
    w, h, y = 2.0, 0.82, 3.15
    labels = [
        ("IF", "PC / instruction ROM", BLUE),
        ("ID", "decode / RAW / redirect", TEAL),
        ("EX", "ALU / mult / div", GOLD),
        ("MEM", "sync RAM / byte lanes", BLUE),
        ("WB", "GPR / HI-LO commit", TEAL),
    ]
    for i, (title, subtitle, color) in enumerate(labels):
        box(ax, (xs[i], y), w, h, title, subtitle, color=color,
            fill="#F4F8FA", title_size=14, subtitle_size=8.7)
        if i < len(xs) - 1:
            arrow(ax, (xs[i] + w + 0.08, y + h / 2),
                  (xs[i + 1] - 0.08, y + h / 2), color=NAVY, lw=1.8)

    # Keep the control-point notes directly beneath their owning stage. The
    # vertical links make the correspondence clear without crossing labels.
    notes = [
        ("IF control", "sync instruction\nROM", BLUE, "#F4F8FA"),
        ("Operand / branch", "RAW check\nEX > MEM > WB > RF", TEAL, "#E9F5F2"),
        ("EX control", "HI/LO busy/done\nbackpressure", GOLD, "#FFF5E6"),
        ("MEM control", "byte lanes / merge\nsign / zero extend", BLUE, "#F4F8FA"),
        ("WB control", "valid commit\nzero write checked", TEAL, "#E9F5F2"),
    ]
    for i, (title, subtitle, color, fill) in enumerate(notes):
        box(ax, (xs[i], 0.66), w, 1.28, title, subtitle,
            color=color, fill=fill, title_size=9.7, subtitle_size=7.6)
        arrow(ax, (xs[i] + w / 2, 1.96), (xs[i] + w / 2, y - 0.04),
              color=color, lw=1.25, mutation=10)
    save(fig, "cpu_pipeline.png")


def draw_hilo_fsm() -> None:
    fig, ax = plt.subplots(figsize=(10.6, 5.7))
    ax.set_xlim(0, 10.6)
    ax.set_ylim(0, 6.0)
    ax.axis("off")
    ax.text(5.3, 5.62, "HI/LO operation handshake", ha="center", va="center",
            fontsize=16, color=NAVY, fontweight="bold")

    states = {
        "idle": (0.65, 2.55, 2.0, 1.05, "IDLE", "accept one request", TEAL, "#E9F5F2"),
        "mult": (4.05, 4.0, 2.25, 1.05, "MULT_WAIT", "pipelined product", GOLD, "#FFF5E6"),
        "div": (4.05, 1.15, 2.25, 1.05, "DIV_WAIT", "divider valid", GOLD, "#FFF5E6"),
        "done": (7.75, 2.55, 2.1, 1.05, "DONE", "hold until consume", BLUE, "#EAF2F8"),
    }
    coords = {}
    for key, (x, y, w, h, title, subtitle, color, fill) in states.items():
        box(ax, (x, y), w, h, title, subtitle, color, fill,
            title_size=12, subtitle_size=8.2)
        coords[key] = (x, y, w, h)

    arrow(ax, (2.68, 3.42), (4.00, 4.30), TEAL, connection="arc3,rad=0.05")
    ax.text(3.22, 4.13, "start & MULT/MULTU", fontsize=8.3, color=INK,
            ha="center", va="center", rotation=25)
    arrow(ax, (2.68, 2.75), (4.00, 1.95), TEAL, connection="arc3,rad=-0.05")
    ax.text(3.24, 2.02, "start & DIV/DIVU", fontsize=8.3, color=INK,
            ha="center", va="center", rotation=-22)
    arrow(ax, (6.35, 4.42), (7.70, 3.34), GOLD, connection="arc3,rad=-0.05")
    ax.text(7.16, 4.03, "result captured", fontsize=8.3, color=INK,
            ha="center", va="center", rotation=-26)
    arrow(ax, (6.35, 1.72), (7.70, 2.80), GOLD, connection="arc3,rad=0.05")
    ax.text(7.10, 2.05, "valid result", fontsize=8.3, color=INK,
            ha="center", va="center", rotation=26)
    # Route DONE -> IDLE below the divider node so the return path does not
    # obscure the DIV_WAIT label.
    consume_path = MplPath(
        [(8.80, 2.52), (8.80, 0.72), (1.65, 0.72), (1.65, 2.52)],
        [MplPath.MOVETO, MplPath.LINETO, MplPath.LINETO, MplPath.LINETO],
    )
    ax.add_patch(FancyArrowPatch(
        path=consume_path, arrowstyle="-|>", mutation_scale=13,
        linewidth=1.7, color=BLUE,
    ))
    ax.text(5.25, 0.30, "consume_done returns to IDLE; reset clears state and cancels an in-flight divide",
            ha="center", va="center", fontsize=8.4, color=BLUE)
    ax.text(5.30, 3.04, "HI = high product / remainder\nLO = low product / quotient",
            ha="center", va="center", fontsize=8.5, color=NAVY,
            bbox=dict(boxstyle="round,pad=0.35", facecolor="white", edgecolor="#D5DEE5"))
    save(fig, "hilo_handshake.png")


def draw_branch_case() -> None:
    fig, ax = plt.subplots(figsize=(12.4, 5.0))
    ax.set_xlim(0, 12.4)
    ax.set_ylim(0, 5.3)
    ax.axis("off")
    ax.text(6.2, 4.95, "Directed case: branch immediately after a multi-cycle DIV",
            ha="center", va="center", fontsize=15, color=NAVY, fontweight="bold")

    items = [
        (0.35, "0x08", "DIV r1,r2", "-23 / 5", GOLD, "#FFF5E6"),
        (2.75, "0x0C", "BEQ r0,r0", "taken", TEAL, "#E9F5F2"),
        (5.15, "0x10", "delay slot", "r3 = 0x55", BLUE, "#EAF2F8"),
        (7.55, "0x14", "fall-through", "r4 = 0x1234", RED, "#FBECEC"),
        (9.95, "0x18", "target / MFLO", "r5 = -4", TEAL, "#E9F5F2"),
    ]
    nodes = []
    for x, pc, op, desc, color, fill in items:
        nodes.append(box(ax, (x, 2.45), 2.05, 1.14,
                         f"{pc}  {op}", desc, color, fill,
                         title_size=9.3, subtitle_size=8.5))
    for i in range(2):
        arrow(ax, (items[i][0] + 2.08, 3.02), (items[i + 1][0] - 0.06, 3.02), MUTED)
    # The taken branch keeps the delay slot and then bypasses fall-through.
    branch_path = MplPath(
        [(6.17, 2.42), (6.17, 1.72), (10.98, 1.72), (10.98, 2.42)],
        [MplPath.MOVETO, MplPath.LINETO, MplPath.LINETO, MplPath.LINETO],
    )
    ax.add_patch(FancyArrowPatch(
        path=branch_path, arrowstyle="-|>", mutation_scale=13,
        linewidth=2.0, color=TEAL,
    ))
    ax.text(8.55, 1.45, "taken branch redirects after the delay slot", fontsize=8.7,
            color=TEAL, ha="center")
    ax.text(8.58, 2.05, "must not retire", fontsize=8.2, color=RED, ha="center")

    box(ax, (1.05, 0.35), 2.55, 0.72, "HI / remainder", "r6 = -3", BLUE, "#EAF2F8", 9.5, 8)
    box(ax, (4.28, 0.35), 2.55, 0.72, "MFLO / quotient", "r5 = -4", BLUE, "#EAF2F8", 9.5, 8)
    box(ax, (7.52, 0.35), 3.2, 0.72, "branch target marker", "r7 = 0x66", TEAL, "#E9F5F2", 9.5, 8)
    ax.text(6.2, 0.05,
            "Observed trace: r3, r5, r6 and r7 are written; no r4 write appears.",
            ha="center", va="center", fontsize=8.8, color=INK)
    save(fig, "div_branch_delay_slot.png")


def draw_verification_summary() -> None:
    lab6 = parse_result(RESULTS / "lab6-20261022T062908Z" / "result.txt")
    lab7 = parse_result(RESULTS / "lab7-20261022T063433Z" / "result.txt")
    rows = [
        ("Lab6", int(lab6["FUNCTIONAL_POINT_PASSES"]),
         int(lab6["EXPECTED_FUNCTIONAL_POINTS"]), BLUE),
        ("Lab7", int(lab7["FUNCTIONAL_POINT_PASSES"]),
         int(lab7["EXPECTED_FUNCTIONAL_POINTS"]), TEAL),
    ]
    for name, passed, expected, _ in rows:
        if passed != expected:
            raise RuntimeError(f"{name} is not a full PASS: {passed}/{expected}")
    fig, ax = plt.subplots(figsize=(10.4, 3.4))
    ax.set_xlim(0, 106)
    ax.set_ylim(-0.8, 1.8)
    ax.set_yticks([1, 0], ["Lab6 cumulative suite", "Lab7 cumulative suite"])
    ax.set_xticks([0, 20, 40, 60, 80, 100], ["0", "20", "40", "60", "80", "100%"])
    ax.set_xlabel("Functional points passed")
    ax.grid(axis="x", color="#D9E1E7", linewidth=0.8)
    ax.set_axisbelow(True)
    for y, (name, passed, expected, color) in zip([1, 0], rows):
        ax.barh(y, 100, height=0.48, color="#E8EDF1", edgecolor="none")
        ax.barh(y, 100 * passed / expected, height=0.48,
                color=color, edgecolor="none")
        ax.text(50, y, f"{passed} / {expected}", color="white",
                ha="center", va="center", fontsize=12, fontweight="bold")
    ax.spines[["top", "right", "left"]].set_visible(False)
    ax.spines["bottom"].set_color("#AAB8C2")
    ax.tick_params(axis="y", length=0, labelcolor=INK, labelsize=10)
    ax.tick_params(axis="x", colors=MUTED, labelsize=8)
    ax.xaxis.label.set_color(MUTED)
    ax.xaxis.label.set_size(9)
    ax.set_title("Cumulative functional-point acceptance", color=NAVY,
                 fontsize=14, fontweight="bold", pad=14)
    fig.tight_layout()
    save(fig, "functional_coverage.png")


def main() -> None:
    plt.rcParams.update({
        "font.family": "DejaVu Sans",
        "font.size": 9,
        "axes.edgecolor": "#AAB8C2",
        "figure.facecolor": "white",
        "savefig.facecolor": "white",
    })
    draw_pipeline()
    draw_hilo_fsm()
    draw_branch_case()
    draw_verification_summary()
    print(f"Generated report figures in {FIGURES}")


if __name__ == "__main__":
    main()
