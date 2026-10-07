"""Independent integer golden model. Standard library only; no NumPy required."""
from pathlib import Path
import random

ROOT = Path(__file__).resolve().parents[1]
M, K, N = 11, 17, 13


def matmul(a, b):
    return [[sum(a[i][k] * b[k][j] for k in range(len(b)))
             for j in range(len(b[0]))] for i in range(len(a))]


def write_hex(path, values, bits):
    mask = (1 << bits) - 1
    path.write_text("".join(f"{x & mask:0{bits // 4}x}\n" for x in values), encoding="ascii")


def main():
    rng = random.Random(20261007)
    a = [[rng.randrange(-128, 128) for _ in range(K)] for _ in range(M)]
    b = [[rng.randrange(-128, 128) for _ in range(N)] for _ in range(K)]
    a[0][:4] = [-128, 127, 0, -1]
    b[0][:4] = [-128, 127, 0, 1]
    c = matmul(a, b)
    out = ROOT / "sim" / "vectors"
    out.mkdir(parents=True, exist_ok=True)
    for name, matrix, bits in (("a", a, 8), ("b", b, 8), ("c", c, 32)):
        write_hex(out / f"{name}.mem", [x for row in matrix for x in row], bits)
    print(f"Generated A[{M},{K}] x B[{K},{N}] -> C[{M},{N}] in {out}")


if __name__ == "__main__":
    main()
