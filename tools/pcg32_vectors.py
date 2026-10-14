#!/usr/bin/env python3
"""Print PCG32 vectors for WyrdRng.

Transcription of imneme/pcg-c-basic pcg_basic.c at
bc39cd76ac3d541e618606bcc6e1e5ba5e5e6aa3. Not run in CI.
pcg-c-basic does not commit demo stdout. Round 1 of this script matches
imneme/pcg-c test-high/expected/check-pcg32.out at
89b7dfbc5a50e5bf272cfac29dc435e81d2080d3, which is what pcg32-demo.c prints
for pcg32_srandom_r(&rng, 42u, 54u).
"""

MASK = (1 << 64) - 1
MUL = 6364136223846793005


def lsr(value, n):
    return (value & MASK) >> n


def step(state, inc):
    old = state & MASK
    state = (old * MUL + inc) & MASK
    xorshifted = lsr(lsr(old, 18) ^ old, 27) & 0xFFFFFFFF
    rot = lsr(old, 59)
    out = ((xorshifted >> rot) | ((xorshifted << ((-rot) & 31)) & 0xFFFFFFFF)) & 0xFFFFFFFF
    return state, out


def seed(initstate, initseq):
    state = 0
    inc = ((initseq << 1) | 1) & MASK
    state, _ = step(state, inc)
    state = (state + (initstate & MASK)) & MASK
    state, _ = step(state, inc)
    return state, inc


def draws(initstate, initseq, count):
    state, inc = seed(initstate, initseq)
    out = []
    for _ in range(count):
        state, value = step(state, inc)
        out.append(value)
    return out


def bounded(state, inc, bound):
    threshold = ((1 << 32) - bound) % bound
    while True:
        state, roll = step(state, inc)
        if roll >= threshold:
            return state, roll % bound


def main():
    state, inc = seed(42, 54)
    print("seed 42 stream 54")
    print("  state 0x%016x" % state)
    print("  inc   0x%016x" % inc)
    values = []
    for _ in range(6):
        state, value = step(state, inc)
        values.append(value)
    print("  u32  ", " ".join("0x%08x" % value for value in values))
    coins = []
    for _ in range(65):
        state, bit = bounded(state, inc, 2)
        coins.append("H" if bit else "T")
    print("  coins", "".join(coins))
    faces = []
    for _ in range(33):
        state, face = bounded(state, inc, 6)
        faces.append(str(face + 1))
    print("  dice ", " ".join(faces))
    top = draws(1 << 63, 54, 6)
    print("top-bit seed", " ".join("0x%08x" % value for value in top))
    _, guard = step(0x8000000000000000, 1)
    print("logical-shift guard", "0x%08x" % guard)
    _, zero = step(0x8000200008000000, 1)
    print("zero output", "0x%08x" % zero)


if __name__ == "__main__":
    main()
