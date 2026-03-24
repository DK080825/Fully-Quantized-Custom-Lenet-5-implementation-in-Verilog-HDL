import os
import re
from pathlib import Path


# ============================================================
# USER SETTINGS
# ============================================================
# Folder containing all .coe files
COE_DIR = r"D:\Verilog_learning\INT8_LENET_Implemetation\INT8_coe_files"

# Number of output filters
NUM_FILTERS = 16

# Number of input channels concatenated into each Layer2_Fx.coe
NUM_INPUTS = 6

# Source naming: conv2_f{f}_in{i}.coe
# Packed naming: Layer2_F{f}.coe
# ============================================================


def parse_coe_file(path):
    """
    Parse a .coe file and return:
      radix (int), values (list of int)
    Supports signed decimal source files and unsigned decimal packed files.
    """
    text = Path(path).read_text().strip()

    radix_match = re.search(r"memory_initialization_radix\s*=\s*(\d+)\s*;", text, re.IGNORECASE)
    if not radix_match:
        raise ValueError(f"Cannot find radix in file: {path}")
    radix = int(radix_match.group(1))

    vec_match = re.search(
        r"memory_initialization_vector\s*=\s*(.*)\s*;",
        text,
        re.IGNORECASE | re.DOTALL
    )
    if not vec_match:
        raise ValueError(f"Cannot find initialization vector in file: {path}")

    vec_text = vec_match.group(1)
    raw_items = [x.strip() for x in vec_text.replace("\n", " ").split(",")]
    raw_items = [x for x in raw_items if x != ""]

    values = []
    for item in raw_items:
        if radix == 10:
            values.append(int(item))
        elif radix == 16:
            values.append(int(item, 16))
        elif radix == 2:
            values.append(int(item, 2))
        else:
            raise ValueError(f"Unsupported radix {radix} in file: {path}")

    return radix, values


def to_uint8_from_signed(val):
    """
    Convert signed decimal in range [-128, 127] into 8-bit unsigned two's complement.
    Example:
      22   -> 22
      -75  -> 181
      -128 -> 128
    """
    if val < -128 or val > 127:
        raise ValueError(f"Value {val} is outside signed 8-bit range")
    return val & 0xFF


def pack_6x8bit(vals):
    """
    Pack 6 signed 8-bit values into one 48-bit unsigned integer:
      [7:0]   = vals[0]
      [15:8]  = vals[1]
      [23:16] = vals[2]
      [31:24] = vals[3]
      [39:32] = vals[4]
      [47:40] = vals[5]
    """
    if len(vals) != 6:
        raise ValueError("pack_6x8bit expects exactly 6 values")

    packed = 0
    for i, v in enumerate(vals):
        packed |= (to_uint8_from_signed(v) << (8 * i))
    return packed


def verify_one_filter(folder, filt_idx):
    """
    Verify Layer2_F{filt_idx}.coe against:
      conv2_f{filt_idx}_in0.coe ... conv2_f{filt_idx}_in5.coe
    """
    src_paths = [
        os.path.join(folder, f"conv2_f{filt_idx}_in{i}.coe")
        for i in range(NUM_INPUTS)
    ]
    packed_path = os.path.join(folder, f"Layer2_F{filt_idx}.coe")

    for p in src_paths + [packed_path]:
        if not os.path.exists(p):
            raise FileNotFoundError(f"Missing file: {p}")

    src_values = []
    for p in src_paths:
        radix, vals = parse_coe_file(p)
        if radix != 10:
            raise ValueError(f"Expected radix=10 in source file, got radix={radix} in {p}")
        src_values.append(vals)

    packed_radix, packed_vals = parse_coe_file(packed_path)
    if packed_radix != 10:
        raise ValueError(f"Expected radix=10 in packed file, got radix={packed_radix} in {packed_path}")

    lengths = [len(v) for v in src_values]
    if len(set(lengths)) != 1:
        raise ValueError(
            f"Source files for filter {filt_idx} have mismatched lengths: {lengths}"
        )

    src_len = lengths[0]
    if len(packed_vals) != src_len:
        raise ValueError(
            f"Packed file length mismatch for filter {filt_idx}: "
            f"packed has {len(packed_vals)} values, source has {src_len}"
        )

    mismatches = []

    for idx in range(src_len):
        vals_at_idx = [src_values[in_idx][idx] for in_idx in range(NUM_INPUTS)]
        expected = pack_6x8bit(vals_at_idx)
        actual = packed_vals[idx]

        if expected != actual:
            mismatches.append({
                "index": idx,
                "source_vals": vals_at_idx,
                "expected": expected,
                "actual": actual
            })

    return mismatches


def main():
    total_errors = 0

    for f in range(NUM_FILTERS):
        print(f"\nChecking filter F{f} ...")
        try:
            mismatches = verify_one_filter(COE_DIR, f)

            if not mismatches:
                print(f"  PASS: Layer2_F{f}.coe is correct")
            else:
                print(f"  FAIL: {len(mismatches)} mismatches found in Layer2_F{f}.coe")
                total_errors += len(mismatches)

                # Show first few mismatches
                for m in mismatches[:10]:
                    print(f"    index {m['index']}:")
                    print(f"      source   = {m['source_vals']}")
                    print(f"      expected = {m['expected']}")
                    print(f"      actual   = {m['actual']}")

        except Exception as e:
            total_errors += 1
            print(f"  ERROR: {e}")

    print("\n================================================")
    if total_errors == 0:
        print("ALL FILES VERIFIED SUCCESSFULLY")
    else:
        print(f"VERIFICATION FINISHED WITH {total_errors} ERROR(S)")
    print("================================================")


if __name__ == "__main__":
    main()