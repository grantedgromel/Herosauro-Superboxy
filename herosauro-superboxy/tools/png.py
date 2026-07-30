"""Minimal PNG read/write. No dependencies — this container has no Pillow.

Only what the harness needs: Godot writes 8-bit non-interlaced RGB/RGBA, and we
read that back, compare it, downscale it and write it out again. Everything is
kept as a flat bytearray of RGB triples rather than a nested list, because a
1280x720 image is 921,600 pixels and per-pixel Python objects make the diff gate
take longer than the capture it is gating.
"""

from __future__ import annotations

import struct
import zlib


class Image:
    __slots__ = ("w", "h", "rgb")

    def __init__(self, w: int, h: int, rgb: bytearray):
        self.w = w
        self.h = h
        self.rgb = rgb  # 3 bytes per pixel, row-major

    def pixel(self, x: int, y: int) -> tuple[int, int, int]:
        i = (y * self.w + x) * 3
        return self.rgb[i], self.rgb[i + 1], self.rgb[i + 2]


def _paeth(a: int, b: int, c: int) -> int:
    p = a + b - c
    pa, pb, pc = abs(p - a), abs(p - b), abs(p - c)
    if pa <= pb and pa <= pc:
        return a
    return b if pb <= pc else c


def read(path: str) -> Image:
    with open(path, "rb") as fh:
        data = fh.read()
    if data[:8] != b"\x89PNG\r\n\x1a\n":
        raise ValueError(f"{path}: not a PNG")

    pos = 8
    idat = bytearray()
    w = h = depth = color = 0
    while pos < len(data):
        (length,) = struct.unpack(">I", data[pos:pos + 4])
        ctype = data[pos + 4:pos + 8]
        body = data[pos + 8:pos + 8 + length]
        pos += 12 + length  # length + type + body + crc

        if ctype == b"IHDR":
            w, h, depth, color, _comp, _filt, interlace = struct.unpack(">IIBBBBB", body)
            if depth != 8:
                raise ValueError(f"{path}: only 8-bit PNGs supported (got {depth})")
            if interlace:
                raise ValueError(f"{path}: interlaced PNGs not supported")
            if color not in (2, 6):
                raise ValueError(f"{path}: only RGB/RGBA supported (got colour type {color})")
        elif ctype == b"IDAT":
            idat += body
        elif ctype == b"IEND":
            break

    nch = 3 if color == 2 else 4
    raw = zlib.decompress(bytes(idat))
    stride = w * nch

    # Undo the per-scanline filters in place.
    out = bytearray(h * stride)
    prev = bytearray(stride)
    src = 0
    for y in range(h):
        ftype = raw[src]
        src += 1
        line = bytearray(raw[src:src + stride])
        src += stride
        if ftype == 1:
            for i in range(nch, stride):
                line[i] = (line[i] + line[i - nch]) & 0xFF
        elif ftype == 2:
            for i in range(stride):
                line[i] = (line[i] + prev[i]) & 0xFF
        elif ftype == 3:
            for i in range(stride):
                left = line[i - nch] if i >= nch else 0
                line[i] = (line[i] + ((left + prev[i]) >> 1)) & 0xFF
        elif ftype == 4:
            for i in range(stride):
                left = line[i - nch] if i >= nch else 0
                ul = prev[i - nch] if i >= nch else 0
                line[i] = (line[i] + _paeth(left, prev[i], ul)) & 0xFF
        elif ftype != 0:
            raise ValueError(f"{path}: bad filter type {ftype} on row {y}")
        out[y * stride:(y + 1) * stride] = line
        prev = line

    if nch == 3:
        return Image(w, h, out)

    # Drop alpha. Every capture is opaque; carrying the channel doubles the
    # work in every comparison for no information.
    rgb = bytearray(w * h * 3)
    for i in range(w * h):
        rgb[i * 3:i * 3 + 3] = out[i * 4:i * 4 + 3]
    return Image(w, h, rgb)


def write(path: str, img: Image) -> None:
    stride = img.w * 3
    raw = bytearray()
    for y in range(img.h):
        raw.append(0)  # filter: none. These are small and written once.
        raw += img.rgb[y * stride:(y + 1) * stride]

    def chunk(tag: bytes, body: bytes) -> bytes:
        return (struct.pack(">I", len(body)) + tag + body
                + struct.pack(">I", zlib.crc32(tag + body) & 0xFFFFFFFF))

    with open(path, "wb") as fh:
        fh.write(b"\x89PNG\r\n\x1a\n")
        fh.write(chunk(b"IHDR", struct.pack(">IIBBBBB", img.w, img.h, 8, 2, 0, 0, 0)))
        fh.write(chunk(b"IDAT", zlib.compress(bytes(raw), 6)))
        fh.write(chunk(b"IEND", b""))


def scaled(img: Image, w: int, h: int) -> Image:
    """Box-filter downscale. Nearest-neighbour aliases badly enough on thin
    ironwork that a contact sheet made with it misrepresents the frame."""
    out = bytearray(w * h * 3)
    for y in range(h):
        y0 = y * img.h // h
        y1 = max(y0 + 1, (y + 1) * img.h // h)
        for x in range(w):
            x0 = x * img.w // w
            x1 = max(x0 + 1, (x + 1) * img.w // w)
            r = g = b = n = 0
            for sy in range(y0, y1):
                base = sy * img.w * 3
                for sx in range(x0, x1):
                    i = base + sx * 3
                    r += img.rgb[i]
                    g += img.rgb[i + 1]
                    b += img.rgb[i + 2]
                    n += 1
            o = (y * w + x) * 3
            out[o] = r // n
            out[o + 1] = g // n
            out[o + 2] = b // n
    return Image(w, h, out)


def blank(w: int, h: int, color: tuple[int, int, int] = (0, 0, 0)) -> Image:
    return Image(w, h, bytearray(bytes(color) * (w * h)))


def blit(dst: Image, src: Image, x: int, y: int) -> None:
    for row in range(src.h):
        dy = y + row
        if dy < 0 or dy >= dst.h:
            continue
        di = (dy * dst.w + x) * 3
        si = row * src.w * 3
        dst.rgb[di:di + src.w * 3] = src.rgb[si:si + src.w * 3]
