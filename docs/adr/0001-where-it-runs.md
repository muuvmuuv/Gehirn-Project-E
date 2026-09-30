# ADR-0001: Where gehirn runs

**Status:** Proposed
**Date:** 2026-09-30
**Deciders:** repository owner

## Context

gehirn has three kinds of work with different needs. HQ runs the core and the three MAGI units, four language models at a few calls per second, and needs a GPU with enough memory to hold them. The field unit runs the 50 Hz loop (seat, sync, blend, the armor's soft layer, recorder, umbilical watch) and needs little compute but steady timing. The hard restraints need guaranteed timing, because they stop the body when everything above them has failed.

The goal is to build as much as possible in V, ideally on [Vinix](https://vinix-os.org/). Vinix is a kernel written from scratch in V: monolithic, no garbage collector in the kernel, and it runs unmodified aarch64 Alpine Linux binaries through Linux system call compatibility. Its FAQ is explicit that it is not a real time system: `SCHED_FIFO` and `SCHED_RR` fail with `EINVAL`, and hard real time work is left to a different system. Official hardware support is M1 Macs for now (as of September 10, 2026); amd64 installs work, with weak driver support. Its GPU effort is the Apple AGX and DCP graphics stack with Mesa and OpenGL on top, so there is no path to running models on a GPU there yet. Drivers are V modules compiled into the kernel that publish nodes under `/dev` and implement the kernel's `Resource` interface.

[Omarchy](https://omarchy.org/) is Arch Linux with Hyprland, and it sets up NVIDIA drivers during installation, which makes it a ready machine for local models.

## Decision

Split by tier. HQ runs on Linux with a GPU: an Omarchy workstation with an NVIDIA card now, and later a GB10 class machine such as a DGX Spark, whose 128 GB of unified memory holds all four models at once. The field unit is portable V with no Linux specific interfaces, so the same code runs on Linux today and on Vinix once Vinix runs on the field computer. The hard restraints run on a microcontroller behind a physical e-stop and are never delegated to an operating system.

## Options Considered

### Option A: Omarchy everywhere

| Dimension | Assessment |
| --- | --- |
| Complexity | Low |
| Models on a GPU | Yes |
| Real time | Possible with a PREEMPT_RT kernel, not the default |
| V coverage | Applications only |

**Pros:** one operating system, GPU ready, and Linux has real time kernels.
**Cons:** nothing below the application is V, which gives up the point of the project, and a desktop distribution is a poor fit for a field computer.

### Option B: Vinix everywhere

| Dimension | Assessment |
| --- | --- |
| Complexity | High |
| Models on a GPU | No |
| Real time | No, by design for now |
| V coverage | Kernel to application |

**Pros:** V from kernel to application, and the body can become a kernel driver.
**Cons:** the models would have to run elsewhere anyway, there is no real time scheduling, and it puts alpha software under the one layer that must not fail.

### Option C: Split by tier

| Dimension | Assessment |
| --- | --- |
| Complexity | Medium |
| Models on a GPU | Yes, on HQ |
| Real time | On the microcontroller, where it belongs |
| V coverage | Field unit now, a Vinix driver later |

**Pros:** each tier runs on the system that fits it, and V still covers everything that runs on the machine itself.
**Cons:** two operating systems plus firmware, and a link between them that has to be designed for loss.

## Trade-off Analysis

The deciding property is not language coverage but where a failure lands. A hung model or a crashed HQ must leave a body that holds, which the umbilical already guarantees: without HQ there is no quorum, so nothing irreversible happens while the cable is cut. A stalled field process must leave a body that stops, which only works if stopping does not depend on that process, hence the microcontroller. Given that, Vinix on the field tier costs nothing in safety and keeps the V path open, while Vinix on HQ would cost the GPU.

## Consequences

Easier: HQ can move between machines without the field unit noticing, and Vinix can take over the field tier whenever it runs on the field computer, since that code needs nothing beyond V's standard modules (`net`, `os`, `time`, `math`, `json2`).

Harder: the one binary becomes two processes once LCL moves onto a real transport, and the microcontroller firmware has to duplicate every limit of the armor, zero its outputs when commands stop arriving, and own the e-stop circuit.

On Vinix the body becomes a kernel driver published as `/dev/eva0` through devtmpfs and implementing `Resource`: `read` returns percepts, `write` takes velocity commands, `ioctl` runs effectors and halt. Only the armor's process may open it. There are no loadable kernel modules, so the driver is compiled into the kernel image, and a full rebuild takes seconds.

Revisit when Vinix gains real time scheduling or GPU compute, or when a CL1 core becomes primary, in which case HQ moves next to the CL1 on the network.

## Action Items

1. [ ] Move LCL onto Zenoh through zenoh-c and split HQ and the field unit into two processes.
2. [ ] Write the microcontroller firmware for the hard restraints, linked through zenoh-pico.
3. [ ] Prototype `/dev/eva0` in a Vinix VM with the simulator behind it.
