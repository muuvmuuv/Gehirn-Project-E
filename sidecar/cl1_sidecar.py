#!/usr/bin/env python3
"""CL1 sidecar for gehirn's biological core.

Runs on the CL1 itself, because the CL API is a Python SDK. Every tick's spikes go to
gehirn in the format of Cortical Labs' UDP spike receiver example: a u64 little endian
timestamp, then one byte per spiking channel. Stim packets from core/cl1.v (u16 little
endian duration in milliseconds, then channel and rate pairs) become stimulation: every
listed channel is pulsed at its rate until the duration runs out or a newer packet
replaces the pattern.

The calls follow the notebooks in github.com/Cortical-Labs/cl-api-doc. Check the stim
signature, its unit and the allowed amplitude range in CL-06 against the SDK version on
your device before the first run.
"""

import socket
import struct

import cl

GEHIRN = ("gehirn.local", 12345)  # where core/cl1.v listens for spikes (CL1_SPIKES)
LISTEN = ("0.0.0.0", 12346)  # where core/cl1.v sends stim packets (CL1_SIDECAR)
TICKS = 1000  # loop rate in ticks per second
AMPLITUDE = 1.0  # per pulse; unit and safe range per CL-06


def parse(packet: bytes, now: int) -> tuple[int, list[tuple[int, int]]] | None:
    """Turn a stim packet into (end tick, [(channel, period in ticks)])."""
    if len(packet) < 2:
        return None
    (duration_ms,) = struct.unpack_from("<H", packet, 0)
    pattern = []
    for i in range(2, len(packet) - 1, 2):
        channel, hz = packet[i], packet[i + 1]
        if hz > 0:
            pattern.append((channel, max(1, TICKS // hz)))
    return now + duration_ms * TICKS // 1000, pattern


def main() -> None:
    out = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
    inbox = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
    inbox.bind(LISTEN)
    inbox.setblocking(False)
    until, pattern = 0, []

    with cl.open() as neurons:
        for tick in neurons.loop(ticks_per_second=TICKS, ignore_jitter=True):
            spikes = tick.analysis.spikes
            if spikes:
                head = struct.pack("<Q", spikes[0].timestamp)
                out.sendto(head + bytes(s.channel for s in spikes), GEHIRN)

            while True:
                try:
                    packet, _ = inbox.recvfrom(1500)
                except BlockingIOError:
                    break
                parsed = parse(packet, tick.iteration)
                if parsed:
                    until, pattern = parsed

            if tick.iteration < until:
                for channel, period in pattern:
                    if tick.iteration % period == 0:
                        neurons.stim(channel, AMPLITUDE)


if __name__ == "__main__":
    main()
