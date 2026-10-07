#!/usr/bin/env python3
"""Probe a host:port for a STUN/TURN server and print which implementation answers.

Sends a STUN Binding request over TCP and UDP and reports the SOFTWARE/SERVER attribute
if a server responds. This is how the coturn container's "Address already in use"
was traced to a leftover `eturnal` on the VPS: the answer said SOFTWARE=eturnal
instead of Coturn-... .

Usage:
    python3 devops/stun_probe.py [host] [port]   (defaults: matrix.johnethel.school 3478)

Exit code 0 = a STUN server answered (its identity is printed);
1 = unreachable / no answer; 2 = answered but not STUN.
"""

import socket
import struct
import sys


def binding_request() -> bytes:
    return struct.pack(">HHI", 0x0001, 0, 0x2112A442) + b"0123456789ab"


def stun_probe(host: str, port: int, proto: str, timeout: float = 4.0) -> bytes | None:
    req = binding_request()
    try:
        if proto == "udp":
            s = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
            s.settimeout(timeout)
            s.sendto(req, (host, port))
            data, _ = s.recvfrom(2048)
        else:
            s = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
            s.settimeout(timeout)
            s.connect((host, port))
            s.sendall(req)
            data = s.recv(2048)
        s.close()
        return data
    except OSError:
        return None


def software_attr(data: bytes) -> str:
    """Pull the SOFTWARE or SERVER attribute out of a STUN response if present."""
    if len(data) < 20 or struct.unpack(">I", data[4:8])[0] != 0x2112A442:
        return ""
    off, found = 20, []
    while off + 4 <= len(data):
        t, length = struct.unpack(">HH", data[off : off + 4])
        value = data[off + 4 : off + 4 + length]
        if t in (0x8022, 0x0012):  # SOFTWARE, SERVER
            found.append(value.decode(errors="replace"))
        off += 4 + length + ((4 - length % 4) % 4)
    return "; ".join(found)


def main() -> int:
    host = sys.argv[1] if len(sys.argv) > 1 else "matrix.johnethel.school"
    port = int(sys.argv[2]) if len(sys.argv) > 2 else 3478
    ok = False
    for proto in ("tcp", "udp"):
        data = stun_probe(host, port, proto)
        if data is None:
            print(f"{proto} {host}:{port}: no answer (nothing listening / filtered)")
        elif struct.unpack(">H", data[:2])[0] in (0x0101, 0x0111) and struct.unpack(">I", data[4:8])[0] == 0x2112A442:
            soft = software_attr(data)
            print(f"{proto} {host}:{port}: STUN server answered (SOFTWARE: {soft or 'unknown'})")
            ok = True
        else:
            print(f"{proto} {host}:{port}: answered, but not a STUN response")
            return 2
    return 0 if ok else 1


if __name__ == "__main__":
    sys.exit(main())
